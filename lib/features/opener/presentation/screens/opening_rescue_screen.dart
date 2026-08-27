import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/reveal_pill.dart';
import '../../../../shared/widgets/scroll_card_ticks.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../subscription/domain/services/subscription_tier_helper.dart';
import '../../../../core/services/usage_service.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../data/providers/opener_providers.dart';
import '../../data/services/opener_request_session.dart';
import '../../domain/opener_access.dart';
import '../../data/services/opener_result_cache_service.dart';
import '../../data/services/opener_service.dart';
import '../../../../shared/widgets/coaching_outcome_capture_card.dart';
import '../../../../shared/widgets/coaching_outcome_follow_up_bar.dart';
import '../../../../shared/widgets/staggered_appear.dart';
import '../../../../shared/widgets/stream_progress_ticker.dart';
import '../../../coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../coaching_memory/domain/entities/coaching_outcome_event.dart';
import '../../../analysis/presentation/widgets/swipe_hint_nudge.dart';
import '../../../new_topic/presentation/widgets/new_topic_view.dart';
import '../widgets/opener_generation_progress.dart';
import '../../../../core/services/app_haptics.dart';

/// `/opener` 頁的兩個模式：開場白（既有 opener body）與新話題。
/// `?mode=new_topic` 只決定初始 tab；頁內切換不改 route。
enum OpeningRescueMode { opener, newTopic }

/// 「她回覆了，開始分析對話」按下後對導航堆疊做的事。
enum OpenerHandoffNavigation {
  /// 回到堆疊下面那張既有的對象卡（開場救星退出堆疊，不新增任何頁）。
  popToBoundPartner,

  /// 用 handoff 目的地取代開場救星本身（開場救星不留在返回路徑上）。
  replaceWithHandoff,
}

class OpeningRescueScreen extends ConsumerStatefulWidget {
  const OpeningRescueScreen({
    super.key,
    this.partnerId,
    this.initialMode = OpeningRescueMode.opener,
  });

  /// Optional: when entered from a partner-scoped sheet (PartnerDetail / Analysis),
  /// drafts saved here are tagged with this partnerId so the「最近開場草稿」
  /// card knows which person each draft belongs to.
  final String? partnerId;

  /// 初始模式；unknown query 值由 route 層 fallback 成 opener。
  final OpeningRescueMode initialMode;

  /// Route query `mode` 解析：只認 `new_topic`，其他一律 opener。
  static OpeningRescueMode modeFromQuery(String? raw) {
    return raw == 'new_topic'
        ? OpeningRescueMode.newTopic
        : OpeningRescueMode.opener;
  }

  /// Builds the handoff URL used by the「她回覆了，開始分析對話」CTA.
  ///
  /// 2026-08-26 產品調整：拿掉中間的「接續開場」頁，CTA 直接進「新增對象」。
  /// 開場救星是先鋒，真正的後續分析要先有對象卡承接；建立後 AddPartnerScreen
  /// 會 pushReplacement 到 `/partner/:id`，使用者在那裡貼上送出的開場與她的
  /// 回覆。已綁定對象的入口（PartnerDetail → 分析新片段 → 開場救星）不該再
  /// 開一張重複的卡，直接回到那張對象卡。
  static String handoffLocationFor({String? partnerId}) {
    final trimmed = partnerId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '/partner/new';
    }
    return '/partner/$trimmed';
  }

  /// CTA 的導航動作。目的地網址只講「去哪」，這裡講的是「堆疊要變成什麼」——
  /// 兩個入口要的結果不同，用同一個 push 會留下錯的返回路徑（Eric-AI
  /// 2026-08-26 複審 #39 退回項 1、2）。
  ///
  /// - 已綁定對象（PartnerDetail → 分析新片段 → 開場救星）：那張對象卡就在
  ///   堆疊下面，pop 回去即可；再 push 一次會疊出第二張一模一樣的卡，按返回
  ///   還會看到開場救星。深連結直開 `/opener?partnerId=` 時沒得 pop，退回
  ///   pushReplacement。
  /// - 未綁定對象：pushReplacement 讓開場救星退出堆疊。AddPartnerScreen 建立
  ///   成功後自己 pushReplacement 到 `/partner/:id`，於是新對象卡下面是首頁，
  ///   按返回回首頁而不是又回到開場救星。
  static OpenerHandoffNavigation handoffNavigationFor({
    required String? partnerId,
    required bool canPop,
  }) {
    final trimmed = partnerId?.trim();
    final isBound = trimmed != null && trimmed.isNotEmpty;
    return isBound && canPop
        ? OpenerHandoffNavigation.popToBoundPartner
        : OpenerHandoffNavigation.replaceWithHandoff;
  }

  /// 執行 [handoffNavigationFor] 決定的導航。CTA 只呼叫這一個入口，
  /// 導航語意才有單一測得到的來源。
  static void navigateToHandoff(BuildContext context, {String? partnerId}) {
    final router = GoRouter.of(context);
    final navigation = handoffNavigationFor(
      partnerId: partnerId,
      canPop: router.canPop(),
    );
    switch (navigation) {
      case OpenerHandoffNavigation.popToBoundPartner:
        router.pop();
      case OpenerHandoffNavigation.replaceWithHandoff:
        router.pushReplacement(handoffLocationFor(partnerId: partnerId));
    }
  }

  static bool canStartGeneration({
    required bool isGenerating,
    required bool hasResult,
  }) {
    return !isGenerating && !hasResult;
  }

  static bool shouldClearPaywallQuotaError({
    required bool hasError,
    required bool isPremium,
  }) {
    return hasError && isPremium;
  }

  static String generateButtonText({required bool hasResult}) {
    return hasResult ? '已生成開場白' : '生成開場白';
  }

  static String generationQuotaHint({
    required bool hasResult,
    required int estimatedCost,
  }) {
    return hasResult ? '已生成，不會重複扣額度' : '將使用 $estimatedCost 則額度';
  }

  static String copiedOpenerMessage(String label) {
    return '已複製這則開場白。貼到交友軟體送出，發出後記得回來回報結果；'
        '她回覆後，點下方「她回覆了，開始分析對話」。';
  }

  /// 批2：opener outcome 事件的 adviceId（＝eventId）。
  /// requestId 缺席→null＝不自動記、不渲染晶片條（防禦，正常路徑必有）。
  static String? openerAdviceIdFor({
    required String? requestId,
    required String type,
  }) {
    final normalized = requestId?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return 'opener:$normalized:$type';
  }

  /// Canonical 5-style labels shared with the server's OPENER_TYPES.
  /// 展示序不看這張 map：paid 走 canonicalPaidOrder，free 走
  /// freeUnlockedOrder（三實卡在前）＋ paidOnlyOrder（兩鎖卡在後）。
  static const openerTypeLabels = {
    'extend': '延展',
    'resonate': '共鳴',
    'tease': '調情',
    'humor': '幽默',
    'coldRead': '冷讀',
  };

  /// profileAnalysis 的 server key 保持契約穩定；畫面只顯示客戶看得懂的語言，
  /// 不把「高手手法／雙球策略」這類內部方法名端出去。
  static const profileAnalysisLabels = {
    'style': '風格',
    'personality': '切入判斷',
    'avoidTopics': '先避開',
    'frameRead': '互動判斷',
    'positiveHooks': '可接線索',
    'masterObservation': '重點觀察',
    'curiosityHook': '容易接話',
    'masterMove': '開場建議',
    'twoBallPlan': '兩個接點',
    'talkingPoints': '話題切入點',
    'openingStrategy': '推薦策略',
    'vibe': '氛圍',
    'interests': '興趣',
  };

  static String? profileAnalysisLabelFor(String key) =>
      profileAnalysisLabels[key];

  /// Card list is contract-driven, not payload driven（contract v2）：
  /// Free 依展示序放 extend/humor/tease 實卡（缺句跳過，舊 v1 單卡快取只有
  /// extend），再固定補 resonate/coldRead 兩張鎖卡升級 CTA；鎖卡 content
  /// 一律清空——paid-era 草稿降級回看時鎖定內容連 spec 都不進。
  /// Paid 永遠沒有鎖卡，sanitizer 丟掉的風格直接跳過。
  /// Free 沒有任何可用實卡時整區不渲染（no orphan upsell）。
  static List<OpenerCardSpec> visibleOpenerCards({
    required Map<String, String> openers,
    required String? recommendedPick,
    required bool isFreeUser,
  }) {
    final cards = <OpenerCardSpec>[];

    if (!isFreeUser) {
      for (final type in OpenerAccessContract.canonicalPaidOrder) {
        final content = openers[type]?.trim() ?? '';
        if (content.isEmpty) continue;
        cards.add(OpenerCardSpec(
          type: type,
          content: content,
          isLocked: false,
          isRecommended: type == recommendedPick,
        ));
      }
      return _recommendedFirst(cards);
    }

    for (final type in OpenerAccessContract.freeUnlockedOrder) {
      final content = openers[type]?.trim() ?? '';
      if (content.isEmpty) continue;
      cards.add(OpenerCardSpec(
        type: type,
        content: content,
        isLocked: false,
        isRecommended: type == recommendedPick,
      ));
    }

    if (cards.isEmpty) return cards;

    for (final type in OpenerAccessContract.paidOnlyOrder) {
      cards.add(OpenerCardSpec(
        type: type,
        content: '',
        isLocked: true,
        isRecommended: false,
      ));
    }
    return _recommendedFirst(cards);
  }

  /// 2026-08-19 v2：AI 推薦卡固定排第一張（免用戶橫滑找）；其餘維持展示序，
  /// 鎖卡永遠在最後（推薦卡必為實卡，free 被鎖的 pick 不掛 badge 也不前移）。
  static List<OpenerCardSpec> _recommendedFirst(List<OpenerCardSpec> cards) {
    final recommendedIndex = cards.indexWhere((card) => card.isRecommended);
    if (recommendedIndex <= 0) return cards;
    final recommended = cards.removeAt(recommendedIndex);
    cards.insert(0, recommended);
    return cards;
  }

  static String openerStylesHeaderSuffix({required int cardCount}) {
    return ' ・$cardCount 種風格';
  }

  /// Legacy fallback ONLY — fresh results use the server's `access.servedTier`
  /// as the authoritative tier decision. When access metadata is absent (old
  /// Edge during rollout / old cache), the strongest safe payload signal is a
  /// paid-only style with content: contract v2 free payloads legitimately
  /// carry humor/tease, so "any non-extend content" would misread every free
  /// v2 result as paid. A result that passes this check renders unlocked even
  /// while the local subscription snapshot is still stale-free. Draft replays
  /// deliberately do NOT use this: a paid-era draft viewed by a now-free user
  /// stays gated by the live subscription.
  static bool resultHasPaidStyles(Map<String, String> openers) {
    return openers.entries.any(
      (entry) =>
          OpenerAccessContract.paidOnlyOrder.contains(entry.key) &&
          entry.value.trim().isNotEmpty,
    );
  }

  @override
  ConsumerState<OpeningRescueScreen> createState() =>
      _OpeningRescueScreenState();
}

/// One rendered opener card: a real payload entry, or a synthesized locked
/// upsell placeholder (empty content) for a style the server stripped from
/// a free-tier payload.
class OpenerCardSpec {
  const OpenerCardSpec({
    required this.type,
    required this.content,
    required this.isLocked,
    required this.isRecommended,
  });

  final String type;
  final String content;
  final bool isLocked;
  final bool isRecommended;
}

class _OpeningRescueScreenState extends ConsumerState<OpeningRescueScreen> {
  // 頁內模式切換不清 result/error/requestId、不改 route（§13.1）；
  // IndexedStack 讓另一模式保持 mounted，in-flight 生成不中斷。
  late OpeningRescueMode _mode = widget.initialMode;
  int _selectedTab = 0;
  List<Uint8List> _images = [];

  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _interestsController = TextEditingController();
  String? _meetingContext;

  bool _isGenerating = false;

  // F3-2 進度文案凍結在生成開始送出的 input（Codex R1 P2）：生成中用戶仍可
  // 切 tab/移除截圖，activeInput 會變但後端處理的是原始輸入，文案不得跟漂。
  List<String>? _generationProgressPhrases;
  // 真串流進度（server 事件）；每次生成開始清空。空＝還沒收到事件
  //（或 server 降級 legacy），顯示本地輪播 fallback。heartbeat 不進清單。
  final List<String> _streamProgress = [];
  // 已完成的串流 phase（style_extend…）：骨架卡點亮用（v2）。
  final Set<String> _completedStreamPhases = {};
  OpenerResult? _result;
  String? _error;
  final _scrollController = ScrollController();
  // 2026-08-18 呈現精修：完成後定格在結果區頂部（開場白建議），不再捲到底
  // 把 5 張卡整個略過。
  final _resultsSectionKey = GlobalKey();
  final _resultCacheService = OpenerResultCacheService();

  // 扣費 idempotency（Batch 4#2）：失敗重試沿用同 requestId，成功才 rotate。
  final _requestSession = OpenerRequestIdSession();
  List<OpenerDraft> _drafts = const [];
  String? _currentDraftId;
  bool _suppressInputClear = false;

  // 本次 _result 是否由 server 以付費 tier 產出（payload 形狀判定）。
  // fresh 生成設定、draft 回看清空；渲染鎖卡時優先於訂閱快照，
  // 封掉「付費結果被 stale free 快照蓋鎖卡」的 race（Codex R1 P2）。
  bool _resultGeneratedPaid = false;

  static const _meetingOptions = ['交友軟體', 'IG', '現實認識', '其他'];

  // Flat 3-quota cost per opener request. Image processing cost is
  // platform-absorbed; the predictable price is more important than
  // strict per-image cost recovery, and discourages users from skipping
  // screenshots just to save quota.
  int get _estimatedCost => 3;

  @override
  void initState() {
    super.initState();
    _reloadDrafts();
    _prefillFromPartner();
    _nameController.addListener(_clearGeneratedResultOnInputChange);
    _bioController.addListener(_clearGeneratedResultOnInputChange);
    _interestsController.addListener(_clearGeneratedResultOnInputChange);
  }

  void _prefillFromPartner() {
    final id = widget.partnerId;
    if (id == null || id.isEmpty) return;
    final partner = ref.read(partnerByIdProvider(id));
    if (partner == null) return;
    final name = partner.name.trim();
    if (name.isEmpty) return;
    _nameController.text = name;
  }

  String? _resolveBoundPartnerName() {
    final id = widget.partnerId;
    if (id == null || id.isEmpty) return null;
    final partner = ref.watch(partnerByIdProvider(id));
    final name = partner?.name.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  void _clearGeneratedResultOnInputChange() {
    if (_suppressInputClear ||
        !mounted ||
        (_result == null && _error == null)) {
      return;
    }
    setState(() {
      _result = null;
      _error = null;
      _currentDraftId = null;
    });
  }

  UsageData _currentUsageSnapshot() {
    final subscription = ref.read(subscriptionProvider);
    final localUsage = ref.read(usageDataProvider);

    if (subscription.isLoading) {
      return localUsage;
    }

    return UsageData(
      monthlyUsed: subscription.monthlyMessagesUsed,
      monthlyLimit: subscription.monthlyLimit,
      dailyUsed: subscription.dailyMessagesUsed,
      dailyLimit: subscription.dailyLimit,
      dailyResetAt: localUsage.dailyResetAt,
      tier: subscription.tier,
    );
  }

  Future<bool> _canStartGeneration(int cost) async {
    if (_currentUsageSnapshot().canAfford(cost)) {
      return true;
    }

    try {
      await ref.read(subscriptionScreenRefreshProvider)();
    } catch (_) {
      // If refresh is temporarily unavailable, let the Edge Function make the
      // authoritative quota decision instead of blocking a fresh free user.
      return true;
    }

    if (_currentUsageSnapshot().canAfford(cost)) {
      return true;
    }

    if (mounted) {
      await _showPaywallAndRefresh();
      if (_currentUsageSnapshot().canAfford(cost)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _showPaywallAndRefresh() async {
    if (!mounted) return;

    final unlockedTier = await context.push<String>('/paywall');
    if (!mounted) return;

    if (unlockedTier != null && unlockedTier.isNotEmpty) {
      try {
        await ref.read(subscriptionProvider.notifier).forceSyncTier(
              unlockedTier,
            );
      } catch (e) {
        debugPrint('OpeningRescueScreen paywall force sync failed: $e');
      }
    }

    try {
      await ref.read(subscriptionScreenRefreshProvider)();
    } catch (e) {
      debugPrint('OpeningRescueScreen paywall refresh failed: $e');
    }
    if (!mounted) return;

    final subscription = ref.read(subscriptionProvider);
    if (OpeningRescueScreen.shouldClearPaywallQuotaError(
      hasError: _error != null,
      isPremium: subscription.isPremium,
    )) {
      setState(() => _error = null);
    }
  }

  String _buildDraftInputPreview() {
    if (_selectedTab == 0 && _images.isNotEmpty) {
      return '${_images.length} 張截圖';
    }

    final parts = [
      _nameController.text.trim(),
      _bioController.text.trim(),
      _interestsController.text.trim(),
      _meetingContext,
    ].whereType<String>().where((part) => part.isNotEmpty).toList();

    if (parts.isEmpty) {
      return '手動輸入';
    }

    return parts.join(' · ');
  }

  void _reloadDrafts() {
    _drafts =
        _resultCacheService.loadDraftsForScope(partnerId: widget.partnerId);
  }

  /// 只在草稿上蓋「已接續」章；開場白不再自動帶進下一頁（「接續開場」頁已移除），
  /// 所以這裡不需要再寫 latest 槽位。
  Future<void> _markDraftContinuedForHandoff() async {
    if (_result == null) return;
    final draftId = _currentDraftId;
    if (draftId == null) return;

    try {
      await _resultCacheService.markDraftContinued(draftId);
    } catch (_) {
      // Starting a conversation should not fail because local metadata failed.
    }
  }

  /// 回看草稿。不再寫 latest 槽位——那個槽位只服務已移除的「接續開場」帶入，
  /// 留著只是讓回看多做一次沒人讀的磁碟寫入。
  void _openDraft(OpenerDraft draft) {
    _suppressInputClear = true;
    _nameController.clear();
    _bioController.clear();
    _interestsController.clear();
    _suppressInputClear = false;

    if (!mounted) return;
    setState(() {
      _images = [];
      _meetingContext = null;
      _result = draft.result;
      _resultGeneratedPaid = false;
      _currentDraftId = draft.id;
      _error = null;
    });

    _snapToResults();
  }

  /// 完成／載入草稿後定格在結果區頂部（沿用 analyze-chat 完成定格拍板：
  /// 錨用戶當下最想要的內容，這裡是 5 張建議卡的標題列）。post-frame 才
  /// 量得到新掛載的結果區位置。
  void _snapToResults() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _resultsSectionKey.currentContext;
      if (targetContext == null || !mounted) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.04,
        duration: AppMotion.scroll,
        curve: AppMotion.easeOut,
      );
    });
  }

  Future<void> _deleteDraft(String id) async {
    await _resultCacheService.deleteDraft(id);
    if (!mounted) return;
    setState(() {
      _reloadDrafts();
      if (_currentDraftId == id) {
        _currentDraftId = null;
        _result = null;
      }
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_clearGeneratedResultOnInputChange);
    _bioController.removeListener(_clearGeneratedResultOnInputChange);
    _interestsController.removeListener(_clearGeneratedResultOnInputChange);
    _nameController.dispose();
    _bioController.dispose();
    _interestsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!OpeningRescueScreen.canStartGeneration(
      isGenerating: _isGenerating,
      hasResult: _result != null,
    )) {
      if (_result != null) {
        _showOpenerSnackBar('這組輸入已生成開場白；想重做請先調整上方資料。');
      }
      return;
    }

    final input = OpenerGenerationInput.fromActiveTab(
      useScreenshotTab: _selectedTab == 0,
      images: _images,
      name: _nameController.text,
      bio: _bioController.text,
      interests: _interestsController.text,
      meetingContext: _meetingContext,
    );

    if (!input.hasContent) {
      setState(() => _error = '請上傳截圖或輸入對方資料');
      return;
    }

    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: '開場救星',
    );
    if (!consented || !mounted) return;

    final cost = _estimatedCost;
    if (!await _canStartGeneration(cost)) {
      return;
    }
    if (!mounted) return;

    // 收鍵盤
    FocusScope.of(context).unfocus();

    setState(() {
      _isGenerating = true;
      _streamProgress.clear();
      _completedStreamPhases.clear();
      _generationProgressPhrases = OpenerGenerationProgress.phrasesFor(
        hasImages: input.images?.isNotEmpty ?? false,
      );
      _error = null;
      _result = null;
      _currentDraftId = null;
    });

    try {
      final subscriptionSnapshot = ref.read(subscriptionProvider);
      var expectedTier = subscriptionSnapshot.tier;
      String? revenueCatAppUserId;
      try {
        final customerInfo = await RevenueCatService.getCustomerInfo();
        final revenueCatTier =
            RevenueCatService.getTierFromCustomerInfo(customerInfo);
        revenueCatAppUserId =
            RevenueCatService.getRevenueCatAppUserId(customerInfo);
        if (SubscriptionTierHelper.rankOf(revenueCatTier) >
            SubscriptionTierHelper.rankOf(expectedTier)) {
          expectedTier = revenueCatTier;
        }
      } catch (e) {
        debugPrint('OpeningRescueScreen RevenueCat hint failed: $e');
      }
      if (!mounted) return;

      // F3-1：關於我/對象風格設定進 opener（只調語氣，server 端 prompt 守門）。
      // await resolve 讓快照在 beginAttempt 之前定案（Codex R1 P2：sync
      // valueOrNull 冷啟動讀到 loading，重試時 fingerprint 漂移會換新
      // requestId，server 對前一次已扣費 run 去重失效）。載入失敗不擋生成。
      String? effectiveStyleContext;
      try {
        effectiveStyleContext =
            await ref.read(openerStyleContextProvider(widget.partnerId).future);
      } catch (e) {
        debugPrint('OpeningRescueScreen style context failed: $e');
      }
      if (!mounted) return;

      // 同可見輸入的重試沿用 attempt 凍結的風格快照（Codex R2 P2），
      // 所以 payload 一律取 attempt.styleContext 而非本次解析值。
      final attempt = _requestSession.beginAttempt(
        fingerprint: OpenerRequestIdSession.fingerprintFor(
          images: input.images,
          name: input.name,
          bio: input.bio,
          interests: input.interests,
          meetingContext: input.meetingContext,
        ),
        styleContext: effectiveStyleContext,
      );

      final service = OpenerService();
      // 2026-08-18 真串流：進度事件即時上牆；server flag off／舊 Edge 會
      // 回一般 JSON，service 內自動降級，這裡無感。
      final rawResult = await service.generateOpenersStreaming(
        images: input.images,
        name: input.name,
        bio: input.bio,
        interests: input.interests,
        meetingContext: input.meetingContext,
        expectedTier: expectedTier,
        revenueCatAppUserId: revenueCatAppUserId,
        effectiveStyleContext: attempt.styleContext,
        requestId: attempt.requestId,
        onProgress: (label, phase) {
          if (!mounted || !_isGenerating) return;
          if (phase == 'heartbeat') return; // 活著訊號不進階段清單
          setState(() {
            _streamProgress.add(label);
            if (phase != null) _completedStreamPhases.add(phase);
          });
        },
      );
      // 結果已到手＝這次計費完結；之後任何失敗（存草稿等）都不該讓
      // 下一次生成沿用同 id 而被 server 當重試去重。
      _requestSession.markSuccess();
      // 批2：outcome adviceId 與扣費共用同一 requestId；必須在 saveDraft
      // 前掛上，草稿序列化才帶得到。
      final result = rawResult.withRequestId(attempt.requestId);
      try {
        final draft = await _resultCacheService.saveDraft(
          result: result,
          displayName: input.name,
          sourceLabel: _selectedTab == 0 ? '截圖自介' : '手動輸入',
          inputPreview: _buildDraftInputPreview(),
          partnerId: widget.partnerId,
        );
        _currentDraftId = draft.id;
        _reloadDrafts();
      } catch (_) {
        // The paid result should still be shown even if local persistence fails.
      }
      if (mounted) {
        setState(() {
          _result = result;
          // Fresh result 的 tier 真相源＝server access；舊 Edge 未帶 access
          // 時才退回 paid-only keys 形狀判斷（§8.4）。
          _resultGeneratedPaid = result.access?.servedPaid ??
              OpeningRescueScreen.resultHasPaidStyles(result.openers);
          _isGenerating = false;
          _reloadDrafts();
        });

        // 先排定格再做額度 refresh：refresh 是網路呼叫，擋在前面會造成
        // 「結果出現 → 停 1~2 秒 → 突然捲動」的體感（dogfood 回報）。
        _snapToResults();

        try {
          await ref.read(subscriptionScreenRefreshProvider)();
        } catch (_) {
          // The opener result already succeeded; usage UI can catch up on the
          // next subscription refresh if this best-effort sync fails.
        }
      }
    } on OpenerQuotaExceededException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isGenerating = false;
        });
        await _showPaywallAndRefresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyGenerationError(e);
          _isGenerating = false;
        });
      }
    }
  }

  /// Maps an opener-generation failure to safe, user-facing Chinese copy.
  ///
  /// OpenerService wraps its known failures in Chinese-message Exceptions, but
  /// raw network/platform errors (SocketException / TimeoutException /
  /// ClientException) and a rare raw server `error` passthrough can reach this
  /// catch-all in English. Only surface a message that is actually localized
  /// (contains Chinese); otherwise fall back to a fixed Chinese string so
  /// engineering/network vocabulary never reaches the user.
  String _friendlyGenerationError(Object error) {
    const fallback = '開場暫時生成失敗，請稍後再試。';
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    final hasChinese = RegExp(r'[一-鿿]').hasMatch(message);
    return hasChinese && message.isNotEmpty ? message : fallback;
  }

  void _showOpenerSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.35,
            ),
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.brandSurface2,
          elevation: 8,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);
    final boundPartnerName = _resolveBoundPartnerName();
    final activeInput = OpenerGenerationInput.fromActiveTab(
      useScreenshotTab: _selectedTab == 0,
      images: _images,
      name: _nameController.text,
      bio: _bioController.text,
      interests: _interestsController.text,
      meetingContext: _meetingContext,
    );
    final hasGeneratedResult = _result != null;

    return BrandScaffold(
      title: '開場救星',
      tone: BrandVisualTone.coach,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      safeArea: false,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: BrandSegmentedButton<OpeningRescueMode>(
                tone: BrandVisualTone.coach,
                segments: const [
                  BrandSegment(
                    value: OpeningRescueMode.opener,
                    label: '開場白',
                  ),
                  BrandSegment(
                    value: OpeningRescueMode.newTopic,
                    label: '新話題',
                  ),
                ],
                selected: _mode,
                // 本地切換不改 route（避免 GoRouter replace 重建）；
                // IndexedStack 保兩側 state，生成中切換不中斷工作。
                onChanged: (mode) => setState(() => _mode = mode),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _mode.index,
                children: [
                  _buildOpenerBody(
                    subscription: subscription,
                    boundPartnerName: boundPartnerName,
                    activeInput: activeInput,
                    hasGeneratedResult: hasGeneratedResult,
                  ),
                  NewTopicView(initialPartnerId: widget.partnerId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 既有 opener body 原樣抽出（§13.1：不動 controllers、request session、
  /// draft、outcome lifecycle；只換掛載位置）。
  Widget _buildOpenerBody({
    required SubscriptionState subscription,
    required String? boundPartnerName,
    required OpenerGenerationInput activeInput,
    required bool hasGeneratedResult,
  }) {
    final scrollBody = SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            '開場救星',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.coachAccentBright,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            boundPartnerName != null
                ? '為 $boundPartnerName 想開場'
                : 'AI 幫你想第一句開場',
            style: AppTypography.headlineLarge.copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),

          // Tab switcher
          BrandSegmentedButton<int>(
            tone: BrandVisualTone.coach,
            segments: const [
              BrandSegment(value: 0, label: '截圖自介'),
              BrandSegment(value: 1, label: '手動輸入'),
            ],
            selected: _selectedTab,
            onChanged: (val) => setState(() {
              _selectedTab = val;
              _result = null;
              _error = null;
              _currentDraftId = null;
            }),
          ),
          const SizedBox(height: 24),

          // Tab content
          if (_selectedTab == 0) _buildScreenshotTab(),
          if (_selectedTab == 1) _buildManualTab(),

          if (_drafts.isNotEmpty && _result == null) ...[
            const SizedBox(height: 16),
            _buildRecentDraftsCard(),
          ],

          const SizedBox(height: 16),

          // Cost indicator + 柔性提示
          // 統一 3 則扣費；附截圖效果通常較好（AI 看到對方一手資訊
          // 而非用戶口中的二手描述），但不強制 — 用戶可以視情況決定。
          Center(
            child: Column(
              children: [
                Text(
                  OpeningRescueScreen.generationQuotaHint(
                    hasResult: hasGeneratedResult,
                    estimatedCost: _estimatedCost,
                  ),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                if (activeInput.images == null ||
                    activeInput.images!.isEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '附上對方截圖，AI 看到的線索更具體，開場通常更準',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.72),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Generate button
          BrandPrimaryButton(
            label: _isGenerating
                ? '生成中…'
                : OpeningRescueScreen.generateButtonText(
                    hasResult: hasGeneratedResult,
                  ),
            // v2：生成中不轉圈（下方骨架卡已有動態，雙轉圈很吵），
            // 改禁用態純文字「生成中…」。
            isLoading: false,
            onPressed: OpeningRescueScreen.canStartGeneration(
              isGenerating: _isGenerating,
              hasResult: hasGeneratedResult,
            )
                ? _generate
                : null,
          ),
          const SizedBox(height: 16),

          // Loading state（2026-08-19 v2）：串流事件到達後顯示一行狀態＋
          // 五張風格骨架卡（server 每寫完一種就點亮一張＝真串流體感）；
          // 事件還沒來（連線中）或 server 降級 legacy 時沿用本地輪播文案。
          // 文案凍結在 _generate 送出的 input，不讀 activeInput。
          if (_isGenerating)
            _streamProgress.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StreamProgressTicker(labels: _streamProgress),
                      const SizedBox(height: 12),
                      _OpenerStyleSkeletonRow(
                        completedPhases: _completedStreamPhases,
                      ),
                    ],
                  )
                : Center(
                    child: OpenerGenerationProgress(
                      phrases: _generationProgressPhrases ??
                          kOpenerManualProgressPhrases,
                    ),
                  ),

          // Error
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  _error!,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // Results
          if (_result != null) ...[
            const SizedBox(height: 24),
            _buildResults(subscription),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );

    return scrollBody;
  }

  Widget _buildScreenshotTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '上傳對方的交友軟體自介截圖',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
        ),
        const SizedBox(height: 12),
        ImagePickerWidget(
          maxImages: 3,
          allowMultiSelect: true,
          // 共用元件的提示文字是為聊天截圖寫的（「保留 15 則內」「LINE 回覆框」
          // 「請上傳聊天畫面」），開場救星只收自介／大頭照，那些提示在這裡
          // 不只是多餘、還會誤導（2026-08-19 Eric 真機回報）。上面那行
          // 「上傳對方的交友軟體自介截圖」已經講完這一頁要什麼。
          showHelperText: false,
          // 對齊分析頁空片段的選圖磚大小（2026-08-14 Eric：原 70 太小）
          tileSize: 104,
          surfaceColor: AppColors.coachSurface,
          surfaceBorderColor: AppColors.coachAccent.withValues(alpha: 0.28),
          accentColor: AppColors.coachAccentBright,
          onImagesChanged: (images) => setState(() {
            _images = images;
            _result = null;
            _error = null;
            _currentDraftId = null;
          }),
          externalImages: _images,
        ),
      ],
    );
  }

  Widget _buildRecentDraftsCard() {
    final drafts = _drafts.take(3).toList(growable: false);

    return BrandSurfaceCard(
      tone: BrandVisualTone.coach,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 18,
                color: AppColors.coachAccent,
              ),
              const SizedBox(width: 8),
              Text(
                '最近開場草稿',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '已生成的開場會保留在本機。新截圖不會自動帶入舊結果，想回看再點「回看」。',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          ...drafts.map(_buildDraftRow),
        ],
      ),
    );
  }

  Widget _buildDraftRow(OpenerDraft draft) {
    final continued = draft.continuedAt != null;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.brandInk.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          draft.title,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onBackgroundPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (continued) ...[
                        const SizedBox(width: 6),
                        Text(
                          '已接續',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.coachAccentBright,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    draft.previewForAccess(
                      isFreeUser: !ref.watch(subscriptionProvider).isPremium,
                    ),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.70),
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _openDraft(draft),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ctaStart,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('回看'),
            ),
            IconButton(
              tooltip: '刪除草稿',
              onPressed: () => _deleteDraft(draft.id),
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualTab() {
    return BrandSurfaceCard(
      tone: BrandVisualTone.coach,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel('對方名字'),
          const SizedBox(height: 6),
          _buildBrandField(
            controller: _nameController,
            hintText: '輸入對方名字（選填）',
            maxLength: 200,
            isDense: true,
          ),
          const SizedBox(height: 16),
          _buildFieldLabel('Bio / 自我介紹'),
          const SizedBox(height: 6),
          _buildBrandField(
            controller: _bioController,
            hintText: '貼上對方的自介內容',
            maxLength: 2000,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          _buildFieldLabel('興趣'),
          const SizedBox(height: 6),
          _buildBrandField(
            controller: _interestsController,
            hintText: '對方的興趣標籤（選填）',
            maxLength: 2000,
            isDense: true,
          ),
          const SizedBox(height: 16),
          _buildFieldLabel('認識場景'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _meetingOptions.map((option) {
              return BrandChoiceChip(
                tone: BrandVisualTone.coach,
                label: option,
                selected: _meetingContext == option,
                onTap: () {
                  setState(() {
                    _meetingContext = _meetingContext == option ? null : option;
                    _result = null;
                    _error = null;
                    _currentDraftId = null;
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: AppTypography.bodySmall.copyWith(
        color: AppColors.onBackgroundSecondary.withValues(alpha: 0.82),
      ),
    );
  }

  /// 暗紫橘輸入框（取代淺色 GlassmorphicTextField / 自繪多行框）。
  /// maxLength 用 formatter 靜默截斷（無 counter、不擋操作），鏡像 server
  /// normalizeOpenerProfileInfo 的權威上限，防超長輸入插值進 prompt。
  Widget _buildBrandField({
    required TextEditingController controller,
    required String hintText,
    required int maxLength,
    bool isDense = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
      cursorColor: AppColors.coachAccentBright,
      style: AppTypography.bodyMedium.copyWith(color: Colors.white),
      decoration: brandInputDecoration(
        hintText: hintText,
        tone: BrandVisualTone.coach,
      ).copyWith(
        isDense: isDense,
      ),
    );
  }

  Widget _buildResults(SubscriptionState subscription) {
    final result = _result!;
    final isFree = subscription.isFreeUser && !_resultGeneratedPaid;
    final openerCards = OpeningRescueScreen.visibleOpenerCards(
      openers: result.openers,
      recommendedPick: result.recommendedPick,
      isFreeUser: isFree,
    );

    // 2026-08-18 呈現精修（減法拍板）：預設展開的只留「5 張卡＋推薦理由＋
    // 對方資料解讀／先鋒備案／下一步收成一行標題，點開才展。
    return Column(
      key: _resultsSectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profile analysis card（背景資訊非行動項 → 預設收合）
        if (result.profileAnalysis != null) ...[
          _CollapsibleBrandCard(
            icon: Icons.person_search_outlined,
            title: '對方資料解讀',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildProfileAnalysisItems(result.profileAnalysis!),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Opener cards header
        Row(
          children: [
            Text(
              '開場白建議',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
              ),
            ),
            Text(
              OpeningRescueScreen.openerStylesHeaderSuffix(
                cardCount: openerCards.length,
              ),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
            const Spacer(),
            // 復用分析頁滑動提示（2026-08-19 Eric）：灰字在深底上隱形，
            // 改白底膠囊＋常駐左右晃動，兩頁同一視覺語言。
            const SwipeHintNudge(
              child: SwipeHintChip(),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal scroll opener cards（v2：完成揭示逐張彈入，
        // 沿用 analyze-chat 回覆卡進場語彙；key 綁本輪 result 讓
        // 新結果重播、回看草稿也有同一進場）。
        SizedBox(
          height: 220,
          // ScrollCardTicks 橫向：掃過卡列每換一張打一下輕觸覺——
          // 報告作戰板 Dock 節拍的原生橫向版（2026-08-19 Eric）。
          child: ScrollCardTicks(
            axis: Axis.horizontal,
            focusFraction: 0.3,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: openerCards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final card = openerCards[index];
                return CardTickTarget(
                  index: index,
                  child: StaggeredAppear(
                    key: ValueKey(
                      'opener-card-appear-${identityHashCode(result)}-${card.type}',
                    ),
                    index: index,
                    child: _buildOpenerCard(
                      type: card.type,
                      content: card.content,
                      isRecommended: card.isRecommended,
                      isLocked: card.isLocked,
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        ..._buildOpenerOutcomeBars(openerCards),

        // Recommended reason：free 只在 pick 落在解鎖三型且真的有句時顯示
        //（被鎖 pick 的 reason 是替鎖定內容寫的，不得硬套）。
        if (result.recommendedReason != null &&
            (!isFree ||
                (result.recommendedPick != null &&
                    OpenerAccessContract.freeUnlockedTypes
                        .contains(result.recommendedPick) &&
                    (result.openers[result.recommendedPick]
                            ?.trim()
                            .isNotEmpty ??
                        false)))) ...[
          const SizedBox(height: 12),
          BrandSurfaceCard(
            tone: BrandVisualTone.coach,
            padding: const EdgeInsets.all(12),
            elevated: false,
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 18,
                  color: AppColors.coachRecommendation,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI 推薦理由：${result.recommendedReason}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (result.pioneerPlan != null && result.pioneerPlan!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildPioneerPlanCard(result.pioneerPlan!),
        ],

        const SizedBox(height: 16),
        _buildSavedDraftNotice(),
        const SizedBox(height: 12),
        _buildNextStepCard(),

        const SizedBox(height: 16),

        Center(
          child: Text(
            '想重做？先調整上方線索；畫面會清空這次結果後再生成。',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildSavedDraftNotice() {
    final saved = _currentDraftId != null;

    return BrandSurfaceCard(
      tone: BrandVisualTone.coach,
      padding: const EdgeInsets.all(12),
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            saved ? Icons.bookmark_added_outlined : Icons.info_outline,
            size: 18,
            color: AppColors.coachAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              saved
                  ? '這次開場已儲存成草稿。你可以離開後再回到開場救星回看，不會自動混到下一個對象。'
                  : '這次結果只顯示在目前頁面；若本機儲存失敗，建議先複製想用的開場。',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextStepCard() {
    // 2026-08-19 Eric 拍板：與教練卡「看完整教練分析」同款懸浮深墨膠囊
    // （共用 RevealPill）——頁尾折疊的存在感太低，用戶不知道要往下拉。
    return RevealPill(
      label: '下一步怎麼接？',
      children: [
        Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '開場救星只是「先鋒」：先複製一則去送出，等她真的回覆後，再幫她建一張對象卡分析後續。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          _buildNextStepRow(
            icon: Icons.content_copy_outlined,
            title: '1. 複製開場，去交友軟體送出',
            description: '你可以直接用，也可以照自己的語氣微調。',
          ),
          const SizedBox(height: 8),
          _buildNextStepRow(
            icon: Icons.person_add_alt_1_outlined,
            title: '2. 她回覆後，回來建立對象',
            description: '先幫她建一張對象卡，之後的對話都收在同一個人底下。',
          ),
          const SizedBox(height: 8),
          _buildNextStepRow(
            icon: Icons.psychology_alt_outlined,
            title: '3. 貼上對話，再問教練怎麼接',
            description: '把你送出的那句加上她的回覆貼進對象卡；只有真實互動進入分析後，才會接上對象記憶。',
          ),
          const SizedBox(height: 16),
          BrandPrimaryButton(
            label: '她回覆了，開始分析對話',
            icon: Icons.add_comment_outlined,
            onPressed: () {
              // 蓋「已接續」章是本機 bookkeeping，不擋導航：這一頁本來就會
              // 離開堆疊（pop 或 replace），等一次磁碟寫入只是讓轉場變慢，
              // 也讓導航行為變成無法在 widget test 裡驗證的非同步路徑。
              unawaited(_markDraftContinuedForHandoff());
              OpeningRescueScreen.navigateToHandoff(
                context,
                partnerId: widget.partnerId,
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            '這次結果只套用在目前這組輸入；換對象或換截圖時會清空，避免混到上一個人的開場。',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.62),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        ),
      ],
    );
  }

  Widget _buildNextStepRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: AppColors.coachAccentBright.withValues(alpha: 0.90),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTypography.caption.copyWith(
                  color:
                      AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPioneerPlanCard(Map<String, String> pioneerPlan) {
    final labelMap = {
      'ifCold': '她冷回',
      'ifShortPositive': '短回有接',
      'ifEngaged': '她認真回',
      'handoff': '下一步',
    };

    final entries = pioneerPlan.entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList();

    return _CollapsibleBrandCard(
      icon: Icons.flag_outlined,
      title: '先鋒備案',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '貼出去後如果她冷回或短回，先照這裡接；有新回覆再回來分析或問教練。',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ...entries.map((entry) {
            final label = labelMap[entry.key] ?? entry.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(
                      label,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.coachAccentBright,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  List<Widget> _buildProfileAnalysisItems(Map<String, dynamic> analysis) {
    final items = <Widget>[];

    for (final entry in analysis.entries) {
      // Whitelist: backend may include telemetry keys (e.g. insufficientInfo)
      // in profileAnalysis; only render fields we have a Chinese label for.
      final label = OpeningRescueScreen.profileAnalysisLabelFor(entry.key);
      if (label == null) continue;
      final value = entry.value;
      if (value == null) continue;

      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.coachAccentBright.withValues(alpha: 0.90),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value is List ? value.join('、') : value.toString(),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    return items;
  }

  String? _openerAdviceId(String type) => OpeningRescueScreen.openerAdviceIdFor(
        requestId: _result?.requestId,
        type: type,
      );

  CoachingAdviceContext? _openerAdviceContext({
    required String type,
    required String content,
  }) {
    final adviceId = _openerAdviceId(type);
    if (adviceId == null) return null;
    return CoachingAdviceContext(
      eventId: adviceId,
      partnerId: widget.partnerId,
      source: CoachingOutcomeSource.opener,
      adviceId: adviceId,
      adviceType: type,
      suggestedMoveSummary: content,
    );
  }

  Future<void> _recordOpenerCopy({
    required String type,
    required String content,
  }) async {
    final advice = _openerAdviceContext(type: type, content: content);
    if (advice == null) return;
    try {
      await ref
          .read(coachingOutcomeRecorderProvider)
          .recordAdviceCopied(advice);
    } catch (_) {
      // 記錄失敗不擋複製主流程，也不打擾使用者。
    }
  }

  Future<void> _recordOpenerUserAction({
    required String type,
    required String content,
    required CoachingUserAction action,
  }) async {
    final advice = _openerAdviceContext(type: type, content: content);
    if (advice == null) return;
    try {
      await ref.read(coachingOutcomeRecorderProvider).recordAdviceUserAction(
            advice: advice,
            userAction: action,
            outcome: coachingOutcomeForUserAction(action),
          );
      _showOpenerSnackBar(
        '已記下「${coachingUserActionLabel(action)}」，不扣額度。',
      );
    } catch (_) {
      _showOpenerSnackBar('暫時記不起來，晚點再試一次。');
    }
  }

  Future<void> _recordOpenerReaction({
    required String type,
    required CoachingOutcomeSignal signal,
  }) async {
    final adviceId = _openerAdviceId(type);
    if (adviceId == null) return;
    try {
      final updated = await ref
          .read(coachingOutcomeRecorderProvider)
          .recordAdviceReaction(eventId: adviceId, outcome: signal);
      if (updated == null) return;
      _showOpenerSnackBar(
        '已記下「${coachingOutcomeSignalLabel(signal)}」，不扣額度。',
      );
    } catch (_) {
      _showOpenerSnackBar('暫時記不起來，晚點再試一次。');
    }
  }

  List<Widget> _buildOpenerOutcomeBars(List<OpenerCardSpec> openerCards) {
    final bars = <Widget>[];
    for (final card in openerCards) {
      if (card.isLocked) continue;
      final adviceId = _openerAdviceId(card.type);
      if (adviceId == null) continue;
      final event = ref.watch(coachingOutcomeEventProvider(adviceId));
      if (event == null) continue; // 沒複製過不浮出
      bars.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: CoachingOutcomeFollowUpBar(
          event: event,
          label: OpeningRescueScreen.openerTypeLabels[card.type] ?? card.type,
          onUserActionSelected: (action) => _recordOpenerUserAction(
            type: card.type,
            content: card.content,
            action: action,
          ),
          onOutcomeSelected: (signal) => _recordOpenerReaction(
            type: card.type,
            signal: signal,
          ),
        ),
      ));
    }
    if (bars.isEmpty) return const [];
    return [const SizedBox(height: 4), ...bars];
  }

  Widget _buildOpenerCard({
    required String type,
    required String content,
    bool isRecommended = false,
    bool isLocked = false,
  }) {
    final label = OpeningRescueScreen.openerTypeLabels[type] ?? type;

    return SizedBox(
      width: 280,
      child: BrandSurfaceCard(
        tone: BrandVisualTone.coach,
        borderColor: isRecommended
            ? AppColors.coachRecommendation.withValues(alpha: 0.58)
            : null,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                if (replyStyleIcons[type] != null) ...[
                  Icon(replyStyleIcons[type],
                      size: 16, color: AppColors.onBackgroundPrimary),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
                const Spacer(),
                if (isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.coachRecommendation.withValues(
                        alpha: 0.16,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.coachRecommendation.withValues(
                          alpha: 0.64,
                        ),
                      ),
                    ),
                    child: Text(
                      'AI 推薦',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.coachRecommendation,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Content or locked state
            Expanded(
              child: isLocked
                  ? _buildLockedContent()
                  : Text(
                      content,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        height: 1.6,
                      ),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),

            const SizedBox(height: 8),

            // Copy button or upgrade button
            if (isLocked)
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    await _showPaywallAndRefresh();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ctaStart,
                  ),
                  child: const Text('升級解鎖'),
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    AppHaptics.light();
                    Clipboard.setData(ClipboardData(text: content));
                    unawaited(_recordOpenerCopy(type: type, content: content));
                    _showOpenerSnackBar(
                      OpeningRescueScreen.copiedOpenerMessage(label),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('複製'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ctaStart,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 32,
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            '升級解鎖此風格',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

/// 收合式資訊卡（2026-08-18 減法拍板）：預設只露一行標題，點開才展內容。
/// 用於背景／延後性資訊（對方資料解讀、先鋒備案、下一步），把預設展開的
/// 內容壓到 5 張卡左右的一屏多。
class _CollapsibleBrandCard extends StatefulWidget {
  const _CollapsibleBrandCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  State<_CollapsibleBrandCard> createState() => _CollapsibleBrandCardState();
}

class _CollapsibleBrandCardState extends State<_CollapsibleBrandCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      tone: BrandVisualTone.coach,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: ValueKey('collapsible-card-header-${widget.title}'),
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              AppHaptics.tap();
              setState(() => _expanded = !_expanded);
            },
            child: Padding(
              // 觸控高度 ≥44：內容 padding 外再補 4，避免一行標題太難點。
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 18,
                    color: AppColors.coachAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.onBackgroundSecondary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: widget.child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// v2 串流骨架卡列（2026-08-19）：生成一開始就把五種風格的骨架排出來，
/// server 每寫完一種（`style_<type>` 進度事件）對應卡點亮打勾——「看著它
/// 一張一張寫完」的體感，但內容仍是驗證＋扣費全過的 done 才落地，
/// 扣費前零內容外流。
class _OpenerStyleSkeletonRow extends StatelessWidget {
  const _OpenerStyleSkeletonRow({required this.completedPhases});

  final Set<String> completedPhases;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: OpenerAccessContract.canonicalPaidOrder.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final type = OpenerAccessContract.canonicalPaidOrder[index];
          return _SkeletonStyleCard(
            type: type,
            done: completedPhases.contains('style_$type'),
          );
        },
      ),
    );
  }
}

class _SkeletonStyleCard extends StatelessWidget {
  const _SkeletonStyleCard({required this.type, required this.done});

  final String type;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final label = OpeningRescueScreen.openerTypeLabels[type] ?? type;
    Widget shimmerBar(double width) => Container(
          width: width,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: done ? 0.16 : 0.07),
            borderRadius: BorderRadius.circular(99),
          ),
        );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: done ? 1 : 0.55,
      child: SizedBox(
        width: 148,
        child: BrandSurfaceCard(
          key: ValueKey('opener-skeleton-$type-${done ? 'done' : 'pending'}'),
          tone: BrandVisualTone.coach,
          borderColor:
              done ? AppColors.coachAccent.withValues(alpha: 0.55) : null,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (replyStyleIcons[type] != null) ...[
                    Icon(replyStyleIcons[type],
                        size: 14, color: AppColors.onBackgroundSecondary),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  done
                      ? const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: AppColors.coachAccentBright,
                        )
                      : Icon(
                          Icons.circle_outlined,
                          size: 14,
                          color: AppColors.onBackgroundSecondary
                              .withValues(alpha: 0.4),
                        ),
                ],
              ),
              const SizedBox(height: 12),
              shimmerBar(112),
              const SizedBox(height: 8),
              shimmerBar(88),
              const SizedBox(height: 8),
              shimmerBar(100),
            ],
          ),
        ),
      ),
    );
  }
}

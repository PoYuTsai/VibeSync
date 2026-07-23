import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
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
import '../../../coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../coaching_memory/domain/entities/coaching_outcome_event.dart';
import '../widgets/opener_generation_progress.dart';

class OpeningRescueScreen extends ConsumerStatefulWidget {
  const OpeningRescueScreen({super.key, this.partnerId});

  /// Optional: when entered from a partner-scoped sheet (PartnerDetail / Analysis),
  /// drafts saved here are tagged with this partnerId so the「最近開場草稿」
  /// card knows which person each draft belongs to.
  final String? partnerId;

  /// Builds the `/new` handoff URL used by the「她回覆了，開始分析對話」CTA.
  /// Carries partnerId when the screen was entered from a partner-scoped flow
  /// so the resulting conversation stays bound to the same partner.
  static String handoffLocationFor({String? partnerId}) {
    final trimmed = partnerId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '/new?source=opener';
    }
    return Uri(
      path: '/new',
      queryParameters: {'source': 'opener', 'partnerId': trimmed},
    ).toString();
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
    'extend': '🔄 延展',
    'resonate': '💬 共鳴',
    'tease': '😏 調情',
    'humor': '🎭 幽默',
    'coldRead': '🔮 冷讀',
  };

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
      return cards;
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
  OpenerResult? _result;
  String? _error;
  final _scrollController = ScrollController();
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

  bool get _hasBoundPartner =>
      widget.partnerId != null && widget.partnerId!.trim().isNotEmpty;

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

  OpenerResult _resultForCurrentAccess(OpenerResult result) {
    final subscription = ref.read(subscriptionProvider);
    return result.visibleForAccess(isFreeUser: !subscription.isPremium);
  }

  Future<void> _saveLatestForHandoff() async {
    final result = _result;
    if (result == null) return;
    final handoffResult = _resultForCurrentAccess(result);

    try {
      if (!_hasBoundPartner) {
        await _resultCacheService.saveLatest(handoffResult);
      }
      final draftId = _currentDraftId;
      if (draftId != null) {
        await _resultCacheService.markDraftContinued(draftId);
      }
    } catch (_) {
      // Starting a conversation should not fail because local metadata failed.
    }
  }

  Future<void> _openDraft(OpenerDraft draft) async {
    try {
      if ((draft.partnerId ?? '').trim().isEmpty) {
        await _resultCacheService.saveLatest(
          _resultForCurrentAccess(draft.result),
        );
      }
    } catch (_) {
      // Best effort only; the visible result is still useful.
    }

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
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
        effectiveStyleContext = await ref
            .read(openerStyleContextProvider(widget.partnerId).future);
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
      final rawResult = await service.generateOpeners(
        images: input.images,
        name: input.name,
        bio: input.bio,
        interests: input.interests,
        meetingContext: input.meetingContext,
        expectedTier: expectedTier,
        revenueCatAppUserId: revenueCatAppUserId,
        effectiveStyleContext: attempt.styleContext,
        requestId: attempt.requestId,
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

        try {
          await ref.read(subscriptionScreenRefreshProvider)();
        } catch (_) {
          // The opener result already succeeded; usage UI can catch up on the
          // next subscription refresh if this best-effort sync fails.
        }
        if (!mounted) return;

        // 滾到結果區域
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
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
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 72),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      safeArea: false,
      body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  '開場救星',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.ctaStart,
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
                const SizedBox(height: 20),

                // Tab switcher
                BrandSegmentedButton<int>(
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
                const SizedBox(height: 20),

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
                  label: OpeningRescueScreen.generateButtonText(
                    hasResult: hasGeneratedResult,
                  ),
                  isLoading: _isGenerating,
                  onPressed: OpeningRescueScreen.canStartGeneration(
                    isGenerating: _isGenerating,
                    hasResult: hasGeneratedResult,
                  )
                      ? _generate
                      : null,
                ),
                const SizedBox(height: 16),

                // Loading state：staged 本地進度文案（F3-2 低配版，
                // 真 streaming 另案）。文案凍結在 _generate 送出的 input，
                // 不讀 activeInput——生成中切 tab/改輸入不得讓文案漂移。
                if (_isGenerating)
                  Center(
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
          ),
        ),
    );
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 18,
                color: AppColors.ctaStart,
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
          const SizedBox(height: 10),
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
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.brandInk.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(14),
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
                            color: AppColors.ctaStart,
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
                padding: const EdgeInsets.symmetric(horizontal: 10),
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
                label: option,
                selected: _meetingContext == option,
                onTap: () {
                  setState(() {
                    _meetingContext =
                        _meetingContext == option ? null : option;
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
      cursorColor: AppColors.ctaStart,
      style: AppTypography.bodyMedium.copyWith(color: Colors.white),
      decoration: brandInputDecoration(hintText: hintText).copyWith(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profile analysis card
        if (result.profileAnalysis != null) ...[
          BrandSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '對方資料解讀',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ..._buildProfileAnalysisItems(result.profileAnalysis!),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
            Text(
              '左右滑動看更多',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal scroll opener cards
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: openerCards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final card = openerCards[index];
              return _buildOpenerCard(
                type: card.type,
                content: card.content,
                isRecommended: card.isRecommended,
                isLocked: card.isLocked,
              );
            },
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
            padding: const EdgeInsets.all(12),
            elevated: false,
            child: Row(
              children: [
                const Text('💡', style: TextStyle(fontSize: 16)),
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
      padding: const EdgeInsets.all(12),
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            saved ? Icons.bookmark_added_outlined : Icons.info_outline,
            size: 18,
            color: AppColors.ctaStart,
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
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_outlined,
                size: 18,
                color: AppColors.ctaStart,
              ),
              const SizedBox(width: 8),
              Text(
                '下一步怎麼接？',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '開場救星只是「先鋒」：先複製一則去送出，等她真的回覆後，再建立新對話分析後續。',
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
          const SizedBox(height: 10),
          _buildNextStepRow(
            icon: Icons.chat_bubble_outline,
            title: '2. 她回覆後，回來開新對話',
            description: '把你送出的那句，加上她的回覆一起貼上。',
          ),
          const SizedBox(height: 10),
          _buildNextStepRow(
            icon: Icons.psychology_alt_outlined,
            title: '3. 分析後再問教練怎麼接',
            description: '只有真實互動進入分析後，才會接上對象記憶。',
          ),
          const SizedBox(height: 14),
          BrandPrimaryButton(
            label: '她回覆了，開始分析對話',
            icon: Icons.add_comment_outlined,
            onPressed: () async {
              await _saveLatestForHandoff();
              if (!mounted) return;
              setState(_reloadDrafts);
              context.push(OpeningRescueScreen.handoffLocationFor(
                partnerId: widget.partnerId,
              ));
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
          color: AppColors.ctaStart.withValues(alpha: 0.86),
        ),
        const SizedBox(width: 10),
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
                  color: AppColors.onBackgroundSecondary
                      .withValues(alpha: 0.70),
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

    return BrandSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_outlined,
                size: 18,
                color: AppColors.ctaStart,
              ),
              const SizedBox(width: 8),
              Text(
                '先鋒備案',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(
                      label,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ctaStart,
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
    final labelMap = {
      'style': '風格',
      'personality': '切入判斷',
      'avoidTopics': '先避開',
      'frameRead': '框架判斷',
      'positiveHooks': '可接線索',
      'masterObservation': '高手觀察',
      'curiosityHook': '好奇鉤子',
      'masterMove': '高手手法',
      'twoBallPlan': '雙球策略',
      'talkingPoints': '話題切入點',
      'openingStrategy': '推薦策略',
      'vibe': '氛圍',
      'interests': '興趣',
    };

    for (final entry in analysis.entries) {
      // Whitelist: backend may include telemetry keys (e.g. insufficientInfo)
      // in profileAnalysis; only render fields we have a Chinese label for.
      final label = labelMap[entry.key];
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
                  color: AppColors.ctaStart.withValues(alpha: 0.86),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
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
                      gradient: const LinearGradient(
                        colors: [AppColors.ctaStart, AppColors.ctaEnd],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'AI 推薦',
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
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

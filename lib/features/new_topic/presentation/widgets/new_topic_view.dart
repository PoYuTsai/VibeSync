import '../../../../shared/widgets/local_avatar.dart';
import '../../../../shared/widgets/brand/opener_entry_icon.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../../shared/widgets/brand/opener_home_components.dart';
import '../../../opener/presentation/widgets/opener_quota_sheet.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/scroll_card_ticks.dart';
import '../../../../shared/widgets/staggered_appear.dart';
import '../../../../shared/widgets/stream_progress_ticker.dart';
import '../../../opener/presentation/widgets/opener_generation_progress.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../partner/presentation/widgets/partner_picker_sheet.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../subscription/domain/services/subscription_tier_helper.dart';
import '../../../subscription/presentation/paywall_entry.dart';
import '../../../subscription/presentation/quota_copy.dart';
import '../../data/providers/new_topic_providers.dart';
import '../../data/services/new_topic_service.dart';
import '../../domain/entities/new_topic_result.dart';
import '../../domain/new_topic_two_stage_copy.dart';
import '../../../opener/presentation/widgets/blank_fill_sheet.dart';
import 'new_topic_idea_card.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../core/services/app_haptics.dart';

/// 新話題（破冰腦力）分頁（計畫 §13）。掛在 OpeningRescueScreen 的
/// IndexedStack 內：切換模式不 unmount，結果/錯誤/requestId 全保留。
class NewTopicView extends ConsumerStatefulWidget {
  const NewTopicView({super.key, this.initialPartnerId, this.isActive = true});
  final bool isActive;
  @visibleForTesting
  static NewTopicService Function()? debugServiceFactory;
  @visibleForTesting
  static String? Function()? debugOwnerIdOverride;

  /// 從 partner-scoped 入口帶進來的初選對象；必須先驗證存在
  /// owner-scoped partner list 才預選（missing/deleted 顯示重新選擇）。
  final String? initialPartnerId;

  /// 第一問四個可 deselect 的情境（文案在兩段式文案檔）。
  static const situationOptions = NewTopicTwoStageCopy.situationOptions;

  /// New Topic 專用 staged 進度文案。
  static const progressPhrases = [
    '正在整理她的作戰板…',
    '從你們的互動找新切入點…',
    '挑出她最可能接的話題…',
    '打磨可以直接送出的第一句…',
    '還在整理最適合先試的方向，請保持連線…',
  ];

  /// 對象紀錄還不多時的說明。新話題不讀「關於我」（規格 PR-5），只能說會參考
  /// 使用者這次選的狀況或寫的素材。
  static const thinRecordHelper = '她的紀錄還不多，這次會先參考你選的狀況或寫下的素材。';

  /// 額度不足（生成前看到、或伺服器回過額度不足）時，主按鈕直接開付費頁：免費、
  /// Starter 寫升級；Essential 已經是最高方案，只寫查看方案（Eric 2026-10-18）。
  static const upgradeButtonLabel = '升級方案';
  static const viewPlansButtonLabel = '查看方案';

  static const freeUpsellHeadline = '免費版先看最推薦的 1 個完整方案';
  static const freeUpsellBody = '升級可再解鎖另外 4 個話題';

  /// 未分類例外可能含 SDK 類名、HTTP status、server code 與整包 details。
  /// 已知錯誤應在 service 轉成 typed exception；漏網者一律固定文案，
  /// 不能再用「字串裡有中文」當成可直接顯示的安全判準。
  static String customerMessageForUnexpectedError(Object _) =>
      '新話題暫時生成失敗，請稍後再試。';

  @override
  ConsumerState<NewTopicView> createState() => _NewTopicViewState();
}

class _NewTopicViewState extends ConsumerState<NewTopicView> {
  final _scrollController = ScrollController();
  // 2026-08-18 呈現精修：完成後定格在結果區頂端（這組根據、新話題建議），不再
  // 捲到底略過 5 張題卡。
  final _resultsSectionKey = GlobalKey();
  // 生成中那一行狀態：生成鈕固定在底部，按下後要捲到看得到（2026-10-12）。
  final _progressKey = GlobalKey();
  // 正在跑「捲到看得到進度」的動畫：那不是用戶在捲，結果到時照樣定格。新動畫會取消舊的、
  // 舊的 Future 仍會完成，所以只有最新那次（編號相同）可以清掉旗標。
  bool _revealingProgress = false;
  int _revealGeneration = 0;
  final _situationKey = GlobalKey();
  final _materialController = TextEditingController();

  String? _selectedPartnerId;
  String? _situation;
  String? _coldDuration;
  String? _coldStop;
  String? _engagement;
  String? _materialKind;
  // 進階不可用時用戶選了基本模式：同一組答案改不送 topicContext，
  // 任何答案或對象改變就回到進階。
  bool _forceBasic = false;
  // 真串流進度（server 事件）；每次生成開始清空。空＝還沒收到事件
  //（或 server 降級 legacy），顯示本地輪播 fallback。heartbeat 不進清單。
  final List<String> _streamProgress = [];
  // 已完成的串流 phase（topic_1…topic_5）：骨架卡點亮用（v2）。
  final Set<String> _completedStreamPhases = {};
  NewTopicResult? _result;
  String? _error;

  /// 伺服器回的額度錯誤：說明在顯示時才照目前方案組（見 [_shownError]）。
  NewTopicQuotaExceededException? _quotaError;
  bool _isGenerating = false;
  bool _preparing = false;
  final _partnerFocus = FocusNode();
  bool _showDetails = false;
  bool _pendingScroll = false;
  bool _confirmPending = false;
  // 伺服器明確回過「額度不足」的那一筆（請求編號）：沒有落帳，同一筆再按只會再被擋。
  // 只綁那一筆：換對象或答案後別的待重試請求（可能已落帳）照常可以取回。
  String? _quotaRejectedRequestId;
  int _inputVersion = 0;
  String? get _owner =>
      NewTopicView.debugOwnerIdOverride?.call() ??
      SupabaseService.currentUser?.id;
  bool get _busy => _preparing || _isGenerating;
  NewTopicTwoStageAnswers get _answers => NewTopicTwoStageAnswers(
        situation: _situation,
        coldDuration: _coldDuration,
        coldStop: _coldStop,
        engagement: _engagement,
        materialKind: _materialKind,
        materialText: _materialController.text,
      );
  Map<String, dynamic>? get _topicContext =>
      _forceBasic ? null : _answers.toTopicContextJson();

  /// 要送出非空素材原文才算素材（空字串不算，同 server hasNewTopicMaterial）。
  static bool _hasMaterialText(Map<String, dynamic>? topicContext) =>
      (topicContext?['materialText'] as String?)?.isNotEmpty ?? false;

  @override
  void didUpdateWidget(covariant NewTopicView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive && _pendingScroll) {
      _snapToResults();
    }
  }

  void _snapToResults() {
    if (!widget.isActive) {
      _pendingScroll = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.isActive ||
          !_pendingScroll &&
              !_revealingProgress &&
              _scrollController.position.isScrollingNotifier.value) {
        return;
      }
      final target = _resultsSectionKey.currentContext;
      if (target == null) return;
      _pendingScroll = false;
      snapSectionTopIntoView(target);
    });
  }

  /// 生成鈕固定在底部，進度那一行常落在它後面：開始生成、串流第一個事件到時，
  /// 捲到它剛好露出（只在看不到時捲）。
  void _revealProgress() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive || !_isGenerating) return;
      final target = _progressKey.currentContext;
      if (target == null) return;
      final generation = ++_revealGeneration;
      _revealingProgress = true;
      Scrollable.ensureVisible(target,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppMotion.scroll,
              curve: AppMotion.easeOut)
          .whenComplete(() {
        if (generation == _revealGeneration) _revealingProgress = false;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _selectedPartnerId = widget.initialPartnerId?.trim();
    if (_selectedPartnerId?.isEmpty ?? false) _selectedPartnerId = null;
  }

  @override
  void dispose() {
    _partnerFocus.dispose();
    _scrollController.dispose();
    _materialController.dispose();
    super.dispose();
  }

  /// route 帶進來的 partnerId 每次 build 都對 owner-scoped list 驗證；
  /// missing/deleted 視同未選（顯示重新選擇），不能只信未驗證 lookup。
  String? _validatedPartnerId() {
    final id = _selectedPartnerId;
    if (id == null) return null;
    final partners = ref.read(partnerListProvider);
    return partners.any((p) => p.id == id) ? id : null;
  }

  Future<void> _pickPartner() async {
    if (_busy || !widget.isActive) return;
    final owner = _owner;
    final version = _inputVersion;
    final partners = ref.read(partnerListProvider);
    if (partners.isEmpty) {
      await context.push('/partner/new');
      return;
    }

    final selected = await showAppSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OpenerHomeStyle.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(sheetContext).height -
                          MediaQuery.viewInsetsOf(sheetContext).bottom) *
                      0.8),
              child: PartnerPickerSheet(
                  openerStyle: true,
                  selectedId: _selectedPartnerId,
                  onSelected: (partner) =>
                      Navigator.pop(sheetContext, partner.id)))),
    );
    if (!mounted ||
        selected == null ||
        selected == _selectedPartnerId ||
        owner != _owner ||
        version != _inputVersion ||
        !ref.read(partnerListProvider).any((p) => p.id == selected)) {
      return;
    }

    if (!await _confirmClearResultIfNeeded()) return;
    if (!mounted || owner != _owner || version != _inputVersion) return;
    setState(() {
      _inputVersion++;
      _selectedPartnerId = selected;
      _forceBasic = false;
      _result = null;
      _confirmPending = false;
      _showDetails = false;
      _error = null;
    });
  }

  /// 任何答案變更：有結果先確認清除，再套用變更（同一份答案才沿用 requestId）。
  Future<bool> _changeAnswers(void Function() apply) async {
    if (_busy) return false;
    final owner = _owner, version = _inputVersion;
    if (!await _confirmClearResultIfNeeded()) return false;
    if (!mounted || owner != _owner || version != _inputVersion) return false;
    setState(() {
      _inputVersion++;
      apply();
      _forceBasic = false;
      _result = null;
      _confirmPending = false;
      _error = null;
    });
    return true;
  }

  /// 所有選項再點一次就取消。
  static String? _toggle(String? current, String value) =>
      current == value ? null : value;

  /// 換第一問清掉追問、保留素材。
  void _selectSituation(String value) => unawaited(_changeAnswers(() {
        _situation = _toggle(_situation, value);
        _coldDuration = _coldStop = _engagement = null;
      }));

  /// 「調整狀況」：清結果後捲回第一問。
  Future<void> _adjustAnswers() async {
    if (!await _changeAnswers(() {})) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _situationKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(target,
          alignment: 0.04,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.scroll,
          curve: AppMotion.easeOut);
    });
  }

  /// 進階不可用：問要不要改用基本模式；答案與文字都保留。
  Future<void> _offerBasicMode() async {
    final owner = _owner, version = _inputVersion;
    final basic = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.coachSurfaceRaised,
        title: Text(
          NewTopicTwoStageCopy.advancedUnavailableTitle,
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onBackgroundSecondary,
            ),
            child: const Text(NewTopicTwoStageCopy.advancedUnavailableCancel),
          ),
          TextButton(
            onPressed:
                AppHaptics.onPress(() => Navigator.pop(dialogContext, true)),
            style: TextButton.styleFrom(foregroundColor: AppColors.ctaStart),
            child: const Text(NewTopicTwoStageCopy.advancedUnavailableConfirm),
          ),
        ],
      ),
    );
    if (basic != true ||
        !mounted ||
        owner != _owner ||
        version != _inputVersion) {
      return;
    }
    setState(() => _forceBasic = true);
    await _generate();
  }

  /// 已有結果時要換 Partner／情境，先確認會清除舊結果（§13.7）。
  /// 確認後只清 New Topic result；Opener result 完全不受影響。
  Future<bool> _confirmClearResultIfNeeded() async {
    if (_result == null) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.coachSurfaceRaised,
        title: Text(
          '更換條件會清除目前結果',
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        content: Text(
          '目前這批新話題不會保存，確定要更換嗎？',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onBackgroundSecondary,
            ),
            child: const Text('先不要'),
          ),
          TextButton(
            onPressed:
                AppHaptics.onPress(() => Navigator.pop(dialogContext, true)),
            style: TextButton.styleFrom(foregroundColor: AppColors.ctaStart),
            child: const Text('清除並更換'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    return true;
  }

  Future<void> _generate() async {
    if (_busy || _result != null || !widget.isActive) return;
    final partnerId = _validatedPartnerId();
    if (partnerId == null) return;
    final owner = _owner, version = _inputVersion;
    if (owner == null) return;
    final requestSession = ref.read(
        newTopicRequestSessionProvider((ownerId: owner, partnerId: partnerId)));
    final situation = _situation;
    final topicContext = _topicContext;
    final partnerContext = ref.read(newTopicPartnerContextProvider(partnerId));
    final pending = requestSession.pendingFor(
        partnerId: partnerId, situation: situation, topicContext: topicContext);
    var offerBasic = false;
    String? styleContext = pending?.effectiveStyleContext;
    bool current() =>
        mounted &&
        owner == _owner &&
        version == _inputVersion &&
        _validatedPartnerId() == partnerId &&
        ref.read(newTopicReadinessProvider(partnerId)) !=
            NewTopicReadiness.dataQualityBlocked;
    if (!current()) return;
    // 生成前收鍵盤（同開場白），進度與結果不被鍵盤擋住。
    FocusScope.of(context).unfocus();
    setState(() {
      _preparing = true;
      _error = null;
      _quotaError = null;
      _quotaRejectedRequestId = null;
    });
    try {
      if (pending == null) {
        try {
          styleContext =
              await ref.read(newTopicStyleContextProvider(partnerId).future);
        } catch (_) {/* Other real materials may still be sufficient. */}
      }
      if (!current()) return;
      if (pending == null &&
          !canGenerateNewTopic(
              readiness: ref.read(newTopicReadinessProvider(partnerId)),
              situation: situation,
              hasMaterialText: _hasMaterialText(topicContext))) {
        setState(() => _error = '請選一個目前情境，或先補充對象資料。');
        return;
      }
      // A background preparation may finish, but it must never open a modal
      // over the other mode. The user can submit again when this mode is visible.
      if (!mounted || !widget.isActive) return;
      final consented =
          await AiDataSharingConsent.ensure(context, featureLabel: '新話題');
      if (!current() || !consented) return;
      final subscriptionSnapshot = ref.read(subscriptionProvider);
      // A pending operation can already be settled; always resolve its original ID.
      if (pending == null &&
          !subscriptionSnapshot.isLoading &&
          subscriptionSnapshot.error == null &&
          (subscriptionSnapshot.monthlyRemaining < kNewTopicQuotaCost ||
              subscriptionSnapshot.dailyRemaining < kNewTopicQuotaCost)) {
        setState(() => _error = '本次需要 $kNewTopicQuotaCost 則，目前可用額度不足。');
        _trackQuotaBlock(QuotaBlockSource.precheck,
            isMonthly:
                subscriptionSnapshot.monthlyRemaining < kNewTopicQuotaCost);
        if (widget.isActive) {
          await _showPaywallAndRefresh(
              entry: _quotaEntryFor(subscriptionSnapshot));
        }
        return;
      }
      var expectedTier = pending?.expectedTier ?? subscriptionSnapshot.tier;
      String? revenueCatAppUserId = pending?.revenueCatAppUserId;
      if (pending == null) {
        try {
          final info = await RevenueCatService.getCustomerInfo();
          if (!current()) return;
          final tier = RevenueCatService.getTierFromCustomerInfo(info);
          revenueCatAppUserId = RevenueCatService.getRevenueCatAppUserId(info);
          if (SubscriptionTierHelper.rankOf(tier) >
              SubscriptionTierHelper.rankOf(expectedTier)) {
            expectedTier = tier;
          }
        } catch (_) {/* Server remains authoritative. */}
      }
      if (!current()) return;
      final attempt = requestSession.beginAttempt(
        partnerId: partnerId,
        partnerSummary: partnerContext.promptText,
        effectiveStyleContext: styleContext,
        situation: situation,
        topicContext: topicContext,
        expectedTier: expectedTier,
        revenueCatAppUserId: revenueCatAppUserId,
      );
      setState(() {
        _preparing = false;
        _isGenerating = true;
        _streamProgress.clear();
        _completedStreamPhases.clear();
      });
      _revealProgress();
      final service =
          NewTopicView.debugServiceFactory?.call() ?? NewTopicService();
      final result = await service.generateTopicsStreaming(
        requestId: attempt.requestId,
        partnerSummary: attempt.partnerSummary,
        effectiveStyleContext: attempt.effectiveStyleContext,
        situation: attempt.situation,
        topicContext: attempt.topicContext,
        expectedTier: attempt.expectedTier,
        revenueCatAppUserId: attempt.revenueCatAppUserId,
        onProgress: (label, phase) {
          if (!current() || !_isGenerating || phase == 'heartbeat') return;
          final first = _streamProgress.isEmpty;
          setState(() {
            _streamProgress.add(label);
            if (phase != null) _completedStreamPhases.add(phase);
          });
          // 本地輪播換成串流狀態列，位置會變：再確認一次看得到。
          if (first) _revealProgress();
        },
      );
      if (!current()) return;
      requestSession.markSuccess();
      setState(() {
        _result = result;
        _confirmPending = false;
        _preparing = false;
        _isGenerating = false;
      });
      _snapToResults();
      unawaited(_refreshUsageAfterResult());
    } on NewTopicQuotaExceededException catch (e) {
      if (!current()) return;
      setState(() {
        _error = e.message;
        _quotaError = e;
        _quotaRejectedRequestId = requestSession
            .pendingFor(
                partnerId: partnerId,
                situation: situation,
                topicContext: topicContext)
            ?.requestId;
      });
      _trackQuotaBlock(QuotaBlockSource.server, isMonthly: e.isMonthly);
      if (widget.isActive) {
        await _showPaywallAndRefresh(
          entry: PaywallEntry.forQuota(
            isMonthly: e.isMonthly,
            remaining: e.remaining,
          ),
        );
      }
    } on NewTopicRequestInProgressException catch (e) {
      if (!current()) return;
      setState(() {
        _error = e.message;
        _confirmPending = true;
      });
    } on NewTopicStatePendingException catch (e) {
      if (!current()) return;
      setState(() {
        _error = e.message;
        _confirmPending = true;
      });
    } on NewTopicAdvancedUnavailableException catch (e) {
      if (!current()) return;
      // server 回這個時已佔住這筆編號且保證不會落帳（Codex R2 P1）：清掉 pending，
      // 之後再按會換新編號，不會撞上被佔住的租約而空等。
      requestSession.markSuccess();
      // 基本模式不帶素材原文：它自己生得出來才提議，否則請用戶先選第一問。
      offerBasic = canGenerateNewTopic(
          readiness: ref.read(newTopicReadinessProvider(partnerId)),
          situation: situation,
          hasMaterialText: false);
      setState(() => _error = offerBasic
          ? e.message
          : NewTopicTwoStageCopy.advancedUnavailableNeedsSituation);
    } on NewTopicMaterialBlockedException catch (e) {
      if (!current()) return;
      // 同一句重送一定再被擋：不留 pending，按鈕回到「生成新話題」。
      requestSession.markSuccess();
      setState(() => _error = e.message);
    } on NewTopicReplayMismatchException catch (e) {
      if (!current()) return;
      // 同一個編號再送只會再撞：丟掉 pending，下次按生成換新編號。
      requestSession.markSuccess();
      setState(() => _error = e.message);
    } on NewTopicException catch (e) {
      if (!current()) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!current()) return;
      setState(
          () => _error = NewTopicView.customerMessageForUnexpectedError(e));
    } finally {
      if (mounted && version == _inputVersion) {
        setState(() {
          _preparing = false;
          _isGenerating = false;
        });
      }
    }
    // 生成鎖解開後才開對話框，選基本模式才能再進 _generate。
    if (offerBasic && current() && widget.isActive) await _offerBasicMode();
  }

  Future<void> _refreshUsageAfterResult() async {
    try {
      await ref.read(subscriptionScreenRefreshProvider)();
    } catch (_) {
      /* A delivered result does not depend on subscription refresh. */
    }
  }

  /// 額度不足的說法在顯示時照目前訂閱方案組（主審第 1 輪 P2-2）：重試時請求照舊帶
  /// 那筆的 expectedTier，說明卻要照用戶現在的方案（跟付費頁大標同一個來源）。
  /// [error] 正是這筆額度錯誤時才換，其他錯誤照原文。
  String _shownError(String error, String tier) {
    final quotaError = _quotaError;
    return quotaError != null && error == quotaError.message
        ? quotaShortMessage(
            tier: tier,
            isMonthly: quotaError.isMonthly,
            feature: '新話題',
          )
        : error;
  }

  /// 額度不足事件（onboarding 轉換第 6 步）：只記錄，不影響額度判斷與付費頁。
  void _trackQuotaBlock(QuotaBlockSource source, {required bool isMonthly}) =>
      unawaited(ref.read(funnelTrackerProvider).trackQuotaBlockShown(
            feature: QuotaBlockFeature.newTopic,
            scope: isMonthly ? QuotaBlockScope.monthly : QuotaBlockScope.daily,
            source: source,
          ));

  /// 額度不夠時開付費頁的入口：跟伺服器一樣先看本月、再看今天，付費頁照每月或
  /// 每日、用完或只是不夠換大標（Eric 2026-10-18）。
  PaywallEntry _quotaEntryFor(SubscriptionState usage) {
    final isMonthly = usage.monthlyRemaining < kNewTopicQuotaCost;
    return PaywallEntry.forQuota(
      isMonthly: isMonthly,
      remaining: isMonthly ? usage.monthlyRemaining : usage.dailyRemaining,
    );
  }

  /// [entry]：從哪裡打開，付費頁的大標跟著換；免費的鎖卡入口照舊一般入口。
  Future<void> _showPaywallAndRefresh({
    PaywallEntry entry = PaywallEntry.general,
  }) async {
    if (!mounted || !widget.isActive) return;
    final owner = _owner;
    await context.push<String>('/paywall', extra: entry);
    if (owner != _owner) return;
    if (!mounted) return;
    try {
      await ref.read(subscriptionScreenRefreshProvider)();
    } catch (e) {
      debugPrint('NewTopicView paywall refresh failed: $e');
    }
    if (!mounted || owner != _owner) return;
    final subscription = ref.read(subscriptionProvider);
    if (_error != null && subscription.isPremium) {
      setState(() => _error = null);
    }
  }

  Future<void> _copyOpeningLine(NewTopicIdea idea) async {
    var text = idea.openingLine;
    // 留「＿＿」的句子先填好再複製（Bruce 2026-10-18 #97：三個功能留空格一律用「＿＿」）。
    if (blankFillNeeded(text)) {
      final filled = await showBlankFillSheet(context, text: text);
      if (filled == null || !mounted) return;
      text = filled;
    }
    AppHaptics.light();
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    // 去識別化：只記有複製、是不是推薦那題，不含句子（量新話題有沒有被拿去傳）。
    unawaited(ref.read(funnelTrackerProvider).track('new_topic_copied',
        properties: {
          'is_recommended': idea.id == _result?.recommendation.topicId,
        }));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('已複製這句話，貼到聊天室送出試試。')),
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authConversationScopeProvider, (previous, next) {
      if (previous?.hasValue != true ||
          previous?.valueOrNull == next.valueOrNull) {
        return;
      }
      setState(() {
        _inputVersion++;
        _selectedPartnerId = null;
        _situation = null;
        _coldDuration = _coldStop = _engagement = _materialKind = null;
        _materialController.clear();
        _forceBasic = false;
        _result = null;
        _error = null;
        _preparing = false;
        _isGenerating = false;
        _pendingScroll = false;
        _confirmPending = false;
        _showDetails = false;
      });
    });
    ref.listen(partnerListProvider, (previous, next) {
      final selected = _selectedPartnerId;
      if (selected == null ||
          previous == null ||
          !previous.any((p) => p.id == selected) ||
          next.any((p) => p.id == selected)) {
        return;
      }
      final owner = _owner;
      if (owner != null) {
        ref
            .read(newTopicRequestSessionProvider(
                (ownerId: owner, partnerId: selected)))
            .markSuccess();
      }
      setState(() {
        _inputVersion++;
        _result = null;
        _error = '找不到這位對象，請重新選擇。';
        _preparing = false;
        _isGenerating = false;
        _confirmPending = false;
      });
    });
    final partners = ref.watch(partnerListProvider);
    final validPartnerId = _validatedPartnerId();
    final partner = validPartnerId == null
        ? null
        : partners.firstWhere((p) => p.id == validPartnerId);
    final readiness = validPartnerId == null
        ? NewTopicReadiness.missingPartner
        : ref.watch(newTopicReadinessProvider(validPartnerId));
    final style = validPartnerId == null
        ? const AsyncData<String?>(null)
        : ref.watch(newTopicStyleContextProvider(validPartnerId));
    final answers = _answers;
    final topicContext = _topicContext;
    final hasMaterialText = _hasMaterialText(topicContext);
    final owner = _owner;
    final requestSession = owner == null || validPartnerId == null
        ? null
        : ref.watch(newTopicRequestSessionProvider(
            (ownerId: owner, partnerId: validPartnerId)));
    final pending = requestSession?.pendingFor(
        partnerId: validPartnerId,
        situation: _situation,
        topicContext: topicContext);
    final loading = style.isLoading && pending == null;
    final ready = pending != null
        ? validPartnerId != null &&
            readiness != NewTopicReadiness.dataQualityBlocked
        : !loading &&
            canGenerateNewTopic(
                readiness: readiness,
                situation: _situation,
                hasMaterialText: hasMaterialText);
    // 選了要寫的素材卻沒寫或超長：不能生成，不偷偷截斷。
    final materialHint = answers.materialMissing
        ? NewTopicTwoStageCopy.materialMissingHint
        : answers.materialTooLong
            ? NewTopicTwoStageCopy.materialTooLongHint
            : null;
    // 第一問以外的素材（含用戶寫的那句）夠不夠：夠就可以不選第一問。
    final otherMaterials = canGenerateNewTopic(
        readiness: readiness,
        situation: null,
        hasMaterialText: hasMaterialText);
    final usage = ref.watch(subscriptionProvider);
    final quotaShort = !usage.isLoading &&
        usage.error == null &&
        (usage.monthlyRemaining < kNewTopicQuotaCost ||
            usage.dailyRemaining < kNewTopicQuotaCost);
    // 待重試的那筆可能已落帳（重試只回放、不扣），平常照樣讓它重試；伺服器明確回過
    // 額度不足的那筆沒有落帳，再按只會再被擋：跟生成前額度不足一樣給付費頁入口。
    final quotaBlocked = quotaShort &&
        (pending == null || pending.requestId == _quotaRejectedRequestId);
    // 提示與按鈕在底下那一列，有結果時整列收起來（見下面的 footer）：真的顯示給他看
    // 才記，成功用完最後額度不算撞額度（Codex 主審第 1 輪 P2）。
    if (quotaBlocked && widget.isActive && _result == null) {
      // 按鈕換成「升級／查看方案」、提示寫額度不足：畫完這一幀再記。
      final isMonthly = usage.monthlyRemaining < kNewTopicQuotaCost;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _trackQuotaBlock(QuotaBlockSource.precheck, isMonthly: isMonthly);
        }
      });
    }
    final helper = validPartnerId == null
        ? '先選擇聊天對象，再補充目前情境。'
        : readiness == NewTopicReadiness.dataQualityBlocked
            ? '這位對象的資料需要先確認。'
            : loading
                ? '正在整理可用素材…'
                : otherMaterials
                    ? '可以不選，直接找新的切入點。'
                    : '請選一個目前情境，或先補充對象資料。';
    final footer = OpenerActionFooter(
      buttonKey: const ValueKey('new-topic-generate'),
      label: _preparing
          ? '正在準備…'
          : _isGenerating
              ? '生成中…'
              : quotaBlocked
                  ? (canUpgradeQuota(usage.tier)
                      ? NewTopicView.upgradeButtonLabel
                      : NewTopicView.viewPlansButtonLabel)
                  : _confirmPending && pending != null
                      ? '確認本次結果'
                      : pending != null
                          ? '重試'
                          : '生成新話題',
      hint: quotaBlocked
          ? '本次需要 $kNewTopicQuotaCost 則，目前可用額度不足。'
          : materialHint != null && validPartnerId != null
              ? materialHint
              : ready
                  ? '將使用 $kNewTopicQuotaCost 則額度'
                  : validPartnerId == null
                      ? '先選擇聊天對象'
                      : '',
      onPressed: _busy
          ? null
          : quotaBlocked
              ? () => unawaited(
                  _showPaywallAndRefresh(entry: _quotaEntryFor(usage)))
              : !ready || materialHint != null
                  ? null
                  : _generate,
      onQuota: () => showOpenerQuotaSheet(context, newTopic: true),
    );
    return ScrollCardTicks(
        child: OpenerResponsiveBody(
            controller: _scrollController,
            footer: _result == null ? footer : null,
            content:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('換個話題，讓聊天繼續', style: OpenerHomeStyle.title),
              const SizedBox(height: 8),
              const Text('從她的興趣和你們的互動，找到新切入點。', style: OpenerHomeStyle.body),
              const SizedBox(height: 24),
              _buildPartnerCard(partner,
                  _selectedPartnerId != null && validPartnerId == null),
              const SizedBox(height: 24),
              Text(NewTopicTwoStageCopy.situationTitle,
                  key: _situationKey, style: OpenerHomeStyle.label),
              const SizedBox(height: 8),
              OpenerSituationGrid(
                  options: NewTopicView.situationOptions,
                  selected: _situation,
                  onChanged: _busy ? null : _selectSituation),
              ..._buildFollowUps(answers),
              ..._buildMaterial(answers),
              const SizedBox(height: 8),
              Semantics(
                  liveRegion: true,
                  child: Text(helper, style: OpenerHomeStyle.helper)),
              if (readiness == NewTopicReadiness.dataQualityBlocked)
                TextButton(
                    onPressed: AppHaptics.onPress(_busy
                        ? null
                        : () => context.push('/partner/$validPartnerId')),
                    child: const Text('查看對象資料')),
              if (style.hasError && validPartnerId != null)
                TextButton(
                    onPressed: AppHaptics.onPress(_busy
                        ? null
                        : () => ref.invalidate(
                            newTopicStyleContextProvider(validPartnerId))),
                    child: const Text('重新載入個人風格')),
              const SizedBox(height: 16),
              // v2：串流事件到達後顯示一行狀態＋五張題卡骨架（topic_n 事件
              // 點亮）；事件未到（連線中／legacy 降級）沿用本地輪播。
              if (_isGenerating)
                _streamProgress.isNotEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KeyedSubtree(
                              key: _progressKey,
                              child: StreamProgressTicker(
                                  labels: _streamProgress)),
                          if (!_completedStreamPhases
                              .contains('finalizing')) ...[
                            const SizedBox(height: 12),
                            _TopicSkeletonList(
                              enteredPhases: _completedStreamPhases,
                            ),
                          ],
                        ],
                      )
                    : KeyedSubtree(
                        key: _progressKey,
                        child: const Center(
                          child: OpenerGenerationProgress(
                            phrases: NewTopicView.progressPhrases,
                          ),
                        ),
                      ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                      liveRegion: true,
                      child: Center(
                        child: Text(
                          _shownError(_error!, usage.tier),
                          style: AppTypography.bodyMedium
                              .copyWith(color: AppColors.error),
                          textAlign: TextAlign.center,
                        ),
                      )),
                ),
              if (_result != null) ...[
                const SizedBox(height: 24),
                KeyedSubtree(
                  key: _resultsSectionKey,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBasisRow(),
                        const SizedBox(height: 8),
                        NewTopicResultsSection(
                          result: _result!,
                          onCopyIdeaOpeningLine: _copyOpeningLine,
                          onUpgrade: _showPaywallAndRefresh,
                        ),
                      ]),
                ),
              ],
            ])));
  }

  Widget _choiceGroup(String? title, List<NewTopicOption> options,
      String? selected, ValueChanged<String> onTap,
      {required String keyPrefix}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null) ...[
        const SizedBox(height: 16),
        Text(title, style: OpenerHomeStyle.body),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final option in options)
          BrandChoiceChip(
            key: ValueKey('$keyPrefix-${option.value}'),
            label: option.label,
            selected: selected == option.value,
            tone: BrandVisualTone.coach,
            enabled: !_busy,
            onTap: () => onTap(option.value),
          ),
      ]),
    ]);
  }

  /// 第一問的追問＋教練提醒（選了第一問才出現）。
  List<Widget> _buildFollowUps(NewTopicTwoStageAnswers answers) {
    final situation = _situation;
    if (situation == null) return const [];
    final tip = NewTopicTwoStageCopy.coachTip(answers);
    return [
      if (situation == 'went_cold') ...[
        _choiceGroup(
            NewTopicTwoStageCopy.coldDurationTitle,
            NewTopicTwoStageCopy.coldDurationOptions,
            _coldDuration,
            (v) => unawaited(_changeAnswers(
                () => _coldDuration = _toggle(_coldDuration, v))),
            keyPrefix: 'new-topic-cold-duration'),
        _choiceGroup(
            NewTopicTwoStageCopy.coldStopTitle,
            NewTopicTwoStageCopy.coldStopOptions,
            _coldStop,
            (v) => unawaited(
                _changeAnswers(() => _coldStop = _toggle(_coldStop, v))),
            keyPrefix: 'new-topic-cold-stop'),
      ] else
        _choiceGroup(
            NewTopicTwoStageCopy.engagementTitle(situation),
            NewTopicTwoStageCopy.engagementOptions(situation),
            _engagement,
            (v) => unawaited(
                _changeAnswers(() => _engagement = _toggle(_engagement, v))),
            keyPrefix: 'new-topic-engagement'),
      if (tip != null) ...[
        const SizedBox(height: 16),
        OpenerHomePanel(
            key: const ValueKey('new-topic-coach-tip'),
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.tips_and_updates_outlined,
                    size: 18, color: AppColors.coachAccentBright),
                SizedBox(width: 6),
                Text(NewTopicTwoStageCopy.coachTipTitle,
                    style: OpenerHomeStyle.label),
              ]),
              const SizedBox(height: 6),
              Text(tip.open, style: OpenerHomeStyle.body),
              const SizedBox(height: 4),
              Text(tip.avoid, style: OpenerHomeStyle.body),
            ])),
      ],
    ];
  }

  /// 第二問＋素材輸入框（選了要寫的素材才出現）。
  List<Widget> _buildMaterial(NewTopicTwoStageAnswers answers) {
    final inputTitle =
        NewTopicTwoStageCopy.materialInputTitle(_materialKind, _situation);
    final tooLong = answers.materialTooLong;
    return [
      const SizedBox(height: 24),
      const Text(NewTopicTwoStageCopy.materialTitle,
          style: OpenerHomeStyle.label),
      _choiceGroup(
          null,
          NewTopicTwoStageCopy.materialOptions(_situation),
          _materialKind,
          (v) => unawaited(
              _changeAnswers(() => _materialKind = _toggle(_materialKind, v))),
          keyPrefix: 'new-topic-material'),
      if (inputTitle != null) ...[
        const SizedBox(height: 16),
        // 標題已由下方 Semantics 掛在輸入框上，避免 VoiceOver 唸兩次。
        ExcludeSemantics(child: Text(inputTitle, style: OpenerHomeStyle.body)),
        const SizedBox(height: 8),
        // 不用 formatter 截斷：超長保留原文、顯示紅字、擋生成。
        Semantics(
          label: inputTitle,
          child: TextField(
            key: const ValueKey('new-topic-material-text'),
            controller: _materialController,
            readOnly: _busy || _result != null,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() {
              _inputVersion++;
              _forceBasic = false;
              _confirmPending = false;
              _error = null;
            }),
            cursorColor: AppColors.coachAccentBright,
            style: AppTypography.bodyMedium.copyWith(color: Colors.white),
            // 大字級時提示會換行，不能被截掉。
            decoration: OpenerHomeStyle.field(
                    NewTopicTwoStageCopy.materialInputHint(_materialKind))
                .copyWith(hintMaxLines: 5),
          ),
        ),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(NewTopicTwoStageCopy.materialHelper(_materialKind),
                  style: OpenerHomeStyle.helper)),
          const SizedBox(width: 8),
          Flexible(
              child: Semantics(
                  liveRegion: tooLong,
                  child: Text(
                    NewTopicTwoStageCopy.materialCounter(
                        answers.materialLength),
                    key: const ValueKey('new-topic-material-counter'),
                    textAlign: TextAlign.end,
                    style: OpenerHomeStyle.helper
                        .copyWith(color: tooLong ? AppColors.error : null),
                  ))),
        ]),
      ],
    ];
  }

  /// 結果上方：「這組根據」＋「調整狀況」。
  Widget _buildBasisRow() {
    // 基本模式沒有送追問與素材，根據只剩第一問。
    final basis = NewTopicTwoStageCopy.basisLine(_forceBasic
        ? NewTopicTwoStageAnswers(situation: _situation)
        : _answers);
    return Row(children: [
      Expanded(
          child: basis == null
              ? const SizedBox.shrink()
              : Text(basis,
                  key: const ValueKey('new-topic-basis'),
                  style: OpenerHomeStyle.helper)),
      TextButton(
          key: const ValueKey('new-topic-adjust'),
          onPressed: AppHaptics.onPress(_busy ? null : _adjustAnswers),
          style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: OpenerHomeStyle.accent),
          child: const Text(NewTopicTwoStageCopy.adjustButton)),
    ]);
  }

  Future<void> _openPartnerPicker() async {
    await _pickPartner();
    if (mounted && widget.isActive) _partnerFocus.requestFocus();
  }

  Widget _buildPartnerCard(Partner? partner, bool invalid) {
    final noPartners = ref.watch(partnerListProvider).isEmpty;
    final contextData = partner == null
        ? null
        : ref.watch(newTopicPartnerContextProvider(partner.id));
    final aggregate = partner == null
        ? null
        : ref.watch(partnerAggregateProvider(partner.id));
    final detailLabels = [
      ...?aggregate?.unionInterests,
      ...?aggregate?.unionTraits
    ].take(3).join('、');
    final hasDetails = (contextData?.hasActionableSignals ?? false) ||
        aggregate?.latestHeat != null ||
        detailLabels.isNotEmpty;
    final title = partner?.name ??
        (invalid
            ? '重新選擇聊天對象'
            : noPartners
                ? '先建立聊天對象'
                : '選擇聊天對象');
    final description = partner != null
        ? '已選擇聊天對象'
        : invalid
            ? '找不到原本的對象，請重新選擇。'
            : noPartners
                ? '建立後，就能根據她的資料找新話題。'
                : '根據她的作戰板，找到適合你們的話題。';
    return OpenerHomePanel(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
              button: true,
              enabled: !_busy,
              label: partner == null ? title : '目前對象 ${partner.name}，更換對象',
              child: InkWell(
                focusNode: _partnerFocus,
                borderRadius: BorderRadius.circular(24),
                onTap: AppHaptics.onPress(_busy ? null : _openPartnerPicker),
                child: ExcludeSemantics(
                    child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: partner == null ? 128 : 88),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final vertical =
                          MediaQuery.textScalerOf(context).scale(15) > 20;
                      final Widget avatar = partner == null
                          ? OpenerEntryIcon(
                              kind: OpenerEntryKind.partner,
                              size: constraints.maxWidth >= 300 ? 128 : 104)
                          : Container(
                              width: 48,
                              height: 48,
                              clipBehavior: Clip.antiAlias,
                              decoration: const BoxDecoration(
                                  color: OpenerHomeStyle.selected,
                                  shape: BoxShape.circle),
                              child: LocalAvatar(
                                  path: partner.avatarPath,
                                  fallback: const Icon(Icons.person_outline,
                                      size: 28, color: OpenerHomeStyle.icon)));
                      final copy = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title,
                                maxLines: partner == null ? null : 2,
                                overflow: partner == null
                                    ? null
                                    : TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                            const SizedBox(height: 4),
                            Text(description, style: OpenerHomeStyle.body),
                          ]);
                      final change =
                          Row(mainAxisSize: MainAxisSize.min, children: [
                        if (partner != null)
                          const Text('更換', style: OpenerHomeStyle.helper),
                        const Icon(Icons.chevron_right,
                            size: 20, color: OpenerHomeStyle.secondary),
                      ]);
                      if (vertical) {
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [avatar, const Spacer(), change]),
                              const SizedBox(height: 12),
                              copy
                            ]);
                      }
                      return Row(children: [
                        avatar,
                        SizedBox(width: partner == null ? 8 : 12),
                        Expanded(child: copy),
                        const SizedBox(width: 4),
                        change
                      ]);
                    }),
                  ),
                )),
              )),
          if (partner != null && !hasDetails)
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(NewTopicView.thinRecordHelper,
                    style: OpenerHomeStyle.helper)),
          if (hasDetails)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton(
                          onPressed: AppHaptics.onPress(() =>
                              setState(() => _showDetails = !_showDetails)),
                          child: Text(_showDetails ? '收合使用資料' : '查看使用資料')),
                      if (_showDetails)
                        Text(
                            [
                              if (aggregate?.latestHeat != null)
                                '目前熱度：${aggregate!.latestHeat}',
                              if (detailLabels.isNotEmpty) detailLabels,
                              if (contextData?.hasNoteSignals ?? false)
                                '已加入你的備註',
                              if (detailLabels.isEmpty &&
                                  !(contextData?.hasNoteSignals ?? false))
                                '已加入你們的互動紀錄',
                            ].join('\n'),
                            style: OpenerHomeStyle.body),
                    ])),
        ]));
  }
}

/// 結果區（抽成公開 widget 供 widget test 直接驗證排序與可見性；
/// 計畫 §10.3）：推薦理由 → 原 topics → Free upsell。
class NewTopicResultsSection extends StatelessWidget {
  const NewTopicResultsSection({
    super.key,
    required this.result,
    required this.onCopyIdeaOpeningLine,
    required this.onUpgrade,
  });

  final NewTopicResult result;
  final ValueChanged<NewTopicIdea> onCopyIdeaOpeningLine;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final recommendedId = result.recommendation.topicId;
    // 2026-08-19 v2：AI 推薦題固定排第一（免捲動找），其餘維持原序。
    final orderedTopics = [
      ...result.topics.where((idea) => idea.id == recommendedId),
      ...result.topics.where((idea) => idea.id != recommendedId),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '新話題建議',
          style: AppTypography.titleLarge.copyWith(color: Colors.white),
        ),
        if (result.recommendation.reason?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                size: 18,
                color: AppColors.coachRecommendation,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI 推薦理由：${result.recommendation.reason}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // v2：完成揭示逐張彈入（同 opener 卡進場語彙）。
        for (final (index, idea) in orderedTopics.indexed) ...[
          // CardTickTarget：捲過焦點線打一下輕觸覺（Mac Dock 節拍的垂直版）。
          CardTickTarget(
            index: index,
            child: StaggeredAppear(
              key: ValueKey(
                'topic-card-appear-${identityHashCode(result)}-${idea.id}',
              ),
              index: index,
              child: NewTopicIdeaCard(
                idea: idea,
                isRecommended: idea.id == recommendedId,
                onCopyOpeningLine: () => onCopyIdeaOpeningLine(idea),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Free：一張完整推薦卡＋compact upsell，不渲染四張空鎖卡（§13.6）。
        if (result.access.isFree)
          BrandSurfaceCard(
            tone: BrandVisualTone.coach,
            padding: const EdgeInsets.all(16),
            elevated: false,
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  color: AppColors.onBackgroundSecondary.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        NewTopicView.freeUpsellHeadline,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onBackgroundPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        NewTopicView.freeUpsellBody,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onUpgrade,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ctaStart,
                  ),
                  child: const Text('升級解鎖'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 欄位開始事件只表示進入該題；正式內容只在 done 驗證成功後顯示。
class _TopicSkeletonList extends StatelessWidget {
  const _TopicSkeletonList({required this.enteredPhases});

  final Set<String> enteredPhases;

  @override
  Widget build(BuildContext context) {
    Widget shimmerBar(double width, bool started) => Container(
          width: width,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: started ? 0.16 : 0.07),
            borderRadius: BorderRadius.circular(99),
          ),
        );
    return Column(
      children: [
        for (var n = 1; n <= 5; n++) ...[
          if (n > 1) const SizedBox(height: 8),
          Builder(builder: (context) {
            final started = enteredPhases.contains('topic_$n');
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: started ? 1 : 0.55,
              child: BrandSurfaceCard(
                key: ValueKey(
                  'topic-skeleton-$n-${started ? 'started' : 'pending'}',
                ),
                tone: BrandVisualTone.coach,
                borderColor: started
                    ? AppColors.coachAccent.withValues(alpha: 0.55)
                    : null,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '新話題 $n',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.onBackgroundSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          shimmerBar(180, started),
                          const SizedBox(height: 6),
                          shimmerBar(120, started),
                        ],
                      ),
                    ),
                    started
                        ? const Icon(
                            Icons.more_horiz_rounded,
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
              ),
            );
          }),
        ],
      ],
    );
  }
}

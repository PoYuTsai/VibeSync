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
import '../../data/providers/new_topic_providers.dart';
import '../../data/services/new_topic_request_session.dart';
import '../../data/services/new_topic_service.dart';
import '../../domain/entities/new_topic_result.dart';
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

  /// 四個可 deselect 的情境 chips（不提供自由輸入）。
  static const situationOptions = [
    (label: '冷掉了', value: 'went_cold'),
    (label: '剛約完', value: 'after_date'),
    (label: '聊著但卡住', value: 'stuck'),
    (label: '想升溫', value: 'warm_up'),
  ];

  /// New Topic 專用 staged 進度文案。
  static const progressPhrases = [
    '正在整理她的作戰板…',
    '從你們的互動找新切入點…',
    '把你的風格放進話題裡…',
    '打磨可以直接送出的第一句…',
    '還在整理最適合先試的方向，請保持連線…',
  ];

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
  // 2026-08-18 呈現精修：完成後定格在「新話題建議」標題，不再捲到底
  // 略過 5 張題卡。
  final _resultsSectionKey = GlobalKey();
  final _requestSession = NewTopicRequestSession();

  String? _selectedPartnerId;
  String? _situation;
  // 真串流進度（server 事件）；每次生成開始清空。空＝還沒收到事件
  //（或 server 降級 legacy），顯示本地輪播 fallback。heartbeat 不進清單。
  final List<String> _streamProgress = [];
  // 已完成的串流 phase（topic_1…topic_5）：骨架卡點亮用（v2）。
  final Set<String> _completedStreamPhases = {};
  NewTopicResult? _result;
  String? _error;
  bool _isGenerating = false;
  bool _preparing = false;
  final _partnerFocus = FocusNode();
  bool _showDetails = false;
  bool _pendingScroll = false;
  bool _confirmPending = false;
  int _inputVersion = 0;
  String? get _owner =>
      NewTopicView.debugOwnerIdOverride?.call() ??
      SupabaseService.currentUser?.id;
  bool get _busy => _preparing || _isGenerating;

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
              _scrollController.position.isScrollingNotifier.value) {
        return;
      }
      final target = _resultsSectionKey.currentContext;
      if (target == null) return;
      _pendingScroll = false;
      Scrollable.ensureVisible(target,
          alignment: 0.04,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.scroll,
          curve: AppMotion.easeOut);
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
      _result = null;
      _confirmPending = false;
      _showDetails = false;
      _error = null;
    });
  }

  Future<void> _selectSituation(String? value) async {
    if (_busy) return;
    final next = _situation == value ? null : value;
    if (next == _situation) return;
    final owner = _owner, version = _inputVersion;
    if (!await _confirmClearResultIfNeeded()) return;
    if (!mounted || owner != _owner || version != _inputVersion) return;
    setState(() {
      _inputVersion++;
      _situation = next;
      _result = null;
      _confirmPending = false;
      _error = null;
    });
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
    final situation = _situation;
    final partnerContext = ref.read(newTopicPartnerContextProvider(partnerId));
    final pending =
        _requestSession.pendingFor(partnerId: partnerId, situation: situation);
    bool current() =>
        mounted &&
        owner == _owner &&
        version == _inputVersion &&
        _validatedPartnerId() == partnerId &&
        ref.read(newTopicReadinessProvider(partnerId)) !=
            NewTopicReadiness.dataQualityBlocked;
    if (!current()) return;
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      String? styleContext = pending?.effectiveStyleContext;
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
              styleContext: styleContext,
              situation: situation)) {
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
        if (widget.isActive) await _showPaywallAndRefresh();
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
      final attempt = _requestSession.beginAttempt(
        partnerId: partnerId,
        partnerSummary: partnerContext.promptText,
        effectiveStyleContext: styleContext,
        situation: situation,
        expectedTier: expectedTier,
        revenueCatAppUserId: revenueCatAppUserId,
      );
      setState(() {
        _preparing = false;
        _isGenerating = true;
        _streamProgress.clear();
        _completedStreamPhases.clear();
      });
      final service =
          NewTopicView.debugServiceFactory?.call() ?? NewTopicService();
      final result = await service.generateTopicsStreaming(
        requestId: attempt.requestId,
        partnerSummary: attempt.partnerSummary,
        effectiveStyleContext: attempt.effectiveStyleContext,
        situation: attempt.situation,
        expectedTier: attempt.expectedTier,
        revenueCatAppUserId: attempt.revenueCatAppUserId,
        onProgress: (label, phase) {
          if (!current() || !_isGenerating || phase == 'heartbeat') return;
          setState(() {
            _streamProgress.add(label);
            if (phase != null) _completedStreamPhases.add(phase);
          });
        },
      );
      if (!current()) return;
      _requestSession.markSuccess();
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
      setState(() => _error = e.message);
      if (widget.isActive) await _showPaywallAndRefresh();
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
  }

  Future<void> _refreshUsageAfterResult() async {
    try {
      await ref.read(subscriptionScreenRefreshProvider)();
    } catch (_) {
      /* A delivered result does not depend on subscription refresh. */
    }
  }

  Future<void> _showPaywallAndRefresh() async {
    if (!mounted || !widget.isActive) return;
    final owner = _owner;
    await context.push<String>('/paywall');
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

  void _copyOpeningLine(NewTopicIdea idea) {
    AppHaptics.light();
    Clipboard.setData(ClipboardData(text: idea.openingLine));
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
        _result = null;
        _error = null;
        _preparing = false;
        _isGenerating = false;
        _pendingScroll = false;
        _confirmPending = false;
        _showDetails = false;
        _requestSession.markSuccess();
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
      setState(() {
        _inputVersion++;
        _result = null;
        _error = '找不到這位對象，請重新選擇。';
        _preparing = false;
        _isGenerating = false;
        _confirmPending = false;
        _requestSession.markSuccess();
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
    final pending = _requestSession.pendingFor(
        partnerId: validPartnerId, situation: _situation);
    final loading = style.isLoading && pending == null;
    final ready = pending != null
        ? validPartnerId != null &&
            readiness != NewTopicReadiness.dataQualityBlocked
        : !loading &&
            canGenerateNewTopic(
                readiness: readiness,
                styleContext:
                    pending?.effectiveStyleContext ?? style.valueOrNull,
                situation: _situation);
    final otherMaterials = canGenerateNewTopic(
        readiness: readiness, styleContext: style.valueOrNull, situation: null);
    final usage = ref.watch(subscriptionProvider);
    final quotaBlocked = pending == null &&
        !usage.isLoading &&
        usage.error == null &&
        (usage.monthlyRemaining < kNewTopicQuotaCost ||
            usage.dailyRemaining < kNewTopicQuotaCost);
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
              : _confirmPending && pending != null
                  ? '確認本次結果'
                  : pending != null
                      ? '重試'
                      : '生成新話題',
      hint: quotaBlocked
          ? '本次需要 $kNewTopicQuotaCost 則，目前可用額度不足。'
          : ready
              ? '將使用 $kNewTopicQuotaCost 則額度'
              : validPartnerId == null
                  ? '先選擇聊天對象'
                  : '',
      onPressed: _busy || !ready || quotaBlocked ? null : _generate,
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
              const Text('目前聊得怎麼樣？（選填）', style: OpenerHomeStyle.label),
              const SizedBox(height: 8),
              OpenerSituationGrid(
                  options: NewTopicView.situationOptions,
                  selected: _situation,
                  onChanged: _busy
                      ? null
                      : (value) => unawaited(_selectSituation(value))),
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
                          StreamProgressTicker(labels: _streamProgress),
                          if (!_completedStreamPhases
                              .contains('finalizing')) ...[
                            const SizedBox(height: 12),
                            _TopicSkeletonList(
                              enteredPhases: _completedStreamPhases,
                            ),
                          ],
                        ],
                      )
                    : const Center(
                        child: OpenerGenerationProgress(
                          phrases: NewTopicView.progressPhrases,
                        ),
                      ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                      liveRegion: true,
                      child: Center(
                        child: Text(
                          _error!,
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
                  child: NewTopicResultsSection(
                    result: _result!,
                    onCopyIdeaOpeningLine: _copyOpeningLine,
                    onUpgrade: _showPaywallAndRefresh,
                  ),
                ),
              ],
            ])));
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
                child: Text('她的紀錄還不多，這次會先參考你的設定或所選情境。',
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

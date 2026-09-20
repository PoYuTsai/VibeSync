import '../../../../shared/widgets/local_avatar.dart';
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
    if (_busy) return;
    final owner = _owner;
    final version = _inputVersion;
    final partners = ref.read(partnerListProvider);
    if (partners.isEmpty) {
      context.push('/partner/new');
      return;
    }

    final selected = await showAppSheet<String>(
      context: context,
      backgroundColor: AppColors.coachSurfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => PartnerPickerSheet(
        openerStyle: true,
        selectedId: _selectedPartnerId,
        onSelected: (partner) => Navigator.pop(sheetContext, partner.id),
      ),
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
    if (mounted) setState(() => _result = null);
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
      if (!mounted) return;
      final consented =
          await AiDataSharingConsent.ensure(context, featureLabel: '新話題');
      if (!current() || !consented) return;
      final subscriptionSnapshot = ref.read(subscriptionProvider);
      // A pending operation can already be settled; always resolve its original ID.
      if (pending == null &&
          !subscriptionSnapshot.isLoading &&
          subscriptionSnapshot.error == null &&
          (subscriptionSnapshot.monthlyRemaining < 3 ||
              subscriptionSnapshot.dailyRemaining < 3)) {
        setState(() => _error = '本次需要 3 則，目前可用額度不足。');
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
      });
      _snapToResults();
      try {
        await ref.read(subscriptionScreenRefreshProvider)();
      } catch (_) {/* Keep delivered result. */}
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
    if (!mounted) return;
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
    final ready = !loading &&
        canGenerateNewTopic(
            readiness: readiness,
            styleContext: pending?.effectiveStyleContext ?? style.valueOrNull,
            situation: _situation);
    final otherMaterials = canGenerateNewTopic(
        readiness: readiness, styleContext: style.valueOrNull, situation: null);
    final usage = ref.watch(subscriptionProvider);
    final quotaBlocked = pending == null &&
        !usage.isLoading &&
        usage.error == null &&
        (usage.monthlyRemaining < 3 || usage.dailyRemaining < 3);
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
              : _confirmPending
                  ? '確認本次結果'
                  : pending != null
                      ? '重試'
                      : '生成新話題',
      hint: quotaBlocked
          ? '本次需要 3 則，目前可用額度不足。'
          : ready
              ? '將使用 3 則額度'
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
              const Text('目前聊得怎麼樣？（選填）', style: OpenerHomeStyle.body),
              const SizedBox(height: 8),
              OpenerSituationGrid(
                  options: NewTopicView.situationOptions,
                  selected: _situation,
                  onChanged: _busy
                      ? null
                      : (value) => unawaited(_selectSituation(value))),
              const SizedBox(height: 8),
              Text(helper, style: OpenerHomeStyle.helper),
              if (style.hasError && validPartnerId != null)
                TextButton(
                    onPressed: _busy
                        ? null
                        : () => ref.invalidate(
                            newTopicStyleContextProvider(validPartnerId)),
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
                          const SizedBox(height: 12),
                          _TopicSkeletonList(
                            completedPhases: _completedStreamPhases,
                          ),
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
                  child: Center(
                    child: Text(
                      _error!,
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
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

  Widget _buildPartnerCard(Partner? partner, bool invalid) {
    final noPartners = ref.watch(partnerListProvider).isEmpty;
    final contextData = partner == null
        ? null
        : ref.watch(newTopicPartnerContextProvider(partner.id));
    final hasDetails = contextData?.hasActionableSignals ?? false;
    final aggregate = partner == null
        ? null
        : ref.watch(partnerAggregateProvider(partner.id));
    final detailLabels = [
      ...?aggregate?.unionInterests,
      ...?aggregate?.unionTraits
    ].take(3).join('、');
    final avatar = partner?.avatarPath;
    final fallback =
        const Icon(Icons.person_outline, size: 28, color: OpenerHomeStyle.icon);
    return OpenerHomePanel(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
              button: true,
              label: partner == null ? '選擇聊天對象' : '目前對象 ${partner.name}，更換對象',
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _busy ? null : _pickPartner,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 120),
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ExcludeSemantics(
                            child: Row(children: [
                          Container(
                              width: 48,
                              height: 48,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                  color: OpenerHomeStyle.selected,
                                  borderRadius: BorderRadius.circular(24)),
                              child: LocalAvatar(
                                  path: avatar, fallback: fallback)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(
                                    partner?.name ??
                                        (noPartners ? '先建立聊天對象' : '選擇聊天對象'),
                                    style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                                const SizedBox(height: 4),
                                Text(
                                    partner != null
                                        ? '已選擇聊天對象'
                                        : invalid
                                            ? '原本的對象已不存在，請重新選擇'
                                            : '根據她的作戰板，找到適合你們的話題。',
                                    style: OpenerHomeStyle.helper),
                              ])),
                          const Icon(Icons.chevron_right,
                              color: OpenerHomeStyle.secondary),
                        ])))),
              )),
          if (partner != null && !hasDetails)
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text('這位對象的紀錄還很少，建議可能會比較通用。',
                    style: OpenerHomeStyle.helper)),
          if (hasDetails)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton(
                          onPressed: () =>
                              setState(() => _showDetails = !_showDetails),
                          child: Text(_showDetails ? '收合使用資料' : '查看使用資料')),
                      if (_showDetails)
                        Text(
                            [
                              if (detailLabels.isNotEmpty) detailLabels,
                              if (contextData!.hasNoteSignals) '已加入你的備註',
                              if (detailLabels.isEmpty &&
                                  !contextData.hasNoteSignals)
                                '已加入你們的互動紀錄'
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
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        if (result.recommendation.reason != null) ...[
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
                  style: AppTypography.bodySmall.copyWith(
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
                        style: AppTypography.bodySmall.copyWith(
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

/// v2 串流骨架卡列（2026-08-19）：五個新話題的骨架，server 每寫完一題
/// （topic_n 進度事件）就點亮一張；內容仍是 done 才落地（扣費前零外流）。
class _TopicSkeletonList extends StatelessWidget {
  const _TopicSkeletonList({required this.completedPhases});

  final Set<String> completedPhases;

  @override
  Widget build(BuildContext context) {
    Widget shimmerBar(double width, bool done) => Container(
          width: width,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: done ? 0.16 : 0.07),
            borderRadius: BorderRadius.circular(99),
          ),
        );
    return Column(
      children: [
        for (var n = 1; n <= 5; n++) ...[
          if (n > 1) const SizedBox(height: 8),
          Builder(builder: (context) {
            final done = completedPhases.contains('topic_$n');
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: done ? 1 : 0.55,
              child: BrandSurfaceCard(
                key: ValueKey(
                  'topic-skeleton-$n-${done ? 'done' : 'pending'}',
                ),
                tone: BrandVisualTone.coach,
                borderColor:
                    done ? AppColors.coachAccent.withValues(alpha: 0.55) : null,
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
                          shimmerBar(180, done),
                          const SizedBox(height: 6),
                          shimmerBar(120, done),
                        ],
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
              ),
            );
          }),
        ],
      ],
    );
  }
}

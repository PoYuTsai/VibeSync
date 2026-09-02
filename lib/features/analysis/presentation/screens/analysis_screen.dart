// lib/features/analysis/presentation/screens/analysis_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/message_calculator.dart';
import '../../../../core/services/keyboard_privacy_purge_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../shared/services/image_compress_service.dart';
import '../../../../shared/services/screenshot_preflight_service.dart';
import '../../../../shared/widgets/analysis_preview_dialog.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../../shared/widgets/brand/brand_feedback_snack_bar.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/coach_action_card.dart';
import '../../../coach_chat/data/services/coach_chat_api_service.dart';
import '../../../coach_chat/presentation/widgets/coach_cta_card.dart';
import '../../../../shared/widgets/coaching_outcome_capture_card.dart';
import '../../../../shared/widgets/coaching_outcome_follow_up_bar.dart';
import '../../../analysis_history/data/providers/analysis_history_providers.dart';
import '../../../coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../coaching_memory/domain/entities/coaching_outcome_event.dart';
import '../../../conversation/data/providers/conversation_archive_providers.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/data/providers/conversation_write_controller.dart';
import '../../../follow_up_notification/data/providers/follow_up_notification_service.dart';
import '../../../follow_up_notification/domain/follow_up_opt_in.dart';
import '../../../follow_up_notification/presentation/soft_opt_in_card.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../partner/presentation/utils/conversation_archive_sections.dart';
import '../../data/providers/analysis_record_providers.dart';
import '../../application/analysis_persistence_coordinator.dart';
import '../../application/analysis_run_preparer.dart';
import '../../application/analysis_session_controller.dart';
import '../../application/reply_iteration_coordinator.dart';
import '../../application/screenshot_import_coordinator.dart';
import '../../data/providers/analysis_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../../conversation/presentation/widgets/new_conversation_sheet.dart';
import '../../data/notifiers/streaming_analyze_notifier.dart';
import '../../data/services/analysis_archive_lifecycle.dart';
import '../../data/services/analysis_hint_service.dart';
import '../../data/services/analysis_service.dart';
import '../../data/services/analysis_telemetry_guardrail_helper.dart';
import '../../data/services/optimize_message_request_session.dart';
import '../../domain/coach/coach_action_policy.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/enthusiasm_level.dart';
import '../../domain/entities/game_stage.dart';
import '../../domain/entities/analysis_record.dart';
import '../../domain/services/analysis_fragment_policy.dart';
import '../../domain/services/screenshot_recognition_helper.dart';
import '../../domain/services/screenshot_session_context_defaults.dart';
import '../screens/partner_analysis_records_screen.dart';
import '../widgets/analysis_platform_picker.dart';
import '../widgets/draft_polish_sheet.dart';
import '../widgets/reply_refine_sheet.dart';
import '../widgets/reply_style_card.dart';
import '../widgets/screenshot_recognition_dialog.dart';
import '../widgets/analysis_usage_summary_line.dart';
import '../helpers/analysis_progress_stage_copy.dart';
import '../sections/analysis_banners_section.dart';
import '../sections/analysis_error_card.dart';
import '../sections/analysis_followup_section.dart';
import '../sections/analysis_fragment_section.dart';
import '../sections/analysis_feedback_section.dart';
import '../sections/detailed_analysis_section.dart';
import '../sections/edit_message_coach_mark.dart';
import '../sections/recognized_conversation_section.dart';
import '../sections/reply_zone_section.dart';
import '../sections/screenshot_intake_section.dart';
import '../sections/streaming_content_section.dart';
import '../sections/telemetry_diagnostics_section.dart';
import '../helpers/analysis_run_metadata_mapping.dart';
import '../helpers/analysis_usage_copy.dart';
import '../widgets/analysis_action_widgets.dart';
import '../widgets/streaming_analysis_loading_widgets.dart';
import '../../../learning/presentation/screens/ebook_detail_screen.dart'
    show ebookChapterRoute;
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../subscription/domain/services/subscription_tier_helper.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../../user_profile/data/providers/partner_style_providers.dart';
import '../../../user_profile/domain/entities/user_profile.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../core/services/app_haptics.dart';
import '../../data/services/analysis_transport_support.dart';

/// Keeps user intent separate from programmatic live-follow movement without
/// indenting the analysis screen's large child tree.
class _AnalysisScrollView extends SingleChildScrollView {
  const _AnalysisScrollView({
    required this.onUserScrollTowardStart,
    super.controller,
    super.padding,
    super.keyboardDismissBehavior,
    super.child,
  }) : super(key: const ValueKey('analysis-primary-scroll'));

  final VoidCallback onUserScrollTowardStart;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        if (notification.dragDetails != null &&
            (notification.scrollDelta ?? 0) < 0) {
          onUserScrollTowardStart();
        }
        return false;
      },
      child: super.build(context),
    );
  }
}

class AnalysisScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const AnalysisScreen({
    super.key,
    required this.conversationId,
  });

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

enum _AnalysisErrorOrigin {
  analysis,
  recognition,
}

enum _AnalysisAppBarAction {
  profile,
  export,
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin
    implements
        AnalysisFeedbackActions,
        AnalysisFragmentActions,
        RecognitionDraftActions,
        ReplyZoneActions,
        ScreenshotIntakeActions {
  // 訂閱同步屬 best-effort 前置：卡住不得凍結分析/刷新 spinner（2.1(b)）。
  static const _subscriptionSyncTimeout = Duration(seconds: 20);
  bool get _showTelemetryDiagnostics => kDebugMode;
  bool _isAnalyzing = false;
  bool _isRefreshingPremiumReplies = false;
  int? _enthusiasmScore;
  Map<String, int>? _dimensionScores;
  String? _strategy;
  Map<String, String>? _replies;
  Map<String, ReplyOption>? _replyOptions;
  TopicDepth? _topicDepth;
  HealthCheck? _healthCheck;
  String? _errorMessage;
  AnalysisErrorAction? _errorAction;
  _AnalysisErrorOrigin? _errorOrigin;
  String? _errorGuidance;

  // 對話階段分析
  GameStageInfo? _gameStage;

  // 心理分析
  PsychologyAnalysis? _psychology;

  // 最終建議
  FinalRecommendation? _finalRecommendation;

  // 可接球點教練卡
  CoachActionHint? _coachActionHint;

  // 一致性提醒
  String? _reminder;

  // 冰點放棄建議
  // ignore: prefer_final_fields
  bool _shouldGiveUp = false;

  // Analyze V2 一級決策（Phase 1c）；null＝v1 結果，走本地備援。
  AnalysisDecisionV2? _decision;

  // 反饋相關
  bool _feedbackSubmitted = false;
  bool _showFeedbackForm = false;
  bool _isSubmittingFeedback = false;
  bool _includeFeedbackContext = false;

  // 訊息優化功能（顯示狀態在 DraftPolishSheet；這裡只留草稿與計費路徑）
  bool _showDetailedAnalysis = false;
  final _optimizeController = TextEditingController();
  late final ReplyIterationCoordinator _replyIteration =
      ref.read(replyIterationCoordinatorFactoryProvider)();

  String? _feedbackCategory;
  final _feedbackCommentController = TextEditingController();

  // UI-facing progress and error mirrors from the single streaming notifier.
  // The notifier remains authoritative for the durable run and final result.
  String? _streamErrorMessage;
  int _streamErrorRetriesRemaining = 0;

  /// Quota 429 分流（smoke P1 fix 2026-06-11）：非 null 時 retry 卡換升級卡。
  /// 生命週期與 _streamErrorMessage 配對——所有清除/賦值點必須同步。
  QuotaExceededInfo? _quotaExceededInfo;
  String? _streamProgressLabel;
  String? _streamProgressDetail;
  List<AnalysisStreamContent> _streamContents = const [];
  int? _activeAnalysisMessageCount;
  bool _isLeavingAfterPersistence = false;
  // application coordinator 一律經 composition root 工廠組裝；畫面只
  // 提供 UI callback（重繪、provider 失效、48h 跟進軟卡）。
  late final AnalysisPersistenceCoordinator _persistence =
      ref.read(analysisPersistenceCoordinatorFactoryProvider)(
    conversationId: widget.conversationId,
    notifyStateChanged: () {
      if (mounted) setState(() {});
    },
    invalidateRecordViews: (conversation) {
      _invalidateAnalysisArchiveCount();
      _invalidatePartnerAnalysisRecords(conversation);
      if (mounted) setState(() {});
    },
    afterAnalysisPersisted: _maybeScheduleFollowUpNotification,
  );
  late final AnalysisSessionController _session =
      ref.read(analysisSessionControllerFactoryProvider)(
    conversationId: widget.conversationId,
    persistence: _persistence,
  );
  late final ScreenshotImportCoordinator _screenshotImport =
      ref.read(screenshotImportCoordinatorFactoryProvider)(
    conversationId: widget.conversationId,
  );
  String? _analysisArchiveCountScopeKey;
  int _analysisArchiveCount = 0;
  Map<String, dynamic>? _lastAiResponse; // 儲存最後的 AI 回應

  /// 批2：本輪分析結果的 outcome 關聯鍵。AnalysisResult 無穩定 id
  ///（已核實 analysis_models.dart:840 無 id 欄位、snapshot 只存 rawResponse），
  /// 每次 _applyAnalysisResult 自產；重開畫面 restore 會重生→複製另開一筆
  /// pending，為已拍板接受的邊際成本。
  String? _analysisRunKey;

  /// 潤飾稿獨立 runKey（_polishDraft 不走 _applyAnalysisResult 漏斗）。
  String? _polishRunKey;

  final _scrollController = ScrollController();
  final _analysisProgressEndKey = GlobalKey();
  final _replyZoneSectionKey = GlobalKey();
  // 進場時間軸的單一真相源在 ReplyZoneSection（區塊 320ms＋每卡 stagger
  // 50ms＝總長 570ms）；controller 與一次性播放時機由本 screen 持有。
  late final AnimationController _replyZoneEntrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: ReplyZoneSection.entranceTotalMs),
  );
  bool _replyZonePlayed = false;
  // 使用者手指是否正在拖動主捲軸。分析完成的一次性自動捲動只在使用者沒在
  // 拖動時執行，避免把他手上的捲動搶走。不進 setState：純行為旗標，不影響
  // 渲染。
  bool _userDragInProgress = false;
  bool _followLiveAnalysis = false;
  bool _analysisFollowScrollScheduled = false;

  // 首次看到對話 bubble 時提示用戶長按可編輯。
  OverlayEntry? _editMessageCoachMarkEntry;
  // 上次觸發 coach mark check 時的 messages.length。每次 messages 變多
  // （手動輸入新訊息 / 截圖再次加入）都重新 schedule callback，讓 dogfood
  // 反覆測試每個 action 都看得到提醒。production 由 hint 旗標 gate 成
  // first-run only。
  int _coachMarkLastSeenMessageCount = 0;

  // 截圖 root ScaffoldMessenger reference，避免 dispose 時 context lookup 失敗。
  // 用於 dispose 時清除可能殘留的 SnackBar，避免 OCR 加入提示跨頁殘留
  // （OCR 加入 SnackBar duration=7s，用戶離開頁面後 root
  // messenger 會繼續顯示在其他頁面上，Bruce 2026-05-21 dogfood 回報）。
  ScaffoldMessengerState? _scaffoldMessenger;

  // 截圖上傳功能
  List<Uint8List> _selectedImages = [];
  List<SelectedImageMetrics> _selectedImageMetrics = [];
  List<Uint8List> _lastRecognitionImages = [];
  List<SelectedImageMetrics> _lastRecognitionImageMetrics = [];
  RecognizedConversation? _recognizedConversation;
  String? _recognizedWarningMessage;
  bool _hasPendingRecognitionImport = false;
  bool _recognitionFromCache = false;
  bool _isRecognizing = false;
  AnalysisProgressStage _recognizeStage =
      AnalysisProgressStage.preparingPayload;
  AnalysisTelemetry? _lastRecognizeTelemetry;
  AnalysisTelemetry? _lastAnalysisTelemetry;
  MeetingContext _screenshotMeetingContext = MeetingContext.datingApp;
  AcquaintanceDuration _screenshotDuration = AcquaintanceDuration.justMet;
  UserGoal _screenshotGoal = UserGoal.dateInvite;
  final _screenshotAnalysisContextNoteController = TextEditingController();

  /// 重入防護（Codex 雙審 r1-P2b 2026-06-11）：quota 升級卡新增了高頻
  /// paywall 入口，快速連點不得 push 多個 paywall route。
  bool _isPaywallInFlight = false;

  Future<void> _showPaywall(BuildContext context) async {
    if (_isPaywallInFlight) return;
    _isPaywallInFlight = true;
    _clearAnalysisSnackBarsBeforePush();
    final String? unlockedTier;
    try {
      unlockedTier = await context.push<String>('/paywall');
    } finally {
      _isPaywallInFlight = false;
    }
    if (!mounted) {
      return;
    }

    if (unlockedTier != null && unlockedTier.isNotEmpty) {
      await ref.read(subscriptionProvider.notifier).forceSyncTier(unlockedTier);
    }

    await ref.read(subscriptionProvider.notifier).refresh();
    if (!mounted || unlockedTier == null || unlockedTier.isEmpty) {
      return;
    }

    final subscription = ref.read(subscriptionProvider);
    if (_analysisNeedsReplyRefresh(subscription)) {
      _showFloatingSnackBar('已升級完整分析，正在幫你刷新回覆選項。');
      await _refreshPremiumReplies();
    }
  }

  String _currentPlanLabel() {
    switch (ref.read(subscriptionProvider).tier) {
      case SubscriptionTierHelper.starter:
        return 'Starter';
      case SubscriptionTierHelper.essential:
        return 'Essential';
      case SubscriptionTierHelper.free:
      default:
        return 'Free';
    }
  }

  String _dailyQuotaExceededMessage(DailyLimitExceededException e) {
    return '目前方案 ${_currentPlanLabel()}：今日額度已用完 (${e.used}/${e.dailyLimit})，每天早上 8 點恢復；升級方案可取得更多額度。';
  }

  String _monthlyQuotaExceededMessage(MonthlyLimitExceededException e) {
    return '目前方案 ${_currentPlanLabel()}：本月額度已用完 (${e.used}/${e.monthlyLimit})，升級方案可取得更多分析額度。';
  }

  CoachChatAnalysisSnapshot _buildCoachChatAnalysisSnapshot() {
    final subscription = ref.read(subscriptionProvider);
    final keySignals = <String>[
      if (_psychology?.subtext.trim().isNotEmpty == true)
        _psychology!.subtext.trim(),
      if (_topicDepth?.suggestion.trim().isNotEmpty == true)
        _topicDepth!.suggestion.trim(),
      if (subscription.isEssential && _healthCheck?.issues.isNotEmpty == true)
        ..._healthCheck!.issues.take(2),
    ];

    return CoachChatAnalysisSnapshot(
      heatScore: _enthusiasmScore,
      stage: _gameStage?.current.name,
      summary: _strategy,
      nextStep: _gameStage?.nextStep,
      coachActionType: _finalRecommendation?.pick,
      keySignals: keySignals.take(8).toList(growable: false),
    );
  }

  Future<void> _refreshPremiumReplies() async {
    if (_isAnalyzing || _isRefreshingPremiumReplies) {
      return;
    }

    setState(() {
      _isRefreshingPremiumReplies = true;
      _resetErrorState();
    });

    try {
      await ref
          .read(subscriptionProvider.notifier)
          .refresh()
          .timeout(_subscriptionSyncTimeout);
      if (!mounted) {
        return;
      }

      final refreshedSubscription = ref.read(subscriptionProvider);
      if (!refreshedSubscription.isPremium) {
        await ref
            .read(subscriptionProvider.notifier)
            .syncWithRevenueCat()
            .timeout(_subscriptionSyncTimeout);
        await ref
            .read(subscriptionProvider.notifier)
            .refresh()
            .timeout(_subscriptionSyncTimeout);
        if (!mounted) {
          return;
        }
      }

      final conversation =
          ref.read(conversationProvider(widget.conversationId));
      final refreshThrough = conversation == null
          ? null
          : _effectiveLastAnalyzedMessageCount(conversation)
              .clamp(
                0,
                conversation.messages.length,
              )
              .toInt();
      await _runAnalysis(
        skipPreview: true,
        waitForCompletion: true,
        analysisMessageLimit: refreshThrough,
        allowPendingOutgoingRefresh: true,
      );
      if (!mounted) {
        return;
      }

      final subscription = ref.read(subscriptionProvider);
      if (_analysisNeedsReplyRefresh(subscription)) {
        _showFloatingSnackBar('完整分析還在同步中，請稍後再試一次。');
      } else {
        _showFloatingSnackBar('完整分析已更新。');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFloatingSnackBar('完整分析刷新失敗，請稍後再試。');
      debugPrint('Premium reply refresh error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingPremiumReplies = false;
        });
      }
    }
  }

  String? _analysisTierUsed() {
    final usage = _lastAiResponse?['usage'];
    if (usage is Map) {
      final tierUsed = usage['tierUsed'];
      if (tierUsed is String && tierUsed.trim().isNotEmpty) {
        return tierUsed.trim();
      }
    }
    return null;
  }

  bool _analysisNeedsReplyRefresh(SubscriptionState subscription) {
    const freeReplyStyles = {'extend', 'tease'};
    if (!subscription.isPremium ||
        _replies == null ||
        _replies!.isEmpty ||
        !_replies!.containsKey('extend') ||
        !_replies!.keys.every(freeReplyStyles.contains)) {
      return false;
    }

    final tierUsed = _analysisTierUsed();
    if (tierUsed == null) {
      return false;
    }

    return tierUsed == SubscriptionTierHelper.free;
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  void _resetErrorState() {
    _errorMessage = null;
    _errorAction = null;
    _errorOrigin = null;
    _errorGuidance = null;
  }

  void _applyErrorState({
    required String message,
    AnalysisErrorAction? action,
    _AnalysisErrorOrigin? origin,
    String? guidance,
  }) {
    _errorMessage = message;
    _errorAction = action;
    _errorOrigin = origin;
    _errorGuidance = guidance ?? _defaultErrorGuidance(action);
  }

  String? _defaultErrorGuidance(AnalysisErrorAction? action) {
    switch (action) {
      case AnalysisErrorAction.retry:
        return _errorOrigin == _AnalysisErrorOrigin.recognition
            ? '先確認網路穩定；如果同一批截圖持續失敗，建議改成分段截圖後再試。'
            : '保留目前對話內容即可，我會重新送出這次分析。';
      case AnalysisErrorAction.relogin:
        return '登入狀態可能已過期，重新登入後即可恢復分析與訂閱資料。';
      case AnalysisErrorAction.rescreenshot:
        return '保留標題列、左右對話氣泡與外層主訊息；長對話可拆成 2–3 張同批選取。';
      case AnalysisErrorAction.shortenInput:
        return _selectedImages.isNotEmpty
            ? '每張截圖建議少於 15 則訊息；若內容太長，請拆成 2–3 張同批選取。'
            : '請重新選擇較短、真正需要 AI 解析的聊天片段。';
      case AnalysisErrorAction.upgrade:
        return '升級後可解鎖更完整的分析能力與較高額度。';
      case AnalysisErrorAction.wait:
        return '今日額度用完後會在隔天重置，或升級方案取得更多額度。';
      case AnalysisErrorAction.addIncomingMessage:
        return _selectedImages.isNotEmpty
            ? '先把截圖辨識成文字並確認為本次片段；若沒有她的訊息，請重新選擇包含她回覆的截圖。'
            : '一般分析至少需要一則對方訊息；請重新選擇包含她回覆的聊天截圖。';
      case null:
        return null;
    }
  }

  String _primaryErrorActionLabel(AnalysisErrorAction action) {
    switch (action) {
      case AnalysisErrorAction.retry:
        return _errorOrigin == _AnalysisErrorOrigin.recognition
            ? '重新辨識'
            : '重新分析';
      case AnalysisErrorAction.relogin:
        return '重新登入';
      case AnalysisErrorAction.rescreenshot:
        return _selectedImages.isNotEmpty ? '調整截圖' : '上傳截圖';
      case AnalysisErrorAction.shortenInput:
        return '調整內容';
      case AnalysisErrorAction.upgrade:
        return '查看方案';
      case AnalysisErrorAction.wait:
        return '稍後再試';
      case AnalysisErrorAction.addIncomingMessage:
        if (_selectedImages.isNotEmpty) {
          return '先辨識截圖';
        }
        return _hasCompletedCurrentFragment ? '分析新片段' : '重新選擇截圖';
    }
  }

  String _secondaryErrorActionLabel() {
    if (_errorAction == null || _errorAction == AnalysisErrorAction.wait) {
      return '知道了';
    }
    return '稍後處理';
  }

  bool _shouldShowSecondaryErrorAction() {
    if (_errorAction == null) {
      return true;
    }
    return _errorAction != AnalysisErrorAction.wait;
  }

  Future<void> _scrollToBottom({Duration delay = Duration.zero}) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: AppMotion.scroll,
      curve: AppMotion.easeOut,
    );
  }

  Future<void> _jumpToCurrentAnalysis() async {
    if (!mounted) return;
    final shouldFollow = _isAnalyzing;
    if (_followLiveAnalysis != shouldFollow) {
      setState(() {
        _followLiveAnalysis = shouldFollow;
      });
    }
    await _scrollToCurrentAnalysisEnd();
  }

  Future<void> _scrollToCurrentAnalysisEnd() async {
    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: AppMotion.scroll,
      curve: AppMotion.easeOut,
    );
  }

  void _scheduleFollowCurrentAnalysis() {
    if (!_isAnalyzing ||
        !_followLiveAnalysis ||
        _analysisFollowScrollScheduled) {
      return;
    }
    _analysisFollowScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analysisFollowScrollScheduled = false;
      if (!mounted || !_isAnalyzing || !_followLiveAnalysis) return;
      unawaited(_scrollToCurrentAnalysisEnd());
    });
  }

  void _stopFollowingForUserScroll() {
    if (!mounted || !_isAnalyzing || !_followLiveAnalysis) return;
    setState(() {
      _followLiveAnalysis = false;
    });
  }

  /// 分析完成後的一次性自動捲動：把「回覆建議」區頂帶到視口上緣附近。
  ///
  /// 錨的是回覆區、不是上方的「下一步」卡（2026-08-09 拍板）：完成當下使用者
  /// 要的是可以直接抄的回覆。只掛在 live 完成轉場
  /// （[_onStreamingAnalyzeStateChanged] 的 done case）；回頁 hydrate 不捲，
  /// 免得使用者一回來就被跳位。使用者手指還在拖動時跳過。
  void _scheduleSnapToReplyZone() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userDragInProgress) return;
      final replyZoneContext = _replyZoneSectionKey.currentContext;
      if (replyZoneContext == null || !replyZoneContext.mounted) return;
      unawaited(Scrollable.ensureVisible(
        replyZoneContext,
        duration: AppMotion.scroll,
        curve: AppMotion.easeOut,
        alignment: 0.04,
      ));
    });
  }

  bool get _hasCompletedCurrentFragment {
    final conversation = ref.read(
      conversationProvider(widget.conversationId),
    );
    return _enthusiasmScore != null ||
        (conversation != null &&
            AnalysisFragmentPolicy.hasCompletedAnalysis(conversation));
  }

  Future<void> _openReplacementInput() async {
    if (!mounted) {
      return;
    }
    if (_hasCompletedCurrentFragment) {
      await _openNewConversationSheet();
      return;
    }
    _dismissKeyboard();
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: AppMotion.scroll,
      curve: AppMotion.easeOut,
    );
  }

  /// 問教練＝直達 Sydney 視窗（conversation scope），分析快照 extra 隨行。
  /// 額度與 consent gate 全在視窗內。
  void _openCoachQuestion() {
    if (!mounted) return;
    _dismissKeyboard();
    context.push(
      '/coach?conversationId=${widget.conversationId}',
      extra: _buildCoachChatAnalysisSnapshot(),
    );
  }

  Future<void> _openNewConversationSheet() async {
    if (!mounted) {
      return;
    }
    _dismissKeyboard();
    final conversation = ref.read(conversationProvider(widget.conversationId));
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewConversationSheet(partnerId: conversation?.partnerId),
    );
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  Future<void> _handleErrorAction(AnalysisErrorAction action) async {
    switch (action) {
      case AnalysisErrorAction.retry:
        setState(_resetErrorState);
        if (_errorOrigin == _AnalysisErrorOrigin.recognition) {
          await _recognizeAndAddToConversation();
        } else {
          await _runAnalysis();
        }
        return;
      case AnalysisErrorAction.relogin:
        setState(_resetErrorState);
        try {
          await SupabaseService.signOut();
        } catch (error) {
          // Privacy purge is fail-closed. If the auth session still exists,
          // do not present a logged-out UI while keyboard data may remain.
          if (error is KeyboardPrivacyPurgeException ||
              SupabaseService.isAuthenticated) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('登出前無法清除鍵盤隱私資料，請再試一次。'),
                ),
              );
            }
            return;
          }
        }
        if (!mounted) {
          return;
        }
        context.go('/login');
        return;
      case AnalysisErrorAction.rescreenshot:
        setState(_resetErrorState);
        await _openReplacementInput();
        return;
      case AnalysisErrorAction.shortenInput:
        setState(_resetErrorState);
        await _openReplacementInput();
        return;
      case AnalysisErrorAction.upgrade:
        setState(_resetErrorState);
        await _showPaywall(context);
        return;
      case AnalysisErrorAction.wait:
        setState(_resetErrorState);
        return;
      case AnalysisErrorAction.addIncomingMessage:
        setState(_resetErrorState);
        if (_selectedImages.isNotEmpty && !_isRecognizing) {
          await _recognizeAndAddToConversation();
          return;
        }
        await _openReplacementInput();
        return;
    }
  }

  // 記錄已分析的訊息數量，用於判斷是否需要重新分析
  int _lastAnalyzedMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrateScreenshotAnalysisSettings();
    final initialState =
        ref.read(streamingAnalyzeProvider(widget.conversationId));
    _restorePersistedAnalysis(
      repairRecord: initialState.phase != StreamingAnalyzePhase.done,
    );
    // If the provider is already mid-analyze on remount, the snapshot we just
    // restored is from a *previous* completed run. Clear the detailed mirrors
    // synchronously so the first frame does not flash the old detailed
    // analysis on top of the new run's streaming loader / retry state.
    // (I-P1-c, Codex round-2).
    if (_isStreamingAnalyzePartialPhase(initialState.phase) ||
        _session.isResultStaleForCurrentConversation(
            initialState.toRunMetadata())) {
      _clearDetailedAnalysisStateForStreamingAnalyzePartial();
    }
    // Hydrate from existing streaming analyze notifier state on remount.
    // ref.listen (set up in build) only fires on future transitions, so a
    // screen rebuilt while the provider is mid-analyze would otherwise lose
    // the current streaming/full state. Post-frame so ref reads are safe and
    // setState lands on the next frame (I-P1-a).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(streamingAnalyzeProvider(widget.conversationId));
      if (current.phase != StreamingAnalyzePhase.idle) {
        _hydrateStreamingAnalyzeState(current);
      }
    });
    // 不再自動分析，讓用戶手動點擊
  }

  void _hydrateScreenshotAnalysisSettings() {
    final conversation = ref
        .read(conversationRepositoryProvider)
        .getConversation(widget.conversationId);
    final partnerId = conversation?.partnerId?.trim();
    final partner = (() {
      if (partnerId == null || partnerId.isEmpty) return null;
      try {
        return ref.read(partnerRepositoryProvider).getById(partnerId);
      } catch (error) {
        // Context defaults are a convenience, not a screen-startup gate. If
        // local partner storage is temporarily unavailable, keep the product
        // defaults and let the normal repository path surface its own issue.
        debugPrint(
            'Partner defaults unavailable for screenshot analysis: $error');
        return null;
      }
    })();
    final defaults = ScreenshotSessionContextDefaults.resolve(
      conversation: conversation,
      partner: partner,
    );

    _screenshotMeetingContext = defaults.meetingContext;
    _screenshotDuration = defaults.duration;
    _screenshotGoal = defaults.goal;
    _screenshotAnalysisContextNoteController.text =
        defaults.analysisContextNote ?? '';
  }

  bool _isStreamingAnalyzePartialPhase(StreamingAnalyzePhase p) {
    switch (p) {
      case StreamingAnalyzePhase.connecting:
      case StreamingAnalyzePhase.streamingReport:
      case StreamingAnalyzePhase.failedAfterRecommendation:
      case StreamingAnalyzePhase.failedBeforeRecommendation:
        return true;
      case StreamingAnalyzePhase.done:
      case StreamingAnalyzePhase.idle:
        return false;
    }
  }

  /// Apply the current streaming analyze notifier state to local mirrors without
  /// triggering side-effects (paywall, persistence, subscription sync) that
  /// the original transition already handled. Called on screen remount so a
  /// user who navigates away mid-analyze sees the correct state when they
  /// come back.
  void _hydrateStreamingAnalyzeState(StreamingAnalysisState s) {
    if (!mounted) return;
    switch (s.phase) {
      case StreamingAnalyzePhase.connecting:
        setState(() {
          _isAnalyzing = true;
          _streamErrorMessage = null;
          _streamErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = s.streamProgressLabel;
          _streamProgressDetail = s.streamProgressDetail;
          _streamContents = s.streamContents;
          _activeAnalysisMessageCount =
              s.analyzedMessageCount ?? s.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.streamingReport:
        setState(() {
          _isAnalyzing = true;
          _streamErrorMessage = null;
          _streamErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = s.streamProgressLabel;
          _streamProgressDetail = s.streamProgressDetail;
          _streamContents = s.streamContents;
          _activeAnalysisMessageCount =
              s.analyzedMessageCount ?? s.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.done:
        final result = s.result;
        if (result == null) return;
        if (_session.isResultStaleForCurrentConversation(s.toRunMetadata())) {
          setState(() {
            _isAnalyzing = false;
            _streamErrorMessage = '你剛剛更新了本次片段，這份完整分析先不套用。請重新按「開始分析」。';
            _streamErrorRetriesRemaining = 0;
            _quotaExceededInfo = null;
            _streamContents = const [];
            _activeAnalysisMessageCount =
                s.analyzedMessageCount ?? s.conversationMessageCount;
            _clearDetailedAnalysisStateForStreamingAnalyzePartial();
          });
          return;
        }
        setState(() {
          _isAnalyzing = false;
          _streamErrorMessage = null;
          _streamErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = const [];
          _activeAnalysisMessageCount = null;
          _applyAnalysisResult(result);
          _enthusiasmScore = result.enthusiasmScore;
          _dimensionScores = result.dimensionScores;
          _strategy = result.strategy;
          _replies = result.replies;
          _replyOptions = result.replyOptions;
          _topicDepth = result.topicDepth;
          _healthCheck = result.healthCheck;
          // 閉環驗收 7：本次無有效 stage（缺值／未知值）不得渲染成破冰。
          _gameStage = result.gameStage.hasValidStage ? result.gameStage : null;
          _psychology = result.psychology;
          _finalRecommendation = result.recommendation;
          _coachActionHint = result.coachActionHint;
          _reminder = result.reminder;
          _shouldGiveUp = result.shouldGiveUp;
          _decision = result.decision;
          _lastAiResponse = result.rawResponse;
        });
        // Idempotent: only persist + sync usage when the live listener clearly
        // did NOT run for this result (e.g., user navigated away during
        // streamingReport and the done transition arrived off-screen). If the
        // listener already wrote this exact snapshot, the dedup signal below
        // short-circuits to avoid double-writes (I-P2-e/f, Codex round-2).
        _maybePersistAndSyncOnHydrate(s, result);
        break;
      case StreamingAnalyzePhase.failedAfterRecommendation:
        // 額度用盡才震（一般格式失敗不是付費牆時刻，不給錯誤觸覺）。
        if (s.quotaExceeded != null) AppHaptics.failure();
        setState(() {
          _isAnalyzing = false;
          _streamErrorMessage = s.streamErrorMessage;
          _streamErrorRetriesRemaining = s.retriesRemaining;
          _quotaExceededInfo = s.quotaExceeded;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = s.streamContents;
          _activeAnalysisMessageCount =
              s.analyzedMessageCount ?? s.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.failedBeforeRecommendation:
        final hydrateQuotaInfo = s.quotaExceeded;
        final isQuotaError =
            s.recommendationPreviewErrorCode == 'DAILY_LIMIT_EXCEEDED' ||
                s.recommendationPreviewErrorCode == 'MONTHLY_LIMIT_EXCEEDED';
        setState(() {
          _isAnalyzing = false;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = const [];
          _activeAnalysisMessageCount = null;
          if (hydrateQuotaInfo != null) {
            // Quota 429 升級卡分流（Codex 雙審 r1-P2a）：fresh-start 也渲染
            // QuotaExceededUpgradeCard（剩 N/需 M），不走 generic error 卡。
            _quotaExceededInfo = hydrateQuotaInfo;
            _resetErrorState();
          } else {
            _applyErrorState(
              message: s.recommendationPreviewErrorMessage ?? '分析暫時失敗，請稍後再試。',
              action: isQuotaError
                  ? AnalysisErrorAction.upgrade
                  : AnalysisErrorAction.retry,
              origin: _AnalysisErrorOrigin.analysis,
            );
          }
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        // Skip _showPaywall — already opened on the original transition.
        break;
      case StreamingAnalyzePhase.idle:
        break;
    }
  }

  /// Persist + sync usage from a hydrate-time done result IF the live
  /// `_onStreamingAnalyzeStateChanged` listener clearly did not already do so. Dedup
  /// signal: analyzed count, full input revision, analyzed-prefix revision,
  /// and stored analysis payload all match. A match means the listener path
  /// already wrote this exact snapshot (I-P2-e/f).
  ///
  /// Required for the off-screen completion path: user starts analyze, leaves
  /// the screen mid-`streamingReport`, the notifier transitions to `done`
  /// while the listener is unmounted; on return the screen sees `done`
  /// but the snapshot + usage were never written.
  void _maybePersistAndSyncOnHydrate(
    StreamingAnalysisState s,
    AnalysisResult result,
  ) {
    final repository = ref.read(conversationRepositoryProvider);
    final conv = repository.getConversation(widget.conversationId);
    if (conv == null) return;
    final expectedAnalyzedCount =
        s.analyzedMessageCount ?? conv.messages.length;

    final persisted = _session.persistHydratedResultIfNeeded(
      s.toRunMetadata(),
      result,
      expectedAnalyzedCount: expectedAnalyzedCount,
      conversation: conv,
    );
    if (!persisted) return;

    if (mounted) {
      setState(() {
        _lastAnalyzedMessageCount = expectedAnalyzedCount;
      });
    }
    _syncSubscriptionUsageFromResult(result);
  }

  /// Wipe the local mirrors of a *previous* completed analysis so the render
  /// tree shows only the live streaming state during a fresh run.
  /// `_restorePersistedAnalysis()` seeds these from `lastAnalysisSnapshotJson`
  /// in initState; without clearing on hydrate of a partial phase the build
  /// tree would keep showing the stale detailed analysis (I-P1-c, Codex
  /// round-2). Must be called inside the caller's `setState`.
  void _clearDetailedAnalysisStateForStreamingAnalyzePartial() {
    _enthusiasmScore = null;
    _dimensionScores = null;
    _strategy = null;
    _replies = null;
    _replyOptions = null;
    _topicDepth = null;
    _healthCheck = null;
    _gameStage = null;
    _psychology = null;
    _finalRecommendation = null;
    _coachActionHint = null;
    _reminder = null;
    _shouldGiveUp = false;
    _decision = null;
    _lastAiResponse = null;
    _showDetailedAnalysis = false;
    _resetFeedbackState();
  }

  /// 已是伴侶（認識情境）判定：opening 的可見語意要換成「重新連線」。
  bool _isCommittedPartner(Conversation? conversation) =>
      conversation?.sessionContext?.meetingContext ==
      MeetingContext.committedPartner;

  String? _visibleGameStageLabel(Conversation? conversation) {
    final stage = _gameStage?.current;
    if (stage == null) return null;
    if (_isCommittedPartner(conversation) && stage == GameStage.opening) {
      return '重新連線';
    }
    return stage.label;
  }

  /// data 層 wire 型別 → section view model 的映射（icon 對映留在
  /// composition root，section 維持 data-neutral）。
  List<StreamingContentItem> get _streamContentItems => _streamContents
      .map(
        (content) => StreamingContentItem(
          icon: _streamContentIcon(content.kind),
          title: content.title,
          body: content.body,
        ),
      )
      .toList(growable: false);

  IconData _streamContentIcon(AnalysisStreamContentKind kind) {
    switch (kind) {
      case AnalysisStreamContentKind.decision:
        return Icons.route_outlined;
      case AnalysisStreamContentKind.replyOption:
        return Icons.chat_bubble_outline;
      case AnalysisStreamContentKind.metrics:
        return Icons.query_stats;
      case AnalysisStreamContentKind.coachHint:
        return Icons.tips_and_updates_outlined;
      case AnalysisStreamContentKind.reportSection:
        return Icons.subject;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  }

  int _effectiveLastAnalyzedMessageCount(Conversation conversation) {
    if (_lastAnalyzedMessageCount > 0) {
      return _lastAnalyzedMessageCount;
    }
    if (conversation.lastAnalyzedMessageCount != null) {
      return conversation.lastAnalyzedMessageCount!;
    }
    final hasVisibleAnalysis = _enthusiasmScore != null ||
        conversation.lastAnalysisSnapshotJson?.trim().isNotEmpty == true;
    return hasVisibleAnalysis ? conversation.messages.length : 0;
  }

  int _pendingAnalysisBaselineMessageCount(Conversation conversation) {
    final completed = _effectiveLastAnalyzedMessageCount(conversation);
    final active = _activeAnalysisMessageCount;
    if (active != null && active > completed) {
      return active;
    }
    return completed;
  }

  List<Message> _pendingMessages(Conversation conversation) {
    final baseline = _pendingAnalysisBaselineMessageCount(conversation);
    if (baseline >= conversation.messages.length) {
      return const <Message>[];
    }
    return conversation.messages.sublist(baseline);
  }

  bool _pendingMessagesAreOutgoingOnly(Conversation conversation) {
    final pendingMessages = _pendingMessages(conversation);
    return pendingMessages.isNotEmpty &&
        pendingMessages.every((message) => message.isFromMe);
  }

  List<Message> _analysisFragmentMessages(Conversation conversation) {
    if (conversation.messages.isEmpty) return const <Message>[];

    final completed = _effectiveLastAnalyzedMessageCount(conversation)
        .clamp(0, conversation.messages.length)
        .toInt();
    final active = _activeAnalysisMessageCount;
    if (!AnalysisFragmentPolicy.hasCompletedAnalysis(conversation)) {
      if (active != null &&
          active > completed &&
          active <= conversation.messages.length) {
        // A draft can change while the stream is running. Keep the active
        // batch visible; the stale-result guard prevents an older result from
        // being persisted over it.
        return conversation.messages.sublist(completed);
      }

      if (conversation.messages.length > completed) {
        return conversation.messages.sublist(completed);
      }
    }

    final current = _persistence.currentRecordFor(conversation);
    final streamingState =
        ref.read(streamingAnalyzeProvider(widget.conversationId));
    final streamTarget = streamingState.analyzedMessageCount;
    final streamCompletionKey = streamingState.analysisRunId?.trim();
    if (streamingState.phase == StreamingAnalyzePhase.done &&
        streamTarget != null &&
        streamTarget > 0 &&
        streamTarget <= conversation.messages.length &&
        (current == null ||
            streamCompletionKey == null ||
            current.completionKey != streamCompletionKey)) {
      final previous = streamingState.previousAnalyzedCount ?? 0;
      final start = current != null && streamTarget <= previous
          ? current.segmentStart
          : previous;
      if (start >= 0 && start < streamTarget) {
        return conversation.messages.sublist(start, streamTarget);
      }
    }

    if (current != null &&
        current.segmentEnd >= 0 &&
        current.segmentEnd < completed) {
      // Canonical snapshot persistence may win while the independent record
      // write is still retrying. On a cold idle restore, show the canonical
      // newer fragment (the exact range repair will create), not the stale
      // current record beside newer analysis cards.
      return conversation.messages.sublist(current.segmentEnd, completed);
    }

    if (current != null &&
        current.segmentStart >= 0 &&
        current.segmentStart < current.segmentEnd &&
        current.segmentEnd <= conversation.messages.length) {
      // Use the live message instances for the current screen. Completed
      // messages are read-only; the archived record remains an immutable copy.
      return conversation.messages.sublist(
        current.segmentStart,
        current.segmentEnd,
      );
    }

    final legacyEnd = conversation.lastAnalyzedMessageCount;
    if (legacyEnd != null &&
        legacyEnd > 0 &&
        legacyEnd <= conversation.messages.length) {
      return conversation.messages.sublist(0, legacyEnd);
    }
    return conversation.messages;
  }

  bool _isShowingPendingAnalysisFragment(Conversation conversation) {
    if (AnalysisFragmentPolicy.hasCompletedAnalysis(conversation)) {
      return false;
    }
    final completed = _effectiveLastAnalyzedMessageCount(conversation)
        .clamp(0, conversation.messages.length)
        .toInt();
    final active = _activeAnalysisMessageCount;
    return (active != null && active > completed) ||
        conversation.messages.length > completed;
  }

  String? _conversationAnalysisSource(Conversation conversation) {
    final ownerUserId = _persistence.recordOwnerFor(conversation);
    if (ownerUserId == null) return null;
    return ref.read(analysisRecordStoreProvider).conversationSource(
          ownerUserId: ownerUserId,
          conversationId: conversation.id,
        );
  }

  Future<void> _chooseConversationAnalysisSource(
    Conversation conversation,
  ) async {
    final ownerUserId = _persistence.recordOwnerFor(conversation);
    if (ownerUserId == null) return;
    final result = await showAnalysisPlatformPicker(
      context,
      currentValue: _conversationAnalysisSource(conversation),
      title: '這段聊天來自哪裡？',
    );
    if (!mounted || result == null) return;
    if (_persistence.inFlightCount != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分析紀錄正在保存，完成後再設定聊天來源')),
      );
      return;
    }
    final relabelCurrent = !_persistence.recordNeedsRepair &&
        _persistence.inFlightCount == 0 &&
        !_isShowingPendingAnalysisFragment(conversation) &&
        _persistence.currentRecordFor(conversation) != null;
    try {
      final saved =
          await ref.read(analysisRecordStoreProvider).setConversationSource(
                ownerUserId: ownerUserId,
                conversationId: conversation.id,
                sourcePlatform: result.platform,
                relabelCurrent: relabelCurrent,
              );
      if (!saved) throw StateError('source write rejected');
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Analysis source save failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('聊天來源儲存失敗，請再試一次')),
      );
    }
  }

  List<Conversation> _analysisArchiveConversations(
    Conversation conversation,
  ) {
    final partnerId = conversation.partnerId?.trim();
    return partnerId == null || partnerId.isEmpty
        ? <Conversation>[conversation]
        : ref.read(conversationsByPartnerProvider(partnerId));
  }

  List<AnalysisRecord> _archivedAnalysisRecordsFor(
    Conversation conversation,
  ) {
    final ownerUserId = _persistence.recordOwnerFor(conversation);
    if (ownerUserId == null) return const [];
    return AnalysisArchiveLifecycle.recordsFor(
      store: ref.read(analysisRecordStoreProvider),
      ownerUserId: ownerUserId,
      conversations: _analysisArchiveConversations(conversation),
    );
  }

  int _archivedAnalysisRecordCountFor(Conversation conversation) {
    final ownerUserId = _persistence.recordOwnerFor(conversation);
    if (ownerUserId == null) {
      _analysisArchiveCountScopeKey = null;
      _analysisArchiveCount = 0;
      return 0;
    }
    final conversationIds = _analysisArchiveConversations(conversation)
        .map((item) => item.id)
        .toList(growable: false);
    final scopeKey = '$ownerUserId|${conversationIds.join(',')}';
    if (_analysisArchiveCountScopeKey != scopeKey) {
      _analysisArchiveCountScopeKey = scopeKey;
      _analysisArchiveCount = AnalysisArchiveLifecycle.recordsFor(
        store: ref.read(analysisRecordStoreProvider),
        ownerUserId: ownerUserId,
        conversations: _analysisArchiveConversations(conversation),
      ).length;
    }
    return _analysisArchiveCount;
  }

  void _invalidateAnalysisArchiveCount() {
    _analysisArchiveCountScopeKey = null;
  }

  void _invalidatePartnerAnalysisRecords(Conversation conversation) {
    if (!mounted) return;
    final partnerId = conversation.partnerId?.trim();
    if (partnerId == null || partnerId.isEmpty) return;
    ref.invalidate(partnerAnalysisRecordsProvider(partnerId));
  }

  Future<void> _openPartnerAnalysisRecords(
    Conversation conversation,
  ) async {
    await _persistence.awaitSettled();
    if (!mounted) return;
    conversation = ref
            .read(conversationRepositoryProvider)
            .getConversation(conversation.id) ??
        conversation;
    final ownerUserId = _persistence.recordOwnerFor(conversation);
    if (ownerUserId == null) return;
    final partnerId = conversation.partnerId?.trim();
    final conversations = _analysisArchiveConversations(conversation);
    final store = ref.read(analysisRecordStoreProvider);
    final promoted =
        await AnalysisArchiveLifecycle.promoteCompletedCurrentRecords(
      store: store,
      ownerUserId: ownerUserId,
      conversations: conversations,
    );
    if (!promoted || !mounted) {
      if (mounted) _showFloatingSnackBar('分析紀錄整理失敗，請再試一次。');
      return;
    }
    final records = _archivedAnalysisRecordsFor(conversation);
    final partner = partnerId == null || partnerId.isEmpty
        ? null
        : ref.read(partnerRepositoryProvider).getById(partnerId);
    final metVia = partnerId == null || partnerId.isEmpty
        ? null
        : store.partnerMetVia(
            ownerUserId: ownerUserId,
            partnerId: partnerId,
          );
    final archiveStore = ref.read(conversationArchiveStoreProvider);
    final latestAnalysisAtFor = createLazyLatestAnalyzeAtLookup(
      () => ref.read(analysisHistoryRepositoryProvider),
    );
    final archivedConversationCount = partnerId == null || partnerId.isEmpty
        ? 0
        : partitionConversationsByArchive(
            conversations,
            entryFor: archiveStore.entryFor,
            latestAnalysisAtFor: latestAnalysisAtFor,
          )
            .archived
            .where(
              (item) => !AnalysisArchiveLifecycle.hasStandaloneFragmentRecord(
                conversation: item.conversation,
                records: records,
              ),
            )
            .length;
    var deletedCurrentConversation = false;

    final action = await showPartnerAnalysisRecordsSheet(
      context,
      subjectName: partner?.name ?? conversation.name,
      records: records,
      metVia: metVia,
      platformForRecord: (record) => record.sourcePlatform,
      archivedConversationCount: archivedConversationCount,
      onSetMetVia: partnerId == null || partnerId.isEmpty
          ? null
          : (platform) async {
              final saved = await store.setPartnerMetVia(
                ownerUserId: ownerUserId,
                partnerId: partnerId,
                sourcePlatform: platform,
              );
              if (!saved) throw StateError('met-via write rejected');
            },
      onDelete: (record) async {
        Conversation? recordConversation;
        for (final candidate in conversations) {
          if (candidate.id == record.conversationId) {
            recordConversation = candidate;
            break;
          }
        }
        if (recordConversation != null &&
            AnalysisArchiveLifecycle.isStandaloneFragmentRecord(
              record: record,
              conversation: recordConversation,
              records: records,
            )) {
          await ref
              .read(conversationWriteControllerProvider.notifier)
              .delete(recordConversation);
          deletedCurrentConversation =
              recordConversation.id == widget.conversationId;
          return;
        }

        final deleted = await store.deleteRecord(
          ownerUserId: ownerUserId,
          conversationId: record.conversationId,
          recordId: record.id,
        );
        if (!deleted) throw StateError('record delete rejected');
      },
    );

    if (!mounted) return;
    _invalidateAnalysisArchiveCount();
    if (deletedCurrentConversation) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
      return;
    }
    if (action == PartnerAnalysisRecordsSheetAction.openArchivedConversations &&
        partnerId != null &&
        partnerId.isNotEmpty) {
      await context.push('/partner/$partnerId/analysis-archive');
    }
    if (mounted) setState(() {});
  }

  void _showEditedAnalyzedMessageSnackBar() {
    if (!mounted) return;

    final messenger = _scaffoldMessenger ?? ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      buildBrandFeedbackSnackBar(
        title: '已儲存，點重新分析更新結果。',
        icon: Icons.edit_note_rounded,
        duration: const Duration(seconds: 8),
        actionLabel: '重新分析',
        onAction: () {
          messenger.hideCurrentSnackBar();
          if (_isAnalyzing) return;
          unawaited(_runAnalysis());
        },
      ),
    );
  }

  void _applyAnalysisResult(
    AnalysisResult result, {
    bool resetFeedbackState = true,
  }) {
    _analysisRunKey = const Uuid().v4();
    _enthusiasmScore = result.enthusiasmScore;
    _dimensionScores = result.dimensionScores;
    _strategy = result.strategy;
    _replies = result.replies;
    _replyOptions = result.replyOptions;
    _topicDepth = result.topicDepth;
    _healthCheck = result.healthCheck;
    // 閉環驗收 7：本次無有效 stage（缺值／未知值）不得渲染成破冰。
    _gameStage = result.gameStage.hasValidStage ? result.gameStage : null;
    _psychology = result.psychology;
    _finalRecommendation = result.recommendation;
    _coachActionHint = result.coachActionHint;
    _reminder = result.reminder;
    _shouldGiveUp = result.shouldGiveUp;
    _decision = result.decision;
    _lastAiResponse = result.rawResponse;
    _showDetailedAnalysis = false;

    if (resetFeedbackState) {
      _resetFeedbackState();
    }
  }

  /// 綁 partner 的分析完成後：首次（opt-in=unknown）顯示軟詢問卡，
  /// 再委派 service 依 opt-in 決定要不要排 48h 跟進通知。
  Future<void> _maybeScheduleFollowUpNotification(Conversation conv) async {
    final partnerId = conv.partnerId;
    if (partnerId == null || partnerId.isEmpty) return;
    try {
      final service = ref.read(followUpNotificationServiceProvider);
      final displayName = _partnerDisplayName(partnerId);

      // 首次綁 partner 分析完成才問一次軟卡（之後 opt-in 非 unknown 不再問）。
      if (shouldShowSoftCard(service.optIn)) {
        if (!mounted) return;
        final accepted = await showSoftOptInCard(
          context,
          displayName: displayName,
        );
        if (accepted == true) {
          await service.requestSoftOptIn();
        } else {
          await service.declineSoftOptIn();
        }
      }

      // opt-in=granted 才真的排；否則 service 內部（buildFollowUpPlan）回 null 略過。
      await service.onPartnerAnalysisSaved(
        partnerId: partnerId,
        displayName: displayName,
      );
    } catch (e) {
      debugPrint('FollowUp schedule after analysis failed: $e');
    }
  }

  /// 由 partnerId 查 partner 顯示名，取不到回空字串（domain 文案層 fallback 用）。
  String _partnerDisplayName(String partnerId) {
    final partner = ref.read(partnerRepositoryProvider).getById(partnerId);
    return partner?.name ?? '';
  }

  /// 冷啟動還原：委派 coordinator，成功時套用畫面本地鏡像。
  void _restorePersistedAnalysis({bool repairRecord = true}) {
    final outcome = _persistence.restore(repairRecord: repairRecord);
    if (outcome == null) return;
    _lastAnalyzedMessageCount = outcome.analyzedMessageCount;
    _applyAnalysisResult(outcome.result);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 清掉可能殘留的 root SnackBar（OCR 加入綠色 banner 等），避免跨頁顯示。
    _scaffoldMessenger?.clearSnackBars();
    final coachMark = _editMessageCoachMarkEntry;
    if (coachMark != null && coachMark.mounted) {
      coachMark.remove();
    }
    _editMessageCoachMarkEntry = null;
    _scrollController.dispose();
    _replyZoneEntrance.dispose();
    _feedbackCommentController.dispose();
    _optimizeController.dispose();
    _screenshotAnalysisContextNoteController.dispose();
    super.dispose();
  }

  /// Push 到別的 route 之前先清掉 analysis-screen 本頁觸發的 root SnackBar，
  /// 避免 OCR 加入綠色 banner（duration=7s）跟著用戶飄到下一頁。
  /// Pop 路徑由 dispose 清；push 路徑（profile / article / paywall）走這裡。
  void _clearAnalysisSnackBarsBeforePush() {
    _scaffoldMessenger?.clearSnackBars();
  }

  /// 首次看到對話 bubble 時浮出 coach mark，引導用戶長按 bubble 編輯訊息。
  /// 已讀取過或當前已有 overlay 顯示時 no-op。
  Future<void> _maybeShowEditMessageCoachMark({String? partnerId}) async {
    if (!mounted) return;
    if (_editMessageCoachMarkEntry != null) return;
    if (await AnalysisHintService.hasSeenEditMessage(partnerId: partnerId)) {
      return;
    }
    if (!mounted) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => EditMessageCoachMark(
        onDismiss: () async {
          if (entry.mounted) entry.remove();
          if (_editMessageCoachMarkEntry == entry) {
            _editMessageCoachMarkEntry = null;
          }
          await AnalysisHintService.markEditMessageSeen(partnerId: partnerId);
        },
      ),
    );
    _editMessageCoachMarkEntry = entry;
    overlay.insert(entry);
  }

  /// 退出時自動刪除空對話（沒有訊息的「新對話」）
  ///
  /// Navigation:
  ///   - If there's a route underneath (push from PartnerDetail / list /
  ///     anywhere), pop back to it so the user lands where they came from.
  ///   - Only fall back to '/' when this screen is the navigation root
  ///     (e.g. deep-link entry, no underlying stack).
  ///   Pre-A2 this hardcoded `context.go('/')`, which broke
  ///   PartnerDetail → 新增對話 → conversation → ← because go() resets
  ///   the entire stack regardless of how the user arrived.
  ///   (Bruce TF feedback 2026-04-28).
  Future<void> _cleanupAndGoBack() async {
    if (_isLeavingAfterPersistence) return;
    _isLeavingAfterPersistence = true;
    await _persistence.awaitSettled();
    if (!mounted) return;
    final repository = ref.read(conversationRepositoryProvider);
    final conversation = repository.getConversation(widget.conversationId);
    try {
      if (conversation != null && conversation.messages.isEmpty) {
        await ref
            .read(conversationWriteControllerProvider.notifier)
            .delete(conversation);
      }
    } catch (_) {
      // Leaving the screen should not be blocked by best-effort cleanup.
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  bool _canMutateMessage(Conversation conversation, Message message) {
    final index = conversation.messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return false;
    final completed = _effectiveLastAnalyzedMessageCount(conversation)
        .clamp(0, conversation.messages.length)
        .toInt();
    return index >= completed;
  }

  /// 換邊（她說 ↔ 我說）
  Future<void> _swapMessageSide(
      Conversation conversation, Message message) async {
    if (!_canMutateMessage(conversation, message)) return;
    final index = conversation.messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;

    conversation.messages[index] = Message(
      id: message.id,
      content: message.content,
      isFromMe: !message.isFromMe,
      timestamp: message.timestamp,
      enthusiasmScore: message.enthusiasmScore,
      quotedReplyPreview: message.quotedReplyPreview,
      quotedReplyPreviewIsFromMe: message.quotedReplyPreviewIsFromMe,
    );

    await ref
        .read(conversationWriteControllerProvider.notifier)
        .save(conversation);
    if (!mounted) return;
    ref.invalidate(conversationProvider(widget.conversationId));
    _showEditedAnalyzedMessageSnackBar();
  }

  /// 編輯訊息文字（供 OCR 錯字現場修正用）
  Future<void> _editMessage(Conversation conversation, Message message) async {
    if (!_canMutateMessage(conversation, message)) return;
    final controller = TextEditingController(text: message.content);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.brandSurface2,
        surfaceTintColor: Colors.transparent,
        title: Text('編輯文字',
            style: TextStyle(color: AppColors.onBackgroundPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          minLines: 1,
          onTapOutside: (_) => _dismissKeyboard(),
          cursorColor: AppColors.ctaStart,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
            height: 1.35,
          ),
          decoration: InputDecoration(
            hintText: '修正這則訊息…',
            hintStyle: TextStyle(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.6)),
            filled: true,
            fillColor: AppColors.brandInk.withValues(alpha: 0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.ctaStart, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            // unselectedText 是白玻璃底用的暗紫，放深底約 1.8:1 幾乎看不見。
            child: Text('取消',
                style: TextStyle(color: AppColors.onBackgroundSecondary)),
          ),
          TextButton(
            onPressed: AppHaptics.onPress(
                () => Navigator.of(context).pop(controller.text.trim())),
            style: TextButton.styleFrom(foregroundColor: AppColors.ctaStart),
            child: const Text('儲存'),
          ),
        ],
      ),
    );

    if (edited == null || edited.isEmpty || edited == message.content) {
      return;
    }
    if (!_canMutateMessage(conversation, message)) return;

    final index = conversation.messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;

    conversation.messages[index] = Message(
      id: message.id,
      content: edited,
      isFromMe: message.isFromMe,
      timestamp: message.timestamp,
      enthusiasmScore: message.enthusiasmScore,
      quotedReplyPreview: message.quotedReplyPreview,
      quotedReplyPreviewIsFromMe: message.quotedReplyPreviewIsFromMe,
    );

    await ref
        .read(conversationWriteControllerProvider.notifier)
        .save(conversation);
    if (!mounted) return;
    ref.invalidate(conversationProvider(widget.conversationId));
    _showEditedAnalyzedMessageSnackBar();
  }

  /// 刪除訊息
  Future<void> _deleteMessage(
      Conversation conversation, Message message) async {
    if (!_canMutateMessage(conversation, message)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.brandSurface2,
        title: Text('刪除訊息',
            style: TextStyle(color: AppColors.onBackgroundPrimary)),
        content: Text(
          '確定要刪除這則訊息嗎？',
          style: TextStyle(color: AppColors.onBackgroundSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            // unselectedText 是白玻璃底用的暗紫，放深底約 1.8:1 幾乎看不見。
            child: Text('取消',
                style: TextStyle(color: AppColors.onBackgroundSecondary)),
          ),
          TextButton(
            onPressed:
                AppHaptics.onPress(() => Navigator.of(context).pop(true)),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!_canMutateMessage(conversation, message)) return;

    conversation.messages.removeWhere((m) => m.id == message.id);
    await ref
        .read(conversationWriteControllerProvider.notifier)
        .save(conversation);
    if (!mounted) return;
    ref.invalidate(conversationProvider(widget.conversationId));
  }

  /// 啟動識別計時器
  void _startRecognizeTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isRecognizing || _recognizeCancelled) {
        return false;
      }
      setState(() {
        _recognizeElapsedSeconds++;
      });
      _debugLog('[Timer] $_recognizeElapsedSeconds 秒');
      return true;
    });
  }

  /// 取消識別
  void _cancelRecognize() {
    _debugLog('用戶取消識別');
    _recognizeCancelled = true;
    setState(() {
      _isRecognizing = false;
      _applyErrorState(message: '已取消辨識');
      _selectedImages = [];
      _selectedImageMetrics = [];
      _recognizedConversation = null;
      _recognizedWarningMessage = null;
      _hasPendingRecognitionImport = false;
      _recognitionFromCache = false;
    });
  }

  /// 新增訊息到對話並重新分析
  void _handleRecognizeProgress(AnalysisProgressUpdate update) {
    if (!mounted || !_isRecognizing || _recognizeCancelled) {
      return;
    }

    setState(() {
      _recognizeStage = update.stage;
    });
  }

  void _handleRecognizeTelemetry(AnalysisTelemetry telemetry) {
    if (!mounted || _recognizeCancelled) {
      return;
    }

    setState(() {
      _lastRecognizeTelemetry = telemetry;
    });
  }

  void _handleAnalysisTelemetry(AnalysisTelemetry telemetry) {
    if (!mounted) {
      return;
    }

    setState(() {
      _lastAnalysisTelemetry = telemetry;
    });
  }

  String _recognizeStageLabel(AnalysisProgressStage stage) {
    return analysisProgressStageLabel(stage);
  }

  int get _totalOriginalImageBytes => _selectedImageMetrics.fold(
        0,
        (sum, metric) => sum + metric.originalBytes,
      );

  int get _totalCompressedImageBytes => _selectedImageMetrics.isEmpty
      ? _selectedImages.fold(0, (sum, image) => sum + image.length)
      : _selectedImageMetrics.fold(
          0,
          (sum, metric) => sum + metric.compressedBytes,
        );

  String get _recognizeButtonLabel {
    if (_isRecognizing) {
      return _recognizeStageLabel(_recognizeStage);
    }

    final conversation = ref.read(conversationProvider(widget.conversationId));
    final isReplacingCurrentBatch = conversation != null &&
        AnalysisFragmentPolicy.canAppendInput(conversation) &&
        conversation.messages.isNotEmpty;
    return isReplacingCurrentBatch
        ? '辨識並取代本次內容（${_selectedImages.length} 張）'
        : '辨識截圖文字（${_selectedImages.length} 張）';
  }

  void _handleSelectedImagesChanged(List<Uint8List> images) {
    setState(() {
      _selectedImages = List<Uint8List>.from(images);
      _selectedImageMetrics = [];
      _lastRecognitionImages = List<Uint8List>.from(images);
      _lastRecognitionImageMetrics = [];
      _recognizedConversation = null;
      _recognizedWarningMessage = null;
      _hasPendingRecognitionImport = false;
      _lastRecognizeTelemetry = null;
      if (_selectedImages.isNotEmpty) {
        _resetErrorState();
      }
    });
  }

  void _handleSelectedImageMetricsChanged(List<SelectedImageMetrics> metrics) {
    setState(() {
      _selectedImageMetrics = List<SelectedImageMetrics>.from(metrics);
      if (_selectedImages.isNotEmpty) {
        _lastRecognitionImageMetrics = List<SelectedImageMetrics>.from(metrics);
      }
    });
  }

  void _discardPendingRecognitionDraft() {
    setState(() {
      _recognizedConversation = null;
      _recognizedWarningMessage = null;
      _hasPendingRecognitionImport = false;
      _recognitionFromCache = false;
    });
  }

  void _rememberRecognitionReplay({
    required List<Uint8List> images,
    required List<SelectedImageMetrics> metrics,
  }) {
    _lastRecognitionImages = List<Uint8List>.from(images);
    _lastRecognitionImageMetrics = List<SelectedImageMetrics>.from(metrics);
  }

  bool get _canForceReRecognize =>
      !_isRecognizing && _lastRecognitionImages.isNotEmpty;

  Future<void> _forceReRecognizeLastBatch() async {
    if (!_canForceReRecognize) {
      return;
    }

    await _recognizeAndAddToConversation(
      forceRefresh: true,
      overrideImages: _lastRecognitionImages,
      overrideMetrics: _lastRecognitionImageMetrics,
    );
  }

  /// 「重新選圖」（2026-08-16 Bruce 回饋，取代「重新讀圖」）：直接開相簿
  /// 重選 1–3 張，選完**回到選圖確認區**（縮圖可增刪、由使用者自己按
  /// 「辨識並取代本次內容」）。不自動辨識——已匯入片段的畫面上沒有辨識
  /// 進度 UI，自動辨識會讓畫面停在舊結果毫無反應（2026-08-16 Eric 實測）。
  ///
  /// 檢查鏈與 ImagePickerWidget._processImage 同一套（格式→preflight→壓縮
  /// →大小）；那邊改規則這裡要同步。差異：這裡任一張不合格就整批中止、
  /// 保留原批不動，使用者重選即可。
  Future<void> _repickScreenshots() async {
    if (_isRecognizing) return;

    final List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(limit: 3);
    } catch (_) {
      _showFloatingSnackBar('選取圖片失敗，請稍後再試。');
      return;
    }
    if (files.isEmpty) return;

    final images = <Uint8List>[];
    final metrics = <SelectedImageMetrics>[];
    for (final file in files.take(3)) {
      if (!ImageCompressService.isSupportedFormat(file.mimeType)) {
        _showFloatingSnackBar('目前只支援 JPEG、PNG、WebP、HEIC 截圖。');
        return;
      }
      final bytes = await file.readAsBytes();
      final preflight = ScreenshotPreflightService.inspect(bytes);
      if (preflight.isRejected) {
        _showFloatingSnackBar(preflight.message ?? '這張圖片暫時不適合做聊天截圖辨識。');
        return;
      }
      if (preflight.isWarning && mounted) {
        _showFloatingSnackBar(preflight.message ?? '這張截圖可能辨識較不穩，請先確認內容。');
      }
      final compressed = await ImageCompressService.compressImage(bytes);
      if (compressed == null ||
          compressed.length > ImageCompressService.maxSizeBytes) {
        _showFloatingSnackBar('截圖處理失敗，請換一張再試。');
        return;
      }
      images.add(compressed);
      metrics.add(
        SelectedImageMetrics(
          originalBytes: bytes.length,
          compressedBytes: compressed.length,
        ),
      );
    }
    if (!mounted) return;

    // 走既有選圖狀態：清掉舊辨識預覽、顯示選圖確認區（含辨識 CTA 與進度）。
    _handleSelectedImagesChanged(images);
    _handleSelectedImageMetricsChanged(metrics);
    unawaited(_scrollToBottom(delay: const Duration(milliseconds: 250)));
  }

  SessionContext _screenshotSessionContextFor(Conversation conversation) {
    final existing = conversation.sessionContext;
    final note = _screenshotAnalysisContextNoteFor();
    return SessionContext(
      meetingContext: _screenshotMeetingContext,
      duration: _screenshotDuration,
      goal: _screenshotGoal,
      userStyle: existing?.userStyle,
      userInterests: existing?.userInterests,
      targetDescription: existing?.targetDescription,
      analysisContextNote: note,
    );
  }

  String? _screenshotAnalysisContextNoteFor() {
    final typed = _screenshotAnalysisContextNoteController.text.trim();
    return typed.isEmpty ? null : typed;
  }

  Future<void> _applyRecognitionImport({
    required ScreenshotRecognitionDialogResult dialogResult,
    required RecognizedConversation recognized,
  }) async {
    final commit = await _screenshotImport.commitImport(
      editedRecognizedMessages: dialogResult.messages,
      newName: dialogResult.name,
      meeting: dialogResult.meetingContext,
      duration: dialogResult.duration,
      goal: dialogResult.goal,
      analysisContextNote: dialogResult.analysisContextNote,
      recognized: recognized,
      hasLoadedAnalysisResult: _enthusiasmScore != null,
    );

    switch (commit.kind) {
      case ScreenshotImportCommitKind.conversationMissing:
        if (!mounted || _recognizeCancelled) {
          return;
        }
        setState(() {
          _isRecognizing = false;
          _applyErrorState(
            message: '目前對話不存在，請重新進入後再試一次',
            action: AnalysisErrorAction.retry,
            origin: _AnalysisErrorOrigin.recognition,
          );
        });
        return;
      case ScreenshotImportCommitKind.createdNewFragment:
        if (!mounted || _recognizeCancelled) {
          _debugLog(
              '[Recognize] Ignore post-save UI update after cancel/dispose');
          return;
        }
        setState(() {
          _selectedImages = [];
          _selectedImageMetrics = [];
          _recognizedConversation = commit.updatedRecognized;
          _recognizedWarningMessage = null;
          _hasPendingRecognitionImport = false;
        });
        // OCR 匯入浮動提示全拆（2026-08-16 Eric：沒什麼用）。來源已完成分析
        // 而另開新片段時，直接帶使用者過去，不留在舊片段乾等。
        context.push('/conversation/${commit.createdConversationId}');
        return;
      case ScreenshotImportCommitKind.replacedBatch:
        if (!mounted || _recognizeCancelled) {
          _debugLog(
              '[Recognize] Ignore post-save UI update after cancel/dispose');
          return;
        }
        setState(() {
          _selectedImages = [];
          _selectedImageMetrics = [];
          _recognizedConversation = commit.updatedRecognized;
          _recognizedWarningMessage = null;
          _hasPendingRecognitionImport = false;
        });
        // 「已確認本次片段／查看本次內容」浮動提示已拆（2026-08-16 Eric：
        // 沒什麼用——內容就在眼前，確認框也已揭露取代規則）。另開新片段的
        // 「前往新片段」提示保留，那個有導航作用。
        return;
    }
  }

  Future<void> _resumeRecognitionImport() async {
    final recognized = _recognizedConversation;
    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (recognized == null || conversation == null) {
      return;
    }

    final dialogResult = await _showRecognitionConfirmDialog(
      recognized: recognized,
      currentConversation: conversation,
      warningMessage: _recognizedWarningMessage,
    );

    if (dialogResult == null) {
      if (!mounted) return;
      showBrandFeedbackSnackBar(
        context,
        title: '已保留這次辨識結果，你可以稍後再繼續確認。',
        icon: Icons.info_outline_rounded,
      );
      return;
    }

    await _applyRecognitionImport(
      dialogResult: dialogResult,
      recognized: recognized,
    );
  }

  void _preserveRecognitionDraft({
    required RecognizedConversation recognized,
    required String? warningMessage,
  }) {
    setState(() {
      _selectedImages = [];
      _selectedImageMetrics = [];
      _recognizedConversation = recognized;
      _recognizedWarningMessage = warningMessage;
      _hasPendingRecognitionImport = true;
    });
  }

  void _showFloatingSnackBar(String message) {
    if (!mounted) return;

    showBrandFeedbackSnackBar(
      context,
      title: message,
      icon: Icons.info_outline_rounded,
    );
  }

  UsageData _buildPreviewUsageData() {
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

  /// ADR #19 r3 分析前確認流程。
  ///
  /// 順序（定案 #4）：算出本次計費字數/則數 → 4001+ 先擋（請分批，不送出）
  /// → 額度檢查（preview dialog 內建，不足時無法確認、給升級 CTA）→
  /// >2000 確認框（同一 dialog 的 overcharge 變體，顯示精確 20 則）。
  Future<({bool confirmed, OverchargeConfirmationPayload? overcharge})>
      _confirmAnalysisPreview(List<Message> requestMessages) async {
    if (!mounted) {
      return (confirmed: false, overcharge: null);
    }

    final conversation = ref.read(conversationProvider(widget.conversationId));
    // 增量 = 字數差：billing baseline 用 lastAnalyzedCharCount（ADR #19
    // 規格 #1 欄位職責分離——lastAnalyzedMessageCount 只留給 stale/UI 判斷）。
    final preview = MessageCalculator.previewConversation(
      requestMessages,
      previousAnalyzedCharCount: conversation?.lastAnalyzedCharCount ?? 0,
    );

    if (preview.band.kind == BillingBandKind.reject) {
      // 4000 字硬上限本地預警層（server 守門 CONTENT_TOO_LONG 是第二層）。
      _showFloatingSnackBar(
        '這次新增內容超過 ${MessageCalculator.maxBillableChars} 字，請分批分析。',
      );
      return (confirmed: false, overcharge: null);
    }

    final confirmed = await showAnalysisPreviewDialog(
      context: context,
      preview: preview,
      usage: _buildPreviewUsageData(),
      onUpgrade: () {
        Navigator.of(context, rootNavigator: true).pop(false);
        _showPaywall(context);
      },
    );
    if (!confirmed || !mounted) {
      return (confirmed: false, overcharge: null);
    }

    if (preview.band.kind == BillingBandKind.overcharge) {
      // 用戶已在確認框看到精確「本次將使用 20 則」。生成一次性確認憑證：
      // 綁定即將送出 payload 的 hash + 計費字數 + confirmationId
      //（定案 #5：server 以 hash 驗證內容未變、以 confirmationId 做
      // idempotency claim，重送/雙送絕不重扣 20）。
      return (
        confirmed: true,
        overcharge: OverchargeConfirmationPayload(
          payloadHash: MessageCalculator.computeBillingPayloadHash(
            requestMessages.map((message) => message.content).toList(),
          ),
          billableChars: preview.billableChars,
          confirmationId: const Uuid().v4(),
        ),
      );
    }

    return (confirmed: true, overcharge: null);
  }

  void _syncSubscriptionUsageFromResult(
    AnalysisResult result, {
    bool showChargeToast = false,
    String chargeActionLabel = '分析',
  }) {
    final usage = result.rawResponse?['usage'];
    if (usage is! Map) {
      return;
    }

    // ADR #19 r3：預覽只報區間，分析後告知 server 實扣則數。
    // 只在分析完成現場顯示（hydration 恢復快照時不顯示）。
    if (showChargeToast) {
      final toast = buildAnalysisUsageChargeToast(
        usage,
        actionLabel: chargeActionLabel,
      );
      if (toast != null) {
        _showFloatingSnackBar(toast);
      }
    }

    final monthlyRemaining = usage['monthlyRemaining'];
    final dailyRemaining = usage['dailyRemaining'];
    if (monthlyRemaining is! num || dailyRemaining is! num) {
      return;
    }

    ref.read(subscriptionProvider.notifier).syncUsageFromServer(
          monthlyRemaining: monthlyRemaining.round(),
          dailyRemaining: dailyRemaining.round(),
          isTestAccount: usage['isTestAccount'] == true,
        );
  }

  String? _buildRecognitionWarning({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
  }) =>
      ScreenshotRecognitionHelper.buildWarning(
        recognized: recognized,
        currentConversation: currentConversation,
        expectedPartnerName:
            _screenshotImport.expectedPartnerName(currentConversation),
      );

  /// data 層守門評估 → section 展示資料（severity 映射留在 composition root）。
  List<TelemetryGuardrailChipData> _telemetryGuardrailChips(
    AnalysisTelemetry telemetry,
  ) =>
      AnalysisTelemetryGuardrailHelper.evaluate(telemetry)
          .map(
            (guardrail) => TelemetryGuardrailChipData(
              color: _telemetryGuardrailColor(guardrail),
              icon: _telemetryGuardrailIcon(guardrail),
              label: guardrail.label,
              detail: guardrail.detail,
            ),
          )
          .toList(growable: false);

  Color _telemetryGuardrailColor(AnalysisTelemetryGuardrail guardrail) {
    switch (guardrail.severity) {
      case AnalysisTelemetryGuardrailSeverity.critical:
        return AppColors.error;
      case AnalysisTelemetryGuardrailSeverity.warning:
        return AppColors.warning;
      case AnalysisTelemetryGuardrailSeverity.info:
        return AppColors.info;
    }
  }

  IconData _telemetryGuardrailIcon(AnalysisTelemetryGuardrail guardrail) {
    switch (guardrail.severity) {
      case AnalysisTelemetryGuardrailSeverity.critical:
        return Icons.error_outline_rounded;
      case AnalysisTelemetryGuardrailSeverity.warning:
        return Icons.warning_amber_rounded;
      case AnalysisTelemetryGuardrailSeverity.info:
        return Icons.insights_rounded;
    }
  }

  /// 顯示識別確認對話框，讓用戶設定對方名字和情境
  Future<ScreenshotRecognitionDialogResult?> _showRecognitionConfirmDialog({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
    String? warningMessage,
  }) async {
    final expectedPartnerName =
        _screenshotImport.expectedPartnerName(currentConversation);
    final partnerId = currentConversation.partnerId?.trim();
    final isPartnerBound = partnerId != null && partnerId.isNotEmpty;
    final initialContext = _screenshotSessionContextFor(currentConversation);
    return showDialog<ScreenshotRecognitionDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ScreenshotRecognitionDialog(
        recognized: recognized,
        warningMessage: warningMessage,
        initialName: isPartnerBound
            ? expectedPartnerName ?? currentConversation.name
            : recognized.contactName?.trim() ?? '',
        initialMeetingContext: initialContext.meetingContext,
        initialDuration: initialContext.duration,
        initialGoal: initialContext.goal,
        initialAnalysisContextNote: _screenshotAnalysisContextNoteFor() ?? '',
        currentConversation: currentConversation,
        expectedPartnerName: expectedPartnerName,
      ),
    );
  }

  // 識別計時器
  int _recognizeElapsedSeconds = 0;
  bool _recognizeCancelled = false;

  /// 識別截圖並加入對話（不進行完整分析）
  Future<void> _recognizeAndAddToConversation({
    bool forceRefresh = false,
    List<Uint8List>? overrideImages,
    List<SelectedImageMetrics>? overrideMetrics,
  }) async {
    final sourceImages = overrideImages ?? _selectedImages;
    final sourceMetrics = overrideMetrics ?? _selectedImageMetrics;
    if (sourceImages.isEmpty) return;
    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: '截圖辨識',
    );
    if (!consented || !mounted) return;

    _selectedImages = List<Uint8List>.from(sourceImages);
    _selectedImageMetrics = List<SelectedImageMetrics>.from(sourceMetrics);

    _debugLog('=== 開始截圖識別 ===');
    _debugLog('圖片數量: ${_selectedImages.length}');
    _debugLog(
        '圖片大小: ${_selectedImages.map((i) => '${(i.length / 1024).toStringAsFixed(1)}KB').join(', ')}');

    // 重置計時器狀態
    _recognizeElapsedSeconds = 0;
    _recognizeCancelled = false;

    setState(() {
      _isRecognizing = true;
      _resetErrorState();
      // 重新讀圖＝上一輪（若有）已完成的分析結果已失效：清掉它，否則辨識預覽卡
      // 會因 _enthusiasmScore 仍非 null 而不重現，且 stale 分析會與新辨識並存。
      _clearDetailedAnalysisStateForStreamingAnalyzePartial();
      _recognizedConversation = null;
      _recognizedWarningMessage = null;
      _hasPendingRecognitionImport = false;
      _recognitionFromCache = false;
      _recognizeStage = AnalysisProgressStage.preparingPayload;
      _lastRecognizeTelemetry = null;
    });

    // 啟動計時器更新 UI
    _startRecognizeTimer();

    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) {
      _debugLog('錯誤: 找不到對話');
      setState(() {
        _isRecognizing = false;
        _applyErrorState(
          message: '找不到對話',
          action: AnalysisErrorAction.retry,
          origin: _AnalysisErrorOrigin.recognition,
        );
      });
      return;
    }

    _debugLog('對話 ID: ${conversation.id}');
    _debugLog('現有訊息數: ${conversation.messages.length}');
    final startTime = DateTime.now();
    final metricsToProcess = List<SelectedImageMetrics>.from(sourceMetrics);

    // 複製圖片列表，避免狀態問題
    final imagesToProcess = List<Uint8List>.from(_selectedImages);
    _debugLog('複製圖片列表完成，數量: ${imagesToProcess.length}');

    try {
      // 呼叫 API 識別截圖（純識別模式，不做完整分析，節省時間和額度）
      _debugLog('呼叫 API... (timeout: 120s)');
      final recognition = await _screenshotImport.recognize(
        images: imagesToProcess,
        conversation: conversation,
        sessionContext: _screenshotSessionContextFor(conversation),
        forceRefresh: forceRefresh,
        totalCompressedImageBytes: _totalCompressedImageBytes,
        onProgress: _handleRecognizeProgress,
        onTelemetry: _handleRecognizeTelemetry,
      );
      final result = recognition.result;
      final isFromCache = recognition.fromCache;
      if (isFromCache) {
        _debugLog('[Recognize] OCR cache hit');
        _rememberRecognitionReplay(
          images: imagesToProcess,
          metrics: metricsToProcess,
        );
      } else {
        _debugLog(
            'API 回應成功，耗時: ${DateTime.now().difference(startTime).inSeconds}s');
        if (result.recognizedConversation != null) {
          _rememberRecognitionReplay(
            images: imagesToProcess,
            metrics: metricsToProcess,
          );
        }
      }

      if (!mounted || _recognizeCancelled) {
        _debugLog('[Recognize] Ignore result after cancel/dispose');
        return;
      }

      if (result.recognizedConversation != null &&
          result.recognizedConversation!.messages != null &&
          result.recognizedConversation!.messages!.isNotEmpty) {
        final recognized = result.recognizedConversation!;
        final warningMessage = _buildRecognitionWarning(
          recognized: recognized,
          currentConversation: conversation,
        );

        if (recognized.importPolicy == 'reject') {
          setState(() {
            _isRecognizing = false;
            _applyErrorState(
              message: warningMessage ?? recognized.summary,
              action: AnalysisErrorAction.rescreenshot,
              origin: _AnalysisErrorOrigin.recognition,
            );
            _recognizedConversation = recognized;
            _recognizedWarningMessage = warningMessage;
            _hasPendingRecognitionImport = false;
            _recognitionFromCache = isFromCache;
          });
          return;
        }

        setState(() {
          _isRecognizing = false;
          _recognitionFromCache = isFromCache;
        });

        // 顯示確認對話框
        if (!mounted) return;
        final dialogResult = await _showRecognitionConfirmDialog(
          recognized: recognized,
          currentConversation: conversation,
          warningMessage: warningMessage,
        );

        // 用戶取消
        if (dialogResult == null) {
          _preserveRecognitionDraft(
            recognized: recognized,
            warningMessage: warningMessage,
          );
          if (!mounted) return;
          showBrandFeedbackSnackBar(
            context,
            title: '已保留這次辨識結果，你可以稍後再繼續確認。',
            icon: Icons.info_outline_rounded,
          );
          return;
        }

        await _applyRecognitionImport(
          dialogResult: dialogResult,
          recognized: recognized,
        );
        return;
      }

      // 識別失敗或沒有識別到訊息
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      _debugLog('識別失敗 (無訊息)，耗時: ${elapsed}s');
      _debugLog('recognizedConversation: ${result.recognizedConversation}');
      setState(() {
        _isRecognizing = false;
        _applyErrorState(
          message: recognitionFailureMessage(
            result.recognizedConversation?.summary,
          ),
          action: AnalysisErrorAction.rescreenshot,
          origin: _AnalysisErrorOrigin.recognition,
        );
      });
    } on AnalysisException catch (e) {
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      _debugLog('AnalysisException，耗時: ${elapsed}s');
      _debugLog('錯誤訊息: ${e.message}');
      if (!mounted || _recognizeCancelled) {
        _debugLog('[Recognize] Ignore AnalysisException after cancel/dispose');
        return;
      }
      setState(() {
        _isRecognizing = false;
        _applyErrorState(
          message: e.message,
          action: e.suggestedAction,
          origin: _AnalysisErrorOrigin.recognition,
        );
      });
    } catch (e) {
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      _debugLog('未知錯誤，耗時: ${elapsed}s');
      _debugLog('錯誤類型: ${e.runtimeType}');
      _debugLog('錯誤詳情: $e');
      setState(() {
        _isRecognizing = false;
        _applyErrorState(
          message: '截圖辨識暫時失敗，請稍後再試。',
          action: AnalysisErrorAction.retry,
          origin: _AnalysisErrorOrigin.recognition,
        );
      });
    }
  }

  Future<void> _runAnalysis({
    bool skipPreview = false,
    bool waitForCompletion = false,
    int? analysisMessageLimit,
    bool allowPendingOutgoingRefresh = false,
  }) async {
    final pendingRecordRepair = _persistence.recordRepairFuture;
    if (pendingRecordRepair != null) {
      await pendingRecordRepair;
    }
    if (!mounted) return;
    if (_persistence.recordNeedsRepair) {
      _restorePersistedAnalysis();
      final retry = _persistence.recordRepairFuture;
      if (retry != null) await retry;
      if (!mounted) return;
      if (_persistence.recordNeedsRepair) {
        setState(() {
          _isAnalyzing = false;
          _applyErrorState(
            message: '上一筆分析紀錄尚未安全保存，請稍後再試。',
            action: AnalysisErrorAction.retry,
            origin: _AnalysisErrorOrigin.analysis,
            guidance: '我們會先保留上一筆結果，等紀錄保存成功後才能開始新的分析。',
          );
        });
        return;
      }
    }
    // 先關閉 SnackBar (如果有的話)
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    setState(() {
      _resetErrorState();
      _lastAnalysisTelemetry = null;
    });

    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) {
      setState(() {
        _isAnalyzing = false;
        _applyErrorState(
          message: '找不到對話',
          action: AnalysisErrorAction.retry,
          origin: _AnalysisErrorOrigin.analysis,
        );
      });
      return;
    }

    final preparer = ref.read(analysisRunPreparerProvider);
    final runGate = preparer.gate(
      conversation: conversation,
      analysisMessageLimit: analysisMessageLimit,
    );
    switch (runGate.failure) {
      case AnalysisRunPrepareFailure.emptyConversation:
        setState(() {
          _isAnalyzing = false;
          _applyErrorState(
            message: '請先輸入對話內容或上傳截圖',
            action: AnalysisErrorAction.addIncomingMessage,
            origin: _AnalysisErrorOrigin.analysis,
            guidance: '請重新選擇包含她回覆的聊天截圖，確認文字後再分析。',
          );
        });
        return;
      case AnalysisRunPrepareFailure.noIncomingReply:
        setState(() {
          _isAnalyzing = false;
          _applyErrorState(
            message: '目前還沒有她的新回覆可以分析。',
            action: AnalysisErrorAction.addIncomingMessage,
            origin: _AnalysisErrorOrigin.analysis,
            guidance: '請重新選擇包含她回覆的聊天截圖，再按「開始分析」。',
          );
        });
        return;
      case null:
        break;
    }

    if (!allowPendingOutgoingRefresh &&
        _pendingMessagesAreOutgoingOnly(conversation)) {
      setState(() {
        _isAnalyzing = false;
        _applyErrorState(
          message: '已記錄你剛剛說的內容，先不預測她可能怎麼回。',
          action: AnalysisErrorAction.addIncomingMessage,
          origin: _AnalysisErrorOrigin.analysis,
          guidance: '等她回覆後補上「她說」，我會用最新來回重新給下一步建議。',
        );
      });
      return;
    }

    try {
      final preparation = await preparer.assemble(
        conversation: conversation,
        gate: runGate,
      );
      final analyzedMessageCount = preparation.analyzedMessageCount;

      // 呼叫 Supabase Edge Function（不帶圖片，因為截圖已轉成文字存入）
      // skipPreview 路徑刻意拿不到 overcharge 憑證：>2000 字會被 server
      // 守門擋回（409 要求重新確認），絕不可能未經確認被扣 20 則。
      ({
        bool confirmed,
        OverchargeConfirmationPayload? overcharge
      }) previewDecision;
      if (skipPreview) {
        previewDecision = (confirmed: true, overcharge: null);
      } else {
        previewDecision = await _confirmAnalysisPreview(
          preparation.requestMessages,
        );
      }
      if (!previewDecision.confirmed || !mounted) {
        return;
      }
      final consented = await AiDataSharingConsent.ensure(
        context,
        featureLabel: '對話分析',
      );
      if (!consented || !mounted) {
        return;
      }

      setState(() {
        _isAnalyzing = true;
        _followLiveAnalysis = false;
        _streamErrorMessage = null;
        _streamErrorRetriesRemaining = 0;
        _quotaExceededInfo = null;
        _streamProgressLabel = '開始完整分析';
        _streamProgressDetail = '正在建立串流連線。';
        _streamContents = const [];
        _activeAnalysisMessageCount = analyzedMessageCount;
      });

      // Fire-and-forget（waitForCompletion 之外）。notifier 快取 payload 供
      // retryStream 並跨畫面導航存活；ref.listen + initState hydration 把
      // provider 狀態鏡射回本地欄位，讓讀 _enthusiasmScore、_isAnalyzing 的
      // 舊 render tree 繼續運作（Eric 2026-05-28 UX spec）。
      await _session.start(
        conversation: conversation,
        preparation: preparation,
        confirmedOvercharge: previewDecision.overcharge,
        waitForCompletion: waitForCompletion,
        shouldProceed: () => mounted,
      );
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _followLiveAnalysis = false;
        _applyErrorState(
          message: '分析暫時失敗，請稍後再試。',
          action: AnalysisErrorAction.retry,
          origin: _AnalysisErrorOrigin.analysis,
        );
      });
    }
  }

  /// Apply a transition from [streamingAnalyzeProvider] into local
  /// setState-backed fields. The notifier is the source of truth; this method
  /// just mirrors transitions onto the legacy render code so we don't have to
  /// rewrite the 4000-line build() tree.
  void _onStreamingAnalyzeStateChanged(
    StreamingAnalysisState? prev,
    StreamingAnalysisState next,
  ) {
    if (!mounted) return;
    if (prev?.phase == next.phase &&
        prev?.analysisRunId == next.analysisRunId &&
        prev?.result == next.result &&
        prev?.streamProgressLabel == next.streamProgressLabel &&
        prev?.streamProgressDetail == next.streamProgressDetail &&
        prev?.streamContents == next.streamContents) {
      return;
    }
    switch (next.phase) {
      case StreamingAnalyzePhase.connecting:
        setState(() {
          _isAnalyzing = true;
          _streamErrorMessage = null;
          _streamErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = next.streamProgressLabel;
          _streamProgressDetail = next.streamProgressDetail;
          _streamContents = next.streamContents;
          _activeAnalysisMessageCount =
              next.analyzedMessageCount ?? next.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
          _resetErrorState();
        });
        break;
      case StreamingAnalyzePhase.streamingReport:
        // Mirror the notifier's cleared error fields (I-P2-d) so the build
        // tree flips from retry back to live streaming when the user taps
        // retry. Without this the local _streamErrorMessage keeps the RetryCard
        // rendered even though the notifier is mid-flight.
        setState(() {
          _isAnalyzing = true;
          _streamErrorMessage = null;
          _streamErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = next.streamProgressLabel;
          _streamProgressDetail = next.streamProgressDetail;
          _streamContents = next.streamContents;
          _activeAnalysisMessageCount =
              next.analyzedMessageCount ?? next.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.done:
        final result = next.result;
        if (result == null) return;
        if (_session
            .isResultStaleForCurrentConversation(next.toRunMetadata())) {
          setState(() {
            _isAnalyzing = false;
            _followLiveAnalysis = false;
            _streamErrorMessage = '你剛剛更新了本次片段，這份完整分析先不套用。請重新按「開始分析」。';
            _streamErrorRetriesRemaining = 0;
            _quotaExceededInfo = null;
            _streamContents = const [];
            _activeAnalysisMessageCount =
                next.analyzedMessageCount ?? next.conversationMessageCount;
            _clearDetailedAnalysisStateForStreamingAnalyzePartial();
          });
          return;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
        final conv = ref.read(conversationProvider(widget.conversationId));
        final analyzedMessageCount = next.analyzedMessageCount ??
            next.conversationMessageCount ??
            conv?.messages.length;
        setState(() {
          _isAnalyzing = false;
          _followLiveAnalysis = false;
          _streamErrorMessage = null;
          _streamErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = const [];
          _activeAnalysisMessageCount = null;
          if (conv != null && analyzedMessageCount != null) {
            _lastAnalyzedMessageCount = analyzedMessageCount;
          }
          _applyAnalysisResult(result);
          _enthusiasmScore = result.enthusiasmScore;
          _dimensionScores = result.dimensionScores;
          _strategy = result.strategy;
          _replies = result.replies;
          _replyOptions = result.replyOptions;
          _topicDepth = result.topicDepth;
          _healthCheck = result.healthCheck;
          // 閉環驗收 7：本次無有效 stage（缺值／未知值）不得渲染成破冰。
          _gameStage = result.gameStage.hasValidStage ? result.gameStage : null;
          _psychology = result.psychology;
          _finalRecommendation = result.recommendation;
          _coachActionHint = result.coachActionHint;
          _reminder = result.reminder;
          _shouldGiveUp = result.shouldGiveUp;
          _decision = result.decision;
          _lastAiResponse = result.rawResponse;
          _resetFeedbackState();
        });
        _session.persistCompletedRun(
          next.toRunMetadata(),
          result,
          analyzedMessageCount: analyzedMessageCount,
          allowArchivedRecordRefresh: _isRefreshingPremiumReplies,
        );
        _syncSubscriptionUsageFromResult(result, showChargeToast: true);
        // 一次性捲到「回覆建議」區頂。只在 live 完成轉場做（hydrate 不做），
        // setState 排定的重建幀之後才量得到新位置。
        _scheduleSnapToReplyZone();
        break;
      case StreamingAnalyzePhase.failedAfterRecommendation:
        setState(() {
          _isAnalyzing = false;
          _followLiveAnalysis = false;
          _streamErrorMessage = next.streamErrorMessage;
          _streamErrorRetriesRemaining = next.retriesRemaining;
          _quotaExceededInfo = next.quotaExceeded;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = next.streamContents;
          _activeAnalysisMessageCount =
              next.analyzedMessageCount ?? next.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.failedBeforeRecommendation:
        final code = next.recommendationPreviewErrorCode;
        final message =
            next.recommendationPreviewErrorMessage ?? '分析暫時失敗，請稍後再試。';
        final liveQuotaInfo = next.quotaExceeded;
        final isQuotaError =
            code == 'DAILY_LIMIT_EXCEEDED' || code == 'MONTHLY_LIMIT_EXCEEDED';
        setState(() {
          _isAnalyzing = false;
          _followLiveAnalysis = false;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = const [];
          _activeAnalysisMessageCount = null;
          if (liveQuotaInfo != null) {
            // Quota 429 升級卡分流（Codex 雙審 r1-P2a）：fresh-start 也渲染
            // QuotaExceededUpgradeCard（剩 N/需 M），不走 generic error 卡。
            _quotaExceededInfo = liveQuotaInfo;
            _resetErrorState();
          } else {
            _applyErrorState(
              message: message,
              action: isQuotaError
                  ? AnalysisErrorAction.upgrade
                  : AnalysisErrorAction.retry,
              origin: _AnalysisErrorOrigin.analysis,
            );
          }
        });
        if (isQuotaError) {
          unawaited(_showPaywall(context));
        }
        break;
      case StreamingAnalyzePhase.idle:
        break;
    }
    _scheduleFollowCurrentAnalysis();
  }

  /// Retry the last interrupted analysis stream. The notifier owns the cached
  /// payload from the most recent `start()` (survives screen remount via
  /// `ref.keepAlive`), so we just delegate. I-P1-b.
  void _retryStreamAnalysis() {
    unawaited(_session.retry());
  }

  /// 優化用戶訊息
  /// 草稿潤飾的唯一計費路徑；DraftPolishSheet 只透過這裡送出。
  /// 成功回 success；被擋下（亂碼／安全／格式無效，皆不扣費）回 blocked
  /// 讓面板把說明留在畫面上；其他失敗或取消回 null（提示已在這裡顯示）。
  Future<DraftPolishOutcome?> _polishDraft(String draftInput) async {
    final draft = draftInput.trim();
    if (draft.isEmpty) return null;

    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) return null;
    final ownerUserId = SupabaseService.currentUser?.id;
    if (ownerUserId == null || ownerUserId.isEmpty) {
      _showFloatingSnackBar('登入狀態已失效，請重新登入後再試。本次不會扣額度。');
      return null;
    }

    try {
      final analysisContext = await ref
          .read(analysisRunPreparerProvider)
          .prepareAuxiliary(conversation: conversation);
      final polishOutcome = await _replyIteration.runPolish(
        ownerUserId: ownerUserId,
        context: analysisContext,
        sessionContext: conversation.sessionContext,
        draft: draft,
        onReadyToSend: () async {
          if (!mounted) return false;
          final consented = await AiDataSharingConsent.ensure(
            context,
            featureLabel: '草稿潤飾',
            consentKey: AiDataSharingConsent.optimizeReplayConsentKey,
            dataDescription: AiDataSharingConsent.optimizeReplayDataDescription,
            purposeText: AiDataSharingConsent.optimizeReplayPurposeText,
          );
          if (!consented || !mounted) return false;

          setState(() {
            _polishRunKey = null;
            _lastAnalysisTelemetry = null;
          });
          return true;
        },
        onTelemetry: _handleAnalysisTelemetry,
      );

      // cancelled：使用者拒絕同意或畫面已離開，什麼都沒送出也沒鑄身分。
      if (polishOutcome == null) return null;
      if (!mounted) return null;

      final pending = polishOutcome.pending;
      final result = polishOutcome.result;
      setState(() {
        _polishRunKey = const Uuid().v4();
      });

      _syncSubscriptionUsageFromResult(
        result,
        showChargeToast: true,
        chargeActionLabel: '潤飾',
      );
      // Only clear the durable replay identity after Flutter has rendered the
      // paid result. If the user leaves before this frame, returning with the
      // same payload replays the server result instead of minting a new charge.
      // 結果現在畫在 DraftPolishSheet（蓋在本頁上的 route）：這裡的
      // isCurrent 檢查會讓清理等到面板關閉後由 build/lifecycle 補做；期間
      // requestId 保留，同一份輸入 replay 拿回同一結果，不重複扣費。
      await _clearOptimizePendingAfterVisibleFrame(pending);
      return DraftPolishOutcome.success(result.optimizedMessage!);
    } on DailyLimitExceededException catch (e) {
      if (!mounted) return null;
      _showFloatingSnackBar(_dailyQuotaExceededMessage(e));
      await _showPaywall(context);
      return null;
    } on MonthlyLimitExceededException catch (e) {
      if (!mounted) return null;
      _showFloatingSnackBar(_monthlyQuotaExceededMessage(e));
      await _showPaywall(context);
      return null;
    } on AnalysisException catch (e) {
      // 身分被伺服器否認時的 reset 由 OptimizeRequestRunner 負責，這裡只顯示文案。
      if (!mounted) return null;
      // 被擋下（亂碼防呆／安全守門與格式無效，皆不扣費）：說明改留在面板
      // 上，snackbar 一閃就過看不懂為什麼沒結果（2026-08-16 Eric 真機回饋）。
      if (e.code == 'OPTIMIZE_MESSAGE_DRAFT_UNREADABLE' ||
          e.code == 'OPTIMIZE_MESSAGE_SAFETY_BLOCKED' ||
          e.code == 'OPTIMIZE_MESSAGE_RESULT_INVALID') {
        return DraftPolishOutcome.blocked(e.message);
      }
      _showFloatingSnackBar(e.message);
      if (e.suggestedAction == AnalysisErrorAction.upgrade) {
        await _showPaywall(context);
      }
      return null;
    } catch (e) {
      if (!mounted) return null;
      _showFloatingSnackBar('訊息優化暫時失敗，請稍後再試。');
      return null;
    }
  }

  Future<void> _openDraftPolishSheet() async {
    await showDraftPolishSheet(
      context,
      draftController: _optimizeController,
      onPolish: _polishDraft,
      onCopy: _copyPolishedDraft,
      onRefine: (text) =>
          _refineReply(originText: text, originCardKey: 'polish'),
    );
  }

  void _copyPolishedDraft(String text) {
    AppHaptics.light();
    Clipboard.setData(ClipboardData(text: text));
    unawaited(_recordAnalysisCopy(cardKey: 'polish', copiedText: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已複製草稿，發出後記得回來回報結果')),
    );
  }

  Future<void> _clearOptimizePendingAfterVisibleFrame(
    OptimizeMessagePendingRequest pending,
  ) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    await _replyIteration.acknowledgePolishPresented(pending);
  }

  /// 「再調一下」：把一則已經產出的回覆就地再修一次，可以連續迭代。
  ///
  /// 每一輪都走 `_optimizeRequestRunner`，與草稿潤飾共用同一條 exactly-once
  /// 帳本。指令有進 fingerprint，所以同一句話的兩種不同指令不會共用同一顆
  /// requestId 而 replay 出上一輪的結果。
  ///
  /// 微調對象一律是**單一則回覆**，不是整組合併後的文字：整組的「短一點」語意
  /// 不清，而且多輪迭代很快就會撞到 server 的 userDraft 長度上限。
  Future<void> _refineReply({
    required String originText,
    required String originCardKey,
  }) async {
    final origin = originText.trim();
    if (origin.isEmpty) return;

    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) return;
    final ownerUserId = SupabaseService.currentUser?.id;
    if (ownerUserId == null || ownerUserId.isEmpty) {
      _showFloatingSnackBar('登入狀態已失效，請重新登入後再試。本次不會扣額度。');
      return;
    }

    final analysisContext = await ref
        .read(analysisRunPreparerProvider)
        .prepareAuxiliary(conversation: conversation);
    if (!mounted) return;

    // 讀失敗就當作沒有草稿：這只是方便用的快取，不能為了它擋住面板。
    final restored = await _replyIteration.restoreRefineDraft(
      ownerUserId: ownerUserId,
      originText: origin,
    );
    if (!mounted) return;

    final sheetResult = await showReplyRefineSheet(
      context,
      originalText: origin,
      restoredText: restored?.refinedText,
      restoredRequestId: restored?.requestId,
      freeRemaining: _replyIteration.refineFreeRemaining,
      onRefine: ({required currentText, required instruction}) async {
        final round = await _replyIteration.runRefineRound(
          ownerUserId: ownerUserId,
          context: analysisContext,
          sessionContext: conversation.sessionContext,
          currentText: currentText,
          instruction: instruction,
          // 多輪漂移錨：永遠帶「這串微調最初的原句」，讓 server 的
          // anchor_action 條款有錨可判——第 N 版不得長出原句沒有的邀約。
          anchorText: origin,
          onReadyToSend: () async {
            if (!mounted) return false;
            return AiDataSharingConsent.ensure(
              context,
              featureLabel: '回覆微調',
              consentKey: AiDataSharingConsent.optimizeReplayConsentKey,
              dataDescription:
                  AiDataSharingConsent.optimizeReplayDataDescription,
              purposeText: AiDataSharingConsent.optimizeReplayPurposeText,
            );
          },
          onTelemetry: _handleAnalysisTelemetry,
        );
        if (round == null) return null;

        _syncSubscriptionUsageFromResult(
          round.result,
          showChargeToast: false,
          chargeActionLabel: '微調',
        );
        // durable 暫存已在 coordinator 內先落地（順序不能反：先存得回來、
        // 才在可見幀後清掉付費身分）；存檔失敗時保留 pending 走 replay。
        if (round.restorable) {
          unawaited(_markRefinePendingAfterVisibleFrame(round.pending));
        }
        return ReplyRefineOutcome(
          refinedText: round.refinedText,
          requestId: round.pending.requestId,
          freeRemaining: round.freeRemaining,
          freeDailyLimit: round.freeDailyLimit,
          chargedQuota: round.chargedQuota,
        );
      },
    );

    if (!mounted || sheetResult == null || !sheetResult.isRefined) return;
    AppHaptics.light();
    await Clipboard.setData(ClipboardData(text: sheetResult.adoptedText));
    unawaited(
      _recordRefineCopy(
        originCardKey: originCardKey,
        requestId: sheetResult.requestId,
        copiedText: sheetResult.adoptedText,
      ),
    );
    if (!mounted) return;
    _showFloatingSnackBar('已複製這個版本，發出後記得回來回報結果');
  }

  /// 微調後複製要記成**獨立事件**，不能落回原卡的 adviceId。
  ///
  /// 原卡的 adviceId 是決定論的（`analyze:對話:runKey:cardKey`），覆寫它污染的
  /// 不只是統計：outcome digest 會回注 coach prompt，教練會以為你送出的是原句。
  /// 事件 key 用 `refine:<原卡 adviceId>:<requestId>`——requestId 是這一輪微調的
  /// 冪等鍵，重複複製同一版不會多記一筆。
  Future<void> _recordRefineCopy({
    required String originCardKey,
    required String? requestId,
    required String copiedText,
  }) async {
    // 沒有穩定的冪等鍵就不記：寧可少一筆樣本，也不要記出無法去重的髒資料。
    final eventId = ReplyIterationCoordinator.refineCopyEventId(
      originAdviceId: _analyzeAdviceId(originCardKey),
      requestId: requestId,
    );
    if (eventId == null) return;
    final conversation = ref.read(conversationProvider(widget.conversationId));
    try {
      await ref.read(coachingOutcomeRecorderProvider).recordAdviceCopied(
            CoachingAdviceContext(
              eventId: eventId,
              partnerId: conversation?.partnerId,
              conversationId: widget.conversationId,
              source: CoachingOutcomeSource.analyze,
              adviceId: eventId,
              // 來源卡別留在 adviceType，不動 outcome schema。
              adviceType: 'refine:$originCardKey',
              suggestedMoveSummary: copiedText,
            ),
          );
    } catch (_) {
      // 記錄失敗不擋複製主流程。
    }
  }

  /// 微調的結果畫在面板裡，而面板是蓋在本頁上的 route，所以不能沿用
  /// `_clearOptimizePendingAfterVisibleFrame` 的 `ModalRoute.isCurrent`
  /// 條件——那個條件在面板開著時恆為 false，付費身分會永遠清不掉。
  Future<void> _markRefinePendingAfterVisibleFrame(
    OptimizeMessagePendingRequest pending,
  ) async {
    // 面板拿到結果後重建的那一幀。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    await _replyIteration.acknowledgeRefinePresented(pending);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final pending = _replyIteration.pendingAwaitingPresentation;
    if (pending == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_clearOptimizePendingAfterVisibleFrame(pending));
      }
    });
  }

  /// 匯出對話紀錄 (含 AI 分析結果)
  void _exportConversation(Conversation conversation) {
    final buffer = StringBuffer();

    // 標題
    buffer.writeln('=== VibeSync 對話分析紀錄 ===');
    buffer.writeln('對象: ${conversation.name}');
    buffer.writeln('匯出時間: ${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln('');

    // 對話內容
    buffer.writeln('--- 對話內容 ---');
    for (final msg in conversation.messages) {
      final sender = msg.isFromMe ? '我' : '她';
      buffer.writeln('$sender: ${msg.content}');
    }
    buffer.writeln('');

    // AI 分析結果
    if (_enthusiasmScore != null) {
      buffer.writeln('--- AI 分析結果 ---');
      final visibleScore = clampVisibleInvestmentScore(_enthusiasmScore!);
      buffer.writeln(
        '對方這次的投入度: $visibleScore/${AppConstants.investmentVisibleMax}',
      );

      if (_gameStage != null) {
        buffer.writeln(
          '目前互動重點: ${_visibleGameStageLabel(conversation)}',
        );
        buffer.writeln('節奏: ${_gameStage!.status.label}');
        buffer.writeln('下一步: ${_gameStage!.nextStep}');
      }

      if (_psychology != null) {
        buffer.writeln('');
        buffer.writeln('她話裡的意思: ${_psychology!.subtext}');
        if (_psychology!.shitTest != null) {
          buffer.writeln('試探偵測: ${_psychology!.shitTest}');
        }
      }

      if (_topicDepth != null) {
        buffer.writeln('話題深度: ${_topicDepth!.current.label}');
        if (_topicDepth!.suggestion.isNotEmpty) {
          buffer.writeln('深度建議: ${_topicDepth!.suggestion}');
        }
      }

      if (_strategy != null) {
        buffer.writeln('');
        buffer.writeln('策略建議: $_strategy');
      }

      buffer.writeln('');
      buffer.writeln('--- 建議回覆 ---');
      if (_replies != null) {
        _replies!.forEach((type, content) {
          final typeLabel = {
                'extend': '延展',
                'resonate': '共鳴',
                'tease': '調情',
                'humor': '幽默',
                'coldRead': '冷讀',
              }[type] ??
              type;
          buffer.writeln('[$typeLabel] $content');
        });
      }

      if (_finalRecommendation != null) {
        buffer.writeln('');
        buffer.writeln('--- AI 推薦 ---');
        buffer.writeln('推薦回覆: ${_finalRecommendation!.content}');
        buffer.writeln('推薦理由: ${_finalRecommendation!.reason}');
        buffer.writeln('互動判斷: ${_finalRecommendation!.psychology}');
      }

      final subscription = ref.read(subscriptionProvider);
      if (subscription.isEssential &&
          _healthCheck != null &&
          _healthCheck!.issues.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln('--- 對話健檢 ---');
        for (final issue in _healthCheck!.issues) {
          buffer.writeln('⚠️ $issue');
        }
        for (final suggestion in _healthCheck!.suggestions) {
          buffer.writeln('💡 $suggestion');
        }
      }
    }

    buffer.writeln('');
    buffer.writeln('=== 紀錄結束 ===');

    // 複製到剪貼簿
    AppHaptics.light();
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('對話紀錄已複製到剪貼簿')),
    );
  }

  /// 提交反饋
  Future<void> _submitFeedback(String rating) async {
    if (_feedbackSubmitted || _isSubmittingFeedback) return;

    _dismissKeyboard();
    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) return;

    // 取得用戶訂閱資訊
    final subscription = ref.read(subscriptionProvider);
    final userTier = subscription.tier;
    final conversationSnippet = _buildFeedbackConversationSnippet(conversation);
    final aiResponse = _buildFeedbackAiContext();
    final usage = _lastAiResponse?['usage'];
    final modelUsed = usage is Map && usage['model'] is String
        ? usage['model'] as String
        : null;

    setState(() {
      _isSubmittingFeedback = true;
    });

    try {
      // 無 timeout 時網路停滯會讓 _isSubmittingFeedback 永遠卡 true、按鈕
      // 無限轉圈；逾時走既有 catch → 「稍後再試」snackbar＋finally 解鎖。
      final response = await Supabase.instance.client.functions.invoke(
        'submit-feedback',
        body: {
          'rating': rating,
          'category': _feedbackCategory,
          'comment': _feedbackCommentController.text.trim().isEmpty
              ? null
              : _feedbackCommentController.text.trim(),
          'conversationSnippet': conversationSnippet,
          'aiResponse': aiResponse,
          'userTier': userTier,
          'modelUsed': modelUsed,
        },
      ).timeout(const Duration(seconds: 20));

      if (!mounted) {
        return;
      }

      if (response.status >= 200 && response.status < 300) {
        setState(() {
          _feedbackSubmitted = true;
          _showFeedbackForm = false;
          _feedbackCategory = null;
          _includeFeedbackContext = false;
        });
        _feedbackCommentController.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(rating == 'positive' ? '謝謝回饋！' : '感謝你的回饋，我們會持續改進！'),
            ),
          );
        }
      } else {
        debugPrint('[Feedback] Server returned status ${response.status}');
        setState(() {
          _feedbackSubmitted = false;
          _showFeedbackForm = rating == 'negative';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('回饋暫時沒有送出，稍後可以再試一次。')),
          );
        }
      }
    } catch (e) {
      debugPrint('[Feedback] Error: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _feedbackSubmitted = false;
        _showFeedbackForm = rating == 'negative';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回饋暫時沒有送出，稍後可以再試一次。')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingFeedback = false;
        });
      }
    }
  }

  // ── AnalysisFeedbackActions（反饋 section 的動作實作）──────────────

  @override
  void submitPositiveFeedback() => unawaited(_submitFeedback('positive'));

  @override
  void openNegativeFeedbackForm() => setState(() => _showFeedbackForm = true);

  @override
  void selectFeedbackCategory(String? category) {
    AppHaptics.light();
    setState(() => _feedbackCategory = category);
  }

  @override
  void setIncludeFeedbackContext(bool include) {
    AppHaptics.tap();
    setState(() => _includeFeedbackContext = include);
  }

  @override
  void submitNegativeFeedback() => unawaited(_submitFeedback('negative'));

  @override
  void dismissKeyboard() => _dismissKeyboard();

  // ── ReplyZoneActions（回覆區 section 的動作實作）─────────────────────

  @override
  void copyRecommendationText(String text, String label) {
    AppHaptics.light();
    Clipboard.setData(ClipboardData(text: text));
    unawaited(_recordAnalysisCopy(cardKey: 'final', copiedText: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label，發出後記得回來回報結果')),
    );
  }

  @override
  void copyStyleReply(String type, String text, String snackBarMessage) {
    unawaited(_recordAnalysisCopy(cardKey: type, copiedText: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$snackBarMessage，發出後記得回來回報結果'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void refineReply(String text, String originCardKey) => unawaited(
        _refineReply(originText: text, originCardKey: originCardKey),
      );

  @override
  void openPaywall() => unawaited(_showPaywall(context));

  @override
  void refreshPremiumReplies() => unawaited(_refreshPremiumReplies());

  /// 回覆區尾端提示的種類；null＝不顯示。顯示條件沿用既有規則：
  /// 有回覆且（Free 用戶／已升級但看舊 Free 結果／付費單一 extend fallback）。
  ReplyZoneNoticeKind? _replyZoneNoticeKind(SubscriptionState subscription) {
    final replies = _replies;
    if (replies == null || replies.isEmpty) return null;
    // 不回／收尾決策下零推銷（規格 §16）。
    if (_decision?.hidesReplyZone ?? false) return null;
    if (subscription.isFreeUser) return ReplyZoneNoticeKind.freeUpgrade;
    if (_analysisNeedsReplyRefresh(subscription)) {
      return ReplyZoneNoticeKind.refreshStale;
    }
    if (replies.length == 1 && replies.containsKey('extend')) {
      return ReplyZoneNoticeKind.premiumDefault;
    }
    return null;
  }

  // ── AnalysisFragmentActions（片段卡的動作實作）──────────────────────

  @override
  void chooseConversationSource() {
    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) return;
    unawaited(_chooseConversationAnalysisSource(conversation));
  }

  @override
  void editFragmentMessage(Message message) {
    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) return;
    unawaited(_editMessage(conversation, message));
  }

  @override
  void swapFragmentMessageSide(Message message) {
    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) return;
    unawaited(_swapMessageSide(conversation, message));
  }

  @override
  void deleteFragmentMessage(Message message) {
    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) return;
    unawaited(_deleteMessage(conversation, message));
  }

  // ── ScreenshotIntakeActions（選圖／辨識區的動作實作）────────────────

  @override
  void selectedImagesChanged(List<Uint8List> images) =>
      _handleSelectedImagesChanged(images);

  @override
  void selectedImageMetricsChanged(List<SelectedImageMetrics> metrics) =>
      _handleSelectedImageMetricsChanged(metrics);

  @override
  void recognizeScreenshots() => unawaited(_recognizeAndAddToConversation());

  @override
  void cancelRecognition() => _cancelRecognize();

  // ── RecognitionDraftActions（辨識結果卡的動作實作）──────────────────

  @override
  void forceReRecognizeLastBatch() => unawaited(_forceReRecognizeLastBatch());

  @override
  void repickScreenshots() => unawaited(_repickScreenshots());

  @override
  void resumeRecognitionImport() => unawaited(_resumeRecognitionImport());

  @override
  void discardRecognitionDraft() => _discardPendingRecognitionDraft();

  void _resetFeedbackState() {
    _feedbackSubmitted = false;
    _showFeedbackForm = false;
    _feedbackCategory = null;
    _includeFeedbackContext = false;
    _isSubmittingFeedback = false;
    _feedbackCommentController.clear();
  }

  String _truncateFeedbackText(String value, int maxLength) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  String? _buildFeedbackConversationSnippet(Conversation conversation) {
    if (!_includeFeedbackContext) {
      return null;
    }

    final messages = conversation.messages;
    final lastMessages =
        messages.length > 6 ? messages.sublist(messages.length - 6) : messages;
    final snippet = lastMessages
        .map((m) => '${m.isFromMe ? "我" : "她"}: ${m.content}')
        .join('\n')
        .trim();

    if (snippet.isEmpty) {
      return null;
    }

    return _truncateFeedbackText(snippet, 1000);
  }

  Map<String, dynamic>? _buildFeedbackAiContext() {
    final payload = <String, dynamic>{
      'schemaVersion': 1,
    };

    if (_enthusiasmScore != null) {
      payload['enthusiasmScore'] = _enthusiasmScore;
    }

    if (_strategy != null && _strategy!.trim().isNotEmpty) {
      payload['strategy'] = _truncateFeedbackText(_strategy!, 300);
    }

    if (_gameStage != null) {
      payload['gameStage'] = _gameStage!.current.name;
      payload['gameStageStatus'] = _gameStage!.status.name;
    }

    if (_topicDepth != null) {
      payload['topicDepth'] = _topicDepth!.current.name;
    }

    final tierUsed = _analysisTierUsed();
    if (tierUsed != null && tierUsed.isNotEmpty) {
      payload['tierUsed'] = tierUsed;
    }

    if (_finalRecommendation != null) {
      payload['finalRecommendation'] = {
        'pick': _finalRecommendation!.pick,
        'content': _truncateFeedbackText(_finalRecommendation!.content, 300),
        'reason': _truncateFeedbackText(_finalRecommendation!.reason, 200),
      };
    }

    return payload.length > 1 ? payload : null;
  }

  String? _analyzeAdviceId(String cardKey) {
    final runKey = cardKey == 'polish' ? _polishRunKey : _analysisRunKey;
    if (runKey == null) return null;
    return 'analyze:${widget.conversationId}:$runKey:$cardKey';
  }

  Future<void> _recordAnalysisCopy({
    required String cardKey,
    required String copiedText,
  }) async {
    final adviceId = _analyzeAdviceId(cardKey);
    if (adviceId == null) return;
    final conversation = ref.read(conversationProvider(widget.conversationId));
    try {
      await ref.read(coachingOutcomeRecorderProvider).recordAdviceCopied(
            CoachingAdviceContext(
              eventId: adviceId,
              partnerId: conversation?.partnerId,
              conversationId: widget.conversationId,
              source: CoachingOutcomeSource.analyze,
              adviceId: adviceId,
              adviceType: cardKey,
              suggestedMoveSummary: copiedText,
            ),
          );
    } catch (_) {
      // 記錄失敗不擋複製主流程。
    }
  }

  Future<void> _recordAnalysisUserAction({
    required String cardKey,
    required String summary,
    required CoachingUserAction action,
  }) async {
    final adviceId = _analyzeAdviceId(cardKey);
    if (adviceId == null) return;
    final conversation = ref.read(conversationProvider(widget.conversationId));
    try {
      await ref.read(coachingOutcomeRecorderProvider).recordAdviceUserAction(
            advice: CoachingAdviceContext(
              eventId: adviceId,
              partnerId: conversation?.partnerId,
              conversationId: widget.conversationId,
              source: CoachingOutcomeSource.analyze,
              adviceId: adviceId,
              adviceType: cardKey,
              suggestedMoveSummary: summary,
            ),
            userAction: action,
            outcome: coachingOutcomeForUserAction(action),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已記下「${coachingUserActionLabel(action)}」，不扣額度。')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暫時記不起來，晚點再試一次。')),
      );
    }
  }

  Future<void> _recordAnalysisReaction({
    required String cardKey,
    required CoachingOutcomeSignal signal,
  }) async {
    final adviceId = _analyzeAdviceId(cardKey);
    if (adviceId == null) return;
    try {
      final updated = await ref
          .read(coachingOutcomeRecorderProvider)
          .recordAdviceReaction(eventId: adviceId, outcome: signal);
      if (updated == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已記下「${coachingOutcomeSignalLabel(signal)}」，不扣額度。')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暫時記不起來，晚點再試一次。')),
      );
    }
  }

  Widget _buildAnalysisOutcomeBar({required String cardKey, String? label}) {
    final adviceId = _analyzeAdviceId(cardKey);
    if (adviceId == null) return const SizedBox.shrink();
    final event = ref.watch(coachingOutcomeEventProvider(adviceId));
    if (event == null) return const SizedBox.shrink(); // 沒複製過不浮出
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: CoachingOutcomeFollowUpBar(
        event: event,
        label: label,
        onUserActionSelected: (action) => _recordAnalysisUserAction(
          cardKey: cardKey,
          summary: event.suggestedMoveSummary,
          action: action,
        ),
        onOutcomeSelected: (signal) => _recordAnalysisReaction(
          cardKey: cardKey,
          signal: signal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final replyZoneCards = ReplyZoneCards(
      recommendation: _finalRecommendation,
      replies: _replies,
      replyOptions: _replyOptions,
    );
    _syncReplyZoneEntrance(hasContent: replyZoneCards.hasContent);
    final optimizePending = _replyIteration.pendingAwaitingPresentation;
    if (optimizePending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_clearOptimizePendingAfterVisibleFrame(optimizePending));
        }
      });
    }
    // Mirror streaming analyze transitions onto local setState fields so the
    // legacy render tree (which reads _enthusiasmScore, _isAnalyzing, etc.)
    // keeps working without a screen-wide rewrite. See Phase 3 plan §Task 3.4.
    ref.listen<StreamingAnalysisState>(
      streamingAnalyzeProvider(widget.conversationId),
      _onStreamingAnalyzeStateChanged,
    );
    final conversation = ref.watch(conversationProvider(widget.conversationId));
    final subscription = ref.watch(subscriptionProvider);

    if (conversation == null) {
      return BrandScaffold(
        title: '對話',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _cleanupAndGoBack,
        ),
        body: Stack(
          children: [
            const Center(child: Text('找不到對話')),
            _buildRoutePopScopeRegistration(),
          ],
        ),
      );
    }

    final analysisFragmentMessages = _analysisFragmentMessages(conversation);
    final conversationSource = _conversationAnalysisSource(conversation);
    final isPendingAnalysisFragment =
        _isShowingPendingAnalysisFragment(conversation);
    final hasCompletedAnalysisEvidence =
        AnalysisFragmentPolicy.hasCompletedAnalysis(conversation) ||
            _enthusiasmScore != null;
    final isCompletedAnalysisFragment =
        !isPendingAnalysisFragment && hasCompletedAnalysisEvidence;

    final hasMutableFragmentMessage = analysisFragmentMessages.any(
      (message) => _canMutateMessage(conversation, message),
    );
    if (hasMutableFragmentMessage &&
        conversation.messages.length > _coachMarkLastSeenMessageCount) {
      _coachMarkLastSeenMessageCount = conversation.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _maybeShowEditMessageCoachMark(partnerId: conversation.partnerId),
          );
        }
      });
    }

    final showInitialScreenshotSetup = !hasCompletedAnalysisEvidence &&
        !_isAnalyzing &&
        _errorMessage == null &&
        _streamErrorMessage == null;
    final isScreenshotOnlyEmptyState =
        showInitialScreenshotSetup && conversation.messages.isEmpty;
    final showFloatingAnalysisAction = showInitialScreenshotSetup &&
        analysisFragmentMessages.isNotEmpty &&
        _selectedImages.isEmpty;
    // 空白新片段（對標示意稿 2026-08-14）：整頁走深色平鋪，不再用白卡框住。
    final isEmptyFragmentSetup =
        isScreenshotOnlyEmptyState && analysisFragmentMessages.isEmpty;
    final showStreamInterruptedAction = !_isAnalyzing &&
        _enthusiasmScore == null &&
        _streamErrorMessage != null;

    return BrandScaffold(
      // body 自帶 SafeArea（見下方），故關掉鷹架的外層 SafeArea 避免雙層巢套。
      safeArea: false,
      resizeToAvoidBottomInset: true,
      floatingActionButton: buildAnalysisFloatingOverlay(
        showStartAction: showFloatingAnalysisAction,
        isAnalyzing: _isAnalyzing,
        analysisCompleted: _enthusiasmScore != null,
        onStart: (_isAnalyzing || _isRecognizing) ? null : _runAnalysis,
        onFollowProgress: _jumpToCurrentAnalysis,
        isFollowing: _followLiveAnalysis,
        streamInterrupted: showStreamInterruptedAction,
      ),
      floatingActionButtonLocation: showFloatingAnalysisAction
          ? const AnalysisSideCenterFabLocation()
          : FloatingActionButtonLocation.endFloat,
      title: conversation.name,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _cleanupAndGoBack,
      ),
      actions: [
        AnalysisRecordsEntryButton(
          key: const ValueKey('analysis-records-entry'),
          archivedCount: _archivedAnalysisRecordCountFor(conversation),
          onPressed: () => _openPartnerAnalysisRecords(conversation),
        ),
        PopupMenuButton<_AnalysisAppBarAction>(
          tooltip: '更多',
          onSelected: (action) {
            switch (action) {
              case _AnalysisAppBarAction.profile:
                _clearAnalysisSnackBarsBeforePush();
                context.push('/profile/${widget.conversationId}');
                break;
              case _AnalysisAppBarAction.export:
                _exportConversation(conversation);
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _AnalysisAppBarAction.profile,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_outline),
                title: Text('對方檔案'),
              ),
            ),
            PopupMenuItem(
              value: _AnalysisAppBarAction.export,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.share_outlined),
                title: Text('匯出對話紀錄'),
              ),
            ),
          ],
        ),
        if (_isAnalyzing || _isRefreshingPremiumReplies)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
      body: SafeArea(
        // RWD: 限制最大寬度，大螢幕置中顯示
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                _buildRoutePopScopeRegistration(),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    // 追蹤使用者拖動狀態，給分析完成的一次性自動捲動判斷用
                    //（拖動中不搶捲）。dragDetails != null 才算手指拖動，
                    // 程式的 animateTo 不會誤判。
                    onNotification: (notification) {
                      if (notification is ScrollStartNotification) {
                        _userDragInProgress = notification.dragDetails != null;
                      } else if (notification is ScrollUpdateNotification) {
                        if (notification.dragDetails != null) {
                          _userDragInProgress = true;
                        }
                      } else if (notification is ScrollEndNotification) {
                        _userDragInProgress = false;
                      }
                      return false;
                    },
                    child: _AnalysisScrollView(
                      onUserScrollTowardStart: _stopFollowingForUserScroll,
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      // 移除 physics 設定，使用平台預設（與第一頁一致）
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnalysisFragmentCard(
                            isEmptyFragmentSetup: isEmptyFragmentSetup,
                            isPendingFragment: isPendingAnalysisFragment,
                            isCompletedFragment: isCompletedAnalysisFragment,
                            showRecordRepairWarning:
                                _persistence.recordNeedsRepair,
                            isScreenshotOnlyEmptyState:
                                isScreenshotOnlyEmptyState,
                            showEmptyState: analysisFragmentMessages.isEmpty &&
                                !(isEmptyFragmentSetup &&
                                    _selectedImages.isNotEmpty),
                            messages: [
                              for (final message in analysisFragmentMessages)
                                FragmentMessageItem(
                                  message: message,
                                  mutable: !_isAnalyzing &&
                                      _canMutateMessage(conversation, message),
                                ),
                            ],
                            sourceLabel: conversationSource == null
                                ? '來源未設定'
                                : '來源：$conversationSource',
                            sourceEditable:
                                _persistence.recordOwnerFor(conversation) !=
                                        null &&
                                    !_isAnalyzing &&
                                    _persistence.inFlightCount == 0,
                            actions: this,
                          ),

                          const SizedBox(height: 24),

                          if (_isRefreshingPremiumReplies) ...[
                            const PremiumRefreshBanner(),
                            const SizedBox(height: 16),
                          ],

                          // Error message
                          if (_errorMessage != null) ...[
                            AnalysisErrorCard(
                              message: _errorMessage!,
                              guidance: _errorGuidance,
                              primaryActionLabel: _errorAction == null
                                  ? null
                                  : _primaryErrorActionLabel(_errorAction!),
                              secondaryActionLabel:
                                  _secondaryErrorActionLabel(),
                              showSecondaryAction:
                                  _shouldShowSecondaryErrorAction(),
                              showForceReRecognize: _canForceReRecognize &&
                                  _errorOrigin ==
                                      _AnalysisErrorOrigin.recognition,
                              busy: _isAnalyzing || _isRecognizing,
                              onPrimaryAction: () =>
                                  _handleErrorAction(_errorAction!),
                              onForceReRecognize: _forceReRecognizeLastBatch,
                              onDismiss: () => setState(_resetErrorState),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // 選圖／辨識區在空片段出現；片段確認後收掉，但
                          // 「重新選圖」把新批塞進 _selectedImages 時要重新
                          // 展開，讓使用者增刪縮圖後自己按「辨識並取代」。
                          if (isEmptyFragmentSetup ||
                              _selectedImages.isNotEmpty) ...[
                            ScreenshotIntakeSection(
                              isEmptyFragmentSetup: isEmptyFragmentSetup,
                              selectedImages: _selectedImages,
                              isRecognizing: _isRecognizing,
                              recognizeButtonLabel: _recognizeButtonLabel,
                              showRecognizeDiagnostics:
                                  _showTelemetryDiagnostics && _isRecognizing,
                              recognizeStageLabel:
                                  _recognizeStageLabel(_recognizeStage),
                              recognizeElapsedSeconds: _recognizeElapsedSeconds,
                              totalOriginalImageBytes: _totalOriginalImageBytes,
                              totalCompressedImageBytes:
                                  _totalCompressedImageBytes,
                              lastRecognizeTelemetry: _lastRecognizeTelemetry,
                              actions: this,
                            ),
                            const SizedBox(height: 24),
                          ],

                          // 截圖識別結果
                          if (_showTelemetryDiagnostics &&
                              _lastRecognizeTelemetry != null &&
                              !_isRecognizing) ...[
                            OcrTelemetryPanel(
                              telemetry: _lastRecognizeTelemetry!,
                              guardrails: _telemetryGuardrailChips(
                                _lastRecognizeTelemetry!,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_showTelemetryDiagnostics &&
                              _lastAnalysisTelemetry != null &&
                              !_isAnalyzing) ...[
                            AnalysisTelemetryPanel(
                              telemetry: _lastAnalysisTelemetry!,
                              guardrails: _telemetryGuardrailChips(
                                _lastAnalysisTelemetry!,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // 這張「已讀取 N 則…尚未開始分析」辨識預覽卡只在分析真正
                          // 尚未開始時出現：分析中（_isAnalyzing）或已完成
                          // （_enthusiasmScore != null）都必須隱藏，否則會殘留誤導
                          // 的「尚未開始分析」提示。重新讀圖會清空 _enthusiasmScore
                          // （見 _recognizeAndAddToConversation），卡片即正確重現。
                          if (!_isAnalyzing &&
                              _enthusiasmScore == null &&
                              _recognizedConversation != null &&
                              _recognizedConversation!.messageCount > 0) ...[
                            RecognizedConversationCard(
                              recognized: _recognizedConversation!,
                              warningMessage: _recognizedWarningMessage,
                              fromCache: _recognitionFromCache,
                              canForceReRecognize: _canForceReRecognize,
                              hasPendingImport: _hasPendingRecognitionImport,
                              isRecognizing: _isRecognizing,
                              actions: this,
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_enthusiasmScore != null) ...[
                            // Phase 1c：後端 V2 決策說不回時，決策卡是唯一
                            // 主卡；放棄橫幅／教練行動卡只服務 v1 或 send。
                            if (_decision != null && !_decision!.isSend) ...[
                              AnalysisDecisionCard(
                                decision: _decision!,
                                onCopyClosingMessage:
                                    _decision!.sendableClosingMessage == null
                                        ? null
                                        : () => copyRecommendationText(
                                              _decision!
                                                  .sendableClosingMessage!,
                                              '已複製收尾句',
                                            ),
                              ),
                              const SizedBox(height: 16),
                            ] else if (_shouldGiveUp) ...[
                              const GiveUpAdviceBanner(),
                              const SizedBox(height: 16),
                            ] else if (_gameStage != null &&
                                _finalRecommendation != null) ...[
                              Builder(
                                builder: (context) {
                                  final conversation = ref.watch(
                                      conversationProvider(
                                          widget.conversationId));
                                  final partnerId = conversation?.partnerId;
                                  final flagged = partnerId != null
                                      ? ref
                                          .watch(dataQualityFlagProvider(
                                              partnerId))
                                          .isFlagged
                                      : false;
                                  final practiceGoals = partnerId != null
                                      ? ref
                                          .watch(
                                              effectiveStyleProvider(partnerId))
                                          .practiceGoals
                                      : const <PracticeGoal>[];
                                  final stuckPoints = partnerId != null
                                      ? ref
                                          .watch(
                                              effectiveStyleProvider(partnerId))
                                          .stuckPoints
                                      : const <StuckPoint>[];

                                  final cardData = CoachActionPolicy.evaluate(
                                    heatScore: _enthusiasmScore!,
                                    gameStage: _gameStage!,
                                    finalRecommendation: _finalRecommendation!,
                                    messages: conversation?.messages ??
                                        const <Message>[],
                                    practiceGoals: practiceGoals,
                                    stuckPoints: stuckPoints,
                                    isDataQualityFlagged: flagged,
                                    coachActionHint: _coachActionHint,
                                    psychology: _psychology,
                                  );

                                  return CoachActionCard(
                                    data: cardData,
                                    onLearningLinkTap: (target) {
                                      _clearAnalysisSnackBarsBeforePush();
                                      context.push(
                                        ebookChapterRoute(
                                          target.bookId,
                                          target.chapterId,
                                          entryId: target.entryId,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],

                          // 回覆區合併（Bruce dogfood 2026-08-08 拍板）：
                          // AI 推薦回覆是橫滑卡組第一張，右滑接其他風格；
                          // 回覆不再藏在詳細分析折疊裡。
                          if (replyZoneCards.hasContent &&
                              !(_decision?.hidesReplyZone ?? false))
                            ReplyZoneSection(
                              cards: replyZoneCards,
                              entrance: _replyZoneEntrance,
                              anchorKey: _replyZoneSectionKey,
                              actions: this,
                              noticeKind: _replyZoneNoticeKind(subscription),
                              noticeBusy:
                                  _isAnalyzing || _isRefreshingPremiumReplies,
                              outcomeBars: [
                                if (replyZoneCards.showRecommended)
                                  _buildAnalysisOutcomeBar(
                                    cardKey: 'final',
                                    label: 'AI 推薦回覆',
                                  ),
                                for (final type
                                    in replyZoneCards.presentStyleTypes)
                                  _buildAnalysisOutcomeBar(
                                    cardKey: type,
                                    label: ReplyStyleCard.labels[type] ?? type,
                                  ),
                              ],
                            ),

                          if (_enthusiasmScore != null) ...[
                            // 實扣顯示常駐行（smoke P2 fix 2026-06-11）：
                            // 隨快照持久化，回看也顯示；SnackBar 保留即時感知。
                            AnalysisUsageSummaryLine(
                              usage: _lastAiResponse?['usage'],
                            ),
                          ],

                          // 問教練上移到詳細分析之前（2026-08-09 回覆區滿版批）：
                          // 完成後首屏留給「下一步＋回覆建議」。2026-08-15 拍板：
                          // 內嵌 CoachSurface 退場，改 CTA 卡直達 Sydney 視窗
                          // （conversation scope＋分析快照隨行）。
                          if (_enthusiasmScore != null &&
                              _gameStage != null &&
                              _finalRecommendation != null) ...[
                            CoachCtaCard(
                              buttonKey: const Key('analysis_coach_cta'),
                              onTap: _openCoachQuestion,
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_enthusiasmScore != null) ...[
                            DetailedAnalysisToggleCard(
                              expanded: _showDetailedAnalysis,
                              onToggle: () => setState(
                                () => _showDetailedAnalysis =
                                    !_showDetailedAnalysis,
                              ),
                              enthusiasmScore: _enthusiasmScore,
                              // 伴侶的 opening 可見語意固定為「重新連線」
                              // （閉環規則 5），不是退回陌生人。
                              stageLabel: _visibleGameStageLabel(conversation),
                              hasRadar: _dimensionScores != null,
                            ),
                            if (_showDetailedAnalysis)
                              DetailedAnalysisContent(
                                enthusiasmScore: _enthusiasmScore!,
                                dimensionScores: _dimensionScores,
                                isPremium: subscription.isPremium,
                                isEssential: subscription.isEssential,
                                gameStage: _gameStage,
                                psychology: _psychology,
                                strategy: _strategy,
                                topicDepth: _topicDepth,
                                healthCheck: _healthCheck,
                                reconnectWording:
                                    _isCommittedPartner(conversation),
                              ),
                          ],

                          if (_isAnalyzing && _enthusiasmScore == null) ...[
                            Center(
                              child: StreamingAnalysisLoader(
                                label: _streamProgressLabel,
                                detail: _streamProgressDetail,
                              ),
                            ),
                          ],

                          if ((_isAnalyzing || _streamErrorMessage != null) &&
                              _streamContents.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            StreamingContentCard(
                              progressLabel: _streamProgressLabel,
                              items: _streamContentItems,
                            ),
                          ],

                          // gate 含 _quotaExceededInfo：fresh-start quota 429
                          // （failedBeforeRecommendation）只設 quota state、
                          // 不設 _streamErrorMessage（Codex 雙審 r1-P2a）。
                          if (_streamErrorMessage != null ||
                              _quotaExceededInfo != null) ...[
                            const SizedBox(height: 12),
                            // Quota 429 分流：額度不足不是技術失敗，渲染升級卡
                            // 而非「無法再重試」（smoke P1 fix 2026-06-11）。
                            if (_quotaExceededInfo != null)
                              QuotaExceededUpgradeCard(
                                isMonthly: _quotaExceededInfo!.isMonthly,
                                remaining: _quotaExceededInfo!.remaining,
                                quotaNeeded: _quotaExceededInfo!.quotaNeeded,
                                onViewPlans: () => _showPaywall(context),
                              )
                            else
                              StreamingAnalysisRetryCard(
                                retriesRemaining: _streamErrorRetriesRemaining,
                                errorMessage: _streamErrorMessage,
                                onRetry: _streamErrorRetriesRemaining > 0
                                    ? _retryStreamAnalysis
                                    : null,
                              ),
                          ],

                          if (_isAnalyzing ||
                              _streamErrorMessage != null ||
                              _quotaExceededInfo != null)
                            SizedBox(
                              key: _analysisProgressEndKey,
                              height: 1,
                            ),

                          // 草稿潤飾：獨立面板入口（2026-08-16 Bruce 回饋，
                          // 從收合卡升級成整頁式）。判斷/策略仍交給 Coach 1:1。
                          if (_enthusiasmScore != null) ...[
                            const SizedBox(height: 24),
                            DraftPolishEntryCard(
                              onOpen: _openDraftPolishSheet,
                              outcomeBar: _buildAnalysisOutcomeBar(
                                cardKey: 'polish',
                                label: '潤飾草稿',
                              ),
                            ),
                          ],

                          // 一致性提醒
                          if (_reminder != null &&
                              _reminder!.trim().isNotEmpty) ...[
                            const SizedBox(height: 16),
                            ReminderBanner(text: _reminder!),
                          ],

                          // 反饋區塊 (有分析結果時顯示)
                          if (_enthusiasmScore != null) ...[
                            const SizedBox(height: 24),
                            AnalysisFeedbackSection(
                              submitted: _feedbackSubmitted,
                              showForm: _showFeedbackForm,
                              isSubmitting: _isSubmittingFeedback,
                              selectedCategory: _feedbackCategory,
                              includeContext: _includeFeedbackContext,
                              commentController: _feedbackCommentController,
                              actions: this,
                            ),
                          ],

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
                // 對話延續輸入區（有分析結果時可收合）
                if (!isScreenshotOnlyEmptyState)
                  _buildCollapsibleMessageInput(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoutePopScopeRegistration() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _cleanupAndGoBack();
      },
      child: const SizedBox.shrink(),
    );
  }

  /// 每次 build 開頭呼叫：回覆區內容 false→true 的那次 build 播一次進場，
  /// 內容歸零（新一輪分析）後解鎖重播。reduced-motion 直接跳到終值。
  void _syncReplyZoneEntrance({required bool hasContent}) {
    if (!hasContent) {
      _replyZonePlayed = false;
      return;
    }
    if (_replyZonePlayed) return;
    _replyZonePlayed = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _replyZoneEntrance.value = 1;
    } else {
      _replyZoneEntrance.forward(from: 0);
    }
  }

  Widget _buildCollapsibleMessageInput() {
    if (_isAnalyzing) {
      return const SizedBox.shrink();
    }

    final conversation = ref.read(conversationProvider(widget.conversationId));
    final hasCompletedAnalysisEvidence = conversation != null &&
        AnalysisFragmentPolicy.hasCompletedAnalysis(conversation);

    // 待分析片段的內容在前一頁一次建立；OCR 重新選圖也只會整批
    // 取代。這裡不再提供逐則追加入口，避免把零散聊天拼成逐字稿。
    if (_enthusiasmScore == null && !hasCompletedAnalysisEvidence) {
      return const SizedBox.shrink();
    }

    return ConversationContinuationBar(
      onAskCoach: _openCoachQuestion,
      onNewFragment: _openNewConversationSheet,
    );
  }
}

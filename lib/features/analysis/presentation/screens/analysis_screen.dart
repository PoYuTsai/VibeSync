// ignore_for_file: dead_code, unchecked_use_of_nullable_value

// lib/features/analysis/presentation/screens/analysis_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/message_calculator.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/analysis_preview_dialog.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../../shared/widgets/game_stage_indicator.dart';
import '../../../../shared/widgets/dimension_radar_chart.dart';
import '../../../../shared/widgets/coach_action_card.dart';
import '../../../../shared/widgets/score_hero_card.dart';
import '../../../coach_chat/data/services/coach_chat_api_service.dart';
import '../../../coach_chat/presentation/widgets/coach_chat_card.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/data/providers/conversation_write_controller.dart';
import '../../data/providers/analysis_providers.dart';
import '../../../conversation/data/services/memory_service.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/conversation_summary.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../../conversation/presentation/widgets/message_bubble.dart';
import '../../../conversation/presentation/widgets/new_conversation_sheet.dart';
import '../../data/notifiers/streaming_analyze_notifier.dart';
import '../../data/services/ocr_recognition_cache_service.dart';
import '../../data/services/analysis_hint_service.dart';
import '../../data/services/analysis_service.dart';
import '../../data/services/analysis_telemetry_guardrail_helper.dart';
import '../../domain/coach/coach_action_policy.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/game_stage.dart';
import '../../domain/services/screenshot_recognition_helper.dart';
import '../widgets/reply_style_card.dart';
import '../widgets/screenshot_added_feedback_card.dart';
import '../widgets/screenshot_recognition_dialog.dart';
import '../widgets/analysis_usage_summary_line.dart';
import '../widgets/streaming_analysis_loading_widgets.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../subscription/domain/services/subscription_tier_helper.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../../user_profile/data/providers/partner_style_providers.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';
import '../../../user_profile/domain/entities/user_profile.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  /// `/conversation/:id?coachPrefill=` 的 query param 名。路由（routes.dart）
  /// 與入口（作戰板 nextStep 節點）共用此常數，避免兩端字串走鐘。
  static const coachPrefillQueryParam = 'coachPrefill';

  final String conversationId;

  /// 進頁後捲到 Coach 1:1 並把這句預填進輸入框（作戰板 nextStep 節點入口，
  /// `/conversation/:id?coachPrefill=`）。只預填、絕不 auto-send（quota 安全
  /// 硬規則）；卡片渲染條件不滿足（無已還原分析）時安靜 no-op。
  final String? coachPrefillQuestion;

  const AnalysisScreen({
    super.key,
    required this.conversationId,
    this.coachPrefillQuestion,
  });

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

enum _AnalysisErrorOrigin {
  analysis,
  recognition,
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen>
    with WidgetsBindingObserver {
  final MemoryService _memoryService = MemoryService();
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

  // 反饋相關
  bool _feedbackSubmitted = false;
  bool _showFeedbackForm = false;
  bool _isSubmittingFeedback = false;
  bool _includeFeedbackContext = false;

  // 訊息優化功能
  bool _showOptimizeInput = false;
  bool _showDetailedAnalysis = false;
  bool _isOptimizing = false;
  final _optimizeController = TextEditingController();
  OptimizedMessage? _optimizedMessage;

  String? _feedbackCategory;
  final _feedbackCommentController = TextEditingController();

  // Streaming analyze mirrors from the notifier. The backend now runs full
  // streaming directly; old rollback preview data stays inside the notifier
  // only for retry compatibility and is not rendered on this screen.
  String? _fullErrorMessage;
  int _fullErrorRetriesRemaining = 0;

  /// Quota 429 分流（smoke P1 fix 2026-06-11）：非 null 時 retry 卡換升級卡。
  /// 生命週期與 _fullErrorMessage 配對——所有清除/賦值點必須同步。
  QuotaExceededInfo? _quotaExceededInfo;
  String? _streamProgressLabel;
  String? _streamProgressDetail;
  List<AnalysisStreamContent> _streamContents = const [];
  int? _activeAnalysisMessageCount;
  Map<String, dynamic>? _lastAiResponse; // 儲存最後的 AI 回應

  // 對話延續功能
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageFocusNode = FocusNode();
  final _messageInputKey = GlobalKey();
  final _coachChatCardKey = GlobalKey();
  bool _showAllMessages = false;
  String? _lastManualAddedMessageId;
  String? _lastManualAddedContent;
  bool? _lastManualAddedIsFromMe;
  String? _lastScreenshotAddedMessageId;
  String? _lastScreenshotAddedPreview;
  bool? _lastScreenshotAddedIsFromMe;
  int? _lastScreenshotAddedCount;
  bool _hasEditedAnalyzedMessage = false;
  int _coachChatFocusRequest = 0;
  // 隨下一次 focus request 一併預填進 Coach 輸入框的問題。每次
  // _openCoachQuestion 都整個覆寫（含 null），避免舊預填黏到後續
  // 純 focus 的請求上。
  String? _coachChatPrefill;

  // 首次看到對話 bubble 時提示用戶長按可編輯。
  OverlayEntry? _editMessageCoachMarkEntry;
  // 上次觸發 coach mark check 時的 messages.length。每次 messages 變多
  // （手動輸入新訊息 / 截圖再次加入）都重新 schedule callback，讓 dogfood
  // 反覆測試每個 action 都看得到提醒。production 由 hint 旗標 gate 成
  // first-run only。
  int _coachMarkLastSeenMessageCount = 0;

  // 截圖 root ScaffoldMessenger reference，避免 dispose 時 context lookup 失敗。
  // 用於 dispose 時清除可能殘留的 SnackBar，避免綠色 banner 跨頁殘留
  // （`Colors.green` 的 OCR 加入 SnackBar duration=7s，用戶離開頁面後 root
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
  static const String _importModeNewConversation =
      ScreenshotRecognitionHelper.importModeNewConversation;
  MeetingContext _screenshotMeetingContext = MeetingContext.datingApp;
  AcquaintanceDuration _screenshotDuration = AcquaintanceDuration.justMet;
  UserGoal _screenshotGoal = UserGoal.dateInvite;
  final _screenshotAnalysisContextNoteController = TextEditingController();
  bool _showScreenshotAnalysisSettings = false;

  // 分析後繼續對話展開狀態
  bool _showContinueConversation = false;

  Future<void> _showPaywall(BuildContext context) async {
    _clearAnalysisSnackBarsBeforePush();
    final unlockedTier = await context.push<String>('/paywall');
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
      _showFloatingSnackBar('已升級完整版，正在幫你刷新完整回覆選項。');
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
    return '目前方案 ${_currentPlanLabel()}：今日額度已用完 (${e.used}/${e.dailyLimit})，明天會自動恢復；升級方案可取得更多額度。';
  }

  String _monthlyQuotaExceededMessage(MonthlyLimitExceededException e) {
    return '目前方案 ${_currentPlanLabel()}：本月額度已用完 (${e.used}/${e.monthlyLimit})，升級方案可取得更多分析額度。';
  }

  Future<void> _handleCoachChatQuotaExceeded() async {
    if (!mounted) return;
    _showFloatingSnackBar('教練額度已用完，帶你去升級方案。');
    await _showPaywall(context);
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
      await ref.read(subscriptionProvider.notifier).refresh();
      if (!mounted) {
        return;
      }

      final refreshedSubscription = ref.read(subscriptionProvider);
      if (!refreshedSubscription.isPremium) {
        await ref.read(subscriptionProvider.notifier).syncWithRevenueCat();
        await ref.read(subscriptionProvider.notifier).refresh();
        if (!mounted) {
          return;
        }
      }

      await _runAnalysis(skipPreview: true, waitForCompletion: true);
      if (!mounted) {
        return;
      }

      final subscription = ref.read(subscriptionProvider);
      if (_analysisNeedsReplyRefresh(subscription)) {
        _showFloatingSnackBar('完整回覆還在同步中，請稍後再試一次。');
      } else {
        _showFloatingSnackBar('完整回覆已更新。');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFloatingSnackBar('完整回覆刷新失敗，請稍後再試。');
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
    if (!subscription.isPremium ||
        _replies == null ||
        _replies!.length != 1 ||
        !_replies!.containsKey('extend')) {
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
        return '保留標題列、左右對話氣泡與外層主訊息；長截圖可拆成 2-3 張分段加入。';
      case AnalysisErrorAction.shortenInput:
        return _selectedImages.isNotEmpty
            ? '每張截圖建議少於 15 則訊息；若內容太長，請拆成多張後再加入。'
            : '可先刪減較舊訊息、縮短草稿，或分成兩次分析。';
      case AnalysisErrorAction.upgrade:
        return '升級後可解鎖更完整的分析能力與較高額度。';
      case AnalysisErrorAction.wait:
        return '今日額度用完後會在隔天重置，或升級方案取得更多額度。';
      case AnalysisErrorAction.addIncomingMessage:
        return _selectedImages.isNotEmpty
            ? '先把截圖辨識成文字並加入目前對話，或在下方補上一則她的回覆後再分析。'
            : '一般分析至少需要一則對方訊息；你也可以先存著，等她回覆後再回來分析。';
      case null:
        return null;
    }
  }

  String _primaryErrorActionLabel(AnalysisErrorAction action) {
    switch (action) {
      case AnalysisErrorAction.retry:
        return _errorOrigin == _AnalysisErrorOrigin.recognition
            ? '重新識別'
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
        return _selectedImages.isNotEmpty ? '先識別截圖' : '補上對方訊息';
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
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openContinueComposer() async {
    if (!mounted) {
      return;
    }
    _dismissKeyboard();
    await Future.delayed(const Duration(milliseconds: 60));

    if (_enthusiasmScore != null && !_showContinueConversation) {
      setState(() {
        _showContinueConversation = true;
      });
      await _scrollToBottom(delay: const Duration(milliseconds: 120));
      return;
    }

    await _scrollToBottom();
  }

  Future<void> _openCoachQuestion({String? prefill}) async {
    if (!mounted) {
      return;
    }
    _dismissKeyboard();
    if (_showContinueConversation) {
      setState(() {
        _showContinueConversation = false;
      });
      await Future.delayed(const Duration(milliseconds: 80));
    }
    final coachContext = _coachChatCardKey.currentContext;
    if (!mounted || coachContext == null || !coachContext.mounted) {
      return;
    }
    await Scrollable.ensureVisible(
      coachContext,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      alignment: 0.08,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _coachChatPrefill = prefill;
      _coachChatFocusRequest++;
    });
  }

  Future<void> _returnToAnalysisOverview() async {
    _dismissKeyboard();
    if (_showContinueConversation) {
      setState(() {
        _showContinueConversation = false;
      });
      await Future.delayed(const Duration(milliseconds: 80));
    }
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openNewConversationSheet() async {
    if (!mounted) {
      return;
    }
    _dismissKeyboard();
    final conversation = ref.read(conversationProvider(widget.conversationId));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewConversationSheet(partnerId: conversation?.partnerId),
    );
  }

  Future<void> _collapseComposerAndShowMessages() async {
    _dismissKeyboard();
    if (_enthusiasmScore != null && _showContinueConversation) {
      setState(() {
        _showContinueConversation = false;
      });
      await Future.delayed(const Duration(milliseconds: 80));
    }

    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
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
        } catch (_) {
          // Ignore sign-out cleanup errors and still route back to login.
        }
        if (!mounted) {
          return;
        }
        context.go('/login');
        return;
      case AnalysisErrorAction.rescreenshot:
        setState(_resetErrorState);
        if (_enthusiasmScore != null) {
          await _openContinueComposer();
        }
        return;
      case AnalysisErrorAction.shortenInput:
        setState(_resetErrorState);
        if (_selectedImages.isNotEmpty || _enthusiasmScore != null) {
          await _openContinueComposer();
        }
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
        await _openContinueComposer();
        return;
    }
  }

  // 記錄已分析的訊息數量，用於判斷是否需要重新分析
  int _lastAnalyzedMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messageFocusNode.addListener(_handleMessageInputFocus);
    _screenshotAnalysisContextNoteController
        .addListener(_refreshScreenshotAnalysisSettingsSummary);
    _restorePersistedAnalysis();
    // If the provider is already mid-analyze on remount, the snapshot we just
    // restored is from a *previous* completed run. Clear the detailed mirrors
    // synchronously so the first frame does not flash the old detailed
    // analysis on top of the new run's streaming loader / retry state.
    // (I-P1-c, Codex round-2).
    final initialState =
        ref.read(streamingAnalyzeProvider(widget.conversationId));
    if (_isStreamingAnalyzePartialPhase(initialState.phase) ||
        _isStreamingAnalyzeResultStaleForCurrentConversation(initialState)) {
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
    // 作戰板 nextStep 入口：首幀後捲到 Coach 1:1 並預填問題。
    // _restorePersistedAnalysis() 是同步的，首幀即含 CoachChatCard；
    // 渲染條件不滿足時 _openCoachQuestion 內部安靜 no-op。
    final prefill = widget.coachPrefillQuestion?.trim();
    if (prefill != null && prefill.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openCoachQuestion(prefill: prefill));
      });
    }
    // 不再自動分析，讓用戶手動點擊
  }

  bool _isStreamingAnalyzePartialPhase(StreamingAnalyzePhase p) {
    switch (p) {
      case StreamingAnalyzePhase.connecting:
      case StreamingAnalyzePhase.recommendationReady:
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
          _fullErrorMessage = null;
          _fullErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = s.streamProgressLabel;
          _streamProgressDetail = s.streamProgressDetail;
          _streamContents = s.streamContents;
          _activeAnalysisMessageCount = s.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.recommendationReady:
      case StreamingAnalyzePhase.streamingReport:
        setState(() {
          _isAnalyzing = true;
          _fullErrorMessage = null;
          _fullErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = s.streamProgressLabel;
          _streamProgressDetail = s.streamProgressDetail;
          _streamContents = s.streamContents;
          _activeAnalysisMessageCount = s.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.done:
        final result = s.full;
        if (result == null) return;
        if (_isStreamingAnalyzeResultStaleForCurrentConversation(s)) {
          setState(() {
            _isAnalyzing = false;
            _fullErrorMessage = '你剛剛補了新的聊天紀錄，這份完整分析先不套用。請按「分析新增內容」更新到最新版。';
            _fullErrorRetriesRemaining = 0;
            _quotaExceededInfo = null;
            _streamContents = const [];
            _activeAnalysisMessageCount = s.conversationMessageCount;
            _clearDetailedAnalysisStateForStreamingAnalyzePartial();
          });
          return;
        }
        setState(() {
          _isAnalyzing = false;
          _fullErrorMessage = null;
          _fullErrorRetriesRemaining = 0;
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
          _gameStage = result.gameStage;
          _psychology = result.psychology;
          _finalRecommendation = result.recommendation;
          _coachActionHint = result.coachActionHint;
          _reminder = result.reminder;
          _shouldGiveUp = result.shouldGiveUp;
          _lastAiResponse = result.rawResponse;
        });
        // Idempotent: only persist + sync usage when the live listener clearly
        // did NOT run for this result (e.g., user navigated away during
        // streamingReport and the done transition arrived off-screen). If the
        // listener already wrote this exact snapshot, the dedup signal below
        // short-circuits to avoid double-writes (I-P2-e/f, Codex round-2).
        _maybePersistAndSyncOnHydrate(result);
        break;
      case StreamingAnalyzePhase.failedAfterRecommendation:
        setState(() {
          _isAnalyzing = false;
          _fullErrorMessage = s.fullErrorMessage;
          _fullErrorRetriesRemaining = s.retriesRemaining;
          _quotaExceededInfo = s.quotaExceeded;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = s.streamContents;
          _activeAnalysisMessageCount = s.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.failedBeforeRecommendation:
        final isQuotaError =
            s.recommendationPreviewErrorCode == 'DAILY_LIMIT_EXCEEDED' ||
                s.recommendationPreviewErrorCode == 'MONTHLY_LIMIT_EXCEEDED';
        setState(() {
          _isAnalyzing = false;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = const [];
          _activeAnalysisMessageCount = null;
          _applyErrorState(
            message: s.recommendationPreviewErrorMessage ?? '分析暫時失敗，請稍後再試。',
            action: isQuotaError
                ? AnalysisErrorAction.upgrade
                : AnalysisErrorAction.retry,
            origin: _AnalysisErrorOrigin.analysis,
          );
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
  /// signal: `conv.lastAnalyzedMessageCount == conv.messages.length` AND
  /// `conv.lastAnalysisSnapshotJson == jsonEncode(result.rawResponse)`. When
  /// the signal matches, the listener path already wrote this exact snapshot
  /// and re-running would be a wasted Hive write + a redundant subscription
  /// sync (I-P2-e/f, Codex round-2).
  ///
  /// Required for the off-screen completion path: user starts analyze, leaves
  /// the screen mid-`streamingReport`, the notifier transitions to `done`
  /// while the listener is unmounted; on return the screen sees `done`
  /// but the snapshot + usage were never written.
  void _maybePersistAndSyncOnHydrate(AnalysisResult result) {
    final repository = ref.read(conversationRepositoryProvider);
    final conv = repository.getConversation(widget.conversationId);
    if (conv == null) return;

    final encoded = result.rawResponse == null || result.rawResponse!.isEmpty
        ? null
        : jsonEncode(result.rawResponse);
    final alreadyPersisted =
        conv.lastAnalyzedMessageCount == conv.messages.length &&
            conv.lastAnalysisSnapshotJson == encoded;
    if (alreadyPersisted) {
      return;
    }

    if (mounted) {
      setState(() {
        _lastAnalyzedMessageCount = conv.messages.length;
      });
    }
    _persistLatestAnalysisSnapshot(result).catchError((_) {
      // Same fire-and-forget contract as the listener path — Hive failures in
      // tests must not surface as unhandled futures.
    });
    _syncSubscriptionUsageFromResult(result);
  }

  /// Wipe the local mirrors of a *previous* completed analysis so the render
  /// tree shows only the live full-streaming state during a fresh run.
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
    _lastAiResponse = null;
    _showDetailedAnalysis = false;
    _resetFeedbackState();
  }

  Widget _buildStreamingContentCard() {
    final contents = _streamContents;
    if (contents.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.backgroundGradientMid,
            Color(0xFF3A185B),
            Color(0xFF612C65),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.24),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryLight, AppColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '完整分析即時整理中',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_streamProgressLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _streamProgressLabel!,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.78),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < contents.length; i++) ...[
            _buildStreamingContentItem(
              contents[i],
              isLatest: i == contents.length - 1,
            ),
            if (i != contents.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildStreamingContentItem(
    AnalysisStreamContent content, {
    required bool isLatest,
  }) {
    final accent = isLatest ? AppColors.bokehYellow : AppColors.primaryLight;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isLatest ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: isLatest ? 0.32 : 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _streamContentIcon(content.kind),
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.title,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content.body,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.84),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (_messageFocusNode.hasFocus) {
      _scheduleMessageInputIntoView();
    }
  }

  void _handleMessageInputFocus() {
    if (mounted) {
      setState(() {});
    }
    if (!_messageFocusNode.hasFocus) {
      return;
    }
    _scheduleMessageInputIntoView();
  }

  void _scheduleMessageInputIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messageFocusNode.hasFocus) {
        return;
      }
      final context = _messageInputKey.currentContext;
      if (context == null) {
        unawaited(_scrollToBottom());
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    });
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

  int _pendingMessageCount(Conversation conversation) {
    final diff = conversation.messages.length -
        _pendingAnalysisBaselineMessageCount(
          conversation,
        );
    return diff > 0 ? diff : 0;
  }

  bool _isStreamingAnalyzeResultStaleForCurrentConversation(
    StreamingAnalysisState state,
  ) {
    final expectedCount = state.conversationMessageCount;
    if (expectedCount == null) return false;
    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) return false;
    return conversation.messages.length != expectedCount;
  }

  void _showEditedAnalyzedMessageSnackBar() {
    if (!mounted) return;

    final messenger = _scaffoldMessenger ?? ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('已儲存，點重新分析更新結果。'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '重新分析',
          onPressed: () {
            if (_isAnalyzing) return;
            unawaited(_runAnalysis());
          },
        ),
      ),
    );
  }

  void _restorePersistedAnalysis() {
    final repository = ref.read(conversationRepositoryProvider);
    final conversation = repository.getConversation(widget.conversationId);
    if (conversation == null) {
      return;
    }

    _lastAnalyzedMessageCount =
        conversation.lastAnalyzedMessageCount ?? conversation.messages.length;

    final snapshotJson = conversation.lastAnalysisSnapshotJson;
    if (snapshotJson == null || snapshotJson.trim().isEmpty) {
      return;
    }

    try {
      final snapshot = _normalizeJsonMap(jsonDecode(snapshotJson));
      if (snapshot == null) {
        return;
      }

      _applyAnalysisResult(AnalysisResult.fromJson(snapshot));
    } catch (error) {
      _debugLog(
        '[AnalysisScreen] Failed to restore persisted analysis for '
        '${widget.conversationId}: $error',
      );
    }
  }

  Map<String, dynamic>? _normalizeJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return null;
  }

  void _applyAnalysisResult(
    AnalysisResult result, {
    bool resetFeedbackState = true,
  }) {
    _enthusiasmScore = result.enthusiasmScore;
    _dimensionScores = result.dimensionScores;
    _strategy = result.strategy;
    _replies = result.replies;
    _replyOptions = result.replyOptions;
    _topicDepth = result.topicDepth;
    _healthCheck = result.healthCheck;
    _gameStage = result.gameStage;
    _psychology = result.psychology;
    _finalRecommendation = result.recommendation;
    _coachActionHint = result.coachActionHint;
    _reminder = result.reminder;
    _shouldGiveUp = result.shouldGiveUp;
    _lastAiResponse = result.rawResponse;
    _showDetailedAnalysis = false;

    if (resetFeedbackState) {
      _resetFeedbackState();
    }
  }

  Future<void> _persistLatestAnalysisSnapshot(
    AnalysisResult result,
  ) async {
    final repository = ref.read(conversationRepositoryProvider);
    final conv = repository.getConversation(widget.conversationId);
    if (conv == null) {
      return;
    }

    conv.lastEnthusiasmScore = result.enthusiasmScore;
    conv.lastAnalyzedMessageCount = conv.messages.length;
    // ADR #19 規格 #8：char baseline 對應「實際送出的 requestMessages」
    //（notifier 在 start 時計），不是完成時 repository 裡的最新 messages
    //（避免分析中新進訊息造成 baseline 漂移）。
    final payloadCharCount = ref
        .read(streamingAnalyzeProvider(widget.conversationId).notifier)
        .lastPayloadCharCount;
    if (payloadCharCount != null) {
      conv.lastAnalyzedCharCount = payloadCharCount;
    }
    conv.currentGameStage = result.gameStage.current.name;
    conv.lastAnalysisSnapshotJson =
        result.rawResponse == null || result.rawResponse!.isEmpty
            ? null
            : jsonEncode(result.rawResponse);

    await ref.read(conversationWriteControllerProvider.notifier).save(conv);
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
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _feedbackCommentController.dispose();
    _optimizeController.dispose();
    _screenshotAnalysisContextNoteController
        .removeListener(_refreshScreenshotAnalysisSettingsSummary);
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
      builder: (ctx) => _EditMessageCoachMark(
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

  /// 換邊（她說 ↔ 我說）
  Future<void> _swapMessageSide(
      Conversation conversation, Message message) async {
    final index = conversation.messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;
    final analyzedCount = _effectiveLastAnalyzedMessageCount(conversation);
    final editedAnalyzedMessage = index < analyzedCount;

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
    ref.invalidate(conversationProvider(widget.conversationId));
    setState(() {
      if (_lastManualAddedMessageId == message.id) {
        _lastManualAddedIsFromMe = !message.isFromMe;
      }
      if (_lastScreenshotAddedMessageId == message.id) {
        _lastScreenshotAddedIsFromMe = !message.isFromMe;
      }
      if (editedAnalyzedMessage) {
        _lastAnalyzedMessageCount = analyzedCount;
        _hasEditedAnalyzedMessage = true;
      }
    });
    _showEditedAnalyzedMessageSnackBar();
  }

  /// 編輯訊息文字（供 OCR 錯字現場修正用）
  Future<void> _editMessage(Conversation conversation, Message message) async {
    final controller = TextEditingController(text: message.content);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        surfaceTintColor: Colors.transparent,
        title:
            Text('編輯文字', style: TextStyle(color: AppColors.glassTextPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          minLines: 1,
          onTapOutside: (_) => _dismissKeyboard(),
          cursorColor: AppColors.primary,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.glassTextPrimary,
            height: 1.35,
          ),
          decoration: InputDecoration(
            hintText: '修正這則訊息...',
            hintStyle: TextStyle(color: AppColors.glassTextHint),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child:
                Text('取消', style: TextStyle(color: AppColors.unselectedText)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('儲存'),
          ),
        ],
      ),
    );

    if (edited == null || edited.isEmpty || edited == message.content) {
      return;
    }

    final index = conversation.messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;
    final analyzedCount = _effectiveLastAnalyzedMessageCount(conversation);
    final editedAnalyzedMessage = index < analyzedCount;

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
    ref.invalidate(conversationProvider(widget.conversationId));
    setState(() {
      if (_lastManualAddedMessageId == message.id) {
        _lastManualAddedContent = edited;
        _lastManualAddedIsFromMe = message.isFromMe;
      }
      if (_lastScreenshotAddedMessageId == message.id) {
        _lastScreenshotAddedPreview = edited;
        _lastScreenshotAddedIsFromMe = message.isFromMe;
      }
      if (editedAnalyzedMessage) {
        _lastAnalyzedMessageCount = analyzedCount;
        _hasEditedAnalyzedMessage = true;
      }
    });
    _showEditedAnalyzedMessageSnackBar();
  }

  /// 刪除訊息
  Future<void> _deleteMessage(
      Conversation conversation, Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title:
            Text('刪除訊息', style: TextStyle(color: AppColors.glassTextPrimary)),
        content: Text(
          '確定要刪除這則訊息嗎？',
          style: TextStyle(color: AppColors.glassTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child:
                Text('取消', style: TextStyle(color: AppColors.unselectedText)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    conversation.messages.removeWhere((m) => m.id == message.id);
    await ref
        .read(conversationWriteControllerProvider.notifier)
        .save(conversation);
    ref.invalidate(conversationProvider(widget.conversationId));
    setState(() {
      if (_lastManualAddedMessageId == message.id) {
        _lastManualAddedMessageId = null;
        _lastManualAddedContent = null;
        _lastManualAddedIsFromMe = null;
      }
      if (_lastScreenshotAddedMessageId == message.id) {
        _clearScreenshotAddedFeedback();
      }
    });
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
      _applyErrorState(message: '已取消識別');
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
    switch (stage) {
      case AnalysisProgressStage.preparingPayload:
        return '準備圖片中';
      case AnalysisProgressStage.uploadingRequest:
        return '上傳圖片中';
      case AnalysisProgressStage.awaitingAi:
        return 'AI 辨識中';
    }
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

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) {
      return '--';
    }

    final seconds = duration.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(seconds >= 10 ? 0 : 1)} 秒';
  }

  String get _recognizeButtonLabel {
    if (_isRecognizing) {
      return _recognizeStageLabel(_recognizeStage);
    }

    return '辨識截圖文字 (${_selectedImages.length} 張)';
  }

  void _clearScreenshotAddedFeedback() {
    _lastScreenshotAddedMessageId = null;
    _lastScreenshotAddedPreview = null;
    _lastScreenshotAddedIsFromMe = null;
    _lastScreenshotAddedCount = null;
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
      _clearScreenshotAddedFeedback();
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

  SessionContext _screenshotSessionContextFor(Conversation conversation) {
    final existing = conversation.sessionContext;
    final note = _screenshotAnalysisContextNoteFor(conversation);
    if (existing != null) {
      return SessionContext(
        meetingContext: existing.meetingContext,
        duration: existing.duration,
        goal: existing.goal,
        userStyle: existing.userStyle,
        userInterests: existing.userInterests,
        targetDescription: existing.targetDescription,
        analysisContextNote: note,
      );
    }

    return SessionContext(
      meetingContext: _screenshotMeetingContext,
      duration: _screenshotDuration,
      goal: _screenshotGoal,
      analysisContextNote: note,
    );
  }

  String? _screenshotAnalysisContextNoteFor(Conversation conversation) {
    final typed = _screenshotAnalysisContextNoteController.text.trim();
    if (typed.isNotEmpty) {
      return typed;
    }
    final existing = conversation.sessionContext?.analysisContextNote?.trim();
    return existing == null || existing.isEmpty ? null : existing;
  }

  void _refreshScreenshotAnalysisSettingsSummary() {
    if (mounted) {
      setState(() {});
    }
  }

  String _screenshotMeetingContextLabel(MeetingContext context) {
    switch (context) {
      case MeetingContext.datingApp:
        return '交友軟體';
      case MeetingContext.inPerson:
        return '現實認識';
      case MeetingContext.friendIntro:
        return '朋友介紹';
      case MeetingContext.other:
        return '其他';
      case MeetingContext.committedPartner:
        return '已是伴侶';
    }
  }

  String _screenshotDurationLabel(AcquaintanceDuration duration) {
    switch (duration) {
      case AcquaintanceDuration.justMet:
        return '剛認識';
      case AcquaintanceDuration.fewDays:
        return '幾天';
      case AcquaintanceDuration.fewWeeks:
        return '幾週';
      case AcquaintanceDuration.monthPlus:
        return '一個月以上';
    }
  }

  String _screenshotGoalLabel(UserGoal goal) {
    switch (goal) {
      case UserGoal.dateInvite:
        return '邀約見面';
      case UserGoal.maintainHeat:
        return '維持熱度';
      case UserGoal.justChat:
        return '自然聊天';
    }
  }

  String _screenshotAnalysisSettingsSummary() {
    final parts = [
      _screenshotMeetingContextLabel(_screenshotMeetingContext),
      _screenshotDurationLabel(_screenshotDuration),
      _screenshotGoalLabel(_screenshotGoal),
    ];
    if (_screenshotAnalysisContextNoteController.text.trim().isNotEmpty) {
      parts.insert(0, '已補充背景');
    }
    return parts.join('・');
  }

  Widget _buildScreenshotSettingSection() {
    Text settingLabel(String text) {
      return Text(
        text,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.onBackgroundPrimary,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        InkWell(
          onTap: () => setState(
            () => _showScreenshotAnalysisSettings =
                !_showScreenshotAnalysisSettings,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _showScreenshotAnalysisSettings
                    ? Icons.expand_less
                    : Icons.expand_more,
                color: AppColors.onBackgroundSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '這次分析設定（可不改）',
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _screenshotAnalysisSettingsSummary(),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '不確定可以先跳過；AI 會用預設情境分析。',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
            height: 1.35,
          ),
        ),
        if (_showScreenshotAnalysisSettings) ...[
          const SizedBox(height: 14),
          Text(
            '截圖只看得到對話，看不到你們的關係。這只影響這個對話的分析，不會改對象資料。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          settingLabel('認識情境'),
          const SizedBox(height: 8),
          GlassmorphicSegmentedButton<MeetingContext>(
            segments: MeetingContext.visibleAnalysisOptions
                .map(
                  (value) => GlassSegment(
                    value: value,
                    label: _screenshotMeetingContextLabel(value),
                  ),
                )
                .toList(),
            selected: _screenshotMeetingContext,
            onChanged: (value) =>
                setState(() => _screenshotMeetingContext = value),
          ),
          const SizedBox(height: 14),
          settingLabel('認識多久'),
          const SizedBox(height: 8),
          GlassmorphicSegmentedButton<AcquaintanceDuration>(
            segments: AcquaintanceDuration.values
                .map(
                  (value) => GlassSegment(
                    value: value,
                    label: _screenshotDurationLabel(value),
                  ),
                )
                .toList(),
            selected: _screenshotDuration,
            onChanged: (value) => setState(() => _screenshotDuration = value),
          ),
          const SizedBox(height: 14),
          settingLabel('目前目標'),
          const SizedBox(height: 8),
          GlassmorphicSegmentedButton<UserGoal>(
            segments: UserGoal.values
                .map(
                  (value) => GlassSegment(
                    value: value,
                    label: _screenshotGoalLabel(value),
                  ),
                )
                .toList(),
            selected: _screenshotGoal,
            onChanged: (value) => setState(() => _screenshotGoal = value),
          ),
          const SizedBox(height: 14),
          settingLabel('補充背景（選填）'),
          const SizedBox(height: 8),
          TextField(
            controller: _screenshotAnalysisContextNoteController,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onEditingComplete: _dismissKeyboard,
            onTapOutside: (_) => _dismissKeyboard(),
            decoration: InputDecoration(
              hintText: '沒有可以留空',
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextHint,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.86),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '把 AI 看不到的關係、背景或你的真實狀態補在這裡。只影響這個對話的分析，不會改對象資料。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConversationScreenshotSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '也可以直接上傳新的聊天截圖，先辨識成文字，確認後加入這段對話，再接著分析。',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.glassTextHint,
          ),
        ),
        const SizedBox(height: 8),
        ImagePickerWidget(
          maxImages: 3,
          externalImages: _selectedImages,
          onImagesChanged: _handleSelectedImagesChanged,
          onMetricsChanged: _handleSelectedImageMetricsChanged,
        ),
        _buildScreenshotSettingSection(),
        if (_selectedImages.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_isRecognizing || _isAnalyzing)
                      ? null
                      : _recognizeAndAddToConversation,
                  icon: _isRecognizing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_photo_alternate),
                  label: Text(_recognizeButtonLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.7),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.95),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 強制重新識別按鈕（忽略快取）
              Tooltip(
                message: '忽略快取，重新跑 OCR',
                child: OutlinedButton(
                  onPressed: (_isRecognizing || _isAnalyzing)
                      ? null
                      : () =>
                          _recognizeAndAddToConversation(forceRefresh: true),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 13, horizontal: 12),
                  ),
                  child: const Icon(Icons.refresh_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isRecognizing
                ? '識別中：${_recognizeStageLabel(_recognizeStage)}'
                : '先把截圖識別進目前對話；右邊按鈕可忽略快取重新識別。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.unselectedText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Future<void> _applyRecognitionImport({
    required ScreenshotRecognitionDialogResult dialogResult,
    required RecognizedConversation recognized,
  }) async {
    final repository = ref.read(conversationRepositoryProvider);
    final editedRecognizedMessages = dialogResult.messages;
    final importedMessages = _buildImportedMessages(editedRecognizedMessages);
    final newName = dialogResult.name;
    final meeting = dialogResult.meetingContext;
    final duration = dialogResult.duration;
    final goal = dialogResult.goal;
    final analysisContextNote = dialogResult.analysisContextNote;
    final importMode = dialogResult.importMode;
    final updatedRecognized = recognized.copyWith(
      contactName: newName.isNotEmpty ? newName : recognized.contactName,
      messageCount: editedRecognizedMessages.length,
      messages: editedRecognizedMessages,
    );

    if (importMode == _importModeNewConversation) {
      final controller = ref.read(conversationWriteControllerProvider.notifier);
      // Inherit partnerId from the source conversation so the new "互動紀錄"
      // shows up under the same Partner detail page. Pre-A2 this path
      // created orphan conversations (partnerId=null) which silently
      // disappeared from `conversationsByPartnerProvider(partnerId)`.
      // (Bruce TF feedback 2026-04-28.)
      final sourceConversation =
          repository.getConversation(widget.conversationId);
      final createdConversation = await controller.create(
        name: _resolveImportedConversationName(
          enteredName: newName,
          recognizedName: recognized.contactName,
        ),
        messages: importedMessages,
        partnerId: sourceConversation?.partnerId,
      );

      if (meeting != null && duration != null) {
        createdConversation.sessionContext = SessionContext(
          meetingContext: meeting,
          duration: duration,
          goal: goal ?? UserGoal.dateInvite,
          analysisContextNote: analysisContextNote,
        );
      }
      await controller.save(createdConversation);
      ref.invalidate(conversationProvider(widget.conversationId));

      final messageCount = importedMessages.length;
      if (!mounted || _recognizeCancelled) {
        _debugLog(
            '[Recognize] Ignore post-save UI update after cancel/dispose');
        return;
      }

      setState(() {
        _selectedImages = [];
        _selectedImageMetrics = [];
        _recognizedConversation = updatedRecognized;
        _recognizedWarningMessage = null;
        _hasPendingRecognitionImport = false;
        _clearScreenshotAddedFeedback();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已建立新對話並加入 $messageCount 則訊息'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: '前往新對話',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              context.push('/conversation/${createdConversation.id}');
            },
          ),
        ),
      );
      return;
    }

    final conv = repository.getConversation(widget.conversationId);
    if (conv == null) {
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
    }

    if (newName.isNotEmpty &&
        ScreenshotRecognitionHelper.isPlaceholderConversationName(conv.name)) {
      conv.name = newName;
    }

    if (conv.sessionContext == null && meeting != null && duration != null) {
      conv.sessionContext = SessionContext(
        meetingContext: meeting,
        duration: duration,
        goal: goal ?? UserGoal.dateInvite,
        analysisContextNote: analysisContextNote,
      );
    } else if (conv.sessionContext != null &&
        analysisContextNote != null &&
        analysisContextNote.trim().isNotEmpty) {
      final existing = conv.sessionContext!;
      conv.sessionContext = SessionContext(
        meetingContext: existing.meetingContext,
        duration: existing.duration,
        goal: existing.goal,
        userStyle: existing.userStyle,
        userInterests: existing.userInterests,
        targetDescription: existing.targetDescription,
        analysisContextNote: analysisContextNote.trim(),
      );
    }

    conv.messages.addAll(importedMessages);
    await ref.read(conversationWriteControllerProvider.notifier).save(conv);
    ref.invalidate(conversationProvider(widget.conversationId));

    final messageCount = importedMessages.length;
    final lastImportedMessage = importedMessages.last;
    if (!mounted || _recognizeCancelled) {
      _debugLog('[Recognize] Ignore post-save UI update after cancel/dispose');
      return;
    }
    setState(() {
      _selectedImages = [];
      _selectedImageMetrics = [];
      _recognizedConversation = updatedRecognized;
      _recognizedWarningMessage = null;
      _hasPendingRecognitionImport = false;
      _lastManualAddedMessageId = null;
      _lastManualAddedContent = null;
      _lastManualAddedIsFromMe = null;
      _lastScreenshotAddedMessageId = lastImportedMessage.id;
      _lastScreenshotAddedPreview = lastImportedMessage.content;
      _lastScreenshotAddedIsFromMe = lastImportedMessage.isFromMe;
      _lastScreenshotAddedCount = messageCount;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已加入目前對話，共 $messageCount 則訊息'),
            const SizedBox(height: 4),
            Text(
              '💡 若這段訊息不連貫，建議從首頁開新對話避免「對方檔案」混淆',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 7),
        action: SnackBarAction(
          label: '捲到加入位置',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            if (!_showAllMessages) {
              setState(() => _showAllMessages = true);
            }
            _scrollToBottom(delay: const Duration(milliseconds: 80));
          },
        ),
      ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已保留這次辨識結果，你可以稍後再繼續加入。'),
        ),
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

  Future<void> _addMessage({required bool isFromMe}) async {
    final content = _messageController.text.trim();
    if (content.isEmpty) {
      final hint =
          isFromMe ? '先輸入你要補上的訊息，再點「這句是我說」。' : '先貼上或輸入對方的新回覆，再點「這句是她說」。';
      _showFloatingSnackBar(hint);
      return;
    }

    _dismissKeyboard();
    final repository = ref.read(conversationRepositoryProvider);
    final conversation = repository.getConversation(widget.conversationId);
    if (conversation == null) return;

    // 建立新訊息
    final newMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isFromMe: isFromMe,
      timestamp: DateTime.now(),
    );

    // 更新對話
    conversation.messages.add(newMessage);
    await ref
        .read(conversationWriteControllerProvider.notifier)
        .save(conversation);

    // 清空輸入框
    _messageController.clear();
    setState(() {
      _lastManualAddedMessageId = newMessage.id;
      _lastManualAddedContent = content;
      _lastManualAddedIsFromMe = isFromMe;
      _clearScreenshotAddedFeedback();
    });

    // 補訊息只記錄內容；是否分析由使用者明確點「分析新增內容」決定。

    // 滾動到頂部顯示新分析結果
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  List<Message> _visibleMessagePreview(List<Message> messages) {
    if (_showAllMessages || messages.length <= 5) {
      return messages;
    }
    // Collapsed mode must show the latest messages so a freshly added
    // manual "她說 / 我說" appears immediately in the preview card.
    return messages.skip(messages.length - 5).toList();
  }

  Future<void> _editLastManualAddedMessage() async {
    final messageId = _lastManualAddedMessageId;
    if (messageId == null) return;

    final repository = ref.read(conversationRepositoryProvider);
    final conversation = repository.getConversation(widget.conversationId);
    if (conversation == null) return;

    Message? message;
    for (final candidate in conversation.messages) {
      if (candidate.id == messageId) {
        message = candidate;
        break;
      }
    }
    if (message == null) return;

    await _editMessage(conversation, message);
  }

  Widget _buildManualAddedFeedback() {
    final content = _lastManualAddedContent;
    final isFromMe = _lastManualAddedIsFromMe;
    if (content == null || isFromMe == null) {
      return const SizedBox.shrink();
    }

    final conversation = ref.watch(conversationProvider(widget.conversationId));
    final pendingCount =
        conversation == null ? 1 : _pendingMessageCount(conversation);
    final displayPendingCount = pendingCount > 0 ? pendingCount : 1;
    final countLabel = displayPendingCount > 1
        ? '已補上 $displayPendingCount 則新訊息'
        : '已補上 1 則新訊息';
    final speakerLabel = isFromMe ? '我說' : '她說';
    final isFullWorkingOnOlderMessages = conversation != null &&
        _activeAnalysisMessageCount != null &&
        conversation.messages.length > _activeAnalysisMessageCount!;
    final nextStep = isFromMe
        ? '已記錄你剛剛回覆的內容。等她回覆後，再補上「她說」，我會用最新來回分析下一步。'
        : '已放到上方對話框。按「分析新增內容」後，會開始串流整理下一步與完整分析。';
    final workingNote = isFullWorkingOnOlderMessages
        ? '目前完整分析仍在整理上一版；你補的新訊息會等你按「分析新增內容」後才納入。'
        : null;
    final preview =
        content.length > 36 ? '${content.substring(0, 36)}…' : content;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$countLabel｜最新：$speakerLabel「$preview」',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.glassTextPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            workingNote == null ? nextStep : '$nextStep\n$workingNote',
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: _editLastManualAddedMessage,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('編輯剛剛那則'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              TextButton.icon(
                onPressed: _collapseComposerAndShowMessages,
                icon: const Icon(Icons.keyboard_arrow_up, size: 16),
                label: const Text('看上方對話'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              if (!isFromMe)
                TextButton.icon(
                  onPressed: _isAnalyzing ? null : _runAnalysis,
                  icon: const Icon(Icons.auto_graph, size: 16),
                  label: const Text('分析新增內容'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotAddedFeedback() {
    final count = _lastScreenshotAddedCount;
    final preview = _lastScreenshotAddedPreview;
    final isFromMe = _lastScreenshotAddedIsFromMe;
    if (count == null || preview == null || isFromMe == null) {
      return const SizedBox.shrink();
    }

    return ScreenshotAddedFeedbackCard(
      messageCount: count,
      lastMessageIsFromMe: isFromMe,
      lastMessagePreview: preview,
      isAnalyzing: _isAnalyzing,
      onShowConversation: _collapseComposerAndShowMessages,
      onAnalyze: _runAnalysis,
    );
  }

  Widget _buildManualInputGuide({required bool isContinue}) {
    final title = isContinue ? '接續上一段對話' : '建立這段對話';
    final description = isContinue
        ? '只補新的來回訊息。舊對話會用必要摘要和最近訊息當背景，不用重貼；按分析前會先確認本次額度，已分析過的舊訊息不重複扣。'
        : '照聊天順序一則一則補上，先選這句是誰說的。分析前會先確認本次額度。';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isContinue ? Icons.playlist_add : Icons.chat_bubble_outline,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.glassTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.glassTextSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFloatingSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
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
  }) {
    final usage = result.rawResponse?['usage'];
    if (usage is! Map) {
      return;
    }

    // ADR #19 r3：預覽只報區間，分析後告知 server 實扣則數。
    // 只在分析完成現場顯示（hydration 恢復快照時不顯示）。
    if (showChargeToast) {
      final messagesUsed = usage['messagesUsed'];
      if (messagesUsed is num &&
          messagesUsed > 0 &&
          usage['isTestAccount'] != true) {
        _showFloatingSnackBar('本次分析使用 ${messagesUsed.round()} 則');
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

  List<Message>? _buildMessagesForReplyAnalysis(List<Message> messages) {
    if (messages.isEmpty) return null;

    final lastIncomingIndex =
        messages.lastIndexWhere((message) => !message.isFromMe);
    if (lastIncomingIndex == -1) {
      return null;
    }

    return messages.sublist(0, lastIncomingIndex + 1);
  }

  Future<String?> _buildHistoricalContextSummary(
    Conversation conversation,
  ) async {
    final persistedSummary =
        _memoryService.buildHistoricalSummary(conversation);
    if (persistedSummary != null && persistedSummary.isNotEmpty) {
      return persistedSummary;
    }

    final olderRounds =
        conversation.currentRound - MemoryService.maxRecentRounds;
    if (olderRounds < MemoryService.minRoundsPerSummary) {
      return null;
    }

    final ephemeralSummary = await _memoryService.generateSummary(
      conversation,
      0,
      olderRounds,
    );

    final formattedSummary = _memoryService.formatSummarySegments(
      <ConversationSummary>[ephemeralSummary],
    );

    return formattedSummary.isEmpty ? null : formattedSummary;
  }

  /// Build the per-call partner-context block for `analyze-chat`. Returns
  /// null when the conversation has no partner attached, the partner row is
  /// missing, or the summary builder yields empty (owner-mismatch defense).
  /// Rebuilt every call — partner aggregate must reflect the latest snapshot.
  String? _resolvePartnerSummary(Conversation conversation) {
    return ref.read(partnerContextResolverProvider).resolve(conversation);
  }

  /// Spec 2.5: About Me + per-partner style becomes compact prompt context.
  /// If Spec 3 flags this partner card, partner-specific style is suspended
  /// and only global About Me remains trusted.
  String? _resolveEffectiveStyleContext(Conversation conversation) {
    final global = ref.read(userProfileControllerProvider).valueOrNull;
    final partnerId = conversation.partnerId;
    if (partnerId == null) {
      return ref.read(effectiveStylePromptBuilderProvider).buildForAnalysis(
            global: global,
            partner: null,
            includePartnerOverride: false,
          );
    }

    final includePartnerOverride =
        !ref.read(dataQualityFlagProvider(partnerId)).isFlagged;
    final partner = includePartnerOverride
        ? ref.read(partnerStyleOverrideProvider(partnerId)).valueOrNull
        : null;
    return ref.read(effectiveStylePromptBuilderProvider).buildForAnalysis(
          global: global,
          partner: partner,
          includePartnerOverride: includePartnerOverride,
        );
  }

  Future<({List<Message> requestMessages, String? conversationSummary})>
      _buildSummaryAwareAnalysisContext({
    required Conversation conversation,
    required List<Message> baseMessages,
  }) async {
    final conversationSummary = await _buildHistoricalContextSummary(
      conversation,
    );

    if (conversationSummary == null || conversationSummary.isEmpty) {
      return (
        requestMessages: baseMessages,
        conversationSummary: null,
      );
    }

    final requestMessages = _memoryService.clipToRecentRounds(
      baseMessages,
      MemoryService.maxRecentRounds,
    );

    return (
      requestMessages: requestMessages.isEmpty ? baseMessages : requestMessages,
      conversationSummary: conversationSummary,
    );
  }

  String? _buildRecognitionWarning({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
  }) =>
      ScreenshotRecognitionHelper.buildWarning(
        recognized: recognized,
        currentConversation: currentConversation,
      );

  String _defaultRecognitionImportMode({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
  }) =>
      ScreenshotRecognitionHelper.defaultImportMode(
        recognized: recognized,
        currentConversation: currentConversation,
      );

  List<Message> _buildImportedMessages(List<RecognizedMessage> recognized) {
    final baseTimestamp = DateTime.now();
    return List.generate(recognized.length, (index) {
      final message = recognized[index];
      return Message(
        id: '${baseTimestamp.microsecondsSinceEpoch}_$index',
        content: message.content,
        isFromMe: message.isFromMe,
        timestamp: baseTimestamp.add(Duration(milliseconds: index)),
        quotedReplyPreview: message.quotedReplyPreview,
        quotedReplyPreviewIsFromMe: message.quotedReplyPreviewIsFromMe,
      );
    });
  }

  String _resolveImportedConversationName({
    required String? enteredName,
    required String? recognizedName,
  }) =>
      ScreenshotRecognitionHelper.resolveImportedConversationName(
        enteredName: enteredName,
        recognizedName: recognizedName,
      );

  String _recognitionClassificationLabel(String classification) =>
      ScreenshotRecognitionHelper.classificationLabel(classification);

  String _recognitionConfidenceLabel(String confidence) =>
      ScreenshotRecognitionHelper.confidenceLabel(confidence);

  String _recognitionSideConfidenceLabel(String confidence) =>
      ScreenshotRecognitionHelper.sideConfidenceLabel(confidence);

  String? _recognizeTelemetryRecognitionSummary(AnalysisTelemetry telemetry) {
    if (telemetry.recognizedClassification == null &&
        telemetry.recognizedSideConfidence == null &&
        telemetry.recognizedMessageCount == null) {
      return null;
    }

    final parts = <String>[
      if (telemetry.recognizedClassification != null)
        '分類 ${_recognitionClassificationLabel(telemetry.recognizedClassification!)}',
      if (telemetry.recognizedSideConfidence != null)
        '方向 ${_recognitionSideConfidenceLabel(telemetry.recognizedSideConfidence!)}',
      if (telemetry.recognizedMessageCount != null)
        '訊息 ${telemetry.recognizedMessageCount} 則',
      if ((telemetry.uncertainSideCount ?? 0) > 0)
        '待確認 ${telemetry.uncertainSideCount} 則',
    ];

    return parts.isEmpty ? null : parts.join('｜');
  }

  String? _recognizeTelemetryNormalizationSummary(AnalysisTelemetry telemetry) {
    final parts = <String>[
      if ((telemetry.quotedPreviewAttachedCount ?? 0) > 0)
        '引用併回 ${telemetry.quotedPreviewAttachedCount} 次',
      if ((telemetry.quotedPreviewRemovedCount ?? 0) > 0 &&
          (telemetry.quotedPreviewAttachedCount ?? 0) == 0)
        '引用忽略 ${telemetry.quotedPreviewRemovedCount} 次',
      if ((telemetry.continuityAdjustedCount ?? 0) > 0)
        '方向校正 ${telemetry.continuityAdjustedCount} 次',
      if ((telemetry.groupedAdjustedCount ?? 0) > 0)
        '群組校正 ${telemetry.groupedAdjustedCount} 次',
      if ((telemetry.layoutFirstAdjustedCount ?? 0) > 0)
        '版面分群 ${telemetry.layoutFirstAdjustedCount} 次',
      if ((telemetry.overlapRemovedCount ?? 0) > 0)
        '重疊去重 ${telemetry.overlapRemovedCount} 次',
    ];

    return parts.isEmpty ? null : parts.join('｜');
  }

  String? _recognizeTelemetryContextSummary(AnalysisTelemetry telemetry) {
    if (telemetry.contextMode == null &&
        telemetry.truncatedMessageCount == null &&
        telemetry.conversationSummaryUsed == false) {
      return null;
    }

    final modeLabel = telemetry.contextMode == 'opening_plus_recent'
        ? '上下文 開頭+最近'
        : telemetry.contextMode == 'full'
            ? '上下文 全量'
            : null;

    final parts = <String>[
      if (modeLabel != null) modeLabel,
      if ((telemetry.inputMessageCount ?? 0) > 0 &&
          (telemetry.compiledMessageCount ?? 0) > 0)
        '送出 ${telemetry.compiledMessageCount}/${telemetry.inputMessageCount} 則',
      if ((telemetry.truncatedMessageCount ?? 0) > 0)
        '省略 ${telemetry.truncatedMessageCount} 則',
      if (telemetry.conversationSummaryUsed) '含舊摘要',
    ];

    return parts.isEmpty ? null : parts.join('｜');
  }

  String _analysisTelemetryRequestLabel(AnalysisTelemetry telemetry) {
    switch (telemetry.requestType) {
      case 'my_message':
        return '上次「我說」量測';
      case 'optimize_message':
        return '上次優化量測';
      case 'analyze_with_images':
        return '上次帶圖分析量測';
      default:
        return '上次分析量測';
    }
  }

  String _analysisTelemetryTransportSummary(AnalysisTelemetry telemetry) {
    final retrySummary =
        telemetry.retryCount > 0 ? '重試 ${telemetry.retryCount} 次' : null;
    final fallbackSummary = telemetry.fallbackUsed ? '有 fallback' : null;
    final timeoutSummary = telemetry.timeoutDuration != null
        ? '逾時上限 ${_formatDuration(telemetry.timeoutDuration)}'
        : null;

    final parts = <String>[
      '請求 ${_formatBytes(telemetry.requestBodyBytes)}',
      '本機準備 ${_formatDuration(telemetry.payloadPreparationDuration)}',
      '往返 ${_formatDuration(telemetry.roundTripDuration)}',
      if (retrySummary != null) retrySummary,
      if (fallbackSummary != null) fallbackSummary,
      if (timeoutSummary != null) timeoutSummary,
    ];

    return parts.join('｜');
  }

  String? _analysisTelemetryQuotaSummary(AnalysisTelemetry telemetry) {
    final estimatedCount =
        telemetry.estimatedMessageCount ?? telemetry.chargedMessageCount;

    if (telemetry.shouldChargeQuota == true) {
      final chargedCount = telemetry.chargedMessageCount ?? estimatedCount;
      if ((chargedCount ?? 0) > 0) {
        return '本次扣 $chargedCount 則訊息額度';
      }
      return '本次會扣訊息額度';
    }

    if (telemetry.requestType == 'recognize_only' ||
        telemetry.quotaReason == 'recognize_only_free') {
      return '本次純識別，不扣額度';
    }

    if (telemetry.quotaReason == 'test_account_waived') {
      if ((estimatedCount ?? 0) > 0) {
        return '測試帳號，本次未扣額度（原本會扣 $estimatedCount 則）';
      }
      return '測試帳號，本次未扣額度';
    }

    if (telemetry.shouldChargeQuota == false && (estimatedCount ?? 0) > 0) {
      return '本次未扣額度';
    }

    return null;
  }

  List<AnalysisTelemetryGuardrail> _telemetryGuardrails(
    AnalysisTelemetry telemetry,
  ) =>
      AnalysisTelemetryGuardrailHelper.evaluate(telemetry);

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

  Widget _buildTelemetryGuardrailSection(AnalysisTelemetry telemetry) {
    final guardrails = _telemetryGuardrails(telemetry);
    if (guardrails.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: guardrails.map((guardrail) {
              final color = _telemetryGuardrailColor(guardrail);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: color.withValues(alpha: 0.20),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _telemetryGuardrailIcon(guardrail),
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      guardrail.label,
                      style: AppTypography.bodySmall.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          ...guardrails.map(
            (guardrail) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${guardrail.label}：${guardrail.detail}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _recognitionConfidenceColor(RecognizedConversation recognized) {
    if (recognized.importPolicy == 'reject') {
      return AppColors.error;
    }
    switch (recognized.confidence) {
      case 'low':
        return AppColors.warning;
      case 'medium':
        return AppColors.info;
      case 'high':
      default:
        return AppColors.success;
    }
  }

  String _recognitionActionGuidance(RecognizedConversation recognized) =>
      ScreenshotRecognitionHelper.actionGuidance(recognized);

  ScreenshotRecognitionGuidance _recognitionGuidance(
    RecognizedConversation recognized,
  ) =>
      ScreenshotRecognitionHelper.guidance(recognized);

  Color _recognitionGuidanceColor(RecognizedConversation recognized) {
    switch (_recognitionGuidance(recognized).tone) {
      case ScreenshotRecognitionGuidanceTone.reject:
        return AppColors.error;
      case ScreenshotRecognitionGuidanceTone.caution:
        return AppColors.warning;
      case ScreenshotRecognitionGuidanceTone.review:
        return AppColors.info;
      case ScreenshotRecognitionGuidanceTone.stable:
        return AppColors.success;
    }
  }

  IconData _recognitionGuidanceIcon(RecognizedConversation recognized) {
    switch (_recognitionGuidance(recognized).tone) {
      case ScreenshotRecognitionGuidanceTone.reject:
        return Icons.block_rounded;
      case ScreenshotRecognitionGuidanceTone.caution:
        return Icons.call_split_rounded;
      case ScreenshotRecognitionGuidanceTone.review:
        return Icons.fact_check_rounded;
      case ScreenshotRecognitionGuidanceTone.stable:
        return Icons.check_circle_outline_rounded;
    }
  }

  Widget _buildRecognitionStatusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 顯示識別確認對話框，讓用戶設定對方名字和情境
  Future<ScreenshotRecognitionDialogResult?> _showRecognitionConfirmDialog({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
    String? warningMessage,
  }) async {
    final defaultImportMode = _defaultRecognitionImportMode(
      recognized: recognized,
      currentConversation: currentConversation,
    );
    return showDialog<ScreenshotRecognitionDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ScreenshotRecognitionDialog(
        recognized: recognized,
        warningMessage: warningMessage,
        initialName: recognized.contactName?.trim() ?? '',
        initialMeetingContext:
            _screenshotSessionContextFor(currentConversation).meetingContext,
        initialDuration:
            _screenshotSessionContextFor(currentConversation).duration,
        initialGoal: _screenshotSessionContextFor(currentConversation).goal,
        initialAnalysisContextNote:
            _screenshotAnalysisContextNoteFor(currentConversation) ?? '',
        initialImportMode: defaultImportMode,
        forceShowSessionContextFields:
            currentConversation.sessionContext == null,
        currentConversation: currentConversation,
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
      if (forceRefresh) {
        await OcrRecognitionCacheService.invalidate(
          imagesToProcess,
          widget.conversationId,
        );
      }
      final cachedRecognition = forceRefresh
          ? null
          : await OcrRecognitionCacheService.read(
              imagesToProcess,
              widget.conversationId,
            );
      AnalysisResult result;
      if (cachedRecognition != null) {
        _debugLog('[Recognize] OCR cache hit');
        _handleRecognizeTelemetry(
          AnalysisTelemetry(
            requestType: 'recognize_only',
            imageCount: imagesToProcess.length,
            requestBodyBytes: 0,
            payloadPreparationDuration: Duration.zero,
            roundTripDuration: Duration.zero,
            edgeAiDuration: Duration.zero,
            totalCompressedImageBytes: _totalCompressedImageBytes,
            cacheHit: true,
            recognizedClassification:
                cachedRecognition.recognizedConversation.classification,
            recognizedConfidence:
                cachedRecognition.recognizedConversation.confidence,
            recognizedSideConfidence:
                cachedRecognition.recognizedConversation.sideConfidence,
            recognizedMessageCount:
                cachedRecognition.recognizedConversation.messageCount,
            uncertainSideCount:
                cachedRecognition.recognizedConversation.uncertainSideCount,
          ),
        );
        result = AnalysisResult.fromJson(
          {
            'recognizedConversation':
                cachedRecognition.recognizedConversation.toJson(),
          },
        );
        _rememberRecognitionReplay(
          images: imagesToProcess,
          metrics: metricsToProcess,
        );
      } else {
        final analysisService = AnalysisService();

        // 使用 Future.any 來實現強制 timeout
        result = await Future.any([
          analysisService.analyzeConversation(
            conversation.messages.isEmpty
                ? [
                    Message(
                        id: 'placeholder',
                        content: '請識別截圖內容',
                        isFromMe: true,
                        timestamp: DateTime.now())
                  ]
                : conversation.messages,
            images: imagesToProcess,
            sessionContext: _screenshotSessionContextFor(conversation),
            knownContactName:
                ScreenshotRecognitionHelper.isPlaceholderConversationName(
              conversation.name,
            )
                    ? null
                    : conversation.name.trim(),
            onProgress: _handleRecognizeProgress,
            onTelemetry: _handleRecognizeTelemetry,
            recognizeOnly: true, // 純識別模式：只識別截圖，不扣額度
          ),
          // 強制 130 秒 timeout (比 API 的 120 秒稍長)
          Future.delayed(const Duration(seconds: 130), () {
            throw TimeoutException('識別超時 (130秒)');
          }),
        ]);
        _debugLog(
            'API 回應成功，耗時: ${DateTime.now().difference(startTime).inSeconds}s');

        // 把識別結果存入對話
        if (result.recognizedConversation != null) {
          await OcrRecognitionCacheService.write(
            images: imagesToProcess,
            recognizedConversation: result.recognizedConversation!,
            conversationId: widget.conversationId,
          );
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

        final isFromCache = cachedRecognition != null;
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已保留這次辨識結果，你可以稍後再繼續加入。'),
            ),
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
          message: result.recognizedConversation?.summary ?? '無法識別截圖中的對話',
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
  }) async {
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

    // 驗證分析條件：必須有訊息
    if (conversation.messages.isEmpty) {
      setState(() {
        _isAnalyzing = false;
        _applyErrorState(
          message: '請先輸入對話內容或上傳截圖',
          action: AnalysisErrorAction.addIncomingMessage,
          origin: _AnalysisErrorOrigin.analysis,
          guidance: '你可以先在下方補上一則她的回覆，或先上傳截圖辨識文字後再分析。',
        );
      });
      return;
    }

    final messagesForAnalysis = _buildMessagesForReplyAnalysis(
      conversation.messages,
    );
    if (messagesForAnalysis == null) {
      setState(() {
        _isAnalyzing = false;
        _applyErrorState(
          message: '目前還沒有她的新回覆可以分析。',
          action: AnalysisErrorAction.addIncomingMessage,
          origin: _AnalysisErrorOrigin.analysis,
          guidance: '你可以先補上你說的內容作紀錄；等她回覆後，再按「分析新增內容」會比較準。',
        );
      });
      return;
    }

    if (conversation.messages.last.isFromMe &&
        _pendingMessageCount(conversation) > 0) {
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
      final analysisContext = await _buildSummaryAwareAnalysisContext(
        conversation: conversation,
        baseMessages: messagesForAnalysis,
      );

      // 呼叫 Supabase Edge Function（不帶圖片，因為截圖已轉成文字存入）
      // skipPreview 路徑刻意拿不到 overcharge 憑證：>2000 字會被 server
      // 守門擋回（409 要求重新確認），絕不可能未經確認被扣 20 則。
      ({bool confirmed, OverchargeConfirmationPayload? overcharge})
          previewDecision;
      if (skipPreview) {
        previewDecision = (confirmed: true, overcharge: null);
      } else {
        previewDecision = await _confirmAnalysisPreview(
          analysisContext.requestMessages,
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
        _fullErrorMessage = null;
        _fullErrorRetriesRemaining = 0;
        _quotaExceededInfo = null;
        _streamProgressLabel = '開始完整分析';
        _streamProgressDetail = '正在建立串流連線。';
        _streamContents = const [];
        _activeAnalysisMessageCount = conversation.messages.length;
      });

      await ref
          .read(subscriptionProvider.notifier)
          .ensureServerEntitlementSyncedForAnalysis();
      if (!mounted) {
        return;
      }

      // Fire-and-forget. The notifier caches the payload for retryFull and
      // keeps itself alive across screen navigation; ref.listen + the initState
      // hydration path mirror provider state back into local fields so the
      // legacy render tree (which reads _enthusiasmScore, _isAnalyzing, etc.)
      // keeps working (Eric 2026-05-28 UX spec).
      final analysisFuture = ref
          .read(streamingAnalyzeProvider(widget.conversationId).notifier)
          .start(
            messages: analysisContext.requestMessages,
            sessionContext: conversation.sessionContext,
            conversationSummary: analysisContext.conversationSummary,
            partnerSummary: _resolvePartnerSummary(conversation),
            effectiveStyleContext: _resolveEffectiveStyleContext(conversation),
            knownContactName:
                ScreenshotRecognitionHelper.isPlaceholderConversationName(
              conversation.name,
            )
                    ? null
                    : conversation.name.trim(),
            previousAnalyzedCount: conversation.lastAnalyzedMessageCount,
            previousAnalyzedCharCount: conversation.lastAnalyzedCharCount,
            confirmedOvercharge: previewDecision.overcharge,
            conversationMessageCount: conversation.messages.length,
          );
      if (waitForCompletion) {
        await analysisFuture;
      } else {
        unawaited(analysisFuture);
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
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
        prev?.full == next.full &&
        prev?.streamProgressLabel == next.streamProgressLabel &&
        prev?.streamProgressDetail == next.streamProgressDetail &&
        prev?.streamContents == next.streamContents) {
      return;
    }
    switch (next.phase) {
      case StreamingAnalyzePhase.connecting:
        setState(() {
          _isAnalyzing = true;
          _fullErrorMessage = null;
          _fullErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = next.streamProgressLabel;
          _streamProgressDetail = next.streamProgressDetail;
          _streamContents = next.streamContents;
          _activeAnalysisMessageCount = next.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
          _resetErrorState();
        });
        break;
      case StreamingAnalyzePhase.recommendationReady:
        setState(() {
          _isAnalyzing = true;
          _fullErrorMessage = null;
          _fullErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = next.streamProgressLabel;
          _streamProgressDetail = next.streamProgressDetail;
          _streamContents = next.streamContents;
          _activeAnalysisMessageCount = next.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.streamingReport:
        // Mirror the notifier's cleared error fields (I-P2-d) so the build
        // tree flips from retry back to live streaming when the user taps
        // retry. Without this the local _fullErrorMessage keeps the RetryCard
        // rendered even though the notifier is mid-flight.
        setState(() {
          _isAnalyzing = true;
          _fullErrorMessage = null;
          _fullErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = next.streamProgressLabel;
          _streamProgressDetail = next.streamProgressDetail;
          _streamContents = next.streamContents;
          _activeAnalysisMessageCount = next.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.done:
        final result = next.full;
        if (result == null) return;
        if (_isStreamingAnalyzeResultStaleForCurrentConversation(next)) {
          setState(() {
            _isAnalyzing = false;
            _fullErrorMessage = '你剛剛補了新的聊天紀錄，這份完整分析先不套用。請按「分析新增內容」更新到最新版。';
            _fullErrorRetriesRemaining = 0;
            _quotaExceededInfo = null;
            _streamContents = const [];
            _activeAnalysisMessageCount = next.conversationMessageCount;
            _clearDetailedAnalysisStateForStreamingAnalyzePartial();
          });
          return;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
        final conv = ref.read(conversationProvider(widget.conversationId));
        setState(() {
          _isAnalyzing = false;
          _fullErrorMessage = null;
          _fullErrorRetriesRemaining = 0;
          _quotaExceededInfo = null;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = const [];
          _activeAnalysisMessageCount = null;
          if (conv != null) {
            _lastAnalyzedMessageCount = conv.messages.length;
            _hasEditedAnalyzedMessage = false;
          }
          _applyAnalysisResult(result);
          _enthusiasmScore = result.enthusiasmScore;
          _dimensionScores = result.dimensionScores;
          _strategy = result.strategy;
          _replies = result.replies;
          _replyOptions = result.replyOptions;
          _topicDepth = result.topicDepth;
          _healthCheck = result.healthCheck;
          _gameStage = result.gameStage;
          _psychology = result.psychology;
          _finalRecommendation = result.recommendation;
          _coachActionHint = result.coachActionHint;
          _reminder = result.reminder;
          _shouldGiveUp = result.shouldGiveUp;
          _lastAiResponse = result.rawResponse;
          _resetFeedbackState();
        });
        _persistLatestAnalysisSnapshot(result).catchError((_) {
          // Ignore errors in test environment.
        });
        _syncSubscriptionUsageFromResult(result, showChargeToast: true);
        break;
      case StreamingAnalyzePhase.failedAfterRecommendation:
        setState(() {
          _isAnalyzing = false;
          _fullErrorMessage = next.fullErrorMessage;
          _fullErrorRetriesRemaining = next.retriesRemaining;
          _quotaExceededInfo = next.quotaExceeded;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = next.streamContents;
          _activeAnalysisMessageCount = next.conversationMessageCount;
          _clearDetailedAnalysisStateForStreamingAnalyzePartial();
        });
        break;
      case StreamingAnalyzePhase.failedBeforeRecommendation:
        final code = next.recommendationPreviewErrorCode;
        final message =
            next.recommendationPreviewErrorMessage ?? '分析暫時失敗，請稍後再試。';
        final isQuotaError =
            code == 'DAILY_LIMIT_EXCEEDED' || code == 'MONTHLY_LIMIT_EXCEEDED';
        setState(() {
          _isAnalyzing = false;
          _streamProgressLabel = null;
          _streamProgressDetail = null;
          _streamContents = const [];
          _activeAnalysisMessageCount = null;
          _applyErrorState(
            message: message,
            action: isQuotaError
                ? AnalysisErrorAction.upgrade
                : AnalysisErrorAction.retry,
            origin: _AnalysisErrorOrigin.analysis,
          );
        });
        if (isQuotaError) {
          unawaited(_showPaywall(context));
        }
        break;
      case StreamingAnalyzePhase.idle:
        break;
    }
  }

  /// Retry the last failed full analysis. The notifier owns the cached
  /// payload from the most recent `start()` (survives screen remount via
  /// `ref.keepAlive`), so we just delegate. I-P1-b.
  void _retryFullAnalysis() {
    unawaited(
      ref
          .read(streamingAnalyzeProvider(widget.conversationId).notifier)
          .retryFull(),
    );
  }

  /// 優化用戶訊息
  Future<void> _optimizeMessage() async {
    final draft = _optimizeController.text.trim();
    if (draft.isEmpty) return;

    if (!ref.read(subscriptionProvider).isEssential) {
      _showFloatingSnackBar('草稿潤飾器需要 Essential 方案。');
      await _showPaywall(context);
      return;
    }
    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: '草稿潤飾',
    );
    if (!consented || !mounted) return;

    _dismissKeyboard();
    setState(() {
      _isOptimizing = true;
      _optimizedMessage = null;
      _lastAnalysisTelemetry = null;
    });

    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) {
      setState(() => _isOptimizing = false);
      return;
    }

    try {
      final analysisContext = await _buildSummaryAwareAnalysisContext(
        conversation: conversation,
        baseMessages: conversation.messages,
      );

      final analysisService = AnalysisService();
      final result = await analysisService.analyzeConversation(
        analysisContext.requestMessages,
        sessionContext: conversation.sessionContext,
        conversationSummary: analysisContext.conversationSummary,
        partnerSummary: _resolvePartnerSummary(conversation),
        effectiveStyleContext: _resolveEffectiveStyleContext(conversation),
        knownContactName:
            ScreenshotRecognitionHelper.isPlaceholderConversationName(
          conversation.name,
        )
                ? null
                : conversation.name.trim(),
        userDraft: draft,
        onTelemetry: _handleAnalysisTelemetry,
      );
      if (!mounted) return;

      setState(() {
        _isOptimizing = false;
        _optimizedMessage = result.optimizedMessage;
      });

      if (_optimizedMessage == null || _optimizedMessage!.optimized.isEmpty) {
        _showFloatingSnackBar('這次沒有產生可用的優化結果，請稍後再試。');
      }
      _syncSubscriptionUsageFromResult(result, showChargeToast: true);
    } on DailyLimitExceededException catch (e) {
      if (!mounted) return;
      setState(() {
        _isOptimizing = false;
      });
      _showFloatingSnackBar(_dailyQuotaExceededMessage(e));
      await _showPaywall(context);
    } on MonthlyLimitExceededException catch (e) {
      if (!mounted) return;
      setState(() {
        _isOptimizing = false;
      });
      _showFloatingSnackBar(_monthlyQuotaExceededMessage(e));
      await _showPaywall(context);
    } on AnalysisException catch (e) {
      if (!mounted) return;
      setState(() {
        _isOptimizing = false;
      });
      _showFloatingSnackBar(e.message);
      if (e.suggestedAction == AnalysisErrorAction.upgrade) {
        await _showPaywall(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isOptimizing = false;
      });
      _showFloatingSnackBar('訊息優化暫時失敗，請稍後再試。');
    }
  }

  // ===== 分析輔助方法 (Mock 邏輯，之後會被真正的 AI 取代) =====

  // ignore: unused_element
  int _calculateEnthusiasmScore(
      List<Message> theirMessages, List<Message> myMessages, int totalRounds) {
    if (theirMessages.isEmpty) return 20;

    // 基礎分數根據對話輪數
    int baseScore = 30;
    if (totalRounds == 1) baseScore = 25;
    if (totalRounds > 3) baseScore = 40;
    if (totalRounds > 5) baseScore = 50;

    // 根據她的訊息長度加分
    final avgLength =
        theirMessages.map((m) => m.content.length).reduce((a, b) => a + b) /
            theirMessages.length;
    if (avgLength > 20) baseScore += 15;
    if (avgLength > 50) baseScore += 10;

    // 檢查是否有問號（表示她有興趣問你）
    final hasQuestions = theirMessages
        .any((m) => m.content.contains('?') || m.content.contains('？'));
    if (hasQuestions) baseScore += 15;

    // 確保分數在合理範圍
    return baseScore.clamp(15, 95);
  }

  // ignore: unused_element
  GameStage _determineGameStage(int totalRounds, List<Message> theirMessages) {
    if (totalRounds <= 1) return GameStage.opening;
    if (totalRounds <= 3) return GameStage.premise;
    if (totalRounds <= 6) return GameStage.qualification;
    if (totalRounds <= 10) return GameStage.narrative;
    return GameStage.close;
  }

  // ignore: unused_element
  TopicDepthLevel _determineTopicDepth(List<Message> theirMessages) {
    if (theirMessages.isEmpty) return TopicDepthLevel.event;

    final allContent = theirMessages.map((m) => m.content).join(' ');

    // 檢查是否有個人情感關鍵字
    final personalKeywords = ['喜歡', '討厭', '覺得', '想', '希望', '感覺', '心情'];
    final hasPersonal = personalKeywords.any((k) => allContent.contains(k));

    // 檢查是否有曖昧關鍵字
    final intimateKeywords = ['約', '見面', '一起', '下次', '週末', '有空'];
    final hasIntimate = intimateKeywords.any((k) => allContent.contains(k));

    if (hasIntimate) return TopicDepthLevel.intimate;
    if (hasPersonal) return TopicDepthLevel.personal;
    return TopicDepthLevel.event;
  }

  // ignore: unused_element
  List<String> _checkHealthIssues(
      List<Message> myMessages, List<Message> theirMessages) {
    final issues = <String>[];

    if (myMessages.isEmpty) return issues;

    // 檢查是否連續發多則訊息
    // (簡化邏輯，實際應該看時間戳)

    // 檢查訊息長度比例
    if (theirMessages.isNotEmpty) {
      final myAvg =
          myMessages.map((m) => m.content.length).reduce((a, b) => a + b) /
              myMessages.length;
      final theirAvg =
          theirMessages.map((m) => m.content.length).reduce((a, b) => a + b) /
              theirMessages.length;
      if (myAvg > theirAvg * 2) {
        issues.add('你的訊息比她長太多，可能顯得過於積極');
      }
    }

    return issues;
  }

  // ignore: unused_element
  String _getNextStepForStage(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return '建立基本連結，創造對話理由';
      case GameStage.premise:
        return '可以開始評估她的興趣程度';
      case GameStage.qualification:
        return '確認互相興趣，準備建立更深連結';
      case GameStage.narrative:
        return '建立情感連結，分享故事';
      case GameStage.close:
        return '可以考慮邀約見面';
    }
  }

  // ignore: unused_element
  String _generateSubtext(String lastMessage, GameStage stage) {
    if (lastMessage.isEmpty) return '等待她的回應';
    if (lastMessage.length < 5) return '她的回覆很簡短，可能在忙或興趣一般';
    if (lastMessage.contains('?') || lastMessage.contains('？')) {
      return '她主動問你問題，對你有好奇心';
    }
    if (stage == GameStage.opening) {
      return '剛開始對話，她在觀察你是什麼樣的人';
    }
    return '她願意回覆代表對話還在進行中';
  }

  // ignore: unused_element
  Map<String, String> _generateReplies(String lastMessage) {
    // 簡化版本，實際應該由 AI 生成
    final msg = lastMessage.isEmpty ? '嗨' : lastMessage;
    return {
      'extend': '關於「$msg」可以多聊聊',
      'resonate': '我也有類似的感覺',
      'tease': '你這樣說讓我很好奇欸',
      'humor': '哈哈這讓我想到一個笑話',
      'coldRead': '感覺你是那種很有想法的人',
    };
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
      buffer.writeln('熱度分數: $_enthusiasmScore/100');

      if (_gameStage != null) {
        buffer.writeln('對話進度: ${_gameStage!.current.label}');
        buffer.writeln('狀態: ${_gameStage!.status}');
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
      );

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

  List<String> _extractRecommendationSegments(String content) {
    final normalized = content.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final matches = RegExp(r'[①②③④⑤💡]').allMatches(normalized).toList();
    if (matches.isEmpty) {
      return [normalized];
    }

    final segments = <String>[];
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end =
          i + 1 < matches.length ? matches[i + 1].start : normalized.length;
      final segment = normalized.substring(start, end).trim();
      if (segment.isNotEmpty) {
        segments.add(segment);
      }
    }
    return segments;
  }

  String? _extractRecommendationReplyText(String segment) {
    final normalized = segment.replaceAll('\r\n', '\n').trim();
    final match =
        RegExp(r'^[①②③④⑤]\s*[^→\n]{0,80}\s*→\s*').firstMatch(normalized);
    if (match == null) {
      return null;
    }

    final replyText = normalized
        .substring(match.end)
        .trim()
        .replaceAll(RegExp(r'^[「『"“]+|[」』"”]+$'), '');
    return replyText.isEmpty ? null : replyText;
  }

  void _copyRecommendationText(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label)),
    );
  }

  /// 截圖識別結果卡片
  /// 優先呈現結構化分段回覆；舊版 ①② 格式只保留相容。
  List<Widget> _buildRecommendationContent(FinalRecommendation recommendation) {
    final content = recommendation.content.trim();
    final structuredSegments = recommendation.replySegments
        .where((segment) => segment.reply.trim().isNotEmpty)
        .toList();
    if (structuredSegments.isNotEmpty) {
      return _buildStructuredRecommendationSegments(
        recommendation: recommendation,
        segments: structuredSegments,
      );
    }

    final segments = _extractRecommendationSegments(content);
    if (segments.length <= 1) {
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(content, style: AppTypography.bodyLarge),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              _copyRecommendationText(content, '已複製到剪貼簿');
            },
            icon: const Icon(Icons.copy),
            label: const Text('複製推薦回覆'),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    for (final segment in segments) {
      final trimmed = segment.trim();
      final isHint = trimmed.startsWith('💡');
      final replyText =
          isHint ? null : _extractRecommendationReplyText(trimmed);

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isHint
                ? AppColors.info.withValues(alpha: 0.08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: isHint
                ? Border.all(color: AppColors.info.withValues(alpha: 0.2))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trimmed,
                style: AppTypography.bodyMedium.copyWith(
                  color:
                      isHint ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
              if (!isHint && replyText != null && replyText.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _copyRecommendationText(replyText, '已複製這句');
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('複製這句', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  List<Widget> _buildStructuredRecommendationSegments({
    required FinalRecommendation recommendation,
    required List<ReplySegment> segments,
  }) {
    final widgets = <Widget>[
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
        ),
        child: Text(
          segments.length == 1
              ? '這是推薦訊息素材；下方保留引用，方便你確認 AI 接的是哪顆球。'
              : '建議拆成 ${segments.length} 則短訊息。每段都引用她的原句，也能單獨複製。',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 10),
    ];

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final source = segment.sourceMessage.trim();
      final reply = segment.reply.trim();
      final reason = segment.reason.trim();
      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.format_quote_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      segment.displayLabel,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (source.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.45),
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    source,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                reply,
                style: AppTypography.bodyLarge.copyWith(height: 1.45),
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  reason,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _copyRecommendationText(reply, '已複製第 ${i + 1} 句');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(
                    segments.length == 1 ? '複製這句' : '複製第 ${i + 1} 句',
                    style: AppTypography.labelMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final allContent = recommendation.content.trim();
    if (segments.length > 1 && allContent.isNotEmpty) {
      widgets.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              _copyRecommendationText(allContent, '已複製整組訊息');
            },
            icon: const Icon(Icons.copy),
            label: const Text('複製整組訊息'),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildRecognizedConversationCard() {
    final recognized = _recognizedConversation!;
    final displayWarning = _recognizedWarningMessage ?? recognized.warning;
    final displayRecognized = recognized.copyWith(warning: displayWarning);
    final guidance = _recognitionGuidance(displayRecognized);
    final guidanceColor = _recognitionGuidanceColor(displayRecognized);
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_library,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  recognized.summary,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.glassTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildRecognitionStatusChip(
                icon: Icons.chat_bubble_outline,
                label: _recognitionClassificationLabel(
                  displayRecognized.classification,
                ),
                color: displayRecognized.importPolicy == 'reject'
                    ? AppColors.error
                    : AppColors.primary,
              ),
              _buildRecognitionStatusChip(
                icon: Icons.auto_awesome,
                label:
                    _recognitionConfidenceLabel(displayRecognized.confidence),
                color: _recognitionConfidenceColor(displayRecognized),
              ),
              _buildRecognitionStatusChip(
                icon: Icons.compare_arrows_rounded,
                label: _recognitionSideConfidenceLabel(
                  displayRecognized.sideConfidence,
                ),
                color: _recognitionConfidenceColor(
                  displayRecognized.copyWith(
                    confidence: displayRecognized.sideConfidence,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: guidanceColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: guidanceColor.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _recognitionGuidanceIcon(displayRecognized),
                  size: 18,
                  color: guidanceColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guidance.title,
                        style: AppTypography.bodySmall.copyWith(
                          color: guidanceColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _recognitionActionGuidance(displayRecognized),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.glassTextPrimary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (displayWarning != null && displayWarning.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  displayWarning,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.glassTextPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          if (recognized.messages != null &&
              recognized.messages!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              title: Text(
                '查看識別內容',
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.primary),
              ),
              iconColor: AppColors.glassTextPrimary,
              collapsedIconColor: AppColors.glassTextPrimary,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              children: recognized.messages!
                  .map((m) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              m.isFromMe ? Icons.person : Icons.person_outline,
                              size: 16,
                              color: m.isFromMe
                                  ? AppColors.avatarMeStart
                                  : AppColors.avatarHerStart,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                m.content,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.glassTextPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ],
          if (_canForceReRecognize) ...[
            const SizedBox(height: 12),
            if (_recognitionFromCache) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cached_rounded,
                      size: 18,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '這是上次相同截圖的快取結果',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.glassTextPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _forceReRecognizeLastBatch,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_recognitionFromCache ? '強制重新識別' : '重新讀圖'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _recognitionFromCache
                  ? '如果結果有誤，點「強制重新識別」會忽略快取，重新跑 OCR。'
                  : '如果剛剛的我說 / 她說不太對，可以直接重讀同一批截圖，不會沿用上次的快取結果。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.unselectedText,
                height: 1.4,
              ),
            ),
          ],
          if (_hasPendingRecognitionImport) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _resumeRecognitionImport,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('繼續確認加入'),
                  ),
                ),
                const SizedBox(width: 8),
                if (_canForceReRecognize)
                  TextButton(
                    onPressed: _forceReRecognizeLastBatch,
                    child: const Text('重讀這批圖'),
                  ),
                if (_canForceReRecognize) const SizedBox(width: 4),
                TextButton(
                  onPressed: _discardPendingRecognitionDraft,
                  child: const Text('清除草稿'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '剛剛的識別結果已暫存在這裡，不用重新跑 OCR。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.unselectedText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeedbackCategoryChip(String value, String label) {
    final isSelected = _feedbackCategory == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: _isSubmittingFeedback
          ? null
          : (selected) {
              setState(() => _feedbackCategory = selected ? value : null);
            },
    );
  }

  Widget _buildDetailedAnalysisToggle() {
    return Semantics(
      button: true,
      label: _showDetailedAnalysis ? '收起詳細分析與更多回覆' : '展開詳細分析與更多回覆',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(
          () => _showDetailedAnalysis = !_showDetailedAnalysis,
        ),
        child: GlassmorphicContainer(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.insights_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '詳細分析與更多回覆',
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.glassTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '熱度、階段、心理訊號、五維雷達與更多回覆風格',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.glassTextSecondary,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _showDetailedAnalysis ? '收起' : '展開',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _showDetailedAnalysis
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_enthusiasmScore != null)
                    _buildDetailedAnalysisPill('熱度 $_enthusiasmScore'),
                  if (_gameStage != null)
                    _buildDetailedAnalysisPill(_gameStage!.current.label),
                  if (_replies != null && _replies!.isNotEmpty)
                    _buildDetailedAnalysisPill('${_replies!.length} 種回覆'),
                  if (_dimensionScores != null)
                    _buildDetailedAnalysisPill('五維雷達'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedAnalysisPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: AppColors.glassTextSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      return GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _cleanupAndGoBack,
            ),
          ),
          body: Stack(
            children: [
              const Center(child: Text('找不到對話')),
              _buildRoutePopScopeRegistration(),
            ],
          ),
        ),
      );
    }

    if (conversation.messages.length > _coachMarkLastSeenMessageCount) {
      _coachMarkLastSeenMessageCount = conversation.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _maybeShowEditMessageCoachMark(partnerId: conversation.partnerId),
          );
        }
      });
    }

    final showInitialScreenshotSetup = _enthusiasmScore == null &&
        !_isAnalyzing &&
        _errorMessage == null &&
        _fullErrorMessage == null;
    final isScreenshotOnlyEmptyState =
        showInitialScreenshotSetup && conversation.messages.isEmpty;

    return GradientBackground(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(conversation.name, style: AppTypography.titleLarge),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _cleanupAndGoBack,
          ),
          actions: [
            // 對方檔案按鈕
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: '對方檔案',
              onPressed: () {
                _clearAnalysisSnackBarsBeforePush();
                context.push('/profile/${widget.conversationId}');
              },
            ),
            // 匯出按鈕
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: '匯出對話紀錄',
              onPressed: () => _exportConversation(conversation),
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
        ),
        body: SafeArea(
          // RWD: 限制最大寬度，大螢幕置中顯示
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  _buildRoutePopScopeRegistration(),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      // 移除 physics 設定，使用平台預設（與第一頁一致）
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Messages preview
                          GlassmorphicContainer(
                            child: Column(
                              children: [
                                if (conversation.messages.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                      horizontal: 8,
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.chat_bubble_outline,
                                          color: AppColors.glassTextHint,
                                          size: 34,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          '還沒有訊息',
                                          style: AppTypography.titleMedium
                                              .copyWith(
                                            color: AppColors.glassTextPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          isScreenshotOnlyEmptyState
                                              ? '先上傳聊天截圖，確認文字後再加入這段對話。'
                                              : '先在下方輸入一句，再選「這句是她說」或「這句是我說」。',
                                          textAlign: TextAlign.center,
                                          style:
                                              AppTypography.bodySmall.copyWith(
                                            color: AppColors.glassTextSecondary,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                // 顯示訊息 (可展開/收合)
                                ..._visibleMessagePreview(
                                  conversation.messages,
                                ).map((m) => MessageBubble(
                                      message: m,
                                      onEdit: () =>
                                          _editMessage(conversation, m),
                                      onSwapSide: () =>
                                          _swapMessageSide(conversation, m),
                                      onDelete: () =>
                                          _deleteMessage(conversation, m),
                                    )),
                                if (conversation.messages.length > 5)
                                  GestureDetector(
                                    onTap: () => setState(() =>
                                        _showAllMessages = !_showAllMessages),
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _showAllMessages
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                            size: 16,
                                            color: AppColors.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _showAllMessages
                                                ? '收合訊息'
                                                : '展開全部 ${conversation.messages.length} 則訊息',
                                            style: AppTypography.caption
                                                .copyWith(
                                                    color: AppColors.primary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          if (_isRefreshingPremiumReplies) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.28),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '正在重新分析完整回覆，完成後會更新新版回覆選項。',
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Error message
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                        AppColors.error.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.error_outline,
                                          color: AppColors.error),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: AppTypography.bodyMedium
                                              .copyWith(color: AppColors.error),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_errorGuidance != null) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      _errorGuidance!,
                                      style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.textSecondary),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      if (_errorAction != null)
                                        ElevatedButton(
                                          onPressed:
                                              _isAnalyzing || _isRecognizing
                                                  ? null
                                                  : () => _handleErrorAction(
                                                      _errorAction!),
                                          child: Text(
                                            _primaryErrorActionLabel(
                                              _errorAction!,
                                            ),
                                          ),
                                        ),
                                      // 強制重新識別按鈕（當有之前的圖片可以重試時）
                                      if (_canForceReRecognize &&
                                          _errorOrigin ==
                                              _AnalysisErrorOrigin.recognition)
                                        OutlinedButton.icon(
                                          onPressed:
                                              _isAnalyzing || _isRecognizing
                                                  ? null
                                                  : _forceReRecognizeLastBatch,
                                          icon:
                                              const Icon(Icons.refresh_rounded),
                                          label: const Text('強制重新識別'),
                                        ),
                                      if (_shouldShowSecondaryErrorAction())
                                        OutlinedButton(
                                          onPressed: _isAnalyzing ||
                                                  _isRecognizing
                                              ? null
                                              : () =>
                                                  setState(_resetErrorState),
                                          child: Text(
                                            _secondaryErrorActionLabel(),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // 手動分析按鈕 (尚未分析時顯示)
                          if (showInitialScreenshotSetup) ...[
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                children: [
                                  // 動作優先：選圖按鈕置頂，介紹文字降到 caption。
                                  ImagePickerWidget(
                                    maxImages: 3,
                                    externalImages: _selectedImages, // 同步外部狀態
                                    onImagesChanged:
                                        _handleSelectedImagesChanged,
                                    onMetricsChanged:
                                        _handleSelectedImageMetricsChanged,
                                  ),
                                  _buildScreenshotSettingSection(),
                                  const SizedBox(height: 8),

                                  // 對話長度提示
                                  Text(
                                    '建議每張截圖保留 15 則內完整對話；過長請拆成 2-3 張，辨識會更穩。',
                                    style: AppTypography.bodySmall.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.55),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),

                                  // 如果有截圖，先顯示「辨識截圖文字」按鈕
                                  if (_selectedImages.isNotEmpty) ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isRecognizing
                                            ? null
                                            : _recognizeAndAddToConversation,
                                        icon: _isRecognizing
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white),
                                              )
                                            : const Icon(
                                                Icons.add_photo_alternate),
                                        label: Text(_recognizeButtonLabel),
                                        /*
                                            ? '識別中...'
                                            : '辨識截圖文字 (${_selectedImages.length}張)'),
                                        */
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor: AppColors
                                              .primary
                                              .withValues(alpha: 0.7),
                                          disabledForegroundColor: Colors.white
                                              .withValues(alpha: 0.95),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Debug 狀態顯示
                                    if (_showTelemetryDiagnostics &&
                                        _isRecognizing)
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: Colors.orange
                                                  .withValues(alpha: 0.3)),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              '目前階段：${_recognizeStageLabel(_recognizeStage)} ($_recognizeElapsedSeconds 秒)',
                                              style: AppTypography.bodySmall
                                                  .copyWith(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '圖片：${_selectedImages.length} 張｜原始 ${_formatBytes(_totalOriginalImageBytes)} -> 壓縮 ${_formatBytes(_totalCompressedImageBytes)}',
                                              style: AppTypography.caption
                                                  .copyWith(
                                                color: Colors.orange
                                                    .withValues(alpha: 0.8),
                                                fontFamily: 'monospace',
                                                fontSize: 10,
                                              ),
                                            ),
                                            if (_lastRecognizeTelemetry != null)
                                              Text(
                                                _lastRecognizeTelemetry!
                                                        .cacheHit
                                                    ? '本次直接使用本機快取結果，未重新送出 OCR 請求'
                                                    : '請求 ${_formatBytes(_lastRecognizeTelemetry!.requestBodyBytes)}｜本機準備 ${_formatDuration(_lastRecognizeTelemetry!.payloadPreparationDuration)}｜往返 ${_formatDuration(_lastRecognizeTelemetry!.roundTripDuration)}',
                                                style: AppTypography.caption
                                                    .copyWith(
                                                  color: Colors.orange
                                                      .withValues(alpha: 0.8),
                                                  fontSize: 10,
                                                ),
                                              ),
                                            if (_lastRecognizeTelemetry != null)
                                              Text(
                                                _lastRecognizeTelemetry!
                                                        .cacheHit
                                                    ? '本次使用本機快取，未重新上傳或呼叫 AI'
                                                    : 'AI ${_formatDuration(_lastRecognizeTelemetry!.edgeAiDuration)}｜估計傳輸/排隊 ${_formatDuration(_lastRecognizeTelemetry!.estimatedTransferDuration)}',
                                                style: AppTypography.caption
                                                    .copyWith(
                                                  color: Colors.orange
                                                      .withValues(alpha: 0.8),
                                                  fontSize: 10,
                                                ),
                                              ),
                                            if (_lastRecognizeTelemetry !=
                                                    null &&
                                                _recognizeTelemetryRecognitionSummary(
                                                        _lastRecognizeTelemetry!) !=
                                                    null)
                                              Text(
                                                _recognizeTelemetryRecognitionSummary(
                                                    _lastRecognizeTelemetry!)!,
                                                style: AppTypography.caption
                                                    .copyWith(
                                                  color: Colors.orange
                                                      .withValues(alpha: 0.8),
                                                  fontSize: 10,
                                                ),
                                              ),
                                            if (_lastRecognizeTelemetry !=
                                                    null &&
                                                _recognizeTelemetryNormalizationSummary(
                                                        _lastRecognizeTelemetry!) !=
                                                    null)
                                              Text(
                                                _recognizeTelemetryNormalizationSummary(
                                                    _lastRecognizeTelemetry!)!,
                                                style: AppTypography.caption
                                                    .copyWith(
                                                  color: Colors.orange
                                                      .withValues(alpha: 0.8),
                                                  fontSize: 10,
                                                ),
                                              ),
                                            Text(
                                              '若超過 130 秒仍無結果，建議換更少訊息的截圖再試。',
                                              style: AppTypography.caption
                                                  .copyWith(
                                                color: Colors.orange
                                                    .withValues(alpha: 0.8),
                                                fontSize: 10,
                                              ),
                                            ),
                                            /*
                                            Text(
                                              '🔄 正在識別截圖... ($_recognizeElapsedSeconds 秒)',
                                              style: AppTypography.bodySmall
                                                  .copyWith(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '圖片: ${_selectedImages.length}張 (${_selectedImages.map((i) => '${(i.length / 1024).toStringAsFixed(0)}KB').join(', ')})',
                                              style: AppTypography.caption
                                                  .copyWith(
                                                color: Colors.orange
                                                    .withValues(alpha: 0.8),
                                                fontFamily: 'monospace',
                                                fontSize: 10,
                                              ),
                                            ),
                                            Text(
                                              '最長等待 130 秒',
                                              style: AppTypography.caption
                                                  .copyWith(
                                                color: Colors.orange
                                                    .withValues(alpha: 0.8),
                                                fontSize: 10,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            // 取消按鈕
                                            */
                                            /*
                                            TextButton(
                                              onPressed: _cancelRecognize,
                                              child: Text(
                                                '取消',
                                                style: AppTypography.bodySmall
                                                    .copyWith(
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ),
                                            */
                                            TextButton(
                                              onPressed: _cancelRecognize,
                                              child: const Text('取消'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (!_isRecognizing)
                                      Text(
                                        '截圖會先辨識成對話文字。請先確認我說／她說與內容，再加入對話；加入後再開始分析。',
                                        style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.warning,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    /*
                                      // 提示：有截圖時要先識別
                                      Text(
                                        '請先點擊上方按鈕識別截圖，再進行分析',
                                        style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.warning,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    */
                                    const SizedBox(height: 12),
                                  ] else if (conversation
                                      .messages.isNotEmpty) ...[
                                    // 沒有截圖時才顯示「開始分析」按鈕
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed:
                                            (_isAnalyzing || _isRecognizing)
                                                ? null
                                                : _runAnalysis,
                                        icon: const Icon(Icons.auto_awesome),
                                        label: const Text('開始分析'),
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  Text(
                                    'AI 會分析她的熱度、讀懂語意，教你最適合的回覆方式',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // 截圖識別結果
                          if (_showTelemetryDiagnostics &&
                              _lastRecognizeTelemetry != null &&
                              !_isRecognizing) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '上次 OCR 量測',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.onBackgroundPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _lastRecognizeTelemetry!.cacheHit
                                        ? '本次直接使用本機快取結果，未重新送出 OCR 請求'
                                        : '請求 ${_formatBytes(_lastRecognizeTelemetry!.requestBodyBytes)}｜本機準備 ${_formatDuration(_lastRecognizeTelemetry!.payloadPreparationDuration)}｜往返 ${_formatDuration(_lastRecognizeTelemetry!.roundTripDuration)}',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  if (_analysisTelemetryQuotaSummary(
                                          _lastRecognizeTelemetry!) !=
                                      null)
                                    Text(
                                      _analysisTelemetryQuotaSummary(
                                        _lastRecognizeTelemetry!,
                                      )!,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  Text(
                                    _lastRecognizeTelemetry!.cacheHit
                                        ? '本次使用本機快取，未重新上傳或呼叫 AI'
                                        : 'AI ${_formatDuration(_lastRecognizeTelemetry!.edgeAiDuration)}｜估計傳輸/排隊 ${_formatDuration(_lastRecognizeTelemetry!.estimatedTransferDuration)}',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  if (_recognizeTelemetryRecognitionSummary(
                                          _lastRecognizeTelemetry!) !=
                                      null)
                                    Text(
                                      _recognizeTelemetryRecognitionSummary(
                                          _lastRecognizeTelemetry!)!,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  if (_recognizeTelemetryNormalizationSummary(
                                          _lastRecognizeTelemetry!) !=
                                      null)
                                    Text(
                                      _recognizeTelemetryNormalizationSummary(
                                          _lastRecognizeTelemetry!)!,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  if (_recognizeTelemetryContextSummary(
                                          _lastRecognizeTelemetry!) !=
                                      null)
                                    Text(
                                      _recognizeTelemetryContextSummary(
                                          _lastRecognizeTelemetry!)!,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  _buildTelemetryGuardrailSection(
                                    _lastRecognizeTelemetry!,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_showTelemetryDiagnostics &&
                              _lastAnalysisTelemetry != null &&
                              !_isAnalyzing) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.info.withValues(alpha: 0.16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _analysisTelemetryRequestLabel(
                                      _lastAnalysisTelemetry!,
                                    ),
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.onBackgroundPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _analysisTelemetryTransportSummary(
                                      _lastAnalysisTelemetry!,
                                    ),
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  if (_analysisTelemetryQuotaSummary(
                                          _lastAnalysisTelemetry!) !=
                                      null)
                                    Text(
                                      _analysisTelemetryQuotaSummary(
                                        _lastAnalysisTelemetry!,
                                      )!,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  Text(
                                    'AI ${_formatDuration(_lastAnalysisTelemetry!.edgeAiDuration)}｜估計傳輸/排隊 ${_formatDuration(_lastAnalysisTelemetry!.estimatedTransferDuration)}',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  if (_recognizeTelemetryContextSummary(
                                          _lastAnalysisTelemetry!) !=
                                      null)
                                    Text(
                                      _recognizeTelemetryContextSummary(
                                        _lastAnalysisTelemetry!,
                                      )!,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  _buildTelemetryGuardrailSection(
                                    _lastAnalysisTelemetry!,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_recognizedConversation != null &&
                              _recognizedConversation!.messageCount > 0) ...[
                            _buildRecognizedConversationCard(),
                            const SizedBox(height: 16),
                          ],

                          if (_enthusiasmScore != null) ...[
                            if (_shouldGiveUp) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.error
                                          .withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Text('⚠️',
                                        style: TextStyle(fontSize: 20)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '這段互動目前不建議再投入，先保護自己的時間與情緒成本。',
                                        style: AppTypography.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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

                                  final cardData = CoachActionPolicy.evaluate(
                                    heatScore: _enthusiasmScore!,
                                    gameStage: _gameStage!,
                                    finalRecommendation: _finalRecommendation!,
                                    messages: conversation?.messages ??
                                        const <Message>[],
                                    practiceGoals: practiceGoals,
                                    isDataQualityFlagged: flagged,
                                    coachActionHint: _coachActionHint,
                                    psychology: _psychology,
                                  );

                                  return CoachActionCard(
                                    data: cardData,
                                    onLearningLinkTap: (articleId) {
                                      _clearAnalysisSnackBarsBeforePush();
                                      context.push('/article/$articleId');
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],

                          if (_finalRecommendation != null &&
                              _finalRecommendation!.content
                                  .trim()
                                  .isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withValues(alpha: 0.1),
                                    AppColors.primary.withValues(alpha: 0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text('🎯',
                                          style: TextStyle(fontSize: 20)),
                                      const SizedBox(width: 8),
                                      Text('AI 推薦回覆',
                                          style: AppTypography.titleLarge),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ..._buildRecommendationContent(
                                      _finalRecommendation!),
                                  const SizedBox(height: 12),
                                  Text(
                                    '📝 ${_finalRecommendation!.reason}',
                                    style: AppTypography.bodyMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '🧠 ${_finalRecommendation!.psychology}',
                                    style: AppTypography.caption,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_enthusiasmScore != null &&
                              _gameStage != null &&
                              _finalRecommendation != null) ...[
                            KeyedSubtree(
                              key: _coachChatCardKey,
                              child: CoachChatCard(
                                conversationId: widget.conversationId,
                                analysisSnapshot:
                                    _buildCoachChatAnalysisSnapshot(),
                                focusRequestToken: _coachChatFocusRequest,
                                prefillText: _coachChatPrefill,
                                onReturnToAnalysis: _returnToAnalysisOverview,
                                onQuotaExceeded: () {
                                  unawaited(_handleCoachChatQuotaExceeded());
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_isAnalyzing && _enthusiasmScore == null) ...[
                            Center(
                              child: StreamingAnalysisLoader(
                                label: _streamProgressLabel,
                                detail: _streamProgressDetail,
                              ),
                            ),
                          ],

                          if ((_isAnalyzing || _fullErrorMessage != null) &&
                              _streamContents.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildStreamingContentCard(),
                          ],

                          if (_fullErrorMessage != null) ...[
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
                              FullAnalysisRetryCard(
                                retriesRemaining: _fullErrorRetriesRemaining,
                                errorMessage: _fullErrorMessage,
                                onRetry: _fullErrorRetriesRemaining > 0
                                    ? _retryFullAnalysis
                                    : null,
                              ),
                          ],

                          if (_enthusiasmScore != null) ...[
                            // 實扣顯示常駐行（smoke P2 fix 2026-06-11）：
                            // 隨快照持久化，回看也顯示；SnackBar 保留即時感知。
                            AnalysisUsageSummaryLine(
                              usage: _lastAiResponse?['usage'],
                            ),
                            _buildDetailedAnalysisToggle(),
                            if (_showDetailedAnalysis) ...[
                              const SizedBox(height: 12),
                              ScoreHeroCard(
                                score: _enthusiasmScore!,
                                // previousScore: null for now
                              ),

                              // 五維度剖析 (Starter / Essential only)
                              if (_dimensionScores != null &&
                                  subscription.isPremium) ...[
                                const SizedBox(height: 16),
                                DimensionRadarChart(
                                  scores: DimensionScores(
                                    heat: _dimensionScores!['heat'] ?? 50,
                                    engagement:
                                        _dimensionScores!['engagement'] ?? 50,
                                    topicDepth:
                                        _dimensionScores!['topicDepth'] ?? 50,
                                    replyWillingness:
                                        _dimensionScores!['replyWillingness'] ??
                                            50,
                                    emotionalConnection: _dimensionScores![
                                            'emotionalConnection'] ??
                                        50,
                                  ),
                                ),
                              ],

                              // 對話階段指示器
                              if (_gameStage != null) ...[
                                const SizedBox(height: 16),
                                GameStageIndicator(
                                  currentStage: _gameStage!.current,
                                  status: _gameStage!.status,
                                  nextStep: _gameStage!.nextStep,
                                ),
                              ],

                              // 她話裡的意思
                              if (_psychology != null) ...[
                                const SizedBox(height: 16),
                                GlassmorphicContainer(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text('🧠',
                                              style: TextStyle(fontSize: 18)),
                                          const SizedBox(width: 8),
                                          Text('她話裡的意思',
                                              style: AppTypography.titleMedium
                                                  .copyWith(
                                                      color: AppColors
                                                          .glassTextPrimary)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(_psychology!.subtext,
                                          style: AppTypography.bodyMedium
                                              .copyWith(
                                                  color: AppColors
                                                      .glassTextPrimary)),
                                      if (_psychology!.shitTest != null) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppColors.warning
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            children: [
                                              const Text('⚠️',
                                                  style:
                                                      TextStyle(fontSize: 14)),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '互動測試訊號: ${_psychology!.shitTest}',
                                                  style: AppTypography.caption
                                                      .copyWith(
                                                          color: AppColors
                                                              .glassTextPrimary),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      if (_psychology!.qualificationSignal) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.check_circle,
                                                size: 16,
                                                color: AppColors.success),
                                            const SizedBox(width: 4),
                                            Text('她有主動投入訊號',
                                                style: AppTypography.caption
                                                    .copyWith(
                                                        color: AppColors
                                                            .glassTextPrimary)),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],

                              // Strategy
                              if (_strategy != null &&
                                  _strategy!.trim().isNotEmpty) ...[
                                const SizedBox(height: 16),
                                GlassmorphicContainer(
                                  child: Row(
                                    children: [
                                      const Text('💡',
                                          style: TextStyle(fontSize: 20)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _strategy!,
                                          style: AppTypography.bodyMedium
                                              .copyWith(
                                                  color: AppColors
                                                      .glassTextPrimary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Topic Depth (話題深度)
                              if (_topicDepth != null) ...[
                                const SizedBox(height: 16),
                                GlassmorphicContainer(
                                  child: Row(
                                    children: [
                                      Text(_topicDepth!.current.emoji,
                                          style: const TextStyle(fontSize: 20)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                '話題深度: ${_topicDepth!.current.label}',
                                                style: AppTypography.bodyMedium
                                                    .copyWith(
                                                        color: AppColors
                                                            .glassTextPrimary)),
                                            if (_topicDepth!
                                                .suggestion.isNotEmpty)
                                              Text(_topicDepth!.suggestion,
                                                  style: AppTypography.caption
                                                      .copyWith(
                                                          color: AppColors
                                                              .glassTextHint)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Health Check (對話健檢 - Essential 專屬)
                              if (_healthCheck != null &&
                                  subscription.isEssential &&
                                  _healthCheck!.issues.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: AppColors.warning
                                            .withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text('🩺',
                                              style: TextStyle(fontSize: 18)),
                                          const SizedBox(width: 8),
                                          Text('對話健檢',
                                              style: AppTypography.titleMedium),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ..._healthCheck!.issues
                                          .map((issue) => Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 4),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                        Icons.warning_amber,
                                                        size: 16,
                                                        color:
                                                            AppColors.warning),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                        child: Text(issue,
                                                            style: AppTypography
                                                                .bodyMedium)),
                                                  ],
                                                ),
                                              )),
                                      if (_healthCheck!
                                          .suggestions.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        ..._healthCheck!.suggestions
                                            .map((suggestion) => Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 4),
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                          Icons
                                                              .lightbulb_outline,
                                                          size: 16,
                                                          color: AppColors
                                                              .success),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                          child: Text(
                                                              suggestion,
                                                              style:
                                                                  AppTypography
                                                                      .caption)),
                                                    ],
                                                  ),
                                                )),
                                      ],
                                    ],
                                  ),
                                ),
                              ],

                              // Reply suggestions (5 種回覆)
                              if (_replies != null && _replies!.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Text('接法建議・${_replies!.length} 種風格',
                                        style: AppTypography.titleLarge
                                            .copyWith(
                                                color: AppColors
                                                    .onBackgroundPrimary)),
                                    const Spacer(),
                                    Text('← 左右滑動',
                                        style: AppTypography.caption.copyWith(
                                            color: AppColors.glassTextHint)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 360,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    children: [
                                      if (_replies!.containsKey('extend'))
                                        _buildHorizontalReplyCard(
                                            'extend', _replies!['extend']!,
                                            option: _replyOptions?['extend'],
                                            isRecommended:
                                                _isRecommendedReplyType(
                                                    'extend')),
                                      if (_replies!.containsKey('resonate'))
                                        _buildHorizontalReplyCard(
                                            'resonate', _replies!['resonate']!,
                                            option: _replyOptions?['resonate'],
                                            isRecommended:
                                                _isRecommendedReplyType(
                                                    'resonate')),
                                      if (_replies!.containsKey('tease'))
                                        _buildHorizontalReplyCard(
                                            'tease', _replies!['tease']!,
                                            option: _replyOptions?['tease'],
                                            isRecommended:
                                                _isRecommendedReplyType(
                                                    'tease')),
                                      if (_replies!.containsKey('humor'))
                                        _buildHorizontalReplyCard(
                                            'humor', _replies!['humor']!,
                                            option: _replyOptions?['humor'],
                                            isRecommended:
                                                _isRecommendedReplyType(
                                                    'humor')),
                                      if (_replies!.containsKey('coldRead'))
                                        _buildHorizontalReplyCard(
                                            'coldRead', _replies!['coldRead']!,
                                            option: _replyOptions?['coldRead'],
                                            isRecommended:
                                                _isRecommendedReplyType(
                                                    'coldRead')),
                                    ],
                                  ),
                                ),
                                // 如果只有 extend，根據用戶 tier 顯示不同提示
                                if (_replies!.length == 1 &&
                                    _replies!.containsKey('extend')) ...[
                                  const SizedBox(height: 12),
                                  Builder(
                                    builder: (context) {
                                      // Free 用戶：顯示升級提示
                                      if (subscription.isFreeUser) {
                                        return GestureDetector(
                                          onTap: () async =>
                                              _showPaywall(context),
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.3)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.lock_outline,
                                                    color: AppColors.primary),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '升級解鎖共鳴、調情、幽默、冷讀等回覆風格',
                                                    style: AppTypography
                                                        .bodyMedium
                                                        .copyWith(
                                                            color: AppColors
                                                                .primary),
                                                  ),
                                                ),
                                                const Icon(
                                                    Icons.arrow_forward_ios,
                                                    size: 16,
                                                    color: AppColors.primary),
                                              ],
                                            ),
                                          ),
                                        );
                                      }
                                      if (_analysisNeedsReplyRefresh(
                                        subscription,
                                      )) {
                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.auto_awesome,
                                                    color: AppColors.primary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      '你已升級完整版，這份分析仍是免費版結果。',
                                                      style: AppTypography
                                                          .bodyMedium
                                                          .copyWith(
                                                        color:
                                                            AppColors.primary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '重新分析一次，就能拿到完整回覆選項。',
                                                style: AppTypography.caption
                                                    .copyWith(
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              SizedBox(
                                                width: double.infinity,
                                                child: OutlinedButton.icon(
                                                  onPressed: (_isAnalyzing ||
                                                          _isRefreshingPremiumReplies)
                                                      ? null
                                                      : _refreshPremiumReplies,
                                                  icon: (_isAnalyzing ||
                                                          _isRefreshingPremiumReplies)
                                                      ? const SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                        )
                                                      : const Icon(
                                                          Icons.refresh_rounded,
                                                        ),
                                                  label: Text(
                                                    (_isAnalyzing ||
                                                            _isRefreshingPremiumReplies)
                                                        ? '正在刷新完整回覆...'
                                                        : '重新分析完整回覆',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      // 付費用戶：AI 判斷此情境最適合延展
                                      return Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppColors.onBackgroundSecondary
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.lightbulb_outline,
                                                color: AppColors
                                                    .onBackgroundSecondary),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'AI 判斷此情境最適合使用延展回覆',
                                                style: AppTypography.bodyMedium
                                                    .copyWith(
                                                  color: AppColors
                                                      .onBackgroundSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ],
                          ],

                          // 草稿潤飾功能：使用者已有方向時才用；判斷/策略交給 Coach 1:1。
                          if (_enthusiasmScore != null) ...[
                            const SizedBox(height: 24),
                            GlassmorphicContainer(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() =>
                                        _showOptimizeInput =
                                            !_showOptimizeInput),
                                    child: Row(
                                      children: [
                                        const Text('✏️',
                                            style: TextStyle(fontSize: 20)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '我已有草稿，幫我修自然',
                                            style: AppTypography.titleMedium
                                                .copyWith(
                                                    color: AppColors
                                                        .glassTextPrimary),
                                          ),
                                        ),
                                        Icon(
                                          _showOptimizeInput
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: AppColors.glassTextHint,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '適合你已經知道想回什麼，只想調整語氣、長度和壓迫感。還不確定該不該回，就用「問教練」。',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.glassTextSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                  if (!subscription.isEssential) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.lock_outline,
                                            color: AppColors.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '草稿潤飾器是 Essential 功能，升級後可直接把你的草稿修得更自然。',
                                              style: AppTypography.bodyMedium
                                                  .copyWith(
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                _showPaywall(context),
                                            child: const Text('查看方案'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else if (_showOptimizeInput) ...[
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _optimizeController,
                                      style: AppTypography.bodyMedium.copyWith(
                                          color: AppColors.glassTextPrimary),
                                      decoration: InputDecoration(
                                        hintText: '貼上你原本想傳的訊息...',
                                        helperText: '這裡只修草稿；想討論下一步，請用「問教練」。',
                                        hintStyle:
                                            AppTypography.bodyMedium.copyWith(
                                          color: AppColors.glassTextHint,
                                        ),
                                        helperStyle:
                                            AppTypography.caption.copyWith(
                                          color: AppColors.glassTextHint,
                                        ),
                                        filled: true,
                                        fillColor:
                                            Colors.white.withValues(alpha: 0.5),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                              color: AppColors.glassBorder),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                              color: AppColors.glassBorder),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                              color: AppColors.selectedStart,
                                              width: 1.5),
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(Icons.keyboard_hide,
                                              color: AppColors.glassTextHint),
                                          onPressed: _dismissKeyboard,
                                          tooltip: '收起鍵盤',
                                        ),
                                      ),
                                      maxLines: 3,
                                      textInputAction: TextInputAction.done,
                                      onEditingComplete: _dismissKeyboard,
                                      onTapOutside: (_) => _dismissKeyboard(),
                                      enabled: !_isOptimizing,
                                      onChanged: (_) => setState(() {}),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isOptimizing ||
                                                _optimizeController.text
                                                    .trim()
                                                    .isEmpty
                                            ? null
                                            : _optimizeMessage,
                                        icon: _isOptimizing
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : const Icon(Icons.auto_fix_high),
                                        label: Text(
                                          _isOptimizing ? '優化中...' : '優化這段草稿',
                                        ),
                                      ),
                                    ),
                                  ],
                                  // 顯示優化結果
                                  if (subscription.isEssential &&
                                      _optimizedMessage != null &&
                                      _optimizedMessage!
                                          .optimized.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    const Divider(),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Text('✨',
                                            style: TextStyle(fontSize: 18)),
                                        const SizedBox(width: 8),
                                        Text(
                                          '優化後草稿',
                                          style: AppTypography.titleMedium
                                              .copyWith(
                                            color: AppColors.glassTextPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.primaryDark
                                                .withValues(alpha: 0.94),
                                            AppColors.primary
                                                .withValues(alpha: 0.88),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.primaryLight
                                              .withValues(alpha: 0.55),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primaryDark
                                                .withValues(alpha: 0.22),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        _optimizedMessage!.optimized,
                                        style: AppTypography.bodyLarge.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (_optimizedMessage!
                                        .reason.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '💡 ${_optimizedMessage!.reason}',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.glassTextPrimary,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(
                                              text: _optimizedMessage!
                                                  .optimized));
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text('已複製到剪貼簿')),
                                          );
                                        },
                                        icon: const Icon(Icons.copy),
                                        label: const Text('複製草稿'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],

                          // 一致性提醒
                          if (_reminder != null &&
                              _reminder!.trim().isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Text('💬',
                                      style: TextStyle(fontSize: 18)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _reminder!,
                                      style: AppTypography.bodyMedium.copyWith(
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // 反饋區塊 (有分析結果時顯示)
                          if (_enthusiasmScore != null) ...[
                            const SizedBox(height: 24),
                            if (!_feedbackSubmitted) ...[
                              Divider(
                                  color: AppColors.onBackgroundSecondary
                                      .withValues(alpha: 0.5)),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('這個建議有幫助嗎？',
                                      style: AppTypography.bodyMedium.copyWith(
                                          color:
                                              AppColors.onBackgroundPrimary)),
                                  const SizedBox(width: 16),
                                  IconButton(
                                    icon: const Icon(Icons.thumb_up_outlined),
                                    onPressed: _isSubmittingFeedback
                                        ? null
                                        : () => _submitFeedback('positive'),
                                    tooltip: '有幫助',
                                    color: AppColors.success,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.thumb_down_outlined),
                                    onPressed: _isSubmittingFeedback
                                        ? null
                                        : () => setState(
                                            () => _showFeedbackForm = true),
                                    tooltip: '需要改進',
                                    color: AppColors.error,
                                  ),
                                ],
                              ),
                              if (_showFeedbackForm) ...[
                                const SizedBox(height: 16),
                                GlassmorphicContainer(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('哪裡需要改進？',
                                          style: AppTypography.bodyLarge
                                              .copyWith(
                                                  color: AppColors
                                                      .glassTextPrimary)),
                                      const SizedBox(height: 8),
                                      Text(
                                        '預設只送評分類別與結構化分析資訊，不附原始對話。',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.glassTextHint,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _buildFeedbackCategoryChip(
                                              'too_direct', '太直接'),
                                          _buildFeedbackCategoryChip(
                                              'unnatural', '不自然'),
                                          _buildFeedbackCategoryChip(
                                              'too_long', '回覆太長'),
                                          _buildFeedbackCategoryChip(
                                              'wrong_style', '不符合我的風格'),
                                          _buildFeedbackCategoryChip(
                                              'other', '其他'),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Checkbox(
                                            value: _includeFeedbackContext,
                                            onChanged: _isSubmittingFeedback
                                                ? null
                                                : (value) {
                                                    setState(() {
                                                      _includeFeedbackContext =
                                                          value ?? false;
                                                    });
                                                  },
                                          ),
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 12),
                                              child: Text(
                                                '附上最後 6 則對話片段，幫助我們排查（選填）',
                                                style: AppTypography.bodySmall
                                                    .copyWith(
                                                  color: AppColors
                                                      .glassTextPrimary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _feedbackCommentController,
                                        enabled: !_isSubmittingFeedback,
                                        style: AppTypography.bodyMedium
                                            .copyWith(
                                                color:
                                                    AppColors.glassTextPrimary),
                                        decoration: InputDecoration(
                                          hintText: '補充說明（選填）',
                                          helperText: '輸入完可先收起鍵盤，再送出反饋。',
                                          hintStyle: AppTypography.bodyMedium
                                              .copyWith(
                                                  color:
                                                      AppColors.glassTextHint),
                                          helperStyle:
                                              AppTypography.caption.copyWith(
                                            color: AppColors.glassTextHint,
                                          ),
                                          isDense: true,
                                          filled: true,
                                          fillColor: Colors.white
                                              .withValues(alpha: 0.5),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide(
                                                color: AppColors.glassBorder),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide(
                                                color: AppColors.glassBorder),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: const BorderSide(
                                                color: AppColors.selectedStart,
                                                width: 1.5),
                                          ),
                                          suffixIcon: IconButton(
                                            icon: Icon(Icons.keyboard_hide,
                                                color: AppColors.glassTextHint),
                                            onPressed: _dismissKeyboard,
                                            tooltip: '收起鍵盤',
                                          ),
                                        ),
                                        maxLength: 300,
                                        maxLines: 3,
                                        textInputAction: TextInputAction.done,
                                        onEditingComplete: _dismissKeyboard,
                                        onTapOutside: (_) => _dismissKeyboard(),
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: _feedbackCategory !=
                                                      null &&
                                                  !_isSubmittingFeedback
                                              ? () =>
                                                  _submitFeedback('negative')
                                              : null,
                                          child: _isSubmittingFeedback
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Text('送出反饋'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ] else ...[
                              Center(
                                child: Text(
                                  '已收到你的回饋',
                                  style: AppTypography.bodyMedium
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ],

                          if (_hasEditedAnalyzedMessage &&
                              conversation.messages.length <=
                                  _lastAnalyzedMessageCount) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      AppColors.warning.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.update,
                                      color: AppColors.warning),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '已修改已分析過的訊息，重新分析後會更新熱度與回覆建議。',
                                      style: AppTypography.bodyMedium,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed:
                                        _isAnalyzing ? null : _runAnalysis,
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('重新分析'),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // 新訊息提示 (根據最後一則是誰來顯示不同內容)
                          if (conversation.messages.isNotEmpty &&
                              _pendingMessageCount(conversation) > 0) ...[
                            const SizedBox(height: 16),
                            Builder(
                              builder: (context) {
                                final lastIsFromMe =
                                    conversation.messages.last.isFromMe;
                                final pendingCount =
                                    _pendingMessageCount(conversation);

                                if (lastIsFromMe) {
                                  // 最後是「我說」→ 只記錄，不預測她可能怎麼回。
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.arrow_downward,
                                            color: AppColors.primary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '有 $pendingCount 則新訊息，最後一則是你說。等她回覆後再按分析會比較準；現在不會自動預測她怎麼回。',
                                            style: AppTypography.bodyMedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  // 最後是「她說」→ 可以重新分析
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.warning
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: AppColors.warning
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.update,
                                            color: AppColors.warning),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '有 $pendingCount 則新訊息，可以更新下一步建議。',
                                            style: AppTypography.bodyMedium,
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: _isAnalyzing
                                              ? null
                                              : _runAnalysis,
                                          icon: const Icon(Icons.refresh,
                                              size: 18),
                                          label: const Text('分析新增內容'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            ),
                          ],

                          const SizedBox(height: 24),
                        ],
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

  bool _isRecommendedReplyType(String type) {
    final pick = _finalRecommendation?.pick.trim();
    return pick == type && (_replies?[type]?.trim().isNotEmpty ?? false);
  }

  Widget _buildHorizontalReplyCard(
    String type,
    String content, {
    ReplyOption? option,
    bool isRecommended = false,
  }) {
    return ReplyStyleCard(
      type: type,
      content: content,
      option: option,
      isRecommended: isRecommended,
      onCopy: (_, message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 1),
          ),
        );
      },
    );
  }

  Widget _buildCollapsibleMessageInput() {
    if (_isAnalyzing) {
      return const SizedBox.shrink();
    }

    // 沒有分析結果時，直接顯示輸入區
    if (_enthusiasmScore == null) {
      return _buildMessageInput(showScreenshotUpload: false);
    }

    // 有分析結果時，顯示可展開的「繼續對話」區塊
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 收合時顯示「繼續對話」按鈕
          if (!_showContinueConversation)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                border: Border(
                  top: BorderSide(color: AppColors.glassBorder),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openCoachQuestion,
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('問教練：我現在該怎麼做？'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openContinueComposer,
                            icon: const Icon(Icons.add_comment_outlined),
                            label: const Text('補聊天紀錄'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(
                                color:
                                    AppColors.primary.withValues(alpha: 0.45),
                              ),
                              foregroundColor: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openNewConversationSheet,
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('開新對話'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(
                                color: AppColors.glassBorder,
                              ),
                              foregroundColor: AppColors.glassTextPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '問教練：釐清不扣，正式建議才扣 1 則。補聊天紀錄後，重新分析只扣新增內容。',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.unselectedText,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            // 展開時顯示完整輸入區
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 收合按鈕
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.glassWhite,
                    border: Border(
                      top: BorderSide(color: AppColors.glassBorder),
                    ),
                  ),
                  child: InkWell(
                    onTap: _collapseComposerAndShowMessages,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.keyboard_arrow_down,
                              color: AppColors.unselectedText, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            '收起補聊天紀錄，回到分析結果',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.unselectedText),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildMessageInput(showScreenshotUpload: true),
              ],
            ),
        ],
      ),
    );
  }

  /// 建立訊息輸入區
  Widget _buildMessageInput({required bool showScreenshotUpload}) {
    final canAddManualMessage =
        !_isAnalyzing && !_isRecognizing && _selectedImages.isEmpty;
    final isTypingMessage = _messageFocusNode.hasFocus;
    final showComposerHelp = !isTypingMessage;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        border: Border(
          top: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showScreenshotUpload) ...[
              _buildContinueComposerToolbar(),
              const SizedBox(height: 12),
            ],
            if (showScreenshotUpload && showComposerHelp) ...[
              _buildConversationScreenshotSection(),
              const SizedBox(height: 12),
            ],
            if (showComposerHelp) ...[
              if (_lastManualAddedContent != null)
                _buildManualAddedFeedback()
              else if (_lastScreenshotAddedCount != null)
                _buildScreenshotAddedFeedback()
              else
                _buildManualInputGuide(isContinue: _enthusiasmScore != null),
              const SizedBox(height: 10),
            ],
            // 輸入框 + 貼上按鈕
            TextField(
              key: _messageInputKey,
              controller: _messageController,
              focusNode: _messageFocusNode,
              onTap: _scheduleMessageInputIntoView,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.glassTextPrimary),
              decoration: InputDecoration(
                hintText: '貼上或輸入新的一則訊息...',
                helperText: showScreenshotUpload
                    ? '輸入完選「她說／我說」。不想補了可點上方「回分析」。'
                    : '輸入完先收起鍵盤，再選這句是她說，還是我說。',
                helperStyle: AppTypography.caption.copyWith(
                  color: AppColors.glassTextHint,
                ),
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color: AppColors.glassTextHint,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.glassBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: AppColors.selectedStart, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 96),
                // iOS multiline keyboards do not always show an obvious dismiss
                // affordance, so keep explicit controls inside the visible field.
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.keyboard_hide,
                          color: AppColors.glassTextHint),
                      onPressed: _dismissKeyboard,
                      tooltip: '收起鍵盤',
                    ),
                    IconButton(
                      icon: Icon(Icons.content_paste,
                          color: AppColors.glassTextHint),
                      onPressed: _isAnalyzing
                          ? null
                          : () async {
                              final data =
                                  await Clipboard.getData(Clipboard.kTextPlain);
                              if (data?.text != null &&
                                  data!.text!.isNotEmpty) {
                                _messageController.text = data.text!;
                                _messageController.selection =
                                    TextSelection.fromPosition(
                                  TextPosition(
                                      offset: _messageController.text.length),
                                );
                              }
                            },
                      tooltip: '貼上',
                    ),
                  ],
                ),
              ),
              maxLines: 5,
              minLines: 2,
              textInputAction: TextInputAction.done,
              onEditingComplete: _dismissKeyboard,
              onTapOutside: (_) => _dismissKeyboard(),
              enabled: !_isAnalyzing,
            ),
            const SizedBox(height: 12),
            // 新增按鈕 - 加大點擊區域
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: canAddManualMessage
                          ? () => _addMessage(isFromMe: false)
                          : null,
                      icon: const Text('👩', style: TextStyle(fontSize: 18)),
                      label: Text('這句是她說',
                          style: TextStyle(color: AppColors.glassTextPrimary)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(
                            color: AppColors.glassBorder, width: 1.5),
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: canAddManualMessage
                            ? const [AppColors.ctaStart, AppColors.ctaEnd]
                            : [
                                AppColors.ctaStart.withValues(alpha: 0.35),
                                AppColors.ctaEnd.withValues(alpha: 0.35),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.ctaStart.withValues(
                              alpha: canAddManualMessage ? 0.3 : 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: canAddManualMessage
                            ? () => _addMessage(isFromMe: true)
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('👤', style: TextStyle(fontSize: 18)),
                              SizedBox(width: 8),
                              Text('這句是我說',
                                  style: TextStyle(
                                      color: canAddManualMessage
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueComposerToolbar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.add_comment_outlined,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '正在補聊天紀錄',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.glassTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '只補新的來回訊息，不會重扣已分析內容。',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.glassTextSecondary,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _collapseComposerAndShowMessages,
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            label: const Text('回分析'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 第一次分析結果出現時的 coach mark。
/// 暗色 backdrop + 卡片置於螢幕下半，向上的箭頭視覺指向上方 bubble 區。
class _EditMessageCoachMark extends StatelessWidget {
  const _EditMessageCoachMark({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
              child: GestureDetector(
                onTap: () {}, // 吸收卡片內部點擊，避免穿透到 backdrop dismiss
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.keyboard_double_arrow_up_rounded,
                        size: 44,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '💡 你知道嗎？',
                        style: AppTypography.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '長按上方的訊息泡泡可以\n編輯內容、切換角色、或刪除整則',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onDismiss,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('知道了'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

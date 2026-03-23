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
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/message_calculator.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/analysis_preview_dialog.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../../shared/widgets/enthusiasm_gauge.dart';
import '../../../../shared/widgets/game_stage_indicator.dart';
import '../../../../shared/widgets/reply_card.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/data/services/memory_service.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/conversation_summary.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../../conversation/presentation/widgets/message_bubble.dart';
import '../../data/services/ocr_recognition_cache_service.dart';
import '../../data/services/analysis_service.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/game_stage.dart';
import '../../domain/services/screenshot_recognition_helper.dart';
import '../widgets/screenshot_recognition_dialog.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../subscription/domain/services/subscription_tier_helper.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const AnalysisScreen({super.key, required this.conversationId});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

enum _AnalysisErrorOrigin {
  analysis,
  recognition,
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  final MemoryService _memoryService = MemoryService();
  bool _isAnalyzing = false;
  int? _enthusiasmScore;
  String? _strategy;
  Map<String, String>? _replies;
  TopicDepth? _topicDepth;
  HealthCheck? _healthCheck;
  String? _errorMessage;
  AnalysisErrorAction? _errorAction;
  _AnalysisErrorOrigin? _errorOrigin;
  String? _errorGuidance;

  // GAME 階段分析
  GameStageInfo? _gameStage;

  // 心理分析
  PsychologyAnalysis? _psychology;

  // 最終建議
  FinalRecommendation? _finalRecommendation;

  // 一致性提醒
  String? _reminder;

  // 冰點放棄建議
  // ignore: prefer_final_fields
  bool _shouldGiveUp = false;

  // 反饋相關
  bool _feedbackSubmitted = false;
  bool _showFeedbackForm = false;

  // 訊息優化功能
  bool _showOptimizeInput = false;
  bool _isOptimizing = false;
  final _optimizeController = TextEditingController();
  OptimizedMessage? _optimizedMessage;

  // 「我說」話題延續功能
  MyMessageAnalysis? _myMessageAnalysis;
  bool _isAnalyzingMyMessage = false;
  String? _feedbackCategory;
  final _feedbackCommentController = TextEditingController();
  Map<String, dynamic>? _lastAiResponse; // 儲存最後的 AI 回應

  // 對話延續功能
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showAllMessages = false;

  // 截圖上傳功能
  List<Uint8List> _selectedImages = [];
  List<SelectedImageMetrics> _selectedImageMetrics = [];
  RecognizedConversation? _recognizedConversation;
  String? _recognizedWarningMessage;
  bool _hasPendingRecognitionImport = false;
  bool _isRecognizing = false;
  AnalysisProgressStage _recognizeStage =
      AnalysisProgressStage.preparingPayload;
  AnalysisTelemetry? _lastRecognizeTelemetry;
  AnalysisTelemetry? _lastAnalysisTelemetry;
  static const String _importModeAppendCurrent =
      ScreenshotRecognitionHelper.importModeAppendCurrent;
  static const String _importModeNewConversation =
      ScreenshotRecognitionHelper.importModeNewConversation;

  // 分析後繼續對話展開狀態
  bool _showContinueConversation = false;

  Future<void> _showPaywall(BuildContext context) async {
    final unlocked = await context.push<bool>('/paywall');
    if (!mounted) {
      return;
    }

    await ref.read(subscriptionProvider.notifier).refresh();
    if (!mounted || unlocked != true) {
      return;
    }

    final subscription = ref.read(subscriptionProvider);
    if (_analysisNeedsReplyRefresh(subscription)) {
      _showFloatingSnackBar('已升級完整版，重新分析後就能解鎖完整回覆選項。');
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
        return '保留標題列、左右對話氣泡與外層主訊息；長截圖可拆成 2-3 張分段匯入。';
      case AnalysisErrorAction.shortenInput:
        return _selectedImages.isNotEmpty
            ? '每張截圖建議少於 15 則訊息；若內容太長，請拆成多張後再匯入。'
            : '可先刪減較舊訊息、縮短草稿，或分成兩次分析。';
      case AnalysisErrorAction.upgrade:
        return '升級後可解鎖更完整的分析能力與較高額度。';
      case AnalysisErrorAction.wait:
        return '這通常是暫時性的服務忙碌或逾時問題，稍後再試即可。';
      case AnalysisErrorAction.addIncomingMessage:
        return _selectedImages.isNotEmpty
            ? '先把截圖識別進目前對話，或在下方補上一則她的回覆後再分析。'
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

    if (_enthusiasmScore != null && !_showContinueConversation) {
      setState(() {
        _showContinueConversation = true;
      });
      await _scrollToBottom(delay: const Duration(milliseconds: 120));
      return;
    }

    await _scrollToBottom();
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
    _restorePersistedAnalysis();
    // 不再自動分析，讓用戶手動點擊
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
    _strategy = result.strategy;
    _replies = result.replies;
    _topicDepth = result.topicDepth;
    _healthCheck = result.healthCheck;
    _gameStage = result.gameStage;
    _psychology = result.psychology;
    _finalRecommendation = result.recommendation;
    _reminder = result.reminder;
    _shouldGiveUp = result.shouldGiveUp;
    _lastAiResponse = result.rawResponse;

    if (resetFeedbackState) {
      _feedbackSubmitted = false;
      _showFeedbackForm = false;
      _feedbackCategory = null;
    }
  }

  Future<void> _persistLatestAnalysisSnapshot(
    Conversation conversation,
    AnalysisResult result,
  ) async {
    final repository = ref.read(conversationRepositoryProvider);
    final conv = repository.getConversation(widget.conversationId);
    if (conv == null) {
      return;
    }

    conv.lastEnthusiasmScore = result.enthusiasmScore;
    conv.lastAnalyzedMessageCount = conversation.messages.length;
    conv.lastAnalysisSnapshotJson =
        result.rawResponse == null || result.rawResponse!.isEmpty
            ? null
            : jsonEncode(result.rawResponse);

    await repository.updateConversation(conv);
    ref.invalidate(conversationsProvider);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _feedbackCommentController.dispose();
    _optimizeController.dispose();
    super.dispose();
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

    return '識別並加入目前對話 (${_selectedImages.length} 張)';
  }

  void _handleSelectedImagesChanged(List<Uint8List> images) {
    setState(() {
      _selectedImages = List<Uint8List>.from(images);
      _selectedImageMetrics = [];
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
    });
  }

  void _discardPendingRecognitionDraft() {
    setState(() {
      _recognizedConversation = null;
      _recognizedWarningMessage = null;
      _hasPendingRecognitionImport = false;
    });
  }

  Widget _buildConversationScreenshotSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '也可以直接上傳新的聊天截圖，先識別進這段對話，再接著分析。',
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
        if (_selectedImages.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
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
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isRecognizing
                ? '識別中：${_recognizeStageLabel(_recognizeStage)}'
                : '先把截圖識別進目前對話，再選「她說 / 我說」補上新的訊息。',
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
    final importMode = dialogResult.importMode;
    final updatedRecognized = recognized.copyWith(
      contactName: newName.isNotEmpty ? newName : recognized.contactName,
      messageCount: editedRecognizedMessages.length,
      messages: editedRecognizedMessages,
    );

    if (importMode == _importModeNewConversation) {
      final createdConversation = await repository.createConversation(
        name: _resolveImportedConversationName(
          enteredName: newName,
          recognizedName: recognized.contactName,
        ),
        messages: importedMessages,
      );

      if (meeting != null && duration != null) {
        createdConversation.sessionContext = SessionContext(
          meetingContext: meeting,
          duration: duration,
        );
      }
      await repository.updateConversation(createdConversation);
      ref.invalidate(conversationsProvider);
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
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已建立新對話並匯入 $messageCount 則訊息'),
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
      );
    }

    conv.messages.addAll(importedMessages);
    await repository.updateConversation(conv);
    ref.invalidate(conversationsProvider);
    ref.invalidate(conversationProvider(widget.conversationId));

    final messageCount = importedMessages.length;
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
    });

    final canAnalyzeImportedConversation =
        _buildMessagesForReplyAnalysis(conv.messages) != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已加入目前對話，共 $messageCount 則訊息'),
        backgroundColor: Colors.green,
        action: canAnalyzeImportedConversation
            ? SnackBarAction(
                label: '立即分析',
                textColor: Colors.white,
                onPressed: _runAnalysis,
              )
            : null,
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
          content: Text('已保留這次識別結果，你可以稍後再繼續匯入。'),
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
    if (content.isEmpty) return;

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
    await repository.updateConversation(conversation);

    // 刷新對話列表，確保返回首頁時能看到更新
    ref.invalidate(conversationsProvider);

    // 清空輸入框
    _messageController.clear();

    // 根據訊息類型決定行為
    if (!isFromMe) {
      // 「她說」：不自動分析，顯示提示讓用戶決定
      _showAnalyzePrompt();
    } else {
      // 「我說」：Essential 用戶自動分析話題延續 (Haiku, 快速)
      final subscription = ref.read(subscriptionProvider);
      if (subscription.tier == 'essential') {
        await _runMyMessageAnalysis();
      } else {
        setState(() {
          _myMessageAnalysis = null;
        });
      }
    }

    // 滾動到頂部顯示新分析結果
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 顯示分析提示，讓用戶決定是否分析「她說」的訊息
  void _showAnalyzePrompt() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已新增對方訊息'),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '分析熱度與建議',
          textColor: AppColors.primary,
          onPressed: _runAnalysis,
        ),
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

  Future<bool> _confirmAnalysisPreview(List<Message> requestMessages) async {
    if (!mounted) {
      return false;
    }

    return showAnalysisPreviewDialog(
      context: context,
      preview: MessageCalculator.previewConversation(requestMessages),
      usage: _buildPreviewUsageData(),
      onUpgrade: () {
        Navigator.of(context, rootNavigator: true).pop(false);
        _showPaywall(context);
      },
    );
  }

  void _syncSubscriptionUsageFromResult(AnalysisResult result) {
    final usage = result.rawResponse?['usage'];
    if (usage is! Map) {
      return;
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
    final retrySummary = telemetry.retryCount > 0
        ? '重試 ${telemetry.retryCount} 次'
        : null;
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
        initialMeetingContext: defaultImportMode == _importModeAppendCurrent
            ? currentConversation.sessionContext?.meetingContext
            : null,
        initialDuration: defaultImportMode == _importModeAppendCurrent
            ? currentConversation.sessionContext?.duration
            : null,
        initialImportMode: defaultImportMode,
        forceShowSessionContextFields:
            currentConversation.sessionContext == null,
      ),
    );
  }

  // 識別計時器
  int _recognizeElapsedSeconds = 0;
  bool _recognizeCancelled = false;

  /// 識別截圖並加入對話（不進行完整分析）
  Future<void> _recognizeAndAddToConversation() async {
    if (_selectedImages.isEmpty) return;

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

    // 複製圖片列表，避免狀態問題
    final imagesToProcess = List<Uint8List>.from(_selectedImages);
    _debugLog('複製圖片列表完成，數量: ${imagesToProcess.length}');

    try {
      // 呼叫 API 識別截圖（純識別模式，不做完整分析，節省時間和額度）
      _debugLog('呼叫 API... (timeout: 120s)');
      final cachedRecognition = await OcrRecognitionCacheService.read(
        imagesToProcess,
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
            sessionContext: conversation.sessionContext,
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
          });
          return;
        }

        setState(() => _isRecognizing = false);
        if (cachedRecognition != null) {
          _showFloatingSnackBar('已使用最近一次相同截圖的識別結果');
        }

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
              content: Text('已保留這次識別結果，你可以稍後再繼續匯入。'),
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

  Future<void> _runAnalysis() async {
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
          guidance: '你可以先在下方補上一則她的回覆，或先上傳截圖做識別再分析。',
        );
      });
      return;
    }

    final messagesForAnalysis = _buildMessagesForReplyAnalysis(
      conversation.messages,
    );
    if (messagesForAnalysis == null) {
      final subscription = ref.read(subscriptionProvider);
      final errorMessage = subscription.tier == 'essential'
          ? '目前還沒有她的回覆，暫時無法做一般分析。你可以等她回訊後再分析，或使用下方的「我說」延續建議。'
          : '目前還沒有她的回覆，暫時無法分析。你可以先把對話存著，等她回訊後再回來分析。';
      setState(() {
        _isAnalyzing = false;
        _applyErrorState(
          message: errorMessage,
          action: AnalysisErrorAction.addIncomingMessage,
          origin: _AnalysisErrorOrigin.analysis,
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
      final confirmed = await _confirmAnalysisPreview(
        analysisContext.requestMessages,
      );
      if (!confirmed || !mounted) {
        return;
      }

      setState(() {
        _isAnalyzing = true;
      });

      final analysisService = AnalysisService();
      final result = await analysisService.analyzeConversation(
        analysisContext.requestMessages,
        sessionContext: conversation.sessionContext,
        conversationSummary: analysisContext.conversationSummary,
        onTelemetry: _handleAnalysisTelemetry,
      );

      // 記錄已分析的訊息數量
      _lastAnalyzedMessageCount = conversation.messages.length;

      setState(() {
        _isAnalyzing = false;
        _applyAnalysisResult(result);
        _enthusiasmScore = result.enthusiasmScore;
        _strategy = result.strategy;
        _replies = result.replies;
        _topicDepth = result.topicDepth;
        _healthCheck = result.healthCheck;
        _gameStage = result.gameStage;
        _psychology = result.psychology;
        _finalRecommendation = result.recommendation;
        _reminder = result.reminder;
        _shouldGiveUp = result.shouldGiveUp;
        _lastAiResponse = result.rawResponse; // 儲存原始 AI 回應
        _feedbackSubmitted = false; // 重置反饋狀態
        _showFeedbackForm = false;
        _feedbackCategory = null;
      });

      try {
        await _persistLatestAnalysisSnapshot(conversation, result);
      } catch (_) {
        // Ignore errors in test environment
      }

      _syncSubscriptionUsageFromResult(result);
    } on DailyLimitExceededException catch (e) {
      setState(() {
        _isAnalyzing = false;
        _applyErrorState(
          message: '今日額度已用完 (${e.used}/${e.dailyLimit})，明天再來！',
          action: AnalysisErrorAction.wait,
          origin: _AnalysisErrorOrigin.analysis,
        );
      });
    } on MonthlyLimitExceededException catch (e) {
      setState(() {
        _isAnalyzing = false;
        _applyErrorState(
          message: '本月額度已用完 (${e.used}/${e.monthlyLimit})，升級方案獲得更多！',
          action: AnalysisErrorAction.upgrade,
          origin: _AnalysisErrorOrigin.analysis,
        );
      });
    } on AnalysisException catch (e) {
      setState(() {
        _isAnalyzing = false;
        _applyErrorState(
          message: e.message,
          action: e.suggestedAction,
          origin: _AnalysisErrorOrigin.analysis,
        );
      });
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

  /// 「我說」話題延續分析（Essential 專屬）
  Future<void> _runMyMessageAnalysis() async {
    setState(() {
      _isAnalyzingMyMessage = true;
      _myMessageAnalysis = null;
      _lastAnalysisTelemetry = null;
    });

    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) {
      setState(() => _isAnalyzingMyMessage = false);
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
        analyzeMode: 'my_message',
        onTelemetry: _handleAnalysisTelemetry,
      );

      setState(() {
        _isAnalyzingMyMessage = false;
        _myMessageAnalysis = result.myMessageAnalysis;
      });
      _syncSubscriptionUsageFromResult(result);
    } on AnalysisException catch (e) {
      setState(() {
        _isAnalyzingMyMessage = false;
      });
      _showFloatingSnackBar(e.message);
    } catch (e) {
      setState(() {
        _isAnalyzingMyMessage = false;
      });
      _showFloatingSnackBar('分析暫時失敗，請稍後再試。');
    }
  }

  /// 優化用戶訊息
  Future<void> _optimizeMessage() async {
    final draft = _optimizeController.text.trim();
    if (draft.isEmpty) return;

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
      _syncSubscriptionUsageFromResult(result);
    } on AnalysisException catch (e) {
      if (!mounted) return;
      setState(() {
        _isOptimizing = false;
      });
      _showFloatingSnackBar(e.message);
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

  int _calculateMaxReplyLength(Conversation conversation) {
    final theirMessages = conversation.theirMessages;
    if (theirMessages.isEmpty) return 50;

    final lastTheirMessage = theirMessages.last;
    return (lastTheirMessage.wordCount * AppConstants.goldenRuleMultiplier)
        .round();
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
        buffer.writeln('心理解讀: ${_psychology!.subtext}');
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
        buffer.writeln('心理學依據: ${_finalRecommendation!.psychology}');
      }

      if (_healthCheck != null && _healthCheck!.issues.isNotEmpty) {
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
    if (_feedbackSubmitted) return;

    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) return;

    // 取得用戶訂閱資訊
    final subscription = ref.read(subscriptionProvider);
    final userTier = subscription.tier;

    // 建構對話片段 (最後 6 則訊息)
    final messages = conversation.messages;
    final lastMessages =
        messages.length > 6 ? messages.sublist(messages.length - 6) : messages;
    final conversationSnippet = lastMessages
        .map((m) => '${m.isFromMe ? "我" : "她"}: ${m.content}')
        .join('\n');

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
          'aiResponse': _lastAiResponse,
          'userTier': userTier,
          'modelUsed': _lastAiResponse?['usage']?['model'],
        },
      );

      if (response.status == 200) {
        setState(() {
          _feedbackSubmitted = true;
          _showFeedbackForm = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(rating == 'positive' ? '謝謝回饋！' : '感謝你的回饋，我們會持續改進！'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('反饋送出失敗，請稍後再試')),
        );
      }
    }
  }

  /// 截圖識別結果卡片
  Widget _buildRecognizedConversationCard() {
    final recognized = _recognizedConversation!;
    final displayWarning = _recognizedWarningMessage ?? recognized.warning;
    final displayRecognized = recognized.copyWith(warning: displayWarning);
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
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.info.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              _recognitionActionGuidance(displayRecognized),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextPrimary,
                height: 1.45,
              ),
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
          if (_hasPendingRecognitionImport) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _resumeRecognitionImport,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('繼續匯入設定'),
                  ),
                ),
                const SizedBox(width: 8),
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
      onSelected: (selected) {
        setState(() => _feedbackCategory = selected ? value : null);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
              onPressed: () => context.go('/'),
            ),
          ),
          body: const Center(child: Text('找不到對話')),
        ),
      );
    }

    final maxLength = _calculateMaxReplyLength(conversation);

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(conversation.name, style: AppTypography.titleLarge),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/'),
          ),
          actions: [
            // 匯出按鈕
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: '匯出對話紀錄',
              onPressed: () => _exportConversation(conversation),
            ),
            if (_isAnalyzing)
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
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      // 移除 physics 設定，使用平台預設（與第一頁一致）
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Messages preview
                          GlassmorphicContainer(
                            child: Column(
                              children: [
                                // 顯示訊息 (可展開/收合)
                                ...(_showAllMessages
                                        ? conversation.messages
                                        : conversation.messages.take(5))
                                    .map((m) => MessageBubble(message: m)),
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
                                          onPressed: _isAnalyzing ||
                                                  _isRecognizing
                                              ? null
                                              : () => _handleErrorAction(
                                                  _errorAction!),
                                          child: Text(
                                            _primaryErrorActionLabel(
                                              _errorAction!,
                                            ),
                                          ),
                                        ),
                                      if (_shouldShowSecondaryErrorAction())
                                        OutlinedButton(
                                          onPressed:
                                              _isAnalyzing || _isRecognizing
                                                  ? null
                                                  : () => setState(
                                                      _resetErrorState),
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
                          if (_enthusiasmScore == null &&
                              !_isAnalyzing &&
                              _errorMessage == null) ...[
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
                                  const Text('🎯',
                                      style: TextStyle(fontSize: 48)),
                                  const SizedBox(height: 12),
                                  Text(
                                    '準備好分析這段對話了嗎？',
                                    style: AppTypography.titleMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '我會分析熱度、對話進度、心理解讀，\n並給你最適合的回覆建議。',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),

                                  // 截圖上傳區
                                  ImagePickerWidget(
                                    maxImages: 3,
                                    externalImages: _selectedImages, // 同步外部狀態
                                    onImagesChanged:
                                        _handleSelectedImagesChanged,
                                    onMetricsChanged:
                                        _handleSelectedImageMetricsChanged,
                                  ),
                                  const SizedBox(height: 8),

                                  // 對話長度提示
                                  Text(
                                    '建議每張截圖保留 15 則內完整對話；過長請拆成 2-3 張，辨識會更穩。',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.unselectedText,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),

                                  // 如果有截圖，顯示「識別並加入對話」按鈕
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
                                            : '識別並加入對話 (${_selectedImages.length}張)'),
                                        */
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          backgroundColor: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Debug 狀態顯示
                                    if (_isRecognizing)
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
                                        '截圖會先辨識成對話文字並加入目前草稿，確認沒問題後再開始分析。',
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
                                  ] else ...[
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
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // 截圖識別結果
                          if (_lastRecognizeTelemetry != null &&
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
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_lastAnalysisTelemetry != null &&
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

                          // Enthusiasm Gauge
                          if (_enthusiasmScore != null) ...[
                            Text('熱度分析',
                                style: AppTypography.titleLarge.copyWith(
                                    color: AppColors.onBackgroundPrimary)),
                            const SizedBox(height: 12),
                            EnthusiasmGauge(score: _enthusiasmScore!),

                            // 冰點放棄建議
                            if (_shouldGiveUp) ...[
                              const SizedBox(height: 12),
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
                                    const Text('🚫',
                                        style: TextStyle(fontSize: 20)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '熱度過低，建議放棄這段對話，開始新的機會',
                                        style: AppTypography.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ] else if (_isAnalyzing) ...[
                            const Center(
                              child: Column(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('分析中...'),
                                ],
                              ),
                            ),
                          ],

                          // GAME 階段指示器
                          if (_gameStage != null) ...[
                            const SizedBox(height: 16),
                            GameStageIndicator(
                              currentStage: _gameStage!.current,
                              status: _gameStage!.status,
                              nextStep: _gameStage!.nextStep,
                            ),
                          ],

                          // 心理分析 (淺溝通解讀)
                          if (_psychology != null) ...[
                            const SizedBox(height: 16),
                            GlassmorphicContainer(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text('🧠',
                                          style: TextStyle(fontSize: 18)),
                                      const SizedBox(width: 8),
                                      Text('心理解讀',
                                          style: AppTypography.titleMedium
                                              .copyWith(
                                                  color: AppColors
                                                      .glassTextPrimary)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(_psychology!.subtext,
                                      style: AppTypography.bodyMedium.copyWith(
                                          color: AppColors.glassTextPrimary)),
                                  if (_psychology!.shitTest != null) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        children: [
                                          const Text('⚠️',
                                              style: TextStyle(fontSize: 14)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '偵測到廢測: ${_psychology!.shitTest}',
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
                                            size: 16, color: AppColors.success),
                                        const SizedBox(width: 4),
                                        Text('她在向你證明自己',
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
                          if (_strategy != null) ...[
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
                                      style: AppTypography.bodyMedium.copyWith(
                                          color: AppColors.glassTextPrimary),
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
                                        if (_topicDepth!.suggestion.isNotEmpty)
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
                              _healthCheck!.issues.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppColors.warning
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                                const Icon(Icons.warning_amber,
                                                    size: 16,
                                                    color: AppColors.warning),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                    child: Text(issue,
                                                        style: AppTypography
                                                            .bodyMedium)),
                                              ],
                                            ),
                                          )),
                                  if (_healthCheck!.suggestions.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    ..._healthCheck!.suggestions
                                        .map((suggestion) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 4),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                      Icons.lightbulb_outline,
                                                      size: 16,
                                                      color: AppColors.success),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                      child: Text(suggestion,
                                                          style: AppTypography
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
                          if (_replies != null) ...[
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Text('建議回覆',
                                    style: AppTypography.titleLarge.copyWith(
                                        color: AppColors.onBackgroundPrimary)),
                                const Spacer(),
                                Text(
                                  '字數上限: $maxLength字',
                                  style: AppTypography.caption
                                      .copyWith(color: AppColors.glassTextHint),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // 延展回覆 (所有方案都有)
                            if (_replies!.containsKey('extend'))
                              ReplyCard(
                                type: ReplyType.extend,
                                content: _replies!['extend']!,
                              ),
                            // 以下回覆根據 API 回傳結果顯示 (已在後端過濾)
                            if (_replies!.containsKey('resonate'))
                              ReplyCard(
                                type: ReplyType.resonate,
                                content: _replies!['resonate']!,
                              ),
                            if (_replies!.containsKey('tease'))
                              ReplyCard(
                                type: ReplyType.tease,
                                content: _replies!['tease']!,
                              ),
                            if (_replies!.containsKey('humor'))
                              ReplyCard(
                                type: ReplyType.humor,
                                content: _replies!['humor']!,
                              ),
                            if (_replies!.containsKey('coldRead'))
                              ReplyCard(
                                type: ReplyType.coldRead,
                                content: _replies!['coldRead']!,
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
                                      onTap: () async => _showPaywall(context),
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
                                                style: AppTypography.bodyMedium
                                                    .copyWith(
                                                        color:
                                                            AppColors.primary),
                                              ),
                                            ),
                                            const Icon(Icons.arrow_forward_ios,
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
                                        borderRadius: BorderRadius.circular(8),
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
                                                    color: AppColors.primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '重新分析一次，就能拿到完整回覆選項。',
                                            style:
                                                AppTypography.caption.copyWith(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed: _isAnalyzing
                                                  ? null
                                                  : _runAnalysis,
                                              icon: const Icon(
                                                Icons.refresh_rounded,
                                              ),
                                              label: const Text('重新分析完整回覆'),
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
                                      borderRadius: BorderRadius.circular(8),
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

                          // 最終建議 (AI 推薦)
                          if (_finalRecommendation != null) ...[
                            const SizedBox(height: 24),
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
                                      const Text('⭐',
                                          style: TextStyle(fontSize: 20)),
                                      const SizedBox(width: 8),
                                      Text('AI 推薦回覆',
                                          style: AppTypography.titleLarge),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _finalRecommendation!.content,
                                      style: AppTypography.bodyLarge,
                                    ),
                                  ),
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
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(
                                              text: _finalRecommendation!
                                                  .content),
                                        );
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text('已複製到剪貼簿')),
                                        );
                                      },
                                      icon: const Icon(Icons.copy),
                                      label: const Text('複製推薦回覆'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // 優化我的訊息功能
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
                                            '我有想說的，幫我優化',
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
                                  if (_showOptimizeInput) ...[
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _optimizeController,
                                      style: AppTypography.bodyMedium.copyWith(
                                          color: AppColors.glassTextPrimary),
                                      decoration: InputDecoration(
                                        hintText: '輸入你想說的內容...',
                                        hintStyle:
                                            AppTypography.bodyMedium.copyWith(
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
                                      ),
                                      maxLines: 3,
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
                                            _isOptimizing ? '優化中...' : '幫我優化'),
                                      ),
                                    ),
                                  ],
                                  // 顯示優化結果
                                  if (_optimizedMessage != null &&
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
                                          '優化後的訊息',
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
                                        label: const Text('複製優化訊息'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],

                          // 一致性提醒
                          if (_reminder != null) ...[
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
                                    onPressed: () =>
                                        _submitFeedback('positive'),
                                    tooltip: '有幫助',
                                    color: AppColors.success,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.thumb_down_outlined),
                                    onPressed: () => setState(
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
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _buildFeedbackCategoryChip(
                                              'too_direct', '太直接/不自然'),
                                          _buildFeedbackCategoryChip(
                                              'too_long', '回覆太長'),
                                          _buildFeedbackCategoryChip(
                                              'wrong_style', '不符合我的風格'),
                                          _buildFeedbackCategoryChip(
                                              'other', '其他'),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: _feedbackCommentController,
                                        style: AppTypography.bodyMedium
                                            .copyWith(
                                                color:
                                                    AppColors.glassTextPrimary),
                                        decoration: InputDecoration(
                                          hintText: '補充說明（選填）',
                                          hintStyle: AppTypography.bodyMedium
                                              .copyWith(
                                                  color:
                                                      AppColors.glassTextHint),
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
                                        ),
                                        maxLines: 2,
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: _feedbackCategory != null
                                              ? () =>
                                                  _submitFeedback('negative')
                                              : null,
                                          child: const Text('送出反饋'),
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

                          // 新訊息提示 (根據最後一則是誰來顯示不同內容)
                          if (conversation.messages.isNotEmpty &&
                              conversation.messages.length >
                                  _lastAnalyzedMessageCount) ...[
                            const SizedBox(height: 16),
                            Builder(
                              builder: (context) {
                                final lastIsFromMe =
                                    conversation.messages.last.isFromMe;
                                final newCount = conversation.messages.length -
                                    _lastAnalyzedMessageCount;

                                if (lastIsFromMe) {
                                  // 最後是「我說」→ 仍可分析，但以前一則她的訊息為基準
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
                                            '有 $newCount 則新訊息，會以前一則她的回覆作為分析基準。',
                                            style: AppTypography.bodyMedium,
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: _isAnalyzing
                                              ? null
                                              : _runAnalysis,
                                          icon: const Icon(Icons.refresh,
                                              size: 18),
                                          label: const Text('繼續分析'),
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
                                            '有 $newCount 則新訊息',
                                            style: AppTypography.bodyMedium,
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: _isAnalyzing
                                              ? null
                                              : _runAnalysis,
                                          icon: const Icon(Icons.refresh,
                                              size: 18),
                                          label: const Text('重新分析'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            ),
                          ],

                          // 「我說」話題延續分析結果（Essential 專屬）
                          if (_isAnalyzingMyMessage) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.2)),
                              ),
                              child: const Column(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  SizedBox(height: 8),
                                  Text('分析話題延續方向...'),
                                ],
                              ),
                            ),
                          ] else if (_myMessageAnalysis != null) ...[
                            const SizedBox(height: 16),
                            _buildMyMessageAnalysisCard(),
                          ],

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  // 對話延續輸入區（有分析結果時可收合）
                  _buildCollapsibleMessageInput(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 建立「我說」話題延續分析卡片
  Widget _buildMyMessageAnalysisCard() {
    final analysis = _myMessageAnalysis!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💡', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('話題延續建議', style: AppTypography.titleLarge),
            ],
          ),
          const SizedBox(height: 16),

          // 如果她冷淡回覆
          if (analysis.ifColdResponse.suggestion.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('😐', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text('如果她冷淡回覆',
                          style: AppTypography.bodyMedium
                              .copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (analysis.ifColdResponse.prediction.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '她可能說：「${analysis.ifColdResponse.prediction}」',
                      style: AppTypography.caption
                          .copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '→ ${analysis.ifColdResponse.suggestion}',
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 如果她熱情回覆
          if (analysis.ifWarmResponse.suggestion.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('😊', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text('如果她熱情回覆',
                          style: AppTypography.bodyMedium
                              .copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (analysis.ifWarmResponse.prediction.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '她可能說：「${analysis.ifWarmResponse.prediction}」',
                      style: AppTypography.caption
                          .copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '→ ${analysis.ifWarmResponse.suggestion}',
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 備用話題
          if (analysis.backupTopics.isNotEmpty) ...[
            Text('📚 備用話題',
                style: AppTypography.bodyMedium
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...analysis.backupTopics.map((topic) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(topic, style: AppTypography.bodyMedium)),
                    ],
                  ),
                )),
          ],

          // 注意事項
          if (analysis.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...analysis.warnings.map((warning) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber,
                          size: 14, color: AppColors.error),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(warning,
                            style: AppTypography.caption
                                .copyWith(color: AppColors.error)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  /// 建立可收合的訊息輸入區（有分析結果時預設收合）
  Widget _buildCollapsibleMessageInput() {
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
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => _showContinueConversation = true),
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('繼續對話'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5)),
                      foregroundColor: AppColors.primary,
                    ),
                  ),
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
                    onTap: () =>
                        setState(() => _showContinueConversation = false),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.keyboard_arrow_down,
                              color: AppColors.unselectedText, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            '收合',
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
              _buildConversationScreenshotSection(),
              const SizedBox(height: 12),
            ],
            // 輸入框 + 貼上按鈕
            TextField(
              controller: _messageController,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.glassTextPrimary),
              decoration: InputDecoration(
                hintText: '貼上對方的回覆...',
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
                // 貼上按鈕
                suffixIcon: IconButton(
                  icon:
                      Icon(Icons.content_paste, color: AppColors.glassTextHint),
                  onPressed: _isAnalyzing
                      ? null
                      : () async {
                          final data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null && data!.text!.isNotEmpty) {
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
              ),
              maxLines: 5,
              minLines: 2,
              textInputAction: TextInputAction.newline,
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
                      label: Text('她說...',
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
                              Text('我說...',
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
}

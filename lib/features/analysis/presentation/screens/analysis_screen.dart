// lib/features/analysis/presentation/screens/analysis_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../../shared/widgets/enthusiasm_gauge.dart';
import '../../../../shared/widgets/game_stage_indicator.dart';
import '../../../../shared/widgets/reply_card.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/presentation/widgets/message_bubble.dart';
import '../../data/services/analysis_service.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/game_stage.dart';
import '../../../subscription/data/providers/subscription_providers.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const AnalysisScreen({super.key, required this.conversationId});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  bool _isAnalyzing = false;
  int? _enthusiasmScore;
  String? _strategy;
  Map<String, String>? _replies;
  TopicDepth? _topicDepth;
  HealthCheck? _healthCheck;
  String? _errorMessage;

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

  void _showPaywall(BuildContext context) {
    // TODO: Navigate to paywall screen
    context.push('/paywall');
  }

  // 記錄已分析的訊息數量，用於判斷是否需要重新分析
  int _lastAnalyzedMessageCount = 0;

  @override
  void initState() {
    super.initState();
    // 不再自動分析，讓用戶手動點擊
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _feedbackCommentController.dispose();
    _optimizeController.dispose();
    super.dispose();
  }

  /// 新增訊息到對話並重新分析
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

  Future<void> _runAnalysis() async {
    // 先關閉 SnackBar (如果有的話)
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = '找不到對話';
      });
      return;
    }

    // 驗證：最後一則必須是「她」的訊息
    if (conversation.messages.isEmpty) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = '請先輸入對話內容';
      });
      return;
    }

    if (conversation.messages.last.isFromMe) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = '請先輸入對方的回覆，才能給你建議';
      });
      return;
    }

    try {
      // 呼叫真正的 Supabase Edge Function
      final analysisService = AnalysisService();
      final result = await analysisService.analyzeConversation(
        conversation.messages,
        sessionContext: conversation.sessionContext,
      );

      // 記錄已分析的訊息數量
      _lastAnalyzedMessageCount = conversation.messages.length;

      setState(() {
        _isAnalyzing = false;
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

      // Update conversation with score
      try {
        final repository = ref.read(conversationRepositoryProvider);
        final conv = repository.getConversation(widget.conversationId);
        if (conv != null && _enthusiasmScore != null) {
          conv.lastEnthusiasmScore = _enthusiasmScore;
          await repository.updateConversation(conv);
          ref.invalidate(conversationsProvider);
        }
      } catch (_) {
        // Ignore errors in test environment
      }
    } on DailyLimitExceededException catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = '今日額度已用完 (${e.used}/${e.dailyLimit})，明天再來！';
      });
    } on MonthlyLimitExceededException catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = '本月額度已用完 (${e.used}/${e.monthlyLimit})，升級方案獲得更多！';
      });
    } on AnalysisException catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = '分析失敗: $e';
      });
    }
  }

  /// 「我說」話題延續分析（Essential 專屬）
  Future<void> _runMyMessageAnalysis() async {
    setState(() {
      _isAnalyzingMyMessage = true;
      _myMessageAnalysis = null;
    });

    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) {
      setState(() => _isAnalyzingMyMessage = false);
      return;
    }

    try {
      final analysisService = AnalysisService();
      final result = await analysisService.analyzeConversation(
        conversation.messages,
        sessionContext: conversation.sessionContext,
        analyzeMode: 'my_message',
      );

      setState(() {
        _isAnalyzingMyMessage = false;
        _myMessageAnalysis = result.myMessageAnalysis;
      });
    } on AnalysisException catch (e) {
      setState(() {
        _isAnalyzingMyMessage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析失敗: ${e.message}')),
        );
      }
    } catch (e) {
      setState(() {
        _isAnalyzingMyMessage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析失敗: $e')),
        );
      }
    }
  }

  /// 優化用戶訊息
  Future<void> _optimizeMessage() async {
    final draft = _optimizeController.text.trim();
    if (draft.isEmpty) return;

    setState(() {
      _isOptimizing = true;
      _optimizedMessage = null;
    });

    final conversation = ref.read(conversationProvider(widget.conversationId));
    if (conversation == null) {
      setState(() => _isOptimizing = false);
      return;
    }

    try {
      final analysisService = AnalysisService();
      final result = await analysisService.analyzeConversation(
        conversation.messages,
        sessionContext: conversation.sessionContext,
        userDraft: draft,
      );

      setState(() {
        _isOptimizing = false;
        // 只更新優化結果，不覆蓋其他分析
        _optimizedMessage = result.optimizedMessage;

        // 檢查優化是否成功
        if (_optimizedMessage == null || _optimizedMessage!.optimized.isEmpty) {
          // 優化失敗，顯示錯誤但保留原本的分析結果
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('優化失敗，請重試')),
          );
        }
      });
    } on AnalysisException catch (e) {
      setState(() {
        _isOptimizing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('優化失敗: ${e.message}')),
      );
    } catch (e) {
      setState(() {
        _isOptimizing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('優化失敗: $e')),
      );
    }
  }

  // ===== 分析輔助方法 (Mock 邏輯，之後會被真正的 AI 取代) =====

  int _calculateEnthusiasmScore(List<Message> theirMessages, List<Message> myMessages, int totalRounds) {
    if (theirMessages.isEmpty) return 20;

    // 基礎分數根據對話輪數
    int baseScore = 30;
    if (totalRounds == 1) baseScore = 25;
    if (totalRounds > 3) baseScore = 40;
    if (totalRounds > 5) baseScore = 50;

    // 根據她的訊息長度加分
    final avgLength = theirMessages.map((m) => m.content.length).reduce((a, b) => a + b) / theirMessages.length;
    if (avgLength > 20) baseScore += 15;
    if (avgLength > 50) baseScore += 10;

    // 檢查是否有問號（表示她有興趣問你）
    final hasQuestions = theirMessages.any((m) => m.content.contains('?') || m.content.contains('？'));
    if (hasQuestions) baseScore += 15;

    // 確保分數在合理範圍
    return baseScore.clamp(15, 95);
  }

  GameStage _determineGameStage(int totalRounds, List<Message> theirMessages) {
    if (totalRounds <= 1) return GameStage.opening;
    if (totalRounds <= 3) return GameStage.premise;
    if (totalRounds <= 6) return GameStage.qualification;
    if (totalRounds <= 10) return GameStage.narrative;
    return GameStage.close;
  }

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

  List<String> _checkHealthIssues(List<Message> myMessages, List<Message> theirMessages) {
    final issues = <String>[];

    if (myMessages.isEmpty) return issues;

    // 檢查是否連續發多則訊息
    // (簡化邏輯，實際應該看時間戳)

    // 檢查訊息長度比例
    if (theirMessages.isNotEmpty) {
      final myAvg = myMessages.map((m) => m.content.length).reduce((a, b) => a + b) / myMessages.length;
      final theirAvg = theirMessages.map((m) => m.content.length).reduce((a, b) => a + b) / theirMessages.length;
      if (myAvg > theirAvg * 2) {
        issues.add('你的訊息比她長太多，可能顯得過於積極');
      }
    }

    return issues;
  }

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
          }[type] ?? type;
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
    final lastMessages = messages.length > 6
        ? messages.sublist(messages.length - 6)
        : messages;
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
              content: Text(rating == 'positive'
                  ? '謝謝回饋！'
                  : '感謝你的回饋，我們會持續改進！'),
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
                  // 防止 iOS Safari pull-to-refresh 關閉頁面
                  child: ScrollConfiguration(
                    behavior: kIsWeb
                        ? ScrollConfiguration.of(context).copyWith(
                            overscroll: false,
                            physics: const ClampingScrollPhysics(),
                          )
                        : ScrollConfiguration.of(context),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      // 優化滑動效能：使用 Clamping 防止 overscroll
                      physics: const ClampingScrollPhysics(),
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
                            onTap: () => setState(() => _showAllMessages = !_showAllMessages),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _showAllMessages ? Icons.expand_less : Icons.expand_more,
                                    size: 16,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _showAllMessages
                                        ? '收合訊息'
                                        : '展開全部 ${conversation.messages.length} 則訊息',
                                    style: AppTypography.caption.copyWith(color: AppColors.primary),
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
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _runAnalysis,
                      child: const Text('重試'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 手動分析按鈕 (尚未分析時顯示)
            if (_enthusiasmScore == null && !_isAnalyzing && _errorMessage == null) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    const Text('🎯', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      '準備好分析這段對話了嗎？',
                      style: AppTypography.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '我會分析熱度、對話進度、心理解讀，\n並給你最適合的回覆建議',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _runAnalysis,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('開始分析'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Enthusiasm Gauge
            if (_enthusiasmScore != null) ...[
              Text('熱度分析', style: AppTypography.titleLarge),
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
                    border:
                        Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Text('🚫', style: TextStyle(fontSize: 20)),
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
                        const Text('🧠', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text('心理解讀', style: AppTypography.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_psychology!.subtext, style: AppTypography.bodyMedium),
                    if (_psychology!.shitTest != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Text('⚠️', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '偵測到廢測: ${_psychology!.shitTest}',
                                style: AppTypography.caption,
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
                          Text('她在向你證明自己', style: AppTypography.caption),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _strategy!,
                        style: AppTypography.bodyMedium,
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('話題深度: ${_topicDepth!.current.label}',
                              style: AppTypography.bodyMedium),
                          if (_topicDepth!.suggestion.isNotEmpty)
                            Text(_topicDepth!.suggestion,
                                style: AppTypography.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Health Check (對話健檢 - Essential 專屬)
            if (_healthCheck != null && _healthCheck!.issues.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🩺', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text('對話健檢', style: AppTypography.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._healthCheck!.issues.map((issue) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber,
                                  size: 16, color: AppColors.warning),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(issue,
                                      style: AppTypography.bodyMedium)),
                            ],
                          ),
                        )),
                    if (_healthCheck!.suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ..._healthCheck!.suggestions.map((suggestion) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.lightbulb_outline,
                                    size: 16, color: AppColors.success),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(suggestion,
                                        style: AppTypography.caption)),
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
                  Text('建議回覆', style: AppTypography.titleLarge),
                  const Spacer(),
                  Text(
                    '字數上限: $maxLength字',
                    style: AppTypography.caption,
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
              // 如果只有 extend，顯示升級提示
              if (_replies!.length == 1 && _replies!.containsKey('extend')) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _showPaywall(context),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '升級解鎖共鳴、調情、幽默、冷讀等回覆風格',
                            style: AppTypography.bodyMedium.copyWith(color: AppColors.primary),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.primary),
                      ],
                    ),
                  ),
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
                  border:
                      Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('⭐', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text('AI 推薦回覆', style: AppTypography.titleLarge),
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
                            ClipboardData(text: _finalRecommendation!.content),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已複製到剪貼簿')),
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
                      onTap: () => setState(() => _showOptimizeInput = !_showOptimizeInput),
                      child: Row(
                        children: [
                          const Text('✏️', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '我有想說的，幫我優化',
                              style: AppTypography.titleMedium,
                            ),
                          ),
                          Icon(
                            _showOptimizeInput ? Icons.expand_less : Icons.expand_more,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                    if (_showOptimizeInput) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _optimizeController,
                        style: AppTypography.bodyMedium.copyWith(color: AppColors.glassTextPrimary),
                        decoration: InputDecoration(
                          hintText: '輸入你想說的內容...',
                          hintStyle: AppTypography.bodyMedium.copyWith(
                            color: AppColors.glassTextHint,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.5),
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
                            borderSide: const BorderSide(color: AppColors.selectedStart, width: 1.5),
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
                          onPressed: _isOptimizing || _optimizeController.text.trim().isEmpty
                              ? null
                              : _optimizeMessage,
                          icon: _isOptimizing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.auto_fix_high),
                          label: Text(_isOptimizing ? '優化中...' : '幫我優化'),
                        ),
                      ),
                    ],
                    // 顯示優化結果
                    if (_optimizedMessage != null && _optimizedMessage!.optimized.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('✨', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Text('優化後的訊息', style: AppTypography.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _optimizedMessage!.optimized,
                          style: AppTypography.bodyLarge,
                        ),
                      ),
                      if (_optimizedMessage!.reason.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '💡 ${_optimizedMessage!.reason}',
                          style: AppTypography.caption,
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _optimizedMessage!.optimized));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已複製到剪貼簿')),
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
                    const Text('💬', style: TextStyle(fontSize: 18)),
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
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('這個建議有幫助嗎？', style: AppTypography.bodyMedium),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.thumb_up_outlined),
                      onPressed: () => _submitFeedback('positive'),
                      tooltip: '有幫助',
                      color: AppColors.success,
                    ),
                    IconButton(
                      icon: const Icon(Icons.thumb_down_outlined),
                      onPressed: () => setState(() => _showFeedbackForm = true),
                      tooltip: '需要改進',
                      color: AppColors.error,
                    ),
                  ],
                ),
                if (_showFeedbackForm) ...[
                  const SizedBox(height: 16),
                  GlassmorphicContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('哪裡需要改進？', style: AppTypography.bodyLarge),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildFeedbackCategoryChip('too_direct', '太直接/不自然'),
                            _buildFeedbackCategoryChip('too_long', '回覆太長'),
                            _buildFeedbackCategoryChip('wrong_style', '不符合我的風格'),
                            _buildFeedbackCategoryChip('other', '其他'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _feedbackCommentController,
                          style: AppTypography.bodyMedium.copyWith(color: AppColors.glassTextPrimary),
                          decoration: InputDecoration(
                            hintText: '補充說明（選填）',
                            hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.glassTextHint),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.5),
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
                              borderSide: const BorderSide(color: AppColors.selectedStart, width: 1.5),
                            ),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _feedbackCategory != null
                                ? () => _submitFeedback('negative')
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
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ],

            // 新訊息提示 (根據最後一則是誰來顯示不同內容)
            if (conversation.messages.isNotEmpty &&
                conversation.messages.length > _lastAnalyzedMessageCount) ...[
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final lastIsFromMe = conversation.messages.last.isFromMe;
                  final newCount = conversation.messages.length - _lastAnalyzedMessageCount;

                  if (lastIsFromMe) {
                    // 最後是「我說」→ 提示輸入她的回覆
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_downward, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '請在下方輸入她的回覆，再點「👩 她說...」',
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
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.update, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '有 $newCount 則新訊息',
                              style: AppTypography.bodyMedium,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _isAnalyzing ? null : _runAnalysis,
                            icon: const Icon(Icons.refresh, size: 18),
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
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: const Column(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
        ),
        // 對話延續輸入區
        _buildMessageInput(),
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
                      Text('如果她冷淡回覆', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (analysis.ifColdResponse.prediction.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '她可能說：「${analysis.ifColdResponse.prediction}」',
                      style: AppTypography.caption.copyWith(fontStyle: FontStyle.italic),
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
                      Text('如果她熱情回覆', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (analysis.ifWarmResponse.prediction.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '她可能說：「${analysis.ifWarmResponse.prediction}」',
                      style: AppTypography.caption.copyWith(fontStyle: FontStyle.italic),
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
            Text('📚 備用話題', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...analysis.backupTopics.map((topic) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(topic, style: AppTypography.bodyMedium)),
                ],
              ),
            )),
          ],

          // 注意事項
          if (analysis.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...analysis.warnings.map((warning) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 14, color: AppColors.error),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(warning, style: AppTypography.caption.copyWith(color: AppColors.error)),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  /// 建立訊息輸入區
  Widget _buildMessageInput() {
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
            // 輸入框 + 貼上按鈕
            TextField(
              controller: _messageController,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.glassTextPrimary),
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
                  borderSide: const BorderSide(color: AppColors.selectedStart, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                // 貼上按鈕
                suffixIcon: IconButton(
                  icon: Icon(Icons.content_paste, color: AppColors.glassTextHint),
                  onPressed: _isAnalyzing ? null : () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null && data!.text!.isNotEmpty) {
                      _messageController.text = data.text!;
                      _messageController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _messageController.text.length),
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
                      onPressed: _isAnalyzing ? null : () => _addMessage(isFromMe: false),
                      icon: const Text('👩', style: TextStyle(fontSize: 18)),
                      label: const Text('她說...'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isAnalyzing ? null : () => _addMessage(isFromMe: true),
                      icon: const Text('👤', style: TextStyle(fontSize: 18)),
                      label: const Text('我說...'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
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

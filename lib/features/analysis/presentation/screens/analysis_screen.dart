// lib/features/analysis/presentation/screens/analysis_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
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

  void _showPaywall(BuildContext context) {
    // TODO: Navigate to paywall screen
    context.push('/paywall');
  }

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
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

    try {
      // 呼叫真正的 Supabase Edge Function
      final analysisService = AnalysisService();
      final result = await analysisService.analyzeConversation(
        conversation.messages,
        sessionContext: conversation.sessionContext,
      );

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
      });

      // Update conversation with score
      try {
        final repository = ref.read(conversationRepositoryProvider);
        final conv = repository.getConversation(widget.conversationId);
        if (conv != null && _enthusiasmScore != null) {
          conv.lastEnthusiasmScore = _enthusiasmScore;
          await repository.updateConversation(conv);
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

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(conversationProvider(widget.conversationId));

    if (conversation == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/'),
          ),
        ),
        body: const Center(child: Text('找不到對話')),
      );
    }

    final maxLength = _calculateMaxReplyLength(conversation);

    return Scaffold(
      appBar: AppBar(
        title: Text(conversation.name, style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Messages preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ...conversation.messages
                      .take(5)
                      .map((m) => MessageBubble(message: m)),
                  if (conversation.messages.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '...還有 ${conversation.messages.length - 5} 則訊息',
                        style: AppTypography.caption,
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
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

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

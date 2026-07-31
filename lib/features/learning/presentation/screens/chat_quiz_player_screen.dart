// lib/features/learning/presentation/screens/chat_quiz_player_screen.dart
//
// 聊天測驗答題器：一題一頁、頂部進度、底部統一送出。
//
// 行為約束：
//   - 沒選任何選項不能送出，也不能往下一題。
//   - 送出前畫面上不得有任何正解線索（卡片負責，見 chat_quiz_question_card）。
//   - 送出後就地展開回饋，然後才出現「下一題」。
//   - 題目 revision 改了，之前存的作答視為未作答。
//   - 權限四態各給各的畫面；`resolving` 只給中性 loading，不得出現付費文案。
//
// 重試無限次、不扣任何東西：這裡完全不碰 quota、不打網路，只讀 bundled JSON
// 與本機進度。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../data/providers/chat_quiz_providers.dart';
import '../../domain/chat_quiz_access.dart';
import '../../domain/models/chat_quiz.dart';
import '../../domain/models/chat_quiz_progress.dart';
import '../widgets/chat_quiz_gate_message.dart';
import '../widgets/chat_quiz_question_card.dart';
import '../widgets/ebook_access_gate.dart';
import 'chat_quiz_result_screen.dart';

class ChatQuizPlayerScreen extends ConsumerWidget {
  const ChatQuizPlayerScreen({super.key, required this.levelId});

  final String levelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(chatQuizCatalogProvider);

    return catalog.when(
      loading: () => const ChatQuizGateScaffold(
        title: '聊天測驗',
        child: ChatQuizGateLoading(label: '正在載入題目…'),
      ),
      error: (error, _) => ChatQuizGateScaffold(
        title: '聊天測驗',
        child: ChatQuizGateMessage(
          icon: Icons.error_outline,
          title: '題目載入失敗',
          message: '這一批題目暫時讀不到，你的進度不會受影響。',
          primaryLabel: '回關卡地圖',
          onPrimary: () => context.go('/learning/quiz'),
        ),
      ),
      data: (data) {
        final level = data.findLevel(levelId);
        if (level == null) {
          return ChatQuizGateScaffold(
            title: '聊天測驗',
            child: ChatQuizGateMessage(
              icon: Icons.help_outline,
              title: '找不到這一關',
              message: '這一關可能已經調整或移除了。回關卡地圖看看其他關。',
              primaryLabel: '回關卡地圖',
              onPrimary: () => context.go('/learning/quiz'),
            ),
          );
        }

        return _ChatQuizLevelGate(level: level);
      },
    );
  }
}

/// 關卡層的付費閘門。四態各走各的分支，`resolving` 絕不顯示付費文案。
class _ChatQuizLevelGate extends ConsumerStatefulWidget {
  const _ChatQuizLevelGate({required this.level});

  final ChatQuizLevel level;

  @override
  ConsumerState<_ChatQuizLevelGate> createState() => _ChatQuizLevelGateState();
}

class _ChatQuizLevelGateState extends ConsumerState<_ChatQuizLevelGate> {
  /// 防止 post-frame callback 重複導航到 paywall。
  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    final gate =
        gateForLevel(widget.level, ref.watch(ebookSubscriptionAccessProvider));

    switch (gate) {
      case ChatQuizGate.allowed:
        return ChatQuizPlayerBody(level: widget.level);

      case ChatQuizGate.resolving:
        return const ChatQuizGateScaffold(
          title: '聊天測驗',
          child: ChatQuizGateLoading(label: '正在確認你的訂閱狀態…'),
        );

      case ChatQuizGate.unavailable:
        return ChatQuizGateScaffold(
          title: '聊天測驗',
          child: ChatQuizGateMessage(
            icon: Icons.cloud_off_outlined,
            title: '暫時無法確認訂閱狀態',
            message: '這通常是連線問題。重試一次就好，你的進度不會受影響。',
            primaryLabel: '重試',
            onPrimary: () => ref.read(subscriptionProvider.notifier).refresh(),
            secondaryLabel: '回關卡地圖',
            onSecondary: () => context.go('/learning/quiz'),
          ),
        );

      case ChatQuizGate.locked:
        if (!_redirected) {
          _redirected = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.push('/paywall');
          });
        }
        // 導航前後都不建立題目畫面，避免付費內容閃現。刻意不是 loading：
        // 使用者從 paywall 返回後不會再自動導航，spinner 會變成死角。
        return ChatQuizGateScaffold(
          title: '聊天測驗',
          child: ChatQuizGateMessage(
            icon: Icons.workspace_premium_outlined,
            title: '這一關需要訂閱',
            message: '第一關「她現在是哪一種」永久免費。訂閱之後其餘關卡會一次全部開放，'
                '而且重試不限次數。',
            primaryLabel: '看訂閱方案',
            onPrimary: () => context.push('/paywall'),
            secondaryLabel: '回關卡地圖',
            onSecondary: () => context.go('/learning/quiz'),
          ),
        );
    }
  }
}

/// 實際的答題流程。權限已經確認過才會被建立。
class ChatQuizPlayerBody extends ConsumerStatefulWidget {
  const ChatQuizPlayerBody({super.key, required this.level});

  final ChatQuizLevel level;

  @override
  ConsumerState<ChatQuizPlayerBody> createState() => _ChatQuizPlayerBodyState();
}

class _ChatQuizPlayerBodyState extends ConsumerState<ChatQuizPlayerBody> {
  /// questionId → 這一輪選了哪個選項。
  final Map<String, String> _picks = <String, String>{};

  /// 已經送出的題目 id。
  final Set<String> _submitted = <String>{};

  int _index = 0;
  bool _finished = false;
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    // 進度還沒讀出來之前不渲染題目：先畫第一題再跳到第三題，看起來像 bug。
    final progress = ref.watch(chatQuizProgressControllerProvider);
    if (progress is! AsyncData<ChatQuizProgress>) {
      return const ChatQuizGateScaffold(
        title: '聊天測驗',
        child: ChatQuizGateLoading(label: '正在讀取進度…'),
      );
    }
    _seedFromSavedProgress(progress.value);

    final level = widget.level;
    final question = level.questions[_index];
    final revealed = _submitted.contains(question.id);
    final picked = _picks[question.id];

    if (_finished) return _buildFinished(context);

    return ChatQuizGateScaffold(
      title: '${level.number} ${level.title}',
      onClose: () => context.go('/learning/quiz'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressHeader(
            current: _index + 1,
            total: level.questionCount,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: ChatQuizQuestionCard(
                question: question,
                selectedChoiceId: picked,
                revealed: revealed,
                onSelect: (choiceId) => _select(question, choiceId),
                onReadSource: question.source == null
                    ? null
                    : () => _openSource(context, question.source!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildActionButton(question, revealed, picked),
        ],
      ),
    );
  }

  /// 用已保存的作答補回這一輪的狀態。
  ///
  /// 只補 revision 相符的：題目改寫過就當成沒答過，使用者會重新看到那一題。
  void _seedFromSavedProgress(ChatQuizProgress progress) {
    if (_seeded) return;
    _seeded = true;
    for (final question in widget.level.questions) {
      final answer =
          progress.answerFor(question.id, revision: question.revision);
      if (answer == null) continue;
      if (question.findChoice(answer.choiceId) == null) continue;
      _picks[question.id] = answer.choiceId;
      _submitted.add(question.id);
    }
    // 從第一個還沒答的題目開始；全部答過就停在最後一題（按一下就能看結果）。
    final next =
        widget.level.questions.indexWhere((q) => !_submitted.contains(q.id));
    _index = next < 0 ? widget.level.questionCount - 1 : next;
  }

  void _select(ChatQuizQuestion question, String choiceId) {
    if (_submitted.contains(question.id)) return;
    setState(() => _picks[question.id] = choiceId);
  }

  Widget _buildActionButton(
    ChatQuizQuestion question,
    bool revealed,
    String? picked,
  ) {
    if (!revealed) {
      return BrandPrimaryButton(
        label: '送出答案',
        onPressed: picked == null ? null : () => _submit(question, picked),
      );
    }
    final isLast = _index == widget.level.questionCount - 1;
    return BrandPrimaryButton(
      label: isLast ? '看結果' : '下一題',
      onPressed: isLast ? _finish : _next,
    );
  }

  void _submit(ChatQuizQuestion question, String choiceId) {
    setState(() => _submitted.add(question.id));
    // best-effort 保存；寫入失敗不影響這一輪的作答流程。
    ref.read(chatQuizProgressControllerProvider.notifier).recordAnswer(
          questionId: question.id,
          choiceId: choiceId,
          revision: question.revision,
        );
  }

  void _next() {
    if (_index >= widget.level.questionCount - 1) return;
    setState(() => _index += 1);
  }

  void _finish() {
    final level = widget.level;
    final correctCount = level.questions
        .where((q) => q.isCorrectChoice(_picks[q.id] ?? ''))
        .length;
    ref.read(chatQuizProgressControllerProvider.notifier).recordLevelResult(
          levelId: level.id,
          correctCount: correctCount,
          questionCount: level.questionCount,
          passed: level.isPassing(correctCount),
        );
    setState(() => _finished = true);
  }

  void _openSource(BuildContext context, ChatQuizSource source) {
    context.push(
      '/learning/books/${source.bookId}/chapters/${source.chapterId}',
    );
  }

  /// 跑完之後的結果頁。
  Widget _buildFinished(BuildContext context) {
    return ChatQuizResultScreen(
      level: widget.level,
      picks: Map<String, String>.unmodifiable(_picks),
      onRetry: _retry,
      onBackToMap: () => context.go('/learning/quiz'),
      onReadSource: (source) => _openSource(context, source),
    );
  }

  /// 再跑一次：清掉這一關的作答，從第一題重新開始。
  ///
  /// 刻意不動已保存的最佳成績——重試不扣任何東西，也不該把拿到的東西收回去。
  void _retry() {
    final questionIds =
        widget.level.questions.map((question) => question.id).toList();
    ref.read(chatQuizProgressControllerProvider.notifier)
        .clearAnswers(questionIds);
    setState(() {
      _picks.clear();
      _submitted.clear();
      _index = 0;
      _finished = false;
    });
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '第 $current 題，共 $total 題',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '第 $current 題 / 共 $total 題',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : current / total,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.ctaStart),
            ),
          ),
        ],
      ),
    );
  }
}

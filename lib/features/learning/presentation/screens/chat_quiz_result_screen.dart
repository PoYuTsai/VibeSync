// lib/features/learning/presentation/screens/chat_quiz_result_screen.dart
//
// 一關跑完的結果頁。
//
// 產品規則：
//   - 過關門檻 80%。**沒過的標題是「再跑一次」，不是「失敗」。**
//   - 重試無限次、不扣任何東西——這裡不出現任何額度或付費文案。
//   - 答錯的題列出來；有 source 的顯示「讀原理」，沒有的不顯示按鈕。
//
// 動效：過關的慶祝動畫由 [AnimationController] 推導，**不用 Timer 當時間軸**
// （Timer 在 widget test 的 fake async 下不會收斂，pumpAndSettle 直接逾時）。
// 系統開啟「減少動態效果」時直接跳到終點，不跑動畫。
//
// 音效與觸覺回饋第 1 期都不做：全 App 目前只有抽卡儀式兩處用觸覺，在這裡新增
// 等於多開一種全新的回饋模式；音效則需要新增音檔與授權處理。兩者留給第 2 期
// 單獨評估（報告 §6.6 自己也標了「需要先確認」）。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/models/chat_quiz.dart';
import '../widgets/chat_quiz_gate_message.dart';

class ChatQuizResultScreen extends StatefulWidget {
  const ChatQuizResultScreen({
    super.key,
    required this.level,
    required this.picks,
    required this.onRetry,
    required this.onBackToMap,
    this.onReadSource,
  });

  final ChatQuizLevel level;

  /// questionId → 這一輪選了哪個選項。
  final Map<String, String> picks;

  final VoidCallback onRetry;
  final VoidCallback onBackToMap;

  /// 深連到原理章節。`null` 時「讀原理」不顯示。
  final void Function(ChatQuizSource source)? onReadSource;

  @override
  State<ChatQuizResultScreen> createState() => _ChatQuizResultScreenState();
}

class _ChatQuizResultScreenState extends State<ChatQuizResultScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion || !_passed) {
      // 沒過就不慶祝；減少動態效果時直接呈現終點狀態。
      _controller.value = 1;
      return;
    }
    if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _correctCount => widget.level.questions
      .where((q) => q.isCorrectChoice(widget.picks[q.id] ?? ''))
      .length;

  bool get _passed => widget.level.isPassing(_correctCount);

  List<ChatQuizQuestion> get _missed => widget.level.questions
      .where((q) => !q.isCorrectChoice(widget.picks[q.id] ?? ''))
      .toList();

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final total = level.questionCount;

    return ChatQuizGateScaffold(
      title: '${level.number} ${level.title}',
      fallbackLocation: '/learning/quiz',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _ScoreCard(
            controller: _controller,
            passed: _passed,
            correctCount: _correctCount,
            total: total,
            requiredCount: level.requiredCorrectCount,
          ),
          if (_missed.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '這幾題再看一次',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final question in _missed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MissedQuestionCard(
                  question: question,
                  pickedChoiceId: widget.picks[question.id],
                  onReadSource: question.source == null ||
                          widget.onReadSource == null
                      ? null
                      : () => widget.onReadSource!(question.source!),
                ),
              ),
          ],
          const SizedBox(height: 8),
          BrandPrimaryButton(
            label: '再跑一次',
            icon: Icons.replay,
            onPressed: widget.onRetry,
          ),
          const SizedBox(height: 8),
          BrandSecondaryButton(
            label: '回關卡地圖',
            onPressed: widget.onBackToMap,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.controller,
    required this.passed,
    required this.correctCount,
    required this.total,
    required this.requiredCount,
  });

  final AnimationController controller;
  final bool passed;
  final int correctCount;
  final int total;
  final int requiredCount;

  @override
  Widget build(BuildContext context) {
    final accent = passed ? AppColors.success : AppColors.warning;
    final curved = CurvedAnimation(parent: controller, curve: Curves.easeOutBack);

    return BrandSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: AnimatedBuilder(
              animation: curved,
              builder: (context, child) {
                // 動效完全由 controller 推導：0 → 1 一次到底，不 repeat。
                final scale = 0.72 + 0.28 * curved.value.clamp(0.0, 1.0);
                return Transform.scale(scale: scale, child: child);
              },
              child: Icon(
                passed ? Icons.emoji_events_outlined : Icons.refresh_outlined,
                size: 44,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            // 沒過不是失敗，是再跑一次。這一行的用字是產品決定，不要改成
            // 「未通過」那種判決語氣。
            passed ? '過關' : '再跑一次',
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$correctCount / $total 題答對',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            passed
                ? '這一關的判讀你已經穩了。下一關會更難一點。'
                : '答對 $requiredCount 題就過。重試不限次數，也不會扣任何東西。',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissedQuestionCard extends StatelessWidget {
  const _MissedQuestionCard({
    required this.question,
    required this.pickedChoiceId,
    required this.onReadSource,
  });

  final ChatQuizQuestion question;
  final String? pickedChoiceId;
  final VoidCallback? onReadSource;

  @override
  Widget build(BuildContext context) {
    final picked =
        pickedChoiceId == null ? null : question.findChoice(pickedChoiceId!);
    final correct = question.correctChoice;

    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.question,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          if (picked != null)
            _Line(
              label: '你選了',
              text: picked.text,
              color: AppColors.error,
            ),
          if (picked != null) const SizedBox(height: 6),
          _Line(
            label: '正解',
            text: correct.text,
            color: AppColors.success,
          ),
          const SizedBox(height: 8),
          Text(
            question.takeaway,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.45,
            ),
          ),
          if (onReadSource != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onReadSource,
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: const Text(
                  '讀原理',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ctaStart,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.text, required this.color});

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2, right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

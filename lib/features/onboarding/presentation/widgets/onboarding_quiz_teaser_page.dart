// lib/features/onboarding/presentation/widgets/onboarding_quiz_teaser_page.dart
//
// onboarding 轉換第 12 步第 2 頁：先讓他親手做一題判讀（內建聊天測驗題庫的一題，
// 題號見 kOnboardingQuizQuestionId），零 AI 費用。
//   - 顯示情境、題目、選項；點一個就定案，接著只展開「他選的那個」的解析＋整題重點。
//   - 對錯一律用 ChatQuizQuestion.isCorrectChoice 判斷，不看位置（ADR #36：正確
//     答案的位置是打散的）。
//   - 對錯除了顏色一定有文字標籤（同聊天測驗的規矩，色盲讀得出來）。
//   - 題庫讀不到或找不到這一題：只顯示一句說明，OnboardingScreen 的「下一步」照樣能按。
// Controlled widget：選了哪個存在 OnboardingScreen，本頁只負責畫與回報。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../learning/domain/models/chat_quiz.dart';
import '../../../learning/presentation/widgets/chat_quiz_question_card.dart'
    show kChatQuizCorrectLabel, kChatQuizIncorrectLabel, kChatQuizYourPickLabel;
import '../../data/onboarding_quiz.dart';

class OnboardingQuizTeaserPage extends ConsumerWidget {
  const OnboardingQuizTeaserPage({
    super.key,
    required this.selectedChoiceId,
    required this.onAnswer,
  });

  /// 選了哪個選項；null＝還沒作答。
  final String? selectedChoiceId;

  final void Function(ChatQuizQuestion question, String choiceId) onAnswer;

  static const title = '先考你一題';
  static const subtitle = '選一個，答完馬上看解析。';
  static const unavailableText = '這一題暫時打不開，按「下一步」繼續就好。';

  /// 答完之後接回產品：教練看每段對話也是先看燈號（說法同 2026-10-18 的燈號頁）。
  static const bridgeLine = '每段對話，教練都先看燈號，再告訴你：該回、先別回，還是收尾。';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(onboardingQuizItemProvider);
    final answered = selectedChoiceId != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.headlineMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
          const SizedBox(height: 24),
          switch (item) {
            AsyncData(value: final OnboardingQuizItem data) => _QuizCard(
                item: data,
                selectedChoiceId: selectedChoiceId,
                onAnswer: (choiceId) => onAnswer(data.question, choiceId),
              ),
            AsyncLoading() => _note('題目載入中…'),
            _ => _note(unavailableText),
          },
          if (answered) ...[
            const SizedBox(height: 16),
            Text(
              bridgeLine,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _note(String text) => Text(
        text,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.onBackgroundSecondary.withValues(alpha: 0.82),
        ),
      );
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.item,
    required this.selectedChoiceId,
    required this.onAnswer,
  });

  final OnboardingQuizItem item;
  final String? selectedChoiceId;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final question = item.question;
    final scenario = question.scenario;
    final picked = selectedChoiceId == null
        ? null
        : question.findChoice(selectedChoiceId!);
    final revealed = picked != null;
    return BrandSurfaceCard(
      key: const ValueKey('onboarding-quiz-card'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '取自聊天測驗 ${item.levelNumber}',
            style: AppTypography.caption.copyWith(
              color: AppColors.ctaStart,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (scenario != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandInk.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                scenario,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            question.question,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          for (final choice in question.choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TeaserChoice(
                key: ValueKey('onboarding-quiz-choice-${choice.id}'),
                choice: choice,
                isCorrect: question.isCorrectChoice(choice.id),
                isPicked: choice.id == picked?.id,
                revealed: revealed,
                onTap: () => onAnswer(choice.id),
              ),
            ),
          if (picked != null) ...[
            const SizedBox(height: 4),
            _Explanation(
              key: const ValueKey('onboarding-quiz-explanation'),
              solved: question.isCorrectChoice(picked.id),
              feedback: picked.feedback,
              takeaway: question.takeaway,
            ),
          ],
        ],
      ),
    );
  }
}

/// 一個選項。作答前可點；作答後不能再點，正解標「正確」、選錯的標「不是這個 ·
/// 你的選擇」，沒選的錯誤選項不加標記。
class _TeaserChoice extends StatelessWidget {
  const _TeaserChoice({
    super.key,
    required this.choice,
    required this.isCorrect,
    required this.isPicked,
    required this.revealed,
    required this.onTap,
  });

  final ChatQuizChoice choice;
  final bool isCorrect;
  final bool isPicked;
  final bool revealed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    final marked = revealed && (isCorrect || isPicked);
    final Color borderColor;
    if (!revealed) {
      borderColor = Colors.white.withValues(alpha: 0.12);
    } else if (isCorrect) {
      borderColor = AppColors.success.withValues(alpha: 0.70);
    } else if (isPicked) {
      borderColor = AppColors.error.withValues(alpha: 0.60);
    } else {
      borderColor = Colors.white.withValues(alpha: 0.08);
    }
    // 作答前沒有「選中」狀態（點下去就定案）；作答後選的那個照對錯上底色。
    final Color fillColor;
    if (revealed && isPicked) {
      fillColor = isCorrect
          ? AppColors.success.withValues(alpha: 0.12)
          : AppColors.error.withValues(alpha: 0.10);
    } else {
      fillColor = Colors.white.withValues(alpha: 0.04);
    }
    final verdict = isCorrect ? kChatQuizCorrectLabel : kChatQuizIncorrectLabel;
    final semanticsLabel = marked
        ? '${choice.text}。$verdict。${isPicked ? '你選了這個。' : ''}'
        : choice.text;

    // 裡面的 InkWell 被 excludeSemantics 排掉了，讀屏的點擊要接在這一層；作答後跟手點
    // 一樣不能再點（主審 r1 P2）。
    return Semantics(
      button: !revealed,
      selected: isPicked,
      inMutuallyExclusiveGroup: true,
      label: semanticsLabel,
      onTap: revealed ? null : onTap,
      excludeSemantics: true,
      child: PressableScale(
        enabled: !revealed,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: revealed ? null : onTap,
            child: AnimatedContainer(
              duration: AppMotion.state,
              curve: AppMotion.easeOut,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: radius,
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Icon(
                          _icon(marked),
                          size: 18,
                          color: _iconColor(marked),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          choice.text,
                          style: AppTypography.bodyMedium.copyWith(
                            color: revealed && !marked
                                ? AppColors.onBackgroundSecondary
                                    .withValues(alpha: 0.7)
                                : AppColors.onBackgroundPrimary,
                            height: 1.4,
                            fontWeight:
                                isPicked ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (marked) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 26),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          Text(
                            verdict,
                            style: AppTypography.caption.copyWith(
                              color: isCorrect
                                  ? AppColors.success
                                  : AppColors.error,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (isPicked)
                            Text(
                              kChatQuizYourPickLabel,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.onBackgroundSecondary
                                    .withValues(alpha: 0.75),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _icon(bool marked) {
    if (!marked) return Icons.radio_button_unchecked;
    return isCorrect ? Icons.check_circle_outline : Icons.highlight_off;
  }

  Color _iconColor(bool marked) {
    const neutral = AppColors.onBackgroundSecondary;
    if (!revealed) return neutral.withValues(alpha: 0.7);
    if (!marked) return neutral.withValues(alpha: 0.4);
    return isCorrect ? AppColors.success : AppColors.error;
  }
}

/// 作答後的解析：他選的那個選項的 feedback，加上整題的 takeaway。
class _Explanation extends StatelessWidget {
  const _Explanation({
    super.key,
    required this.solved,
    required this.feedback,
    required this.takeaway,
  });

  final bool solved;
  final String feedback;
  final String takeaway;

  @override
  Widget build(BuildContext context) {
    final accent = solved ? AppColors.success : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                solved ? Icons.check_circle_outline : Icons.lightbulb_outline,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  solved ? '答對了' : '這一題再看一次',
                  style: AppTypography.titleSmall.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            feedback,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '重點',
            style: AppTypography.caption.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            takeaway,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

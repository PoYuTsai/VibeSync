// lib/features/learning/presentation/widgets/chat_quiz_question_card.dart
//
// 聊天測驗的單題卡。
//
// 為什麼不複用 [EbookQuizCard]：那張卡是設計來「嵌在閱讀流程裡」的自足卡片，
// 自己帶標題列、自己管重試。這裡是「一題一頁」的連續流程，送出鍵在畫面底部、
// 進度在頂部、重試是整關重跑——容器不同，硬共用只會讓兩邊都變形。
//
// 複用的是互動規矩（照抄 `ebook_quiz_card.dart` 的行為）：
//   - 送出前絕不揭示任何對錯線索。
//   - 送出後就地展開：每個選項各自的 feedback ＋ 整題 takeaway。
//   - **正誤一定要有文字標籤**，不能只靠紅綠色差——色盲使用者讀不出顏色。
//   - 題目 revision 改了就視為未作答（由呼叫端以 revision 驗證後傳入）。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/entrance_reveal.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../domain/models/chat_quiz.dart';

/// 送出後才會顯示的正誤文字。抽成常數讓測試與畫面共用同一份字串。
const String kChatQuizCorrectLabel = '正確';
const String kChatQuizIncorrectLabel = '不是這個';
const String kChatQuizYourPickLabel = '· 你的選擇';

class ChatQuizQuestionCard extends StatelessWidget {
  const ChatQuizQuestionCard({
    super.key,
    required this.question,
    required this.selectedChoiceId,
    required this.revealed,
    required this.onSelect,
    this.onReadSource,
  });

  final ChatQuizQuestion question;

  /// 目前選取的選項；`null` = 還沒作答。
  final String? selectedChoiceId;

  /// 是否已送出。送出前這張卡不得洩漏任何正解線索。
  final bool revealed;

  final ValueChanged<String> onSelect;

  /// 深連到原理章節。題目沒有 `source` 時傳 `null`，按鈕就不顯示。
  final VoidCallback? onReadSource;

  @override
  Widget build(BuildContext context) {
    final scenario = question.scenario;

    return BrandSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_typeIcon, size: 16, color: AppColors.ctaStart),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _typeLabel,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (scenario != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandInk.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                scenario,
                style: AppTypography.bodySmall.copyWith(
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
              child: _ChoiceRow(
                choice: choice,
                isSelected: selectedChoiceId == choice.id,
                revealed: revealed,
                onTap: () => onSelect(choice.id),
              ),
            ),
          // 送出後就地展開，不瞬跳：高度 240ms 展開＋內容 200ms 淡入。
          AnimatedSize(
            duration: AppMotion.state,
            curve: AppMotion.easeOut,
            alignment: Alignment.topCenter,
            child: !revealed
                ? const SizedBox(width: double.infinity)
                : EntranceReveal(
                    duration: AppMotion.state,
                    offsetY: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        _TakeawayPanel(
                          takeaway: question.takeaway,
                          solved: selectedChoiceId != null &&
                              question.isCorrectChoice(selectedChoiceId!),
                          onReadSource: onReadSource,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  IconData get _typeIcon => switch (question.type) {
        ChatQuizQuestionType.signalRead => Icons.traffic_outlined,
        ChatQuizQuestionType.pickReply => Icons.forum_outlined,
        ChatQuizQuestionType.findDeathPoint => Icons.troubleshoot_outlined,
        ChatQuizQuestionType.doseCheck => Icons.tune_outlined,
        ChatQuizQuestionType.gearShift => Icons.alt_route_outlined,
      };

  // 找死亡點的標籤刻意寫成通用形「哪一個在扣分」：群 3 的載體是照片、
  // 自介、行程清單，不是對話，綁死成「對話死在哪一句」在場外關會不貼。
  String get _typeLabel => switch (question.type) {
        ChatQuizQuestionType.signalRead => '讀燈 · 她現在是哪一種',
        ChatQuizQuestionType.pickReply => '選回覆 · 這一句該怎麼接',
        ChatQuizQuestionType.findDeathPoint => '找死亡點 · 哪一個在扣分',
        ChatQuizQuestionType.doseCheck => '份量診斷 · 多了還是少了',
        ChatQuizQuestionType.gearShift => '換檔 · 推進、維持還是收手',
      };
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.choice,
    required this.isSelected,
    required this.revealed,
    required this.onTap,
  });

  final ChatQuizChoice choice;
  final bool isSelected;
  final bool revealed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color borderColor;
    if (!revealed) {
      borderColor = isSelected
          ? AppColors.ctaStart.withValues(alpha: 0.75)
          : Colors.white.withValues(alpha: 0.12);
    } else {
      borderColor = choice.isCorrect
          ? AppColors.success.withValues(alpha: 0.70)
          : Colors.white.withValues(alpha: 0.12);
    }

    final IconData leadingIcon;
    if (revealed) {
      leadingIcon =
          choice.isCorrect ? Icons.check_circle_outline : Icons.highlight_off;
    } else {
      leadingIcon = isSelected
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked;
    }

    final iconColor = revealed
        ? (choice.isCorrect ? AppColors.success : AppColors.error)
        : (isSelected
            ? AppColors.ctaStart
            : AppColors.onBackgroundSecondary.withValues(alpha: 0.7));

    // 正誤不只靠顏色：文字標籤一定同時出現。
    final verdictLabel =
        choice.isCorrect ? kChatQuizCorrectLabel : kChatQuizIncorrectLabel;

    final semanticsLabel = revealed
        ? '${choice.text}。$verdictLabel。${isSelected ? '你選了這個。' : ''}${choice.feedback}'
        : '${choice.text}${isSelected ? '，已選取' : ''}';

    return Semantics(
      button: !revealed,
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: PressableScale(
        enabled: !revealed,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: revealed ? null : onTap,
            child: AnimatedContainer(
              duration: AppMotion.state,
              curve: AppMotion.easeOut,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.ctaStart.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 10),
                        child: Icon(leadingIcon, size: 18, color: iconColor),
                      ),
                      Expanded(
                        child: Text(
                          choice.text,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.onBackgroundPrimary,
                            height: 1.4,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 送出後就地展開，不瞬跳：高度 240ms 展開＋內容 200ms 淡入。
                  AnimatedSize(
                    duration: AppMotion.state,
                    curve: AppMotion.easeOut,
                    alignment: Alignment.topCenter,
                    child: !revealed
                        ? const SizedBox(width: double.infinity)
                        : EntranceReveal(
                            duration: AppMotion.state,
                            offsetY: 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                // Wrap 而非 Row：大字級在窄螢幕時兩個標籤放不進一行。
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 2,
                                  children: [
                                    Text(
                                      verdictLabel,
                                      style: AppTypography.caption.copyWith(
                                        color: choice.isCorrect
                                            ? AppColors.success
                                            : AppColors.error,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (isSelected)
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
                                const SizedBox(height: 4),
                                Text(
                                  choice.feedback,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.onBackgroundSecondary
                                        .withValues(alpha: 0.85),
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TakeawayPanel extends StatelessWidget {
  const _TakeawayPanel({
    required this.takeaway,
    required this.solved,
    required this.onReadSource,
  });

  final String takeaway;
  final bool solved;
  final VoidCallback? onReadSource;

  @override
  Widget build(BuildContext context) {
    final accent = solved ? AppColors.success : AppColors.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    solved
                        ? Icons.check_circle_outline
                        : Icons.lightbulb_outline,
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
                takeaway,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        if (onReadSource != null) ...[
          const SizedBox(height: 10),
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
    );
  }
}

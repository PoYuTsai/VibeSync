// lib/features/learning/presentation/widgets/ebook_quiz_card.dart
//
// 情境測驗卡。
//
// 行為約束：
//   - 單選用 radio-like 控件，複選用 checkbox-like 控件。
//   - 提交前絕不揭示正解。
//   - 提交後每個選項都給圖示＋「正確／不是這個」文字＋自己的 feedback，
//     再加全題 takeaway；正誤不能只靠綠紅色差。
//   - retryPolicy=untilCorrect（預設）答錯後可重設再試；答對標示已理解。
//   - restore 由呼叫端以 quizRevision 驗證過才傳進來，revision 改變即視為未作答。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/ebook_block.dart';
import '../../domain/models/ebook_progress.dart';

class EbookQuizCard extends StatefulWidget {
  const EbookQuizCard({
    super.key,
    required this.quiz,
    required this.savedState,
    required this.onSubmit,
  });

  final EbookQuizBlock quiz;

  /// 已經以 [EbookQuizBlock.revision] 驗證過的保存狀態；`null` = 未作答。
  final EbookQuizState? savedState;

  /// 提交後回報給 controller 保存。
  final void Function(Set<String> choiceIds, bool solved) onSubmit;

  @override
  State<EbookQuizCard> createState() => _EbookQuizCardState();
}

class _EbookQuizCardState extends State<EbookQuizCard> {
  late Set<String> _selected;
  late bool _submitted;
  late bool _solved;

  @override
  void initState() {
    super.initState();
    _restoreFromSavedState();
  }

  @override
  void didUpdateWidget(EbookQuizCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 換題目（例如 PageView 回收）時重新以保存狀態開場。
    if (oldWidget.quiz.id != widget.quiz.id ||
        oldWidget.quiz.revision != widget.quiz.revision) {
      _restoreFromSavedState();
    }
  }

  void _restoreFromSavedState() {
    final saved = widget.savedState;
    final validIds = widget.quiz.choices.map((choice) => choice.id).toSet();
    // 只還原目前題目仍存在的選項 id，避免舊 id 造成幽靈選取。
    final restored = <String>{};
    if (saved != null) {
      restored.addAll(saved.selectedChoiceIds.where(validIds.contains));
    }
    _selected = restored;
    _submitted = saved != null && restored.isNotEmpty;
    _solved = saved?.solved ?? false;
  }

  bool get _isMultiple => widget.quiz.mode == EbookQuizMode.multiple;

  bool get _canRetry =>
      widget.quiz.retryPolicy == EbookQuizRetryPolicy.untilCorrect && !_solved;

  void _toggleChoice(String choiceId) {
    if (_submitted) return;
    setState(() {
      if (_isMultiple) {
        if (!_selected.remove(choiceId)) _selected.add(choiceId);
      } else {
        _selected = <String>{choiceId};
      }
    });
  }

  void _submit() {
    if (_selected.isEmpty || _submitted) return;
    final solved = widget.quiz.isSolvedBy(_selected);
    setState(() {
      _submitted = true;
      _solved = solved;
    });
    widget.onSubmit(Set<String>.unmodifiable(_selected), solved);
  }

  void _reset() {
    setState(() {
      _selected = <String>{};
      _submitted = false;
      _solved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final quiz = widget.quiz;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.brandSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.quiz_outlined,
                  size: 16, color: AppColors.ctaStart),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _isMultiple ? '情境測驗 · 可多選' : '情境測驗 · 單選',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_submitted && _solved)
                Semantics(
                  label: '這一題已理解',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_outlined,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(
                        '已理解',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (quiz.scenario != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandInk.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                quiz.scenario!,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  height: 1.45,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            quiz.question,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          for (final choice in quiz.choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ChoiceRow(
                choice: choice,
                isMultiple: _isMultiple,
                isSelected: _selected.contains(choice.id),
                revealed: _submitted,
                onTap: () => _toggleChoice(choice.id),
              ),
            ),
          const SizedBox(height: 4),
          if (!_submitted)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ctaStart,
                  disabledBackgroundColor:
                      Colors.white.withValues(alpha: 0.10),
                  foregroundColor: Colors.white,
                  disabledForegroundColor:
                      Colors.white.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text(
                  '送出答案',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            )
          else
            _ResultPanel(
              quiz: quiz,
              solved: _solved,
              canRetry: _canRetry,
              onRetry: _reset,
            ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.choice,
    required this.isMultiple,
    required this.isSelected,
    required this.revealed,
    required this.onTap,
  });

  final EbookQuizChoice choice;
  final bool isMultiple;
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
      leadingIcon = choice.isCorrect
          ? Icons.check_circle_outline
          : Icons.highlight_off;
    } else if (isMultiple) {
      leadingIcon =
          isSelected ? Icons.check_box_outlined : Icons.check_box_outline_blank;
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
    final verdictLabel = choice.isCorrect ? '正確' : '不是這個';

    final semanticsLabel = revealed
        ? '${choice.text}。$verdictLabel。${isSelected ? '你選了這個。' : ''}${choice.feedback}'
        : '${choice.text}${isSelected ? '，已選取' : ''}';

    return Semantics(
      button: !revealed,
      selected: isSelected,
      inMutuallyExclusiveGroup: !isMultiple,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: revealed ? null : onTap,
          child: Container(
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
                if (revealed) ...[
                  const SizedBox(height: 8),
                  // Wrap 而非 Row：大字級（2.0）在 320px 寬時兩個標籤放不進一行。
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
                          '· 你的選擇',
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
                      color:
                          AppColors.onBackgroundSecondary.withValues(alpha: 0.85),
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.quiz,
    required this.solved,
    required this.canRetry,
    required this.onRetry,
  });

  final EbookQuizBlock quiz;
  final bool solved;
  final bool canRetry;
  final VoidCallback onRetry;

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
                        : Icons.refresh_outlined,
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    solved ? '答對了' : '再想想',
                    style: AppTypography.titleSmall.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                quiz.takeaway,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        if (canRetry) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.replay, size: 16),
              label: const Text(
                '再試一次',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

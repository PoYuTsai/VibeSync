// lib/features/learning/presentation/widgets/ebook_block_renderer.dart
//
// 章節區塊 renderer。
//
// 對 sealed [EbookBlock] 做 exhaustive switch：新增一種 block type 時，
// 編譯器會強迫這裡補上 UI，不會出現「JSON 有但畫面沒有」的靜默漏渲染。
// 未知的 JSON type 更早一步在 parser 就 fail closed，不會走到這裡。
//
// 這個 widget 刻意不碰 Riverpod：互動狀態由呼叫端以 callback 收下，
// 方便 widget test 直接驗行為。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/ebook_block.dart';
import '../../domain/models/ebook_progress.dart';
import 'ebook_checklist_block.dart';
import 'ebook_dialogue_block.dart';
import 'ebook_flip_card.dart';
import 'ebook_quiz_card.dart';
import 'ebook_stage_funnel.dart';

class EbookBlockRenderer extends StatelessWidget {
  const EbookBlockRenderer({
    super.key,
    required this.block,
    required this.progress,
    required this.onQuizSubmitted,
    required this.onChecklistItemChanged,
    required this.onFunnelTargetTap,
  });

  final EbookBlock block;
  final EbookBookProgress progress;

  final void Function(EbookQuizBlock quiz, Set<String> choiceIds, bool solved)
      onQuizSubmitted;
  final void Function(EbookChecklistBlock block, String itemId, bool checked)
      onChecklistItemChanged;

  /// 漏斗診斷的跳章請求。required 是刻意的：漏斗沒接上導覽就等於死按鈕，
  /// 讓編譯器在每個使用處都逼一次。
  final void Function(EbookStageFunnelBlock block, EbookFunnelStage stage)
      onFunnelTargetTap;

  @override
  Widget build(BuildContext context) {
    // 用 local 才能讓 pattern matching 做型別提升（欄位不會被 promote）。
    final block = this.block;
    switch (block) {
      case EbookHeadingBlock():
        return Text(
          block.text,
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        );

      case EbookParagraphBlock():
        return Text(
          block.text,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundSecondary,
            height: 1.62,
          ),
        );

      case EbookBulletListBlock():
        return _BulletList(block: block);

      case EbookCalloutBlock():
        return _Callout(block: block);

      case EbookComparisonBlock():
        return _Comparison(block: block);

      case EbookDialogueBlock():
        return EbookDialogueBlockView(block: block);

      case EbookFlipCardBlock():
        return EbookFlipCard(block: block);

      case EbookQuizBlock():
        return EbookQuizCard(
          quiz: block,
          savedState: progress.quizStateFor(block.id, block.revision),
          onSubmit: (choiceIds, solved) =>
              onQuizSubmitted(block, choiceIds, solved),
        );

      case EbookStageFunnelBlock():
        return EbookStageFunnelView(
          block: block,
          onOpenTarget: (stage) => onFunnelTargetTap(block, stage),
        );

      case EbookChecklistBlock():
        return EbookChecklistBlockView(
          block: block,
          checkedItemIds: progress.checkedItemsFor(block.id),
          onItemChanged: (itemId, checked) =>
              onChecklistItemChanged(block, itemId, checked),
        );
    }
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.block});

  final EbookBulletListBlock block;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.title != null) ...[
          Text(
            block.title!,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (var index = 0; index < block.items.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 2),
                  child: block.ordered
                      ? Text(
                          '${index + 1}.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.ctaStart,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.ctaStart.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                ),
                Expanded(
                  child: Text(
                    block.items[index],
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.block});

  final EbookCalloutBlock block;

  static IconData _iconFor(EbookCalloutTone tone) {
    switch (tone) {
      case EbookCalloutTone.info:
        return Icons.info_outline;
      case EbookCalloutTone.principle:
        return Icons.architecture_outlined;
      case EbookCalloutTone.goal:
        return Icons.flag_outlined;
      case EbookCalloutTone.safety:
        return Icons.shield_outlined;
      case EbookCalloutTone.warning:
        return Icons.report_problem_outlined;
      case EbookCalloutTone.takeaway:
        return Icons.local_florist_outlined;
    }
  }

  static Color _accentFor(EbookCalloutTone tone) {
    switch (tone) {
      case EbookCalloutTone.info:
        return AppColors.info;
      case EbookCalloutTone.principle:
        return AppColors.coachAccentBright;
      case EbookCalloutTone.goal:
        return AppColors.ctaStart;
      case EbookCalloutTone.safety:
        return AppColors.success;
      case EbookCalloutTone.warning:
        return AppColors.warning;
      case EbookCalloutTone.takeaway:
        return AppColors.brandBlush;
    }
  }

  /// 語意標籤。安全提醒不能只靠盾牌圖示，文字要說出來。
  static String _kickerFor(EbookCalloutTone tone) {
    switch (tone) {
      case EbookCalloutTone.info:
        return '補充';
      case EbookCalloutTone.principle:
        return '原理';
      case EbookCalloutTone.goal:
        return '本章目標';
      case EbookCalloutTone.safety:
        return '安全與界線';
      case EbookCalloutTone.warning:
        return '注意';
      case EbookCalloutTone.takeaway:
        return '今天帶走';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(block.tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(block.tone), size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _kickerFor(block.tone),
                  style: AppTypography.caption.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (block.title != null) ...[
            const SizedBox(height: 8),
            Text(
              block.title!,
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            block.text,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.block});

  final EbookComparisonBlock block;

  static IconData _iconFor(EbookComparisonStance stance) {
    switch (stance) {
      case EbookComparisonStance.weak:
        return Icons.thumb_down_off_alt_outlined;
      case EbookComparisonStance.strong:
        return Icons.thumb_up_off_alt_outlined;
      case EbookComparisonStance.neutral:
        return Icons.drag_indicator;
    }
  }

  static Color _accentFor(EbookComparisonStance stance) {
    switch (stance) {
      case EbookComparisonStance.weak:
        return AppColors.error;
      case EbookComparisonStance.strong:
        return AppColors.success;
      case EbookComparisonStance.neutral:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.title != null) ...[
          Text(
            block.title!,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final item in block.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _accentFor(item.stance).withValues(alpha: 0.40),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_iconFor(item.stance),
                          size: 14, color: _accentFor(item.stance)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.label,
                          style: AppTypography.caption.copyWith(
                            color: _accentFor(item.stance),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.text,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      height: 1.5,
                    ),
                  ),
                  if (item.note != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.note!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.80),
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (block.caption != null)
          Text(
            block.caption!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.72),
              height: 1.4,
            ),
          ),
      ],
    );
  }
}

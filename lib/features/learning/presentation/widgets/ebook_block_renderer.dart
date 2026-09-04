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
import '../../domain/models/ebook.dart';
import '../../domain/models/ebook_block.dart';
import '../../domain/models/ebook_progress.dart';
import 'ebook_checklist_block.dart';
import 'ebook_dialogue_block.dart';
import 'ebook_entry_list.dart';
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
    required this.onCrossRefTap,
    this.layout = EbookReadingLayout.framed,
    this.anchorEntryId,
    this.onAnchorConsumed,
  });

  final EbookBlock block;
  final EbookBookProgress progress;

  /// 這本書的排版語言。預設 [EbookReadingLayout.framed]：新增呼叫點忘了傳時
  /// 落在既有外觀，不會讓某本書突然換一種樣子。
  final EbookReadingLayout layout;

  /// 從交叉指涉跳過來時要自動展開的條目 id。
  final String? anchorEntryId;

  /// 條目庫展開並捲到定位之後回呼，讓呼叫端把 anchor 清掉——否則讀者手動
  /// 收合再換章回來，它會自己又打開一次。
  final VoidCallback? onAnchorConsumed;

  final void Function(EbookQuizBlock quiz, Set<String> choiceIds, bool solved)
      onQuizSubmitted;
  final void Function(EbookChecklistBlock block, String itemId, bool checked)
      onChecklistItemChanged;

  /// 漏斗診斷的跳章請求。required 是刻意的：漏斗沒接上導覽就等於死按鈕，
  /// 讓編譯器在每個使用處都逼一次。
  final void Function(EbookStageFunnelBlock block, EbookFunnelStage stage)
      onFunnelTargetTap;

  /// 交叉指涉的前往請求。同樣 required：沒接上導覽的按鈕就是死按鈕。
  final void Function(EbookCrossRefBlock block) onCrossRefTap;

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
        return _Callout(block: block, layout: layout);

      case EbookComparisonBlock():
        return _Comparison(block: block, layout: layout);

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

      case EbookEntryListBlock():
        return EbookEntryListView(
          block: block,
          anchorEntryId: anchorEntryId,
          onAnchorConsumed: onAnchorConsumed,
          // 巢狀 block 走同一個 renderer，quiz／checklist 的 callback 一路傳下去。
          entryBlockBuilder: (child) => EbookBlockRenderer(
            block: child,
            progress: progress,
            layout: layout,
            onQuizSubmitted: onQuizSubmitted,
            onChecklistItemChanged: onChecklistItemChanged,
            onFunnelTargetTap: onFunnelTargetTap,
            onCrossRefTap: onCrossRefTap,
          ),
        );

      case EbookCrossRefBlock():
        return _CrossRefButton(
          block: block,
          onTap: () => onCrossRefTap(block),
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

/// 交叉指涉按鈕。整塊可點，不是行內連結——手機上行內連結的觸控面積太小，
/// 而且按之前看不出會去哪。
class _CrossRefButton extends StatelessWidget {
  const _CrossRefButton({required this.block, required this.onTap});

  final EbookCrossRefBlock block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '前往${block.label}，位於${block.contextLabel}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.42)),
            ),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        block.contextLabel,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.info,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        block.label,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onBackgroundPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: AppColors.info.withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: block.ordered
                      ? Text(
                          '${index + 1}.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.ctaStart,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: 8),
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
  const _Callout({required this.block, required this.layout});

  final EbookCalloutBlock block;
  final EbookReadingLayout layout;

  /// 內容紅線的視覺守門：這兩個 tone 在任何排版下都維持整框。
  ///
  /// 內容不變量測試會要求含守門詞的章節必須有 warning／safety callout；把它們
  /// 降成跟原理、今天帶走一樣的左側色條，等於讓「這裡有風險」跟一般重點在畫面
  /// 上同重，守門就只剩測試層還在守。
  static bool _mustStayFramed(EbookCalloutTone tone) =>
      tone == EbookCalloutTone.warning || tone == EbookCalloutTone.safety;

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
      case EbookCalloutTone.fix:
        return Icons.build_outlined;
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
      case EbookCalloutTone.fix:
        return AppColors.success;
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
      case EbookCalloutTone.fix:
        return '修正';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(block.tone);
    final spine =
        layout == EbookReadingLayout.spine && !_mustStayFramed(block.tone);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 左側色條已經在講 tone，圖示再講一次是重複的裝飾；文字 kicker
            // 一律保留，安全提醒本來就不能只靠圖示。
            if (!spine) ...[
              Icon(_iconFor(block.tone), size: 16, color: accent),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                _kickerFor(block.tone),
                style: AppTypography.caption.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: spine ? 1.2 : null,
                ),
              ),
            ),
          ],
        ),
        if (block.title != null) ...[
          SizedBox(height: spine ? 4 : 8),
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
    );

    if (spine) {
      return Container(
        width: double.infinity,
        // 只有左邊有線。上下留白比整框版小：沒有外框要撐開，靠留白分段就夠。
        padding: const EdgeInsets.fromLTRB(16, 2, 0, 2),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: accent.withValues(alpha: 0.85), width: 3),
          ),
        ),
        child: body,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
      ),
      child: body,
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.block, required this.layout});

  final EbookComparisonBlock block;
  final EbookReadingLayout layout;

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
        // 題目前提排在答案卡之前，讀者（與 VoiceOver）才不會先聽到答案再回頭
        // 找題目；比較後的結論仍留在 caption，排在 items 之後。
        if (block.scenario != null) ...[
          Text(
            block.scenario!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.72),
              height: 1.4,
            ),
          ),
          SizedBox(height: layout == EbookReadingLayout.spine ? 12 : 10),
        ],
        for (final item in block.items)
          Padding(
            padding: EdgeInsets.only(
              bottom: layout == EbookReadingLayout.spine ? 16 : 8,
            ),
            child: Container(
              width: double.infinity,
              padding: layout == EbookReadingLayout.spine
                  ? const EdgeInsets.fromLTRB(16, 0, 0, 0)
                  : const EdgeInsets.all(16),
              decoration: layout == EbookReadingLayout.spine
                  ? BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: _accentFor(item.stance)
                              .withValues(alpha: 0.85),
                          width: 3,
                        ),
                      ),
                    )
                  : BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(18),
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

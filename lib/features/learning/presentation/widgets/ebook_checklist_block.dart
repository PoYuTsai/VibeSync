// lib/features/learning/presentation/widgets/ebook_checklist_block.dart
//
// 自評 checklist。只保存 item id 與勾選狀態，刻意不提供任何自由文字輸入
// （MVP 不儲存使用者的真實聊天或長篇反思）。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/ebook_block.dart';

class EbookChecklistBlockView extends StatelessWidget {
  const EbookChecklistBlockView({
    super.key,
    required this.block,
    required this.checkedItemIds,
    required this.onItemChanged,
  });

  final EbookChecklistBlock block;
  final Set<String> checkedItemIds;
  final void Function(String itemId, bool checked) onItemChanged;

  @override
  Widget build(BuildContext context) {
    final checkedCount =
        block.items.where((item) => checkedItemIds.contains(item.id)).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.brandSurface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rtl,
                  size: 16, color: AppColors.ctaStart),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  block.title ?? '自評 checklist',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$checkedCount / ${block.items.length}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary
                      .withValues(alpha: 0.78),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (block.caption != null) ...[
            const SizedBox(height: 6),
            Text(
              block.caption!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.72),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final item in block.items)
            _ChecklistRow(
              item: item,
              checked: checkedItemIds.contains(item.id),
              onChanged: (checked) => onItemChanged(item.id, checked),
            ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.item,
    required this.checked,
    required this.onChanged,
  });

  final EbookChecklistItem item;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      label: '${item.text}${item.note == null ? '' : '。${item.note}'}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onChanged(!checked),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 8),
                  child: Icon(
                    checked
                        ? Icons.check_box_outlined
                        : Icons.check_box_outline_blank,
                    size: 20,
                    color: checked
                        ? AppColors.success
                        : AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.68),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.text,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onBackgroundPrimary,
                          height: 1.4,
                          fontWeight:
                              checked ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (item.note != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.note!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onBackgroundSecondary
                                .withValues(alpha: 0.72),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

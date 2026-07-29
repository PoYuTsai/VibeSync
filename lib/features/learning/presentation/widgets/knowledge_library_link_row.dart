// lib/features/learning/presentation/widgets/knowledge_library_link_row.dart
//
// 「從結論進到原理」的統一入口列。
//
// 純 presentation：只畫外觀、把點擊丟回呼叫端。導頁留在各自的畫面層，
// 因為每個入口 push 之前要做的清理不同（分析頁要先收 SnackBar），
// 而且既有的 CoachActionCard 契約是 callback，不該為了共用外觀把它翻掉。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class KnowledgeLibraryLinkRow extends StatelessWidget {
  const KnowledgeLibraryLinkRow({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
  });

  final String label;
  final VoidCallback onTap;

  /// 預設用 CTA 主色；玻璃卡以外的背景可覆寫。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.ctaStart;
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_forward,
            size: 14,
            color: tint,
          ),
        ],
      ),
    );
  }
}

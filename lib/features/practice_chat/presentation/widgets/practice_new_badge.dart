import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 「NEW」小標：練習室入口卡的標題旁、翻牌揭曉的新角色（V3.1 規格 §5.14）共用同一顆。
class PracticeNewBadge extends StatelessWidget {
  const PracticeNewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ctaStart,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'NEW',
        style: TextStyle(
          color: AppColors.onCta,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0,
          height: 1,
        ),
      ),
    );
  }
}

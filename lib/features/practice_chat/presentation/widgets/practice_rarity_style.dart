// 稀有度呈現的單一真相（圖鑑卡與翻牌揭曉結果卡共用）：主色／badge／星等。
// display-only：抽中機率由 server 加權決定，這裡只管視覺。
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/practice_girl_rarity.dart';

/// 稀有度主色：SR 金、R 紫、N 冷灰藍。只用於邊框／badge／星等。
Color practiceRarityColor(PracticeGirlRarity rarity) {
  switch (rarity) {
    case PracticeGirlRarity.sr:
      return const Color(0xFFFFB34D);
    case PracticeGirlRarity.r:
      return AppColors.primaryLight;
    case PracticeGirlRarity.n:
      return const Color(0xFF8FA0BE);
  }
}

/// 稀有度 badge 膠囊（rarity 色底＋label）。
class PracticeRarityBadge extends StatelessWidget {
  const PracticeRarityBadge({
    super.key,
    required this.rarity,
    this.fontSize = 10,
  });

  final PracticeGirlRarity rarity;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: practiceRarityColor(rarity),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        rarity.label,
        style: AppTypography.caption.copyWith(
          color: AppColors.brandInk,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// 星等列（滿星 5）：亮星＝rarity 色、空星＝白 18%。
class PracticeRarityStars extends StatelessWidget {
  const PracticeRarityStars({
    super.key,
    required this.rarity,
    this.size = 14,
  });

  final PracticeGirlRarity rarity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = practiceRarityColor(rarity);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < rarity.stars
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            size: size,
            color: i < rarity.stars
                ? color
                : Colors.white.withValues(alpha: 0.18),
          ),
      ],
    );
  }
}

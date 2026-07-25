// lib/features/learning/presentation/widgets/ebook_cover_badge.dart
//
// 書封元素。刻意不新增封面圖檔：書號＋主題 icon＋品牌漸層就是封面。
// JSON 只給語意 theme key，圖示與配色在這裡查表。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/ebook.dart';

IconData ebookThemeIcon(EbookTheme theme) {
  switch (theme) {
    case EbookTheme.compass:
      return Icons.explore_outlined;
    case EbookTheme.lens:
      return Icons.travel_explore_outlined;
    case EbookTheme.firstAid:
      return Icons.medical_services_outlined;
    case EbookTheme.bridge:
      return Icons.route_outlined;
  }
}

List<Color> ebookThemeGradient(EbookTheme theme) {
  switch (theme) {
    case EbookTheme.compass:
      return const [AppColors.ctaStart, AppColors.brandBlush];
    case EbookTheme.lens:
      return const [AppColors.coachAccent, AppColors.coachAccentBright];
    case EbookTheme.firstAid:
      return const [AppColors.hot, AppColors.brandBlush];
    case EbookTheme.bridge:
      return const [AppColors.cold, AppColors.coachAccent];
  }
}

class EbookCoverBadge extends StatelessWidget {
  const EbookCoverBadge({
    super.key,
    required this.book,
    this.size = 56,
  });

  final Ebook book;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '第 ${book.number} 冊',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: ebookThemeGradient(book.theme),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              ebookThemeIcon(book.theme),
              size: size * 0.34,
              color: Colors.white,
            ),
            const SizedBox(height: 2),
            Text(
              '第 ${book.number} 冊',
              style: AppTypography.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

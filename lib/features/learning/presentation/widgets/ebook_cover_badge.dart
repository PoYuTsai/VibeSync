// lib/features/learning/presentation/widgets/ebook_cover_badge.dart
//
// 書封元素。
//
// 2026-07-27 夥伴回饋：原本的「書號＋主題 icon＋漸層」太像設定選項，改成人物
// 照片（官網 Blog 卡片的做法）。照片沿用練習室既有的 100 張圖，不新增資產；
// 書號改成壓在照片下緣的標籤，排序資訊不會消失。
//
// JSON 仍然只給語意 theme key：照片與配色在這裡查表，內容檔不出現資產路徑。
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

/// 每本書的封面照。沿用練習室的圖庫，不新增資產。
///
/// 選圖標準：正面清楚、單人、衣著日常，並且和該冊主題有一點呼應
/// （書店／相機／辦公室／店裡）。要換圖只改這裡的編號。
String ebookCoverPhotoAsset(EbookTheme theme) {
  const base = 'assets/images/practice_girls';
  switch (theme) {
    case EbookTheme.compass:
      return '$base/practice_girl_012.jpg';
    case EbookTheme.lens:
      return '$base/practice_girl_034.jpg';
    case EbookTheme.firstAid:
      return '$base/practice_girl_061.jpg';
    case EbookTheme.bridge:
      return '$base/practice_girl_083.jpg';
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
    // 書封是固定比例的裝飾元素：讓它隨字級長大（有上限），內層再用
    // FittedBox 收斂，這樣 2.0 字級下既讀得到書號也不會 overflow。
    final scale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);
    final boxSize = size * scale;

    final accent = ebookThemeGradient(book.theme).first;
    final radius = BorderRadius.circular(boxSize * 0.28);

    return Semantics(
      label: '第 ${book.number} 冊',
      excludeSemantics: true,
      child: Container(
        width: boxSize,
        height: boxSize,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.4),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 主題漸層當底：照片還沒解出來或讀不到時，看到的仍是這本書的顏色
              // 而不是一塊黑。
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: ebookThemeGradient(book.theme),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Image.asset(
                ebookCoverPhotoAsset(book.theme),
                fit: BoxFit.cover,
                // 直式照片裁成方形：臉在偏上，對齊要往上挪才不會只剩下巴。
                alignment: const Alignment(0, -0.45),
                errorBuilder: (context, _, __) => Center(
                  child: Icon(
                    ebookThemeIcon(book.theme),
                    size: boxSize * 0.34,
                    color: Colors.white,
                  ),
                ),
              ),
              // 下緣壓一層暗角，書號才在任何一張照片上都讀得到。
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: boxSize * 0.08),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '第 ${book.number} 冊',
                      textScaler: TextScaler.noScaling,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: size * 0.17,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

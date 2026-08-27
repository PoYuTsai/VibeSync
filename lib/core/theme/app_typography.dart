// lib/core/theme/app_typography.dart
//
// 字級尺度（DESIGN.md §3，B5 批 2026-08-10 上線）：12 / 15 / 19 / 24 / 30 / 38。
// 相鄰級距 ≥1.25，內文統一 15，12 只給 caption/label；38 是 display 檔，
// 保留給 hero 數字與儀式時刻。lib/ 內散落 fontSize 一律貼齊這六檔。
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  /// Display 檔（38）——hero 數字、儀式時刻專用，不做一般標題。
  static const display = TextStyle(
    fontSize: 38,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const headlineLarge = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const headlineMedium = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const titleLarge = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// 頁面標題（AppBar）唯一字級檔：19 / w800 / 白字。
  /// 沒有指定時 Flutter 會落回 `textTheme.titleLarge`——那在 iOS 上是
  /// `.SF UI Display` 22/w400，字體家族、字級、字重全部跟 App 其他頁不同
  /// （2026-08-27 Eric 真機回報「新增對象」標題字體不一樣）。所以
  /// AppBarTheme 與 brandAppBar 都綁這一顆，不要各自寫 TextStyle。
  static const appBarTitle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w800,
    color: AppColors.onBackgroundPrimary,
  );

  static const titleMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const bodyLarge = TextStyle(
    fontSize: 15,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static const bodyMedium = TextStyle(
    fontSize: 15,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const labelLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: AppColors.textSecondary,
  );

  static const labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: AppColors.textSecondary,
  );

  static const titleSmall = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const bodySmall = TextStyle(
    fontSize: 12,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const caption = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );
}

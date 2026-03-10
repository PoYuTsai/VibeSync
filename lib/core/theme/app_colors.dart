// lib/core/theme/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary - Deep Purple
  static const primary = Color(0xFF6B4EE6);
  static const primaryLight = Color(0xFF9D8DF7);
  static const primaryDark = Color(0xFF4527A0);

  // Enthusiasm Levels
  static const cold = Color(0xFF64B5F6);
  static const warm = Color(0xFFFFD54F);
  static const hot = Color(0xFFFF8A65);
  static const veryHot = Color(0xFFFF6B9D);

  // Neutral (Dark Mode)
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceVariant = Color(0xFF2D2D2D);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B3);
  static const divider = Color(0xFF3D3D3D);

  // Semantic
  static const success = Color(0xFF4CAF50);
  static const error = Color(0xFFE57373);
  static const warning = Color(0xFFFFB74D);
  static const info = Color(0xFF64B5F6);

  // === Warm Theme - 漸層背景 ===
  static const backgroundGradientStart = Color(0xFF1A0533);  // 深紫
  static const backgroundGradientMid = Color(0xFF2D1B4E);    // 中紫
  static const backgroundGradientEnd = Color(0xFF4A2C6A);    // 淡紫

  // === Warm Theme - 光暈泡泡 ===
  static const bokehPink = Color(0xFFFF6B9D);
  static const bokehCoral = Color(0xFFFF8A65);
  static const bokehYellow = Color(0xFFFFD54F);

  // === Warm Theme - 毛玻璃 (改用實色，更穩定) ===
  static const glassWhite = Color(0xFFFAF5F8);     // 更淺的粉白色
  static const glassBorder = Color(0xFFFFFFFF);    // 純白邊框

  // === Warm Theme - 毛玻璃文字 ===
  static const glassTextPrimary = Color(0xFF4A3548);   // 深紫灰 (主要文字)
  static const glassTextHint = Color(0xFF8B4557);      // 酒紅色 (hint，參考圖風格)

  // === Warm Theme - 未選中狀態文字 ===
  static const unselectedText = Color(0xFF5D4E6B);     // 深紫灰色

  // === Warm Theme - 選中狀態 ===
  static const selectedStart = Color(0xFFFF6B9D);
  static const selectedEnd = Color(0xFFFF8A65);

  // === Warm Theme - CTA 按鈕 ===
  static const ctaStart = Color(0xFFFF7043);
  static const ctaEnd = Color(0xFFFF5722);

  // === Warm Theme - 頭像漸層 ===
  static const avatarHerStart = Color(0xFFFFD54F);
  static const avatarHerEnd = Color(0xFFFFC107);
  static const avatarMeStart = Color(0xFF9D8DF7);
  static const avatarMeEnd = Color(0xFF6B4EE6);
}

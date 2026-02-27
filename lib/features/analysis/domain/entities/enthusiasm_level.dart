// lib/features/analysis/domain/entities/enthusiasm_level.dart
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:flutter/material.dart';

enum EnthusiasmLevel {
  cold,
  warm,
  hot,
  veryHot;

  static EnthusiasmLevel fromScore(int score) {
    if (score <= AppConstants.coldMax) return cold;
    if (score <= AppConstants.warmMax) return warm;
    if (score <= AppConstants.hotMax) return hot;
    return veryHot;
  }

  String get label {
    switch (this) {
      case cold:
        return '冰點';
      case warm:
        return '溫和';
      case hot:
        return '熱情';
      case veryHot:
        return '高熱';
    }
  }

  String get emoji {
    switch (this) {
      case cold:
        return '❄️';
      case warm:
        return '🌤️';
      case hot:
        return '🔥';
      case veryHot:
        return '💖';
    }
  }

  Color get color {
    switch (this) {
      case cold:
        return AppColors.cold;
      case warm:
        return AppColors.warm;
      case hot:
        return AppColors.hot;
      case veryHot:
        return AppColors.veryHot;
    }
  }
}

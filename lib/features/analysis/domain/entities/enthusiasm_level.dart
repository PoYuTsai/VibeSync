// lib/features/analysis/domain/entities/enthusiasm_level.dart
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

/// 鏡像 server post_process 的 finalize 校準：ceil(clamp(raw,0,100) × 0.9)，
/// raw 100 → 顯示 90。只給「尚未經 server finalize」的即時串流指標用；
/// finalResult 的 enthusiasm score 已在 server 校準過，不得再套一次。
int calibrateVisibleInvestment(num raw) => (raw.clamp(0, 100) * 0.9).ceil();

/// Defensive display clamp for already-finalized or legacy stored scores.
/// This does not apply the 0.9 calibration a second time.
int clampVisibleInvestmentScore(num score) =>
    score.clamp(0, AppConstants.investmentVisibleMax).round();

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
        return '投入偏低';
      case warm:
        return '有在回應';
      case hot:
        return '投入明顯';
      case veryHot:
        return '高度投入';
    }
  }

  IconData get icon {
    switch (this) {
      case cold:
        return TablerIcons.snowflake;
      case warm:
        return TablerIcons.sun_low;
      case hot:
        return TablerIcons.flame;
      case veryHot:
        return TablerIcons.hearts;
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

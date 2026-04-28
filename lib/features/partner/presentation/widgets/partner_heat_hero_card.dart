// lib/features/partner/presentation/widgets/partner_heat_hero_card.dart
//
// Hero card on PartnerDetailScreen — surfaces "this person's interaction
// state" instead of just listing data. Post-A2 visual polish (2026-04-28).
//
// Hard rules:
//  - Heat number is read-only from existing data (latest conversation /
//    aggregate). NEVER synthesize a score. NEVER call AI from this widget.
//  - Label/subtitle are deterministic — see `PartnerHeatMessaging`.
//  - Null heat → "--" + 待分析 placeholder copy. Empty state must look
//    intentional, not "broken".
//  - Right-side orb is pure Flutter (RadialGradient + BoxShadow). NO image
//    asset, NO DALL-E.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Deterministic mapping from heat (0-100, nullable) to display strings.
/// Locked spec — see partner_heat_hero_card_test.dart for the contract.
class PartnerHeatMessaging {
  PartnerHeatMessaging._();

  static String labelFor(int? heat) {
    if (heat == null) return '待分析';
    if (heat <= 30) return '冷靜觀察';
    if (heat <= 60) return '穩定互動';
    if (heat <= 80) return '升溫中';
    return '高互動熱度';
  }

  static String subtitleFor(int? heat) {
    if (heat == null) return '新增或分析第一段互動後，這裡會顯示狀態';
    if (heat <= 30) return '先觀察節奏，別急著推進';
    if (heat <= 60) return '互動穩定，可以慢慢加深';
    if (heat <= 80) return '關係正在升溫中';
    return '互動熱度很高，適合延續話題';
  }

  static String numberFor(int? heat) => heat?.toString() ?? '--';
}

class PartnerHeatHeroCard extends StatelessWidget {
  final int? heat;
  const PartnerHeatHeroCard({super.key, required this.heat});

  @override
  Widget build(BuildContext context) {
    final number = PartnerHeatMessaging.numberFor(heat);
    final label = PartnerHeatMessaging.labelFor(heat);
    final subtitle = PartnerHeatMessaging.subtitleFor(heat);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 32,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number,
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackgroundPrimary,
                    height: 1.0,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _HeatOrb(),
        ],
      ),
    );
  }
}

/// Abstract decorative orb on the right side of the hero. Two stacked
/// radial gradients (purple halo + warm pink core) — purely visual, no
/// data binding. Kept const to avoid rebuild churn when heat updates.
class _HeatOrb extends StatelessWidget {
  const _HeatOrb();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primaryLight.withValues(alpha: 0.55),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.bokehPink.withValues(alpha: 0.65),
                  AppColors.bokehPink.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

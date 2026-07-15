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

  static const scopeExplanation = '只反映這次互動中的文字訊號，不代表關係進度。';

  static String labelFor(int? heat) {
    if (heat == null) return '待分析';
    if (heat <= 30) return '投入偏低';
    if (heat <= 60) return '有在回應';
    if (heat <= 80) return '投入明顯';
    return '高度投入';
  }

  static String subtitleFor(int? heat) {
    if (heat == null) return '分析第一段互動後，這裡會顯示對方這次的投入度';
    if (heat <= 30) return '這次文字訊號較少';
    if (heat <= 60) return '這次有回應，投入訊號普通';
    if (heat <= 80) return '這次有多個明顯的投入訊號';
    return '這次文字訊號呈現高度投入';
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
                  '對方這次的投入度',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                const SizedBox(height: 6),
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
                const SizedBox(height: 8),
                Text(
                  PartnerHeatMessaging.scopeExplanation,
                  style: AppTypography.caption.copyWith(
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

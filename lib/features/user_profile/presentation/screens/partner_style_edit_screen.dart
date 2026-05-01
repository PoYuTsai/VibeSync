import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../partner/presentation/providers/partner_providers.dart';

/// Stub edit screen — Spec 2 Phase 5 Task 13.
///
/// Wires the `/partner/:partnerId/my-style` route so the inline entry card
/// has a destination. Real per-field UI (chips, notes, save) lands in
/// Phase 6 (Tasks 14–18).
class PartnerStyleEditScreen extends ConsumerWidget {
  const PartnerStyleEditScreen({super.key, required this.partnerId});

  final String partnerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerByIdProvider(partnerId));
    final title =
        partner == null ? '我的風格' : '我的風格 · ${partner.name}';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '編輯介面 Phase 6 上線',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// lib/features/partner/presentation/screens/partner_list_screen.dart
//
// Phase 2 Home tab body — replaces the old conversation-centric HomeContent.
//
// Aggregate is watched AT THE LIST LEVEL (not inside the card) so each row
// re-evaluates only when its own partner's conversations change. This keeps
// the narrow-invalidation contract intact (Codex C1) and lets the card stay
// pure-render (Codex r1 P1.3b).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_list_card.dart';

class PartnerListScreen extends ConsumerWidget {
  const PartnerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partners = ref.watch(partnerListProvider);
    if (partners.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '還沒有對象，從右下加一個開始',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: partners.length,
      itemBuilder: (context, i) {
        final p = partners[i];
        final agg = ref.watch(partnerAggregateProvider(p.id));
        return PartnerListCard(
          partner: p,
          aggregate: agg,
          onTap: () => context.push('/partner/${p.id}'),
        );
      },
    );
  }
}

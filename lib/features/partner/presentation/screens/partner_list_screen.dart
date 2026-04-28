// lib/features/partner/presentation/screens/partner_list_screen.dart
//
// Phase 2 Home tab body — partner-first replacement for the old
// conversation-centric home (deprecated donor removed in Phase 4 Task 6).
//
// Aggregate is watched AT THE LIST LEVEL (not inside the card) so each row
// re-evaluates only when its own partner's conversations change. This keeps
// the narrow-invalidation contract intact (Codex C1) and lets the card stay
// pure-render (Codex r1 P1.3b).
//
// Phase 4 Task 2 also captures the live `conversationsByPartner.length` per
// row and routes it into the two-mode delete dialog. Counting from the
// provider — NOT from `aggregate.totalRounds` — guards against the
// zero-round-conversation false-safe (Codex P1.2).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../data/providers/partner_banner_providers.dart';
import '../../data/providers/partner_write_controller.dart';
import '../../data/repositories/partner_repository.dart';
import '../../data/services/partner_banner_service.dart';
import '../../domain/entities/partner.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_list_card.dart';
import '../widgets/same_name_dedupe_banner.dart';

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

    // Banner gating (Phase 4 Task 4):
    //   uid null  → no banner (no scope to key dismissal)
    //   no dup    → no banner
    //   dismissed → no banner (loading/error also treated as "don't show")
    final uid = ref.watch(authConversationScopeProvider).valueOrNull;
    final dupPair = uid == null ? null : _findFirstDupPair(partners);
    final dismissedAsync = uid == null
        ? const AsyncValue<bool>.data(true)
        : ref.watch(partnerDedupeBannerDismissedProvider(uid));
    final showBanner = dupPair != null && dismissedAsync.value == false;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      // +1 for the banner slot when shown.
      itemCount: partners.length + (showBanner ? 1 : 0),
      itemBuilder: (context, i) {
        if (showBanner && i == 0) {
          return SameNameDedupeBanner(
            partnerName: dupPair.newer.name,
            onMergeTap: () => context.push(
              '/partner/${dupPair.newer.id}/merge?target=${dupPair.older.id}',
            ),
            onDismissTap: () async {
              await PartnerBannerService.markDismissed(uid!);
              try {
                // Guard against widget disposal during the await above —
                // sign-out / nav-away invalidates ref before this lands.
                ref.invalidate(partnerDedupeBannerDismissedProvider(uid));
              } catch (e, st) {
                // Widget disposed; invalidation is moot, but keep a breadcrumb
                // in debug logs so real dismiss failures are not silent.
                debugPrint(
                  'PartnerListScreen banner dismiss invalidation skipped: '
                  '$e\n$st',
                );
              }
            },
          );
        }
        final pIndex = showBanner ? i - 1 : i;
        final p = partners[pIndex];
        final agg = ref.watch(partnerAggregateProvider(p.id));
        // Codex P1.2 — count real conversation rows, not aggregate.totalRounds
        // (zero-round conversations would otherwise be invisible to the
        // delete dialog and let the user fall straight into the repo throw).
        final convCount =
            ref.watch(conversationsByPartnerProvider(p.id)).length;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: PartnerListCard(
            partner: p,
            aggregate: agg,
            onTap: () => context.push('/partner/${p.id}'),
            onDelete: () => _onDelete(context, ref, p, convCount),
          ),
        );
      },
    );
  }

  /// First same-name pair, ordered by createdAt ASC.
  /// Returns null when no group of size ≥2 exists.
  /// older=earliest createdAt (survivor); newer=second earliest (absorbed).
  /// (D-P4-2: keep the older identity, absorb the newer duplicate into it.)
  ({Partner older, Partner newer})? _findFirstDupPair(List<Partner> partners) {
    final byName = <String, List<Partner>>{};
    for (final p in partners) {
      byName.putIfAbsent(p.name, () => []).add(p);
    }
    for (final entry in byName.entries) {
      if (entry.value.length >= 2) {
        final sorted = [...entry.value]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return (older: sorted[0], newer: sorted[1]);
      }
    }
    return null;
  }

  Future<void> _onDelete(
    BuildContext context,
    WidgetRef ref,
    Partner partner,
    int conversationCount,
  ) async {
    if (conversationCount > 0) {
      await _showInformationalDialog(context, partner, conversationCount);
      return;
    }
    await _showConfirmDialog(context, ref, partner);
  }

  Future<void> _showInformationalDialog(
    BuildContext context,
    Partner partner,
    int conversationCount,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '無法刪除',
          style: const TextStyle(color: AppColors.glassTextPrimary),
        ),
        content: Text(
          '「${partner.name}」還有 $conversationCount 個對話，無法刪除。'
          '請先合併重複對象，或改派對話到其他對象。',
          style: const TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _showConfirmDialog(
    BuildContext context,
    WidgetRef ref,
    Partner partner,
  ) async {
    // Capture messenger before any await so we don't reuse `context` across
    // async gaps (avoids `use_build_context_synchronously` lint).
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '刪除對象',
          style: const TextStyle(color: AppColors.glassTextPrimary),
        ),
        content: Text(
          '確定刪除「${partner.name}」？',
          style: const TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '取消',
              style: const TextStyle(color: AppColors.unselectedText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(partnerWriteControllerProvider.notifier).delete(partner);
      messenger.showSnackBar(
        SnackBar(content: Text('已刪除「${partner.name}」')),
      );
    } on PartnerHasConversationsException catch (e) {
      // Defensive — a conversation may have been created between the
      // dialog open and the repo call. Surface the live count.
      messenger.showSnackBar(
        SnackBar(
          content: Text('刪除失敗：仍有 ${e.conversationCount} 個對話'),
        ),
      );
    } catch (e, st) {
      debugPrint('PartnerListScreen delete failed: $e\n$st');
      messenger.showSnackBar(
        const SnackBar(content: Text('刪除失敗，請稍後再試')),
      );
    }
  }
}

// lib/features/partner/presentation/screens/partner_detail_screen.dart
//
// Partner detail — post-A2 visual polish (2026-04-28).
// Mood: 深夜陪你讀懂這段關係，不是冷冰冰的 dashboard。
//
// Visual pattern:
//  - Transparent Scaffold + extendBodyBehindAppBar so the dark navy
//    backdrop sits under the AppBar (mirrors the AddPartner screen).
//  - Background = vertical gradient (very dark navy) + 3 STATIC glow
//    bubbles (no AnimationController — keeps widget tests pumpAndSettle-safe).
//  - PartnerHeatHeroCard at top reads `aggregate.latestHeat` only —
//    NO synthesized score, NO AI insight (per scope lock).
//  - Existing PartnerTraitsCard / PartnerRadarSummaryCard / Tile keep
//    their data sources; only their surface styling is upgraded.
//
// Behavior unchanged:
//  - ⋮ menu (merge / edit / delete-即將推出) — see partner_detail_screen_test.
//  - FAB still opens NewConversationSheet(partnerId).
//  - FAB label STAYS "+ 新增對話" per ADR-15 vocabulary contract
//    (see test/widget/features/copy_sweep_snapshot_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/data/providers/conversation_write_controller.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/presentation/dialogs/conversation_reassign_picker.dart';
import '../../../conversation/presentation/dialogs/delete_conversation_confirm_dialog.dart';
import '../../../conversation/presentation/widgets/new_conversation_sheet.dart';
import '../../data/providers/partner_write_controller.dart';
import '../../domain/entities/partner.dart';
import '../dialogs/partner_edit_dialog.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_conversation_tile.dart';
import '../widgets/partner_heat_hero_card.dart';
import '../widgets/partner_radar_summary_card.dart';
import '../widgets/partner_traits_card.dart';

class PartnerDetailScreen extends ConsumerWidget {
  final String partnerId;
  const PartnerDetailScreen({super.key, required this.partnerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerByIdProvider(partnerId));
    final aggregate = ref.watch(partnerAggregateProvider(partnerId));
    final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
    final partners = ref.watch(partnerListProvider);
    final hasOtherPartner = partners.any((p) => p.id != partnerId);

    if (partner == null) {
      return const Scaffold(
        body: Center(child: Text('找不到對象（可能已被合併或刪除）')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: AppColors.onBackgroundPrimary,
        ),
        title: Text(
          partner.name,
          style: const TextStyle(color: AppColors.onBackgroundPrimary),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              color: AppColors.onBackgroundPrimary,
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'merge',
                enabled: hasOtherPartner,
                child: Text(hasOtherPartner ? '合併重複對象' : '合併重複對象（需至少 2 個對象）'),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: Text('編輯對象'),
              ),
              const PopupMenuItem(
                value: 'delete',
                enabled: false,
                child: Text('刪除對象（即將推出）'),
              ),
            ],
            onSelected: (v) {
              if (v == 'merge') context.push('/partner/$partnerId/merge');
              if (v == 'edit') _onEditPartner(context, ref, partner);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _PartnerDetailBackground()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                PartnerHeatHeroCard(heat: aggregate.latestHeat),
                const SizedBox(height: 16),
                PartnerTraitsCard(view: aggregate),
                const SizedBox(height: 12),
                PartnerRadarSummaryCard(
                  latestConversation:
                      conversations.isEmpty ? null : conversations.first,
                ),
                const SizedBox(height: 16),
                if (conversations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '尚未有對話 — 等待第一段互動建立',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary,
                      ),
                    ),
                  )
                else
                  ...conversations.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PartnerConversationTile(
                        conversation: c,
                        onTap: () => context.push('/conversation/${c.id}'),
                        onReassign: () => showConversationReassignPicker(
                          context,
                          conversation: c,
                          ref: ref,
                        ),
                        onDelete: () =>
                            _confirmDeleteConversation(context, ref, c),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          // Keep conversations created from this screen attached to the
          // current Partner, including the manual-entry route.
          builder: (_) => NewConversationSheet(partnerId: partnerId),
        ),
        backgroundColor: AppColors.ctaStart,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: const StadiumBorder(),
        // ADR-15 vocabulary lock — copy stays "+ 新增對話" verbatim
        // (Path A 2026-04-28). Visual is the only thing that changed:
        // pill shape + warm orange + amplified elevation. Subtle warm
        // glow comes from the bottom-left bubble in the backdrop.
        label: const Text(
          '+ 新增對話',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Static dark-navy backdrop with 3 brand-colored glow bubbles.
///
/// Bubbles are intentionally STATIC (no AnimationController). This mirrors
/// `AddPartnerScreen._AddPartnerBackground` for the same reason: animated
/// controllers cause `pumpAndSettle` hangs in widget tests, and detail-screen
/// tests rely on it. The mood is provided by gradient + tinted glows alone.
class _PartnerDetailBackground extends StatelessWidget {
  const _PartnerDetailBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.partnerDetailBgTop,
            AppColors.partnerDetailBgBottom,
          ],
        ),
      ),
      child: IgnorePointer(
        child: Stack(
          children: [
            // Top-right purple halo — sits behind the hero card.
            Positioned(
              top: -60,
              right: -60,
              child: _GlowBubble(
                color: AppColors.primaryLight,
                size: 220,
                opacity: 0.32,
              ),
            ),
            // Bottom-left warm-pink halo — sits near the FAB region.
            Positioned(
              bottom: -40,
              left: -40,
              child: _GlowBubble(
                color: AppColors.ctaStart,
                size: 180,
                opacity: 0.22,
              ),
            ),
            // Mid-right faint pink — ambient warmth between cards.
            Positioned(
              top: 320,
              right: -80,
              child: _GlowBubble(
                color: AppColors.bokehPink,
                size: 140,
                opacity: 0.18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBubble extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;
  const _GlowBubble({
    required this.color,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: opacity),
            blurRadius: 80,
            spreadRadius: 30,
          ),
        ],
      ),
    );
  }
}

Future<void> _onEditPartner(
  BuildContext context,
  WidgetRef ref,
  Partner partner,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(partnerWriteControllerProvider.notifier);
  final newName = await showDialog<String>(
    context: context,
    builder: (_) => PartnerEditDialog(initialName: partner.name),
  );
  if (newName == null) return;
  try {
    await controller.updateName(partner, newName);
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('已更新名稱')));
  } catch (e, st) {
    debugPrint('PartnerDetailScreen edit failed: $e\n$st');
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('更新失敗，請稍後再試')),
    );
  }
}

Future<void> _confirmDeleteConversation(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
) async {
  final dateLabel = DateFormat('MM/dd').format(c.updatedAt);
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(conversationWriteControllerProvider.notifier);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => DeleteConversationConfirmDialog(
      dateLabel: dateLabel,
      messageCount: c.messages.length,
    ),
  );
  if (confirmed != true) return;
  try {
    await controller.delete(c);
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('已刪除這段互動紀錄')),
    );
  } catch (e, st) {
    debugPrint('PartnerDetailScreen conversation delete failed: $e\n$st');
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('刪除失敗，請稍後再試')),
    );
  }
}

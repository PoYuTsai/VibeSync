// lib/features/partner/presentation/screens/partner_detail_screen.dart
//
// Phase 2 Partner detail screen. Replaces the Task 6 stub.
//
// Reads three narrow providers from Phase 1:
//   - partnerByIdProvider(id)            → null when partner deleted/merged
//   - partnerAggregateProvider(id)       → traits / counters
//   - conversationsByPartnerProvider(id) → list of conversations
//
// ⋮ menu: Phase 3 PR-B wires the merge handler. edit / delete remain
// disabled "即將推出" until Phase 4. Merge auto-disables when the user
// has only one partner (no valid target).
//
// + 新增對話 FAB opens the shared `NewConversationSheet` (extracted from
// main_shell.dart in this task). Phase 3 Task 10 wires partnerId into the
// new-conversation flow; Phase 2 still creates conversations without
// partnerId via the legacy path.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../conversation/presentation/widgets/new_conversation_sheet.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_conversation_tile.dart';
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
      appBar: AppBar(
        title: Text(partner.name),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'merge',
                enabled: hasOtherPartner,
                child: Text(hasOtherPartner
                    ? '合併到其他對象'
                    : '合併到其他對象（需至少 2 個對象）'),
              ),
              const PopupMenuItem(
                value: 'edit',
                enabled: false,
                child: Text('編輯對象（即將推出）'),
              ),
              const PopupMenuItem(
                value: 'delete',
                enabled: false,
                child: Text('刪除對象（即將推出）'),
              ),
            ],
            onSelected: (v) {
              if (v == 'merge') context.push('/partner/$partnerId/merge');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PartnerTraitsCard(view: aggregate),
          const SizedBox(height: 12),
          PartnerRadarSummaryCard(
            latestConversation:
                conversations.isEmpty ? null : conversations.first,
          ),
          const SizedBox(height: 16),
          if (conversations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '尚未有對話，從下方「+ 新增對話」開始',
                textAlign: TextAlign.center,
              ),
            )
          else
            ...conversations.map(
              (c) => PartnerConversationTile(
                conversation: c,
                onTap: () => context.push('/conversation/${c.id}'),
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
        label: const Text('+ 新增對話'),
      ),
    );
  }
}

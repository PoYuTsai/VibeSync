// lib/features/partner/presentation/widgets/partner_conversation_tile.dart
//
// Cell rendering a single conversation underneath a Partner detail screen.
// Pure render — receives the Conversation + onTap + optional onReassign.
//
// PR-B Task 5: trailing changed from chevron to ⋮ menu so reassign is
// discoverable. The tile stays pure (no routing / picker) — caller wires
// onReassign with the actual picker + ConversationWriteController flow.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/domain/entities/conversation.dart';

class PartnerConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onReassign;
  final VoidCallback? onDelete;
  const PartnerConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onReassign,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final heat = conversation.lastEnthusiasmScore;
    final dateLabel = DateFormat('MM/dd').format(conversation.updatedAt);
    return ListTile(
      onTap: onTap,
      title: Text('$dateLabel 互動紀錄', style: AppTypography.titleSmall),
      subtitle: Text(
        '${conversation.currentRound} 輪 · ${conversation.messages.length} 則訊息'
        '${heat != null ? ' · 熱度 $heat' : ''}',
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundSecondary,
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) {
          if (v == 'reassign') onReassign?.call();
          if (v == 'delete') onDelete?.call();
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'reassign',
            enabled: onReassign != null,
            child: const Text('改派到其他對象'),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            enabled: onDelete != null,
            child: const Text('刪除對話'),
          ),
        ],
      ),
    );
  }
}

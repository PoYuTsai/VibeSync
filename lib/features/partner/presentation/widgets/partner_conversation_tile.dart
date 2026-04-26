// lib/features/partner/presentation/widgets/partner_conversation_tile.dart
//
// Cell rendering a single conversation underneath a Partner detail screen.
// Pure render — receives the Conversation + onTap callback.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/domain/entities/conversation.dart';

class PartnerConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  const PartnerConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final heat = conversation.lastEnthusiasmScore;
    return ListTile(
      onTap: onTap,
      title: Text(conversation.name, style: AppTypography.titleSmall),
      subtitle: Text(
        '${conversation.currentRound} 輪 · ${conversation.messages.length} 則訊息'
        '${heat != null ? ' · 熱度 $heat' : ''}',
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundSecondary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

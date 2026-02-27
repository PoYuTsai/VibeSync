// lib/features/conversation/presentation/widgets/conversation_tile.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis/domain/entities/enthusiasm_level.dart';
import '../../domain/entities/conversation.dart';
import 'package:intl/intl.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return DateFormat('HH:mm').format(date);
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    }
    return DateFormat('MM/dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final level = conversation.lastEnthusiasmScore != null
        ? EnthusiasmLevel.fromScore(conversation.lastEnthusiasmScore!)
        : null;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceVariant,
        child: Text(
          conversation.name.isNotEmpty ? conversation.name[0] : '?',
          style: AppTypography.titleLarge,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.name,
              style: AppTypography.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatDate(conversation.updatedAt),
            style: AppTypography.caption,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (level != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(level.emoji),
                const SizedBox(width: 4),
                Text(
                  '${conversation.lastEnthusiasmScore}',
                  style: AppTypography.caption.copyWith(color: level.color),
                ),
              ],
            ),
          ],
          if (conversation.lastMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              conversation.lastMessage!.content,
              style: AppTypography.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

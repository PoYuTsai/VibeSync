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
  final VoidCallback? onDelete;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onDelete,
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
      trailing: onDelete != null
          ? IconButton(
              icon: Icon(Icons.delete_outline, color: AppColors.glassTextHint),
              onPressed: onDelete,
              tooltip: '刪除對話',
            )
          : null,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.avatarHerStart, AppColors.avatarHerEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            conversation.name.isNotEmpty ? conversation.name[0] : '?',
            style: AppTypography.titleLarge.copyWith(color: Colors.black87),
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.name,
              style: AppTypography.titleLarge.copyWith(color: AppColors.glassTextPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatDate(conversation.updatedAt),
            style: AppTypography.caption.copyWith(color: AppColors.glassTextHint),
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
              style: AppTypography.caption.copyWith(color: AppColors.glassTextHint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

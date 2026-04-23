// lib/features/conversation/presentation/widgets/message_bubble.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onSwapSide;
  final VoidCallback? onDelete;

  const MessageBubble({
    super.key,
    required this.message,
    this.onSwapSide,
    this.onDelete,
  });

  String? _quotedReplyLabel() {
    final quotedIsFromMe = message.quotedReplyPreviewIsFromMe;
    if (quotedIsFromMe == null) {
      return null;
    }

    return quotedIsFromMe ? '引用我剛剛說的' : '引用對方剛剛說的';
  }

  @override
  Widget build(BuildContext context) {
    final quotedReplyLabel = _quotedReplyLabel();

    final hasActions = onSwapSide != null || onDelete != null;

    return GestureDetector(
      onLongPress: hasActions
          ? () => _showActionMenu(context)
          : null,
      child: Align(
        alignment:
            message.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: message.isFromMe
              ? const LinearGradient(
                  colors: [AppColors.avatarMeStart, AppColors.avatarMeEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: message.isFromMe ? null : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: message.isFromMe ? const Radius.circular(4) : null,
            bottomLeft: !message.isFromMe ? const Radius.circular(4) : null,
          ),
          border: message.isFromMe
              ? null
              : Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.quotedReplyPreview != null &&
                message.quotedReplyPreview!.trim().isNotEmpty) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: message.isFromMe
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: message.isFromMe
                        ? Colors.white.withValues(alpha: 0.18)
                        : AppColors.glassBorder.withValues(alpha: 0.7),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (quotedReplyLabel != null) ...[
                      Text(
                        quotedReplyLabel,
                        style: AppTypography.bodySmall.copyWith(
                          color: message.isFromMe
                              ? Colors.white.withValues(alpha: 0.72)
                              : AppColors.glassTextHint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      message.quotedReplyPreview!,
                      style: AppTypography.bodySmall.copyWith(
                        color: message.isFromMe
                            ? Colors.white.withValues(alpha: 0.85)
                            : AppColors.glassTextHint,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Text(
              message.content,
              style: AppTypography.bodyMedium.copyWith(
                color: message.isFromMe
                    ? Colors.white
                    : AppColors.glassTextPrimary,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showActionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Preview of the message
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                message.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.glassTextSecondary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (onSwapSide != null)
              ListTile(
                leading: Icon(Icons.swap_horiz, color: AppColors.primary),
                title: Text(
                  message.isFromMe ? '改成她說' : '改成我說',
                  style: TextStyle(color: AppColors.glassTextPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onSwapSide!();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.error),
                title: Text(
                  '刪除這則訊息',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete!();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

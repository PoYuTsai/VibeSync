// lib/features/conversation/presentation/widgets/message_bubble.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onSwapSide;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const MessageBubble({
    super.key,
    required this.message,
    this.onSwapSide,
    this.onDelete,
    this.onEdit,
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
    final hasActions = onSwapSide != null || onDelete != null || onEdit != null;
    final isMe = message.isFromMe;
    final fillColor = isMe
        ? AppColors.ctaStart.withValues(alpha: 0.14)
        : AppColors.primaryLight.withValues(alpha: 0.18);
    final borderColor = isMe
        ? AppColors.ctaEnd.withValues(alpha: 0.46)
        : AppColors.primaryLight.withValues(alpha: 0.52);
    final speakerColor = isMe ? AppColors.ctaEnd : AppColors.primaryDark;

    return GestureDetector(
      // opaque：整個 bubble（含 padding / border 邊框 dead zone）都接收
      // long-press。預設 deferToChild 只認 Text 渲染區，user 必須按到「字」
      // 才觸發 — Bruce/Eric 2026-05-23 dogfood 點出這個跟視覺直覺落差。
      behavior: HitTestBehavior.opaque,
      onLongPress: hasActions ? () => _showActionMenu(context) : null,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(14).copyWith(
              bottomRight: isMe ? const Radius.circular(5) : null,
              bottomLeft: !isMe ? const Radius.circular(5) : null,
            ),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isMe ? '我說' : '她說',
                style: AppTypography.bodySmall.copyWith(
                  color: speakerColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (message.quotedReplyPreview != null &&
                  message.quotedReplyPreview!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.glassBorder.withValues(alpha: 0.90),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (quotedReplyLabel != null) ...[
                        Text(
                          quotedReplyLabel,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.glassTextSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        message.quotedReplyPreview!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.glassTextSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                message.content,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  height: 1.4,
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
            if (onEdit != null)
              ListTile(
                leading: Icon(Icons.edit_outlined, color: AppColors.primary),
                title: Text(
                  '編輯文字',
                  style: TextStyle(color: AppColors.glassTextPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onEdit!();
                },
              ),
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

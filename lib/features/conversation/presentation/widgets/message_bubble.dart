// lib/features/conversation/presentation/widgets/message_bubble.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
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
                child: Text(
                  message.quotedReplyPreview!,
                  style: AppTypography.bodySmall.copyWith(
                    color: message.isFromMe
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppColors.glassTextHint,
                    height: 1.35,
                  ),
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
    );
  }
}

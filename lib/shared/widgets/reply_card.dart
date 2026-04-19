// lib/shared/widgets/reply_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

enum ReplyType { extend, resonate, tease, humor, coldRead }

class ReplyCard extends StatelessWidget {
  final ReplyType type;
  final String content;
  final bool isLocked;
  final VoidCallback? onTap;

  const ReplyCard({
    super.key,
    required this.type,
    required this.content,
    this.isLocked = false,
    this.onTap,
  });

  String get _label {
    switch (type) {
      case ReplyType.extend:
        return '🔄 延展・深挖她的回答';
      case ReplyType.resonate:
        return '💬 共鳴・讓她覺得你懂她';
      case ReplyType.tease:
        return '😏 調情・製造曖昧張力';
      case ReplyType.humor:
        return '🎭 幽默・讓她笑著想回';
      case ReplyType.coldRead:
        return '🔮 冷讀・猜中她沒說的';
    }
  }

  Color get _color {
    switch (type) {
      case ReplyType.extend:
        return AppColors.cold;
      case ReplyType.resonate:
        return AppColors.warm;
      case ReplyType.tease:
        return AppColors.veryHot;
      case ReplyType.humor:
        return AppColors.hot;
      case ReplyType.coldRead:
        return AppColors.primaryLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isLocked ? onTap : () => _copyToClipboard(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppTypography.caption.copyWith(color: _color),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isLocked)
                      Icon(Icons.lock, size: 16, color: AppColors.glassTextHint)
                    else
                      Icon(Icons.copy,
                          size: 16, color: AppColors.glassTextHint),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  isLocked ? '升級解鎖完整回覆' : content,
                  style: isLocked
                      ? AppTypography.bodyMedium.copyWith(
                          color: AppColors.glassTextHint,
                          fontStyle: FontStyle.italic,
                        )
                      : AppTypography.bodyLarge.copyWith(
                          color: AppColors.glassTextPrimary,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已複製到剪貼簿'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}

// lib/shared/widgets/bubble_avatar.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 漸層泡泡頭像
class BubbleAvatar extends StatelessWidget {
  final String label;
  final bool isMe;
  final double size;

  const BubbleAvatar({
    super.key,
    required this.label,
    required this.isMe,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isMe
              ? [AppColors.avatarMeStart, AppColors.avatarMeEnd]
              : [AppColors.avatarHerStart, AppColors.avatarHerEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: (isMe ? AppColors.avatarMeEnd : AppColors.avatarHerEnd)
                .withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
            // 「她」黃色背景用深色文字，「我」紫色背景用白色文字
            color: isMe ? Colors.white : const Color(0xFF2D1B4E),
          ),
        ),
      ),
    );
  }
}

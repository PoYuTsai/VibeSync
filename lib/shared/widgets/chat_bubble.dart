import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 分析片段與練習室共用的泡泡外觀；排列、互動與語意由呼叫端負責。
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.isMe,
    required this.child,
    this.tail = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.maxWidth,
  });

  final bool isMe;
  final Widget child;
  final bool tail;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;

  static const _radius = Radius.circular(18);
  // DESIGN.md §4／§7：每組第一顆、貼向說話者的上角。
  static const _tailRadius = Radius.circular(5);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth!),
      padding: padding,
      decoration: BoxDecoration(
        color: isMe ? AppColors.transcriptBubbleMine : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: !isMe && tail ? _tailRadius : _radius,
          topRight: isMe && tail ? _tailRadius : _radius,
          bottomLeft: _radius,
          bottomRight: _radius,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 頭像靠上對齊；同組後續泡泡傳 null 留空位。沒有對象時不包這層。
class ChatAvatarGutter extends StatelessWidget {
  const ChatAvatarGutter({super.key, this.avatar, required this.child});

  static const avatarSize = 30.0;
  static const avatarGap = 8.0;

  final Widget? avatar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar ?? const SizedBox(width: avatarSize),
        const SizedBox(width: avatarGap),
        Flexible(child: child),
      ],
    );
  }
}

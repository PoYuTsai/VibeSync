// lib/shared/widgets/pressable_scale.dart
import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

/// 按壓縮放回饋外殼：包住任何可點元素，按下時縮到 0.97。
///
/// 用 [Listener] 而非 GestureDetector——不進手勢競技場，
/// 所以不會搶走子樹裡 InkWell/GestureDetector 的 onTap。
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? AppMotion.pressedScale : 1.0,
        duration: AppMotion.press,
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}

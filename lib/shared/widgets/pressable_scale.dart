// lib/shared/widgets/pressable_scale.dart
import 'package:flutter/material.dart';

import '../../core/services/app_haptics.dart';
import '../../core/theme/app_motion.dart';

/// 按壓縮放回饋外殼：包住任何可點元素，按下時縮到 0.97。
///
/// 用 [Listener] 而非 GestureDetector——不進手勢競技場，
/// 所以不會搶走子樹裡 InkWell/GestureDetector 的 onTap。
///
/// 觸覺跟著按壓走：
/// - [hapticOnDown] true → 按下瞬間 [AppHaptics.light]，給主按鈕的實心感。
/// - false（預設）→ 放開且未被捲動取消時 [AppHaptics.tap]，
///   捲動清單裡的項目不會因為手指碰到就震。
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.hapticOnDown = false,
  });

  final Widget child;
  final bool enabled;
  final bool hapticOnDown;

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
      onPointerDown: (_) {
        if (widget.enabled && widget.hapticOnDown) AppHaptics.light();
        _setPressed(true);
      },
      onPointerUp: (_) {
        // _pressed 仍為 true 代表沒被捲動 cancel 掉，是真的點擊。
        if (_pressed && !widget.hapticOnDown) AppHaptics.tap();
        _setPressed(false);
      },
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? AppMotion.pressedScale : 1.0,
        duration: _pressed ? AppMotion.pressDown : AppMotion.pressUp,
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}

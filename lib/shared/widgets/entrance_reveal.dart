// lib/shared/widgets/entrance_reveal.dart
import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

/// 內容進場橋接：掛載時播一次 fade（可選 translateY／scale），
/// 讓條件渲染的內容不再瞬間彈出。
///
/// 換 key 重掛載會重播；系統開啟 reduced motion 時直接跳到終態。
class EntranceReveal extends StatefulWidget {
  const EntranceReveal({
    super.key,
    required this.child,
    this.duration = AppMotion.enter,
    this.curve = AppMotion.easeOut,
    this.opacityCurve,
    this.offsetY = 14,
    this.beginScale = 0.98,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;

  /// 淡入專用曲線；null 時跟 [curve]。easeOutBack 這類過衝曲線
  /// 會讓 opacity 提前夾到 1、吃掉淡入尾段，慶祝檔要分開給。
  final Curve? opacityCurve;

  /// 進場起始向下位移（邏輯像素），0 = 純 fade。
  final double offsetY;

  /// 進場起始縮放，1 = 不縮放。
  final double beginScale;

  @override
  State<EntranceReveal> createState() => _EntranceRevealState();
}

class _EntranceRevealState extends State<EntranceReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion || !TickerMode.valuesOf(context).enabled) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = widget.curve.transform(_controller.value);
        final ot =
            (widget.opacityCurve ?? widget.curve).transform(_controller.value);
        // easeOutBack 這類曲線會超過 1，opacity 必須夾住。
        final opacity = ot.clamp(0.0, 1.0);
        Widget result = Opacity(opacity: opacity, child: child);
        if (widget.beginScale != 1) {
          result = Transform.scale(
            scale: widget.beginScale + (1 - widget.beginScale) * t,
            child: result,
          );
        }
        if (widget.offsetY != 0) {
          result = Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - t)),
            child: result,
          );
        }
        return result;
      },
    );
  }
}

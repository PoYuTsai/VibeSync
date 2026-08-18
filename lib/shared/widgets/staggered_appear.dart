import 'package:flutter/material.dart';

/// 完成揭示的錯開彈入（2026-08-19 v2 精修）：沿用 analyze-chat 回覆卡的
/// 進場語彙——每張延遲 [stepDelay]×index，fade＋scale 0.96→1 easeOutBack。
/// 用單一 controller＋Interval 實作延遲（不用 Timer，widget test 免 pending
/// timer）。尊重系統減少動態（disableAnimations 時直接顯示）。一次性進場，
/// 換新內容用不同 key 重建即可重播。
class StaggeredAppear extends StatefulWidget {
  const StaggeredAppear({
    super.key,
    required this.index,
    required this.child,
    this.stepDelay = const Duration(milliseconds: 60),
    this.duration = const Duration(milliseconds: 240),
  });

  final int index;
  final Widget child;
  final Duration stepDelay;
  final Duration duration;

  @override
  State<StaggeredAppear> createState() => _StaggeredAppearState();
}

class _StaggeredAppearState extends State<StaggeredAppear>
    with SingleTickerProviderStateMixin {
  late final Duration _total =
      widget.stepDelay * widget.index + widget.duration;
  late final double _delayFraction = _total.inMilliseconds == 0
      ? 0
      : (widget.stepDelay * widget.index).inMilliseconds /
          _total.inMilliseconds;
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _total)..forward();
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Interval(_delayFraction, 1, curve: Curves.easeOut),
  );
  late final Animation<double> _scale = Tween<double>(begin: 0.96, end: 1)
      .animate(CurvedAnimation(
    parent: _controller,
    curve: Interval(_delayFraction, 1, curve: Curves.easeOutBack),
  ));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

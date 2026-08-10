import 'package:flutter/material.dart';

/// 「← 左右滑動」提示的一次性動態提醒（2026-08-10 Eric 指定：套用 OCR
/// 滑動教學的節奏）。進場停 650ms 後右去右回、頓一下、左去左回各一趟，
/// 播完停回原位不重複；reduced motion 直接維持靜態。
///
/// 延遲刻意烘進 TweenSequence 首段而不用 Timer——卸載型 widget 測試
/// 會被 pending Timer 炸掉（bug-log 舊坑），純 controller 沒這問題。
class SwipeHintNudge extends StatefulWidget {
  const SwipeHintNudge({super.key, required this.child});

  final Widget child;

  @override
  State<SwipeHintNudge> createState() => _SwipeHintNudgeState();
}

class _SwipeHintNudgeState extends State<SwipeHintNudge>
    with SingleTickerProviderStateMixin {
  /// 提示字是 caption 級，位移比 OCR 教學泡泡（28px）收斂到 8px。
  static const double _shift = 8;

  late final AnimationController _controller;
  late final Animation<double> _offsetX;
  bool _playScheduled = false;

  @override
  void initState() {
    super.initState();
    // 650ms 進場延遲＋1800ms 動作＝2450ms 總長，首段 ConstantTween 當延遲。
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2450),
    );
    _offsetX = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 65),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: _shift)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 33,
      ),
      TweenSequenceItem(tween: ConstantTween(_shift), weight: 12),
      TweenSequenceItem(
        tween: Tween(begin: _shift, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 33,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 12),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -_shift)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 33,
      ),
      TweenSequenceItem(tween: ConstantTween(-_shift), weight: 12),
      TweenSequenceItem(
        tween: Tween(begin: -_shift, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 33,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 12),
    ]).animate(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_playScheduled) return;
    _playScheduled = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offsetX,
      builder: (context, child) => Transform.translate(
        offset: Offset(_offsetX.value, 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}

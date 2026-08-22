// lib/shared/widgets/motion/count_up_text.dart
//
// 數字揭曉：從 0 快速跑到目標值。
//
// 等價於 GSAP 的計數器慣用寫法——
//   gsap.to(obj, { val: 36, duration: 1.2, ease: 'power2.out', snap: { val: 1 } })
// `snap: { val: 1 }` 就是這裡的 `value.round()`：畫面上永遠是整數，不會出現
// 36.4183 這種中間態。
//
// 紀律：
// - one-shot，無無限 ticker，`pumpAndSettle` 必收斂。
// - 關動畫（reduce motion／TickerMode 靜音）直接落在終點，不做半套。
// - 不碰文字透明度（全 App 殘影禁令）——只換字，不淡入。
// - 數字用 tabular figures，跑動時不會每格抖一次寬度。
import 'package:flutter/widgets.dart';

import '../../../core/animation/gsap_ease.dart';
import '../../../core/animation/motion_preference.dart';
import '../../../core/services/app_haptics.dart';
import '../../../core/theme/app_motion.dart';

class CountUpText extends StatefulWidget {
  const CountUpText({
    super.key,
    required this.value,
    this.style,
    this.textAlign,
    this.duration = AppMotion.countUp,
    this.curve = GsapEase.power2Out,
    this.haptic = true,
    this.animate = true,
    this.onEnd,
  });

  /// 目標數字。中途變更會從當下值重新補間（GSAP 的 retarget 行為）。
  final int value;

  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration duration;
  final Curve curve;

  /// 每跳一格給一次節流過的細碎觸覺（[AppHaptics.tick] 自帶 70ms 節流）。
  final bool haptic;

  /// false＝跳過跑動直接顯示終值。給「已經播過一次、不該因為 widget 被
  /// 回收重建就重播」的情境用（lazy ListView 捲出 cacheExtent 會回收）。
  final bool animate;

  /// 數字跑完時呼叫一次；關動畫（duration 0）也算跑完。[animate] false 的
  /// 起點就是終點，沒有東西可跑，這時不會回呼。
  final VoidCallback? onEnd;

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText> {
  int _lastShown = 0;

  /// 第一次 builder 回呼還沒發生前不出聲：`animate: false` 的第一格直接就是
  /// 終值，那不是「跳了一格」，不該給觸覺。
  bool _primed = false;

  @override
  Widget build(BuildContext context) {
    final still = motionDisabled(context);
    final target = widget.value.toDouble();
    // 不跑開場時把起點壓在終點上：TweenAnimationBuilder 看到 begin == end 就
    // 不會 forward，畫面直接是終值。之後 value 真的變了照樣會補間過去——
    // 「這次不播開場」不等於「這張卡從此不准動」。
    final begin = widget.animate ? 0.0 : target;
    final style = (widget.style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: begin, end: target),
      duration: still ? Duration.zero : widget.duration,
      curve: widget.curve,
      onEnd: widget.onEnd,
      builder: (context, value, _) {
        final shown = value.round();
        if (shown != _lastShown) {
          _lastShown = shown;
          if (_primed && widget.haptic && !still) AppHaptics.tick();
        }
        _primed = true;
        return Text('$shown', style: style, textAlign: widget.textAlign);
      },
    );
  }
}

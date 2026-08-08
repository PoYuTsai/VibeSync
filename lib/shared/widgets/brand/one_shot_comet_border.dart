import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 一次性「金色彗星掃邊」：當 [trigger] 換成新的非 null 值時，沿子元件的
/// 圓角矩形邊框掃「一圈」金色彗星光（亮金頭、暖橘拖尾、少量金火花）後淡出。
///
/// 設計約束（paywall 選卡慶祝場景）：
/// - 一次性、非常駐：播完自動收掉，不留任何殘光，也沒有無限 ticker。
/// - 首幀不播：initState 當下的 [trigger] 值不觸發，只有之後「變成新值」才播；
///   [trigger] 為 null 時永不播（並立刻收掉播到一半的殘光）。
/// - reduced motion／TickerMode 關閉時直接不播（守門手法同 LiquidMotionFrame）。
/// - 只畫邊框描邊 overlay，絕不覆蓋、淡化子元件內容（殘影禁令）。
class OneShotCometBorder extends StatefulWidget {
  const OneShotCometBorder({
    super.key,
    required this.child,
    required this.trigger,
    this.borderRadius = 24,
    this.duration = const Duration(milliseconds: 1050),
  }) : assert(borderRadius >= 0);

  final Widget child;

  /// 播放訊號：null＝不播；由 null→值、或值→不同值時播一次。
  /// 首次建立（initState）當下的值不會觸發。
  final int? trigger;

  /// 對齊子卡片的圓角半徑。
  final double borderRadius;

  /// 掃一圈＋淡出的總時長。
  final Duration duration;

  @override
  State<OneShotCometBorder> createState() => _OneShotCometBorderState();
}

class _OneShotCometBorderState extends State<OneShotCometBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool get _motionEnabled {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return TickerMode.valuesOf(context).enabled && !reduceMotion;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 播到一半途中系統切成 reduced motion / TickerMode 關閉：立刻收掉。
    if (!_motionEnabled && _controller.value != 0) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant OneShotCometBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.trigger != null && widget.trigger != oldWidget.trigger) {
      _playOnce();
    } else if (widget.trigger == null && _controller.value != 0) {
      // 取消選取：立刻收掉，不留殘光。
      _controller
        ..stop()
        ..value = 0;
    }
  }

  void _playOnce() {
    // reduced motion / TickerMode 關閉：整段效果直接不出現（不播、不留靜態光）。
    if (!_motionEnabled) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  // 靜止（未播或播完）時整層拿掉，確保零殘光零繪製成本。
                  if (!_controller.isAnimating && (t <= 0 || t >= 1)) {
                    return const SizedBox.shrink();
                  }
                  return CustomPaint(
                    painter: OneShotCometBorderPainter(
                      progress: t,
                      borderRadius: widget.borderRadius,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 金色彗星掃邊 painter：確定性（零 Random），progress 0→1 對應
/// 「掃完一圈＋整體淡出」。手法承襲 practice_draw_ceremony 的
/// _EnergyBorderPainter（path metrics 取樣畫拖尾圓點），配色改走品牌暖金
/// （亮核暖白 → 金 bokehYellow → 焰橘 ctaStart 拖尾）。
@visibleForTesting
class OneShotCometBorderPainter extends CustomPainter {
  OneShotCometBorderPainter({
    required this.progress,
    required this.borderRadius,
  });

  /// 0..1：整段動畫進度（含尾端淡出）。
  final double progress;
  final double borderRadius;

  // 品牌暖金三階：亮核暖白／金頭／焰橘拖尾（拖尾再淡到透明）。
  static const Color _coreWhite = Color(0xFFFFF1E4);
  static const Color _gold = AppColors.bokehYellow;
  static const Color _flame = AppColors.ctaStart;

  static const double _goldenAngle = 2.399963229728653; // 黃金角（弧度）
  static const int _sparkCount = 6;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // 淡入 10% → 全亮 → 尾端 25% 淡出；頭尾都是 0，靜止幀必為全透明。
    final fadeIn = Curves.easeOut.transform((progress / 0.10).clamp(0.0, 1.0));
    final fadeOut =
        1 - Curves.easeIn.transform(((progress - 0.75) / 0.25).clamp(0.0, 1.0));
    final intensity = (fadeIn * fadeOut).clamp(0.0, 1.0);
    if (intensity <= 0.01) return;

    // 掃行進度用 easeInOut：起步蓄勢、中段加速、收尾減速，剛好繞一圈。
    final travel = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));

    final rect = (Offset.zero & size).deflate(1);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        rect,
        Radius.circular(math.max(0, borderRadius - 1)),
      ));

    final comet = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (final metric in path.computeMetrics()) {
      final len = metric.length;
      final head = (travel * len) % len;
      final tailLen = len * 0.28; // 拖尾約占周長 28%
      const steps = 22;

      // 拖尾：焰橘 → 金，越近頭越亮越粗。
      for (var s = 0; s < steps; s++) {
        final frac = s / (steps - 1); // 0=拖尾末端 .. 1=head
        final offset = (head - tailLen * (1 - frac)) % len;
        final tan =
            metric.getTangentForOffset(offset < 0 ? offset + len : offset);
        if (tan == null) continue;
        comet.color = Color.lerp(_flame, _gold, frac)!.withValues(
          alpha: ((0.08 + 0.62 * frac * frac) * intensity).clamp(0.0, 1.0),
        );
        canvas.drawCircle(tan.position, 1.4 + 2.4 * frac, comet);
      }

      // 頭部亮核：外圈金暈＋內核暖白，給「彗星」的一點鋒芒。
      final headTan = metric.getTangentForOffset(head);
      if (headTan != null) {
        canvas.drawCircle(
          headTan.position,
          6.5,
          Paint()
            ..color = _gold.withValues(alpha: 0.55 * intensity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
          headTan.position,
          2.6,
          Paint()..color = _coreWhite.withValues(alpha: 0.95 * intensity),
        );
      }

      // 少量金火花：golden-angle 確定性佈點，貼著拖尾往外飄一點點就淡掉，
      // 刻意收斂不搶 CTA。
      final spark = Paint()..style = PaintingStyle.fill;
      for (var k = 0; k < _sparkCount; k++) {
        final a = (k * _goldenAngle) % (2 * math.pi);
        final backFrac = 0.15 + 0.7 * (k / _sparkCount); // 落在拖尾中後段
        final offset = (head - tailLen * backFrac) % len;
        final tan =
            metric.getTangentForOffset(offset < 0 ? offset + len : offset);
        if (tan == null) continue;
        // 沿法線往外飄，飄越遠越淡。
        final normal = Offset(-tan.vector.dy, tan.vector.dx);
        final drift = 3 + 5 * ((math.sin(a) + 1) / 2);
        final fade = (1 - backFrac) * intensity;
        spark.color = _gold.withValues(alpha: (0.5 * fade).clamp(0.0, 1.0));
        canvas.drawCircle(
          tan.position + normal * drift,
          0.9 + 0.9 * fade,
          spark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(OneShotCometBorderPainter old) =>
      old.progress != progress || old.borderRadius != borderRadius;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 一次性「玻璃反光橫掃」覆層：一道斜向的玻璃反光帶，從卡片左側掃到右側
/// 一次（約 0.8 秒）就消失，之後不再重播。
///
/// 視覺語彙借自練習室抽卡儀式的 `_GlassWipePainter`（斜角光帶＋圓角裁切），
/// 但獨立成可重用元件：包住任何圓角卡片，掛載（State 建立）當下播一次。
/// 一般 rebuild 不會重播——只有 State 重新掛載（例如條件渲染重新出現）才會。
///
/// 動畫紀律：
/// - 遵守 [MediaQuery.disableAnimations] 與 [TickerMode]：關閉動畫時直接跳到
///   終點（光帶已離場＝什麼都不畫），與 LiquidMotionFrame 同一套 guard。
/// - 純 one-shot，無無限 ticker，`pumpAndSettle` 必收斂。
/// - 只用 CustomPaint 疊加光帶，絕不動文字透明度（全 App 殘影禁令）。
class OneShotGlassWipe extends StatefulWidget {
  const OneShotGlassWipe({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.duration = const Duration(milliseconds: 800),
    this.intensity = 1,
  })  : assert(borderRadius >= 0),
        assert(intensity >= 0 && intensity <= 1);

  final Widget child;

  /// 裁切光帶用的圓角，要跟被包住的卡片圓角一致。
  final double borderRadius;
  final Duration duration;

  /// 0–1 整體亮度縮放。
  final double intensity;

  @override
  State<OneShotGlassWipe> createState() => _OneShotGlassWipeState();
}

class _OneShotGlassWipeState extends State<OneShotGlassWipe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  /// 是否已決定過要不要播（State 一生只決定一次，不因 rebuild 重播）。
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = TickerMode.valuesOf(context).enabled && !reduceMotion;

    if (!_decided) {
      _decided = true;
      if (enabled) {
        _controller.forward();
      } else {
        // 關閉動畫：直接停在終點，光帶已離場、不留殘影。
        _controller.value = 1;
      }
      return;
    }

    // 播到一半動畫被關掉（reduced motion / TickerMode 切換）→ 跳到終點。
    if (!enabled && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.intensity == 0) return widget.child;

    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _OneShotGlassWipePainter(
                      progress: _progress.value,
                      borderRadius: widget.borderRadius,
                      intensity: widget.intensity,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OneShotGlassWipePainter extends CustomPainter {
  const _OneShotGlassWipePainter({
    required this.progress,
    required this.borderRadius,
    required this.intensity,
  });

  final double progress;
  final double borderRadius;
  final double intensity;

  // 光帶斜角（弧度）：與抽卡儀式的玻璃反光同一傾斜語彙。
  static const double _tilt = -0.42;

  @override
  void paint(Canvas canvas, Size size) {
    // 起點（0）光帶還在左外側、終點（1）已完全掃出右外側：都不必畫。
    if (size.isEmpty || progress <= 0 || progress >= 1) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(borderRadius),
    );

    canvas
      ..save()
      ..clipRRect(rrect);

    final center = rect.center;
    canvas
      ..translate(center.dx, center.dy)
      ..rotate(_tilt);

    final w = size.width;
    // 位移範圍抓寬一點（±1.1w），確保斜角下頭尾兩端都完全離場。
    final sweepX = -w * 1.1 + w * 2.2 * progress;
    final bandRect = Rect.fromCenter(
      center: Offset(sweepX, 0),
      width: w * 0.46,
      // 斜角旋轉後仍要蓋滿卡片高度。
      height: math.max(size.height, w) * 2.2,
    );

    final band = Paint()
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.14 * intensity),
          Colors.white.withValues(alpha: 0.40 * intensity),
          AppColors.bokehYellow.withValues(alpha: 0.16 * intensity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.32, 0.50, 0.68, 1.0],
      ).createShader(bandRect);
    canvas
      ..drawRect(bandRect, band)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _OneShotGlassWipePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.intensity != intensity;
  }
}

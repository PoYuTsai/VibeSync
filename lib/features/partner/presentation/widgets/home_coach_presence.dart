import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';

/// 每個姿勢圖的畫布與「人物邊界框」量測值（alpha>8 的不透明像素範圍，
/// 2026-08-09 以 sydney_bbox_probe 實測）。四張圖人物都貼齊畫布底邊，但
/// 畫布規格與人物佔比、水平中心都不一致——不帶量測值直接同高渲染，換姿勢
/// 時 Sydney 會忽大忽小、忽左忽右（Eric 真機回報）。
enum HomeCoachPose {
  // canvas 1023×1537，人物 box=[116,185..963,1536]
  greeting(
    'assets/images/coach/sydney_greeting.png',
    aspectRatio: 1023 / 1537,
    figureHeightFraction: 1352 / 1537,
    figureCenterX: 0.5274,
  ),
  // canvas 941×1672，人物 box=[126,148..883,1671]
  thinking(
    'assets/images/coach/sydney_thinking.png',
    aspectRatio: 941 / 1672,
    figureHeightFraction: 1524 / 1672,
    figureCenterX: 0.5361,
  ),
  // canvas 1023×1537，人物 box=[121,182..1000,1536]
  tip(
    'assets/images/coach/sydney_tip.png',
    aspectRatio: 1023 / 1537,
    figureHeightFraction: 1355 / 1537,
    figureCenterX: 0.5479,
  ),
  // canvas 1122×1402，人物 box=[201,88..958,1401]
  encouragement(
    'assets/images/coach/sydney_encouragement.png',
    aspectRatio: 1122 / 1402,
    figureHeightFraction: 1314 / 1402,
    figureCenterX: 0.5165,
  );

  const HomeCoachPose(
    this.assetPath, {
    required this.aspectRatio,
    required this.figureHeightFraction,
    required this.figureCenterX,
  });

  final String assetPath;

  /// 圖檔畫布寬高比（w/h）。
  final double aspectRatio;

  /// 人物實際高度佔畫布高的比例（人物皆貼齊底邊）。
  final double figureHeightFraction;

  /// 人物水平中心在畫布寬的相對位置（0..1）。
  final double figureCenterX;

  HomeCoachPose differentPose(Random random) {
    final step = 1 + random.nextInt(values.length - 1);
    return values[(index + step) % values.length];
  }
}

/// 首頁 Sydney。2026-08-09 拍板：以「雙手張開」（greeting）為基準，任何
/// 姿勢都維持固定位置與觀感大小——人物顯示高度一致、人物中心水平置中、
/// 底邊錨定；正規化倍率皆 ≤1（基準姿勢的人物佔比最小），身版不會被切。
class HomeCoachPresence extends StatelessWidget {
  const HomeCoachPresence({
    super.key,
    required this.pose,
    this.height,
  });

  final HomeCoachPose pose;
  final double? height;

  static const HomeCoachPose _baseline = HomeCoachPose.greeting;

  /// 正規化後最寬的渲染寬（相對畫布高的倍率），保留水平空間用。
  static final double _maxNormalizedWidthFactor = HomeCoachPose.values
      .map(
        (p) =>
            p.aspectRatio *
            _baseline.figureHeightFraction /
            p.figureHeightFraction,
      )
      .reduce(max);

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final resolvedHeight =
        height ?? (viewportHeight * 0.55).clamp(420.0, 480.0);
    final availableWidth = max(0.0, viewportWidth - 32);
    final canvasHeight = min(
      resolvedHeight,
      availableWidth / _maxNormalizedWidthFactor,
    );

    // 人物同高：把各姿勢的人物高縮放到與基準姿勢一致。
    final renderHeight = canvasHeight *
        _baseline.figureHeightFraction /
        pose.figureHeightFraction;
    final renderWidth = renderHeight * pose.aspectRatio;
    // 人物置中：把「人物中心」而非「畫布中心」對到頁面中線。
    final dx = (0.5 - pose.figureCenterX) * renderWidth;

    return SizedBox(
      height: resolvedHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        // 換姿勢用 crossfade 不瞬跳。包整個含幾何的子樹（各姿勢寬高/位移不同，
        // 只包 Image 會讓舊圖在淡出時被新幾何拉伸），底邊錨定對齊。
        child: AnimatedSwitcher(
          duration: AppMotion.enter,
          switchInCurve: AppMotion.easeOut,
          switchOutCurve: AppMotion.easeOut,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.bottomCenter,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          child: Transform.translate(
            key: ValueKey(pose),
            offset: Offset(dx, 0),
            child: SizedBox(
              width: renderWidth,
              height: renderHeight,
              child: Semantics(
                image: true,
                label: 'VibeSync Coach Sydney，欣欣',
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0, 0.1, 0.92, 1],
                  ).createShader(bounds),
                  child: Image.asset(
                    pose.assetPath,
                    key: ValueKey('home-coach-pose-${pose.name}'),
                    width: renderWidth,
                    height: renderHeight,
                    fit: BoxFit.fitHeight,
                    alignment: Alignment.bottomCenter,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

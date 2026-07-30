import 'dart:math';

import 'package:flutter/material.dart';

enum HomeCoachPose {
  greeting('assets/images/coach/sydney_greeting.png'),
  thinking('assets/images/coach/sydney_thinking.png'),
  tip('assets/images/coach/sydney_tip.png'),
  encouragement('assets/images/coach/sydney_encouragement.png');

  const HomeCoachPose(this.assetPath);

  final String assetPath;

  HomeCoachPose differentPose(Random random) {
    final step = 1 + random.nextInt(values.length - 1);
    return values[(index + step) % values.length];
  }
}

class HomeCoachPresence extends StatelessWidget {
  const HomeCoachPresence({
    super.key,
    required this.pose,
    this.height,
  });

  final HomeCoachPose pose;
  final double? height;

  // The encouragement pose has the widest source canvas (1122 × 1402).
  // Reserve enough horizontal room for it, then render every pose at the same
  // canvas height so switching gestures never changes Sydney's visual scale.
  static const _widestPoseAspectRatio = 1122 / 1402;

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final resolvedHeight =
        height ?? (viewportHeight * 0.55).clamp(420.0, 480.0);
    final availableWidth = max(0.0, viewportWidth - 32);
    final canvasHeight = min(
      resolvedHeight,
      availableWidth / _widestPoseAspectRatio,
    );
    final canvasWidth = canvasHeight * _widestPoseAspectRatio;

    return SizedBox(
      height: resolvedHeight,
      child: Align(
        alignment: Alignment.bottomRight,
        child: SizedBox(
          width: canvasWidth,
          height: canvasHeight,
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
                width: canvasWidth,
                height: canvasHeight,
                fit: BoxFit.fitHeight,
                alignment: Alignment.bottomRight,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

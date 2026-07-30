import 'package:flutter/material.dart';

enum HomeCoachPose {
  greeting('assets/images/coach/sydney_greeting.jpg'),
  thinking('assets/images/coach/sydney_thinking.jpg'),
  tip('assets/images/coach/sydney_tip.jpg'),
  encouragement('assets/images/coach/sydney_encouragement.jpg');

  const HomeCoachPose(this.assetPath);

  final String assetPath;
}

class HomeCoachPresence extends StatelessWidget {
  const HomeCoachPresence({
    super.key,
    required this.pose,
    this.height,
  });

  final HomeCoachPose pose;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final resolvedHeight =
        height ?? (viewportHeight * 0.55).clamp(420.0, 480.0);

    return SizedBox(
      height: resolvedHeight,
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
            width: double.infinity,
            height: resolvedHeight,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.1),
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}

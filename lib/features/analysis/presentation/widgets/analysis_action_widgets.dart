import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Resolves the single floating surface used by the analysis screen.
///
/// The in-progress hint must win over the idle CTA. Long pending fragments
/// still satisfy the CTA's visibility rules after analysis starts, so letting
/// the caller order these conditions can leave the disabled CTA covering the
/// scroll hint for the entire stream.
Widget? buildAnalysisFloatingOverlay({
  required bool showStartAction,
  required bool isAnalyzing,
  required bool analysisCompleted,
  required VoidCallback? onStart,
}) {
  if (isAnalyzing && !analysisCompleted) {
    return const AnalysisScrollHint();
  }
  if (showStartAction) {
    return FloatingAnalysisActionButton(onPressed: onStart);
  }
  return null;
}

/// Keeps the primary analyze action reachable while the user reviews a long
/// conversation preview.
///
/// The extended pill is deliberate: a circle works for a familiar icon, but
/// 「開始分析」is a decision and needs a readable label. The button floats over
/// the scroll viewport, so the user does not have to hunt for the action after
/// checking a long imported conversation.
class FloatingAnalysisActionButton extends StatelessWidget {
  static const buttonKey = ValueKey('floating-analysis-action');

  final VoidCallback? onPressed;

  const FloatingAnalysisActionButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(
          alignment: Alignment.bottomRight,
          scale: 0.92 + (0.08 * value),
          child: child,
        ),
      ),
      child: Semantics(
        button: true,
        label: '使用目前對話開始分析',
        child: ExcludeSemantics(
          child: FilledButton.icon(
            key: buttonKey,
            onPressed: onPressed,
            icon: const Icon(Icons.auto_awesome_rounded, size: 19),
            label: Text(
              '開始分析',
              style: AppTypography.titleSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(132, 52),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              backgroundColor: AppColors.ctaStart,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AppColors.ctaStart.withValues(alpha: 0.46),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.72),
              elevation: 9,
              shadowColor: Colors.black.withValues(alpha: 0.38),
              shape: StadiumBorder(
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short, non-interactive cue that tells users where streamed analysis
/// content will appear after they start a long conversation analysis.
class AnalysisScrollHint extends StatefulWidget {
  static const hintKey = ValueKey('analysis-scroll-hint');
  static const defaultDuration = Duration(milliseconds: 2100);

  final Duration duration;

  const AnalysisScrollHint({
    super.key,
    this.duration = defaultDuration,
  });

  @override
  State<AnalysisScrollHint> createState() => _AnalysisScrollHintState();
}

class _AnalysisScrollHintState extends State<AnalysisScrollHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _reducedMotionTimer;
  bool _started = false;
  bool _visible = true;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0),
        weight: 25,
      ),
    ]).animate(_controller);
    _offset = Tween<Offset>(
      begin: const Offset(0, -0.12),
      end: const Offset(0, 0.18),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _hide();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _reducedMotionTimer = Timer(widget.duration, _hide);
    } else {
      _controller.forward();
    }
  }

  void _hide() {
    if (!mounted || !_visible) return;
    setState(() => _visible = false);
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final hint = Semantics(
      liveRegion: true,
      excludeSemantics: true,
      label: '分析內容會在下方陸續出現，請往下滑',
      child: IgnorePointer(
        child: Container(
          key: AnalysisScrollHint.hintKey,
          width: 72,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.brandInk.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.ctaStart.withValues(alpha: 0.62),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.keyboard_double_arrow_down_rounded,
                size: 22,
                color: AppColors.ctaStart,
              ),
              const SizedBox(height: 2),
              Text(
                '往下滑',
                maxLines: 1,
                style: AppTypography.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (_reduceMotion) return hint;
    return SlideTransition(
      position: _offset,
      child: FadeTransition(
        opacity: _opacity,
        alwaysIncludeSemantics: true,
        child: hint,
      ),
    );
  }
}

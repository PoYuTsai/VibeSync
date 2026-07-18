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
  required VoidCallback? onFollowProgress,
  bool isFollowing = false,
  bool streamInterrupted = false,
}) {
  if ((isAnalyzing && !analysisCompleted) || streamInterrupted) {
    return AnalysisScrollHint(
      onPressed: onFollowProgress,
      isFollowing: isFollowing,
      interrupted: streamInterrupted,
    );
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

/// Persistent progress navigation for a streamed analysis.
///
/// This is an action rather than a toast: it stays available until the stream
/// ends, jumps to the latest rendered section, and reports whether live follow
/// mode is active. If the stream stops after partial content, the same surface
/// leads to the preserved content and retry card.
class AnalysisScrollHint extends StatefulWidget {
  static const hintKey = ValueKey('analysis-scroll-hint');

  final VoidCallback? onPressed;
  final bool isFollowing;
  final bool interrupted;

  const AnalysisScrollHint({
    super.key,
    this.onPressed,
    this.isFollowing = false,
    this.interrupted = false,
  });

  @override
  State<AnalysisScrollHint> createState() => _AnalysisScrollHintState();
}

class _AnalysisScrollHintState extends State<AnalysisScrollHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: const Offset(0, 0.12),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _reduceMotion = reduceMotion;
    _syncAnimationState();
  }

  @override
  void didUpdateWidget(covariant AnalysisScrollHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interrupted != widget.interrupted) {
      _syncAnimationState();
    }
  }

  void _syncAnimationState() {
    if (_reduceMotion || widget.interrupted) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.interrupted
        ? '查看中斷'
        : widget.isFollowing
            ? '跟隨進度'
            : '跟到最新';
    final semanticsLabel =
        widget.interrupted ? '分析中斷，點一下查看保留內容與重試選項' : '分析內容會在下方陸續出現，點一下跟到最新進度';
    final accent = widget.interrupted ? AppColors.warning : AppColors.ctaStart;
    final icon = widget.interrupted
        ? Icons.error_outline_rounded
        : Icons.keyboard_double_arrow_down_rounded;
    final animatedIcon = Icon(icon, size: 21, color: accent);

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: FilledButton.icon(
          key: AnalysisScrollHint.hintKey,
          onPressed: widget.onPressed,
          icon: _reduceMotion || widget.interrupted
              ? animatedIcon
              : SlideTransition(position: _offset, child: animatedIcon),
          label: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              label,
              key: ValueKey(label),
              maxLines: 1,
              style: AppTypography.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size(124, 50),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            backgroundColor: AppColors.brandInk.withValues(alpha: 0.96),
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.brandInk.withValues(alpha: 0.82),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.72),
            elevation: 9,
            shadowColor: Colors.black.withValues(alpha: 0.38),
            shape: StadiumBorder(
              side: BorderSide(
                color: accent.withValues(alpha: 0.62),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

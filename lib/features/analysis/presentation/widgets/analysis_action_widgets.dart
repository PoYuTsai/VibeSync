import 'dart:math' as math;

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

/// Pins the analysis shortcut to the vertical center of the visible body.
///
/// Scaffold's default `endFloat` location is bottom-right. That makes a
/// persistent shortcut look like a second bottom CTA and lets it drift away
/// from the messages the user is reviewing. This location uses the actual
/// content bounds, including keyboard and bottom-sheet insets, so the action
/// stays centered in the currently visible viewport.
class AnalysisSideCenterFabLocation extends FloatingActionButtonLocation {
  const AnalysisSideCenterFabLocation({this.edgeInset = 12});

  final double edgeInset;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final scaffoldSize = scaffoldGeometry.scaffoldSize;
    final actionSize = scaffoldGeometry.floatingActionButtonSize;
    final visibleTop = scaffoldGeometry.contentTop;
    final keyboardTop = scaffoldSize.height - scaffoldGeometry.minInsets.bottom;
    final visibleBottom = math.max(
      visibleTop,
      math.min(scaffoldGeometry.contentBottom, keyboardTop),
    );
    final availableHeight = math.max(0.0, visibleBottom - visibleTop);
    final x = math.max(
      0.0,
      scaffoldSize.width - actionSize.width - edgeInset,
    );
    final y =
        visibleTop + math.max(0.0, availableHeight - actionSize.height) / 2;

    return Offset(x, y);
  }
}

/// Keeps the primary analyze action reachable while the user reviews a long
/// conversation preview.
///
/// This compact analysis orb is a shortcut, not a second full-width CTA.
///
/// The dark core keeps the warm orange as a signal instead of a large flat
/// fill. A single entrance scan establishes affordance without leaving a
/// distracting ticker running over the conversation.
class FloatingAnalysisActionButton extends StatefulWidget {
  static const buttonKey = ValueKey('floating-analysis-action');
  static const orbKey = ValueKey('floating-analysis-orb');

  final VoidCallback? onPressed;

  const FloatingAnalysisActionButton({
    super.key,
    required this.onPressed,
  });

  @override
  State<FloatingAnalysisActionButton> createState() =>
      _FloatingAnalysisActionButtonState();
}

class _FloatingAnalysisActionButtonState
    extends State<FloatingAnalysisActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 1;
    } else if (_controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: '使用目前對話開始分析',
      child: ExcludeSemantics(
        child: SizedBox.square(
          key: FloatingAnalysisActionButton.orbKey,
          dimension: 72,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = _controller.value;
              final entrance = const Interval(
                0,
                0.52,
                curve: Curves.easeOutCubic,
              ).transform(value);
              final scan = const Interval(
                0.08,
                1,
                curve: Curves.easeOutCubic,
              ).transform(value);

              return Opacity(
                opacity: 0.18 + (0.82 * entrance),
                child: Transform.scale(
                  scale: 0.88 + (0.12 * entrance),
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Transform.scale(
                        scale: 0.82 + (0.32 * scan),
                        child: Opacity(
                          opacity: (1 - scan) * (enabled ? 0.48 : 0.18),
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.ctaStart,
                                width: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: enabled ? 1 : 0.34,
                        child: Transform.rotate(
                          angle: -0.52 * (1 - entrance),
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                colors: [
                                  AppColors.ctaStart.withValues(alpha: 0.08),
                                  AppColors.ctaStart.withValues(alpha: 0.92),
                                  AppColors.bokehYellow.withValues(alpha: 0.82),
                                  AppColors.ctaStart.withValues(alpha: 0.08),
                                ],
                                stops: const [0, 0.48, 0.67, 1],
                              ),
                              boxShadow: enabled
                                  ? [
                                      BoxShadow(
                                        color: AppColors.ctaStart
                                            .withValues(alpha: 0.24),
                                        blurRadius: 16,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      child!,
                    ],
                  ),
                ),
              );
            },
            child: FilledButton(
              key: FloatingAnalysisActionButton.buttonKey,
              onPressed: widget.onPressed,
              style: FilledButton.styleFrom(
                fixedSize: const Size.square(52),
                minimumSize: const Size.square(52),
                maximumSize: const Size.square(52),
                padding: EdgeInsets.zero,
                backgroundColor: AppColors.brandInk,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.brandInk.withValues(alpha: 0.88),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.50),
                elevation: enabled ? 10 : 2,
                shadowColor: Colors.black.withValues(alpha: 0.52),
                shape: CircleBorder(
                  side: BorderSide(
                    color: enabled
                        ? Colors.white.withValues(alpha: 0.20)
                        : Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ).copyWith(
                overlayColor: WidgetStatePropertyAll(
                  AppColors.ctaStart.withValues(alpha: 0.20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: enabled
                        ? AppColors.bokehYellow
                        : Colors.white.withValues(alpha: 0.42),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '開始分析',
                    maxLines: 1,
                    style: AppTypography.caption.copyWith(
                      color: enabled
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.50),
                      fontSize: 10,
                      height: 1.05,
                      letterSpacing: -0.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
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

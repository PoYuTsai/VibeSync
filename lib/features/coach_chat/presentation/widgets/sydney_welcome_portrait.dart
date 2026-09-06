import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/animation/motion_preference.dart';

/// Entry-only Sydney performance. Removing the welcome section also releases
/// the decoder; answers and keyboard space never depend on the video timeline.
/// 沒有暫停鍵（2026-09-07 Eric）：靜音循環不需要控制項，Reduce Motion 走靜態圖。
class SydneyWelcomePortrait extends StatefulWidget {
  const SydneyWelcomePortrait({super.key});

  static const videoAsset = 'assets/videos/coach/sydney_performance_v3.mp4';
  static const posterAsset =
      'assets/images/coach/sydney_performance_v3_poster.jpg';

  @override
  State<SydneyWelcomePortrait> createState() => _SydneyWelcomePortraitState();
}

class _SydneyWelcomePortraitState extends State<SydneyWelcomePortrait>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _motionDisabled = true;
  bool _routeCurrent = false;
  bool _foreground = true;

  bool get _canPlay => !_motionDisabled && _routeCurrent && _foreground;

  bool get _supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionDisabled = motionDisabled(context);
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _updatePlayback();
  }

  void _updatePlayback() {
    if (_controller == null && !_failed && _supported && _canPlay) {
      unawaited(_initialize());
    } else {
      unawaited(_syncPlayback());
    }
  }

  Future<void> _initialize() async {
    // This widget owns lifecycle decisions. The player's automatic resume must
    // not override a covered route or Reduce Motion on return.
    final controller = VideoPlayerController.asset(
      SydneyWelcomePortrait.videoAsset,
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: true,
      ),
    );
    _controller = controller;
    controller.addListener(_onPlayerChanged);
    try {
      await controller.initialize();
      if (!mounted || _failed) return;
      await controller.setVolume(0);
      if (!mounted || _failed) return;
      await controller.setLooping(true);
      if (!mounted || _failed) return;
      await controller.setPreventsDisplaySleepDuringVideoPlayback(false);
      if (!mounted || _failed) return;
      setState(() => _ready = true);
      await _syncPlayback();
    } catch (_) {
      _showPoster();
    }
  }

  void _onPlayerChanged() {
    if (_controller?.value.hasError ?? false) _showPoster();
  }

  void _showPoster() {
    if (!mounted || _failed) return;
    setState(() {
      _failed = true;
      _ready = false;
    });
    _releasePlayer();
  }

  Future<void> _syncPlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (mounted && _ready && !_failed && _canPlay) {
        if (!controller.value.isPlaying) await controller.play();
      } else if (controller.value.isPlaying) {
        await controller.pause();
      }
    } catch (_) {
      _showPoster();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updatePlayback();
  }

  void _releasePlayer() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onPlayerChanged);
      // Disposal can finish after the welcome subtree is removed during input.
      unawaited(controller.dispose().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releasePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showVideo = _ready && !_failed && !_motionDisabled;
    // 素材底色是整片深紫，直接貼在漸層底上會露出一個長方形；四邊都淡出，
    // 人物像是從背景長出來，不用裁圓角也不用暫停鍵蓋在臉旁邊。
    Widget fade(Widget child,
        {required Alignment begin,
        required Alignment end,
        required List<double> stops}) {
      return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: begin,
          end: end,
          colors: const [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: stops,
        ).createShader(bounds),
        child: child,
      );
    }

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ExcludeSemantics(
        child: fade(
          fade(
            showVideo
                ? VideoPlayer(_controller!)
                : Image.asset(
                    SydneyWelcomePortrait.posterAsset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0, 0.16, 0.84, 1],
          ),
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.06, 0.86, 1],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/animation/motion_preference.dart';
import '../../../../core/theme/app_colors.dart';

/// Entry-only Sydney performance. Removing the welcome section also releases
/// the decoder; answers and keyboard space never depend on the video timeline.
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
  bool _userPaused = false;
  bool _foreground = true;

  bool get _canPlay =>
      !_motionDisabled && _routeCurrent && !_userPaused && _foreground;

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
    // not override a user's pause, a covered route or Reduce Motion on return.
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
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0, 0.88, 1],
                ).createShader(bounds),
                child: showVideo
                    ? VideoPlayer(_controller!)
                    : Image.asset(
                        SydneyWelcomePortrait.posterAsset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
            ),
          ),
          if (showVideo)
            Positioned(
              right: 0,
              bottom: 0,
              child: IconButton.filledTonal(
                tooltip: _userPaused ? '播放 Sydney 動畫' : '暫停 Sydney 動畫',
                onPressed: () {
                  setState(() => _userPaused = !_userPaused);
                  unawaited(_syncPlayback());
                },
                style: IconButton.styleFrom(
                  backgroundColor:
                      AppColors.brandSurface.withValues(alpha: 0.8),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(44, 44),
                  iconSize: 18,
                ),
                icon: Icon(_userPaused ? Icons.play_arrow : Icons.pause),
              ),
            ),
        ],
      ),
    );
  }
}

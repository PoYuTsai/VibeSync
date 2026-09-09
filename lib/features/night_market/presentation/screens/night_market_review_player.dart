import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/night_market_scenario.dart';

/// Replays a chapter using the existing assets. Its controller belongs to this
/// route, so a closed replay cannot keep playing behind the reading pages.
class NightMarketReviewPlayer extends StatefulWidget {
  const NightMarketReviewPlayer({
    super.key,
    required this.scenario,
    required this.chapter,
  });

  final NightMarketScenario scenario;
  final NightMarketReviewChapter chapter;

  @override
  State<NightMarketReviewPlayer> createState() =>
      _NightMarketReviewPlayerState();
}

class _NightMarketReviewPlayerState extends State<NightMarketReviewPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Completer<void>? _initializationCancelled;
  int _generation = 0;
  int _index = 0;
  bool _loading = true;
  bool _failed = false;
  bool _ended = false;
  bool _transitioning = false;
  bool _foreground = true;
  bool _autoplay = true;

  NightMarketReviewClip get _clip => widget.chapter.clips[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(_load(0));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _autoplay = false;
      unawaited(_pause());
    }
  }

  Future<void> _pause() async {
    try {
      await _controller?.pause();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _load(int index) async {
    final generation = ++_generation;
    _cancelInitialization();
    setState(() {
      _loading = true;
      _failed = false;
      _ended = false;
      _transitioning = true;
      _index = index;
    });
    final old = _controller;
    _controller = null;
    old?.removeListener(_onVideo);
    await old?.dispose();
    if (!mounted || generation != _generation) return;
    final controller = VideoPlayerController.asset(
      widget.scenario.beatById(_clip.beatId)!.videoAsset,
    );
    _controller = controller;
    try {
      final cancelled = Completer<void>();
      _initializationCancelled = cancelled;
      await Future.any<void>([controller.initialize(), cancelled.future])
          .timeout(const Duration(seconds: 12));
      if (!mounted || _controller != controller) return;
      await controller.setLooping(false);
      await controller.seekTo(_clip.start);
      if (!mounted || _controller != controller) return;
      controller.addListener(_onVideo);
      _transitioning = false;
      setState(() => _loading = false);
      if (_foreground && _autoplay) await controller.play();
    } catch (_) {
      if (mounted && _controller == controller) {
        setState(() {
          _failed = true;
          _loading = false;
          _transitioning = false;
        });
      }
    }
  }

  void _cancelInitialization() {
    final cancelled = _initializationCancelled;
    _initializationCancelled = null;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
  }

  void _onVideo() {
    final controller = _controller;
    if (!mounted || controller == null || _transitioning || _ended) return;
    if (controller.value.hasError) {
      setState(() => _failed = true);
      return;
    }
    final value = controller.value;
    if (value.isCompleted || value.position >= _clip.end) {
      _transitioning = true;
      unawaited(_finishClip(controller));
    }
  }

  Future<void> _finishClip(VideoPlayerController controller) async {
    await _pause();
    if (!mounted || _controller != controller || _failed) return;
    // 位置通知可能晚於終點：暫停後把位置拉回片段末端，不停在下一章的畫面
    //（Codex R1 P2，2026-09-10）。
    if (controller.value.position > _clip.end) {
      await controller.seekTo(_clip.end);
      if (!mounted || _controller != controller || _failed) return;
    }
    if (_index + 1 < widget.chapter.clips.length) {
      await _load(_index + 1);
    } else {
      // Stay on the last frame; do not enter a choice node or the next chapter.
      setState(() {
        _ended = true;
        _transitioning = false;
      });
    }
  }

  Future<void> _toggle() async {
    if (_loading || _transitioning) return;
    if (_ended) {
      _autoplay = true;
      await _load(0);
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else if (_foreground) {
        _autoplay = true;
        await controller.play();
      }
    } catch (_) {
      if (mounted && _controller == controller) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _cancelInitialization();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onVideo);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('回看片段'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                  '${widget.chapter.title}\n${widget.chapter.timeLabel}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.5)),
            ),
            Expanded(
              child: _failed
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('影片暫時無法播放',
                              style: TextStyle(color: Colors.white)),
                          OutlinedButton(
                            onPressed: () {
                              _autoplay = true;
                              unawaited(_load(_index));
                            },
                            child: const Text('重試'),
                          ),
                        ],
                      ),
                    )
                  : _loading || controller == null
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),
                        ),
            ),
            if (!_failed && !_loading && controller != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (_, value, __) => FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.ctaStart,
                      foregroundColor: AppColors.brandInk,
                    ),
                    onPressed: _transitioning ? null : _toggle,
                    icon: Icon(_ended
                        ? Icons.replay
                        : value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow),
                    label: Text(_ended
                        ? '再看一次'
                        : value.isPlaying
                            ? '暫停'
                            : '繼續播放'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

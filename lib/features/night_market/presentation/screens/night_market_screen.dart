import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/reveal_pill.dart';
import '../../data/night_market_story.dart';
import '../../domain/night_market_scenario.dart';

/// Full-screen, VR-style run of the night-market scenario: no UI while the
/// video plays; the film stops only at its stop points and at the review.
class NightMarketScreen extends StatefulWidget {
  const NightMarketScreen({super.key});

  @override
  State<NightMarketScreen> createState() => _NightMarketScreenState();
}

class _NightMarketScreenState extends State<NightMarketScreen>
    with WidgetsBindingObserver {
  final _scenario = buildNightMarketScenario();
  late String _beatId = _scenario.initialBeatId;
  VideoPlayerController? _video;
  int _loadAttempt = 0;
  bool _started = false;
  bool _completed = false;
  bool _failed = false;
  bool _paused = false;
  bool _muted = false;
  bool _captionsOn = false;
  bool _finished = false;
  String? _coachCard;
  String? _pendingNextId;

  NightMarketBeat get _beat => _scenario.beatById(_beatId)!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding freezes the frame; coming back waits for the player's tap
    // instead of restarting on its own.
    if (state != AppLifecycleState.resumed && !_paused && !_completed) {
      _paused = true;
      unawaited(_video?.pause());
      if (mounted) setState(() {});
    }
  }

  Future<void> _load(String id) async {
    final attempt = ++_loadAttempt;
    final old = _video;
    _video = null;
    old?.removeListener(_onVideo);
    await old?.dispose();
    if (!mounted || attempt != _loadAttempt) return;
    setState(() {
      _beatId = id;
      _completed = false;
      _failed = false;
      _paused = false;
      _coachCard = null;
      _pendingNextId = null;
    });
    final controller = VideoPlayerController.asset(_beat.videoAsset);
    _video = controller;
    controller.addListener(_onVideo);
    try {
      await controller.initialize().timeout(const Duration(seconds: 12));
      if (!mounted || _video != controller) return;
      await controller.setLooping(false);
      await controller.setVolume(_muted ? 0 : 1);
      if (!_paused) await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted && _video == controller) setState(() => _failed = true);
    }
  }

  void _onVideo() {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized || _completed) {
      return;
    }
    if (controller.value.hasError) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final value = controller.value;
    final done = value.isCompleted ||
        (value.duration > Duration.zero && value.position >= value.duration);
    if (!done) return;
    _completed = true;
    unawaited(controller.pause());
    if (mounted) setState(() => _finished = _beat.ending);
  }

  Future<void> _start() async {
    setState(() => _started = true);
    await _load(_scenario.initialBeatId);
  }

  Future<void> _restart() async {
    setState(() => _finished = false);
    await _load(_scenario.initialBeatId);
  }

  void _togglePause() {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized || _completed) {
      return;
    }
    setState(() => _paused = !_paused);
    unawaited(_paused ? controller.pause() : controller.play());
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _video?.setVolume(_muted ? 0 : 1);
  }

  Future<void> _choose(NightMarketChoice choice) async {
    if (choice.coachCard == null) {
      await _load(choice.nextId);
      return;
    }
    setState(() {
      _coachCard = choice.coachCard;
      _pendingNextId = choice.nextId;
    });
  }

  @override
  void dispose() {
    _loadAttempt++;
    WidgetsBinding.instance.removeObserver(this);
    _video?.removeListener(_onVideo);
    unawaited(_video?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: !_started
          ? _startPanel()
          : _finished
              ? _reviewPage()
              : _player(),
    );
  }

  Widget _topBar({List<Widget> leading = const []}) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...leading,
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: '關閉',
              color: Colors.white70,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _startPanel() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _scenario.coverAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const ColoredBox(color: AppColors.brandInk),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black26, Colors.black87],
            ),
          ),
        ),
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_scenario.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(_scenario.subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 15, height: 1.4)),
                    const SizedBox(height: 6),
                    const Text('沒有字幕、沒有提示。只在兩個地方停下來，選你會做的。',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 14, height: 1.4)),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: _start, child: const Text('開始')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _topBar(),
      ],
    );
  }

  Widget _player() {
    final controller = _video;
    final ready =
        controller != null && controller.value.isInitialized && !_failed;
    final beat = _beat;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePause,
          child: ready
              ? FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                )
              : ColoredBox(
                  color: AppColors.brandInk,
                  child: Center(
                    child: _failed
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('影片暫時無法播放',
                                  style: TextStyle(color: Colors.white)),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                  onPressed: () => _load(beat.id),
                                  child: const Text('重試')),
                            ],
                          )
                        : const CircularProgressIndicator(
                            color: Colors.white54),
                  ),
                ),
        ),
        if (ready && _captionsOn)
          Positioned(
            left: 16,
            right: 16,
            bottom: 96,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (_, value, __) => _caption(beat, value.position),
            ),
          ),
        if (ready && _paused && !_completed)
          const IgnorePointer(
            child: Center(
              child: Icon(Icons.play_circle_outline,
                  color: Colors.white70, size: 72),
            ),
          ),
        _topBar(leading: [
          IconButton(
            onPressed: () => setState(() => _captionsOn = !_captionsOn),
            tooltip: _captionsOn ? '關閉字幕' : '顯示字幕',
            color: _captionsOn ? Colors.white : Colors.white38,
            icon: const Icon(Icons.closed_caption),
          ),
          IconButton(
            onPressed: _toggleMute,
            tooltip: _muted ? '開啟聲音' : '靜音',
            color: Colors.white70,
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
          ),
        ]),
        if (_completed && beat.choices.isNotEmpty)
          Align(
            alignment: Alignment.bottomCenter,
            child: _coachCard == null ? _choiceCard(beat) : _coachCardView(),
          ),
      ],
    );
  }

  Widget _caption(NightMarketBeat beat, Duration position) {
    final active = beat.captions
        .where((c) => position >= c.start && position < c.end)
        .toList(growable: false);
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final caption in active)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                '${switch (caption.speaker) {
                  NightMarketSpeaker.coach => 'Sydney',
                  NightMarketSpeaker.npc => 'Leah',
                  NightMarketSpeaker.user => '你',
                }}：${caption.text}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _choiceCard(NightMarketBeat beat) {
    return _card(children: [
      if (beat.hint != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(beat.hint!,
              style: const TextStyle(
                  color: AppColors.ctaStart, fontSize: 15, height: 1.4)),
        ),
      for (final choice in beat.choices)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FilledButton(
            onPressed: () => _choose(choice),
            child: Text(choice.label, textAlign: TextAlign.center),
          ),
        ),
    ]);
  }

  Widget _coachCardView() {
    return _card(children: [
      Text(_coachCard!,
          style:
              const TextStyle(color: Colors.white, fontSize: 16, height: 1.45)),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => _load(_pendingNextId!),
        child: const Text('知道了'),
      ),
    ]);
  }

  Widget _reviewPage() {
    final items = _scenario.review;
    List<NightMarketReviewItem> tier(NightMarketReviewTier t) =>
        items.where((i) => i.tier == t).toList(growable: false);
    return Stack(
      children: [
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 32),
            children: [
              const Text('復盤',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('重點不是台詞，是淺溝通：態度、眼神、肢體。不背土味情話，不用罐頭話術。',
                  style: TextStyle(color: Colors.white70, height: 1.45)),
              const SizedBox(height: 20),
              for (final item in tier(NightMarketReviewTier.mindset))
                _reviewLine(item),
              const SizedBox(height: 16),
              const Text('這次的 6 個關鍵',
                  style: TextStyle(
                      color: AppColors.ctaStart, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final item in tier(NightMarketReviewTier.key))
                _reviewCard(item),
              // 與開場救星「下一步怎麼接？」同款揭示膠囊（Eric 2026-09-08）。
              RevealPill(
                label: '更多技巧',
                children: [
                  for (final item in tier(NightMarketReviewTier.more))
                    _reviewCard(item),
                ],
              ),
              const SizedBox(height: 20),
              Text(_scenario.takeaway,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              FilledButton(onPressed: _restart, child: const Text('再練一次')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('回練習室'),
              ),
            ],
          ),
        ),
        _topBar(),
      ],
    );
  }

  Widget _reviewLine(NightMarketReviewItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: '${item.term}｜',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        TextSpan(
            text: item.plain, style: const TextStyle(color: Colors.white70)),
      ])),
    );
  }

  Widget _reviewCard(NightMarketReviewItem item) {
    final color = item.met ? Colors.white : Colors.white38;
    final suffix = !item.met
        ? '（這次沒遇到）'
        : item.optional
            ? '（不是必要）'
            : '';
    return Card(
      color: AppColors.brandSurface2,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.term}$suffix',
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(item.plain,
                style: TextStyle(
                    color: item.met ? Colors.white70 : Colors.white30,
                    height: 1.4)),
          ],
        ),
      ),
    );
  }
}

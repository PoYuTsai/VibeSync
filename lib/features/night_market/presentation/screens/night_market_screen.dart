import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../data/night_market_story.dart';
import '../../domain/night_market_scenario.dart';
import '../night_market_essential_gate.dart';
import 'night_market_review_screen.dart';

/// Full-screen, VR-style run of the night-market scenario: no UI while the
/// video plays; the film stops only at its stop points and at the review.
class NightMarketScreen extends ConsumerStatefulWidget {
  const NightMarketScreen({super.key});

  @override
  ConsumerState<NightMarketScreen> createState() => _NightMarketScreenState();
}

class _NightMarketScreenState extends ConsumerState<NightMarketScreen>
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
  bool _paywallInFlight = false;

  /// A likely-real purchase/restore was made but couldn't yet be confirmed
  /// (see [NightMarketUnlockOutcome.pendingConfirmation]). While true, the
  /// next gate hit retries confirmation instead of reopening the store
  /// paywall.
  bool _pendingConfirmation = false;

  /// S3 finished playing but essential access could not (yet) be confirmed
  /// at that exact moment — shows a retry card instead of leaving the last
  /// frozen frame with no way forward.
  bool _awaitingReviewAccess = false;

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
      _awaitingReviewAccess = false;
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
    if (!_beat.ending) {
      if (mounted) setState(() {});
      return;
    }
    unawaited(_resolveEnding());
  }

  /// Access could have been lost while S3 was still playing (expiry,
  /// revocation) — passing the gate earlier at the choice does not carry
  /// forward, so this re-checks right at the point of actually building the
  /// full recap, same rule as every other entry into essential-gated
  /// content.
  ///
  /// Also the recovery entry point for a stalled "待進復盤" state: unlike a
  /// mid-stream choice, S3 finishing has no choice buttons to tap again, so
  /// resolving/unavailable/cancelled here would otherwise be a dead end —
  /// [_awaitingReviewAccess] keeps a retry button on screen instead of
  /// relying on this listener (which won't fire again once the video is
  /// paused at the end) ever re-running on its own.
  Future<void> _resolveEnding() async {
    if (mounted) setState(() => _awaitingReviewAccess = true);
    await _withEssentialGate(_beat.access, () async {
      if (mounted) {
        setState(() {
          _finished = true;
          _awaitingReviewAccess = false;
        });
      }
    });
    if (mounted && !_finished) setState(() {});
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

  /// Single choke point for every way this screen can advance into
  /// essential-gated content: a choice tap, tapping "知道了" on a coach card,
  /// and finishing the ending beat. Each one re-checks the gate fresh right
  /// before acting — passing the gate earlier (at choice-time) does not
  /// carry forward to a later moment of actually entering the content.
  ///
  /// Guards re-entrancy at the very top, before even reading the gate: if a
  /// paywall round trip is already in flight, a second tap is dropped
  /// outright, even if the subscription provider has already flipped to
  /// allowed mid-flight (it would otherwise race the pending restart).
  Future<void> _withEssentialGate(
    EbookAccess access,
    Future<void> Function() onAllowed,
  ) async {
    if (_paywallInFlight) return;
    final gate = gateFor(access, ref.read(ebookSubscriptionAccessProvider));
    switch (gate) {
      case ChatQuizGate.allowed:
        await onAllowed();
        break;
      case ChatQuizGate.locked:
        // Guard covers the whole sequence including the restart, releasing
        // only in `finally`, so a fast double-tap can't open a second
        // paywall or trigger a second restart.
        _paywallInFlight = true;
        try {
          // A prior attempt ended pendingConfirmation: retry confirmation
          // only, never reopen the store paywall for a purchase that may
          // have already gone through.
          final outcome = _pendingConfirmation
              ? await resolveNightMarketPendingConfirmation(context, ref)
              : await resolveNightMarketEssentialUnlock(context, ref);
          if (!context.mounted) return;
          _pendingConfirmation =
              outcome == NightMarketUnlockOutcome.pendingConfirmation;
          if (outcome == NightMarketUnlockOutcome.unlocked) {
            await _restart();
          }
        } finally {
          _paywallInFlight = false;
        }
        break;
      case ChatQuizGate.resolving:
        showNightMarketGateNotice(context, '正在確認你的訂閱狀態，請稍後再點一次');
        break;
      case ChatQuizGate.unavailable:
        showNightMarketGateNotice(
          context,
          '暫時無法確認訂閱狀態',
          actionLabel: '重試',
          onAction: () => ref.read(subscriptionProvider.notifier).refresh(),
        );
        break;
    }
  }

  Future<void> _choose(NightMarketChoice choice) {
    return _withEssentialGate(
      _scenario.beatById(choice.nextId)!.access,
      () async {
        if (choice.coachCard == null) {
          await _load(choice.nextId);
          return;
        }
        setState(() {
          _coachCard = choice.coachCard;
          _pendingNextId = choice.nextId;
        });
      },
    );
  }

  /// "知道了" on the coach card. Time may have passed since the choice was
  /// made (and access could have been lost since), so this re-checks the
  /// gate rather than loading `_pendingNextId` unconditionally.
  Future<void> _acceptCoachCard() {
    final pendingNextId = _pendingNextId!;
    return _withEssentialGate(
      _scenario.beatById(pendingNextId)!.access,
      () => _load(pendingNextId),
    );
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
        if (_completed && beat.ending && _awaitingReviewAccess)
          Align(
            alignment: Alignment.bottomCenter,
            child: _reviewAccessPendingCard(),
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
    final subscription = ref.watch(ebookSubscriptionAccessProvider);
    final locked = beat.choices.any((choice) =>
        gateFor(_scenario.beatById(choice.nextId)!.access, subscription) ==
        ChatQuizGate.locked);
    return _card(children: [
      if (beat.hint != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(beat.hint!,
              style: const TextStyle(
                  color: AppColors.ctaStart, fontSize: 15, height: 1.4)),
        ),
      if (locked)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 14, color: Colors.white54),
              SizedBox(width: 6),
              Text('接下來的段落是 Essential 方案內容',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
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
        onPressed: _acceptCoachCard,
        child: const Text('知道了'),
      ),
    ]);
  }

  /// Shown on S3's frozen last frame while essential access still isn't
  /// confirmed — the explicit "待進復盤" state and recovery entry point
  /// required instead of leaving a dead end that only a (never-refiring)
  /// video listener could have retried.
  Widget _reviewAccessPendingCard() {
    return _card(children: [
      Text(
        _pendingConfirmation
            ? '已收到你的購買，正在確認中。'
            : '復盤是 Essential 方案內容。',
        style:
            const TextStyle(color: Colors.white, fontSize: 16, height: 1.45),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _resolveEnding,
        child: Text(_pendingConfirmation ? '重試確認' : '重試'),
      ),
    ]);
  }

  Widget _reviewPage() => NightMarketReviewScreen(
        scenario: _scenario,
        onRestart: _restart,
        onExit: () => Navigator.of(context).maybePop(),
      );
}

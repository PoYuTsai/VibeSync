import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/night_market_story.dart';
import '../../domain/night_market_scenario.dart';

class NightMarketScreen extends StatefulWidget {
  const NightMarketScreen({super.key, this.variant});

  final NightMarketRunVariant? variant;

  @override
  State<NightMarketScreen> createState() => _NightMarketScreenState();
}

class _NightMarketScreenState extends State<NightMarketScreen>
    with WidgetsBindingObserver {
  late NightMarketRunVariant _variant;
  late NightMarketScenario _scenario;
  late NightMarketFlowState _flow =
      NightMarketFlowState(beatId: _scenario.initialBeatId);
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  AudioPlayer? _sfx;
  AudioPlayer? _ambient;
  bool _started = false;
  bool _failed = false;
  bool _readingFallback = false;
  bool _pausedByUser = false;
  int _loadAttempt = 0;
  int _audioToken = 0;
  bool _foreground = true;
  String? _pendingNextId;
  bool _audioPhase = false;
  bool _voiceFailed = false;
  String? _activeChoiceText;
  StreamSubscription<void>? _voiceCompletion;
  int _retryCount = 0;
  String? _methodAnswer;

  static const _ambientAsset = 'assets/audio/night_market/market-bed.mp3';
  // The bundled bed is -23.5 LUFS; this keeps it audible below dialogue.
  static const _ambientVolume = 0.45;
  // These players share one scene; cues must not steal focus from its video.
  static final _sceneAudioContext = AudioContext(
    android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
    iOS: AudioContextIOS(options: {AVAudioSessionOptions.mixWithOthers}),
  );

  NightMarketBeat? get _beat => _scenario.beatById(_flow.beatId);

  @override
  void initState() {
    super.initState();
    _variant = widget.variant ??
        (Random().nextBool()
            ? NightMarketRunVariant.available
            : NightMarketRunVariant.busy);
    _scenario = buildNightMarketScenario(variant: _variant);
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _switchTimeVariant() async {
    final next = _variant == NightMarketRunVariant.available
        ? NightMarketRunVariant.busy
        : NightMarketRunVariant.available;
    _audioToken++;
    await _voiceCompletion?.cancel();
    _voiceCompletion = null;
    _activeChoiceText = null;
    _voiceFailed = false;
    _audioPhase = false;
    _pendingNextId = null;
    await _audio?.stop();
    await _ambient?.stop();
    if (!mounted) return;
    setState(() {
      _variant = next;
      _scenario = buildNightMarketScenario(variant: next);
      _flow = NightMarketFlowState(
        beatId: _scenario.initialBeatId,
        isMuted: _flow.isMuted,
        hintVisible: _flow.hintVisible,
      );
      _methodAnswer = null;
      _retryCount = 0;
      _failed = false;
      _started = true;
    });
    await _loadBeat(_scenario.initialBeatId);
  }

  Future<void> _replayFrom(String id) async {
    if (_scenario.beatById(id) == null) return;
    final keep = <String>{
      if (id == 'opening') 'approach',
      if (id == 'work' || id == 'craft' || id == 'call') ...{
        'approach',
        'introduce',
        'answer_intent',
      },
      if (id == 'craft' || id == 'call') 'share_product_design',
      if (id == 'call') ...{
        'share_pen_holder',
        'share_pen_holder_light',
        'first_today',
        'hungry_vendor',
      },
    };
    _audioToken++;
    await _voiceCompletion?.cancel();
    _voiceCompletion = null;
    _activeChoiceText = null;
    _voiceFailed = false;
    _audioPhase = false;
    _pendingNextId = null;
    await _audio?.stop();
    await _ambient?.stop();
    if (!mounted) return;
    setState(() {
      _flow = _flow.copyWith(
        beatId: id,
        selectedChoiceIds: _flow.selectedChoiceIds
            .where(keep.contains)
            .toList(growable: false),
        videoCompleted: false,
      );
      _methodAnswer = null;
      _retryCount = 0;
      _failed = false;
    });
    await _loadBeat(id);
  }

  void _pauseMedia() {
    unawaited(_video?.pause());
    unawaited(_audio?.pause());
    unawaited(_sfx?.pause());
    unawaited(_ambient?.pause());
  }

  void _resumeMedia() {
    if (!_started || !_canPlay) return;
    if (_audioPhase) {
      if (!_voiceFailed) unawaited(_audio?.resume());
      unawaited(_startAmbient());
    } else if (_pendingNextId != null) {
      unawaited(_advancePending());
    } else if (_flow.videoCompleted) {
      if (_beat?.choices.isNotEmpty == true) unawaited(_startAmbient());
    } else if (_video?.value.isInitialized == true && !_failed) {
      _onVideoChanged();
      if (!_flow.videoCompleted && _pendingNextId == null) {
        unawaited(_video?.play());
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_canPlay) {
      _pauseMedia();
    } else {
      _resumeMedia();
    }
  }

  Future<void> _start() async {
    if (_started) return;
    setState(() => _started = true);
    await _loadBeat(_flow.beatId);
  }

  Future<void> _loadBeat(String id) async {
    final beat = _scenario.beatById(id);
    if (beat == null) return;
    _pausedByUser = false;
    _readingFallback = false;
    unawaited(_ambient?.pause());
    final attempt = ++_loadAttempt;
    final old = _video;
    _video = null;
    old?.removeListener(_onVideoChanged);
    await old?.dispose();
    if (!mounted || attempt != _loadAttempt) return;
    if (beat.textOnly) {
      setState(() {
        _flow = _flow.copyWith(
          beatId: id,
          videoCompleted: true,
          isPlaying: false,
        );
        _failed = false;
      });
      return;
    }
    final videoAsset = beat.videoAsset;
    setState(() {
      _flow =
          _flow.copyWith(beatId: id, videoCompleted: false, isPlaying: false);
      _failed = false;
    });
    final controller = VideoPlayerController.asset(
      videoAsset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video = controller;
    controller.addListener(_onVideoChanged);
    try {
      await controller.initialize().timeout(const Duration(seconds: 12));
      if (!mounted || _video != controller || attempt != _loadAttempt) return;
      await controller.setLooping(false);
      await controller.setVolume(_flow.isMuted ? 0 : 1);
      if (_canPlay) await controller.play();
      final sfx = beat.sfxAsset;
      if (sfx != null && _canPlay && !_flow.isMuted) {
        try {
          _sfx ??= AudioPlayer();
          await _sfx!.setVolume(0.35);
          await _sfx!.play(AssetSource(sfx.replaceFirst('assets/', '')),
              ctx: _sceneAudioContext);
          if (!_canPlay) await _sfx!.pause();
        } catch (_) {}
      }
      if (mounted && _canPlay) {
        setState(() => _flow = _flow.copyWith(isPlaying: true));
      }
    } catch (_) {
      if (mounted && _video == controller && attempt == _loadAttempt) {
        setState(() {
          _failed = true;
        });
      }
    }
  }

  void _continueByText() {
    if (!_failed) return;
    _pausedByUser = false;
    if (!_canPlay) return;
    _failed = false;
    _readingFallback = true;
    _completeBeat();
  }

  void _onVideoChanged() {
    if (_audioPhase) return;
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
      return;
    }
    if (controller.value.isPlaying && mounted && !_flow.isPlaying) {
      setState(() => _flow = _flow.copyWith(isPlaying: true));
    }
    if (controller.value.isInitialized &&
        controller.value.position >= controller.value.duration &&
        !_flow.videoCompleted) {
      _completeBeat();
    }
  }

  void _completeBeat() {
    if (!mounted || !_canPlay) return;
    setState(
        () => _flow = _flow.copyWith(videoCompleted: true, isPlaying: false));
    unawaited(_video?.pause());
    final beat = _beat;
    if (beat != null && beat.choices.isNotEmpty) {
      unawaited(_startAmbient());
    }
    if (beat != null && beat.choices.isEmpty && beat.nextId != null) {
      _pendingNextId = beat.nextId;
      unawaited(_advancePending());
    }
  }

  bool get _canPlay =>
      _foreground &&
      !_pausedByUser &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _advancePending() async {
    final next = _pendingNextId;
    if (next == null || _audioPhase || !_canPlay) return;
    _pendingNextId = null;
    await _loadBeat(next);
  }

  Future<void> _startAmbient() async {
    if (!_canPlay || _flow.isMuted) return;
    try {
      _ambient ??= AudioPlayer();
      await _ambient!.setReleaseMode(ReleaseMode.loop);
      await _ambient!.setVolume(_ambientVolume);
      if (!_canPlay) return;
      if (_ambient!.state != PlayerState.playing) {
        await _ambient!.play(
          AssetSource(_ambientAsset.replaceFirst('assets/', '')),
          ctx: _sceneAudioContext,
        );
      }
    } catch (_) {
      // Ambient sound is optional; a playback failure must not block choices.
    }
  }

  Future<void> _finishVoice(int token) async {
    if (!mounted || token != _audioToken || !_audioPhase) return;
    final completion = _voiceCompletion;
    _voiceCompletion = null;
    unawaited(completion?.cancel() ?? Future<void>.value());
    try {
      await _audio?.stop();
    } catch (_) {}
    if (!mounted || token != _audioToken) return;
    setState(() {
      _audioPhase = false;
      _voiceFailed = false;
      _activeChoiceText = null;
    });
    await _advancePending();
  }

  void _voiceError(int token) {
    if (!mounted || token != _audioToken || !_audioPhase) return;
    unawaited(_audio?.stop().catchError((Object _) {}));
    setState(() => _voiceFailed = true);
  }

  Future<void> _choose(NightMarketChoice choice) async {
    if (!_flow.videoCompleted || !_canPlay) return;
    if (_beat?.ending == true) {
      await _replayFrom(choice.nextId);
      return;
    }
    final asset = choice.audioAsset;
    final token = ++_audioToken;
    setState(() {
      _flow = _flow.copyWith(
        selectedChoiceIds: [..._flow.selectedChoiceIds, choice.id],
        videoCompleted: false,
      );
      _pendingNextId = choice.nextId;
      _activeChoiceText = choice.spokenText;
      _audioPhase = asset != null;
      _voiceFailed = false;
    });
    if (asset == null) {
      await _advancePending();
      return;
    }
    try {
      _audio ??= AudioPlayer();
      await _voiceCompletion?.cancel();
      _voiceCompletion = _audio!.onPlayerComplete.listen(
        (_) => unawaited(_finishVoice(token)),
        onError: (Object _) => _voiceError(token),
      );
      await _audio!.setVolume(_flow.isMuted ? 0 : 1);
      // Bound loading only. Pausing or backgrounding never consumes the
      // spoken response's playback time.
      await _audio!
          .play(AssetSource(asset.replaceFirst('assets/', '')),
              ctx: _sceneAudioContext)
          .timeout(const Duration(seconds: 10));
      if (!mounted || token != _audioToken) return;
      if (!_canPlay) await _audio!.pause();
    } catch (_) {
      _voiceError(token);
    }
  }

  Future<void> _toggleMute() async {
    final muted = !_flow.isMuted;
    setState(() => _flow = _flow.copyWith(isMuted: muted));
    await _video?.setVolume(muted ? 0 : 1);
    await _audio?.setVolume(muted ? 0 : 1);
    await _sfx?.setVolume(muted ? 0 : 0.35);
    await _ambient?.setVolume(muted ? 0 : _ambientVolume);
    if (muted) {
      await _ambient?.pause();
    } else if (_audioPhase ||
        (_flow.videoCompleted && _beat?.choices.isNotEmpty == true)) {
      await _startAmbient();
    }
  }

  Future<void> _togglePlayback() async {
    if (!_started || _failed || (_flow.videoCompleted && !_audioPhase)) return;
    setState(() {
      _pausedByUser = !_pausedByUser;
      _flow = _flow.copyWith(isPlaying: !_pausedByUser);
    });
    if (_pausedByUser) {
      _pauseMedia();
    } else {
      _resumeMedia();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _resumeMedia();
    } else {
      _pauseMedia();
    }
  }

  @override
  void dispose() {
    _audioToken++;
    _loadAttempt++;
    unawaited(_voiceCompletion?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _video?.removeListener(_onVideoChanged);
    unawaited(_video?.dispose());
    unawaited(_audio?.dispose());
    unawaited(_sfx?.dispose());
    unawaited(_ambient?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final beat = _beat;
    return BrandScaffold(
      title: '台灣夜市情境練習',
      actions: [
        IconButton(
            onPressed: _toggleMute,
            tooltip: _flow.isMuted ? '開啟聲音' : '靜音',
            icon: Icon(_flow.isMuted ? Icons.volume_off : Icons.volume_up))
      ],
      body: SafeArea(
        child: _started ? _body(beat) : _startPanel(),
      ),
    );
  }

  Widget _body(NightMarketBeat? beat) {
    if (beat == null) return const SizedBox.shrink();
    final controller = _video;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (!beat.textOnly)
          GestureDetector(
            onTap: _togglePlayback,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: controller != null &&
                      controller.value.isInitialized &&
                      !_failed
                  ? VideoPlayer(controller)
                  : beat.posterAsset != null
                      ? Image.asset(
                          beat.posterAsset!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: AppColors.brandInk,
                            child: Center(
                              child: Text(
                                _failed ? '影片暫時無法播放，仍可閱讀情境。' : '載入中…',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        )
                      : ColoredBox(
                          color: AppColors.brandInk,
                          child: Center(
                            child: Text(
                              _failed ? '影片暫時無法播放，仍可閱讀情境。' : '載入中…',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
            ),
          ),
        if (!beat.textOnly && !_failed && !_flow.videoCompleted)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _togglePlayback,
              icon: Icon(_pausedByUser ? Icons.play_arrow : Icons.pause),
              label: Text(_pausedByUser ? '繼續播放' : '暫停'),
            ),
          ),
        ...[
          if (controller != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (_, __, ___) => _captionBlock(beat),
            )
          else
            _captionBlock(beat),
          if (beat.hint != null &&
              _flow.hintVisible &&
              _flow.videoCompleted &&
              beat.choices.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(beat.hint!,
                    style: const TextStyle(
                        color: AppColors.ctaStart, height: 1.35))),
          if (beat.hint != null &&
              _flow.videoCompleted &&
              beat.choices.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _flow = _flow.copyWith(
                      hintVisible: !_flow.hintVisible,
                    )),
                child: Text(_flow.hintVisible ? '隱藏提示' : '顯示提示'),
              ),
            ),
          if (_flow.videoCompleted && beat.choices.isNotEmpty) ...[
            for (final choice in beat.choices)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: FilledButton(
                      onPressed: () => _choose(choice),
                      child: Text(choice.label))),
          ],
          if (_voiceFailed)
            TextButton(
              onPressed: () => _finishVoice(_audioToken),
              child: const Text('語音暫時無法播放，閱讀後繼續'),
            ),
          if (_failed)
            Wrap(spacing: 8, children: [
              OutlinedButton(
                  onPressed: _retryCount < 2
                      ? () {
                          _retryCount++;
                          _loadBeat(beat.id);
                        }
                      : null,
                  child: const Text('重試影片')),
              TextButton(
                  onPressed: _continueByText, child: const Text('用文字繼續')),
            ]),
          if (beat.ending && _flow.videoCompleted) ...[
            _endingFeedback(),
            _methodCards(),
            _leahPracticeCta(),
          ],
        ],
      ],
    );
  }

  Widget _startPanel() {
    final poster = _scenario.beatById(_scenario.initialBeatId)?.posterAsset;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (poster != null)
          Image.asset(poster,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        const SizedBox(height: 20),
        const Text('台灣夜市・初次見面',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Sydney 會陪你練習。對話選項出現時，選你想說的。',
            style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.4)),
        const SizedBox(height: 20),
        FilledButton(onPressed: _start, child: const Text('開始情境')),
      ],
    );
  }

  Widget _captionBlock(NightMarketBeat beat) {
    final position = _video?.value.position ?? Duration.zero;
    final active = beat.captions.where((caption) {
      return position >= caption.start && position < caption.end;
    }).toList(growable: false);
    final captions = _failed || _readingFallback
        ? beat.captions
        : _flow.videoCompleted && beat.captions.isNotEmpty
            ? [beat.captions.last]
            : active;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        _audioPhase
            ? '你：${_activeChoiceText ?? ''}'
            : captions.map((caption) {
                final speaker = switch (caption.speaker) {
                  NightMarketSpeaker.coach => 'Sydney',
                  NightMarketSpeaker.npc => 'Leah',
                  NightMarketSpeaker.user => '你',
                  NightMarketSpeaker.vendor => '攤主',
                };
                return '$speaker：${caption.text}';
              }).join('\n'),
        style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.35),
      ),
    );
  }

  Widget _endingFeedback() {
    final ids = _flow.selectedChoiceIds.toSet();
    final feedback = ids.contains('invite_craft_stall')
        ? '你先接住她對手作的興趣，再提出一起逛攤位；邀約有共同話題，也留了自然的選擇空間。可以再練習把邀約說得更短。'
        : ids.contains('offer_contact')
            ? '你回應她現在很忙，只提出一次聯絡方式就收住；下一次也可以先確認她是否方便再開口。'
            : ids.contains('keepwalking')
                ? '這次先繼續逛也可以。回想讓你猶豫的是怕打擾，還是擔心被拒絕？下次先觀察對方是否方便，再決定要不要打招呼。'
                : ids.contains('leave_available')
                    ? '你選擇在聊得愉快時收尾；有興趣也可以回應她剛提的手作攤。'
                    : ids.contains('respect_busy_bye')
                        ? '你注意到當下的時間與意願，讓對方能自在離開，也守住自己的步調。'
                        : ids.contains('ask_demographics')
                            ? '她剛問你做什麼，你卻跳去問年齡。下一次先回答她，再分享一小段自己。'
                            : ids.contains('pressure_wait')
                                ? '她還沒有說要走，你就先要她留下。下一次簡短介紹自己，再留空間讓她接話。'
                                : ids.contains('challenge_sales')
                                    ? '她問你是不是推銷，你把問題丟了回去。下一次先回答來意疑慮，語氣可以輕鬆，不必自證。'
                                    : ids.contains('answer_intent')
                                        ? '你有回答她的疑慮，也把自己的來意說清楚了；下一次可以把回應再收短一點。'
                                        : '你有根據現場資訊決定下一步；回看時留意對方的時間與回應，再選一個自然的接法。';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        feedback,
        style: const TextStyle(color: AppColors.ctaStart, height: 1.4),
      ),
    );
  }

  Widget _methodCards() {
    const methods = <({String id, String title, String prompt})>[
      (id: '1', title: '開場', prompt: '先說你觀察到的現場，再簡短說明來意。'),
      (id: '11', title: '傾聽', prompt: '先回應她實際分享的資訊，再接一個相關問題。'),
      (id: '21', title: '低壓邀約', prompt: '把活動、時間感和可拒絕空間放進一句話。'),
    ];
    return Column(
      children: [
        for (final method in methods)
          Card(
            color: AppColors.brandSurface2,
            child: ListTile(
              title: Text(method.title,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(method.prompt,
                  style: const TextStyle(color: Colors.white70)),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => context.push('/article/${method.id}'),
                    child: const Text('讀心法'),
                  ),
                  TextButton(
                    onPressed: () => _replayFrom(switch (method.id) {
                      '1' => 'opening',
                      '11' => 'work',
                      _ => 'call',
                    }),
                    child: const Text('重練'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('小練習：她說朋友快到了，你會怎麼做？',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        Row(children: [
          Expanded(
              child: OutlinedButton(
            onPressed: () => setState(() => _methodAnswer = 'respect'),
            child: const Text('先尊重她的安排'),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: OutlinedButton(
            onPressed: () => setState(() => _methodAnswer = 'pressure'),
            child: const Text('追問她一定要走嗎'),
          )),
        ]),
        if (_methodAnswer != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _methodAnswer == 'respect'
                  ? '對，先確認對方時間與意願，再決定要不要提出下一步。'
                  : '可以再練習留一點空間：清楚表達想法，也讓對方容易拒絕。',
              style: const TextStyle(color: AppColors.ctaStart, height: 1.35),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _switchTimeVariant,
          child: Text(_variant == NightMarketRunVariant.available
              ? '試試另一種時間情境（忙碌）'
              : '試試另一種時間情境（有空）'),
        ),
      ],
    );
  }

  Widget _leahPracticeCta() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton(
        onPressed: () =>
            context.push('/practice-chat?profileId=practice_girl_078'),
        child: const Text('開啟 Leah 文字陪練'),
      ),
    );
  }
}

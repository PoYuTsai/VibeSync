// The fake drives the locked audioplayers platform boundary directly; keep
// this test-only transitive import explicit without adding a runtime package.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vibesync/features/night_market/domain/night_market_scenario.dart';
import 'package:vibesync/features/night_market/presentation/screens/night_market_screen.dart';

import '../../../helpers/fake_sydney_video_platform.dart';

class _RegressionVideoPlatform extends FakeSydneyVideoPlatform {
  final positions = <int, Duration>{};
  final _initTimers = <Timer>[];

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final previousAutoInitialize = autoInitialize;
    autoInitialize = false;
    final id = await super.createWithOptions(options);
    autoInitialize = previousAutoInitialize;
    // The base fake emits initialized inside createWithOptions, before the
    // real controller installs its event subscription. Delay it one event
    // turn so this test exercises the actual controller boundary.
    final playerId = id!;
    if (!failInitialization) {
      _initTimers
          .add(Timer(Duration.zero, () => finishInitialization(playerId)));
    }
    return id;
  }

  @override
  void finishInitialization(int id) {
    streams[id]!.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 10),
      size: const Size(1280, 720),
    ));
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Future<void> play(int playerId) async {
    await super.play(playerId);
  }

  @override
  void close() {
    for (final timer in _initTimers) {
      timer.cancel();
    }
    super.close();
  }
}

class _FakeAudioPlatform extends AudioplayersPlatformInterface {
  final streams = <String, StreamController<AudioEvent>>{};
  final sourceUrls = <String, String>{};
  final pauseCalls = <String>[];
  final resumeCalls = <String>[];

  @override
  Future<void> create(String playerId) async {
    streams[playerId] = StreamController<AudioEvent>();
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      streams[playerId]!.stream;

  void complete(String playerId) {
    assert(streams[playerId]!.hasListener,
        'audio player $playerId must have native event listener');
    streams[playerId]!
        .add(const AudioEvent(eventType: AudioEventType.complete));
  }

  void error(String playerId) {
    assert(streams[playerId]!.hasListener,
        'audio player $playerId must have native event listener');
    streams[playerId]!.addError(StateError('test voice stream failure'));
  }

  @override
  Future<void> dispose(String playerId) async => streams[playerId]?.close();
  @override
  Future<void> pause(String playerId) async {
    pauseCalls.add(playerId);
  }

  @override
  Future<void> stop(String playerId) async {}
  @override
  Future<void> resume(String playerId) async {
    resumeCalls.add(playerId);
  }

  @override
  Future<void> release(String playerId) async {}
  @override
  Future<void> seek(String playerId, Duration position) async {}
  @override
  Future<void> setBalance(String playerId, double balance) async {}
  @override
  Future<void> setVolume(String playerId, double volume) async {}
  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}
  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}
  @override
  Future<void> setSourceUrl(String playerId, String url,
      {bool? isLocal, String? mimeType}) async {
    sourceUrls[playerId] = url;
    streams[playerId]!.add(const AudioEvent(
      eventType: AudioEventType.prepared,
      isPrepared: true,
    ));
  }

  @override
  Future<void> setSourceBytes(String playerId, Uint8List bytes,
      {String? mimeType}) async {}
  @override
  Future<void> setAudioContext(
      String playerId, AudioContext audioContext) async {}
  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}
  @override
  Future<int?> getDuration(String playerId) async => 1000;
  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;
  @override
  Future<void> emitLog(String playerId, String message) async {}
  @override
  Future<void> emitError(String playerId, String code, String message) async {}
}

class _FakeAudioCache extends AudioCache {
  @override
  Future<String> loadPath(String fileName) async => '/tmp/$fileName';
}

class _FakeGlobalAudioPlatform extends GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}
  @override
  Future<void> emitGlobalLog(String message) async {}
  @override
  Future<void> emitGlobalError(String code, String message) async {}
}

Future<void> _start(
  WidgetTester tester, {
  NightMarketRunVariant variant = NightMarketRunVariant.available,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: KeyedSubtree(
          key: UniqueKey(), child: NightMarketScreen(variant: variant))));
  for (var turn = 0;
      turn < 10 && find.text('開始情境').evaluate().isEmpty;
      turn++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.scrollUntilVisible(find.text('開始情境'), 200, maxScrolls: 12);
  await tester.tap(find.text('開始情境'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _completeCurrent(
  WidgetTester tester,
  _RegressionVideoPlatform platform,
) async {
  if (find.text('用文字繼續').evaluate().isNotEmpty) {
    await tester.tap(find.text('用文字繼續'));
    await tester.pump(const Duration(seconds: 1));
    return;
  }
  final id = platform.creations.length - 1;
  for (var turn = 0;
      turn < 10 && platform.playCalls.where((v) => v == id).isEmpty;
      turn++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(platform.playCalls, contains(id),
      reason: 'controller $id must play before completion');
  // Emit the platform completion event and make the real controller's
  // pause().then(seekTo(duration)) update the native position.
  platform.positions[id] = const Duration(seconds: 10);
  platform.streams[id]!.add(VideoEvent(eventType: VideoEventType.completed));
  final oldCreationCount = platform.creations.length;
  for (var turn = 0; turn < 10; turn++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (platform.creations.length > oldCreationCount) break;
  }
}

Future<void> _tapChoice(
  WidgetTester tester,
  _RegressionVideoPlatform platform,
  _FakeAudioPlatform audio,
  String text, {
  String? expectedVoiceId,
}) async {
  final before = platform.creations.length;
  final resumeBefore = audio.resumeCalls.length;
  final finder = find.text(text);
  for (var turn = 0; turn < 20 && finder.evaluate().isEmpty; turn++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.scrollUntilVisible(finder, 200, maxScrolls: 10);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  var signaledAudio = false;
  String? voicePlayerReady;
  for (var turn = 0; turn < 50; turn++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (!signaledAudio && expectedVoiceId != null) {
      if (voicePlayerReady != null) {
        audio.complete(voicePlayerReady);
        signaledAudio = true;
        continue;
      }
      for (final entry in audio.sourceUrls.entries) {
        final expectedSource = entry.value.endsWith('/$expectedVoiceId.mp3') ||
            entry.value.endsWith('$expectedVoiceId.mp3');
        final resumedAfterTap = audio.resumeCalls.indexWhere(
              (playerId) => playerId == entry.key,
              resumeBefore,
            ) >=
            resumeBefore;
        if (expectedSource && resumedAfterTap) {
          voicePlayerReady = entry.key;
          break;
        }
      }
    }
    if (platform.creations.length > before) break;
  }
  expect(platform.creations.length, greaterThan(before),
      reason:
          'choice transition must wait for audio completion then load next beat; '
          'sourceUrls=${audio.sourceUrls}, resumeCalls=${audio.resumeCalls}');
}

void main() {
  late _RegressionVideoPlatform platform;
  late _FakeAudioPlatform audio;
  late VideoPlayerPlatform previous;
  late AudioplayersPlatformInterface previousAudio;
  late GlobalAudioplayersPlatformInterface previousGlobalAudio;
  late AudioCache previousCache;

  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = _RegressionVideoPlatform()..autoInitialize = false;
    VideoPlayerPlatform.instance = platform;
    previousAudio = AudioplayersPlatformInterface.instance;
    previousGlobalAudio = GlobalAudioplayersPlatformInterface.instance;
    audio = _FakeAudioPlatform();
    AudioplayersPlatformInterface.instance = audio;
    GlobalAudioplayersPlatformInterface.instance = _FakeGlobalAudioPlatform();
    previousCache = AudioCache.instance;
    AudioCache.instance = _FakeAudioCache();
  });

  tearDown(() {
    platform.close();
    VideoPlayerPlatform.instance = previous;
    AudioplayersPlatformInterface.instance = previousAudio;
    GlobalAudioplayersPlatformInterface.instance = previousGlobalAudio;
    AudioCache.instance = previousCache;
  });

  testWidgets('available branch reaches ending after selecting its choices',
      (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await _start(tester);
    expect(find.text('走到她看得到的側前方'), findsNothing);
    await _completeCurrent(tester, platform);
    expect(platform.creations, hasLength(2));
    expect(platform.creations[1].dataSource.asset,
        'assets/videos/night_market/hesitate.mp4');
    await _completeCurrent(tester, platform);
    expect(platform.playing[1], isFalse);
    expect(platform.positions[1], const Duration(seconds: 10));
    await _tapChoice(tester, platform, audio, '走到她看得到的側前方');
    expect(platform.creations, hasLength(3));
    expect(platform.creations[2].dataSource.asset,
        'assets/videos/night_market/opening.mp4');
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '我叫阿澤，剛下班來逛逛。',
        expectedVoiceId: 'introduce');
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '不是，我沒有東西要賣；就是想跟妳聊兩句。',
        expectedVoiceId: 'answer_intent');
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '我做產品設計，把亂的東西整理成好用的流程。妳呢？',
        expectedVoiceId: 'share_product_design');
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '現在拿來放筆了，放在桌上剛剛好。',
        expectedVoiceId: 'share_pen_holder');
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '今天第一個。',
        expectedVoiceId: 'first_today');
    await _completeCurrent(tester, platform);
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '要不要去旁邊逛兩分鐘手作攤？',
        expectedVoiceId: 'invite_craft_stall');
    await _completeCurrent(tester, platform);
    expect(platform.creations.last.dataSource.asset,
        'assets/videos/night_market/decline.mp4');
    await _completeCurrent(tester, platform);
    await _completeCurrent(tester, platform);
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(find.text('低壓邀約'), 200, maxScrolls: 12);
    expect(
      find.text('低壓邀約'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('keepwalking reaches text-only ending without coach video',
      (tester) async {
    await _start(tester);
    await _completeCurrent(tester, platform);
    await _completeCurrent(tester, platform);
    final keepWalking = find.text('先繼續逛夜市');
    final approach = find.text('走到她看得到的側前方');
    await tester.scrollUntilVisible(approach, 200, maxScrolls: 10);
    await tester.scrollUntilVisible(keepWalking, 200, maxScrolls: 10);
    await tester.tap(keepWalking);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(find.text('小練習：她說朋友快到了，你會怎麼做？'), 200,
        maxScrolls: 12);
    expect(find.text('小練習：她說朋友快到了，你會怎麼做？'), findsOneWidget);
    expect(platform.creations, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('busy branch waits through contact before coach ending',
      (tester) async {
    await _start(tester, variant: NightMarketRunVariant.busy);
    await _completeCurrent(tester, platform);
    await _completeCurrent(tester, platform);
    await tester.scrollUntilVisible(find.text('走到她看得到的側前方'), 200,
        maxScrolls: 10);
    await tester.tap(find.text('走到她看得到的側前方'));
    await tester.pump();
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '我叫阿澤，剛下班來逛逛。',
        expectedVoiceId: 'introduce');
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '不是，我沒有東西要賣；就是想跟妳聊兩句。',
        expectedVoiceId: 'answer_intent');
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '我做產品設計，把亂的東西整理成好用的流程。妳呢？',
        expectedVoiceId: 'share_product_design');
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '現在拿來放筆了，放在桌上剛剛好。',
        expectedVoiceId: 'share_pen_holder');
    await _completeCurrent(tester, platform);
    await _tapChoice(tester, platform, audio, '今天第一個。',
        expectedVoiceId: 'first_today');
    await _completeCurrent(tester, platform);
    await _completeCurrent(tester, platform);
    await tester.scrollUntilVisible(find.text('妳願意的話我留我的，改天喝無糖烏龍；不用現在回。'), 200,
        maxScrolls: 12);
    await _tapChoice(tester, platform, audio, '妳願意的話我留我的，改天喝無糖烏龍；不用現在回。',
        expectedVoiceId: 'offer_contact');
    await _completeCurrent(tester, platform);
    await _completeCurrent(tester, platform);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.scrollUntilVisible(find.text('低壓邀約'), 200, maxScrolls: 12);
    expect(find.text('低壓邀約'), findsOneWidget);
  });

  testWidgets('lifecycle pauses video and resumes active voice only',
      (tester) async {
    await _start(tester);
    await _completeCurrent(tester, platform);
    await _completeCurrent(tester, platform);
    await tester.scrollUntilVisible(find.text('走到她看得到的側前方'), 200,
        maxScrolls: 10);
    await tester.tap(find.text('走到她看得到的側前方'));
    await tester.pump();
    await _completeCurrent(tester, platform);
    final introduce = find.text('我叫阿澤，剛下班來逛逛。');
    await tester.scrollUntilVisible(introduce, 200, maxScrolls: 10);
    await tester.tap(introduce);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.creations, hasLength(3));
    final activeVideoId = platform.creations.length - 1;
    final videoPlaysBeforeBackground =
        platform.playCalls.where((id) => id == activeVideoId).length;
    final voiceId = audio.sourceUrls.entries
        .singleWhere((entry) => entry.value.endsWith('/introduce.mp3'))
        .key;
    final voiceResumeBefore =
        audio.resumeCalls.where((playerId) => playerId == voiceId).length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(platform.pauseCalls, contains(platform.creations.length - 1));
    expect(audio.pauseCalls, contains(voiceId));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      audio.resumeCalls.where((playerId) => playerId == voiceId).length,
      voiceResumeBefore + 1,
    );
    expect(platform.playCalls.where((id) => id == activeVideoId).length,
        videoPlaysBeforeBackground);
    audio.complete(voiceId);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.creations, hasLength(4));
  });

  testWidgets('failed opening can continue by text', (tester) async {
    platform.failInitialization = true;
    await _start(tester);
    for (var i = 0; i < 20 && find.text('用文字繼續').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('用文字繼續'), findsOneWidget);
    platform.failInitialization = false;
    await tester.tap(find.text('用文字繼續'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(platform.creations, hasLength(2));
    await _completeCurrent(tester, platform);
    await tester.scrollUntilVisible(find.text('走到她看得到的側前方'), 200,
        maxScrolls: 10);
    expect(find.text('走到她看得到的側前方'), findsOneWidget);
  });

  testWidgets('covered route pauses and pop resumes video', (tester) async {
    await _start(tester);
    final videoId = platform.creations.length - 1;
    final beforePause = platform.pauseCalls.length;
    final navigator =
        Navigator.of(tester.element(find.byType(NightMarketScreen)));
    unawaited(navigator.push(
        MaterialPageRoute<void>(builder: (_) => const SizedBox.expand())));
    await tester.pumpAndSettle();
    expect(platform.pauseCalls.length, greaterThan(beforePause));
    final beforePlay = platform.playCalls.where((id) => id == videoId).length;
    navigator.pop();
    await tester.pumpAndSettle();
    expect(platform.playCalls.where((id) => id == videoId).length,
        greaterThan(beforePlay));
  });

  testWidgets('2.5x keepwalking ending cards and CTA fit', (tester) async {
    await _start(tester, textScale: 2.5);
    await _completeCurrent(tester, platform);
    await _completeCurrent(tester, platform);
    await tester.scrollUntilVisible(find.text('走到她看得到的側前方'), 200,
        maxScrolls: 12);
    await tester.scrollUntilVisible(find.text('先繼續逛夜市'), 200, maxScrolls: 12);
    await tester.tap(find.text('先繼續逛夜市'));
    await tester.pump(const Duration(milliseconds: 100));
    final practice = find.text('小練習：她說朋友快到了，你會怎麼做？');
    await tester.scrollUntilVisible(practice, 200, maxScrolls: 20);
    expect(practice, findsOneWidget);
    expect(find.text('開場'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('開場'), 200, maxScrolls: 20);
    expect(find.text('開場'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('傾聽'), 200, maxScrolls: 20);
    expect(find.text('傾聽'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('低壓邀約'), 200, maxScrolls: 20);
    expect(find.text('低壓邀約'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('到圖鑑繼續文字陪練'), 200,
        maxScrolls: 20);
    expect(find.text('到圖鑑繼續文字陪練'), findsOneWidget);
  });

  testWidgets('stuck video help shows full captions and advances by text',
      (tester) async {
    await _start(tester);
    expect(platform.creations, hasLength(1));
    final help = find.text('播放卡住了？');
    await tester.scrollUntilVisible(help, 200, maxScrolls: 10);
    await tester.tap(help);
    await tester.pump();
    expect(find.textContaining('前面有一家手作攤。'), findsOneWidget);
    expect(find.text('用文字繼續'), findsOneWidget);
    await tester.tap(find.text('用文字繼續'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(platform.creations, hasLength(2));
    expect(platform.creations[1].dataSource.asset,
        'assets/videos/night_market/hesitate.mp4');
  });

  testWidgets('voice playback failure can continue into next video',
      (tester) async {
    await _start(tester);
    await _completeCurrent(tester, platform);
    await _completeCurrent(tester, platform);
    await tester.scrollUntilVisible(find.text('走到她看得到的側前方'), 200,
        maxScrolls: 10);
    await tester.tap(find.text('走到她看得到的側前方'));
    await tester.pump();
    await _completeCurrent(tester, platform);
    final introduce = find.text('我叫阿澤，剛下班來逛逛。');
    await tester.scrollUntilVisible(introduce, 200, maxScrolls: 10);
    await tester.tap(introduce);
    String? voicePlayer;
    for (var turn = 0; turn < 20 && voicePlayer == null; turn++) {
      await tester.pump(const Duration(milliseconds: 20));
      for (final entry in audio.sourceUrls.entries) {
        if (entry.value.endsWith('/introduce.mp3')) voicePlayer = entry.key;
      }
    }
    expect(voicePlayer, isNotNull);
    audio.error(voicePlayer!);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('語音暫時無法播放，閱讀後繼續'), findsOneWidget);
    await tester.tap(find.text('語音暫時無法播放，閱讀後繼續'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(platform.creations, hasLength(4));
    expect(platform.creations[3].dataSource.asset,
        'assets/videos/night_market/concern.mp4');
  });

  testWidgets('stuck voice exposes playback help and reading continuation',
      (tester) async {
    await _start(tester);
    await _completeCurrent(tester, platform);
    await _completeCurrent(tester, platform);
    await tester.scrollUntilVisible(find.text('走到她看得到的側前方'), 200,
        maxScrolls: 10);
    await tester.tap(find.text('走到她看得到的側前方'));
    await tester.pump();
    await _completeCurrent(tester, platform);
    final introduce = find.text('我叫阿澤，剛下班來逛逛。');
    await tester.scrollUntilVisible(introduce, 200, maxScrolls: 10);
    await tester.tap(introduce);
    String? voicePlayer;
    for (var turn = 0; turn < 20 && voicePlayer == null; turn++) {
      await tester.pump(const Duration(milliseconds: 20));
      for (final entry in audio.sourceUrls.entries) {
        if (entry.value.endsWith('/introduce.mp3')) voicePlayer = entry.key;
      }
    }
    expect(voicePlayer, isNotNull);
    expect(platform.creations, hasLength(3),
        reason: 'stalled voice must not create the next video early');
    // Deliberately emit neither complete nor error: the user must still have
    // an escape hatch from a native player that stalls indefinitely.
    expect(find.text('播放卡住了？'), findsOneWidget);
    await tester.tap(find.text('播放卡住了？'));
    await tester.pump();
    expect(find.text('語音暫時無法播放，閱讀後繼續'), findsOneWidget);
    await tester.tap(find.text('語音暫時無法播放，閱讀後繼續'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(platform.creations, hasLength(4));
    expect(platform.creations[3].dataSource.asset,
        'assets/videos/night_market/concern.mp4');
  });
}

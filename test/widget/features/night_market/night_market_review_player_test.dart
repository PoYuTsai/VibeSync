import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vibesync/features/night_market/data/night_market_story.dart';
import 'package:vibesync/features/night_market/presentation/screens/night_market_review_player.dart';

import '../../../helpers/fake_sydney_video_platform.dart';

class _ReviewVideoPlatform extends FakeSydneyVideoPlatform {
  final positions = <int, Duration>{};
  final seeks = <(int, Duration)>[];

  @override
  void finishInitialization(int id) {
    streams[id]!.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 90),
      size: const Size(540, 960),
    ));
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add((playerId, position));
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;
}

Future<void> _advance(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late _ReviewVideoPlatform platform;
  late VideoPlayerPlatform previous;

  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = _ReviewVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() {
    platform.close();
    VideoPlayerPlatform.instance = previous;
  });

  Future<void> show(WidgetTester tester, int chapter) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scenario = buildNightMarketScenario();
    await tester.pumpWidget(MaterialApp(
        home: NightMarketReviewPlayer(
      scenario: scenario,
      chapter: scenario.reviewChapters[chapter],
    )));
    await _advance(tester);
  }

  testWidgets('seeks to the chapter start and stops at the excerpt end',
      (tester) async {
    await show(tester, 1);
    expect(platform.creations.single.dataSource.asset,
        endsWith('s2_opening_to_craft.mp4'));
    expect(platform.seeks.single.$2, const Duration(milliseconds: 11150));
    expect(platform.playing[0], isTrue);
    // 位置通知晚於終點 300ms：要暫停並拉回片段末端，不停在下一章畫面。
    platform.positions[0] = const Duration(milliseconds: 23471);
    await _advance(tester);
    expect(platform.playing[0], isFalse);
    expect(platform.seeks.last.$2, const Duration(milliseconds: 23171));
    expect(platform.positions[0], const Duration(milliseconds: 23171));
    expect(find.text('再看一次'), findsOneWidget);
    expect(platform.creations, hasLength(1));
    await tester.tap(find.text('再看一次'));
    await _advance(tester);
    expect(platform.seeks.last.$2, const Duration(milliseconds: 11150));
    expect(platform.disposed, contains(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await _advance(tester);
    expect(platform.playing[1], isFalse);
    expect(platform.disposed, contains(1));
  });

  testWidgets(
      'chapter spanning two assets continues then stops without choices',
      (tester) async {
    await show(tester, 0);
    platform.positions[0] = const Duration(milliseconds: 13250);
    await _advance(tester);
    expect(platform.creations, hasLength(2));
    expect(platform.creations[1].dataSource.asset,
        endsWith('s2_opening_to_craft.mp4'));
    expect(platform.disposed, contains(0));
    expect(platform.playing[1], isTrue);
    platform.positions[1] = const Duration(milliseconds: 11150);
    await _advance(tester);
    expect(find.text('再看一次'), findsOneWidget);
    expect(platform.playing[1], isFalse);
    expect(platform.creations, hasLength(2));
  });

  testWidgets('background pauses and foreground waits for an explicit play',
      (tester) async {
    await show(tester, 5);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _advance(tester);
    expect(platform.playing[0], isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _advance(tester);
    expect(platform.playing[0], isFalse);
    await tester.tap(find.text('繼續播放'));
    await _advance(tester);
    expect(platform.playing[0], isTrue);
  });

  testWidgets('initialization finishing in background does not start audio',
      (tester) async {
    platform.autoInitialize = false;
    await show(tester, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    platform.finishInitialization(0);
    await _advance(tester);
    expect(platform.playCalls, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _advance(tester);
    expect(platform.playCalls, isEmpty);
  });

  testWidgets('leaving during initialization disposes the pending player',
      (tester) async {
    platform.autoInitialize = false;
    await show(tester, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    platform.finishInitialization(0);
    await _advance(tester);
    expect(platform.playCalls, isEmpty);
    expect(platform.disposed, contains(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('foreground return during loading still waits for a tap',
      (tester) async {
    platform.autoInitialize = false;
    await show(tester, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    platform.finishInitialization(0);
    await _advance(tester);
    expect(platform.playCalls, isEmpty);
    await tester.tap(find.text('繼續播放'));
    await _advance(tester);
    expect(platform.playing[0], isTrue);
  });

  testWidgets('failed play can retry at the same excerpt start',
      (tester) async {
    platform.failPlay = true;
    await show(tester, 4);
    expect(find.text('影片暫時無法播放'), findsOneWidget);
    platform.failPlay = false;
    await tester.tap(find.text('重試'));
    await _advance(tester);
    expect(platform.seeks.last.$2, const Duration(milliseconds: 32521));
    expect(platform.playing[1], isTrue);
  });

  testWidgets(
      'initialization that never completes eventually shows the failed state',
      (tester) async {
    platform.autoInitialize = false;
    await show(tester, 3);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Never call platform.finishInitialization(0): initialize() hangs and
    // only the 12s Future.any(...).timeout in _load should end the wait.
    await tester.pump(const Duration(seconds: 13));
    await _advance(tester);
    expect(find.text('影片暫時無法播放'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
  });

  testWidgets('leaving the screen mid-timeout does not throw or leak state',
      (tester) async {
    platform.autoInitialize = false;
    await show(tester, 3);
    // Leave partway through the 12s wait, while _initializationCancelled is
    // still pending, to exercise _cancelInitialization() from dispose().
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 13));
    await _advance(tester);
    expect(tester.takeException(), isNull);
    expect(platform.disposed, contains(0));
  });
}

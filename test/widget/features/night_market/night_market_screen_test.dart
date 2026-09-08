import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vibesync/features/night_market/presentation/screens/night_market_screen.dart';

import '../../../helpers/fake_sydney_video_platform.dart';

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _pumpStarted(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: NightMarketScreen()));
  await tester.tap(find.text('開始'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
}

/// Emits the platform completion event for the newest controller and pumps
/// until the screen reacts.
Future<void> _complete(WidgetTester tester, FakeSydneyVideoPlatform p) async {
  final id = p.creations.length - 1;
  p.streams[id]!.add(VideoEvent(eventType: VideoEventType.completed));
  for (var turn = 0; turn < 10; turn++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakeSydneyVideoPlatform platform;
  late VideoPlayerPlatform previous;

  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = FakeSydneyVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() {
    platform.close();
    VideoPlayerPlatform.instance = previous;
  });

  testWidgets('start panel names the run; 開始 loads the first bundled video',
      (tester) async {
    await _pumpStarted(tester);
    expect(platform.creations, hasLength(1));
    expect(platform.creations.single.dataSource.asset,
        'assets/videos/night_market/s1_notice.mp4');
    expect(platform.playing[0], isTrue);
    // No captions, hint or choices while the video plays.
    expect(find.text('等我一下，我看一下這個。'), findsNothing);
    expect(find.textContaining('確信感'), findsNothing);
  });

  testWidgets('tap pauses/resumes; background pauses and stays paused',
      (tester) async {
    await _pumpStarted(tester);
    await tester.tap(find.byType(VideoPlayer));
    await tester.pump();
    expect(platform.playing[0], isFalse);
    await tester.tap(find.byType(VideoPlayer));
    await tester.pump();
    expect(platform.playing[0], isTrue);
    await _lifecycle(tester, AppLifecycleState.inactive);
    expect(platform.playing[0], isFalse);
    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(platform.playing[0], isFalse);
  });

  testWidgets(
      'stop point: wrong choice shows coach card then continues; ending shows review',
      (tester) async {
    await _pumpStarted(tester);
    await _complete(tester, platform);
    expect(find.textContaining('確信感'), findsOneWidget);
    await tester.tap(find.text('等她逛到我旁邊再說'));
    await tester.pump();
    expect(find.textContaining('等時機'), findsOneWidget);
    expect(platform.creations, hasLength(1));
    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(platform.creations, hasLength(2));
    expect(platform.creations[1].dataSource.asset,
        'assets/videos/night_market/s2_opening_to_craft.mp4');
    expect(platform.disposed, contains(0));

    await _complete(tester, platform);
    await tester.tap(find.textContaining('我之前也去過一次'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(platform.creations, hasLength(3));

    await _complete(tester, platform);
    expect(find.text('復盤'), findsOneWidget);
    expect(find.text('下次只記這個：強眼神溝通。', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('淺溝通＋強眼神溝通'), findsOneWidget);
    // 「更多技巧」是揭示膠囊：收合時不列出次要技巧。
    expect(find.text('更多技巧', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('第一分鐘破防', skipOffstage: false), findsNothing);
    await tester.scrollUntilVisible(find.text('再練一次'), 300);
    await tester.tap(find.text('再練一次'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(platform.creations, hasLength(4));
    expect(platform.creations[3].dataSource.asset,
        'assets/videos/night_market/s1_notice.mp4');
  });

  testWidgets('captions toggle shows the timed line only when on',
      (tester) async {
    await _pumpStarted(tester);
    await tester.tap(find.byTooltip('顯示字幕'));
    await tester.pump();
    // Fake position stays at zero; the first S1 line starts at 3.64s.
    expect(find.textContaining('等我一下'), findsNothing);
  });

  testWidgets('failed video offers retry instead of a blank screen',
      (tester) async {
    platform.failInitialization = true;
    await _pumpStarted(tester);
    expect(find.text('影片暫時無法播放'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
  });
}

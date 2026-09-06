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

  testWidgets('首屏有說明，開始後建立 bundle video 並可手動 pause/resume', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: NightMarketScreen()));
    expect(find.text('台灣夜市・初次見面'), findsOneWidget);
    expect(find.text('Sydney 會陪你練習。對話選項出現時，選你想說的。'), findsOneWidget);
    await tester.tap(find.text('開始情境'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(platform.creations, hasLength(1));
    expect(
        platform.creations.single.dataSource.sourceType, DataSourceType.asset);
    await tester.tap(find.byType(VideoPlayer));
    await tester.pump();
    expect(platform.playing[0], isFalse);
    await tester.tap(find.byType(VideoPlayer));
    await tester.pump();
    expect(platform.playing[0], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(platform.disposed, contains(0));
  });

  testWidgets(
      'background pauses and resume restores playback unless manually paused',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: NightMarketScreen()));
    await tester.scrollUntilVisible(find.text('開始情境'), 200, maxScrolls: 12);
    await tester.tap(find.text('開始情境'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await _lifecycle(tester, AppLifecycleState.inactive);
    expect(platform.playing[0], isFalse);
    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(platform.playing[0], isTrue);
    await tester.tap(find.byType(VideoPlayer));
    await tester.pump();
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(platform.playing[0], isFalse);
  });

  testWidgets('large text still renders the start content without overflow',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.5)),
          child: child!,
        ),
        home: const NightMarketScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('台灣夜市・初次見面'), findsOneWidget);
    expect(
        MediaQuery.textScalerOf(tester.element(find.text('台灣夜市・初次見面')))
            .scale(10),
        25);
    expect(tester.takeException(), isNull);
  });
}

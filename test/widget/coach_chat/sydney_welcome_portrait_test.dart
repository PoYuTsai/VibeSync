import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/sydney_welcome_portrait.dart';

import '../../helpers/fake_sydney_video_platform.dart';

/// A self-contained image fixture keeps these lifecycle tests independent of
/// generated assets or local build output. The real asset path is asserted below.
class _PosterBundle extends CachingAssetBundle {
  static final _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object?>{})!;
    }
    if (key == SydneyWelcomePortrait.posterAsset) {
      return ByteData.sublistView(_pixel);
    }
    throw StateError('Unexpected asset in Sydney test: $key');
  }
}

class _Harness {
  _Harness({bool reduceMotion = false}) : reduced = ValueNotifier(reduceMotion);

  final ValueNotifier<bool> reduced;
  final tickers = ValueNotifier(true);
  final navigator = GlobalKey<NavigatorState>();
  final bundle = _PosterBundle();

  Widget build() => MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => DefaultAssetBundle(
          bundle: bundle,
          child: ValueListenableBuilder<bool>(
            valueListenable: reduced,
            builder: (context, reduceMotion, _) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: ValueListenableBuilder<bool>(
                valueListenable: tickers,
                builder: (context, enabled, _) => TickerMode(
                  enabled: enabled,
                  child: child!,
                ),
              ),
            ),
          ),
        ),
        home: const Scaffold(
          body: Column(
            children: [
              Center(
                child: SizedBox(
                  height: 240,
                  child: SydneyWelcomePortrait(),
                ),
              ),
              TextField(key: Key('coach-input')),
            ],
          ),
        ),
      );

  void dispose() {
    reduced.dispose();
    tickers.dispose();
  }
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump();
}

Finder get _poster => find.byWidgetPredicate((widget) =>
    widget is Image &&
    widget.image is AssetImage &&
    (widget.image as AssetImage).assetName ==
        SydneyWelcomePortrait.posterAsset);

void portraitTest(
    String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, body,
      variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
  await _flush(tester);
}

void main() {
  late FakeSydneyVideoPlatform platform;
  late VideoPlayerPlatform previousPlatform;

  setUp(() {
    previousPlatform = VideoPlayerPlatform.instance;
    platform = FakeSydneyVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() {
    platform.close();
    VideoPlayerPlatform.instance = previousPlatform;
  });

  Future<_Harness> mount(
    WidgetTester tester, {
    bool reduceMotion = false,
    AppLifecycleState initialLifecycle = AppLifecycleState.resumed,
  }) async {
    await _lifecycle(tester, initialLifecycle);
    final harness = _Harness(reduceMotion: reduceMotion);
    await tester.pumpWidget(harness.build());
    await _flush(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _flush(tester);
      harness.dispose();
    });
    return harness;
  }

  portraitTest('V3 使用本機資產、靜音循環並保持完整 9:16', (tester) async {
    await mount(tester);

    expect(platform.creations, hasLength(1));
    expect(
        platform.creations.single.dataSource.sourceType, DataSourceType.asset);
    expect(platform.creations.single.dataSource.asset,
        SydneyWelcomePortrait.videoAsset);
    expect(platform.volumes[0], 0);
    expect(platform.looping[0], isTrue);
    expect(platform.preventsDisplaySleep[0], isFalse);
    expect(platform.playing[0], isTrue);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(_poster, findsNothing);
    final rect = tester.getRect(find.byType(VideoPlayer));
    expect(rect.height, 240);
    expect(rect.width / rect.height, closeTo(9 / 16, 0.001));
    expect(tester.takeException(), isNull);
  });

  portraitTest('手動暫停後經背景及返回仍暫停，主動播放才恢復', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('暫停 Sydney 動畫'));
    await _flush(tester);
    final playsBeforeBackground = platform.playCalls.length;

    await _lifecycle(tester, AppLifecycleState.paused);
    await _flush(tester);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _flush(tester);

    expect(platform.playing[0], isFalse);
    expect(platform.playCalls.length, playsBeforeBackground);
    expect(find.byTooltip('播放 Sydney 動畫'), findsOneWidget);
    await tester.tap(find.byTooltip('播放 Sydney 動畫'));
    await _flush(tester);
    expect(platform.playing[0], isTrue);
  });

  portraitTest('所有非 resumed 生命週期都停播，回前景才恢復', (tester) async {
    await mount(tester);
    for (final state in AppLifecycleState.values
        .where((state) => state != AppLifecycleState.resumed)) {
      await _lifecycle(tester, state);
      await _flush(tester);
      expect(platform.playing[0], isFalse, reason: '$state');
      await _lifecycle(tester, AppLifecycleState.resumed);
      await _flush(tester);
      expect(platform.playing[0], isTrue, reason: 'return from $state');
    }
  });

  portraitTest('透明路由蓋住入口也停播，返回時恢復同一播放器', (tester) async {
    final harness = await mount(tester);
    unawaited(harness.navigator.currentState!.push<void>(PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) =>
          const Center(child: Text('覆蓋入口')),
    )));
    await _flush(tester);
    expect(platform.playing[0], isFalse);
    harness.navigator.currentState!.pop();
    await _flush(tester);
    expect(platform.playing[0], isTrue);
    expect(platform.creations, hasLength(1));
  });

  portraitTest('TickerMode 和減少動態會停播，還原偏好才恢復', (tester) async {
    final harness = await mount(tester);
    harness.tickers.value = false;
    await _flush(tester);
    expect(platform.playing[0], isFalse);
    harness.tickers.value = true;
    await _flush(tester);
    expect(platform.playing[0], isTrue);

    harness.reduced.value = true;
    await _flush(tester);
    expect(platform.playing[0], isFalse);
    expect(_poster, findsOneWidget);
    harness.reduced.value = false;
    await _flush(tester);
    expect(platform.playing[0], isTrue);
    expect(platform.creations, hasLength(1));
  });

  portraitTest('初始減少動態只顯示 poster，不配置 decoder，關閉後才建立', (tester) async {
    final harness = await mount(tester, reduceMotion: true);
    expect(platform.creations, isEmpty);
    expect(_poster, findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);

    harness.reduced.value = false;
    await _flush(tester);
    expect(platform.creations, hasLength(1));
    expect(platform.playing[0], isTrue);
  });

  portraitTest('初始未回到前景不配置 decoder，resumed 後才開始', (tester) async {
    await mount(tester, initialLifecycle: AppLifecycleState.inactive);
    expect(platform.creations, isEmpty);
    expect(_poster, findsOneWidget);
    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(platform.creations, hasLength(1));
    expect(platform.playing[0], isTrue);
  });

  portraitTest('初始化尚未完成就進背景，晚到 initialized 不會偷播', (tester) async {
    platform.autoInitialize = false;
    await mount(tester);
    await _lifecycle(tester, AppLifecycleState.inactive);
    platform.finishInitialization(0);
    await _flush(tester);
    expect(platform.playCalls, isEmpty);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _flush(tester);
    expect(platform.playing[0], isTrue);
  });

  portraitTest('移除入口會釋放 decoder，之後前景通知不會重啟', (tester) async {
    await mount(tester);
    final playCount = platform.playCalls.length;
    await tester.pumpWidget(const SizedBox.shrink());
    await _flush(tester);

    expect(platform.disposed, [0]);
    await _lifecycle(tester, AppLifecycleState.paused);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _flush(tester);
    expect(platform.playCalls.length, playCount);
    expect(tester.takeException(), isNull);
  });

  portraitTest('卸載後才完成 native 建立及初始化，不播放且仍釋放', (tester) async {
    platform.creationGate = Completer<void>();
    await mount(tester);
    expect(platform.creations, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    platform.creationGate!.complete();
    await _flush(tester);
    expect(platform.playCalls, isEmpty);
    expect(platform.disposed, [0]);
    expect(tester.takeException(), isNull);
  });

  for (final failure in ['initialize', 'play', 'stream']) {
    portraitTest('$failure 失敗顯示 poster，仍可輸入且不重試播放器', (tester) async {
      platform.failInitialization = failure == 'initialize';
      platform.failPlay = failure == 'play';
      final harness = await mount(tester);
      if (failure == 'stream') {
        platform.emitError(0);
        await _flush(tester);
      }
      expect(_poster, findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byTooltip('暫停 Sydney 動畫'), findsNothing);
      expect(platform.disposed, [0], reason: '影片失敗後也要釋放 native decoder');
      expect(platform.playing[0], isFalse);
      await tester.enterText(find.byKey(const Key('coach-input')), '我想問教練');
      await _flush(tester);
      expect(find.text('我想問教練'), findsOneWidget);
      harness.reduced.value = true;
      await _flush(tester);
      harness.reduced.value = false;
      await _flush(tester);
      expect(platform.creations, hasLength(1));
      expect(_poster, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

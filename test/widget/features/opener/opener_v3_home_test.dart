import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/app_haptics.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/shared/widgets/image_picker_widget.dart';
import '../../../visual_proof/proof_support.dart';

// The only mocked boundary is the device compression plugin. Validation,
// decoding, batching, busy state and parent callbacks run the real code.
class _Compress extends UnsupportedFlutterImageCompress {
  @override
  Future<Uint8List> compressWithList(Uint8List image,
          {int minWidth = 1920,
          int minHeight = 1080,
          int quality = 95,
          int rotate = 0,
          int inSampleSize = 1,
          bool autoCorrectionAngle = true,
          CompressFormat format = CompressFormat.jpeg,
          bool keepExif = false}) async =>
      image;
}

class _Subscription extends SubscriptionNotifier {
  _Subscription({bool error = false}) {
    state = SubscriptionState(
        tier: 'free',
        monthlyLimit: 30,
        dailyLimit: 15,
        error: error ? 'test unavailable' : null);
  }
}

final _root = GlobalKey();
Future<void> _pump(WidgetTester t,
    {Size size = const Size(390, 844),
    double scale = 1,
    List<Partner> partners = const [],
    bool quotaError = false}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(
      overrides: [
        authConversationScopeProvider.overrideWith((_) => const Stream.empty()),
        partnerListProvider.overrideWith((_) => partners),
        subscriptionProvider
            .overrideWith((_) => _Subscription(error: quotaError)),
        subscriptionScreenRefreshProvider.overrideWith((_) => () async {
              if (quotaError) throw StateError('offline');
            }),
      ],
      child: RepaintBoundary(
          key: _root,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'AppTC'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const OpeningRescueScreen()))));
  await t.pump(const Duration(milliseconds: 400));
}

Finder field(String hint) => find
    .byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);
ElevatedButton cta(WidgetTester t) => t.widget<ElevatedButton>(
    find.byKey(const ValueKey('opener-analyze-button')));

Future<void> capture(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 250));
  expect(t.takeException(), isNull);
  await t.runAsync(() async {
    final image = await t
        .renderObject<RenderRepaintBoundary>(find.byKey(_root))
        .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/visual_proof/v3/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<Uint8List> _profileImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 720, 1280),
      Paint()..color = const Color(0xFF59466F));
  final text = TextPainter(
      text: const TextSpan(
          text: '合成測試資料\n\n週末喜歡走走\n咖啡與旅行',
          style: TextStyle(
              fontFamily: 'AppTC', fontSize: 45, color: Colors.white)),
      textDirection: TextDirection.ltr)
    ..layout(maxWidth: 660);
  text.paint(canvas, const Offset(20, 40));
  final picture = recorder.endRecording();
  final image = await picture.toImage(720, 1280);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  picture.dispose();
  image.dispose();
  return bytes;
}

void main() {
  final haptics = <Object?>[];
  late Uint8List profile;
  late FlutterImageCompressPlatform original;
  setUpAll(() async {
    original = FlutterImageCompressPlatform.instance;
    FlutterImageCompressPlatform.instance = _Compress();
    Hive.init(Directory.systemTemp.createTempSync('v3_home').path);
    await Hive.openBox(AppConstants.settingsBox);
    await loadProofFonts();
    profile = await _profileImage();
  });
  setUp(() {
    AppHaptics.enabled = true;
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    OpeningRescueScreen.debugOwnerIdOverride = () => 'synthetic-owner';
  });
  tearDown(() {
    AppHaptics.enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    OpeningRescueScreen.debugOwnerIdOverride = null;
    OpeningRescueScreen.debugImageSelector = null;
  });
  tearDownAll(() async {
    FlutterImageCompressPlatform.instance = original;
    await Hive.close();
  });

  testWidgets('UI-01/02/08/09/10/12/SH-03 real form and one footer', (t) async {
    await _pump(t);
    expect(cta(t).onPressed, isNull);
    expect(find.textContaining('分析不扣'), findsNothing);
    expect(find.text('草稿'), findsNothing);
    await capture(t, 'opener-empty-390');
    await t.tap(find.text('手動輸入'));
    await t.pump();
    await t.enterText(field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店'), '喜歡走步道');
    await t.pump();
    expect(cta(t).onPressed, isNotNull);
    await t.enterText(field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店'), '');
    await t.pump();
    expect(cta(t).onPressed, isNull);
    await t.tap(find.text('補充其他資料（選填）'));
    await t.pump();
    await t.enterText(field('輸入對方名字（選填）'), '測試對象');
    await t.pump();
    expect(cta(t).onPressed, isNotNull);
    await t.enterText(field('輸入對方名字（選填）'), '');
    await t.ensureVisible(field('對方的興趣標籤（選填）'));
    await t.enterText(field('對方的興趣標籤（選填）'), '咖啡');
    await t.pump();
    expect(cta(t).onPressed, isNotNull);
    await t.enterText(field('對方的興趣標籤（選填）'), '');
    await t.ensureVisible(find.text('IG'));
    await t.tap(find.text('IG'));
    await t.pump();
    expect(cta(t).onPressed, isNull);
    await t.ensureVisible(find.byKey(const ValueKey('opener-initial-note')));
    final note = find.byKey(const ValueKey('opener-initial-note'));
    await t.enterText(note, '我也喜歡咖啡');
    await t.pump();
    expect(cta(t).onPressed, isNull);
    await t.enterText(field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店'), '週末去郊外');
    await t.enterText(note, List.filled(300, '👨‍👩‍👧‍👦').join());
    await t.pump();
    expect(cta(t).onPressed, isNotNull);
    await t.enterText(note, List.filled(301, '👨‍👩‍👧‍👦').join());
    await t.pump();
    expect(cta(t).onPressed, isNull);
    expect(t.widget<TextField>(note).controller!.text.characters.length, 301);
    expect(find.text('已保留你的文字，請縮短至 300 字內再分析。'), findsOneWidget);
    expect(find.byKey(const ValueKey('opener-analyze-button')), findsOneWidget);
  });

  testWidgets(
      'UI-03/04/05/07/11 picker batch guard, separate preview/remove and source',
      (t) async {
    final selected = Completer<List<XFile>>();
    var calls = 0;
    OpeningRescueScreen.debugImageSelector =
        ({required allowMultiple, required limit}) {
      calls++;
      return selected.future;
    };
    await _pump(t, size: const Size(320, 568));
    await t.tap(find.byKey(const ValueKey('opener-add-images')));
    await t.pump();
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    await t.tap(find.byKey(const ValueKey('opener-add-images')));
    await t.pump();
    expect(haptics, hasLength(1), reason: 'busy picker cannot vibrate again');
    expect(calls, 1);
    expect(cta(t).onPressed, isNull);
    await t.tap(find.text('手動輸入'));
    await t.pump();
    expect(field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店'), findsNothing);
    await t.runAsync(() async {
      selected.complete(List.generate(
          3,
          (i) => XFile.fromData(profile,
              mimeType: 'image/png', name: 'test$i.png')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await t.pump();
    expect(find.text('已加入 3／3 張'), findsOneWidget);
    expect(find.text('加入'), findsNothing);
    await capture(t, 'opener-three-320');
    haptics.clear();
    await t.tapAt(t.getBottomLeft(find.bySemanticsLabel('第 1 張圖片，點擊查看')) +
        const Offset(8, -8));
    await t.pump();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    await t.tap(find.byTooltip('關閉'));
    await t.pumpAndSettle();
    haptics.clear();
    await t.tap(find.byTooltip('移除第 1 張圖片'));
    await t.pump();
    expect(haptics, ['HapticFeedbackType.mediumImpact'],
        reason: 'delete must not also activate thumbnail preview');
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('已加入 2／3 張'), findsOneWidget);
    await t.tap(find.byTooltip('移除第 1 張圖片'));
    await t.pump();
    expect(find.text('已加入 1／3 張'), findsOneWidget);
    await capture(t, 'opener-one-320');
    await t.binding.setSurfaceSize(const Size(390, 844));
    await t.pump();
    final tile = find.byKey(const ValueKey('opener-add-image-tile'));
    final thumb = find.bySemanticsLabel('第 1 張圖片，點擊查看');
    expect(t.getTopLeft(tile).dy, t.getTopLeft(thumb).dy);
    expect(t.getSize(tile).width, greaterThanOrEqualTo(64));
    expect(t.getSize(tile).height, greaterThanOrEqualTo(72));
    await capture(t, 'opener-one-390');
    await t.tap(find.text('手動輸入'));
    await t.pump();
    expect(cta(t).onPressed, isNull);
    await t.tap(find.text('截圖自介'));
    await t.pump();
    expect(find.text('已加入 1／3 張'), findsOneWidget);
    expect(cta(t).onPressed, isNotNull);
  });

  testWidgets(
      'UI-06 picker cancel preserves image; stale owner batch is discarded',
      (t) async {
    var scope = 'a';
    var calls = 0;
    final picked = Completer<List<XFile>>();
    final busy = <bool>[];
    var changes = 0;
    Widget widget() => MaterialApp(
        home: Scaffold(
            body: ImagePickerWidget(
                variant: ImagePickerVariant.openerPanel,
                externalImages: [profile],
                operationScope: scope,
                onBusyChanged: busy.add,
                onImagesChanged: (_) => changes++,
                fileSelector: ({required allowMultiple, required limit}) {
                  calls++;
                  return picked.future;
                })));
    await t.pumpWidget(widget());
    await t.tap(find.text('加入'));
    await t.pump();
    scope = 'b';
    await t.pumpWidget(widget());
    picked.complete([XFile.fromData(profile, mimeType: 'image/png')]);
    await t.pump();
    expect(calls, 1);
    expect(changes, 0);
    expect(busy, [true, false]);
    expect(find.text('已加入 1／3 張'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ImagePickerWidget(
                variant: ImagePickerVariant.openerPanel,
                externalImages: [profile],
                onImagesChanged: (_) => changes++,
                fileSelector:
                    ({required allowMultiple, required limit}) async => []))));
    await t.tap(find.text('加入'));
    await t.pump();
    expect(find.text('已加入 1／3 張'), findsOneWidget);
    expect(changes, 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'UI-07 partial invalid batch retains valid images and releases busy',
      (t) async {
    final busy = <bool>[];
    List<Uint8List> images = [];
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ImagePickerWidget(
      variant: ImagePickerVariant.openerPanel,
      onBusyChanged: busy.add,
      onImagesChanged: (value) => images = value,
      fileSelector: ({required allowMultiple, required limit}) async => [
        XFile.fromData(profile, mimeType: 'image/png', name: 'valid.png'),
        XFile.fromData(Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/png', name: 'invalid.png'),
      ],
    ))));
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('opener-add-images')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await t.pump();
    expect(images, hasLength(1));
    expect(busy, [true, false]);
    expect(find.text('已加入 1／3 張'), findsOneWidget);
    expect(find.text('加入'), findsOneWidget);
    expect(find.text('有 1 張圖片無法加入，請換張圖片再試。'), findsOneWidget);
  });

  testWidgets(
      'SH-01/02/03 full screen mode retains manual input with one active CTA',
      (t) async {
    await _pump(t, partners: [
      Partner(
          id: 'synthetic-partner',
          name: '合成測試對象',
          ownerUserId: 'synthetic-owner',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026))
    ]);
    await t.tap(find.text('手動輸入'));
    await t.pump();
    await t.enterText(field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店'), '合成測試：喜歡閱讀');
    await t.tap(find.text('新話題'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('opener-analyze-button')), findsNothing);
    expect(t.testTextInput.isVisible, isFalse);
    expect(t.getRect(find.text('開場救星')).top, greaterThanOrEqualTo(0));
    expect(t.getRect(find.byKey(const ValueKey('new-topic-generate'))).bottom,
        lessThanOrEqualTo(844));
    await capture(t, 'topic-fullscreen-390');
    await t.tap(find.text('開場白').first);
    await t.pumpAndSettle();
    expect(t.widget<TextField>(field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店')).controller!.text,
        '合成測試：喜歡閱讀');
    expect(find.byKey(const ValueKey('opener-analyze-button')), findsOneWidget);
    expect(cta(t).onPressed, isNotNull);
  });

  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets(
        'background tap dismisses keyboard without swallowing input or controls $size',
        (t) async {
      await _pump(t, size: size);
      await t.tap(find.text('手動輸入'));
      await t.pump();
      final bio = field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店');
      await t.enterText(bio, '喜歡散步與咖啡');
      await t.pump(const Duration(milliseconds: 500));
      await t.tapAt(t.getTopLeft(bio) + const Offset(24, 24));
      await t.pump();
      expect(t.testTextInput.isVisible, isTrue,
          reason: 'a field tap must keep its keyboard open');

      // The unpainted page gutter must also dismiss, not just a text label.
      haptics.clear();
      await t.tapAt(Offset(8, t.getCenter(bio).dy));
      await t.pump();
      expect(t.testTextInput.isVisible, isFalse);
      expect(t.widget<TextField>(bio).controller!.text, '喜歡散步與咖啡');
      expect(haptics, isEmpty);

      await t.tapAt(t.getTopLeft(bio) + const Offset(24, 24));
      await t.pump();
      expect(t.testTextInput.isVisible, isTrue);
      t.view.viewInsets =
          FakeViewPadding(bottom: 300 * t.view.devicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      final note = find.byKey(const ValueKey('opener-initial-note'));
      await t.ensureVisible(note);
      await t.pumpAndSettle();
      await t.tap(note);
      await t.enterText(note, '我也喜歡咖啡');
      await t.pump();
      expect(t.testTextInput.isVisible, isTrue,
          reason: 'switching text fields must keep input working');
      expect(t.widget<TextField>(note).controller!.text, '我也喜歡咖啡');

      await t.dragFrom(Offset(8, t.getCenter(note).dy), const Offset(0, 80));
      await t.pumpAndSettle();
      expect(t.testTextInput.isVisible, isFalse,
          reason: 'existing drag-to-dismiss must still work');
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('額度說明'));
      await t.pumpAndSettle();
      haptics.clear();
      await t.tap(find.text('額度說明'));
      await t.pumpAndSettle();
      expect(find.textContaining('包含 3 組'), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.mediumImpact'],
          reason: 'a nested button must still activate exactly once');
      expect(t.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
        'UI-18/SH-03 manual focus survives keyboard footer move scale=$scale',
        (t) async {
      await _pump(t, scale: scale);
      await t.tap(find.text('手動輸入'));
      await t.pump();
      await t.enterText(field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店'), '合成資料：喜歡散步與咖啡');
      await t.pump();
      final controller =
          t.widget<TextField>(field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店')).controller;
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      expect(t.widget<TextField>(field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店')).controller,
          same(controller));
      await t
          .ensureVisible(find.byKey(const ValueKey('opener-analyze-button')));
      await t.pump();
      expect(
          find.byKey(const ValueKey('opener-analyze-button')), findsOneWidget);
      await capture(t, 'opener-keyboard-$scale');
      t.view.resetViewInsets();
      await t.pump();
      await t.ensureVisible(field('例如：喜歡爬山、養了一隻貓，週末常去咖啡店'));
      await t.pump();
      await capture(t, 'opener-manual-$scale');
    });
  }

  testWidgets(
      'UI-19/20/SH-04 quota failure shows retry with no invented balances',
      (t) async {
    await _pump(t, quotaError: true);
    await t.ensureVisible(find.text('額度說明'));
    await t.tap(find.text('額度說明'));
    await t.pumpAndSettle();
    expect(find.text('暫時無法載入額度說明'), findsOneWidget);
    expect(find.textContaining('本月可用'), findsNothing);
    expect(find.textContaining('每日最多 5'), findsNothing);
    expect(find.textContaining('包含 3 組'), findsOneWidget);
    await capture(t, 'opener-quota-error');
    await t.tap(find.text('重試'));
    await t.pumpAndSettle();
    expect(find.text('暫時無法載入額度說明'), findsOneWidget);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/conversation/presentation/screens/new_conversation_screen.dart';
import 'package:vibesync/features/opener/data/services/opener_result_cache_service.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';

void main() {
  group('NewConversationScreen', () {
    testWidgets('displays title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('手動輸入'), findsOneWidget);
    });

    testWidgets('shows name input field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('對話對象'), findsOneWidget);
      expect(find.text('例如：小安'), findsOneWidget);
    });

    testWidgets('shows content input field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('對話內容'), findsOneWidget);
      expect(find.text('她說了什麼…'), findsOneWidget);
      expect(find.text('我說了什麼…'), findsOneWidget);
    });

    testWidgets('collapses analysis settings by default', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('這次分析設定（可不改）'), findsOneWidget);
      expect(find.text('交友軟體・剛認識・邀約見面'), findsOneWidget);
      expect(find.text('不確定可以先跳過；AI 會用預設情境分析。'), findsOneWidget);
      expect(find.text('認識情境'), findsNothing);
      expect(find.text('補充背景（選填）'), findsNothing);
    });

    testWidgets('expands meeting context selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      await tester.tap(find.text('這次分析設定（可不改）'));
      await tester.pump();

      expect(find.text('認識情境'), findsOneWidget);
      expect(find.text('交友軟體'), findsOneWidget);
      expect(find.text('現實認識'), findsOneWidget);
      expect(find.text('朋友介紹'), findsOneWidget);
      expect(find.text('已是伴侶'), findsOneWidget);
      expect(find.text('其他'), findsNothing);
    });

    testWidgets('expands duration selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      await tester.tap(find.text('這次分析設定（可不改）'));
      await tester.pump();

      expect(find.text('認識多久'), findsOneWidget);
      expect(find.text('剛認識'), findsOneWidget);
      expect(find.text('幾天'), findsOneWidget);
      expect(find.text('幾週'), findsOneWidget);
      expect(find.text('一個月以上'), findsOneWidget);
    });

    testWidgets('expands goal selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      await tester.tap(find.text('這次分析設定（可不改）'));
      await tester.pump();

      expect(find.text('目前目標'), findsOneWidget);
      expect(find.text('邀約見面'), findsOneWidget);
      expect(find.text('維持熱度'), findsOneWidget);
      expect(find.text('自然聊天'), findsOneWidget);
    });

    testWidgets('shows optional analysis context note field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      await tester.tap(find.text('這次分析設定（可不改）'));
      await tester.pump();

      expect(find.text('補充背景（選填）'), findsOneWidget);
      expect(find.text('沒有可以留空'), findsOneWidget);
      expect(find.text('其他'), findsNothing);
      expect(find.textContaining('只影響這個對話的分析'), findsOneWidget);
      final noteField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '沒有可以留空',
        ),
      );
      expect(noteField.maxLength, 300);
      expect(noteField.textInputAction, TextInputAction.done);
    });

    testWidgets('hides save button before any message is added',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('先儲存對話'), findsNothing);
    });

    testWidgets('keeps save button hidden after only outgoing message is added',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      final myMessageField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '我說了什麼…',
      );
      await tester.ensureVisible(myMessageField);
      await tester.enterText(myMessageField, '你好');
      final addButton = find.byIcon(Icons.add).last;
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pump();

      expect(find.text('先儲存對話'), findsNothing);
      expect(find.text('先儲存開場草稿'), findsNothing);
      expect(find.text('建立對話'), findsNothing);
    });

    testWidgets('shows create button after incoming message is added',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      final herMessageField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '她說了什麼…',
      );
      await tester.ensureVisible(herMessageField);
      await tester.enterText(herMessageField, '你好');
      final addButton = find.byIcon(Icons.add).first;
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pump();

      expect(find.text('建立對話'), findsOneWidget);
    });

    testWidgets('shows current message-entry hint', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('依序輸入對話，至少先加入一則訊息。'), findsOneWidget);
    });

    test('opener handoff hint says to send opener then paste reply', () {
      expect(
        newConversationHintText(
          hasMessages: true,
          hasOpenerSeed: true,
          hasIncomingMessage: false,
          endsWithMyMessage: true,
        ),
        '先把這句傳給對方；收到回覆後，貼到「她說」再建立對話分析。',
      );
      expect(
        newConversationHintText(
          hasMessages: true,
          hasOpenerSeed: true,
          hasIncomingMessage: false,
          endsWithMyMessage: true,
        ),
        isNot(contains('已先帶入你準備送出的開場白')),
      );
    });
  });

  _manualInputDesignTests();
}

/// 手動輸入正式版：群組卡 + Sydney 出血構圖的版面契約測試。
///
/// 這些測試鎖的是「設計稿定案的結構」而不是像素：單一群組卡、44×44 觸控、
/// 去背素材、Sydney 排在提示文字之後且被裁切容器切在裙子中段。
Finder _hintField(String hint) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == hint,
    );

Finder get _composerGroup =>
    find.byKey(const ValueKey(manualInputComposerGroupKey));

Finder get _sydneyClip =>
    find.byKey(const ValueKey(manualInputSydneySkirtBleedKey));

Finder get _sydneyArt => find.byKey(const ValueKey(manualInputSydneyArtKey));

Future<void> _pumpScreen(
  WidgetTester tester, {
  String? partnerId,
  bool seedFromLatestOpener = false,
  Size size = const Size(393, 852),
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: NewConversationScreen(
            partnerId: partnerId,
            seedFromLatestOpener: seedFromLatestOpener,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _manualInputDesignTests() {
  group('手動輸入正式版版面', () {
    testWidgets('顯示標題、區塊標題與兩個 placeholder', (tester) async {
      await _pumpScreen(tester, partnerId: 'p-1');

      expect(find.text('手動輸入'), findsOneWidget);
      expect(find.text('對話內容'), findsOneWidget);
      expect(find.text('她說了什麼…'), findsOneWidget);
      expect(find.text('我說了什麼…'), findsOneWidget);
      expect(find.text('依序輸入對話，至少先加入一則訊息。'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('兩列輸入合在同一張群組卡內，提示文字在卡外', (tester) async {
      await _pumpScreen(tester, partnerId: 'p-1');

      expect(_composerGroup, findsOneWidget);
      // 兩列都在同一張卡裡。
      for (final hint in const ['她說了什麼…', '我說了什麼…']) {
        expect(
          find.descendant(of: _composerGroup, matching: _hintField(hint)),
          findsOneWidget,
        );
      }
      // 兩個「＋」也在同一張卡裡。
      expect(
        find.descendant(of: _composerGroup, matching: find.byIcon(Icons.add)),
        findsNWidgets(2),
      );
      // 中間只有一條分隔線（空狀態沒有訊息列表）。
      expect(
        find.descendant(of: _composerGroup, matching: find.byType(Divider)),
        findsOneWidget,
      );
      // 提示列與 Sydney 都在卡外。
      expect(
        find.descendant(
          of: _composerGroup,
          matching: find.text('依序輸入對話，至少先加入一則訊息。'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: _composerGroup, matching: _sydneyArt),
        findsNothing,
      );
    });

    testWidgets('兩個新增按鈕的點擊區都至少 44×44', (tester) async {
      await _pumpScreen(tester, partnerId: 'p-1');

      final buttons = find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(GestureDetector),
      );
      expect(buttons, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final size = tester.getSize(buttons.at(i));
        expect(size.width, greaterThanOrEqualTo(44.0));
        expect(size.height, greaterThanOrEqualTo(44.0));
      }
    });

    testWidgets('Sydney 使用去背正式素材', (tester) async {
      await _pumpScreen(tester, partnerId: 'p-1');

      expect(_sydneyArt, findsOneWidget);
      final image = tester.widget<Image>(_sydneyArt);
      final provider = image.image;
      expect(provider, isA<AssetImage>());
      expect(
        (provider as AssetImage).assetName,
        'assets/images/coach/sydney_manual_input_full.png',
      );
      expect((provider).assetName, manualInputSydneyAsset);
      expect(image.filterQuality, FilterQuality.medium);
    });

    testWidgets('空白狀態下 Sydney 排在提示文字之後且不重疊', (tester) async {
      await _pumpScreen(tester, partnerId: 'p-1');

      final hintRect = tester.getRect(find.text('依序輸入對話，至少先加入一則訊息。'));
      final sydneyRect = tester.getRect(_sydneyClip);
      expect(sydneyRect.top, greaterThanOrEqualTo(hintRect.bottom));

      // 也不能壓到群組卡。
      final cardRect = tester.getRect(_composerGroup);
      expect(sydneyRect.top, greaterThanOrEqualTo(cardRect.bottom));
    });

    testWidgets('裙襬裁切容器一定比實際繪製高度矮（永遠切在裙子中段）', (tester) async {
      await _pumpScreen(tester, partnerId: 'p-1');

      expect(_sydneyClip, findsOneWidget);
      final clipHeight = tester.getSize(_sydneyClip).height;
      final artHeight = tester.getSize(_sydneyArt).height;

      // 素材本身已裁在裙襬之上；再加上這層裁切，素材自己的下緣也不會露出來。
      expect(artHeight, greaterThan(clipHeight));
      expect(
        artHeight,
        closeTo(clipHeight * manualInputSydneyBleedFactor, 0.5),
      );
      expect(
          clipHeight,
          greaterThanOrEqualTo(
            manualInputSydneyMinVisibleHeight,
          ));

      // 裁切容器貼齊畫面底部（出血），不會浮在半空中。
      final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
      expect(
        tester.getRect(_sydneyClip).bottom,
        closeTo(screenHeight, 0.5),
      );
    });

    testWidgets('加入訊息後訊息列表與「建立對話」都正常', (tester) async {
      await _pumpScreen(tester, partnerId: 'p-1');

      await tester.enterText(_hintField('她說了什麼…'), '你好呀');
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();

      // 訊息進到同一張群組卡裡。
      expect(
        find.descendant(of: _composerGroup, matching: find.text('你好呀')),
        findsOneWidget,
      );
      expect(find.text('建立對話'), findsOneWidget);
      // Sydney 仍在 CTA 之後，沒有蓋住按鈕。
      expect(
        tester.getRect(_sydneyClip).top,
        greaterThanOrEqualTo(tester.getRect(find.text('建立對話')).bottom),
      );

      // 刪除鍵仍可用。
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('你好呀'), findsNothing);
      expect(find.text('建立對話'), findsNothing);
    });

    testWidgets('對象卡入口不顯示「對話對象」與分析設定', (tester) async {
      await _pumpScreen(tester, partnerId: 'p-1');

      expect(find.text('對話對象'), findsNothing);
      expect(find.text('例如：小安'), findsNothing);
      expect(find.text('這次分析設定（可不改）'), findsNothing);
      expect(_composerGroup, findsOneWidget);
    });

    testWidgets('孤兒對話入口保留「對話對象」與分析設定', (tester) async {
      await _pumpScreen(tester, size: const Size(393, 1200));

      expect(find.text('對話對象'), findsOneWidget);
      expect(find.text('例如：小安'), findsOneWidget);
      expect(find.text('這次分析設定（可不改）'), findsOneWidget);
      expect(_composerGroup, findsOneWidget);
      expect(_sydneyArt, findsOneWidget);
    });

    testWidgets('沒有開場草稿時 seedFromLatestOpener 安全退回一般手動輸入', (tester) async {
      await _pumpScreen(
        tester,
        partnerId: 'p-1',
        seedFromLatestOpener: true,
      );

      expect(find.text('手動輸入'), findsOneWidget);
      expect(find.text('接續開場'), findsNothing);
      expect(find.text('已帶入剛剛的開場白'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('400px 窄螢幕 + 1.3 倍文字不 overflow', (tester) async {
      await _pumpScreen(
        tester,
        size: const Size(400, 700),
        textScale: 1.3,
      );

      expect(tester.takeException(), isNull);
      expect(_composerGroup, findsOneWidget);
      expect(_sydneyArt, findsOneWidget);

      // 捲到底仍摸得到 Sydney，且沒有 overflow 例外。
      await tester.drag(_composerGroup, const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('320px 極窄螢幕 + 1.6 倍文字不 overflow', (tester) async {
      await _pumpScreen(
        tester,
        size: const Size(320, 640),
        textScale: 1.6,
      );

      expect(tester.takeException(), isNull);
      expect(_composerGroup, findsOneWidget);
    });
  });

  group('接續開場入口', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('manual_input_opener');
      Hive.init(tempDir.path);
      if (!Hive.isBoxOpen(AppConstants.settingsBox)) {
        await Hive.openBox(AppConstants.settingsBox);
      }
      OpenerResultCacheService.debugDefaultOwnerIdOverride = () => 'u-test';
    });

    tearDownAll(() async {
      OpenerResultCacheService.debugDefaultOwnerIdOverride = null;
      await Hive.close();
      tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      await Hive.box(AppConstants.settingsBox).clear();
    });

    testWidgets('帶入開場白後標題改為「接續開場」，草稿進到群組卡', (tester) async {
      // 'extend' 是 free 也看得到的型別，避免 visibleForAccess 過濾掉。
      // Hive 寫入是真的磁碟 I/O：testWidgets 的 fake-async zone 不會讓它
      // 完成，必須放進 runAsync。
      await tester.runAsync(() async {
        await OpenerResultCacheService(ownerIdResolver: () => 'u-test')
            .saveDraft(
          result: const OpenerResult(
            openers: {'extend': '妳那張爬山的照片是在哪座山拍的？'},
            recommendedPick: 'extend',
            recommendedReason: '直接接她自己放的內容，不用另開話題。',
          ),
          partnerId: 'p-1',
        );
      });

      await _pumpScreen(
        tester,
        partnerId: 'p-1',
        seedFromLatestOpener: true,
        size: const Size(393, 1200),
      );

      expect(find.text('接續開場'), findsOneWidget);
      expect(find.text('已帶入剛剛的開場白'), findsOneWidget);
      expect(
        find.descendant(
          of: _composerGroup,
          matching: find.text('妳那張爬山的照片是在哪座山拍的？'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('先把這句傳給對方；收到回覆後，貼到「她說」再建立對話分析。'),
        findsOneWidget,
      );

      // 「不帶入」把草稿收回去，標題也退回手動輸入。
      await tester.tap(find.text('不帶入'));
      await tester.pump();
      expect(find.text('手動輸入'), findsOneWidget);
      expect(find.text('妳那張爬山的照片是在哪座山拍的？'), findsNothing);
      expect(find.text('依序輸入對話，至少先加入一則訊息。'), findsOneWidget);
    });
  });
}

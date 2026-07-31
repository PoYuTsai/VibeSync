// Scoped visual proof — 聊天測驗（關卡地圖、答題器、結果頁）。
// Run: flutter test test/visual_proof/chat_quiz_proof_test.dart
// Out: build/visual_proof/chat_quiz_*.png
//
// **鐵坑（電子書踩過）**：拍付費關卡一定要給對權限。用錯權限會被 gate 導走，
// 截圖拍到空畫面而測試照樣綠。所以每一張截圖前都先斷言「畫面上真的有目標
// 文字」，斷言不過就不會產出圖。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/learning/data/providers/chat_quiz_providers.dart';
import 'package:vibesync/features/learning/data/repositories/chat_quiz_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/presentation/screens/chat_quiz_map_screen.dart';
import 'package:vibesync/features/learning/presentation/screens/chat_quiz_player_screen.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

import '../helpers/chat_quiz_test_content.dart';
import '../helpers/ebook_widget_harness.dart' show InMemoryHiveBox;
import 'proof_support.dart';

Future<void> _loadFonts() async {
  // 絕不寫死本機字型路徑：這些 proof 會跟著 release gate 在 CI 上跑。
  for (final path in const [
    '/mnt/c/Windows/Fonts/msjh.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await (FontLoader('AppTC')
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
    break;
  }
  await loadProofFonts();
}

void main() {
  late ChatQuizCatalog catalog;

  setUpAll(() async {
    await _loadFonts();
    // 內容資產一定要在 testWidgets 之外載入：>50KB 的 loadString 走 isolate，
    // 在 fake async 下永遠不會完成，測試會整個卡死。
    catalog = await loadProductionChatQuizCatalog();
  });

  /// 用真實內容 pump 一個測驗畫面，並回傳截圖用的 root key。
  Future<GlobalKey> pumpQuiz(
    WidgetTester tester, {
    required String initialLocation,
    required EbookSubscriptionAccess access,
    Size size = const Size(390, 1200),
    InMemoryHiveBox? box,
  }) async {
    final container = ProviderContainer(
      overrides: [
        ebookSubscriptionAccessProvider.overrideWith((ref) => access),
        chatQuizCatalogProvider.overrideWith((ref) async => catalog),
        chatQuizProgressOwnerProvider
            .overrideWith((ref) => Stream<String?>.value('proof-owner')),
        chatQuizProgressRepositoryProvider.overrideWithValue(
          ChatQuizProgressRepository(box: box ?? InMemoryHiveBox()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/paywall',
          builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(
          path: '/learning/quiz',
          builder: (_, __) => const ChatQuizMapScreen(),
        ),
        GoRoute(
          path: '/learning/quiz/levels/:levelId',
          builder: (context, state) => ChatQuizPlayerScreen(
            levelId: state.pathParameters['levelId']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final rootKey = GlobalKey();
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
          routerConfig: router,
          builder: (context, child) => RepaintBoundary(
            key: rootKey,
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'AppTC'),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return rootKey;
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey rootKey,
    String name,
  ) async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(outPath(name))..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  testWidgets('關卡地圖：免費視角', (tester) async {
    final rootKey = await pumpQuiz(
      tester,
      initialLocation: '/learning/quiz',
      access: const EbookSubscriptionAccess.free(),
    );

    // 拍到東西才算數：免費視角必須看得到免費關、鎖住的關與唯一的付費入口。
    expect(find.text('1-1　她現在是哪一種'), findsOneWidget);
    expect(find.text('1-2　消極期先止損'), findsOneWidget);
    expect(find.text('可以開始'), findsOneWidget);
    expect(find.text('看訂閱方案'), findsOneWidget);

    await capture(tester, rootKey, 'chat_quiz_map_free.png');
  });

  testWidgets('關卡地圖：付費視角', (tester) async {
    // 鐵坑：這裡用錯權限會被 gate 導走，拍到空畫面而測試照樣綠。
    final rootKey = await pumpQuiz(
      tester,
      initialLocation: '/learning/quiz',
      access: const EbookSubscriptionAccess.premium(),
    );

    expect(find.text('2-1　對話死在哪'), findsOneWidget);
    expect(find.text('2-2　情緒是開口'), findsOneWidget);
    expect(find.text('需要訂閱'), findsNothing, reason: '付費視角不該還有鎖');
    expect(find.text('看訂閱方案'), findsNothing);

    await capture(tester, rootKey, 'chat_quiz_map_premium.png');
  });

  testWidgets('答題器：送出前', (tester) async {
    final rootKey = await pumpQuiz(
      tester,
      initialLocation: '/learning/quiz/levels/quiz-level-1-1',
      access: const EbookSubscriptionAccess.free(),
      size: const Size(390, 900),
    );

    expect(find.text('第 1 題 / 共 10 題'), findsOneWidget);
    expect(find.text('這則回覆是什麼燈？'), findsOneWidget);
    expect(find.text('送出答案'), findsOneWidget);
    // 送出前不得有任何正解線索——這張圖就是那條規則的證據。
    expect(find.text('正確'), findsNothing);
    expect(find.text('不是這個'), findsNothing);

    await tester.tap(find.textContaining('綠燈——她主動給了超出你問的東西'));
    await tester.pumpAndSettle();
    await capture(tester, rootKey, 'chat_quiz_player_before_submit.png');
  });

  testWidgets('答題器：送出後', (tester) async {
    final rootKey = await pumpQuiz(
      tester,
      initialLocation: '/learning/quiz/levels/quiz-level-1-1',
      access: const EbookSubscriptionAccess.free(),
      size: const Size(390, 1400),
    );

    await tester.tap(find.textContaining('黃燈——她只是禮貌地接住'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    expect(find.text('正確'), findsOneWidget);
    expect(find.text('不是這個'), findsNWidgets(2));
    expect(find.text('· 你的選擇'), findsOneWidget);
    expect(find.text('讀原理'), findsOneWidget);

    await capture(tester, rootKey, 'chat_quiz_player_after_submit.png');
  });

  testWidgets('結果頁：過關', (tester) async {
    final rootKey = await pumpQuiz(
      tester,
      initialLocation: '/learning/quiz/levels/quiz-level-1-1',
      access: const EbookSubscriptionAccess.free(),
      size: const Size(390, 900),
    );

    await _playLevel(tester, correctRatio: 1.0);

    expect(find.text('過關'), findsOneWidget);
    expect(find.text('10 / 10 題答對'), findsOneWidget);

    await capture(tester, rootKey, 'chat_quiz_result_passed.png');
  });

  testWidgets('結果頁：再跑一次', (tester) async {
    final rootKey = await pumpQuiz(
      tester,
      initialLocation: '/learning/quiz/levels/quiz-level-1-1',
      access: const EbookSubscriptionAccess.free(),
      size: const Size(390, 1600),
    );

    await _playLevel(tester, correctRatio: 0.5);

    expect(find.text('再跑一次'), findsWidgets);
    expect(find.text('5 / 10 題答對'), findsOneWidget);
    expect(find.text('這幾題再看一次'), findsOneWidget);
    // 沒過的畫面上不得出現「失敗」，也不得出現任何額度或付費文案。
    expect(find.textContaining('失敗'), findsNothing);
    expect(find.textContaining('額度'), findsNothing);

    await capture(tester, rootKey, 'chat_quiz_result_retry.png');
  });
}

/// 把 1-1 跑完。[correctRatio] 決定前幾題答對，其餘刻意答錯。
Future<void> _playLevel(
  WidgetTester tester, {
  required double correctRatio,
}) async {
  const total = 10;
  final correctCount = (total * correctRatio).round();

  for (var index = 0; index < total; index++) {
    final card = find.byType(ChatQuizPlayerBody);
    expect(card, findsOneWidget, reason: '第 ${index + 1} 題沒有渲染出來');

    // 正解一律是每題的第一個選項（內容檔就是這樣寫的）；答錯時挑第二個。
    final choices = find.byType(InkWell);
    await tester.tap(choices.at(index < correctCount ? 0 : 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    final next = index == total - 1 ? '看結果' : '下一題';
    await tester.scrollUntilVisible(find.text(next), 200);
    await tester.tap(find.text(next));
    await tester.pumpAndSettle();
  }
}

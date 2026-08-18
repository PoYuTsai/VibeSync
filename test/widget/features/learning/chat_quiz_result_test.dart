// test/widget/features/learning/chat_quiz_result_test.dart
//
// 結果頁。守的是三件事：
//   1. 沒過的標題是「再跑一次」，不是「失敗」。這是產品用字，不是文案偏好。
//   2. 重試不扣任何東西——畫面上不得出現任何額度或付費文案。
//   3. 答錯的題列得出來，有 source 才顯示「讀原理」。
//
// 動效由 AnimationController 推導、一次到底不 repeat，所以 pumpAndSettle 一定
// 收斂。用 Timer 當時間軸的話這一整支測試會逾時。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/presentation/screens/chat_quiz_result_screen.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

import '../../../helpers/chat_quiz_test_content.dart';
import '../../../helpers/chat_quiz_widget_harness.dart';

/// 五題的關卡，門檻 80% ＝ 要對 4 題。
ChatQuizLevel _level() {
  return buildTestChatQuizLevel(
    questions: [
      for (var index = 0; index < 5; index++)
        buildTestChatQuizQuestion(
          id: 'q-$index',
          source: index == 0
              ? const ChatQuizSource(
                  bookId: 'ebook-2-conversation',
                  chapterId: 'ebook-2-chapter-4',
                )
              : null,
        ),
    ],
  );
}

/// 前 [correct] 題答對，其餘答錯。
Map<String, String> _picks(int correct) {
  return <String, String>{
    for (var index = 0; index < 5; index++)
      'q-$index': index < correct ? 'q-$index-a' : 'q-$index-b',
  };
}

Future<void> _pumpResult(
  WidgetTester tester, {
  required int correct,
  bool reduceMotion = false,
  VoidCallback? onRetry,
  VoidCallback? onBackToMap,
  void Function(ChatQuizSource)? onReadSource,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: ChatQuizResultScreen(
        level: _level(),
        picks: _picks(correct),
        onRetry: onRetry ?? () {},
        onBackToMap: onBackToMap ?? () {},
        onReadSource: onReadSource ?? (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('80% 就過關', (tester) async {
    await _pumpResult(tester, correct: 4);

    expect(find.text('過關'), findsOneWidget);
    expect(find.text('4 / 5 題答對'), findsOneWidget);
  });

  testWidgets('沒過的標題是「再跑一次」，不是「失敗」', (tester) async {
    await _pumpResult(tester, correct: 3);

    expect(find.text('再跑一次'), findsWidgets);
    expect(find.textContaining('失敗'), findsNothing);
    expect(find.textContaining('未通過'), findsNothing);
    expect(find.text('答對 4 題就過。重試不限次數，也不會扣任何東西。'), findsOneWidget);
  });

  testWidgets('重試無限次不扣任何東西：畫面上沒有額度或付費文案', (tester) async {
    await _pumpResult(tester, correct: 1);

    expect(find.textContaining('額度'), findsNothing);
    expect(find.textContaining('訂閱'), findsNothing);
    expect(find.textContaining('升級'), findsNothing);
    expect(find.textContaining('次數用完'), findsNothing);
  });

  testWidgets('答錯的題列出來，答對的不列', (tester) async {
    await _pumpResult(tester, correct: 3);

    expect(find.text('這幾題再看一次'), findsOneWidget);
    // 五題裡答錯兩題：兩張卡，各一組「你選了 / 正解」。
    expect(find.text('你選了'), findsNWidgets(2));
    expect(find.text('正解'), findsNWidgets(2));
  });

  testWidgets('全對時不出現錯題區', (tester) async {
    await _pumpResult(tester, correct: 5);

    expect(find.text('這幾題再看一次'), findsNothing);
    expect(find.text('過關'), findsOneWidget);
  });

  testWidgets('有 source 的錯題才顯示「讀原理」', (tester) async {
    ChatQuizSource? opened;
    // 全錯：第一題有 source，其餘沒有 → 只有一顆「讀原理」。
    await _pumpResult(
      tester,
      correct: 0,
      onReadSource: (source) => opened = source,
    );

    // ListView 只建出畫面內的卡片，所以這裡不數總數，只確認錯題區存在，
    // 以及唯一有 source 的那一題掛著「讀原理」。
    expect(find.text('你選了'), findsWidgets);
    expect(find.text('讀原理'), findsOneWidget);

    await tester.tap(find.text('讀原理'));
    await tester.pumpAndSettle();
    expect(opened?.chapterId, 'ebook-2-chapter-4');
  });

  testWidgets('再跑一次與回關卡地圖都接得到', (tester) async {
    var retried = 0;
    var backToMap = 0;
    await _pumpResult(
      tester,
      correct: 2,
      onRetry: () => retried += 1,
      onBackToMap: () => backToMap += 1,
    );

    final retryButton = find.widgetWithText(ElevatedButton, '再跑一次');
    await tester.scrollUntilVisible(retryButton, 200);
    await tester.tap(retryButton);
    await tester.pumpAndSettle();
    expect(retried, 1);

    final backButton = find.text('回關卡地圖');
    await tester.scrollUntilVisible(backButton, 200);
    await tester.tap(backButton);
    await tester.pumpAndSettle();
    expect(backToMap, 1);
  });

  testWidgets('沒過關時點分數卡就是重跑；過關時點了不動作', (tester) async {
    var retried = 0;
    await _pumpResult(tester, correct: 2, onRetry: () => retried += 1);

    // 分數卡標題寫「再跑一次」長得像按鈕（2026-08-18 dogfood），點卡片要有反應。
    await tester.tap(find.byIcon(Icons.refresh_outlined));
    await tester.pumpAndSettle();
    expect(retried, 1);

    retried = 0;
    await _pumpResult(tester, correct: 5, onRetry: () => retried += 1);
    await tester.tap(find.byIcon(Icons.emoji_events_outlined));
    await tester.pumpAndSettle();
    expect(retried, 0);
    // 過關觸覺是漸強三下（共 200ms），把後兩下的 timer 走完避免殘留。
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('開啟減少動態效果時直接呈現終點狀態，不跑動畫', (tester) async {
    await _pumpResult(tester, correct: 5, reduceMotion: true);

    final transform = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byIcon(Icons.emoji_events_outlined),
            matching: find.byType(Transform),
          )
          .first,
    );
    // 終點的縮放是 1.0；動畫還在跑的話會小於 1。
    expect(transform.transform.getMaxScaleOnAxis(), closeTo(1.0, 0.001));

    // 過關觸覺是漸強三下（共 200ms），把後兩下的 timer 走完避免殘留。
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('過關動效跑完會停在終點（沒有無限 repeat）', (tester) async {
    await _pumpResult(tester, correct: 5);

    // pumpAndSettle 已經回來了就代表動畫收斂；再確認終點值。
    final transform = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byIcon(Icons.emoji_events_outlined),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(transform.transform.getMaxScaleOnAxis(), closeTo(1.0, 0.001));
  });

  testWidgets('答題器跑完會進到結果頁，再跑一次會回到第一題', (tester) async {
    await pumpChatQuizApp(
      tester,
      initialLocation: '/learning/quiz/levels/quiz-level-1-1',
      catalog: ChatQuizCatalog(
        groups: [
          buildTestChatQuizGroup(
            levels: [
              buildTestChatQuizLevel(
                questions: [
                  buildTestChatQuizQuestion(id: 'q-0'),
                  buildTestChatQuizQuestion(id: 'q-1'),
                ],
              ),
            ],
          ),
        ],
      ),
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < 2; index++) {
      await tester.tap(find.text('選項 2')); // 每題都答錯
      await tester.pumpAndSettle();
      await tester.tap(find.text('送出答案'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(index == 1 ? '看結果' : '下一題'));
      await tester.pumpAndSettle();
    }

    expect(find.text('0 / 2 題答對'), findsOneWidget);
    expect(find.text('這幾題再看一次'), findsOneWidget);

    final retryButton = find.widgetWithText(ElevatedButton, '再跑一次');
    await tester.scrollUntilVisible(retryButton, 200);
    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(find.text('第 1 題 / 共 2 題'), findsOneWidget);
    expect(find.text('送出答案'), findsOneWidget);
  });
}

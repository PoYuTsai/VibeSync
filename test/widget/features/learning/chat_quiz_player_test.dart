// test/widget/features/learning/chat_quiz_player_test.dart
//
// 答題器行為。重點在兩件事：
//   1. 送出前不得洩漏任何正解線索——這是整個測驗有沒有價值的分界。
//   2. 對錯不能只靠顏色。色盲使用者看不出紅綠，文字標籤是唯一的保證。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/learning/data/repositories/chat_quiz_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/presentation/widgets/chat_quiz_question_card.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

import '../../../helpers/chat_quiz_test_content.dart';
import '../../../helpers/chat_quiz_widget_harness.dart';
import '../../../helpers/ebook_widget_harness.dart' show InMemoryHiveBox;

const _levelId = 'quiz-level-1-1';
const _ownerUserId = 'quiz-harness-owner';

/// 三題的免費關：夠測「送出 → 下一題 → 看結果」的完整流程。
ChatQuizCatalog _catalog({int questionCount = 3, int revision = 1}) {
  return ChatQuizCatalog(
    groups: [
      buildTestChatQuizGroup(
        levels: [
          buildTestChatQuizLevel(
            questions: [
              for (var index = 0; index < questionCount; index++)
                buildTestChatQuizQuestion(
                  id: 'q-$index',
                  revision: revision,
                  source: index == 0
                      ? const ChatQuizSource(
                          bookId: 'ebook-2-conversation',
                          chapterId: 'ebook-2-chapter-4',
                        )
                      : null,
                ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<ChatQuizHarness> _pump(
  WidgetTester tester, {
  ChatQuizCatalog? catalog,
  double textScale = 1.0,
  Size size = const Size(390, 900),
  Box? progressBox,
}) async {
  final harness = await pumpChatQuizApp(
    tester,
    initialLocation: '/learning/quiz/levels/$_levelId',
    catalog: catalog ?? _catalog(),
    access: const EbookSubscriptionAccess.free(),
    textScale: textScale,
    size: size,
    progressBox: progressBox,
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('未作答不能按送出，也不能往下一題', (tester) async {
    await _pump(tester);

    expect(find.text('第 1 題 / 共 3 題'), findsOneWidget);
    final submit = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '送出答案'),
    );
    expect(submit.onPressed, isNull, reason: '沒選任何選項時送出鍵必須是停用的');
    expect(find.text('下一題'), findsNothing);
  });

  testWidgets('送出前畫面上沒有任何正解線索', (tester) async {
    await _pump(tester);

    expect(find.text(kChatQuizCorrectLabel), findsNothing);
    expect(find.text(kChatQuizIncorrectLabel), findsNothing);
    expect(find.text('對，往情緒走。'), findsNothing);
    expect(find.text('這句把對話收掉了。'), findsNothing);
    expect(find.text('情緒是開口，事實是死路。'), findsNothing);

    // 選了之後、送出之前，一樣不得揭示。
    await tester.tap(find.text('選項 2'));
    await tester.pumpAndSettle();
    expect(find.text(kChatQuizCorrectLabel), findsNothing);
    expect(find.text(kChatQuizIncorrectLabel), findsNothing);
  });

  testWidgets('送出後每個選項都有自己的 feedback，而且對錯有文字標示', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('選項 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    // 三個選項各自一段 feedback：一個正解、兩個錯的。
    expect(find.text('對，往情緒走。'), findsOneWidget);
    expect(find.text('這句把對話收掉了。'), findsNWidgets(2));

    // 對錯有文字，不是只有顏色。
    expect(find.text(kChatQuizCorrectLabel), findsOneWidget);
    expect(find.text(kChatQuizIncorrectLabel), findsNWidgets(2));
    expect(find.text(kChatQuizYourPickLabel), findsOneWidget);

    // 整題 takeaway 一併展開。
    expect(find.text('情緒是開口，事實是死路。'), findsOneWidget);
  });

  testWidgets('答對與答錯都會展開回饋，答錯不會被擋著不能往下', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('選項 1')); // 正解
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    expect(find.text('答對了'), findsOneWidget);
    expect(find.text('下一題'), findsOneWidget);

    await tester.tap(find.text('下一題'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 題 / 共 3 題'), findsOneWidget);

    await tester.tap(find.text('選項 2')); // 錯的
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    expect(find.text('這一題再看一次'), findsOneWidget);
    expect(find.text('下一題'), findsOneWidget, reason: '答錯不該把人卡在這一題');
  });

  testWidgets('送出後不能改答案', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('選項 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('選項 2'));
    await tester.pumpAndSettle();
    expect(
      find.text(kChatQuizYourPickLabel),
      findsOneWidget,
      reason: '送出後再點別的選項不該改變「你的選擇」',
    );
  });

  testWidgets('有 source 的題目才顯示「讀原理」，而且點得到章節', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('選項 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();
    expect(find.text('讀原理'), findsOneWidget);

    await tester.tap(find.text('讀原理'));
    await tester.pumpAndSettle();
    expect(find.text(ebookChapterStubText), findsOneWidget);
  });

  testWidgets('沒有 source 的題目不顯示「讀原理」', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('選項 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一題'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('選項 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();
    expect(find.text('讀原理'), findsNothing);
  });

  testWidgets('跑完最後一題會結算，成績寫進本機進度', (tester) async {
    final harness = await _pump(tester);

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.text('選項 1')); // 每題都答對
      await tester.pumpAndSettle();
      await tester.tap(find.text('送出答案'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(index == 2 ? '看結果' : '下一題'));
      await tester.pumpAndSettle();
    }

    expect(find.text('過關'), findsOneWidget);
    expect(find.text('3 / 3 題答對'), findsOneWidget);

    final progress = await harness.repository.load(_ownerUserId);
    expect(progress.resultFor(_levelId)?.correctCount, 3);
    expect(progress.isLevelPassed(_levelId), isTrue);
    expect(progress.answers, hasLength(3));
  });

  testWidgets('revision 變更後，已答過的題目回到未作答狀態', (tester) async {
    final box = InMemoryHiveBox();

    // 先用 revision 1 答完第一題。
    await _pump(tester, progressBox: box);
    await tester.tap(find.text('選項 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();
    expect(find.text(kChatQuizCorrectLabel), findsOneWidget);

    final saved = await ChatQuizProgressRepository(box: box).load(_ownerUserId);
    expect(saved.answers['q-0'], isNotNull);

    // 題目改寫成 revision 2 之後重進同一關。
    await _pump(tester, catalog: _catalog(revision: 2), progressBox: box);
    expect(find.text('第 1 題 / 共 3 題'), findsOneWidget);
    expect(
      find.text(kChatQuizCorrectLabel),
      findsNothing,
      reason: '題目改寫後不得顯示上一版的作答結果',
    );
    expect(find.text('送出答案'), findsOneWidget);
  });

  testWidgets('回到同一關會接續在第一個還沒答的題目', (tester) async {
    final box = InMemoryHiveBox();

    await _pump(tester, progressBox: box);
    await tester.tap(find.text('選項 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    await _pump(tester, progressBox: box);
    expect(find.text('第 2 題 / 共 3 題'), findsOneWidget);
  });

  testWidgets('系統字級放到最大不爆版（textScaler 3.0）', (tester) async {
    await _pump(
      tester,
      textScale: 3.0,
      size: const Size(320, 900),
    );

    await tester.tap(find.text('選項 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

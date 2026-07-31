// test/widget/features/learning/chat_quiz_map_test.dart
//
// 關卡地圖。守三件事：
//   1. 免費 / 付費 / Starter 三種視角各自看到什麼。
//   2. 訂閱狀態還在確認時**不得出現付費文案**——那個 bug 的外觀是「一開 App
//      就被推銷」，不是任何錯誤。
//   3. 付費入口只出現一次。同一個功能出現三次升級提示，讀起來就是在推銷。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/repositories/chat_quiz_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/screens/chat_quiz_map_screen.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

import '../../../helpers/chat_quiz_test_content.dart';
import '../../../helpers/chat_quiz_widget_harness.dart';
import '../../../helpers/ebook_widget_harness.dart'
    show InMemoryHiveBox, paywallStubText;

const _ownerUserId = 'quiz-harness-owner';

/// 兩群四關，形狀與第 1 期的正式內容一致。
ChatQuizCatalog _catalog({EbookAccess secondGroupAccess = EbookAccess.premium}) {
  return ChatQuizCatalog(
    groups: [
      buildTestChatQuizGroup(
        levels: [
          buildTestChatQuizLevel(
            id: 'quiz-level-1-1',
            number: '1-1',
            title: '她現在是哪一種',
            questions: [buildTestChatQuizQuestion(id: 'q-1-1-01')],
          ),
          buildTestChatQuizLevel(
            id: 'quiz-level-1-2',
            number: '1-2',
            title: '消極期先止損',
            access: EbookAccess.premium,
            questions: [buildTestChatQuizQuestion(id: 'q-1-2-01')],
          ),
        ],
      ),
      buildTestChatQuizGroup(
        id: 'quiz-group-2',
        number: 2,
        key: 'lifeline',
        title: '救對話',
        levels: [
          buildTestChatQuizLevel(
            id: 'quiz-level-2-1',
            number: '2-1',
            title: '對話死在哪',
            access: secondGroupAccess,
            questions: [buildTestChatQuizQuestion(id: 'q-2-1-01')],
          ),
          buildTestChatQuizLevel(
            id: 'quiz-level-2-2',
            number: '2-2',
            title: '情緒是開口',
            access: secondGroupAccess,
            questions: [buildTestChatQuizQuestion(id: 'q-2-2-01')],
          ),
        ],
      ),
    ],
  );
}

Future<ChatQuizHarness> _pump(
  WidgetTester tester, {
  ChatQuizCatalog? catalog,
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.free(),
  InMemoryHiveBox? progressBox,
}) async {
  final harness = await pumpChatQuizApp(
    tester,
    initialLocation: '/learning/quiz',
    catalog: catalog ?? _catalog(),
    access: access,
    progressBox: progressBox,
    mapBuilder: (_, __) => const ChatQuizMapScreen(),
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('免費帳號：1-1 可進、1-2 鎖、第 2 群整群鎖', (tester) async {
    await _pump(tester);

    expect(find.text('可以開始'), findsOneWidget);
    expect(find.text('需要訂閱'), findsNWidgets(3));

    await tester.tap(find.text('1-1　她現在是哪一種'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 題 / 共 1 題'), findsOneWidget);
  });

  testWidgets('免費帳號點鎖住的關卡不會進去', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('1-2　消極期先止損'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 題 / 共 1 題'), findsNothing);
    expect(find.text('1-2　消極期先止損'), findsOneWidget);
  });

  testWidgets('付費帳號：四關都不再上鎖，但群內仍是線性', (tester) async {
    await _pump(tester, access: const EbookSubscriptionAccess.premium());

    expect(find.text('需要訂閱'), findsNothing);
    // 1-1 與 2-1 是各群的第一關，直接可進；1-2、2-2 要先過上一關。
    expect(find.text('可以開始'), findsNWidgets(2));
    expect(find.text('先過上一關'), findsNWidgets(2));
  });

  testWidgets('過了 1-1 之後 1-2 才開，而且第 2 群不受影響', (tester) async {
    final box = InMemoryHiveBox();
    await ChatQuizProgressRepository(box: box).recordLevelResult(
      ownerUserId: _ownerUserId,
      levelId: 'quiz-level-1-1',
      correctCount: 1,
      questionCount: 1,
      passed: true,
    );

    await _pump(
      tester,
      access: const EbookSubscriptionAccess.premium(),
      progressBox: box,
    );

    // 1-1、1-2、2-1 都開；只有 2-2 還要先過 2-1。
    expect(find.text('可以開始'), findsNWidgets(3));
    expect(find.text('先過上一關'), findsOneWidget);
  });

  testWidgets('群跟群之間全開：沒過第 1 群也能進第 2 群的第一關', (tester) async {
    await _pump(tester, access: const EbookSubscriptionAccess.premium());

    await tester.tap(find.text('2-1　對話死在哪'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 題 / 共 1 題'), findsOneWidget);
  });

  testWidgets('isResolving：不顯示任何付費文案，只給中性 loading', (tester) async {
    await _pump(tester, access: const EbookSubscriptionAccess.resolving());

    expect(find.text('需要訂閱'), findsNothing);
    expect(find.text('看訂閱方案'), findsNothing);
    expect(find.text('正在確認你的訂閱狀態…'), findsNWidgets(3));
  });

  testWidgets('付費入口只出現一次', (tester) async {
    await _pump(tester);

    expect(find.text('看訂閱方案'), findsOneWidget);

    await tester.tap(find.text('看訂閱方案'));
    await tester.pumpAndSettle();
    expect(find.text(paywallStubText), findsOneWidget);
  });

  testWidgets('Starter 看不到 essential 取材的關卡', (tester) async {
    // 第 1 期沒有 essential 關卡，這條先把行為釘住，第 2 期會用到。
    await _pump(
      tester,
      catalog: _catalog(secondGroupAccess: EbookAccess.essential),
      access: const EbookSubscriptionAccess.premium(),
    );

    expect(find.text('1-1　她現在是哪一種'), findsOneWidget);
    expect(find.text('2-1　對話死在哪'), findsNothing);
    expect(find.text('2-2　情緒是開口'), findsNothing);
  });

  testWidgets('Essential 看得到 essential 取材的關卡', (tester) async {
    await _pump(
      tester,
      catalog: _catalog(secondGroupAccess: EbookAccess.essential),
      access: const EbookSubscriptionAccess.essential(),
    );

    expect(find.text('2-1　對話死在哪'), findsOneWidget);
  });

  testWidgets('第 3–5 群完全不出現在畫面上', (tester) async {
    await _pump(tester);

    expect(find.textContaining('3-1'), findsNothing);
    expect(find.textContaining('即將推出'), findsNothing);
    expect(find.text('讀燈'), findsOneWidget);
    expect(find.text('救對話'), findsOneWidget);
  });

  testWidgets('已通過的關卡顯示最佳成績', (tester) async {
    final box = InMemoryHiveBox();
    await ChatQuizProgressRepository(box: box).recordLevelResult(
      ownerUserId: _ownerUserId,
      levelId: 'quiz-level-1-1',
      correctCount: 1,
      questionCount: 1,
      passed: true,
    );

    await _pump(tester, progressBox: box);
    expect(find.text('最佳 1 / 1'), findsOneWidget);
  });

  testWidgets('內容載入失敗時顯示錯誤，不假裝沒有關卡', (tester) async {
    await pumpChatQuizApp(
      tester,
      initialLocation: '/learning/quiz',
      catalogError: StateError('boom'),
      mapBuilder: (_, __) => const ChatQuizMapScreen(),
    );
    await tester.pumpAndSettle();

    expect(find.text('關卡載入失敗'), findsOneWidget);
  });

  testWidgets('從別的頁 push 進來時，畫面上有回上一頁的入口', (tester) async {
    final harness = await pumpChatQuizApp(
      tester,
      initialLocation: '/',
      catalog: _catalog(),
      access: const EbookSubscriptionAccess.free(),
      mapBuilder: (_, __) => const ChatQuizMapScreen(),
    );
    await tester.pumpAndSettle();

    harness.router.push('/learning/quiz');
    await tester.pumpAndSettle();
    expect(find.text('判讀訓練場'), findsOneWidget);

    // 回上一頁的入口：AppBar 左上角的返回鍵。
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('HOME_STUB'), findsOneWidget);
  });

  testWidgets('deep link 直接進來也有出口：返回鍵退回學習頁', (tester) async {
    // 沒有可 pop 的 route 時，AppBar 的 automaticallyImplyLeading 不會給返回鍵。
    // 這一條就是那個死角的守門。
    final harness = await _pump(tester);

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(harness.location, startsWith('/'));
    expect(find.text('判讀訓練場'), findsNothing);
  });
}

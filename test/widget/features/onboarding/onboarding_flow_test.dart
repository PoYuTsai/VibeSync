// test/widget/features/onboarding/onboarding_flow_test.dart
//
// onboarding 轉換第 12 步：9 頁改 4 頁（選路徑 → 一題判讀 → 目標 → 登入後做什麼）。
// 這支測整條流程：頁數、換頁、三條路徑的目的地、未登入時寫暫存、每頁的逃生出口
// （我有帳號／先逛逛／直接開始／略過）、系統返回鍵與漏斗事件。
// 用無 redirect 的 stub GoRouter 驗證真實導流落點＋SharedPreferences 寫入。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/onboarding/data/onboarding_quiz.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/domain/onboarding_intent.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_finish_page.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_intent_page.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_questionnaire_page.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_quiz_teaser_page.dart';

import '../../../helpers/chat_quiz_test_content.dart';
import '../../../helpers/onboarding_test_harness.dart';

const _uid = 'test-uid';

late ChatQuizCatalog _catalog;

ChatQuizQuestion get _question =>
    _catalog.findQuestion(kOnboardingQuizQuestionId)!;

Future<Map<String, Object?>> _storedHandoff() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(OnboardingService.pendingHandoffKey);
  expect(raw, isNotNull, reason: '應該寫了交接暫存');
  return (jsonDecode(raw!) as Map).cast<String, Object?>();
}

void main() {
  setUpAll(() async {
    _catalog = await loadProductionChatQuizCatalog();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OnboardingService.reset();
  });

  group('頁面結構', () {
    testWidgets('第 1 頁：4 顆頁數點、三條路徑、先逛逛、右上我有帳號；沒有上一頁與底部按鈕', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);

      expect(find.text(OnboardingIntentPage.title), findsOneWidget);
      expect(find.text('我是 Sydney，你的 AI 戀愛教練'), findsOneWidget);
      for (final option in OnboardingIntentPage.options) {
        expect(find.text(option.title), findsOneWidget);
        expect(find.text(option.subtitle), findsOneWidget);
      }
      expect(find.text(OnboardingIntentPage.browseLabel), findsOneWidget);
      expect(find.text(OnboardingScreen.haveAccountLabel), findsOneWidget);
      expect(find.byTooltip('上一頁'), findsNothing);
      expect(find.text(OnboardingScreen.nextLabel), findsNothing);
      expect(find.text(OnboardingScreen.finishLabel), findsNothing);
      final dots = find.descendant(
        of: find.byKey(const ValueKey('onboarding-page-dots')),
        matching: find.byType(AnimatedContainer),
      );
      expect(dots, findsNWidgets(OnboardingScreen.pageCount));
    });

    testWidgets('功能介紹 6 頁與獨立隱私頁都拿掉了', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);

      for (final oldTitle in [
        '不知道怎麼回她？',
        '即時看懂她的訊號',
        '該回的時候給你 3–5 張回覆',
        '還沒有對象？先練',
        '越用越會聊',
        '不只教你回這句',
        'AI 與你的隱私',
        '你現在有正在聊的對象嗎？',
      ]) {
        expect(find.text(oldTitle), findsNothing, reason: oldTitle);
      }
    });

    testWidgets('選路徑才往下走：換頁只能按，不能滑', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text(OnboardingIntentPage.title), findsOneWidget);

      await chooseIntent(tester, OnboardingIntent.analyze);
      expect(find.text(OnboardingQuizTeaserPage.title), findsOneWidget);
      expect(find.byTooltip('上一頁'), findsOneWidget);
      expect(find.text(OnboardingScreen.skipQuizLabel), findsOneWidget);
    });

    testWidgets('上一頁回到第 1 頁，剛選的路徑標成已選', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);
      final semantics = tester.ensureSemantics();

      await chooseIntent(tester, OnboardingIntent.opener);
      await tester.tap(find.byTooltip('上一頁'));
      await tester.pumpAndSettle();

      expect(find.text(OnboardingIntentPage.title), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('onboarding-intent-opener')),
        ),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('onboarding-intent-analyze')),
        ),
        isSemantics(isSelected: false),
      );
      semantics.dispose();
    });

    testWidgets('讀屏：三條路徑都點得到，點了跟手點一樣換到第 2 頁（主審 r1 P2）', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);
      final semantics = tester.ensureSemantics();

      for (final option in OnboardingIntentPage.options) {
        await semanticsTap(
          tester,
          find.byKey(ValueKey('onboarding-intent-${option.intent.wire}')),
        );
        expect(
          find.text(OnboardingQuizTeaserPage.title),
          findsOneWidget,
          reason: option.intent.wire,
        );
        await tester.tap(find.byTooltip('上一頁'));
        await tester.pumpAndSettle();
      }
      semantics.dispose();
    });

    testWidgets('系統返回鍵：第 2 頁回第 1 頁，不離開 onboarding', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);
      await chooseIntent(tester, OnboardingIntent.practice);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(OnboardingIntentPage.title), findsOneWidget);
    });

    testWidgets('第 2、3 頁按「下一步」換頁；第 4 頁按鈕是「繼續」、右上沒有逃生字', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);
      await chooseIntent(tester, OnboardingIntent.analyze);
      await tester.tap(find.byKey(
          ValueKey('onboarding-quiz-choice-${_question.choices.first.id}')));
      await tester.pumpAndSettle();
      await tapLabel(tester, OnboardingScreen.nextLabel);
      expect(find.text(OnboardingQuestionnairePage.title), findsOneWidget);
      expect(
        find.text(OnboardingScreen.skipQuestionnaireLabel),
        findsOneWidget,
      );

      await tapLabel(tester, OnboardingScreen.nextLabel);
      expect(find.text(OnboardingScreen.finishLabel), findsOneWidget);
      expect(find.text(OnboardingScreen.nextLabel), findsNothing);
      expect(find.text(OnboardingScreen.skipQuestionnaireLabel), findsNothing);
      expect(find.text(OnboardingScreen.skipQuizLabel), findsNothing);
      expect(find.text(OnboardingScreen.haveAccountLabel), findsNothing);
    });
  });

  group('三條路徑的目的地（已登入：直接種、直接帶過去）', () {
    for (final (intent, landing) in [
      (OnboardingIntent.analyze, 'partner-new-screen next=screenshot'),
      (OnboardingIntent.opener, openerStubText),
      (OnboardingIntent.practice, 'practice-collection-screen guide=1'),
    ]) {
      testWidgets('${intent.wire} → $landing，返回回到首頁', (tester) async {
        final app = await pumpOnboardingApp(tester,
            catalog: _catalog, signedInUid: _uid);
        await goToFinishPage(tester, intent);
        await tapLabel(tester, OnboardingScreen.finishLabel);

        expect(find.text(landing), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('onboarding_completed'), isTrue);
        // 已登入不寫暫存。
        expect(prefs.containsKey(OnboardingService.pendingHandoffKey), isFalse);

        // 先 go('/') 再 push：返回落在首頁，不是 onboarding。
        app.router.pop();
        await tester.pumpAndSettle();
        expect(find.text(mainShellStubText), findsOneWidget);
      });
    }

    test('路徑對應表：先逛逛沒有目的地', () {
      expect(
        OnboardingScreen.routeForIntent(OnboardingIntent.analyze),
        '/partner/new?next=screenshot',
      );
      expect(
          OnboardingScreen.routeForIntent(OnboardingIntent.opener), '/opener');
      expect(
        OnboardingScreen.routeForIntent(OnboardingIntent.practice),
        '/practice-collection?guide=1',
      );
      expect(OnboardingScreen.routeForIntent(OnboardingIntent.browse), isNull);
    });
  });

  group('未登入完成 onboarding（onboarding 先於登入）', () {
    testWidgets('繼續 → 寫新格式暫存（路徑、目的地、目標、答對沒有、時間）→ 回到 /，不直接 push',
        (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);
      await chooseIntent(tester, OnboardingIntent.analyze);
      final correctId = _question.correctChoice.id;
      await tester
          .tap(find.byKey(ValueKey('onboarding-quiz-choice-$correctId')));
      await tester.pumpAndSettle();
      await tapLabel(tester, OnboardingScreen.nextLabel);
      await tester
          .tap(find.byKey(const ValueKey('onboarding-goal-softInvite')));
      await tester.pumpAndSettle();
      await tapLabel(tester, OnboardingScreen.nextLabel);
      final before = DateTime.now().toUtc();
      await tapLabel(tester, OnboardingScreen.finishLabel);

      // 未登入：只回到 '/'（真實 App 會被 redirect 轉去 /login），不 push 目的地。
      expect(find.text(mainShellStubText), findsOneWidget);
      expect(find.textContaining('partner-new-screen'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);

      final stored = await _storedHandoff();
      expect(stored['version'], OnboardingService.pendingHandoffVersion);
      expect(stored['intent'], 'analyze');
      expect(stored['route'], '/partner/new?next=screenshot');
      expect(stored['goals'], ['softInvite']);
      expect(stored['quizCorrect'], isTrue);
      final stashedAt = DateTime.parse(stored['stashedAt']! as String);
      expect(stashedAt.isUtc, isTrue);
      expect(
        stashedAt.difference(before).inMinutes.abs(),
        lessThan(1),
      );
      // 舊鍵不再寫。
      expect(prefs.containsKey('onboarding_pending_route'), isFalse);
      expect(prefs.containsKey('onboarding_pending_goals'), isFalse);
    });

    testWidgets('答錯也記在暫存；按「直接開始」跳過就是 null', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);
      await chooseIntent(tester, OnboardingIntent.practice);
      final wrong = _question.choices
          .firstWhere((choice) => !_question.isCorrectChoice(choice.id));
      await tester
          .tap(find.byKey(ValueKey('onboarding-quiz-choice-${wrong.id}')));
      await tester.pumpAndSettle();
      await tapLabel(tester, OnboardingScreen.nextLabel);
      await tapLabel(tester, OnboardingScreen.nextLabel);
      await tapLabel(tester, OnboardingScreen.finishLabel);

      final stored = await _storedHandoff();
      expect(stored['intent'], 'practice');
      expect(stored['route'], '/practice-collection?guide=1');
      expect(stored['goals'], isEmpty);
      expect(stored['quizCorrect'], isFalse);
    });

    testWidgets('「直接開始」跳過測驗：暫存的 quizCorrect 是 null', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);
      await goToFinishPage(tester, OnboardingIntent.opener);
      await tapLabel(tester, OnboardingScreen.finishLabel);

      final stored = await _storedHandoff();
      expect(stored['intent'], 'opener');
      expect(stored['route'], '/opener');
      expect(stored.containsKey('quizCorrect'), isTrue);
      expect(stored['quizCorrect'], isNull);
    });
  });

  group('逃生出口', () {
    testWidgets('「我有帳號」：記成看過 onboarding、直接到 /login、不寫暫存、不記略過', (tester) async {
      final app = await pumpOnboardingApp(tester, catalog: _catalog);

      await tapLabel(tester, OnboardingScreen.haveAccountLabel);

      expect(find.text(loginStubText), findsOneWidget);
      expect(OnboardingService.isCompletedSync, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);
      expect(prefs.containsKey(OnboardingService.pendingHandoffKey), isFalse);
      expect(app.funnel.names, isNot(contains('onboarding_skip')));
      expect(app.funnel.names, isNot(contains('onboarding_intent')));
    });

    testWidgets('「先逛逛」：記 intent=browse 與 onboarding_skip(0)、回到 /、不寫暫存',
        (tester) async {
      final app = await pumpOnboardingApp(tester, catalog: _catalog);

      await tapLabel(tester, OnboardingIntentPage.browseLabel);

      expect(find.text(mainShellStubText), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);
      expect(prefs.containsKey(OnboardingService.pendingHandoffKey), isFalse);
      expect(app.funnel.propsOf('onboarding_intent'), [
        {'intent': 'browse'},
      ]);
      expect(app.funnel.propsOf('onboarding_skip'), [
        {'page_index': 0},
      ]);
    });

    testWidgets('「直接開始」：跳過測驗與目標，直接到第 4 頁', (tester) async {
      final app = await pumpOnboardingApp(tester, catalog: _catalog);
      await goToFinishPage(tester, OnboardingIntent.analyze);

      expect(find.text(OnboardingScreen.finishLabel), findsOneWidget);
      expect(find.text(OnboardingFinishPage.goalsLine), findsNothing);
      expect(app.funnel.names, isNot(contains('onboarding_quiz_answer')));
      // 跳頁不滑過第 3 頁：page_view 只記 0、1、3。
      expect(app.funnel.propsOf('onboarding_page_view'), [
        {'page_index': 0},
        {'page_index': 1},
        {'page_index': 3},
      ]);
      expect(app.funnel.names, isNot(contains('onboarding_skip')));
    });

    testWidgets('第 3 頁「略過」：清掉已選的目標，到第 4 頁沒有目標那一行', (tester) async {
      await pumpOnboardingApp(tester, catalog: _catalog);
      await chooseIntent(tester, OnboardingIntent.analyze);
      await tester.tap(find.byKey(
          ValueKey('onboarding-quiz-choice-${_question.choices.first.id}')));
      await tester.pumpAndSettle();
      await tapLabel(tester, OnboardingScreen.nextLabel);
      await tester
          .tap(find.byKey(const ValueKey('onboarding-goal-softInvite')));
      await tester.pumpAndSettle();

      await tapLabel(tester, OnboardingScreen.skipQuestionnaireLabel);
      expect(find.text(OnboardingScreen.finishLabel), findsOneWidget);
      expect(find.text(OnboardingFinishPage.goalsLine), findsNothing);

      await tapLabel(tester, OnboardingScreen.finishLabel);
      final stored = await _storedHandoff();
      expect(stored['goals'], isEmpty);
    });
  });

  group('漏斗事件', () {
    testWidgets('page_view 0–3：每換一頁一筆，按上一頁也記；路徑每選一次記一筆', (tester) async {
      final app = await pumpOnboardingApp(tester, catalog: _catalog);

      await chooseIntent(tester, OnboardingIntent.analyze);
      await tester.tap(find.byTooltip('上一頁'));
      await tester.pumpAndSettle();
      await chooseIntent(tester, OnboardingIntent.practice);
      final correctId = _question.correctChoice.id;
      await tester
          .tap(find.byKey(ValueKey('onboarding-quiz-choice-$correctId')));
      await tester.pumpAndSettle();
      await tapLabel(tester, OnboardingScreen.nextLabel);
      await tapLabel(tester, OnboardingScreen.nextLabel);

      expect(
        [
          for (final props in app.funnel.propsOf('onboarding_page_view'))
            props['page_index'],
        ],
        [0, 1, 0, 1, 2, 3],
      );
      expect(app.funnel.propsOf('onboarding_intent'), [
        {'intent': 'analyze'},
        {'intent': 'practice'},
      ]);
      expect(app.funnel.propsOf('onboarding_quiz_answer'), [
        {'correct': true},
      ]);
    });

    testWidgets('繼續時送 questionnaire_submit（目標數），不再送分流答案', (tester) async {
      final app = await pumpOnboardingApp(tester, catalog: _catalog);
      await chooseIntent(tester, OnboardingIntent.opener);
      await tester.tap(find.byKey(
          ValueKey('onboarding-quiz-choice-${_question.choices.last.id}')));
      await tester.pumpAndSettle();
      await tapLabel(tester, OnboardingScreen.nextLabel);
      await tester
          .tap(find.byKey(const ValueKey('onboarding-goal-softInvite')));
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('onboarding-goal-humorousReply')));
      await tester.pumpAndSettle();
      await tapLabel(tester, OnboardingScreen.nextLabel);
      await tapLabel(tester, OnboardingScreen.finishLabel);

      expect(app.funnel.propsOf('onboarding_questionnaire_submit'), [
        {'goals_count': 2},
      ]);
      expect(app.funnel.names, isNot(contains('onboarding_branch_answer')));
    });

    // 行為鎖：PageView 換頁動畫期間本來就不收點擊（Scrollable 動畫中忽略指標），
    // _selectIntent 只在第 1 頁收是第二道防線；兩者任一在，結果都要是這樣。
    testWidgets('換頁動畫期間連點第二條路徑：不多記一筆、不多跳一頁', (tester) async {
      final app = await pumpOnboardingApp(tester, catalog: _catalog);

      await tester.tap(find.byKey(const ValueKey('onboarding-intent-analyze')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(
        find.byKey(const ValueKey('onboarding-intent-practice')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text(OnboardingQuizTeaserPage.title), findsOneWidget);
      expect(app.funnel.propsOf('onboarding_intent'), [
        {'intent': 'analyze'},
      ]);
    });
  });

  testWidgets('小螢幕（375×667）每一頁都不 overflow', (tester) async {
    await pumpOnboardingApp(
      tester,
      catalog: _catalog,
      size: const Size(375, 667),
    );
    await chooseIntent(tester, OnboardingIntent.analyze);
    final correctId = _question.correctChoice.id;
    await tester.tap(find.byKey(ValueKey('onboarding-quiz-choice-$correctId')));
    await tester.pumpAndSettle();
    await tapLabel(tester, OnboardingScreen.nextLabel);
    await tester.tap(find.byKey(const ValueKey('onboarding-goal-softInvite')));
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('onboarding-goal-humorousReply')));
    await tester.pumpAndSettle();
    // 兩個目標的鏡像卡都撐開了，還是排得下（排不下會捲動）。
    expect(
        find.byKey(const ValueKey('onboarding-mirror-card')), findsOneWidget);
    await tapLabel(tester, OnboardingScreen.nextLabel);

    expect(find.text(OnboardingScreen.finishLabel), findsOneWidget);
    expect(find.text(OnboardingFinishPage.goalsLine), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// test/widget/features/onboarding/onboarding_quiz_teaser_page_test.dart
//
// onboarding 轉換第 12 步第 2 頁：內建聊天測驗題庫的一題判讀（kOnboardingQuizQuestionId）。
//   - 顯示情境、題目、選項；作答前不洩漏對錯。
//   - 點一個就定案：只展開選的那個選項的 feedback，加上整題 takeaway。
//   - 對錯用 isCorrectChoice 判斷，不看位置（ADR #36：正解位置是打散的）。
//   - 記 onboarding_quiz_answer {correct}；作答前「下一步」不能按。
//   - 題庫讀不到或找不到這一題：一句說明，「下一步」照樣能按。
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/presentation/widgets/chat_quiz_question_card.dart'
    show kChatQuizCorrectLabel, kChatQuizIncorrectLabel, kChatQuizYourPickLabel;
import 'package:vibesync/features/onboarding/data/onboarding_quiz.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/domain/onboarding_intent.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_questionnaire_page.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_quiz_teaser_page.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';

import '../../../helpers/chat_quiz_test_content.dart';
import '../../../helpers/onboarding_test_harness.dart';

late ChatQuizCatalog _production;

ChatQuizQuestion get _realQuestion =>
    _production.findQuestion(kOnboardingQuizQuestionId)!;

Finder _choice(String choiceId) =>
    find.byKey(ValueKey('onboarding-quiz-choice-$choiceId'));

BrandPrimaryButton _nextButton(WidgetTester tester) => tester.widget(
      find.widgetWithText(BrandPrimaryButton, OnboardingScreen.nextLabel),
    );

/// 只有一題、正解放在第 [correctIndex] 個的小題庫（題號跟正式的一樣）。
ChatQuizCatalog _fixtureCatalog({int correctIndex = 2}) => ChatQuizCatalog(
      groups: [
        buildTestChatQuizGroup(
          levels: [
            buildTestChatQuizLevel(
              questions: [
                buildTestChatQuizQuestion(
                  id: kOnboardingQuizQuestionId,
                  correctIndex: correctIndex,
                ),
              ],
            ),
          ],
        ),
      ],
    );

Future<OnboardingHarness> _pumpQuizPage(
  WidgetTester tester, {
  ChatQuizCatalog? catalog,
  Object? catalogError,
}) async {
  final app = await pumpOnboardingApp(
    tester,
    catalog: catalog ?? _production,
    catalogError: catalogError,
  );
  await chooseIntent(tester, OnboardingIntent.analyze);
  expect(find.text(OnboardingQuizTeaserPage.title), findsOneWidget);
  return app;
}

void main() {
  setUpAll(() async {
    _production = await loadProductionChatQuizCatalog();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OnboardingService.reset();
  });

  testWidgets('用內建題庫那一題：情境、題目、選項、出處關號；作答前沒有解析、下一步不能按', (tester) async {
    await _pumpQuizPage(tester);

    expect(find.text(_realQuestion.scenario!), findsOneWidget);
    expect(find.text(_realQuestion.question), findsOneWidget);
    for (final choice in _realQuestion.choices) {
      expect(find.text(choice.text), findsOneWidget);
      expect(find.text(choice.feedback), findsNothing);
    }
    expect(find.text('取自聊天測驗 1-1'), findsOneWidget);
    expect(find.text(_realQuestion.takeaway), findsNothing);
    expect(find.text(kChatQuizCorrectLabel), findsNothing);
    expect(find.text(OnboardingQuizTeaserPage.bridgeLine), findsNothing);
    expect(_nextButton(tester).onPressed, isNull);
  });

  testWidgets('答對：只展開選的那個的解析＋重點，標「正確 · 你的選擇」，記 correct=true', (tester) async {
    final app = await _pumpQuizPage(tester);
    final correct = _realQuestion.correctChoice;

    await tester.tap(_choice(correct.id));
    await tester.pumpAndSettle();

    expect(find.text('答對了'), findsOneWidget);
    expect(find.text(correct.feedback), findsOneWidget);
    expect(find.text(_realQuestion.takeaway), findsOneWidget);
    for (final other
        in _realQuestion.choices.where((c) => c.id != correct.id)) {
      expect(find.text(other.feedback), findsNothing, reason: other.id);
    }
    expect(find.text(kChatQuizCorrectLabel), findsOneWidget);
    expect(find.text(kChatQuizYourPickLabel), findsOneWidget);
    expect(find.text(kChatQuizIncorrectLabel), findsNothing);
    expect(find.text(OnboardingQuizTeaserPage.bridgeLine), findsOneWidget);
    expect(app.funnel.propsOf('onboarding_quiz_answer'), [
      {'correct': true},
    ]);
    expect(_nextButton(tester).onPressed, isNotNull);
  });

  testWidgets('答錯：顯示選的那個的 feedback、整題重點；正解標「正確」，記 correct=false',
      (tester) async {
    final app = await _pumpQuizPage(tester);
    final wrong = _realQuestion.choices
        .firstWhere((choice) => !_realQuestion.isCorrectChoice(choice.id));

    await tester.tap(_choice(wrong.id));
    await tester.pumpAndSettle();

    expect(find.text('這一題再看一次'), findsOneWidget);
    expect(find.text(wrong.feedback), findsOneWidget);
    expect(find.text(_realQuestion.correctChoice.feedback), findsNothing);
    expect(find.text(_realQuestion.takeaway), findsOneWidget);
    // 正解與選錯的都有文字標籤，不只靠顏色。
    expect(find.text(kChatQuizCorrectLabel), findsOneWidget);
    expect(find.text(kChatQuizIncorrectLabel), findsOneWidget);
    expect(find.text(kChatQuizYourPickLabel), findsOneWidget);
    expect(app.funnel.propsOf('onboarding_quiz_answer'), [
      {'correct': false},
    ]);
  });

  testWidgets('讀屏：作答前選項點得到、點了跟手點一樣定案；作答後就點不到（主審 r1 P2）', (tester) async {
    final app = await _pumpQuizPage(tester);
    final semantics = tester.ensureSemantics();
    final correct = _realQuestion.correctChoice;

    await semanticsTap(tester, _choice(correct.id));

    expect(find.text('答對了'), findsOneWidget);
    expect(app.funnel.propsOf('onboarding_quiz_answer'), [
      {'correct': true},
    ]);
    for (final choice in _realQuestion.choices) {
      expect(
        tester
            .getSemantics(_choice(choice.id))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
        reason: choice.id,
      );
    }
    semantics.dispose();
  });

  testWidgets('對錯不看位置：正解放在第 3 個也判得對，第 1 個是錯的', (tester) async {
    final catalog = _fixtureCatalog(correctIndex: 2);
    final question = catalog.findQuestion(kOnboardingQuizQuestionId)!;
    final app = await _pumpQuizPage(tester, catalog: catalog);

    await tester.tap(_choice(question.choices.first.id));
    await tester.pumpAndSettle();
    expect(find.text('這一題再看一次'), findsOneWidget);
    expect(app.funnel.propsOf('onboarding_quiz_answer'), [
      {'correct': false},
    ]);
  });

  testWidgets('對錯不看位置：選第 3 個（正解）判答對', (tester) async {
    final catalog = _fixtureCatalog(correctIndex: 2);
    final question = catalog.findQuestion(kOnboardingQuizQuestionId)!;
    final app = await _pumpQuizPage(tester, catalog: catalog);

    await tester.tap(_choice(question.choices.last.id));
    await tester.pumpAndSettle();
    expect(find.text('答對了'), findsOneWidget);
    expect(app.funnel.propsOf('onboarding_quiz_answer'), [
      {'correct': true},
    ]);
  });

  testWidgets('作答一次就定案：再點別的選項不改答案、不再記事件', (tester) async {
    final app = await _pumpQuizPage(tester);
    final correct = _realQuestion.correctChoice;
    final wrong = _realQuestion.choices
        .firstWhere((choice) => !_realQuestion.isCorrectChoice(choice.id));

    await tester.tap(_choice(correct.id));
    await tester.pumpAndSettle();
    await tester.tap(_choice(wrong.id), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('答對了'), findsOneWidget);
    expect(find.text(wrong.feedback), findsNothing);
    expect(app.funnel.propsOf('onboarding_quiz_answer'), hasLength(1));
  });

  testWidgets('作答後回上一頁再回來：答案還在，不重記', (tester) async {
    final app = await _pumpQuizPage(tester);
    final correct = _realQuestion.correctChoice;
    await tester.tap(_choice(correct.id));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('上一頁'));
    await tester.pumpAndSettle();
    await chooseIntent(tester, OnboardingIntent.analyze);

    expect(find.text('答對了'), findsOneWidget);
    expect(app.funnel.propsOf('onboarding_quiz_answer'), hasLength(1));
  });

  testWidgets('作答後「下一步」到目標頁', (tester) async {
    await _pumpQuizPage(tester);
    await tester.tap(_choice(_realQuestion.choices.first.id));
    await tester.pumpAndSettle();

    await tapLabel(tester, OnboardingScreen.nextLabel);
    expect(find.text(OnboardingQuestionnairePage.title), findsOneWidget);
  });

  testWidgets('題庫讀不到：一句說明，「下一步」照樣能按', (tester) async {
    await _pumpQuizPage(
      tester,
      catalogError: StateError('題庫壞了'),
    );

    expect(find.text(OnboardingQuizTeaserPage.unavailableText), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-quiz-card')), findsNothing);
    expect(_nextButton(tester).onPressed, isNotNull);
    await tapLabel(tester, OnboardingScreen.nextLabel);
    expect(find.text(OnboardingQuestionnairePage.title), findsOneWidget);
  });

  testWidgets('題庫裡找不到這一題：一樣顯示說明、不擋路', (tester) async {
    await _pumpQuizPage(tester, catalog: buildTestChatQuizCatalog());

    expect(find.text(OnboardingQuizTeaserPage.unavailableText), findsOneWidget);
    expect(_nextButton(tester).onPressed, isNotNull);
  });
}

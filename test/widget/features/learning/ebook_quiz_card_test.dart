// test/widget/features/learning/ebook_quiz_card_test.dart
//
// Quiz 卡：單選／複選、提交前不揭示正解、feedback、retry、restore、
// 正誤不只靠顏色、大字級不 overflow。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';
import 'package:vibesync/features/learning/domain/models/ebook_progress.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_quiz_card.dart';

import '../../../helpers/ebook_test_content.dart';

const _wrong = '辛苦了';
const _right = '發生什麼事，是人的問題還是事的問題';
const _third = '那你早點休息';

class QuizRecorder {
  final submissions = <({Set<String> choiceIds, bool solved})>[];

  void call(Set<String> choiceIds, bool solved) {
    submissions.add((choiceIds: choiceIds, solved: solved));
  }
}

Future<QuizRecorder> pumpQuiz(
  WidgetTester tester, {
  EbookQuizBlock? quiz,
  EbookQuizState? savedState,
  double textScale = 1.0,
  Size size = const Size(390, 900),
}) async {
  final recorder = QuizRecorder();
  // setSurfaceSize 才會真的改 layout 約束（MediaQueryData.size 單獨改不會）。
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: widget!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: EbookQuizCard(
              quiz: quiz ?? buildTestQuiz(),
              savedState: savedState,
              onSubmit: recorder.call,
            ),
          ),
        ),
      ),
    ),
  );
  return recorder;
}

void main() {
  testWidgets('single choice: no answer revealed before submit', (tester) async {
    await pumpQuiz(tester);

    expect(find.text('情境測驗 · 單選'), findsOneWidget);
    expect(find.text('正確'), findsNothing);
    expect(find.text('不是這個'), findsNothing);
    expect(find.text('往情緒走，而且給了超好答的框架。'), findsNothing);

    // 未選任何選項時送出鍵是 disabled。
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('single choice keeps only one selection', (tester) async {
    await pumpQuiz(tester);

    await tester.tap(find.text(_wrong));
    await tester.pump();
    expect(
      tester.widget<Icon>(find.byIcon(Icons.radio_button_checked)),
      isNotNull,
    );
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

    await tester.tap(find.text(_right));
    await tester.pump();
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
  });

  testWidgets('wrong answer shows feedback and allows a retry', (tester) async {
    final recorder = await pumpQuiz(tester);

    await tester.tap(find.text(_wrong));
    await tester.pump();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    expect(recorder.submissions, hasLength(1));
    expect(recorder.submissions.single.solved, isFalse);
    expect(recorder.submissions.single.choiceIds, {'quiz-1-a'});

    // 正誤同時有圖示與文字，不只靠顏色。
    expect(find.text('再想想'), findsOneWidget);
    expect(find.byIcon(Icons.highlight_off), findsWidgets);
    expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
    expect(find.text('這是終結句，對話無處可去。'), findsOneWidget);
    expect(find.text('往情緒走，而且給了超好答的框架。'), findsOneWidget);
    expect(find.text('情緒是開口，事實是死路。'), findsOneWidget);
    expect(find.text('· 你的選擇'), findsOneWidget);

    await tester.tap(find.text('再試一次'));
    await tester.pumpAndSettle();

    expect(find.text('送出答案'), findsOneWidget);
    expect(find.text('這是終結句，對話無處可去。'), findsNothing);

    await tester.tap(find.text(_right));
    await tester.pump();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    expect(recorder.submissions, hasLength(2));
    expect(recorder.submissions.last.solved, isTrue);
    expect(find.text('答對了'), findsOneWidget);
    expect(find.text('已理解'), findsOneWidget);
    // 答對後不再提供 retry。
    expect(find.text('再試一次'), findsNothing);
  });

  testWidgets('multiple choice needs the exact correct set', (tester) async {
    final quiz = buildTestQuiz(id: 'quiz-m', mode: EbookQuizMode.multiple);
    final recorder = await pumpQuiz(tester, quiz: quiz);

    expect(find.text('情境測驗 · 可多選'), findsOneWidget);

    await tester.tap(find.text(_right));
    await tester.pump();
    await tester.tap(find.text(_third));
    await tester.pump();
    expect(find.byIcon(Icons.check_box_outlined), findsNWidgets(2));

    // 取消其中一個再送出 → 不完整，應判未答對。
    await tester.tap(find.text(_third));
    await tester.pump();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    expect(recorder.submissions.single.choiceIds, {'quiz-m-b'});
    expect(recorder.submissions.single.solved, isFalse);
  });

  testWidgets('multiple choice with the full correct set is solved',
      (tester) async {
    final quiz = buildTestQuiz(id: 'quiz-m', mode: EbookQuizMode.multiple);
    final recorder = await pumpQuiz(tester, quiz: quiz);

    await tester.tap(find.text(_right));
    await tester.pump();
    await tester.tap(find.text(_third));
    await tester.pump();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    expect(recorder.submissions.single.solved, isTrue);
    expect(recorder.submissions.single.choiceIds, {'quiz-m-b', 'quiz-m-c'});
  });

  testWidgets('restores a saved solved answer', (tester) async {
    await pumpQuiz(
      tester,
      savedState: const EbookQuizState(
        quizRevision: 1,
        selectedChoiceIds: ['quiz-1-b'],
        solved: true,
      ),
    );

    expect(find.text('答對了'), findsOneWidget);
    expect(find.text('已理解'), findsOneWidget);
    expect(find.text('· 你的選擇'), findsOneWidget);
    expect(find.text('送出答案'), findsNothing);
  });

  testWidgets('restores a saved wrong answer and still offers a retry',
      (tester) async {
    await pumpQuiz(
      tester,
      savedState: const EbookQuizState(
        quizRevision: 1,
        selectedChoiceIds: ['quiz-1-a'],
        solved: false,
      ),
    );

    expect(find.text('再想想'), findsOneWidget);
    expect(find.text('再試一次'), findsOneWidget);
  });

  testWidgets('ignores stored choice ids that no longer exist', (tester) async {
    await pumpQuiz(
      tester,
      savedState: const EbookQuizState(
        quizRevision: 1,
        selectedChoiceIds: ['removed-choice'],
        solved: true,
      ),
    );

    // 舊 id 已不存在 → 視為未作答，重新讓使用者選。
    expect(find.text('送出答案'), findsOneWidget);
    expect(find.text('答對了'), findsNothing);
  });

  testWidgets('lockedAfterSubmit does not offer a retry', (tester) async {
    final quiz = buildTestQuiz(
      id: 'quiz-locked',
      retryPolicy: EbookQuizRetryPolicy.lockedAfterSubmit,
    );
    await pumpQuiz(tester, quiz: quiz);

    await tester.tap(find.text(_wrong));
    await tester.pump();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    expect(find.text('再想想'), findsOneWidget);
    expect(find.text('再試一次'), findsNothing);
  });

  testWidgets('選項在提交後不可再點', (tester) async {
    final recorder = await pumpQuiz(tester);

    await tester.tap(find.text(_wrong));
    await tester.pump();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_right));
    await tester.pumpAndSettle();
    expect(recorder.submissions, hasLength(1));
  });

  testWidgets('no overflow at 2.0 text scale on 320px width', (tester) async {
    await pumpQuiz(
      tester,
      textScale: 2.0,
      size: const Size(320, 2400),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(_wrong));
    await tester.pump();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

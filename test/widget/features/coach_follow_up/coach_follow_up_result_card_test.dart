// Spec 5 C21 — CoachFollowUpResultCard widget TDD spec.
//
// Renders the 5-field card stored in CoachFollowUpResult per design §1.3.
// Privacy / wire shape are owned upstream — this widget is presentation only:
// it does NOT call providers, the API service, or the repository.
//
// UI label mapping (design §1.3 table):
//   headline          → bold, no label
//   observation       → "我看到的重點"
//   task              → "這次建議你做"
//   suggestedLine     → "可以這樣說" (hidden when null — only optional field)
//   boundaryReminder  → "邊界提醒" (ALWAYS shown — required by schema)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_phase.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';
import 'package:vibesync/features/coach_follow_up/presentation/widgets/coach_follow_up_result_card.dart';

CoachFollowUpResult _result({
  String phase = 'prepareInvite',
  String headline = '不是話術問題，是節奏問題',
  String observation = '她回應仍在線但變短了一些',
  String task = '丟一個輕量提案',
  String? suggestedLine = '週六下午這家咖啡廳怎麼樣？',
  String boundaryReminder = '若她沒回，48 小時內不再追問',
}) =>
    CoachFollowUpResult(
      partnerId: 'p-1',
      phase: phase,
      headline: headline,
      observation: observation,
      task: task,
      suggestedLine: suggestedLine,
      boundaryReminder: boundaryReminder,
      generatedAt: DateTime.utc(2026, 5, 2, 18, 30),
      modelUsed: 'claude-sonnet-4-20250514',
    );

Future<void> _pump(WidgetTester tester, CoachFollowUpResult r) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CoachFollowUpResultCard(result: r),
      ),
    ),
  );
}

void main() {
  group('CoachFollowUpResultCard — required fields always rendered', () {
    testWidgets('renders headline content (bold, no label prefix)',
        (tester) async {
      await _pump(tester, _result(headline: '不是話術問題，是節奏問題'));

      expect(find.text('不是話術問題，是節奏問題'), findsOneWidget);
      // Headline has no UI label per design §1.3 — verify no label text
      // wraps it. The label "headline" or any "標題" etc. should not appear.
      expect(find.text('headline'), findsNothing);
      expect(find.text('標題'), findsNothing);
    });

    testWidgets('headline is rendered with bold weight', (tester) async {
      await _pump(tester, _result(headline: '不是話術問題，是節奏問題'));

      final textWidget =
          tester.widget<Text>(find.text('不是話術問題，是節奏問題'));
      expect(
        textWidget.style?.fontWeight,
        anyOf(FontWeight.w600, FontWeight.w700, FontWeight.bold),
        reason: 'design §1.3: headline displayed bold without label',
      );
    });

    testWidgets('renders observation with "我看到的重點" label', (tester) async {
      await _pump(tester, _result(observation: '她回應仍在線但變短'));

      expect(find.textContaining('我看到的重點'), findsOneWidget);
      expect(find.textContaining('她回應仍在線但變短'), findsOneWidget);
    });

    testWidgets('renders task with "這次建議你做" label', (tester) async {
      await _pump(tester, _result(task: '丟一個輕量提案'));

      expect(find.textContaining('這次建議你做'), findsOneWidget);
      expect(find.textContaining('丟一個輕量提案'), findsOneWidget);
    });

    testWidgets(
        'renders boundaryReminder with "邊界提醒" label (ALWAYS shown — '
        'required by schema)', (tester) async {
      await _pump(
        tester,
        _result(boundaryReminder: '若她沒回，48 小時內不再追問'),
      );

      expect(find.textContaining('邊界提醒'), findsOneWidget);
      expect(find.textContaining('48 小時內不再追問'), findsOneWidget);
    });
  });

  group('CoachFollowUpResultCard — suggestedLine optional behaviour', () {
    testWidgets('renders "可以這樣說" + content when suggestedLine is non-null',
        (tester) async {
      await _pump(tester, _result(suggestedLine: '週六下午咖啡？'));

      expect(find.textContaining('可以這樣說'), findsOneWidget);
      expect(find.textContaining('週六下午咖啡？'), findsOneWidget);
    });

    testWidgets('hides "可以這樣說" label entirely when suggestedLine is null',
        (tester) async {
      await _pump(tester, _result(suggestedLine: null));

      expect(find.textContaining('可以這樣說'), findsNothing);
    });

    testWidgets(
        'still shows boundaryReminder when suggestedLine is null '
        '(boundary is required, suggested is not)', (tester) async {
      await _pump(
        tester,
        _result(
          suggestedLine: null,
          boundaryReminder: '保留你的時間給更值得的人',
        ),
      );

      expect(find.textContaining('邊界提醒'), findsOneWidget);
      expect(find.textContaining('保留你的時間給更值得的人'), findsOneWidget);
    });
  });

  group('CoachFollowUpResultCard — phase header (繁中 displayLabel)', () {
    testWidgets('prepareInvite phase shows "準備邀約" header label',
        (tester) async {
      await _pump(
        tester,
        _result(phase: CoachFollowUpPhase.prepareInvite.name),
      );

      expect(find.text('準備邀約'), findsOneWidget);
    });

    testWidgets('preDateReminder phase shows "約會前提醒" header label',
        (tester) async {
      await _pump(
        tester,
        _result(phase: CoachFollowUpPhase.preDateReminder.name),
      );

      expect(find.text('約會前提醒'), findsOneWidget);
    });

    testWidgets('postDateReflection phase shows "約會後復盤" header label',
        (tester) async {
      await _pump(
        tester,
        _result(phase: CoachFollowUpPhase.postDateReflection.name),
      );

      expect(find.text('約會後復盤'), findsOneWidget);
    });

    testWidgets(
        'unknown / future phase string falls back to the raw stored value '
        '(graceful degradation — never shows a blank header)',
        (tester) async {
      // If the local Hive box pre-dates a phase enum rename, displayLabel
      // lookup returns null. Card must still render — show the raw key as
      // a fallback rather than a blank line.
      await _pump(tester, _result(phase: 'futurePhaseV2'));

      expect(find.text('futurePhaseV2'), findsOneWidget);
    });
  });
}

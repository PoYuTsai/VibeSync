import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import 'package:vibesync/shared/widgets/coaching_outcome_capture_card.dart';

CoachingOutcomeEvent _event({
  required CoachingUserAction userAction,
  required CoachingOutcomeSignal outcome,
}) {
  return CoachingOutcomeEvent(
    id: 'coach:r1',
    source: CoachingOutcomeSource.coach,
    suggestedMoveSummary: '約她週末看展',
    userAction: userAction,
    outcome: outcome,
    createdAt: DateTime(2026, 7, 6),
  );
}

Widget _harness({
  CoachingOutcomeEvent? event,
  ValueChanged<CoachingUserAction>? onUserActionSelected,
  ValueChanged<CoachingOutcomeSignal>? onOutcomeSelected,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CoachingOutcomeCaptureCard(
          event: event,
          onUserActionSelected: onUserActionSelected ?? (_) {},
          onOutcomeSelected: onOutcomeSelected ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  group('CoachingOutcomeCaptureCard', () {
    testWidgets(
      'shows only stage-1 chips and hides stage-2 when event is null',
      (tester) async {
        await tester.pumpWidget(_harness(event: null));

        expect(find.text('照著發了'), findsOneWidget);
        expect(find.text('改一改才發'), findsOneWidget);
        expect(find.text('沒有發'), findsOneWidget);
        expect(find.text('回頭問了教練'), findsOneWidget);

        expect(find.text('有接話'), findsNothing);
        expect(find.text('冷回'), findsNothing);
        expect(find.text('已讀沒回'), findsNothing);
        expect(find.text('反應不好'), findsNothing);
      },
    );

    testWidgets(
      'marks 照著發了 selected and reveals all 4 stage-2 chips when '
      'userAction=sentAsIs (outcome=pending)',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            event: _event(
              userAction: CoachingUserAction.sentAsIs,
              outcome: CoachingOutcomeSignal.pending,
            ),
          ),
        );

        final chip = tester.widget<ChoiceChip>(
          find.ancestor(
            of: find.text('照著發了'),
            matching: find.byType(ChoiceChip),
          ),
        );
        expect(chip.selected, isTrue);

        expect(find.text('有接話'), findsOneWidget);
        expect(find.text('冷回'), findsOneWidget);
        expect(find.text('已讀沒回'), findsOneWidget);
        expect(find.text('反應不好'), findsOneWidget);
      },
    );

    testWidgets(
      'hides stage-2 when userAction=didNotSend',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            event: _event(
              userAction: CoachingUserAction.didNotSend,
              outcome: CoachingOutcomeSignal.pending,
            ),
          ),
        );

        expect(find.text('有接話'), findsNothing);
        expect(find.text('冷回'), findsNothing);
        expect(find.text('已讀沒回'), findsNothing);
        expect(find.text('反應不好'), findsNothing);
      },
    );

    testWidgets(
      'hides stage-2 when userAction=askedCoach',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            event: _event(
              userAction: CoachingUserAction.askedCoach,
              outcome: CoachingOutcomeSignal.unknown,
            ),
          ),
        );

        expect(find.text('有接話'), findsNothing);
        expect(find.text('冷回'), findsNothing);
        expect(find.text('已讀沒回'), findsNothing);
        expect(find.text('反應不好'), findsNothing);
      },
    );

    testWidgets(
      'tapping 改一改才發 fires onUserActionSelected with editedAndSent',
      (tester) async {
        CoachingUserAction? selected;
        await tester.pumpWidget(
          _harness(
            event: null,
            onUserActionSelected: (action) => selected = action,
          ),
        );

        await tester.tap(find.text('改一改才發'));
        await tester.pump();

        expect(selected, CoachingUserAction.editedAndSent);
      },
    );

    testWidgets(
      'tapping 已讀沒回 fires onOutcomeSelected with noReply when '
      'userAction=editedAndSent (outcome=pending)',
      (tester) async {
        CoachingOutcomeSignal? selected;
        await tester.pumpWidget(
          _harness(
            event: _event(
              userAction: CoachingUserAction.editedAndSent,
              outcome: CoachingOutcomeSignal.pending,
            ),
            onOutcomeSelected: (signal) => selected = signal,
          ),
        );

        await tester.tap(find.text('已讀沒回'));
        await tester.pump();

        expect(selected, CoachingOutcomeSignal.noReply);
      },
    );

    testWidgets(
      'marks 有接話 selected when userAction=sentAsIs, outcome=engaged',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            event: _event(
              userAction: CoachingUserAction.sentAsIs,
              outcome: CoachingOutcomeSignal.engaged,
            ),
          ),
        );

        final chip = tester.widget<ChoiceChip>(
          find.ancestor(
            of: find.text('有接話'),
            matching: find.byType(ChoiceChip),
          ),
        );
        expect(chip.selected, isTrue);
      },
    );
  });
}

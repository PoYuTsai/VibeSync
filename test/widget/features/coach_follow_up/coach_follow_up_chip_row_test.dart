// Spec 5 C22 — CoachFollowUpChipRow widget TDD spec.
//
// Pure-presentation chip row: 3 fixed lifecycle phases always visible,
// optional AI hint line, always-visible 額度 caption. Parent
// owns the selected state + telemetry — this widget just renders + bubbles
// taps via onPhaseSelected.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_phase.dart';
import 'package:vibesync/features/coach_follow_up/presentation/widgets/coach_follow_up_chip_row.dart';

Future<void> _pump(
  WidgetTester tester, {
  CoachFollowUpPhase? selectedPhase,
  CoachFollowUpPhase? hintedPhase,
  String? hintText,
  bool isLoading = false,
  ValueChanged<CoachFollowUpPhase>? onPhaseSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CoachFollowUpChipRow(
          selectedPhase: selectedPhase,
          hintedPhase: hintedPhase,
          hintText: hintText,
          isLoading: isLoading,
          onPhaseSelected: onPhaseSelected ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  group('CoachFollowUpChipRow — chip rendering', () {
    testWidgets('renders all 3 phase displayLabels (繁中)', (tester) async {
      await _pump(tester);

      expect(find.text('準備邀約'), findsOneWidget);
      expect(find.text('約會前提醒'), findsOneWidget);
      expect(find.text('約會後復盤'), findsOneWidget);
      expect(find.text('我有其他問題'), findsNothing,
          reason: 'openCoach is rendered as a separate text-box entry by '
              'CoachFollowUpSection, not as a fourth lifecycle chip.');
    });

    testWidgets('renders lifecycle chips in fixed order', (tester) async {
      await _pump(tester);

      // Topological order check: prepareInvite renders BEFORE preDateReminder
      // BEFORE postDateReflection. We use byKey so the ordering is stable
      // regardless of where the labels live inside ChoiceChip's subtree.
      final chipKeys =
          tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect(chipKeys, hasLength(3));
      expect(
        (chipKeys[0].label as Text).data,
        '準備邀約',
      );
      expect((chipKeys[1].label as Text).data, '約會前提醒');
      expect((chipKeys[2].label as Text).data, '約會後復盤');
    });
  });

  group('CoachFollowUpChipRow — quota caption', () {
    testWidgets('renders "生成會使用 1 則額度" caption — always visible',
        (tester) async {
      await _pump(tester);

      expect(find.textContaining('生成會使用 1 則額度'), findsOneWidget);
    });

    testWidgets('caption persists when a chip is selected', (tester) async {
      await _pump(tester, selectedPhase: CoachFollowUpPhase.prepareInvite);

      expect(find.textContaining('生成會使用 1 則額度'), findsOneWidget);
    });
  });

  group('CoachFollowUpChipRow — AI hint text', () {
    testWidgets('shows hint line with 💡 prefix when hintText is non-null',
        (tester) async {
      await _pump(
        tester,
        hintText: '看起來你最近聊到見面，可以試「約會前提醒」',
        hintedPhase: CoachFollowUpPhase.preDateReminder,
      );

      expect(
        find.textContaining('看起來你最近聊到見面'),
        findsOneWidget,
      );
      expect(find.textContaining('💡'), findsOneWidget);
    });

    testWidgets('hides hint line entirely when hintText is null',
        (tester) async {
      await _pump(tester, hintedPhase: CoachFollowUpPhase.preDateReminder);

      expect(find.textContaining('💡'), findsNothing);
    });
  });

  group('CoachFollowUpChipRow — chip selection state', () {
    testWidgets(
        'highlights only the selectedPhase chip when caller provides one',
        (tester) async {
      await _pump(tester, selectedPhase: CoachFollowUpPhase.preDateReminder);

      final chips =
          tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect(chips[0].selected, isFalse, reason: 'prepareInvite');
      expect(chips[1].selected, isTrue, reason: 'preDateReminder');
      expect(chips[2].selected, isFalse, reason: 'postDateReflection');
    });

    testWidgets(
        'highlights hintedPhase chip when no explicit selection (UI nudge)',
        (tester) async {
      await _pump(tester, hintedPhase: CoachFollowUpPhase.postDateReflection);

      final chips =
          tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect(chips[2].selected, isTrue);
      expect(chips[0].selected, isFalse);
      expect(chips[1].selected, isFalse);
    });

    testWidgets(
        'selectedPhase wins over hintedPhase when both are provided '
        '(user choice trumps AI nudge)', (tester) async {
      await _pump(
        tester,
        selectedPhase: CoachFollowUpPhase.prepareInvite,
        hintedPhase: CoachFollowUpPhase.preDateReminder,
      );

      final chips =
          tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect(chips[0].selected, isTrue, reason: 'user-selected');
      expect(chips[1].selected, isFalse, reason: 'hint suppressed');
    });

    testWidgets('no chip is highlighted when neither prop is set',
        (tester) async {
      await _pump(tester);

      final chips =
          tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect(chips.every((c) => !c.selected), isTrue);
    });
  });

  group('CoachFollowUpChipRow — tap callback', () {
    testWidgets('tapping a chip fires onPhaseSelected with the matching enum',
        (tester) async {
      CoachFollowUpPhase? tapped;
      await _pump(tester, onPhaseSelected: (p) => tapped = p);

      await tester.tap(find.text('約會後復盤'));
      await tester.pump();

      expect(tapped, CoachFollowUpPhase.postDateReflection);
    });

    testWidgets(
        'tapping the already-selected chip still fires the callback '
        '(parent decides whether to ignore)', (tester) async {
      CoachFollowUpPhase? tapped;
      await _pump(
        tester,
        selectedPhase: CoachFollowUpPhase.prepareInvite,
        onPhaseSelected: (p) => tapped = p,
      );

      await tester.tap(find.text('準備邀約'));
      await tester.pump();

      expect(tapped, CoachFollowUpPhase.prepareInvite);
    });
  });

  group('CoachFollowUpChipRow — loading state', () {
    testWidgets('chips disabled while loading: tap does NOT fire callback',
        (tester) async {
      CoachFollowUpPhase? tapped;
      await _pump(
        tester,
        isLoading: true,
        onPhaseSelected: (p) => tapped = p,
      );

      await tester.tap(find.text('準備邀約'));
      await tester.pump();

      expect(tapped, isNull,
          reason: 'in-flight generate must lock chip selection');
    });

    testWidgets('caption + chips still render while loading', (tester) async {
      await _pump(tester, isLoading: true);

      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(find.textContaining('生成會使用 1 則額度'), findsOneWidget);
    });
  });
}

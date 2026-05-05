// Spec 5 C23 — CoachFollowUpInputSheet widget TDD spec.
//
// Implements design §1.2 Click-First Input Flow. 3 lifecycle variants × Q1/Q2/Q3
// plus v1.1 openCoach free-form question. STABLE ENGLISH KEYS internally; 中文
// labels render only at the chip surface — Edge function never sees 繁中
// option strings (locked by C19's wire shape + this widget's submit assertion).
//
// Submit button gating:
//   • prepareInvite / preDateReminder — Q1 required only
//   • postDateReflection — Q1 + Q2 both required
//   • openCoach — q3 open question required, q1 emits stable sentinel
//   • isLoading=true — always disabled (debounce — Q2 verdict)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_follow_up/data/services/coach_follow_up_api_service.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_phase.dart';
import 'package:vibesync/features/coach_follow_up/presentation/widgets/coach_follow_up_input_sheet.dart';

Future<void> _pump(
  WidgetTester tester, {
  required CoachFollowUpPhase phase,
  bool isLoading = false,
  ValueChanged<CoachFollowUpAnswers>? onSubmit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CoachFollowUpInputSheet(
            phase: phase,
            isLoading: isLoading,
            onSubmit: onSubmit ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

Future<void> _tapChipText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('CoachFollowUpInputSheet — prepareInvite phase', () {
    testWidgets('renders Q1 with 3 options + Q2 with 4 + Q3 textfield',
        (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.prepareInvite);

      // Q1 options (繁中 labels only — stable keys are internal)
      expect(find.textContaining('模糊邀約'), findsOneWidget);
      expect(find.textContaining('具體邀約'), findsOneWidget);
      expect(find.text('還沒想好'), findsOneWidget);

      // Q2 options
      expect(find.text('被拒絕'), findsOneWidget);
      expect(find.text('顯得太急'), findsOneWidget);
      expect(find.text('找不到合適理由'), findsOneWidget);
      expect(find.text('不知道怎麼開口'), findsOneWidget);

      // Q3 textfield exists and accepts text
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('submit button is disabled until Q1 is selected',
        (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.prepareInvite);

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '產生跟進建議'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('submit becomes enabled after Q1 selected (Q2 not required)',
        (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.prepareInvite);
      await _tapChipText(tester, '模糊邀約（看看她要不要）');

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '產生跟進建議'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('submit emits Q1 stable English key (not 繁中 label)',
        (tester) async {
      CoachFollowUpAnswers? captured;
      await _pump(
        tester,
        phase: CoachFollowUpPhase.prepareInvite,
        onSubmit: (a) => captured = a,
      );
      await _tapChipText(tester, '模糊邀約（看看她要不要）');
      await tester.tap(find.widgetWithText(ElevatedButton, '產生跟進建議'));
      await tester.pumpAndSettle();

      expect(captured?.q1, 'fuzzy');
      // 繁中 must never reach the wire shape
      expect(captured?.q1, isNot(contains('模糊')));
    });

    testWidgets('submit emits Q2 stable key when user selected one',
        (tester) async {
      CoachFollowUpAnswers? captured;
      await _pump(
        tester,
        phase: CoachFollowUpPhase.prepareInvite,
        onSubmit: (a) => captured = a,
      );
      await _tapChipText(tester, '具體邀約（時間 + 活動都明確）');
      await _tapChipText(tester, '顯得太急');
      await tester.tap(find.widgetWithText(ElevatedButton, '產生跟進建議'));
      await tester.pumpAndSettle();

      expect(captured?.q1, 'concrete');
      expect(captured?.q2, 'fearTooEager');
      expect(captured?.q2, isNot(contains('太急')));
    });

    testWidgets('submit emits q2 = null when user did NOT select Q2',
        (tester) async {
      CoachFollowUpAnswers? captured;
      await _pump(
        tester,
        phase: CoachFollowUpPhase.prepareInvite,
        onSubmit: (a) => captured = a,
      );
      await _tapChipText(tester, '還沒想好');
      await tester.tap(find.widgetWithText(ElevatedButton, '產生跟進建議'));
      await tester.pumpAndSettle();

      expect(captured?.q1, 'undecided');
      expect(captured?.q2, isNull);
      expect(captured?.q3, isNull,
          reason: 'empty Q3 text must serialize to null, not ""');
    });
  });

  group('CoachFollowUpInputSheet — preDateReminder phase', () {
    testWidgets('renders 4 Q1 options (today / tomorrow / 3 days / week)',
        (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.preDateReminder);

      expect(find.textContaining('今天'), findsOneWidget);
      expect(find.text('明天'), findsOneWidget);
      expect(find.text('三天內'), findsOneWidget);
      expect(find.text('一週內'), findsOneWidget);
    });

    testWidgets('Q1 only required — Q2 optional like prepareInvite',
        (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.preDateReminder);

      // Initial: disabled
      var btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '產生跟進建議'),
      );
      expect(btn.onPressed, isNull);

      // After Q1 only → enabled
      await _tapChipText(tester, '明天');
      btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '產生跟進建議'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Q1 stable keys: today/tomorrow/withinThreeDays/withinWeek',
        (tester) async {
      CoachFollowUpAnswers? captured;
      await _pump(
        tester,
        phase: CoachFollowUpPhase.preDateReminder,
        onSubmit: (a) => captured = a,
      );
      await _tapChipText(tester, '三天內');
      await tester.tap(find.widgetWithText(ElevatedButton, '產生跟進建議'));
      await tester.pumpAndSettle();

      expect(captured?.q1, 'withinThreeDays');
    });
  });

  group(
      'CoachFollowUpInputSheet — postDateReflection phase '
      '(Q1 + Q2 BOTH required)', () {
    testWidgets('renders 4 Q1 options + 4 Q2 options', (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.postDateReflection);

      // Q1
      expect(find.text('比預期好'), findsOneWidget);
      expect(find.text('還可以'), findsOneWidget);
      expect(find.text('卡卡的'), findsOneWidget);
      expect(find.text('不確定'), findsOneWidget);
      // Q2
      expect(find.textContaining('主動找下一次'), findsOneWidget);
      expect(find.text('還在禮貌回應'), findsOneWidget);
      expect(find.text('變慢或變淡'), findsOneWidget);
      expect(find.textContaining('還看不出來'), findsOneWidget);
    });

    testWidgets(
        'submit stays disabled when only Q1 is selected (Q2 also required)',
        (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.postDateReflection);
      await _tapChipText(tester, '還可以');

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '產生跟進建議'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('submit enables once Q1 + Q2 are BOTH selected',
        (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.postDateReflection);
      await _tapChipText(tester, '卡卡的');
      await _tapChipText(tester, '還在禮貌回應');

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '產生跟進建議'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Q2 stable keys: proactive / polite / cooling / stillUnclear',
        (tester) async {
      CoachFollowUpAnswers? captured;
      await _pump(
        tester,
        phase: CoachFollowUpPhase.postDateReflection,
        onSubmit: (a) => captured = a,
      );
      await _tapChipText(tester, '比預期好');
      await _tapChipText(tester, '變慢或變淡');
      await tester.tap(find.widgetWithText(ElevatedButton, '產生跟進建議'));
      await tester.pumpAndSettle();

      expect(captured?.q1, 'betterThanExpected');
      expect(captured?.q2, 'cooling');
    });
  });

  group('CoachFollowUpInputSheet — Q3 free text', () {
    testWidgets('Q3 TextField caps input at 80 chars', (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.prepareInvite);

      final textFieldWidget = tester.widget<TextField>(find.byType(TextField));
      expect(textFieldWidget.maxLength, 80);
      expect(textFieldWidget.textInputAction, TextInputAction.done);
      expect(find.byTooltip('收起鍵盤'), findsOneWidget);
    });

    testWidgets('Q3 can dismiss keyboard before submit', (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.prepareInvite);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '怕她覺得我太急');
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.byTooltip('收起鍵盤'));
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('Q3 text is forwarded to onSubmit when non-empty',
        (tester) async {
      CoachFollowUpAnswers? captured;
      await _pump(
        tester,
        phase: CoachFollowUpPhase.prepareInvite,
        onSubmit: (a) => captured = a,
      );
      await _tapChipText(tester, '具體邀約（時間 + 活動都明確）');
      await tester.enterText(find.byType(TextField), '想再約一次但不太確定她有沒有興趣');
      await tester.tap(find.widgetWithText(ElevatedButton, '產生跟進建議'));
      await tester.pumpAndSettle();

      expect(captured?.q3, '想再約一次但不太確定她有沒有興趣');
    });

    testWidgets('Q3 trims whitespace; if blank → q3 emits null',
        (tester) async {
      // Empty / whitespace-only Q3 must serialize to null so the wire body
      // omits q3 entirely (matches Edge schema .nullable().optional()).
      CoachFollowUpAnswers? captured;
      await _pump(
        tester,
        phase: CoachFollowUpPhase.prepareInvite,
        onSubmit: (a) => captured = a,
      );
      await _tapChipText(tester, '還沒想好');
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(ElevatedButton, '產生跟進建議'));
      await tester.pumpAndSettle();

      expect(captured?.q3, isNull);
    });
  });

  group('CoachFollowUpInputSheet — openCoach phase', () {
    testWidgets('renders open question textarea without Q1/Q2 chips',
        (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.openCoach);

      expect(find.text('我有其他問題'), findsOneWidget);
      expect(find.textContaining('把你現在卡住的點寫下來'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('讓教練看一下'), findsOneWidget);
      expect(find.text('你想用什麼方式邀？'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('submit disabled until user writes a question', (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.openCoach);

      var btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '讓教練看一下'),
      );
      expect(btn.onPressed, isNull);

      await tester.enterText(find.byType(TextField), '我太有邊界感，不知道怎麼推進');
      await tester.pumpAndSettle();

      btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '讓教練看一下'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('submit emits q1=openQuestion and q3 trimmed', (tester) async {
      CoachFollowUpAnswers? captured;
      await _pump(
        tester,
        phase: CoachFollowUpPhase.openCoach,
        onSubmit: (a) => captured = a,
      );

      await tester.enterText(find.byType(TextField), '  她回很慢，我該等還是約？  ');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '讓教練看一下'));
      await tester.pumpAndSettle();

      expect(captured?.q1, 'openQuestion');
      expect(captured?.q2, isNull);
      expect(captured?.q3, '她回很慢，我該等還是約？');
    });

    testWidgets('open question text caps at 120 chars', (tester) async {
      await _pump(tester, phase: CoachFollowUpPhase.openCoach);

      final textFieldWidget = tester.widget<TextField>(find.byType(TextField));
      expect(textFieldWidget.maxLength, 120);
      expect(textFieldWidget.textInputAction, TextInputAction.done);
      expect(find.byTooltip('收起鍵盤'), findsOneWidget);
    });
  });

  group('CoachFollowUpInputSheet — loading state (debounce)', () {
    testWidgets(
        'submit button is disabled while isLoading=true even with all '
        'required fields answered', (tester) async {
      await _pump(
        tester,
        phase: CoachFollowUpPhase.prepareInvite,
        isLoading: true,
      );
      await _tapChipText(tester, '模糊邀約（看看她要不要）');

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '產生跟進建議'),
      );
      expect(btn.onPressed, isNull);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import 'package:vibesync/shared/widgets/coaching_outcome_capture_card.dart';
import 'package:vibesync/shared/widgets/coaching_outcome_follow_up_bar.dart';

CoachingOutcomeEvent _event({
  CoachingUserAction userAction = CoachingUserAction.sentAsIs,
  CoachingOutcomeSignal outcome = CoachingOutcomeSignal.pending,
}) {
  return CoachingOutcomeEvent(
    id: 'opener:req-1:extend',
    source: CoachingOutcomeSource.opener,
    suggestedMoveSummary: '妳週末也會去爬山嗎？',
    userAction: userAction,
    outcome: outcome,
    createdAt: DateTime(2026, 7, 6),
  );
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('event 為 null 時整條不渲染', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: null,
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.textContaining('後來呢？'), findsNothing);
  });

  testWidgets('預設收合：看得到標題、看不到晶片', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(),
      label: '延展',
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.textContaining('後來呢？'), findsOneWidget);
    expect(find.textContaining('延展'), findsOneWidget);
    expect(find.byType(CoachingOutcomeCaptureCard), findsNothing);
  });

  testWidgets('複製自動記（sentAsIs/pending）收合標題顯示中性文案、不謊稱「照著發了」',
      (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(), // sentAsIs / pending
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.textContaining('已複製，發出後回報結果'), findsOneWidget);
    expect(find.textContaining('已記下：照著發了'), findsNothing);
  });

  testWidgets('未送類（didNotSend/unknown）收合標題報第一段動作', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(
        userAction: CoachingUserAction.didNotSend,
        outcome: CoachingOutcomeSignal.unknown,
      ),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.textContaining('已記下：沒有發'), findsOneWidget);
  });

  testWidgets('點標題展開後渲染共用晶片卡、再點收合', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    await tester.tap(find.textContaining('後來呢？'));
    await tester.pumpAndSettle();
    expect(find.byType(CoachingOutcomeCaptureCard), findsOneWidget);
    expect(find.text('照著發了'), findsOneWidget);
    await tester.tap(find.textContaining('後來呢？'));
    await tester.pumpAndSettle();
    expect(find.byType(CoachingOutcomeCaptureCard), findsNothing);
  });

  testWidgets('展開後晶片回呼直通', (tester) async {
    CoachingOutcomeSignal? got;
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (s) => got = s,
    )));
    await tester.tap(find.textContaining('後來呢？'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('有接話'));
    expect(got, CoachingOutcomeSignal.engaged);
  });

  testWidgets('已有第二段答案時收合標題帶回報狀態', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(outcome: CoachingOutcomeSignal.engaged),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.textContaining('有接話'), findsOneWidget);
  });
}

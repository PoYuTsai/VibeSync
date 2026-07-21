import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';

import '../../../helpers/memory_coaching_outcome_repository.dart';

CoachChatResult _result() {
  return CoachChatResult(
    id: 'result-1',
    conversationId: 'conversation-1',
    partnerId: 'partner-1',
    question: '我現在該怎麼回？',
    mode: 'replyCraft',
    headline: '先穩住節奏',
    answer: '先接住她的情緒，再丟一個好回的小球。',
    userState: '有點急著想推進',
    nextStep: '先用一句輕鬆的話把球丟回去',
    suggestedLine: '你這句有點突然，但我可以接。',
    boundaryReminder: '不要急著把對話推太重。',
    needsReflection: false,
    generatedAt: DateTime.utc(2026, 7, 6, 8),
    provider: 'claude',
    modelUsed: 'claude-sonnet-4-20250514',
  );
}

Widget _wrap(MemoryCoachingOutcomeRepository repo) {
  return ProviderScope(
    overrides: [
      coachingOutcomeRepositoryProvider.overrideWithValue(repo),
      coachingOutcomeNowProvider
          .overrideWithValue(() => DateTime.utc(2026, 7, 6, 9)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CoachChatResultView(
            // Phase E：view 改吃 unified 型別；fixture 經 1:1 映射轉入。
            result: UnifiedCoachResult.fromCoachChatResult(_result()),
            dailyRemaining: 3,
            onFollowUp: () {},
            onForceAnswer: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('點第一段「照著發了」→ recorder 寫入 sentAsIs/pending 並浮出第二段',
      (tester) async {
    final repo = MemoryCoachingOutcomeRepository();
    await tester.pumpWidget(_wrap(repo));

    await tester.tap(find.text('照著發了'));
    await tester.pumpAndSettle();

    final stored = repo.get('coach:result-1')!;
    expect(stored.userAction, CoachingUserAction.sentAsIs);
    expect(stored.outcome, CoachingOutcomeSignal.pending);
    expect(find.text('有接話'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5)); // 清 SnackBar timer
  });

  testWidgets('點「沒有發」→ outcome=unknown 且不出第二段', (tester) async {
    final repo = MemoryCoachingOutcomeRepository();
    await tester.pumpWidget(_wrap(repo));

    await tester.tap(find.text('沒有發'));
    await tester.pumpAndSettle();

    final stored = repo.get('coach:result-1')!;
    expect(stored.userAction, CoachingUserAction.didNotSend);
    expect(stored.outcome, CoachingOutcomeSignal.unknown);
    expect(find.text('有接話'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('第二段作答後重按同一顆第一段晶片，反應不被洗掉（批2同值短路）',
      (tester) async {
    final repo = MemoryCoachingOutcomeRepository();
    await tester.pumpWidget(_wrap(repo));

    // 每段回報後浮出的 floating SnackBar 會蓋住下一顆晶片、吃掉點擊，
    // 故每次點擊後先讓 SnackBar 逾時消失再點下一顆。
    await tester.tap(find.text('照著發了'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('有接話'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('照著發了')); // 重按同值
    await tester.pumpAndSettle();

    final stored = repo.get('coach:result-1')!;
    expect(stored.userAction, CoachingUserAction.sentAsIs);
    expect(stored.outcome, CoachingOutcomeSignal.engaged);

    await tester.pump(const Duration(seconds: 5));
  });
}

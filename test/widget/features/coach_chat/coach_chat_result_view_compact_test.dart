import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_chat_card.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';

import '../../../helpers/memory_coaching_outcome_repository.dart';

CoachChatResult _formalResult() {
  return CoachChatResult(
    id: 'formal-result',
    conversationId: 'conversation-1',
    partnerId: 'partner-1',
    question: '我現在該怎麼做？',
    mode: 'replyCraft',
    headline: '先穩住節奏',
    answer: '完整分析正文',
    userState: '正在反覆修改訊息',
    nextStep: '先發一個低壓小球',
    suggestedLine: '最近那家店看起來不錯，你有興趣嗎？',
    boundaryReminder: '發出後先不要連續追問',
    needsReflection: true,
    reflectionQuestion: '你真正想確認的是什麼？',
    generatedAt: DateTime.utc(2026, 7, 16, 8),
    provider: 'claude',
    modelUsed: 'claude-sonnet-4-20250514',
    userTruth: '想靠近，但不想給對方壓力',
    rewriteDecision: 'light_edit',
    rewriteReason: '保留原意',
    frictionType: 'overPolishing',
  );
}

CoachChatResult _clarifyingResult() {
  return CoachChatResult(
    id: 'clarifying-result',
    conversationId: 'conversation-1',
    partnerId: 'partner-1',
    question: '我現在該怎麼做？',
    mode: 'clarifyIntent',
    headline: '先確認你的目標',
    answer: '我需要先知道你想推進，還是只想維持舒服互動。',
    userState: '還沒確定自己想往哪裡走',
    nextStep: '告訴我你比較想要哪一種結果',
    boundaryReminder: '先不急著替對方下結論',
    needsReflection: true,
    reflectionQuestion: '你此刻比較想靠近，還是先觀察？',
    generatedAt: DateTime.utc(2026, 7, 16, 8),
    provider: 'claude',
    modelUsed: 'claude-sonnet-4-20250514',
    responseType: 'clarifyingQuestion',
    userTruth: '不確定關係是不是能再往前',
    costDeducted: 0,
    frictionType: 'unclearIntent',
  );
}

Widget _wrap(CoachChatResult result) {
  return ProviderScope(
    overrides: [
      coachingOutcomeRepositoryProvider.overrideWithValue(
        MemoryCoachingOutcomeRepository(),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CoachChatResultView(
            result: result,
            dailyRemaining: 3,
            onFollowUp: () {},
            onForceAnswer: () {},
          ),
        ),
      ),
    ),
  );
}

Finder _richText(String value) {
  return find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText() == value,
  );
}

void main() {
  testWidgets('正式回答首層只顯示行動資訊，完整分析預設收合', (tester) async {
    await tester.pumpWidget(_wrap(_formalResult()));

    expect(find.text('先穩住節奏'), findsOneWidget);
    expect(find.text('已扣 1 則 · 今日剩 3 則'), findsOneWidget);
    expect(_richText('這次先做：先發一個低壓小球'), findsOneWidget);
    expect(find.text('最近那家店看起來不錯，你有興趣嗎？'), findsOneWidget);
    expect(find.text('複製這句'), findsOneWidget);
    expect(_richText('邊界提醒：發出後先不要連續追問'), findsOneWidget);
    expect(find.text('看完整教練分析'), findsOneWidget);
    expect(find.text('繼續深挖'), findsOneWidget);
    expect(find.text('照著發了'), findsOneWidget);

    expect(find.text('完整分析正文'), findsNothing);
    expect(_richText('我理解你的真實想法：想靠近，但不想給對方壓力'), findsNothing);
    expect(_richText('這輪卡點：想找完美句，反而卡住'), findsNothing);
    expect(_richText('你現在卡在：正在反覆修改訊息'), findsNothing);
    expect(_richText('教練判斷：輕修就好：保留原意'), findsNothing);
    expect(_richText('教練追問：你真正想確認的是什麼？'), findsNothing);

    await tester.ensureVisible(find.text('看完整教練分析'));
    await tester.tap(find.text('看完整教練分析'));
    await tester.pumpAndSettle();

    expect(find.text('完整分析正文'), findsOneWidget);
    expect(_richText('我理解你的真實想法：想靠近，但不想給對方壓力'), findsOneWidget);
    expect(_richText('這輪卡點：想找完美句，反而卡住'), findsOneWidget);
    expect(_richText('你現在卡在：正在反覆修改訊息'), findsOneWidget);
    expect(_richText('教練判斷：輕修就好：保留原意'), findsOneWidget);
    expect(_richText('教練追問：你真正想確認的是什麼？'), findsOneWidget);
  });

  testWidgets('免費釐清回答維持直接展開，不顯示完整分析收合入口', (tester) async {
    await tester.pumpWidget(_wrap(_clarifyingResult()));

    expect(find.text('先確認你的目標'), findsOneWidget);
    expect(find.text('免費釐清（最多 3 次）'), findsOneWidget);
    expect(find.text('教練想先問清楚（免費釐清）'), findsOneWidget);
    expect(find.text('你此刻比較想靠近，還是先觀察？'), findsOneWidget);
    expect(
      find.text('我需要先知道你想推進，還是只想維持舒服互動。'),
      findsOneWidget,
    );
    expect(_richText('我理解你的真實想法：不確定關係是不是能再往前'), findsOneWidget);
    expect(_richText('這輪卡點：意圖還沒完全釐清'), findsOneWidget);
    expect(_richText('你現在卡在：還沒確定自己想往哪裡走'), findsOneWidget);
    expect(_richText('先補充這一點：告訴我你比較想要哪一種結果'), findsOneWidget);
    expect(_richText('邊界提醒：先不急著替對方下結論'), findsOneWidget);
    expect(find.text('補充我的想法'), findsOneWidget);
    expect(find.text('直接看建議（扣 1 則）'), findsOneWidget);
    expect(find.text('看完整教練分析'), findsNothing);
    expect(find.text('照著發了'), findsNothing);
  });
}

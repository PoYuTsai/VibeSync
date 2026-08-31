import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
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

Widget _wrap(CoachChatResult result, {int? clarificationOrdinal}) {
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
            // Phase E：view 改吃 unified 型別；測試 fixture 沿用 legacy
            // builder 經 1:1 映射轉入（機械調整，UI 邏輯不變）。
            result: UnifiedCoachResult.fromCoachChatResult(result),
            dailyRemaining: 3,
            onFollowUp: () {},
            onAskDifferent: () {},
            onForceAnswer: () {},
            clarificationOrdinal: clarificationOrdinal,
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
    // 兩段式成效卡已退場（2026-08-16 Bruce 回饋三輪），換輕量拇指回饋。
    expect(find.text('這個建議有幫助嗎？'), findsOneWidget);
    expect(find.text('照著發了'), findsNothing);
    expect(find.text('這則建議你怎麼處理？'), findsNothing);

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

  testWidgets('幫教練釐清回答維持直接展開，不顯示完整分析收合入口', (tester) async {
    await tester.pumpWidget(_wrap(_clarifyingResult()));

    expect(find.text('先確認你的目標'), findsOneWidget);
    // 「免費釐清」改名「幫教練釐清」（2026-08-16 Eric 拍板，扣費行為不變）。
    expect(find.text('幫教練釐清 · 免費（最多 3 次）'), findsOneWidget);
    expect(find.text('教練想先問清楚（幫教練釐清）'), findsOneWidget);
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
    // 「補充」由輸入列 hint 承擔；這顆改為跳出釐清循環的「想問別的」
    // （2026-08-16 Bruce 回饋）。
    expect(find.text('想問別的'), findsOneWidget);
    expect(find.text('補充我的想法'), findsNothing);
    expect(find.text('直接看建議（扣 1 則）'), findsOneWidget);
    expect(find.text('看完整教練分析'), findsNothing);
    expect(find.text('照著發了'), findsNothing);
  });

  testWidgets('👎 先問哪裡不好：展開 Coach 可行動分類＋跳過，點分類才送出', (tester) async {
    await tester.pumpWidget(_wrap(_formalResult()));

    await tester
        .ensureVisible(find.byKey(const ValueKey('coach-feedback-down')));
    await tester.tap(find.byKey(const ValueKey('coach-feedback-down')));
    await tester.pump();

    // 還沒送出（沒有任何 snackbar），先展開分類。
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('哪裡不好？幫我們改進（選一個就好）'), findsOneWidget);
    for (final key in const [
      'coach-feedback-category-should_not_send',
      'coach-feedback-category-too_beta',
      'coach-feedback-category-too_generic',
      'coach-feedback-category-invented_detail',
      'coach-feedback-category-wrong_judgment',
      'coach-feedback-category-too_many_questions',
      'coach-feedback-category-missed_context',
      'coach-feedback-category-too_long',
      'coach-feedback-category-wrong_style',
      'coach-feedback-category-other',
      'coach-feedback-category-skip',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }

    // 點分類即嘗試送出（測試環境無 Supabase → 走失敗 snackbar，
    // 證明 submit 路徑被觸發）。
    await tester.ensureVisible(
      find.byKey(const ValueKey('coach-feedback-category-too_long')),
    );
    await tester
        .tap(find.byKey(const ValueKey('coach-feedback-category-too_long')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('回饋暫時沒有送出，稍後可以再試一次。'), findsOneWidget);
  });

  testWidgets('釐清卡帶序數：第 1 次與第 3 次的文案（看情況框架，不是配額）', (tester) async {
    await tester
        .pumpWidget(_wrap(_clarifyingResult(), clarificationOrdinal: 1));
    expect(find.text('免費釐清 第 1 次（最多 3 次）'), findsOneWidget);

    await tester
        .pumpWidget(_wrap(_clarifyingResult(), clarificationOrdinal: 3));
    await tester.pumpAndSettle();
    expect(find.text('免費釐清 第 3 次 · 下一則就是正式建議'), findsOneWidget);
  });

  testWidgets('do_not_send 且無建議句時顯示「這輪先別傳」，不出複製鈕（Batch A）', (tester) async {
    final holdResult = CoachChatResult(
      id: 'hold-result',
      conversationId: 'conversation-1',
      partnerId: 'partner-1',
      question: '要不要再約她一次？',
      mode: 'stopSignal',
      headline: '這輪先收手',
      answer: '她連續兩次沒有承接邀約，再推只會讓你的投入超過她給的互惠。',
      userState: '你想推進，但對方目前沒有給窗口',
      nextStep: '等她主動帶新材料，沒有就先把注意力移開',
      suggestedLine: null,
      boundaryReminder: '除非她主動延伸或給時間，否則先不再提出邀約',
      needsReflection: false,
      generatedAt: DateTime.utc(2026, 8, 31, 8),
      provider: 'claude',
      modelUsed: 'claude-sonnet-5',
      rewriteDecision: 'do_not_send',
      rewriteReason: '兩次邀約未被承接，先停一輪',
      frictionType: 'stopLoss',
    );
    await tester.pumpWidget(_wrap(holdResult));
    expect(find.text('這輪先別傳'), findsOneWidget);
    expect(find.text('兩次邀約未被承接，先停一輪'), findsOneWidget);
    expect(find.text('複製這句'), findsNothing);
  });

  testWidgets('messageDecision=no_message_needed 顯示第三態卡（B2）', (tester) async {
    final noMessageResult = CoachChatResult(
      id: 'no-message-result',
      conversationId: 'conversation-1',
      partnerId: 'partner-1',
      question: '我約會時該怎麼穩住心態？',
      mode: 'stateCalibration',
      headline: '把注意力放回自己',
      answer: '這題的關鍵在你怎麼看待這場約會，不在傳什麼訊息。',
      userState: '你把成敗都押在對方反應上',
      nextStep: '出門前寫下你自己想確認的一件事',
      suggestedLine: null,
      boundaryReminder: '不要為了安全感要求對方保證',
      needsReflection: false,
      generatedAt: DateTime.utc(2026, 8, 31, 9),
      provider: 'claude',
      modelUsed: 'claude-sonnet-5',
      rewriteDecision: 'keep_original',
      rewriteReason: null,
      frictionType: 'fearOfMistake',
      messageDecision: 'no_message_needed',
    );
    await tester.pumpWidget(_wrap(noMessageResult));
    expect(find.text('這題不用回訊息'), findsOneWidget);
    // 不是警示卡：不得出現「先別傳」。
    expect(find.text('這輪先別傳'), findsNothing);
    expect(find.text('複製這句'), findsNothing);
  });
}

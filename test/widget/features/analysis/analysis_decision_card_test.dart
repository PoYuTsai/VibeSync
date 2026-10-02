// Phase 1c：Analyze V2 決策卡（不回／資料不夠／先收尾）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/sections/analysis_banners_section.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

/// need_context／acknowledge_and_stop 卡維持原樣：沒有「先不要回」的下一步區塊。
void _expectNoDoNotSendExtras() {
  expect(find.text('下一步'), findsNothing);
  expect(find.text('她一直沒動靜就別追這條，過幾天用新話題重開。'), findsNothing);
  expect(find.text('用新話題重新開'), findsNothing);
  expect(find.text('我還是想回'), findsNothing);
  expect(find.text('不該出現的句子'), findsNothing);
}

void main() {
  const doNotSend = AnalysisDecisionV2(
    messageDecision: AnalysisMessageDecision.doNotSend,
    replyMode: 'none',
    action: 'pause',
    reason: '她只回哈哈，沒有新內容',
    stopCondition: '等她主動給新話題',
  );
  const doNotSendWithLine = AnalysisDecisionV2(
    messageDecision: AnalysisMessageDecision.doNotSend,
    replyMode: 'none',
    action: 'pause',
    reason: '她只回哈哈，沒有新內容',
    stopCondition: '等她主動給新話題',
    closingMessage: '好，那妳先忙。',
  );

  testWidgets('do_not_send：下一步區塊（等待條件＋固定提醒）；沒備用句就沒「我還是想回」', (tester) async {
    await _pump(tester, const AnalysisDecisionCard(decision: doNotSend));
    expect(
        find.byKey(const ValueKey('analysis-decision-card')), findsOneWidget);
    expect(find.text('這輪先不要回'), findsOneWidget);
    expect(find.text('她只回哈哈，沒有新內容'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('等到這時候再回：等她主動給新話題'), findsOneWidget);
    expect(find.text('她一直沒動靜就別追這條，過幾天用新話題重開。'), findsOneWidget);
    expect(find.text('我還是想回'), findsNothing);
    expect(find.text('複製收尾句'), findsNothing);
    // 沒傳回呼（例如歷史紀錄）就不出新話題按鈕。
    expect(find.text('用新話題重新開'), findsNothing);
  });

  testWidgets('do_not_send 沒有等待條件：不出空的「等到這時候再回」', (tester) async {
    await _pump(
      tester,
      const AnalysisDecisionCard(
        decision: AnalysisDecisionV2(
          messageDecision: AnalysisMessageDecision.doNotSend,
          replyMode: 'none',
          reason: '她只回哈哈',
        ),
      ),
    );
    expect(find.textContaining('等到這時候再回'), findsNothing);
    expect(find.text('她一直沒動靜就別追這條，過幾天用新話題重開。'), findsOneWidget);
  });

  testWidgets('do_not_send 有回呼才出「用新話題重新開」，點了觸發回呼', (tester) async {
    var opened = 0;
    await _pump(
      tester,
      AnalysisDecisionCard(
        decision: doNotSend,
        onStartNewTopic: () => opened++,
      ),
    );
    await tester.tap(find.text('用新話題重新開'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('do_not_send 帶備用句：收合在「我還是想回」後面，展開才看得到句子與複製', (tester) async {
    var copied = 0;
    var closingCopied = 0;
    await _pump(
      tester,
      AnalysisDecisionCard(
        decision: doNotSendWithLine,
        onCopyClosingMessage: () => closingCopied++,
        onCopyAgainstAdviceLine: () => copied++,
      ),
    );
    expect(find.text('我還是想回'), findsOneWidget);
    expect(find.text('好，那妳先忙。'), findsNothing);
    expect(find.text('教練不建議現在回。真的要回，這句壓力最低：'), findsNothing);
    expect(find.text('複製這句'), findsNothing);
    // 不是收尾句：永遠不出「複製收尾句」。
    expect(find.text('複製收尾句'), findsNothing);

    await tester.tap(find.text('我還是想回'));
    await tester.pump();
    expect(find.text('我還是想回'), findsNothing);
    expect(find.text('教練不建議現在回。真的要回，這句壓力最低：'), findsOneWidget);
    expect(find.text('好，那妳先忙。'), findsOneWidget);
    await tester.tap(find.text('複製這句'));
    await tester.pump();
    expect(copied, 1);
    expect(closingCopied, 0);
    expect(find.text('複製收尾句'), findsNothing);
  });

  testWidgets('do_not_send 備用句沒給複製回呼：展開只顯示句子', (tester) async {
    await _pump(
      tester,
      const AnalysisDecisionCard(decision: doNotSendWithLine),
    );
    await tester.tap(find.text('我還是想回'));
    await tester.pump();
    expect(find.text('好，那妳先忙。'), findsOneWidget);
    expect(find.text('複製這句'), findsNothing);
  });

  testWidgets('換一輪分析（新決策）就重新收合「我還是想回」', (tester) async {
    await _pump(
      tester,
      const AnalysisDecisionCard(decision: doNotSendWithLine),
    );
    await tester.tap(find.text('我還是想回'));
    await tester.pump();
    expect(find.text('好，那妳先忙。'), findsOneWidget);

    await _pump(
      tester,
      const AnalysisDecisionCard(
        decision: AnalysisDecisionV2(
          messageDecision: AnalysisMessageDecision.doNotSend,
          replyMode: 'none',
          reason: '她還是只回貼圖',
          closingMessage: '好，改天聊。',
        ),
      ),
    );
    expect(find.text('我還是想回'), findsOneWidget);
    expect(find.text('好，改天聊。'), findsNothing);
  });

  testWidgets('need_context：補截圖文案', (tester) async {
    await _pump(
      tester,
      AnalysisDecisionCard(
        onStartNewTopic: () {},
        onCopyAgainstAdviceLine: () {},
        decision: const AnalysisDecisionV2(
          messageDecision: AnalysisMessageDecision.needContext,
          replyMode: 'none',
          reason: '看不出哪句是誰說的',
          stopCondition: '補上完整對話截圖',
          closingMessage: '不該出現的句子',
        ),
      ),
    );
    expect(find.text('資料不夠，先補截圖'), findsOneWidget);
    expect(find.text('補上後再分析：補上完整對話截圖'), findsOneWidget);
    _expectNoDoNotSendExtras();
  });

  testWidgets('acknowledge_and_stop：顯示收尾句，複製鈕觸發回呼', (tester) async {
    var copied = 0;
    await _pump(
      tester,
      AnalysisDecisionCard(
        decision: const AnalysisDecisionV2(
          messageDecision: AnalysisMessageDecision.acknowledgeAndStop,
          replyMode: 'single',
          action: 'stop',
          reason: '她已經說改天',
          stopCondition: '等她再約',
          closingMessage: '好，那先這樣，改天再聊。',
        ),
        onCopyClosingMessage: () => copied++,
        onStartNewTopic: () {},
        onCopyAgainstAdviceLine: () {},
      ),
    );
    expect(find.text('這輪先收尾'), findsOneWidget);
    expect(find.text('等到這時候再回：等她再約'), findsOneWidget);
    expect(find.text('好，那先這樣，改天再聊。'), findsOneWidget);
    await tester.tap(find.text('複製收尾句'));
    await tester.pump();
    expect(copied, 1);
    _expectNoDoNotSendExtras();
  });
}

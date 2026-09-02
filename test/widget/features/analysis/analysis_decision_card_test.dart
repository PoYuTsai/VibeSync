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

void main() {
  testWidgets('do_not_send：標題、原因、等待條件；無收尾句與複製鈕', (tester) async {
    await _pump(
      tester,
      const AnalysisDecisionCard(
        decision: AnalysisDecisionV2(
          messageDecision: AnalysisMessageDecision.doNotSend,
          replyMode: 'none',
          action: 'pause',
          reason: '她只回哈哈，沒有新內容',
          stopCondition: '等她主動給新話題',
        ),
      ),
    );
    expect(
        find.byKey(const ValueKey('analysis-decision-card')), findsOneWidget);
    expect(find.text('這輪先不要回'), findsOneWidget);
    expect(find.text('她只回哈哈，沒有新內容'), findsOneWidget);
    expect(find.text('等到這時候再回：等她主動給新話題'), findsOneWidget);
    expect(find.text('複製收尾句'), findsNothing);
  });

  testWidgets('do_not_send 帶 closingMessage：不顯示句子也不給複製', (tester) async {
    var copied = 0;
    await _pump(
      tester,
      AnalysisDecisionCard(
        decision: const AnalysisDecisionV2(
          messageDecision: AnalysisMessageDecision.doNotSend,
          replyMode: 'none',
          reason: '她只回哈哈',
          stopCondition: '等她提新話題',
          closingMessage: '不該出現的句子',
        ),
        onCopyClosingMessage: () => copied++,
      ),
    );
    expect(find.text('不該出現的句子'), findsNothing);
    expect(find.text('複製收尾句'), findsNothing);
    expect(copied, 0);
  });

  testWidgets('need_context：補截圖文案', (tester) async {
    await _pump(
      tester,
      const AnalysisDecisionCard(
        decision: AnalysisDecisionV2(
          messageDecision: AnalysisMessageDecision.needContext,
          replyMode: 'none',
          reason: '看不出哪句是誰說的',
          stopCondition: '補上完整對話截圖',
        ),
      ),
    );
    expect(find.text('資料不夠，先補截圖'), findsOneWidget);
    expect(find.text('補上後再分析：補上完整對話截圖'), findsOneWidget);
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
      ),
    );
    expect(find.text('這輪先收尾'), findsOneWidget);
    expect(find.text('好，那先這樣，改天再聊。'), findsOneWidget);
    await tester.tap(find.text('複製收尾句'));
    await tester.pump();
    expect(copied, 1);
  });
}

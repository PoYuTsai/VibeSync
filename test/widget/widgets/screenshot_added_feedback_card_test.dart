import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_added_feedback_card.dart';

void main() {
  Widget buildHost({
    required bool lastMessageIsFromMe,
    required VoidCallback onAnalyze,
    required VoidCallback onShowConversation,
    bool isAnalyzing = false,
    bool? canAnalyzeNow,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ScreenshotAddedFeedbackCard(
          messageCount: 4,
          lastMessageIsFromMe: lastMessageIsFromMe,
          lastMessagePreview: '馬 來搭車～',
          isAnalyzing: isAnalyzing,
          canAnalyzeNow: canAnalyzeNow,
          onAnalyze: onAnalyze,
          onShowConversation: onShowConversation,
        ),
      ),
    );
  }

  testWidgets(
      'shows analyze CTA when the latest screenshot message is from her',
      (tester) async {
    var analyzed = false;
    var showedConversation = false;

    await tester.pumpWidget(
      buildHost(
        lastMessageIsFromMe: false,
        onAnalyze: () => analyzed = true,
        onShowConversation: () => showedConversation = true,
      ),
    );

    expect(find.textContaining('已從截圖加入 4 則新訊息'), findsOneWidget);
    expect(find.textContaining('最新：她說「馬 來搭車～」'), findsOneWidget);
    expect(find.textContaining('按「分析新增內容」後'), findsOneWidget);

    await tester.tap(find.text('看上方對話'));
    expect(showedConversation, isTrue);

    await tester.tap(find.text('分析新增內容'));
    expect(analyzed, isTrue);
  });

  testWidgets(
      'does not show analyze CTA when latest screenshot message is mine',
      (tester) async {
    await tester.pumpWidget(
      buildHost(
        lastMessageIsFromMe: true,
        onAnalyze: () {},
        onShowConversation: () {},
      ),
    );

    expect(find.textContaining('最新：我說「馬 來搭車～」'), findsOneWidget);
    expect(find.textContaining('等她回覆後'), findsOneWidget);
    expect(find.text('分析新增內容'), findsNothing);
  });

  testWidgets(
      'shows analyze CTA for an OCR batch ending with mine when the batch contains her reply',
      (tester) async {
    var analyzed = false;

    await tester.pumpWidget(
      buildHost(
        lastMessageIsFromMe: true,
        canAnalyzeNow: true,
        onAnalyze: () => analyzed = true,
        onShowConversation: () {},
      ),
    );

    expect(find.text('分析新增內容'), findsOneWidget);

    await tester.tap(find.text('分析新增內容'));
    expect(analyzed, isTrue);
  });
}

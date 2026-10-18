import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/new_topic/domain/entities/new_topic_result.dart';
import 'package:vibesync/features/new_topic/presentation/widgets/new_topic_idea_card.dart';

void main() {
  Future<int> pumpCard(WidgetTester tester, String openingLine) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NewTopicIdeaCard(
            idea: NewTopicIdea(
              id: 't1',
              direction: '週末早午餐',
              openingLine: openingLine,
              whyItWorks: '她一句就能回',
              nextMove: '先接住她的話',
            ),
            isRecommended: true,
            onCopyOpeningLine: () => taps++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return taps;
  }

  // Bruce 2026-10-18（#97）：留了「＿＿」的句子要先填好再複製。
  testWidgets('句子留了＿＿：按鈕寫「填好再複製」', (tester) async {
    await pumpCard(tester, '我最近在＿＿附近發現一間早午餐，妳週末都吃哪');
    expect(find.text('填好再複製'), findsOneWidget);
    expect(find.text('複製'), findsNothing);
  });

  testWidgets('沒有空格：照舊「複製」', (tester) async {
    await pumpCard(tester, '妳週末都吃哪一間早午餐');
    expect(find.text('複製'), findsOneWidget);
    expect(find.text('填好再複製'), findsNothing);
  });
}

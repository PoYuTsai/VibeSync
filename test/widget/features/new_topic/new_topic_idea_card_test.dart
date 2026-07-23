import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/new_topic/domain/entities/new_topic_result.dart';
import 'package:vibesync/features/new_topic/presentation/widgets/new_topic_idea_card.dart';

const _idea = NewTopicIdea(
  id: 'nt_2',
  direction: '接她上次提到的露營計畫',
  openingLine: '欸妳上次說要去露營，結果搶到營位了嗎？',
  whyItWorks: '接她自己開過的話題，低壓又有延續感。',
  nextMove: '她回覆後可以分享你自己的戶外糗事，讓話題雙向。',
);

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('渲染四欄＋可直接傳區塊＋複製鍵回呼', (tester) async {
    var copied = 0;
    await tester.pumpWidget(_wrap(NewTopicIdeaCard(
      idea: _idea,
      isRecommended: false,
      onCopyOpeningLine: () => copied++,
    )));

    expect(find.text('接她上次提到的露營計畫'), findsOneWidget);
    expect(find.text('欸妳上次說要去露營，結果搶到營位了嗎？'), findsOneWidget);
    expect(find.text('可直接傳'), findsOneWidget);
    expect(find.text('為什麼現在有效'), findsOneWidget);
    expect(find.text('接下來怎麼延續'), findsOneWidget);
    expect(find.text('AI 推薦'), findsNothing);

    await tester.tap(find.text('複製'));
    expect(copied, 1);
  });

  testWidgets('推薦卡顯示 AI 推薦 badge', (tester) async {
    await tester.pumpWidget(_wrap(NewTopicIdeaCard(
      idea: _idea,
      isRecommended: true,
      onCopyOpeningLine: () {},
    )));

    expect(find.text('AI 推薦'), findsOneWidget);
  });
}

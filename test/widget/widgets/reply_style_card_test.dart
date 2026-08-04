import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/widgets/reply_style_card.dart';

void main() {
  // 2026-08-04 拍板：互動風格／舒適區（延伸標記）概念整條移除，
  // ReplyStyleCard 不再有 stretchLevel 提示可顯示。
  testWidgets('shows long approach and message text without ellipsis',
      (tester) async {
    const longApproach = '接住她對義美產品的認同感，順到騎車行程，再輕微稱讚她的眼光，讓整段回覆保持生活感與自然延伸';
    const longSource = '今天去全家發現沒喝過的高蛋白，義美的無糖系列確實不錯欸';
    const longReply = '今天去全家發現沒喝過的高蛋白真的會很開心欸，而且義美的品質一直蠻穩定的。騎車運動完補充嗎？感覺妳蠻會發現好東西';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReplyStyleCard(
            type: 'extend',
            content: longReply,
            option: const ReplyOption(
              approach: longApproach,
              messages: [
                ReplySegment(
                  label: 'recommended',
                  sourceMessage: longSource,
                  reply: longReply,
                  reason: '自然延伸生活分享',
                ),
              ],
            ),
            isRecommended: true,
            onCopy: (_, __) {},
          ),
        ),
      ),
    );

    final approach = tester.widget<Text>(find.text(longApproach));
    expect(approach.maxLines, isNull);
    expect(approach.overflow, isNot(TextOverflow.ellipsis));

    final source = tester.widget<Text>(find.text('接：$longSource'));
    expect(source.maxLines, isNull);
    expect(source.overflow, isNot(TextOverflow.ellipsis));

    final reply = tester.widget<Text>(find.text(longReply));
    expect(reply.maxLines, isNull);
    expect(reply.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('再調一下只掛在單一則訊息上，整組複製不給微調', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final refined = <String>[];
    final copied = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReplyStyleCard(
            type: 'extend',
            content: '第一句\n第二句',
            option: const ReplyOption(
              approach: '順勢接話',
              messages: [
                ReplySegment(
                  label: 'a',
                  sourceMessage: '她說了什麼',
                  reply: '第一句',
                  reason: '',
                ),
                ReplySegment(
                  label: 'b',
                  sourceMessage: '',
                  reply: '第二句',
                  reason: '',
                ),
              ],
            ),
            isRecommended: false,
            onCopy: (text, _) => copied.add(text),
            onRefine: refined.add,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('reply-style-refine-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('reply-style-refine-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reply-style-refine-1')));
    await tester.pumpAndSettle();
    expect(refined, ['第二句']);

    // 整組合併的文字只能複製，不能拿去微調。
    await tester.tap(find.text('複製整組'));
    await tester.pumpAndSettle();
    expect(copied, ['第一句\n第二句']);
    expect(refined, ['第二句']);
  });

  testWidgets('沒給 onRefine 就不出現微調按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReplyStyleCard(
            type: 'extend',
            content: '只有一句',
            option: const ReplyOption(approach: '', messages: []),
            isRecommended: false,
            onCopy: (_, __) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('reply-style-refine-0')), findsNothing);
  });
}

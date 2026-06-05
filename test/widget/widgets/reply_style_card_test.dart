import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/widgets/reply_style_card.dart';

void main() {
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
}

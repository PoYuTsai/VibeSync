import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/presentation/widgets/message_bubble.dart';

void main() {
  group('MessageBubble', () {
    testWidgets('displays message content', (tester) async {
      final message = Message(
        id: '1',
        content: 'Hello!',
        isFromMe: true,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message),
          ),
        ),
      );

      expect(find.text('Hello!'), findsOneWidget);
    });

    testWidgets('aligns right for user messages', (tester) async {
      final message = Message(
        id: '1',
        content: 'My message',
        isFromMe: true,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message),
          ),
        ),
      );

      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.centerRight);
    });

    testWidgets('aligns left for other messages', (tester) async {
      final message = Message(
        id: '1',
        content: 'Their message',
        isFromMe: false,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message),
          ),
        ),
      );

      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.centerLeft);
    });

    testWidgets('不再寫「她說／我說」，說話者改由語意標籤念出', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MessageBubble(message: _message('她的訊息', isFromMe: false)),
                MessageBubble(message: _message('我的訊息', isFromMe: true)),
              ],
            ),
          ),
        ),
      );

      expect(find.text('她說'), findsNothing);
      expect(find.text('我說'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^她說\n她的訊息')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^我說\n我的訊息')), findsOneWidget);
    });

    testWidgets('VoiceOver 把引用和回覆分開念，引用不會聽成說話者自己說的', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _message(
                '好',
                isFromMe: true,
                quote: '明天一起吃飯？',
                quoteIsFromMe: true,
              ),
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('我說\n引用：明天一起吃飯？\n回覆：好'),
        findsOneWidget,
      );
      // 子層文字不再各自成為節點，避免引用被單獨念成一句。
      expect(find.bySemanticsLabel('明天一起吃飯？'), findsNothing);
      expect(find.bySemanticsLabel('好'), findsNothing);
    });

    testWidgets('可編修的泡泡在語意節點上保留長按動作', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _message('可以一起', isFromMe: false),
              onEdit: () {},
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.bySemanticsLabel('她說\n可以一起'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.longPress),
        isTrue,
      );
    });

    testWidgets('引用小卡原樣顯示截圖原文，不拆名字也不寫「引用我剛剛說的」', (tester) async {
      // 原文本身有冒號的情況（PR #86 審查 P2-2）也要原樣顯示。
      for (final quote in [
        '阿哲：感覺11點多到的就好',
        '時間：明天下午',
        '明天下午3：00見',
        'PS: 記得帶傘',
        '🙂 😮',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: _message(
                  '好',
                  isFromMe: true,
                  quote: quote,
                  quoteIsFromMe: true,
                ),
              ),
            ),
          ),
        );

        expect(find.text(quote), findsOneWidget, reason: quote);
        expect(find.text('引用我剛剛說的'), findsNothing, reason: quote);
        expect(find.text('引用對方剛剛說的'), findsNothing, reason: quote);
      }
      expect(find.text('阿哲'), findsNothing);
    });

    testWidgets('對方頭像只掛在每組第一則，我方不畫頭像', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MessageBubble(
                  message: _message('第一則', isFromMe: false),
                  partnerInitial: '雲',
                ),
                MessageBubble(
                  message: _message('連發第二則', isFromMe: false),
                  isGroupStart: false,
                  partnerInitial: '雲',
                ),
                MessageBubble(
                  message: _message('我的回覆', isFromMe: true),
                  partnerInitial: '雲',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('雲'), findsOneWidget);
      final firstLeft = tester.getTopLeft(find.text('第一則')).dx;
      final secondLeft = tester.getTopLeft(find.text('連發第二則')).dx;
      expect(secondLeft, firstLeft, reason: '連發的泡泡要和第一顆對齊頭像欄');
    });

    testWidgets('尾巴角只在每組第一顆，貼向說話者那側', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MessageBubble(message: _message('她組首', isFromMe: false)),
                MessageBubble(
                  message: _message('她連發', isFromMe: false),
                  isGroupStart: false,
                ),
                MessageBubble(message: _message('我組首', isFromMe: true)),
                MessageBubble(
                  message: _message('我連發', isFromMe: true),
                  isGroupStart: false,
                ),
              ],
            ),
          ),
        ),
      );

      BorderRadiusGeometry? radiusOf(String text) {
        final bubble = tester.widget<Container>(_bubbleOf(text));
        return (bubble.decoration! as BoxDecoration).borderRadius;
      }

      const round = Radius.circular(18);
      const tail = Radius.circular(5);
      expect(
        radiusOf('她組首'),
        const BorderRadius.only(
          topLeft: tail,
          topRight: round,
          bottomLeft: round,
          bottomRight: round,
        ),
      );
      expect(
        radiusOf('我組首'),
        const BorderRadius.only(
          topLeft: round,
          topRight: tail,
          bottomLeft: round,
          bottomRight: round,
        ),
      );
      expect(radiusOf('她連發'), const BorderRadius.all(round));
      expect(radiusOf('我連發'), const BorderRadius.all(round));
    });

    testWidgets('泡泡最寬為螢幕 70%，短句不會被撐寬', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const longText = '那我先問小美要不要一起，晚點再跟妳說時間，順便問她幾點到';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MessageBubble(message: _message(longText, isFromMe: true)),
                MessageBubble(message: _message('好', isFromMe: true)),
              ],
            ),
          ),
        ),
      );

      final longWidth = tester.getSize(_bubbleOf(longText)).width;
      expect(longWidth, lessThanOrEqualTo(390 * 0.7 + 0.5));
      expect(longWidth, greaterThan(390 * 0.6), reason: '長句應該頂到上限換行');
      expect(tester.getSize(_bubbleOf('好')).width, lessThan(80));
    });
  });
}

/// 泡泡本體：內文往上最近的 Container（引用小卡不是內文的祖先）。
Finder _bubbleOf(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(Container)).first;

Message _message(
  String content, {
  required bool isFromMe,
  String? quote,
  bool? quoteIsFromMe,
}) =>
    Message(
      id: content,
      content: content,
      isFromMe: isFromMe,
      timestamp: DateTime(2026, 10, 2),
      quotedReplyPreview: quote,
      quotedReplyPreviewIsFromMe: quoteIsFromMe,
    );

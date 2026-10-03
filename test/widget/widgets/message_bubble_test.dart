import 'package:flutter/material.dart';
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
  });
}

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

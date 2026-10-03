import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/sections/analysis_fragment_section.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/presentation/widgets/message_bubble.dart';

class _NoopFragmentActions implements AnalysisFragmentActions {
  const _NoopFragmentActions();

  @override
  void chooseConversationSource() {}

  @override
  void editFragmentMessage(Message message) {}

  @override
  void swapFragmentMessageSide(Message message) {}

  @override
  void deleteFragmentMessage(Message message) {}
}

Message _message(String id, {required bool isFromMe}) => Message(
      id: id,
      content: '訊息 $id',
      isFromMe: isFromMe,
      timestamp: DateTime(2026, 10, 2),
    );

Future<void> _pumpCard(
  WidgetTester tester, {
  required List<Message> messages,
  String? partnerName,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AnalysisFragmentCard(
            isEmptyFragmentSetup: false,
            isPendingFragment: false,
            isCompletedFragment: true,
            showRecordRepairWarning: false,
            isScreenshotOnlyEmptyState: false,
            showEmptyState: false,
            messages: [
              for (final message in messages)
                FragmentMessageItem(message: message, mutable: false),
            ],
            sourceLabel: '來源：LINE',
            sourceEditable: false,
            actions: const _NoopFragmentActions(),
            partnerName: partnerName,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('同一人連發只有第一則算組首，頭像取對象名字第一個字', (tester) async {
    await _pumpCard(
      tester,
      partnerName: ' 小雲 ',
      messages: [
        _message('1', isFromMe: false),
        _message('2', isFromMe: false),
        _message('3', isFromMe: true),
        _message('4', isFromMe: true),
        _message('5', isFromMe: false),
      ],
    );

    final bubbles =
        tester.widgetList<MessageBubble>(find.byType(MessageBubble)).toList();
    expect(
      bubbles.map((bubble) => bubble.isGroupStart),
      [true, false, true, false, true],
    );
    expect(bubbles.map((bubble) => bubble.partnerInitial).toSet(), {'小'});
    // 對方兩組各一個頭像，我方不畫。
    expect(find.text('小'), findsNWidgets(2));
    expect(find.text('她說'), findsNothing);
    expect(find.text('我說'), findsNothing);
  });

  testWidgets('泡泡之間：同一人連發 4、換人 12', (tester) async {
    await _pumpCard(
      tester,
      partnerName: '小雲',
      messages: [
        _message('1', isFromMe: false),
        _message('2', isFromMe: false),
        _message('3', isFromMe: true),
      ],
    );

    // 量泡泡本體（內文往上最近的 Container），不是整個 MessageBubble 列。
    Finder bubble(String text) => find
        .ancestor(of: find.text(text), matching: find.byType(Container))
        .first;
    double gapBetween(String upper, String lower) =>
        tester.getTopLeft(bubble(lower)).dy -
        tester.getBottomLeft(bubble(upper)).dy;

    expect(gapBetween('訊息 1', '訊息 2'), 4);
    expect(gapBetween('訊息 2', '訊息 3'), 12);
  });

  testWidgets('沒有對象名字就不畫頭像', (tester) async {
    await _pumpCard(
      tester,
      messages: [_message('1', isFromMe: false)],
    );

    final bubble = tester.widget<MessageBubble>(find.byType(MessageBubble));
    expect(bubble.partnerInitial, isNull);
  });

  testWidgets('「新對話」這類預設名稱不畫頭像（不會出現「新」）', (tester) async {
    for (final placeholder in ['新對話', '新的對話', '  ']) {
      await _pumpCard(
        tester,
        partnerName: placeholder,
        messages: [_message('1', isFromMe: false)],
      );

      final bubble = tester.widget<MessageBubble>(find.byType(MessageBubble));
      expect(bubble.partnerInitial, isNull, reason: placeholder);
      expect(find.text('新'), findsNothing, reason: placeholder);
    }
  });
}

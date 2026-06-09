import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/presentation/screens/new_conversation_screen.dart';

void main() {
  group('NewConversationScreen', () {
    testWidgets('displays title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('手動輸入'), findsOneWidget);
    });

    testWidgets('shows name input field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('對話對象'), findsOneWidget);
      expect(find.text('例如：小安'), findsOneWidget);
    });

    testWidgets('shows content input field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('對話內容'), findsOneWidget);
      expect(find.text('她說了什麼...'), findsOneWidget);
      expect(find.text('我說了什麼...'), findsOneWidget);
    });

    testWidgets('collapses analysis settings by default', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('這次分析設定（可不改）'), findsOneWidget);
      expect(find.text('交友軟體・剛認識・邀約見面'), findsOneWidget);
      expect(find.text('不確定可以先跳過；AI 會用預設情境分析。'), findsOneWidget);
      expect(find.text('認識情境'), findsNothing);
      expect(find.text('補充背景（選填）'), findsNothing);
    });

    testWidgets('expands meeting context selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      await tester.tap(find.text('這次分析設定（可不改）'));
      await tester.pump();

      expect(find.text('認識情境'), findsOneWidget);
      expect(find.text('交友軟體'), findsOneWidget);
      expect(find.text('現實認識'), findsOneWidget);
      expect(find.text('朋友介紹'), findsOneWidget);
      expect(find.text('已是伴侶'), findsOneWidget);
      expect(find.text('其他'), findsNothing);
    });

    testWidgets('expands duration selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      await tester.tap(find.text('這次分析設定（可不改）'));
      await tester.pump();

      expect(find.text('認識多久'), findsOneWidget);
      expect(find.text('剛認識'), findsOneWidget);
      expect(find.text('幾天'), findsOneWidget);
      expect(find.text('幾週'), findsOneWidget);
      expect(find.text('一個月以上'), findsOneWidget);
    });

    testWidgets('expands goal selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      await tester.tap(find.text('這次分析設定（可不改）'));
      await tester.pump();

      expect(find.text('目前目標'), findsOneWidget);
      expect(find.text('邀約見面'), findsOneWidget);
      expect(find.text('維持熱度'), findsOneWidget);
      expect(find.text('自然聊天'), findsOneWidget);
    });

    testWidgets('shows optional analysis context note field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      await tester.tap(find.text('這次分析設定（可不改）'));
      await tester.pump();

      expect(find.text('補充背景（選填）'), findsOneWidget);
      expect(find.text('沒有可以留空'), findsOneWidget);
      expect(find.text('其他'), findsNothing);
      expect(find.textContaining('只影響這個對話的分析'), findsOneWidget);
      final noteField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '沒有可以留空',
        ),
      );
      expect(noteField.maxLength, 300);
      expect(noteField.textInputAction, TextInputAction.done);
    });

    testWidgets('hides save button before any message is added',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('先儲存對話'), findsNothing);
    });

    testWidgets('keeps save button hidden after only outgoing message is added',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      final myMessageField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '我說了什麼...',
      );
      await tester.ensureVisible(myMessageField);
      await tester.enterText(myMessageField, '你好');
      final addButton = find.byIcon(Icons.add).last;
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pump();

      expect(find.text('先儲存對話'), findsNothing);
      expect(find.text('先儲存開場草稿'), findsNothing);
      expect(find.text('建立對話'), findsNothing);
    });

    testWidgets('shows create button after incoming message is added',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      final herMessageField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '她說了什麼...',
      );
      await tester.ensureVisible(herMessageField);
      await tester.enterText(herMessageField, '你好');
      final addButton = find.byIcon(Icons.add).first;
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pump();

      expect(find.text('建立對話'), findsOneWidget);
    });

    testWidgets('shows current message-entry hint', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('依序輸入對話，至少先加入一則訊息。'), findsOneWidget);
    });
  });
}

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

    testWidgets('shows meeting context selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('認識情境'), findsOneWidget);
      expect(find.text('交友軟體'), findsOneWidget);
      expect(find.text('現實認識'), findsOneWidget);
      expect(find.text('朋友介紹'), findsOneWidget);
    });

    testWidgets('shows duration selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('認識多久'), findsOneWidget);
      expect(find.text('剛認識'), findsOneWidget);
      expect(find.text('幾天'), findsOneWidget);
      expect(find.text('幾週'), findsOneWidget);
      expect(find.text('一個月以上'), findsOneWidget);
    });

    testWidgets('shows goal selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('目前目標'), findsOneWidget);
      expect(find.text('邀約見面'), findsOneWidget);
      expect(find.text('維持熱度'), findsOneWidget);
      expect(find.text('自然聊天'), findsOneWidget);
    });

    testWidgets('shows analyze button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('先儲存對話'), findsOneWidget);
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

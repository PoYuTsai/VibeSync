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

      expect(find.text('新增對話'), findsOneWidget);
    });

    testWidgets('shows name input field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('對話對象暱稱'), findsOneWidget);
    });

    testWidgets('shows content input field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('貼上對話內容'), findsOneWidget);
    });

    testWidgets('shows meeting context selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('認識場景'), findsOneWidget);
      expect(find.text('交友軟體'), findsOneWidget);
      expect(find.text('現實搭訕'), findsOneWidget);
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
      expect(find.text('一個月+'), findsOneWidget);
    });

    testWidgets('shows goal selector', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('你的目標'), findsOneWidget);
      expect(find.text('約出來'), findsOneWidget);
      expect(find.text('維持熱度'), findsOneWidget);
      expect(find.text('隨意聊'), findsOneWidget);
    });

    testWidgets('shows analyze button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('開始分析'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows format hint', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('格式：每行一則訊息，以「她:」或「我:」開頭'), findsOneWidget);
    });
  });
}

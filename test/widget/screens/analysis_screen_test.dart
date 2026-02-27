import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

void main() {
  group('AnalysisScreen', () {
    // Helper to pump with enough time for the 2-second delay to complete
    Future<void> pumpWithDelay(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }

    testWidgets('shows loading state initially', (tester) async {
      final testConversation = Conversation(
        id: 'test-123',
        name: 'Test User',
        messages: [
          Message(
            id: '1',
            content: '嗨',
            isFromMe: false,
            timestamp: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationProvider('test-123').overrideWithValue(testConversation),
          ],
          child: const MaterialApp(
            home: AnalysisScreen(conversationId: 'test-123'),
          ),
        ),
      );

      // Should show loading indicator initially
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Let the timer complete to avoid pending timer error
      await pumpWithDelay(tester);
    });

    testWidgets('shows back button', (tester) async {
      final testConversation = Conversation(
        id: 'test-123',
        name: 'Test User',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationProvider('test-123').overrideWithValue(testConversation),
          ],
          child: const MaterialApp(
            home: AnalysisScreen(conversationId: 'test-123'),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Let the timer complete to avoid pending timer error
      await pumpWithDelay(tester);
    });

    testWidgets('shows conversation name in app bar', (tester) async {
      final testConversation = Conversation(
        id: 'test-123',
        name: 'Alice',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationProvider('test-123').overrideWithValue(testConversation),
          ],
          child: const MaterialApp(
            home: AnalysisScreen(conversationId: 'test-123'),
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);

      // Let the timer complete to avoid pending timer error
      await pumpWithDelay(tester);
    });

    testWidgets('shows not found when conversation does not exist',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationProvider('non-existent').overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: AnalysisScreen(conversationId: 'non-existent'),
          ),
        ),
      );

      expect(find.text('找不到對話'), findsOneWidget);

      // Let the timer complete (it will still run even with null conversation)
      await pumpWithDelay(tester);
    });

    testWidgets('shows analysis results after loading', (tester) async {
      final testConversation = Conversation(
        id: 'test-123',
        name: 'Alice',
        messages: [
          Message(
            id: '1',
            content: '週末我去爬抹茶山',
            isFromMe: false,
            timestamp: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationProvider('test-123').overrideWithValue(testConversation),
          ],
          child: const MaterialApp(
            home: AnalysisScreen(conversationId: 'test-123'),
          ),
        ),
      );

      // Wait for analysis to complete (mock delay is 2 seconds)
      await pumpWithDelay(tester);

      // Should show analysis sections
      expect(find.text('熱度分析'), findsOneWidget);
      expect(find.text('建議回覆'), findsOneWidget);
      expect(find.text('AI 推薦回覆'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/presentation/screens/home_screen.dart';

void main() {
  group('HomeScreen', () {
    testWidgets('displays app title', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationsProvider.overrideWithValue([]),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.text('VibeSync'), findsOneWidget);
    });

    testWidgets('shows empty state when no conversations', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationsProvider.overrideWithValue([]),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.text('還沒有對話'), findsOneWidget);
      expect(find.text('點擊右下角 + 開始新增'), findsOneWidget);
    });

    testWidgets('shows FAB button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationsProvider.overrideWithValue([]),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows settings icon', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationsProvider.overrideWithValue([]),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('shows empty state icon', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationsProvider.overrideWithValue([]),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('shows conversation list when conversations exist',
        (tester) async {
      final testConversation = Conversation(
        id: '1',
        name: 'Alice',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastEnthusiasmScore: 75,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationsProvider.overrideWithValue([testConversation]),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('還沒有對話'), findsNothing);
    });
  });
}

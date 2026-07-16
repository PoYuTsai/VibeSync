import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../helpers/memory_coaching_outcome_repository.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

void main() {
  group('AnalysisScreen', () {
    testWidgets('shows manual analysis action initially', (tester) async {
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
            coachingOutcomeRepositoryProvider
                .overrideWithValue(MemoryCoachingOutcomeRepository()),
            conversationProvider('test-123')
                .overrideWithValue(testConversation),
          ],
          child: const MaterialApp(
            home: AnalysisScreen(conversationId: 'test-123'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('開始分析'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('analysis-records-entry')),
        findsOneWidget,
      );
      expect(find.byTooltip('分析紀錄'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('analysis-record-count-badge')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('analysis-source-pill')),
        findsOneWidget,
      );
      expect(find.text('來源未設定'), findsOneWidget);
      expect(find.textContaining('未分類'), findsNothing);
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
            coachingOutcomeRepositoryProvider
                .overrideWithValue(MemoryCoachingOutcomeRepository()),
            conversationProvider('test-123')
                .overrideWithValue(testConversation),
          ],
          child: const MaterialApp(
            home: AnalysisScreen(conversationId: 'test-123'),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
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
            coachingOutcomeRepositoryProvider
                .overrideWithValue(MemoryCoachingOutcomeRepository()),
            conversationProvider('test-123')
                .overrideWithValue(testConversation),
          ],
          child: const MaterialApp(
            home: AnalysisScreen(conversationId: 'test-123'),
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows not found when conversation does not exist',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coachingOutcomeRepositoryProvider
                .overrideWithValue(MemoryCoachingOutcomeRepository()),
            conversationProvider('non-existent').overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: AnalysisScreen(conversationId: 'non-existent'),
          ),
        ),
      );

      expect(find.text('找不到對話'), findsOneWidget);
    });

    testWidgets('shows message preview without legacy append controls',
        (tester) async {
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
            coachingOutcomeRepositoryProvider
                .overrideWithValue(MemoryCoachingOutcomeRepository()),
            conversationProvider('test-123')
                .overrideWithValue(testConversation),
          ],
          child: const MaterialApp(
            home: AnalysisScreen(conversationId: 'test-123'),
          ),
        ),
      );

      expect(find.text('週末我去爬抹茶山'), findsOneWidget);
      expect(find.text('開始分析'), findsOneWidget);
      expect(find.text('建立本次片段'), findsNothing);
      expect(find.text('貼上或輸入新的一則訊息…'), findsNothing);
      expect(find.text('分析新增內容'), findsNothing);
      expect(find.textContaining('有 1 則新訊息'), findsNothing);
    });
  });
}

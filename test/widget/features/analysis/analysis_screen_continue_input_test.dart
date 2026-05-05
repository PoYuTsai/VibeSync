import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Future<void> _pumpAnalysisScreen(
  WidgetTester tester, {
  List<Message>? messages,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final conversation = Conversation(
    id: 'continue-input-test',
    name: '小雲',
    messages: messages ??
        [
          Message(
            id: 'm1',
            content: '昨天那家甜點不錯耶',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 4),
          ),
        ],
    createdAt: DateTime(2026, 5, 4),
    updatedAt: DateTime(2026, 5, 4),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conversationProvider('continue-input-test')
            .overrideWithValue(conversation),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: 'continue-input-test'),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('AnalysisScreen continue input', () {
    testWidgets('explains that text must be entered before choosing speaker',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      expect(find.text('貼上或輸入新的一則訊息...'), findsOneWidget);
      expect(find.text('輸入後，再選下方「加入為她說」或「加入為我說」。'), findsOneWidget);
      expect(find.text('加入為她說'), findsOneWidget);
      expect(find.text('加入為我說'), findsOneWidget);
    });

    testWidgets(
        'shows a reminder when tapping her-message button with empty input',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      final herButton = find.text('加入為她說');
      await tester.ensureVisible(herButton);
      await tester.tap(herButton);
      await tester.pump();

      expect(
        find.text('先貼上或輸入對方的新回覆，再點「加入為她說」。'),
        findsOneWidget,
      );
    });

    testWidgets('collapsed preview shows latest messages instead of oldest',
        (tester) async {
      await _pumpAnalysisScreen(
        tester,
        messages: List.generate(
          6,
          (index) => Message(
            id: 'm$index',
            content: '訊息 ${index + 1}',
            isFromMe: index.isOdd,
            timestamp: DateTime(2026, 5, 4, 12, index),
          ),
        ),
      );

      expect(find.text('訊息 1'), findsNothing);
      expect(find.text('訊息 2'), findsOneWidget);
      expect(find.text('訊息 6'), findsOneWidget);
      expect(find.text('展開全部 6 則訊息'), findsOneWidget);
    });
  });
}

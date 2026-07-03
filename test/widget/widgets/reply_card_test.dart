import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/shared/widgets/reply_card.dart';

void main() {
  group('ReplyCard', () {
    testWidgets('displays correct label for extend type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplyCard(
              type: ReplyType.extend,
              content: '測試內容',
            ),
          ),
        ),
      );

      expect(find.text('🔄 延展・深挖她的回答'), findsOneWidget);
      expect(find.text('測試內容'), findsOneWidget);
    });

    testWidgets('displays correct label for resonate type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplyCard(
              type: ReplyType.resonate,
              content: '共鳴內容',
            ),
          ),
        ),
      );

      expect(find.text('💬 共鳴・讓她覺得你懂她'), findsOneWidget);
    });

    testWidgets('displays correct label for tease type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplyCard(
              type: ReplyType.tease,
              content: '調情內容',
            ),
          ),
        ),
      );

      expect(find.text('😏 調情・製造曖昧張力'), findsOneWidget);
    });

    testWidgets('displays correct label for humor type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplyCard(
              type: ReplyType.humor,
              content: '幽默內容',
            ),
          ),
        ),
      );

      expect(find.text('🎭 幽默・讓她笑著想回'), findsOneWidget);
    });

    testWidgets('displays correct label for coldRead type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplyCard(
              type: ReplyType.coldRead,
              content: '冷讀內容',
            ),
          ),
        ),
      );

      expect(find.text('🔮 冷讀・猜中她沒說的'), findsOneWidget);
    });

    testWidgets('shows lock icon when isLocked is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplyCard(
              type: ReplyType.resonate,
              content: '測試內容',
              isLocked: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.text('升級解鎖完整分析'), findsOneWidget);
    });

    testWidgets('shows copy icon when not locked', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplyCard(
              type: ReplyType.extend,
              content: '測試內容',
              isLocked: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.copy), findsOneWidget);
    });
  });
}

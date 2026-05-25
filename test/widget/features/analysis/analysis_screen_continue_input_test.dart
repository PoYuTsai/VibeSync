import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

import '../conversation/_fakes/recording_conversation_write_controller.dart';

Future<void> _pumpAnalysisScreen(
  WidgetTester tester, {
  Conversation? conversation,
  List<Message>? messages,
  ConversationWriteController? writeController,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final testConversation = conversation ??
      Conversation(
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
            .overrideWithValue(testConversation),
        if (writeController != null)
          conversationWriteControllerProvider
              .overrideWith(() => writeController),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: 'continue-input-test'),
      ),
    ),
  );
  await tester.pump();
  await _dismissEditHintIfVisible(tester);
}

Future<void> _dismissEditHintIfVisible(WidgetTester tester) async {
  await tester.pump();
  final dismissButton = find.text('知道了');
  if (dismissButton.evaluate().isEmpty) {
    return;
  }
  await tester.tap(dismissButton);
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AnalysisScreen continue input', () {
    testWidgets('explains that text must be entered before choosing speaker',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      expect(find.text('貼上或輸入新的一則訊息...'), findsOneWidget);
      expect(find.text('建立這段對話'), findsOneWidget);
      expect(find.text('輸入完先收起鍵盤，再選這句是她說，還是我說。'), findsOneWidget);
      expect(find.text('這句是她說'), findsOneWidget);
      expect(find.text('這句是我說'), findsOneWidget);
    });

    testWidgets('manual input can dismiss keyboard before choosing speaker',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      final textFieldFinder = find.byType(TextField).last;
      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.textInputAction, TextInputAction.done);
      expect(find.byTooltip('收起鍵盤'), findsOneWidget);

      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, '要幫你帶什麼嗎？');
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.byTooltip('收起鍵盤'));
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('edit dialog keeps the text field readable on a light surface',
        (tester) async {
      await _pumpAnalysisScreen(
        tester,
        messages: [
          Message(
            id: 'm1',
            content: 'Readable edit target',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 4),
          ),
        ],
      );

      final bubble = find.text('Readable edit target').first;
      await tester.ensureVisible(bubble);
      await tester.longPress(bubble);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('編輯文字'));
      await tester.pump(const Duration(milliseconds: 300));

      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.backgroundColor, AppColors.glassWhite);
      expect(dialog.surfaceTintColor, Colors.transparent);

      final fieldFinder = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      final field = tester.widget<TextField>(fieldFinder);
      expect(field.cursorColor, AppColors.primary);
      expect(field.style?.color, AppColors.glassTextPrimary);
      expect(field.decoration?.filled, isTrue);
      expect(field.decoration?.fillColor, Colors.white);
    });

    testWidgets('editing an analyzed bubble shows a reanalysis call to action',
        (tester) async {
      final conversation = Conversation(
        id: 'continue-input-test',
        name: '小雲',
        messages: [
          Message(
            id: 'm1',
            content: 'Original analyzed text',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 4),
          ),
        ],
        createdAt: DateTime(2026, 5, 4),
        updatedAt: DateTime(2026, 5, 4),
        lastAnalyzedMessageCount: 1,
        lastAnalysisSnapshotJson: jsonEncode({
          'enthusiasm': {'score': 65},
        }),
      );

      await _pumpAnalysisScreen(
        tester,
        conversation: conversation,
        writeController: RecordingConversationWriteController(),
      );

      final bubble = find.text('Original analyzed text').first;
      await tester.ensureVisible(bubble);
      await tester.longPress(bubble);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('編輯文字'));
      await tester.pump(const Duration(milliseconds: 300));

      final fieldFinder = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fieldFinder, 'Updated analyzed text');
      await tester.tap(find.widgetWithText(TextButton, '儲存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('已修改已分析過的訊息，重新分析後會更新熱度與回覆建議。'),
        findsOneWidget,
      );
      expect(find.text('已儲存，點重新分析更新結果。'), findsOneWidget);
      expect(find.text('重新分析'), findsWidgets);
    });

    testWidgets(
        'shows a reminder when tapping her-message button with empty input',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      final herButton = find.text('這句是她說');
      await tester.ensureVisible(herButton);
      await tester.tap(herButton);
      await tester.pump();

      expect(
        find.text('先貼上或輸入對方的新回覆，再點「這句是她說」。'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('empty conversation explains the first manual-input step',
        (tester) async {
      await _pumpAnalysisScreen(tester, messages: const []);

      expect(find.text('還沒有訊息'), findsOneWidget);
      expect(
        find.text('先在下方輸入一句，再選「這句是她說」或「這句是我說」。'),
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

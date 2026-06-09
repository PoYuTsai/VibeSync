import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/services/screenshot_recognition_helper.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';

void main() {
  Widget buildDialogHost({
    required RecognizedConversation recognized,
    required String initialImportMode,
    required bool forceShowSessionContextFields,
    String? warningMessage,
    String initialName = '',
    MeetingContext? initialMeetingContext,
    AcquaintanceDuration? initialDuration,
    UserGoal? initialGoal,
    String initialAnalysisContextNote = '',
    Conversation? currentConversation,
    ValueChanged<ScreenshotRecognitionDialogResult?>? onResult,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result =
                  await showDialog<ScreenshotRecognitionDialogResult>(
                context: context,
                builder: (_) => ScreenshotRecognitionDialog(
                  recognized: recognized,
                  warningMessage: warningMessage,
                  initialName: initialName,
                  initialMeetingContext: initialMeetingContext,
                  initialDuration: initialDuration,
                  initialGoal: initialGoal,
                  initialAnalysisContextNote: initialAnalysisContextNote,
                  initialImportMode: initialImportMode,
                  forceShowSessionContextFields: forceShowSessionContextFields,
                  currentConversation: currentConversation ??
                      Conversation(
                        id: 'conversation-1',
                        name: '小美',
                        messages: [
                          Message(
                            id: 'her-1',
                            content: '哈囉',
                            isFromMe: false,
                            timestamp: DateTime(2026, 3, 24),
                          ),
                        ],
                        createdAt: DateTime(2026, 3, 24),
                        updatedAt: DateTime(2026, 3, 24),
                      ),
                ),
              );
              onResult?.call(result);
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    );
  }

  const recognizedConversation = RecognizedConversation(
    contactName: '小美',
    messageCount: 3,
    summary: '識別到 3 則訊息',
    classification: 'low_confidence',
    importPolicy: 'confirm',
    confidence: 'low',
    messages: [
      RecognizedMessage(side: 'left', isFromMe: false, content: '你今天在忙嗎'),
      RecognizedMessage(side: 'right', isFromMe: true, content: '剛忙完'),
      RecognizedMessage(side: 'right', isFromMe: false, content: '那晚點聊'),
    ],
  );

  group('ScreenshotRecognitionDialog', () {
    testWidgets('shows OCR status badges and guidance', (tester) async {
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          warningMessage: '這張截圖辨識信心較低，加入前請先確認預覽內容是否正確。',
          initialImportMode:
              ScreenshotRecognitionHelper.importModeNewConversation,
          forceShowSessionContextFields: true,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('需要確認'), findsOneWidget);
      expect(find.text('內容需確認'), findsOneWidget);
      expect(find.text('先確認再加入'), findsOneWidget);
      expect(find.textContaining('請先確認內容和「我說／她說」'), findsOneWidget);
      expect(find.textContaining('LINE 的回覆引用框'), findsOneWidget);
      expect(find.text('另存成新對話'), findsOneWidget);
    });

    testWidgets('returns selected import mode on confirm', (tester) async {
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('另存成新對話'));
      await tester.pumpAndSettle();
      await tester.enterText(_partnerNameField(), 'Amber');
      await tester.tap(find.text('確認加入對話'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(
        dialogResult!.importMode,
        ScreenshotRecognitionHelper.importModeNewConversation,
      );
      expect(dialogResult!.name, 'Amber');
    });

    testWidgets('shows session context fields when requested', (tester) async {
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeNewConversation,
          forceShowSessionContextFields: true,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('認識場景（選填）'), findsOneWidget);
      expect(find.text('認識多久（選填）'), findsOneWidget);
    });

    testWidgets('returns null when cancelled', (tester) async {
      ScreenshotRecognitionDialogResult? dialogResult =
          const ScreenshotRecognitionDialogResult(
        name: 'sentinel',
        meetingContext: null,
        duration: null,
        goal: null,
        analysisContextNote: null,
        importMode: ScreenshotRecognitionHelper.importModeAppendCurrent,
        messages: [],
      );

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('稍後再加入'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });

    testWidgets('returns selected goal with session context', (tester) async {
      await _useTallSurface(tester);

      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeNewConversation,
          forceShowSessionContextFields: true,
          initialMeetingContext: MeetingContext.datingApp,
          initialDuration: AcquaintanceDuration.justMet,
          initialGoal: UserGoal.maintainHeat,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('目前目標'), findsOneWidget);
      await tester.tap(find.text('確認加入對話'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.goal, UserGoal.maintainHeat);
    });

    testWidgets('returns optional analysis context note', (tester) async {
      await _useTallSurface(tester);

      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeNewConversation,
          forceShowSessionContextFields: true,
          initialMeetingContext: MeetingContext.committedPartner,
          initialDuration: AcquaintanceDuration.monthPlus,
          initialGoal: UserGoal.justChat,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final noteField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '沒有可以留空',
        ),
      );
      expect(noteField.maxLength, 300);
      expect(noteField.textInputAction, TextInputAction.done);
      expect(find.text('其他'), findsNothing);
      await tester.enterText(find.byType(TextField).last, '她是我女友');
      await tester.tap(find.text('確認加入對話'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.analysisContextNote, '她是我女友');
    });

    testWidgets('allows editing speaker and content before import',
        (tester) async {
      await _useTallSurface(tester);

      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.textContaining('有問題可以直接修改'), findsOneWidget);
      expect(find.text('依左／右重新套用'), findsOneWidget);

      await _tapVisible(tester, find.widgetWithText(ChoiceChip, '我說').first);

      final textFields = find.byType(TextField);
      expect(textFields, findsAtLeastNWidgets(3));

      await tester.enterText(textFields.at(0), '其實剛好忙完，晚點可以聊');
      await tester.tap(find.byTooltip('刪除這則訊息').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('刪除'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages, hasLength(2));
      expect(dialogResult!.messages.first.isFromMe, isTrue);
      expect(dialogResult!.messages.first.content, '其實剛好忙完，晚點可以聊');
    });

    testWidgets('supports batch speaker correction from bubble sides',
        (tester) async {
      await _useTallSurface(tester);

      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('依左／右重新套用'));

      await _tapVisible(tester, find.text('這幾則都改成我說'));

      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages[0].isFromMe, isFalse);
      expect(dialogResult!.messages[1].isFromMe, isTrue);
      expect(dialogResult!.messages[2].isFromMe, isTrue);
    });

    testWidgets('shows batch correction as optional quick fix copy',
        (tester) async {
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('這幾則都改成我說'), findsOneWidget);
      expect(find.textContaining('如果每則都判對了'), findsOneWidget);
      expect(find.textContaining('這區可以直接略過'), findsOneWidget);
    });
  });
}

Finder _partnerNameField() {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == '輸入對方名字',
    description: 'partner name TextField',
  );
}

Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(500, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

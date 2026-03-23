import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/services/screenshot_recognition_helper.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart';
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
                  initialImportMode: initialImportMode,
                  forceShowSessionContextFields: forceShowSessionContextFields,
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
          warningMessage: '這張截圖辨識信心較低，匯入前請先確認預覽內容是否正確。',
          initialImportMode:
              ScreenshotRecognitionHelper.importModeNewConversation,
          forceShowSessionContextFields: true,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('識別成功'), findsOneWidget);
      expect(find.text('低信心'), findsOneWidget);
      expect(find.text('信心偏低'), findsOneWidget);
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
      await tester.enterText(find.byType(TextField), 'Amber');
      await tester.tap(find.text('確認匯入'));
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
      await tester.tap(find.text('稍後再匯入'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });

    testWidgets('allows editing speaker and content before import',
        (tester) async {
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

      expect(find.textContaining('可直接修正錯字'), findsOneWidget);
      expect(find.text('依左 / 右重新套用'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '我說').first);
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(4));

      await tester.enterText(textFields.at(0), '其實剛好忙完，晚點可以聊');
      await tester.tap(find.byTooltip('刪除這則訊息').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認匯入'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages, hasLength(2));
      expect(dialogResult!.messages.first.isFromMe, isTrue);
      expect(dialogResult!.messages.first.content, '其實剛好忙完，晚點可以聊');
    });

    testWidgets('supports batch speaker correction from bubble sides',
        (tester) async {
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

      await tester.tap(find.text('依左 / 右重新套用'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('這組改成我說'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('確認匯入'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages[0].isFromMe, isFalse);
      expect(dialogResult!.messages[1].isFromMe, isTrue);
      expect(dialogResult!.messages[2].isFromMe, isTrue);
    });
  });
}

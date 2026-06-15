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

  const quotedHighConfidenceConversation = RecognizedConversation(
    contactName: 'Candy',
    messageCount: 2,
    summary: '識別到 2 則訊息',
    classification: 'valid_chat',
    importPolicy: 'allow',
    confidence: 'high',
    sideConfidence: 'high',
    messages: [
      RecognizedMessage(
        side: 'left',
        isFromMe: false,
        content: '好可愛',
        quotedReplyPreview: 'Bruce Chiang: 🐶',
        quotedReplyPreviewIsFromMe: true,
      ),
      RecognizedMessage(
        side: 'left',
        isFromMe: false,
        content: '今天北鼻都是這隻紅貴賓',
      ),
    ],
  );

  // 假 mixed：高信心 allow，但同時有「我說」「她說」。暗色單側誤讀的失敗型態
  // 正是長成這樣（見 ai-arbitration-queue Track 2 量測 A/B）——所以這種對話
  // 不該走 compact「方向看起來很穩」安撫流程。
  const mixedHighConfidenceConversation = RecognizedConversation(
    contactName: '小美',
    messageCount: 3,
    summary: '識別到 3 則訊息',
    classification: 'valid_chat',
    importPolicy: 'allow',
    confidence: 'high',
    sideConfidence: 'high',
    messages: [
      RecognizedMessage(side: 'left', isFromMe: false, content: '在幹嘛'),
      RecognizedMessage(side: 'right', isFromMe: true, content: '剛回到家'),
      RecognizedMessage(side: 'left', isFromMe: false, content: '這麼晚還沒睡'),
    ],
  );

  // 真正單側（整段她說），高信心。這種沒有可被誤翻的「我說」，仍可走 compact，
  // 確保 mixed 排除沒有過度擴張到正常單側截圖。
  const singleSpeakerHighConfidenceConversation = RecognizedConversation(
    contactName: '小美',
    messageCount: 3,
    summary: '識別到 3 則訊息',
    classification: 'valid_chat',
    importPolicy: 'allow',
    confidence: 'high',
    sideConfidence: 'high',
    messages: [
      RecognizedMessage(side: 'left', isFromMe: false, content: '在幹嘛'),
      RecognizedMessage(side: 'left', isFromMe: false, content: '這麼晚還沒睡'),
      RecognizedMessage(side: 'left', isFromMe: false, content: '我剛洗完澡'),
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

    testWidgets('quoted replies keep side-direction review copy visible',
        (tester) async {
      await tester.pumpWidget(
        buildDialogHost(
          recognized: quotedHighConfidenceConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('先確認我說 / 她說'), findsOneWidget);
      expect(find.textContaining('回覆引用框'), findsWidgets);
      expect(find.textContaining('引用卡裡的人名'), findsWidgets);
      expect(find.textContaining('方向看起來很穩'), findsNothing);
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

    testWidgets('預設唯讀預覽：內容攤開可檢查但不可直接編輯，點「編輯內容」才開啟', (tester) async {
      await _useTallSurface(tester);

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

      // 唯讀預覽：訊息內容看得到（攤開給用戶質疑），但不在 TextField 裡，
      // 也沒有她說／我說切換 chip。
      expect(find.text('你今天在忙嗎'), findsOneWidget);
      expect(find.widgetWithText(TextField, '你今天在忙嗎'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, '我說'), findsNothing);

      // 點功能鍵才進入編輯模式。
      await _tapVisible(tester, find.text('編輯內容'));
      expect(find.widgetWithText(TextField, '你今天在忙嗎'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '我說'), findsWidgets);

      // 完成編輯收回唯讀預覽。
      await _tapVisible(tester, find.text('完成編輯'));
      expect(find.widgetWithText(ChoiceChip, '我說'), findsNothing);
    });

    testWidgets('收合預覽下送出 0 則有效訊息 → 驗證訊息可見並自動展開編輯', (tester) async {
      await _useTallSurface(tester);

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

      await _tapVisible(tester, find.text('編輯內容'));
      for (final original in ['你今天在忙嗎', '剛忙完', '那晚點聊']) {
        final field = find.widgetWithText(TextField, original);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, '');
        await tester.pumpAndSettle();
      }
      await _tapVisible(tester, find.text('完成編輯'));

      await _tapVisible(tester, find.text('確認加入對話'));

      expect(find.text('至少要保留一則可加入對話的訊息。'), findsOneWidget);
      // 自動展開編輯模式，讓用戶能直接修。
      expect(find.widgetWithText(ChoiceChip, '我說'), findsWidgets);
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

      await _tapVisible(tester, find.text('編輯內容'));

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

      await _tapVisible(tester, find.text('編輯內容'));
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

      await _tapVisible(tester, find.text('編輯內容'));

      expect(find.text('這幾則都改成我說'), findsOneWidget);
      expect(find.textContaining('如果每則都判對了'), findsOneWidget);
      expect(find.textContaining('這區可以直接略過'), findsOneWidget);
    });

    testWidgets('mixed-speaker high-confidence conversation cancels the '
        'compact「方向看起來很穩」reassurance', (tester) async {
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedHighConfidenceConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.textContaining('方向看起來很穩'), findsNothing);
    });

    testWidgets('single-speaker high-confidence conversation keeps the compact '
        'reassurance (mixed exclusion does not over-broaden)', (tester) async {
      await tester.pumpWidget(
        buildDialogHost(
          recognized: singleSpeakerHighConfidenceConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.textContaining('方向看起來很穩'), findsOneWidget);
    });

    testWidgets('offers a one-tap「全部都是對方說的」fallback that marks every '
        'message as the other person', (tester) async {
      await _useTallSurface(tester);

      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedHighConfidenceConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // 兜底鍵在預覽層就看得到，不必先點「編輯內容」。
      await _tapVisible(tester, find.text('全部都是對方說的'));
      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages, hasLength(3));
      expect(
        dialogResult!.messages.every((message) => !message.isFromMe),
        isTrue,
      );
    });

    testWidgets('hides the「全部都是對方說的」fallback when nothing is marked '
        'as me', (tester) async {
      await tester.pumpWidget(
        buildDialogHost(
          recognized: singleSpeakerHighConfidenceConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('全部都是對方說的'), findsNothing);
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

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

  const quotedConversation = RecognizedConversation(
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

  // 含「我說」「她說」混合的對話。第 0 則初始她說、第 1 則初始我說，方便分別
  // 驗證右滑改我說 / 左滑改她說。
  const mixedConversation = RecognizedConversation(
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

  // 整段都是對方說的（全部 isFromMe=false），驗證沒有「我說」時兜底鍵隱藏。
  const singleSpeakerConversation = RecognizedConversation(
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

  group('ScreenshotRecognitionDialog 滑動校正器', () {
    testWidgets('顯示滑動提示，砍掉 OCR 信心徽章與安撫框，但保留警示與加入方式',
        (tester) async {
      await _useTallSurface(tester);
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

      // 保留：滑動提示一行 + 加入方式切換 + 低信心警示。
      expect(find.text('判錯邊？左右滑動訊息即可切換。'), findsOneWidget);
      expect(find.text('另存成新對話'), findsOneWidget);
      expect(find.textContaining('辨識信心較低'), findsWidgets);

      // 砍掉：狀態徽章、安撫框、舊編輯器入口。
      expect(find.text('需要確認'), findsNothing);
      expect(find.text('內容需確認'), findsNothing);
      expect(find.textContaining('方向看起來很穩'), findsNothing);
      expect(find.text('編輯內容'), findsNothing);
      expect(find.text('依左／右重新套用'), findsNothing);
    });

    testWidgets('右滑超過門檻 → 該則改成我說 (isFromMe=true)', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // 第 0 則「在幹嘛」初始她說，右滑改我說。
      await tester.drag(find.text('在幹嘛'), const Offset(400, 0));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages[0].isFromMe, isTrue);
    });

    testWidgets('左滑超過門檻 → 該則改成她說 (isFromMe=false)', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // 第 1 則「剛回到家」初始我說，左滑改她說。
      await tester.drag(find.text('剛回到家'), const Offset(-400, 0));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages[1].isFromMe, isFalse);
    });

    testWidgets('門檻內放開 → isFromMe 不變、彈回原側', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // 第 0 則「在幹嘛」初始她說，右滑一小段（已過 touch slop 但未過切換門檻）
      // 應彈回、不切換。
      await tester.drag(find.text('在幹嘛'), const Offset(40, 0));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages[0].isFromMe, isFalse);
    });

    testWidgets('點泡泡開單則編輯 sheet → 改文字後送出同步', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('在幹嘛'));

      // sheet 內出現可編輯文字框。
      expect(find.widgetWithText(TextField, '在幹嘛'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '在幹嘛'),
        '你在幹嘛呀',
      );
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('完成'));

      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages[0].content, '你在幹嘛呀');
    });

    testWidgets('點泡泡開 sheet → 刪除該則後該則消失', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('剛回到家'));
      await _tapVisible(tester, find.text('刪除這則訊息'));
      // 二次確認刪除。
      await _tapVisible(tester, find.text('刪除'));

      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages, hasLength(2));
      expect(
        dialogResult!.messages.any((message) => message.content == '剛回到家'),
        isFalse,
      );
    });

    testWidgets('清空所有訊息後送出 → 顯示「至少保留一則」驗證且不送出',
        (tester) async {
      await _useTallSurface(tester);
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
          recognized: mixedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      for (final original in ['在幹嘛', '剛回到家', '這麼晚還沒睡']) {
        await _tapVisible(tester, find.text(original));
        await tester.enterText(find.widgetWithText(TextField, original), '');
        await tester.pumpAndSettle();
        await _tapVisible(tester, find.text('完成'));
      }

      await _tapVisible(tester, find.text('確認加入對話'));

      expect(find.text('至少要保留一則可加入對話的訊息。'), findsOneWidget);
      // dialog 不應 pop（仍是初始 sentinel，未被覆寫）。
      expect(dialogResult, isNotNull);
      expect(dialogResult!.name, 'sentinel');
    });

    testWidgets('引用預覽唯讀顯示，且不再有引用歸屬切換', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: quotedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Bruce Chiang'), findsWidgets);
      expect(find.text('引用我方'), findsNothing);
      expect(find.text('引用對方'), findsNothing);
    });

    testWidgets('有「我說」時提供一鍵「全部都是對方說的」兜底', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          initialImportMode:
              ScreenshotRecognitionHelper.importModeAppendCurrent,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('全部都是對方說的'));
      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages, hasLength(3));
      expect(
        dialogResult!.messages.every((message) => !message.isFromMe),
        isTrue,
      );
    });

    testWidgets('全部都是對方說的時隱藏兜底鍵', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: singleSpeakerConversation,
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

  group('ScreenshotRecognitionDialog 加入流程（不受改版影響）', () {
    testWidgets('returns selected import mode on confirm', (tester) async {
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

      await _tapVisible(tester, find.text('另存成新對話'));
      await tester.enterText(_partnerNameField(), 'Amber');
      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(
        dialogResult!.importMode,
        ScreenshotRecognitionHelper.importModeNewConversation,
      );
      expect(dialogResult!.name, 'Amber');
    });

    testWidgets('shows session context fields when requested', (tester) async {
      await _useTallSurface(tester);
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
      await _tapVisible(tester, find.text('確認加入對話'));

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
      await tester.enterText(find.byType(TextField).last, '她是我女友');
      await _tapVisible(tester, find.text('確認加入對話'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.analysisContextNote, '她是我女友');
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

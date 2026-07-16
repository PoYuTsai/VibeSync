import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';

void main() {
  const ocrSwipeTutorialSeenKey = 'analysis_ocr_swipe_tutorial_seen_v1_global';

  setUp(() {
    // Existing dialog tests are not tutorial tests, so keep their
    // pumpAndSettle paths fast and deterministic. Tutorial cases opt back into
    // first-run state explicitly.
    SharedPreferences.setMockInitialValues({
      ocrSwipeTutorialSeenKey: true,
    });
  });

  Widget buildDialogHost({
    required RecognizedConversation recognized,
    required bool forceShowSessionContextFields,
    bool reduceMotion = false,
    String? warningMessage,
    String initialName = '',
    MeetingContext? initialMeetingContext,
    AcquaintanceDuration? initialDuration,
    UserGoal? initialGoal,
    String initialAnalysisContextNote = '',
    Conversation? currentConversation,
    String? expectedPartnerName,
    ValueChanged<ScreenshotRecognitionDialogResult?>? onResult,
  }) {
    return MaterialApp(
      builder: (context, child) => reduceMotion
          ? MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            )
          : child!,
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
                  expectedPartnerName: expectedPartnerName,
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
    testWidgets('已有草稿時提示整批取代，且不再顯示加入方式', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.textContaining('整批取代目前內容'), findsOneWidget);
      expect(find.textContaining('不會接在原訊息下面'), findsOneWidget);
      expect(find.text('加入方式'), findsNothing);
      expect(find.text('加入本次片段'), findsNothing);
      expect(find.text('另開分析片段'), findsNothing);
      expect(find.textContaining('目前選擇：'), findsNothing);
    });

    testWidgets('空白草稿不顯示取代提示或加入方式', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          forceShowSessionContextFields: false,
          currentConversation: Conversation(
            id: 'empty-conversation',
            name: '小美',
            messages: const [],
            createdAt: DateTime(2026, 7, 16),
            updatedAt: DateTime(2026, 7, 16),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.textContaining('整批取代目前內容'), findsNothing);
      expect(find.text('加入方式'), findsNothing);
      expect(find.text('加入本次片段'), findsNothing);
      expect(find.text('另開分析片段'), findsNothing);
    });

    testWidgets('已完成分析時只能另開片段，不能再加入舊內容下方', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? result;
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          forceShowSessionContextFields: false,
          onResult: (value) => result = value,
          currentConversation: Conversation(
            id: 'completed-fragment',
            name: '小美',
            messages: [
              Message(
                id: 'old-message',
                content: '舊片段',
                isFromMe: false,
                timestamp: DateTime(2026, 7, 16),
              ),
            ],
            createdAt: DateTime(2026, 7, 16),
            updatedAt: DateTime(2026, 7, 16),
            lastAnalysisSnapshotJson: '{"done":true}',
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 45,
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('加入方式'), findsNothing);
      expect(find.text('加入本次片段'), findsNothing);
      expect(find.text('另開分析片段'), findsNothing);
      expect(
        find.textContaining('自動另存成新的分析片段'),
        findsOneWidget,
      );
      await _tapVisible(tester, find.text('確認本次內容'));

      expect(result, isNotNull);
    });

    testWidgets('辨識名稱不同時，必須明確確認同一對象才能加入', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? result;
      const mismatchedConversation = RecognizedConversation(
        contactName: 'Amber',
        messageCount: 2,
        summary: '識別到 2 則訊息',
        classification: 'valid_chat',
        importPolicy: 'allow',
        confidence: 'high',
        messages: [
          RecognizedMessage(
            side: 'left',
            isFromMe: false,
            content: '晚安',
          ),
          RecognizedMessage(
            side: 'right',
            isFromMe: true,
            content: '你也是',
          ),
        ],
      );
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mismatchedConversation,
          forceShowSessionContextFields: false,
          onResult: (value) => result = value,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(
        find.text('我確認這些截圖都是目前這位對象'),
        findsOneWidget,
      );
      expect(
        find.textContaining('如果是另一人，請取消並回到正確對象'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(
              ElevatedButton,
              '確認本次內容',
            ))
            .onPressed,
        isNull,
      );

      await _tapVisible(tester, find.text('我確認這些截圖都是目前這位對象'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(
              ElevatedButton,
              '確認本次內容',
            ))
            .onPressed,
        isNotNull,
      );
      await _tapVisible(tester, find.text('確認本次內容'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
    });

    testWidgets('對象頁名稱相符時不重複要求確認，並隱藏名字欄', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          forceShowSessionContextFields: false,
          expectedPartnerName: '小美',
          initialName: '小美',
          currentConversation: Conversation(
            id: 'partner-bound-placeholder',
            name: '新對話',
            partnerId: 'partner-xiaomei',
            messages: const [],
            createdAt: DateTime(2026, 7, 16),
            updatedAt: DateTime(2026, 7, 16),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(
        find.text('我確認這些截圖都是目前這位對象'),
        findsNothing,
      );
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(
              ElevatedButton,
              '確認本次內容',
            ))
            .onPressed,
        isNotNull,
      );
      expect(find.text('對方名字'), findsNothing);
      expect(_partnerNameField(), findsNothing);
    });

    testWidgets('OCR 名稱衝突時仍保留目前 Partner 名稱', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? result;
      const mismatchedConversation = RecognizedConversation(
        contactName: 'L',
        messageCount: 1,
        summary: '識別到 1 則訊息',
        messages: [
          RecognizedMessage(
            side: 'left',
            isFromMe: false,
            content: '晚安',
          ),
        ],
      );
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mismatchedConversation,
          forceShowSessionContextFields: false,
          expectedPartnerName: 'Bruce',
          initialName: 'Bruce',
          onResult: (value) => result = value,
          currentConversation: Conversation(
            id: 'named-empty-conversation',
            name: 'Bruce',
            partnerId: 'partner-bruce',
            messages: const [],
            createdAt: DateTime(2026, 7, 16),
            updatedAt: DateTime(2026, 7, 16),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(
        find.text('我確認這些是「Bruce」的聊天'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(
              ElevatedButton,
              '確認本次內容',
            ))
            .onPressed,
        isNull,
      );
      expect(find.text('對方名字'), findsNothing);

      await _tapVisible(tester, find.text('我確認這些是「Bruce」的聊天'));
      await _tapVisible(tester, find.text('確認本次內容'));

      expect(result, isNotNull);
      expect(result!.name, 'Bruce');
    });

    testWidgets('顯示滑動提示與警示，但不再顯示加入方式', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          warningMessage: '這張截圖辨識信心較低，加入前請先確認預覽內容是否正確。',
          forceShowSessionContextFields: true,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // 保留：滑動提示一行 + 低信心警示。
      expect(find.text('判錯邊？滑動訊息切換說話者。'), findsOneWidget);
      expect(
        find.text('右滑＝我說，左滑＝她說；點訊息可改字或刪除。'),
        findsOneWidget,
      );
      expect(find.text('加入方式'), findsNothing);
      expect(find.text('另開分析片段'), findsNothing);
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
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // 第 0 則「在幹嘛」初始她說，右滑改我說。
      await tester.drag(find.text('在幹嘛'), const Offset(400, 0));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('確認本次內容'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages[0].isFromMe, isTrue);
    });

    testWidgets('左滑超過門檻 → 該則改成她說 (isFromMe=false)', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // 第 1 則「剛回到家」初始我說，左滑改她說。
      await tester.drag(find.text('剛回到家'), const Offset(-400, 0));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('確認本次內容'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages[1].isFromMe, isFalse);
    });

    testWidgets('門檻內放開 → isFromMe 不變、彈回原側', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
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

      await _tapVisible(tester, find.text('確認本次內容'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages[0].isFromMe, isFalse);
    });

    testWidgets('點泡泡開單則編輯 sheet → 改文字後送出同步', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
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

      await _tapVisible(tester, find.text('確認本次內容'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages[0].content, '你在幹嘛呀');
    });

    testWidgets('點泡泡開 sheet → 刪除該則後該則消失', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
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

      await _tapVisible(tester, find.text('確認本次內容'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages, hasLength(2));
      expect(
        dialogResult!.messages.any((message) => message.content == '剛回到家'),
        isFalse,
      );
    });

    testWidgets('清空所有訊息後送出 → 顯示「至少保留一則」驗證且不送出', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult =
          const ScreenshotRecognitionDialogResult(
        name: 'sentinel',
        meetingContext: null,
        duration: null,
        goal: null,
        analysisContextNote: null,
        messages: [],
      );

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
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

      await _tapVisible(tester, find.text('確認本次內容'));

      expect(find.text('至少要保留一則可加入片段的訊息。'), findsOneWidget);
      // dialog 不應 pop（仍是初始 sentinel，未被覆寫）。
      expect(dialogResult, isNotNull);
      expect(dialogResult!.name, 'sentinel');
    });

    testWidgets('引用預覽唯讀顯示，且不再有引用歸屬切換', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: quotedConversation,
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
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('全部都是對方說的'));
      await _tapVisible(tester, find.text('確認本次內容'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages, hasLength(3));
      expect(
        dialogResult!.messages.every((message) => !message.isFromMe),
        isTrue,
      );
    });

    testWidgets('首次開啟進場 350ms 後依序播右滑我說、左滑她說，播完歸零', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump(); // flush SharedPreferences read after first frame

      // Dialog 先完成進場；350ms 前不可偷跑。
      await tester.pump(const Duration(milliseconds: 349));
      expect(_tutorialShiftX(tester), 0);

      // Timer 到點後先走右滑 phase。
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_tutorialShiftX(tester), greaterThan(0));
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-right-hint'),
        greaterThan(0),
      );
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-left-hint'),
        0,
      );

      // 後半段切到左滑 phase，方向與文案一起換。
      await tester.pump(const Duration(milliseconds: 900));
      expect(_tutorialShiftX(tester), lessThan(0));
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-right-hint'),
        0,
      );
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-left-hint'),
        greaterThan(0),
      );

      // 一次性：pumpAndSettle 必收斂（零無限 repeat），播完位移歸零。
      await tester.pumpAndSettle();
      expect(_tutorialShiftX(tester), 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(ocrSwipeTutorialSeenKey),
        isTrue,
      );
    });

    testWidgets('已看過不再自動播，但問號仍可重播', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(_tutorialShiftX(tester), 0);
      expect(find.byTooltip('重播滑動教學'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('ocr-swipe-tutorial-replay')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_tutorialShiftX(tester), greaterThan(0));
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-right-hint'),
        greaterThan(0),
      );
      await tester.pumpAndSettle();
      expect(_tutorialShiftX(tester), 0);
    });

    testWidgets('首次進場延遲內開始操作訊息會取消自動教學', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      // 在 SharedPreferences read／350ms timer 都可能仍在途時先真實滑動。
      await tester.drag(find.text('在幹嘛'), const Offset(40, 0));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(_tutorialShiftX(tester), 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ocrSwipeTutorialSeenKey), isNull);
    });

    testWidgets('首次進場延遲內一鍵改為對方也會取消自動教學', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump(); // flush SharedPreferences read
      final markAllButton = find.text('全部都是對方說的');
      await tester.ensureVisible(markAllButton);
      await tester.pump();
      await tester.tap(markAllButton);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(_tutorialShiftX(tester), 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ocrSwipeTutorialSeenKey), isNull);
    });

    testWidgets('reduce-motion 不自動位移，問號改顯示靜態雙向圖例', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          forceShowSessionContextFields: false,
          reduceMotion: true,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(_tutorialShiftX(tester), 0);

      await tester.tap(
        find.byKey(const ValueKey('ocr-swipe-tutorial-replay')),
      );
      await tester.pump();
      expect(_tutorialShiftX(tester), 0);
      expect(
        find.byKey(const ValueKey('ocr-swipe-tutorial-static-legend')),
        findsOneWidget,
      );
      expect(find.text('右滑 → 我說'), findsWidgets);
      expect(find.text('左滑 → 她說'), findsWidgets);

      // 沒有真的播放 motion，不消耗首次動畫旗標；日後關閉 reduce-motion
      // 還能收到一次自動教學。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ocrSwipeTutorialSeenKey), isNull);
    });

    testWidgets('350ms 延遲期間關閉 dialog 會取消 autoplay timer', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byType(ScreenshotRecognitionDialog), findsNothing);
    });

    testWidgets('沒有可示範訊息時不播放也不寫 seen flag', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: const RecognizedConversation(
            contactName: '小美',
            messageCount: 0,
            summary: '沒有訊息',
            classification: 'low_confidence',
            importPolicy: 'confirm',
            confidence: 'low',
            messages: [],
          ),
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.byKey(const ValueKey('ocr-swipe-tutorial-shift')),
        findsNothing,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ocrSwipeTutorialSeenKey), isNull);
    });

    testWidgets('全部都是對方說的時隱藏兜底鍵', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: singleSpeakerConversation,
          forceShowSessionContextFields: false,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('全部都是對方說的'), findsNothing);
    });
  });

  group('ScreenshotRecognitionDialog 確認流程', () {
    testWidgets('returns edited content without exposing import mode controls', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('加入方式'), findsNothing);
      expect(find.text('另開分析片段'), findsNothing);
      await tester.enterText(_partnerNameField(), 'Amber');
      await _tapVisible(tester, find.text('確認本次內容'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.name, 'Amber');
    });

    testWidgets('shows session context fields when requested', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
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
        messages: [],
      );

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          forceShowSessionContextFields: false,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });

    testWidgets('returns selected goal with session context', (tester) async {
      await _useTallSurface(tester);

      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
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
      await _tapVisible(tester, find.text('確認本次內容'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.goal, UserGoal.maintainHeat);
    });

    testWidgets('returns optional analysis context note', (tester) async {
      await _useTallSurface(tester);

      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
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
      await _tapVisible(tester, find.text('確認本次內容'));

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

double _tutorialShiftX(WidgetTester tester) {
  return tester
      .widget<Transform>(
        find.byKey(const ValueKey('ocr-swipe-tutorial-shift')),
      )
      .transform
      .getTranslation()
      .x;
}

double _tutorialHintOpacity(WidgetTester tester, String key) {
  return tester.widget<FadeTransition>(find.byKey(ValueKey(key))).opacity.value;
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

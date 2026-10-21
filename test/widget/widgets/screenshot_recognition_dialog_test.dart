import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/services/screenshot_recognition_helper.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/shared/widgets/analysis_preview_dialog.dart';

void main() {
  Widget buildDialogHost({
    required RecognizedConversation recognized,
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
    AnalysisQuotaLine? Function(List<RecognizedMessage> messages)?
        analyzeQuotaLineFor,
    TextScaler? textScaler,
  }) {
    return MaterialApp(
      builder: (context, child) => reduceMotion || textScaler != null
          ? MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reduceMotion ? true : null,
                textScaler: textScaler,
              ),
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
                  analyzeQuotaLineFor: analyzeQuotaLineFor,
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
      const mismatchWarning =
          '這張截圖辨識到「Amber」，和目前對象「小美」不同。若是另一人，請取消並回到正確對象；只有確認是目前這位對象時才能繼續。';
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
          warningMessage: mismatchWarning,
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
        find.text('辨識到的名字和目前對象不同，請先確認是不是同一人。'),
        findsOneWidget,
      );
      expect(find.text(mismatchWarning), findsNothing);
      expect(
        find.textContaining('如果是另一人，請取消並回到正確對象'),
        findsOneWidget,
      );
      // 2026-08-09 改版：沒勾時按鈕不再 disabled 裝死——可以按，但 _submit
      // 擋下、dialog 不關、出現指引並捲到確認格（真機回報「根本不知道要勾」）。
      await _tapVisible(tester, find.text('確認本次內容'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.textContaining('請先勾選上方的確認格'), findsOneWidget);

      await _tapVisible(tester, find.text('我確認這些截圖都是目前這位對象'));
      await tester.pumpAndSettle();
      // 勾選後指引消失。
      expect(find.textContaining('請先勾選上方的確認格'), findsNothing);

      await _tapVisible(tester, find.text('確認本次內容'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
    });

    // 2026-10-21 改版：確認格收進提醒卡，在訊息板上面，不必捲到所有訊息下面。
    testWidgets('同一人確認格跟提醒在同一張卡、排在訊息板上面', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: const RecognizedConversation(
            contactName: 'Amber',
            messageCount: 1,
            summary: '識別到 1 則訊息',
            messages: [
              RecognizedMessage(side: 'left', isFromMe: false, content: '晚安'),
            ],
          ),
          warningMessage: '這張截圖辨識到「Amber」，和目前對象「小美」不同。',
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final summary = tester.getRect(
        find.text('辨識到的名字和目前對象不同，請先確認是不是同一人。'),
      );
      final confirm = tester.getRect(find.text('我確認這些截圖都是目前這位對象'));
      final board = tester.getRect(
        find.byKey(const ValueKey('ocr-message-edit-workspace')),
      );
      expect(confirm.top, greaterThan(summary.bottom));
      expect(confirm.bottom, lessThan(board.top));
    });

    testWidgets('對象頁名稱相符時不重複要求確認，並隱藏名字欄', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
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
      // 沒勾時按鈕可按但 _submit 擋下（2026-08-09 顯眼化改版）。
      await _tapVisible(tester, find.text('確認本次內容'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.textContaining('請先勾選上方的確認格'), findsOneWidget);
      expect(find.text('對方名字'), findsNothing);

      await _tapVisible(tester, find.text('我確認這些是「Bruce」的聊天'));
      await _tapVisible(tester, find.text('確認本次內容'));

      expect(result, isNotNull);
      expect(result!.name, 'Bruce');
    });

    testWidgets('顯示滑動提示與警示，但不再顯示加入方式', (tester) async {
      await _useTallSurface(tester);
      const warning = '這張截圖辨識信心較低，加入前請先確認預覽內容是否正確。';
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          warningMessage: warning,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // 保留：滑動提示一行 + 低信心警示。左右對應改由常駐圖例講（2026-10-21）。
      expect(find.text('判錯邊？滑動訊息切換說話者。'), findsOneWidget);
      expect(find.text('點訊息可改字或刪除。'), findsOneWidget);
      expect(_directionLegend(), findsOneWidget);
      expect(find.text('加入方式'), findsNothing);
      expect(find.text('另開分析片段'), findsNothing);
      expect(find.text('這次辨識信心較低，請先快速確認內容。'), findsOneWidget);
      expect(find.text(warning), findsNothing);
      expect(find.byTooltip('查看辨識提醒詳情'), findsOneWidget);
      final infoButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('recognition-warning-info-button')),
      );
      expect(infoButton.constraints?.minWidth, 48);
      expect(infoButton.constraints?.minHeight, 48);

      await tester.tap(
        find.byKey(const ValueKey('recognition-warning-info-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text(warning), findsOneWidget);
      expect(find.byTooltip('收起辨識提醒詳情'), findsOneWidget);

      // 砍掉：狀態徽章、安撫框、舊編輯器入口。
      expect(find.text('需要確認'), findsNothing);
      expect(find.text('內容需確認'), findsNothing);
      expect(find.textContaining('方向看起來很穩'), findsNothing);
      expect(find.text('編輯內容'), findsNothing);
      expect(find.text('依左／右重新套用'), findsNothing);
    });

    testWidgets('rejected non-chat screenshot keeps an actionable summary',
        (tester) async {
      await _useTallSurface(tester);
      const warning = '這張圖看起來像相簿或選圖畫面，不是聊天視窗。';
      await tester.pumpWidget(
        buildDialogHost(
          recognized: const RecognizedConversation(
            contactName: '小美',
            messageCount: 1,
            summary: '不是聊天畫面',
            classification: 'gallery_album',
            importPolicy: 'reject',
            messages: [
              RecognizedMessage(
                side: 'left',
                isFromMe: false,
                content: '預覽內容',
              ),
            ],
          ),
          warningMessage: warning,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('這張是相簿或選圖畫面，請改傳聊天視窗。'), findsOneWidget);
      expect(find.text(warning), findsNothing);
    });

    testWidgets('uncertain speaker sides keep the required correction visible',
        (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: const RecognizedConversation(
            contactName: '小美',
            messageCount: 1,
            summary: '方向待確認',
            sideConfidence: 'low',
            uncertainSideCount: 2,
            messages: [
              RecognizedMessage(
                side: 'left',
                isFromMe: false,
                content: '在嗎',
              ),
            ],
          ),
          warningMessage: '有 2 則訊息的左右還不夠清楚，請再看一下我說或她說有沒有判對。',
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(
        find.text('有 2 則說話者方向不確定，請確認「我說／她說」。'),
        findsOneWidget,
      );
    });

    testWidgets('右滑超過門檻 → 該則改成我說 (isFromMe=true)', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(_directionLegend(), findsOneWidget);

      // 第 0 則「在幹嘛」初始她說，右滑改我說。
      await tester.drag(find.text('在幹嘛'), const Offset(400, 0));
      await tester.pumpAndSettle();

      // 左右圖例常駐（2026-10-21 改版），滑過也不收。
      expect(_directionLegend(), findsOneWidget);

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
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(_directionLegend(), findsOneWidget);

      // 第 0 則「在幹嘛」初始她說，右滑一小段（已過 touch slop 但未過切換門檻）
      // 應彈回、不切換。
      await tester.drag(find.text('在幹嘛'), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(_directionLegend(), findsOneWidget);

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
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Bruce Chiang'), findsWidgets);
      expect(find.text('引用我方'), findsNothing);
      expect(find.text('引用對方'), findsNothing);
    });

    testWidgets('有「我說」時提供一鍵「全是她說」兜底', (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('全部都是對方說的'), findsNothing);
      await _tapVisible(tester, find.text('全是她說'));
      await _tapVisible(tester, find.text('確認本次內容'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.messages, hasLength(3));
      expect(
        dialogResult!.messages.every((message) => !message.isFromMe),
        isTrue,
      );
    });

    testWidgets('每次開啟進場 650ms 後以 2.6 秒節奏循環雙向示範，動手後停下留靜態圖例',
        (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump(); // flush post-frame autoplay scheduling

      // Dialog 先完成進場；650ms 前不可偷跑，讓使用者先看清內容。
      await tester.pump(const Duration(milliseconds: 649));
      expect(_tutorialShiftX(tester), 0);

      // Timer 到點後先走右滑 phase（2.6 秒一輪的前半）。
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 700));
      expect(_tutorialShiftX(tester), greaterThan(0));
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-right-hint'),
        greaterThan(0),
      );
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-left-hint'),
        0,
      );

      // 同一輪後半（~1.95 秒處）切到左滑 phase。
      await tester.pump(const Duration(milliseconds: 1250));
      expect(_tutorialShiftX(tester), lessThan(0));
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-right-hint'),
        0,
      );
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-left-hint'),
        greaterThan(0),
      );

      // 循環：整整一輪（2.6 秒）之後回到同 phase，仍在動——不是播一次就停。
      await tester.pump(const Duration(milliseconds: 2600));
      expect(_tutorialShiftX(tester), lessThan(0));
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-left-hint'),
        greaterThan(0),
      );

      // 使用者動手（全是她說）即停，位移歸零；左右圖例常駐。
      await tester.tap(find.text('全是她說'));
      await tester.pump();
      expect(_tutorialShiftX(tester), 0);
      expect(_directionLegend(), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('教學位移時露出的那條跟真的滑一樣：右移露「改成我說」、左移露「改成她說」',
        (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump(); // flush post-frame autoplay scheduling
      await tester.pump(const Duration(milliseconds: 650));

      // 右移停住的那段：左邊讓出來的寬度＝位移，「改成我說」整段落在裡面。
      await tester.pump(const Duration(milliseconds: 600));
      final rightShift = _tutorialShiftX(tester);
      expect(rightShift, greaterThan(60), reason: '要移得夠開，露出的字才看得到');
      // Transform 只移畫面，這裡量到的是那一排原本的位置。
      final firstRow = tester.getRect(
        find.byKey(const ValueKey('ocr-swipe-tutorial-shift')),
      );
      final toMeLabel = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('ocr-swipe-tutorial-right-hint')),
          matching: find.text('改成我說'),
        ),
      );
      expect(toMeLabel.left, greaterThanOrEqualTo(firstRow.left));
      expect(toMeLabel.right, lessThanOrEqualTo(firstRow.left + rightShift));

      // 同一輪後半左移：右邊讓出來的那段露出「改成她說」。
      await tester.pump(const Duration(milliseconds: 1300));
      expect(_tutorialShiftX(tester), lessThan(-60));
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-left-hint'),
        greaterThan(0),
      );
      await tester.pumpAndSettle();
      expect(_tutorialShiftX(tester), 0);
    });

    testWidgets('關閉再開仍會自動播，問號也可手動重播', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump(const Duration(seconds: 1));
      expect(_tutorialShiftX(tester), greaterThan(0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_tutorialShiftX(tester), greaterThan(0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('重播滑動教學'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('ocr-swipe-tutorial-replay')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_tutorialShiftX(tester), greaterThan(0));
      expect(
        _tutorialHintOpacity(tester, 'ocr-swipe-tutorial-right-hint'),
        greaterThan(0),
      );
      await tester.pumpAndSettle();
      expect(_tutorialShiftX(tester), 0);
    });

    testWidgets('首次進場延遲內開始操作訊息會取消自動教學', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      // 在 650ms timer 仍在途時先真實滑動。
      await tester.drag(find.text('在幹嘛'), const Offset(40, 0));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(_tutorialShiftX(tester), 0);
      expect(_directionLegend(), findsOneWidget);
    });

    testWidgets('首次進場延遲內按「全是她說」也會取消自動教學', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump(); // flush post-frame autoplay scheduling
      final markAllButton = find.text('全是她說');
      await tester.ensureVisible(markAllButton);
      await tester.pump();
      await tester.tap(markAllButton);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(_tutorialShiftX(tester), 0);
    });

    testWidgets('reduce-motion 不自動位移，左右圖例照樣在', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          reduceMotion: true,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(_tutorialShiftX(tester), 0);
      expect(_directionLegend(), findsOneWidget);
      expect(
        find.descendant(of: _directionLegend(), matching: find.text('她說')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _directionLegend(), matching: find.text('我說')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(_directionLegend()).label,
        '左滑改成她說，右滑改成我說。',
      );
    });

    testWidgets('650ms 延遲期間關閉 dialog 會取消 autoplay timer', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.byType(ScreenshotRecognitionDialog), findsNothing);
    });

    testWidgets('沒有可示範訊息時不播放', (tester) async {
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
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.byKey(const ValueKey('ocr-swipe-tutorial-shift')),
        findsNothing,
      );
    });

    testWidgets('打開時就全是她說：不出現「全是她說」那一格', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: singleSpeakerConversation,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('全是她說'), findsNothing);
      expect(find.text('已全部改成她說'), findsNothing);
    });
  });

  // 「全是她說」移到說明正下方、按完保留位置加「復原」（Bruce 2026-10-21
  // 示意稿）：原本在所有訊息最後，使用者常常手動改完才看到。
  group('ScreenshotRecognitionDialog 全是她說與復原', () {
    final markAllHers = find.byKey(const ValueKey('ocr-mark-all-hers'));
    final markedDone = find.byKey(const ValueKey('ocr-mark-all-hers-done'));
    final undo = find.byKey(const ValueKey('ocr-mark-all-hers-undo'));

    Future<void> openMixed(
      WidgetTester tester, {
      ValueChanged<ScreenshotRecognitionDialogResult?>? onResult,
    }) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          reduceMotion: true,
          onResult: onResult,
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
    }

    testWidgets('放在「判錯邊？」說明正下方、第一則訊息上面', (tester) async {
      await openMixed(tester);

      final hint = tester.getRect(find.text('點訊息可改字或刪除。'));
      final slot = tester.getRect(markAllHers);
      final firstMessage = tester.getRect(find.text('在幹嘛'));
      expect(slot.top, greaterThan(hint.bottom));
      expect(slot.bottom, lessThan(firstMessage.top));
      expect(slot.height, 44);
    });

    testWidgets('按下後同一格改成「已全部改成她說・復原」，位置和高度不變、第一則不跳',
        (tester) async {
      await openMixed(tester);
      // 量相對位置：訊息換邊後整段變短，捲到底時整頁會一起被夾回，絕對座標
      // 會跟著動，但那一格離說明、離第一則的距離不能變。
      ({double fromHint, double height, double toFirstMessage}) measure(
        Finder slot,
      ) {
        final hint = tester.getRect(find.text('點訊息可改字或刪除。'));
        final rect = tester.getRect(slot);
        final firstMessage = tester.getRect(find.text('在幹嘛'));
        return (
          fromHint: rect.top - hint.bottom,
          height: rect.height,
          toFirstMessage: firstMessage.top - rect.bottom,
        );
      }

      final before = measure(markAllHers);
      await _tapVisible(tester, find.text('全是她說'));

      expect(find.text('全是她說'), findsNothing);
      expect(find.text('已全部改成她說'), findsOneWidget);
      expect(undo, findsOneWidget);
      expect(measure(markedDone), before);
      expect(before.height, 44);
    });

    testWidgets('按「復原」：每則回到按之前的說話者，這格變回「全是她說」', (tester) async {
      ScreenshotRecognitionDialogResult? dialogResult;
      await openMixed(tester, onResult: (result) => dialogResult = result);

      await _tapVisible(tester, find.text('全是她說'));
      await _tapVisible(tester, find.text('復原'));

      expect(find.text('全是她說'), findsOneWidget);
      expect(find.text('已全部改成她說'), findsNothing);
      await _tapVisible(tester, find.text('確認本次內容'));
      expect(
        [for (final message in dialogResult!.messages) message.isFromMe],
        [false, true, false],
      );
    });

    testWidgets('按完又手動把某則滑成「我說」：復原作廢，這格變回「全是她說」', (tester) async {
      ScreenshotRecognitionDialogResult? dialogResult;
      await openMixed(tester, onResult: (result) => dialogResult = result);

      await _tapVisible(tester, find.text('全是她說'));
      await tester.drag(find.text('這麼晚還沒睡'), const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(undo, findsNothing);
      expect(find.text('全是她說'), findsOneWidget);
      await _tapVisible(tester, find.text('確認本次內容'));
      expect(
        [for (final message in dialogResult!.messages) message.isFromMe],
        [false, false, true],
      );
    });

    testWidgets('按完往同一邊再滑（還是她說）：沒換邊，復原照樣在', (tester) async {
      await openMixed(tester);

      await _tapVisible(tester, find.text('全是她說'));
      await tester.drag(find.text('在幹嘛'), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(undo, findsOneWidget);
    });

    testWidgets('沒按按鈕、自己滑到全是她說：顯示「已全部改成她說」但沒有「復原」', (tester) async {
      await openMixed(tester);

      // 唯一一則「我說」是「剛回到家」，左滑改她說。
      await tester.drag(find.text('剛回到家'), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('已全部改成她說'), findsOneWidget);
      expect(undo, findsNothing);
    });

    testWidgets('打開時全是她說、之後滑出「我說」：這格照樣不出現，訊息不往下跳', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: singleSpeakerConversation,
          reduceMotion: true,
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      final firstMessageTop = tester.getRect(find.text('在幹嘛')).top;

      await tester.drag(find.text('這麼晚還沒睡'), const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(find.text('全是她說'), findsNothing);
      expect(find.text('已全部改成她說'), findsNothing);
      expect(tester.getRect(find.text('在幹嘛')).top, firstMessageTop);
    });

    // PR #110 審查 P3：那一格原本固定 44 高，320 寬、1.4 倍字時「已全部改成她說」
    // 排成兩行，第二行被裁掉。改成最少 44，字排兩行時那一格跟著長高。
    testWidgets('320 寬、1.4 倍字：按完那一格跟著字長高、不裁字，「復原」照樣按得到', (tester) async {
      _usePhone(tester, const Size(320, 568));
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          reduceMotion: true,
          textScaler: const TextScaler.linear(1.4),
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('全是她說'));

      final status =
          find.descendant(of: markedDone, matching: find.text('已全部改成她說'));
      final paragraph = _paragraphOf(tester, status);
      final slot = tester.getRect(markedDone);
      final undoButton = tester.getRect(undo);
      // 四件一起比，紅的時候都看得到。排成兩行是這個情境的前提。
      expect(
        (
          wraps: _lineCount(tester, status) > 1,
          textClipped: paragraph.textSize.height > paragraph.size.height,
          slotFitsText: slot.height >= paragraph.textSize.height,
          undoTarget44: undoButton.width >= 44 && undoButton.height >= 44,
        ),
        (
          wraps: true,
          textClipped: false,
          slotFitsText: true,
          undoTarget44: true
        ),
      );

      await _tapVisible(tester, find.text('復原'));
      expect(find.text('全是她說'), findsOneWidget);
      expect(find.text('已全部改成她說'), findsNothing);
    });

    testWidgets('390 寬、1.0 倍字：按之前、按之後那一格都是 44 高，換狀態不跳', (tester) async {
      _usePhone(tester, const Size(390, 844));
      await tester.pumpWidget(
        buildDialogHost(recognized: mixedConversation, reduceMotion: true),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      final beforeTap = tester.getRect(markAllHers).height;

      await _tapVisible(tester, find.text('全是她說'));

      expect(
        (beforeTap: beforeTap, afterTap: tester.getRect(markedDone).height),
        (beforeTap: 44.0, afterTap: 44.0),
      );
    });
  });

  group('ScreenshotRecognitionDialog 確認流程', () {
    testWidgets('returns edited content without exposing import mode controls',
        (tester) async {
      await _useTallSurface(tester);
      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
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

    testWidgets('keeps session context fields out of OCR confirmation',
        (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('認識場景（選填）'), findsNothing);
      expect(find.text('認識多久（選填）'), findsNothing);
      expect(find.text('目前目標'), findsNothing);
      expect(find.text('補充背景（選填）'), findsNothing);
      expect(find.text('沒有可以留空'), findsNothing);
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
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });

    testWidgets('returns inherited goal without showing duplicate controls',
        (tester) async {
      await _useTallSurface(tester);

      ScreenshotRecognitionDialogResult? dialogResult;

      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          initialMeetingContext: MeetingContext.datingApp,
          initialDuration: AcquaintanceDuration.justMet,
          initialGoal: UserGoal.maintainHeat,
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('目前目標'), findsNothing);
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
          initialMeetingContext: MeetingContext.committedPartner,
          initialDuration: AcquaintanceDuration.monthPlus,
          initialGoal: UserGoal.justChat,
          initialAnalysisContextNote: '她是我女友',
          onResult: (result) => dialogResult = result,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('補充背景（選填）'), findsNothing);
      expect(find.text('沒有可以留空'), findsNothing);
      await _tapVisible(tester, find.text('確認本次內容'));

      expect(dialogResult, isNotNull);
      expect(dialogResult!.analysisContextNote, '她是我女友');
    });
  });

  // 一鍵加入並開始分析（Eric 2026-10-18）：這次會用幾則由畫面算好傳進來，
  // 確認框只負責照目前要匯入的訊息問、把看到的那一行原樣帶回去。
  group('ScreenshotRecognitionDialog 加入並開始分析', () {
    AnalysisQuotaLine? freeLineFor(List<RecognizedMessage> messages) =>
        AnalysisQuotaLine.of(
          MessageCalculator.previewAnalysisRequest([
            for (final (index, message) in messages.indexed)
              Message(
                id: 'line-$index',
                content: message.content,
                isFromMe: message.isFromMe,
                timestamp: DateTime(2026, 10, 18, 9, index),
              ),
          ]),
          monthlyRemaining: AppConstants.freeMonthlyLimit,
          dailyRemaining: AppConstants.freeDailyLimit,
        );

    final analyzeButton =
        find.byKey(ScreenshotRecognitionDialog.analyzeButtonKey);
    final quotaLine = find.byKey(ScreenshotRecognitionDialog.quotaLineKey);

    testWidgets('沒給算法：只有今天的「確認本次內容」', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(recognized: mixedConversation),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(_actionBarLabels(tester), unorderedEquals(['取消', '確認本次內容']));
      expect(analyzeButton, findsNothing);
      expect(quotaLine, findsNothing);
    });

    // Bruce 真機試過說用不到，Eric 2026-10-19「照 Bruce 拿掉」：沒有只匯入不分析的鈕，
    // 不想現在分析就按「取消」，辨識結果留在分析頁（續看卡）。
    testWidgets('有給算法：底下只剩「取消」和「加入並開始分析」，沒有「先存起來」', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          analyzeQuotaLineFor: freeLineFor,
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(
        _actionBarLabels(tester),
        unorderedEquals(['取消', '加入並開始分析']),
      );
      expect(find.text('先存起來，晚點再分析'), findsNothing);
    });

    testWidgets('有給算法：不論按哪一顆送出，都是匯入並開始分析、帶回看到的那一行', (tester) async {
      await _useTallSurface(tester);
      final results = <ScreenshotRecognitionDialogResult?>[];
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          onResult: results.add,
          analyzeQuotaLineFor: freeLineFor,
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      final submitLabels = [
        for (final label in _actionBarLabels(tester))
          if (label != '取消') label,
      ];
      expect(submitLabels, isNotEmpty);

      for (final label in submitLabels) {
        if (find.byType(ScreenshotRecognitionDialog).evaluate().isEmpty) {
          await tester.tap(find.text('Open Dialog'));
          await tester.pumpAndSettle();
        }
        await _tapVisible(
          tester,
          find.descendant(of: _actionBar(), matching: find.text(label)),
        );
      }

      final expected = freeLineFor(mixedConversation.messages!)!;
      expect(results, hasLength(submitLabels.length));
      for (final result in results) {
        expect(result!.startAnalysis, isTrue);
        expect(result.shownQuotaLine, expected);
        expect(result.messages, hasLength(3));
      }
    });

    testWidgets('有給算法：按「取消」帶回 null、確認框關掉', (tester) async {
      await _useTallSurface(tester);
      final results = <ScreenshotRecognitionDialogResult?>[];
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          onResult: results.add,
          analyzeQuotaLineFor: freeLineFor,
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await _tapVisible(
        tester,
        find.descendant(of: _actionBar(), matching: find.text('取消')),
      );

      expect(results, [isNull]);
      expect(find.byType(ScreenshotRecognitionDialog), findsNothing);
    });

    testWidgets('有給算法：寫出那一行；主鈕帶回要分析與看到的那一行', (tester) async {
      await _useTallSurface(tester);
      List<RecognizedMessage>? asked;
      final results = <ScreenshotRecognitionDialogResult?>[];
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          onResult: results.add,
          analyzeQuotaLineFor: (messages) {
            asked = messages;
            return freeLineFor(messages);
          },
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final expected = freeLineFor(mixedConversation.messages!)!;
      expect(
        [for (final message in asked!) message.content],
        [for (final message in mixedConversation.messages!) message.content],
      );
      expect(tester.widget<Text>(quotaLine).data, expected.text);
      expect(find.text('加入並開始分析'), findsOneWidget);
      expect(find.text('確認本次內容'), findsNothing);

      await _tapVisible(tester, analyzeButton);

      expect(results, hasLength(1));
      expect(results.single!.startAnalysis, isTrue);
      expect(results.single!.shownQuotaLine, expected);
      expect(results.single!.messages, hasLength(3));
    });

    testWidgets('算不出那一行（超過一般長度、額度不夠）：不寫，主鈕照樣能按、帶回 null', (tester) async {
      await _useTallSurface(tester);
      final results = <ScreenshotRecognitionDialogResult?>[];
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          onResult: results.add,
          analyzeQuotaLineFor: (_) => null,
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(quotaLine, findsNothing);
      await _tapVisible(tester, analyzeButton);

      expect(results, hasLength(1));
      expect(results.single!.startAnalysis, isTrue);
      expect(results.single!.shownQuotaLine, isNull);
    });

    testWidgets('連點主鈕：只關一次、只帶回一次，底下的頁面還在', (tester) async {
      await _useTallSurface(tester);
      final results = <ScreenshotRecognitionDialogResult?>[];
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          onResult: results.add,
          analyzeQuotaLineFor: freeLineFor,
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(analyzeButton);
      await tester.tap(analyzeButton);
      await tester.tap(analyzeButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(results, hasLength(1));
      expect(find.text('Open Dialog'), findsOneWidget);
    });

    testWidgets('同對象確認還沒勾：主鈕一樣擋下、不關', (tester) async {
      await _useTallSurface(tester);
      final results = <ScreenshotRecognitionDialogResult?>[];
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognizedConversation,
          onResult: results.add,
          analyzeQuotaLineFor: freeLineFor,
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
      expect(find.text('我確認這些截圖都是目前這位對象'), findsOneWidget);

      await _tapVisible(tester, analyzeButton);

      expect(results, isEmpty);
      expect(find.byType(ScreenshotRecognitionDialog), findsOneWidget);
      expect(find.textContaining('請先勾選上方的確認格'), findsOneWidget);
    });

    // 主審 r1 P3：App 字級上限 1.4（app.dart），320 寬的小手機上同一排放不下，主鈕的字
    // 變成「加入並開始分／析」、那一行剩「則」單獨一行。放不下就改上下排。
    testWidgets('320 寬、1.4 倍字：那一行和主鈕的字都只排一行，「取消」改到主鈕下面、一樣寬', (tester) async {
      _usePhone(tester, const Size(320, 568));
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          reduceMotion: true,
          analyzeQuotaLineFor: freeLineFor,
          textScaler: const TextScaler.linear(1.4),
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final analyzeLabel = find.descendant(
        of: analyzeButton,
        matching: find.text('加入並開始分析'),
      );
      final cancel = tester.getRect(_cancelButton());
      final analyze = tester.getRect(analyzeButton);
      // 三件一起比，紅的時候三件都看得到。
      expect(
        (
          quotaLines: _lineCount(tester, quotaLine),
          labelLines: _lineCount(tester, analyzeLabel),
          cancelBelow: cancel.top >= analyze.bottom,
        ),
        (quotaLines: 1, labelLines: 1, cancelBelow: true),
      );
      expect(tester.getRect(quotaLine).bottom, lessThanOrEqualTo(analyze.top));
      expect(cancel.width, analyze.width, reason: '「取消」跟主鈕一樣整排寬');
    });

    testWidgets('390 寬、1.0 倍字：「取消」和主鈕照舊同一排，那一行在主鈕上面', (tester) async {
      _usePhone(tester, const Size(390, 844));
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          reduceMotion: true,
          analyzeQuotaLineFor: freeLineFor,
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final cancel = tester.getRect(_cancelButton());
      final analyze = tester.getRect(analyzeButton);
      expect(cancel.right, lessThanOrEqualTo(analyze.left), reason: '「取消」在左');
      expect(cancel.bottom, moreOrLessEquals(analyze.bottom),
          reason: '同一排、底對齊');
      expect(tester.getRect(quotaLine).bottom, lessThanOrEqualTo(analyze.top));
      expect(_lineCount(tester, quotaLine), 1);
    });

    // 放得下就維持同一排：一點一點加寬，兩種排法都不斷行；第一個排成同一排的寬度，那一行
    // 或主鈕的字剛好塞滿（少 1 點就會斷行），不會提早改上下排。
    for (final (name, lineFor) in [
      ('有那一行', freeLineFor),
      ('沒有那一行', (List<RecognizedMessage> _) => null),
    ]) {
      testWidgets('1.4 倍字從 320 寬加到 440 寬（$name）：都不斷行，剛好放得下才回到同一排',
          (tester) async {
        _usePhone(tester, const Size(320, 568));
        await tester.pumpWidget(
          buildDialogHost(
            recognized: mixedConversation,
            reduceMotion: true,
            analyzeQuotaLineFor: lineFor,
            textScaler: const TextScaler.linear(1.4),
          ),
        );
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        final texts = [
          if (quotaLine.evaluate().isNotEmpty) quotaLine,
          find.descendant(of: analyzeButton, matching: find.text('加入並開始分析')),
        ];
        double? firstRowWidth;
        for (var width = 320.0; width <= 440; width++) {
          tester.view.physicalSize =
              Size(width, 568) * tester.view.devicePixelRatio;
          await tester.pump();
          for (final text in texts) {
            expect(_lineCount(tester, text), 1, reason: '寬 $width');
          }
          final inRow = tester.getRect(_cancelButton()).right <=
              tester.getRect(analyzeButton).left;
          if (firstRowWidth != null) {
            expect(inRow, isTrue, reason: '寬 $width 比 $firstRowWidth 寬，維持同一排');
          } else if (inRow) {
            firstRowWidth = width;
            final slack =
                texts.map((text) => _slack(tester, text)).reduce(math.min);
            expect(slack, lessThan(1), reason: '寬 $width 才剛好放得下');
          }
        }
        expect(firstRowWidth, isNotNull);
      });
    }

    testWidgets('沒給算法（確認本次內容）：320 寬、1.4 倍字也排得下一行，照舊同一排', (tester) async {
      _usePhone(tester, const Size(320, 568));
      await tester.pumpWidget(
        buildDialogHost(
          recognized: mixedConversation,
          reduceMotion: true,
          textScaler: const TextScaler.linear(1.4),
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final confirm = find.widgetWithText(ElevatedButton, '確認本次內容');
      expect(
        _lineCount(
          tester,
          find.descendant(of: confirm, matching: find.text('確認本次內容')),
        ),
        1,
      );
      expect(
        tester.getRect(_cancelButton()).right,
        lessThanOrEqualTo(tester.getRect(confirm).left),
      );
    });
  });

  // PR #110 審查 P2：確認格收進提醒卡後，沒勾就送出原本捲到整張卡；詳情展開後卡片
  // 比視口高（320 寬、1.4 倍字），對齊整張卡會把卡底的確認格推出畫面。改成捲確認格
  // 那一列，放得下就連卡片下面的紅字一起帶進視口。
  group('ScreenshotRecognitionDialog 沒勾確認格就送出：捲到確認格', () {
    const partnerName = '思妤';
    const confirmLabel = '我確認這些是「$partnerName」的聊天';
    // 跟改版實拍（ocr_confirm_redesign_proof_test.dart）同一組範例對話：名字不同、
    // 兩邊都有人說話、帶引用。
    const recognized = RecognizedConversation(
      contactName: 'Sylvia',
      messageCount: 10,
      summary: '識別到 10 則訊息',
      classification: 'valid_chat',
      importPolicy: 'allow',
      confidence: 'high',
      sideConfidence: 'high',
      messages: [
        RecognizedMessage(side: 'left', isFromMe: false, content: '北鼻～北鼻～我下課了'),
        RecognizedMessage(side: 'left', isFromMe: false, content: '剛上捷運'),
        RecognizedMessage(
          side: 'right',
          isFromMe: true,
          content: '[貼圖：咬你喔]',
          quotedReplyPreview: '只對你一個人浪漫',
          quotedReplyPreviewIsFromMe: false,
        ),
        RecognizedMessage(
          side: 'right',
          isFromMe: true,
          content: '我專屬的',
          quotedReplyPreview: '只對你一個人浪漫',
          quotedReplyPreviewIsFromMe: false,
        ),
        RecognizedMessage(
          side: 'right',
          isFromMe: true,
          content: '已經幫你買好了',
          quotedReplyPreview: '北鼻最懂我 起司口味捲餅',
          quotedReplyPreviewIsFromMe: false,
        ),
        RecognizedMessage(side: 'left', isFromMe: false, content: '你怎麼知道我想吃這個'),
        RecognizedMessage(side: 'left', isFromMe: false, content: '好感動喔'),
        RecognizedMessage(side: 'right', isFromMe: true, content: '因為我有在聽你說話啊'),
        RecognizedMessage(side: 'left', isFromMe: false, content: '再三站就到了'),
        RecognizedMessage(side: 'right', isFromMe: true, content: '我在出口等你'),
      ],
    );
    final conversation = Conversation(
      id: 'conversation-siyu',
      name: partnerName,
      partnerId: 'partner-siyu',
      messages: [
        Message(
          id: 'existing-1',
          content: '早安',
          isFromMe: false,
          timestamp: DateTime(2026, 10, 21, 8),
        ),
      ],
      createdAt: DateTime(2026, 10, 21),
      updatedAt: DateTime(2026, 10, 21),
    );
    // 跟分析頁同一套組字：名字不同和引用提醒兩段都在，展開詳情時卡片才會這麼長。
    final warning = ScreenshotRecognitionHelper.buildWarning(
      recognized: recognized,
      currentConversation: conversation,
      expectedPartnerName: partnerName,
    );

    AnalysisQuotaLine? lineFor(List<RecognizedMessage> messages) =>
        AnalysisQuotaLine.of(
          MessageCalculator.previewAnalysisRequest([
            for (final (index, message) in messages.indexed)
              Message(
                id: 'reveal-$index',
                content: message.content,
                isFromMe: message.isFromMe,
                timestamp: DateTime(2026, 10, 21, 9, index),
              ),
          ]),
          monthlyRemaining: AppConstants.freeMonthlyLimit,
          dailyRemaining: AppConstants.freeDailyLimit,
        );

    /// 開框（可先展開詳情）→ 捲到最底（看完訊息才按）→ 沒勾就按「加入並開始分析」。
    /// 回傳捲動區視口、確認格那一列（圈＋說明）、紅字、整張提醒卡的位置。
    Future<({Rect viewport, Rect checkboxRow, Rect guidance, Rect card})>
        submitUnticked(
      WidgetTester tester, {
      required Size size,
      TextScaler? textScaler,
      bool expandDetails = false,
    }) async {
      _usePhone(tester, size);
      await tester.pumpWidget(
        buildDialogHost(
          recognized: recognized,
          reduceMotion: true,
          warningMessage: warning,
          currentConversation: conversation,
          expectedPartnerName: partnerName,
          analyzeQuotaLineFor: lineFor,
          textScaler: textScaler,
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final info =
          find.byKey(const ValueKey('recognition-warning-info-button'));
      if (expandDetails) {
        await tester.tap(info);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('recognition-warning-details')),
          findsOneWidget,
        );
      }
      final label = find.text(confirmLabel);
      final scrollable =
          find.ancestor(of: label, matching: find.byType(Scrollable));
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(ScreenshotRecognitionDialog.analyzeButtonKey));
      await tester.pumpAndSettle();
      expect(find.byType(ScreenshotRecognitionDialog), findsOneWidget,
          reason: '沒勾不送出');
      return (
        viewport: tester.getRect(scrollable),
        checkboxRow: tester.getRect(
          find.ancestor(of: label, matching: find.byType(InkWell)),
        ),
        guidance: tester.getRect(find.textContaining('請先勾選上方的確認格')),
        // 資訊鈕往上最近的 Container 就是整張提醒卡。
        card: tester.getRect(
          find.ancestor(of: info, matching: find.byType(Container)).first,
        ),
      );
    }

    testWidgets('320 寬、1.4 倍字、詳情展開：確認格整列和紅字都捲進視口', (tester) async {
      final shown = await submitUnticked(
        tester,
        size: const Size(320, 568),
        textScaler: const TextScaler.linear(1.4),
        expandDetails: true,
      );
      // 前提：整張卡比視口高（對齊整張卡就會把確認格推出去），而確認格到紅字這一段
      // 放得下，所以兩樣都要看得到。
      expect(shown.card.height, greaterThan(shown.viewport.height));
      expect(
        shown.guidance.bottom - shown.checkboxRow.top,
        lessThanOrEqualTo(shown.viewport.height),
      );
      expect(
        (
          checkboxRow: _fullyInside(shown.checkboxRow, shown.viewport),
          guidance: _fullyInside(shown.guidance, shown.viewport),
        ),
        (checkboxRow: true, guidance: true),
      );
    });

    testWidgets('375×667、1.4 倍字、詳情展開：確認格整列和紅字都捲進視口', (tester) async {
      final shown = await submitUnticked(
        tester,
        size: const Size(375, 667),
        textScaler: const TextScaler.linear(1.4),
        expandDetails: true,
      );
      expect(
        (
          checkboxRow: _fullyInside(shown.checkboxRow, shown.viewport),
          guidance: _fullyInside(shown.guidance, shown.viewport),
        ),
        (checkboxRow: true, guidance: true),
      );
    });

    testWidgets('390×844、1.0 倍字：整張卡連紅字都放得下，三樣都在視口裡、卡頂不捲出去', (tester) async {
      final shown = await submitUnticked(tester, size: const Size(390, 844));
      expect(
        shown.guidance.bottom - shown.card.top,
        lessThan(shown.viewport.height),
      );
      expect(
        (
          card: _fullyInside(shown.card, shown.viewport),
          checkboxRow: _fullyInside(shown.checkboxRow, shown.viewport),
          guidance: _fullyInside(shown.guidance, shown.viewport),
        ),
        (card: true, checkboxRow: true, guidance: true),
      );
    });
  });
}

/// [inner] 上下都在 [outer] 裡（捲動區只看縱向）。
bool _fullyInside(Rect inner, Rect outer) =>
    inner.top >= outer.top - 0.5 && inner.bottom <= outer.bottom + 0.5;

/// 確認框底部固定的動作列：整個確認框只有這一處是 SafeArea。
Finder _actionBar() => find.descendant(
      of: find.byType(ScreenshotRecognitionDialog),
      matching: find.byType(SafeArea),
    );

/// 動作列上的「取消」。
Finder _cancelButton() => find.descendant(
      of: _actionBar(),
      matching: find.widgetWithText(TextButton, '取消'),
    );

/// 畫出這段字的那個 RenderParagraph。
RenderParagraph _paragraphOf(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: text,
        matching: find.byType(RichText),
        matchRoot: true,
      ),
    );

/// 這段字離斷行還差幾點：排它的寬度減掉排成一行要的寬度。
double _slack(WidgetTester tester, Finder text) {
  final paragraph = _paragraphOf(tester, text);
  return paragraph.constraints.maxWidth -
      paragraph.getMaxIntrinsicWidth(double.infinity);
}

/// 這段字實際排成幾行：問畫出來的那個 RenderParagraph，每一行的框頂端各是一個高度。
int _lineCount(WidgetTester tester, Finder text) {
  final paragraph = _paragraphOf(tester, text);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
    boxHeightStyle: ui.BoxHeightStyle.max,
  );
  return {for (final box in boxes) box.top}.length;
}

/// 手機尺寸：版面寬度和 MediaQuery 都照這個（setSurfaceSize 只改版面）。
void _usePhone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

/// 動作列上每一顆按鈕的字。
List<String> _actionBarLabels(WidgetTester tester) {
  expect(_actionBar(), findsOneWidget, reason: '確認框只有底部動作列是 SafeArea');
  final buttons = find.descendant(
    of: _actionBar(),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );
  return [
    for (final button in buttons.evaluate())
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byElementPredicate((element) => element == button),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .join(),
  ];
}

Finder _partnerNameField() {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == '輸入對方名字',
    description: 'partner name TextField',
  );
}

/// 對話板上常駐的左右圖例（← 她說／我說 →）。
Finder _directionLegend() =>
    find.byKey(const ValueKey('ocr-swipe-direction-legend'));

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

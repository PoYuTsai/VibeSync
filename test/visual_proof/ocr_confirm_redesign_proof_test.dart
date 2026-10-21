// 截圖確認框改版（Bruce 2026-10-21 示意稿）的改前改後實拍。
//
// 跟 anti_ai_ui2 同一套契約：沒給 OCR_CONFIRM_PROOF_STAGE 就跳過；給 before／
// after 就把畫面拍到 build/visual_proof/ocr_confirm_redesign/<stage>/。情境照
// 2026-10-21 真機截圖那一張（名字不同、要確認同一人、兩邊都有人說話、帶引用），內容
// 換成範例對話。「全是她說」按下後與滑動教學只有改版後才有，只在 after 拍。
//
//   flutter test --dart-define=OCR_CONFIRM_PROOF_STAGE=after \
//     test/visual_proof/ocr_confirm_redesign_proof_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/shared/widgets/analysis_preview_dialog.dart';

import 'proof_support.dart';

const _stage = String.fromEnvironment('OCR_CONFIRM_PROOF_STAGE');

String _stagePath(String name) => outPath('ocr_confirm_redesign/$_stage/$name');

const _recognized = RecognizedConversation(
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

final _conversation = Conversation(
  id: 'proof-ocr-confirm',
  name: '思妤',
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

AnalysisQuotaLine? _quotaLineFor(List<RecognizedMessage> messages) =>
    AnalysisQuotaLine.of(
      MessageCalculator.previewAnalysisRequest([
        for (final (index, message) in messages.indexed)
          Message(
            id: 'proof-$index',
            content: message.content,
            isFromMe: message.isFromMe,
            timestamp: DateTime(2026, 10, 21, 9, index),
          ),
      ]),
      monthlyRemaining: AppConstants.freeMonthlyLimit,
      dailyRemaining: AppConstants.freeDailyLimit,
    );

/// 開出確認框（走真的 showDialog），回傳整張手機畫面的 RepaintBoundary key。
Future<GlobalKey> _openConfirmSheet(
  WidgetTester tester, {
  required bool reduceMotion,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = kPhone * 3;
  addTearDown(tester.view.reset);
  final rootKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: rootKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          child: Scaffold(
            backgroundColor: const Color(0xFF120B1F),
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ScreenshotRecognitionDialog(
                      recognized: _recognized,
                      warningMessage:
                          '這張截圖辨識到「Sylvia」，和目前對象「思妤」不同。若是另一人，請取消並回到正確對象；只有確認是目前這位對象時才能繼續。',
                      initialName: '思妤',
                      initialMeetingContext: null,
                      initialDuration: null,
                      initialGoal: null,
                      initialAnalysisContextNote: '',
                      currentConversation: _conversation,
                      expectedPartnerName: '思妤',
                      analyzeQuotaLineFor: _quotaLineFor,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  return rootKey;
}

Future<void> _capture(WidgetTester tester, GlobalKey rootKey, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    (File(_stagePath(name))..createSync(recursive: true))
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  if (_stage.isEmpty) {
    test('ocr confirm redesign proof（需 --dart-define=OCR_CONFIRM_PROOF_STAGE）', () {
      markTestSkipped('未指定 OCR_CONFIRM_PROOF_STAGE，跳過產圖');
    });
    return;
  }
  setUpAll(loadProofFonts);

  testWidgets('打開時（頂端）', (tester) async {
    final rootKey = await _openConfirmSheet(tester, reduceMotion: true);
    await tester.pumpAndSettle();
    await _capture(tester, rootKey, 'open_top.png');
  });

  testWidgets('捲到底', (tester) async {
    final rootKey = await _openConfirmSheet(tester, reduceMotion: true);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    await _capture(tester, rootKey, 'scrolled_bottom.png');
  });

  if (_stage != 'after') return;

  testWidgets('按下「全是她說」之後', (tester) async {
    final rootKey = await _openConfirmSheet(tester, reduceMotion: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全是她說'));
    await tester.pumpAndSettle();
    await _capture(tester, rootKey, 'all_hers_done.png');
  });

  testWidgets('勾了同一人、滑動教學右移那一刻', (tester) async {
    final rootKey = await _openConfirmSheet(tester, reduceMotion: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('我確認這些是「思妤」的聊天'));
    // 勾選不算動手（教學照播）：等進場延遲過後，停在右移最遠那段。
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 560));
    await _capture(tester, rootKey, 'tutorial_reveal.png');
    await tester.pumpAndSettle();
  });
}

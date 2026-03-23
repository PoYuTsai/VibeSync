import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/services/screenshot_recognition_helper.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

void main() {
  Conversation buildConversation({
    required String name,
    List<Message>? messages,
  }) {
    return Conversation(
      id: 'conversation-1',
      name: name,
      messages: messages ?? <Message>[],
      createdAt: DateTime(2026, 3, 17),
      updatedAt: DateTime(2026, 3, 17),
    );
  }

  Message buildMessage({required bool isFromMe, required String content}) {
    return Message(
      id: '${isFromMe ? "me" : "her"}-$content',
      content: content,
      isFromMe: isFromMe,
      timestamp: DateTime(2026, 3, 17),
    );
  }

  group('ScreenshotRecognitionHelper.defaultImportMode', () {
    test('uses current thread for empty conversation', () {
      final recognized = const RecognizedConversation(
        contactName: '小美',
        messageCount: 3,
        summary: '識別到 3 則訊息',
      );
      final conversation = buildConversation(name: '新對話');

      final result = ScreenshotRecognitionHelper.defaultImportMode(
        recognized: recognized,
        currentConversation: conversation,
      );

      expect(
        result,
        ScreenshotRecognitionHelper.importModeAppendCurrent,
      );
    });

    test('uses new conversation for low-confidence import', () {
      final recognized = const RecognizedConversation(
        contactName: '小美',
        messageCount: 3,
        summary: '識別到 3 則訊息',
        importPolicy: 'confirm',
        confidence: 'low',
      );
      final conversation = buildConversation(
        name: '小美',
        messages: [buildMessage(isFromMe: false, content: '嗨')],
      );

      final result = ScreenshotRecognitionHelper.defaultImportMode(
        recognized: recognized,
        currentConversation: conversation,
      );

      expect(
        result,
        ScreenshotRecognitionHelper.importModeNewConversation,
      );
    });

    test('uses new conversation when recognized name mismatches thread name',
        () {
      final recognized = const RecognizedConversation(
        contactName: 'Amber',
        messageCount: 2,
        summary: '識別到 2 則訊息',
      );
      final conversation = buildConversation(
        name: '小美',
        messages: [buildMessage(isFromMe: false, content: '晚安')],
      );

      final result = ScreenshotRecognitionHelper.defaultImportMode(
        recognized: recognized,
        currentConversation: conversation,
      );

      expect(
        result,
        ScreenshotRecognitionHelper.importModeNewConversation,
      );
    });
  });

  group('ScreenshotRecognitionHelper.isPlaceholderConversationName', () {
    test('treats both 新對話 and 新的對話 as placeholder titles', () {
      expect(
        ScreenshotRecognitionHelper.isPlaceholderConversationName('新對話'),
        isTrue,
      );
      expect(
        ScreenshotRecognitionHelper.isPlaceholderConversationName('新的對話'),
        isTrue,
      );
      expect(
        ScreenshotRecognitionHelper.isPlaceholderConversationName('Amy'),
        isFalse,
      );
    });
  });

  group('ScreenshotRecognitionHelper.buildWarning', () {
    test('includes mismatch warning when recognized name differs', () {
      final recognized = const RecognizedConversation(
        contactName: 'Amber',
        messageCount: 2,
        summary: '識別到 2 則訊息',
      );
      final conversation = buildConversation(
        name: '小美',
        messages: [buildMessage(isFromMe: false, content: '晚安')],
      );

      final result = ScreenshotRecognitionHelper.buildWarning(
        recognized: recognized,
        currentConversation: conversation,
      );

      expect(result, isNotNull);
      expect(result, contains('Amber'));
      expect(result, contains('名稱不同'));
    });

    test('falls back to confidence warning for confirm imports', () {
      final recognized = const RecognizedConversation(
        messageCount: 2,
        summary: '識別到 2 則訊息',
        importPolicy: 'confirm',
      );
      final conversation = buildConversation(name: '新對話');

      final result = ScreenshotRecognitionHelper.buildWarning(
        recognized: recognized,
        currentConversation: conversation,
      );

      expect(result, '這張截圖辨識信心較低，匯入前請先確認預覽內容是否正確。');
    });
  });

  group('ScreenshotRecognitionHelper.resolveImportedConversationName', () {
    test('prefers entered name over recognized name', () {
      final result =
          ScreenshotRecognitionHelper.resolveImportedConversationName(
        enteredName: '  新名字  ',
        recognizedName: '小美',
      );

      expect(result, '新名字');
    });

    test('falls back to recognized name then 新對話', () {
      expect(
        ScreenshotRecognitionHelper.resolveImportedConversationName(
          enteredName: '   ',
          recognizedName: 'Amber',
        ),
        'Amber',
      );

      expect(
        ScreenshotRecognitionHelper.resolveImportedConversationName(
          enteredName: null,
          recognizedName: '   ',
        ),
        '新對話',
      );
    });
  });

  group('ScreenshotRecognitionHelper.copyAndGuidance', () {
    test('returns localized labels', () {
      expect(
        ScreenshotRecognitionHelper.classificationLabel('social_feed'),
        '社群內容',
      );
      expect(
        ScreenshotRecognitionHelper.classificationLabel('group_chat'),
        '群組聊天',
      );
      expect(
        ScreenshotRecognitionHelper.classificationLabel('gallery_album'),
        '相簿畫面',
      );
      expect(
        ScreenshotRecognitionHelper.confidenceLabel('medium'),
        '信心中等',
      );
    });

    test('returns social feed guidance for rejected non-chat images', () {
      const recognized = RecognizedConversation(
        messageCount: 0,
        summary: '像是社群貼文',
        classification: 'social_feed',
        importPolicy: 'reject',
      );

      final result = ScreenshotRecognitionHelper.actionGuidance(recognized);
      final guidance = ScreenshotRecognitionHelper.guidance(recognized);

      expect(result, contains('社群貼文'));
      expect(result, contains('雙人聊天畫面'));
      expect(guidance.title, '建議改傳雙人聊天截圖');
      expect(guidance.tone, ScreenshotRecognitionGuidanceTone.reject);
    });

    test(
        'returns low-confidence guidance for quoted reply or blurry screenshots',
        () {
      const recognized = RecognizedConversation(
        messageCount: 6,
        summary: '識別到 6 則訊息',
        classification: 'low_confidence',
        importPolicy: 'confirm',
        confidence: 'low',
      );

      final result = ScreenshotRecognitionHelper.actionGuidance(recognized);
      final guidance = ScreenshotRecognitionHelper.guidance(recognized);

      expect(result, contains('LINE 的回覆引用框'));
      expect(result, contains('重截'));
      expect(guidance.title, '建議先確認再匯入');
      expect(guidance.tone, ScreenshotRecognitionGuidanceTone.review);
    });

    test('returns group chat guidance for rejected group screenshots', () {
      const recognized = RecognizedConversation(
        messageCount: 5,
        summary: '像是群組聊天',
        classification: 'group_chat',
        importPolicy: 'reject',
      );

      final result = ScreenshotRecognitionHelper.actionGuidance(recognized);
      final guidance = ScreenshotRecognitionHelper.guidance(recognized);

      expect(result, contains('群組聊天'));
      expect(result, contains('一對一'));
      expect(guidance.title, '請改傳一對一聊天視窗');
    });

    test('supplies fallback warning for reject classifications', () {
      const recognized = RecognizedConversation(
        messageCount: 0,
        summary: '相簿畫面',
        classification: 'gallery_album',
        importPolicy: 'reject',
      );
      final conversation = buildConversation(name: '新對話');

      final result = ScreenshotRecognitionHelper.buildWarning(
        recognized: recognized,
        currentConversation: conversation,
      );

      expect(result, isNotNull);
      expect(result, contains('相簿'));
    });

    test('prefers new conversation copy for mixed-thread append mode', () {
      const recognized = RecognizedConversation(
        contactName: 'Amy',
        messageCount: 4,
        summary: '識別到 4 則訊息',
        importPolicy: 'confirm',
        warning: '這批截圖可能混入不同聯絡人的聊天段落',
      );
      final conversation = buildConversation(
        name: 'Amy',
        messages: [buildMessage(isFromMe: false, content: '嗨')],
      );

      final result = ScreenshotRecognitionHelper.importModeDescription(
        recognized: recognized,
        currentConversation: conversation,
        selectedImportMode: ScreenshotRecognitionHelper.importModeAppendCurrent,
      );

      expect(result, contains('只有在你確定'));
      expect(result, contains('另存成新對話'));
    });

    test('warns to fix direction before appending when side confidence is low',
        () {
      const recognized = RecognizedConversation(
        messageCount: 4,
        summary: '識別到 4 則訊息',
        sideConfidence: 'low',
      );
      final conversation = buildConversation(
        name: 'Amy',
        messages: [buildMessage(isFromMe: false, content: '嗨')],
      );

      final result = ScreenshotRecognitionHelper.importModeDescription(
        recognized: recognized,
        currentConversation: conversation,
        selectedImportMode: ScreenshotRecognitionHelper.importModeAppendCurrent,
      );

      expect(result, contains('我說 / 她說'));
      expect(result, contains('加入目前對話前'));
    });
  });
}

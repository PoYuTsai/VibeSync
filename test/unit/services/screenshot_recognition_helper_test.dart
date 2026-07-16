import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/services/screenshot_recognition_helper.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

void main() {
  Conversation buildConversation({
    required String name,
    List<Message>? messages,
    String? partnerId,
  }) {
    return Conversation(
      id: 'conversation-1',
      name: name,
      partnerId: partnerId,
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

    test('recognition contact name prefers Partner and skips placeholders', () {
      final partnerBound = buildConversation(
        name: '舊片段自訂標題',
        partnerId: 'partner-bruce',
      );
      final placeholder = buildConversation(name: '新對話');
      final standalone = buildConversation(name: 'Amy');

      expect(
        ScreenshotRecognitionHelper.resolveKnownContactName(
          currentConversation: partnerBound,
          expectedPartnerName: ' Bruce ',
        ),
        'Bruce',
      );
      expect(
        ScreenshotRecognitionHelper.resolveKnownContactName(
          currentConversation: partnerBound,
        ),
        isNull,
      );
      expect(
        ScreenshotRecognitionHelper.resolveKnownContactName(
          currentConversation: placeholder,
        ),
        isNull,
      );
      expect(
        ScreenshotRecognitionHelper.resolveKnownContactName(
          currentConversation: standalone,
        ),
        'Amy',
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
      expect(result, contains('目前對象不同'));
      expect(result, contains('取消並回到正確對象'));
    });

    test('requires explicit same-partner confirmation for name mismatch', () {
      const recognized = RecognizedConversation(
        contactName: 'Amber',
        messageCount: 2,
        summary: '識別到 2 則訊息',
      );
      final conversation = buildConversation(
        name: '小美',
        messages: [buildMessage(isFromMe: false, content: '晚安')],
      );

      expect(
        ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
          recognized: recognized,
          currentConversation: conversation,
        ),
        isTrue,
      );

      final emptyNamedConversation = buildConversation(
        name: '小美',
        partnerId: 'partner-xiaomei',
      );
      expect(
        ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
          recognized: recognized,
          currentConversation: emptyNamedConversation,
        ),
        isTrue,
      );
    });

    test('requires explicit confirmation when server sees different contacts',
        () {
      const recognized = RecognizedConversation(
        contactName: '小美',
        messageCount: 2,
        summary: '識別到 2 則訊息',
        warning: '這批截圖可能混入不同聯絡人的內容',
      );
      final conversation = buildConversation(
        name: '小美',
        messages: [buildMessage(isFromMe: false, content: '晚安')],
      );

      expect(
        ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
          recognized: recognized,
          currentConversation: conversation,
        ),
        isTrue,
      );
      expect(
        ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
          recognized: const RecognizedConversation(
            contactName: '小美',
            messageCount: 2,
            summary: '識別到 2 則訊息',
            warning: '畫面可能混入另一段對話',
          ),
          currentConversation: conversation,
        ),
        isTrue,
      );
    });

    test('requires confirmation for any placeholder already bound to partner',
        () {
      const recognized = RecognizedConversation(
        contactName: 'Amber',
        messageCount: 2,
        summary: '識別到 2 則訊息',
      );
      final conversation = buildConversation(
        name: '新對話',
        partnerId: 'partner-xiaomei',
      );
      final placeholderWithMessage = buildConversation(
        name: '新對話',
        partnerId: 'partner-xiaomei',
        messages: [buildMessage(isFromMe: false, content: '嗨')],
      );

      expect(
        ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
          recognized: recognized,
          currentConversation: conversation,
        ),
        isTrue,
      );
      expect(
        ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
          recognized: recognized,
          currentConversation: placeholderWithMessage,
        ),
        isTrue,
      );
      expect(
        ScreenshotRecognitionHelper.buildWarning(
          recognized: recognized,
          currentConversation: conversation,
        ),
        contains('已歸在目前對象名下'),
      );
    });

    test('uses the real partner name to avoid generic confirmation', () {
      final conversation = buildConversation(
        name: '新對話',
        partnerId: 'partner-bruce',
      );

      expect(
        ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
          recognized: const RecognizedConversation(
            contactName: 'Bruce',
            messageCount: 2,
            summary: '識別到 2 則訊息',
          ),
          currentConversation: conversation,
          expectedPartnerName: 'Bruce',
        ),
        isFalse,
      );
      expect(
        ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
          recognized: const RecognizedConversation(
            contactName: 'L',
            messageCount: 2,
            summary: '識別到 2 則訊息',
          ),
          currentConversation: conversation,
          expectedPartnerName: 'Bruce',
        ),
        isTrue,
      );
      expect(
        ScreenshotRecognitionHelper.buildWarning(
          recognized: const RecognizedConversation(
            contactName: 'L',
            messageCount: 2,
            summary: '識別到 2 則訊息',
          ),
          currentConversation: conversation,
          expectedPartnerName: 'Bruce',
        ),
        allOf(contains('L'), contains('Bruce')),
      );
    });

    test('missing OCR name is not a mismatch when partner identity is known',
        () {
      final conversation = buildConversation(
        name: '新對話',
        partnerId: 'partner-bruce',
      );

      expect(
        ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
          recognized: const RecognizedConversation(
            messageCount: 2,
            summary: '識別到 2 則訊息',
          ),
          currentConversation: conversation,
          expectedPartnerName: 'Bruce',
        ),
        isFalse,
      );
    });

    test('standalone empty placeholder does not add partner confirmation', () {
      const recognized = RecognizedConversation(
        contactName: 'Amber',
        messageCount: 2,
        summary: '識別到 2 則訊息',
      );
      final conversation = buildConversation(name: '新對話');

      expect(
        ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
          recognized: recognized,
          currentConversation: conversation,
        ),
        isFalse,
      );
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

      expect(result, '這張圖還不太確定，請先看一下內容有沒有抓對。');
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

    test('partner-bound name trusts Partner identity instead of OCR', () {
      final conversation = buildConversation(
        name: '新對話',
        partnerId: 'partner-bruce',
      );

      expect(
        ScreenshotRecognitionHelper.resolvePartnerBoundConversationName(
          currentConversation: conversation,
          expectedPartnerName: ' Bruce ',
        ),
        'Bruce',
      );
      expect(
        ScreenshotRecognitionHelper.resolvePartnerBoundConversationName(
          currentConversation: conversation,
        ),
        '新對話',
      );
    });

    test('partner-bound replacement preserves an existing custom title', () {
      final conversation = buildConversation(
        name: '春季活動那次',
        partnerId: 'partner-bruce',
      );

      expect(
        ScreenshotRecognitionHelper.resolvePartnerBoundConversationName(
          currentConversation: conversation,
          expectedPartnerName: 'Bruce',
        ),
        '春季活動那次',
      );
      expect(
        ScreenshotRecognitionHelper.resolvePartnerBoundNewFragmentName(
          currentConversation: conversation,
          expectedPartnerName: 'Bruce',
        ),
        'Bruce',
      );
    });
  });

  group('ScreenshotRecognitionHelper.copyAndGuidance', () {
    test('returns localized labels', () {
      expect(
        ScreenshotRecognitionHelper.classificationLabel('social_feed'),
        '社群畫面',
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
        '內容大致可用',
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
      expect(guidance.title, '請改傳聊天截圖');
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
      expect(guidance.title, '先確認本次內容');
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
      expect(guidance.title, '請改傳一對一聊天');
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

    test('mixed-thread copy never claims new conversation can separate people',
        () {
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

      final guidance = ScreenshotRecognitionHelper.guidance(recognized);
      final warning = ScreenshotRecognitionHelper.buildWarning(
        recognized: recognized,
        currentConversation: conversation,
      );

      expect(guidance.title, '先確認是不是同一人');
      expect(guidance.body, contains('取消並回到正確對象'));
      expect(warning, contains('若混到另一人'));
    });

    test('warns to fix direction when side confidence is low', () {
      const recognized = RecognizedConversation(
        messageCount: 4,
        summary: '識別到 4 則訊息',
        sideConfidence: 'low',
      );
      final guidance = ScreenshotRecognitionHelper.guidance(recognized);

      expect(guidance.title, '先確認我說 / 她說');
      expect(guidance.body, contains('「我說」還是「她說」'));
    });

    test('treats quoted replies as speaker-direction review risk', () {
      const recognized = RecognizedConversation(
        messageCount: 2,
        summary: '識別到 2 則訊息',
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
      final warning =
          ScreenshotRecognitionHelper.sideConfidenceWarning(recognized);
      final guidance = ScreenshotRecognitionHelper.guidance(recognized);

      expect(warning, contains('回覆引用框'));
      expect(warning, contains('我說 / 她說'));
      expect(guidance.title, '先確認我說 / 她說');
      expect(guidance.body, contains('引用'));
      expect(guidance.tone, ScreenshotRecognitionGuidanceTone.review);
    });
  });
}

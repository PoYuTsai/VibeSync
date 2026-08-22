// Work B 特徵化測試：釘住即將搬進 typed client 的對外行為
//（wire payload 形狀與回應解析），不綁實作文字。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Message _msg(String content, {bool fromMe = false}) {
  return Message(
    id: content,
    content: content,
    isFromMe: fromMe,
    timestamp: DateTime(2026, 5, 28, 12, 0, 0),
  );
}

const Map<String, dynamic> _optimizedSuccessBody = {
  'enthusiasm': {'score': 70, 'level': 'warm'},
  'gameStage': {'current': 'premise', 'status': 'normal', 'nextStep': '繼續'},
  'psychology': {'subtext': '有興趣', 'qualificationSignal': true},
  'topicDepth': {'current': 'personal', 'suggestion': '可深入'},
  'replies': {
    'extend': 'a',
    'resonate': 'b',
    'tease': 'c',
    'humor': 'd',
    'coldRead': 'e',
  },
  'finalRecommendation': {
    'pick': 'tease',
    'content': 'c',
    'reason': 'r',
    'psychology': 'p',
  },
  'strategy': '保持沉穩',
  'optimizedMessage': {
    'original': '要不要喝咖啡',
    'optimized': '這週要不要一起喝杯咖啡？',
    'improvements': ['更自然'],
  },
};

AnalysisAuxiliaryClient _service(List<Map<String, dynamic>> capturedBodies) {
  return AnalysisAuxiliaryClient(
    clientFactory: () => MockClient((request) async {
      capturedBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode(_optimizedSuccessBody),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
    accessTokenProvider: () => 'fake-token',
    expectedTierProvider: () => 'essential',
    revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:char',
  );
}

void main() {
  const requestId = '123e4567-e89b-42d3-a456-426614174000';

  group('回覆微調 refineAnchorText 守門（多輪漂移錨）', () {
    test('指令非空且錨句 != 草稿時，錨句才進 payload', () async {
      final bodies = <Map<String, dynamic>>[];
      await _service(bodies).refineReply(
        messages: [_msg('最近有空嗎？')],
        userDraft: '第 3 版微調稿',
        refineInstruction: '短一點',
        refineAnchorText: '原始那句話',
        requestId: requestId,
      );
      expect(bodies.single['refineAnchorText'], '原始那句話');
      expect(bodies.single['refineInstruction'], '短一點');
    });

    test('錨句與草稿相同時省略（server 端也會忽略，省 payload）', () async {
      final bodies = <Map<String, dynamic>>[];
      await _service(bodies).refineReply(
        messages: [_msg('最近有空嗎？')],
        userDraft: '同一句話',
        refineInstruction: '短一點',
        refineAnchorText: '  同一句話  ',
        requestId: requestId,
      );
      expect(bodies.single.containsKey('refineAnchorText'), isFalse);
    });

    test('沒有微調指令時錨句不得出現（純潤飾 payload 不分岔）', () async {
      final bodies = <Map<String, dynamic>>[];
      // typed 入口下「沒有指令」只能走 optimizeDraft，錨句在介面層就進不來；
      // wire 上仍須確認兩鍵都缺席。
      await _service(bodies).optimizeDraft(
        messages: [_msg('最近有空嗎？')],
        userDraft: '要不要喝咖啡',
        requestId: requestId,
      );
      expect(bodies.single.containsKey('refineAnchorText'), isFalse);
      expect(bodies.single.containsKey('refineInstruction'), isFalse);
    });
  });

  group('OCR recognizeOnly wire 形狀', () {
    test('圖片依序編 1..n、mediaType 固定 jpeg、recognizeOnly 旗標在場', () async {
      final bodies = <Map<String, dynamic>>[];
      final service = AnalysisAuxiliaryClient(
        clientFactory: () => MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'recognizedConversation': {
                'contactName': '小美',
                'messageCount': 2,
                'summary': '兩則訊息',
                'classification': 'valid_chat',
                'importPolicy': 'allow',
                'confidence': 'high',
                'sideConfidence': 'high',
                'uncertainSideCount': 0,
                'messages': [
                  {'content': '嗨', 'isFromMe': false},
                  {'content': '哈囉', 'isFromMe': true},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => null,
        revenueCatAppUserIdProvider: () async => null,
      );

      final imageA = Uint8List.fromList([1, 2, 3]);
      final imageB = Uint8List.fromList([4, 5, 6]);
      final result = await service.recognizeScreenshots(
        images: [imageA, imageB],
      );

      final body = bodies.single;
      expect(body['recognizeOnly'], isTrue);
      expect(body['messages'], isEmpty);
      final images = (body['images'] as List).cast<Map<String, dynamic>>();
      expect(images.map((image) => image['order']).toList(), [1, 2]);
      expect(
        images.map((image) => image['mediaType']).toSet(),
        {'image/jpeg'},
      );
      expect(images[0]['data'], base64Encode(imageA));
      expect(images[1]['data'], base64Encode(imageB));
      expect(body.containsKey('userDraft'), isFalse);
      expect(body.containsKey('refineInstruction'), isFalse);

      final recognized = result.recognizedConversation;
      expect(recognized, isNotNull);
      expect(recognized!.contactName, '小美');
      expect(recognized.messages, hasLength(2));
      expect(recognized.messages!.first.isFromMe, isFalse);
    });
  });
}

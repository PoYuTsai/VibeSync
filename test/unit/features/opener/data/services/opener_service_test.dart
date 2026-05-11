import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';

void main() {
  group('OpenerService', () {
    test('sends opener mode with image data objects and profile info',
        () async {
      final calls = <Map<String, dynamic>>[];
      final service = OpenerService(
        invoker: (functionName, {required body}) async {
          calls.add({
            'functionName': functionName,
            'body': body,
          });
          return const OpenerInvokeResponse(
            status: 200,
            data: {
              'openers': {'extend': '嗨，你也喜歡看展嗎？'},
              'recommendation': {
                'pick': 'extend',
                'reason': '低壓自然',
              },
              'pioneerPlan': {
                'ifCold': '她只回嗯嗯，就先輕鬆換一個具體小問題。',
                'handoff': '她回覆後貼回分析或問教練。',
              },
              'profileAnalysis': {'tone': '生活感'},
              'usage': {'cost': 5},
            },
          );
        },
      );

      final result = await service.generateOpeners(
        images: [
          Uint8List.fromList([1, 2])
        ],
        name: 'Candy',
        bio: '喜歡旅行',
        interests: '咖啡',
        meetingContext: 'IG',
      );

      expect(result.openers['extend'], '嗨，你也喜歡看展嗎？');
      expect(result.pioneerPlan?['ifCold'], '她只回嗯嗯，就先輕鬆換一個具體小問題。');
      expect(result.pioneerPlan?['handoff'], '她回覆後貼回分析或問教練。');
      expect(result.recommendedPick, 'extend');
      expect(result.recommendedReason, '低壓自然');
      expect(result.costUsed, 5);

      expect(calls, hasLength(1));
      expect(calls.single['functionName'], 'analyze-chat');
      final body = calls.single['body'] as Map<String, dynamic>;
      expect(body['mode'], 'opener');
      expect(body['profileInfo'], {
        'name': 'Candy',
        'bio': '喜歡旅行',
        'interests': '咖啡',
        'meetingContext': 'IG',
      });
      expect(body['images'], [
        {
          'data': 'AQI=',
          'mediaType': 'image/jpeg',
          'order': 1,
        },
      ]);
    });

    test('accepts nested opener text fields from tolerant server payload',
        () async {
      final service = OpenerService(
        invoker: (_, {required body}) async {
          return const OpenerInvokeResponse(
            status: 200,
            data: {
              'openers': {
                'extend': {'text': 'You look like trouble in a fun way'},
              },
              'recommendation': {'pick': 'extend'},
              'usage': {'cost': 3},
            },
          );
        },
      );

      final result = await service.generateOpeners(name: 'Grace');

      expect(result.openers['extend'], 'You look like trouble in a fun way');
      expect(result.bestOpenerText, 'You look like trouble in a fun way');
    });

    test('rejects raw json code fence as opener text', () async {
      final service = OpenerService(
        invoker: (_, {required body}) async {
          return const OpenerInvokeResponse(
            status: 200,
            data: {
              'openers': {
                'extend':
                    '```json\n{"profileAnalysis":{},"openers":{"extend":"hello"}}\n```',
              },
              'usage': {'cost': 5},
            },
          );
        },
      );

      await expectLater(
        service.generateOpeners(name: 'Grace'),
        throwsA(isA<Exception>()),
      );
    });

    test('maps quota 429 to OpenerQuotaExceededException', () async {
      final service = OpenerService(
        invoker: (_, {required body}) async {
          return const OpenerInvokeResponse(
            status: 429,
            data: {
              'error': 'Quota exceeded',
              'message': '額度不足，請先升級方案。',
              'monthlyRemaining': 1,
              'dailyRemaining': 1,
              'quotaNeeded': 3,
            },
          );
        },
      );

      await expectLater(
        service.generateOpeners(name: 'Candy'),
        throwsA(
          isA<OpenerQuotaExceededException>()
              .having((e) => e.message, 'message', '額度不足，請先升級方案。')
              .having((e) => e.monthlyRemaining, 'monthlyRemaining', 1)
              .having((e) => e.dailyRemaining, 'dailyRemaining', 1)
              .having((e) => e.quotaNeeded, 'quotaNeeded', 3),
        ),
      );
    });

    test('maps generic monthly 429 to user-facing quota message', () async {
      final service = OpenerService(
        invoker: (_, {required body}) async {
          return const OpenerInvokeResponse(
            status: 429,
            data: {
              'error': 'Monthly limit exceeded',
              'monthlyLimit': 30,
              'used': 30,
            },
          );
        },
      );

      await expectLater(
        service.generateOpeners(name: 'Candy'),
        throwsA(
          isA<OpenerQuotaExceededException>().having(
            (e) => e.message,
            'message',
            '本月額度不足，升級方案可取得更多開場與分析額度。',
          ),
        ),
      );
    });
  });
}

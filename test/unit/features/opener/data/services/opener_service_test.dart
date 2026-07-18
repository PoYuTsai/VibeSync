import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';

void main() {
  group('OpenerService', () {
    test('client timeout leaves room for the server opener deadline', () {
      expect(kOpenerRequestTimeout, const Duration(seconds: 70));
    });

    test('active screenshot tab payload ignores hidden manual fields', () {
      final input = OpenerGenerationInput.fromActiveTab(
        useScreenshotTab: true,
        images: [
          Uint8List.fromList([1, 2, 3])
        ],
        name: 'Hidden Name',
        bio: 'Hidden bio should not be sent',
        interests: 'Hidden interests',
        meetingContext: 'IG',
      );

      expect(input.hasContent, isTrue);
      expect(input.images, hasLength(1));
      expect(input.name, isNull);
      expect(input.bio, isNull);
      expect(input.interests, isNull);
      expect(input.meetingContext, isNull);
    });

    test('active manual tab payload ignores hidden screenshots', () {
      final input = OpenerGenerationInput.fromActiveTab(
        useScreenshotTab: false,
        images: [
          Uint8List.fromList([9, 9, 9])
        ],
        name: 'Candy',
        bio: '喜歡咖啡',
        interests: '手沖',
        meetingContext: '交友軟體',
      );

      expect(input.hasContent, isTrue);
      expect(input.images, isNull);
      expect(input.name, 'Candy');
      expect(input.bio, '喜歡咖啡');
      expect(input.interests, '手沖');
      expect(input.meetingContext, '交友軟體');
    });

    test('free handoff uses unlocked extend opener instead of locked pick', () {
      const result = OpenerResult(
        openers: {
          'extend': 'Free visible line',
          'coldRead': 'Locked recommended line',
        },
        recommendedPick: 'coldRead',
      );

      expect(
        result.bestOpenerTextForAccess(isFreeUser: true),
        'Free visible line',
      );
      expect(
        result.bestOpenerTextForAccess(isFreeUser: false),
        'Locked recommended line',
      );
    });

    test('free visible result removes locked openers and locked reason', () {
      const result = OpenerResult(
        openers: {
          'extend': 'Free visible line',
          'resonate': 'Locked resonate line',
          'coldRead': 'Locked recommended line',
        },
        recommendedPick: 'coldRead',
        recommendedReason: 'The locked line has the best hook.',
        costUsed: 3,
      );

      final visible = result.visibleForAccess(isFreeUser: true);

      expect(visible.openers, {'extend': 'Free visible line'});
      expect(visible.bestOpenerText, 'Free visible line');
      expect(visible.recommendedPick, 'extend');
      expect(visible.recommendedReason, isNull);
      expect(visible.costUsed, 3);
    });

    test('sends requestId in body when provided (charge idempotency)',
        () async {
      final calls = <Map<String, dynamic>>[];
      final service = OpenerService(
        invoker: (functionName, {required body}) async {
          calls.add(body);
          return const OpenerInvokeResponse(
            status: 200,
            data: {
              'openers': {'extend': '嗨！'},
            },
          );
        },
      );

      await service.generateOpeners(
        name: 'Grace',
        requestId: '123e4567-e89b-42d3-a456-426614174000',
      );

      expect(
        calls.single['requestId'],
        '123e4567-e89b-42d3-a456-426614174000',
      );
    });

    test('sends effectiveStyleContext in body when provided (F3-1)', () async {
      final calls = <Map<String, dynamic>>[];
      final service = OpenerService(
        invoker: (functionName, {required body}) async {
          calls.add(body);
          return const OpenerInvokeResponse(
            status: 200,
            data: {
              'openers': {'extend': '嗨！'},
            },
          );
        },
      );

      await service.generateOpeners(
        name: 'Grace',
        effectiveStyleContext: '- Preferred voice: 幽默；回覆要輕鬆',
      );

      expect(
        calls.single['effectiveStyleContext'],
        '- Preferred voice: 幽默；回覆要輕鬆',
      );
    });

    test('omits effectiveStyleContext key when null or blank', () async {
      final calls = <Map<String, dynamic>>[];
      final service = OpenerService(
        invoker: (functionName, {required body}) async {
          calls.add(body);
          return const OpenerInvokeResponse(
            status: 200,
            data: {
              'openers': {'extend': '嗨！'},
            },
          );
        },
      );

      await service.generateOpeners(name: 'Grace');
      await service.generateOpeners(name: 'Grace', effectiveStyleContext: '  ');

      expect(calls[0].containsKey('effectiveStyleContext'), isFalse);
      expect(calls[1].containsKey('effectiveStyleContext'), isFalse);
    });

    test('omits requestId key entirely when not provided', () async {
      final calls = <Map<String, dynamic>>[];
      final service = OpenerService(
        invoker: (functionName, {required body}) async {
          calls.add(body);
          return const OpenerInvokeResponse(
            status: 200,
            data: {
              'openers': {'extend': '嗨！'},
            },
          );
        },
      );

      await service.generateOpeners(name: 'Grace');

      expect(calls.single.containsKey('requestId'), isFalse);
    });

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
        expectedTier: 'essential',
        revenueCatAppUserId: r'$RCAnonymousID:abc',
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
      expect(body['expectedTier'], 'essential');
      expect(body['revenueCatAppUserId'], r'$RCAnonymousID:abc');
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

    test('MODEL_RATE_LIMITED 429 不當 quota 例外（不得誤開 paywall）', () async {
      final service = OpenerService(
        invoker: (_, {required body}) async {
          return const OpenerInvokeResponse(
            status: 429,
            data: {
              'error': 'Model rate limited',
              'code': 'MODEL_RATE_LIMITED',
              'message': '操作太頻繁，請稍等一分鐘再試。',
              'retryable': false,
            },
          );
        },
      );

      await expectLater(
        service.generateOpeners(name: 'Candy'),
        throwsA(
          allOf(
            isNot(isA<OpenerQuotaExceededException>()),
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('操作太頻繁'),
            ),
          ),
        ),
      );
    });

    test('prefers non-429 friendly message from edge payload', () async {
      final service = OpenerService(
        invoker: (_, {required body}) async {
          return const OpenerInvokeResponse(
            status: 502,
            data: {
              'error': '開場產生格式異常',
              'message': '這次 AI 回傳格式異常，請重新生成一次；本次不會扣額度。',
              'shouldChargeQuota': false,
            },
          );
        },
      );

      await expectLater(
        service.generateOpeners(name: 'Candy'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('本次不會扣額度'),
          ),
        ),
      );
    });
  });

  group('OpenerResult.requestId（批2 outcome adviceId 基底）', () {
    test('toJson/fromJson round-trip 保留 requestId', () {
      const result = OpenerResult(
        openers: {'extend': '妳週末也會去爬山嗎？'},
        requestId: 'req-1',
      );
      final restored = OpenerResult.fromJson(result.toJson());
      expect(restored.requestId, 'req-1');
    });

    test('fromJson 缺 requestId（舊快取）自產非空 id，且每次解析各自成一 id', () {
      final json = const OpenerResult(openers: {'extend': 'hi'}).toJson()
        ..remove('requestId');
      final a = OpenerResult.fromJson(json);
      final b = OpenerResult.fromJson(json);
      expect(a.requestId, isNotNull);
      expect(a.requestId, isNotEmpty);
      expect(a.requestId, isNot(b.requestId)); // 接受的邊際成本，鎖住行為
    });

    test('visibleForAccess 對 free user 保留 requestId', () {
      const result = OpenerResult(
        openers: {'extend': 'hi', 'tease': 'yo'},
        recommendedPick: 'tease',
        requestId: 'req-1',
      );
      expect(
        result.visibleForAccess(isFreeUser: true).requestId,
        'req-1',
      );
    });

    test('withRequestId 只掛 id 不動其他欄位', () {
      const result = OpenerResult(
        openers: {'extend': 'hi'},
        recommendedPick: 'extend',
        costUsed: 5,
      );
      final tagged = result.withRequestId('req-9');
      expect(tagged.requestId, 'req-9');
      expect(tagged.openers, result.openers);
      expect(tagged.recommendedPick, 'extend');
      expect(tagged.costUsed, 5);
    });
  });
}

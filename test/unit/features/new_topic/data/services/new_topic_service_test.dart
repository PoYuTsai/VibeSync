import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/new_topic/data/services/new_topic_service.dart';
import 'package:vibesync/features/new_topic/domain/entities/new_topic_result.dart';

const _requestId = '123e4567-e89b-42d3-a456-426614174000';

Map<String, dynamic> _topic(int n, {String id = ''}) => {
      'id': id.isEmpty ? 'nt_$n' : id,
      'direction': '方向$n',
      'openingLine': '開場句$n',
      'whyItWorks': '因為$n',
      'nextMove': '下一步$n',
    };

Map<String, dynamic> _paidBody() => {
      'topics': [for (var n = 1; n <= 5; n++) _topic(n)],
      'recommendation': {'topicId': 'nt_1', 'reason': '最貼近近況'},
      'access': {
        'servedTier': 'essential',
        'limited': false,
        'totalCount': 5,
        'unlockedCount': 5,
        'lockedCount': 0,
      },
      'usage': {'cost': 3},
    };

Map<String, dynamic> _freeBody() => {
      'topics': [_topic(3)],
      'recommendation': {'topicId': 'nt_3'},
      'access': {
        'servedTier': 'free',
        'limited': true,
        'totalCount': 5,
        'unlockedCount': 1,
        'lockedCount': 4,
      },
      'usage': {'cost': 3},
    };

void main() {
  group('NewTopicService request body', () {
    test('必送 mode/requestId；blank optional 欄位不送', () async {
      final calls = <Map<String, dynamic>>[];
      final service = NewTopicService(
        invoker: (fn, {required body}) async {
          calls.add({'fn': fn, 'body': body});
          return NewTopicInvokeResponse(status: 200, data: _paidBody());
        },
      );

      await service.generateTopics(
        requestId: _requestId,
        partnerSummary: '  ',
        effectiveStyleContext: null,
        situation: 'went_cold',
        expectedTier: 'free',
      );

      expect(calls.single['fn'], 'analyze-chat');
      final body = calls.single['body'] as Map<String, dynamic>;
      expect(body['mode'], 'new_topic');
      expect(body['requestId'], _requestId);
      expect(body.containsKey('partnerSummary'), isFalse);
      expect(body.containsKey('effectiveStyleContext'), isFalse);
      expect(body['situation'], 'went_cold');
      expect(body['expectedTier'], 'free');
    });
  });

  group('NewTopicService success parsing', () {
    test('paid 五題完整解析；tier 信 server access', () async {
      final service = NewTopicService(
        invoker: (_, {required body}) async =>
            NewTopicInvokeResponse(status: 200, data: _paidBody()),
      );

      final result = await service.generateTopics(requestId: _requestId);

      expect(result.topics, hasLength(5));
      expect(result.access.servedTier, 'essential');
      expect(result.access.limited, isFalse);
      expect(result.recommendation.topicId, 'nt_1');
      expect(result.recommendedTopic.openingLine, '開場句1');
      expect(result.requestId, _requestId);
      expect(result.costUsed, 3);
    });

    test('free 一題＋lockedCount 4 解析成功', () async {
      final service = NewTopicService(
        invoker: (_, {required body}) async =>
            NewTopicInvokeResponse(status: 200, data: _freeBody()),
      );

      final result = await service.generateTopics(requestId: _requestId);

      expect(result.topics, hasLength(1));
      expect(result.access.isFree, isTrue);
      expect(result.access.lockedCount, 4);
      expect(result.recommendation.reason, isNull);
    });

    test('半套 200（缺 access／題數不符）視為失敗且 retrySameRequest', () async {
      final missingAccess = _paidBody()..remove('access');
      final service = NewTopicService(
        invoker: (_, {required body}) async =>
            NewTopicInvokeResponse(status: 200, data: missingAccess),
      );

      await expectLater(
        service.generateTopics(requestId: _requestId),
        throwsA(
          isA<NewTopicException>()
              .having((e) => e.retrySameRequest, 'retrySameRequest', isTrue),
        ),
      );
    });

    test('free access 卻帶五題（鎖定內容外洩形狀）拒絕解析', () {
      final leaked = _paidBody();
      leaked['access'] = _freeBody()['access'];
      expect(
        NewTopicResult.tryParse(leaked, requestId: _requestId),
        isNull,
      );
    });

    test('推薦指向不存在的 topic 拒絕解析', () {
      final dangling = _paidBody();
      (dangling['recommendation'] as Map)['topicId'] = 'nt_9';
      expect(
        NewTopicResult.tryParse(dangling, requestId: _requestId),
        isNull,
      );
    });

    test('code fence／raw JSON 欄位拒絕解析', () {
      final fenced = _paidBody();
      (fenced['topics'] as List)[0] = _topic(1)
        ..['openingLine'] = '```json {"x":1} ```';
      expect(
        NewTopicResult.tryParse(fenced, requestId: _requestId),
        isNull,
      );
    });
  });

  group('NewTopicResult.formulaTopics（2026-07-24 公式回覆計畫 §12）', () {
    Map<String, dynamic> formulaItem(int n) => {
          'openingLine': '公式新話題$n：抓她一個具體線索加一點我的反應。',
          'whyItWorks': '因為她只要補一個細節就能回（$n）。',
        };

    test('原 result strict valid＋formula valid → 成功且 0/1/2 則都收', () {
      for (final count in [0, 1, 2]) {
        final body = _paidBody();
        body['formulaTopics'] = [
          for (var n = 1; n <= count; n++) formulaItem(n),
        ];
        final result = NewTopicResult.tryParse(body, requestId: _requestId);
        expect(result, isNotNull, reason: 'formula $count 則應成功');
        expect(result!.formulaTopics.length, count);
        if (count > 0) {
          expect(
            result.formulaTopics.first.openingLine,
            formulaItem(1)['openingLine'],
          );
        }
      }
    });

    test('原 result strict valid＋formula malformed → 成功且空清單', () {
      final malformedCases = <dynamic>[
        'not-a-list',
        {'openingLine': 'x', 'whyItWorks': 'y'},
        [
          {'openingLine': '', 'whyItWorks': '理由'},
        ],
        [
          {'openingLine': '句子'},
        ],
        [null, 42, 'str'],
      ];
      for (final malformed in malformedCases) {
        final body = _paidBody();
        body['formulaTopics'] = malformed;
        final result = NewTopicResult.tryParse(body, requestId: _requestId);
        expect(result, isNotNull, reason: '壞公式不得拖垮 base：$malformed');
        expect(result!.formulaTopics, isEmpty);
      }
    });

    test('原 result strict invalid＋formula valid → 仍整份失敗', () {
      final body = _paidBody();
      (body['topics'] as List).removeLast();
      body['formulaTopics'] = [formulaItem(1), formulaItem(2)];
      expect(NewTopicResult.tryParse(body, requestId: _requestId), isNull);
    });

    test('legacy replay row（無 formulaTopics 鍵）→ 成功且空清單', () {
      final paid = NewTopicResult.tryParse(_paidBody(), requestId: _requestId);
      expect(paid, isNotNull);
      expect(paid!.formulaTopics, isEmpty);

      final free = NewTopicResult.tryParse(_freeBody(), requestId: _requestId);
      expect(free, isNotNull);
      expect(free!.formulaTopics, isEmpty);
    });

    test('Free 也收公式（全 tier 可見，不做投影）', () {
      final body = _freeBody();
      body['formulaTopics'] = [formulaItem(1), formulaItem(2)];
      final result = NewTopicResult.tryParse(body, requestId: _requestId);
      expect(result, isNotNull);
      expect(result!.formulaTopics.length, 2);
      expect(result.access.isFree, isTrue);
      expect(result.topics.length, 1, reason: '原 Free 1 題不因公式改變');
    });

    test('client guard：cap 以 runes 計、markers／內部標籤丟該則、最多兩則', () {
      final body = _paidBody();
      body['formulaTopics'] = [
        {'openingLine': '🀄' * 181, 'whyItWorks': '理由'},
        {'openingLine': '```json 洩漏', 'whyItWorks': '理由'},
        {'openingLine': '從對象作戰板看到妳喜歡爬山', 'whyItWorks': '理由'},
        formulaItem(4),
        formulaItem(5),
        formulaItem(6),
      ];
      final result = NewTopicResult.tryParse(body, requestId: _requestId);
      expect(result, isNotNull);
      expect(result!.formulaTopics.length, 2, reason: '壞三則丟、好三則取前兩');
      expect(
        result.formulaTopics.map((f) => f.openingLine),
        [formulaItem(4)['openingLine'], formulaItem(5)['openingLine']],
      );
    });
  });

  group('NewTopicService errors', () {
    test('quota 429 → NewTopicQuotaExceededException（開 paywall）', () async {
      final service = NewTopicService(
        invoker: (_, {required body}) async => const NewTopicInvokeResponse(
          status: 429,
          data: {
            'error': '額度不足',
            'message': '本月額度不足，升級方案可取得更多新話題與分析額度。',
            'quotaNeeded': 3,
            'monthlyRemaining': 1,
            'dailyRemaining': 2,
          },
        ),
      );

      await expectLater(
        service.generateTopics(requestId: _requestId),
        throwsA(
          isA<NewTopicQuotaExceededException>()
              .having((e) => e.quotaNeeded, 'quotaNeeded', 3)
              .having((e) => e.monthlyRemaining, 'monthlyRemaining', 1),
        ),
      );
    });

    test('MODEL_RATE_LIMITED 429 絕不當 quota 例外（不誤開 paywall）', () async {
      final service = NewTopicService(
        invoker: (_, {required body}) async => const NewTopicInvokeResponse(
          status: 429,
          data: {
            'error': 'Model rate limited',
            'code': 'MODEL_RATE_LIMITED',
            'message': '操作太頻繁，請稍等一分鐘再試。',
          },
        ),
      );

      await expectLater(
        service.generateTopics(requestId: _requestId),
        throwsA(
          allOf(
            isNot(isA<NewTopicQuotaExceededException>()),
            isA<NewTopicException>()
                .having((e) => e.message, 'message', contains('太頻繁'))
                .having((e) => e.retrySameRequest, 'retry', isTrue),
          ),
        ),
      );
    });

    test('409 in progress → NewTopicRequestInProgressException＋retryAfterMs',
        () async {
      final service = NewTopicService(
        invoker: (_, {required body}) async => const NewTopicInvokeResponse(
          status: 409,
          data: {
            'code': 'NEW_TOPIC_REQUEST_IN_PROGRESS',
            'message': '這筆請求正在生成中，請稍候片刻再用同一筆請求重試。',
            'retryAfterMs': 1200,
          },
        ),
      );

      await expectLater(
        service.generateTopics(requestId: _requestId),
        throwsA(
          isA<NewTopicRequestInProgressException>()
              .having((e) => e.retryAfterMs, 'retryAfterMs', 1200),
        ),
      );
    });

    test('settlement pending 503 → retrySameRequest true', () async {
      final service = NewTopicService(
        invoker: (_, {required body}) async => const NewTopicInvokeResponse(
          status: 503,
          data: {
            'code': 'NEW_TOPIC_SETTLEMENT_PENDING',
            'message': '結果正在確認，請用同一筆請求重試。',
          },
        ),
      );

      await expectLater(
        service.generateTopics(requestId: _requestId),
        throwsA(
          isA<NewTopicException>()
              .having((e) => e.retrySameRequest, 'retry', isTrue)
              .having((e) => e.message, 'message', contains('結果正在確認')),
        ),
      );
    });

    test('英文工程錯誤訊息不外露，換固定中文文案', () async {
      final service = NewTopicService(
        invoker: (_, {required body}) async => const NewTopicInvokeResponse(
          status: 500,
          data: {'message': 'PGRST301 connection reset by peer'},
        ),
      );

      await expectLater(
        service.generateTopics(requestId: _requestId),
        throwsA(
          isA<NewTopicException>().having(
            (e) => e.message,
            'message',
            'AI 暫時生成失敗，請稍後再試；本次不會扣額度。',
          ),
        ),
      );
    });
  });
}

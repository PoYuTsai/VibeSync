// NewTopicService 串流路徑（2026-08-18 呈現精修第 2 包）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:vibesync/features/new_topic/data/services/new_topic_service.dart';

const _requestId = '123e4567-e89b-42d3-a456-426614174000';

Map<String, dynamic> _topic(int n) => {
      'id': 'nt_$n',
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
      'formulaTopics': [
        {'openingLine': '公式一', 'whyItWorks': '好接'},
      ],
      'usage': {'cost': 3},
    };

MockClient _ndjsonClient(
  List<Map<String, dynamic>> events, {
  void Function(String body)? onRequest,
}) {
  return MockClient.streaming((request, bodyStream) async {
    final requestBody = await utf8.decodeStream(bodyStream);
    onRequest?.call(requestBody);
    final lines = events.map((event) => '${jsonEncode(event)}\n').join();
    return http.StreamedResponse(
      Stream.value(utf8.encode(lines)),
      200,
      headers: {'content-type': 'application/x-ndjson; charset=utf-8'},
    );
  });
}

NewTopicService _service(http.Client client) => NewTopicService(
      streamClientFactory: () => client,
      accessTokenProvider: () => 'fake-token',
    );

void main() {
  for (final response in [(546, 'OTHER_ERROR'), (500, 'WORKER_LIMIT')]) {
    test('其他服務錯誤 ${response.$1}/${response.$2} 不套用平台中止自動重試', () async {
      var attempts = 0;
      final service = NewTopicService(
        accessTokenProvider: () => 'fake-token',
        streamClientFactory: () => MockClient.streaming((_, body) async {
          await body.drain<void>();
          attempts++;
          return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({'code': response.$2}))),
              response.$1,
              headers: {'content-type': 'application/json'});
        }),
      );
      await expectLater(
          service.generateTopicsStreaming(requestId: _requestId),
          throwsA(isA<NewTopicException>().having(
              (e) => e is NewTopicTransportException,
              'not a worker stop',
              isFalse)));
      expect(attempts, 1);
    });
  }

  for (final code in ['WORKER_LIMIT', 'WORKER_RESOURCE_LIMIT']) {
    for (final legacyFallback in [false, true]) {
      test('後端 $code 中止：${legacyFallback ? "legacy" : "stream"} 沿用原請求接回結果',
          () async {
        final requests = <Map<String, dynamic>>[];
        final progress = <String>[];
        var attempts = 0;
        NewTopicInvokeResponse response(Map<String, dynamic> body) {
          requests.add(body);
          attempts++;
          if (attempts == 1) {
            return NewTopicInvokeResponse(status: 546, data: {'code': code});
          }
          if (attempts == 2) {
            return const NewTopicInvokeResponse(status: 409, data: {
              'code': 'NEW_TOPIC_REQUEST_IN_PROGRESS',
              'retryAfterMs': 0,
            });
          }
          return NewTopicInvokeResponse(status: 200, data: _paidBody());
        }

        final service = NewTopicService(
          accessTokenProvider: () => 'fake-token',
          streamClientFactory: () =>
              MockClient.streaming((_, bodyStream) async {
            final body = jsonDecode(await utf8.decodeStream(bodyStream))
                as Map<String, dynamic>;
            final reply = legacyFallback
                ? const NewTopicInvokeResponse(status: 400, data: {
                    'code': 'NEW_TOPIC_REQUEST_INVALID',
                  })
                : response(body);
            return http.StreamedResponse(
                Stream.value(utf8.encode(jsonEncode(reply.data))), reply.status,
                headers: {'content-type': 'application/json'});
          }),
          invoker: (_, {required body}) async {
            final reply = response(body);
            if (reply.status != 200) {
              throw FunctionException(
                  status: reply.status, details: reply.data);
            }
            return reply;
          },
        );
        final result = await service.generateTopicsStreaming(
          requestId: _requestId,
          partnerSummary: '合成測試資料',
          situation: 'after_date',
          expectedTier: 'essential',
          onProgress: (label, _) => progress.add(label),
        );
        expect(result.topics, hasLength(5));
        expect(attempts, 3);
        expect(
            requests.every(
                (body) => jsonEncode(body) == jsonEncode(requests.first)),
            isTrue);
        expect(requests.first['requestId'], _requestId);
        expect(progress, hasLength(2));
      });
    }
    test('後端持續 $code：只自動接回一次，保留同筆請求且不保證未扣額度', () async {
      var attempts = 0;
      final service = NewTopicService(
        accessTokenProvider: () => 'fake-token',
        streamClientFactory: () => MockClient.streaming((_, body) async {
          await body.drain<void>();
          attempts++;
          return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({'code': code}))), 546,
              headers: {'content-type': 'application/json'});
        }),
      );
      await expectLater(
          service.generateTopicsStreaming(requestId: _requestId),
          throwsA(isA<NewTopicTransportException>()
              .having((e) => e.retrySameRequest, 'preserve request', isTrue)
              .having((e) => e.message.contains('本次不會扣'), 'unknown outcome',
                  isFalse)));
      expect(attempts, 2);
    });
  }

  test('NDJSON：progress 依序回報、done 帶回完整結果；body 帶 responseMode', () async {
    String? capturedBody;
    final client = _ndjsonClient(
      [
        {'type': 'new_topic.started', 'label': '開始生成新話題'},
        {'type': 'new_topic.progress', 'phase': 'topic_1', 'label': '新話題 1/5'},
        {'type': 'new_topic.done', 'result': _paidBody()},
      ],
      onRequest: (body) => capturedBody = body,
    );
    final progress = <String>[];

    final result = await _service(client).generateTopicsStreaming(
      requestId: _requestId,
      situation: 'went_cold',
      onProgress: (label, phase) => progress.add('$label|${phase ?? '-'}'),
    );

    expect(progress, ['開始生成新話題|-', '新話題 1/5|topic_1']);
    expect(result.topics, hasLength(5));
    final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
    expect(body['responseMode'], 'stream');
    expect(body['mode'], 'new_topic');
    expect(body['requestId'], _requestId);
  });

  test('new_topic.error 429 quota payload → NewTopicQuotaExceededException',
      () async {
    final client = _ndjsonClient([
      {
        'type': 'new_topic.error',
        'status': 429,
        'error': '額度不足',
        'message': '本月額度不足，升級方案可取得更多新話題與分析額度。',
        'monthlyLimit': 30,
        'dailyLimit': 10,
        'monthlyRemaining': 0,
        'quotaNeeded': 3,
      },
    ]);

    expect(
      () => _service(client).generateTopicsStreaming(requestId: _requestId),
      throwsA(isA<NewTopicQuotaExceededException>()),
    );
  });

  test('new_topic.error 503 settlement pending → retrySameRequest', () async {
    final client = _ndjsonClient([
      {
        'type': 'new_topic.error',
        'status': 503,
        'code': 'NEW_TOPIC_SETTLEMENT_PENDING',
        'message': '結果正在確認，請用同一筆請求重試。',
        'retryable': true,
      },
    ]);

    expect(
      () => _service(client).generateTopicsStreaming(requestId: _requestId),
      throwsA(isA<NewTopicException>()
          .having((e) => e.retrySameRequest, 'retrySameRequest', isTrue)),
    );
  });

  test('server flag off：content-type json 的 200 → legacy 解析', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(_paidBody()))),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result =
        await _service(client).generateTopicsStreaming(requestId: _requestId);
    expect(result.topics, hasLength(5));
  });

  test('new_topic.error 409 in-progress → NewTopicRequestInProgressException',
      () async {
    var requestCount = 0;
    final client = _ndjsonClient(
      [
        {
          'type': 'new_topic.error',
          'status': 409,
          'code': 'NEW_TOPIC_REQUEST_IN_PROGRESS',
          'message': '這筆請求正在生成中，請稍候片刻再用同一筆請求重試。',
          'retryAfterMs': 1,
        },
      ],
      onRequest: (_) => requestCount += 1,
    );

    await expectLater(
      () => _service(client).generateTopicsStreaming(requestId: _requestId),
      throwsA(isA<NewTopicRequestInProgressException>()
          .having((e) => e.retryAfterMs, 'retryAfterMs', 1)),
    );
    expect(requestCount, 2, reason: '只能自動接回一次，第二次仍 pending 就停止');
  });

  test('舊 Edge 400 NEW_TOPIC_REQUEST_INVALID → 自動降級 legacy 重打（不雙扣）', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'error': 'NEW_TOPIC_REQUEST_INVALID',
          'code': 'NEW_TOPIC_REQUEST_INVALID',
          'message': '新話題暫不支援這種回應模式，請更新 App 後再試。本次不會扣額度。',
        }))),
        400,
        headers: {'content-type': 'application/json'},
      );
    });
    final legacyCalls = <Map<String, dynamic>>[];
    final service = NewTopicService(
      streamClientFactory: () => client,
      accessTokenProvider: () => 'fake-token',
      invoker: (_, {required body}) async {
        legacyCalls.add(body);
        return NewTopicInvokeResponse(status: 200, data: _paidBody());
      },
    );

    final result = await service.generateTopicsStreaming(requestId: _requestId);
    expect(result.topics, hasLength(5));
    expect(legacyCalls, hasLength(1));
    expect(legacyCalls.single.containsKey('responseMode'), isFalse,
        reason: 'legacy 重打不得再帶 responseMode');
  });

  test('legacy fallback 遇 SDK 409：等待後沿用同 requestId 自動接回結果', () async {
    var streamCalls = 0;
    var legacyCalls = 0;
    final service = NewTopicService(
      streamClientFactory: () =>
          MockClient.streaming((request, bodyStream) async {
        streamCalls += 1;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({
            'error': 'NEW_TOPIC_REQUEST_INVALID',
            'code': 'NEW_TOPIC_REQUEST_INVALID',
            'message': '新話題暫不支援這種回應模式，請更新 App 後再試。本次不會扣額度。',
          }))),
          400,
          headers: {'content-type': 'application/json'},
        );
      }),
      accessTokenProvider: () => 'fake-token',
      invoker: (_, {required body}) async {
        legacyCalls += 1;
        expect(body['requestId'], _requestId);
        if (legacyCalls == 1) {
          throw const FunctionException(
            status: 409,
            details: {
              'code': 'NEW_TOPIC_REQUEST_IN_PROGRESS',
              'message': '這筆請求正在生成中，請稍候片刻再用同一筆請求重試。',
              'retryable': true,
              'retryAfterMs': 1,
            },
            reasonPhrase: 'Conflict',
          );
        }
        return NewTopicInvokeResponse(status: 200, data: _paidBody());
      },
    );

    final result = await service.generateTopicsStreaming(requestId: _requestId);

    expect(result.topics, hasLength(5));
    expect(streamCalls, 2);
    expect(legacyCalls, 2);
  });

  test('第一次 transport 中斷：沿用同 requestId 自動重連一次並接回結果', () async {
    var clientCount = 0;
    final requestIds = <String>[];
    final service = NewTopicService(
      streamClientFactory: () {
        clientCount += 1;
        if (clientCount == 1) {
          return MockClient.streaming((request, bodyStream) async {
            final body = jsonDecode(await utf8.decodeStream(bodyStream))
                as Map<String, dynamic>;
            requestIds.add(body['requestId'] as String);
            throw http.ClientException('connection lost');
          });
        }
        return MockClient.streaming((request, bodyStream) async {
          final body = jsonDecode(await utf8.decodeStream(bodyStream))
              as Map<String, dynamic>;
          requestIds.add(body['requestId'] as String);
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(_paidBody()))),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
      },
      accessTokenProvider: () => 'fake-token',
    );

    final result = await service.generateTopicsStreaming(requestId: _requestId);

    expect(result.topics, hasLength(5));
    expect(requestIds, [_requestId, _requestId]);
  });

  test('transport 連斷兩次：同 requestId 只接回一次後停止', () async {
    final requestIds = <String>[];
    final service = NewTopicService(
      streamClientFactory: () =>
          MockClient.streaming((request, bodyStream) async {
        final body = jsonDecode(await utf8.decodeStream(bodyStream))
            as Map<String, dynamic>;
        requestIds.add(body['requestId'] as String);
        throw http.ClientException('connection lost');
      }),
      accessTokenProvider: () => 'fake-token',
    );

    await expectLater(
      service.generateTopicsStreaming(requestId: _requestId),
      throwsA(isA<NewTopicTransportException>()),
    );

    expect(requestIds, [_requestId, _requestId]);
  });

  test('第一次回報 claim 狀態待恢復：同 requestId 經 pending 後自動接回結果', () async {
    var clientCount = 0;
    final requestIds = <String>[];
    final service = NewTopicService(
      streamClientFactory: () {
        clientCount += 1;
        return MockClient.streaming((request, bodyStream) async {
          final body = jsonDecode(await utf8.decodeStream(bodyStream))
              as Map<String, dynamic>;
          requestIds.add(body['requestId'] as String);
          if (clientCount == 1) {
            final lines = '${jsonEncode({
                  'type': 'new_topic.error',
                  'status': 503,
                  'code': 'NEW_TOPIC_CLAIM_RELEASE_RETRYABLE',
                  'message': '請求狀態暫時無法釋放，請稍後用同一筆請求重試。',
                  'retryable': true,
                })}\n';
            return http.StreamedResponse(
              Stream.value(utf8.encode(lines)),
              200,
              headers: {'content-type': 'application/x-ndjson'},
            );
          }
          if (clientCount == 2) {
            final lines = '${jsonEncode({
                  'type': 'new_topic.error',
                  'status': 409,
                  'code': 'NEW_TOPIC_REQUEST_IN_PROGRESS',
                  'message': '這筆請求正在生成中，請稍候片刻再用同一筆請求重試。',
                  'retryAfterMs': 1,
                })}\n';
            return http.StreamedResponse(
              Stream.value(utf8.encode(lines)),
              200,
              headers: {'content-type': 'application/x-ndjson'},
            );
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(_paidBody()))),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
      },
      accessTokenProvider: () => 'fake-token',
    );

    final result = await service.generateTopicsStreaming(requestId: _requestId);

    expect(result.topics, hasLength(5));
    expect(requestIds, [_requestId, _requestId, _requestId]);
  });

  test('混合 pending／409／transport：全局最多三次同 requestId 呼叫', () async {
    var clientCount = 0;
    final requestIds = <String>[];
    final service = NewTopicService(
      streamClientFactory: () {
        clientCount += 1;
        return MockClient.streaming((request, bodyStream) async {
          final body = jsonDecode(await utf8.decodeStream(bodyStream))
              as Map<String, dynamic>;
          requestIds.add(body['requestId'] as String);
          if (clientCount == 1) {
            final lines = '${jsonEncode({
                  'type': 'new_topic.error',
                  'status': 503,
                  'code': 'NEW_TOPIC_CLAIM_RELEASE_RETRYABLE',
                  'message': '請求狀態暫時無法釋放，請稍後用同一筆請求重試。',
                  'retryable': true,
                })}\n';
            return http.StreamedResponse(
              Stream.value(utf8.encode(lines)),
              200,
              headers: {'content-type': 'application/x-ndjson'},
            );
          }
          if (clientCount == 2) {
            final lines = '${jsonEncode({
                  'type': 'new_topic.error',
                  'status': 409,
                  'code': 'NEW_TOPIC_REQUEST_IN_PROGRESS',
                  'message': '這筆請求正在生成中，請稍候片刻再用同一筆請求重試。',
                  'retryAfterMs': 1,
                })}\n';
            return http.StreamedResponse(
              Stream.value(utf8.encode(lines)),
              200,
              headers: {'content-type': 'application/x-ndjson'},
            );
          }
          if (clientCount == 3) {
            throw http.ClientException('connection lost');
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(_paidBody()))),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
      },
      accessTokenProvider: () => 'fake-token',
    );

    await expectLater(
      service.generateTopicsStreaming(requestId: _requestId),
      throwsA(isA<NewTopicTransportException>()),
    );

    expect(clientCount, 3);
    expect(requestIds, [_requestId, _requestId, _requestId]);
  });

  test('串流結束沒收到終局事件 → retrySameRequest（同 requestId 重試不雙扣）', () async {
    final client = _ndjsonClient([
      {'type': 'new_topic.started', 'label': '開始'},
    ]);

    expect(
      () => _service(client).generateTopicsStreaming(requestId: _requestId),
      throwsA(isA<NewTopicException>()
          .having((e) => e.retrySameRequest, 'retrySameRequest', isTrue)),
    );
  });
}

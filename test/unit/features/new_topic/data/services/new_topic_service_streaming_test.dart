// NewTopicService 串流路徑（2026-08-18 呈現精修第 2 包）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
      onProgress: progress.add,
    );

    expect(progress, ['開始生成新話題', '新話題 1/5']);
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

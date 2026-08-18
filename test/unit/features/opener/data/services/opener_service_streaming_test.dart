// OpenerService 串流路徑（2026-08-18 呈現精修第 2 包）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';

Map<String, dynamic> _successBody() => {
      'profileAnalysis': {'style': '活潑'},
      'openers': {
        'extend': '延展句',
        'resonate': '共鳴句',
        'tease': '調情句',
        'humor': '幽默句',
        'coldRead': '冷讀句',
      },
      'pioneerPlan': {'ifCold': '先冷處理'},
      'recommendation': {'pick': 'extend', 'reason': '最自然'},
      'formulaOpeners': [
        {'openingLine': '公式一', 'whyItWorks': '好接'},
        {'openingLine': '公式二', 'whyItWorks': '也好接'},
      ],
      'access': {
        'contractVersion': 2,
        'servedTier': 'essential',
        'visibleTypes': ['extend', 'resonate', 'tease', 'humor', 'coldRead'],
        'lockedTypes': <String>[],
      },
      'usage': {'cost': 3},
    };

MockClient _ndjsonClient(
  List<Map<String, dynamic>> events, {
  void Function(http.BaseRequest request, String body)? onRequest,
}) {
  return MockClient.streaming((request, bodyStream) async {
    final requestBody = await utf8.decodeStream(bodyStream);
    onRequest?.call(request, requestBody);
    final lines = events.map((event) => '${jsonEncode(event)}\n').join();
    return http.StreamedResponse(
      Stream.value(utf8.encode(lines)),
      200,
      headers: {'content-type': 'application/x-ndjson; charset=utf-8'},
    );
  });
}

OpenerService _service(http.Client client) => OpenerService(
      streamClientFactory: () => client,
      accessTokenProvider: () => 'fake-token',
    );

void main() {
  test('NDJSON：progress 依序回報、done 帶回完整結果；body 帶 responseMode', () async {
    String? capturedBody;
    final client = _ndjsonClient(
      [
        {'type': 'opener.started', 'label': '開始生成開場白'},
        {'type': 'opener.progress', 'phase': 'profile', 'label': '解讀對方資料'},
        {'type': 'opener.progress', 'phase': 'heartbeat', 'label': '生成仍在進行'},
        {'type': 'unknown.future.event'},
        {'type': 'opener.done', 'result': _successBody()},
      ],
      onRequest: (_, body) => capturedBody = body,
    );
    final progress = <String>[];

    final result = await _service(client).generateOpenersStreaming(
      name: '小美',
      requestId: 'req-1',
      onProgress: (label, phase) => progress.add('$label|${phase ?? '-'}'),
    );

    expect(progress, [
      '開始生成開場白|-',
      '解讀對方資料|profile',
      '生成仍在進行|heartbeat',
    ]);
    expect(result.openers['extend'], '延展句');
    expect(result.recommendedPick, 'extend');
    expect(result.formulaOpeners, hasLength(2));
    final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
    expect(body['responseMode'], 'stream');
    expect(body['mode'], 'opener');
  });

  test('opener.error 429 quota payload → OpenerQuotaExceededException', () async {
    final client = _ndjsonClient([
      {'type': 'opener.started', 'label': '開始'},
      {
        'type': 'opener.error',
        'status': 429,
        'error': 'Monthly limit exceeded',
        'message': '本月額度不足，升級方案可取得更多開場與分析額度。',
        'monthlyLimit': 30,
        'dailyLimit': 10,
        'monthlyRemaining': 1,
        'quotaNeeded': 3,
      },
    ]);

    expect(
      () => _service(client).generateOpenersStreaming(name: '小美'),
      throwsA(isA<OpenerQuotaExceededException>()
          .having((e) => e.monthlyRemaining, 'monthlyRemaining', 1)),
    );
  });

  test('opener.error 無額度鍵的 429（限流）→ 一般 Exception，不誤開 paywall', () async {
    final client = _ndjsonClient([
      {
        'type': 'opener.error',
        'status': 429,
        'code': 'MODEL_RATE_LIMITED',
        'message': '請求太頻繁，請稍後再試。',
      },
    ]);

    expect(
      () => _service(client).generateOpenersStreaming(name: '小美'),
      throwsA(isA<Exception>()
          .having((e) => e, 'type', isNot(isA<OpenerQuotaExceededException>()))),
    );
  });

  test('server flag off：content-type json 的 200 → legacy 解析，呼叫端無感', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(_successBody()))),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await _service(client).generateOpenersStreaming(name: '小美');
    expect(result.openers, hasLength(5));
  });

  test('非 200 的 JSON 錯誤照 legacy 對映（502 不扣文案）', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'error': '開場產生格式異常',
          'message': '這次 AI 回傳格式異常，請重新生成一次；本次不會扣額度。',
        }))),
        502,
        headers: {'content-type': 'application/json'},
      );
    });

    expect(
      () => _service(client).generateOpenersStreaming(name: '小美'),
      throwsA(predicate((e) => e.toString().contains('本次不會扣額度'))),
    );
  });

  test('200 但 body 不是合法 JSON object → 友善格式錯誤（不炸 FormatException）',
      () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(
        Stream.value(utf8.encode('not-json')),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    expect(
      () => _service(client).generateOpenersStreaming(name: '小美'),
      throwsA(predicate((e) => e.toString().contains('開場產生格式異常'))),
    );
  });

  test('串流結束沒收到終局事件 → 提示重試且說明不會雙扣', () async {
    final client = _ndjsonClient([
      {'type': 'opener.started', 'label': '開始'},
      {'type': 'opener.progress', 'phase': 'profile', 'label': '解讀對方資料'},
    ]);

    expect(
      () => _service(client).generateOpenersStreaming(name: '小美'),
      throwsA(predicate((e) => e.toString().contains('不會重複扣額度'))),
    );
  });

  test('傳輸中斷（ClientException）→ 同樣提示不會雙扣', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      final stream = Stream<List<int>>.multi((controller) {
        controller.add(utf8.encode(
          '${jsonEncode({'type': 'opener.started', 'label': '開始'})}\n',
        ));
        controller.addError(http.ClientException('Connection reset'));
        controller.close();
      });
      return http.StreamedResponse(
        stream,
        200,
        headers: {'content-type': 'application/x-ndjson'},
      );
    });

    expect(
      () => _service(client).generateOpenersStreaming(name: '小美'),
      throwsA(predicate((e) => e.toString().contains('不會重複扣額度'))),
    );
  });
}

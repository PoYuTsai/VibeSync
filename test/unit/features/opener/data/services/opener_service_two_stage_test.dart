// OpenerService 兩段式傳輸：NDJSON 事件、body 形狀、錯誤碼對映、舊 Edge 不支援偵測。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';
import 'package:vibesync/features/opener/domain/opener_flow_models.dart';

Map<String, dynamic> _analyzeResult() => {
      'stage': 'analyze',
      'flowVersion': 1,
      'sessionId': 'sess-1',
      'analysisRevision': 1,
      'expiresAt': '2026-09-18T12:00:00Z',
      'approach': {'mode': 'anchor_hooks', 'summary': '可以從她的狗開', 'avoid': []},
      'cues': [{'id': 'cue_1', 'label': '養狗', 'source': 'profile_text'}],
      'question': null,
      'usage': {'chargedNow': 0, 'firstGenerationCost': 3, 'includedGenerationCount': 3, 'generationsUsed': 0, 'quotaCharged': false},
      'replayed': false,
    };

Map<String, dynamic> _generateResult() => {
      'stage': 'generate',
      'sessionId': 'sess-1',
      'generationId': 'gen-1',
      'expiresAt': '2026-09-18T12:00:00Z',
      'openers': {'extend': '牠散步會自己選路嗎', 'humor': '導航派還是隨機派', 'tease': '妳家狗比妳會排行程'},
      'recommendation': {'pick': 'extend', 'reason': '直接問你想知道的事'},
      'cardReasons': {'extend': '直接問你想知道的事'},
      'materialUse': {'inputState': 'answered', 'references': [], 'traceStatus': 'uncertain', 'displayNote': null},
      'access': {'contractVersion': 2, 'servedTier': 'free', 'visibleTypes': ['extend', 'humor', 'tease'], 'lockedTypes': ['resonate', 'coldRead']},
      'usage': {'chargedNow': 3, 'sessionChargedTotal': 3, 'generationsUsed': 1, 'generationsRemaining': 2, 'replayed': false},
    };

MockClient _ndjson(List<Map<String, dynamic>> events, {void Function(String body)? onRequest}) {
  return MockClient.streaming((request, bodyStream) async {
    onRequest?.call(await utf8.decodeStream(bodyStream));
    final lines = events.map((e) => '${jsonEncode(e)}\n').join();
    return http.StreamedResponse(Stream.value(utf8.encode(lines)), 200, headers: {'content-type': 'application/x-ndjson; charset=utf-8'});
  });
}

MockClient _json(int status, Map<String, dynamic> body) {
  return MockClient.streaming((request, bodyStream) async {
    await utf8.decodeStream(bodyStream);
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status, headers: {'content-type': 'application/json'});
  });
}

OpenerService _service(http.Client client) => OpenerService(streamClientFactory: () => client, accessTokenProvider: () => 'token');

const _contribution = OpenerContribution(state: OpenerContributionState.answered, questionId: 'question_1', selectedOptionId: 'option_2', freeText: '沒養過');

void main() {
  test('第一段：body 帶 mode/openerFlowVersion/analysisRequestId/initialUserNote，progress 依序、done 解析成 OpenerAnalysis', () async {
    String? captured;
    final progress = <String>[];
    final client = _ndjson([
      {'type': 'opener_analyze.started', 'label': '開始分析對方資料'},
      {'type': 'opener_analyze.progress', 'phase': 'analyze_cues', 'label': '整理可接線索'},
      {'type': 'opener_analyze.progress', 'phase': 'heartbeat', 'label': '仍在進行'},
      {'type': 'opener_analyze.done', 'result': _analyzeResult()},
    ], onRequest: (body) => captured = body);
    final analysis = await _service(client).analyzeProfileStreaming(
      bio: '有養一隻狗',
      analysisRequestId: 'req-1',
      initialUserNote: ' 想從狗開 ',
      onProgress: (label, phase) => progress.add('$label|${phase ?? '-'}'),
    );
    expect(analysis.sessionId, 'sess-1');
    expect(analysis.question, isNull);
    expect(progress, ['開始分析對方資料|-', '整理可接線索|analyze_cues', '仍在進行|heartbeat']);
    final body = jsonDecode(captured!) as Map<String, dynamic>;
    expect(body['mode'], 'opener_analyze');
    expect(body['openerFlowVersion'], 1);
    expect(body['openerContractVersion'], 2);
    expect(body['analysisRequestId'], 'req-1');
    expect(body['initialUserNote'], '想從狗開');
    expect(body['responseMode'], 'stream');
    expect(body['profileInfo'], {'bio': '有養一隻狗'});
  });

  test('第二段：body 帶 sessionId/analysisRevision/generationId/userContribution；done 解析成 OpenerGeneration', () async {
    String? captured;
    final client = _ndjson([
      {'type': 'opener_generate.started', 'label': '開始'},
      {'type': 'opener_generate.progress', 'phase': 'style_extend', 'label': '開場白 1/5'},
      {'type': 'opener_generate.done', 'result': _generateResult()},
    ], onRequest: (body) => captured = body);
    final generation = await _service(client).generateFromAnalysisStreaming(
      sessionId: 'sess-1', analysisRevision: 1, generationId: 'gen-1', contribution: _contribution,
    );
    expect(generation.generationId, 'gen-1');
    expect(generation.result.requestId, 'gen-1');
    expect(generation.usage.chargedNow, 3);
    expect(generation.contribution.freeText, '沒養過');
    final body = jsonDecode(captured!) as Map<String, dynamic>;
    expect(body['mode'], 'opener_generate');
    expect(body['openerCardSet'], 2, reason: '這版 App 看得懂一句推薦＋四句備選');
    expect(body['userContribution'], {'state': 'answered', 'questionId': 'question_1', 'selectedOptionId': 'option_2', 'freeText': '沒養過'});
    expect(body.containsKey('images'), isFalse, reason: '第二段不重傳圖片');
  });

  test('opener_generate.error 帶 code → OpenerFlowException（到期／次數用完／輸入不一致／限流）', () async {
    for (final (code, status) in [
      (OpenerFlowErrorCode.sessionExpired, 410),
      (OpenerFlowErrorCode.generationLimitReached, 409),
      (OpenerFlowErrorCode.inputMismatch, 409),
      (OpenerFlowErrorCode.modelRateLimited, 429),
    ]) {
      final client = _ndjson([
        {'type': 'opener_generate.error', 'status': status, 'code': code, 'error': code, 'message': '訊息', 'retryable': false},
      ]);
      await expectLater(
        () => _service(client).generateFromAnalysisStreaming(sessionId: 's', analysisRevision: 1, generationId: 'g', contribution: _contribution),
        throwsA(isA<OpenerFlowException>().having((e) => e.code, 'code', code).having((e) => e.status, 'status', status)),
      );
    }
  });

  test('訂閱額度 429（帶額度鍵）仍是 OpenerQuotaExceededException；限流 429 不是', () async {
    final quota = _ndjson([
      {'type': 'opener_generate.error', 'status': 429, 'error': '額度不足', 'message': '本月額度不足', 'monthlyLimit': 30, 'dailyLimit': 10, 'monthlyRemaining': 1, 'quotaNeeded': 3},
    ]);
    await expectLater(
      () => _service(quota).generateFromAnalysisStreaming(sessionId: 's', analysisRevision: 1, generationId: 'g', contribution: _contribution),
      throwsA(isA<OpenerQuotaExceededException>().having((e) => e.quotaNeeded, 'quotaNeeded', 3)),
    );
    final limited = _ndjson([
      {'type': 'opener_generate.error', 'status': 429, 'code': 'MODEL_RATE_LIMITED', 'message': '操作太頻繁', 'retryable': false},
    ]);
    await expectLater(
      () => _service(limited).generateFromAnalysisStreaming(sessionId: 's', analysisRevision: 1, generationId: 'g', contribution: _contribution),
      throwsA(isA<OpenerFlowException>().having((e) => e.isRateLimited, 'isRateLimited', isTrue)),
    );
  });

  test('舊 Edge：mode 不認識→400 沒有 code → OPENER_FLOW_UNSUPPORTED；503 OPENER_FLOW_UNAVAILABLE 保留 code', () async {
    final old = _json(400, {'error': 'Invalid messages'});
    await expectLater(
      () => _service(old).analyzeProfileStreaming(bio: 'x', analysisRequestId: 'r'),
      throwsA(isA<OpenerFlowException>().having((e) => e.isUnsupported, 'isUnsupported', isTrue)),
    );
    final retired = _json(410, {'error': 'ANALYZE_STREAMING_REQUIRED', 'code': 'ANALYZE_STREAMING_REQUIRED', 'message': 'x'});
    await expectLater(
      () => _service(retired).analyzeProfileStreaming(bio: 'x', analysisRequestId: 'r'),
      throwsA(isA<OpenerFlowException>().having((e) => e.isUnsupported, 'isUnsupported', isTrue)),
    );
    final disabled = _json(503, {'error': 'OPENER_FLOW_UNAVAILABLE', 'code': 'OPENER_FLOW_UNAVAILABLE', 'message': '暫停中', 'retryable': false});
    await expectLater(
      () => _service(disabled).analyzeProfileStreaming(bio: 'x', analysisRequestId: 'r'),
      throwsA(isA<OpenerFlowException>().having((e) => e.isUnavailable, 'isUnavailable', isTrue)),
    );
  });

  test('wrongSurface 422 → OpenerFlowException 帶 surface（引導既有對話分析）', () async {
    final client = _ndjson([
      {'type': 'opener_analyze.error', 'status': 422, 'error': 'OPENER_WRONG_SURFACE', 'surface': 'chat_conversation', 'message': '這看起來是聊天對話的截圖'},
    ]);
    await expectLater(
      () => _service(client).analyzeProfileStreaming(bio: 'x', analysisRequestId: 'r'),
      throwsA(isA<OpenerFlowException>().having((e) => e.surface, 'surface', 'chat_conversation').having((e) => e.code, 'code', OpenerFlowErrorCode.wrongSurface)),
    );
  });

  test('串流中斷沒有終局事件 → 一般 Exception（同一筆請求重試不重扣）', () async {
    final client = _ndjson([{'type': 'opener_generate.started', 'label': '開始'}]);
    await expectLater(
      () => _service(client).generateFromAnalysisStreaming(sessionId: 's', analysisRevision: 1, generationId: 'g', contribution: _contribution),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('同一筆請求重試不會重複扣額度'))),
    );
  });
}

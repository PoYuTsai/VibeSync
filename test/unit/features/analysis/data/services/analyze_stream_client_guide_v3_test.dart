import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

/// v3 事件照伺服器 `guide_v3/stream_flow.ts` 的順序：started（帶 guideVersion）
/// → 扣費成功後 read＋第一張卡 → 其他卡 → done。
Message _msg(String content, {bool fromMe = false}) {
  return Message(
    id: content,
    content: content,
    isFromMe: fromMe,
    timestamp: DateTime(2026, 10, 17, 12),
  );
}

const _readEvent = {
  'type': 'analysis.read',
  'guideVersion': 'v3.4',
  'decision': 'send',
  'light': 'green',
  'judgment': '她有在接你的話，可以往前一步。',
  'plannedCards': [
    {'slot': 1, 'task': 'accept', 'locked': false},
    {'slot': 2, 'task': 'push', 'locked': false},
  ],
};

Map<String, dynamic> _cardEvent(int slot, String task, String text) => {
      'type': 'analysis.card',
      'slot': slot,
      'task': task,
      'method': 'reaction',
      'voice': 'default',
      'messages': [text],
      'hasInventedDetail': false,
      'hasBlank': false,
    };

Map<String, dynamic> _finalResult({bool recovered = false}) => {
      'guideVersion': 'v3.4',
      'read': {
        for (final entry in _readEvent.entries)
          if (entry.key != 'type') entry.key: entry.value,
      },
      'cards': [
        {
          for (final entry in _cardEvent(1, 'accept', '那家我也想吃吃看').entries)
            if (entry.key != 'type') entry.key: entry.value,
        },
        if (!recovered)
          {
            for (final entry in _cardEvent(2, 'push', '週六一起去？').entries)
              if (entry.key != 'type') entry.key: entry.value,
          },
      ],
      'partial': recovered,
      if (recovered) 'recovered': true,
      'usage': {'messagesUsed': 1, 'shouldChargeQuota': true},
    };

AnalyzeStreamClient _client(
  List<Map<String, dynamic>> events, {
  void Function(http.Request request)? onRequest,
}) {
  final mockClient = MockClient((request) async {
    onRequest?.call(request);
    return http.Response.bytes(
      utf8.encode(events.map(jsonEncode).join('\n')),
      200,
      headers: {'content-type': 'application/x-ndjson'},
    );
  });
  return AnalyzeStreamClient(
    displayMapper: const AnalysisStreamContentDisplayMapper(),
    clientFactory: () => mockClient,
    accessTokenProvider: () => 'fake-token',
    expectedTierProvider: () => null,
    revenueCatAppUserIdProvider: () async => null,
  );
}

const _v3Started = {
  'type': 'analysis.started',
  'runId': 'run_v3',
  'conversationHash': 'hash',
  'etaSeconds': 6,
  'guideVersion': 'v3.4',
};

Future<StreamModeException> _streamError(
  List<Map<String, dynamic>> events,
) async {
  try {
    await _client(events)
        .stream(AnalyzeStreamRequest(messages: [_msg('哈囉')]))
        .toList();
  } on StreamModeException catch (error) {
    return error;
  }
  fail('expected StreamModeException');
}

void main() {
  group('AnalyzeStreamClient — v3 任務卡', () {
    test('判讀與每張卡一到就往上送，done 給 v3 結果、不經過五種風格解析', () async {
      late Map<String, dynamic> body;
      final updates = await _client(
        [
          _v3Started,
          _readEvent,
          _cardEvent(1, 'accept', '那家我也想吃吃看'),
          {
            'type': 'analysis.progress',
            'phase': 'heartbeat',
            'runId': 'run_v3',
            'label': '分析仍在進行',
          },
          _cardEvent(2, 'push', '週六一起去？'),
          {
            'type': 'analysis.done',
            'runId': 'run_v3',
            'finalResult': _finalResult(),
            'result': _finalResult(),
          },
        ],
        onRequest: (request) =>
            body = jsonDecode(request.body) as Map<String, dynamic>,
      ).stream(AnalyzeStreamRequest(messages: [_msg('哈囉')])).toList();

      expect(body['analysisContractVersion'], 3);
      expect(updates.map((u) => u.kind), [
        AnalysisStreamUpdateKind.started,
        AnalysisStreamUpdateKind.guideV3Read,
        AnalysisStreamUpdateKind.guideV3Card,
        AnalysisStreamUpdateKind.progress,
        AnalysisStreamUpdateKind.guideV3Card,
        AnalysisStreamUpdateKind.done,
      ]);
      expect(updates.first.guideVersion, 'v3.4');
      expect(updates[1].guideV3Read!.decision, GuideV3Decision.send);
      expect(updates[2].guideV3Card!.messages, ['那家我也想吃吃看']);
      expect(updates[2].runId, 'run_v3');
      final done = updates.last;
      expect(done.result, isNull, reason: 'v3 不能被補成熱度 50 的五種風格結果');
      expect(done.guideV3Result!.cards.map((c) => c.task),
          [GuideV3Task.accept, GuideV3Task.push]);
      expect(done.runId, 'run_v3');
    });

    test('關係狀態（Bruce 2026-10-19 路線二）：判讀事件與 done 的判讀都帶得到；壞的欄位不收、不讓分析失敗',
        () async {
      const relation = {
        'stage': 'narrative',
        'heat': 80,
        'dimensions': {
          'heat': 80,
          'engagement': 75,
          'topicDepth': 60,
          'replyWillingness': 82,
          'emotionalConnection': 70,
        },
        'herMove': 'laugh_ending',
        'willingness': 'medium',
      };
      final updates = await _client([
        _v3Started,
        {..._readEvent, 'relation': relation},
        _cardEvent(1, 'accept', '那家我也想吃吃看'),
        {
          'type': 'analysis.done',
          'runId': 'run_v3',
          'finalResult': {
            ..._finalResult(),
            'read': {
              ...(_finalResult()['read'] as Map<String, dynamic>),
              // 伺服器丟掉的欄位（例如熱度超出範圍）App 也不收，其他照收。
              'relation': {...relation, 'heat': 180},
            },
          },
        },
      ]).stream(AnalyzeStreamRequest(messages: [_msg('哈囉')])).toList();

      final read = updates
          .firstWhere((u) => u.kind == AnalysisStreamUpdateKind.guideV3Read)
          .guideV3Read!;
      expect(read.relation!.heat, 80);
      expect(read.relation!.herMove, GuideV3HerMove.laughEnding);
      expect(read.relation!.willingness, GuideV3Willingness.medium);
      final done = updates
          .firstWhere((u) => u.kind == AnalysisStreamUpdateKind.done)
          .guideV3Result!;
      expect(done.read.relation!.heat, isNull);
      expect(done.read.relation!.dimensions!['heat'], 80);
      expect(done.cards.first.messages, ['那家我也想吃吃看']);
    });

    test('「為什麼這樣回」：卡之後、done 之前每張一則，照種類找；讀不懂的跳過，卡與結果照舊', () async {
      final updates = await _client([
        _v3Started,
        _readEvent,
        _cardEvent(1, 'accept', '那家我也想吃吃看'),
        _cardEvent(2, 'push', '週六一起去？'),
        {'type': 'analysis.card_explain', 'card': 1, 'text': '  先接住她的分享。 '},
        {'type': 'analysis.card_explain', 'card': 0, 'text': '沒有這張'},
        {'type': 'analysis.card_explain', 'card': 2, 'text': '   '},
        {'type': 'analysis.card_explain', 'card': '2', 'text': '代碼不對'},
        {'type': 'analysis.card_explain', 'card': 2, 'text': '順著她說的地方約。'},
        {
          'type': 'analysis.done',
          'runId': 'run_v3',
          'finalResult': _finalResult()
        },
      ]).stream(AnalyzeStreamRequest(messages: [_msg('哈囉')])).toList();

      final explains = updates
          .where((u) => u.kind == AnalysisStreamUpdateKind.guideV3CardExplain)
          .map((u) => u.guideV3CardExplain!)
          .toList();
      expect(explains.map((e) => e.card), [1, 2]);
      expect(explains.map((e) => e.text), ['先接住她的分享。', '順著她說的地方約。']);
      final done = updates
          .firstWhere((u) => u.kind == AnalysisStreamUpdateKind.done)
          .guideV3Result!;
      expect(done.cards.map((c) => c.slot), [1, 2]);
      // 伺服器的最終結果不帶說明；由 notifier 併進去。
      expect(done.cardExplains, isEmpty);
    });

    test('中途讀不懂的判讀或卡跳過，等 done 的完整結果', () async {
      final updates = await _client([
        _v3Started,
        {'type': 'analysis.read', 'decision': 'unknown'},
        {'type': 'analysis.card', 'slot': 1, 'task': 'accept'},
        {'type': 'analysis.done', 'finalResult': _finalResult()},
      ]).stream(AnalyzeStreamRequest(messages: [_msg('哈囉')])).toList();
      expect(updates.map((u) => u.kind), [
        AnalysisStreamUpdateKind.started,
        AnalysisStreamUpdateKind.done,
      ]);
      expect(updates.last.guideV3Result!.cards, hasLength(2));
    });

    test('續看重播（started 不帶 guideVersion）也認得 v3 結果', () async {
      final updates = await _client([
        {
          'type': 'analysis.started',
          'runId': 'run_v3',
          'resumed': true,
          'label': '正在取回分析結果',
        },
        {
          'type': 'analysis.progress',
          'phase': 'recovery',
          'label': '連線已恢復',
        },
        {
          'type': 'analysis.done',
          'runId': 'run_v3',
          'finalResult': _finalResult(recovered: true),
          'recovered': true,
        },
      ])
          .stream(AnalyzeStreamRequest(
            analysisRunId: 'run_v3',
            messages: [_msg('哈囉')],
          ))
          .toList();
      final result = updates.last.guideV3Result!;
      expect(result.recovered, isTrue);
      expect(result.partial, isTrue);
      expect(result.cards.single.slot, 1);
      expect(updates.first.guideVersion, isNull);
    });

    test('v3 結果的判讀壞掉：照無效結果處理，不補成五種風格', () async {
      final broken = _finalResult()..['read'] = {'decision': 'nope'};
      expect(
        () => _client([
          _v3Started,
          {'type': 'analysis.done', 'finalResult': broken},
        ]).stream(AnalyzeStreamRequest(messages: [_msg('哈囉')])).toList(),
        throwsA(isA<AnalysisException>().having(
          (e) => e.code,
          'code',
          'INVALID_STREAM_RESULT',
        )),
      );
    });
  });

  group('AnalyzeStreamClient — v3 錯誤的重試規則', () {
    test('沒扣費的錯誤只給重新分析（不續看同一個 run）', () async {
      final error = await _streamError([
        _v3Started,
        {
          'type': 'analysis.error',
          'code': 'GUIDE_V3_NO_CARDS',
          'message': '這次沒有產生可以用的回覆，請重新分析。本次不會扣額度。',
          'recoverable': true,
        },
      ]);
      expect(error.code, 'GUIDE_V3_NO_CARDS');
      expect(error.recoverable, isFalse);
      expect(error.retriesRemaining, 0);
      expect(error.suggestedAction, AnalysisErrorAction.retry);
      expect(error.message, '這次沒有產生可以用的回覆，請重新分析。本次不會扣額度。');
    });

    test('扣費結果不明：可以續看同一個 run', () async {
      final error = await _streamError([
        _v3Started,
        {
          'type': 'analysis.error',
          'code': 'GUIDE_V3_CHARGE_UNCONFIRMED',
          'message': '分析結果還在確認，請稍後重新整理。',
          'recoverable': true,
        },
      ]);
      expect(error.recoverable, isTrue);
      expect(error.retriesRemaining, 1);
    });

    test('扣費後伺服器出錯：可以續看同一個 run', () async {
      final error = await _streamError([
        _v3Started,
        _readEvent,
        _cardEvent(1, 'accept', '那家我也想吃吃看'),
        {
          'type': 'analysis.error',
          'code': 'GUIDE_V3_INTERNAL_ERROR',
          'message': '分析中途出了問題，請稍後重新整理結果。',
          'recoverable': true,
        },
      ]);
      expect(error.recoverable, isTrue);
      expect(error.retriesRemaining, 1);
    });

    test('拒答：不重試、建議改內容', () async {
      final error = await _streamError([
        _v3Started,
        {
          'type': 'analysis.error',
          'code': 'MODEL_REFUSAL',
          'message': '這段對話 AI 沒辦法分析，請調整內容後再試。本次不會扣額度。',
          'recoverable': false,
        },
      ]);
      expect(error.recoverable, isFalse);
      expect(error.retriesRemaining, 0);
      expect(error.suggestedAction, AnalysisErrorAction.wait);
    });

    test('v2 的錯誤照舊：可恢復又沒帶次數時給 1 次', () async {
      final error = await _streamError([
        {'type': 'analysis.started', 'runId': 'run_v2'},
        {
          'type': 'analysis.error',
          'code': 'STREAM_FAILED',
          'message': '分析暫時失敗。',
          'recoverable': true,
        },
      ]);
      expect(error.recoverable, isTrue);
      expect(error.retriesRemaining, 1);
    });
  });
}

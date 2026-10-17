import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Message _msg(String content, {bool fromMe = false}) {
  return Message(
    id: content,
    content: content,
    isFromMe: fromMe,
    timestamp: DateTime(2026, 10, 17, 12),
  );
}

GuideV3Read _read() => GuideV3Read.fromJson({
      'guideVersion': 'v3.4',
      'decision': 'send',
      'light': 'green',
      'judgment': '她有在接你的話。',
      'plannedCards': [
        {'slot': 1, 'task': 'accept', 'locked': false},
        {'slot': 2, 'task': 'tension', 'locked': false},
        {'slot': 3, 'task': 'push', 'locked': false},
      ],
    })!;

Map<String, dynamic> _cardJson(int slot, String task) => {
      'slot': slot,
      'task': task,
      'method': 'reaction',
      'voice': 'default',
      'messages': ['第 $slot 張'],
      'hasInventedDetail': false,
      'hasBlank': false,
    };

GuideV3Card _card(int slot, String task) =>
    GuideV3Card.fromJson(_cardJson(slot, task))!;

GuideV3Result _result({
  List<Map<String, dynamic>>? cards,
  bool recovered = false,
}) =>
    GuideV3Result.fromJson({
      'guideVersion': 'v3.4',
      'read': {
        'guideVersion': 'v3.4',
        'decision': 'send',
        'light': 'green',
        'judgment': '她有在接你的話。',
        'plannedCards': [
          {'slot': 1, 'task': 'accept', 'locked': false},
          {'slot': 2, 'task': 'tension', 'locked': false},
          {'slot': 3, 'task': 'push', 'locked': false},
        ],
      },
      'cards': cards ??
          [
            _cardJson(1, 'accept'),
            _cardJson(2, 'tension'),
            _cardJson(3, 'push'),
          ],
      'partial': recovered,
      if (recovered) 'recovered': true,
      'usage': {'messagesUsed': 1},
    })!;

const _v3Started = AnalysisStreamUpdate.started(
  runId: 'run_v3',
  guideVersion: 'v3.4',
);
const _resumeStarted = AnalysisStreamUpdate.started(runId: 'run_v3');

/// 每次呼叫照腳本吐事件；腳本裡的 Exception 就丟出、Completer 就等。
class _ScriptedClient extends AnalyzeStreamClient {
  _ScriptedClient(this.scripts)
      : super(displayMapper: const AnalysisStreamContentDisplayMapper());

  final List<List<Object>> scripts;
  final List<AnalyzeStreamRequest> requests = [];

  @override
  Stream<AnalysisStreamUpdate> stream(AnalyzeStreamRequest request) async* {
    final index = requests.length;
    requests.add(request);
    for (final step in scripts[index]) {
      if (step is AnalysisStreamUpdate) {
        yield step;
      } else if (step is Exception) {
        throw step;
      } else if (step is Completer<void>) {
        await step.future;
      }
    }
  }
}

ProviderContainer _container(AnalyzeStreamClient client) {
  return ProviderContainer(overrides: [
    analyzeStreamClientProvider.overrideWithValue(client),
  ]);
}

void main() {
  group('StreamingAnalyzeNotifier — v3 任務卡', () {
    test('判讀與卡一到就進狀態，done 換成最終結果，不產生五種風格結果', () async {
      final gate = Completer<void>();
      final client = _ScriptedClient([
        [
          _v3Started,
          AnalysisStreamUpdate.guideV3Read(read: _read(), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Card(
              card: _card(1, 'accept'), runId: 'run_v3'),
          gate,
          AnalysisStreamUpdate.guideV3Card(
              card: _card(2, 'tension'), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Card(
              card: _card(3, 'push'), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Done(result: _result(), runId: 'run_v3'),
        ],
      ]);
      final container = _container(client);
      addTearDown(container.dispose);
      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      final run = notifier.start(messages: [_msg('哈囉')]);
      await Future<void>.delayed(Duration.zero);
      var state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.streamingReport);
      expect(state.isGuideV3Run, isTrue);
      expect(state.guideV3Read?.judgment, '她有在接你的話。');
      expect(state.guideV3Cards.map((c) => c.slot), [1]);
      expect(state.analysisRunId, 'run_v3');

      gate.complete();
      await run;
      state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
      expect(state.result, isNull);
      expect(state.guideV3Result!.cards.map((c) => c.slot), [1, 2, 3]);
      expect(state.guideV3Cards.map((c) => c.slot), [1, 2, 3]);
    });

    test('第一張卡後斷線：自動續看同一個 run，重組只有第一張也不讓看過的卡消失', () async {
      final client = _ScriptedClient([
        [
          _v3Started,
          AnalysisStreamUpdate.guideV3Read(read: _read(), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Card(
              card: _card(1, 'accept'), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Card(
              card: _card(2, 'tension'), runId: 'run_v3'),
          AnalysisException('網路中斷',
              code: 'NETWORK_ERROR',
              suggestedAction: AnalysisErrorAction.retry),
        ],
        [
          _resumeStarted,
          AnalysisStreamUpdate.guideV3Done(
            result: _result(cards: [_cardJson(1, 'accept')], recovered: true),
            runId: 'run_v3',
          ),
        ],
      ]);
      final container = _container(client);
      addTearDown(container.dispose);

      await container
          .read(streamingAnalyzeProvider('conv-1').notifier)
          .start(messages: [_msg('哈囉')]);

      expect(client.requests, hasLength(2));
      expect(client.requests[1].analysisRunId, 'run_v3');
      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
      final result = state.guideV3Result!;
      expect(result.recovered, isTrue);
      expect(result.cards.map((c) => c.slot), [1, 2]);
      expect((result.rawResponse['cards'] as List), hasLength(2));
    });

    test('沒扣費的錯誤：照「重新分析」處理，不留可續看的 run', () async {
      final client = _ScriptedClient([
        [
          _v3Started,
          StreamModeException(
            '這次沒有產生可以用的回覆，請重新分析。本次不會扣額度。',
            code: 'GUIDE_V3_NO_CARDS',
            recoverable: false,
            retriesRemaining: 0,
            suggestedAction: AnalysisErrorAction.retry,
          ),
        ],
      ]);
      final container = _container(client);
      addTearDown(container.dispose);

      await container
          .read(streamingAnalyzeProvider('conv-1').notifier)
          .start(messages: [_msg('哈囉')]);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedBeforeRecommendation);
      expect(state.recommendationPreviewErrorCode, 'GUIDE_V3_NO_CARDS');
      expect(state.recommendationPreviewErrorMessage, contains('本次不會扣額度'));
      expect(state.retriesRemaining, 0);
      expect(client.requests, hasLength(1), reason: '不自動續看');
    });

    test('扣費結果不明：給一次續看，續看帶同一個 run', () async {
      final client = _ScriptedClient([
        [
          _v3Started,
          StreamModeException(
            '分析結果還在確認，請稍後重新整理。',
            code: 'GUIDE_V3_CHARGE_UNCONFIRMED',
            recoverable: true,
            retriesRemaining: 1,
            suggestedAction: AnalysisErrorAction.retry,
          ),
        ],
        [
          _resumeStarted,
          AnalysisStreamUpdate.guideV3Done(
            result: _result(cards: [_cardJson(1, 'accept')], recovered: true),
            runId: 'run_v3',
          ),
        ],
      ]);
      final container = _container(client);
      addTearDown(container.dispose);
      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('哈囉')]);
      var state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(state.retriesRemaining, 1);
      expect(state.streamErrorCode, 'GUIDE_V3_CHARGE_UNCONFIRMED');
      expect(client.requests, hasLength(1), reason: '不自動續看，等他按');

      await notifier.retryStream();
      expect(client.requests[1].analysisRunId, 'run_v3');
      state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
      expect(state.guideV3Result!.cards.single.slot, 1);
    });

    test('續看最後還是失敗：看過的卡留在畫面上', () async {
      final client = _ScriptedClient([
        [
          _v3Started,
          AnalysisStreamUpdate.guideV3Read(read: _read(), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Card(
              card: _card(1, 'accept'), runId: 'run_v3'),
          AnalysisException('網路中斷',
              code: 'NETWORK_ERROR',
              suggestedAction: AnalysisErrorAction.retry),
        ],
        [
          _resumeStarted,
          AnalysisException('網路中斷',
              code: 'NETWORK_ERROR', suggestedAction: AnalysisErrorAction.retry)
        ],
        [
          _resumeStarted,
          AnalysisException('網路中斷',
              code: 'NETWORK_ERROR', suggestedAction: AnalysisErrorAction.retry)
        ],
      ]);
      final container = _container(client);
      addTearDown(container.dispose);

      await container
          .read(streamingAnalyzeProvider('conv-1').notifier)
          .start(messages: [_msg('哈囉')]);

      expect(client.requests, hasLength(3));
      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(state.guideV3Cards.map((c) => c.slot), [1]);
      expect(state.guideV3Read, isNotNull);
      expect(state.retriesRemaining, 1);
    });

    test('新的一次分析清掉上一次的 v3 狀態', () async {
      final client = _ScriptedClient([
        [
          _v3Started,
          AnalysisStreamUpdate.guideV3Read(read: _read(), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Card(
              card: _card(1, 'accept'), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Done(
            result: _result(cards: [_cardJson(1, 'accept')]),
            runId: 'run_v3',
          ),
        ],
        [Completer<void>()],
      ]);
      final container = _container(client);
      addTearDown(container.dispose);
      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);
      await notifier.start(messages: [_msg('哈囉')]);
      unawaited(notifier.start(messages: [_msg('再一次')]));
      await Future<void>.delayed(Duration.zero);
      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.connecting);
      expect(state.isGuideV3Run, isFalse);
      expect(state.guideV3Read, isNull);
      expect(state.guideV3Cards, isEmpty);
      expect(state.guideV3Result, isNull);
    });
  });
}

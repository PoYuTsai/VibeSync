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

ProviderContainer _container(
  AnalyzeStreamClient client, {
  List<String>? silenced,
}) {
  return ProviderContainer(overrides: [
    analyzeStreamClientProvider.overrideWithValue(client),
    if (silenced != null)
      analysisFollowUpSilencerProvider.overrideWithValue(
        (partnerId) async => silenced.add(partnerId),
      ),
  ]);
}

GuideV3Result _decisionResult(String decision) => GuideV3Result.fromJson({
      'guideVersion': 'v3.6',
      'read': {
        'guideVersion': 'v3.6',
        'decision': decision,
        'light': decision == 'care' ? null : 'red',
        'judgment': decision == 'care' ? '' : '她說了不要。',
        if (decision == 'care') 'careMessage': '先把安全放在第一位。',
        'plannedCards': const [],
      },
      'cards': const [],
      'partial': false,
      'usage': {'messagesUsed': decision == 'care' ? 0 : 1},
    })!;

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

    test('F04：存檔用的字數基準不含最後面他傳的（上限內）', () async {
      final client = _ScriptedClient([
        [Completer<void>()],
      ]);
      final container = _container(client);
      addTearDown(container.dispose);
      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);
      unawaited(notifier.start(messages: [
        _msg('週末要幹嘛'),
        _msg('還沒想耶', fromMe: true),
      ]));
      await Future<void>.delayed(Duration.zero);
      expect(notifier.lastPayloadCharCount, 5);
      expect(client.requests.single.messages, hasLength(2),
          reason: '他傳的照樣送去分析');
    });

    test('只分析最後 2,000 字（Onboarding 第 15 步）：存檔用的字數基準照呼叫端給的整段，送出的只有尾段', () async {
      final client = _ScriptedClient([
        [Completer<void>()],
      ]);
      final container = _container(client);
      addTearDown(container.dispose);
      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);
      unawaited(notifier.start(
        messages: [_msg('最後那段')],
        nextCharBaseline: 2400,
        analyzedMessageCount: 5,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(notifier.lastPayloadCharCount, 2400,
          reason: '尾段只有 4 字；基準要存整段的，下次才不會把跳過的那段算進去');
      final request = client.requests.single;
      expect(request.messages, hasLength(1));
      expect(request.previousAnalyzedCount, isNull);
      expect(request.previousAnalyzedCharCount, isNull);
      expect(
        container.read(streamingAnalyzeProvider('conv-1')).analyzedMessageCount,
        5,
      );
    });

    test('「為什麼這樣回」（Bruce 2026-10-19 路線二）：一到就進狀態，done 時併進結果與存檔的原樣', () async {
      final gate = Completer<void>();
      final client = _ScriptedClient([
        [
          _v3Started,
          AnalysisStreamUpdate.guideV3Read(read: _read(), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Card(
              card: _card(1, 'accept'), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Card(
              card: _card(2, 'tension'), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Card(
              card: _card(3, 'push'), runId: 'run_v3'),
          const AnalysisStreamUpdate.guideV3CardExplain(
            explain: GuideV3CardExplain(card: 2, text: '第二張的說明'),
            runId: 'run_v3',
          ),
          const AnalysisStreamUpdate.guideV3CardExplain(
            explain: GuideV3CardExplain(card: 1, text: '第一張的說明'),
            runId: 'run_v3',
          ),
          // 同一張送兩次：留第一次的。
          const AnalysisStreamUpdate.guideV3CardExplain(
            explain: GuideV3CardExplain(card: 1, text: '重複'),
            runId: 'run_v3',
          ),
          gate,
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
      expect(state.guideV3CardExplains, {2: '第二張的說明', 1: '第一張的說明'});

      gate.complete();
      await run;
      state = container.read(streamingAnalyzeProvider('conv-1'));
      final result = state.guideV3Result!;
      expect(result.cardExplains, {1: '第一張的說明', 2: '第二張的說明'});
      expect(result.rawResponse[guideV3CardExplainsKey], [
        {'card': 1, 'text': '第一張的說明'},
        {'card': 2, 'text': '第二張的說明'},
      ]);
      // 存檔的原樣重新解析，說明照樣在（重開畫面看得到）。
      expect(
        GuideV3Result.fromJson(result.rawResponse)!.cardExplains,
        result.cardExplains,
      );
    });

    test('沒有說明（兩段式沒開）：結果照伺服器原樣，不多欄位', () async {
      final client = _ScriptedClient([
        [
          _v3Started,
          AnalysisStreamUpdate.guideV3Read(read: _read(), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Card(
              card: _card(1, 'accept'), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Done(result: _result(), runId: 'run_v3'),
        ],
      ]);
      final container = _container(client);
      addTearDown(container.dispose);

      await container
          .read(streamingAnalyzeProvider('conv-1').notifier)
          .start(messages: [_msg('哈囉')]);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.guideV3Result!.cardExplains, isEmpty);
      expect(
        state.guideV3Result!.rawResponse.containsKey(guideV3CardExplainsKey),
        isFalse,
      );
    });

    group('跟進提醒（P1 安全修正；主審第 1 輪 finding 1）：判成關心或停時 notifier 自己收回，不靠分析頁', () {
      Future<List<String>> run(
        List<Object> script, {
        String? partnerId = 'partner-1',
      }) async {
        final silenced = <String>[];
        final container =
            _container(_ScriptedClient([script]), silenced: silenced);
        addTearDown(container.dispose);
        await container.read(streamingAnalyzeProvider('conv-1').notifier).start(
          messages: [_msg('哈囉')],
          conversationPartnerId: partnerId,
        );
        await Future<void>.delayed(Duration.zero);
        return silenced;
      }

      test('關心與停：判讀一到就收回這位對象的提醒；同一個 run 到 done 也只叫一次', () async {
        for (final decision in ['care', 'stop']) {
          final result = _decisionResult(decision);
          final silenced = await run([
            _v3Started,
            AnalysisStreamUpdate.guideV3Read(read: result.read, runId: 'r'),
            AnalysisStreamUpdate.guideV3Done(result: result, runId: 'r'),
          ]);
          expect(silenced, ['partner-1'], reason: decision);
        }
      });

      test('判讀還沒送到就斷了、只有 done 帶決定：done 時收回', () async {
        final result = _decisionResult('stop');
        expect(
          await run([
            _v3Started,
            AnalysisStreamUpdate.guideV3Done(result: result, runId: 'r'),
          ]),
          ['partner-1'],
        );
      });

      test('先別回、出卡、沒綁對象：不叫', () async {
        final hold = _decisionResult('hold');
        expect(
          await run([
            _v3Started,
            AnalysisStreamUpdate.guideV3Read(read: hold.read, runId: 'r'),
            AnalysisStreamUpdate.guideV3Done(result: hold, runId: 'r'),
          ]),
          isEmpty,
        );
        expect(
          await run([
            _v3Started,
            AnalysisStreamUpdate.guideV3Read(read: _read(), runId: 'r'),
            AnalysisStreamUpdate.guideV3Done(result: _result(), runId: 'r'),
          ]),
          isEmpty,
        );
        final care = _decisionResult('care');
        expect(
          await run([
            _v3Started,
            AnalysisStreamUpdate.guideV3Read(read: care.read, runId: 'r'),
            AnalysisStreamUpdate.guideV3Done(result: care, runId: 'r'),
          ], partnerId: null),
          isEmpty,
        );
      });
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
      expect(state.guideV3CardExplains, isEmpty);
    });

    test('等待（Eric 2026-10-18）：v3 的 started 不停在「開始完整分析」，改輪播 v3 的句子；寫卡進度到了就接手',
        () async {
      final readDone = Completer<void>();
      final cardsReady = Completer<void>();
      final client = _ScriptedClient([
        [
          // 伺服器的 started 沒帶字，客戶端補預設字（analyze_stream_client）。
          const AnalysisStreamUpdate.started(
            runId: 'run_v3',
            label: '開始完整分析',
            guideVersion: 'v3.4',
          ),
          readDone,
          const AnalysisStreamUpdate.progress(
            runId: 'run_v3',
            label: '看完了，正在寫回覆',
          ),
          cardsReady,
          AnalysisStreamUpdate.guideV3Read(read: _read(), runId: 'run_v3'),
          AnalysisStreamUpdate.guideV3Done(result: _result(), runId: 'run_v3'),
        ],
      ]);
      final container = _container(client);
      addTearDown(container.dispose);
      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      final run = notifier.start(messages: [_msg('哈囉')]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      var state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.connecting);
      expect(state.isGuideV3Run, isTrue);
      expect(state.streamProgressLabel, '正在讀這段對話');
      expect(state.streamProgressDetail, '看你們聊到哪、她最後怎麼接。');

      await Future<void>.delayed(const Duration(milliseconds: 3200));
      state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.streamProgressLabel, '正在看她現在冷還熱');
      expect(
        '${state.streamProgressLabel}${state.streamProgressDetail}',
        isNot(contains('關係階段')),
        reason: 'v3 沒有關係階段',
      );

      readDone.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.streamProgressLabel, '看完了，正在寫回覆');
      expect(state.streamProgressDetail, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 3200));
      state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.streamProgressLabel, '看完了，正在寫回覆', reason: '伺服器的進度不會被本地輪播蓋掉');

      cardsReady.complete();
      await run;
      state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
    });
  });
}

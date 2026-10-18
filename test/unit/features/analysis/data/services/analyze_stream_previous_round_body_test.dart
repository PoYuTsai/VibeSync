// 上一輪脈絡進 wire payload（Eric 2026-10-18）：有才帶 previousRound，沒有時整個
// body 跟今天一模一樣；請求組裝器把 resolver 的結果原樣交出去。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/application/ports/conversation_memory_port.dart';
import 'package:vibesync/features/analysis/data/services/analysis_transport_support.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/domain/entities/previous_round_context.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

class _NoopMemory implements ConversationMemoryPort {
  @override
  String? persistedHistoricalSummary(Conversation conversation) => null;

  @override
  Future<String> formatEphemeralSummary(
    Conversation conversation,
    int olderRounds,
  ) async =>
      '';

  @override
  List<Message> clipToRecentRounds(List<Message> messages, int maxRounds) =>
      messages;

  @override
  int get maxRecentRounds => 15;

  @override
  int get minRoundsPerSummary => 3;
}

void main() {
  final now = DateTime(2026, 10, 18);
  final messages = [
    Message(id: 'm1', content: '好啊，那就週六', isFromMe: false, timestamp: now),
  ];
  const previousRound = PreviousRoundContext(
    decision: 'hold',
    light: 'yellow',
    judgment: '她只回了貼圖',
    sentCard: '那週六去吃早午餐？\n我知道一間不錯的',
    messages: [
      PreviousRoundMessage(isFromMe: true, content: '週末有空嗎'),
      PreviousRoundMessage(isFromMe: false, content: '應該在家耍廢'),
    ],
  );

  test('有上一輪才帶 previousRound，其餘欄位跟沒帶時一模一樣', () {
    final without = AnalyzeStreamClient.buildStreamBody(
      AnalyzeStreamRequest(messages: messages),
      const AnalysisEntitlementContext(),
    );
    final withRound = AnalyzeStreamClient.buildStreamBody(
      AnalyzeStreamRequest(messages: messages, previousRound: previousRound),
      const AnalysisEntitlementContext(),
    );
    expect(without.containsKey('previousRound'), isFalse);
    expect(withRound['previousRound'], {
      'decision': 'hold',
      'light': 'yellow',
      'judgment': '她只回了貼圖',
      'sentCard': '那週六去吃早午餐？\n我知道一間不錯的',
      'messages': [
        {'isFromMe': true, 'content': '週末有空嗎'},
        {'isFromMe': false, 'content': '應該在家耍廢'},
      ],
    });
    expect(Map.of(withRound)..remove('previousRound'), without);
  });

  test('沒有的欄位不送（燈號、判讀、複製的卡）', () {
    const minimal = PreviousRoundContext(
      decision: 'send',
      messages: [PreviousRoundMessage(isFromMe: false, content: '你呢')],
    );
    expect(minimal.toJson(), {
      'decision': 'send',
      'messages': [
        {'isFromMe': false, 'content': '你呢'},
      ],
    });
    expect(minimal.charCount, 2);
    expect(previousRound.charCount, 6 + 18 + 5 + 6);
  });

  test('請求組裝器把上一輪原樣交出去；沒注入 resolver 就沒有', () async {
    final conversation = Conversation(
      id: 'c-1',
      name: '小雲',
      messages: messages,
      createdAt: now,
      updatedAt: now,
      partnerId: 'p-1',
    );
    Conversation? asked;
    final preparer = AnalysisRunPreparer(
      memory: _NoopMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
      resolvePreviousRound: (c) {
        asked = c;
        return previousRound;
      },
    );
    final gate = preparer.gate(conversation: conversation);
    final preparation = await preparer.assemble(
      conversation: conversation,
      gate: gate,
    );
    expect(asked, same(conversation));
    expect(preparation.previousRound, same(previousRound));

    final plain = AnalysisRunPreparer(
      memory: _NoopMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
    );
    final plainPreparation = await plain.assemble(
      conversation: conversation,
      gate: plain.gate(conversation: conversation),
    );
    expect(plainPreparation.previousRound, isNull);
  });
}

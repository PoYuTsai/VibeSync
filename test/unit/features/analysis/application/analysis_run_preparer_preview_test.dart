// 額度那一行的同步預覽（主審 r1 P2）：跟實際組請求同一套訊息切片——有歷史摘要
// 時只送最近 15 輪——算出來的計費則數才會跟按下去時一樣。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/data/services/conversation_memory_adapter.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

/// [rounds] 輪，每輪他一則、她一則，各 10 字，最後是她。
Conversation _rounds(int rounds, {List<ConversationSummary>? summaries}) {
  final messages = <Message>[];
  for (var i = 1; i <= rounds; i++) {
    final n = i.toString().padLeft(2, '0');
    messages
      ..add(Message(
        id: 'me-$i',
        content: '第$n輪他說的那些話',
        isFromMe: true,
        timestamp: DateTime(2026, 10, 18, 9, i),
      ))
      ..add(Message(
        id: 'her-$i',
        content: '第$n輪她回的那些話',
        isFromMe: false,
        timestamp: DateTime(2026, 10, 18, 10, i),
      ));
  }
  return Conversation(
    id: 'c-$rounds',
    name: '小雲',
    messages: messages,
    createdAt: DateTime(2026, 10, 18),
    updatedAt: DateTime(2026, 10, 18),
    currentRound: rounds,
    summaries: summaries,
  );
}

AnalysisRunPreparer _preparer() => AnalysisRunPreparer(
      memory: ConversationMemoryAdapter(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
    );

Future<void> _expectPreviewMatchesAssemble(Conversation conversation) async {
  final preparer = _preparer();
  final gate = preparer.gate(conversation: conversation);
  final preview = preparer.previewRequestMessages(
    conversation: conversation,
    gate: gate,
  );
  final preparation = await preparer.assemble(
    conversation: conversation,
    gate: gate,
  );
  expect(
    [for (final m in preview) m.id],
    [for (final m in preparation.requestMessages) m.id],
  );
}

void main() {
  test('主審的例子：25 輪、每輪各 10 字，有摘要只送最近 15 輪，算 8 則不是 10 則', () async {
    final conversation = _rounds(25);
    final preparer = _preparer();
    final preview = preparer.previewRequestMessages(
      conversation: conversation,
      gate: preparer.gate(conversation: conversation),
    );
    expect(preview, hasLength(30));
    expect(preview.first.id, 'me-11');
    expect(
      MessageCalculator.previewAnalysisRequest(preview).band.units,
      8,
    );
    await _expectPreviewMatchesAssemble(conversation);
  });

  test('輪數不夠做摘要：整段照送', () async {
    final conversation = _rounds(19);
    final preparer = _preparer();
    final preview = preparer.previewRequestMessages(
      conversation: conversation,
      gate: preparer.gate(conversation: conversation),
    );
    expect(preview, hasLength(38));
    await _expectPreviewMatchesAssemble(conversation);
  });

  test('有存好的摘要：就算輪數不多也只送最近 15 輪', () async {
    final conversation = _rounds(18, summaries: [
      ConversationSummary(
        id: 's-1',
        roundsCovered: 3,
        content: '前三輪在聊週末',
        keyTopics: const [],
        sharedInterests: const [],
        relationshipStage: '',
        createdAt: DateTime(2026, 10, 18),
      ),
    ]);
    final preparer = _preparer();
    final preview = preparer.previewRequestMessages(
      conversation: conversation,
      gate: preparer.gate(conversation: conversation),
    );
    expect(preview, hasLength(30));
    expect(preview.first.id, 'me-4');
    await _expectPreviewMatchesAssemble(conversation);
  });
}

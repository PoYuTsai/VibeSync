import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/services/analysis_fragment_policy.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Conversation _conversation({
  List<Message>? messages,
  String? snapshotJson,
  int? analyzedMessageCount,
  int? enthusiasmScore,
}) {
  return Conversation(
    id: 'fragment-policy-test',
    name: '小雲',
    messages: messages ?? const <Message>[],
    createdAt: DateTime(2026, 7, 16),
    updatedAt: DateTime(2026, 7, 16),
    lastAnalysisSnapshotJson: snapshotJson,
    lastAnalyzedMessageCount: analyzedMessageCount,
    lastEnthusiasmScore: enthusiasmScore,
  );
}

Message _message(String id) => Message(
      id: id,
      content: '訊息 $id',
      isFromMe: false,
      timestamp: DateTime(2026, 7, 16),
    );

void main() {
  group('AnalysisFragmentPolicy', () {
    test('尚未分析的空白或草稿片段可以繼續加入同批內容', () {
      expect(
        AnalysisFragmentPolicy.canAppendInput(_conversation()),
        isTrue,
      );
      expect(
        AnalysisFragmentPolicy.canAppendInput(
          _conversation(messages: [_message('draft')]),
        ),
        isTrue,
      );
    });

    test('只要有成功分析證據，後續輸入就必須另開片段', () {
      expect(
        AnalysisFragmentPolicy.canAppendInput(
          _conversation(snapshotJson: '{"enthusiasm":{"score":45}}'),
        ),
        isFalse,
      );
      expect(
        AnalysisFragmentPolicy.canAppendInput(
          _conversation(analyzedMessageCount: 1),
        ),
        isFalse,
      );
      expect(
        AnalysisFragmentPolicy.canAppendInput(
          _conversation(enthusiasmScore: 45),
        ),
        isFalse,
      );
    });

    test('舊版已疊加待分析訊息也不得再往同一逐字稿追加', () {
      final legacyStackedConversation = _conversation(
        messages: [_message('analyzed'), _message('pending')],
        snapshotJson: '{"enthusiasm":{"score":45}}',
        analyzedMessageCount: 1,
        enthusiasmScore: 45,
      );

      expect(
        AnalysisFragmentPolicy.canAppendInput(legacyStackedConversation),
        isFalse,
      );
      expect(legacyStackedConversation.messages, hasLength(2),
          reason: '舊資料只保留相容，不由 client 猜測邊界或自動切割。');
    });
  });
}

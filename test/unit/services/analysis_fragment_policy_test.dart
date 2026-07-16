import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/services/analysis_fragment_policy.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Conversation _conversation({
  List<Message>? messages,
  String? snapshotJson,
  int? analyzedMessageCount,
  int? enthusiasmScore,
  List<ConversationSummary>? summaries,
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
    summaries: summaries,
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

    test('確認視窗開啟期間若片段完成，回來時必須另建片段', () {
      final conversation = _conversation(messages: [_message('draft')]);
      expect(
        AnalysisFragmentPolicy.mustCreateNewFragmentForImport(
          conversation: conversation,
          hasLoadedAnalysisResult: false,
        ),
        isFalse,
      );

      conversation.lastAnalyzedMessageCount = 1;

      expect(
        AnalysisFragmentPolicy.mustCreateNewFragmentForImport(
          conversation: conversation,
          hasLoadedAnalysisResult: false,
        ),
        isTrue,
      );
    });

    test('畫面已載入完成分析時也必須另建片段', () {
      expect(
        AnalysisFragmentPolicy.mustCreateNewFragmentForImport(
          conversation: _conversation(messages: [_message('draft')]),
          hasLoadedAnalysisResult: true,
        ),
        isTrue,
      );
    });

    test('重新匯入一批內容會整批取代，不會往下疊加', () {
      final conversation = _conversation(
        messages: [_message('old-1'), _message('old-2')],
      );

      AnalysisFragmentPolicy.replaceDraftBatch(
        conversation: conversation,
        messages: [_message('new-1')],
      );
      expect(
        conversation.messages.map((message) => message.id),
        ['new-1'],
      );

      AnalysisFragmentPolicy.replaceDraftBatch(
        conversation: conversation,
        messages: [_message('new-2'), _message('new-3')],
      );
      expect(
        conversation.messages.map((message) => message.id),
        ['new-2', 'new-3'],
      );
    });

    test('整批取代時會清掉舊批次衍生的摘要', () {
      final conversation = _conversation(
        messages: [_message('old')],
        summaries: [
          ConversationSummary(
            id: 'old-summary',
            roundsCovered: 20,
            content: '上一批聊天的摘要',
            keyTopics: const ['舊內容'],
            sharedInterests: const [],
            relationshipStage: 'unknown',
            createdAt: DateTime(2026, 7, 16),
          ),
        ],
      );

      AnalysisFragmentPolicy.replaceDraftBatch(
        conversation: conversation,
        messages: [_message('new')],
      );

      expect(conversation.messages.single.id, 'new');
      expect(conversation.summaries, isNull);
    });

    test('完成分析的片段不能被整批取代', () {
      final conversation = _conversation(
        messages: [_message('analyzed')],
        analyzedMessageCount: 1,
      );

      expect(
        () => AnalysisFragmentPolicy.replaceDraftBatch(
          conversation: conversation,
          messages: [_message('new')],
        ),
        throwsStateError,
      );
      expect(conversation.messages.single.id, 'analyzed');
    });
  });
}

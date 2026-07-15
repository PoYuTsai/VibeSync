import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

AnalysisRecord _record() => AnalysisRecord(
      id: 'record-1',
      ownerUserId: 'owner-1',
      conversationId: 'conversation-1',
      partnerId: 'partner-1',
      subjectName: '小雲',
      segmentStart: 2,
      segmentEnd: 3,
      createdAt: DateTime.utc(2026, 7, 15, 12),
      messages: [
        AnalysisRecordMessage.fromMessage(
          Message(
            id: 'message-2',
            content: '你週末有空嗎？',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 15, 11),
            enthusiasmScore: 78,
            quotedReplyPreview: '上次說到的展覽',
            quotedReplyPreviewIsFromMe: true,
          ),
        ),
      ],
      analysisSnapshotJson: '{"finalRecommendation":"順勢約她"}',
      analyzedContentRevision: 'revision-1',
      completionKey: 'run-1',
      sourcePlatform: 'Threads',
      enthusiasmScore: 78,
      gameStageLabel: '建立連結',
    );

void main() {
  test('JSON round trip preserves owner, boundary, source, and quoted message',
      () {
    final decoded = AnalysisRecord.tryDecode(_record().encode());

    expect(decoded, isNotNull);
    expect(decoded!.ownerUserId, 'owner-1');
    expect(decoded.segmentStart, 2);
    expect(decoded.segmentEnd, 3);
    expect(decoded.analyzedContentRevision, 'revision-1');
    expect(decoded.completionKey, 'run-1');
    expect(decoded.sourcePlatform, 'Threads');
    expect(decoded.messages.single.enthusiasmScore, 78);
    expect(decoded.messages.single.quotedReplyPreview, '上次說到的展覽');
    expect(decoded.messages.single.quotedReplyPreviewIsFromMe, isTrue);
    expect(decoded.messages.single.toMessage().quotedReplyPreview, '上次說到的展覽');
  });

  test('missing identity/revision fields or inconsistent fragment is rejected',
      () {
    final json = jsonDecode(_record().encode()) as Map<String, dynamic>;
    expect(
      AnalysisRecord.tryDecode(jsonEncode({...json}..remove('completionKey'))),
      isNull,
    );
    expect(
      AnalysisRecord.tryDecode(
        jsonEncode({...json, 'analyzedContentRevision': ' '}),
      ),
      isNull,
    );
    expect(
      AnalysisRecord.tryDecode(jsonEncode({...json, 'segmentEnd': 4})),
      isNull,
    );
    expect(AnalysisRecord.tryDecode('not-json{'), isNull);
  });

  test('preview prefers latest incoming message and truncates long text', () {
    final longRecord = AnalysisRecord(
      id: 'record-2',
      ownerUserId: 'owner-1',
      conversationId: 'conversation-1',
      partnerId: null,
      subjectName: '小雲',
      segmentStart: 0,
      segmentEnd: 2,
      createdAt: DateTime.utc(2026, 7, 15),
      messages: [
        AnalysisRecordMessage.fromMessage(
          Message(
            id: 'incoming',
            content: '這是一段超過三十二個字而且應該要被截斷的對方訊息，列表只需要顯示摘要即可',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 15),
          ),
        ),
        AnalysisRecordMessage.fromMessage(
          Message(
            id: 'mine',
            content: '我的回覆',
            isFromMe: true,
            timestamp: DateTime.utc(2026, 7, 15, 0, 1),
          ),
        ),
      ],
      analysisSnapshotJson: '{}',
      analyzedContentRevision: 'revision-2',
      completionKey: 'run-2',
      sourcePlatform: null,
      enthusiasmScore: 50,
      gameStageLabel: 'stage',
    );

    expect(longRecord.previewText, endsWith('…'));
    expect(longRecord.previewText, isNot(contains('我的回覆')));
    expect(longRecord.archiveTitle, startsWith('她說：「'));
  });
}

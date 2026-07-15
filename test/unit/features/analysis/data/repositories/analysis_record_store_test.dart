import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis/data/repositories/analysis_record_store.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Conversation _conversation({
  required String id,
  String owner = 'owner-1',
  String? partnerId = 'partner-1',
  int messageCount = 2,
}) {
  return Conversation(
    id: id,
    name: '小雲',
    messages: List.generate(messageCount, _message),
    createdAt: DateTime.utc(2026, 7, 15),
    updatedAt: DateTime.utc(2026, 7, 15),
    ownerUserId: owner,
    partnerId: partnerId,
  );
}

Message _message(int index) => Message(
      id: 'message-$index',
      content: '訊息 $index',
      isFromMe: index.isEven,
      timestamp: DateTime.utc(2026, 7, 15, 10, index),
      enthusiasmScore: 40 + index,
      quotedReplyPreview: index == 1 ? '被引用的原話' : null,
      quotedReplyPreviewIsFromMe: index == 1 ? true : null,
    );

Future<AnalysisRecordSaveResult> _save(
  AnalysisRecordStore store,
  Conversation conversation, {
  required String completionKey,
  required int previousCount,
  int? analyzedCount,
  DateTime? completedAt,
  String owner = 'owner-1',
  String snapshot = '{"finalRecommendation":"先接住她的話題"}',
}) {
  final count = analyzedCount ?? conversation.messages.length;
  return store.saveSuccessfulAnalysis(
    ownerUserId: owner,
    conversation: conversation,
    completionKey: completionKey,
    runStartPreviousCount: previousCount,
    analyzedMessageCount: count,
    analyzedContentRevision: conversationContentRevision(
      conversation,
      messageCount: count,
    ),
    analysisSnapshotJson: snapshot,
    enthusiasmScore: 72,
    gameStageLabel: '建立連結',
    completedAt: completedAt,
  );
}

void main() {
  group('HiveAnalysisRecordStore', () {
    late Box<dynamic> box;
    late HiveAnalysisRecordStore store;

    setUp(() async {
      Hive.init('./.dart_tool/test_hive_analysis_record');
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      box = await Hive.openBox<dynamic>('analysis_record_$timestamp');
      store = HiveAnalysisRecordStore(() => box);
    });

    tearDown(() async {
      await box.deleteFromDisk();
    });

    test('first success creates current from 0 even on same-count hydrate',
        () async {
      final conversation = _conversation(id: 'conversation-1');
      await store.setConversationSource(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
        sourcePlatform: 'Omi',
      );

      final result = await _save(
        store,
        conversation,
        completionKey: 'run-1',
        previousCount: 2,
        completedAt: DateTime.utc(2026, 7, 15, 12),
      );

      expect(result.status, AnalysisRecordSaveStatus.createdCurrent);
      expect(result.record!.segmentStart, 0);
      expect(result.record!.segmentEnd, 2);
      expect(result.record!.sourcePlatform, 'Omi');
      expect(result.record!.messages.map((message) => message.content), [
        '訊息 0',
        '訊息 1',
      ]);
      expect(result.record!.messages.last.quotedReplyPreview, '被引用的原話');
      expect(result.record!.messages.last.quotedReplyPreviewIsFromMe, isTrue);
      expect(result.record!.messages.last.enthusiasmScore, 41);
      expect(
        store
            .currentFor(
              ownerUserId: 'owner-1',
              conversationId: conversation.id,
            )
            ?.id,
        result.record!.id,
      );
      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ),
        isEmpty,
      );
      expect(
        box.keys.whereType<String>(),
        contains(startsWith('analysis_record_v2:owner-1:conversation-1:')),
      );
      expect(
        box.keys,
        contains('analysis_record_state_v1:owner-1:conversation-1'),
      );

      // The record owns immutable values rather than the live Message object.
      conversation.messages.first.enthusiasmScore = 99;
      conversation.messages = List.generate(2, (index) => _message(index + 10));
      expect(result.record!.messages.first.content, '訊息 0');
      expect(result.record!.messages.first.enthusiasmScore, 40);
    });

    test('appended success advances current and exposes old current as archive',
        () async {
      final conversation = _conversation(id: 'conversation-1');
      final first = await _save(
        store,
        conversation,
        completionKey: 'run-1',
        previousCount: 0,
        completedAt: DateTime.utc(2026, 7, 15, 10),
      );
      conversation.messages = List.generate(4, _message);

      final second = await _save(
        store,
        conversation,
        completionKey: 'run-2',
        previousCount: 2,
        completedAt: DateTime.utc(2026, 7, 15, 11),
      );

      expect(second.status, AnalysisRecordSaveStatus.advancedCurrent);
      expect(second.archivedPrevious?.id, first.record!.id);
      expect(second.record!.id, isNot(first.record!.id));
      expect(second.record!.segmentStart, 2);
      expect(second.record!.segmentEnd, 4);
      expect(second.record!.messages.map((message) => message.content), [
        '訊息 2',
        '訊息 3',
      ]);
      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ).map((record) => record.id),
        [first.record!.id],
      );
    });

    test('validated current boundary wins a stale caller baseline', () async {
      final conversation = _conversation(id: 'conversation-stale-baseline');
      await _save(
        store,
        conversation,
        completionKey: 'boundary-run-1',
        previousCount: 0,
      );
      conversation.messages = List.generate(5, _message);

      final advanced = await _save(
        store,
        conversation,
        completionKey: 'boundary-run-2',
        previousCount: 0,
      );

      expect(advanced.status, AnalysisRecordSaveStatus.advancedCurrent);
      expect(advanced.record?.segmentStart, 2);
      expect(advanced.record?.segmentEnd, 5);
      expect(
        advanced.record?.messages.map((message) => message.content),
        ['訊息 2', '訊息 3', '訊息 4'],
      );
    });

    test(
        'same completion replays only identical snapshot; refresh replaces current',
        () async {
      final conversation = _conversation(id: 'conversation-1');
      final first = await _save(
        store,
        conversation,
        completionKey: 'run-1',
        previousCount: 0,
      );
      final keyCount = box.length;

      final replay = await _save(
        store,
        conversation,
        completionKey: 'run-1',
        previousCount: 0,
      );
      expect(replay.status, AnalysisRecordSaveStatus.replayed);
      expect(box.length, keyCount);

      final collidingRefresh = await _save(
        store,
        conversation,
        completionKey: 'run-1',
        previousCount: 0,
        snapshot: '{"different":"fresh result without run id"}',
      );
      expect(
        collidingRefresh.status,
        AnalysisRecordSaveStatus.replacedCurrent,
      );
      expect(collidingRefresh.record!.id, first.record!.id);
      expect(
        collidingRefresh.record!.analysisSnapshotJson,
        contains('fresh result without run id'),
      );
      expect(box.length, keyCount);

      final refresh = await _save(
        store,
        conversation,
        completionKey: 'run-refresh',
        previousCount: 2,
        snapshot: '{"refresh":true}',
      );
      expect(refresh.status, AnalysisRecordSaveStatus.replacedCurrent);
      expect(refresh.record!.id, first.record!.id);
      expect(refresh.record!.completionKey, 'run-refresh');
      expect(refresh.record!.analysisSnapshotJson, '{"refresh":true}');
      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ),
        isEmpty,
      );
    });

    test('reused completion key cannot replay or overwrite a newer fragment',
        () async {
      final conversation = _conversation(id: 'conversation-reused-run');
      final first = await _save(
        store,
        conversation,
        completionKey: 'stream-preview',
        previousCount: 0,
      );
      conversation.messages = List.generate(3, _message);

      final second = await _save(
        store,
        conversation,
        completionKey: 'stream-preview',
        previousCount: 2,
      );

      expect(second.status, AnalysisRecordSaveStatus.advancedCurrent);
      expect(second.record!.id, isNot(first.record!.id));
      expect(second.record!.segmentStart, 2);
      expect(
        store
            .listArchived(
              ownerUserId: 'owner-1',
              conversationIds: [conversation.id],
            )
            .single
            .id,
        first.record!.id,
      );
    });

    test('records have no FIFO and archived listing is newest first', () async {
      final conversation = _conversation(id: 'conversation-1', messageCount: 1);
      for (var count = 1; count <= 8; count++) {
        conversation.messages = List.generate(count, _message);
        await _save(
          store,
          conversation,
          completionKey: 'run-$count',
          previousCount: count - 1,
          completedAt: DateTime.utc(2026, 7, 15, 10, count),
        );
      }

      final archived = store.listArchived(
        ownerUserId: 'owner-1',
        conversationIds: [conversation.id],
      );
      expect(archived, hasLength(7));
      expect(archived.first.completionKey, 'run-7');
      expect(archived.last.completionKey, 'run-1');
      expect(
        archived.any((record) => record.completionKey == 'run-8'),
        isFalse,
      );
    });

    test('archived listing spans requested conversations but isolates owner',
        () async {
      final first = _conversation(id: 'conversation-1');
      await _save(
        store,
        first,
        completionKey: 'first-1',
        previousCount: 0,
        completedAt: DateTime.utc(2026, 7, 15, 9),
      );
      first.messages = List.generate(3, _message);
      await _save(
        store,
        first,
        completionKey: 'first-2',
        previousCount: 2,
      );

      final second = _conversation(id: 'conversation-2');
      await _save(
        store,
        second,
        completionKey: 'second-1',
        previousCount: 0,
        completedAt: DateTime.utc(2026, 7, 15, 10),
      );
      second.messages = List.generate(3, _message);
      await _save(
        store,
        second,
        completionKey: 'second-2',
        previousCount: 2,
      );

      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: ['conversation-1', 'conversation-2'],
        ).map((record) => record.completionKey),
        ['second-1', 'first-1'],
      );
      expect(
        store.listArchived(
          ownerUserId: 'owner-2',
          conversationIds: ['conversation-1', 'conversation-2'],
        ),
        isEmpty,
      );
    });

    test('blank/mismatched owner, stale revision, and invalid range reject',
        () async {
      final conversation = _conversation(id: 'conversation-1');
      final blankOwner = await _save(
        store,
        conversation,
        owner: ' ',
        completionKey: 'run-1',
        previousCount: 0,
      );
      final otherOwner = await _save(
        store,
        conversation,
        owner: 'owner-2',
        completionKey: 'run-2',
        previousCount: 0,
      );
      final stale = await store.saveSuccessfulAnalysis(
        ownerUserId: 'owner-1',
        conversation: conversation,
        completionKey: 'run-3',
        runStartPreviousCount: 0,
        analyzedMessageCount: 2,
        analyzedContentRevision: 'stale',
        analysisSnapshotJson: '{}',
        enthusiasmScore: 50,
        gameStageLabel: 'stage',
      );
      final invalidRange = await store.saveSuccessfulAnalysis(
        ownerUserId: 'owner-1',
        conversation: conversation,
        completionKey: 'run-4',
        runStartPreviousCount: 0,
        analyzedMessageCount: 3,
        analyzedContentRevision: 'irrelevant',
        analysisSnapshotJson: '{}',
        enthusiasmScore: 50,
        gameStageLabel: 'stage',
      );

      expect(blankOwner.rejectionReason, 'owner_is_blank');
      expect(otherOwner.rejectionReason, 'conversation_owner_mismatch');
      expect(stale.rejectionReason, 'stale_content_revision');
      expect(invalidRange.rejectionReason, 'invalid_message_boundary');
      expect(box.keys, isEmpty);
    });

    test('manual delete removes one archive without touching current',
        () async {
      final conversation = _conversation(id: 'conversation-1');
      final first = await _save(
        store,
        conversation,
        completionKey: 'run-1',
        previousCount: 0,
      );
      conversation.messages = List.generate(3, _message);
      final second = await _save(
        store,
        conversation,
        completionKey: 'run-2',
        previousCount: 2,
      );

      expect(
        await store.deleteRecord(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
          recordId: first.record!.id,
        ),
        isTrue,
      );
      expect(
        store
            .currentFor(
              ownerUserId: 'owner-1',
              conversationId: conversation.id,
            )
            ?.id,
        second.record!.id,
      );
      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ),
        isEmpty,
      );
    });

    test('conversation cleanup removes records, state, and source only',
        () async {
      final conversation = _conversation(id: 'conversation-1');
      await store.setConversationSource(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
        sourcePlatform: 'LINE',
      );
      await store.setPartnerMetVia(
        ownerUserId: 'owner-1',
        partnerId: 'partner-1',
        sourcePlatform: 'Omi',
      );
      final first = await _save(
        store,
        conversation,
        completionKey: 'run-1',
        previousCount: 0,
      );
      conversation.messages = List.generate(3, _message);
      await _save(
        store,
        conversation,
        completionKey: 'run-2',
        previousCount: 2,
      );
      final corruptedKey =
          'analysis_record_v2:owner-1:${conversation.id}:${first.record!.id}';
      await box.put(corruptedKey, 'malformed private record');

      expect(
        await store.removeConversation(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        2,
      );
      expect(box.containsKey(corruptedKey), isFalse);
      expect(
        store.currentFor(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isNull,
      );
      expect(
        store.conversationSource(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isNull,
      );
      expect(
        store.partnerMetVia(
          ownerUserId: 'owner-1',
          partnerId: 'partner-1',
        ),
        'Omi',
      );
      expect(
        box.containsKey(
          'analysis_record_deleted_v1:owner-1:${conversation.id}',
        ),
        isTrue,
      );

      final staleWriter = await _save(
        store,
        conversation,
        completionKey: 'late-post-delete-run',
        previousCount: 0,
        snapshot: '{"late":true}',
      );
      expect(staleWriter.rejectionReason, 'conversation_deleted');
      expect(
        box.keys.whereType<String>().where(
              (key) => key.startsWith(
                'analysis_record_v2:owner-1:${conversation.id}:',
              ),
            ),
        isEmpty,
      );
    });

    test('platform metadata is owner-scoped, custom, and blank deletes',
        () async {
      expect(
        await store.setConversationSource(
          ownerUserId: 'owner-1',
          conversationId: 'conversation-1',
          sourcePlatform: '  Threads  ',
        ),
        isTrue,
      );
      await store.setPartnerMetVia(
        ownerUserId: 'owner-1',
        partnerId: 'partner-1',
        sourcePlatform: '自訂社群',
      );
      expect(
        store.conversationSource(
          ownerUserId: 'owner-1',
          conversationId: 'conversation-1',
        ),
        'Threads',
      );
      expect(
        store.conversationSource(
          ownerUserId: 'owner-2',
          conversationId: 'conversation-1',
        ),
        isNull,
      );
      expect(
        store.partnerMetVia(
          ownerUserId: 'owner-1',
          partnerId: 'partner-1',
        ),
        '自訂社群',
      );
      expect(
        await store.setConversationSource(
          ownerUserId: 'owner-1',
          conversationId: 'conversation-1',
          sourcePlatform: ' ',
        ),
        isTrue,
      );
      expect(
        store.conversationSource(
          ownerUserId: 'owner-1',
          conversationId: 'conversation-1',
        ),
        isNull,
      );
      expect(
        await store.setPartnerMetVia(
          ownerUserId: '',
          partnerId: 'partner-1',
          sourcePlatform: 'Omi',
        ),
        isFalse,
      );
    });

    test('partner metadata follows merge policy and is removed on delete',
        () async {
      await store.setPartnerMetVia(
        ownerUserId: 'owner-1',
        partnerId: 'source',
        sourcePlatform: 'Omi',
      );

      expect(
        await store.mergePartnerMetadata(
          ownerUserId: 'owner-1',
          fromPartnerId: 'source',
          toPartnerId: 'target',
        ),
        isTrue,
      );
      expect(
        store.partnerMetVia(ownerUserId: 'owner-1', partnerId: 'source'),
        isNull,
      );
      expect(
        store.partnerMetVia(ownerUserId: 'owner-1', partnerId: 'target'),
        'Omi',
      );

      await store.setPartnerMetVia(
        ownerUserId: 'owner-1',
        partnerId: 'second-source',
        sourcePlatform: 'Tinder',
      );
      await store.mergePartnerMetadata(
        ownerUserId: 'owner-1',
        fromPartnerId: 'second-source',
        toPartnerId: 'target',
      );
      expect(
        store.partnerMetVia(ownerUserId: 'owner-1', partnerId: 'target'),
        'Omi',
        reason: 'an explicit target value must win during merge',
      );
      expect(
        store.partnerMetVia(
          ownerUserId: 'owner-1',
          partnerId: 'second-source',
        ),
        isNull,
      );

      expect(
        await store.removePartnerMetadata(
          ownerUserId: 'owner-1',
          partnerId: 'target',
        ),
        isTrue,
      );
      expect(
        store.partnerMetVia(ownerUserId: 'owner-1', partnerId: 'target'),
        isNull,
      );
    });

    test('relabels only the displayed current fragment before it archives',
        () async {
      final conversation = _conversation(
        id: 'conversation-source-relabel',
        messageCount: 2,
      );
      await _save(
        store,
        conversation,
        completionKey: 'run-source-1',
        previousCount: 0,
        analyzedCount: 1,
      );

      expect(
        await store.setConversationSource(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
          sourcePlatform: 'LINE',
          relabelCurrent: true,
        ),
        isTrue,
      );
      expect(
        store
            .currentFor(
              ownerUserId: 'owner-1',
              conversationId: conversation.id,
            )
            ?.sourcePlatform,
        'LINE',
      );

      // A source chosen while a newer fragment is pending must not rewrite
      // the older current case. It becomes the source snapshot of run 2.
      await store.setConversationSource(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
        sourcePlatform: 'IG',
      );
      await _save(
        store,
        conversation,
        completionKey: 'run-source-2',
        previousCount: 1,
        analyzedCount: 2,
      );

      expect(
        store
            .listArchived(
              ownerUserId: 'owner-1',
              conversationIds: [conversation.id],
            )
            .single
            .sourcePlatform,
        'LINE',
      );
      expect(
        store
            .currentFor(
              ownerUserId: 'owner-1',
              conversationId: conversation.id,
            )
            ?.sourcePlatform,
        'IG',
      );

      expect(
        await store.setConversationSource(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
          sourcePlatform: ' ',
          relabelCurrent: true,
        ),
        isTrue,
      );
      expect(
        store
            .currentFor(
              ownerUserId: 'owner-1',
              conversationId: conversation.id,
            )
            ?.sourcePlatform,
        isNull,
      );
      expect(
        store.conversationSource(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isNull,
      );
    });

    test('explicit source clear survives a same-count record repair', () async {
      final conversation = _conversation(
        id: 'conversation-source-clear-repair',
        messageCount: 2,
      );
      await store.setConversationSource(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
        sourcePlatform: 'LINE',
      );
      await _save(
        store,
        conversation,
        completionKey: 'source-before-repair',
        previousCount: 0,
      );

      await store.setConversationSource(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
        sourcePlatform: null,
      );
      final repaired = await _save(
        store,
        conversation,
        completionKey: 'source-repair',
        previousCount: 2,
        snapshot: '{"repaired":true}',
      );

      expect(repaired.status, AnalysisRecordSaveStatus.replacedCurrent);
      expect(repaired.record?.sourcePlatform, isNull);
      expect(
        store.conversationSource(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isNull,
      );
    });

    test('malformed/unavailable box reads fail safe while writes may throw',
        () async {
      await box.put(
        'analysis_record_state_v1:owner-1:conversation-1',
        'not-json{',
      );
      expect(
        store.currentFor(
          ownerUserId: 'owner-1',
          conversationId: 'conversation-1',
        ),
        isNull,
      );
      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: ['conversation-1'],
        ),
        isEmpty,
      );

      final unavailable = HiveAnalysisRecordStore(
        () => throw HiveError('settings box unavailable'),
      );
      expect(
        unavailable.currentFor(
          ownerUserId: 'owner-1',
          conversationId: 'conversation-1',
        ),
        isNull,
      );
      expect(
        unavailable.recordById(
          ownerUserId: 'owner-1',
          conversationId: 'conversation-1',
          recordId: 'record-1',
        ),
        isNull,
      );
      expect(
        unavailable.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: ['conversation-1'],
        ),
        isEmpty,
      );
      expect(
        unavailable.conversationSource(
          ownerUserId: 'owner-1',
          conversationId: 'conversation-1',
        ),
        isNull,
      );
      expect(
        unavailable.partnerMetVia(
          ownerUserId: 'owner-1',
          partnerId: 'partner-1',
        ),
        isNull,
      );
      await expectLater(
        unavailable.setConversationSource(
          ownerUserId: 'owner-1',
          conversationId: 'conversation-1',
          sourcePlatform: 'LINE',
        ),
        throwsA(isA<HiveError>()),
      );
    });
  });
}

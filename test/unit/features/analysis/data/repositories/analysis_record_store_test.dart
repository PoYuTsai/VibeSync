import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis/data/repositories/analysis_record_store.dart';
import 'package:vibesync/features/analysis/data/services/analysis_archive_lifecycle.dart';
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

    test('completed single-fragment current can be archived and deleted',
        () async {
      final conversation = _conversation(id: 'single-fragment');
      final saved = await _save(
        store,
        conversation,
        completionKey: 'single-run',
        previousCount: 0,
      );

      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ),
        isEmpty,
        reason: 'The current record stays on the analysis screen until closed.',
      );

      expect(
        await store.archiveCurrentRecord(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isTrue,
      );
      expect(
        store
            .listArchived(
              ownerUserId: 'owner-1',
              conversationIds: [conversation.id],
            )
            .single
            .id,
        saved.record!.id,
      );

      expect(
        await store.deleteRecord(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
          recordId: saved.record!.id,
        ),
        isTrue,
      );
      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ),
        isEmpty,
      );
      expect(
        store.currentFor(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isNull,
      );
    });

    test('rejecting deletion of a live current leaves it fully readable',
        () async {
      final conversation = _conversation(id: 'live-current');
      final saved = await _save(
        store,
        conversation,
        completionKey: 'live-run',
        previousCount: 0,
      );

      expect(
        await store.deleteRecord(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
          recordId: saved.record!.id,
        ),
        isFalse,
      );
      expect(
        store
            .currentFor(
              ownerUserId: 'owner-1',
              conversationId: conversation.id,
            )
            ?.id,
        saved.record!.id,
      );
      expect(
        store
            .recordById(
              ownerUserId: 'owner-1',
              conversationId: conversation.id,
              recordId: saved.record!.id,
            )
            ?.id,
        saved.record!.id,
      );
      expect(
        box.containsKey(
          'analysis_record_item_deleted_v1:owner-1:${conversation.id}:'
          '${saved.record!.id}',
        ),
        isFalse,
      );
    });

    test('archive lifecycle exposes and promotes a legacy completed current',
        () async {
      final conversation = _conversation(id: 'legacy-current')
        ..lastAnalysisSnapshotJson = '{"legacy":true}'
        ..lastAnalyzedMessageCount = 2
        ..lastEnthusiasmScore = 61;
      final saved = await _save(
        store,
        conversation,
        completionKey: 'legacy-run',
        previousCount: 0,
      );

      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ),
        isEmpty,
      );
      expect(
        AnalysisArchiveLifecycle.recordsFor(
          store: store,
          ownerUserId: 'owner-1',
          conversations: [conversation],
        ).single.id,
        saved.record!.id,
      );
      expect(
        await AnalysisArchiveLifecycle.promoteCompletedCurrentRecords(
          store: store,
          ownerUserId: 'owner-1',
          conversations: [conversation],
        ),
        isTrue,
      );
      expect(
        store
            .listArchived(
              ownerUserId: 'owner-1',
              conversationIds: [conversation.id],
            )
            .single
            .id,
        saved.record!.id,
      );
    });

    test('archive lifecycle identifies only an exact full standalone fragment',
        () async {
      final conversation = _conversation(id: 'standalone-fragment')
        ..lastAnalysisSnapshotJson = '{"completed":true}'
        ..lastAnalyzedMessageCount = 2
        ..lastEnthusiasmScore = 72;
      final saved = await _save(
        store,
        conversation,
        completionKey: 'standalone-run',
        previousCount: 0,
      );
      await store.archiveCurrentRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
      );
      final records = AnalysisArchiveLifecycle.recordsFor(
        store: store,
        ownerUserId: 'owner-1',
        conversations: [conversation],
      );

      expect(
        AnalysisArchiveLifecycle.isStandaloneFragmentRecord(
          record: saved.record!,
          conversation: conversation,
          records: records,
        ),
        isTrue,
      );
      expect(
        AnalysisArchiveLifecycle.hasStandaloneFragmentRecord(
          conversation: conversation,
          records: records,
        ),
        isTrue,
      );

      final originalOwner = conversation.ownerUserId;
      conversation.ownerUserId = null;
      expect(
        AnalysisArchiveLifecycle.hasStandaloneFragmentRecord(
          conversation: conversation,
          records: records,
        ),
        isFalse,
        reason: '缺 owner 的舊資料不能走整個 Conversation 的安全刪除',
      );
      conversation.ownerUserId = originalOwner;

      final original = conversation.messages.first;
      conversation.messages[0] = Message(
        id: original.id,
        content: '事後修改過的內容',
        isFromMe: original.isFromMe,
        timestamp: original.timestamp,
        enthusiasmScore: original.enthusiasmScore,
        quotedReplyPreview: original.quotedReplyPreview,
        quotedReplyPreviewIsFromMe: original.quotedReplyPreviewIsFromMe,
      );
      expect(
        AnalysisArchiveLifecycle.hasStandaloneFragmentRecord(
          conversation: conversation,
          records: records,
        ),
        isFalse,
        reason: 'revision 不符時必須保守保留 canonical conversation',
      );
    });

    test('legacy stacked records never own the whole conversation', () async {
      final conversation = _conversation(id: 'legacy-stacked-fragments');
      await _save(
        store,
        conversation,
        completionKey: 'legacy-first-run',
        previousCount: 0,
      );
      conversation.messages = List.generate(4, _message);
      await _save(
        store,
        conversation,
        completionKey: 'legacy-second-run',
        previousCount: 2,
      );
      conversation
        ..lastAnalysisSnapshotJson = '{"completed":true}'
        ..lastAnalyzedMessageCount = 4
        ..lastEnthusiasmScore = 72;
      await store.archiveCurrentRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
      );
      final records = AnalysisArchiveLifecycle.recordsFor(
        store: store,
        ownerUserId: 'owner-1',
        conversations: [conversation],
      );

      expect(records, hasLength(2));
      expect(
        AnalysisArchiveLifecycle.hasStandaloneFragmentRecord(
          conversation: conversation,
          records: records,
        ),
        isFalse,
      );
    });

    test('deleted completed fragment stays deleted on repair replay', () async {
      final conversation = _conversation(id: 'deleted-fragment');
      final first = await _save(
        store,
        conversation,
        completionKey: 'first-run',
        previousCount: 0,
      );
      await store.archiveCurrentRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
      );
      await store.deleteRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
        recordId: first.record!.id,
      );

      final repairReplay = await _save(
        store,
        conversation,
        completionKey: 'cold-repair-key-can-differ',
        previousCount: 0,
      );

      expect(repairReplay.status, AnalysisRecordSaveStatus.replayed);
      expect(repairReplay.record, isNull);
      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ),
        isEmpty,
        reason: 'Cold snapshot repair must not resurrect a manual deletion.',
      );

      conversation.messages = List.generate(3, _message);
      final nextFragment = await _save(
        store,
        conversation,
        completionKey: 'next-run',
        previousCount: 2,
      );
      expect(nextFragment.status, AnalysisRecordSaveStatus.advancedCurrent);
      expect(nextFragment.record!.segmentStart, 2);
    });

    test('archived current is immutable at the same boundary', () async {
      final conversation = _conversation(id: 'archived-immutable');
      final first = await _save(
        store,
        conversation,
        completionKey: 'first-run',
        previousCount: 0,
      );
      await store.archiveCurrentRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
      );

      final replacement = await _save(
        store,
        conversation,
        completionKey: 'different-run',
        previousCount: 0,
        snapshot: '{"different":true}',
      );

      expect(replacement.rejectionReason, 'archived_fragment_closed');
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

    test('explicit paid refresh can replace the same archived fragment',
        () async {
      final conversation = _conversation(id: 'archived-paid-refresh');
      final first = await _save(
        store,
        conversation,
        completionKey: 'free-run',
        previousCount: 0,
        snapshot: '{"tier":"free"}',
      );
      await store.archiveCurrentRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
      );

      final refreshed = await store.saveSuccessfulAnalysis(
        ownerUserId: 'owner-1',
        conversation: conversation,
        completionKey: 'paid-refresh-run',
        runStartPreviousCount: conversation.messages.length,
        analyzedMessageCount: conversation.messages.length,
        analyzedContentRevision: conversationContentRevision(conversation),
        analysisSnapshotJson: '{"tier":"paid"}',
        enthusiasmScore: 78,
        gameStageLabel: '穩定互動',
        allowArchivedRefresh: true,
      );

      expect(refreshed.status, AnalysisRecordSaveStatus.replacedCurrent);
      expect(refreshed.record!.id, first.record!.id);
      expect(refreshed.record!.analysisSnapshotJson, '{"tier":"paid"}');
      expect(
        await store.archiveCurrentRecord(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isTrue,
      );
      expect(
        store
            .listArchived(
              ownerUserId: 'owner-1',
              conversationIds: [conversation.id],
            )
            .single
            .analysisSnapshotJson,
        '{"tier":"paid"}',
      );
    });

    test('deleted boundary rejects shorter or changed same-boundary repair',
        () async {
      final conversation = _conversation(id: 'deleted-closed');
      final first = await _save(
        store,
        conversation,
        completionKey: 'first-run',
        previousCount: 0,
      );
      await store.archiveCurrentRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
      );
      await store.deleteRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
        recordId: first.record!.id,
      );

      final changed = await _save(
        store,
        conversation,
        completionKey: 'changed-run',
        previousCount: 0,
        snapshot: '{"changed":true}',
      );
      final shorter = await _save(
        store,
        conversation,
        completionKey: 'short-run',
        previousCount: 0,
        analyzedCount: 1,
      );

      expect(changed.rejectionReason, 'deleted_fragment_closed');
      expect(shorter.rejectionReason, 'deleted_fragment_closed');
      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ),
        isEmpty,
      );
    });

    test('archived boundary extension rejects an edited historical prefix',
        () async {
      final conversation = _conversation(id: 'edited-prefix');
      await _save(
        store,
        conversation,
        completionKey: 'first-run',
        previousCount: 0,
      );
      await store.archiveCurrentRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
      );
      conversation.messages[0] = Message(
        id: 'message-0',
        content: '已被修改的舊訊息',
        isFromMe: true,
        timestamp: DateTime.utc(2026, 7, 15, 10),
      );
      conversation.messages.add(_message(2));

      final extension = await _save(
        store,
        conversation,
        completionKey: 'extended-run',
        previousCount: 2,
      );

      expect(extension.rejectionReason, 'fragment_prefix_changed');
    });

    test('partial-delete residual record stays tombstoned after extension',
        () async {
      final conversation = _conversation(id: 'partial-delete');
      final first = await _save(
        store,
        conversation,
        completionKey: 'first-run',
        previousCount: 0,
      );
      await store.archiveCurrentRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
      );
      await store.deleteRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
        recordId: first.record!.id,
      );
      final oldRecordKey =
          'analysis_record_v2:owner-1:${conversation.id}:${first.record!.id}';
      await box.put(oldRecordKey, first.record!.encode());

      expect(
        store.recordById(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
          recordId: first.record!.id,
        ),
        isNull,
      );
      conversation.messages.add(_message(2));
      final next = await _save(
        store,
        conversation,
        completionKey: 'next-run',
        previousCount: 2,
      );

      expect(next.status, AnalysisRecordSaveStatus.advancedCurrent);
      expect(next.record!.segmentStart, 2);
      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ).where((record) => record.id == first.record!.id),
        isEmpty,
      );
    });

    test('item tombstone alone hides current during a partial delete window',
        () async {
      final conversation = _conversation(id: 'partial-current-delete');
      final saved = await _save(
        store,
        conversation,
        completionKey: 'first-run',
        previousCount: 0,
      );
      await store.archiveCurrentRecord(
        ownerUserId: 'owner-1',
        conversationId: conversation.id,
      );
      await box.put(
        'analysis_record_item_deleted_v1:owner-1:${conversation.id}:'
        '${saved.record!.id}',
        true,
      );

      expect(
        store.currentFor(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isNull,
      );
      expect(
        store.recordById(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
          recordId: saved.record!.id,
        ),
        isNull,
      );

      final replay = await _save(
        store,
        conversation,
        completionKey: 'cold-repair-after-partial-delete',
        previousCount: 0,
      );
      expect(replay.status, AnalysisRecordSaveStatus.replayed);
      expect(replay.record, isNull);
      expect(
        await store.archiveCurrentRecord(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isTrue,
        reason: 'Cold repair must not hard-gate on a durable item tombstone.',
      );
      expect(
        store.currentFor(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isNull,
      );
      expect(
        store.listArchived(
          ownerUserId: 'owner-1',
          conversationIds: [conversation.id],
        ),
        isEmpty,
      );
      final healedState = jsonDecode(
        box.get(
          'analysis_record_state_v1:owner-1:${conversation.id}',
        ) as String,
      ) as Map<String, dynamic>;
      expect(healedState['currentDeleted'], isTrue);
    });

    test('schema v1 current lazily upgrades before archive and delete',
        () async {
      final conversation = _conversation(id: 'schema-v1');
      final first = await _save(
        store,
        conversation,
        completionKey: 'first-run',
        previousCount: 0,
      );
      final stateKey = 'analysis_record_state_v1:owner-1:${conversation.id}';
      await box.put(
        stateKey,
        jsonEncode(<String, Object>{
          'schemaVersion': 1,
          'currentRecordId': first.record!.id,
          'lastCompletionKey': 'first-run',
          'currentStart': 0,
          'currentEnd': 2,
        }),
      );

      expect(
        await store.archiveCurrentRecord(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
        ),
        isTrue,
      );
      expect(box.get(stateKey), contains('"schemaVersion":2'));
      expect(
        await store.deleteRecord(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
          recordId: first.record!.id,
        ),
        isTrue,
      );
      final replay = await _save(
        store,
        conversation,
        completionKey: 'repair-run',
        previousCount: 0,
      );
      expect(replay.status, AnalysisRecordSaveStatus.replayed);
      expect(replay.record, isNull);
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
      expect(
        await store.deleteRecord(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
          recordId: first.record!.id,
        ),
        isTrue,
      );
      final recordTombstonePrefix =
          'analysis_record_item_deleted_v1:owner-1:${conversation.id}:';
      expect(
        box.keys.whereType<String>().where(
              (key) => key.startsWith(recordTombstonePrefix),
            ),
        isNotEmpty,
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
      expect(
        box.keys.whereType<String>().where(
              (key) => key.startsWith(recordTombstonePrefix),
            ),
        isEmpty,
      );

      // A stale payload that appears after whole-conversation cleanup must
      // not let a concurrent item delete leave a ghost tombstone behind.
      await box.put(corruptedKey, first.record!.encode());
      expect(
        await store.deleteRecord(
          ownerUserId: 'owner-1',
          conversationId: conversation.id,
          recordId: first.record!.id,
        ),
        isFalse,
      );
      expect(
        box.keys.whereType<String>().where(
              (key) => key.startsWith(recordTombstonePrefix),
            ),
        isEmpty,
      );
      await box.delete(corruptedKey);

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

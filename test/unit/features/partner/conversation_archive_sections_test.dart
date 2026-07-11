import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/analysis_history/domain/repositories/analysis_history_repository.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/presentation/utils/conversation_archive_sections.dart';

class _TrackingHistoryRepository implements AnalysisHistoryRepository {
  _TrackingHistoryRepository(this.events, {this.throwOnList = false});

  final List<AnalysisHistoryEvent> events;
  final bool throwOnList;
  int listByKindCalls = 0;
  int listByConversationCalls = 0;

  @override
  List<AnalysisHistoryEvent> listByKind(
    AnalysisHistoryKind kind, {
    int? limit,
  }) {
    listByKindCalls++;
    if (throwOnList) throw StateError('history unavailable');
    return events;
  }

  @override
  List<AnalysisHistoryEvent> listByConversation(
    String conversationId, {
    int? limit,
  }) {
    listByConversationCalls++;
    return const [];
  }

  @override
  List<AnalysisHistoryEvent> listRecent({int? limit}) => events;

  @override
  Future<void> append(AnalysisHistoryEvent event) async {}

  @override
  Future<void> clearAll() async {}
}

Conversation _conversation({
  required String id,
  String? snapshot,
  int? analyzedCount,
}) =>
    Conversation(
      id: id,
      name: id,
      messages: const [],
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
      ownerUserId: 'u1',
      partnerId: 'p1',
      lastAnalysisSnapshotJson: snapshot,
      lastAnalyzedMessageCount: analyzedCount,
    );

void main() {
  test('lazy history lookup scans analyze history once and indexes latest', () {
    final repository = _TrackingHistoryRepository([
      AnalysisHistoryEvent.analyze(
        id: 'old',
        createdAt: DateTime(2026, 7, 1),
        conversationId: ' c-1 ',
      ),
      AnalysisHistoryEvent.analyze(
        id: 'new',
        createdAt: DateTime(2026, 7, 3),
        conversationId: 'c-1',
      ),
      AnalysisHistoryEvent.analyze(
        id: 'other',
        createdAt: DateTime(2026, 7, 2),
        conversationId: 'c-2',
      ),
      AnalysisHistoryEvent(
        id: 'practice-shaped',
        kind: AnalysisHistoryKind.practice,
        createdAt: DateTime(2026, 7, 9),
        conversationId: 'c-1',
      ),
      AnalysisHistoryEvent.analyze(
        id: 'post-rollout-window',
        createdAt: DateTime(2026, 7, 12),
        conversationId: 'c-new',
      ),
    ]);
    final lookup = createLazyLatestAnalyzeAtLookup(() => repository);

    expect(repository.listByKindCalls, 0);
    expect(lookup(' c-1 '), DateTime(2026, 7, 3));
    expect(lookup('c-2'), DateTime(2026, 7, 2));
    expect(lookup('c-new'), DateTime(2026, 7, 12));
    expect(lookup('missing'), isNull);
    expect(repository.listByKindCalls, 1);
    expect(repository.listByConversationCalls, 0);
  });

  test('lazy history lookup caches loader and repository failures', () {
    var loaderCalls = 0;
    final loaderFailure = createLazyLatestAnalyzeAtLookup(() {
      loaderCalls++;
      throw StateError('provider unavailable');
    });

    expect(loaderFailure('c-1'), isNull);
    expect(loaderFailure('c-2'), isNull);
    expect(loaderCalls, 1);

    final repository = _TrackingHistoryRepository(
      const [],
      throwOnList: true,
    );
    final repositoryFailure = createLazyLatestAnalyzeAtLookup(() => repository);
    expect(repositoryFailure('c-1'), isNull);
    expect(repositoryFailure('c-2'), isNull);
    expect(repository.listByKindCalls, 1);
  });

  test('explicit archived/active marker 是分流權威且保留 active 輸入順序', () {
    final a = _conversation(id: 'a');
    final b = _conversation(
      id: 'b',
      snapshot: '{"ok":true}',
      analyzedCount: 0,
    );
    final c = _conversation(
      id: 'c',
      snapshot: '{"ok":true}',
      analyzedCount: 0,
    );
    final entries = <String, ConversationArchiveEntry>{
      'b': ConversationArchiveEntry.archived(
        archivedAt: DateTime(2026, 7, 3),
        contentRevision: conversationContentRevision(b),
      ),
      'c': ConversationArchiveEntry.active(
        changedAt: DateTime(2026, 7, 4),
      ),
    };

    final sections = partitionConversationsByArchive(
      [a, b, c],
      entryFor: (conversation) => entries[conversation.id],
      latestAnalysisAtFor: (_) => DateTime(2026, 7, 5),
    );

    expect(sections.active.map((item) => item.id), ['a', 'c']);
    expect(sections.archived.map((item) => item.conversation.id), ['b']);
  });

  test('archived marker 缺 revision 時 fail-open 留在 active', () {
    final conversation = _conversation(id: 'missing-revision');

    final sections = partitionConversationsByArchive(
      [conversation],
      entryFor: (_) => ConversationArchiveEntry.archived(
        archivedAt: DateTime(2026, 7, 3),
      ),
      latestAnalysisAtFor: (_) => DateTime(2026, 7, 3),
    );

    expect(sections.active.single.id, conversation.id);
    expect(sections.archived, isEmpty);
  });

  test('matching archived marker 但快照缺失時 fail-open 留在 active', () {
    final conversation = _conversation(id: 'missing-snapshot');

    final sections = partitionConversationsByArchive(
      [conversation],
      entryFor: (_) => ConversationArchiveEntry.archived(
        archivedAt: DateTime(2026, 7, 3),
        contentRevision: conversationContentRevision(conversation),
      ),
      latestAnalysisAtFor: (_) => DateTime(2026, 7, 3),
    );

    expect(sections.active.single.id, conversation.id);
    expect(sections.archived, isEmpty);
  });

  test('matching archived marker 但只分析部分訊息時 fail-open 留在 active', () {
    final conversation = _conversation(
      id: 'partial-snapshot',
      snapshot: '{"ok":true}',
      analyzedCount: 0,
    )..messages = [
        Message(
          id: 'm-1',
          content: '尚未完整分析',
          isFromMe: false,
          timestamp: DateTime(2026, 7, 11),
        ),
      ];

    final sections = partitionConversationsByArchive(
      [conversation],
      entryFor: (_) => ConversationArchiveEntry.archived(
        archivedAt: DateTime(2026, 7, 3),
        contentRevision: conversationContentRevision(conversation),
      ),
      latestAnalysisAtFor: (_) => DateTime(2026, 7, 3),
    );

    expect(sections.active.single.id, conversation.id);
    expect(sections.archived, isEmpty);
  });

  test('same-count edit 與 archived revision 不符時 fail-open 留在 active', () {
    final conversation = _conversation(id: 'same-count-edit')
      ..messages = [
        Message(
          id: 'm-1',
          content: '分析時內容',
          isFromMe: false,
          timestamp: DateTime(2026, 7, 11),
        ),
      ];
    final archivedRevision = conversationContentRevision(conversation);
    conversation.messages = [
      Message(
        id: 'm-1',
        content: '分析後被改掉',
        isFromMe: false,
        timestamp: DateTime(2026, 7, 11),
      ),
    ];

    final sections = partitionConversationsByArchive(
      [conversation],
      entryFor: (_) => ConversationArchiveEntry.archived(
        archivedAt: DateTime(2026, 7, 3),
        contentRevision: archivedRevision,
      ),
      latestAnalysisAtFor: (_) => DateTime(2026, 7, 3),
    );

    expect(sections.active.single.id, conversation.id);
    expect(sections.archived, isEmpty);
  });

  test('無 marker 的舊資料只有 snapshot/count/event 三證據完整才保守歸檔', () {
    final complete = _conversation(
      id: 'complete',
      snapshot: '{"ok":true}',
      analyzedCount: 0,
    );
    final noHistory = _conversation(
      id: 'no-history',
      snapshot: '{"ok":true}',
      analyzedCount: 0,
    );
    final noSnapshot = _conversation(id: 'no-snapshot', analyzedCount: 0);

    final sections = partitionConversationsByArchive(
      [complete, noHistory, noSnapshot],
      entryFor: (_) => null,
      latestAnalysisAtFor: (id) =>
          id == 'complete' ? DateTime(2026, 7, 2) : null,
    );

    expect(sections.archived.map((item) => item.conversation.id), ['complete']);
    expect(sections.active.map((item) => item.id), [
      'no-history',
      'no-snapshot',
    ]);
  });

  test('舊分析事件早於 conversation.updatedAt 時留在 active，避免同數量編輯誤藏', () {
    final edited = _conversation(
      id: 'edited',
      snapshot: '{"ok":true}',
      analyzedCount: 0,
    )..updatedAt = DateTime(2026, 7, 5);

    final sections = partitionConversationsByArchive(
      [edited],
      entryFor: (_) => null,
      latestAnalysisAtFor: (_) => DateTime(2026, 7, 4),
    );

    expect(sections.active.single.id, 'edited');
    expect(sections.archived, isEmpty);
  });
}

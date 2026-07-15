import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/analysis/data/repositories/analysis_record_store.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/analysis_history/domain/repositories/analysis_history_repository.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_analysis_archive_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_conversation_tile.dart';

class _MemoryArchiveStore implements ConversationArchiveStore {
  final Map<String, ConversationArchiveEntry> entries = {};
  String? lastMarkedActiveId;

  @override
  ConversationArchiveEntry? entryFor(Conversation conversation) =>
      entries[conversation.id];

  @override
  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  }) async {
    lastMarkedActiveId = conversation.id;
    entries[conversation.id] = ConversationArchiveEntry.active(
      changedAt: changedAt ?? DateTime.now(),
      contentRevision:
          analyzedContentRevision ?? entries[conversation.id]?.contentRevision,
    );
  }

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) async {
    entries[conversation.id] = ConversationArchiveEntry.archived(
      archivedAt: archivedAt,
      contentRevision: conversationContentRevision(conversation),
    );
  }

  @override
  Future<void> remove(Conversation conversation) async {
    entries.remove(conversation.id);
  }
}

class _FakeHistoryRepository implements AnalysisHistoryRepository {
  @override
  Future<void> append(AnalysisHistoryEvent event) async {}

  @override
  Future<void> clearAll() async {}

  @override
  List<AnalysisHistoryEvent> listByConversation(
    String conversationId, {
    int? limit,
  }) =>
      const [];

  @override
  List<AnalysisHistoryEvent> listByKind(
    AnalysisHistoryKind kind, {
    int? limit,
  }) =>
      const [];

  @override
  List<AnalysisHistoryEvent> listRecent({int? limit}) => const [];
}

class _StaticAnalysisRecordStore implements AnalysisRecordStore {
  _StaticAnalysisRecordStore(this.records);

  final List<AnalysisRecord> records;

  @override
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  }) =>
      null;

  @override
  List<AnalysisRecord> listArchived({
    required String ownerUserId,
    required Iterable<String> conversationIds,
  }) {
    final ids = conversationIds.toSet();
    return records
        .where(
          (record) =>
              record.ownerUserId == ownerUserId &&
              ids.contains(record.conversationId),
        )
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Partner _partner() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 7, 11),
      ownerUserId: 'u1',
    );

Partner _targetPartner() => Partner(
      id: 'p2',
      name: 'Bob',
      createdAt: DateTime(2026, 1, 2),
      updatedAt: DateTime(2026, 7, 11),
      ownerUserId: 'u1',
    );

Conversation _conversation(String id, DateTime updatedAt) => Conversation(
      id: id,
      name: id,
      messages: const [],
      createdAt: updatedAt,
      updatedAt: updatedAt,
      ownerUserId: 'u1',
      partnerId: 'p1',
      lastAnalysisSnapshotJson: '{"ok":true}',
      lastAnalyzedMessageCount: 0,
    );

GoRouter _router() => GoRouter(
      initialLocation: '/archive',
      routes: [
        GoRoute(
          path: '/archive',
          builder: (_, __) =>
              const PartnerAnalysisArchiveScreen(partnerId: 'p1'),
        ),
        GoRoute(
          path: '/conversation/:conversationId',
          builder: (_, state) {
            final conversationId = state.pathParameters['conversationId']!;
            return Scaffold(
              body: Text(
                'opened-$conversationId',
                key: ValueKey('conversation-target-$conversationId'),
              ),
            );
          },
        ),
      ],
    );

Widget _host({
  required List<Conversation> conversations,
  required _MemoryArchiveStore archiveStore,
  AnalysisRecordStore? analysisRecordStore,
}) {
  return ProviderScope(
    overrides: [
      conversationArchiveStoreProvider.overrideWithValue(archiveStore),
      analysisHistoryRepositoryProvider
          .overrideWithValue(_FakeHistoryRepository()),
      partnerByIdProvider('p1').overrideWith((_) => _partner()),
      partnerListProvider.overrideWith((_) => [_partner(), _targetPartner()]),
      conversationsByPartnerProvider('p1').overrideWith((_) => conversations),
      if (analysisRecordStore != null) ...[
        analysisRecordOwnerProvider.overrideWithValue('u1'),
        analysisRecordStoreProvider.overrideWithValue(analysisRecordStore),
      ],
    ],
    child: MaterialApp.router(routerConfig: _router()),
  );
}

void main() {
  testWidgets('依封存月份分組，且不顯示 active 對話', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final july = _conversation('july', DateTime(2026, 7, 10));
    final june = _conversation('june', DateTime(2026, 6, 20));
    final active = _conversation('active', DateTime(2026, 5, 1));
    final store = _MemoryArchiveStore();
    await store.markArchived(july, archivedAt: DateTime(2026, 7, 11));
    await store.markArchived(june, archivedAt: DateTime(2026, 6, 21));
    await store.markActive(active, changedAt: DateTime(2026, 5, 2));

    await tester.pumpWidget(
      _host(
        conversations: [active, june, july],
        archiveStore: store,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026 年 7 月'), findsOneWidget);
    expect(find.text('2026 年 6 月'), findsOneWidget);
    expect(find.byType(PartnerConversationTile), findsNWidgets(2));
    expect(find.text('07/10 互動紀錄'), findsOneWidget);
    expect(find.text('06/20 互動紀錄'), findsOneWidget);
    expect(find.text('05/01 互動紀錄'), findsNothing);
    expect(
        find.byKey(const ValueKey('archive-new-conversation')), findsOneWidget);
    expect(find.text('+ 分析新片段'), findsOneWidget);
  });

  testWidgets('舊對話只能查看，不會被改回 active', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final conversation = _conversation('archived', DateTime(2026, 7, 10));
    final store = _MemoryArchiveStore();
    await store.markArchived(
      conversation,
      archivedAt: DateTime(2026, 7, 11),
    );

    await tester.pumpWidget(
      _host(conversations: [conversation], archiveStore: store),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('archive-continue-archived')),
      findsNothing,
    );
    expect(find.text('繼續這一段'), findsNothing);
    await tester.tap(find.text('07/10 互動紀錄'));
    await tester.pumpAndSettle();

    expect(store.lastMarkedActiveId, isNull);
    expect(
      store.entryFor(conversation)?.status,
      ConversationArchiveStatus.archived,
    );
    expect(
      find.byKey(const ValueKey('conversation-target-archived')),
      findsOneWidget,
    );
  });

  testWidgets('完整獨立分析片段不會重複出現在舊版整段對話', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final timestamp = DateTime(2026, 7, 10);
    final message = Message(
      id: 'm1',
      content: '這次只想分析這一句',
      isFromMe: false,
      timestamp: timestamp,
    );
    final conversation = Conversation(
      id: 'standalone',
      name: 'standalone',
      messages: [message],
      createdAt: timestamp,
      updatedAt: timestamp,
      ownerUserId: 'u1',
      partnerId: 'p1',
      lastAnalysisSnapshotJson: '{"completed":true}',
      lastAnalyzedMessageCount: 1,
      lastEnthusiasmScore: 72,
    );
    final record = AnalysisRecord(
      id: 'record-standalone',
      ownerUserId: 'u1',
      conversationId: conversation.id,
      partnerId: 'p1',
      subjectName: 'Alice',
      segmentStart: 0,
      segmentEnd: 1,
      createdAt: timestamp,
      messages: [AnalysisRecordMessage.fromMessage(message)],
      analysisSnapshotJson: '{"completed":true}',
      analyzedContentRevision: conversationContentRevision(conversation),
      completionKey: 'run-standalone',
      sourcePlatform: 'Omi',
      enthusiasmScore: 72,
      gameStageLabel: '建立連結',
    );
    final archiveStore = _MemoryArchiveStore();
    await archiveStore.markArchived(
      conversation,
      archivedAt: timestamp.add(const Duration(hours: 1)),
    );

    await tester.pumpWidget(
      _host(
        conversations: [conversation],
        archiveStore: archiveStore,
        analysisRecordStore: _StaticAnalysisRecordStore([record]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PartnerConversationTile), findsNothing);
    expect(
      find.text('這裡保留舊版整段對話供查看；新內容請另開分析片段。'),
      findsOneWidget,
    );
  });

  testWidgets('封存對話保留改派與刪除操作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final conversation = _conversation('actions', DateTime(2026, 7, 10));
    final store = _MemoryArchiveStore();
    await store.markArchived(
      conversation,
      archivedAt: DateTime(2026, 7, 11),
    );

    await tester.pumpWidget(
      _host(conversations: [conversation], archiveStore: store),
    );
    await tester.pumpAndSettle();

    final tile = tester.widget<PartnerConversationTile>(
      find.byType(PartnerConversationTile),
    );
    expect(tile.onReassign, isNotNull);
    expect(tile.onDelete, isNotNull);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('改派到其他對象'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);

    Navigator.of(tester.element(find.text('Bob'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除對話'));
    await tester.pumpAndSettle();
    expect(find.text('刪除這段互動紀錄？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}

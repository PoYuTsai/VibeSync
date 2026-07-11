import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/analysis_history/domain/repositories/analysis_history_repository.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
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
  }) async {
    lastMarkedActiveId = conversation.id;
    entries[conversation.id] = ConversationArchiveEntry.active(
      changedAt: changedAt ?? DateTime.now(),
    );
  }

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) async {
    entries[conversation.id] = ConversationArchiveEntry.archived(
      archivedAt: archivedAt,
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

Partner _partner() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
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
}) {
  return ProviderScope(
    overrides: [
      conversationArchiveStoreProvider.overrideWithValue(archiveStore),
      analysisHistoryRepositoryProvider
          .overrideWithValue(_FakeHistoryRepository()),
      partnerByIdProvider('p1').overrideWith((_) => _partner()),
      conversationsByPartnerProvider('p1').overrideWith((_) => conversations),
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
    expect(find.text('+ 新增對話'), findsOneWidget);
  });

  testWidgets('繼續這一段會改回 active 並導航到該對話', (tester) async {
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

    await tester.tap(
      find.byKey(const ValueKey('archive-continue-archived')),
    );
    await tester.pumpAndSettle();

    expect(store.lastMarkedActiveId, 'archived');
    expect(
      store.entryFor(conversation)?.status,
      ConversationArchiveStatus.active,
    );
    expect(
      find.byKey(const ValueKey('conversation-target-archived')),
      findsOneWidget,
    );
  });
}

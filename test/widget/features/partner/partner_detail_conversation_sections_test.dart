// 對象頁對話分流（Bruce 回饋 follow-up）：
// - active 只留「目前對話」。
// - analysisCompleted 不再與新對話混排。
// - 已收起對話降為右上分析紀錄抽屜內的次入口。
// Hermetic：provider/store 全 override，不碰 Hive。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/analysis_history/domain/repositories/analysis_history_repository.dart';
import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/coach_follow_up/data/providers/coach_follow_up_providers.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';
import 'package:vibesync/features/coach_follow_up/domain/repositories/coach_follow_up_repository.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_conversation_tile.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';

Partner _p() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

Conversation _conv(String id) => Conversation(
      id: id,
      name: '第 $id 段',
      messages: const [],
      createdAt: DateTime(2026, 7, 10),
      updatedAt: DateTime(2026, 7, 10),
      ownerUserId: 'u1',
      partnerId: 'p1',
      lastAnalysisSnapshotJson: '{"ok":true}',
      lastAnalyzedMessageCount: 0,
    );

class _MemoryArchiveStore implements ConversationArchiveStore {
  final Map<String, ConversationArchiveEntry> entries = {};

  @override
  ConversationArchiveEntry? entryFor(Conversation conversation) =>
      entries[conversation.id];

  @override
  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  }) async {
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

class _FakeHistoryRepo implements AnalysisHistoryRepository {
  @override
  Future<void> append(AnalysisHistoryEvent event) async {}
  @override
  Future<void> clearAll() async {}
  @override
  List<AnalysisHistoryEvent> listByConversation(String conversationId,
          {int? limit}) =>
      const [];
  @override
  List<AnalysisHistoryEvent> listByKind(AnalysisHistoryKind kind,
          {int? limit}) =>
      const [];
  @override
  List<AnalysisHistoryEvent> listRecent({int? limit}) => const [];
}

class _FakeCoachFollowUpRepo implements CoachFollowUpRepository {
  final Map<String, CoachFollowUpResult> _store = {};
  @override
  CoachFollowUpResult? get(String id) => _store[id];
  @override
  Future<void> put(CoachFollowUpResult r) async => _store[r.partnerId] = r;
  @override
  Future<void> delete(String id) async => _store.remove(id);
  @override
  Future<void> clearAll() async => _store.clear();
}

class _FakeStyleRepo implements PartnerStyleRepository {
  @override
  Future<void> clearAll() async {}
  @override
  Future<void> delete(String partnerId) async {}
  @override
  Future<PartnerStyleOverride?> load(String partnerId) async => null;
  @override
  Future<void> save(PartnerStyleOverride o) async {}
}

Widget _host(
  List<Conversation> conversations,
  ConversationArchiveStore archiveStore,
) =>
    ProviderScope(
      overrides: [
        conversationArchiveStoreProvider.overrideWithValue(archiveStore),
        analysisHistoryRepositoryProvider.overrideWithValue(_FakeHistoryRepo()),
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        coachFollowUpRepositoryProvider
            .overrideWithValue(_FakeCoachFollowUpRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1').overrideWith((_) => conversations),
        partnerListProvider.overrideWith((_) => [_p()]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    );

void main() {
  group('對象頁目前對話／已收起的對話分流', () {
    testWidgets('active 留在頁面、archived 收進分析紀錄抽屜次入口', (tester) async {
      final active = _conv('active');
      final archived = _conv('archived');
      final store = _MemoryArchiveStore();
      await store.markArchived(archived, archivedAt: DateTime(2026, 7, 10));

      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host([active, archived], store));
      await tester.pumpAndSettle();

      expect(find.text('目前對話'), findsOneWidget);
      expect(find.byType(PartnerConversationTile), findsOneWidget);
      expect(find.text('已收起的對話 (1)'), findsNothing);
      expect(find.textContaining('較早的對話'), findsNothing);
      expect(
        find.byKey(const ValueKey('partner-analysis-records-entry')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('partner-analysis-records-entry')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice 的分析紀錄'), findsOneWidget);
      expect(find.text('已收起的對話 1'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('archived-conversations-secondary-entry'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('全部已分析時不留混排 tile，次入口顯示正確數量', (tester) async {
      final first = _conv('first');
      final second = _conv('second');
      final store = _MemoryArchiveStore();
      await store.markArchived(first, archivedAt: DateTime(2026, 7, 10));
      await store.markArchived(second, archivedAt: DateTime(2026, 7, 9));

      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host([first, second], store));
      await tester.pumpAndSettle();

      expect(find.byType(PartnerConversationTile), findsNothing);
      expect(find.text('目前沒有待整理的對話'), findsOneWidget);
      expect(find.text('已收起的對話 (2)'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('partner-analysis-records-entry')),
      );
      await tester.pumpAndSettle();

      expect(find.text('已收起的對話 2'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('archived-conversations-secondary-entry'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('全部 active 時抽屜不顯示空的已收起對話入口', (tester) async {
      final store = _MemoryArchiveStore();
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host([_conv('a'), _conv('b')], store));
      await tester.pumpAndSettle();

      expect(find.byType(PartnerConversationTile), findsNWidgets(2));
      expect(find.textContaining('已收起的對話 ('), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('partner-analysis-records-entry')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('已收起的對話'), findsNothing);
      expect(
        find.byKey(
          const ValueKey('archived-conversations-secondary-entry'),
        ),
        findsNothing,
      );
    });
  });
}

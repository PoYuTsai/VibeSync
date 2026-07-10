// 互動紀錄列表分區摺疊（Bruce 回饋案 C）：
// - 「進行中」＝updatedAt 距今 ≤30 天；「較早的對話」＝>30 天，預設收合。
// - 全部同一區（全新或全舊）→ 不顯示分區 header，維持單一列表。
// Hermetic：沿用 partner_detail_screen_test 的窄 provider override，不碰 Hive。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibesync/features/coach_follow_up/data/providers/coach_follow_up_providers.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';
import 'package:vibesync/features/coach_follow_up/domain/repositories/coach_follow_up_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/utils/conversation_recency_sections.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_conversation_tile.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';

Partner _p() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

Conversation _convAt(String id, DateTime updatedAt) => Conversation(
      id: id,
      name: '第 $id 段',
      messages: const [],
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );

Conversation _convAgedDays(String id, int daysAgo) =>
    _convAt(id, DateTime.now().subtract(Duration(days: daysAgo)));

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
  final Map<String, PartnerStyleOverride> byPartner = {};
  @override
  Future<PartnerStyleOverride?> load(String partnerId) async =>
      byPartner[partnerId];
  @override
  Future<void> save(PartnerStyleOverride o) async {
    if (o.isEmpty) {
      byPartner.remove(o.partnerId);
    } else {
      byPartner[o.partnerId] = o;
    }
  }

  @override
  Future<void> delete(String partnerId) async => byPartner.remove(partnerId);
  @override
  Future<void> clearAll() async => byPartner.clear();
}

Widget _host(List<Conversation> conversations) => ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        coachFollowUpRepositoryProvider
            .overrideWithValue(_FakeCoachFollowUpRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => conversations),
        partnerListProvider.overrideWith((_) => [_p()]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    );

void main() {
  group('partitionConversationsByRecency 純函式', () {
    test('依 30 天門檻分區且保留輸入順序', () {
      final now = DateTime(2026, 7, 10);
      final sections = partitionConversationsByRecency(
        [
          _convAt('a', now),
          _convAt('b', now.subtract(const Duration(days: 29))),
          _convAt('c', now.subtract(const Duration(days: 31))),
        ],
        now,
      );
      expect(sections.active.map((c) => c.id), ['a', 'b']);
      expect(sections.older.map((c) => c.id), ['c']);
    });

    test('剛好 30 天算進行中（≤30 天）', () {
      final now = DateTime(2026, 7, 10);
      final sections = partitionConversationsByRecency(
        [_convAt('x', now.subtract(const Duration(days: 30)))],
        now,
      );
      expect(sections.active, hasLength(1));
      expect(sections.older, isEmpty);
    });
  });

  group('互動紀錄列表分區摺疊', () {
    testWidgets('3 新 + 2 舊 → 出現「較早的對話 (2)」收合區，展開後全部可見',
        (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));

      await t.pumpWidget(_host([
        _convAgedDays('n1', 1),
        _convAgedDays('n2', 5),
        _convAgedDays('n3', 10),
        _convAgedDays('o1', 40),
        _convAgedDays('o2', 50),
      ]));
      await t.pumpAndSettle();

      expect(find.text('較早的對話 (2)'), findsOneWidget);
      // 預設收合：只有 3 筆進行中 tile。
      expect(find.byType(PartnerConversationTile), findsNWidgets(3));

      await t.tap(find.text('較早的對話 (2)'));
      await t.pumpAndSettle();
      expect(find.byType(PartnerConversationTile), findsNWidgets(5));
    });

    testWidgets('全部 ≤30 天 → 無分區 header，單一列表', (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));

      await t.pumpWidget(_host([
        _convAgedDays('n1', 1),
        _convAgedDays('n2', 5),
        _convAgedDays('n3', 10),
      ]));
      await t.pumpAndSettle();

      expect(find.textContaining('較早的對話'), findsNothing);
      expect(find.byType(PartnerConversationTile), findsNWidgets(3));
    });

    testWidgets('全部 >30 天 → 無分區 header，直接展開顯示不留空白', (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));

      await t.pumpWidget(_host([
        _convAgedDays('o1', 40),
        _convAgedDays('o2', 50),
      ]));
      await t.pumpAndSettle();

      expect(find.textContaining('較早的對話'), findsNothing);
      expect(find.byType(PartnerConversationTile), findsNWidgets(2));
    });
  });
}

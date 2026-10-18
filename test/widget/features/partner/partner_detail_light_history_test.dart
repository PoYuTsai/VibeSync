// test/widget/features/partner/partner_detail_light_history_test.dart
//
// 對象頁的燈號紀錄（Eric 2026-10-18：Starter 主打「燈號紀錄＋邀約進度」，免費只看最新
// 一次）。走真的接線：分析紀錄 → partnerLightHistoryProvider → 卡片；方案用訂閱狀態判斷，
// 只差顯示。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_light_history_card.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';

import '../../../helpers/motion_free_app.dart';
import '../../../helpers/memory_coach_chat_repository.dart';

const _upgradeLabel = '升級 Starter 看完整燈號紀錄';

Partner _p() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

String _v3Snapshot({
  required String decision,
  required String light,
  String? inviteReadiness,
}) =>
    jsonEncode({
      'guideVersion': 'v3.5',
      'read': {
        'guideVersion': 'v3.5',
        'decision': decision,
        'light': light,
        'judgment': '她有在接你的話。',
        if (inviteReadiness != null) 'inviteReadiness': inviteReadiness,
        if (inviteReadiness != null)
          'cold': {'c1': false, 'herPerfunctoryStreak': 0},
        'plannedCards': const [],
      },
      'cards': const [],
      'partial': false,
    });

AnalysisRecord _record(
  String id,
  DateTime createdAt, {
  required String decision,
  required String light,
  String? inviteReadiness,
}) =>
    AnalysisRecord(
      id: id,
      ownerUserId: 'u1',
      conversationId: 'c-$id',
      partnerId: 'p1',
      subjectName: 'Alice',
      segmentStart: 0,
      segmentEnd: 1,
      createdAt: createdAt,
      messages: [
        AnalysisRecordMessage.fromMessage(Message(
          id: 'm-$id',
          content: '好啊',
          isFromMe: false,
          timestamp: createdAt,
        )),
      ],
      analysisSnapshotJson: _v3Snapshot(
        decision: decision,
        light: light,
        inviteReadiness: inviteReadiness,
      ),
      analyzedContentRevision: 'rev-$id',
      completionKey: 'run-$id',
      sourcePlatform: null,
      enthusiasmScore: null,
      gameStageLabel: '',
      guideVersion: 'v3.5',
      guideV3Light: light,
    );

/// 新到舊：綠（出卡，她自己提見面；從黃變綠）、黃（先別回）、綠（出卡）。
final _threeRecords = [
  _record('r3', DateTime(2026, 10, 18, 21, 5),
      decision: 'send', light: 'green', inviteReadiness: 'she_proposed'),
  _record('r2', DateTime(2026, 10, 17, 20, 10),
      decision: 'hold', light: 'yellow', inviteReadiness: 'hesitant'),
  _record('r1', DateTime(2026, 10, 16, 9, 30),
      decision: 'send', light: 'green', inviteReadiness: 'none'),
];

Conversation _latestConversation() => Conversation(
      id: 'c-r3',
      name: '第三段',
      messages: const [],
      createdAt: DateTime(2026, 10, 18),
      updatedAt: DateTime(2026, 10, 18, 21, 5),
      partnerId: 'p1',
      lastAnalysisSnapshotJson: _v3Snapshot(
        decision: 'send',
        light: 'green',
        inviteReadiness: 'she_proposed',
      ),
    );

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

/// 固定方案；任何同步都維持原樣。
class _SeededSubscription extends SubscriptionNotifier {
  _SeededSubscription(String tier) {
    final limits = SubscriptionTierHelper.limitsFor(tier);
    state = SubscriptionState(
      tier: tier,
      monthlyLimit: limits.monthly,
      dailyLimit: limits.daily,
    );
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> syncWithRevenueCat() async {}
}

List<Override> _overrides({
  required String tier,
  required List<AnalysisRecord> records,
}) =>
    [
      partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
      coachChatRepositoryProvider
          .overrideWithValue(MemoryCoachChatRepository()),
      partnerByIdProvider('p1').overrideWith((_) => _p()),
      partnerAggregateProvider('p1')
          .overrideWith((_) => PartnerAggregateView.empty()),
      dataQualityFlagProvider('p1')
          .overrideWith((_) => const DataQualityFlag.unflagged()),
      conversationsByPartnerProvider('p1')
          .overrideWith((_) => [_latestConversation()]),
      partnerListProvider.overrideWith((_) => [_p()]),
      partnerAnalysisRecordsProvider('p1').overrideWith((_) => records),
      subscriptionProvider.overrideWith((_) => _SeededSubscription(tier)),
    ];

Future<void> _pumpScreen(
  WidgetTester t, {
  required String tier,
  required List<AnalysisRecord> records,
}) async {
  await t.binding.setSurfaceSize(const Size(400, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(
    overrides: _overrides(tier: tier, records: records),
    child: motionFreeApp(home: const PartnerDetailScreen(partnerId: 'p1')),
  ));
  await t.pumpAndSettle();
}

Finder _row(String id) => find.byKey(ValueKey('partner-light-history-row-$id'));

void main() {
  testWidgets('免費、三次分析：對象頁只看最新一次，下面鎖住的預覽和一顆升級鈕', (t) async {
    await _pumpScreen(
      t,
      tier: SubscriptionTierHelper.free,
      records: _threeRecords,
    );

    expect(find.byType(PartnerLightHistoryCard), findsOneWidget);
    expect(_row('r3'), findsOneWidget);
    expect(_row('r2'), findsNothing);
    expect(_row('r1'), findsNothing);
    expect(find.text('邀約進度：她自己提見面'), findsOneWidget);
    expect(find.text('還有 ${_threeRecords.length - 1} 次更早的紀錄'), findsOneWidget);
    expect(find.text(_upgradeLabel), findsOneWidget);
  });

  testWidgets('免費、只有一次分析：沒有預覽也沒有升級鈕', (t) async {
    await _pumpScreen(
      t,
      tier: SubscriptionTierHelper.free,
      records: [_threeRecords.first],
    );

    expect(_row('r3'), findsOneWidget);
    expect(find.byKey(const ValueKey('partner-light-history-locked')),
        findsNothing);
    expect(find.text(_upgradeLabel), findsNothing);
  });

  testWidgets('Starter 與 Essential：完整紀錄與變化提示，沒有升級鈕', (t) async {
    for (final tier in [
      SubscriptionTierHelper.starter,
      SubscriptionTierHelper.essential,
    ]) {
      await _pumpScreen(t, tier: tier, records: _threeRecords);

      for (final record in _threeRecords) {
        expect(_row(record.id), findsOneWidget, reason: '$tier ${record.id}');
      }
      expect(find.text('黃 → 綠'), findsOneWidget, reason: tier);
      expect(find.text('先別回 · 邀約進度：猶豫'), findsOneWidget, reason: tier);
      expect(find.text(_upgradeLabel), findsNothing, reason: tier);
    }
  });

  testWidgets('沒有 v3 分析紀錄：不放燈號紀錄', (t) async {
    await _pumpScreen(
      t,
      tier: SubscriptionTierHelper.starter,
      records: const [],
    );

    expect(find.byType(PartnerLightHistoryCard), findsNothing);
    expect(find.text('燈號紀錄'), findsNothing);
  });

  testWidgets('升級鈕打開付費頁', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/partner/p1',
      routes: [
        GoRoute(
          path: '/partner/:id',
          builder: (_, state) =>
              PartnerDetailScreen(partnerId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/paywall',
          builder: (_, __) => const Scaffold(body: Text('paywall-stub')),
        ),
      ],
    );
    await t.pumpWidget(ProviderScope(
      overrides: _overrides(
        tier: SubscriptionTierHelper.free,
        records: _threeRecords,
      ),
      child: motionFreeRouterApp(routerConfig: router),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text(_upgradeLabel));
    await t.pumpAndSettle();
    expect(find.text('paywall-stub'), findsOneWidget);
  });
}

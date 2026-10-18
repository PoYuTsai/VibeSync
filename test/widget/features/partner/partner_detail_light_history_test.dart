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
import 'package:hive_ce/hive_ce.dart';

import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/analysis/data/repositories/analysis_record_store.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/domain/entities/persistable_analysis.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/services/conversation_content_revision.dart';
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

/// [records] 是 null 時不蓋 partnerAnalysisRecordsProvider（走真的存檔讀回）。
List<Override> _overrides({
  required String tier,
  List<AnalysisRecord>? records,
  List<Conversation>? conversations,
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
          .overrideWith((_) => conversations ?? [_latestConversation()]),
      partnerListProvider.overrideWith((_) => [_p()]),
      if (records != null)
        partnerAnalysisRecordsProvider('p1').overrideWith((_) => records),
      subscriptionProvider.overrideWith((_) => _SeededSubscription(tier)),
    ];

/// 照 App 存檔的路徑存一筆 v3 分析：PersistableAnalysis.fromGuideV3，分析紀錄存它的
/// rawResponse 原樣（analysis_persistence_coordinator 的 _ensureAnalysisRecord），寫進真的
/// Hive 紀錄庫。回傳那段對話與紀錄庫給的紀錄 id。
Future<({Conversation conversation, String recordId})> _saveLikeTheApp(
  HiveAnalysisRecordStore store, {
  required String id,
  required DateTime at,
  required GuideV3Result result,
}) async {
  final persistable =
      PersistableAnalysis.fromGuideV3(result, analysisRunId: 'run-$id');
  final snapshot = jsonEncode(persistable.rawResponse);
  final conversation = Conversation(
    id: 'c-$id',
    name: 'Alice',
    messages: [
      Message(id: 'm-$id', content: '好啊', isFromMe: false, timestamp: at),
    ],
    createdAt: at,
    updatedAt: at,
    ownerUserId: 'u1',
    partnerId: 'p1',
    lastAnalysisSnapshotJson: snapshot,
  );
  final saved = await store.saveSuccessfulAnalysis(
    ownerUserId: 'u1',
    conversation: conversation,
    completionKey: 'run-$id',
    runStartPreviousCount: 0,
    analyzedMessageCount: conversation.messages.length,
    analyzedContentRevision: conversationContentRevision(
      conversation,
      messageCount: conversation.messages.length,
    ),
    analysisSnapshotJson: snapshot,
    enthusiasmScore: persistable.enthusiasmScore,
    gameStageLabel: '',
    completedAt: at,
  );
  expect(saved.accepted, isTrue, reason: saved.rejectionReason);
  return (conversation: conversation, recordId: saved.record!.id);
}

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

  testWidgets('免費：最新一次少卡（partial）或斷線後重組（recovered），照真的存檔路徑存完回對象頁，不推升級',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    /// 伺服器 finalResult 送到 App 的樣子（免費方案排 4 張、只寫前 2 張）。
    Map<String, dynamic> serverResult({
      required int delivered,
      bool partial = false,
      bool recovered = false,
    }) =>
        {
          'guideVersion': 'v3.5',
          'read': {
            'guideVersion': 'v3.5',
            'decision': 'send',
            'light': 'green',
            'judgment': '她有在接你的話。',
            'inviteReadiness': 'none',
            'cold': {'c1': false, 'herPerfunctoryStreak': 0},
            'plannedCards': [
              for (var slot = 1; slot <= 4; slot++)
                {'slot': slot, 'task': 'accept', 'locked': slot > 2},
            ],
          },
          'cards': [
            for (var slot = 1; slot <= delivered; slot++)
              {
                'slot': slot,
                'task': 'accept',
                'method': 'reaction',
                'voice': 'default',
                'messages': ['那家我也想吃吃看'],
                'hasInventedDetail': false,
                'hasBlank': false,
              },
          ],
          'partial': partial,
          if (recovered) 'recovered': true,
          'usage': {'messagesUsed': 2, 'shouldChargeQuota': true},
        };

    // 第三種是對照組：最新一次送滿，同一套接線要看得到升級鈕。
    final latestByVariant = <String, GuideV3Result>{
      // 原定 2 張、實際只送到 1 張（主審第 1 輪 P2 的情境）。
      'partial':
          GuideV3Result.fromJson(serverResult(delivered: 1, partial: true))!,
      // 續看重組只帶回第一張，App 再把畫面上已經送到的第 2 張補回去再存
      //（streaming_analyze_notifier 的 withShownCards）。
      'recovered': GuideV3Result.fromJson(
        serverResult(delivered: 1, partial: true, recovered: true),
      )!
          .withShownCards([
        GuideV3Card.fromJson(
          (serverResult(delivered: 2)['cards'] as List).last,
        )!,
      ]),
      'complete': GuideV3Result.fromJson(serverResult(delivered: 2))!,
    };

    for (final MapEntry(key: variant, value: latest)
        in latestByVariant.entries) {
      late Box<dynamic> box;
      late HiveAnalysisRecordStore store;
      late ({Conversation conversation, String recordId}) older;
      late ({Conversation conversation, String recordId}) newest;
      await t.runAsync(() async {
        Hive.init('./.dart_tool/test_hive_partner_light_history');
        box = await Hive.openBox<dynamic>(
          'partner_light_history_${variant}_'
          '${DateTime.now().microsecondsSinceEpoch}',
        );
        store = HiveAnalysisRecordStore(() => box);
        older = await _saveLikeTheApp(
          store,
          id: 'older',
          at: DateTime(2026, 10, 17, 20),
          result: GuideV3Result.fromJson(serverResult(delivered: 2))!,
        );
        newest = await _saveLikeTheApp(
          store,
          id: 'latest',
          at: DateTime(2026, 10, 18, 21, 5),
          result: latest,
        );
      });
      try {
        await t.pumpWidget(ProviderScope(
          overrides: [
            // 不蓋 partnerAnalysisRecordsProvider：走真的 recordsFor（存檔 → 讀回）。
            ..._overrides(
              tier: SubscriptionTierHelper.free,
              conversations: [older.conversation, newest.conversation],
            ),
            analysisRecordStoreProvider.overrideWithValue(store),
            analysisRecordOwnerProvider.overrideWithValue('u1'),
          ],
          child:
              motionFreeApp(home: const PartnerDetailScreen(partnerId: 'p1')),
        ));
        await t.pumpAndSettle();

        expect(_row(newest.recordId), findsOneWidget, reason: variant);
        expect(_row(older.recordId), findsNothing, reason: variant);
        if (variant == 'complete') {
          expect(find.text(_upgradeLabel), findsOneWidget, reason: variant);
        } else {
          expect(find.byKey(const ValueKey('partner-light-history-locked')),
              findsNothing,
              reason: variant);
          expect(find.text(_upgradeLabel), findsNothing, reason: variant);
        }
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await t.runAsync(() => box.deleteFromDisk());
      }
    }
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

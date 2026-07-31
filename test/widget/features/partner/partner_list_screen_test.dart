import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/home_coach_presence.dart';
import 'package:vibesync/features/partner/presentation/widgets/home_feature_entries.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_list_card.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/presentation/widgets/home_quota_strip.dart';

Partner _p(String id, String name) => Partner(
  id: id,
  name: name,
  createdAt: DateTime(2026, 4, 20),
  updatedAt: DateTime(2026, 4, 20),
  ownerUserId: 'u1',
);

PartnerAggregateView _agg({
  int rounds = 0,
  int? heat,
  List<String> interests = const [],
  List<String> traits = const [],
  DateTime? lastInteraction,
}) => PartnerAggregateView(
  unionInterests: interests,
  unionTraits: traits,
  unionNotes: null,
  latestHeat: heat,
  totalRounds: rounds,
  totalMessages: 0,
  lastInteraction: lastInteraction,
);

Conversation _conv(String id, String partnerId) => Conversation(
  id: id,
  name: 'c-$id',
  ownerUserId: 'u1',
  createdAt: DateTime(2026, 4, 20),
  updatedAt: DateTime(2026, 4, 20),
  messages: const [],
  partnerId: partnerId,
);

/// Seeded subscription notifier（my_report_screen_test idiom）：首頁掛了
/// HomeQuotaStrip 後，測試一律用 seeded 訂閱態＋no-op 刷新保持封閉。
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

List<Override> _subscriptionOverrides({
  SubscriptionState seed = const SubscriptionState(),
}) => [
  subscriptionProvider.overrideWith((_) => _SeededSubscriptionNotifier(seed)),
  subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
];

List<Override> _partnerOverrides(int count) {
  final partners = [
    for (var i = 0; i < count; i++) _p('p$i', 'Person ${i + 1}'),
  ];

  return [
    partnerListProvider.overrideWith((_) => partners),
    for (final partner in partners) ...[
      partnerAggregateProvider(partner.id).overrideWith((_) => _agg()),
      conversationsByPartnerProvider(
        partner.id,
      ).overrideWith((_) => const <Conversation>[]),
    ],
  ];
}

Widget _screen({required List<Override> overrides}) => ProviderScope(
  overrides: [..._subscriptionOverrides(), ...overrides],
  child: const MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Scaffold(body: PartnerListScreen()),
    ),
  ),
);

/// GoRouter harness for the empty-state CTAs (案 3) — the buttons call
/// context.push, so navigation assertions need real routes to land on.
Widget _routedScreen({required List<Override> overrides}) => ProviderScope(
  overrides: [..._subscriptionOverrides(), ...overrides],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: PartnerListScreen()),
          ),
        ),
        GoRoute(
          path: '/partner/new',
          builder: (_, __) => const Scaffold(body: Text('partner-new-screen')),
        ),
        GoRoute(
          path: '/practice-collection',
          builder: (_, __) =>
              const Scaffold(body: Text('practice-collection-screen')),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('empty state renders without partner cards', (t) async {
    await t.pumpWidget(
      _screen(
        overrides: [partnerListProvider.overrideWith((_) => const <Partner>[])],
      ),
    );
    await t.pumpAndSettle();

    expect(find.byType(PartnerListCard), findsNothing);
  });

  testWidgets('renders one PartnerListCard per partner with premium visuals', (
    t,
  ) async {
    await t.pumpWidget(
      _screen(
        overrides: [
          partnerListProvider.overrideWith(
            (_) => [_p('a', 'Alice'), _p('b', 'Bob')],
          ),
          partnerAggregateProvider('a').overrideWith(
            (_) => _agg(
              rounds: 3,
              heat: 70,
              interests: const ['coffee'],
              traits: const ['bold'],
            ),
          ),
          partnerAggregateProvider('b').overrideWith((_) => _agg(rounds: 1)),
          conversationsByPartnerProvider(
            'a',
          ).overrideWith((_) => const <Conversation>[]),
          conversationsByPartnerProvider(
            'b',
          ).overrideWith((_) => const <Conversation>[]),
        ],
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('AL'), findsOneWidget);
    expect(find.text('BO'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.text('本次投入 70'), findsOneWidget);
    expect(find.byIcon(Icons.insights_rounded), findsOneWidget);
    expect(find.text('待分析'), findsOneWidget);
    expect(find.text('coffee · bold'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
  });

  for (final count in [1, 2]) {
    testWidgets(
      '$count partner cards keep Sydney anchored above the bottom padding',
      (t) async {
        await t.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => t.binding.setSurfaceSize(null));

        await t.pumpWidget(_screen(overrides: _partnerOverrides(count)));
        await t.pumpAndSettle();

        // Tier 2 批 1 加了頂部額度小條＋入口列後，2 張卡的內容可能略超出
        // 視窗；不再保證免捲動貼底，改守「捲到底後 Sydney 恰好收在
        // bottom padding 之上、絕不從底部導航下露出」。
        await t.drag(find.byType(Scrollable), const Offset(0, -300));
        await t.pumpAndSettle();

        final scaffoldBottom = t.getRect(find.byType(Scaffold)).bottom;
        final coachBottom = t.getRect(find.byType(HomeCoachPresence)).bottom;

        expect(coachBottom, closeTo(scaffoldBottom - 32, 1));
      },
    );
  }

  testWidgets('five partner cards stay continuous before the coach footer', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(_screen(overrides: _partnerOverrides(5)));
    await t.pumpAndSettle();

    final fifthCardBottom = t
        .getRect(find.widgetWithText(PartnerListCard, 'Person 5'))
        .bottom;

    expect(fifthCardBottom, lessThanOrEqualTo(844));
    expect(find.byType(HomeCoachPresence), findsNothing);

    await t.drag(find.byType(Scrollable), const Offset(0, -500));
    await t.pumpAndSettle();

    expect(find.byType(HomeCoachPresence), findsOneWidget);
    expect(
      t.getRect(find.byType(HomeCoachPresence)).bottom,
      lessThanOrEqualTo(844),
    );
  });

  testWidgets('list preserves order from partnerListProvider', (t) async {
    await t.pumpWidget(
      _screen(
        overrides: [
          partnerListProvider.overrideWith(
            (_) => [_p('z', 'Zoe'), _p('a', 'Alice')],
          ),
          partnerAggregateProvider('z').overrideWith((_) => _agg()),
          partnerAggregateProvider('a').overrideWith((_) => _agg()),
          conversationsByPartnerProvider(
            'z',
          ).overrideWith((_) => const <Conversation>[]),
          conversationsByPartnerProvider(
            'a',
          ).overrideWith((_) => const <Conversation>[]),
        ],
      ),
    );
    await t.pumpAndSettle();

    final zoe = t.getTopLeft(find.text('Zoe'));
    final alice = t.getTopLeft(find.text('Alice'));
    expect(zoe.dy < alice.dy, isTrue, reason: 'Zoe must render above Alice');
  });

  group('首頁頂部掛載（Tier 2 批 1：額度小條＋功能入口列）', () {
    testWidgets('empty state 掛上 QuotaStrip 與 FeatureEntries，CTA 保留', (t) async {
      await t.pumpWidget(
        _screen(
          overrides: [
            partnerListProvider.overrideWith((_) => const <Partner>[]),
          ],
        ),
      );
      await t.pumpAndSettle();

      expect(find.byType(HomeQuotaStrip), findsOneWidget);
      expect(find.byType(HomeFeatureEntries), findsOneWidget);
      expect(find.text('建立對象卡，開始分析'), findsOneWidget);
    });

    testWidgets('非空 state 也掛上兩個新 widget', (t) async {
      await t.pumpWidget(_screen(overrides: _partnerOverrides(2)));
      await t.pumpAndSettle();

      expect(find.byType(HomeQuotaStrip), findsOneWidget);
      expect(find.byType(HomeFeatureEntries), findsOneWidget);
      expect(find.byType(PartnerListCard), findsNWidgets(2));
    });
  });

  group('empty state CTAs（案 3 冷啟動分流）', () {
    testWidgets('empty state shows both CTAs', (t) async {
      await t.pumpWidget(
        _screen(
          overrides: [
            partnerListProvider.overrideWith((_) => const <Partner>[]),
          ],
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('建立對象卡，開始分析'), findsOneWidget);
      expect(find.text('先去練習室熱身'), findsOneWidget);
    });

    testWidgets('CTAs are hidden when a partner exists', (t) async {
      await t.pumpWidget(
        _screen(
          overrides: [
            partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
            partnerAggregateProvider('a').overrideWith((_) => _agg()),
            conversationsByPartnerProvider(
              'a',
            ).overrideWith((_) => const <Conversation>[]),
          ],
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('建立對象卡，開始分析'), findsNothing);
      expect(find.text('先去練習室熱身'), findsNothing);
    });

    testWidgets('primary CTA pushes /partner/new', (t) async {
      await t.pumpWidget(
        _routedScreen(
          overrides: [
            partnerListProvider.overrideWith((_) => const <Partner>[]),
          ],
        ),
      );
      await t.pumpAndSettle();

      await t.tap(find.text('建立對象卡，開始分析'));
      await t.pumpAndSettle();

      expect(find.text('partner-new-screen'), findsOneWidget);
    });

    testWidgets('secondary CTA pushes /practice-collection', (t) async {
      await t.pumpWidget(
        _routedScreen(
          overrides: [
            partnerListProvider.overrideWith((_) => const <Partner>[]),
          ],
        ),
      );
      await t.pumpAndSettle();

      await t.tap(find.text('先去練習室熱身'));
      await t.pumpAndSettle();

      expect(find.text('practice-collection-screen'), findsOneWidget);
    });
  });

  group('delete dialog two-mode', () {
    testWidgets(
      'tapping delete with conversationCount==0 shows confirm dialog',
      (t) async {
        await t.pumpWidget(
          _screen(
            overrides: [
              partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
              partnerAggregateProvider('a').overrideWith((_) => _agg()),
              conversationsByPartnerProvider(
                'a',
              ).overrideWith((_) => const <Conversation>[]),
            ],
          ),
        );
        await t.pumpAndSettle();

        await t.tap(find.byIcon(Icons.delete_outline));
        await t.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(TextButton), findsNWidgets(2));
      },
    );

    testWidgets(
      'tapping delete with conversationCount>0 shows informational dialog',
      (t) async {
        await t.pumpWidget(
          _screen(
            overrides: [
              partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
              partnerAggregateProvider(
                'a',
              ).overrideWith((_) => _agg(rounds: 0)),
              conversationsByPartnerProvider(
                'a',
              ).overrideWith((_) => [_conv('c1', 'a'), _conv('c2', 'a')]),
            ],
          ),
        );
        await t.pumpAndSettle();

        await t.tap(find.byIcon(Icons.delete_outline));
        await t.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(TextButton), findsOneWidget);
      },
    );

    testWidgets('confirm dialog calls controller.delete and shows SnackBar', (
      t,
    ) async {
      final fake = _FakePartnerRepo();
      await t.pumpWidget(
        _screen(
          overrides: [
            partnerRepositoryProvider.overrideWithValue(fake),
            partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
            partnerAggregateProvider('a').overrideWith((_) => _agg()),
            conversationsByPartnerProvider(
              'a',
            ).overrideWith((_) => const <Conversation>[]),
          ],
        ),
      );
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();
      await t.tap(find.byType(TextButton).last);
      await t.pumpAndSettle();

      expect(fake.deletedIds, ['a']);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets(
      'confirm dialog surfaces defensive SnackBar when repository blocks delete',
      (t) async {
        final throwing = _FakePartnerRepo(throwBlockCount: 4);
        await t.pumpWidget(
          _screen(
            overrides: [
              partnerRepositoryProvider.overrideWithValue(throwing),
              partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
              partnerAggregateProvider('a').overrideWith((_) => _agg()),
              conversationsByPartnerProvider(
                'a',
              ).overrideWith((_) => const <Conversation>[]),
            ],
          ),
        );
        await t.pumpAndSettle();

        await t.tap(find.byIcon(Icons.delete_outline));
        await t.pumpAndSettle();
        await t.tap(find.byType(TextButton).last);
        await t.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.textContaining('4'), findsOneWidget);
      },
    );
  });
}

class _FakePartnerRepo implements PartnerRepository {
  _FakePartnerRepo({this.throwBlockCount});
  final int? throwBlockCount;
  final List<String> deletedIds = [];

  @override
  Future<void> delete(String partnerId) async {
    if (throwBlockCount != null) {
      throw PartnerHasConversationsException(throwBlockCount!);
    }
    deletedIds.add(partnerId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_collection_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

/// SR 限定翻牌券卡三態（2026-08-08 拍板）：
///   premium＋未用 → 金券（點了直接券抽）
///   free          → 鎖定灰券（點了導 paywall）
///   已用／載入中／讀取失敗 → 不顯示（fail-quiet，券是 bonus 非主流程）
/// harness 沿用 practice_collection_screen_test 的 seeded idiom。

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class _UnusedPracticeSessionBox extends Fake implements Box<PracticeSession> {}

class _FakePracticeSessionRepository extends PracticeSessionRepository {
  _FakePracticeSessionRepository() : super(_UnusedPracticeSessionBox());

  @override
  List<PracticeSession> recentSessions() => const [];

  @override
  Future<void> save(PracticeSession session) async {}
}

PracticeChatApiService _unusedApi() => PracticeChatApiService(
      invoker: (name, {required body}) async =>
          throw UnimplementedError('sr ticket widget test 不應打 practice-chat'),
    );

class _DrawSpyController extends PracticeChatController {
  _DrawSpyController(PracticeChatState seed)
      : super(
          api: _unusedApi(),
          repository: _FakePracticeSessionRepository(),
          sessionId: seed.sessionId,
          createdAt: seed.createdAt,
        ) {
    state = seed;
  }

  int drawCalls = 0;
  bool? lastDrawSrTicket;

  @override
  Future<void> drawNewPracticeGirl({bool srTicket = false}) async {
    drawCalls++;
    lastDrawSrTicket = srTicket;
  }
}

class _SeededSrTicketNotifier extends SrTicketStatusNotifier {
  _SeededSrTicketNotifier(this._seed);
  final Future<SrTicketStatus> Function() _seed;

  @override
  Future<SrTicketStatus> build() => _seed();
}

PracticeChatState _revealedSeed() {
  final girl = practiceGirlProfiles.first;
  return PracticeChatState(
    sessionId: 'sr-ticket-test',
    createdAt: DateTime(2026, 8, 8, 12),
    girl: girl,
    personaId: girl.personaId,
    personaLabel: '',
    difficulty: 'normal',
    difficultyLabel: '一般',
  );
}

const _paid = SubscriptionState(
  tier: SubscriptionTierHelper.starter,
  monthlyLimit: 100,
  dailyLimit: 30,
);

void main() {
  final goldTicket = find.byKey(const ValueKey('collection-sr-ticket'));
  final lockedTicket =
      find.byKey(const ValueKey('collection-sr-ticket-locked'));

  Widget app({
    required SubscriptionState subscription,
    required Future<SrTicketStatus> Function() ticket,
    PracticeChatController? controller,
  }) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const PracticeCollectionScreen(),
        ),
        GoRoute(
          path: '/paywall',
          builder: (_, __) => const Scaffold(
            body: Text('paywall-stub', key: ValueKey('paywall-stub')),
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        practiceCollectionProvider.overrideWith(
          () => _SeededCollection(const <String>{}),
        ),
        practiceChatControllerProvider.overrideWith(
          (ref) => controller ?? _DrawSpyController(_revealedSeed()),
        ),
        subscriptionProvider.overrideWith(
          (ref) => _SeededSubscriptionNotifier(subscription),
        ),
        subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
        srTicketStatusProvider.overrideWith(
          () => _SeededSrTicketNotifier(ticket),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('premium＋券未用 → 顯示金券、無鎖定券', (tester) async {
    await tester.pumpWidget(app(
      subscription: _paid,
      ticket: () async => (eligible: true, granted: true, consumed: false),
    ));
    await tester.pumpAndSettle();

    expect(goldTicket, findsOneWidget);
    expect(lockedTicket, findsNothing);
  });

  testWidgets('點金券 → 券抽（drawNewPracticeGirl(srTicket: true)）',
      (tester) async {
    final spy = _DrawSpyController(_revealedSeed());
    await tester.pumpWidget(app(
      subscription: _paid,
      ticket: () async => (eligible: true, granted: true, consumed: false),
      controller: spy,
    ));
    await tester.pumpAndSettle();

    await tester.tap(goldTicket);
    await tester.pumpAndSettle();

    expect(spy.drawCalls, 1);
    expect(spy.lastDrawSrTicket, true);
  });

  testWidgets('free → 顯示鎖定灰券，點了導 paywall', (tester) async {
    await tester.pumpWidget(app(
      subscription: const SubscriptionState(),
      ticket: () async => (eligible: false, granted: false, consumed: false),
    ));
    await tester.pumpAndSettle();

    expect(goldTicket, findsNothing);
    expect(lockedTicket, findsOneWidget);

    await tester.tap(lockedTicket);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('paywall-stub')), findsOneWidget);
  });

  testWidgets('premium＋已用 → 兩種券卡都不顯示', (tester) async {
    await tester.pumpWidget(app(
      subscription: _paid,
      ticket: () async => (eligible: true, granted: true, consumed: true),
    ));
    await tester.pumpAndSettle();

    expect(goldTicket, findsNothing);
    expect(lockedTicket, findsNothing);
  });

  testWidgets('premium＋狀態讀取失敗 → fail-quiet 不顯示券卡', (tester) async {
    await tester.pumpWidget(app(
      subscription: _paid,
      ticket: () async => throw Exception('network down'),
    ));
    await tester.pumpAndSettle();

    expect(goldTicket, findsNothing);
    expect(lockedTicket, findsNothing);
  });
}

class _SeededCollection extends PracticeCollectionNotifier {
  _SeededCollection(this._ids);

  final Set<String> _ids;

  @override
  Future<Set<String>> build() async => _ids;
}

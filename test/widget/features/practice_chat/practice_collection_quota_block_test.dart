// test/widget/features/practice_chat/practice_collection_quota_block_test.dart
//
// onboarding 轉換第 6 步：練習室圖鑑的翻牌被額度擋下、告訴使用者的那一刻記一筆
// quota_block_shown（feature=practice；翻牌這邊分不出每日或每月，scope 一律
// unknown）。只是記錄：付費頁、snackbar、確認框的行為由
// practice_collection_screen_test 守，這裡只看記了什麼。替身自帶精簡版，跟主測試檔
// 的 harness 分開。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_collection_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

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

/// 翻牌鈕只錄呼叫次數（不真的抽），並開縫讓測試切 state；絕不打 API。
class _DrawSpyController extends PracticeChatController {
  _DrawSpyController(PracticeChatState seed)
      : super(
          api: PracticeChatApiService(
            invoker: (name, {required body}) async =>
                throw UnimplementedError('這個測試不應打 practice-chat'),
          ),
          repository: _FakePracticeSessionRepository(),
          sessionId: seed.sessionId,
          createdAt: seed.createdAt,
        ) {
    state = seed;
  }

  int drawCalls = 0;

  @override
  Future<void> drawNewPracticeGirl({bool srTicket = false}) async {
    drawCalls++;
  }

  @override
  Future<void> refreshDrawQuotaStatus() async {}

  void debugSetState(PracticeChatState next) => state = next;
}

/// 已解鎖一位：不是第一次進練習室。
class _SeededCollection extends PracticeCollectionNotifier {
  @override
  Future<Set<String>> build() async => {practiceGirlProfiles.first.profileId};
}

PracticeChatState _lockedSeed({bool upgradeRequired = false}) =>
    PracticeChatState(
      sessionId: 'quota-block-test',
      createdAt: DateTime(2026, 10, 27, 12),
      girl: null,
      personaId: '',
      personaLabel: '',
      difficulty: 'normal',
      difficultyLabel: '一般',
      drawStatus: PracticeDrawStatus.locked,
      drawUpgradeRequired: upgradeRequired,
    );

PracticeChatState _revealedSeed({
  int? freeAllowance,
  int? freeRemaining,
  int? extraCost,
  bool quotaExceeded = false,
}) {
  final girl = practiceGirlProfiles.first;
  return PracticeChatState(
    sessionId: 'quota-block-test',
    createdAt: DateTime(2026, 10, 27, 12),
    girl: girl,
    personaId: girl.personaId,
    personaLabel: '',
    difficulty: 'normal',
    difficultyLabel: '一般',
    drawFreeAllowance: freeAllowance,
    drawFreeRemaining: freeRemaining,
    drawExtraCost: extraCost,
    drawQuotaExceeded: quotaExceeded,
  );
}

const _starter = SubscriptionState(
  tier: SubscriptionTierHelper.starter,
  monthlyLimit: 100,
  dailyLimit: 30,
);

const _drawButton = ValueKey('collection-draw-button');

void main() {
  final sent = <Map<String, dynamic>>[];

  List<Object?> quotaBlocks() => [
        for (final e in sent)
          if (e['event'] == 'quota_block_shown') e['properties'],
      ];

  Map<String, String> practiceBlock(String source) =>
      {'feature': 'practice', 'scope': 'unknown', 'block_source': source};

  setUp(sent.clear);

  Future<void> pumpCollection(
    WidgetTester tester, {
    required _DrawSpyController controller,
    SubscriptionState subscription = const SubscriptionState(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const PracticeCollectionScreen(),
      ),
      GoRoute(
        path: '/paywall',
        builder: (context, state) => const Scaffold(
          body: Text('paywall-stub', key: ValueKey('paywall-stub')),
        ),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        practiceCollectionProvider.overrideWith(_SeededCollection.new),
        practiceChatControllerProvider.overrideWith((ref) => controller),
        subscriptionProvider
            .overrideWith((ref) => _SeededSubscriptionNotifier(subscription)),
        subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
        funnelTrackerProvider.overrideWithValue(FunnelTracker(
          invoker: (fn, {required body}) async {
            sent.add(body['event'] as Map<String, dynamic>);
            return 200;
          },
          currentUserId: () => 'practice-user',
        )),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
  }

  testWidgets('免費用戶按「換一位」：開付費頁前記一筆 practice／unknown／precheck', (tester) async {
    final controller = _DrawSpyController(_revealedSeed());
    await pumpCollection(tester, controller: controller);

    await tester.tap(find.byKey(_drawButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('paywall-stub')), findsOneWidget);
    expect(quotaBlocks(), [practiceBlock('precheck')]);
    expect(controller.drawCalls, 0);
  });

  testWidgets('付費但今天的免費翻牌用完、又沒有加抽權：開付費頁，記 precheck', (tester) async {
    final controller = _DrawSpyController(
      _revealedSeed(freeAllowance: 1, freeRemaining: 0, extraCost: 0),
    );
    await pumpCollection(tester,
        controller: controller, subscription: _starter);

    await tester.tap(find.byKey(_drawButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('paywall-stub')), findsOneWidget);
    expect(quotaBlocks(), [practiceBlock('precheck')]);
  });

  testWidgets('付費加抽但共用額度不夠：snackbar 照舊，記 precheck，不抽', (tester) async {
    final controller = _DrawSpyController(
      _revealedSeed(freeAllowance: 1, freeRemaining: 0, extraCost: 5),
    );
    // 今日剩 30 - 28 = 2 則，加抽要 5 則。
    await pumpCollection(
      tester,
      controller: controller,
      subscription: const SubscriptionState(
        tier: SubscriptionTierHelper.starter,
        monthlyLimit: 100,
        dailyLimit: 30,
        dailyMessagesUsed: 28,
      ),
    );

    await tester.tap(find.byKey(_drawButton));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(quotaBlocks(), [practiceBlock('precheck')]);
    expect(controller.drawCalls, 0);
  });

  testWidgets('翻牌事後 402：開付費頁，記一筆 server', (tester) async {
    final controller = _DrawSpyController(_lockedSeed());
    await pumpCollection(tester, controller: controller);

    controller.debugSetState(
      _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
    );
    await tester.pump();
    controller.debugSetState(_lockedSeed(upgradeRequired: true));
    // locked 脈動 repeat 中不能 settle；逐幀推進到路由轉場完。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('paywall-stub')), findsOneWidget);
    expect(quotaBlocks(), [practiceBlock('server')]);
  });

  testWidgets('翻牌事後 429（翻牌額度用完）：snackbar 照舊，記 server', (tester) async {
    final controller = _DrawSpyController(_revealedSeed());
    await pumpCollection(tester,
        controller: controller, subscription: _starter);

    controller.debugSetState(
      _revealedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
    );
    await tester.pump();
    controller.debugSetState(
      _revealedSeed(quotaExceeded: true).copyWith(errorMessage: '今日翻牌額度用完了'),
    );
    await tester.pump();

    expect(find.text('今日翻牌額度用完了'), findsOneWidget);
    expect(quotaBlocks(), [practiceBlock('server')]);
    // 失敗觸覺是兩下（90ms 間隔），把第二下的 timer 走完。
    await tester.pump(const Duration(milliseconds: 120));
  });

  testWidgets('翻牌一般失敗（不是額度）：不記', (tester) async {
    final controller = _DrawSpyController(_revealedSeed());
    await pumpCollection(tester,
        controller: controller, subscription: _starter);

    controller.debugSetState(
      _revealedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
    );
    await tester.pump();
    controller.debugSetState(
      _revealedSeed().copyWith(errorMessage: '翻牌失敗了，再試一次。'),
    );
    await tester.pump();

    expect(find.text('翻牌失敗了，再試一次。'), findsOneWidget);
    expect(quotaBlocks(), isEmpty);
    await tester.pump(const Duration(milliseconds: 120));
  });

  testWidgets('還翻得到（付費、今天還有免費次數）：直接翻，不記', (tester) async {
    final controller = _DrawSpyController(
      _revealedSeed(freeAllowance: 3, freeRemaining: 2, extraCost: 5),
    );
    await pumpCollection(tester,
        controller: controller, subscription: _starter);

    await tester.tap(find.byKey(_drawButton));
    await tester.pump();

    expect(controller.drawCalls, 1);
    expect(quotaBlocks(), isEmpty);
  });
}

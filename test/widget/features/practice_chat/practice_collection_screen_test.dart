import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_collection_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_collection_screen.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

/// 同其他 widget test 的 seeded-notifier idiom：constructor 在 super 同步初始化後
/// 直接覆寫 state；無 Supabase user 時後續 async 初始化全 no-op。
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

/// 圖鑑翻牌鈕 gating 測試絕不打 API：任何真呼叫直接炸出來。
PracticeChatApiService _unusedApi() => PracticeChatApiService(
      invoker: (name, {required body}) async =>
          throw UnimplementedError('collection test 不應打 practice-chat'),
    );

/// 同 practice_chat_screen_style_test 的 seeded-controller idiom。
class _SeededPracticeChatController extends PracticeChatController {
  _SeededPracticeChatController(PracticeChatState seed)
      : super(
          api: _unusedApi(),
          repository: _FakePracticeSessionRepository(),
          sessionId: seed.sessionId,
          createdAt: seed.createdAt,
        ) {
    state = seed;
  }
}

/// 翻牌鈕 gating spy：只錄呼叫次數（draw 不真的抽），並開縫讓測試切 state。
class _DrawSpyController extends _SeededPracticeChatController {
  _DrawSpyController(super.seed);

  int drawCalls = 0;
  int lockQuotaCalls = 0;

  @override
  Future<void> drawNewPracticeGirl() async {
    drawCalls++;
  }

  @override
  void lockDrawQuotaExceeded({
    String message = '今日額度已用完，明天再來或升級方案繼續練習。',
  }) {
    lockQuotaCalls++;
    super.lockDrawQuotaExceeded(message: message);
  }

  /// StateNotifier 的 state setter 是 protected，只能從子類開縫給測試切狀態。
  void debugSetState(PracticeChatState next) => state = next;
}

PracticeChatState _lockedSeed({
  bool upgradeRequired = false,
  bool quotaExceeded = false,
  String? errorMessage,
}) {
  return PracticeChatState(
    sessionId: 'collection-gating-test',
    createdAt: DateTime(2026, 7, 3, 12),
    girl: null,
    personaId: '',
    personaLabel: '',
    difficulty: 'normal',
    difficultyLabel: '一般',
    drawStatus: PracticeDrawStatus.locked,
    drawUpgradeRequired: upgradeRequired,
    drawQuotaExceeded: quotaExceeded,
    errorMessage: errorMessage,
  );
}

PracticeChatState _revealedSeed({
  int? freeAllowance,
  int? freeRemaining,
  int? extraCost,
  bool quotaExceeded = false,
}) {
  final girl = practiceGirlProfiles.first;
  return PracticeChatState(
    sessionId: 'collection-gating-test',
    createdAt: DateTime(2026, 7, 3, 12),
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

const _paidSubscription = SubscriptionState(
  tier: SubscriptionTierHelper.starter,
  monthlyLimit: 100,
  dailyLimit: 30,
);

PracticeCollectionNotifier _seededCollection(Set<String> unlocked) {
  final store = InMemoryPracticeCollectionStore();
  for (final id in unlocked) {
    store.add(id);
  }
  return PracticeCollectionNotifier(store);
}

List<Override> _collectionOverrides({
  Set<String> unlocked = const {},
  PracticeChatController? controller,
  SubscriptionState subscription = const SubscriptionState(),
  PracticeCollectionNotifier? collectionNotifier,
  VoidCallback? onSubscriptionRefresh,
}) {
  return [
    practiceCollectionProvider.overrideWith(
        (ref) => collectionNotifier ?? _seededCollection(unlocked)),
    practiceChatControllerProvider.overrideWith(
      (ref) => controller ?? _SeededPracticeChatController(_revealedSeed()),
    ),
    subscriptionProvider
        .overrideWith((ref) => _SeededSubscriptionNotifier(subscription)),
    // 402 導 paywall 順帶的訂閱重同步 seam：測試絕不打網路，只記呼叫。
    subscriptionScreenRefreshProvider.overrideWithValue(() async {
      onSubscriptionRefresh?.call();
    }),
  ];
}

Widget collectionApp({
  Set<String> unlocked = const {},
  PracticeChatController? controller,
  SubscriptionState subscription = const SubscriptionState(),
  PracticeCollectionNotifier? collectionNotifier,
}) {
  return ProviderScope(
    overrides: _collectionOverrides(
      unlocked: unlocked,
      controller: controller,
      subscription: subscription,
      collectionNotifier: collectionNotifier,
    ),
    child: const MaterialApp(home: PracticeCollectionScreen()),
  );
}

/// 帶 /paywall stub 的 router 版：驗證翻牌鈕 gating 導頁行為。
Widget collectionRouterApp({
  PracticeChatController? controller,
  SubscriptionState subscription = const SubscriptionState(),
  VoidCallback? onSubscriptionRefresh,
}) {
  final router = GoRouter(
    routes: [
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
    ],
  );
  return ProviderScope(
    overrides: _collectionOverrides(
      controller: controller,
      subscription: subscription,
      onSubscriptionRefresh: onSubscriptionRefresh,
    ),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  // practice_girl_001 = Alice（slow_worker → N）
  // practice_girl_004 = Mia（teasing_humor → SR）
  Future<void> pumpCollection(
    WidgetTester tester, {
    Set<String> unlocked = const {},
    Size surface = const Size(500, 1600),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(collectionApp(unlocked: unlocked));
    await tester.pump();
  }

  group('PracticeCollectionScreen', () {
    testWidgets('完成度數字與標頭正確', (tester) async {
      await pumpCollection(
        tester,
        unlocked: {'practice_girl_001', 'practice_girl_004'},
      );

      expect(find.text('角色圖鑑'), findsOneWidget); // AppBar 標題
      expect(find.text('VIBESYNC · GACHA'), findsOneWidget);
      expect(find.text('Collection'), findsOneWidget);
      expect(find.text('收藏完成度'), findsOneWidget);

      final count = tester.widget<Text>(
        find.byKey(const ValueKey('collection-completion-count')),
      );
      expect(count.data, '2');
      expect(find.text(' / 100'), findsOneWidget);
      expect(find.byKey(const ValueKey('collection-progress-fill')),
          findsOneWidget);
    });

    testWidgets('catalog 之外的髒 profileId 不灌水完成度', (tester) async {
      await pumpCollection(
        tester,
        unlocked: {'practice_girl_001', 'bogus_id'},
      );
      final count = tester.widget<Text>(
        find.byKey(const ValueKey('collection-completion-count')),
      );
      expect(count.data, '1');
    });

    testWidgets('鎖卡顯「？？？」＋大問號（無鎖頭）；解鎖卡顯名字＋職業＋星等', (tester) async {
      await pumpCollection(tester, unlocked: {'practice_girl_004'});

      // 鎖卡：practice_girl_001（Alice）未解鎖
      final lockedCard =
          find.byKey(const ValueKey('collection-card-practice_girl_001'));
      expect(lockedCard, findsOneWidget);
      expect(
        find.descendant(of: lockedCard, matching: find.text('？？？')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: lockedCard, matching: find.text('Alice')),
        findsNothing,
      );
      // 鎖頭圓徽已退役 → 換中央大「？」神秘標記
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
      final mystery = tester.widget<Text>(
        find.byKey(const ValueKey('collection-mystery-practice_girl_001')),
      );
      expect(mystery.data, '？');
      // 鎖卡無星等
      expect(
        find.descendant(
            of: lockedCard, matching: find.byIcon(Icons.star_rounded)),
        findsNothing,
      );

      // 解鎖卡：practice_girl_004（Mia，teasing_humor → SR 4 星）
      final unlockedCard =
          find.byKey(const ValueKey('collection-card-practice_girl_004'));
      expect(
        find.descendant(of: unlockedCard, matching: find.text('Mia')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: unlockedCard, matching: find.text('咖啡師')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: unlockedCard, matching: find.text('SR')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: unlockedCard, matching: find.byIcon(Icons.star_rounded)),
        findsNWidgets(4),
      );
      expect(
        find.descendant(
            of: unlockedCard,
            matching: find.byIcon(Icons.star_outline_rounded)),
        findsNWidgets(1),
      );
      expect(
        find.byKey(const ValueKey('collection-mystery-practice_girl_004')),
        findsNothing,
      );
    });

    testWidgets('稀有度篩選 chip 過濾 grid', (tester) async {
      await pumpCollection(tester);

      // 預設全部：N 的 001 與 SR 的 004 都在
      expect(find.byKey(const ValueKey('collection-card-practice_girl_001')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('collection-card-practice_girl_004')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('collection-filter-sr')));
      await tester.pump();

      // SR only：001（N）消失、004（SR）仍在
      expect(find.byKey(const ValueKey('collection-card-practice_girl_001')),
          findsNothing);
      expect(find.byKey(const ValueKey('collection-card-practice_girl_004')),
          findsOneWidget);

      // 切回全部
      await tester.tap(find.byKey(const ValueKey('collection-filter-all')));
      await tester.pump();
      expect(find.byKey(const ValueKey('collection-card-practice_girl_001')),
          findsOneWidget);
    });

    testWidgets('已解鎖卡置頂：catalog 尾端的解鎖卡排到第一格、鎖卡沉底', (tester) async {
      final last = practiceGirlProfiles.last;
      await pumpCollection(tester, unlocked: {last.profileId});

      // 惰性 grid：尾端卡若還在原位絕不會 build；找得到＝已置頂。
      final unlockedFinder =
          find.byKey(ValueKey('collection-card-${last.profileId}'));
      expect(unlockedFinder, findsOneWidget);

      // grid 順序 =（dy, dx）字典序：解鎖卡必在首張鎖卡（001）之前。
      final unlockedPos = tester.getTopLeft(unlockedFinder);
      final lockedPos = tester.getTopLeft(
        find.byKey(const ValueKey('collection-card-practice_girl_001')),
      );
      expect(
        unlockedPos.dy < lockedPos.dy ||
            (unlockedPos.dy == lockedPos.dy && unlockedPos.dx < lockedPos.dx),
        isTrue,
      );
    });

    testWidgets('解鎖組內維持圖鑑原序：001 仍排在 004 前', (tester) async {
      await pumpCollection(
        tester,
        unlocked: {'practice_girl_004', 'practice_girl_001'},
      );

      final firstPos = tester.getTopLeft(
        find.byKey(const ValueKey('collection-card-practice_girl_001')),
      );
      final secondPos = tester.getTopLeft(
        find.byKey(const ValueKey('collection-card-practice_girl_004')),
      );
      expect(
        firstPos.dy < secondPos.dy ||
            (firstPos.dy == secondPos.dy && firstPos.dx < secondPos.dx),
        isTrue,
      );
    });

    testWidgets('點鎖卡 → SnackBar「每日翻牌有機會遇到她」', (tester) async {
      await pumpCollection(tester);

      await tester
          .tap(find.byKey(const ValueKey('collection-card-practice_girl_001')));
      await tester.pump();

      expect(find.text('每日翻牌有機會遇到她'), findsOneWidget);
    });

    testWidgets('連點鎖卡不堆疊 SnackBar：一輪生命週期後全部消失', (tester) async {
      await pumpCollection(tester);

      final card =
          find.byKey(const ValueKey('collection-card-practice_girl_001'));
      // 重現真機連點。fake clock 陷阱：tap 後只 pump 一次時，ticker 首 tick
      // 才定基準（elapsed=0），入場動畫會停在 value 0，hideCurrentSnackBar
      // 就變成 reverse from 0 → 同步 dismissed → 佇列瞬間輪替、永遠堆不起來
      // （測不到 bug）。所以每次 tap 後先 pump() 定基準、再 pump(duration)
      // 真推進，讓第一條確實走到 completed / 退場中，才符合真機時序。
      await tester.tap(card);
      await tester.pump(); // 入場 ticker 定基準
      await tester.pump(const Duration(seconds: 1)); // 第一條完整入場（completed）
      await tester.tap(card); // hide：第一條開始 250ms 退場
      await tester.pump(); // 退場 ticker 定基準
      await tester.pump(const Duration(milliseconds: 100)); // 第一條退場中
      await tester.tap(card); // 退場中再點：hide 對退場中條目無新效果
      await tester.pump();

      // 連點後只允許「一輪生命週期」的殘影：從第三點起算，走過
      // 入場 250ms＋顯示 4s＋退場 250ms（frame 粒度放寬到 7s）後必須全空。
      // pre-fix（hideCurrentSnackBar）佇列堆 3 條會輪播到 ~13s 才清空＝紅；
      // post-fix（clearSnackBars）每次點都清佇列，7s 時早已全空＝綠。
      var seenDuringLifecycle = false;
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.text('每日翻牌有機會遇到她').evaluate().isNotEmpty) {
          seenDuringLifecycle = true;
        }
      }
      // sanity：這段期間至少出現過一條（確認 tap 有命中、snackbar 有播）。
      expect(seenDuringLifecycle, isTrue);
      expect(find.text('每日翻牌有機會遇到她'), findsNothing);

      // 佇列若殘留會跨頁持續輪播（root messenger 不隨本頁 dispose）：
      // 再推 10s 仍必須全空，證明沒有殘留條目排隊中。
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('每日翻牌有機會遇到她'), findsNothing);
      }
    });

    testWidgets('點解鎖卡 → 導航 /practice-chat?profileId=…（不開全圖）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 開局由 chat screen 以 startProfileId 發起（autoDispose controller 的
      // 生命週期歸唯一 watcher），圖鑑只負責把 profileId 塞進路由 query。
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const PracticeCollectionScreen(),
          ),
          GoRoute(
            path: '/practice-chat',
            builder: (context, state) => Scaffold(
              body: Text(
                'practice-chat-stub '
                'profileId=${state.uri.queryParameters['profileId']}',
                key: const ValueKey('practice-chat-stub'),
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _collectionOverrides(unlocked: {'practice_girl_004'}),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      await tester
          .tap(find.byKey(const ValueKey('collection-card-practice_girl_004')));
      await tester.pumpAndSettle();

      expect(
        find.text('practice-chat-stub profileId=practice_girl_004'),
        findsOneWidget,
      );
      // 全螢幕照片 viewer 已退役：看大圖由對話頁 profile sheet 承擔。
      expect(
        find.byKey(const ValueKey('practice-girl-full-photo-viewer')),
        findsNothing,
      );
    });
  });

  group('圖鑑翻牌鈕 gating', () {
    const drawButton = ValueKey('collection-draw-button');
    const confirmKey = ValueKey('collection-draw-confirm');
    const cancelKey = ValueKey('collection-draw-cancel');

    Future<void> pumpApp(WidgetTester tester, Widget app) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app);
      await tester.pump();
    }

    testWidgets('翻牌鈕在 Collection 標題右側顯示', (tester) async {
      await pumpApp(tester, collectionApp());

      expect(find.byKey(drawButton), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(drawButton), matching: find.text('翻牌')),
        findsOneWidget,
      );
    });

    testWidgets('locked 點擊 → 直接 drawNewPracticeGirl（每日首抽免費，Free 也放行）',
        (tester) async {
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(tester, collectionApp(controller: controller));

      await tester.tap(find.byKey(drawButton));
      await tester.pump();

      expect(controller.drawCalls, 1);
    });

    testWidgets('locked＋drawUpgradeRequired 點擊 → 導 paywall、不 draw',
        (tester) async {
      final controller = _DrawSpyController(
        _lockedSeed(upgradeRequired: true, errorMessage: '升級後每天可以翻更多陪練女孩。'),
      );
      await pumpApp(tester, collectionRouterApp(controller: controller));

      await tester.tap(find.byKey(drawButton));
      // locked 態脈動微光 repeat 中，不能 pumpAndSettle；逐幀推進到路由轉場完。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('paywall-stub')), findsOneWidget);
      expect(controller.drawCalls, 0);
    });

    testWidgets('locked＋drawQuotaExceeded 點擊 → snackbar 顯示 errorMessage、不 draw',
        (tester) async {
      final controller = _DrawSpyController(
        _lockedSeed(
            quotaExceeded: true, errorMessage: '今日額度已用完，明天再來或升級方案繼續練習。'),
      );
      await pumpApp(tester, collectionApp(controller: controller));

      await tester.tap(find.byKey(drawButton));
      await tester.pump();

      expect(find.text('今日額度已用完，明天再來或升級方案繼續練習。'), findsOneWidget);
      expect(controller.drawCalls, 0);
    });

    testWidgets('revealed＋Free 點擊（換一位）→ 導 paywall、不 draw、不彈 dialog',
        (tester) async {
      final controller = _DrawSpyController(_revealedSeed());
      await pumpApp(tester, collectionRouterApp(controller: controller));

      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle(); // revealed 無脈動，可 settle

      expect(find.byKey(const ValueKey('paywall-stub')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.drawCalls, 0);
    });

    testWidgets(
        'revealed＋免費額度用完＋payload 無加抽權（extraCost 0）→ 直接導 paywall、不彈 dialog、不 draw',
        (tester) async {
      // 訂閱快照 stale（essential 過期降 free 未同步）時 isFreeUser 擋門會放行；
      // payload 的 extraCost 是 server 真實 tier 的鏡子（free 一律 0）→ 必須擋下。
      final controller = _DrawSpyController(
        _revealedSeed(freeAllowance: 1, freeRemaining: 0, extraCost: 0),
      );
      await pumpApp(
        tester,
        collectionRouterApp(
          controller: controller,
          subscription: _paidSubscription,
        ),
      );

      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('paywall-stub')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.drawCalls, 0);
    });

    testWidgets('revealed＋付費＋免費次數用完 → 確認 dialog，確認才 draw', (tester) async {
      final controller = _DrawSpyController(
        _revealedSeed(freeAllowance: 1, freeRemaining: 0, extraCost: 5),
      );
      await pumpApp(
        tester,
        collectionApp(controller: controller, subscription: _paidSubscription),
      );

      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('今日 1 次免費換人已用完，再按一次會扣 5 則額度。'), findsOneWidget);
      expect(controller.drawCalls, 0); // 未確認前絕不 draw

      await tester.tap(find.byKey(confirmKey));
      await tester.pumpAndSettle();

      expect(controller.drawCalls, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('確認 dialog 取消 → 不 draw', (tester) async {
      final controller = _DrawSpyController(
        _revealedSeed(freeAllowance: 1, freeRemaining: 0, extraCost: 5),
      );
      await pumpApp(
        tester,
        collectionApp(controller: controller, subscription: _paidSubscription),
      );

      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(cancelKey));
      await tester.pumpAndSettle();

      expect(controller.drawCalls, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('revealed＋付費＋還有免費次數 → 直接 draw、不彈 dialog', (tester) async {
      final controller = _DrawSpyController(
        _revealedSeed(freeAllowance: 1, freeRemaining: 1, extraCost: 5),
      );
      await pumpApp(
        tester,
        collectionApp(controller: controller, subscription: _paidSubscription),
      );

      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.drawCalls, 1);
    });

    testWidgets(
        'revealed＋付費＋drawQuotaExceeded → lockDrawQuotaExceeded＋snackbar',
        (tester) async {
      final controller = _DrawSpyController(_revealedSeed(quotaExceeded: true));
      await pumpApp(
        tester,
        collectionApp(controller: controller, subscription: _paidSubscription),
      );

      await tester.tap(find.byKey(drawButton));
      await tester.pump();

      expect(controller.lockQuotaCalls, 1);
      expect(controller.drawCalls, 0);
      expect(find.text('今日額度已用完，明天再來或升級方案繼續練習。'), findsOneWidget);
    });

    testWidgets('revealed＋付費但額度不足付費翻牌 → 同鎖、不彈 dialog、不 draw', (tester) async {
      final controller = _DrawSpyController(
        _revealedSeed(freeAllowance: 1, freeRemaining: 0, extraCost: 5),
      );
      // dailyRemaining = 30 - 28 = 2 < cost 5 → 額度不足。
      const lowQuota = SubscriptionState(
        tier: SubscriptionTierHelper.starter,
        monthlyLimit: 100,
        dailyLimit: 30,
        dailyMessagesUsed: 28,
      );
      await pumpApp(
        tester,
        collectionApp(controller: controller, subscription: lowQuota),
      );

      await tester.tap(find.byKey(drawButton));
      await tester.pump();

      expect(controller.lockQuotaCalls, 1);
      expect(controller.drawCalls, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('翻牌中（isDrawing）點擊 → 防連點不重入', (tester) async {
      final controller = _DrawSpyController(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await pumpApp(tester, collectionApp(controller: controller));

      await tester.tap(find.byKey(drawButton));
      await tester.pump();

      expect(controller.drawCalls, 0);
    });

    testWidgets('repeat 鐵則：locked 脈動、revealed 後停（pumpAndSettle 不 hang）',
        (tester) async {
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(tester, collectionApp(controller: controller));
      // locked：脈動 repeat 中，逐幀推進不 settle。
      await tester.pump(const Duration(milliseconds: 700));

      controller.debugSetState(_revealedSeed());
      await tester.pump();
      // revealed 後 repeat 必停：settle 收斂＝鐵則成立（會 hang 即 fail）。
      await tester.pumpAndSettle();

      expect(find.byKey(drawButton), findsOneWidget);
    });

    testWidgets('draw 事後 402 → 直接導 paywall＋觸發訂閱重同步（不出升級 snackbar）',
        (tester) async {
      var refreshCalls = 0;
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionRouterApp(
          controller: controller,
          onSubscriptionRefresh: () => refreshCalls++,
        ),
      );

      // 模擬 drawNewPracticeGirl 在途 → 402 收場（controller 內部行為不真跑）。
      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      controller.debugSetState(
        _lockedSeed(upgradeRequired: true, errorMessage: '升級後每天可以翻更多陪練女孩。'),
      );
      // locked 脈動 repeat 中不能 settle；逐幀推進到路由轉場完。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 產品拍板：Free 額度用完絕不出加抽/升級 snackbar，一律直接進 paywall。
      expect(find.byKey(const ValueKey('paywall-stub')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // 402 常來自 stale 訂閱快照（付費過期降 free）→ 順帶重同步一次。
      expect(refreshCalls, 1);
    });

    testWidgets('draw 事後 429 → snackbar 顯示 errorMessage', (tester) async {
      final controller = _DrawSpyController(_revealedSeed());
      await pumpApp(tester, collectionApp(controller: controller));

      controller.debugSetState(
        _revealedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      controller.debugSetState(
        _revealedSeed(quotaExceeded: true).copyWith(errorMessage: '今日翻牌額度用完了'),
      );
      await tester.pump();

      expect(find.text('今日翻牌額度用完了'), findsOneWidget);
    });
  });

  group('儀式 overlay 掛圖鑑＋揭曉後新卡高亮（Task 4b）', () {
    const backKey = ValueKey('practice-draw-ceremony-back');
    const frontKey = ValueKey('practice-draw-ceremony-front');

    Future<void> pumpApp(WidgetTester tester, Widget app) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app);
      await tester.pump();
    }

    // 高亮 wrapper 邊框的實際 alpha（微光強度 proxy；等待段＝0、微光段>0）。
    double highlightBorderAlpha(WidgetTester tester, String profileId) {
      final container = tester.widget<Container>(
        find.byKey(ValueKey('collection-highlight-$profileId')),
      );
      final decoration = container.foregroundDecoration as BoxDecoration?;
      final border = decoration?.border as Border?;
      return border?.top.color.a ?? 0;
    }

    test('微光時間軸：等待段＝整條儀式 reveal 總長，收場前恆 0、收場後才亮、走完歸 0', () {
      // 等待段與儀式 reveal 共用同一常數：儀式重定時不會讓微光搶跑。
      expect(kCollectionHighlightWait, kPracticeRevealDuration);

      final totalMs =
          (kCollectionHighlightWait + kCollectionHighlightGlow).inMilliseconds;
      final glowStart = kCollectionHighlightWait.inMilliseconds / totalMs;
      expect(collectionHighlightIntensityAt(0), 0);
      expect(collectionHighlightIntensityAt(glowStart * 0.5), 0);
      expect(collectionHighlightIntensityAt(glowStart), 0); // 收場瞬間仍 0
      expect(collectionHighlightIntensityAt(glowStart + 0.02), greaterThan(0));
      expect(collectionHighlightIntensityAt(1), 0); // 收尾歸 0，不殘留
    });

    testWidgets('主路徑時序：儀式 scrim 蓋著期間微光強度 0，過整條 reveal 時間軸後才亮起', (tester) async {
      final notifier = _seededCollection(const {});
      await pumpApp(tester, collectionApp(collectionNotifier: notifier));

      await notifier.add('practice_girl_004');
      await tester.pump(); // 掛上高亮（等待段）、post-frame 捲動起跑
      await tester.pump(const Duration(milliseconds: 100)); // 捲動 ticker 定基準
      await tester
          .pump(const Duration(milliseconds: 300)); // 捲動走完 → forward 已呼叫
      await tester.pump(const Duration(milliseconds: 16)); // 微光 ticker 定基準

      // 解鎖通知＝reveal 時間軸起點；中段（scrim 全黑）微光必須還沒亮。
      await tester.pump(const Duration(seconds: 5));
      expect(highlightBorderAlpha(tester, 'practice_girl_004'), 0);

      // 過了整條 kPracticeRevealDuration（儀式收場交棒）：微光亮起、使用者看得到。
      await tester.pump(const Duration(seconds: 6));
      expect(
        highlightBorderAlpha(tester, 'practice_girl_004'),
        greaterThan(0),
      );

      // 單次 forward 收尾：settle 收斂、高亮移除不殘留。
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('collection-highlight-practice_girl_004')),
        findsNothing,
      );
    });

    testWidgets('reduce-motion：無儀式時間軸，微光直接進微光段即時亮起', (tester) async {
      final notifier = _seededCollection(const {});
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: _collectionOverrides(collectionNotifier: notifier),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const PracticeCollectionScreen(),
          ),
        ),
      );
      await tester.pump();

      await notifier.add('practice_girl_004');
      await tester.pump(); // 掛上高亮、post-frame 捲動起跑
      await tester.pump(const Duration(milliseconds: 100)); // 捲動 ticker 定基準
      await tester
          .pump(const Duration(milliseconds: 300)); // 捲動走完 → forward 已呼叫
      await tester.pump(const Duration(milliseconds: 16)); // 微光 ticker 定基準
      await tester.pump(const Duration(milliseconds: 300)); // 微光段推進

      expect(
        highlightBorderAlpha(tester, 'practice_girl_004'),
        greaterThan(0),
      );

      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('collection-highlight-practice_girl_004')),
        findsNothing,
      );
    });

    testWidgets('儀式 overlay 掛在圖鑑頁：idle 休眠、drawing 浮卡背、揭曉走完收掉', (tester) async {
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(tester, collectionApp(controller: controller));

      // 唯一掛載點：圖鑑頁 body 疊 ceremony；idle 全透明無卡。
      expect(find.byType(PracticeDrawCeremony), findsOneWidget);
      expect(find.byKey(backKey), findsNothing);
      expect(find.byKey(frontKey), findsNothing);

      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80)); // intro 入場推進

      expect(find.byKey(backKey), findsOneWidget);
      expect(find.byKey(frontKey), findsNothing);

      // 抽牌成功 → 有限 reveal 時間軸走完必收斂（含停掉翻牌鈕脈動）。
      controller.debugSetState(_revealedSeed());
      await tester.pumpAndSettle();
      expect(find.byKey(backKey), findsNothing);
      expect(find.byKey(frontKey), findsNothing);
    });

    testWidgets('翻牌解鎖 → 新卡微光高亮，單次 forward 走完自動移除（settle 收斂）', (tester) async {
      final notifier = _seededCollection({'practice_girl_001'});
      await pumpApp(tester, collectionApp(collectionNotifier: notifier));

      await notifier.add('practice_girl_004');
      await tester.pump(); // 集合新增 → listener 掛上高亮

      const highlightKey = ValueKey('collection-highlight-practice_girl_004');
      expect(find.byKey(highlightKey), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 800)); // 微光中段仍在
      expect(find.byKey(highlightKey), findsOneWidget);

      // 單次 forward 終結：settle 必收斂、高亮 wrapper 移除不殘留。
      await tester.pumpAndSettle();
      expect(find.byKey(highlightKey), findsNothing);
      expect(
        find.byKey(const ValueKey('collection-card-practice_girl_004')),
        findsOneWidget,
      );
    });

    testWidgets('filter 開著時解鎖遠端新卡 → 收 filter、捲動到新卡進視野', (tester) async {
      final notifier = _seededCollection(const {});
      await pumpApp(tester, collectionApp(collectionNotifier: notifier));

      // 開一個會把新卡濾掉的稀有度 filter。
      final last = practiceGirlProfiles.last;
      final lastRarity = practiceGirlRarityFor(last.personaId);
      final otherRarity =
          PracticeGirlRarity.values.firstWhere((r) => r != lastRarity);
      await tester.tap(find.byKey(
          ValueKey('collection-filter-${otherRarity.label.toLowerCase()}')));
      await tester.pump();
      final cardFinder =
          find.byKey(ValueKey('collection-card-${last.profileId}'));
      expect(cardFinder, findsNothing);

      await notifier.add(last.profileId);
      await tester.pump();
      await tester.pumpAndSettle(); // 收 filter＋捲動＋微光全走完

      // builder 惰性 grid：catalog 尾端的卡沒捲近絕不 build → 找得到＝已定位。
      expect(cardFinder, findsOneWidget);
      final rect = tester.getRect(cardFinder);
      expect(rect.bottom, greaterThan(0));
      expect(rect.top, lessThan(1600));
      // 高亮已走完移除。
      expect(
        find.byKey(ValueKey('collection-highlight-${last.profileId}')),
        findsNothing,
      );
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_profile.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_collection_screen.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_sfx.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';

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

/// 進場發首抽的 API 替身（Onboarding 第 1 步）：只接 grant_onboarding_draw_bonus、
/// 記呼叫次數；[fail] 時回 500，API 會丟例外，畫面要吞掉。
class _GrantRecorder {
  _GrantRecorder({this.fail = false});

  final bool fail;
  int grantCalls = 0;

  PracticeChatApiService api() => PracticeChatApiService(
        invoker: (name, {required body}) async {
          if (body['mode'] != 'grant_onboarding_draw_bonus') {
            throw UnimplementedError('collection test 只接發首抽：${body['mode']}');
          }
          grantCalls++;
          return fail
              ? const PracticeInvokeResponse(
                  status: 500,
                  data: {'error': 'bonus_grant_failed'},
                )
              : const PracticeInvokeResponse(
                  status: 200,
                  data: {'granted': true, 'consumed': false},
                );
        },
      );
}

/// 首抽發放與第一次翻牌的競態（Codex 主審第 1 輪 P2）：發放卡在 [grant] 完成之前；
/// draw_status 照 server 的樣子回——首抽發下來之前 0 次，發下來之後「剩 1 次」。
class _DelayedGrantApi {
  final grant = Completer<void>();

  /// 發放回 500（API 丟例外，畫面吞掉）。
  bool grantFails = false;
  int grantCalls = 0;

  bool get _granted => grant.isCompleted && !grantFails;

  PracticeChatApiService api() => PracticeChatApiService(
        invoker: (name, {required body}) async {
          switch (body['mode']) {
            case 'grant_onboarding_draw_bonus':
              grantCalls++;
              await grant.future;
              return grantFails
                  ? const PracticeInvokeResponse(
                      status: 500,
                      data: {'error': 'bonus_grant_failed'},
                    )
                  : const PracticeInvokeResponse(
                      status: 200,
                      data: {'granted': true, 'consumed': false},
                    );
            case 'draw_status':
              return PracticeInvokeResponse(
                status: 200,
                data: {
                  'draw': {
                    'freeAllowance': _granted ? 1 : 0,
                    'freeUsed': 0,
                    'freeRemaining': _granted ? 1 : 0,
                    'nextResetAt': '2999-01-01T04:00:00.000Z',
                  },
                },
              );
            default:
              throw UnimplementedError('競態測試不接 ${body['mode']}');
          }
        },
      );
}

/// 額度補水走真的（[_DelayedGrantApi] 回 draw_status），翻牌只記次數；server 的翻牌
/// 結果由測試用 [debugSetState] 模擬。
class _GrantRaceController extends PracticeChatController {
  _GrantRaceController(PracticeChatState seed, PracticeChatApiService api)
      : super(
          api: api,
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

  void debugSetState(PracticeChatState next) => state = next;
}

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
  String? lastLockMessage;
  bool? lastDrawSrTicket;

  @override
  Future<void> drawNewPracticeGirl({bool srTicket = false}) async {
    drawCalls++;
    lastDrawSrTicket = srTicket;
  }

  @override
  void lockDrawQuotaExceeded({required String message}) {
    lockQuotaCalls++;
    lastLockMessage = message;
    super.lockDrawQuotaExceeded(message: message);
  }

  /// 額度列 v2：圖鑑進場的唯讀補水呼叫計數（不真打 API）。
  int quotaStatusRefreshCalls = 0;

  @override
  Future<void> refreshDrawQuotaStatus() async {
    quotaStatusRefreshCalls++;
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

const _essentialSubscription = SubscriptionState(
  tier: SubscriptionTierHelper.essential,
  monthlyLimit: 800,
  dailyLimit: 120,
);

/// 付費方案今天的翻牌用完了（Onboarding 第 2 步）：翻牌是台北中午 12 點恢復，不是
/// 「明天」；Starter 可以升級，Essential 只講恢復時間。
const _drawUsedUpUpgradeable = '今天的翻牌用完了，每天中午 12 點恢復；也可以升級。';
const _drawUsedUpTopTier = '今天的翻牌用完了，每天中午 12 點恢復。';

class _SeededCollection extends PracticeCollectionNotifier {
  _SeededCollection(this._ids);

  final Set<String> _ids;

  @override
  Future<Set<String>> build() async => _ids;
}

/// 圖鑑一直載不到（網路慢、讀取還沒回來）：build 永遠不完成。
class _PendingCollection extends PracticeCollectionNotifier {
  @override
  Future<Set<String>> build() => Completer<Set<String>>().future;
}

List<Override> _collectionOverrides({
  Set<String> unlocked = const {},
  PracticeChatController? controller,
  SubscriptionState subscription = const SubscriptionState(),
  PracticeCollectionNotifier? collectionNotifier,
  VoidCallback? onSubscriptionRefresh,
  PracticeChatApiService? api,
}) {
  return [
    practiceCollectionProvider
        .overrideWith(() => collectionNotifier ?? _SeededCollection(unlocked)),
    practiceChatControllerProvider.overrideWith(
      (ref) => controller ?? _SeededPracticeChatController(_revealedSeed()),
    ),
    // 免費＋圖鑑 0 張進場會發首抽：沒指定替身就用一打就炸的 API，失敗由畫面吞掉。
    practiceChatApiServiceProvider.overrideWithValue(api ?? _unusedApi()),
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
  bool showOnboardingGuide = false,
  PracticeChatApiService? api,
}) {
  return ProviderScope(
    overrides: _collectionOverrides(
      unlocked: unlocked,
      controller: controller,
      subscription: subscription,
      collectionNotifier: collectionNotifier,
      api: api,
    ),
    child: MaterialApp(
      home: PracticeCollectionScreen(
        showOnboardingGuide: showOnboardingGuide,
      ),
    ),
  );
}

/// 帶 /paywall stub 的 router 版：驗證翻牌鈕 gating 導頁行為。
Widget collectionRouterApp({
  PracticeChatController? controller,
  SubscriptionState subscription = const SubscriptionState(),
  VoidCallback? onSubscriptionRefresh,
  PracticeChatApiService? api,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const PracticeCollectionScreen(),
      ),
      GoRoute(
        path: '/paywall',
        // 替身把入口印出來：翻牌撞牆要帶 practiceDraw（Onboarding 第 2 步）。
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              const Text('paywall-stub', key: ValueKey('paywall-stub')),
              Text('entry:${PaywallEntry.fromRouteExtra(state.extra).name}'),
            ],
          ),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: _collectionOverrides(
      controller: controller,
      subscription: subscription,
      onSubscriptionRefresh: onSubscriptionRefresh,
      api: api,
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
      expect(find.text('VIBESYNC COLLECTION'), findsOneWidget);
      expect(find.text('收藏完成度'), findsOneWidget);

      final count = tester.widget<Text>(
        find.byKey(const ValueKey('collection-completion-count')),
      );
      expect(count.data, '2');
      expect(find.text(' / 100'), findsOneWidget);
      expect(find.byKey(const ValueKey('collection-progress-fill')),
          findsOneWidget);
    });

    // 尾端從 chevron 換成品牌標記（沿用 partner_conversation_tile_test 的
    // trailing 換手 idiom）：擋掉素材被誤換或改動被還原。
    testWidgets('動態入口尾端是品牌標記，不是 chevron', (tester) async {
      await pumpCollection(tester);

      final entry = find.byKey(const ValueKey('collection-moments-entry'));
      expect(entry, findsOneWidget);
      expect(find.text('她們的動態'), findsOneWidget);

      expect(
        find.descendant(of: entry, matching: find.byType(SvgPicture)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: entry, matching: find.byIcon(Icons.chevron_right)),
        findsNothing,
      );
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

    testWidgets('鎖卡顯剪影＋鎖頭＋「尚未解鎖」；解鎖卡顯名字＋職業＋星等', (tester) async {
      await pumpCollection(tester, unlocked: {'practice_girl_004'});

      // 鎖卡：practice_girl_001（Alice）未解鎖
      final lockedCard =
          find.byKey(const ValueKey('collection-card-practice_girl_001'));
      expect(lockedCard, findsOneWidget);
      expect(
        find.descendant(of: lockedCard, matching: find.text('尚未解鎖')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: lockedCard, matching: find.text('Alice')),
        findsNothing,
      );
      // 2026-08-13 夥伴稿：中央神秘標記改回鎖頭圓徽（問號退役）。
      expect(
        find.descendant(
          of: lockedCard,
          matching: find.byIcon(Icons.lock_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('collection-mystery-practice_girl_001')),
        findsOneWidget,
      );
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

    testWidgets('點鎖卡 → SnackBar「翻牌有機會遇到她」（free 無每日字樣）', (tester) async {
      await pumpCollection(tester);

      await tester
          .tap(find.byKey(const ValueKey('collection-card-practice_girl_001')));
      await tester.pump();

      expect(find.text('翻牌有機會遇到她'), findsOneWidget);
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
        if (find.text('翻牌有機會遇到她').evaluate().isNotEmpty) {
          seenDuringLifecycle = true;
        }
      }
      // sanity：這段期間至少出現過一條（確認 tap 有命中、snackbar 有播）。
      expect(seenDuringLifecycle, isTrue);
      expect(find.text('翻牌有機會遇到她'), findsNothing);

      // 佇列若殘留會跨頁持續輪播（root messenger 不隨本頁 dispose）：
      // 再推 10s 仍必須全空，證明沒有殘留條目排隊中。
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('翻牌有機會遇到她'), findsNothing);
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

    testWidgets(
      'debrief「去圖鑑換人」用 go 收斂 stack 進來時仍有返回鍵可退場',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(500, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // 鏡射 practice_chat_screen.dart 的 onNewPartner：go 收斂 stack，
        // 圖鑑頁沒有東西可 pop——標準 AppBar 預設返回鍵不會生成。
        final router = GoRouter(
          initialLocation: '/practice-collection',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(
                body: Text('home-stub', key: ValueKey('home-stub')),
              ),
            ),
            GoRoute(
              path: '/practice-collection',
              builder: (context, state) => const PracticeCollectionScreen(),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: _collectionOverrides(),
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();

        final backButton = find.byIcon(Icons.arrow_back);
        expect(backButton, findsOneWidget);

        await tester.tap(backButton);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('home-stub')), findsOneWidget);
      },
    );
  });

  group('onboarding 落地引導（Sydney 泡泡）', () {
    const guideKey = ValueKey('collection-onboarding-guide');
    const drawButton = ValueKey('collection-draw-button');
    const guideMessage = '哈囉！這裡是角色圖鑑～先按右上角的『翻牌』，抽出你的第一位練習夥伴吧！';

    // locked seed 下翻牌鈕脈動微光會 repeat，pumpAndSettle 會 hang（檔頭鐵則）；
    // 一律顯式 pump：入場動畫 200ms，多推 250ms 讓它走完。
    Future<void> pumpApp(WidgetTester tester, Widget app) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    testWidgets('預設（非 onboarding 入口）不出引導層', (tester) async {
      await pumpApp(tester, collectionApp());

      expect(find.byKey(guideKey), findsNothing);
      expect(find.text(guideMessage), findsNothing);
    });

    testWidgets('showOnboardingGuide 出引導層，文案逐字正確', (tester) async {
      await pumpApp(tester, collectionApp(showOnboardingGuide: true));

      expect(find.byKey(guideKey), findsOneWidget);
      expect(find.text(guideMessage), findsOneWidget);
    });

    testWidgets('點任何地方收掉引導層，翻牌鈕恢復可點', (tester) async {
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(showOnboardingGuide: true, controller: controller),
      );

      // 引導層蓋著時：第一下點擊被引導層吸收（收引導），不觸發翻牌。
      await tester.tap(find.byKey(guideKey));
      await tester.pump();
      expect(find.byKey(guideKey), findsNothing);
      expect(controller.drawCalls, 0);

      await tester.tap(find.byKey(drawButton));
      await tester.pump();
      expect(controller.drawCalls, 1);
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

    testWidgets('翻牌鈕在圖鑑摘要右側顯示', (tester) async {
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

    testWidgets('locked＋已收藏全池 → 先提示可能重複；取消不抽、確認才抽', (tester) async {
      final controller = _DrawSpyController(_lockedSeed());
      final allUnlocked = practiceGirlProfiles.map((p) => p.profileId).toSet();
      await pumpApp(
        tester,
        collectionApp(controller: controller, unlocked: allUnlocked),
      );

      await tester.tap(find.byKey(drawButton));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('角色已集滿'), findsOneWidget);
      expect(find.text('已收藏 100/100，接下來可能抽到重複角色。'), findsOneWidget);
      expect(find.text('仍要翻牌'), findsOneWidget);
      expect(controller.drawCalls, 0);

      await tester.tap(find.byKey(cancelKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.drawCalls, 0);

      await tester.tap(find.byKey(drawButton));
      await tester.pump();
      await tester.tap(find.byKey(confirmKey));
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
      expect(find.text('entry:practiceDraw'), findsOneWidget);
      expect(controller.drawCalls, 0);
    });

    testWidgets('locked＋drawQuotaExceeded 點擊 → snackbar 顯示 errorMessage、不 draw',
        (tester) async {
      final controller = _DrawSpyController(
        _lockedSeed(quotaExceeded: true, errorMessage: _drawUsedUpUpgradeable),
      );
      await pumpApp(tester, collectionApp(controller: controller));

      await tester.tap(find.byKey(drawButton));
      await tester.pump();

      expect(find.text(_drawUsedUpUpgradeable), findsOneWidget);
      expect(controller.drawCalls, 0);
    });

    testWidgets('locked＋drawQuotaExceeded 沒有訊息 → 照方案講中午 12 點恢復（Essential 不提升級）',
        (tester) async {
      final controller = _DrawSpyController(_lockedSeed(quotaExceeded: true));
      await pumpApp(
        tester,
        collectionApp(
          controller: controller,
          subscription: _essentialSubscription,
        ),
      );

      await tester.tap(find.byKey(drawButton));
      await tester.pump();

      expect(find.text(_drawUsedUpTopTier), findsOneWidget);
      expect(find.textContaining('明天'), findsNothing);
      expect(controller.drawCalls, 0);
    });

    testWidgets('revealed＋Free 點擊（換一位）→ 導 paywall、不 draw、不彈 dialog',
        (tester) async {
      final controller = _DrawSpyController(_revealedSeed());
      await pumpApp(tester, collectionRouterApp(controller: controller));

      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle(); // revealed 無脈動，可 settle

      expect(find.byKey(const ValueKey('paywall-stub')), findsOneWidget);
      expect(find.text('entry:practiceDraw'), findsOneWidget);
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
      expect(find.text('entry:practiceDraw'), findsOneWidget);
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

    testWidgets('已收藏全池＋付費翻牌 → 重複風險與扣額度合併成單一確認窗', (tester) async {
      final controller = _DrawSpyController(
        _revealedSeed(freeAllowance: 1, freeRemaining: 0, extraCost: 5),
      );
      final allUnlocked = practiceGirlProfiles.map((p) => p.profileId).toSet();
      await pumpApp(
        tester,
        collectionApp(
          controller: controller,
          subscription: _paidSubscription,
          unlocked: allUnlocked,
        ),
      );

      await tester.tap(find.byKey(drawButton));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('角色已集滿'), findsOneWidget);
      expect(
        find.textContaining('已收藏 100/100，接下來可能抽到重複角色。'),
        findsOneWidget,
      );
      expect(
        find.textContaining('今日 1 次免費換人已用完，再按一次會扣 5 則額度。'),
        findsOneWidget,
      );
      expect(find.text('要扣額度翻牌嗎？'), findsNothing);
      expect(controller.drawCalls, 0);

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
      expect(controller.lastLockMessage, _drawUsedUpUpgradeable);
      expect(find.text(_drawUsedUpUpgradeable), findsOneWidget);
    });

    testWidgets('revealed＋Essential＋drawQuotaExceeded → 只講中午 12 點恢復，不叫他升級',
        (tester) async {
      final controller = _DrawSpyController(_revealedSeed(quotaExceeded: true));
      await pumpApp(
        tester,
        collectionApp(
          controller: controller,
          subscription: _essentialSubscription,
        ),
      );

      await tester.tap(find.byKey(drawButton));
      await tester.pump();

      expect(controller.lockQuotaCalls, 1);
      expect(controller.lastLockMessage, _drawUsedUpTopTier);
      expect(find.text(_drawUsedUpTopTier), findsOneWidget);
      expect(find.textContaining('升級'), findsNothing);
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
      expect(controller.lastLockMessage, _drawUsedUpUpgradeable);
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

    testWidgets('AI turn 落盤中 → 翻牌鈕停用且不呼叫 draw', (tester) async {
      final controller = _DrawSpyController(
        _revealedSeed().copyWith(isPersistingTurn: true),
      );
      await pumpApp(
        tester,
        collectionApp(controller: controller, subscription: _paidSubscription),
      );

      final button = tester.widget<GestureDetector>(find.byKey(drawButton));
      expect(button.onTap, isNull);
      await tester.tap(find.byKey(drawButton), warnIfMissed: false);
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

    testWidgets('進場即發唯讀額度補水（額度列 v2）', (tester) async {
      final controller = _DrawSpyController(_revealedSeed());
      await pumpApp(tester, collectionApp(controller: controller));
      await tester.pump(); // post-frame callback 落地

      expect(controller.quotaStatusRefreshCalls, 1);
    });

    // Onboarding 第 1 步（決策 C，Eric 2026-10-27）：沒對象的免費新用戶一進練習室
    // 就拿到那一次首抽，按翻牌抽得到人；伺服器一人一列、重呼冪等。
    group('進場發首抽', () {
      testWidgets('免費＋圖鑑 0 張：發一次首抽，發完重新補水額度列', (tester) async {
        final grants = _GrantRecorder();
        final controller = _DrawSpyController(_lockedSeed());
        await pumpApp(
          tester,
          collectionApp(controller: controller, api: grants.api()),
        );
        await tester.pump();
        await tester.pump();

        expect(grants.grantCalls, 1);
        // 進場一次＋發完首抽一次。
        expect(controller.quotaStatusRefreshCalls, 2);
      });

      testWidgets('付費帳號：不發首抽', (tester) async {
        final grants = _GrantRecorder();
        final controller = _DrawSpyController(_lockedSeed());
        await pumpApp(
          tester,
          collectionApp(
            controller: controller,
            subscription: _paidSubscription,
            api: grants.api(),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(grants.grantCalls, 0);
        expect(controller.quotaStatusRefreshCalls, 1);
      });

      testWidgets('免費但圖鑑已經有角色：不發首抽', (tester) async {
        final grants = _GrantRecorder();
        final controller = _DrawSpyController(_lockedSeed());
        await pumpApp(
          tester,
          collectionApp(
            controller: controller,
            unlocked: {'practice_girl_001'},
            api: grants.api(),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(grants.grantCalls, 0);
        expect(controller.quotaStatusRefreshCalls, 1);
      });

      testWidgets('圖鑑還在讀：讀取中的 0 張不算數，先不發', (tester) async {
        final grants = _GrantRecorder();
        final controller = _DrawSpyController(_lockedSeed());
        await pumpApp(
          tester,
          collectionApp(
            controller: controller,
            collectionNotifier: _PendingCollection(),
            api: grants.api(),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(grants.grantCalls, 0);
      });

      testWidgets('發首抽失敗：圖鑑照常、不跳錯誤；按翻牌照舊 402 → 付費頁', (tester) async {
        final grants = _GrantRecorder(fail: true);
        final controller = _DrawSpyController(_lockedSeed());
        await pumpApp(
          tester,
          collectionRouterApp(controller: controller, api: grants.api()),
        );
        await tester.pump();
        await tester.pump();

        expect(grants.grantCalls, 1);
        expect(controller.quotaStatusRefreshCalls, 1, reason: '沒發成就不重新補水');
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byKey(drawButton), findsOneWidget);

        // 按翻牌照舊直接翻、由 server 裁決；server 回 402 → 付費頁（後備路徑不變）。
        await tester.tap(find.byKey(drawButton));
        await tester.pump();
        expect(controller.drawCalls, 1);
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

        expect(find.byKey(const ValueKey('paywall-stub')), findsOneWidget);
        expect(find.text('entry:practiceDraw'), findsOneWidget);
      });

      // Codex 主審第 1 輪 P2：首抽在背景發，發放比第一次翻牌慢時，人會被 402 鎖在付費頁。
      Finder spinnerOnDrawButton() => find.descendant(
            of: find.byKey(drawButton),
            matching: find.byType(CircularProgressIndicator),
          );

      Future<void> serverReplies402(
        WidgetTester tester,
        _GrantRaceController controller,
      ) async {
        controller.debugSetState(
          _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
        );
        await tester.pump();
        controller.debugSetState(
          _lockedSeed(upgradeRequired: true, errorMessage: '升級後每天可以翻更多陪練女孩。'),
        );
        // locked 脈動 repeat 中不能 settle；逐幀推進到路由轉場完（含失敗觸覺第二下）。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      testWidgets('延遲發放、402 先回：首抽發下來後再按翻牌，抽得到、不會再進付費頁', (tester) async {
        final grants = _DelayedGrantApi();
        final controller = _GrantRaceController(_lockedSeed(), grants.api());
        await pumpApp(
          tester,
          collectionRouterApp(controller: controller, api: grants.api()),
        );
        await tester.pump();
        expect(grants.grantCalls, 1, reason: '發放卡在半路');

        // 402 先回（例如等發放逾時後送出的那一次）：鎖住、開付費頁。
        await serverReplies402(tester, controller);
        expect(find.text('entry:practiceDraw'), findsOneWidget);
        expect(controller.currentState.drawUpgradeRequired, isTrue);

        // 首抽這時才發下來：補水看到還有 1 次，解除 402 的鎖。
        grants.grant.complete();
        await tester.pump();
        await tester.pump();
        expect(controller.currentState.drawUpgradeRequired, isFalse);
        expect(controller.currentState.errorMessage, isNull);

        // 關掉付費頁：額度列寫著首抽還在，按翻牌照常翻、不再進付費頁。
        GoRouter.of(tester.element(find.byKey(const ValueKey('paywall-stub'))))
            .pop();
        // 退場轉場走完前 Navigator 會擋住點擊：推過一秒再按。
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.byKey(const ValueKey('paywall-stub')), findsNothing);
        expect(find.text('免費首抽 剩 1 次'), findsOneWidget);

        await tester.tap(find.byKey(drawButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.drawCalls, 1);
        expect(find.byKey(const ValueKey('paywall-stub')), findsNothing);
      });

      testWidgets('發放還在路上就按翻牌：翻牌鈕先轉圈等，發放完才翻、不會撞 402', (tester) async {
        final grants = _DelayedGrantApi();
        final controller = _GrantRaceController(_lockedSeed(), grants.api());
        await pumpApp(
          tester,
          collectionRouterApp(controller: controller, api: grants.api()),
        );
        await tester.pump();

        await tester.tap(find.byKey(drawButton));
        await tester.pump();
        expect(controller.drawCalls, 0, reason: '首抽還沒發下來，先不送');
        expect(spinnerOnDrawButton(), findsOneWidget);

        await tester.tap(find.byKey(drawButton), warnIfMissed: false);
        await tester.pump();
        expect(controller.drawCalls, 0, reason: '轉圈時不能再按');

        grants.grant.complete();
        await tester.pump();
        await tester.pump();
        expect(controller.drawCalls, 1);
        expect(spinnerOnDrawButton(), findsNothing);
        expect(find.byKey(const ValueKey('paywall-stub')), findsNothing);
        expect(find.text('免費首抽 剩 1 次'), findsOneWidget);
      });

      testWidgets('發放失敗：發放中按的翻牌照常送出，server 回 402 → 付費頁', (tester) async {
        final grants = _DelayedGrantApi()..grantFails = true;
        final controller = _GrantRaceController(_lockedSeed(), grants.api());
        await pumpApp(
          tester,
          collectionRouterApp(controller: controller, api: grants.api()),
        );
        await tester.pump();

        await tester.tap(find.byKey(drawButton));
        await tester.pump();
        expect(controller.drawCalls, 0);

        grants.grant.complete();
        await tester.pump();
        await tester.pump();
        expect(controller.drawCalls, 1, reason: '發放失敗也照常送出，由 server 裁決');

        // server 沒有首抽 → 402 → 付費頁（後備路徑不變），鎖也不會被解除。
        await serverReplies402(tester, controller);
        expect(find.text('entry:practiceDraw'), findsOneWidget);
        expect(controller.currentState.drawUpgradeRequired, isTrue);
      });

      testWidgets('發放卡住超過等候上限：不再等，照常送出、由 server 裁決', (tester) async {
        final grants = _DelayedGrantApi();
        final controller = _GrantRaceController(_lockedSeed(), grants.api());
        await pumpApp(
          tester,
          collectionApp(controller: controller, api: grants.api()),
        );
        await tester.pump();

        await tester.tap(find.byKey(drawButton));
        await tester.pump();
        expect(controller.drawCalls, 0);

        await tester.pump(kFirstDrawGrantWait);
        await tester.pump();
        expect(controller.drawCalls, 1);
        expect(spinnerOnDrawButton(), findsNothing);

        // 收尾：讓卡住的發放結束，不留懸著的請求。
        grants.grant.complete();
        await tester.pump();
      });
    });

    testWidgets('額度列（付費）：有已知額度＋未過重置點 → 顯示「今日免費翻牌 剩 x / y」', (tester) async {
      final controller = _DrawSpyController(
        _revealedSeed(freeAllowance: 3, freeRemaining: 2)
            .copyWith(drawNextResetAt: '2999-01-01T04:00:00.000Z'),
      );
      await pumpApp(
        tester,
        collectionApp(controller: controller, subscription: _paidSubscription),
      );

      expect(find.text('今日免費翻牌 剩 2 / 3'), findsOneWidget);
    });

    testWidgets('額度列（免費）：只有那一次首抽 → 「免費首抽 剩 1 次」，不寫今日', (tester) async {
      final controller = _DrawSpyController(
        _lockedSeed().copyWith(
          drawFreeAllowance: 1,
          drawFreeRemaining: 1,
          drawNextResetAt: '2999-01-01T04:00:00.000Z',
        ),
      );
      await pumpApp(tester, collectionApp(controller: controller));

      expect(find.text('免費首抽 剩 1 次'), findsOneWidget);
      expect(find.textContaining('今日免費翻牌'), findsNothing);
    });

    testWidgets('額度列寧缺勿誤：過了重置點或 allowance 0 都不顯示', (tester) async {
      const lineKey = ValueKey('collection-free-quota-line');

      // 過了 nextResetAt：窗已翻轉、數字失真 → 不顯示。
      final expired = _DrawSpyController(
        _revealedSeed(freeAllowance: 3, freeRemaining: 2)
            .copyWith(drawNextResetAt: '2020-01-01T04:00:00.000Z'),
      );
      await pumpApp(tester, collectionApp(controller: expired));
      expect(find.byKey(lineKey), findsNothing);

      // allowance 0（Free 無每日額度）：沒有可顯示的配額。
      final zero = _DrawSpyController(
        _revealedSeed(freeAllowance: 0, freeRemaining: 0)
            .copyWith(drawNextResetAt: '2999-01-01T04:00:00.000Z'),
      );
      await pumpApp(tester, collectionApp(controller: zero));
      expect(find.byKey(lineKey), findsNothing);
    });

    // 2026-08-13 夥伴稿：卡片不再有稀有度常駐光（SR 繞框光段整組拆除），
    // 稀有度只由左上角 badge 與星等表示，對應測試一併退役。

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
      expect(find.text('entry:practiceDraw'), findsOneWidget);
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

      // 失敗觸覺是兩下（90ms 間隔），把第二下的 timer 走完避免殘留。
      await tester.pump(const Duration(milliseconds: 120));
    });
  });

  group('翻牌儀式掛圖鑑＋收卡飛進那一格（V3）', () {
    const backKey = ValueKey('practice-draw-ceremony-back');
    const frontKey = ValueKey('practice-draw-ceremony-front');
    const continueKey = ValueKey('practice-draw-ceremony-continue');
    const orbKey = ValueKey('practice-draw-ceremony-archive-orb');

    Future<void> pumpApp(WidgetTester tester, Widget app) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app);
      await tester.pump();
    }

    PracticeChatState revealedWith(PracticeGirlProfile girl) =>
        _revealedSeed().copyWith(girl: girl, personaId: girl.personaId);

    /// 抽牌 → 卡背入場走完 → server 回來（揭曉起點：onRevealTarget 捲動起跑）。
    /// [unlockInto]：抽中當下同一輪就寫進圖鑑集合。production 的 +1 要等草稿存完才到、
    /// 可能晚一兩幀；晚到的情況見「解鎖晚到」那一條。
    Future<void> drawAndReveal(
      WidgetTester tester,
      _DrawSpyController controller,
      PracticeGirlProfile girl, {
      _SeededCollection? unlockInto,
    }) async {
      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      controller.debugSetState(revealedWith(girl));
      unlockInto?.add(girl.profileId);
      await tester.pump();
    }

    // 高亮 wrapper 邊框的實際 alpha（發光強度 proxy；落位前＝0、落位後>0）。
    double highlightBorderAlpha(WidgetTester tester, String profileId) {
      final container = tester.widget<Container>(
        find.byKey(ValueKey('collection-highlight-$profileId')),
      );
      final decoration = container.foregroundDecoration as BoxDecoration?;
      final border = decoration?.border as Border?;
      return border?.top.color.a ?? 0;
    }

    test('發光時間軸：前 8% 快速亮起接住光球、停到 40%、之後淡出，收尾歸 0', () {
      expect(collectionHighlightIntensityAt(0), 0);
      expect(collectionHighlightIntensityAt(0.04), closeTo(0.5, 1e-9));
      expect(collectionHighlightIntensityAt(0.08), 1);
      expect(collectionHighlightIntensityAt(0.4), 1);
      expect(collectionHighlightIntensityAt(0.7), inExclusiveRange(0, 1));
      expect(collectionHighlightIntensityAt(1), 0); // 收尾歸 0，不殘留
    });

    testWidgets('儀式掛在整頁最上層（Scaffold 之外）：揭曉時連 AppBar 一起蓋住', (tester) async {
      await pumpApp(tester, collectionApp());

      final ceremony = find.byType(PracticeDrawCeremony);
      expect(ceremony, findsOneWidget);
      expect(
        find.ancestor(of: ceremony, matching: find.byType(Scaffold)),
        findsNothing,
      );
    });

    testWidgets('idle 休眠、drawing 浮卡背、揭曉後停住，點擊收卡後收掉', (tester) async {
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(tester, collectionApp(controller: controller));

      // idle：全透明無卡。
      expect(find.byKey(backKey), findsNothing);
      expect(find.byKey(frontKey), findsNothing);

      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160)); // 入場推進

      expect(find.byKey(backKey), findsOneWidget);
      expect(find.byKey(frontKey), findsNothing);

      // 抽牌成功 → 有限揭曉時間軸走完停住（含停掉翻牌鈕脈動）：pumpAndSettle 收斂。
      controller.debugSetState(_revealedSeed());
      await tester.pumpAndSettle();
      expect(find.byKey(frontKey), findsOneWidget);

      await tester.tap(find.byKey(continueKey));
      await tester.pumpAndSettle();
      expect(find.byKey(backKey), findsNothing);
      expect(find.byKey(frontKey), findsNothing);
    });

    testWidgets('主路徑：揭曉開始就捲到那一格；停住時不亮，光球落進那一格才亮，走完移除', (tester) async {
      final mia = practiceGirlProfiles
          .firstWhere((p) => p.profileId == 'practice_girl_004');
      final notifier = _SeededCollection({'practice_girl_001'});
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(controller: controller, collectionNotifier: notifier),
      );

      await drawAndReveal(tester, controller, mia, unlockInto: notifier);

      const highlightKey = ValueKey('collection-highlight-practice_girl_004');
      expect(find.byKey(highlightKey), findsOneWidget);
      expect(highlightBorderAlpha(tester, mia.profileId), 0);

      await tester.pumpAndSettle(); // 揭曉走完停住：圖鑑那一格還不亮
      expect(find.byKey(frontKey), findsOneWidget);
      expect(highlightBorderAlpha(tester, mia.profileId), 0);

      await tester.tap(find.byKey(continueKey));
      await tester.pump(); // 收卡起飛
      // 光球飛向剛抽到的那一格（儀式滿版在原點：本地座標＝global）。
      final orb = tester.widget<CustomPaint>(find.byKey(orbKey));
      expect(debugArchiveOrbTarget(orb.painter!),
          tester.getRect(find.byKey(highlightKey)));

      await tester.pump(const Duration(milliseconds: 300)); // 落位前
      expect(highlightBorderAlpha(tester, mia.profileId), 0);
      await tester.pump(const Duration(milliseconds: 200)); // 過 0.45 s：落位、起跑
      await tester.pump(const Duration(milliseconds: 50)); // 發光第一幀
      expect(highlightBorderAlpha(tester, mia.profileId), greaterThan(0));

      // 單次 forward 收尾：settle 收斂、高亮移除不殘留。
      await tester.pumpAndSettle();
      expect(find.byKey(highlightKey), findsNothing);
      expect(find.byKey(frontKey), findsNothing);
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('reduce-motion：沒有儀式畫面，抽中當下捲到那一格、捲動到位就亮', (tester) async {
      final mia = practiceGirlProfiles
          .firstWhere((p) => p.profileId == 'practice_girl_004');
      final notifier = _SeededCollection(const {});
      final controller = _DrawSpyController(_lockedSeed());
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: _collectionOverrides(
            controller: controller,
            collectionNotifier: notifier,
          ),
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

      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      controller.debugSetState(revealedWith(mia));
      notifier.add(mia.profileId);
      await tester.pump(); // 抽中當下：掛上高亮、post-frame 捲動起跑
      expect(find.byKey(frontKey), findsNothing); // 沒有揭曉畫面
      await tester.pump(const Duration(milliseconds: 100)); // 捲動 ticker 定基準
      await tester.pump(const Duration(milliseconds: 400)); // 捲動走完 → 補亮
      await tester.pump(const Duration(milliseconds: 100)); // 發光段推進

      expect(highlightBorderAlpha(tester, mia.profileId), greaterThan(0));

      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('collection-highlight-practice_girl_004')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('儀式蓋住整頁時，讀屏碰不到底下的翻牌鈕與返回鍵；收掉後恢復', (tester) async {
      final handle = tester.ensureSemantics();
      final mia = practiceGirlProfiles
          .firstWhere((p) => p.profileId == 'practice_girl_004');
      final notifier = _SeededCollection({'practice_girl_001'});
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(
          controller: controller,
          collectionNotifier: notifier,
          subscription: _paidSubscription,
        ),
      );
      // 付費、今天還有免費換人：底下的翻牌鈕一被觸發就會直接再抽一次（不跳確認）。
      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      controller.debugSetState(revealedWith(mia).copyWith(
        drawFreeAllowance: 3,
        drawFreeRemaining: 2,
        drawExtraCost: 5,
      ));
      notifier.add(mia.profileId);
      await tester.pumpAndSettle(); // 揭曉走完、停住
      expect(find.byKey(frontKey), findsOneWidget);

      bool reachable(Finder finder) {
        final node = tester.getSemantics(finder);
        return node.attached &&
            node.getSemanticsData().hasAction(SemanticsAction.tap);
      }

      final drawButton = find.byKey(const ValueKey('collection-draw-button'));
      final backButton = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      );
      expect(reachable(drawButton), isFalse, reason: '停住時不能再抽一次');
      expect(reachable(backButton), isFalse, reason: '返回鍵在儀式底下');
      expect(find.bySemanticsLabel(RegExp('已抽到')), findsOneWidget);
      expect(controller.drawCalls, 0);

      await tester.tap(find.byKey(continueKey));
      await tester.pumpAndSettle(); // 收卡完成、儀式收掉
      expect(reachable(drawButton), isTrue);
      expect(reachable(backButton), isTrue);
      handle.dispose();
    });

    testWidgets('集滿後抽到重複角色：一樣捲到原本那一格，收卡後發光', (tester) async {
      final alice = practiceGirlProfiles.first;
      final notifier = _SeededCollection({alice.profileId});
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(controller: controller, collectionNotifier: notifier),
      );

      await drawAndReveal(tester, controller, alice); // 集合不變（重複）
      final highlightKey = ValueKey('collection-highlight-${alice.profileId}');
      expect(find.byKey(highlightKey), findsOneWidget);

      await tester.pumpAndSettle();
      await tester.tap(find.byKey(continueKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // 落位、起跑
      await tester.pump(const Duration(milliseconds: 50)); // 發光第一幀
      expect(highlightBorderAlpha(tester, alice.profileId), greaterThan(0));

      await tester.pumpAndSettle();
      expect(find.byKey(highlightKey), findsNothing);
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('重新整理圖鑑（集合變大）不會觸發捲動或高亮', (tester) async {
      final notifier = _SeededCollection({'practice_girl_001'});
      await pumpApp(tester, collectionApp(collectionNotifier: notifier));

      notifier.add('practice_girl_004');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('collection-highlight-practice_girl_004')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('collection-card-practice_girl_004')),
        findsOneWidget,
      );
    });

    testWidgets('filter 開著時抽到被濾掉的遠端卡 → 收 filter、捲動到那一格進視野', (tester) async {
      final notifier = _SeededCollection(const {});
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(controller: controller, collectionNotifier: notifier),
      );

      // 開一個會把這張卡濾掉的稀有度 filter。
      final last = practiceGirlProfiles.last;
      final otherRarity =
          PracticeGirlRarity.values.firstWhere((r) => r != last.rarity);
      await tester.tap(find.byKey(
          ValueKey('collection-filter-${otherRarity.label.toLowerCase()}')));
      await tester.pump();
      final cardFinder =
          find.byKey(ValueKey('collection-card-${last.profileId}'));
      expect(cardFinder, findsNothing);

      await drawAndReveal(tester, controller, last, unlockInto: notifier);
      await tester.pumpAndSettle(); // 收 filter＋捲動走完，儀式停住

      // builder 惰性 grid：catalog 尾端的卡沒捲近絕不 build → 找得到＝已定位。
      expect(cardFinder, findsOneWidget);
      final rect = tester.getRect(cardFinder);
      expect(rect.bottom, greaterThan(0));
      expect(rect.top, lessThan(1600));

      await tester.tap(find.byKey(continueKey));
      await tester.pumpAndSettle(); // 收卡＋發光走完
      expect(
        find.byKey(ValueKey('collection-highlight-${last.profileId}')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('抽牌中其他狀態更新（仍是 drawing）不會讓儀式淡出，結果回來照常揭曉', (tester) async {
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(tester, collectionApp(controller: controller));
      final drawing =
          _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing);

      controller.debugSetState(drawing);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600)); // 入場走完
      // 練習室還在跑的提示剛好回來：狀態變了，但仍在抽牌中。
      controller.debugSetState(drawing.copyWith(hintUsedCount: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600)); // 淡出要 0.5 s
      expect(find.byKey(backKey), findsOneWidget, reason: '卡背不該被當成失敗淡掉');

      controller.debugSetState(_revealedSeed());
      await tester.pumpAndSettle();
      expect(find.byKey(frontKey), findsOneWidget); // 照常揭曉、停住

      await tester.tap(find.byKey(continueKey));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('抽牌中離開圖鑑又回來：結果回來時照樣揭曉（接著走完卡背入場）', (tester) async {
      final controller = _DrawSpyController(_lockedSeed());
      final showPage = ValueNotifier(true);
      addTearDown(showPage.dispose);
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: _collectionOverrides(controller: controller),
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: showPage,
              builder: (context, show, _) => show
                  ? const PracticeCollectionScreen()
                  // 離開圖鑑時上一頁（練習室）仍在聽 controller，它不會被 dispose。
                  : Consumer(
                      builder: (context, ref, _) {
                        ref.watch(practiceChatControllerProvider);
                        return const SizedBox.expand();
                      },
                    ),
            ),
          ),
        ),
      );
      await tester.pump();

      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      showPage.value = false; // 抽牌中離開圖鑑：儀式卸載
      await tester.pump();
      showPage.value = true; // server 回來前又回到圖鑑：新的儀式還是 hidden
      await tester.pump();
      expect(find.byKey(backKey), findsNothing);

      controller.debugSetState(_revealedSeed());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(backKey), findsOneWidget); // 接著走卡背入場
      await tester.pumpAndSettle();
      expect(find.byKey(frontKey), findsOneWidget); // 揭曉、停住
      // 新的圖鑑頁沒有抽牌前的紀錄：不掛 NEW、也不寫「已收藏」（寧可少掛、不錯掛）。
      expect(
        find.byKey(const ValueKey('practice-draw-ceremony-new-tag')),
        findsNothing,
      );
      expect(find.textContaining('已收藏'), findsNothing);

      await tester.tap(find.byKey(continueKey));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('解鎖晚一兩幀才到：那一格仍先排進已解鎖那段，收卡光球飛向它', (tester) async {
      // 用 view 定尺寸（430 寬的大螢幕 iPhone）：捲動估算讀 MediaQuery，要和實際版面一致。
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // 已解鎖 12 張；目標在鎖卡段的第 28 張。還沒解鎖時排第 40 格（第 20 列），
      // 解鎖後排第 12 格（第 6 列）：估算若用舊排序，會捲到離它十幾列外的地方。
      final target = practiceGirlProfiles[40];
      final notifier = _SeededCollection({
        for (final g in practiceGirlProfiles.take(12)) g.profileId,
      });
      final controller = _DrawSpyController(_lockedSeed());
      await tester.pumpWidget(
        collectionApp(controller: controller, collectionNotifier: notifier),
      );
      await tester.pump();

      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600)); // 入場走完
      controller.debugSetState(revealedWith(target)); // R0：捲動起跑，還沒解鎖
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16)); // 過了一幀
      notifier.add(target.profileId); // 圖鑑 +1 晚到
      await tester.pumpAndSettle(); // 揭曉走完停住

      await tester.tap(find.byKey(continueKey));
      await tester.pump(); // 收卡起飛
      final orb = tester.widget<CustomPaint>(find.byKey(orbKey));
      final highlight =
          find.byKey(ValueKey('collection-highlight-${target.profileId}'));
      expect(debugArchiveOrbTarget(orb.painter!), isNotNull,
          reason: '那一格要在畫面內，光球才不會原地收掉');
      expect(debugArchiveOrbTarget(orb.painter!), tester.getRect(highlight));

      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('reduce-motion＋圖鑑 +1 晚一幀才到：一樣捲到那一格，捲動到位才亮', (tester) async {
      final last = practiceGirlProfiles.last;
      final notifier =
          _SeededCollection({practiceGirlProfiles.first.profileId});
      final controller = _DrawSpyController(_lockedSeed());
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: _collectionOverrides(
            controller: controller,
            collectionNotifier: notifier,
          ),
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

      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      controller.debugSetState(revealedWith(last));
      await tester.pump(); // 抽中當下：掛上高亮、捲動起跑（這張卡先排進已解鎖那段）
      notifier.add(last.profileId); // 圖鑑 +1 晚到（草稿存完才解鎖）
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400)); // 捲動走完 → 補亮
      await tester.pump(const Duration(milliseconds: 100));

      final highlightKey = ValueKey('collection-highlight-${last.profileId}');
      expect(find.byKey(highlightKey), findsOneWidget, reason: '那一格要在畫面內');
      expect(highlightBorderAlpha(tester, last.profileId), greaterThan(0));

      await tester.pumpAndSettle();
      expect(find.byKey(highlightKey), findsNothing);
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('reduce-motion 抽中：沒有儀式，咻聲的暖尾巴跟著收掉', (tester) async {
      final sfx = _SfxRecorder();
      final controller = _DrawSpyController(_lockedSeed());
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._collectionOverrides(controller: controller),
            practiceDrawSfxProvider.overrideWithValue(sfx),
          ],
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

      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      expect(sfx.calls, contains(#playWhoosh));
      expect(sfx.calls, isNot(contains(#stopWhoosh)));

      controller.debugSetState(_revealedSeed());
      await tester.pump();
      expect(find.byKey(frontKey), findsNothing); // 沒有儀式畫面
      expect(sfx.calls, contains(#stopWhoosh));

      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
    });

    // ── V3.1 第四刀：NEW、已收藏、「已收集」數字落位才 +1（規格 §5.14、§7）──
    const newTagKey = ValueKey('practice-draw-ceremony-new-tag');
    const countKey = ValueKey('collection-completion-count');

    String countText(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(countKey)).data!;

    double countScale(WidgetTester tester) => tester
        .widget<Transform>(
          find
              .ancestor(
                  of: find.byKey(countKey), matching: find.byType(Transform))
              .first,
        )
        .transform
        .entry(0, 0);

    testWidgets('V3.1 新角色：停住時掛 NEW；儀式期間數字先不動，光球落位才 +1 並跳一下', (tester) async {
      final mia = practiceGirlProfiles
          .firstWhere((p) => p.profileId == 'practice_girl_004');
      final notifier = _SeededCollection({'practice_girl_001'});
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(controller: controller, collectionNotifier: notifier),
      );
      expect(countText(tester), '1');

      await drawAndReveal(tester, controller, mia, unlockInto: notifier);
      await tester.pumpAndSettle(); // 揭曉走完停住（圖鑑的 +1 早就到了）
      expect(find.byKey(newTagKey), findsOneWidget);
      expect(find.textContaining('已收藏'), findsNothing);
      expect(countText(tester), '1', reason: '儀式期間先顯示抽之前的數字');

      await tester.tap(find.byKey(continueKey));
      await tester.pump(); // 收卡起飛
      await tester.pump(const Duration(milliseconds: 400)); // 落位前
      expect(countText(tester), '1');
      await tester.pump(const Duration(milliseconds: 100)); // 過 0.45 s：落位
      await tester.pump(const Duration(milliseconds: 150)); // 跳到一半
      expect(countText(tester), '2');
      expect(countScale(tester), greaterThan(1.1));

      await tester.pumpAndSettle(); // 單次跳動收尾，回到原尺寸
      expect(countScale(tester), 1);
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('V3.1 重複角色：不掛 NEW、資訊欄寫「已收藏」；落位時數字不變也不跳', (tester) async {
      final alice = practiceGirlProfiles.first;
      final notifier = _SeededCollection({alice.profileId});
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(controller: controller, collectionNotifier: notifier),
      );

      await drawAndReveal(tester, controller, alice); // 集合不變（重複）
      await tester.pumpAndSettle();
      expect(find.byKey(newTagKey), findsNothing);
      expect(find.textContaining(RegExp(r' · 已收藏$')), findsOneWidget);

      await tester.tap(find.byKey(continueKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // 落位
      await tester.pump(const Duration(milliseconds: 150));
      expect(countText(tester), '1');
      expect(countScale(tester), 1);

      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('V3.1 解鎖晚到落位之後：落位時數字不動，解鎖到的那一刻才 +1 並跳一下（只跳一次）', (tester) async {
      final mia = practiceGirlProfiles
          .firstWhere((p) => p.profileId == 'practice_girl_004');
      final notifier = _SeededCollection({'practice_girl_001'});
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(controller: controller, collectionNotifier: notifier),
      );

      await drawAndReveal(tester, controller, mia); // 存草稿比儀式慢：解鎖還沒到
      await tester.pumpAndSettle(); // 停住
      expect(find.byKey(newTagKey), findsOneWidget);

      await tester.tap(find.byKey(continueKey));
      await tester.pump(); // 收卡起飛
      await tester.pump(const Duration(milliseconds: 500)); // 落位
      await tester.pump(const Duration(milliseconds: 150));
      expect(countText(tester), '1', reason: '解鎖還沒到：照實際數字');
      expect(countScale(tester), 1, reason: '數字沒變就不跳');
      await tester.pumpAndSettle(); // 儀式收完

      notifier.add(mia.profileId); // 解鎖這時才到
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150)); // 跳到一半
      expect(countText(tester), '2');
      expect(countScale(tester), greaterThan(1.1));
      await tester.pumpAndSettle();
      expect(countScale(tester), 1);

      // 只跳這一次：之後別的角色解鎖，數字照樣更新、不再跳。
      notifier.add('practice_girl_002');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(countText(tester), '3');
      expect(countScale(tester), 1);
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('V3.1 重複角色停住時別的角色解鎖：落位時數字照實際更新，但不跳', (tester) async {
      final alice = practiceGirlProfiles.first;
      final notifier = _SeededCollection({alice.profileId});
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(controller: controller, collectionNotifier: notifier),
      );

      await drawAndReveal(tester, controller, alice); // 重複角色
      await tester.pumpAndSettle(); // 停住
      notifier.add('practice_girl_004'); // 別的角色剛好解鎖（例如別台裝置抽到）
      await tester.pump();
      expect(countText(tester), '1', reason: '儀式期間先顯示抽之前的數字');

      await tester.tap(find.byKey(continueKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // 落位
      await tester.pump(const Duration(milliseconds: 150));
      expect(countText(tester), '2');
      expect(countScale(tester), 1, reason: '這次抽到的是重複角色，不跳');

      await tester.pumpAndSettle();
      expect(countScale(tester), 1);
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('V3.1 圖鑑還沒載到就抽：不掛 NEW、也不寫「已收藏」（寧可少掛、不錯掛）', (tester) async {
      final mia = practiceGirlProfiles
          .firstWhere((p) => p.profileId == 'practice_girl_004');
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(
          controller: controller,
          collectionNotifier: _PendingCollection(),
        ),
      );

      await drawAndReveal(tester, controller, mia);
      await tester.pumpAndSettle(); // 停住
      expect(find.byKey(frontKey), findsOneWidget);
      expect(find.byKey(newTagKey), findsNothing);
      expect(find.textContaining('已收藏'), findsNothing);

      await tester.tap(find.byKey(continueKey));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('V3.1 抽牌沒成功：標題不再卡在抽之前的數字', (tester) async {
      final mia = practiceGirlProfiles
          .firstWhere((p) => p.profileId == 'practice_girl_004');
      final notifier = _SeededCollection({'practice_girl_001'});
      final controller = _DrawSpyController(_lockedSeed());
      await pumpApp(
        tester,
        collectionApp(controller: controller, collectionNotifier: notifier),
      );

      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      controller.debugSetState(_lockedSeed()); // 沒抽成（回到 locked）
      // locked 時翻牌鈕一直在脈動（pumpAndSettle 收不了）：推過儀式淡出就好。
      await tester.pump(const Duration(milliseconds: 600));
      // 之後圖鑑有別的更新（例如重新整理）：標題照實際數字，不卡在抽之前。
      notifier.add(mia.profileId);
      await tester.pump();
      expect(countText(tester), '2');
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('V3.1 reduce-motion：沒有儀式，數字抽中就更新、不跳', (tester) async {
      final mia = practiceGirlProfiles
          .firstWhere((p) => p.profileId == 'practice_girl_004');
      final notifier = _SeededCollection({'practice_girl_001'});
      final controller = _DrawSpyController(_lockedSeed());
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: _collectionOverrides(
            controller: controller,
            collectionNotifier: notifier,
          ),
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

      controller.debugSetState(
        _lockedSeed().copyWith(drawStatus: PracticeDrawStatus.drawing),
      );
      await tester.pump();
      controller.debugSetState(revealedWith(mia));
      notifier.add(mia.profileId);
      await tester.pump();
      expect(countText(tester), '2');
      expect(countScale(tester), 1);

      await tester.pumpAndSettle();
      expect(countScale(tester), 1);
      await tester.pump(const Duration(milliseconds: 250));
    });
  });
}

/// 只記下儀式呼叫了哪些音效方法（不綁介面細節：介面增減方法時不用跟著改）。
class _SfxRecorder implements PracticeDrawSfx {
  final List<Symbol> calls = [];

  @override
  void noSuchMethod(Invocation invocation) => calls.add(invocation.memberName);
}

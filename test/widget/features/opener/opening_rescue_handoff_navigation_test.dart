// 「她回覆了，開始分析對話」的實際導航／返回堆疊測試
//（Eric-AI 2026-08-26 複審 #39 退回項 3：只驗 handoffLocationFor 回傳的網址
// 抓不到「疊出第二張相同對象卡」與「開場救星留在返回路徑上」這兩個回歸）。
//
// 這裡跑的是真的 GoRouter 與真的 OpeningRescueScreen：草稿種進 Hive、按
// 「回看」讓結果上畫面、展開「下一步怎麼接？」、按下真正的 CTA，然後對
// 堆疊本身斷言（誰不見了、剩幾張、再按返回會到哪）。
//
// Hermetic：Hive 走 ./.dart_tool 下的專用暫存目錄，subscription／partner
// providers 全 override，不打網路、不打真的 Supabase。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/opener/data/services/opener_result_cache_service.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

const _ownerId = 'u-handoff-test';
const _partnerId = 'p-1';

/// free 也看得到的型別，避免 visibleForAccess 把它濾掉。
const _draftResult = OpenerResult(
  openers: {'extend': '妳那張爬山的照片是在哪座山拍的？'},
  recommendedPick: 'extend',
  recommendedReason: '直接接她自己放的內容，不用另開話題。',
);

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

/// 各頁用可辨識的 stub，斷言才數得出「剩幾張對象卡」；`/opener` 是真的畫面。
///
/// `/partner/new` 用 stub 而不是真的 AddPartnerScreen：這裡要驗的是它*下面*
/// 是誰（首頁還是開場救星），不是新增表單本身。AddPartnerScreen 建立成功後
/// 會 pushReplacement 到 `/partner/:id` 取代自己，所以只要它下面是首頁，
/// 新對象卡下面就是首頁。
GoRouter _router() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _Stub('home')),
      GoRoute(
        path: '/opener',
        builder: (context, state) => OpeningRescueScreen(
          partnerId: state.uri.queryParameters['partnerId'],
        ),
      ),
      GoRoute(
        path: '/partner/new',
        builder: (_, __) => const _Stub('add-partner'),
      ),
      GoRoute(
        path: '/partner/:partnerId',
        builder: (_, state) =>
            _Stub('partner:${state.pathParameters['partnerId']}'),
      ),
    ],
  );
}

class _Stub extends StatelessWidget {
  const _Stub(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

Future<GoRouter> _pump(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});

  final router = _router();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionProvider.overrideWith(
          (ref) => _SeededSubscriptionNotifier(
            const SubscriptionState(
              tier: SubscriptionTierHelper.free,
              monthlyLimit: 30,
              dailyLimit: 15,
            ),
          ),
        ),
        partnerListProvider.overrideWith((ref) => const []),
        subscriptionScreenRefreshProvider.overrideWith((ref) => () async {}),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await t.pump();
  return router;
}

/// 頁內有常駐循環動畫（RevealPill 的 nudge），不能用 pumpAndSettle；
/// 一次 frame ＋一段夠長的時間足以走完路由轉場與捲動。
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

/// 按「回看」把草稿結果放上畫面，再展開「下一步怎麼接？」露出 CTA。
Future<void> _revealHandoffCta(WidgetTester t) async {
  final review = find.text('回看');
  await t.ensureVisible(review);
  await t.tap(review);
  await _settle(t);

  final pill = find.text('下一步怎麼接？');
  await t.ensureVisible(pill);
  await t.tap(pill);
  await _settle(t);
}

Future<void> _tapHandoffCta(WidgetTester t) async {
  final cta = find.text('她回覆了，開始分析對話');
  await t.ensureVisible(cta);
  await t.tap(cta);
  await _settle(t);
}

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_opening_rescue_handoff');
    OpenerResultCacheService.debugDefaultOwnerIdOverride = () => _ownerId;
  });

  setUp(() async {
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    OpenerResultCacheService.debugDefaultOwnerIdOverride = null;
    await Hive.close();
  });

  /// Hive 寫入是真的磁碟 I/O：testWidgets 的 fake-async zone 不會讓它完成，
  /// 種資料必須放進 runAsync。
  Future<void> seedDraft(WidgetTester t, {String? partnerId}) async {
    await t.runAsync(() async {
      await OpenerResultCacheService(ownerIdResolver: () => _ownerId).saveDraft(
        result: _draftResult,
        partnerId: partnerId,
      );
    });
  }

  testWidgets('已綁定對象：CTA 回到既有對象卡，不疊出第二張', (t) async {
    await seedDraft(t, partnerId: _partnerId);
    final router = await _pump(t);

    // 真實路徑：首頁 → 對象卡 →（分析新片段）→ 開場救星。
    router.push('/partner/$_partnerId');
    await _settle(t);
    router.push('/opener?partnerId=$_partnerId');
    await _settle(t);

    await _revealHandoffCta(t);
    await _tapHandoffCta(t);
    await _settle(t);

    // 開場救星退出堆疊，且畫面上只有原本那一張對象卡（含 offstage：
    // 疊上第二張時舊的那張會變 offstage，不加這個參數就數不到重複）。
    expect(
      find.text('開場救星', skipOffstage: false),
      findsNothing,
      reason: '開場救星必須整個離開堆疊',
    );
    expect(
      find.text('partner:$_partnerId', skipOffstage: false),
      findsOneWidget,
      reason: '應該是回到既有那張對象卡，不是再 push 一張一模一樣的',
    );

    // 從對象卡按返回＝回首頁，不會再撞見開場救星。
    router.pop();
    await _settle(t);
    expect(find.text('home'), findsOneWidget);
    expect(
      find.text('開場救星', skipOffstage: false),
      findsNothing,
      reason: '開場救星必須整個離開堆疊',
    );
  });

  testWidgets('未綁定對象：CTA 進新增對象，且開場救星不留在返回路徑上', (t) async {
    await seedDraft(t);
    final router = await _pump(t);

    router.push('/opener');
    await _settle(t);

    await _revealHandoffCta(t);
    await _tapHandoffCta(t);
    await _settle(t);

    expect(find.text('add-partner'), findsOneWidget);
    expect(
      find.text('開場救星', skipOffstage: false),
      findsNothing,
      reason: '開場救星必須整個離開堆疊',
    );

    // 新增對象頁下面是首頁。AddPartnerScreen 建立成功後 pushReplacement 到
    // /partner/:id 取代自己，所以新對象卡按返回同樣會回到首頁。
    router.pop();
    await _settle(t);
    expect(find.text('home'), findsOneWidget);
    expect(
      find.text('開場救星', skipOffstage: false),
      findsNothing,
      reason: '開場救星必須整個離開堆疊',
    );
  });
}

// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/opener/domain/opener_access.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/screens/paywall_screen.dart';
import 'package:vibesync/features/subscription/presentation/subscription_diagnostics_gate.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';

class _StubSubscriptionNotifier extends SubscriptionNotifier {
  _StubSubscriptionNotifier({
    this.onRestore,
    this.onRefresh,
    this.onPurchase,
    this.onClearPendingDowngrade,
  });

  final Future<bool> Function()? onRestore;
  final Future<void> Function()? onRefresh;
  final Future<SubscriptionPurchaseResult> Function()? onPurchase;
  final Future<bool> Function()? onClearPendingDowngrade;

  void seedState(SubscriptionState value) => state = value;

  @override
  Future<bool> restorePurchases() {
    final handler = onRestore;
    if (handler == null) {
      fail('restorePurchases should not be called in this test');
    }
    return handler();
  }

  @override
  Future<void> refresh() {
    final handler = onRefresh;
    return handler != null ? handler() : Future<void>.value();
  }

  @override
  Future<SubscriptionPurchaseResult> purchase(Package package) {
    final handler = onPurchase;
    if (handler == null) {
      fail('purchase should not be called in this test');
    }
    return handler();
  }

  @override
  Future<bool> clearPendingDowngradeMetadata() {
    final handler = onClearPendingDowngrade;
    if (handler == null) {
      fail('clearPendingDowngradeMetadata should not be called in this test');
    }
    return handler();
  }
}

/// 已付費的方案狀態：付費頁給管理版。
SubscriptionState _paidState(String tier) {
  final limits = SubscriptionTierHelper.limitsFor(tier);
  return SubscriptionState(
    tier: tier,
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
  );
}

StoreProduct _storeProduct(
  String id,
  String title,
  double price,
  String priceString,
  String period,
) =>
    StoreProduct(
      id,
      'description',
      title,
      price,
      priceString,
      'TWD',
      subscriptionPeriod: period,
    );

/// 四個方案都有 App Store 價格（測試編的價格；季繳價隨便訂的）。
Map<String, StoreProduct> _allProducts() => {
      'starter_monthly':
          _storeProduct('starter_monthly', 'Starter', 590, r'NT$590', 'P1M'),
      'starter_quarterly': _storeProduct(
          'starter_quarterly', 'Starter', 1590, r'NT$1,590', 'P3M'),
      'essential_monthly': _storeProduct(
          'essential_monthly', 'Essential', 1290, r'NT$1,290', 'P1M'),
      'essential_quarterly': _storeProduct(
          'essential_quarterly', 'Essential', 3490, r'NT$3,490', 'P3M'),
    };

/// 購買版的方案卡（key 帶方案 id）。
Finder _buyCard(String optionId) =>
    find.byKey(ValueKey('paywall-buy-card-$optionId'));

Finder _inBuyCard(String optionId, Finder finder) =>
    find.descendant(of: _buyCard(optionId), matching: finder);

/// 購買版的方案卡有沒有選到（卡片的 Semantics selected）。
bool _buyCardSelected(WidgetTester tester, String optionId) =>
    tester.widget<Semantics>(_buyCard(optionId)).properties.selected ?? false;

/// 畫得出來的那幾個：沒有徽章的卡留了一個隱形的徽章佔位對齊高度，不算。
int _visibleCount(Finder finder) => finder
    .evaluate()
    .where(
      (element) =>
          element.findAncestorWidgetOfExactType<Visibility>()?.visible ?? true,
    )
    .length;

/// 徽章是不是橘色漸層底（「推薦」樣式）。
bool _badgeIsOrange(WidgetTester tester, Finder badgeText) {
  final container = tester.widget<Container>(
    find.ancestor(of: badgeText, matching: find.byType(Container)).first,
  );
  final gradient = (container.decoration as BoxDecoration?)?.gradient;
  return gradient is LinearGradient &&
      gradient.colors.contains(AppColors.ctaStart);
}

void main() {
  /// 沒給 [state] 就是真的 SubscriptionNotifier：測試環境沒登入，方案是免費。
  Future<void> pumpPaywall(
    WidgetTester tester, {
    Future<void> Function()? refreshUsage,
    SubscriptionState? state,
    PaywallEntry entry = PaywallEntry.general,
    Size size = const Size(430, 1400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final stub =
        state == null ? null : (_StubSubscriptionNotifier()..seedState(state));

    await tester.pumpWidget(
      ProviderScope(
        // 同一個測試裡重開時整棵換掉，override 才會換。
        key: UniqueKey(),
        overrides: [
          if (stub != null) subscriptionProvider.overrideWith((ref) => stub),
          subscriptionScreenRefreshProvider.overrideWithValue(
            refreshUsage ?? () async {},
          ),
        ],
        child: MaterialApp(home: PaywallScreen(entry: entry)),
      ),
    );
    await tester.pump();
  }

  /// 管理版：Starter 用戶打開付費頁。
  Future<void> pumpManagePaywall(WidgetTester tester) =>
      pumpPaywall(tester, state: _paidState(SubscriptionTierHelper.starter));

  group('PaywallScreen', () {
    testWidgets('refreshes subscription usage snapshot on entry',
        (tester) async {
      var refreshCalls = 0;
      await pumpPaywall(tester, refreshUsage: () async {
        refreshCalls++;
      });

      expect(refreshCalls, 1);
    });

    // Onboarding 第 9 步：付費用戶照舊看管理版，升降級怎麼算對他們是必要的。
    testWidgets('付費用戶看管理版：標題、定位句、升降級說明照舊', (tester) async {
      for (final tier in [
        SubscriptionTierHelper.starter,
        SubscriptionTierHelper.essential,
      ]) {
        await pumpPaywall(tester, state: _paidState(tier));

        expect(find.text('方案與額度'), findsOneWidget, reason: tier);
        expect(find.text('升級方案'), findsNothing, reason: tier);
        expect(find.text('完整教練帶路\n把她約出來更有把握'), findsOneWidget);
        expect(find.textContaining('升級會立即生效'), findsAtLeastNWidgets(1));
        expect(find.textContaining('降級則會在下次續訂時生效'), findsOneWidget);
        expect(find.text('目前方案與額度'), findsOneWidget);
        expect(
            find.byKey(const ValueKey('paywall-buy-bottom-bar')), findsNothing);
      }
    });

    testWidgets('close button falls back home when paywall has no back stack',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = GoRouter(
        initialLocation: '/paywall',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('home-root')),
          ),
          GoRoute(
            path: '/paywall',
            builder: (_, __) => const PaywallScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      // 測試環境沒登入＝免費，看購買版。
      expect(find.text('升級方案'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('home-root'), findsOneWidget);
      expect(find.text('升級方案'), findsNothing);
    });

    // 免費用戶的購買版不放額度膠囊（Onboarding 第 9 步）；管理版照舊。
    testWidgets('管理版顯示目前方案與剩餘額度', (tester) async {
      await pumpManagePaywall(tester);

      expect(find.text('目前方案與額度'), findsOneWidget);
      expect(find.text('目前方案：Starter'), findsOneWidget);
      expect(find.text('本月剩餘'), findsOneWidget);
      expect(find.text('今日剩餘'), findsOneWidget);
      // 額度照常數算，之後再調也不用改這裡。
      const monthly = AppConstants.starterMonthlyLimit;
      const daily = AppConstants.starterDailyLimit;
      expect(find.text('$monthly/$monthly'), findsOneWidget);
      expect(find.text('$daily/$daily'), findsOneWidget);
    });

    testWidgets('比較表的每日、每月額度三欄都照方案常數', (tester) async {
      await pumpManagePaywall(tester);

      List<String?> cellsOf(String feature) {
        final row = find
            .ancestor(of: find.text(feature), matching: find.byType(Row))
            .first;
        return tester
            .widgetList<Text>(
                find.descendant(of: row, matching: find.byType(Text)))
            .map((text) => text.data)
            .toList();
      }

      expect(cellsOf('每日額度'), [
        '每日額度',
        '${AppConstants.freeDailyLimit} 則',
        '${AppConstants.starterDailyLimit} 則',
        '${AppConstants.essentialDailyLimit} 則',
      ]);
      expect(cellsOf('每月額度'), [
        '每月額度',
        '${AppConstants.freeMonthlyLimit} 則',
        '${AppConstants.starterMonthlyLimit} 則',
        '${AppConstants.essentialMonthlyLimit} 則',
      ]);
    });

    testWidgets('comparison table names tiers and uses human-readable values',
        (tester) async {
      await pumpManagePaywall(tester);

      expect(find.text('方案功能比較'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Starter'), findsOneWidget);
      expect(find.text('Essential'), findsOneWidget);
      expect(find.text('適合誰'), findsOneWidget);
      expect(find.text('先試手感'), findsOneWidget);
      expect(find.text('穩定練習'), findsOneWidget);
      expect(find.text('深度打磨'), findsOneWidget);
      // 對話分析 v3：三個方案都看全部的卡（Bruce PR #97，Eric 2026-10-19），這一列照留；
      // 不寫「每次 3–5 張」（收尾 1 張、先別回和停沒有卡，Eric 2026-10-18）。新流程沒有
      // 雷達圖，比較表不再列。
      expect(find.text('回覆卡'), findsOneWidget);
      final cardsRow =
          find.ancestor(of: find.text('回覆卡'), matching: find.byType(Row)).first;
      expect(
        tester
            .widgetList<Text>(
                find.descendant(of: cardsRow, matching: find.byType(Text)))
            .map((text) => text.data)
            .toList(),
        ['回覆卡', '全部', '全部', '全部'],
      );
      expect(find.text('前 2 張'), findsNothing);
      expect(find.text('每次回覆卡'), findsNothing);
      expect(find.text('雷達圖'), findsNothing);
      expect(find.text('延展＋調情 2 種'), findsNothing);
      expect(find.text('全部 5 種'), findsNothing);
      // 對話健檢（新流程沒有）與訊息優化（D-4 起全方案）都不再是 Essential 專屬。
      expect(find.text('對話健檢'), findsNothing);
      expect(find.text('訊息優化'), findsNothing);
      expect(find.text('可用'), findsNothing);
      expect(find.text('未開放'), findsNothing);
      // 方案卡的重點也不再寫五種風格或雷達圖；免費也看全部的卡，不再寫「免費看前 2 張」。
      expect(find.text('該回的時候給你 3–5 張回覆'), findsNWidgets(4));
      expect(find.textContaining('免費看前'), findsNothing);
      expect(find.textContaining('對話健檢'), findsNothing);
      expect(find.textContaining('訊息優化'), findsNothing);
      expect(find.textContaining('五種風格'), findsNothing);
      expect(find.textContaining('雷達'), findsNothing);
      expect(find.text('120 則'), findsOneWidget);
      expect(find.text('800 則'), findsOneWidget);
    });

    testWidgets('比較表不再列燈號走勢與邀約進度：不分方案都看完整紀錄（Eric 2026-10-19）', (tester) async {
      await pumpManagePaywall(tester);

      expect(find.text('燈號走勢與邀約進度'), findsNothing);
      expect(find.text('燈號紀錄與邀約進度'), findsNothing);
      expect(find.text('最新一次'), findsNothing);
      expect(find.text('完整走勢'), findsNothing);
    });

    testWidgets('比較表有開場救星：句數照開場權益契約，排在回覆卡下面', (tester) async {
      await pumpManagePaywall(tester);

      // Eric 2026-10-18：免費看 5 句裡的 3 句，兩個付費方案都看完整 5 句。數字從
      // OpenerAccessContract 算，不寫死。
      final freeLines = '${OpenerAccessContract.freeUnlockedOrder.length} 句';
      final paidLines = '${OpenerAccessContract.canonicalPaidOrder.length} 句';
      expect(find.text('開場救星'), findsOneWidget);
      final row = find
          .ancestor(of: find.text('開場救星'), matching: find.byType(Row))
          .first;
      final cells = tester
          .widgetList<Text>(
              find.descendant(of: row, matching: find.byType(Text)))
          .map((text) => text.data)
          .toList();
      expect(cells, ['開場救星', freeLines, paidLines, paidLines]);
      final cardsRow = tester.getTopLeft(find.text('回覆卡')).dy;
      final openerRow = tester.getTopLeft(find.text('開場救星')).dy;
      final drawRow = tester.getTopLeft(find.text('陪練女孩翻牌')).dy;
      expect(openerRow, greaterThan(cardsRow));
      expect(openerRow, lessThan(drawRow));
    });

    testWidgets('comparison table includes practice girl and model copy',
        (tester) async {
      await pumpManagePaywall(tester);

      // 鏡像 server draw_decision.ts：free=0（起步一次性贈抽）/3/5。
      expect(find.text('陪練女孩翻牌'), findsOneWidget);
      expect(find.text('起步贈抽 1 次'), findsOneWidget);
      expect(find.text('每日 3 次'), findsOneWidget);
      expect(find.text('每日 5 次'), findsOneWidget);
      expect(find.text('每日 1 位'), findsNothing); // 舊不實文案絕不回歸
      // SR 限定翻牌（2026-08-08 拍板）：兩檔都送 1 次，白紙黑字回答「哪檔才有」。
      expect(find.text('SR 限定翻牌'), findsOneWidget);
      expect(find.text('送 1 次'), findsNWidgets(2));
      // 零資訊「AI 模型」列已移除，換電子書/測驗兩列真差異。
      expect(find.text('AI 模型'), findsNothing);
      expect(find.text('互動電子書'), findsOneWidget);
      expect(find.text('第 1 冊＋試讀'), findsOneWidget);
      expect(find.text('全 7 冊'), findsOneWidget);
      expect(find.text('聊天測驗'), findsOneWidget);
      // ADR #38：測驗欄不寫死關數，擴充各批加關不用回頭改這裡。
      expect(find.text('免費關卡'), findsOneWidget);
      expect(find.text('全部關卡'), findsNWidgets(2));
      // 夜市第一停點付費牆：Free/Starter 只到第一段，Essential 才有全程＋復盤。
      expect(find.text('夜市實戰影片'), findsOneWidget);
      expect(find.text('第一段'), findsNWidgets(2));
      expect(find.text('完整流程＋復盤'), findsOneWidget);
      expect(find.textContaining('Haiku'), findsNothing);
      expect(find.textContaining('Sonnet'), findsNothing);
    });

    testWidgets('explains the Free vs paid practice-girl continuation rule',
        (tester) async {
      await pumpManagePaywall(tester);

      // Free has no daily draw (removed 2026-08-02); only one round per girl.
      // Upgrading unlocks daily draws and continuing the same girl.
      expect(find.textContaining('同一位陪練女孩只能練一輪'), findsOneWidget);
      expect(find.textContaining('續聊同一位'), findsOneWidget);
      expect(find.textContaining('每天仍可翻出'), findsNothing); // 舊前提絕不回歸
    });

    // Onboarding 第 9 步：「推薦」徽章與橘色樣式跟著預設那一張。以前橘色畫在
    // Essential 季繳、預設卻選 Essential 月繳，兩個對不上。
    testWidgets('管理版：價格同步前四張方案卡也排好，推薦的橘色徽章在預設的 Essential 月繳', (tester) async {
      await pumpManagePaywall(tester);

      expect(find.text('Starter 月繳'), findsOneWidget);
      expect(find.text('Starter 季繳'), findsOneWidget);
      expect(find.text('Essential 月繳'), findsOneWidget);
      expect(find.text('Essential 季繳'), findsOneWidget);
      expect(find.text('入門'), findsNWidgets(2));
      expect(find.text('推薦'), findsOneWidget);
      expect(find.text('最划算'), findsOneWidget);
      expect(find.text('價格同步中'), findsNWidgets(4));
      expect(find.text('請重新載入 App Store 價格'), findsNWidgets(4));
      expect(find.text('方案資訊尚未就緒'), findsOneWidget);
      expect(find.text('本次扣款金額'), findsOneWidget);
      expect(find.text('正在向 App Store 取得價格'), findsOneWidget);
      expect(find.text('重新載入 App Store 價格'), findsOneWidget);

      // 推薦（橘色）就在 Essential 月繳那張卡上；最划算、入門是一般徽章。
      final recommended = find.text('推薦');
      final essentialMonthlyCard = find.ancestor(
        of: find.text('Essential 月繳'),
        matching: find.byType(AnimatedContainer),
      );
      expect(
        find.descendant(of: essentialMonthlyCard, matching: recommended),
        findsOneWidget,
      );
      expect(_badgeIsOrange(tester, recommended), isTrue);
      expect(_badgeIsOrange(tester, find.text('最划算')), isFalse);
      expect(_badgeIsOrange(tester, find.text('入門').first), isFalse);
      expect(_badgeIsOrange(tester, find.text('入門').last), isFalse);
    });

    // Onboarding 第 9 步（Eric 2026-10-27 選 Starter）：免費用戶預設 Starter 月繳；
    // Starter 用戶預設升級的 Essential 月繳；Essential 用戶照舊 Essential 月繳。
    testWidgets('預設選取照目前方案：免費 Starter 月繳，Starter、Essential 用戶 Essential 月繳',
        (tester) async {
      await pumpPaywall(
        tester,
        state: SubscriptionState(storeProducts: _allProducts()),
      );
      expect(_buyCardSelected(tester, 'starter_monthly'), isTrue);
      expect(_buyCardSelected(tester, 'essential_monthly'), isFalse);
      expect(find.text(r'以 NT$590 訂閱 Starter 月繳'), findsOneWidget);

      for (final tier in [
        SubscriptionTierHelper.starter,
        SubscriptionTierHelper.essential,
      ]) {
        await pumpPaywall(tester, state: _paidState(tier));
        final essentialMonthlyRadio = tester.widget<Radio<String>>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Radio<String> && widget.value == 'essential_monthly',
          ),
        );
        expect(essentialMonthlyRadio.groupValue, 'essential_monthly',
            reason: tier);
      }
    });

    testWidgets('can switch selected product option before purchasing',
        (tester) async {
      await pumpManagePaywall(tester);

      await tester.tap(find.text('Starter 月繳'));
      await tester.pump();

      final starterMonthlyRadio = tester.widget<Radio<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Radio<String> && widget.value == 'starter_monthly',
        ),
      );
      expect(starterMonthlyRadio.groupValue, 'starter_monthly');
    });

    testWidgets('選卡只剩 240ms 邊框漸變：沒有掃邊流星那種持續動態光', (tester) async {
      await pumpManagePaywall(tester);
      // 首幀預選 essential_monthly：不排任何動畫幀。
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, 0);

      await tester.tap(find.text('Starter 月繳'));
      await tester.pump();
      // 選取狀態漸變（AppMotion.state = 240ms）跑完就該完全靜止；
      // 掃邊流星（約 1s）若回來，這裡會還有進行中的 ticker。
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.transientCallbackCount, 0);

      // 收斂檢查：沒有殘留動畫、也沒有殘光層。
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('shows consistent legal and subscription management links',
        (tester) async {
      await pumpManagePaywall(tester);

      expect(find.text('服務條款'), findsOneWidget);
      expect(find.text('隱私政策'), findsOneWidget);
      expect(find.text('管理訂閱'), findsOneWidget);
      expect(find.text('恢復購買'), findsOneWidget);
    });

    testWidgets('diagnostics footer link hidden when gate is off (release)',
        (tester) async {
      SubscriptionDiagnosticsGate.debugVisibleOverride = false;
      addTearDown(() {
        SubscriptionDiagnosticsGate.debugVisibleOverride = null;
      });

      await pumpPaywall(tester);

      expect(find.text('複製訂閱診斷'), findsNothing);
    });

    testWidgets('diagnostics footer link visible when gate is on (debug)',
        (tester) async {
      SubscriptionDiagnosticsGate.debugVisibleOverride = true;
      addTearDown(() {
        SubscriptionDiagnosticsGate.debugVisibleOverride = null;
      });

      await pumpPaywall(tester);

      expect(find.text('複製訂閱診斷'), findsOneWidget);
    });
  });

  group('PaywallScreen purchase/restore spinner never hangs (2.1(b))', () {
    Finder purchasingOverlay() => find.byType(CircularProgressIndicator);

    SubscriptionState stateWithEssentialMonthly() {
      final package = Package(
        r'$rc_monthly',
        PackageType.monthly,
        StoreProduct(
          'vibesync_essential_monthly',
          'description',
          'Essential',
          590,
          r'$590',
          'TWD',
          subscriptionPeriod: 'P1M',
        ),
        const PresentedOfferingContext('default', null, null),
      );
      final offering = Offering(
        'default',
        'Default offering',
        const {},
        [package],
      );
      return SubscriptionState(
        offerings: Offerings({'default': offering}, current: offering),
      );
    }

    Future<_StubSubscriptionNotifier> pumpPaywallWithStub(
      WidgetTester tester, {
      Future<bool> Function()? onRestore,
      Future<void> Function()? onRefresh,
      Future<SubscriptionPurchaseResult> Function()? onPurchase,
      Future<bool> Function()? onClearPendingDowngrade,
      SubscriptionState? seededState,
    }) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final stub = _StubSubscriptionNotifier(
        onRestore: onRestore,
        onRefresh: onRefresh,
        onPurchase: onPurchase,
        onClearPendingDowngrade: onClearPendingDowngrade,
      );
      final router = GoRouter(
        initialLocation: '/paywall',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('home-root')),
            routes: [
              GoRoute(
                path: 'paywall',
                builder: (_, __) => const PaywallScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/practice-collection',
            builder: (_, __) => const Scaffold(
              body: Text('collection-stub', key: ValueKey('collection-stub')),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionProvider.overrideWith((ref) => stub),
            subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();
      if (seededState != null) {
        stub.seedState(seededState);
        await tester.pump();
      }
      return stub;
    }

    Future<_StubSubscriptionNotifier> pumpTopLevelPaywallWithStub(
      WidgetTester tester, {
      Future<bool> Function()? onRestore,
      Future<void> Function()? onRefresh,
      Future<SubscriptionPurchaseResult> Function()? onPurchase,
      SubscriptionState? seededState,
    }) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final stub = _StubSubscriptionNotifier(
        onRestore: onRestore,
        onRefresh: onRefresh,
        onPurchase: onPurchase,
      );
      final router = GoRouter(
        initialLocation: '/paywall',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('home-root')),
          ),
          GoRoute(
            path: '/paywall',
            builder: (_, __) => const PaywallScreen(),
          ),
          GoRoute(
            path: '/practice-collection',
            builder: (_, __) => const Scaffold(
              body: Text('collection-stub', key: ValueKey('collection-stub')),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionProvider.overrideWith((ref) => stub),
            subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();
      if (seededState != null) {
        stub.seedState(seededState);
        await tester.pump();
      }
      return stub;
    }

    Future<void> startRestoreFlow(WidgetTester tester) async {
      final restoreLink = find.widgetWithText(TextButton, '恢復購買');
      await tester.ensureVisible(restoreLink);
      await tester.pump();
      await tester.tap(restoreLink, warnIfMissed: false);
      await tester.pump();
      // Dialog 確認鈕與 footer 連結同字，dialog 在 overlay 內＝last。
      await tester.tap(
        find.widgetWithText(TextButton, '恢復購買').last,
        warnIfMissed: false,
      );
      await tester.pump();
    }

    Future<void> flushSnackBars(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('restore hang times out and dismisses the spinner',
        (tester) async {
      await pumpPaywallWithStub(
        tester,
        onRestore: () => Completer<bool>().future,
      );

      await startRestoreFlow(tester);
      // 轉圈中：overlay spinner＋CTA 按鈕內建 loading spinner。
      expect(purchasingOverlay(), findsWidgets);

      await tester.pump(const Duration(seconds: 46));
      await tester.pump();

      expect(purchasingOverlay(), findsNothing);
      expect(find.textContaining('恢復購買逾時'), findsOneWidget);
      await flushSnackBars(tester);
    });

    testWidgets('restore success with hanging refresh still completes and pops',
        (tester) async {
      await pumpPaywallWithStub(
        tester,
        onRestore: () async => true,
        onRefresh: () => Completer<void>().future,
      );

      await startRestoreFlow(tester);

      await tester.pump(const Duration(seconds: 21));
      await tester.pump();

      expect(purchasingOverlay(), findsNothing);
      expect(find.text('訂閱狀態已更新。'), findsOneWidget);
      expect(find.text('home-root'), findsOneWidget);
      await flushSnackBars(tester);
    });

    testWidgets(
        'purchase success with hanging refresh still completes and pops',
        (tester) async {
      await pumpPaywallWithStub(
        tester,
        onPurchase: () async => const SubscriptionPurchaseResult(
          success: true,
          cancelled: false,
          isDeferredDowngrade: false,
          requestedTier: SubscriptionTierHelper.essential,
          previousTier: SubscriptionTierHelper.free,
          activeTier: SubscriptionTierHelper.essential,
        ),
        onRefresh: () => Completer<void>().future,
        seededState: stateWithEssentialMonthly(),
      );

      final cta = find.textContaining('訂閱 Essential');
      expect(cta, findsOneWidget);
      await tester.ensureVisible(cta);
      await tester.pump();
      await tester.tap(cta, warnIfMissed: false);
      await tester.pump();

      await tester.pump(const Duration(seconds: 21));
      await tester.pump();

      expect(purchasingOverlay(), findsNothing);
      expect(find.textContaining('方案已更新'), findsOneWidget);
      // 訂閱成功輕慶祝（2026-08-08 拍板）：同一顆 snackbar 帶 SR 券解鎖訊息＋
      // 「去翻牌」action——點了才去，不點不打斷（Codex 主審 finding 1）。
      expect(find.textContaining('已解鎖 SR 限定翻牌'), findsOneWidget);
      expect(find.text('home-root'), findsOneWidget);
      final goDrawAction = find.text('去翻牌');
      expect(goDrawAction, findsOneWidget);
      // snackbar 進場動畫落定後才點得到 action。
      await tester.pumpAndSettle();
      await tester.tap(goDrawAction);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('collection-stub')), findsOneWidget);
    });

    testWidgets('top-level paywall purchase success falls back home',
        (tester) async {
      await pumpTopLevelPaywallWithStub(
        tester,
        onPurchase: () async => const SubscriptionPurchaseResult(
          success: true,
          cancelled: false,
          isDeferredDowngrade: false,
          requestedTier: SubscriptionTierHelper.essential,
          previousTier: SubscriptionTierHelper.free,
          activeTier: SubscriptionTierHelper.essential,
        ),
        seededState: stateWithEssentialMonthly(),
      );

      final cta = find.textContaining('訂閱 Essential');
      await tester.ensureVisible(cta);
      await tester.pump();
      await tester.tap(cta, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('home-root'), findsOneWidget);
      expect(find.text('訂閱處理失敗，請稍後再試。'), findsNothing);
    });

    testWidgets('top-level paywall restore success falls back home',
        (tester) async {
      await pumpTopLevelPaywallWithStub(
        tester,
        onRestore: () async => true,
      );

      await startRestoreFlow(tester);
      await tester.pumpAndSettle();

      expect(find.text('home-root'), findsOneWidget);
      expect(find.text('恢復購買失敗，請稍後再試。'), findsNothing);
    });

    testWidgets('purchase success with failing refresh must not report failure',
        (tester) async {
      await pumpPaywallWithStub(
        tester,
        onPurchase: () async => const SubscriptionPurchaseResult(
          success: true,
          cancelled: false,
          isDeferredDowngrade: false,
          requestedTier: SubscriptionTierHelper.essential,
          previousTier: SubscriptionTierHelper.free,
          activeTier: SubscriptionTierHelper.essential,
        ),
        onRefresh: () async => throw Exception('refresh boom'),
        seededState: stateWithEssentialMonthly(),
      );

      final cta = find.textContaining('訂閱 Essential');
      await tester.ensureVisible(cta);
      await tester.pump();
      await tester.tap(cta, warnIfMissed: false);
      await tester.pump();
      await tester.pump();

      expect(purchasingOverlay(), findsNothing);
      expect(find.text('訂閱處理失敗，請稍後再試。'), findsNothing);
      expect(find.textContaining('方案已更新'), findsOneWidget);
      expect(find.text('home-root'), findsOneWidget);
      await flushSnackBars(tester);
    });

    testWidgets(
        'pending downgrade cancel refresh hang times out and dismisses spinner',
        (tester) async {
      await pumpPaywallWithStub(
        tester,
        onClearPendingDowngrade: () => Completer<bool>().future,
        seededState: SubscriptionState(
          tier: SubscriptionTierHelper.essential,
          pendingDowngradeToTier: SubscriptionTierHelper.starter,
          pendingDowngradeEffectiveAt: DateTime(2027, 1, 1),
        ),
      );

      final refreshLink = find.text('我已取消降級，更新狀態');
      expect(refreshLink, findsOneWidget);
      await tester.ensureVisible(refreshLink);
      await tester.pump();
      await tester.tap(refreshLink, warnIfMissed: false);
      await tester.pump();
      expect(purchasingOverlay(), findsWidgets);

      await tester.pump(const Duration(seconds: 21));
      await tester.pump();

      expect(purchasingOverlay(), findsNothing);
      expect(find.textContaining('同步逾時'), findsOneWidget);
      await flushSnackBars(tester);
    });

    // Onboarding 第 9 步：付款成功時方案已經換成付費，關頁前還要刷新一次；這段時間
    // 遮罩底下維持購買版，不換成管理版、選取也不換成付費用戶的預設。
    testWidgets('購買處理中方案變成付費：遮罩底下維持購買版與選取，恢復購買先停用', (tester) async {
      final starterMonthly = Package(
        r'$rc_monthly',
        PackageType.monthly,
        _storeProduct('starter_monthly', 'Starter', 590, r'NT$590', 'P1M'),
        const PresentedOfferingContext('default', null, null),
      );
      final offering = Offering(
        'default',
        'Default offering',
        const {},
        [starterMonthly],
      );
      final offerings = Offerings({'default': offering}, current: offering);
      final refresh = Completer<void>();
      late final _StubSubscriptionNotifier stub;
      stub = await pumpPaywallWithStub(
        tester,
        onPurchase: () async {
          final limits =
              SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.starter);
          stub.seedState(SubscriptionState(
            tier: SubscriptionTierHelper.starter,
            monthlyLimit: limits.monthly,
            dailyLimit: limits.daily,
            offerings: offerings,
          ));
          return const SubscriptionPurchaseResult(
            success: true,
            cancelled: false,
            isDeferredDowngrade: false,
            requestedTier: SubscriptionTierHelper.starter,
            previousTier: SubscriptionTierHelper.free,
            activeTier: SubscriptionTierHelper.starter,
          );
        },
        onRefresh: () => refresh.future,
        seededState: SubscriptionState(offerings: offerings),
      );

      final cta = find.text(r'以 NT$590 訂閱 Starter 月繳');
      expect(cta, findsOneWidget);
      await tester.tap(cta, warnIfMissed: false);
      await tester.pump();
      await tester.pump();

      expect(purchasingOverlay(), findsWidgets);
      expect(find.text('升級方案'), findsOneWidget);
      expect(find.text('方案與額度'), findsNothing);
      expect(find.textContaining('升級會立即生效'), findsNothing);
      expect(_buyCardSelected(tester, 'starter_monthly'), isTrue);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '恢復購買'))
            .onPressed,
        isNull,
      );

      refresh.complete();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('方案已更新'), findsOneWidget);
      expect(find.text('home-root'), findsOneWidget);
      await flushSnackBars(tester);
    });
  });

  // 付費頁標題依入口換（Eric 2026-10-18）：鎖住的卡、額度用完、其他入口照舊。
  group('付費頁入口', () {
    const tiers = [
      SubscriptionTierHelper.free,
      SubscriptionTierHelper.starter,
      SubscriptionTierHelper.essential,
    ];

    test('一般、鎖卡入口的大標跟方案無關；一般入口沿用定位句', () {
      for (final tier in tiers) {
        expect(PaywallEntry.general.headlineFor(tier), '完整教練帶路\n把她約出來更有把握');
        expect(PaywallEntry.lockedCards.headlineFor(tier), '每一輪的回覆卡\n全部看得到');
      }
    });

    test('路由 extra 沒帶或帶錯都當一般入口', () {
      expect(PaywallEntry.fromRouteExtra(null), PaywallEntry.general);
      expect(PaywallEntry.fromRouteExtra('lockedCards'), PaywallEntry.general);
      for (final entry in PaywallEntry.values) {
        expect(PaywallEntry.fromRouteExtra(entry), entry);
      }
    });

    // 主審 r1 P2-3：剩 0 則才叫用完；還有剩、或不知道剩幾則，只說不夠這次用。
    test('額度入口：每日或每月、用完或只是不夠', () {
      expect(
        PaywallEntry.forQuota(isMonthly: false, remaining: 0),
        PaywallEntry.dailyQuotaUsedUp,
      );
      expect(
        PaywallEntry.forQuota(isMonthly: false, remaining: 3),
        PaywallEntry.dailyQuotaShort,
      );
      expect(
        PaywallEntry.forQuota(isMonthly: false),
        PaywallEntry.dailyQuotaShort,
      );
      expect(
        PaywallEntry.forQuota(isMonthly: true, remaining: 0),
        PaywallEntry.monthlyQuotaUsedUp,
      );
      expect(
        PaywallEntry.forQuota(isMonthly: true, remaining: 2),
        PaywallEntry.monthlyQuotaShort,
      );
    });

    // 主審 r1 P2-3：大標要給做得到的下一步。Onboarding 第 3 步：一律先說什麼時候恢復
    // （伺服器照 UTC 換日、換月重算，台灣是早上 8 點），免費、Starter 再補升級後額度
    // 更多；Essential 已經是最高方案，不承諾升級，只說什麼時候恢復；也不說換繳費週期
    // 會補額度。
    test('額度大標照目前方案：免費、Starter 先說恢復再說升級後更多，Essential 只說什麼時候恢復', () {
      const upgradeable = {
        PaywallEntry.dailyQuotaUsedUp: '今天的額度用完了\n每天早上 8 點恢復；升級後每天能用更多',
        PaywallEntry.dailyQuotaShort: '今天的額度不夠這次用\n每天早上 8 點恢復；升級後每天能用更多',
        PaywallEntry.monthlyQuotaUsedUp: '這個月的額度用完了\n每月 1 號早上 8 點恢復；升級後每月能用更多',
        PaywallEntry.monthlyQuotaShort: '這個月的額度不夠這次用\n每月 1 號早上 8 點恢復；升級後每月能用更多',
      };
      const topTier = {
        PaywallEntry.dailyQuotaUsedUp: '今天的額度用完了\n每天早上 8 點恢復',
        PaywallEntry.dailyQuotaShort: '今天的額度不夠這次用\n每天早上 8 點恢復',
        PaywallEntry.monthlyQuotaUsedUp: '這個月的額度用完了\n每月 1 號早上 8 點恢復',
        PaywallEntry.monthlyQuotaShort: '這個月的額度不夠這次用\n每月 1 號早上 8 點恢復',
      };
      for (final tier in [
        SubscriptionTierHelper.free,
        SubscriptionTierHelper.starter,
      ]) {
        upgradeable.forEach((entry, headline) {
          expect(entry.headlineFor(tier), headline, reason: '$tier $entry');
        });
      }
      topTier.forEach((entry, headline) {
        final text = entry.headlineFor(SubscriptionTierHelper.essential);
        expect(text, headline, reason: '$entry');
        expect(text, isNot(contains('升級')), reason: '$entry');
      });
      for (final tier in tiers) {
        for (final entry in PaywallEntry.values) {
          expect(entry.headlineFor(tier), isNot(matches(RegExp('繳|季|週期'))),
              reason: '不提換繳費週期');
        }
      }
    });

    testWidgets('付費頁照目前方案換額度大標：免費、Starter、Essential，用完與不夠', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final tier in tiers) {
        for (final entry in [
          PaywallEntry.dailyQuotaUsedUp,
          PaywallEntry.dailyQuotaShort,
          PaywallEntry.monthlyQuotaUsedUp,
          PaywallEntry.monthlyQuotaShort,
        ]) {
          final stub = _StubSubscriptionNotifier();
          final limits = SubscriptionTierHelper.limitsFor(tier);
          stub.seedState(SubscriptionState(
            tier: tier,
            monthlyLimit: limits.monthly,
            dailyLimit: limits.daily,
          ));
          // 每一輪換新的 ProviderScope：同一個 scope 重建時 override 不會換掉。
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey('$tier-$entry'),
              overrides: [
                subscriptionProvider.overrideWith((ref) => stub),
                subscriptionScreenRefreshProvider.overrideWithValue(
                  () async {},
                ),
              ],
              child: MaterialApp(home: PaywallScreen(entry: entry)),
            ),
          );
          await tester.pump();

          expect(find.text(entry.headlineFor(tier)), findsOneWidget,
              reason: '$tier $entry');
          expect(find.text('完整教練帶路\n把她約出來更有把握'), findsNothing);
          // 免費用戶看購買版（Onboarding 第 9 步），付費用戶看管理版。
          expect(
            find.text(
              tier == SubscriptionTierHelper.free ? '升級方案' : '方案與額度',
            ),
            findsOneWidget,
            reason: '$tier $entry',
          );
        }
      }
    });

    // Onboarding 第 2 步：翻牌撞牆的專屬大標。免費版沒有每日翻牌，不寫恢復時間；付費
    // 方案先講翻牌什麼時候恢復（台北中午 12 點，不是一般額度的早上 8 點），Essential
    // 不叫他升級。
    test('翻牌入口的大標照目前方案：免費講升級後多什麼，付費先講中午 12 點恢復', () {
      expect(
        PaywallEntry.practiceDraw.headlineFor(SubscriptionTierHelper.free),
        '想再練一位？\n免費版只有一次翻牌；升級後每天翻 '
        '${AppConstants.starterDailyDrawLimit} 位，同一位能續聊',
      );
      expect(
        PaywallEntry.practiceDraw.headlineFor(SubscriptionTierHelper.starter),
        '今天的翻牌用完了\n每天中午 12 點恢復；升級 Essential 每天翻 '
        '${AppConstants.essentialDailyDrawLimit} 位',
      );
      final essential = PaywallEntry.practiceDraw
          .headlineFor(SubscriptionTierHelper.essential);
      expect(essential, '今天的翻牌用完了\n每天中午 12 點恢復');
      expect(essential, isNot(contains('升級')));
      expect(
        PaywallEntry.practiceDraw.headlineFor(null),
        PaywallEntry.practiceDraw.headlineFor(SubscriptionTierHelper.free),
        reason: '不認得的方案當免費',
      );
      for (final tier in tiers) {
        final text = PaywallEntry.practiceDraw.headlineFor(tier);
        expect(text, isNot(contains('明天')), reason: tier);
        expect(text, isNot(contains('早上 8 點')), reason: tier);
      }
      expect(PaywallEntry.practiceDraw.funnelValue, 'practice_draw');
    });

    testWidgets('從翻牌撞牆打開：免費、Starter、Essential 各換翻牌大標', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final tier in tiers) {
        final stub = _StubSubscriptionNotifier();
        final limits = SubscriptionTierHelper.limitsFor(tier);
        stub.seedState(SubscriptionState(
          tier: tier,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
        ));
        // 每一輪換新的 ProviderScope：同一個 scope 重建時 override 不會換掉。
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey('practice-draw-$tier'),
            overrides: [
              subscriptionProvider.overrideWith((ref) => stub),
              subscriptionScreenRefreshProvider.overrideWithValue(
                () async {},
              ),
            ],
            child: const MaterialApp(
              home: PaywallScreen(entry: PaywallEntry.practiceDraw),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text(PaywallEntry.practiceDraw.headlineFor(tier)),
          findsOneWidget,
          reason: tier,
        );
        expect(find.text('完整教練帶路\n把她約出來更有把握'), findsNothing);
        expect(
          find.text(
            tier == SubscriptionTierHelper.free ? '升級方案' : '方案與額度',
          ),
          findsOneWidget,
          reason: tier,
        );
      }
    });

    testWidgets('從鎖住的卡打開：大標跟著換；免費用戶看購買版', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
          ],
          child: const MaterialApp(
            home: PaywallScreen(entry: PaywallEntry.lockedCards),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
            PaywallEntry.lockedCards.headlineFor(SubscriptionTierHelper.free)),
        findsOneWidget,
      );
      expect(find.text('完整教練帶路\n把她約出來更有把握'), findsNothing);
      expect(find.text('升級方案'), findsOneWidget);
      expect(find.textContaining('升級會立即生效'), findsNothing);
    });
  });

  // Onboarding 第 9 步：免費用戶撞額度時打開的是購買版——第一屏就看得到兩張方案卡、
  // App Store 價格，購買鈕固定在底部。
  group('購買版（免費用戶）', () {
    SubscriptionState freeWithProducts() => SubscriptionState(
          dailyMessagesUsed: AppConstants.freeDailyLimit,
          storeProducts: _allProducts(),
        );
    Finder bottomBar() => find.byKey(const ValueKey('paywall-buy-bottom-bar'));
    Finder inBottomBar(Finder finder) =>
        find.descendant(of: bottomBar(), matching: finder);
    Finder segment(String label) => find.descendant(
          of: find.byType(BrandSegmentedButton<bool>),
          matching: find.text(label),
        );
    Finder renewalNote() =>
        find.byKey(const ValueKey('paywall-buy-renewal-note'));

    /// 購買鈕底下的扣款與續訂說明（拆成幾段排，接起來是一句）。
    String renewalText(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(of: renewalNote(), matching: find.byType(Text)),
        )
        .map((text) => text.data!)
        .join();

    testWidgets('第一屏（390x844，扣掉瀏海與底部橫條）就有兩張方案卡、價格與固定在底部的購買鈕；沒有按比例計費句',
        (tester) async {
      final dpr = tester.view.devicePixelRatio;
      tester.view.padding = FakeViewPadding(top: 47 * dpr, bottom: 34 * dpr);
      addTearDown(tester.view.resetPadding);
      await pumpPaywall(
        tester,
        state: freeWithProducts(),
        entry: PaywallEntry.dailyQuotaUsedUp,
        size: const Size(390, 844),
      );

      // 兩張卡整張都在固定底部上面，不用捲就看得到；價格是 App Store 回傳的字串。
      final barTop = tester.getTopLeft(bottomBar()).dy;
      for (final id in ['starter_monthly', 'essential_monthly']) {
        expect(_buyCard(id), findsOneWidget, reason: id);
        expect(tester.getRect(_buyCard(id)).bottom, lessThanOrEqualTo(barTop),
            reason: id);
      }
      expect(_buyCard('starter_quarterly'), findsNothing);
      expect(_buyCard('essential_quarterly'), findsNothing);
      expect(
          _inBuyCard('starter_monthly', find.text(r'NT$590')), findsOneWidget);
      expect(_inBuyCard('essential_monthly', find.text(r'NT$1,290')),
          findsOneWidget);

      // 購買鈕、扣款與自動續訂說明、條款與隱私都在固定底部，底部橫條上面（App
      // Review 3.1.2；「由 Apple ID 扣款」是主審第 1 輪建議補回的舊頁揭露）。
      final buy = inBottomBar(find.text(r'以 NT$590 訂閱 Starter 月繳'));
      expect(buy, findsOneWidget);
      expect(tester.getRect(buy).bottom, lessThanOrEqualTo(844 - 34));
      expect(inBottomBar(renewalNote()), findsOneWidget);
      expect(renewalText(tester), '由 Apple ID 扣款，每月自動續訂，可隨時在 iPhone 設定取消');
      expect(inBottomBar(find.text('服務條款')), findsOneWidget);
      expect(inBottomBar(find.text('隱私政策')), findsOneWidget);

      // 標題、X、右上恢復購買；大標第二行先講恢復時間、做成副標；差異句。
      expect(find.text('升級方案'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.widgetWithText(TextButton, '恢復購買'), findsOneWidget);
      final headline = tester.widget<Text>(find.text(
        PaywallEntry.dailyQuotaUsedUp.headlineFor(SubscriptionTierHelper.free),
      ));
      final title = headline.textSpan! as TextSpan;
      expect(title.text, '今天的額度用完了');
      final subtitle = title.children!.single as TextSpan;
      expect(subtitle.text, '\n每天早上 8 點恢復；升級後每天能用更多');
      expect(subtitle.style!.fontSize!, lessThan(title.style!.fontSize!));
      expect(find.textContaining('它認得你聊的每一個她'), findsOneWidget);

      // 管理版的東西不放：按比例計費句、額度膠囊、降級排程、管理訂閱；比較表收著。
      expect(find.textContaining('按比例'), findsNothing);
      expect(find.textContaining('升級會立即生效'), findsNothing);
      expect(find.text('目前方案與額度'), findsNothing);
      expect(find.text('本月剩餘'), findsNothing);
      expect(find.text('今日剩餘'), findsNothing);
      expect(find.textContaining('已排程降級'), findsNothing);
      expect(find.text('管理訂閱'), findsNothing);
      expect(find.text('方案與額度'), findsNothing);
      expect(find.text('方案功能比較'), findsNothing);
      // 不寫試用、倒數、打折。
      expect(find.textContaining(RegExp('試用|倒數|限時|打折|折扣|優惠')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('最矮的 iPhone（375x667）也排得下：沒有溢出，購買鈕在畫面裡', (tester) async {
      await pumpPaywall(
        tester,
        state: freeWithProducts(),
        entry: PaywallEntry.monthlyQuotaUsedUp,
        size: const Size(375, 667),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.text(r'以 NT$590 訂閱 Starter 月繳')).bottom,
        lessThanOrEqualTo(667),
      );
      for (final id in ['starter_monthly', 'essential_monthly']) {
        expect(
          tester.getRect(_inBuyCard(id, find.textContaining('NT\$'))).bottom,
          lessThan(tester.getTopLeft(bottomBar()).dy),
          reason: '$id 的價格在第一屏',
        );
      }
    });

    // 卡片權益只用真的數字（Eric：一個數字都不要自己編），冊數跟比較表那兩格一致；
    // 草稿潤飾 7/28 起全方案都能用（D-4），不能寫成 Essential 才有。
    testWidgets('卡片權益照 AppConstants 與比較表；不把草稿潤飾寫成 Essential 權益',
        (tester) async {
      await pumpPaywall(tester, state: freeWithProducts());

      String cardText(String id) => tester
          .widgetList<Text>(_inBuyCard(id, find.byType(Text)))
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
          .join();
      final starter = cardText('starter_monthly');
      expect(
        starter,
        contains('每月 ${AppConstants.starterMonthlyLimit} 則・'
            '每天 ${AppConstants.starterDailyLimit} 則'),
      );
      expect(
        starter,
        contains('陪練每天翻 ${AppConstants.starterDailyDrawLimit} 位、同一位能續聊'),
      );
      expect(starter, contains('互動電子書 4 冊＋聊天測驗全關卡'));
      final essential = cardText('essential_monthly');
      expect(
        essential,
        contains('每月 ${AppConstants.essentialMonthlyLimit} 則・'
            '每天 ${AppConstants.essentialDailyLimit} 則'),
      );
      expect(
        essential,
        contains('陪練每天翻 ${AppConstants.essentialDailyDrawLimit} 位、同一位能續聊'),
      );
      expect(essential, contains('互動電子書全 7 冊、夜市實戰影片完整版'));
      expect(find.textContaining('草稿潤飾'), findsNothing);

      // 冊數、夜市影片跟比較表同一格。
      await tester.tap(find.byKey(const ValueKey('paywall-compare-toggle')));
      await tester.pumpAndSettle();
      List<String?> cellsOf(String feature) => tester
          .widgetList<Text>(find.descendant(
            of: find
                .ancestor(of: find.text(feature), matching: find.byType(Row))
                .first,
            matching: find.byType(Text),
          ))
          .map((text) => text.data)
          .toList();
      expect(cellsOf('互動電子書'), ['互動電子書', '第 1 冊＋試讀', '4 冊', '全 7 冊']);
      expect(cellsOf('聊天測驗'), ['聊天測驗', '免費關卡', '全部關卡', '全部關卡']);
      expect(cellsOf('夜市實戰影片'), ['夜市實戰影片', '第一段', '第一段', '完整流程＋復盤']);
    });

    testWidgets('比較全部方案：預設收著，點了才展開既有的比較表', (tester) async {
      await pumpPaywall(tester, state: freeWithProducts());

      expect(find.text('方案功能比較'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('paywall-compare-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('方案功能比較'), findsOneWidget);
      expect(find.text('陪練女孩翻牌'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('paywall-compare-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('方案功能比較'), findsNothing);
    });

    testWidgets('切到季繳：卡片換季繳價，月均價無條件進位、字比扣款金額小；續訂說明與購買鈕改季', (tester) async {
      await pumpPaywall(tester, state: freeWithProducts());

      // 季繳那一格寫選到的方案省多少：1 - 1590 ÷ (590 × 3) = 10.2% → 省 10%。
      await tester.tap(segment('季繳 省 10%'));
      await tester.pumpAndSettle();

      expect(_buyCard('starter_monthly'), findsNothing);
      expect(_buyCard('essential_monthly'), findsNothing);
      final starterPrice =
          _inBuyCard('starter_quarterly', find.text(r'NT$1,590'));
      expect(starterPrice, findsOneWidget);
      expect(_inBuyCard('essential_quarterly', find.text(r'NT$3,490')),
          findsOneWidget);
      // 1590 ÷ 3 = 530 整除；3490 ÷ 3 = 1163.33… 無條件進位成 1,164，寫「約」。
      final starterAverage =
          _inBuyCard('starter_quarterly', find.text(r'平均每月 NT$530'));
      expect(starterAverage, findsOneWidget);
      expect(
        _inBuyCard('essential_quarterly', find.text(r'平均每月約 NT$1,164')),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(starterAverage).style!.fontSize!,
        lessThan(tester.widget<Text>(starterPrice).style!.fontSize!),
      );
      expect(
          _inBuyCard('starter_quarterly', find.text('省 10%')), findsOneWidget);
      expect(
          _inBuyCard('essential_quarterly', find.text('省 9%')), findsOneWidget);
      // 續訂週期寫季，不能寫成每月。
      expect(renewalText(tester), '由 Apple ID 扣款，每 3 個月自動續訂，可隨時在 iPhone 設定取消');
      expect(find.text(r'以 NT$1,590 訂閱 Starter 季繳'), findsOneWidget);

      // 點 Essential：季繳那一格換成 Essential 省多少；切回月繳還是 Essential。
      await tester.tap(_buyCard('essential_quarterly'));
      await tester.pumpAndSettle();
      expect(find.text(r'以 NT$3,490 訂閱 Essential 季繳'), findsOneWidget);
      expect(segment('季繳 省 9%'), findsOneWidget);
      await tester.tap(segment('月繳'));
      await tester.pumpAndSettle();
      expect(_buyCardSelected(tester, 'essential_monthly'), isTrue);
      expect(find.text(r'以 NT$1,290 訂閱 Essential 月繳'), findsOneWidget);
      expect(renewalText(tester), '由 Apple ID 扣款，每月自動續訂，可隨時在 iPhone 設定取消');
      // 選卡只有 240ms 的邊框漸變，跑完就靜止。
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('推薦徽章與橘色樣式跟著預設那張：免費是 Starter，月繳、季繳都標在 Starter', (tester) async {
      await pumpPaywall(tester, state: freeWithProducts());

      final starterBadge = _inBuyCard('starter_monthly', find.text('推薦'));
      expect(_visibleCount(starterBadge), 1);
      expect(_badgeIsOrange(tester, starterBadge), isTrue);
      expect(
          _visibleCount(_inBuyCard('essential_monthly', find.text('推薦'))), 0);
      // 管理版的固定標籤（入門、最划算）不放進購買版。
      expect(find.text('入門'), findsNothing);
      expect(find.text('最划算'), findsNothing);

      await tester.tap(segment('季繳 省 10%'));
      await tester.pumpAndSettle();
      expect(
          _visibleCount(_inBuyCard('starter_quarterly', find.text('推薦'))), 1);
      expect(
          _visibleCount(_inBuyCard('essential_quarterly', find.text('推薦'))), 0);
    });

    testWidgets('價格還沒到：卡片寫價格同步中，購買鈕改成重新載入價格；切換與點卡照舊', (tester) async {
      await pumpPaywall(tester, state: const SubscriptionState());

      expect(_inBuyCard('starter_monthly', find.text('價格同步中')), findsOneWidget);
      expect(
          _inBuyCard('essential_monthly', find.text('價格同步中')), findsOneWidget);
      expect(inBottomBar(find.text('重新載入 App Store 價格')), findsOneWidget);
      expect(find.textContaining('平均每月'), findsNothing);
      // 全部都還沒價格：預設、推薦都在 Starter 月繳；月繳／季繳照樣能切、卡照樣能點。
      expect(_buyCardSelected(tester, 'starter_monthly'), isTrue);
      expect(_visibleCount(_inBuyCard('starter_monthly', find.text('推薦'))), 1);
      await tester.tap(segment('季繳'));
      await tester.pumpAndSettle();
      expect(_buyCardSelected(tester, 'starter_quarterly'), isTrue);
      await tester.tap(_buyCard('essential_quarterly'));
      await tester.pumpAndSettle();
      expect(_buyCardSelected(tester, 'essential_quarterly'), isTrue);
      expect(inBottomBar(find.text('重新載入 App Store 價格')), findsOneWidget);
    });

    // 主審第 1 輪 P2：App Store 只回了部分方案時，買得到的方案一定選得到。購買版一次
    // 只顯示一個週期；以前選到沒價格的方案會退回「第一個有價格的」，例如只有 Starter
    // 月繳與 Essential 季繳時，點季繳又被拉回 Starter 月繳，Essential 季繳永遠選不到。
    SubscriptionState freeWith(List<String> productIds) => SubscriptionState(
          storeProducts: {
            for (final entry in _allProducts().entries)
              if (productIds.contains(entry.key)) entry.key: entry.value,
          },
        );
    Finder periodToggle() => find.byType(BrandSegmentedButton<bool>);
    int recommendedOn(String optionId) =>
        _visibleCount(_inBuyCard(optionId, find.text('推薦')));

    testWidgets('只回 Starter 月繳與 Essential 季繳：點季繳選到 Essential 季繳，兩張都選得到',
        (tester) async {
      await pumpPaywall(
        tester,
        state: freeWith(['starter_monthly', 'essential_quarterly']),
      );

      expect(periodToggle(), findsOneWidget);
      expect(_buyCardSelected(tester, 'starter_monthly'), isTrue);
      expect(recommendedOn('starter_monthly'), 1);
      // Essential 月繳沒有價格：點了不換選取。
      await tester.tap(_buyCard('essential_monthly'));
      await tester.pumpAndSettle();
      expect(_buyCardSelected(tester, 'starter_monthly'), isTrue);
      expect(find.text(r'以 NT$590 訂閱 Starter 月繳'), findsOneWidget);

      // 切到季繳：Starter 季繳沒價格，選同週期買得到的 Essential 季繳。
      await tester.tap(segment('季繳'));
      await tester.pumpAndSettle();
      expect(_buyCardSelected(tester, 'essential_quarterly'), isTrue);
      expect(find.text(r'以 NT$3,490 訂閱 Essential 季繳'), findsOneWidget);
      expect(renewalText(tester), '由 Apple ID 扣款，每 3 個月自動續訂，可隨時在 iPhone 設定取消');
      // 買不到的 Starter 季繳不標推薦，點了也不換。
      expect(recommendedOn('starter_quarterly'), 0);
      await tester.tap(_buyCard('starter_quarterly'));
      await tester.pumpAndSettle();
      expect(_buyCardSelected(tester, 'essential_quarterly'), isTrue);

      // 切回月繳：Essential 月繳沒價格，回到買得到的 Starter 月繳。
      await tester.tap(segment('月繳'));
      await tester.pumpAndSettle();
      expect(_buyCardSelected(tester, 'starter_monthly'), isTrue);
      expect(find.text(r'以 NT$590 訂閱 Starter 月繳'), findsOneWidget);
    });

    testWidgets('只有月繳：不放切換，兩張月繳卡都選得到，預設與推薦都是 Starter 月繳', (tester) async {
      await pumpPaywall(
        tester,
        state: freeWith(['starter_monthly', 'essential_monthly']),
      );

      expect(periodToggle(), findsNothing);
      expect(_buyCardSelected(tester, 'starter_monthly'), isTrue);
      expect(recommendedOn('starter_monthly'), 1);
      await tester.tap(_buyCard('essential_monthly'));
      await tester.pumpAndSettle();
      expect(_buyCardSelected(tester, 'essential_monthly'), isTrue);
      expect(find.text(r'以 NT$1,290 訂閱 Essential 月繳'), findsOneWidget);
    });

    testWidgets('只有季繳：不放切換，預設退到 Starter 季繳、推薦跟著，Essential 季繳也選得到',
        (tester) async {
      await pumpPaywall(
        tester,
        state: freeWith(['starter_quarterly', 'essential_quarterly']),
      );

      expect(periodToggle(), findsNothing);
      expect(_buyCard('starter_monthly'), findsNothing);
      expect(_buyCardSelected(tester, 'starter_quarterly'), isTrue);
      expect(recommendedOn('starter_quarterly'), 1);
      expect(find.text(r'以 NT$1,590 訂閱 Starter 季繳'), findsOneWidget);
      expect(renewalText(tester), '由 Apple ID 扣款，每 3 個月自動續訂，可隨時在 iPhone 設定取消');
      await tester.tap(_buyCard('essential_quarterly'));
      await tester.pumpAndSettle();
      expect(_buyCardSelected(tester, 'essential_quarterly'), isTrue);
      expect(find.text(r'以 NT$3,490 訂閱 Essential 季繳'), findsOneWidget);
    });

    testWidgets('只有一張卡：不管是哪一張都直接選到它；同畫面另一張買不到，不標推薦、點了不換', (tester) async {
      const buyLabels = {
        'starter_monthly': r'以 NT$590 訂閱 Starter 月繳',
        'starter_quarterly': r'以 NT$1,590 訂閱 Starter 季繳',
        'essential_monthly': r'以 NT$1,290 訂閱 Essential 月繳',
        'essential_quarterly': r'以 NT$3,490 訂閱 Essential 季繳',
      };
      for (final MapEntry(key: id, value: label) in buyLabels.entries) {
        await pumpPaywall(tester, state: freeWith([id]));

        expect(periodToggle(), findsNothing, reason: id);
        expect(_buyCardSelected(tester, id), isTrue, reason: id);
        expect(find.text(label), findsOneWidget, reason: id);
        final other = id.startsWith('starter')
            ? id.replaceFirst('starter', 'essential')
            : id.replaceFirst('essential', 'starter');
        expect(recommendedOn(other), 0, reason: id);
        await tester.tap(_buyCard(other));
        await tester.pumpAndSettle();
        expect(_buyCardSelected(tester, id), isTrue, reason: id);
        expect(find.text(label), findsOneWidget, reason: id);
      }
    });
  });

  // Onboarding 第 9 步：第一幀的方案可能還是本機快取（isLoading），先排骨架，等第一次
  // 同步完才決定購買版或管理版，不先閃錯的那一版再換。
  group('方案同步中先排骨架', () {
    Finder skeleton() => find.byKey(const ValueKey('paywall-loading-skeleton'));
    bool manageShown() =>
        find.text('方案與額度').evaluate().isNotEmpty ||
        find.textContaining('升級會立即生效').evaluate().isNotEmpty;
    bool buyShown() => find.text('升級方案').evaluate().isNotEmpty;

    Future<_StubSubscriptionNotifier> pumpWith(
      WidgetTester tester,
      SubscriptionState initial,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final stub = _StubSubscriptionNotifier()..seedState(initial);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionProvider.overrideWith((ref) => stub),
            subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
          ],
          child: const MaterialApp(home: PaywallScreen()),
        ),
      );
      return stub;
    }

    SubscriptionState loading(String tier) {
      final limits = SubscriptionTierHelper.limitsFor(tier);
      return SubscriptionState(
        tier: tier,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        isLoading: true,
      );
    }

    testWidgets('快取是付費、同步完是免費：先骨架，直接進購買版，中間不閃管理版', (tester) async {
      final stub =
          await pumpWith(tester, loading(SubscriptionTierHelper.starter));

      for (var frame = 0; frame < 3; frame++) {
        expect(skeleton(), findsOneWidget);
        expect(manageShown(), isFalse);
        expect(buyShown(), isFalse);
        // 骨架也關得掉。
        expect(find.byIcon(Icons.close), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
      }

      stub.seedState(const SubscriptionState());
      await tester.pump();
      expect(skeleton(), findsNothing);
      expect(buyShown(), isTrue);
      expect(manageShown(), isFalse);
    });

    testWidgets('快取是免費、同步完是 Starter：先骨架，不先閃購買版，直接進管理版', (tester) async {
      final stub = await pumpWith(tester, loading(SubscriptionTierHelper.free));

      expect(skeleton(), findsOneWidget);
      expect(buyShown(), isFalse);
      expect(manageShown(), isFalse);

      stub.seedState(_paidState(SubscriptionTierHelper.starter));
      await tester.pump();
      expect(skeleton(), findsNothing);
      expect(manageShown(), isTrue);
      expect(buyShown(), isFalse);
    });

    testWidgets('同步一直沒回來：最多等 2 秒，就照當下的方案排版面', (tester) async {
      await pumpWith(tester, loading(SubscriptionTierHelper.free));

      expect(skeleton(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1900));
      expect(skeleton(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(skeleton(), findsNothing);
      expect(buyShown(), isTrue);
    });

    testWidgets('版面排好之後再刷新（isLoading 又變 true）：不閃回骨架', (tester) async {
      final stub = await pumpWith(tester, const SubscriptionState());
      await tester.pump();
      expect(buyShown(), isTrue);

      // 每次打開付費頁都會刷新方案；購買時也會把 isLoading 設成 true。
      stub.seedState(const SubscriptionState(isLoading: true));
      await tester.pump();
      expect(skeleton(), findsNothing);
      expect(buyShown(), isTrue);
    });
  });
}

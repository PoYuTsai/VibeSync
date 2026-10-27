// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/opener/domain/opener_access.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/screens/paywall_screen.dart';
import 'package:vibesync/features/subscription/presentation/subscription_diagnostics_gate.dart';

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

void main() {
  Future<void> pumpPaywall(
    WidgetTester tester, {
    Future<void> Function()? refreshUsage,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionScreenRefreshProvider.overrideWithValue(
            refreshUsage ?? () async {},
          ),
        ],
        child: const MaterialApp(home: PaywallScreen()),
      ),
    );
    await tester.pump();
  }

  group('PaywallScreen', () {
    testWidgets('refreshes subscription usage snapshot on entry',
        (tester) async {
      var refreshCalls = 0;
      await pumpPaywall(tester, refreshUsage: () async {
        refreshCalls++;
      });

      expect(refreshCalls, 1);
    });

    testWidgets('shows launch-ready title and upgrade/downgrade copy',
        (tester) async {
      await pumpPaywall(tester);

      expect(find.text('方案與額度'), findsOneWidget);
      expect(find.text('完整教練帶路\n把她約出來更有把握'), findsOneWidget);
      expect(find.textContaining('升級會立即生效'), findsAtLeastNWidgets(1));
      expect(find.textContaining('降級則會在下次續訂時生效'), findsOneWidget);
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

      expect(find.text('方案與額度'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('home-root'), findsOneWidget);
      expect(find.text('方案與額度'), findsNothing);
    });

    testWidgets('shows current Free quota summary with remaining counts',
        (tester) async {
      await pumpPaywall(tester);

      expect(find.text('目前方案與額度'), findsOneWidget);
      expect(find.text('目前方案：Free'), findsOneWidget);
      expect(find.text('本月剩餘'), findsOneWidget);
      expect(find.text('今日剩餘'), findsOneWidget);
      // 免費額度照常數算，之後再調也不用改這裡。
      const monthly = AppConstants.freeMonthlyLimit;
      const daily = AppConstants.freeDailyLimit;
      expect(find.text('$monthly/$monthly'), findsOneWidget);
      expect(find.text('$daily/$daily'), findsOneWidget);
    });

    testWidgets('比較表的每日、每月額度三欄都照方案常數', (tester) async {
      await pumpPaywall(tester);

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
      await pumpPaywall(tester);

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
      await pumpPaywall(tester);

      expect(find.text('燈號走勢與邀約進度'), findsNothing);
      expect(find.text('燈號紀錄與邀約進度'), findsNothing);
      expect(find.text('最新一次'), findsNothing);
      expect(find.text('完整走勢'), findsNothing);
    });

    testWidgets('比較表有開場救星：句數照開場權益契約，排在回覆卡下面', (tester) async {
      await pumpPaywall(tester);

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
      await pumpPaywall(tester);

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
      await pumpPaywall(tester);

      // Free has no daily draw (removed 2026-08-02); only one round per girl.
      // Upgrading unlocks daily draws and continuing the same girl.
      expect(find.textContaining('同一位陪練女孩只能練一輪'), findsOneWidget);
      expect(find.textContaining('續聊同一位'), findsOneWidget);
      expect(find.textContaining('每天仍可翻出'), findsNothing); // 舊前提絕不回歸
    });

    testWidgets('shows four product options while prices are syncing',
        (tester) async {
      await pumpPaywall(tester);

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
    });

    testWidgets('Essential monthly option is selected by default',
        (tester) async {
      await pumpPaywall(tester);

      final essentialMonthlyRadio = tester.widget<Radio<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Radio<String> && widget.value == 'essential_monthly',
        ),
      );
      expect(essentialMonthlyRadio.groupValue, 'essential_monthly');
    });

    testWidgets('can switch selected product option before purchasing',
        (tester) async {
      await pumpPaywall(tester);

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
      await pumpPaywall(tester);
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
      await pumpPaywall(tester);

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

    // 主審 r1 P2-3：大標要給做得到的下一步。免費、Starter 升級後額度更多；Essential
    // 已經是最高方案，不承諾升級，只說什麼時候恢復（伺服器照 UTC 換日、換月重算，
    // 台灣是早上 8 點）；也不說換繳費週期會補額度。
    test('額度大標照目前方案：免費、Starter 說升級後更多，Essential 說什麼時候恢復', () {
      const upgradeable = {
        PaywallEntry.dailyQuotaUsedUp: '今天的額度用完了\n升級後每天能用更多',
        PaywallEntry.dailyQuotaShort: '今天的額度不夠這次用\n升級後每天能用更多',
        PaywallEntry.monthlyQuotaUsedUp: '這個月的額度用完了\n升級後每月能用更多',
        PaywallEntry.monthlyQuotaShort: '這個月的額度不夠這次用\n升級後每月能用更多',
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
          expect(find.text('方案與額度'), findsOneWidget);
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
        expect(find.text('方案與額度'), findsOneWidget);
      }
    });

    testWidgets('從鎖住的卡打開：標題跟著換，其他內容照舊', (tester) async {
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
      expect(find.text('方案與額度'), findsOneWidget);
      expect(find.textContaining('升級會立即生效'), findsAtLeastNWidgets(1));
    });
  });
}

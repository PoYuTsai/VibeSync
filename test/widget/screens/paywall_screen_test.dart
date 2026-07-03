// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
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
      expect(find.text('完整分析\n回覆更有把握'), findsOneWidget);
      expect(find.textContaining('升級會立即生效'), findsAtLeastNWidgets(1));
      expect(find.textContaining('降級則會在下次續訂時生效'), findsOneWidget);
    });

    testWidgets('shows current Free quota summary with remaining counts',
        (tester) async {
      await pumpPaywall(tester);

      expect(find.text('目前方案與額度'), findsOneWidget);
      expect(find.text('目前方案：Free'), findsOneWidget);
      expect(find.text('本月剩餘'), findsOneWidget);
      expect(find.text('今日剩餘'), findsOneWidget);
      expect(find.text('30/30'), findsOneWidget);
      expect(find.text('15/15'), findsOneWidget);
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
      expect(find.text('雷達圖'), findsOneWidget);
      expect(find.text('可用'), findsNWidgets(4));
      expect(find.text('未開放'), findsNWidgets(5));
      expect(find.text('120 則'), findsOneWidget);
      expect(find.text('800 則'), findsOneWidget);
    });

    testWidgets('comparison table includes practice girl and model copy',
        (tester) async {
      await pumpPaywall(tester);

      expect(find.text('陪練女孩'), findsOneWidget);
      expect(find.text('每日 1 位'), findsOneWidget);
      expect(find.text('開放'), findsNWidgets(2));
      expect(find.text('AI 模型'), findsOneWidget);
      expect(find.text('經濟型'), findsOneWidget);
      expect(find.text('高階型'), findsNWidgets(2));
      expect(find.textContaining('Haiku'), findsNothing);
      expect(find.textContaining('Sonnet'), findsNothing);
    });

    testWidgets('explains the Free vs paid practice-girl continuation rule',
        (tester) async {
      await pumpPaywall(tester);

      // Free can still draw new practice girls daily, but only one round each;
      // upgrading unlocks continuing the same girl for a fuller practice.
      expect(find.textContaining('同一位只能練一輪'), findsOneWidget);
      expect(find.textContaining('續聊同一位'), findsOneWidget);
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

    testWidgets(
        'restore success with hanging refresh still completes and pops',
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
      expect(find.text('home-root'), findsOneWidget);
      await flushSnackBars(tester);
    });

    testWidgets(
        'purchase success with failing refresh must not report failure',
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
}

// test/widget/features/subscription/home_quota_strip_test.dart
//
// 首頁免費額度小條（onboarding 轉化 Tier 2 批 1）：
// - 免費用戶顯示剩餘次數；付費用戶整條隱藏。
// - 剩 ≤3 次切換醒目色（以 key 驗證，不驗像素）。
// - 點擊開說明 sheet，內含「看訂閱方案」導向 /paywall。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/widgets/home_quota_strip.dart';

/// Seeded subscription notifier，同 my_report_screen_test 的 seeded-notifier
/// idiom：constructor body 直接覆寫 state，async 初始化在測試環境全為 no-op。
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

GoRouter _stubRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: HomeQuotaStrip()),
        ),
        GoRoute(
          path: '/paywall',
          builder: (_, __) => const Scaffold(body: Text('paywall-screen')),
        ),
      ],
    );

Future<int> _pumpStrip(
  WidgetTester tester, {
  required SubscriptionState subscription,
}) async {
  var refreshCalls = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionProvider.overrideWith(
          (ref) => _SeededSubscriptionNotifier(subscription),
        ),
        subscriptionScreenRefreshProvider.overrideWithValue(() async {
          refreshCalls++;
        }),
      ],
      child: MaterialApp.router(routerConfig: _stubRouter()),
    ),
  );
  await tester.pump();
  return refreshCalls;
}

void main() {
  testWidgets('免費用戶顯示剩餘次數，並 best-effort 觸發一次額度刷新', (tester) async {
    final refreshCalls = await _pumpStrip(
      tester,
      subscription: const SubscriptionState(
        tier: SubscriptionTierHelper.free,
        monthlyMessagesUsed: 7,
        monthlyLimit: 30,
      ),
    );

    expect(find.text('本月免費額度還剩 23 則'), findsOneWidget);
    expect(find.byKey(HomeQuotaStrip.normalKey), findsOneWidget);
    expect(find.byKey(HomeQuotaStrip.urgentKey), findsNothing);
    expect(refreshCalls, 1);
  });

  testWidgets('付費用戶整條隱藏', (tester) async {
    await _pumpStrip(
      tester,
      subscription: const SubscriptionState(
        tier: SubscriptionTierHelper.starter,
        monthlyMessagesUsed: 7,
        monthlyLimit: 300,
      ),
    );

    expect(find.textContaining('本月免費額度'), findsNothing);
    expect(find.byKey(HomeQuotaStrip.normalKey), findsNothing);
    expect(find.byKey(HomeQuotaStrip.urgentKey), findsNothing);
  });

  testWidgets('剩 3 次以下換醒目色 key', (tester) async {
    await _pumpStrip(
      tester,
      subscription: const SubscriptionState(
        tier: SubscriptionTierHelper.free,
        monthlyMessagesUsed: 27,
        monthlyLimit: 30,
      ),
    );

    expect(find.text('本月免費額度還剩 3 則'), findsOneWidget);
    expect(find.byKey(HomeQuotaStrip.urgentKey), findsOneWidget);
    expect(find.byKey(HomeQuotaStrip.normalKey), findsNothing);
  });

  testWidgets('點擊開說明 sheet，看訂閱方案導向 /paywall', (tester) async {
    await _pumpStrip(
      tester,
      subscription: const SubscriptionState(
        tier: SubscriptionTierHelper.free,
        monthlyMessagesUsed: 7,
        monthlyLimit: 30,
      ),
    );

    await tester.tap(find.text('本月免費額度還剩 23 則'));
    await tester.pumpAndSettle();

    expect(find.text('免費額度怎麼算？'), findsOneWidget);
    expect(find.text('看訂閱方案'), findsOneWidget);

    await tester.tap(find.text('看訂閱方案'));
    await tester.pumpAndSettle();

    expect(find.text('paywall-screen'), findsOneWidget);
  });
}

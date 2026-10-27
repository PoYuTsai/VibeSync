// 付費頁整頁截圖，給 Eric 目檢（DESIGN.md §10：視覺改動先出改前改後對照）。
// 出圖在 build/visual_proof/：
// - prod_paywall.png：管理版（Starter 用戶），430x1700 全高，看 B9 區塊分層節奏。
// - paywall_buy_free_monthly.png／paywall_buy_free_quarterly.png：免費用戶撞每日
//   額度時的購買版（Onboarding 第 9 步），430x1700 全高；季繳那張看月均價小字。
// - paywall_buy_free_first_screen.png：390x844（一般 iPhone 尺寸），看第一屏是不是
//   就有兩張方案卡、價格與購買鈕；paywall_buy_free_first_screen_se.png 是 375x667
//   （iPhone SE，最矮的機型）。
// 價格是測試用的假 StoreKit 商品（季繳價是編的），實機一律顯示 App Store 回傳的價格。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/screens/paywall_screen.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';

import 'proof_support.dart';

/// 一建立就是指定的方案狀態；刷新不動它。
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seeded) {
    state = seeded;
  }

  @override
  Future<void> refresh() async {}
}

StoreProduct _product(
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

SubscriptionState _stateWithProducts(String tier, {int dailyUsed = 0}) {
  final limits = SubscriptionTierHelper.limitsFor(tier);
  return SubscriptionState(
    tier: tier,
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
    dailyMessagesUsed: dailyUsed,
    monthlyMessagesUsed: dailyUsed,
    storeProducts: {
      'starter_monthly':
          _product('starter_monthly', 'Starter', 590, r'NT$590', 'P1M'),
      'starter_quarterly':
          _product('starter_quarterly', 'Starter', 1590, r'NT$1,590', 'P3M'),
      'essential_monthly':
          _product('essential_monthly', 'Essential', 1290, r'NT$1,290', 'P1M'),
      'essential_quarterly': _product(
          'essential_quarterly', 'Essential', 3490, r'NT$3,490', 'P3M'),
    },
  );
}

Future<void> _capture(
  WidgetTester tester, {
  required String name,
  required Size size,
  required SubscriptionState state,
  PaywallEntry entry = PaywallEntry.general,
  Future<void> Function(WidgetTester tester)? beforeCapture,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final rootKey = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionProvider
            .overrideWith((ref) => _SeededSubscriptionNotifier(state)),
        subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          child: RepaintBoundary(
            key: rootKey,
            child: PaywallScreen(entry: entry),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 800));
  if (beforeCapture != null) {
    await beforeCapture(tester);
    await tester.pump(const Duration(milliseconds: 800));
  }

  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    (File(outPath(name))..createSync(recursive: true))
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('capture paywall full page (manage layout, Starter)',
      (tester) async {
    await _capture(
      tester,
      name: 'prod_paywall.png',
      size: const Size(430, 1700),
      state: _stateWithProducts(SubscriptionTierHelper.starter),
    );
  });

  testWidgets('capture buy layout for free users (monthly)', (tester) async {
    await _capture(
      tester,
      name: 'paywall_buy_free_monthly.png',
      size: const Size(430, 1700),
      state: _stateWithProducts(
        SubscriptionTierHelper.free,
        dailyUsed:
            SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.free).daily,
      ),
      entry: PaywallEntry.dailyQuotaUsedUp,
    );
  });

  testWidgets('capture buy layout for free users (quarterly)', (tester) async {
    await _capture(
      tester,
      name: 'paywall_buy_free_quarterly.png',
      size: const Size(430, 1700),
      state: _stateWithProducts(
        SubscriptionTierHelper.free,
        dailyUsed:
            SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.free).daily,
      ),
      entry: PaywallEntry.dailyQuotaUsedUp,
      beforeCapture: (tester) async {
        await tester.tap(find.descendant(
          of: find.byType(BrandSegmentedButton<bool>),
          matching: find.textContaining('季繳'),
        ));
      },
    );
  });

  testWidgets('capture buy layout first screen (390x844)', (tester) async {
    await _capture(
      tester,
      name: 'paywall_buy_free_first_screen.png',
      size: const Size(390, 844),
      state: _stateWithProducts(
        SubscriptionTierHelper.free,
        dailyUsed:
            SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.free).daily,
      ),
      entry: PaywallEntry.dailyQuotaUsedUp,
    );
  });

  testWidgets('capture buy layout first screen (375x667, iPhone SE)',
      (tester) async {
    await _capture(
      tester,
      name: 'paywall_buy_free_first_screen_se.png',
      size: const Size(375, 667),
      state: _stateWithProducts(
        SubscriptionTierHelper.free,
        dailyUsed:
            SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.free).daily,
      ),
      entry: PaywallEntry.dailyQuotaUsedUp,
    );
  });
}

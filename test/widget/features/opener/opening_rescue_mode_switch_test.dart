// Route-level 整合測試（Codex 審查 I3，Eric 2026-07-24 拍板補）：
// /opener 的 mode deep link 與 IndexedStack 模式切換的 state 保留。
// Hermetic：Hive settingsBox（drafts）走 cache-service test 同款暫存目錄；
// subscription/partner providers 全 override，不打網路。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

/// mini router：/opener 的 builder wiring 與 lib/app/routes.dart 相同
/// （modeFromQuery 的 query 解析已由 new_topic_view_contract_test 鎖住）。
GoRouter _router(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/opener',
        builder: (context, state) => OpeningRescueScreen(
          partnerId: state.uri.queryParameters['partnerId'],
          initialMode: OpeningRescueScreen.modeFromQuery(
            state.uri.queryParameters['mode'],
          ),
        ),
      ),
    ],
  );
}

Future<void> _pump(WidgetTester t, String initialLocation) async {
  await t.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});

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
      child: MaterialApp.router(routerConfig: _router(initialLocation)),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

/// onstage＝IndexedStack 當前面板；另一側必須仍 mounted（offstage 找得到）。
void _expectOpenerActive(WidgetTester t) {
  expect(find.text('生成開場白'), findsOneWidget);
  expect(find.text('生成新話題'), findsNothing);
  expect(
    find.text('生成新話題', skipOffstage: false),
    findsOneWidget,
    reason: 'NewTopicView 必須保持 mounted（IndexedStack），不得被卸載',
  );
}

void _expectNewTopicActive(WidgetTester t) {
  expect(find.text('生成新話題'), findsOneWidget);
  expect(find.text('生成開場白'), findsNothing);
  expect(
    find.text('生成開場白', skipOffstage: false),
    findsOneWidget,
    reason: 'opener body 必須保持 mounted（IndexedStack），不得被卸載',
  );
}

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_opening_rescue_mode');
  });

  setUp(() async {
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('/opener 預設 opener 面板，New Topic 保持 mounted', (t) async {
    await _pump(t, '/opener');
    _expectOpenerActive(t);
  });

  testWidgets('?mode=new_topic deep link 直接落在新話題面板', (t) async {
    await _pump(t, '/opener?mode=new_topic');
    _expectNewTopicActive(t);
    // 沒有 partner 時顯示選擇對象卡（空 partner list → 建立 CTA）。
    expect(find.text('選擇對象'), findsOneWidget);
    expect(find.text('先建立一位對象'), findsOneWidget);
    // 沒選對象前生成鍵必須 disabled（不可能送出請求）。
    final button = t.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('生成新話題'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('unknown mode fallback opener', (t) async {
    await _pump(t, '/opener?mode=garbage');
    _expectOpenerActive(t);
  });

  testWidgets('模式來回切換保留兩側 state（輸入文字＋情境 chip 都不丟）', (t) async {
    await _pump(t, '/opener');
    _expectOpenerActive(t);

    // opener 側：切到手動輸入 tab 並輸入名字。
    await t.tap(find.text('手動輸入'));
    await t.pump();
    final nameField = find.byType(TextField).first;
    await t.enterText(nameField, '小雅');
    await t.pump();

    // 切到新話題側：選一個情境 chip。
    await t.tap(find.text('新話題'));
    await t.pump();
    _expectNewTopicActive(t);
    await t.tap(find.text('聊著但卡住'));
    await t.pump();
    ChoiceChip chipOf(String label) => t.widget<ChoiceChip>(
          find.ancestor(
            of: find.text(label, skipOffstage: false),
            matching: find.byType(ChoiceChip, skipOffstage: false),
          ),
        );
    expect(chipOf('聊著但卡住').selected, isTrue);

    // 切回 opener：輸入文字與 tab 選擇必須原封保留。
    await t.tap(find.text('開場白'));
    await t.pump();
    _expectOpenerActive(t);
    expect(find.text('小雅'), findsOneWidget);

    // 再切回新話題：情境 chip 仍選中（結果/選擇不因切換被清）。
    await t.tap(find.text('新話題'));
    await t.pump();
    _expectNewTopicActive(t);
    expect(chipOf('聊著但卡住').selected, isTrue);
  });
}

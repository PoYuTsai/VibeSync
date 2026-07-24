// 開場救星公式開場區塊 placement（2026-07-24 公式回覆計畫 §10.2/§12）。
// Hermetic：以草稿「回看」載入含公式的結果（不打網路），驗證：
// - 公式區在推薦理由之後、先鋒備案之前。
// - 「・N 種風格」只計原五風格卡，公式不算進 N。
// - 複製只複製 openingLine。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/opener/data/services/opener_result_cache_service.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/shared/widgets/formula_reply_section.dart';

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

const _formulaLine1 = '公式開場一：妳那張手沖照讓我想把週末咖啡因額度留給妳推薦的店。';
const _formulaWhy1 = '接她剛分享的生活片段，她補一家店名就能回，不用想太久。';

OpenerResult _resultWithFormula() {
  return OpenerResult.fromJson({
    'openers': {
      'extend': '延展句本體',
      'resonate': '共鳴句本體',
      'tease': '調情句本體',
      'humor': '幽默句本體',
      'coldRead': '冷讀句本體',
    },
    'recommendedPick': 'extend',
    'recommendedReason': '接住咖啡線索，留低壓開口。',
    'pioneerPlan': {'ifCold': '先停一拍', 'handoff': '回來分析'},
    'requestId': '123e4567-e89b-42d3-a456-426614174000',
    'formulaOpeners': [
      {'openingLine': _formulaLine1, 'whyItWorks': _formulaWhy1},
      {'openingLine': '公式開場二：不同線索的第二則。', 'whyItWorks': '第二則的教練註解。'},
    ],
  });
}

Future<void> _pump(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => t.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});

  await t.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionProvider.overrideWith(
          (ref) => _SeededSubscriptionNotifier(
            const SubscriptionState(
              tier: SubscriptionTierHelper.essential,
              monthlyLimit: 300,
              dailyLimit: 100,
            ),
          ),
        ),
        partnerListProvider.overrideWith((ref) => const []),
        // 畫面綁 partnerId：prefill/name 解析不得打到真 partner repo（Hive）。
        partnerByIdProvider.overrideWith((ref, id) => null),
        subscriptionScreenRefreshProvider.overrideWith((ref) => () async {}),
        coachingOutcomeEventProvider.overrideWith((ref, adviceId) => null),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/opener',
          routes: [
            GoRoute(
              path: '/opener',
              // 與 seed draft 同 partner scope（drafts 清單是 partner-scoped）。
              builder: (context, state) =>
                  const OpeningRescueScreen(partnerId: 'partner-1'),
            ),
          ],
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_opening_rescue_formula');
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

  testWidgets('公式開場：推薦理由之後、先鋒備案之前；N 種風格不計公式；複製只複製 openingLine',
      (t) async {
    final copied = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    // Hive 寫入是真 I/O：必須在 runAsync（testWidgets FakeAsync zone 內
    // 直接 await 會永遠不完成）。draft 綁 partnerId 讓 _openDraft 跳過
    // saveLatest 的真 I/O await。
    await t.runAsync(
      () => OpenerResultCacheService()
          .saveDraft(result: _resultWithFormula(), partnerId: 'partner-1'),
    );
    await _pump(t);

    // 以草稿回看載入結果（不打網路）。
    await t.tap(find.text('回看'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    // 原五風格 header 只計五卡，不含公式。
    expect(
      find.textContaining('5 種風格'),
      findsOneWidget,
      reason: '公式不得算進「N 種風格」',
    );

    // 排序：AI 推薦理由 → 公式開場 → 先鋒備案。
    expect(find.text('公式開場'), findsOneWidget);
    final reasonDy =
        t.getTopLeft(find.textContaining('AI 推薦理由', findRichText: true)).dy;
    final formulaDy = t.getTopLeft(find.text('公式開場')).dy;
    final pioneerDy = t.getTopLeft(find.text('先鋒備案')).dy;
    expect(reasonDy < formulaDy, isTrue, reason: '公式區在推薦理由之後');
    expect(formulaDy < pioneerDy, isTrue, reason: '公式區在先鋒備案（pioneerPlan）之前');

    // 兩張公式卡都渲染，教練註解在場。
    expect(find.text('為什麼好接'), findsNWidgets(2));
    expect(find.text(_formulaWhy1), findsOneWidget);

    // 複製只複製 openingLine（公式區內第一顆複製鍵）。
    final formulaCopy = find.descendant(
      of: find.byType(FormulaReplySection),
      matching: find.text('複製'),
    );
    expect(formulaCopy, findsNWidgets(2));
    await t.ensureVisible(formulaCopy.first);
    await t.tap(formulaCopy.first, warnIfMissed: false);
    await t.pump();
    expect(copied, [_formulaLine1]);
    expect(copied.single.contains(_formulaWhy1), isFalse);
  });

  testWidgets('公式空清單：整區不渲染，原結果照常', (t) async {
    final noFormula = OpenerResult.fromJson({
      'openers': {'extend': '延展句本體'},
      'recommendedPick': 'extend',
    });
    await t.runAsync(
      () => OpenerResultCacheService()
          .saveDraft(result: noFormula, partnerId: 'partner-1'),
    );
    await _pump(t);
    await t.tap(find.text('回看'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    expect(find.text('公式開場'), findsNothing);
    expect(find.text(FormulaReplySection.subtitle), findsNothing);
    expect(find.text('延展句本體'), findsOneWidget);
  });
}

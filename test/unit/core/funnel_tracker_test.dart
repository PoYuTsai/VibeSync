// test/unit/core/funnel_tracker_test.dart
//
// FunnelTracker（Tier 2 批 1.5）：best-effort 去識別化漏斗埋點封裝。
// - wire payload 只帶 client 白名單鍵；字典外事件根本不出手機。
// - 非 2xx／invoker 炸掉一律吞掉不 throw。
// - trackOnce 用 SharedPreferences once-flag 去重。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('wire payload：kind=funnel、事件與白名單鍵、clientTs', () async {
    Map<String, dynamic>? captured;
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async {
        expect(fn, 'submit-feedback');
        captured = body;
        return 200;
      },
    );

    await tracker.track(
      'coach_entry_tap',
      properties: {'has_partner': true, 'partnerName': '小美'},
    );

    expect(captured, isNotNull);
    expect(captured!['kind'], 'funnel');
    final event = captured!['event'] as Map<String, dynamic>;
    expect(event['event'], 'coach_entry_tap');
    expect(event['properties'], {'has_partner': true});
    expect(event['clientTs'], isA<String>());
  });

  test('字典外事件：invoker 不被呼叫', () async {
    var calls = 0;
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async {
        calls++;
        return 200;
      },
    );

    await tracker.track('made_up_event');

    expect(calls, 0);
  });

  test('非 2xx 不 throw', () async {
    final tracker = FunnelTracker(invoker: (fn, {required body}) async => 500);

    await tracker.track('quota_strip_tap');
  });

  test('invoker 炸掉不 throw', () async {
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async => throw StateError('boom'),
    );

    await tracker.track('quota_strip_tap');
  });

  test('鍵級白名單與字典逐字鎖死（Grok F5：防單邊漂移）', () {
    expect(FunnelTracker.eventProps, {
      'onboarding_page_view': ['page_index'],
      'onboarding_skip': ['page_index'],
      'onboarding_branch_answer': ['has_partner'],
      'onboarding_questionnaire_submit': ['goals_count'],
      'quota_strip_tap': <String>[],
      'opener_entry_tap': <String>[],
      'coach_entry_tap': ['has_partner'],
      'first_analysis_completed': <String>[],
      'first_practice_completed': <String>[],
      'keyboard_setup_shown': <String>[],
      'keyboard_setup_completed': <String>[],
      'checklist_item_done': ['item'],
      'about_me_opened': ['source'],
      'about_me_saved': [
        'has_style',
        'goals_count',
        'seeds_count',
        'has_notes',
        'has_custom_topics',
      ],
      'about_me_cleared': <String>[],
      'new_topic_copied': ['is_recommended'],
      'paywall_opened': ['entry'],
      'paywall_purchase_completed': ['tier', 'entry', 'purchaser'],
      'locked_cards_upgrade_tap': ['locked_count'],
    });
  });

  // 付費頁與鎖卡（Eric 2026-10-18）：價格、商品 id、收據連手機都不出。
  test('付費頁與鎖卡事件：只帶白名單鍵', () async {
    final sent = <Map<String, dynamic>>[];
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async {
        sent.add(body['event'] as Map<String, dynamic>);
        return 200;
      },
    );

    // purchaser（開始購買時的帳號，給伺服器比對）只有購買事件帶得出去。
    const buyer = '8f14e45f-ceea-4c6b-9a8e-3e4d4b5c6a7f';
    await tracker.track('paywall_opened', properties: {
      'entry': 'locked_cards',
      'route': '/paywall',
      'purchaser': buyer,
    });
    await tracker.track('paywall_purchase_completed', properties: {
      'tier': 'essential',
      'entry': 'quota_exhausted',
      'purchaser': buyer,
      'price': 590,
      'productId': 'vibesync_essential_monthly',
      'receipt': 'MIIT',
    });
    await tracker.track('locked_cards_upgrade_tap', properties: {
      'locked_count': 3,
      'tasks': ['push'],
      'purchaser': buyer,
    });

    final names = [for (final e in sent) e['event']];
    final props = [for (final e in sent) e['properties']];
    expect(names, [
      'paywall_opened',
      'paywall_purchase_completed',
      'locked_cards_upgrade_tap',
    ]);
    expect(props, [
      {'entry': 'locked_cards'},
      {'tier': 'essential', 'entry': 'quota_exhausted', 'purchaser': buyer},
      {'locked_count': 3},
    ]);
  });

  test('trackOnce：字典外事件不落 once-flag（GLM F6）', () async {
    final tracker = FunnelTracker(invoker: (fn, {required body}) async => 200);

    await tracker.trackOnce('not_in_dict');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('funnel_once_not_in_dict'), isNull);
  });

  test('trackOnce：同事件只送一次，跨 instance 也擋', () async {
    var calls = 0;
    FunnelTracker build() => FunnelTracker(
          invoker: (fn, {required body}) async {
            calls++;
            return 200;
          },
        );

    await build().trackOnce('first_analysis_completed');
    await build().trackOnce('first_analysis_completed');

    expect(calls, 1);
  });
}

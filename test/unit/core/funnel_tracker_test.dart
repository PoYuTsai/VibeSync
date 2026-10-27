// test/unit/core/funnel_tracker_test.dart
//
// FunnelTracker（Tier 2 批 1.5）：best-effort 去識別化漏斗埋點封裝。
// - wire payload 只帶 client 白名單鍵；字典外事件根本不出手機。
// - 非 2xx／invoker 炸掉一律吞掉不 throw。
// - trackOnce 用 SharedPreferences once-flag 去重。
// - 沒登入時排進手機佇列，登入後 flushPending 補送（onboarding 轉換第 4 步）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';

const _uid = 'user-a';

/// 已登入（送出路徑）。
String? _signedIn() => _uid;

/// 收下送出的事件；[status] 決定每一筆回什麼（預設 200，也可以丟錯）。
class _Wire {
  final sent = <Map<String, dynamic>>[];
  int Function(Map<String, dynamic> event) status = (_) => 200;

  Future<int> call(String fn, {required Map<String, dynamic> body}) async {
    expect(fn, 'submit-feedback');
    expect(body['kind'], 'funnel');
    final event = body['event'] as Map<String, dynamic>;
    sent.add(event);
    return status(event);
  }

  List<Object?> get names => [for (final e in sent) e['event']];
  List<Object?> get clientTs => [for (final e in sent) e['clientTs']];
  List<Object?> get props => [for (final e in sent) e['properties']];
}

/// 手機裡的佇列原文（解開 JSON）。
Future<List<Map<String, dynamic>>> _storedQueue() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(FunnelTracker.pendingQueueKey);
  if (raw == null) return const [];
  return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
}

final _t0 = DateTime.utc(2026, 10, 27, 1);

String _iso(DateTime at) => at.toUtc().toIso8601String();

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
      currentUserId: _signedIn,
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
      currentUserId: _signedIn,
    );

    await tracker.track('made_up_event');

    expect(calls, 0);
  });

  test('非 2xx 不 throw', () async {
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async => 500,
      currentUserId: _signedIn,
    );

    await tracker.track('quota_strip_tap');
  });

  test('invoker 炸掉不 throw', () async {
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async => throw StateError('boom'),
      currentUserId: _signedIn,
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
      currentUserId: _signedIn,
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
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async => 200,
      currentUserId: _signedIn,
    );

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
          currentUserId: _signedIn,
        );

    await build().trackOnce('first_analysis_completed');
    await build().trackOnce('first_analysis_completed');

    expect(calls, 1);
  });

  // onboarding 轉換第 4 步：登入前伺服器收不到（沒有帳號），先存手機，登入後補送。
  group('登入前排隊、登入後補送', () {
    String? uid;
    late DateTime now;
    late _Wire wire;
    late FunnelTracker tracker;

    setUp(() {
      uid = null;
      now = _t0;
      wire = _Wire();
      tracker = FunnelTracker(
        invoker: wire.call,
        currentUserId: () => uid,
        clock: () => now,
      );
    });

    test('沒登入：不呼叫 invoker，佇列多一筆（事件名、白名單鍵、當時的 clientTs、排隊時間）', () async {
      await tracker.track(
        'onboarding_branch_answer',
        properties: {'has_partner': true, 'partnerName': '小美'},
      );

      expect(wire.sent, isEmpty);
      final queue = await _storedQueue();
      expect(queue, hasLength(1));
      expect(queue.single.keys.toSet(), {
        'id',
        'event',
        'properties',
        'clientTs',
        'queuedAt',
        'attempts',
      });
      expect(queue.single['event'], 'onboarding_branch_answer');
      expect(queue.single['properties'], {'has_partner': true});
      expect(queue.single['clientTs'], _iso(_t0));
      expect(queue.single['queuedAt'], _iso(_t0));
      expect(queue.single['attempts'], 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FunnelTracker.pendingQueueKey),
          isNot(contains('小美')));
    });

    test('登入後補送：依序送出、clientTs 用排隊當時的、成功的移除；之後的事件直接送', () async {
      await tracker
          .track('onboarding_page_view', properties: {'page_index': 0});
      now = _t0.add(const Duration(minutes: 1));
      await tracker
          .track('onboarding_page_view', properties: {'page_index': 1});
      now = _t0.add(const Duration(minutes: 2));
      await tracker.track(
        'onboarding_questionnaire_submit',
        properties: {'goals_count': 2},
      );
      expect(wire.sent, isEmpty);

      uid = _uid;
      now = _t0.add(const Duration(hours: 1));
      await tracker.flushPending();

      expect(wire.names, [
        'onboarding_page_view',
        'onboarding_page_view',
        'onboarding_questionnaire_submit',
      ]);
      expect(wire.clientTs, [
        _iso(_t0),
        _iso(_t0.add(const Duration(minutes: 1))),
        _iso(_t0.add(const Duration(minutes: 2))),
      ]);
      expect(wire.props, [
        {'page_index': 0},
        {'page_index': 1},
        {'goals_count': 2},
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(FunnelTracker.pendingQueueKey), isFalse);

      await tracker.track('quota_strip_tap');
      expect(wire.names.last, 'quota_strip_tap');
      expect(wire.clientTs.last, _iso(now));
      expect(await _storedQueue(), isEmpty);
    });

    test('補送失敗的留著下次再送，每筆最多試 ${FunnelTracker.maxFlushAttempts} 次就丟掉', () async {
      await tracker
          .track('onboarding_page_view', properties: {'page_index': 3});
      await tracker.track('onboarding_skip', properties: {'page_index': 3});
      uid = _uid;
      var pageViewTries = 0;
      wire.status = (event) {
        if (event['event'] != 'onboarding_page_view') return 200;
        pageViewTries++;
        // 非 2xx 與丟錯（functions_client 對非 2xx 會丟）都算沒送到。
        if (pageViewTries == 2) throw StateError('offline');
        return pageViewTries == 1 ? 500 : 400;
      };

      await tracker.flushPending();
      expect(wire.names, ['onboarding_page_view', 'onboarding_skip']);
      var queue = await _storedQueue();
      expect([for (final e in queue) e['event']], ['onboarding_page_view']);
      expect(queue.single['attempts'], 1);

      await tracker.flushPending();
      queue = await _storedQueue();
      expect(queue.single['attempts'], 2);

      await tracker.flushPending();
      expect(await _storedQueue(), isEmpty);
      expect(pageViewTries, FunnelTracker.maxFlushAttempts);

      await tracker.flushPending();
      expect(pageViewTries, FunnelTracker.maxFlushAttempts);
    });

    test('佇列最多 ${FunnelTracker.maxPendingEvents} 筆，超過丟最舊的', () async {
      const total = FunnelTracker.maxPendingEvents + 5;
      for (var i = 0; i < total; i++) {
        now = _t0.add(Duration(seconds: i));
        await tracker
            .track('onboarding_page_view', properties: {'page_index': i});
      }

      final queue = await _storedQueue();
      expect(queue, hasLength(FunnelTracker.maxPendingEvents));
      expect(queue.first['properties'], {'page_index': 5});
      expect(queue.last['properties'], {'page_index': total - 1});

      uid = _uid;
      await tracker.flushPending();
      expect(wire.sent, hasLength(FunnelTracker.maxPendingEvents));
      expect(wire.props.first, {'page_index': 5});
    });

    test('排隊超過 7 天的不補送，直接丟掉', () async {
      await tracker
          .track('onboarding_page_view', properties: {'page_index': 0});
      now = _t0.add(const Duration(days: 6));
      await tracker.track('onboarding_skip', properties: {'page_index': 4});

      uid = _uid;
      now = _t0.add(FunnelTracker.pendingMaxAge + const Duration(minutes: 1));
      await tracker.flushPending();

      expect(wire.names, ['onboarding_skip']);
      expect(await _storedQueue(), isEmpty);
    });

    test('白名單外的鍵補送時也剝掉；字典已經沒有的事件不送、直接丟掉', () async {
      SharedPreferences.setMockInitialValues({
        FunnelTracker.pendingQueueKey: jsonEncode([
          {
            'id': 'old-1',
            'event': 'onboarding_branch_answer',
            'properties': {'has_partner': false, 'partnerName': '小美'},
            'clientTs': _iso(_t0),
            'queuedAt': _iso(_t0),
            'attempts': 0,
          },
          {
            'id': 'old-2',
            'event': 'retired_event',
            'properties': <String, Object?>{},
            'clientTs': _iso(_t0),
            'queuedAt': _iso(_t0),
            'attempts': 0,
          },
        ]),
      });
      uid = _uid;

      await tracker.flushPending();

      expect(wire.names, ['onboarding_branch_answer']);
      expect(wire.props, [
        {'has_partner': false},
      ]);
      expect(await _storedQueue(), isEmpty);
    });

    test('沒登入時補送什麼都不做，佇列留著', () async {
      await tracker
          .track('onboarding_page_view', properties: {'page_index': 0});

      await tracker.flushPending();

      expect(wire.sent, isEmpty);
      expect(await _storedQueue(), hasLength(1));
    });

    test('同時呼叫補送只跑一輪：每筆只送一次', () async {
      await tracker
          .track('onboarding_page_view', properties: {'page_index': 0});
      await tracker
          .track('onboarding_page_view', properties: {'page_index': 1});
      uid = _uid;
      final gate = Completer<void>();
      final slow = FunnelTracker(
        invoker: (fn, {required body}) async {
          await gate.future;
          return wire.call(fn, body: body);
        },
        currentUserId: () => uid,
        clock: () => now,
      );

      final first = slow.flushPending();
      final second = slow.flushPending();
      gate.complete();
      await Future.wait([first, second]);

      expect(wire.props, [
        {'page_index': 0},
        {'page_index': 1},
      ]);
      expect(await _storedQueue(), isEmpty);
    });

    test('補送途中登出又排進新事件：新事件留在佇列，剩下的等下次登入', () async {
      await tracker
          .track('onboarding_page_view', properties: {'page_index': 0});
      await tracker
          .track('onboarding_page_view', properties: {'page_index': 1});
      uid = _uid;
      wire.status = (event) => 200;
      late final FunnelTracker switching;
      switching = FunnelTracker(
        invoker: (fn, {required body}) async {
          final status = await wire.call(fn, body: body);
          // 第一筆送出時登出，接著又有一筆（沒登入）排進來。
          uid = null;
          await switching
              .track('onboarding_skip', properties: {'page_index': 1});
          return status;
        },
        currentUserId: () => uid,
        clock: () => now,
      );

      await switching.flushPending();

      expect(wire.props, [
        {'page_index': 0},
      ]);
      final queue = await _storedQueue();
      expect([
        for (final e in queue) e['event']
      ], [
        'onboarding_page_view',
        'onboarding_skip',
      ]);
      expect(queue.first['attempts'], 0);
    });

    test('佇列內容壞掉：不丟錯，照常排隊與補送', () async {
      SharedPreferences.setMockInitialValues({
        FunnelTracker.pendingQueueKey: 'not json',
      });

      await tracker
          .track('onboarding_page_view', properties: {'page_index': 2});
      uid = _uid;
      await tracker.flushPending();

      expect(wire.props, [
        {'page_index': 2},
      ]);
      expect(await _storedQueue(), isEmpty);
    });
  });
}

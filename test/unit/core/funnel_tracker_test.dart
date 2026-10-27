// test/unit/core/funnel_tracker_test.dart
//
// FunnelTracker（Tier 2 批 1.5）：best-effort 去識別化漏斗埋點封裝。
// - wire payload 只帶 client 白名單鍵；字典外事件根本不出手機。
// - 非 2xx／invoker 炸掉一律吞掉不 throw；track 只有伺服器收下（2xx）才回 true。
// - trackOnce 用 SharedPreferences 記號去重：分帳號、送成功才記（第 5 步）。
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

  test('非 2xx 不 throw，回 false', () async {
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async => 500,
      currentUserId: _signedIn,
    );

    expect(await tracker.track('quota_strip_tap'), isFalse);
  });

  test('invoker 炸掉不 throw，回 false（functions_client 對非 2xx 會丟錯）', () async {
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async => throw StateError('boom'),
      currentUserId: _signedIn,
    );

    expect(await tracker.track('quota_strip_tap'), isFalse);
  });

  test('track 回傳：伺服器收下才是 true；字典外、沒登入排隊都是 false', () async {
    String? uid = _uid;
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async => 204,
      currentUserId: () => uid,
    );

    expect(await tracker.track('quota_strip_tap'), isTrue);
    expect(await tracker.track('made_up_event'), isFalse);
    uid = null;
    expect(await tracker.track('quota_strip_tap'), isFalse);
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
      'quota_block_shown': ['feature', 'scope', 'block_source'],
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
    var calls = 0;
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async {
        calls++;
        return 200;
      },
      currentUserId: _signedIn,
    );

    await tracker.trackOnce('not_in_dict');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('funnel_once')), isEmpty);
    expect(calls, 0);
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

  // onboarding 轉換第 5 步：「只記一次」的事件送成功才記號，記號分帳號。
  group('只記一次：送成功才算', () {
    String? uid;
    late _Wire wire;
    late FunnelTracker tracker;

    setUp(() {
      uid = _uid;
      wire = _Wire();
      tracker = FunnelTracker(invoker: wire.call, currentUserId: () => uid);
    });

    Future<bool?> flag(String key) async =>
        (await SharedPreferences.getInstance()).getBool(key);

    test('送失敗不寫記號，下次觸發會再送；送成功才寫，之後不再送', () async {
      wire.status = (_) => 503;
      await tracker.trackOnce('first_analysis_completed');
      expect(wire.names, ['first_analysis_completed']);
      expect(await flag('funnel_once_v2_${_uid}_first_analysis_completed'),
          isNull);

      wire.status = (_) => 200;
      await tracker.trackOnce('first_analysis_completed');
      expect(wire.names, hasLength(2));
      expect(await flag('funnel_once_v2_${_uid}_first_analysis_completed'),
          isTrue);

      await tracker.trackOnce('first_analysis_completed');
      await FunnelTracker(invoker: wire.call, currentUserId: () => uid)
          .trackOnce('first_analysis_completed');
      expect(wire.names, hasLength(2));
    });

    test('記號分帳號：同一支手機換帳號，第二個帳號的第一次照樣送', () async {
      await tracker.trackOnce('first_practice_completed');
      uid = 'user-b';
      await tracker.trackOnce('first_practice_completed');
      await tracker.trackOnce('first_practice_completed');

      expect(wire.names, [
        'first_practice_completed',
        'first_practice_completed',
      ]);
      expect(await flag('funnel_once_v2_${_uid}_first_practice_completed'),
          isTrue);
      expect(
          await flag('funnel_once_v2_user-b_first_practice_completed'), isTrue);
    });

    test('同一個鍵同時觸發只送一次（起步清單每次重建都會觸發）', () async {
      final gate = Completer<void>();
      final slow = FunnelTracker(
        invoker: (fn, {required body}) async {
          await gate.future;
          return wire.call(fn, body: body);
        },
        currentUserId: () => uid,
      );

      final calls = [
        for (var i = 0; i < 4; i++)
          slow.trackOnce(
            'checklist_item_done',
            properties: {'item': 'profile'},
            onceKey: 'checklist_item_done_profile',
          ),
      ];
      gate.complete();
      await Future.wait(calls);

      expect(wire.props, [
        {'item': 'profile'},
      ]);
      expect(await flag('funnel_once_v2_${_uid}_checklist_item_done_profile'),
          isTrue);
    });

    test('onceKey 讓同一個事件逐項各記一次', () async {
      for (final item in ['profile', 'first_action', 'profile']) {
        await tracker.trackOnce(
          'checklist_item_done',
          properties: {'item': item},
          onceKey: 'checklist_item_done_$item',
        );
      }

      expect(wire.props, [
        {'item': 'profile'},
        {'item': 'first_action'},
      ]);
    });

    test(
        '一直失敗：同一次執行同一個鍵最多試 ${FunnelTracker.maxOnceAttemptsPerRun} 次，'
        '下次開 App（新的 tracker）才再試', () async {
      wire.status = (_) => 400;
      for (var i = 0; i < FunnelTracker.maxOnceAttemptsPerRun + 2; i++) {
        await tracker.trackOnce('first_analysis_completed');
      }
      expect(wire.sent, hasLength(FunnelTracker.maxOnceAttemptsPerRun));

      wire.status = (_) => 200;
      await FunnelTracker(invoker: wire.call, currentUserId: () => uid)
          .trackOnce('first_analysis_completed');
      expect(wire.sent, hasLength(FunnelTracker.maxOnceAttemptsPerRun + 1));
      expect(await flag('funnel_once_v2_${_uid}_first_analysis_completed'),
          isTrue);
    });

    test('沒登入：交給佇列、不寫記號；同一次執行同一個鍵只排一次', () async {
      uid = null;
      await tracker.trackOnce('first_practice_completed');
      await tracker.trackOnce('first_practice_completed');

      expect(wire.sent, isEmpty);
      final queue = await _storedQueue();
      expect([for (final e in queue) e['event']], ['first_practice_completed']);
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getKeys().where((k) => k.startsWith('funnel_once')), isEmpty);

      uid = _uid;
      await tracker.flushPending();
      expect(wire.names, ['first_practice_completed']);
    });

    test('舊的記號鍵（不分帳號、送之前就寫）不再讀：升級前送過的，這個帳號會再送一次', () async {
      SharedPreferences.setMockInitialValues({
        'funnel_once_first_analysis_completed': true,
        'funnel_once_checklist_item_done_profile': true,
      });

      await tracker.trackOnce('first_analysis_completed');
      await tracker.trackOnce(
        'checklist_item_done',
        properties: {'item': 'profile'},
        onceKey: 'checklist_item_done_profile',
      );

      expect(wire.names, [
        'first_analysis_completed',
        'checklist_item_done',
      ]);
    });
  });

  // onboarding 轉換第 6 步：告訴使用者「額度不夠」的那一刻記一筆。
  group('額度不足事件 quota_block_shown', () {
    String? uid;
    late _Wire wire;
    late FunnelTracker tracker;

    setUp(() {
      uid = _uid;
      wire = _Wire();
      tracker = FunnelTracker(invoker: wire.call, currentUserId: () => uid);
    });

    List<Object?> quotaProps() => [
          for (final e in wire.sent)
            if (e['event'] == 'quota_block_shown') e['properties'],
        ];

    test('enum 送出的值跟 server 白名單逐字一致（funnel_utils.ts 的三個 Set）', () {
      expect([
        for (final f in QuotaBlockFeature.values) f.wire
      ], [
        'analyze',
        'opener',
        'new_topic',
        'coach',
        'practice',
        'keyboard',
      ]);
      expect([
        for (final s in QuotaBlockScope.values) s.wire
      ], [
        'daily',
        'monthly',
        'unknown',
      ]);
      expect([
        for (final s in QuotaBlockSource.values) s.wire
      ], [
        'precheck',
        'server',
      ]);
    });

    test('只帶 feature、scope、block_source 三個固定值（不叫 source，避開關於我那個鍵）', () async {
      await tracker.trackQuotaBlockShown(
        feature: QuotaBlockFeature.newTopic,
        scope: QuotaBlockScope.monthly,
        source: QuotaBlockSource.precheck,
      );

      expect(wire.names, ['quota_block_shown']);
      expect(quotaProps(), [
        {
          'feature': 'new_topic',
          'scope': 'monthly',
          'block_source': 'precheck'
        },
      ]);
    });

    test('同一次執行同一個 feature＋scope 只記一次；block_source 不同不算新的一次；換 scope 或功能各記一次',
        () async {
      Future<void> block(
        QuotaBlockFeature feature,
        QuotaBlockScope scope,
        QuotaBlockSource source,
      ) =>
          tracker.trackQuotaBlockShown(
            feature: feature,
            scope: scope,
            source: source,
          );

      await block(QuotaBlockFeature.analyze, QuotaBlockScope.daily,
          QuotaBlockSource.precheck);
      await block(QuotaBlockFeature.analyze, QuotaBlockScope.daily,
          QuotaBlockSource.server);
      await block(QuotaBlockFeature.analyze, QuotaBlockScope.daily,
          QuotaBlockSource.precheck);
      await block(QuotaBlockFeature.analyze, QuotaBlockScope.monthly,
          QuotaBlockSource.server);
      await block(QuotaBlockFeature.coach, QuotaBlockScope.daily,
          QuotaBlockSource.server);

      expect(quotaProps(), [
        {'feature': 'analyze', 'scope': 'daily', 'block_source': 'precheck'},
        {'feature': 'analyze', 'scope': 'monthly', 'block_source': 'server'},
        {'feature': 'coach', 'scope': 'daily', 'block_source': 'server'},
      ]);

      // 下次開 App（新的 tracker）會再記。
      await FunnelTracker(invoker: wire.call, currentUserId: () => uid)
          .trackQuotaBlockShown(
        feature: QuotaBlockFeature.analyze,
        scope: QuotaBlockScope.daily,
        source: QuotaBlockSource.precheck,
      );
      expect(quotaProps(), hasLength(4));
    });

    test('同時觸發只送一次（例如每次重建都碰到被擋的按鈕）', () async {
      final gate = Completer<void>();
      final slow = FunnelTracker(
        invoker: (fn, {required body}) async {
          await gate.future;
          return wire.call(fn, body: body);
        },
        currentUserId: () => uid,
      );

      final calls = [
        for (var i = 0; i < 3; i++)
          slow.trackQuotaBlockShown(
            feature: QuotaBlockFeature.practice,
            scope: QuotaBlockScope.unknown,
            source: QuotaBlockSource.precheck,
          ),
      ];
      gate.complete();
      await Future.wait(calls);

      expect(quotaProps(), hasLength(1));
    });

    test(
        '送失敗不算記過，下次擋到再送；同一次執行最多試 '
        '${FunnelTracker.maxOnceAttemptsPerRun} 次', () async {
      wire.status = (_) => 400; // 舊 server 不認得這個事件
      for (var i = 0; i < FunnelTracker.maxOnceAttemptsPerRun + 2; i++) {
        await tracker.trackQuotaBlockShown(
          feature: QuotaBlockFeature.keyboard,
          scope: QuotaBlockScope.unknown,
          source: QuotaBlockSource.server,
        );
      }
      expect(wire.sent, hasLength(FunnelTracker.maxOnceAttemptsPerRun));

      wire.status = (_) => 200;
      final retry = FunnelTracker(invoker: wire.call, currentUserId: () => uid);
      await retry.trackQuotaBlockShown(
        feature: QuotaBlockFeature.keyboard,
        scope: QuotaBlockScope.unknown,
        source: QuotaBlockSource.server,
      );
      await retry.trackQuotaBlockShown(
        feature: QuotaBlockFeature.keyboard,
        scope: QuotaBlockScope.unknown,
        source: QuotaBlockSource.server,
      );
      expect(wire.sent, hasLength(FunnelTracker.maxOnceAttemptsPerRun + 1));
    });

    test('沒登入：排進佇列就算記過，不重複排', () async {
      uid = null;
      for (var i = 0; i < 2; i++) {
        await tracker.trackQuotaBlockShown(
          feature: QuotaBlockFeature.opener,
          scope: QuotaBlockScope.daily,
          source: QuotaBlockSource.server,
        );
      }

      expect(wire.sent, isEmpty);
      final queue = await _storedQueue();
      expect([
        for (final e in queue) e['properties']
      ], [
        {'feature': 'opener', 'scope': 'daily', 'block_source': 'server'},
      ]);
    });
  });
}

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Testable seam over the Edge Function invocation（同 CoachingOutcomeUploader）。
typedef FunnelUploadInvoker = Future<int> Function(
  String functionName, {
  required Map<String, dynamic> body,
});

/// 目前登入的帳號 id，沒登入回 null（測試注入用）。
typedef FunnelCurrentUserId = String? Function();

/// `quota_block_shown.feature`：哪個功能撞到額度（onboarding 轉換第 6 步）。
enum QuotaBlockFeature {
  analyze('analyze'),
  opener('opener'),
  newTopic('new_topic'),
  coach('coach'),
  practice('practice'),
  keyboard('keyboard');

  const QuotaBlockFeature(this.wire);

  /// 送到伺服器的值（server 白名單 QUOTA_BLOCK_FEATURES）。
  final String wire;
}

/// `quota_block_shown.scope`：撞到的是每日還是每月額度；App 分不出來就是 unknown。
enum QuotaBlockScope {
  daily('daily'),
  monthly('monthly'),
  unknown('unknown');

  const QuotaBlockScope(this.wire);

  /// 送到伺服器的值（server 白名單 QUOTA_BLOCK_SCOPES）。
  final String wire;
}

/// `quota_block_shown.block_source`：App 自己先擋（precheck），還是伺服器回 429／402
/// 或鍵盤轉來伺服器確認過的訊號（server）。鍵名不叫 source：server 的值域表以鍵名全域
/// 共用，source 已經是 about_me_opened 的鍵。
enum QuotaBlockSource {
  precheck('precheck'),
  server('server');

  const QuotaBlockSource(this.wire);

  /// 送到伺服器的值（server 白名單 QUOTA_BLOCK_SOURCES）。
  final String wire;
}

/// Best-effort 去識別化漏斗埋點（Tier 2 批 1.5）。
///
/// 鐵則（隱私＋韌性，照 CoachingOutcomeUploader）：
/// - 絕不 block UI、吞下一切錯誤（網路／非 2xx／exception）。
/// - 沒登入時伺服器收不到（沒有帳號可以掛），先排進手機裡的佇列，登入後由
///   [flushPending] 補送（onboarding 轉換第 4 步）。會再試的只有這個補送（每筆
///   最多 [maxFlushAttempts] 次）與 [trackOnce] 沒送成功的下次觸發（同一次執行
///   最多 [maxOnceAttemptsPerRun] 次）。
/// - 白名單真相源：docs/integrations/funnel-events-v1.md。改字典必同批
///   同步改本檔與 Edge funnel_utils.ts 兩層。
/// - payload 只有事件名＋白名單鍵；對話內容、對象名、自由文字絕不上傳，
///   佇列也只存這些。
class FunnelTracker {
  FunnelTracker({
    FunnelUploadInvoker? invoker,
    FunnelCurrentUserId? currentUserId,
    DateTime Function()? clock,
  })  : _invoke = invoker ?? _defaultInvoker,
        _currentUserId = currentUserId ?? _defaultCurrentUserId,
        _clock = clock ?? DateTime.now;

  static const _functionName = 'submit-feedback';

  /// 登入前排隊的事件（SharedPreferences 裡的 JSON 陣列）。
  @visibleForTesting
  static const pendingQueueKey = 'funnel_pending_queue_v1';

  /// 佇列最多幾筆，滿了丟最舊的。
  @visibleForTesting
  static const maxPendingEvents = 50;

  /// 排隊超過這麼久就不補送：太久以前的事件可能是別人用這支手機時留下的，
  /// 補送會掛到後來登入的帳號。
  @visibleForTesting
  static const pendingMaxAge = Duration(days: 7);

  /// 每筆最多補送幾次，都沒成功就丟掉。
  @visibleForTesting
  static const maxFlushAttempts = 3;

  /// 只記一次的事件：同一次執行同一個鍵最多試幾次（一直失敗時不要每次觸發都重送）。
  @visibleForTesting
  static const maxOnceAttemptsPerRun = 3;

  /// 只記一次的記號鍵：`funnel_once_v2_<uid>_<onceKey ?? event>`，分帳號。
  /// 舊鍵 `funnel_once_<event>` 不分帳號、送之前就寫，不再讀。
  static const _onceFlagPrefix = 'funnel_once_v2_';

  /// client 端白名單鏡像（event → 允許的 properties 鍵）。
  static const Map<String, List<String>> eventProps = {
    'onboarding_page_view': ['page_index'],
    'onboarding_skip': ['page_index'],
    'onboarding_branch_answer': ['has_partner'],
    'onboarding_questionnaire_submit': ['goals_count'],
    'quota_strip_tap': [],
    'opener_entry_tap': [],
    'coach_entry_tap': ['has_partner'],
    'first_analysis_completed': [],
    'first_practice_completed': [],
    'keyboard_setup_shown': [],
    'keyboard_setup_completed': [],
    'checklist_item_done': ['item'],
    'about_me_opened': ['source'],
    'about_me_saved': [
      'has_style',
      'goals_count',
      'seeds_count',
      'has_notes',
      'has_custom_topics',
    ],
    'about_me_cleared': [],
    'new_topic_copied': ['is_recommended'],
    'paywall_opened': ['entry'],
    // purchaser：開始購買時的帳號，伺服器比對登入帳號用，不落庫。
    'paywall_purchase_completed': ['tier', 'entry', 'purchaser'],
    'locked_cards_upgrade_tap': ['locked_count'],
    'quota_block_shown': ['feature', 'scope', 'block_source'],
  };

  final FunnelUploadInvoker _invoke;
  final FunnelCurrentUserId _currentUserId;
  final DateTime Function() _clock;
  final _random = Random();
  Future<void>? _flushing;

  // 只記一次的事件在這次執行中的狀態（記憶體，不落地）。
  final _onceInFlight = <String>{};
  final _onceAttempts = <String, int>{};
  final _onceQueuedSignedOut = <String>{};

  // 額度不足事件在這次執行中的狀態（記憶體，鍵是 feature|scope）。
  final _quotaBlockDone = <String>{};
  final _quotaBlockInFlight = <String>{};
  final _quotaBlockAttempts = <String, int>{};

  /// 送一發事件；伺服器收下（2xx）才回 true，其他（沒送到、被拒、丟錯）一律
  /// false，不丟錯。字典外事件直接丟棄（連手機都不出）。
  /// 沒登入時不送，排進佇列，登入後由 [flushPending] 補送（這次回 false）。
  Future<bool> track(
    String event, {
    Map<String, Object?> properties = const {},
  }) async {
    try {
      final filtered = _whitelisted(event, properties);
      if (filtered == null) {
        debugPrint('[FunnelTracker] unknown event dropped: $event');
        return false;
      }
      final clientTs = _clock().toUtc().toIso8601String();
      if (_currentUserId() == null) {
        await _enqueue(event, filtered, clientTs);
        return false;
      }
      return await _send(event, filtered, clientTs);
    } catch (e) {
      // Best-effort：埋點永遠不影響功能。
      debugPrint('[FunnelTracker] track failed (ignored): $e');
      return false;
    }
  }

  /// 每個帳號只記一次的事件（first_* 類、起步清單逐項）。送成功才記號
  /// （onboarding 轉換第 5 步）：斷網或伺服器沒收下就不記，下次觸發再送；
  /// 記號分帳號，同一支手機換帳號各記各的。
  /// - 沒登入：交給 [track] 排隊、不寫記號；同一次執行同一個鍵只排一次。
  /// - 同一個鍵送出中再觸發直接略過（起步清單每次重建都會觸發）。
  /// - 同一次執行同一個鍵最多試 [maxOnceAttemptsPerRun] 次。
  /// [onceKey] 讓同事件不同維度各自去重（如 checklist 逐項）。
  Future<void> trackOnce(
    String event, {
    Map<String, Object?> properties = const {},
    String? onceKey,
  }) async {
    // 先驗白名單再碰記號（GLM 審查 F6：否則 typo 事件會把記號燒掉，真事件
    // 永遠送不出且無聲無息）。
    if (!eventProps.containsKey(event)) {
      debugPrint('[FunnelTracker] unknown once event dropped: $event');
      return;
    }
    final scope = onceKey ?? event;
    final uid = _currentUserId();
    if (uid == null) {
      if (_onceQueuedSignedOut.add(scope)) {
        await track(event, properties: properties);
      }
      return;
    }
    final flagKey = '$_onceFlagPrefix${uid}_$scope';
    if (_onceInFlight.contains(flagKey)) return;
    if ((_onceAttempts[flagKey] ?? 0) >= maxOnceAttemptsPerRun) return;
    _onceInFlight.add(flagKey);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(flagKey) ?? false) return;
      _onceAttempts[flagKey] = (_onceAttempts[flagKey] ?? 0) + 1;
      if (await track(event, properties: properties)) {
        await prefs.setBool(flagKey, true);
      }
    } catch (e) {
      debugPrint('[FunnelTracker] once-flag failed (ignored): $e');
    } finally {
      _onceInFlight.remove(flagKey);
    }
  }

  /// 額度不足事件（onboarding 轉換第 6 步）：在「告訴使用者額度不夠」的那一刻記一筆。
  /// 同一次執行、同一個 feature＋scope 只記一次：送成功或排進佇列才算數，送失敗的
  /// 下次再擋到時再送（同一次執行最多 [maxOnceAttemptsPerRun] 次）。只記錄，不影響
  /// 任何額度判斷、按鈕狀態或付費頁。
  Future<void> trackQuotaBlockShown({
    required QuotaBlockFeature feature,
    required QuotaBlockScope scope,
    required QuotaBlockSource source,
  }) async {
    final key = '${feature.wire}|${scope.wire}';
    if (_quotaBlockDone.contains(key) || _quotaBlockInFlight.contains(key)) {
      return;
    }
    if ((_quotaBlockAttempts[key] ?? 0) >= maxOnceAttemptsPerRun) return;
    _quotaBlockInFlight.add(key);
    _quotaBlockAttempts[key] = (_quotaBlockAttempts[key] ?? 0) + 1;
    try {
      final queued = _currentUserId() == null;
      final sent = await track(
        'quota_block_shown',
        properties: {
          'feature': feature.wire,
          'scope': scope.wire,
          'block_source': source.wire,
        },
      );
      if (sent || queued) _quotaBlockDone.add(key);
    } catch (e) {
      debugPrint('[FunnelTracker] quota block failed (ignored): $e');
    } finally {
      _quotaBlockInFlight.remove(key);
    }
  }

  /// 補送登入前排隊的事件（登入後進首頁時由 OnboardingHandoffApplier 呼叫）。
  ///
  /// 超過 [pendingMaxAge] 的丟掉；其餘逐筆照原本的 body 與當時的 clientTs 送，
  /// 成功的移除、失敗的留著下次再試，每筆最多 [maxFlushAttempts] 次。沒登入或
  /// 沒有佇列就什麼都不做；同時呼叫只跑一輪。
  Future<void> flushPending() =>
      _flushing ??= _flushPendingOnce().whenComplete(() => _flushing = null);

  Future<void> _flushPendingOnce() async {
    try {
      if (_currentUserId() == null) return;
      final prefs = await SharedPreferences.getInstance();
      final now = _clock().toUtc();
      final stored = _readQueue(prefs);
      final fresh = [
        for (final entry in stored)
          if (now.difference(entry.queuedAt).abs() <= pendingMaxAge) entry,
      ];
      if (fresh.length != stored.length) await _writeQueue(prefs, fresh);
      for (final entry in fresh) {
        // 補送途中登出：剩下的留著，等下次登入。
        if (_currentUserId() == null) return;
        // 字典照現在的版本再過一次：App 更新後可能拿掉事件或鍵。
        final properties = _whitelisted(entry.event, entry.properties);
        final sent = properties != null &&
            await _send(entry.event, properties, entry.clientTs);
        // 送的期間可能有新事件排進來：重讀一次，只動這一筆（讀改寫之間不 await）。
        final queue = _readQueue(prefs);
        final index = queue.indexWhere((e) => e.id == entry.id);
        if (index < 0) continue;
        final attempts = queue[index].attempts + 1;
        if (sent || properties == null || attempts >= maxFlushAttempts) {
          queue.removeAt(index);
        } else {
          queue[index] = queue[index].withAttempts(attempts);
        }
        await _writeQueue(prefs, queue);
      }
    } catch (e) {
      debugPrint('[FunnelTracker] flush failed (ignored): $e');
    }
  }

  /// 只留這個事件白名單內的鍵；字典外事件回 null。
  static Map<String, Object?>? _whitelisted(
    String event,
    Map<String, Object?> properties,
  ) {
    final allowed = eventProps[event];
    if (allowed == null) return null;
    return <String, Object?>{
      for (final key in allowed)
        if (properties.containsKey(key)) key: properties[key],
    };
  }

  /// 送一筆；2xx 回 true，其他一律 false（不丟錯）。
  Future<bool> _send(
    String event,
    Map<String, Object?> properties,
    String clientTs,
  ) async {
    try {
      final status = await _invoke(
        _functionName,
        body: <String, dynamic>{
          'kind': 'funnel',
          'event': <String, dynamic>{
            'event': event,
            'properties': properties,
            'clientTs': clientTs,
          },
        },
      );
      if (status >= 200 && status < 300) return true;
      debugPrint('[FunnelTracker] non-2xx status: $status ($event)');
    } catch (e) {
      // functions_client 對非 2xx 直接丟 FunctionException，一樣算沒送到。
      debugPrint('[FunnelTracker] send failed (ignored): $e');
    }
    return false;
  }

  Future<void> _enqueue(
    String event,
    Map<String, Object?> properties,
    String clientTs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final now = _clock().toUtc();
    // 讀改寫之間不 await：同一個 isolate 裡不會跟另一筆排隊或補送交錯。
    final queue = _readQueue(prefs)
      ..add(_PendingFunnelEvent(
        id: '${now.microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}',
        event: event,
        properties: properties,
        clientTs: clientTs,
        queuedAt: now,
        attempts: 0,
      ));
    if (queue.length > maxPendingEvents) {
      queue.removeRange(0, queue.length - maxPendingEvents);
    }
    await _writeQueue(prefs, queue);
  }

  /// 讀佇列；內容壞掉或不是預期的格式就當沒有（壞掉的那筆略過）。
  static List<_PendingFunnelEvent> _readQueue(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(pendingQueueKey);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(_PendingFunnelEvent.tryParse)
          .whereType<_PendingFunnelEvent>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeQueue(
    SharedPreferences prefs,
    List<_PendingFunnelEvent> queue,
  ) async {
    if (queue.isEmpty) {
      await prefs.remove(pendingQueueKey);
      return;
    }
    await prefs.setString(
      pendingQueueKey,
      jsonEncode([for (final entry in queue) entry.toJson()]),
    );
  }
}

/// 登入前排隊的一筆：事件名、已過白名單的屬性、當時的 clientTs、排進來的時間、
/// 已經補送失敗幾次。
@immutable
class _PendingFunnelEvent {
  const _PendingFunnelEvent({
    required this.id,
    required this.event,
    required this.properties,
    required this.clientTs,
    required this.queuedAt,
    required this.attempts,
  });

  final String id;
  final String event;
  final Map<String, Object?> properties;
  final String clientTs;
  final DateTime queuedAt;
  final int attempts;

  _PendingFunnelEvent withAttempts(int value) => _PendingFunnelEvent(
        id: id,
        event: event,
        properties: properties,
        clientTs: clientTs,
        queuedAt: queuedAt,
        attempts: value,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'event': event,
        'properties': properties,
        'clientTs': clientTs,
        'queuedAt': queuedAt.toIso8601String(),
        'attempts': attempts,
      };

  static _PendingFunnelEvent? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final event = json['event'];
    final properties = json['properties'];
    final clientTs = json['clientTs'];
    final queuedAt = json['queuedAt'];
    final attempts = json['attempts'];
    if (id is! String ||
        event is! String ||
        properties is! Map ||
        clientTs is! String ||
        queuedAt is! String ||
        attempts is! int) {
      return null;
    }
    final parsedQueuedAt = DateTime.tryParse(queuedAt);
    if (parsedQueuedAt == null) return null;
    return _PendingFunnelEvent(
      id: id,
      event: event,
      properties: Map<String, Object?>.from(properties),
      clientTs: clientTs,
      queuedAt: parsedQueuedAt,
      attempts: attempts,
    );
  }
}

String? _defaultCurrentUserId() => SupabaseService.currentUser?.id;

Future<int> _defaultInvoker(
  String fn, {
  required Map<String, dynamic> body,
}) async {
  final res = await Supabase.instance.client.functions.invoke(fn, body: body);
  return res.status;
}

final funnelTrackerProvider = Provider<FunnelTracker>((ref) => FunnelTracker());

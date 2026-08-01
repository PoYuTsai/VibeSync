import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Testable seam over the Edge Function invocation（同 CoachingOutcomeUploader）。
typedef FunnelUploadInvoker = Future<int> Function(
  String functionName, {
  required Map<String, dynamic> body,
});

/// Best-effort, fire-and-forget 去識別化漏斗埋點（Tier 2 批 1.5）。
///
/// 鐵則（隱私＋韌性，照 CoachingOutcomeUploader）：
/// - 絕不 block UI、絕不重試、吞下一切錯誤（網路／非 2xx／exception）。
/// - 白名單真相源：docs/integrations/funnel-events-v1.md。改字典必同批
///   同步改本檔與 Edge funnel_utils.ts 兩層。
/// - payload 只有事件名＋白名單鍵；對話內容、對象名、自由文字絕不上傳。
class FunnelTracker {
  FunnelTracker({FunnelUploadInvoker? invoker})
      : _invoke = invoker ?? _defaultInvoker;

  static const _functionName = 'submit-feedback';

  /// client 端白名單鏡像（event → 允許的 properties 鍵）。
  static const Map<String, List<String>> eventProps = {
    'onboarding_page_view': ['page_index'],
    'onboarding_skip': ['page_index'],
    'onboarding_branch_answer': ['has_partner'],
    'onboarding_questionnaire_submit': ['style_set', 'goals_count'],
    'quota_strip_tap': [],
    'opener_entry_tap': [],
    'coach_entry_tap': ['has_partner'],
    'first_analysis_completed': [],
    'first_practice_completed': [],
    'keyboard_setup_shown': [],
    'keyboard_setup_completed': [],
    'checklist_item_done': ['item'],
    'guest_mode_enter': [],
    'guest_register_view': ['source'],
    'guest_register_success': ['method'],
  };

  final FunnelUploadInvoker _invoke;

  /// 送一發事件。字典外事件直接丟棄（連手機都不出）。
  Future<void> track(
    String event, {
    Map<String, Object?> properties = const {},
  }) async {
    try {
      final allowed = eventProps[event];
      if (allowed == null) {
        debugPrint('[FunnelTracker] unknown event dropped: $event');
        return;
      }
      final filtered = <String, Object?>{
        for (final key in allowed)
          if (properties.containsKey(key)) key: properties[key],
      };
      final body = <String, dynamic>{
        'kind': 'funnel',
        'event': <String, dynamic>{
          'event': event,
          'properties': filtered,
          'clientTs': DateTime.now().toUtc().toIso8601String(),
        },
      };
      final status = await _invoke(_functionName, body: body);
      if (status < 200 || status >= 300) {
        debugPrint('[FunnelTracker] non-2xx status: $status ($event)');
      }
    } catch (e) {
      // Best-effort：埋點永遠不影響功能。
      debugPrint('[FunnelTracker] track failed (ignored): $e');
    }
  }

  /// 本機 once-flag 去重版（first_* 類事件用）。attempt-once 語意：
  /// 旗標在出手前就落，失敗不補送，避免重試風暴。
  /// [onceKey] 讓同事件不同維度各自去重（如 checklist 逐項）。
  Future<void> trackOnce(
    String event, {
    Map<String, Object?> properties = const {},
    String? onceKey,
  }) async {
    // 先驗白名單再落 once-flag（GLM 審查 F6：否則 typo 事件會把旗標
    // 燒掉，真事件永遠送不出且無聲無息）。
    if (!eventProps.containsKey(event)) {
      debugPrint('[FunnelTracker] unknown once event dropped: $event');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'funnel_once_${onceKey ?? event}';
      if (prefs.getBool(key) ?? false) return;
      await prefs.setBool(key, true);
    } catch (e) {
      debugPrint('[FunnelTracker] once-flag failed (ignored): $e');
      return;
    }
    await track(event, properties: properties);
  }
}

Future<int> _defaultInvoker(
  String fn, {
  required Map<String, dynamic> body,
}) async {
  final res = await Supabase.instance.client.functions.invoke(fn, body: body);
  return res.status;
}

final funnelTrackerProvider = Provider<FunnelTracker>((ref) => FunnelTracker());

// lib/core/services/app_haptics.dart
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全 App 觸覺回饋的單一入口：強度階梯＋設定頁開關都收在這裡。
///
/// 強度階梯（常見的最輕、稀有的才重）：
/// tap < light < medium < success/failure（雙擊節奏）。
/// Web 上 HapticFeedback 本身是 no-op，不需另外判斷平台。
abstract final class AppHaptics {
  static const String _prefsKey = 'haptics_enabled';

  /// 目前開關狀態。預設開；[init] 載入前先照預設值震。
  static bool enabled = true;

  /// App 啟動時載入使用者偏好。
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_prefsKey) ?? true;
  }

  /// 設定頁開關寫入口：先改記憶體讓後續震動立即生效，再持久化。
  static Future<void> setEnabled(bool value) async {
    enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  /// 輕點：清單項、選項、切卡片。
  static void tap() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// 按鈕實心感：主要按鈕按下瞬間、抽牌。
  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// 單發強調：翻開、揭曉。
  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// 答對：兩下往上跳（輕→中）。間隔是體感參數，實機調。
  static Future<void> success() async {
    if (!enabled) return;
    HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// 答錯／失敗：兩下短促（中×2）。明確但不兇，語氣交給文案與顏色。
  static Future<void> failure() async {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (enabled) HapticFeedback.mediumImpact();
  }
}

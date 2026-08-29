// lib/core/services/app_haptics.dart
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全 App 觸覺回饋的單一入口：強度階梯＋設定頁開關都收在這裡。
///
/// 強度階梯（常見的最輕、稀有的才重）：
/// tap < light < medium < success/failure（雙擊節奏）。
/// Web 上 HapticFeedback 本身是 no-op，不需另外判斷平台。
///
/// 測試注意：success/failure/celebrate 用 Future.delayed 排後續下，widget
/// test 走到這些路徑要在結尾 `pump(const Duration(milliseconds: 250))`
/// 收掉間隔，否則收尾時會炸 pending timer。
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

  // 2026-08-18 dogfood：selectionClick 起跳的階梯全體感太輕、爽感不足，
  // 整條往上抬一級（tap=light、按鈕=medium、揭曉=heavy）。太重就整條降回來。

  /// 輕點：清單項、選項、切卡片。
  static void tap() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// 按鈕實心感：主要按鈕按下瞬間、抽牌。
  static void light() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// 單發強調：翻開、揭曉。
  static void medium() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  /// 強烈單發：一次性的「踏出去」轉場（開始和她聊）。原生沒有比 heavyImpact
  /// 更重的單發，用極短間隔的重×2 疊成一記強震——比 medium() 明顯重，又不像
  /// failure() 那樣讀起來是負面回饋。太重就把第二下拿掉。
  static Future<void> strong() async {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 55));
    if (enabled) HapticFeedback.heavyImpact();
  }

  /// 答對：兩下往上跳（中→重）。間隔是體感參數，實機調。
  static Future<void> success() async {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    if (enabled) HapticFeedback.heavyImpact();
  }

  /// 答錯／失敗：兩下短促（重×2）。明確但不兇，語氣交給文案與顏色。
  static Future<void> failure() async {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (enabled) HapticFeedback.heavyImpact();
  }

  /// 慶祝：漸強三下（輕→中→重）。測驗過關、訂閱成功、稀有揭曉。
  /// 原生 API 做不了真正的連續漸強曲線；要更綿密得上第三方套件（第 3 步）。
  static Future<void> celebrate() async {
    if (!enabled) return;
    HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!enabled) return;
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    if (enabled) HapticFeedback.heavyImpact();
  }

  static DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  /// 累積感：進度條推進、分數跳動時的細碎「噠噠」。自帶節流——
  /// 跟著動畫每幀呼叫也只會以固定間隔出聲（iOS 太密會被吞、Android 會變嗡嗡）。
  static void tick() {
    if (!enabled) return;
    final now = DateTime.now();
    if (now.difference(_lastTick).inMilliseconds < 70) return;
    _lastTick = now;
    HapticFeedback.selectionClick();
  }

  /// 給原生按鈕 onPressed 包一層按壓觸覺；null（disabled）維持 null。
  static VoidCallback? onPress(VoidCallback? action) {
    if (action == null) return null;
    return () {
      light();
      action();
    };
  }
}

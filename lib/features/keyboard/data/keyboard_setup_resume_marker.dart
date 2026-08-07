// lib/features/keyboard/data/keyboard_setup_resume_marker.dart
//
// 「去 iPhone 設定切完整取用」的中斷旗標。設定頁按 CTA 前落下；iOS 切
// 權限開關必定強殺 App，冷啟動後 app 層據此把設定頁自動推回來——這條
// 不看 onboarding gate 條件（已完成過鍵盤引導的人從起步清單／設定頁重走
// 同樣會被殺，2026-08-07 真機重測命中），設定頁 initState 再消費旗標跳回
// 「長按地球」那一頁。
import 'package:shared_preferences/shared_preferences.dart';

class KeyboardSetupResumeMarker {
  static const key = 'keyboard_setup_awaiting_full_access_return';

  static Future<bool> isSet() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;
}

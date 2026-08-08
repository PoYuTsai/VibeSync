// lib/core/theme/app_motion.dart
import 'package:flutter/animation.dart';

/// 全 App 動效 token：新動畫一律從這裡拿 duration/curve，
/// 不再就地寫 magic number。
///
/// 分級依據（Emil Kowalski 動畫預算表）：
/// - press：高頻按壓回饋，必須近乎無感
/// - enter：內容進場（訊息、loading→內容）
/// - state：狀態切換／展開收合
/// - celebrate：稀有完成時刻，唯一允許 easeOutBack 彈感的檔位
abstract final class AppMotion {
  static const Duration press = Duration(milliseconds: 120);
  static const Duration enter = Duration(milliseconds: 200);
  static const Duration state = Duration(milliseconds: 240);
  static const Duration celebrate = Duration(milliseconds: 320);

  /// 強力 ease-out：前段比 easeOutCubic 快、尾段收更長，
  /// 同樣時長下動作更「有感」。
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);
  static const Curve celebrateCurve = Curves.easeOutBack;

  /// 按壓縮放比例（與 GradientButton 既有 0.97 對齊）。
  static const double pressedScale = 0.97;
}

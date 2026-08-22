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
  /// 舊按壓時長；新按壓一律用不對稱的 [pressDown]/[pressUp]。
  static const Duration press = Duration(milliseconds: 120);

  /// 按下（系統回應要快）／放開（可以慢一點收）——不對稱時序。
  static const Duration pressDown = Duration(milliseconds: 90);
  static const Duration pressUp = Duration(milliseconds: 150);

  static const Duration enter = Duration(milliseconds: 200);
  static const Duration state = Duration(milliseconds: 240);
  static const Duration celebrate = Duration(milliseconds: 320);

  /// tab fade-through 總長（90ms 出＋210ms 進，Material fade-through 規格）。
  static const Duration tabTransition = Duration(milliseconds: 300);

  /// container transform（卡片原地長成整頁，animations 套件 OpenContainer）。
  static const Duration containerTransform = Duration(milliseconds: 380);

  /// modal surface 上浮進場／下沉退場（paywall 等）；退場比進場快。
  static const Duration modalIn = Duration(milliseconds: 320);
  static const Duration modalOut = Duration(milliseconds: 240);

  /// 報表圖揭示——四張圖共用一個檔位（2026-08 收斂前是 480/520/700 三種）。
  static const Duration chartReveal = Duration(milliseconds: 300);

  /// 數字揭曉（分數 0→終值 的跑動）。比 chartReveal 長是刻意的：這是一個
  /// 要被看著跑完的時刻，不是狀態切換，太快就只剩「畫面閃一下」。
  static const Duration countUp = Duration(milliseconds: 1200);

  /// 文字逐字開場：單一字元自己的進場時長。
  static const Duration textRevealChar = Duration(milliseconds: 680);

  /// 文字逐字開場：相鄰字元的起跑時間差。整串總長＝char + stagger×(字數-1)，
  /// 調 stagger 比調 char 更能改變「一個一個蹦出來」的顆粒感。
  static const Duration textRevealStagger = Duration(milliseconds: 75);

  /// 程式捲動（scrollTo/animateTo「捲去剛產生的東西」）統一檔位。
  static const Duration scroll = Duration(milliseconds: 280);

  /// shared-axis「往內走一層」進場／退場（animations 套件）。
  static const Duration sharedAxisIn = Duration(milliseconds: 300);
  static const Duration sharedAxisOut = Duration(milliseconds: 260);

  /// 強力 ease-out：前段比 easeOutCubic 快、尾段收更長，
  /// 同樣時長下動作更「有感」。
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);
  static const Curve celebrateCurve = Curves.easeOutBack;

  /// iOS 抽屜曲線（Emil/Vaul 系）：進場尾段極長收束。
  static const Curve drawer = Cubic(0.32, 0.72, 0, 1);

  /// bottom sheet 進場／退場（showAppSheet 統一入口）；退場比進場快。
  static const Duration sheetIn = Duration(milliseconds: 340);
  static const Duration sheetOut = Duration(milliseconds: 260);

  /// 按壓縮放比例（PressableScale 全域規格）。
  static const double pressedScale = 0.97;
}

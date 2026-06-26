import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 每日翻牌音效掛勾（Batch 4 種呼叫點 → Batch 4.7 補滿 API 與 waiting loop）。
///
/// **目前刻意仍是 no-op**：把「抽牌咻聲」「等待 shimmer loop」「揭曉叮聲」三組呼叫點
/// 種進揭曉儀式（[PracticeDrawCeremony]）的狀態機，之後要接真音檔時只需換一個會真的
/// 播放的 [PracticeDrawSfx] 實作（透過 [practiceDrawSfxProvider] 注入），呼叫端完全
/// 不必再改。
///
/// 設計鐵則（Batch 4.7 仍嚴守）：
/// - **不**引入 audioplayers / just_audio，也**不**打包任何音檔 → 不增依賴、不增包體。
///   真音檔（CC0／自製／買斷／明確可商用打包）尚未取得；授權確認前一律不 bundle，
///   素材清單與授權見 `assets/audio/practice_draw/licenses/practice_draw_audio.md`。
/// - 方法一律靜默、不丟例外；reduce-motion 與 widget test 環境呼叫都安全。
/// - **lifecycle 安全**：等待 loop 必須能被明確 [stopWaitingLoop]（reveal／error／402／
///   429／hidden／dispose 一律呼叫），絕不在背景殘留。呼叫端負責「每個離開 drawing
///   的出口都 stop」，與 `_waiting` 動畫 controller 的 stop 點一一對應。
/// - 可注入：[practiceDrawSfxProvider] 預設給 [NoopPracticeDrawSfx]，測試以 override
///   注入 spy 驗證「在對的轉場呼叫對的音效」。
abstract class PracticeDrawSfx {
  /// 抽牌啟動：翻牌「咻」的滑出聲（約 0.3–0.6 秒，音量克制）。
  void playWhoosh();

  /// 等待 server 抽牌期間的極小聲 shimmer/ambient loop。
  /// 僅在 `drawStatus == drawing` 且**非** reduce-motion 時由呼叫端啟動。
  void playWaitingLoop();

  /// 停止等待 loop。reveal／error／402／429／hidden／dispose 一律呼叫；可重複呼叫
  /// （idempotent），未在播放時呼叫為 no-op。
  void stopWaitingLoop();

  /// 揭曉成功：卡片翻正的 chime/sparkle（約 0.6–1 秒，與 medium haptic 同步）。
  void playRevealChime();
}

/// 預設實作：完全 no-op、不打包音檔、不發聲，所有方法安全靜默。
/// 接上真音檔後端前的常駐實作，也是 widget test 預設（不真的播放聲音）。
class NoopPracticeDrawSfx implements PracticeDrawSfx {
  const NoopPracticeDrawSfx();

  @override
  void playWhoosh() {}

  @override
  void playWaitingLoop() {}

  @override
  void stopWaitingLoop() {}

  @override
  void playRevealChime() {}
}

/// 翻牌音效服務 provider。預設 [NoopPracticeDrawSfx]；測試以
/// `practiceDrawSfxProvider.overrideWithValue(spy)` 注入 spy 驗證呼叫時機，
/// 之後接真音檔只需在這裡換成會播放的實作。
final practiceDrawSfxProvider = Provider<PracticeDrawSfx>(
  (ref) => const NoopPracticeDrawSfx(),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'practice_draw_audio_sfx.dart';

/// 每日翻牌音效掛勾（Batch 4 種呼叫點 → 4.7 補滿 API／waiting loop → 4.7B 接真音檔）。
///
/// 把「抽牌咻聲」「等待 shimmer loop」「揭曉叮聲」三組呼叫點種進揭曉儀式
/// （[PracticeDrawCeremony]）的狀態機；實際發聲由 [practiceDrawSfxProvider] 注入的
/// [PracticeDrawSfx] 實作決定，呼叫端完全不必管是 no-op 還是真音檔。
///
/// **Batch 4.7B**：預設已從 [NoopPracticeDrawSfx] 換成會真的播放的
/// [AudioPlayersPracticeDrawSfx]（audioplayers）。音檔與授權／來源見
/// `assets/audio/practice_draw/licenses/practice_draw_audio.md`。
///
/// 設計鐵則：
/// - 真實 impl **lazy + guarded**：headless／widget-test 環境（無 audio platform channel）
///   一律靜默、不丟例外；測試以 [practiceDrawSfxProvider] override 注入 spy，不真的播放。
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

  /// 兩段升階揭曉的「蓄力 riser」：高潮蓄力段起手時播一次（卡背翻回、能量邊框點亮
  /// 那一刻）。由揭曉時間軸 `_reveal` 跨蓄力門檻 edge-detect 觸發，一次揭曉只播一次。
  void playRiser();

  /// 兩段升階揭曉的「落定 settle」：高潮翻面、典藏卡定位那一刻播一次。由 `_reveal`
  /// 跨高潮門檻 edge-detect 觸發，一次揭曉只播一次。
  void playSettle();
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

  @override
  void playRiser() {}

  @override
  void playSettle() {}
}

/// 翻牌音效服務 provider。預設 [AudioPlayersPracticeDrawSfx]（真音效，Batch 4.7B）；
/// 測試以 `practiceDrawSfxProvider.overrideWithValue(spy)` 注入 spy 驗證呼叫時機
/// （不真的播放）。[NoopPracticeDrawSfx] 保留作為「明確靜音」的可注入實作。
final practiceDrawSfxProvider = Provider<PracticeDrawSfx>(
  (ref) => AudioPlayersPracticeDrawSfx(),
);

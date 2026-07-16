import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'practice_draw_audio_sfx.dart';

/// 每日翻牌音效掛勾（Batch 4 種呼叫點 → 4.7B 接真音檔 → F3 退役 waiting loop）。
///
/// 把「抽牌咻聲」「揭曉配樂」呼叫點種進揭曉儀式
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
/// - waiting loop 已於 F3 退役；相容方法仍保留為 no-op，避免舊 lifecycle 出口在過渡期失效。
/// - 可注入：[practiceDrawSfxProvider] 預設給 [AudioPlayersPracticeDrawSfx]，測試以
///   override 注入 spy 驗證「在對的轉場呼叫對的音效」。
abstract class PracticeDrawSfx {
  /// 抽牌啟動：翻牌「咻」的滑出聲（約 0.3–0.6 秒，音量克制）。
  void playWhoosh();

  /// 已退役的等待 shimmer loop。production 固定 no-op，儀式流程也不得呼叫。
  void playWaitingLoop();

  /// 已退役 waiting loop 的相容 stop；固定 no-op 且可重複呼叫。
  void stopWaitingLoop();

  /// 揭曉成功：卡片翻正的 chime/sparkle（約 0.6–1 秒，與 medium haptic 同步）。
  void playRevealChime();

  /// 揭曉配樂 bed（E2 復刻）：一條與 `_reveal`（~9s）同長同步的連續配樂，直接取自參考片
  /// `音檔.mp4` 的音軌。在揭曉時間軸起始（`_reveal.forward(from:0)`）播一次，取代舊的
  /// 離散 riser/settle accent。可重複呼叫＝重起（內部先 stop 再 play，同時只一條、不重疊）。
  void playRevealBed();

  /// 停止揭曉配樂 bed。reveal 完成／hidden／失敗兜底／dispose 一律呼叫；idempotent
  /// （未播放／重複呼叫皆 no-op）。與 [stopWaitingLoop] 的離開出口一一對應。
  void stopRevealBed();
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
  void playRevealBed() {}

  @override
  void stopRevealBed() {}
}

/// 翻牌音效服務 provider。預設 [AudioPlayersPracticeDrawSfx]（真音效，Batch 4.7B）；
/// 測試以 `practiceDrawSfxProvider.overrideWithValue(spy)` 注入 spy 驗證呼叫時機
/// （不真的播放）。[NoopPracticeDrawSfx] 保留作為「明確靜音」的可注入實作。
final practiceDrawSfxProvider = Provider<PracticeDrawSfx>(
  (ref) => AudioPlayersPracticeDrawSfx(),
);

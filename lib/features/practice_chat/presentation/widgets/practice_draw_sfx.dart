import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'practice_draw_audio_sfx.dart';

/// 每日翻牌音效掛勾（Batch 4 種呼叫點 → 4.7B 接真音檔 → F3 退役 waiting loop → V3 第三刀
/// 紙聲併進配樂、加收卡音）。
///
/// 把「抽牌咻聲」「揭曉配樂」「收卡音」呼叫點種進揭曉儀式
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
  /// 抽牌啟動：翻牌「咻」的滑出聲，音量克制。v2 檔是實心起手加一段一次性的暖尾巴，
  /// 最長 5.5 s，用來接住等待 server 的空檔。
  void playWhoosh();

  /// 停掉咻聲（含 v2 最長 5.5 s 的暖尾巴）：正在出聲時 0.5 秒淡出再停，不一刀切；還沒出聲
  /// 就直接停。只在「離開畫面／抽牌失敗」呼叫；成功揭曉時刻意不停，讓尾巴交棒給配樂 bed。
  /// idempotent、靜默不丟。
  void stopWhoosh();

  /// 已退役的等待 shimmer loop。production 固定 no-op，儀式流程也不得呼叫。
  void playWaitingLoop();

  /// 已退役 waiting loop 的相容 stop；固定 no-op 且可重複呼叫。
  void stopWaitingLoop();

  /// 揭曉前預載：進入抽牌等待時與 [playWhoosh] 一起呼叫，先把揭曉配樂 bed 與收卡音
  /// 載入 player，之後 [playRevealBed]／[playArchive] 只需從頭 resume。重音都在 bed 裡，
  /// bed 晚播重音就一起晚。可重複呼叫：預載中或已載好時 no-op。
  void preloadReveal();

  /// 揭曉配樂 bed：與 `_reveal`（2.7 s）對好拍的配樂，N／R／SR 同一條（規格 D3）。高潮與
  /// 翻牌紙聲都落在單次翻牌（揭曉 1.35 s）。在揭曉時間軸起始（`_reveal.forward(from:0)`）
  /// 播一次。可重複呼叫＝從頭重起（同時只一條、不重疊）。
  void playRevealBed();

  /// 收卡音：點擊收卡那一刻播一次（0.8 s：輕輕上滑，0.45 s 光球落進那一格時一聲水晶鈴）。
  /// 一次性，不另設停止方法；可重複呼叫＝從頭重起。
  void playArchive();

  /// 停止揭曉配樂 bed：正在出聲時短暫淡出再停。點擊收卡／hidden／失敗兜底／dispose
  /// 一律呼叫；idempotent（未播放／重複呼叫皆 no-op）。與 [stopWaitingLoop] 的離開出口
  /// 一一對應。
  void stopRevealBed();
}

/// 預設實作：完全 no-op、不打包音檔、不發聲，所有方法安全靜默。
/// 接上真音檔後端前的常駐實作，也是 widget test 預設（不真的播放聲音）。
class NoopPracticeDrawSfx implements PracticeDrawSfx {
  const NoopPracticeDrawSfx();

  @override
  void playWhoosh() {}

  @override
  void stopWhoosh() {}

  @override
  void playWaitingLoop() {}

  @override
  void stopWaitingLoop() {}

  @override
  void preloadReveal() {}

  @override
  void playRevealBed() {}

  @override
  void playArchive() {}

  @override
  void stopRevealBed() {}
}

/// 翻牌音效服務 provider。預設 [AudioPlayersPracticeDrawSfx]（真音效，Batch 4.7B）；
/// 測試以 `practiceDrawSfxProvider.overrideWithValue(spy)` 注入 spy 驗證呼叫時機
/// （不真的播放）。[NoopPracticeDrawSfx] 保留作為「明確靜音」的可注入實作。
final practiceDrawSfxProvider = Provider<PracticeDrawSfx>(
  (ref) => AudioPlayersPracticeDrawSfx(),
);

/// 每日翻牌音效掛勾（Batch 4 commit 3）。
///
/// **目前刻意是 no-op stub**：先把「抽牌咻聲」「翻開叮聲」兩個呼叫點種在揭曉儀式
/// 流程裡，之後要接真音檔時只需在這裡補實作，呼叫端（[PracticeDrawCeremony]）
/// 完全不必再改。
///
/// 設計鐵則：
/// - **不**引入 audioplayers / just_audio，也**不**打包任何音檔 → 不增依賴、不增包體。
/// - 方法一律靜默且不丟例外；reduce-motion 與 widget test 環境呼叫都安全。
class PracticeDrawSfx {
  const PracticeDrawSfx._();

  /// 抽牌啟動：翻牌「咻」的滑出聲（目前 no-op，保留呼叫點）。
  static void playWhoosh() {
    // 之後接真音檔；現在刻意不做事。
  }

  /// 揭曉成功：卡片翻正的「叮」聲（目前 no-op，保留呼叫點）。
  static void playRevealChime() {
    // 之後接真音檔；現在刻意不做事。
  }
}

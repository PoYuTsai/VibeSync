/// 教練動作卡可推薦的 9 種 actionType（單一 enum，扁平命名空間）。
enum CoachActionType {
  /// 模糊邀約 — 給一個低門檻、可拒可改的邀約。
  softInvite,

  /// 降低壓力 — 把上一句拆掉追問味，留出空白。
  lowerPressureReply,

  /// 故事框架 — 用「場景 + 觀點/情緒 + 開放式提問」延展。
  extendTopicStoryFrame,

  /// 情緒共鳴 — 先接住對方情緒再回。
  emotionalResonance,

  /// 回得剛剛好 — 對齊 1.8x 黃金法則，避免過度延伸。
  rightSizeReply,

  /// 輕鬆幽默 — 拋一個 playful 卡點。
  playfulReply,

  /// 暫停追問 — 留白、不主動再傳。
  pausePursuit,

  /// 輕量表達偏好 — 講一個自己的小喜好/觀點，不問問題。
  preferenceSignal,

  /// 互動品質觀察 — 描述「這次互動感覺如何」，不貼人格標籤；always-safe fallback。
  fitCheck,
}

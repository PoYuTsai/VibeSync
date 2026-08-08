/**
 * Game 可見詞彙唯一真相源（Eric 2026-08-08 拍板：詞彙統一、教學卡優先對標）。
 *
 * 對標 client 練習室 Game 教學卡 glossary（practice_game_intro_sheet.dart）：
 * 框架→「節奏與主見」、推拉→「輕鬆張力」、DHV→「生活樣本」、篩選→「互相合適度」；
 * 五階段可見名：開場／展示／測試／張力／收尾（P3 可見名＝「測試」，舊契約的
 * 「品味門檻」已退場併入）。
 *
 * hint 修復表、debrief 契約指定用語、fallback 標籤三方都從這裡取詞——先前三分裂
 * （hint 標籤修復／jargon 轉譯／debrief 契約各一套），模型可自行發明第三種白話。
 * 改這裡＝改使用者看得到的教學詞彙，必須同步對齊教學卡文案。
 */

export const GAME_PHASE_LABELS = {
  P1_OPEN: "開場",
  P2_VALUE: "展示",
  P3_TEST: "測試",
  P4_TENSION: "張力",
  P5_CLOSE: "收尾",
} as const;

export const GAME_VARIABLE_LABELS = {
  Value: "價值",
  Frame: "節奏與主見",
  Emotion: "情緒",
  Investment: "投入",
  Safety: "安全感",
  // targetVariableFor 的 P1 目標是 familiarity：白話保留「熟悉感」，明確歸入
  // 詞表，不另發明。
  familiarity: "熟悉感",
} as const;

/** 1.2 內部概念詞 → 教學卡白話。 */
export const GAME_CONCEPT_LABELS = {
  篩選: "互相合適度",
  推拉: "輕鬆張力",
  DHV: "生活樣本",
  可得性: "安全感釋放",
} as const;

export const GAME_SPICY_LEVEL_LABELS = {
  L0: "先修安全感",
  L1: "玩笑試探",
  L2: "成人感暗示",
  L3: "高張力暗示",
} as const;

/**
 * 中文 1.2 原詞轉譯表（順序即套用順序：長詞必須先於其子字串，例如
 * 「資格篩選」在「篩選」之前）。可安全轉譯就不 reject：reject 會觸發
 * 重試/fallback，懲罰過重。
 */
export const GAME_JARGON_TRANSLATIONS: ReadonlyArray<readonly [RegExp, string]> =
  [
    [/資格篩選/g, GAME_PHASE_LABELS.P3_TEST],
    [/賦格/g, GAME_PHASE_LABELS.P3_TEST],
    // 退場詞（2026-08-08 拍板）：prompt 已不教，但模型仍可能直接生成
    //（Codex 首審 P2），hint 側修復、debrief 側 reject（visible_text_guard）。
    [/品味門檻/g, GAME_PHASE_LABELS.P3_TEST],
    [/篩選/g, GAME_CONCEPT_LABELS.篩選],
    [/推拉/g, GAME_CONCEPT_LABELS.推拉],
    [/可得性/g, GAME_CONCEPT_LABELS.可得性],
    [/框架/g, GAME_VARIABLE_LABELS.Frame],
    [/\bDHV\b/gi, GAME_CONCEPT_LABELS.DHV],
  ];

/**
 * 自揭語開頭詞：questionPressureScore（查戶口壓力折抵）與 pv 加分共用。
 * 先前兩處各養一份（pv 少了「我也」「我以前」），同一句話在兩個機制眼中
 * 自揭與否不一致。
 */
export const SELF_DISCLOSURE_TERMS = [
  "我也",
  "我剛",
  "我今天",
  "我自己",
  "我以前",
  "我喜歡",
] as const;

const GAME_PHASE_ORDER = [
  "P1_OPEN",
  "P2_VALUE",
  "P3_TEST",
  "P4_TENSION",
  "P5_CLOSE",
] as const;

/** 教學卡五階段路徑（開場→展示→測試→張力→收尾），給契約 prompt 用。 */
export function gamePhasePathLine(): string {
  return GAME_PHASE_ORDER.map((phase) => GAME_PHASE_LABELS[phase]).join("→");
}

/** 五變數白話對照（價值/節奏與主見/情緒/投入/安全感），給契約 prompt 用。 */
export function gameVariableVocabLine(): string {
  return (["Value", "Frame", "Emotion", "Investment", "Safety"] as const)
    .map((variable) => GAME_VARIABLE_LABELS[variable])
    .join("/");
}

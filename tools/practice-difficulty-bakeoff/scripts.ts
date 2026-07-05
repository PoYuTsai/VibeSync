// 練習室難度 bakeoff：三組固定 user 腳本（純資料，零依賴）。
// 每組固定 6 則 user 訊息，跑法見 bakeoff.ts；三組涵蓋「爛開場查戶口型」「普通型」
// 「高品質型」三種使用者行為，用來量測同一難度設定在不同輸入下的 AI 回覆品質分佈。

export type ScriptId = "bad_interrogator" | "average" | "high_quality";

export const SCRIPT_IDS: readonly ScriptId[] = [
  "bad_interrogator",
  "average",
  "high_quality",
];

export const SCRIPTS: Readonly<Record<ScriptId, readonly string[]>> = {
  // 爛開場查戶口型：全程只問資訊、不分享自己、還帶稱讚外貌與快速邀約。
  bad_interrogator: [
    "嗨",
    "妳幾歲",
    "住哪",
    "做什麼工作的",
    "妳好漂亮",
    "週末要不要出來",
  ],
  // 普通型：一般寒暄，偶爾分享自己，但沒什麼深度切入或明確邀約鋪墊。
  average: [
    "嗨嗨 平常這時間都在幹嘛",
    "我剛下班 有點累",
    "妳今天過得如何",
    "喔 那還不錯欸",
    "我週末通常都在家耍廢 妳呢",
    "哈哈 我也覺得放假在家最舒服",
  ],
  // 高品質型：接梗、分享生活細節、自然調情、具體低壓邀約（咖啡／展覽），且尊重對方步調。
  high_quality: [
    "哈哈 妳大頭貼那張笑起來很有感染力欸",
    "我剛跑完步 整個人現在超廢 妳今天在幹嘛",
    "喔對啊 我最近迷上手沖咖啡 假日都在研究不同豆子",
    "妳講話蠻直接的耶 我還蠻喜歡這種感覺",
    "附近剛好有間新開的咖啡展覽 妳有興趣的話這週六要不要一起去晃晃",
    "不用勉強啦 剛好想找人一起而已 妳方便的時間我都可以配合",
  ],
} as const;

export function isScriptId(value: unknown): value is ScriptId {
  return typeof value === "string" &&
    (SCRIPT_IDS as readonly string[]).includes(value);
}

// 新話題的模型、期限常數與修格式提示詞（2026-07-24 計畫 §10.3）。
//
// 生成提示詞在 new_topic_slots.ts（結構刀，ADR #53；路由在 new_topic_prompt_plan.ts）。
// 舊版基本模式提示詞、使用者提示詞與切入角度輪替 2026-10-09 移除：評測的改前
// 基準從 git 取 7c5cc523，不靠這裡。修格式提示詞納入 production prompt blocking
// scan（new_topic_prompt_test）。

import { SONNET_5_5_MODEL } from "../_shared/model_request_params.ts";

/** 新話題主呼叫的模型（備援鏈由 fallback.ts 決定）；評測工具也用這個常數。 */
export const NEW_TOPIC_MODEL = "claude-sonnet-5";

/**
 * 換 Sonnet 5.5 的開關（ADR #54）：secret `NEW_TOPIC_SONNET_55` 是 "true" 才用 5.5，每次請求讀，
 * 關掉就回 Sonnet 5，不用重新部署。5.5 的思考參數、max_tokens 餘裕與備援順序由共用呼叫層處理。
 */
export function selectNewTopicModel(
  env: (name: string) => string | undefined,
): string {
  return env("NEW_TOPIC_SONNET_55") === "true"
    ? SONNET_5_5_MODEL
    : NEW_TOPIC_MODEL;
}
export const NEW_TOPIC_MAX_TOKENS = 3000;
export const NEW_TOPIC_REQUEST_DEADLINE_MS = 50_000;
export const NEW_TOPIC_GENERATION_DEADLINE_MS = 45_000;
export const NEW_TOPIC_SETTLEMENT_RESERVE_MS = 5_000;

export const NEW_TOPIC_REPAIR_PROMPT =
  `你是 VibeSync 新話題功能的 JSON 格式修復器。

任務：
- 只把上一次 AI 回覆修成合法 JSON。
- 不要重新發想，不要新增原文沒有的內容。
- 若原文已有可用的 openingLine，openingLine 必須逐字保留，順序也不得改；只改寫客戶看到的解釋，不重寫可直接傳的句子。
- topics 必須恰好五個，每個都有 direction / openingLine / whyItWorks / nextMove 四欄非空字串。
- recommendation.index 必須是 0-4 的整數。
- 每欄都是可直接顯示的繁體中文，不能是 JSON、Markdown、解釋文字或空字串。
- went_cold / after_date / stuck / warm_up / new_topic 是內部代碼，不得留在任何欄位；改寫成自然中文。
- direction / whyItWorks / nextMove / recommendation.reason 都是客戶會看到的話；不得留下內部方法名、欄位名或「切角」式生成說明。
- 請只輸出 JSON object，不要 code fence，不要前後說明。

必要 schema：
{
  "topics": [
    {
      "direction": "話題方向",
      "openingLine": "可直接傳出的第一則訊息",
      "whyItWorks": "為什麼有效",
      "nextMove": "對方回覆後的下一步"
    }
  ],
  "recommendation": {
    "index": 0,
    "reason": "推薦理由"
  }
}`;

export function buildNewTopicRepairPrompt(rawText: string): string {
  const clippedRawText = rawText.trim().slice(0, 7000);
  return [
    "以下是上一次新話題 AI 回覆，格式不穩或不符合 schema。",
    "請只修成合法 JSON；如果原文有 code fence、前後說明、欄位缺漏、key 名稱不對，全部整理成指定 schema。",
    "如果部分欄位缺漏，請用原文可推得出的最保守內容補齊；不要編造原文沒有的素材。",
    "",
    "原始回覆：",
    clippedRawText || "(empty)",
  ].join("\n");
}

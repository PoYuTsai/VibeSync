// 關係訊號（開關 ANALYZE_GUIDE_V3_RELATION，Bruce 2026-10-19 路線二）：讀局面順便給 v2 的關係階段、
// 熱度與四個維度。v3 上線後作戰板、報表與對象頁的這幾塊都空了；這三欄只拿來記錄與顯示，不進
// 排卡規則，不影響要不要回、出哪幾張卡與扣費。
//
// - 三欄排在讀局面 schema 的最後：模型照 schema 的順序輸出，前面的標記先寫完、不受影響；第一張
//   卡要等讀局面整段寫完，所以這幾欄要短。
// - 結構化輸出不支援數值範圍（跟 memory.ts 的 maxItems 一樣），0–100 在這裡檢查。不合格的那一欄
//   拿掉、記 log，不夾到範圍內，也不讓分析失敗。
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";
import { normalizeOutgoingScript } from "../outgoing_message_text.ts";
import { GUIDE_V3_ENTRIES, type GuideV3Entry } from "./entries.ts";
import { GUIDE_V3_SECTIONS, type GuideV3SectionId } from "./guide_text.ts";
import { readSystemPrompt } from "./prompts.ts";
import { READ_TAGS_SCHEMA } from "./read_tags.ts";

/// v2 的五個關係階段，App 照舊用這幾個代碼（破冰、升溫、深入、連結、邀約）。
export const GAME_STAGES = [
  "opening",
  "premise",
  "qualification",
  "narrative",
  "close",
] as const;
export type GameStage = typeof GAME_STAGES[number];

/// 熱度以外的四個維度；送 App 的 dimensions 另用 heatScore 補上 heat（v2 的 heat 就是熱度分數）。
export const RELATION_DIMENSIONS = [
  "engagement",
  "topicDepth",
  "replyWillingness",
  "emotionalConnection",
] as const;
export type RelationDimension = typeof RELATION_DIMENSIONS[number];
export type RelationDimensions = Readonly<Record<RelationDimension, number>>;

export const RELATION_SCORE_MIN = 0;
export const RELATION_SCORE_MAX = 100;

/// 照 v2 的定義（testdata/v2_stream_prompt_paid.txt 的關係節奏五階段、熱度分析規則、五維度評分）
/// 用我們自己的話寫。回覆意願跟上面的 replyWillingness 標記用同一個標準：說明書 A3、A4 說回覆快慢
/// 不算數，v2 那句「回覆速度暗示」不搬，雷達與「回覆意願」也就不會互相矛盾。
export const RELATION_FIELD_NOTES =
  `## 最後三個欄位：關係狀態（另外記錄，不影響上面的標記）
- gameStage：這段對話最新在做的事，不是認識多久。opening＝第一次搭上話，或冷了很久、吵架後重新搭上；premise＝從一般聊天進到互相好奇，有來有往的玩笑、張力或曖昧；qualification＝互相了解，確認價值觀、生活步調或界線合不合；narrative＝分享自己的故事、經歷與心情；close＝兩人正在談見面，從隨口說要約到敲定時間地點都算。同時有幾種，照 close、qualification、narrative、premise、opening 的順序取前面的；階段可以跳，也可以退。只是打招呼、回得短或資料不夠，不算 opening；作戰板標籤或他的目標不算 close。
- heatScore：她對這段互動的熱度，0–100 的整數，只看她的訊息：回得長、主動問他、延伸話題、認真回應、表情符號多就高，敷衍的單字就低；他講得多不加分。回覆快慢只是很弱的訊號，一次晚回不扣分。
- dimensions：四個 0–100 的整數，也只看她。engagement＝她回的份量、次數與主動提問；topicDepth＝話題從日常表面進到感受、價值觀或曖昧的程度；replyWillingness＝跟上面的 replyWillingness 同一個標準，換成分數；emotionalConnection＝她分享自己的事、說出心情、語氣親近的程度。`;

/// 讀局面提示詞：欄位說明之後多一段 RELATION_FIELD_NOTES，其他一字不變。
export function readSystemPromptWithRelation(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
  entries: readonly GuideV3Entry[] = GUIDE_V3_ENTRIES,
  leakDirective: string = PROMPT_LEAK_DEFENSE_DIRECTIVE,
): string {
  return readSystemPrompt(
    sections,
    entries,
    leakDirective,
    RELATION_FIELD_NOTES,
  );
}

/// 上面那一段的外洩哨兵（主審第 1 輪 P2）：開關開時，判讀與要等她做什麼照抄這段就不給，跟照抄
/// 說明書一樣。挑正常判讀不會整句寫出來的片段：標題、欄位與代碼的定義、0–100 的計分說法；一般
/// 判讀也會講的話（「她對這段互動的熱度」「生活步調合不合」）不單獨挑，熱度那句要連著「0–100 的
/// 整數」才算。每句都照抄自上面那一段（測試會比對）。
export const RELATION_SENTINELS: readonly string[] = [
  "最後三個欄位：關係狀態",
  "另外記錄，不影響上面的標記",
  "這段對話最新在做的事，不是認識多久",
  "opening＝第一次搭上話",
  "premise＝從一般聊天進到互相好奇",
  "qualification＝互相了解，確認價值觀",
  "narrative＝分享自己的故事",
  "close＝兩人正在談見面",
  "從隨口說要約到敲定時間地點都算",
  "照 close、qualification、narrative、premise、opening 的順序取前面的",
  "階段可以跳，也可以退",
  "回得短或資料不夠，不算 opening",
  "作戰板標籤或他的目標不算 close",
  "她對這段互動的熱度，0–100 的整數",
  "認真回應、表情符號多就高",
  "敷衍的單字就低；他講得多不加分",
  "回覆快慢只是很弱的訊號，一次晚回不扣分",
  "四個 0–100 的整數，也只看她",
  "engagement＝她回的份量、次數與主動提問",
  "topicDepth＝話題從日常表面進到感受",
  "replyWillingness＝跟上面的 replyWillingness 同一個標準",
  "同一個標準，換成分數",
  "emotionalConnection＝她分享自己的事",
];

/// 跟說明書哨兵一樣再做一份簡轉繁整理過的（finalize.ts 的 GUIDE_V3_SENTINELS_NORMALIZED）：判讀
/// 整理後才比的那一次要用。
export const RELATION_SENTINELS_NORMALIZED: readonly string[] =
  RELATION_SENTINELS.map((s) => normalizeOutgoingScript(s) ?? s);

/// 開關開時交給 vetPlanText 多比的哨兵（原樣與整理過的，去掉重複）。
export const RELATION_LEAK_SENTINELS: readonly string[] = [
  ...new Set([...RELATION_SENTINELS, ...RELATION_SENTINELS_NORMALIZED]),
];

/// 在任何一份讀局面 schema 的最後加上三欄（都必填）；原本的欄位與順序不動。
export function withRelationFields(
  schema: Record<string, unknown>,
): Record<string, unknown> {
  return {
    ...schema,
    required: [
      ...(schema.required as readonly string[]),
      "gameStage",
      "heatScore",
      "dimensions",
    ],
    properties: {
      ...(schema.properties as Record<string, unknown>),
      gameStage: { type: "string", enum: [...GAME_STAGES] },
      heatScore: { type: "integer" },
      dimensions: {
        type: "object",
        additionalProperties: false,
        required: [...RELATION_DIMENSIONS],
        properties: Object.fromEntries(
          RELATION_DIMENSIONS.map((d) => [d, { type: "integer" }]),
        ),
      },
    },
  };
}

export const READ_TAGS_SCHEMA_WITH_RELATION = withRelationFields(
  READ_TAGS_SCHEMA,
);

export type RelationField = "gameStage" | "heatScore" | "dimensions";

/// missing＝沒給；invalid＝不在選項裡、不是 0–100 的整數，或四個維度缺了、壞了任何一個。
export interface RelationDrop {
  readonly field: RelationField;
  readonly reason: "missing" | "invalid";
}

/// 通過檢查的值；沒過的就沒有那一欄。
export interface RelationRead {
  readonly stage?: GameStage;
  readonly heat?: number;
  readonly dimensions?: RelationDimensions;
}

/// 存進 guideV3Trace：通過檢查的值（只有代碼與數字）與拿掉的欄位，不放模型寫的字。
export interface GuideV3RelationTrace extends RelationRead {
  readonly dropped: readonly RelationDrop[];
}

function isScore(value: unknown): value is number {
  return Number.isInteger(value) && (value as number) >= RELATION_SCORE_MIN &&
    (value as number) <= RELATION_SCORE_MAX;
}

function isStage(value: unknown): value is GameStage {
  return typeof value === "string" &&
    (GAME_STAGES as readonly string[]).includes(value);
}

function dimensionsFrom(value: unknown): RelationDimensions | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const v = value as Record<string, unknown>;
  if (!RELATION_DIMENSIONS.every((d) => isScore(v[d]))) return null;
  return Object.fromEntries(
    RELATION_DIMENSIONS.map((d) => [d, v[d]]),
  ) as Record<RelationDimension, number>;
}

/// 讀局面輸出（已經過 parseReadTags 的同一個 JSON 物件）裡的三欄，逐欄檢查。不丟錯。
export function parseRelation(value: unknown): GuideV3RelationTrace {
  const v = value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
  const dropped: RelationDrop[] = [];
  const drop = (field: RelationField) =>
    dropped.push({
      field,
      reason: v[field] === undefined ? "missing" : "invalid",
    });
  const stage = isStage(v.gameStage) ? v.gameStage : null;
  if (!stage) drop("gameStage");
  const heat = isScore(v.heatScore) ? v.heatScore : null;
  if (heat === null) drop("heatScore");
  const dimensions = dimensionsFrom(v.dimensions);
  if (!dimensions) drop("dimensions");
  return {
    ...(stage ? { stage } : {}),
    ...(heat !== null ? { heat } : {}),
    ...(dimensions ? { dimensions } : {}),
    dropped,
  };
}

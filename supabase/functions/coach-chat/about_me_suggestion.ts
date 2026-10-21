// 規格 PR-9：教練可以建議把使用者自己說出的處境或目標加進「關於我」。只能從
// 固定選項挑、只能「加入」，App 要本人按【加入】才寫進手機。
//
// 代碼跟 App 的 StuckPoint／PracticeGoal enum 同名；中文標籤跟 App 組給教練的
// 「關於我」同一套（EffectiveStylePromptBuilder 的卡點與練習重點標籤），模型
// 才比得出關於我裡是不是已經有了。兩邊各有一個測試鎖住這份清單：這裡的
// prompts_test.ts（部署前的 Edge 契約測試會跑），與 App 的
// test/unit/features/coach_chat/about_me_suggestion_codes_test.dart（它也直接讀
// 這個檔比對）。

import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

export const ABOUT_ME_SUGGESTION_OPTIONS = {
  stuckPoint: {
    fadesOut: "話題卡住接不下去",
    dontKnowHowToAsk: "不知道怎麼開口約",
    anxiousWontSend: "緊張不敢傳",
    overExplains: "容易解釋太多",
    leftOnRead: "已讀不回",
  },
  practiceGoal: {
    softInvite: "想約得出來",
    comfortableChat: "想先能自在聊天",
    humorousReply: "想讓對話更幽默、有來有往",
    buildCloseness: "想培養穩定的親近感",
    findCompatiblePartner: "想找到聊得來的對象",
  },
} as const;

export type AboutMeSuggestionField = keyof typeof ABOUT_ME_SUGGESTION_OPTIONS;

/** 往 App 送的只有欄位與代碼；reason 只用來要模型引用使用者自己的話，不外送。 */
export interface AboutMeSuggestion {
  field: AboutMeSuggestionField;
  key: string;
}

export const ABOUT_ME_SUGGESTION_REASON_MAX = 40;

const RawSuggestionSchema = z.object({
  field: z.enum(["stuckPoint", "practiceGoal"]),
  key: z.string(),
  reason: z.string().trim().min(1).max(ABOUT_ME_SUGGESTION_REASON_MAX),
}).strict();

export type AboutMeSuggestionParse =
  | { kind: "absent" }
  | { kind: "invalid" }
  | { kind: "valid"; suggestion: AboutMeSuggestion };

/**
 * 模型原始 JSON 裡的 `aboutMeSuggestion`。沒填（null／缺）回 `absent`；形狀、
 * 欄位或代碼不對回 `invalid`，整張卡照常，只是不帶建議。
 */
export function normalizeAboutMeSuggestion(
  raw: unknown,
): AboutMeSuggestionParse {
  if (raw === undefined || raw === null) return { kind: "absent" };
  const parsed = RawSuggestionSchema.safeParse(raw);
  if (!parsed.success) return { kind: "invalid" };
  const { field, key } = parsed.data;
  if (!Object.hasOwn(ABOUT_ME_SUGGESTION_OPTIONS[field], key)) {
    return { kind: "invalid" };
  }
  return { kind: "valid", suggestion: { field, key } };
}

function formatOptions(field: AboutMeSuggestionField): string {
  return Object.entries(ABOUT_ME_SUGGESTION_OPTIONS[field])
    .map(([key, label]) => `${key} ${label}`)
    .join("／");
}

/** 接在提示的 JSON schema 後面的使用規則與代碼對照（固定文字）。 */
export function formatAboutMeSuggestionRules(): string {
  return [
    "aboutMeSuggestion 規則：只有使用者在「使用者問題」或「本次教練室對話」裡自己明確說出下列某個處境或目標，而「使用者自述（關於我）」裡還沒有時才填，一次最多一個，reason 用使用者自己的話；clarifyingQuestion 一律 null；不能依據對方的訊息、截圖內容或你的推測來填。",
    `stuckPoint：${formatOptions("stuckPoint")}`,
    `practiceGoal：${formatOptions("practiceGoal")}`,
  ].join("\n");
}

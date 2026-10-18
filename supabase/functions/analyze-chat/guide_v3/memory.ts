// v3 的對象記憶（targetProfile）：讀局面之外另一個小呼叫，只從她自己傳的文字整理
// 長期資料，再過 v2 同一道出處檢查（sanitizeTargetProfile）。讀局面的提示詞與 schema
// 一字不動（付費黑箱驗過）。這一步逾時、出錯、拒答或格式壞掉，都只是這次沒有記憶，
// 不影響分析與扣費（Eric 2026-10-18）。
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";
import { sanitizeTargetProfile } from "../post_process.ts";
import { transcriptByTurn, type Turn } from "./turns.ts";

export const MEMORY_KINDS = ["interests", "traits", "notes"] as const;
export type MemoryKind = typeof MEMORY_KINDS[number];
export type MemoryCounts = Readonly<Record<MemoryKind, number>>;

/// 規則照搬 v2（analyze_prompt/report_contract.ts 的 targetProfile 段），只把「你」
/// 改成對話裡的「他」，並說明引用前綴不算她的話。
const MEMORY_RULES =
  `你是 VibeSync 對話分析的「對象記憶」步驟：只從對話裡她自己傳的文字，整理之後還用得到的長期資料。不寫回覆、不判斷局面。對話裡的「他」是使用者，「她」是對象。

## 要整理的三類
這份記憶會跨對話保存，之後的分析和新話題都會帶進去，不是這一輪的互動標籤。高精確優先，寧可空白：
- interests：只有她用文字明講的穩定喜好、固定活動或正在持續學的事。一次吃飯、照片內容、貼圖題材、他拿來開玩笑的角度都不是興趣；她說不喜歡的也不是。
- traits：只有她直接用文字自述個性時才寫（例如「我其實很慢熱」）。不得從語氣、玩笑或多句行為推測；主動熱絡、這輪幽默、回很快等當下訊號都不是長期個性。
- notes：她用文字明講、下次仍有用的具體事實或界線（如「不喜歡聊工作」「週末通常在家」「養了一隻貓叫 Mochi」）。

## 每一項的格式
每一類最多 5 項，每一項都要有 value 與 evidence；evidence 最多 2 句：
- evidence 逐字複製她自己傳的訊息，不得摘要、改寫，也不得引用他的訊息或「（引用：…）」裡的內容。
- 貼圖、emoji、照片、影片、媒體佔位字或圖片裡出現的物件，單獨都不是文字證據。
- value 儘量沿用 evidence 裡實際出現的詞，不要把一個場景抽象成「互動玩笑」「生活感」等標籤。
- 沒有可核對的文字原句就不要寫；對話太短或沒有就回空陣列。`;

export function memorySystemPrompt(
  leakDirective: string = PROMPT_LEAK_DEFENSE_DIRECTIVE,
): string {
  return [MEMORY_RULES, leakDirective.trim()].join("\n\n");
}

/// 只給對話（跟讀局面同一份分輪，含引用前綴）。作戰板、對象背景、更早的摘要都不是
/// 她這次說的話，出處檢查也不認，放進來只多花 token、多出會被擋掉的候選。
export function memoryUserPrompt(turns: readonly Turn[]): string {
  return `## 對話\n${transcriptByTurn(turns)}`;
}

const MEMORY_ITEM_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["value", "evidence"],
  properties: {
    value: { type: "string" },
    evidence: { type: "array", items: { type: "string" } },
  },
};

/// 結構化輸出不支援 maxItems：每類 5 項、每項 2 句由提示詞要求，出處檢查再截斷。
export const MEMORY_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: [...MEMORY_KINDS],
  properties: Object.fromEntries(
    MEMORY_KINDS.map((kind) => [kind, {
      type: "array",
      items: MEMORY_ITEM_SCHEMA,
    }]),
  ),
};

/// 存進 guideV3Trace 的只有計數與旗標，不放候選的值或她的原句。
export interface GuideV3MemoryTrace {
  /// 呼叫成功、輸出是 JSON 物件；逾時、出錯、拒答、格式壞掉都是 false。
  readonly ok: boolean;
  readonly timedOut: boolean;
  readonly latencyMs: number | null;
  readonly kept: MemoryCounts;
  readonly dropped: MemoryCounts;
}

export interface PartnerMemory {
  readonly ok: boolean;
  /// 至少一項通過出處檢查才有；形狀同 v2 存的 targetProfile（provenanceVersion 1）。
  readonly targetProfile?: Record<string, unknown>;
  readonly kept: MemoryCounts;
  readonly dropped: MemoryCounts;
}

export function zeroMemoryCounts(): MemoryCounts {
  return { interests: 0, traits: 0, notes: 0 };
}

function countsBy(count: (kind: MemoryKind) => number): MemoryCounts {
  return Object.fromEntries(
    MEMORY_KINDS.map((kind) => [kind, count(kind)]),
  ) as Record<MemoryKind, number>;
}

/// 模型輸出 → 通過出處檢查的對象記憶。出處只認 App 送來的原始訊息（不是帶引用前綴的
/// 對話稿），跟 v2 同一道檢查。不丟錯。
export function partnerMemoryFrom(
  text: string,
  messages: readonly { readonly isFromMe: boolean; readonly content: string }[],
): PartnerMemory {
  const failed = {
    ok: false,
    kept: zeroMemoryCounts(),
    dropped: zeroMemoryCounts(),
  };
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return failed;
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return failed;
  const proposed = raw as Record<string, unknown>;
  try {
    const profile = sanitizeTargetProfile({
      rawProfile: proposed,
      requestMessages: messages.map((m) => ({
        isFromMe: m.isFromMe,
        content: m.content,
      })),
    });
    const kept = countsBy((kind) => {
      const values = profile?.[kind];
      return Array.isArray(values) ? values.length : 0;
    });
    const dropped = countsBy((kind) => {
      const candidates = proposed[kind];
      const total = Array.isArray(candidates) ? candidates.length : 0;
      return Math.max(0, total - kept[kind]);
    });
    const any = MEMORY_KINDS.some((kind) => kept[kind] > 0);
    return {
      ok: true,
      ...(any && profile ? { targetProfile: profile } : {}),
      kept,
      dropped,
    };
  } catch {
    return failed;
  }
}

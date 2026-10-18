// 任務卡的「再調一下」（Eric 2026-10-18 核准）：App 帶這張卡的任務、口吻與「有他」做法，
// 伺服器只認 wire.ts 的固定代碼；提示詞多一段任務卡規則；調完的字跟出卡走同一套定稿
// 檢查，另外則數與空格都要留住。計費完全沿用回覆微調（refine_reply），這裡不碰帳。
import { containsPromptLeak } from "../../_shared/prompt_leak_guard.ts";
import { normalizeOutgoingScript } from "../outgoing_message_text.ts";
import type { V3CardTaskCode } from "../stream_run_store.ts";
import { type CardRemovalReason, finalizeCard } from "./finalize.ts";
import type { HisMethod, Task, Voice } from "./rules.ts";
import {
  METHOD_CODE,
  type MethodCode,
  TASK_CODE,
  VOICE_CODE,
  type VoiceCode,
} from "./wire.ts";

export interface GuideV3RefineCard {
  readonly task: V3CardTaskCode;
  readonly voice: VoiceCode;
  readonly method: MethodCode;
}

export type GuideV3RefineCardParse =
  | { readonly kind: "absent" }
  | { readonly kind: "ok"; readonly card: GuideV3RefineCard }
  | { readonly kind: "error" };

function byCode<K extends string>(
  map: Readonly<Record<K, string>>,
): ReadonlyMap<string, K> {
  return new Map(
    (Object.entries(map) as [K, string][]).map(([name, code]) => [code, name]),
  );
}

// 代碼表直接從 wire.ts 反推：出卡加了新任務，這裡跟著認得，不另列一份。
const TASK_BY_CODE = byCode<Task>(TASK_CODE);
const VOICE_BY_CODE = byCode<Voice>(VOICE_CODE);
const METHOD_BY_CODE = byCode<HisMethod>(METHOD_CODE);

/// 沒帶＝一般微調（舊 App）；帶了就三個欄位都要是出卡用的代碼，其餘欄位不看。
export function parseGuideV3RefineCard(raw: unknown): GuideV3RefineCardParse {
  if (raw === undefined || raw === null) return { kind: "absent" };
  if (typeof raw !== "object" || Array.isArray(raw)) return { kind: "error" };
  const { task, voice, method } = raw as Record<string, unknown>;
  if (
    typeof task !== "string" || !TASK_BY_CODE.has(task) ||
    typeof voice !== "string" || !VOICE_BY_CODE.has(voice) ||
    typeof method !== "string" || !METHOD_BY_CODE.has(method)
  ) {
    return { kind: "error" };
  }
  return {
    kind: "ok",
    card: {
      task: task as V3CardTaskCode,
      voice: voice as VoiceCode,
      method: method as MethodCode,
    },
  };
}

/// 一張卡的幾則用換行接成 userDraft 送來；模型偶爾把換行寫成字面的 \n，一併拆開。
export function splitCardMessages(text: string): string[] {
  return text.replace(/\\n/g, "\n").split(/\r?\n/).map((m) => m.trim())
    .filter((m) => m.length > 0);
}

const TASK_RULE: Readonly<Record<Task, string>> = {
  接住:
    "先回應她剛說的內容，再帶出他自己的反應或看法；不要改成反問她或換話題。",
  共鳴: "站在她那邊陪她；不給建議、不評對錯，也不追問經過。",
  帶張力:
    "玩笑帶來的那一點緊繃要留著，後面把氣氛鬆開的那一句也要留著；不要調成只剩客套，或只剩虧她。",
  推進:
    "往前推的意思要留著：用陳述句，或當作已經說定的口氣；最後一句不能是徵求同意的問法（例如可不可以、方不方便、好不好、會不會太突然），也不要為了降低壓力改成這種問法。",
  收: "一句輕輕收尾，不開新話題，也不再追問。",
};

const METHOD_RULE: Readonly<Record<HisMethod, string>> = {
  只用反應: "只用他的反應、看法或提議，不加上他的經歷或生活細節。",
  用他說過的: "提到他自己的事，只能用卡片裡已經有的內容。",
  留空格:
    "他的個人資料（做什麼工作、幾歲、住在哪裡這類）一律維持空格，不替他補上。",
  "照樣寫＋標示":
    "卡片裡有編出來的細節，App 會提醒他改成自己的；可以留著，但不要再多編新的細節。",
};

const VOICE_RULE: Readonly<Record<Voice, string>> = {
  照他:
    "口吻照卡片原本的用字、稱呼和語助詞（卡片用「妳」就維持「妳」），不要換成別的腔調。",
  預設: "稱呼對方一律用「你」，不用「妳」；語助詞和表情符號少用。",
};

/// system prompt 裡的任務卡規則：依任務、做法、口吻組出固定文字（同規格的卡共用快取）。
export function guideV3RefineSection(card: GuideV3RefineCard): string {
  const task = TASK_BY_CODE.get(card.task)!;
  return [
    "## 任務卡規則",
    "",
    "這一則是對話分析寫好的任務卡。這一節優先於上面的「調整品質」與快捷指令示範；「不可覆蓋的規則」仍然最優先。",
    `- 這張卡的任務是「${task}」，調完仍要做同一件事，也不加入卡片沒有的事實：${
      TASK_RULE[task]
    }`,
    `- ${METHOD_RULE[METHOD_BY_CODE.get(card.method)!]}`,
    "- 卡片裡的「＿＿」是留給他自己填的空格：每一個都原樣保留，不要替他填，也不要刪掉。",
    `- ${VOICE_RULE[VOICE_BY_CODE.get(card.voice)!]}`,
    "- userDraft 是陣列，每個元素是一則要分開傳的訊息：調完的則數跟原本一樣，不合併、不拆開、順序不變；optimized 裡一則一行，用換行分開。",
    "- 「更直接」是把他的意思講明白、拿掉繞圈的鋪陳，不是加碼施壓，也不是換成別的任務；「更幽默」是從對話裡現有的東西找輕鬆的點，不拿她本人開玩笑。",
  ].join("\n");
}

/// 每一種規格（任務 × 口吻 × 做法），從 wire.ts 的代碼表列出來。
function allRefineCards(): GuideV3RefineCard[] {
  return Object.values(TASK_CODE).flatMap((task) =>
    Object.values(VOICE_CODE).flatMap((voice) =>
      Object.values(METHOD_CODE).map((method) => ({ task, voice, method }))
    )
  );
}

/// 任務卡規則段落的外洩哨兵（主審第 1 輪 P2-4；出卡的哨兵只涵蓋說明書，見 finalize.ts）：
/// 每一種規格組出來的段落，標題以外每一行依「：；。」切開，留 12 字以上的片段。模型把
/// 段落或其中一條規則照抄成一則時，定稿擋下。
export const GUIDE_V3_REFINE_SENTINELS: readonly string[] = [
  ...new Set(
    allRefineCards()
      .flatMap((card) => guideV3RefineSection(card).split("\n").slice(1))
      .flatMap((line) => line.replace(/^-\s*/, "").split(/[：；。]/))
      .map((part) => part.trim())
      .filter((part) => part.length >= 12),
  ),
];

/// 簡體照抄時整理會轉成繁體（也會改詞），所以哨兵也備一份整理過的。
export const GUIDE_V3_REFINE_SENTINELS_NORMALIZED: readonly string[] =
  GUIDE_V3_REFINE_SENTINELS.map((s) => normalizeOutgoingScript(s) ?? s);

function echoesRefineSection(texts: readonly string[]): boolean {
  return texts.some((text) =>
    containsPromptLeak(text, GUIDE_V3_REFINE_SENTINELS) ||
    containsPromptLeak(text, GUIDE_V3_REFINE_SENTINELS_NORMALIZED)
  );
}

export type GuideV3RefineRejection =
  | CardRemovalReason
  | "message_count_changed"
  | "blank_changed";

export type GuideV3RefineOutcome =
  | { readonly ok: true; readonly messages: readonly string[] }
  | { readonly ok: false; readonly reason: GuideV3RefineRejection };

const BLANK_RUN = /＿+/g;

function blankRuns(message: string): number {
  return message.match(BLANK_RUN)?.length ?? 0;
}

/// 調完的字定稿：拆成幾則，跟出卡同一套 finalizeCard（口吻、整理、簡轉繁、禁語與脅迫、
/// 外洩、語言漂移），再查任務卡規則有沒有被照抄，以及兩件結構上的事——則數
/// 跟原本一樣（多則卡不被併成一則），每一則的空格段數也跟原本一樣（身分空格不能被填成
/// 編的、挪到別則，也不能多編一個；主審第 1 輪 P2-5 改成逐則比）。
export function finalizeRefinedCard(args: {
  readonly draft: string;
  readonly optimized: string;
  readonly card: GuideV3RefineCard;
  /// 對話全文（她跟他傳過的字），英文詞要有它支持或在白名單裡。
  readonly sourceText: string;
}): GuideV3RefineOutcome {
  const before = splitCardMessages(args.draft);
  const out = finalizeCard(
    {
      card: 1,
      messages: splitCardMessages(args.optimized),
      hasInventedDetail: args.card.method === "invented",
      expectedReaction: "",
    },
    { voice: VOICE_BY_CODE.get(args.card.voice)! },
    args.sourceText,
  );
  if (!out.ok) return { ok: false, reason: out.reason };
  // 整理前後兩份都查：預設口吻會把「妳」換成「你」，簡體會轉成繁體。
  if (
    echoesRefineSection([
      out.messages.join("\n"),
      splitCardMessages(args.optimized).join("\n"),
    ])
  ) {
    return { ok: false, reason: "prompt_leak" };
  }
  if (out.messages.length !== before.length) {
    return { ok: false, reason: "message_count_changed" };
  }
  if (out.messages.some((m, i) => blankRuns(m) !== blankRuns(before[i]))) {
    return { ok: false, reason: "blank_changed" };
  }
  return { ok: true, messages: out.messages };
}

/// 會被當成內容問題（引導他換方向再調）的原因；其他當成這次沒調好（請他再試一次）。
///「欠」組 10/18 起跟出卡一樣只記錄、不擋（Bruce 10/18，Eric 2026-10-19）。
export function isGuideV3RefineSafetyRejection(
  reason: GuideV3RefineRejection | null,
): boolean {
  return reason === "unsafe";
}

// 每張卡送出前各自定稿：整理文字、再逐項檢查。命中只拿掉這一張（記原因），
// 不整組換成罐頭句；送出之後不再改字。
import { containsPromptLeak } from "../../_shared/prompt_leak_guard.ts";
import { findUnsupportedLatinTokens } from "../../_shared/zh_tw_visible_text_guard.ts";
import { isBlockedOutgoingCard } from "../guardrails.ts";
import {
  normalizeOutgoingPunctuation,
  normalizeOutgoingScript,
} from "../outgoing_message_text.ts";
import { hasAnalyzeChatPromptLeak } from "../prompt_leak.ts";
import {
  hasPromptInjection,
  hasUnsafeRecommendation,
} from "../stream_recommendation_guardrail.ts";
import { stripUnexpectedForeignClauses } from "../unexpected_foreign_text.ts";
import { applyVoice, scoringWords, type WrittenCard } from "./cards.ts";
import { GUIDE_V3_SECTIONS } from "./guide_text.ts";
import { type GuideV3Plan, HOLD_WAIT_FALLBACK } from "./plan.ts";
import type { CardSpec } from "./rules.ts";

export type CardRemovalReason =
  | "empty_after_cleanup"
  | "unsafe"
  | "prompt_leak"
  | "language_drift";

export type FinalizedCard =
  | {
    readonly ok: true;
    readonly messages: readonly string[];
    readonly hasInventedDetail: boolean;
    /// 改過字時的模型原文（「妳」換「你」、簡轉繁等），只進伺服器紀錄。
    readonly rawMessages?: readonly string[];
    /// C5 打分、考題與「欠」組字眼：只記錄、不擋（Bruce 10/15 維持；「欠」組 10/18 改回只記錄）。
    readonly scoringWords: readonly string[];
    /// 對話裡沒出現、也不在白名單的英文詞：只記錄（品牌名、offer 這類常見）。
    readonly unsupportedLatin: readonly string[];
  }
  | {
    readonly ok: false;
    readonly reason: CardRemovalReason;
    readonly detail?: readonly string[];
  };

/// 說明書每一節的第一行內文（標題之後，去掉項目符號、編號與粗體）的前 24 字當
/// 外洩哨兵：正常的卡不會整句照抄。
export const GUIDE_V3_SENTINELS: readonly string[] = Object.values(
  GUIDE_V3_SECTIONS,
).flatMap((text) => {
  const first = text.split("\n").slice(1)
    .map((l) => l.replace(/^(?:[-*\s]|\d+\.\s*)+/, "").replaceAll("**", ""))
    .find((l) => l.length >= 12);
  return first ? [first.slice(0, 24)] : [];
});

const HAN = /\p{Script=Han}/u;

/// 哨兵也做一份跟卡片同樣的簡轉繁（會改詞，例如「用戶」→「使用者」）：模型用簡體
/// 照抄時，原文對不上繁體哨兵、整理後又被改詞，要拿整理後的哨兵比。
export const GUIDE_V3_SENTINELS_NORMALIZED: readonly string[] =
  GUIDE_V3_SENTINELS.map((s) => normalizeOutgoingScript(s) ?? s);

/// 說明書哨兵也走共用比對（Eric 2026-10-18）：原本直接 includes，夾空白或簡體照抄
/// （「用 户＝他（男生）…」）都對不上（主審 r1 P2-2）。整理過的那份照樣一起比。
const GUIDE_V3_LEAK_SENTINELS: readonly string[] = [
  ...GUIDE_V3_SENTINELS,
  ...GUIDE_V3_SENTINELS_NORMALIZED,
];

/// extra：兩段式實驗新提示詞的哨兵（two_stage_prompts.ts、explain.ts）；沒給就跟今天一樣。
function leaksPrompt(text: string, extra: readonly string[] = []): boolean {
  return hasAnalyzeChatPromptLeak(text) ||
    containsPromptLeak(text, GUIDE_V3_LEAK_SENTINELS) ||
    (extra.length > 0 && containsPromptLeak(text, extra));
}

function cleanMessage(message: string): string | null {
  const expanded = message.replace(/\\n/g, "\n").replace(/\n{2,}/g, "\n");
  return stripUnexpectedForeignClauses(
    normalizeOutgoingScript(normalizeOutgoingPunctuation(expanded)),
  )?.trim() || null;
}

/// sourceText：對話全文（她跟他傳過的字），英文詞要有它支持或在白名單裡。
/// 規格只用到口吻（任務卡的再調也走這裡，見 refine_card.ts）。
/// extraSentinels：兩段式實驗寫卡提示詞新加段落的哨兵；沒給就跟今天一樣。
export function finalizeCard(
  card: WrittenCard,
  spec: Pick<CardSpec, "voice">,
  sourceText: string,
  extraSentinels: readonly string[] = [],
): FinalizedCard {
  const voiced = applyVoice(card, spec);
  const cleaned = voiced.messages.map(cleanMessage).filter((m): m is string =>
    m !== null
  );
  if (cleaned.length === 0) {
    return { ok: false, reason: "empty_after_cleanup" };
  }
  // 檢查整理前後兩份：簡轉繁會改詞（「用戶」→「使用者」），可能讓原文的禁語或
  // 外洩片段對不上。兩份各自整張掃，不能放在一起掃（接起來會湊出不存在的句子）。
  // 脅迫樣式只認「你」，照他口吻的卡可能寫「妳」，掃描時一併換掉。
  const asYou = (ms: readonly string[]) =>
    ms.map((m) => m.replaceAll("妳", "你"));
  const versions = [asYou(cleaned), asYou(card.messages)];
  // v2 推薦卡的英文樣式（跟蹤、施壓、提示詞注入）也一併查。
  if (
    versions.some((ms) =>
      isBlockedOutgoingCard(ms) || ms.some((m) => hasUnsafeRecommendation(m))
    )
  ) return { ok: false, reason: "unsafe" };
  const joined = cleaned.join("\n");
  const rawJoined = card.messages.join("\n");
  if (
    leaksPrompt(joined, extraSentinels) ||
    leaksPrompt(rawJoined, extraSentinels) ||
    hasPromptInjection(joined) || hasPromptInjection(rawJoined)
  ) {
    return { ok: false, reason: "prompt_leak" };
  }
  // 只拿掉「整張卡是英文」的：一個漢字都沒有、又有兩個以上沒來源的英文詞。夾在中文裡
  // 的英文詞（相機型號、offer），或中文卡後面加一則「Good night~」，都是正常的卡，只記錄。
  const latin = findUnsupportedLatinTokens(joined, sourceText);
  if (!cleaned.some((m) => HAN.test(m)) && latin.length >= 2) {
    return { ok: false, reason: "language_drift", detail: latin };
  }
  const changed = cleaned.length !== card.messages.length ||
    cleaned.some((m, i) => m !== card.messages[i]);
  return {
    ok: true,
    messages: cleaned,
    // 模型自己標的；App 據此提醒他把編出來的細節改成自己的。
    hasInventedDetail: card.hasInventedDetail,
    ...(changed ? { rawMessages: card.messages } : {}),
    scoringWords: scoringWords(joined),
    unsupportedLatin: latin,
  };
}

/// 給用戶看的教練文字（判讀、要等她做什麼）：比照 v2 不送型決定的檢查（提示詞注入、
/// 英文的不安全樣式），再加外洩哨兵；整理前後都查。不掃 BLOCKED_PATTERNS：那是給
/// 可以照傳的句子，拿去掃描述會誤傷正確的說明（同 guardrails.ts 的理由）。
export function vetCoachText(
  text: string,
): { ok: true; text: string } | { ok: false } {
  const cleaned =
    (normalizeOutgoingScript(normalizeOutgoingPunctuation(text)) ??
      "").trim();
  for (const t of [text, cleaned]) {
    if (leaksPrompt(t) || hasPromptInjection(t) || hasUnsafeRecommendation(t)) {
      return { ok: false };
    }
  }
  return { ok: true, text: cleaned };
}

/// 判讀命中就不給（空字串）；要等她做什麼命中或清完是空的，就用預設那句（扣費紀錄
/// 的 stopCondition 不能是空的）。
export function vetPlanText(
  plan: GuideV3Plan,
  onRemoved: (field: "judgment" | "waitFor") => void,
): GuideV3Plan {
  let judgment = plan.judgment;
  if (judgment) {
    const vetted = vetCoachText(judgment);
    judgment = vetted.ok ? vetted.text : "";
    if (!vetted.ok) onRemoved("judgment");
  }
  let waitFor = plan.waitFor;
  if (waitFor) {
    const vetted = vetCoachText(waitFor);
    if (vetted.ok && vetted.text) waitFor = vetted.text;
    else {
      waitFor = HOLD_WAIT_FALLBACK;
      onRemoved("waitFor");
    }
  }
  return { ...plan, judgment, waitFor };
}

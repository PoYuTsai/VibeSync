// 每張卡送出前各自定稿：整理文字、再逐項檢查。命中只拿掉這一張（記原因），
// 不整組換成罐頭句；送出之後不再改字。
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
    /// C5 打分或考題字眼：只記錄、不擋（Bruce 10/15 維持）。
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

function leaksPrompt(text: string): boolean {
  return hasAnalyzeChatPromptLeak(text) ||
    GUIDE_V3_SENTINELS.some((s) => text.includes(s));
}

function cleanMessage(message: string): string | null {
  const expanded = message.replace(/\\n/g, "\n").replace(/\n{2,}/g, "\n");
  return stripUnexpectedForeignClauses(
    normalizeOutgoingScript(normalizeOutgoingPunctuation(expanded)),
  )?.trim() || null;
}

/// sourceText：對話全文（她跟他傳過的字），英文詞要有它支持或在白名單裡。
export function finalizeCard(
  card: WrittenCard,
  spec: CardSpec,
  sourceText: string,
): FinalizedCard {
  const voiced = applyVoice(card, spec);
  const cleaned = voiced.messages.map(cleanMessage).filter((m): m is string =>
    m !== null
  );
  if (cleaned.length === 0) {
    return { ok: false, reason: "empty_after_cleanup" };
  }
  // 檢查整理前後兩份：簡轉繁會改詞（「用戶」→「使用者」），可能讓原文的禁語或
  // 外洩片段對不上。脅迫樣式只認「你」，照他口吻的卡可能寫「妳」，掃描時一併換掉。
  const scanned = [...cleaned, ...card.messages].map((m) =>
    m.replaceAll("妳", "你")
  );
  // v2 推薦卡的英文樣式（跟蹤、施壓、提示詞注入）也一併查。
  if (
    isBlockedOutgoingCard(scanned) ||
    scanned.some((m) => hasUnsafeRecommendation(m))
  ) return { ok: false, reason: "unsafe" };
  const joined = cleaned.join("\n");
  const rawJoined = card.messages.join("\n");
  if (
    leaksPrompt(joined) || leaksPrompt(rawJoined) ||
    hasPromptInjection(joined) || hasPromptInjection(rawJoined)
  ) {
    return { ok: false, reason: "prompt_leak" };
  }
  // 只拿掉「整則是英文」的卡：沒有漢字、又有兩個以上沒來源的英文詞。夾在中文裡的
  // 英文詞（相機型號、offer）在過去 896 張黑箱卡裡有 10 張，全是正常的卡，只記錄。
  const latin = findUnsupportedLatinTokens(joined, sourceText);
  if (
    cleaned.some((m) =>
      !HAN.test(m) && findUnsupportedLatinTokens(m, sourceText).length >= 2
    )
  ) {
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

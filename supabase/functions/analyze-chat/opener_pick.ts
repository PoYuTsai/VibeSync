// 開場救星結構刀 P3「另外挑」（需求凍結 §4.3）：寫手不再替自己排名。
// 伺服器只用確定、逐字可判的規則：紅線（veto）不可交付；句型與長度只降級。
// 語意品質（重述、硬抓共同點、捏造自述）不在這裡用 regex 猜——那是規劃的輸入
// 結構與離線評審的工作。

import { normalizeOutgoingMessageText } from "./outgoing_message_text.ts";
import { FIRST_PERSON_FACT_RE, OPENER_TYPES, type OpenerType, buildOpenerAccess, type StretchLevel } from "./opener_payload.ts";
import type { OpenerInputState } from "./opener_material.ts";
import type { OpenerGenerateLedgerResult } from "./opener_flow_payload.ts";
import { approachStillApplies, graphemeLength, type OpenerAnalysisSnapshot } from "./opener_stage.ts";
import type { OpenerPlan, OpenerPlanDigest } from "./opener_plan.ts";
import { OPENER_LENGTH_LIMIT, OPENER_SHORT_LENGTH_LIMIT, type OpenerWriterArm } from "./opener_write.ts";

export type OpenerVeto = "blocked_span_reused" | "excluded_topic";
export type OpenerDemotion = "two_questions" | "too_long" | "profile_copy" | "self_claim_unsourced" | "self_first" | "foreign_token";

export interface OpenerCardVerdict {
  vetoes: OpenerVeto[];
  demotions: OpenerDemotion[];
}

export interface OpenerCardRules {
  blockedQuotes: readonly string[];
  excludedTerms: readonly string[];
  selfFactsAllowed: boolean;
  /** 她的自介原文（重現偵測用）。 */
  profileText: string;
  shorter: boolean;
  /** 她的資料＋用戶補充全文：卡片裡的英文字不在這裡面＝寫手憑空冒出來的。 */
  inputText?: string;
}

/** 她自介裡連續這麼多個字被原樣搬進卡片＝重現原句（降級，不擋）。 */
export const PROFILE_COPY_MIN_CHARS = 6;

const WORD_CHAR_RE = /[\p{L}\p{N}]/u;

/** 卡片裡最長一段逐字出自她自介的字（只算文字與數字，標點空白不算）。 */
export function longestProfileCopy(card: string, profile: string): number {
  const a = [...card].filter((ch) => WORD_CHAR_RE.test(ch));
  const b = [...profile].filter((ch) => WORD_CHAR_RE.test(ch));
  let best = 0;
  let prev = new Array(b.length + 1).fill(0);
  for (let i = 1; i <= a.length; i++) {
    const cur = new Array(b.length + 1).fill(0);
    for (let j = 1; j <= b.length; j++) {
      if (a[i - 1] === b[j - 1]) {
        cur[j] = prev[j - 1] + 1;
        if (cur[j] > best) best = cur[j];
      }
    }
    prev = cur;
  }
  return best;
}

/** Bruce 9/26：不用 emoji。確定可判就直接拿掉（降級會把最好的那句換成別張）；拿完沒字回 null。 */
export function withoutEmoji(text: string): string | null {
  const out = text.replace(/[\p{Extended_Pictographic}\p{Regional_Indicator}\u200d\ufe0f\u20e3]/gu, "").replace(/[ \t]{2,}/g, " ").trim();
  return out || null;
}

/** 紅線比對兩邊用同一套正規化（簡轉繁、你→妳、標點），再去掉空白與標點。 */
export function vetoKey(text: string): string {
  return (normalizeOutgoingMessageText(text) ?? text).replace(/[\s\p{P}\p{S}]/gu, "").toLowerCase();
}

export function containsVetoed(text: string, needles: readonly string[]): boolean {
  const hay = vetoKey(text);
  return needles.some((needle) => {
    const key = vetoKey(needle);
    return key.length > 0 && hay.includes(key);
  });
}

/** 一則要她回答幾次：連續問號（？？）算一次。 */
export function questionCount(text: string): number {
  return (text.match(/[?？]+/gu) ?? []).length;
}

/** 長度：英文單字算一個字（graphemes 逐字母算會把一個單字算成七八個字）。 */
export function openerLength(text: string): number {
  return graphemeLength(text.replace(/[A-Za-z]+/g, "a"));
}

export function judgeOpenerCard(text: string, rules: OpenerCardRules): OpenerCardVerdict {
  const vetoes: OpenerVeto[] = [];
  const demotions: OpenerDemotion[] = [];
  if (containsVetoed(text, rules.blockedQuotes)) vetoes.push("blocked_span_reused");
  if (containsVetoed(text, rules.excludedTerms)) vetoes.push("excluded_topic");
  if (questionCount(text) >= 2) demotions.push("two_questions");
  if (openerLength(text) > (rules.shorter ? OPENER_SHORT_LENGTH_LIMIT : OPENER_LENGTH_LIMIT)) demotions.push("too_long");
  if (rules.profileText && longestProfileCopy(text, rules.profileText) >= PROFILE_COPY_MIN_CHARS) demotions.push("profile_copy");
  // 句式標記，不判語意：沒有准用自述卻出現「我也／我家／我以前…」只降級（寫手本來就沒收到自述）。
  if (!rules.selfFactsAllowed && FIRST_PERSON_FACT_RE.test(text)) demotions.push("self_claim_unsourced");
  // Bruce 9/23：自己的事放在問完她之後，開頭就講自己＝抓共同點當資格（句首位置，不判語意）。
  // 句首可以有標點、表情或語助詞；「我好奇／我想問」是在問她，不是自述。
  if (/^[\p{P}\p{S}\s]*(?:欸|哈+|嗨|其實|說真的)?[，,\s]*我(?!(?:猜|好奇|很好奇|想問|在想|想知道))/u.test(text)) demotions.push("self_first");
  if (rules.inputText !== undefined) {
    const input = rules.inputText.normalize("NFKC").toLowerCase();
    const words = text.normalize("NFKC").match(/[A-Za-z]{3,}/g) ?? [];
    if (words.some((word) => !input.includes(word.toLowerCase()))) demotions.push("foreign_token");
  }
  return { vetoes, demotions };
}

export function demotionScore(verdict: OpenerCardVerdict): number {
  return verdict.demotions.length;
}

/**
 * 挑推薦：可見、有句子、沒有紅線的卡裡，降級分數最低者；同分依偏好順序：
 * 用戶要好笑→幽默、調情（B 臂只有幽默＝輕鬆一點；tease 在 B 臂是換個方向，不是好笑）；
 * 再來規劃提名／寫手的推薦卡（冷讀除外：冷讀永遠排最後）；最後固定順序。
 */
export function pickOpenerCard(input: {
  openers: Partial<Record<OpenerType, string>>;
  verdicts: Partial<Record<OpenerType, OpenerCardVerdict>>;
  visibleTypes: readonly OpenerType[];
  primaryStyle: OpenerType;
  funny: boolean;
  arm?: OpenerWriterArm;
  /** 方向＋範例卡：範例要用戶換成自己的經驗，不能當推薦原封送出。 */
  exclude?: readonly OpenerType[];
}): OpenerType | null {
  const preference: OpenerType[] = [];
  const push = (t: OpenerType) => {
    if (!preference.includes(t)) preference.push(t);
  };
  if (input.funny) (input.arm === "free" ? ["humor"] : ["humor", "tease"]).forEach((t) => push(t as OpenerType));
  if (input.primaryStyle !== "coldRead") push(input.primaryStyle);
  OPENER_TYPES.forEach(push);
  const candidates = preference.filter((t) =>
    input.visibleTypes.includes(t) && input.openers[t] && (input.verdicts[t]?.vetoes.length ?? 0) === 0 && !input.exclude?.includes(t)
  );
  if (!candidates.length) return null;
  const score = (t: OpenerType) => input.verdicts[t] ? demotionScore(input.verdicts[t]!) : 0;
  return candidates.reduce((best, t) => (score(t) < score(best) ? t : best), candidates[0]);
}

// ── 伺服器模板（確定性說明；不交給模型）──────────────────────────────────

export function inviteDeferralNote(topic: string | null): string {
  return topic ? `這句先從「${topic}」開聊，邀約等她回應熱絡再提。` : "這句先開話題，邀約等她回應熱絡再提。";
}


export const HANDLING_NOTE = {
  blocked: "那段字眼不適合放進開場，這次先照她的資料寫。",
  blockedWithIdeas: "那段字眼不適合放進開場，其餘照你的想法寫。",
  noise: "這段看不出想聊什麼，先照她的資料寫。",
  unread: "這次沒讀到你的補充，先照她的資料寫。",
} as const;

function adoptionDisplayNote(digest: OpenerPlanDigest): string | null {
  const first = digest.adopted[0];
  if (!first) return null;
  // 用用戶自己的原話（不是規劃的讀法）；依字元截斷，不切壞 emoji。
  const chars = [...first.quote];
  const text = chars.length > 16 ? `${chars.slice(0, 16).join("")}…` : first.quote;
  switch (first.role) {
    case "question":
      return `這句接的是你想問的：${text}`;
    case "draft_message":
      return "這句是照你想傳的草稿潤飾的。";
    case "interest":
      return `這句從你想聊的「${text}」開始。`;
    default:
      return `這句接的是你想聊的：${text}`;
  }
}

/** 推薦卡是寫手照計畫寫的推薦那一則（沒被改寫、沒換成別張）才能具名說接了哪件事。 */
function pickIsPlannedPrimary(input: { plan: OpenerPlan; pick: OpenerType; primaryStyle: OpenerType; rewrittenStyles: readonly OpenerType[] }): boolean {
  return input.plan.source === "model" && input.pick === input.primaryStyle && !input.rewrittenStyles.includes(input.pick);
}

function traceFor(input: {
  inputState: OpenerInputState;
  digest: OpenerPlanDigest;
  plan: OpenerPlan;
  pick: OpenerType;
  pickText: string;
  primaryStyle: OpenerType;
  rewrittenStyles: readonly OpenerType[];
}): { traceStatus: OpenerGenerateLedgerResult["materialUse"]["traceStatus"]; displayNote: string | null } {
  if (input.inputState !== "answered") return { traceStatus: "no_input", displayNote: null };
  const note = adoptionDisplayNote(input.digest);
  // 還要推薦句與那個想法至少有兩個字相同，才說「這句接的是…」（只影響說明，不影響交付）。
  const first = input.digest.adopted[0];
  const shares = first !== undefined && longestProfileCopy(input.pickText, first.text) >= 2;
  if (note && shares && pickIsPlannedPrimary(input)) return { traceStatus: "matched", displayNote: note };
  return { traceStatus: "uncertain", displayNote: null };
}

export function handlingNoteFor(plan: OpenerPlan, digest: OpenerPlanDigest, hadFreeText: boolean): string | null {
  if (digest.hasBlocked) return digest.adopted.length || digest.selfFacts.length ? HANDLING_NOTE.blockedWithIdeas : HANDLING_NOTE.blocked;
  if (digest.noiseOnly) return HANDLING_NOTE.noise;
  if (hadFreeText && plan.source === "profile_only") return HANDLING_NOTE.unread;
  return null;
}

export function profileAnalysisFromSnapshot(
  snapshot: OpenerAnalysisSnapshot,
  plan: OpenerPlan,
  digest: OpenerPlanDigest,
  freeText: string | null,
): Record<string, unknown> | null {
  const hooks = plan.anchorCueIds
    .map((id) => snapshot.cues.find((c) => c.id === id)?.label)
    .filter((label): label is string => !!label);
  const applies = approachStillApplies(snapshot, freeText);
  const avoid = [...(applies ? snapshot.approach.avoid : []), ...digest.excludedTerms.map((t) => `不聊${t}`)];
  const out: Record<string, unknown> = {};
  if (hooks.length) out.positiveHooks = hooks;
  if (avoid.length) out.avoidTopics = avoid.slice(0, 4);
  if (applies && snapshot.approach.summary) out.openingStrategy = snapshot.approach.summary;
  return Object.keys(out).length ? out : null;
}

function directionsFor(directions: Partial<Record<OpenerType, string>> | undefined, openers: Partial<Record<OpenerType, string>>) {
  const kept = Object.fromEntries(Object.entries(directions ?? {}).filter(([type]) => openers[type as OpenerType]));
  return Object.keys(kept).length ? { directions: kept as Partial<Record<OpenerType, string>> } : {};
}

/** 可交付的卡 → 既有 ledger 形狀（SQL 白名單、回傳形狀、App 解析都不變）。 */
export function projectPlanWriteResult(input: {
  openers: Partial<Record<OpenerType, string>>;
  cardReasons: Partial<Record<OpenerType, string>>;
  pioneerPlan: Record<string, string> | null;
  pick: OpenerType;
  primaryStyle: OpenerType;
  visibleTypes: readonly OpenerType[];
  servedTier: string;
  contractVersion: 1 | 2;
  inputState: OpenerInputState;
  plan: OpenerPlan;
  digest: OpenerPlanDigest;
  snapshot: OpenerAnalysisSnapshot;
  freeText: string | null;
  rewrittenStyles: readonly OpenerType[];
  /** 2＝一句推薦＋四句備選（新版 App 依此顯示新標籤）；沒給＝五風格。 */
  cardSet?: 2;
  /** 方向＋範例卡：類型 → 給用戶的方向；App 依此把那張句子標成範例。 */
  directions?: Partial<Record<OpenerType, string>>;
}): OpenerGenerateLedgerResult {
  const openers: Partial<Record<OpenerType, string>> = {};
  const cardReasons: Partial<Record<OpenerType, string>> = {};
  const stretchLevels: Partial<Record<OpenerType, StretchLevel>> = {};
  for (const type of input.visibleTypes) {
    const text = input.openers[type];
    if (!text) continue;
    openers[type] = text;
    stretchLevels[type] = "within";
    const reason = input.cardReasons[type];
    if (reason) cardReasons[type] = reason;
  }
  const baseReason = cardReasons[input.pick];
  // 邀約說明一套文案（Eric 9/25：不約、不見面看階段，Opener 只負責開場）；推薦句逐字有那個活動才具名「從 X 開聊」，
  // 否則用通用說明，不宣稱沒寫進句子的話題。
  const pickText = openers[input.pick] ?? "";
  const topicKey = input.digest.inviteTopic ? vetoKey(input.digest.inviteTopic) : "";
  // 至少兩個文字或數字才具名：單一個字（「跑」）或純 emoji（ZWJ、變體選擇符不算字）會在不相干的句子裡對到。
  const topic = (topicKey.match(/[\p{L}\p{N}]/gu) ?? []).length >= 2 && vetoKey(pickText).includes(topicKey) ? input.digest.inviteTopic : null;
  const reason = input.digest.inviteRequested ? [baseReason, inviteDeferralNote(topic)].filter(Boolean).join(" ") : baseReason;
  if (reason) cardReasons[input.pick] = reason;
  const trace = traceFor({ ...input, pickText });
  const handlingNote = handlingNoteFor(input.plan, input.digest, input.freeText !== null);
  // 五風格臂（production 只剩評測用：舊版 App 旗標開也走舊路徑）沒有處理提示欄的 App 只顯示推薦理由，
  // 併進推薦理由，補充沒讀到或被擋時用戶才看得到。
  const shownReason = !input.cardSet && handlingNote ? [reason, handlingNote].filter(Boolean).join(" ") : reason;
  const profileAnalysis = profileAnalysisFromSnapshot(input.snapshot, input.plan, input.digest, input.freeText);
  const result: OpenerGenerateLedgerResult = {
    openers,
    recommendation: shownReason ? { pick: input.pick, reason: shownReason } : { pick: input.pick },
    cardReasons,
    access: {
      ...buildOpenerAccess({ contractVersion: input.contractVersion, servedTier: input.servedTier, visibleTypes: input.visibleTypes }),
      ...(input.cardSet ? { cardSet: input.cardSet } : {}),
      ...(directionsFor(input.directions, openers)),
    },
    materialUse: {
      inputState: input.inputState,
      references: [],
      traceStatus: trace.traceStatus,
      displayNote: trace.displayNote,
      ...(handlingNote ? { handlingNote } : {}),
    },
    stretchLevels,
    recommendedPick: input.pick,
  };
  if (shownReason) result.recommendedReason = shownReason;
  if (input.pioneerPlan) result.pioneerPlan = input.pioneerPlan;
  if (profileAnalysis) result.profileAnalysis = profileAnalysis;
  return result;
}

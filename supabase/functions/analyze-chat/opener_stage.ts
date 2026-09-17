// 開場救星兩段式（先分析、再讓用戶補充、按生成才第二段）的合約層：
// 版本常數、兩段請求驗證、第一段模型輸出→伺服器快照的清洗、第二段回答對快照的
// 驗證。全部純函式，不碰 DB／模型（handler 在 opener_flow_handler.ts）。
//
// 三個識別碼各管一件事（附件 §10.1）：analysisRequestId＝按「分析」的操作、
// sessionId＝伺服器發的一局、generationId＝按「生成回覆」的操作。
// 第二段不信任 App 傳回的分析內容——快照只從伺服器讀。

import { isPlainObject } from "../_shared/quota.ts";
import { sanitizeCustomerExplanationText } from "./customer_explanation.ts";
import {
  type NormalizedOpenerProfile,
  normalizeOpenerProfileInfo,
} from "./opener_profile.ts";

export const OPENER_FLOW_VERSION = 1;
export const OPENER_FLOW_PROMPT_VERSION = "opener-two-stage-prompt-v1";
export const OPENER_SESSION_TTL_SECONDS = 24 * 60 * 60;
export const OPENER_INCLUDED_GENERATION_COUNT = 3;
export const OPENER_FIRST_GENERATION_COST = 3;
export const OPENER_FREE_TEXT_MAX_GRAPHEMES = 300;
export const OPENER_ANALYSIS_LEASE_SECONDS = 65;
export const OPENER_GENERATION_LEASE_SECONDS = 65;
export const OPENER_MAX_CUES = 3;
export const OPENER_MAX_AVOID = 2;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function normalizeOpenerFlowUuid(value: unknown): string | null {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) return null;
  return value.toLowerCase();
}

// 中文字、emoji、300 字邊界（F20）：App 端 LengthLimitingTextInputFormatter
// 數的是 grapheme cluster，伺服器用 Intl.Segmenter 同一種算法，不用 UTF-16
// code unit 造成「App 放行、伺服器拒絕」或反過來。
const graphemeSegmenter = new Intl.Segmenter("zh-Hant", { granularity: "grapheme" });
export function graphemeLength(text: string): number {
  let count = 0;
  for (const _ of graphemeSegmenter.segment(text)) count += 1;
  return count;
}

// ── 快照形狀 ──────────────────────────────────────────────────────────────

export const OPENER_APPROACH_MODES = ["anchor_hooks", "fresh_topic", "low_info"] as const;
export type OpenerApproachMode = typeof OPENER_APPROACH_MODES[number];

export const OPENER_CUE_SOURCES = ["profile_text", "image", "manual_field"] as const;
export type OpenerCueSource = typeof OPENER_CUE_SOURCES[number];

export const OPENER_QUESTION_AFFECTS = ["material", "sender_fact", "direction"] as const;
export type OpenerQuestionAffects = typeof OPENER_QUESTION_AFFECTS[number];

/**
 * 選項語意白名單（附件 §10.3）：由受控規則決定，不讓模型任意創建會授權新
 * 事實的類型。只有 assert_sender_fact 在用戶選中後才成為本次自述。
 */
export const OPENER_OPTION_MEANINGS = [
  "pick_cue",
  "assert_sender_fact",
  "curious_without_experience",
  "exclude_cue",
  "change_direction",
  "no_preference",
] as const;
export type OpenerOptionMeaning = typeof OPENER_OPTION_MEANINGS[number];

export interface OpenerCueEvidence {
  field?: "name" | "bio" | "interests" | "meetingContext";
  quote?: string;
  imageIndex?: number;
  visible?: string;
}

export interface OpenerCue {
  id: string;
  label: string;
  source: OpenerCueSource;
  subject: "recipient";
  evidence?: OpenerCueEvidence;
}

export interface OpenerQuestionOption {
  id: string;
  label: string;
  meaning: OpenerOptionMeaning;
  statement?: string;
  cueId?: string;
}

export interface OpenerQuestion {
  id: string;
  affects: OpenerQuestionAffects;
  text: string;
  options: OpenerQuestionOption[];
}

export interface OpenerApproach {
  mode: OpenerApproachMode;
  summary: string;
  avoid: string[];
}

/** 伺服器保存的分析快照（不含圖片、不含用戶補充原文）。 */
export interface OpenerAnalysisSnapshot {
  approach: OpenerApproach;
  cues: OpenerCue[];
  question: OpenerQuestion | null;
  /** 第二段不重傳圖片：第一段把可見事實整理成文字摘要（≤1200 字）。 */
  profileDigest: string;
  /** 手填欄位原文（第二段引用逐字原句用）。 */
  profileText: NormalizedOpenerProfile;
  imageCount: number;
  /** 只記「當時有沒有寫初稿」，不存原文——刪掉的初稿不得從快照復活。 */
  initialNoteProvided: boolean;
  /**
   * 初稿指紋（非密碼學 FNV-1a，只做相等比對）。第一段的 approach.summary／avoid
   * 可能依初稿而寫；第二段只有在目前補充與初稿完全相同時才沿用它們（R3b）。
   */
  initialNoteFingerprint: string | null;
  promptVersion: string;
}

/** 初稿／補充的相等指紋：正規化空白後 FNV-1a 64 位元；不可逆向、不存原文。 */
export function noteFingerprint(text: string): string {
  const normalized = text.replace(/\s+/g, " ").trim();
  let hash = 0xcbf29ce484222325n;
  for (const ch of normalized) {
    hash ^= BigInt(ch.codePointAt(0) ?? 0);
    hash = (hash * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  return hash.toString(16).padStart(16, "0");
}

/**
 * 第一段方向文字（summary／avoid）還適不適用：沒有初稿→適用；有初稿→只有目前
 * 補充與初稿相同才適用。刪掉或改寫初稿後，依初稿衍生的方向不得當底稿。
 */
export function approachStillApplies(snapshot: OpenerAnalysisSnapshot, freeText: string | null): boolean {
  if (!snapshot.initialNoteProvided) return true;
  if (!snapshot.initialNoteFingerprint) return false;
  if (!freeText) return false;
  return noteFingerprint(freeText) === snapshot.initialNoteFingerprint;
}

// ── 第一段請求 ────────────────────────────────────────────────────────────

export type OpenerAnalyzeRequestParse =
  | {
    ok: true;
    request: {
      analysisRequestId: string;
      contractVersion: 1 | 2;
      initialUserNote: string | null;
    };
  }
  | { ok: false; code: "OPENER_FLOW_VERSION_INVALID" | "OPENER_ANALYSIS_REQUEST_ID_INVALID" | "OPENER_CONTRIBUTION_INVALID"; message: string };

export function parseOpenerFlowVersion(raw: unknown): boolean {
  return raw === OPENER_FLOW_VERSION;
}

export function normalizeFreeText(raw: unknown): { ok: true; text: string | null } | { ok: false; message: string } {
  if (raw == null) return { ok: true, text: null };
  if (typeof raw !== "string") return { ok: false, message: "補充內容必須是文字" };
  const trimmed = raw.trim();
  if (!trimmed) return { ok: true, text: null };
  const length = graphemeLength(trimmed);
  if (length > OPENER_FREE_TEXT_MAX_GRAPHEMES) {
    return {
      ok: false,
      message: `補充內容最多 ${OPENER_FREE_TEXT_MAX_GRAPHEMES} 字（目前 ${length} 字），已保留你的文字，請縮短後再送`,
    };
  }
  return { ok: true, text: trimmed };
}

export function parseOpenerAnalyzeRequest(input: {
  rawFlowVersion: unknown;
  rawAnalysisRequestId: unknown;
  rawInitialUserNote: unknown;
  contractVersion: 1 | 2;
}): OpenerAnalyzeRequestParse {
  if (!parseOpenerFlowVersion(input.rawFlowVersion)) {
    return {
      ok: false,
      code: "OPENER_FLOW_VERSION_INVALID",
      message: "App 版本資訊異常，請更新 App 後再試。本次不會扣額度。",
    };
  }
  const analysisRequestId = normalizeOpenerFlowUuid(input.rawAnalysisRequestId);
  if (analysisRequestId === null) {
    return {
      ok: false,
      code: "OPENER_ANALYSIS_REQUEST_ID_INVALID",
      message: "分析請求編號異常，請重新分析一次。本次不會扣額度。",
    };
  }
  const note = normalizeFreeText(input.rawInitialUserNote);
  if (!note.ok) {
    return { ok: false, code: "OPENER_CONTRIBUTION_INVALID", message: note.message };
  }
  return {
    ok: true,
    request: {
      analysisRequestId,
      contractVersion: input.contractVersion,
      initialUserNote: note.text,
    },
  };
}

// ── 第一段模型輸出 → 快照 ──────────────────────────────────────────────────

function textField(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.length > max ? trimmed.slice(0, max) : trimmed;
}

/** 客戶可見文字：擋內部術語外洩、轉繁體；超長裁切而不是整份作廢。 */
function customerText(value: unknown, max: number): string | null {
  const text = sanitizeCustomerExplanationText(value, 4000);
  if (text === null) return null;
  return text.length > max ? text.slice(0, max) : text;
}

/** 文字來源的引文必須逐字在該欄位原文裡；對不上就丟引文、留欄位。 */
function sanitizeCueEvidence(
  raw: unknown,
  source: OpenerCueSource,
  profile: NormalizedOpenerProfile,
  imageCount: number,
): OpenerCueEvidence | undefined {
  if (!isPlainObject(raw)) return undefined;
  if (source === "image") {
    const idx = typeof raw.imageIndex === "number" && Number.isInteger(raw.imageIndex)
      ? raw.imageIndex
      : null;
    if (idx === null || idx < 1 || idx > imageCount) return undefined;
    const visible = textField(raw.visible, 120);
    return visible ? { imageIndex: idx, visible } : { imageIndex: idx };
  }
  const field = raw.field;
  if (field !== "name" && field !== "bio" && field !== "interests" && field !== "meetingContext") {
    return undefined;
  }
  const fieldText = profile[field];
  if (!fieldText) return undefined;
  const quote = textField(raw.quote, 120);
  if (quote && fieldText.includes(quote)) return { field, quote };
  return { field };
}

function sanitizeCues(
  raw: unknown,
  profile: NormalizedOpenerProfile,
  imageCount: number,
): { cues: OpenerCue[]; idMap: Map<string, string> } {
  const cues: OpenerCue[] = [];
  // 模型端的 cue id（或依位置的 cue_n）→ 清洗後的新 id；線索被丟掉時對應消失。
  const idMap = new Map<string, string>();
  if (!Array.isArray(raw)) return { cues, idMap };
  const seenLabels = new Set<string>();
  raw.forEach((item, index) => {
    if (cues.length >= OPENER_MAX_CUES) return;
    if (!isPlainObject(item)) return;
    const label = customerText(item.label, 24);
    if (!label || seenLabels.has(label)) return;
    const source = (OPENER_CUE_SOURCES as readonly string[]).includes(item.source as string)
      ? item.source as OpenerCueSource
      : null;
    if (source === null) return;
    if (source === "image" && imageCount === 0) return;
    if (source !== "image" && !profile.bio && !profile.interests && !profile.name && !profile.meetingContext) {
      return;
    }
    seenLabels.add(label);
    const evidence = sanitizeCueEvidence(item.evidence, source, profile, imageCount);
    const id = `cue_${cues.length + 1}`;
    if (typeof item.id === "string" && item.id.trim()) idMap.set(item.id.trim(), id);
    idMap.set(`cue_${index + 1}`, id);
    cues.push({
      id,
      label,
      source,
      subject: "recipient",
      ...(evidence ? { evidence } : {}),
    });
  });
  return { cues, idMap };
}

function meaningNeedsCue(meaning: OpenerOptionMeaning): boolean {
  return meaning === "pick_cue" || meaning === "curious_without_experience" ||
    meaning === "exclude_cue";
}

/**
 * 題目與選項的受控清洗（附件 §10.3）：meaning 只認白名單、需要 cueId 的
 * 語意必須指向本局線索、assert_sender_fact 必帶第一人稱 statement 且不談她；
 * 清洗後不足 2 個選項＝這題不值得問，回 null（零題是合法結果）。
 */
const NEGATION_RE = /沒|不|無|未|其實|別的|還好/u;
const NON_SELF_SUBJECT_RE = /^我(妹|哥|姐|弟|媽|爸|爺|奶|朋友|同事|家人|室友|前任|們|的(妹|哥|姐|弟|媽|爸|朋友|同事|家人|室友))/u;

/** R3a：assert_sender_fact 的標籤／statement／線索三者要一致，且主體是本人。 */
export function senderFactOptionConsistent(label: string, statement: string, cueLabel: string | undefined): boolean {
  if (NEGATION_RE.test(label) || NEGATION_RE.test(statement)) return false;
  if (!/^我/u.test(statement) || NON_SELF_SUBJECT_RE.test(statement)) return false;
  if (/她|妳|對方/u.test(statement)) return false;
  if (!/我|自己/u.test(label)) return false;
  if (cueLabel) {
    const compact = cueLabel.replace(/[\s、，,]/g, "");
    let overlap = compact.length <= 1 ? statement.includes(compact) : false;
    for (let i = 0; !overlap && i + 2 <= compact.length; i++) {
      if (statement.includes(compact.slice(i, i + 2))) overlap = true;
    }
    if (!overlap) return false;
  }
  return true;
}

function sanitizeQuestion(raw: unknown, cueIdMap: Map<string, string>, cueLabelById: Map<string, string>): OpenerQuestion | null {
  if (!isPlainObject(raw)) return null;
  const text = customerText(raw.text, 60);
  if (!text) return null;
  const affects = (OPENER_QUESTION_AFFECTS as readonly string[]).includes(raw.affects as string)
    ? raw.affects as OpenerQuestionAffects
    : "material";
  if (!Array.isArray(raw.options)) return null;
  const options: OpenerQuestionOption[] = [];
  const seenMeaningCue = new Set<string>();
  for (const item of raw.options) {
    if (options.length >= 4) break;
    if (!isPlainObject(item)) continue;
    const label = customerText(item.label, 20);
    if (!label) continue;
    const meaning = (OPENER_OPTION_MEANINGS as readonly string[]).includes(item.meaning as string)
      ? item.meaning as OpenerOptionMeaning
      : null;
    if (meaning === null) continue;
    const cueId = typeof item.cueId === "string" ? cueIdMap.get(item.cueId.trim()) : undefined;
    if (meaningNeedsCue(meaning) && !cueId) continue;
    let statement: string | undefined;
    if (meaning === "assert_sender_fact") {
      const candidate = textField(item.statement, 40);
      // R3a：白名單類型不等於 statement 與題目、選項相符。只有「標籤是肯定的
      // 本人自述、statement 是肯定的本人自述、且談的是同一個線索」才授權新自述；
      // 矛盾（標籤「沒養，但有興趣」配「我有養狗」）或主體不是本人（「我妹有養狗」）
      // 一律丟掉，不改成凡有「我」就是本人事實。
      if (!candidate || !senderFactOptionConsistent(label, candidate, cueId ? cueLabelById.get(cueId) : undefined)) continue;
      statement = candidate;
    }
    const dedupeKey = `${meaning}:${cueId ?? ""}:${statement ?? ""}`;
    if (seenMeaningCue.has(dedupeKey)) continue;
    seenMeaningCue.add(dedupeKey);
    options.push({
      id: `option_${options.length + 1}`,
      label,
      meaning,
      ...(statement ? { statement } : {}),
      ...(meaningNeedsCue(meaning) || (meaning === "assert_sender_fact" && cueId) ? { cueId } : {}),
    });
  }
  if (options.length < 2) return null;
  return { id: "question_1", affects, text, options };
}

export function buildOpenerAnalysisSnapshot(input: {
  parsed: Record<string, unknown> | null;
  rawProfileInfo: unknown;
  imageCount: number;
  initialUserNote: string | null;
}): OpenerAnalysisSnapshot | null {
  const parsed = input.parsed;
  if (!parsed) return null;
  const profile = normalizeOpenerProfileInfo(input.rawProfileInfo);
  const approachRaw = isPlainObject(parsed.approach) ? parsed.approach : null;
  const summary = customerText(approachRaw?.summary, 120);
  if (!summary) return null;
  const { cues, idMap } = sanitizeCues(parsed.cues, profile, input.imageCount);
  const modeRaw = approachRaw?.mode;
  let mode: OpenerApproachMode = (OPENER_APPROACH_MODES as readonly string[]).includes(modeRaw as string)
    ? modeRaw as OpenerApproachMode
    : "low_info";
  // 沒有任何可接線索就不能宣稱 anchor_hooks。
  if (mode === "anchor_hooks" && cues.length === 0) mode = "low_info";
  const avoid = Array.isArray(approachRaw?.avoid)
    ? approachRaw!.avoid
      .map((item) => customerText(item, 60))
      .filter((item): item is string => item !== null)
      .slice(0, OPENER_MAX_AVOID)
    : [];
  const digest = textField(parsed.profileDigest, 1200) ?? "";
  return {
    approach: { mode, summary, avoid },
    cues,
    question: sanitizeQuestion(parsed.question, idMap, new Map(cues.map((cue) => [cue.id, cue.label]))),
    profileDigest: digest,
    profileText: profile,
    imageCount: input.imageCount,
    initialNoteProvided: input.initialUserNote !== null,
    initialNoteFingerprint: input.initialUserNote === null ? null : noteFingerprint(input.initialUserNote),
    promptVersion: OPENER_FLOW_PROMPT_VERSION,
  };
}

/** 從 DB 讀回的快照做防禦式解析（不是模型輸出，只擋壞資料）。 */
export function parseStoredOpenerAnalysisSnapshot(raw: unknown): OpenerAnalysisSnapshot | null {
  if (!isPlainObject(raw)) return null;
  const approach = raw.approach;
  const cues = raw.cues;
  if (!isPlainObject(approach) || !Array.isArray(cues)) return null;
  if (typeof approach.summary !== "string") return null;
  const profileText = isPlainObject(raw.profileText)
    ? normalizeOpenerProfileInfo(raw.profileText)
    : {};
  return {
    approach: {
      mode: (OPENER_APPROACH_MODES as readonly string[]).includes(approach.mode as string)
        ? approach.mode as OpenerApproachMode
        : "low_info",
      summary: approach.summary,
      avoid: Array.isArray(approach.avoid) ? approach.avoid.filter((x): x is string => typeof x === "string") : [],
    },
    cues: cues.filter((cue): cue is OpenerCue =>
      isPlainObject(cue) && typeof cue.id === "string" && typeof cue.label === "string"
    ),
    question: isPlainObject(raw.question) && typeof raw.question.id === "string" &&
        Array.isArray(raw.question.options)
      ? raw.question as unknown as OpenerQuestion
      : null,
    profileDigest: typeof raw.profileDigest === "string" ? raw.profileDigest : "",
    profileText,
    imageCount: typeof raw.imageCount === "number" ? raw.imageCount : 0,
    initialNoteProvided: raw.initialNoteProvided === true,
    initialNoteFingerprint: typeof raw.initialNoteFingerprint === "string" ? raw.initialNoteFingerprint : null,
    promptVersion: typeof raw.promptVersion === "string" ? raw.promptVersion : "unknown",
  };
}

/** 回給 App 的第一段內容：不含 profileDigest／profileText（App 不需要、也不能回傳當事實）。 */
export function projectAnalysisForClient(snapshot: OpenerAnalysisSnapshot): {
  approach: OpenerApproach;
  cues: OpenerCue[];
  question: OpenerQuestion | null;
} {
  return { approach: snapshot.approach, cues: snapshot.cues, question: snapshot.question };
}

// ── 第二段請求：用戶回答 ───────────────────────────────────────────────────

export const OPENER_CONTRIBUTION_STATES = ["answered", "skipped", "no_answer"] as const;
export type OpenerContributionState = typeof OPENER_CONTRIBUTION_STATES[number];

export interface OpenerContribution {
  state: OpenerContributionState;
  questionId: string | null;
  selectedOptionId: string | null;
  freeText: string | null;
}

export type OpenerGenerateRequestParse =
  | {
    ok: true;
    request: {
      sessionId: string;
      analysisRevision: number;
      generationId: string;
      contribution: OpenerContribution;
    };
  }
  | {
    ok: false;
    code: "OPENER_FLOW_VERSION_INVALID" | "OPENER_SESSION_INVALID" | "OPENER_GENERATION_ID_INVALID" | "OPENER_CONTRIBUTION_INVALID";
    message: string;
  };

/** 請求形狀層驗證（不看快照）：狀態與欄位的一致性、300 字上限。 */
export function parseOpenerGenerateRequest(input: {
  rawFlowVersion: unknown;
  rawSessionId: unknown;
  rawAnalysisRevision: unknown;
  rawGenerationId: unknown;
  rawContribution: unknown;
}): OpenerGenerateRequestParse {
  if (!parseOpenerFlowVersion(input.rawFlowVersion)) {
    return { ok: false, code: "OPENER_FLOW_VERSION_INVALID", message: "App 版本資訊異常，請更新 App 後再試。本次不會扣額度。" };
  }
  const sessionId = normalizeOpenerFlowUuid(input.rawSessionId);
  if (sessionId === null) {
    return { ok: false, code: "OPENER_SESSION_INVALID", message: "找不到這份分析，請重新分析。本次不會扣額度。" };
  }
  const revision = input.rawAnalysisRevision;
  if (typeof revision !== "number" || !Number.isInteger(revision) || revision < 1) {
    return { ok: false, code: "OPENER_SESSION_INVALID", message: "找不到這份分析，請重新分析。本次不會扣額度。" };
  }
  const generationId = normalizeOpenerFlowUuid(input.rawGenerationId);
  if (generationId === null) {
    return { ok: false, code: "OPENER_GENERATION_ID_INVALID", message: "生成請求編號異常，請重新送出。本次不會扣額度。" };
  }
  const raw = input.rawContribution;
  if (!isPlainObject(raw)) {
    return { ok: false, code: "OPENER_CONTRIBUTION_INVALID", message: "補充內容格式異常，已保留你的文字，請重新送出。" };
  }
  const state = (OPENER_CONTRIBUTION_STATES as readonly string[]).includes(raw.state as string)
    ? raw.state as OpenerContributionState
    : null;
  if (state === null) {
    return { ok: false, code: "OPENER_CONTRIBUTION_INVALID", message: "回答狀態異常，已保留你的文字，請重新送出。" };
  }
  const questionId = raw.questionId == null ? null : (typeof raw.questionId === "string" ? raw.questionId.trim() : "");
  const selectedOptionId = raw.selectedOptionId == null ? null : (typeof raw.selectedOptionId === "string" ? raw.selectedOptionId.trim() : "");
  if (questionId === "" || selectedOptionId === "") {
    return { ok: false, code: "OPENER_CONTRIBUTION_INVALID", message: "選項資料異常，已保留你的文字，請重新選擇。" };
  }
  const freeText = normalizeFreeText(raw.freeText);
  if (!freeText.ok) {
    return { ok: false, code: "OPENER_CONTRIBUTION_INVALID", message: freeText.message };
  }
  const hasAnswer = selectedOptionId !== null || freeText.text !== null;
  if (state === "answered" && !hasAnswer) {
    return { ok: false, code: "OPENER_CONTRIBUTION_INVALID", message: "標示已回答但沒有內容；可以改成略過，或補一句再送。" };
  }
  if (state !== "answered" && hasAnswer) {
    return { ok: false, code: "OPENER_CONTRIBUTION_INVALID", message: "已有回答內容，不能同時標示略過；已保留你的文字，請重新送出。" };
  }
  if (selectedOptionId !== null && questionId === null) {
    return { ok: false, code: "OPENER_CONTRIBUTION_INVALID", message: "選項缺少對應題目，請重新選擇。" };
  }
  return {
    ok: true,
    request: {
      sessionId,
      analysisRevision: revision,
      generationId,
      contribution: { state, questionId, selectedOptionId, freeText: freeText.text },
    },
  };
}

export type ContributionAgainstSnapshot =
  | { ok: true; option: OpenerQuestionOption | null }
  | { ok: false; message: string };

/** 快照層驗證（F12）：題目與選項必須屬於本局；題目為 null 時不得帶選項。 */
export function validateContributionAgainstSnapshot(
  contribution: OpenerContribution,
  snapshot: OpenerAnalysisSnapshot,
): ContributionAgainstSnapshot {
  const question = snapshot.question;
  if (contribution.questionId === null && contribution.selectedOptionId === null) {
    return { ok: true, option: null };
  }
  if (question === null) {
    return { ok: false, message: "這份分析沒有題目，選項不屬於本局；已保留你的文字，請重新送出。" };
  }
  if (contribution.questionId !== question.id) {
    return { ok: false, message: "題目不屬於這份分析，請重新分析後再選。" };
  }
  if (contribution.selectedOptionId === null) return { ok: true, option: null };
  const option = question.options.find((item) => item.id === contribution.selectedOptionId) ?? null;
  if (option === null) {
    return { ok: false, message: "選項不屬於這份分析，請重新選擇。" };
  }
  return { ok: true, option };
}

/** 生成輸入指紋：會話／版本／完整回答／prompt 版本（附件 §11.4，回答一定入 hash）。 */
export async function computeOpenerGenerationInputHash(input: {
  sessionId: string;
  analysisRevision: number;
  contribution: OpenerContribution;
  promptVersion: string;
  contractVersion: number;
}): Promise<string> {
  const canonical = JSON.stringify([
    "vibesync-opener-generation-v1",
    input.sessionId,
    input.analysisRevision,
    input.contribution.state,
    input.contribution.questionId,
    input.contribution.selectedOptionId,
    input.contribution.freeText,
    input.promptVersion,
    input.contractVersion,
  ]);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

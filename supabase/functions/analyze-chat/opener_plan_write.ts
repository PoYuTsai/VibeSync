// 開場救星結構刀管線（需求凍結 §4.1）：規劃 → 寫手 → 格式修復或定點改寫（共用唯一
// 額外呼叫）→ 另外挑 → 投影。handler 與付費評測共用這一個函式，評測不再鏡像 handler。
//
// 呼叫預算：規劃 1（不重試、不 fallback；失敗或逾時退「只用她的資料」計畫）＋寫手 1
// （可 fallback）＋額外 1 ＝ ModelCallBudget 上限 3 不變。所有失敗都回給 handler 走
// 既有 release＋不扣費路徑；這裡不碰 claim／settle。

import type { OpenerFlowModelInvoker, OpenerFlowModelOutput } from "./opener_flow_handler.ts";
import type { OpenerGenerateLedgerResult } from "./opener_flow_payload.ts";
import type { OpenerMaterialSet } from "./opener_material.ts";
import { type OpenerType, sanitizeOpenerText } from "./opener_payload.ts";
import type { OpenerAnalysisSnapshot, OpenerQuestionOption } from "./opener_stage.ts";
import { sanitizeCustomerExplanationText } from "./customer_explanation.ts";
import { hasAnalyzeChatPromptLeak } from "./prompt_leak.ts";
import { parseJsonObjectFromText } from "./json_text.ts";
import { isPlainObject } from "../_shared/quota.ts";
import {
  buildOpenerPlanUserContent,
  digestOpenerPlan,
  OPENER_PLAN_MAX_TOKENS,
  OPENER_PLAN_PROMPT,
  OPENER_PLAN_TIMEOUT_MS,
  OPENER_PLAN_WRITER_RESERVE_MS,
  type OpenerPlan,
  type OpenerPlanContext,
  parseOpenerPlan,
  profileOnlyPlan,
} from "./opener_plan.ts";
import {
  buildOpenerRewriteUserContent,
  buildOpenerWritePrompt,
  buildOpenerWriteUserContent,
  OPENER_REWRITE_MAX_TOKENS,
  OPENER_REWRITE_PROMPT,
  DIRECTION_EXAMPLE_TOKENS,
  OPENER_WRITE_MAX_TOKENS,
  type OpenerWriterArm,
  writesDirectionExample,
} from "./opener_write.ts";
import { containsVetoed, judgeOpenerCard, type OpenerCardVerdict, pickOpenerCard, projectPlanWriteResult, withoutEmoji } from "./opener_pick.ts";

/** 定點改寫至少要留這麼多時間，否則直接用降級挑選。 */
const REWRITE_MIN_REMAINING_MS = 8_000;
/** 改寫自己的截止比整個請求早這麼多：改寫逾時就照拿掉紅線卡交付，不拖垮整組。 */
const REWRITE_DEADLINE_MARGIN_MS = 3_000;

export function planWriteEnabled(env: (name: string) => string | undefined): boolean {
  return env("OPENER_PLAN_WRITE") === "true";
}

/** 新版 App 在生成請求帶 openerCardSet=2（它會顯示一句推薦＋四句備選的標籤）；舊版不帶＝五風格。 */
export function writerArmFromRequest(body: Record<string, unknown>): OpenerWriterArm {
  return body.openerCardSet === 2 ? "free" : "styles";
}

export interface PlanWriteInput {
  snapshot: OpenerAnalysisSnapshot;
  freeText: string | null;
  option: OpenerQuestionOption | null;
  materials: OpenerMaterialSet;
  visibleTypes: readonly OpenerType[];
  servedTier: string;
  contractVersion: 1 | 2;
  arm: OpenerWriterArm;
}

export interface PlanWriteDeps {
  invokeModel: OpenerFlowModelInvoker;
  deadlineAtMs: number;
  /** handler 的 OpenerFlowDeadlineError 判斷（避免循環匯入 class）。 */
  isDeadlineError: (error: unknown) => boolean;
  now?: () => number;
  onChunk?: (chunk: string) => void;
}

/** 不含用戶原文的 telemetry。 */
export interface PlanWriteTelemetry {
  arm: OpenerWriterArm;
  planSource: OpenerPlan["source"];
  planRepairedFields: string[];
  planCoverageGap: boolean;
  planError: string | null;
  roleCounts: Record<string, number>;
  anchorCount: number;
  herStatedCount: number;
  hasQuestionTarget: boolean;
  intents: OpenerPlan["intents"];
  primaryStyle: OpenerType | null;
  pick: OpenerType | null;
  verdicts: Partial<Record<OpenerType, OpenerCardVerdict>>;
  formatRepairUsed: boolean;
  rewriteUsed: boolean;
  rewrittenStyles: OpenerType[];
  droppedStyles: OpenerType[];
  /** 帶到自己＝方向＋範例：ok 交付、missing 寫手沒給方向或範例不合格（那張不交付）、unrequested 沒要求卻寫成範例（不交付）、null 不適用。 */
  directionCard: "ok" | "missing" | "unrequested" | null;
  model: string | null;
  inputTokens: number;
  outputTokens: number;
  usageComplete: boolean;
  modelAttempts: number;
  planElapsedMs: number;
  writeElapsedMs: number;
}

export type PlanWriteOutcome =
  | { kind: "ok"; result: OpenerGenerateLedgerResult; telemetry: PlanWriteTelemetry; plan: OpenerPlan; writerRaw: string }
  | {
    kind: "fail";
    reason: "deadline" | "provider" | "leak" | "incomplete" | "no_deliverable";
    stage: string;
    telemetry: PlanWriteTelemetry;
    plan: OpenerPlan | null;
    writerRaw: string | null;
  };

function customerText(value: unknown, max: number): string | null {
  const text = sanitizeCustomerExplanationText(value, 4000);
  if (text === null) return null;
  return text.length > max ? text.slice(0, max) : text;
}

const PIONEER_KEYS = ["ifCold", "ifShortPositive", "ifEngaged", "handoff"] as const;
export const OPENER_DIRECTION_MAX_CHARS = 60;

/**
 * 範例要是一則真的訊息（格式可判，不判語意）：用戶自己分享（有「我」）、不是寫給用戶的說明、
 * 不跟方向同一句、沒有照抄寫手 prompt 範例裡的地名。bb5 實測寫手會把說明或「（沒有使用者自述）」
 * 塞進範例欄，也會把「環河公園」搬去釣魚題。
 */
export function isDirectionExample(example: string, direction: string, inputText: string): boolean {
  if (!example.includes("我") || example === direction) return false;
  if (/先分享|再問她|範例|自述|使用者|方向/u.test(example)) return false;
  return !DIRECTION_EXAMPLE_TOKENS.some((token) => example.includes(token) && !inputText.includes(token));
}

export async function runOpenerPlanWrite(input: PlanWriteInput, deps: PlanWriteDeps): Promise<PlanWriteOutcome> {
  const now = deps.now ?? Date.now;
  const telemetry: PlanWriteTelemetry = {
    arm: input.arm,
    planSource: "profile_only",
    planRepairedFields: [],
    planCoverageGap: false,
    planError: null,
    roleCounts: {},
    anchorCount: 0,
    herStatedCount: 0,
    hasQuestionTarget: false,
    intents: { shorter: false, funny: false },
    primaryStyle: null,
    pick: null,
    verdicts: {},
    formatRepairUsed: false,
    rewriteUsed: false,
    rewrittenStyles: [],
    droppedStyles: [],
    directionCard: null,
    model: null,
    inputTokens: 0,
    outputTokens: 0,
    usageComplete: true,
    modelAttempts: 0,
    planElapsedMs: 0,
    writeElapsedMs: 0,
  };
  const addUsage = (out: OpenerFlowModelOutput) => {
    telemetry.modelAttempts += 1;
    if (typeof out.inputTokens === "number" && typeof out.outputTokens === "number") {
      telemetry.inputTokens += out.inputTokens;
      telemetry.outputTokens += out.outputTokens;
    } else {
      telemetry.usageComplete = false;
    }
  };
  const fail = (reason: Extract<PlanWriteOutcome, { kind: "fail" }>["reason"], stage: string, plan: OpenerPlan | null, writerRaw: string | null): PlanWriteOutcome =>
    ({ kind: "fail", reason, stage, telemetry, plan, writerRaw });

  // ── P1 規劃 ──
  const planCtx: OpenerPlanContext = { snapshot: input.snapshot, freeText: input.freeText, option: input.option, visibleTypes: input.visibleTypes };
  deps.onChunk?.('"materialReading"');
  let plan: OpenerPlan;
  const planStarted = now();
  const planBudgetMs = Math.min(OPENER_PLAN_TIMEOUT_MS, deps.deadlineAtMs - planStarted - OPENER_PLAN_WRITER_RESERVE_MS);
  if (planBudgetMs < 3_000) {
    plan = profileOnlyPlan(planCtx, ["plan.skipped_deadline"]);
    telemetry.planError = "skipped_deadline";
  } else {
    try {
      const out = await deps.invokeModel({
        system: OPENER_PLAN_PROMPT,
        messages: [{ role: "user", content: buildOpenerPlanUserContent(planCtx) }],
        maxTokens: OPENER_PLAN_MAX_TOKENS,
        deadlineAtMs: planStarted + planBudgetMs,
        // 只試一次、不換模型（fallback.ts 的 maxRetries 是「嘗試次數」，預設 1＝不重試）。
        allowModelFallback: false,
        purpose: "plan",
      });
      addUsage(out);
      if (hasAnalyzeChatPromptLeak(out.rawText)) {
        plan = profileOnlyPlan(planCtx, ["plan.leak"]);
        telemetry.planError = "leak";
      } else {
        plan = parseOpenerPlan(parseJsonObjectFromText(out.rawText), planCtx);
      }
    } catch (error) {
      // 規劃只是讓寫手拿到更好的輸入：失敗不擋交付，退回只用她的資料。
      plan = profileOnlyPlan(planCtx, ["plan.error"]);
      telemetry.planError = deps.isDeadlineError(error) ? "timeout" : "error";
    }
  }
  telemetry.planElapsedMs = now() - planStarted;
  telemetry.planSource = plan.source;
  telemetry.planRepairedFields = plan.repairedFields;
  telemetry.planCoverageGap = plan.coverageGap;
  telemetry.anchorCount = plan.anchorCueIds.length;
  telemetry.herStatedCount = plan.herStated.length;
  telemetry.hasQuestionTarget = plan.questionTarget !== null;
  telemetry.intents = plan.intents;
  for (const span of plan.spans) telemetry.roleCounts[span.role] = (telemetry.roleCounts[span.role] ?? 0) + 1;
  if (now() >= deps.deadlineAtMs) return fail("deadline", "plan", plan, null);

  const digest = digestOpenerPlan(plan, planCtx);
  // B 臂推薦句固定寫在 extend（各方案都可見）；A 臂用規劃提名，沒提名就第一張可見卡。
  const primaryStyle: OpenerType = input.arm === "free" ? "extend" : plan.nominatedStyle ?? input.visibleTypes[0] ?? "extend";
  telemetry.primaryStyle = primaryStyle;

  // ── P2 寫手 ──
  const writerSystem = buildOpenerWritePrompt(input.arm);
  const writerContent = buildOpenerWriteUserContent({ snapshot: input.snapshot, freeText: input.freeText, plan, digest, primaryStyle, arm: input.arm });
  const writeStarted = now();
  let writerRaw: string;
  try {
    const out = await deps.invokeModel({
      system: writerSystem,
      messages: [{ role: "user", content: writerContent }],
      maxTokens: OPENER_WRITE_MAX_TOKENS,
      deadlineAtMs: deps.deadlineAtMs,
      allowModelFallback: true,
      onChunk: deps.onChunk,
      purpose: "write",
    });
    addUsage(out);
    telemetry.model = out.model;
    writerRaw = out.rawText;
  } catch (error) {
    telemetry.writeElapsedMs = now() - writeStarted;
    if (deps.isDeadlineError(error) || now() >= deps.deadlineAtMs) return fail("deadline", "model", plan, null);
    return fail("provider", "model", plan, null);
  }
  telemetry.writeElapsedMs = now() - writeStarted;
  if (hasAnalyzeChatPromptLeak(writerRaw)) return fail("leak", "writer", plan, writerRaw);

  let extraCallsRemaining = 1;
  let parsed = parseJsonObjectFromText(writerRaw);
  const writerParsed = parsed;
  // 方向＋範例卡寫不出來只拿掉那張（不修格式、不讓整組 502）：付費黑箱 bb5 有 4/60 因範例空白整組失敗。
  const directional = writesDirectionExample(input.arm, digest);
  // 範例身分在評判／改寫／挑選之前鎖定：寫手在 directions 標了哪張（任何 key、任何非空值；修格式時連原輸出的標記一起算），
  // 除了當次要求的方向＋範例 coldRead，那張整張不交付——不能只丟標記、把範例留成可原封送出的句子（GPT 預審 R2）。
  const markedExample = (json: Record<string, unknown> | null, type: OpenerType) => {
    const value = json && isPlainObject(json.directions) ? json.directions[type] : undefined;
    return value !== undefined && value !== null && !(typeof value === "string" && value.trim() === "");
  };
  const unrequestedExample = (json: Record<string, unknown> | null, type: OpenerType) =>
    !(directional && type === "coldRead") && (markedExample(json, type) || markedExample(writerParsed, type));
  // 要不交付的卡不必交：不為它修格式，也不因它空白整組失敗。
  const requiredTypes = input.visibleTypes.filter((t) => !(directional && t === "coldRead") && !unrequestedExample(writerParsed, t));
  const visibleMissing = (json: Record<string, unknown> | null) => {
    const openers = json && isPlainObject(json.openers) ? json.openers : {};
    return requiredTypes.filter((t) => sanitizeOpenerText(openers[t]) === null);
  };
  if (visibleMissing(parsed).length > 0 && extraCallsRemaining > 0) {
    extraCallsRemaining -= 1;
    telemetry.formatRepairUsed = true;
    try {
      const repair = await deps.invokeModel({
        system: writerSystem,
        messages: [{
          role: "user",
          content: "上一次輸出格式不完整。請輸出合法 JSON，五則都要有；已寫好的句子保留原意。\n上一次輸出：\n" +
            writerRaw.slice(0, 8000) + "\n\n當次資料：\n" + writerContent,
        }],
        maxTokens: OPENER_WRITE_MAX_TOKENS,
        deadlineAtMs: deps.deadlineAtMs,
        allowModelFallback: false,
        purpose: "repair",
      });
      addUsage(repair);
      if (!hasAnalyzeChatPromptLeak(repair.rawText)) {
        const repaired = parseJsonObjectFromText(repair.rawText);
        if (visibleMissing(repaired).length === 0) parsed = repaired;
      }
    } catch (error) {
      if (deps.isDeadlineError(error) || now() >= deps.deadlineAtMs) return fail("deadline", "format_repair", plan, writerRaw);
    }
  }
  if (!parsed || visibleMissing(parsed).length > 0) return fail("incomplete", "writer", plan, writerRaw);

  const rawOpeners = isPlainObject(parsed.openers) ? parsed.openers : {};
  const rawReasons = isPlainObject(parsed.cardReasons) ? parsed.cardReasons : {};
  const openers: Partial<Record<OpenerType, string>> = {};
  const cardReasons: Partial<Record<OpenerType, string>> = {};
  for (const type of input.visibleTypes) {
    if (unrequestedExample(parsed, type)) {
      telemetry.droppedStyles.push(type);
      if (type === "coldRead") telemetry.directionCard = "unrequested";
      continue;
    }
    const sanitized = sanitizeOpenerText(rawOpeners[type]);
    const text = sanitized ? withoutEmoji(sanitized) : null;
    if (text) openers[type] = text;
    const reason = customerText(rawReasons[type], 200);
    if (reason) cardReasons[type] = reason;
  }

  // ── P3 另外挑：紅線 → 一次定點改寫 → 仍踩就拿掉那張 ──
  const rules = {
    blockedQuotes: digest.blockedQuotes,
    excludedTerms: digest.excludedTerms,
    selfFacts: digest.selfFacts,
    profileText: [input.snapshot.profileText.bio, input.snapshot.profileText.interests].filter(Boolean).join("\n"),
    shorter: plan.intents.shorter,
    // 寫手實際看到的全部內容＋她的資料＋用戶原文：卡片裡的英文字不在這裡面才算憑空冒出來。
    inputText: [writerContent, input.snapshot.profileText.name, input.snapshot.profileText.bio, input.snapshot.profileText.interests,
      input.snapshot.profileText.meetingContext, input.snapshot.profileDigest, input.freeText].filter(Boolean).join("\n"),
  };
  const judgeAll = () => {
    const verdicts: Partial<Record<OpenerType, OpenerCardVerdict>> = {};
    for (const type of input.visibleTypes) if (openers[type]) verdicts[type] = judgeOpenerCard(openers[type]!, rules);
    return verdicts;
  };
  let verdicts = judgeAll();
  const vetoed = () => input.visibleTypes.filter((t) => (verdicts[t]?.vetoes.length ?? 0) > 0);
  // 方向＋範例卡不送改寫（改寫器不知道那是範例）：踩紅線就直接拿掉。
  const rewriteTargets = () => vetoed().filter((t) => !(directional && t === "coldRead"));
  if (rewriteTargets().length > 0 && extraCallsRemaining > 0 && deps.deadlineAtMs - now() >= REWRITE_MIN_REMAINING_MS) {
    extraCallsRemaining -= 1;
    telemetry.rewriteUsed = true;
    const targets = rewriteTargets();
    try {
      const rewrite = await deps.invokeModel({
        system: OPENER_REWRITE_PROMPT,
        messages: [{
          role: "user",
          content: buildOpenerRewriteUserContent({
            cards: targets.map((style) => ({ style, text: openers[style]!, vetoes: verdicts[style]!.vetoes })),
            writerInput: writerContent,
          }),
        }],
        maxTokens: OPENER_REWRITE_MAX_TOKENS,
        deadlineAtMs: deps.deadlineAtMs - REWRITE_DEADLINE_MARGIN_MS,
        allowModelFallback: false,
        purpose: "repair",
      });
      addUsage(rewrite);
      const json = hasAnalyzeChatPromptLeak(rewrite.rawText) ? null : parseJsonObjectFromText(rewrite.rawText);
      const rewritten = json && isPlainObject(json.openers) ? json.openers : {};
      for (const style of targets) {
        const sanitized = sanitizeOpenerText(rewritten[style]);
        const text = sanitized ? withoutEmoji(sanitized) : null;
        if (text) {
          openers[style] = text;
          delete cardReasons[style];
          telemetry.rewrittenStyles.push(style);
        }
      }
    } catch {
      // 改寫失敗或逾時（自己的截止）：照原句判定，踩紅線的卡下面拿掉；整個請求到期才算失敗。
      if (now() >= deps.deadlineAtMs) return fail("deadline", "rewrite", plan, writerRaw);
    }
    verdicts = judgeAll();
  }
  for (const style of vetoed()) {
    delete openers[style];
    delete cardReasons[style];
    telemetry.droppedStyles.push(style);
  }
  // 理由與備案也不得帶回冒犯片段或用戶不想聊的事。
  const leaksBlocked = (text: string) => containsVetoed(text, rules.blockedQuotes) || containsVetoed(text, rules.excludedTerms);
  for (const type of Object.keys(cardReasons) as OpenerType[]) if (leaksBlocked(cardReasons[type]!)) delete cardReasons[type];
  // Bruce 9/26（Eric 定案）：B 臂沒有用戶自述時，帶到自己＝給用戶的方向＋一句範例。
  // 方向放 access.directions（跟 cardSet 一樣隨結果存進 App 快取），App 把句子標成範例；寫手沒給方向就不交付那張
  // （範例細節是舉例，不能變成一張看起來可以原封送出的句子）。範例卡不當推薦。
  const directions: Partial<Record<OpenerType, string>> = {};
  if (directional && openers.coldRead) {
    // 方向太長就當沒給（不截斷成半句）；bb5 實測寫手常寫到 41–50 字，上限放 60。
    const rawDirection = isPlainObject(parsed.directions) ? customerText(parsed.directions.coldRead, 4000) : null;
    const direction = rawDirection && rawDirection.length <= OPENER_DIRECTION_MAX_CHARS ? rawDirection : null;
    if (direction && !leaksBlocked(direction) && isDirectionExample(openers.coldRead, direction, rules.inputText)) {
      directions.coldRead = direction;
      telemetry.directionCard = "ok";
    } else {
      delete openers.coldRead;
      delete cardReasons.coldRead;
      telemetry.droppedStyles.push("coldRead");
      telemetry.directionCard = "missing";
    }
  }
  let pioneerPlan: Record<string, string> | null = null;
  if (isPlainObject(parsed.pioneerPlan)) {
    const planOut: Record<string, string> = {};
    for (const key of PIONEER_KEYS) {
      const text = customerText(parsed.pioneerPlan[key], 500);
      if (text && !leaksBlocked(text)) planOut[key] = text;
    }
    if (Object.keys(planOut).length) pioneerPlan = planOut;
  }
  telemetry.verdicts = verdicts;

  const pick = pickOpenerCard({ openers, verdicts, visibleTypes: input.visibleTypes, primaryStyle, funny: plan.intents.funny, arm: input.arm, exclude: Object.keys(directions) as OpenerType[] });
  telemetry.pick = pick;
  if (!pick) return fail("no_deliverable", "pick", plan, writerRaw);
  deps.onChunk?.('"rankedPicks"');
  if (now() >= deps.deadlineAtMs) return fail("deadline", "pre_projection", plan, writerRaw);

  const result = projectPlanWriteResult({
    openers,
    cardReasons,
    pioneerPlan,
    pick,
    primaryStyle,
    visibleTypes: input.visibleTypes,
    servedTier: input.servedTier,
    contractVersion: input.contractVersion,
    inputState: input.materials.inputState,
    plan,
    digest,
    snapshot: input.snapshot,
    freeText: input.freeText,
    rewrittenStyles: telemetry.rewrittenStyles,
    ...(input.arm === "free" ? { cardSet: 2 as const } : {}),
    directions,
  });
  return { kind: "ok", result, telemetry, plan, writerRaw };
}

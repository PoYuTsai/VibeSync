// 新話題成對評測（ADR #51）：改前（base）vs 改後（cand）。local-only、付費。
//
// - base＝改前的 production（預設 7c5cc523）：用 git 取出那一版的 supabase/functions，照當時 handler 的
//   路由組提示詞（沒帶 topicContext 走舊版提示詞、帶了走進階 v1；外洩守門與紅燈收尾也照當時）。
// - cand＝目前工作樹的 production：提示詞、外洩守門、grounding 與紅燈收尾全部由 planNewTopicPrompt
//   產生（handler 呼叫同一個函式）；「今天」用固定時間（--now），可重現。
// - 兩臂同案例、同 requestId、同重複次數成對；模型、max_tokens、thinking 與 system 快取照 production
//   主呼叫（requestBody 與 fallback.ts 送出的 body 相同，run_test 有比對）。不做修格式那一次呼叫。
// - --compare=model（Eric 2026-10-08）：兩臂都用目前工作樹的提示詞（同 cand），只換模型：base＝production
//   的 NEW_TOPIC_MODEL（Sonnet 5）、cand＝Sonnet 5.5；thinking／effort／max_tokens 由 model_request_params
//   依模型決定（同 fallback.ts 每一跳）。這是已知問題的小型診斷，tally.ts 不會把它當 §6.5 驗收。
// 每次呼叫只送一次：不重試、不修格式、不走備援、不串流；API 失敗照最壞預留計費並整批停。
// 預設 dry-run：不打模型、不讀金鑰、不連網；會跑 git（rev-parse、archive）取出改前版本。
// 真跑必須同時帶 --run --confirm-paid --max-calls=<上限> --budget-usd=<上限>，且 Eric 當次說「跑」之後才能下。
// 預算守門用估計的 token 數，不是嚴格上限（見 README「真跑」）。
// 指令與輸出說明見 README.md；盲測填完後用 tally.ts 算驗收門檻（資料不完整不能通過）。

import catalog from "./cases.json" with { type: "json" };
import { isPlainObject } from "../../supabase/functions/_shared/quota.ts";
import {
  maxTokensFor,
  modelRequestParams,
  SONNET_5_5_MODEL,
  SONNET_5_MODEL,
} from "../../supabase/functions/_shared/model_request_params.ts";
import {
  estimateCostUsd,
  SONNET_5_5_PRICING,
  SONNET_5_PRICING,
  type TokenPricing,
} from "../../supabase/functions/_shared/model_pricing.ts";
import { extractClaudeText } from "../../supabase/functions/analyze-chat/fallback.ts";
import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import {
  hasNewTopicMaterial,
  type NewTopicGroundingPolicy,
  type NewTopicModelTopic,
  type NewTopicSituation,
  normalizeNewTopicModelPayload,
  sanitizeNewTopicRequest,
} from "../../supabase/functions/analyze-chat/new_topic_payload.ts";
import {
  NEW_TOPIC_GENERATION_DEADLINE_MS,
  NEW_TOPIC_MAX_TOKENS,
  NEW_TOPIC_MODEL,
} from "../../supabase/functions/analyze-chat/new_topic_prompt.ts";
import { planNewTopicPrompt } from "../../supabase/functions/analyze-chat/new_topic_prompt_plan.ts";
import {
  APOLOGY_PATTERN,
  auditNewTopicTwoStageTopics,
  enforceNewTopicRedClose,
  GAP_MENTION_PATTERN,
  isNewTopicRedClose,
  NEW_TOPIC_TWO_STAGE_PROMPT_VERSION,
  type NewTopicTopicContext,
  type NewTopicTwoStageAudit,
} from "../../supabase/functions/analyze-chat/new_topic_two_stage.ts";
import { graphemeLength } from "../../supabase/functions/analyze-chat/opener_stage.ts";

export type Arm = "base" | "cand";
export const ARMS: readonly Arm[] = ["base", "cand"];
/** ADR #51 之前的 main：改前的真實行為（舊版基本模式提示詞、進階 v1、舊角度清單）。 */
export const DEFAULT_BASE_REF = "7c5cc523";
/** 候選的「今天」：固定時間才可重現（台灣時間 2026-10-05 週一中午）。 */
export const DEFAULT_EVAL_NOW = "2026-10-05T12:00:00+08:00";
export const MODEL = NEW_TOPIC_MODEL;
/** 實際送出的 max_tokens（同 requestBody）：output 最壞就是全滿。 */
export const MAX_OUTPUT_TOKENS = maxTokensFor(MODEL, NEW_TOPIC_MAX_TOKENS);
// 本機沒有 tokenizer：input 先用「字數 × 1.5」估；真跑時若實測每字 token 數更高，之後的預留改用實測值。
export const CJK_TOKENS_PER_CHAR = 1.5;
export const TYPICAL_OUTPUT_TOKENS = 1200;

/** 預估、預留與實付都用同一組單價；換模型沒有單價就直接失敗，不默默用錯價。 */
const PRICING_BY_MODEL: Record<string, TokenPricing> = {
  [SONNET_5_MODEL]: SONNET_5_PRICING,
  [SONNET_5_5_MODEL]: SONNET_5_5_PRICING,
};
export function pricingFor(model: string): TokenPricing {
  const pricing = PRICING_BY_MODEL[model];
  if (!pricing) throw new Error(`沒有 ${model} 的單價`);
  return pricing;
}
export const PRICING = pricingFor(MODEL);
/**
 * 四種 input 單價裡最高的（system 開了 ephemeral 快取，第一次寫入是 1.25 倍）。預估與預留的 input
 * 一律用這個價：不管 usage 怎麼分到一般／快取寫入／快取讀取，實付都不會因為單價高於預留。
 */
export function maxInputPerMTok(pricing: TokenPricing): number {
  return Math.max(
    pricing.inputPerMTok,
    pricing.cacheWritePerMTok,
    pricing.cacheReadPerMTok,
  );
}
export const MAX_INPUT_PER_MTOK = maxInputPerMTok(PRICING);

/** prompt＝改前 vs 改後提示詞（同模型）；model＝同一份提示詞，只換模型。 */
export type Comparison = "prompt" | "model";
export const COMPARISONS: readonly Comparison[] = ["prompt", "model"];
/** 模型對照的 cand 模型（Eric 2026-10-08：先比 Sonnet 5／5.5，再決定要不要加審稿呼叫）。 */
export const MODEL_COMPARE_CANDIDATE = SONNET_5_5_MODEL;

/** 這一臂送哪個模型：提示詞對照兩臂都是 production 的模型；模型對照只有 cand 換。 */
export function armModel(compare: Comparison, arm: Arm): string {
  return compare === "model" && arm === "cand"
    ? MODEL_COMPARE_CANDIDATE
    : MODEL;
}

/** 這個模型實際送出的 max_tokens（5.5 多給思考餘裕）：output 最壞就是全滿。 */
export function maxOutputTokensFor(model: string): number {
  return maxTokensFor(model, NEW_TOPIC_MAX_TOKENS);
}

/** 5.5 的思考 token 算在 output 裡；effort low 在新話題實際用多少還沒量過，估價先多抓這麼多。 */
export const SONNET_5_5_TYPICAL_THINKING_TOKENS = 1000;

export function typicalOutputTokensFor(model: string): number {
  return model === SONNET_5_5_MODEL
    ? TYPICAL_OUTPUT_TOKENS + SONNET_5_5_TYPICAL_THINKING_TOKENS
    : TYPICAL_OUTPUT_TOKENS;
}
const API_TIMEOUT_MS = 60_000; // 同 handler 非串流路徑；超過 production 45 秒期限的另計
/** 同 fallback.ts／streaming_fallback.ts 送出的 header。 */
export const REQUEST_HEADERS = {
  "content-type": "application/json",
  "anthropic-version": "2023-06-01",
  "anthropic-beta": "prompt-caching-2024-07-31",
} as const;
const REPO_ROOT = new URL("../../", import.meta.url);

export type EvalCase = {
  id: string;
  source: string;
  label: string;
  partner: string | null;
  /** null＝狀況沒選。 */
  situation: NewTopicSituation | null;
  /** null＝基本模式（請求不帶 topicContext）。 */
  topicContext: Partial<Record<string, string>> | null;
};
export const CASES = catalog.cases as EvalCase[];
export const PARTNERS = catalog.partners as Record<string, string>;
/** 正式驗收：22 組全跑、每組 2 次、兩臂都有（規格 §6.3）。 */
export const FORMAL_REPEAT = 2;

// ---------------------------------------------------------------------------
// 參數
// ---------------------------------------------------------------------------

export type Options = {
  tag: string;
  repeat: number;
  seed: number;
  only: string[] | null;
  arms: readonly Arm[];
  compare: Comparison;
  run: boolean;
  maxCalls: number | null;
  budgetUsd: number | null;
  baseRef: string;
  now: string;
  nowMs: number;
};

const VALUE_FLAGS = [
  "tag",
  "repeat",
  "seed",
  "only",
  "arms",
  "compare",
  "max-calls",
  "budget-usd",
  "base-ref",
  "now",
];
const BOOL_FLAGS = ["run", "confirm-paid"];

/**
 * 甲乙順序只由 seed 決定，跟模型輸出無關：固定的預設值等於公開了解盲表。預設每次隨機（記在
 * manifest，評完才給評分的人）；nt3 用的舊預設 20261001 位置已公開，不能再用。
 */
function randomSeed(): number {
  const [value] = crypto.getRandomValues(new Uint32Array(1));
  return value === 0 ? 1 : value;
}

export function parseOptions(args: string[]): Options {
  const values = new Map<string, string | true>();
  for (const arg of args) {
    const m = /^--([a-z-]+)(?:=(.+))?$/.exec(arg);
    const key = m?.[1] ?? "";
    const known = m !== null &&
      (m[2] === undefined
        ? BOOL_FLAGS.includes(key)
        : VALUE_FLAGS.includes(key));
    if (!known || values.has(key)) {
      throw new Error(`未知、重複或格式錯誤的參數：${arg}`);
    }
    values.set(key, m[2] ?? true);
  }
  const str = (key: string) => {
    const value = values.get(key);
    return typeof value === "string" ? value : null;
  };
  const int = (key: string, fallback: number, max: number) => {
    const raw = str(key);
    if (raw === null) return fallback;
    const value = Number(raw);
    if (!/^\d+$/.test(raw) || value < 1 || value > max) {
      throw new Error(`--${key} 要是 1–${max} 的整數`);
    }
    return value;
  };

  const tag = str("tag") ?? "dry-run";
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(tag)) {
    throw new Error("--tag 只能用英數、-、_");
  }
  const only = str("only")?.split(",") ?? null;
  if (
    only &&
    (new Set(only).size !== only.length ||
      only.some((id) => !CASES.some((c) => c.id === id)))
  ) {
    throw new Error("--only 有重複或不存在的案例 ID");
  }
  const armsRaw = str("arms") ?? "both";
  const arms = armsRaw === "both"
    ? ARMS
    : ARMS.filter((arm) => arm === armsRaw);
  if (arms.length === 0) {
    throw new Error("--arms 只能是 base、cand 或 both");
  }
  const compare = (str("compare") ?? "prompt") as Comparison;
  if (!COMPARISONS.includes(compare)) {
    throw new Error("--compare 只能是 prompt 或 model");
  }
  // 模型對照兩臂都用目前工作樹的提示詞；收了 --base-ref 會讓人以為有比到改前版本。
  if (compare === "model" && values.has("base-ref")) {
    throw new Error("--compare=model 兩臂都用目前的提示詞，不收 --base-ref");
  }
  // 基準只收 commit SHA：分支名會移動，結果就對不回真正的改前版本。
  const baseRef = str("base-ref") ?? DEFAULT_BASE_REF;
  if (!/^[0-9a-f]{7,40}$/.test(baseRef)) {
    throw new Error("--base-ref 要是 7–40 位的 commit SHA");
  }
  // 時間要帶時區，「今天」才不會因為跑的機器不同而變。
  const now = str("now") ?? DEFAULT_EVAL_NOW;
  const nowMs = Date.parse(now);
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:\d{2})$/.test(
      now,
    ) || !Number.isFinite(nowMs)
  ) {
    throw new Error(
      "--now 要是帶時區的 ISO 時間，例如 2026-10-05T12:00:00+08:00",
    );
  }
  const budgetRaw = str("budget-usd");
  const budgetUsd = budgetRaw === null ? null : Number(budgetRaw);
  if (budgetUsd !== null && !(Number.isFinite(budgetUsd) && budgetUsd > 0)) {
    throw new Error("--budget-usd 要是正數");
  }
  const maxCalls = values.has("max-calls") ? int("max-calls", 0, 1000) : null;
  const run = values.has("run");
  if (
    run &&
    (!values.has("confirm-paid") || maxCalls === null || budgetUsd === null)
  ) {
    throw new Error(
      "真跑必須同時帶 --run --confirm-paid --max-calls=<上限> --budget-usd=<上限>（Eric 當次授權後）",
    );
  }
  return {
    tag,
    repeat: int("repeat", 1, 5),
    seed: int("seed", randomSeed(), 0xffffffff),
    only,
    arms,
    compare,
    run,
    maxCalls,
    budgetUsd,
    baseRef,
    now,
    nowMs,
  };
}

// ---------------------------------------------------------------------------
// 兩臂的路由：cand＝production 的 planNewTopicPrompt；base＝改前 handler 的路由
// ---------------------------------------------------------------------------

export type PlanInput = {
  partnerSummary: string | null;
  effectiveStyleContext: string | null;
  situation: NewTopicSituation | null;
  topicContext: NewTopicTopicContext | null;
  requestId: string;
};

export type ArmPlan = {
  system: string;
  user: string;
  hasPromptLeak: (text: string) => boolean;
  grounding: NewTopicGroundingPolicy;
  appliesRedClose: boolean;
};

export type ArmRouter = (input: PlanInput) => ArmPlan;

/** 候選：handler 呼叫的同一個函式，只把「現在」換成固定時間。 */
export function candRouter(nowMs: number): ArmRouter {
  return (input) => {
    const plan = planNewTopicPrompt({ ...input, nowMs });
    return {
      system: plan.system,
      user: plan.user,
      hasPromptLeak: (text) => plan.hasPromptLeak(text),
      grounding: plan.grounding,
      appliesRedClose: plan.appliesRedClose,
    };
  };
}

/** 改前那一版要用到的 export（從 git 取出的檔案動態載入）。 */
export type BaseModules = {
  NEW_TOPIC_PROMPT: string;
  buildNewTopicUserPrompt: (input: {
    partnerSummary: string | null;
    effectiveStyleContext: string | null;
    situation: NewTopicSituation | null;
    requestId?: string;
  }) => string;
  NEW_TOPIC_TWO_STAGE_PROMPT: string;
  buildNewTopicTwoStageUserPrompt: (input: {
    partnerSummary: string | null;
    effectiveStyleContext: string | null;
    situation: NewTopicSituation | null;
    topicContext: NewTopicTopicContext;
    requestId: string;
  }) => string;
  hasAnalyzeChatPromptLeak: (text: string) => boolean;
  hasNewTopicTwoStagePromptLeak: (text: string) => boolean;
  allowsNewTopicSharedFrame: (input: {
    partnerSummary: string | null;
    situation: NewTopicSituation | null;
    topicContext?: NewTopicTopicContext | null;
  }) => boolean;
};

/**
 * 7c5cc523 的 handler 路由（new_topic_handler.ts@7c5cc523：提示詞 :562-580、grounding :581-589、
 * 外洩守門 :616-620、紅燈收尾 :761-770）：沒帶 topicContext 走舊版提示詞與 analyze-chat 共用的
 * 外洩守門、不套紅燈收尾；帶了走進階 v1。
 */
export function baseRouter(m: BaseModules): ArmRouter {
  return (input) => {
    const grounding: NewTopicGroundingPolicy = {
      allowSharedFrame: m.allowsNewTopicSharedFrame({
        partnerSummary: input.partnerSummary,
        situation: input.situation,
        topicContext: input.topicContext,
      }),
      userMaterialText: input.topicContext?.materialText ?? null,
    };
    if (input.topicContext === null) {
      return {
        system: m.NEW_TOPIC_PROMPT,
        user: m.buildNewTopicUserPrompt({
          partnerSummary: input.partnerSummary,
          effectiveStyleContext: input.effectiveStyleContext,
          situation: input.situation,
          requestId: input.requestId,
        }),
        hasPromptLeak: m.hasAnalyzeChatPromptLeak,
        grounding,
        appliesRedClose: false,
      };
    }
    return {
      system: m.NEW_TOPIC_TWO_STAGE_PROMPT,
      user: m.buildNewTopicTwoStageUserPrompt({
        partnerSummary: input.partnerSummary,
        effectiveStyleContext: input.effectiveStyleContext,
        situation: input.situation,
        topicContext: input.topicContext,
        requestId: input.requestId,
      }),
      hasPromptLeak: m.hasNewTopicTwoStagePromptLeak,
      grounding,
      appliesRedClose: true,
    };
  };
}

function requireExport<T>(
  mod: Record<string, unknown>,
  name: string,
  kind: "string" | "function",
): T {
  const value = mod[name];
  const ok = kind === "string"
    ? typeof value === "string"
    : typeof value === "function";
  if (!ok) {
    throw new Error(`改前版本少了 ${name}（${kind}）：基準 ref 不對？`);
  }
  return value as T;
}

/** 從 materializeRef 取出的目錄載入改前模組。 */
export async function loadBaseModules(root: URL): Promise<BaseModules> {
  const dir = new URL("supabase/functions/analyze-chat/", root);
  const load = (name: string) =>
    import(new URL(name, dir).href) as Promise<Record<string, unknown>>;
  const [prompt, twoStage, leak, payload] = await Promise.all([
    load("new_topic_prompt.ts"),
    load("new_topic_two_stage.ts"),
    load("prompt_leak.ts"),
    load("new_topic_payload.ts"),
  ]);
  return {
    NEW_TOPIC_PROMPT: requireExport(prompt, "NEW_TOPIC_PROMPT", "string"),
    buildNewTopicUserPrompt: requireExport(
      prompt,
      "buildNewTopicUserPrompt",
      "function",
    ),
    NEW_TOPIC_TWO_STAGE_PROMPT: requireExport(
      twoStage,
      "NEW_TOPIC_TWO_STAGE_PROMPT",
      "string",
    ),
    buildNewTopicTwoStageUserPrompt: requireExport(
      twoStage,
      "buildNewTopicTwoStageUserPrompt",
      "function",
    ),
    hasAnalyzeChatPromptLeak: requireExport(
      leak,
      "hasAnalyzeChatPromptLeak",
      "function",
    ),
    hasNewTopicTwoStagePromptLeak: requireExport(
      leak,
      "hasNewTopicTwoStagePromptLeak",
      "function",
    ),
    allowsNewTopicSharedFrame: requireExport(
      payload,
      "allowsNewTopicSharedFrame",
      "function",
    ),
  };
}

async function git(args: string[]): Promise<string> {
  const result = await new Deno.Command("git", {
    args,
    cwd: REPO_ROOT,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    throw new Error(`git ${args[0]} 失敗（exit ${result.code}）`);
  }
  return new TextDecoder().decode(result.stdout).trim();
}

/** 用 git archive 把那一版的 supabase/functions 取到暫存目錄（唯讀，不動工作樹）。 */
export async function materializeRef(
  ref: string,
): Promise<{ sha: string; root: URL }> {
  const sha = await git(["rev-parse", "--verify", `${ref}^{commit}`]);
  const tmp = await Deno.makeTempDir({
    prefix: `new-topic-eval-base-${sha.slice(0, 8)}-`,
  });
  const tarPath = `${tmp}/src.tar`;
  await git([
    "archive",
    "--format=tar",
    `--output=${tarPath}`,
    sha,
    "supabase/functions",
  ]);
  const untar = await new Deno.Command("tar", {
    args: ["-xf", tarPath, "-C", tmp],
  }).output();
  if (!untar.success) throw new Error(`tar 失敗（exit ${untar.code}）`);
  return { sha, root: new URL(`file://${tmp}/`) };
}

// ---------------------------------------------------------------------------
// 呼叫計畫：每案例 × 每次重複 × 選定的臂
// ---------------------------------------------------------------------------

export type PlannedCall = {
  key: string;
  caseId: string;
  attempt: number;
  arm: Arm;
  /** 這次呼叫送的模型（armModel）。 */
  model: string;
  mode: "basic" | "advanced";
  requestId: string;
  situation: NewTopicSituation | null;
  /** 用戶真實的回答；基本模式是 null。 */
  topicContext: NewTopicTopicContext | null;
  partnerSummary: string | null;
  grounding: NewTopicGroundingPolicy;
  appliesRedClose: boolean;
  system: string;
  user: string;
  hasPromptLeak: (text: string) => boolean;
};

export async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** 案例檔的 sha256（manifest 記下；tally 用來確認案例檔沒換過）。 */
export async function catalogSha256(): Promise<string> {
  return await sha256(JSON.stringify(catalog));
}

/** 固定 requestId：同案例同次重複的兩臂拿到同一個 requestId（角度跟著各版的清單），可重現。 */
export async function requestIdFor(
  caseId: string,
  attempt: number,
): Promise<string> {
  const h = await sha256(`new-topic-two-stage-eval:${caseId}:${attempt}`);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${
    h.slice(16, 20)
  }-${h.slice(20, 32)}`;
}

/** 走 production 的請求驗證：案例組合不合法（例如冷掉了卻帶燈號）直接拒絕。 */
export function sanitizeCase(c: EvalCase, requestId: string) {
  const partnerSummary = c.partner === null ? null : PARTNERS[c.partner];
  if (partnerSummary === undefined) {
    throw new Error(`案例 ${c.id} 的 partner 不存在`);
  }
  const body: Record<string, unknown> = { requestId };
  if (partnerSummary !== null) body.partnerSummary = partnerSummary;
  if (c.situation !== null) body.situation = c.situation;
  if (c.topicContext !== null) body.topicContext = c.topicContext;
  const sanitized = sanitizeNewTopicRequest(body);
  if (!sanitized.ok) {
    throw new Error(`案例 ${c.id} 不是合法請求：${sanitized.reason}`);
  }
  if ((c.topicContext === null) !== (sanitized.request.topicContext === null)) {
    throw new Error(`案例 ${c.id} 的 topicContext 正規化後模式不對`);
  }
  if (!hasNewTopicMaterial(sanitized.request)) {
    throw new Error(`案例 ${c.id} 沒有任何素材（production 會回 422）`);
  }
  return sanitized.request;
}

export async function buildPlan(
  cases: EvalCase[],
  repeat: number,
  routers: Partial<Record<Arm, ArmRouter>>,
  arms: readonly Arm[] = ARMS,
  compare: Comparison = "prompt",
): Promise<PlannedCall[]> {
  const plan: PlannedCall[] = [];
  for (const c of cases) {
    for (let attempt = 1; attempt <= repeat; attempt++) {
      const requestId = await requestIdFor(c.id, attempt);
      const request = sanitizeCase(c, requestId);
      for (const arm of arms) {
        const router = routers[arm];
        if (!router) throw new Error(`沒有 ${arm} 臂的路由`);
        const armPlan = router({
          partnerSummary: request.partnerSummary,
          effectiveStyleContext: request.effectiveStyleContext,
          situation: request.situation,
          topicContext: request.topicContext,
          requestId,
        });
        plan.push({
          key: `${c.id}.${attempt}.${arm}`,
          caseId: c.id,
          attempt,
          arm,
          model: armModel(compare, arm),
          mode: request.topicContext === null ? "basic" : "advanced",
          requestId,
          situation: request.situation,
          topicContext: request.topicContext,
          partnerSummary: request.partnerSummary,
          ...armPlan,
        });
      }
    }
  }
  return plan;
}

/** 有模型就照模型算、沒有就是 production 的模型（舊呼叫端與 production 主呼叫一樣）。 */
type ModelCall = Pick<PlannedCall, "system" | "user"> & { model?: string };

/**
 * production 主呼叫的 request body（同 fallback.ts 第一跳；不含串流與備援）。thinking／effort／
 * max_tokens 照 model_request_params 依模型決定，跟 fallback.ts 每一跳送的一樣。
 */
export function requestBody(call: ModelCall) {
  const model = call.model ?? MODEL;
  return {
    model,
    max_tokens: maxOutputTokensFor(model),
    system: [{
      type: "text",
      text: call.system,
      cache_control: { type: "ephemeral" },
    }],
    messages: [{ role: "user", content: call.user }],
    ...modelRequestParams(model),
  };
}

// ---------------------------------------------------------------------------
// 費用：預估、每次送出前的預留、實付都用同一組單價（PRICING）
// ---------------------------------------------------------------------------

export function promptChars(
  call: Pick<PlannedCall, "system" | "user">,
): number {
  return call.system.length + call.user.length;
}

/** 估 input token：字數 × 每字 token 數（預設 1.5；真跑時用實測過的最大值）。 */
export function estimateInputTokens(
  call: Pick<PlannedCall, "system" | "user">,
  tokensPerChar = CJK_TOKENS_PER_CHAR,
): number {
  return Math.ceil(promptChars(call) * tokensPerChar);
}

/** 實付：照 usage 的四格 token 計價（單價依模型）。 */
export function usd(
  inputTokens: number,
  outputTokens: number,
  cacheReadInputTokens = 0,
  cacheCreationInputTokens = 0,
  model: string = MODEL,
): number {
  return estimateCostUsd({
    inputTokens,
    outputTokens,
    cacheReadInputTokens,
    cacheCreationInputTokens,
  }, pricingFor(model));
}

/** 保守計價：input 全部用最高的 input 單價（快取寫入）。預估與每次送出前的預留都用這個。 */
export function conservativeUsd(
  inputTokens: number,
  outputTokens: number,
  model: string = MODEL,
): number {
  const pricing = pricingFor(model);
  return (inputTokens * maxInputPerMTok(pricing) +
    outputTokens * pricing.outputPerMTok) / 1_000_000;
}

/** 每次送出前的預留：input 估計 token 全用快取寫入單價、output 用這個模型的 max_tokens 全滿。 */
export function reservationUsd(
  call: ModelCall,
  tokensPerChar = CJK_TOKENS_PER_CHAR,
): number {
  const model = call.model ?? MODEL;
  return conservativeUsd(
    estimateInputTokens(call, tokensPerChar),
    maxOutputTokensFor(model),
    model,
  );
}

/** 回來的 usage 換算每字 token 數，取目前與實測的較大值（之後的預留跟著變大，不會變小）。 */
export function calibratedTokensPerChar(
  current: number,
  call: Pick<PlannedCall, "system" | "user">,
  usage: {
    inputTokens: number;
    cacheReadInputTokens: number;
    cacheCreationInputTokens: number;
  },
): number {
  const actual = usage.inputTokens + usage.cacheReadInputTokens +
    usage.cacheCreationInputTokens;
  return Math.max(current, actual / promptChars(call));
}

/** 送出前的守門：已停、到次數上限，或已花費＋這次預留超過預算，就不送。 */
export function stopBeforeCall(input: {
  stopped: boolean;
  calls: number;
  maxCalls: number;
  spentUsd: number;
  reservationUsd: number;
  budgetUsd: number;
}): boolean {
  return input.stopped || input.calls >= input.maxCalls ||
    input.spentUsd + input.reservationUsd > input.budgetUsd;
}

export type PlanEstimate = {
  calls: number;
  inputTokens: number;
  typicalOutputTokens: number;
  worstOutputTokens: number;
  typicalUsd: number;
  worstUsd: number;
};

/** 同一個模型的 token 先加總再計價（單一模型時跟整批一起算一樣）。 */
function estimateCalls(plan: ModelCall[]): PlanEstimate {
  const byModel = new Map<string, { calls: number; input: number }>();
  for (const call of plan) {
    const model = call.model ?? MODEL;
    const entry = byModel.get(model) ?? { calls: 0, input: 0 };
    entry.calls++;
    entry.input += estimateInputTokens(call);
    byModel.set(model, entry);
  }
  const total: PlanEstimate = {
    calls: 0,
    inputTokens: 0,
    typicalOutputTokens: 0,
    worstOutputTokens: 0,
    typicalUsd: 0,
    worstUsd: 0,
  };
  for (const [model, { calls, input }] of byModel) {
    const typical = calls * typicalOutputTokensFor(model);
    const worst = calls * maxOutputTokensFor(model);
    total.calls += calls;
    total.inputTokens += input;
    total.typicalOutputTokens += typical;
    total.worstOutputTokens += worst;
    total.typicalUsd += conservativeUsd(input, typical, model);
    total.worstUsd += conservativeUsd(input, worst, model);
  }
  return total;
}

/** 整批估算，另附每一臂的估算（模型對照兩臂的 max_tokens 與一般 output 不同）。 */
export function estimatePlan(plan: (ModelCall & { arm?: Arm })[]) {
  const byArm: Partial<Record<Arm, PlanEstimate>> = {};
  for (const arm of ARMS) {
    const calls = plan.filter((call) => call.arm === arm);
    if (calls.length) byArm[arm] = estimateCalls(calls);
  }
  return { ...estimateCalls(plan), byArm };
}

// ---------------------------------------------------------------------------
// 字面計數（規格 §4.6 的六項＋宣告套話；只看趨勢，不判單筆對錯）
// ---------------------------------------------------------------------------

export const LINE_PATTERNS = {
  questionLines: /[?？]/u,
  hypotheticalLines:
    /如果(?:要|有一天|現在|我們|妳是|讓妳|給妳)|假如|假設|要是(?:妳|我們|讓妳)/u,
  roleAssignLines: /妳負責|妳扮演|妳來演|派妳|分配給妳/u,
  labelJudgmentLines:
    /真實身分|另一個身分|分身|人設|妳(?:感覺|應該|一定|絕對|肯定|根本)(?:是|就是)|妳是哪一?種|哪種人|那種人/u,
  abilityRankLines: /擅長|比較會|哪個比較強|誰比較厲害/u,
  declarationLines:
    /我有個|我只有一個原則|不退讓|不接受反駁|我站.{0,8}(?:這邊|那邊)|我投.{0,12}一票|沒得商量/u,
} as const;

export type LineCounts = Record<keyof typeof LINE_PATTERNS, number> & {
  multiQuestionLines: number;
};

export function emptyLineCounts(): LineCounts {
  return {
    questionLines: 0,
    multiQuestionLines: 0,
    hypotheticalLines: 0,
    roleAssignLines: 0,
    labelJudgmentLines: 0,
    abilityRankLines: 0,
    declarationLines: 0,
  };
}

export function countLines(lines: string[]): LineCounts {
  const counts = emptyLineCounts();
  for (const line of lines) {
    for (const [key, pattern] of Object.entries(LINE_PATTERNS)) {
      if (pattern.test(line)) counts[key as keyof typeof LINE_PATTERNS]++;
    }
    // 連續問號算一段（同 opener_pick.ts 的 questionCount）。
    if ((line.match(/[?？]+/g) ?? []).length >= 2) counts.multiQuestionLines++;
  }
  return counts;
}

/** 規格 §6.5 第 5 項的四種尷尬句型。 */
export function awkwardPatternLines(counts: LineCounts): number {
  return counts.hypotheticalLines + counts.roleAssignLines +
    counts.labelJudgmentLines + counts.abilityRankLines;
}

const STAR_TITLE_TECHNIQUE =
  /分配|安排(?:她|一個)|讓她(?:反駁|澄清)|反差|測試她|角色/u;

/** 解釋欄裡、輸入沒有的英文字（素材或作戰板原本就有的英文名稱不算）。 */
export function explanationEnglish(
  texts: string[],
  inputText: string,
): string[] {
  const allowed = new Set(
    (inputText.match(/[A-Za-z]{2,}/g) ?? []).map((w) => w.toLowerCase()),
  );
  return texts.flatMap((t) => t.match(/[A-Za-z]{2,}/g) ?? []).filter((w) =>
    !allowed.has(w.toLowerCase())
  );
}

/**
 * 把標題、whyItWorks、nextMove 換成佔位字、拿掉推薦理由再驗一次。過了代表只有解釋欄不合格：
 * production 修格式會逐字保留這五句開場句（mergeNewTopicRepairWithPrimaryOpeningLines）。
 * 回傳的 topics 解釋欄是佔位字，只能拿開場句與推薦位置來用。
 */
export function normalizeOpeningsOnly(
  parsed: unknown,
  grounding: NewTopicGroundingPolicy,
) {
  if (!isPlainObject(parsed) || !Array.isArray(parsed.topics)) {
    return normalizeNewTopicModelPayload(parsed, grounding);
  }
  const topics = parsed.topics.map((topic, i) =>
    isPlainObject(topic)
      ? {
        ...topic,
        direction: `方向${i + 1}`,
        whyItWorks: "說明",
        nextMove: "說明",
      }
      : topic
  );
  const recommendation = isPlainObject(parsed.recommendation)
    ? { index: parsed.recommendation.index }
    : parsed.recommendation;
  return normalizeNewTopicModelPayload(
    { ...parsed, topics, recommendation },
    grounding,
  );
}

export function explanationOnlyFailure(
  parsed: unknown,
  grounding: NewTopicGroundingPolicy,
): boolean {
  return !normalizeNewTopicModelPayload(parsed, grounding).ok &&
    normalizeOpeningsOnly(parsed, grounding).ok;
}

// ---------------------------------------------------------------------------
// 結果整理（同 handler：parse → normalize＋grounding → 外洩檢查 → 紅燈收尾保證；不做修格式）
// ---------------------------------------------------------------------------

export type Inspection = {
  /** 不用修格式就能交付（格式合格、沒有外洩）。 */
  deliverable: boolean;
  /**
   * 開場句可評：可交付，或只壞在解釋欄（production 修格式會逐字保留這五句，用戶看得到）。
   * 盲測與開場句的機械指標都算這些；可交付率只算 deliverable。
   */
  openingsEvaluable: boolean;
  promptLeak: boolean;
  normalizeReason: string | null;
  /** 格式不合格，但只壞在解釋欄（production 修格式會保留開場句）。 */
  explanationOnlyFailure: boolean;
  /** 開場句可評時才有；只壞在解釋欄時，標題與解釋是佔位字，不能拿來評解釋。 */
  topics: NewTopicModelTopic[] | null;
  /**
   * 用戶實際看到的推薦（帶 topicContext 時已套紅燈收尾保證，同 production）。只壞在解釋欄時用主呼叫
   * 自己的推薦：production 修格式那一次會重選，可能不同。
   */
  recommendationIndex: number | null;
  recommendationReason: string | null;
  /** 模型自己推的那題（套保證之前）。 */
  modelRecommendationIndex: number | null;
  redCloseOverridden: boolean;
  /** 量測用：兩臂都用目前的稽核函式（不是行為）。 */
  audit: NewTopicTwoStageAudit | null;
  lines: LineCounts | null;
  /** 只算推薦那一題（Free 只看得到這一題）。 */
  star: LineCounts | null;
  openingLengths: number[] | null;
  /** 解釋欄的兩項只算可交付的輸出（只壞在解釋欄的，解釋是佔位字）。 */
  starTitleTechnique: boolean | null;
  starExplanationEnglish: string[] | null;
};

export function inspectOutput(call: PlannedCall, raw: string): Inspection {
  const promptLeak = call.hasPromptLeak(raw);
  const parsed = parseJsonObjectFromText(raw);
  const normalized = normalizeNewTopicModelPayload(parsed, call.grounding);
  // 外洩一律不可用；格式不合格時再看是不是只壞在解釋欄。
  const openings = promptLeak
    ? null
    : normalized.ok
    ? normalized
    : normalizeOpeningsOnly(parsed, call.grounding);
  const normalizeReason = normalized.ok ? null : normalized.reason;
  if (openings === null || !openings.ok) {
    return {
      deliverable: false,
      openingsEvaluable: false,
      promptLeak,
      normalizeReason,
      explanationOnlyFailure: false,
      topics: null,
      recommendationIndex: null,
      recommendationReason: null,
      modelRecommendationIndex: null,
      redCloseOverridden: false,
      audit: null,
      lines: null,
      star: null,
      openingLengths: null,
      starTitleTechnique: null,
      starExplanationEnglish: null,
    };
  }
  const deliverable = normalized.ok;
  const enforced = call.appliesRedClose
    ? enforceNewTopicRedClose(openings, {
      situation: call.situation,
      topicContext: call.topicContext,
    })
    : { normalized: openings, overridden: false };
  const served = enforced.normalized;
  const star = served.topics[served.recommendationIndex];
  const inputText = `${call.partnerSummary ?? ""}\n${
    call.topicContext?.materialText ?? ""
  }`;
  return {
    deliverable,
    openingsEvaluable: true,
    promptLeak,
    normalizeReason,
    explanationOnlyFailure: !deliverable,
    topics: served.topics,
    recommendationIndex: served.recommendationIndex,
    recommendationReason: deliverable ? served.recommendationReason : null,
    modelRecommendationIndex: openings.recommendationIndex,
    redCloseOverridden: enforced.overridden,
    audit: auditNewTopicTwoStageTopics({
      topics: served.topics,
      recommendationIndex: served.recommendationIndex,
      topicContext: call.topicContext,
      situation: call.situation,
    }),
    lines: countLines(served.topics.map((t) => t.openingLine)),
    star: countLines([star.openingLine]),
    openingLengths: served.topics.map((t) =>
      graphemeLength(t.openingLine.replace(/\n/g, ""))
    ),
    starTitleTechnique: deliverable
      ? STAR_TITLE_TECHNIQUE.test(star.direction)
      : null,
    starExplanationEnglish: deliverable
      ? explanationEnglish(
        [star.whyItWorks, star.nextMove, served.recommendationReason ?? ""],
        inputText,
      )
      : null,
  };
}

export type EvalRecord =
  & Omit<PlannedCall, "system" | "hasPromptLeak" | "partnerSummary">
  & {
    status: string;
    inspection: Inspection | null;
    raw?: string;
    stopReason?: string | null;
    usage?: {
      inputTokens: number;
      outputTokens: number;
      cacheReadInputTokens: number;
      cacheCreationInputTokens: number;
    } | null;
    costUsd?: number;
    costKnown?: boolean;
    /** 送出前預留的金額；實付超過它代表 token 估少了（之後的預留已用實測比例調高）。 */
    reservationUsd?: number;
    costExceededReservation?: boolean;
    elapsedMs?: number;
    error?: string;
  };

export function baseRecord(
  call: PlannedCall,
): Omit<EvalRecord, "status" | "inspection"> {
  const {
    system: _system,
    hasPromptLeak: _leak,
    partnerSummary: _partner,
    ...rest
  } = call;
  return rest;
}

// ---------------------------------------------------------------------------
// 機械指標（每臂；可再依基本／進階切）
// ---------------------------------------------------------------------------

/** 解釋為什麼沒回的字眼（道歉、提空窗用 production 稽核的樣式）。 */
const SILENCE_EXPLANATION_PATTERN =
  /斷線|失聯|消失|失蹤|沒回妳|沒回你|晚回|太忙|比較忙|忙到|忙翻|忙瘋/;

/**
 * 我沒回她（ADR #51 產品裁決 5）：一句開場句（可能分兩則傳）有沒有道歉、解釋為什麼沒回，或提空窗。
 * 字面計數只看趨勢。
 */
export function explainsSilence(openingLine: string): boolean {
  return [APOLOGY_PATTERN, GAP_MENTION_PATTERN, SILENCE_EXPLANATION_PATTERN]
    .some((pattern) => pattern.test(openingLine));
}

function percentile(values: number[], p: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(p * sorted.length) - 1)];
}

function cjkBigrams(text: string): Set<string> {
  const bigrams = new Set<string>();
  for (const run of text.match(/\p{Script=Han}+/gu) ?? []) {
    const chars = [...run];
    for (let i = 0; i + 1 < chars.length; i++) {
      bigrams.add(chars[i] + chars[i + 1]);
    }
  }
  return bigrams;
}

export function jaccard(a: string, b: string): number {
  const x = cjkBigrams(a), y = cjkBigrams(b);
  if (x.size === 0 && y.size === 0) return 0;
  let shared = 0;
  for (const bigram of x) if (y.has(bigram)) shared++;
  return shared / (x.size + y.size - shared);
}

/** 同案例第 1、2 次之間的近似重句對數（二字詞 Jaccard ≥ 0.5；開場句可評的輸出）。 */
export function nearDuplicatePairs(rows: EvalRecord[]): number {
  let pairs = 0;
  const byCase = new Map<string, EvalRecord[]>();
  for (const row of rows) {
    if (!row.inspection?.openingsEvaluable || !row.inspection.topics) continue;
    byCase.set(row.caseId, [...(byCase.get(row.caseId) ?? []), row]);
  }
  for (const group of byCase.values()) {
    const sorted = [...group].sort((a, b) => a.attempt - b.attempt);
    for (let i = 0; i < sorted.length; i++) {
      for (let j = i + 1; j < sorted.length; j++) {
        for (const a of sorted[i].inspection!.topics!) {
          for (const b of sorted[j].inspection!.topics!) {
            if (jaccard(a.openingLine, b.openingLine) >= 0.5) pairs++;
          }
        }
      }
    }
  }
  return pairs;
}

export function armMetrics(rows: EvalRecord[]) {
  // 開場句的指標算「開場句可評」（可交付＋只壞在解釋欄：用戶看得到這五句）；★ 解釋的兩項只算可交付。
  const ok = rows.flatMap((r) =>
    r.inspection?.openingsEvaluable && r.inspection.audit
      ? [{ r, a: r.inspection.audit }]
      : []
  );
  const deliverable = ok.filter(({ r }) => r.inspection!.deliverable);
  const sum = (xs: typeof ok, f: (x: typeof ok[number]) => number) =>
    xs.reduce((n, x) => n + f(x), 0);
  const addCounts = (pick: (i: Inspection) => LineCounts | null) => {
    const total = emptyLineCounts();
    for (const { r } of ok) {
      const counts = pick(r.inspection!);
      if (!counts) continue;
      for (const key of Object.keys(total) as (keyof LineCounts)[]) {
        total[key] += counts[key];
      }
    }
    return total;
  };
  const lengths = ok.flatMap(({ r }) => r.inspection!.openingLengths ?? []);
  const redClose = (r: EvalRecord) =>
    isNewTopicRedClose(r.situation, r.topicContext);
  // 分母＝這一臂所有有素材的呼叫；沒跑到、API 失敗、格式壞、外洩都算沒用到。
  const materialTotal =
    rows.filter((r) => r.topicContext?.materialText != null && !redClose(r))
      .length;
  const materialHit =
    ok.filter((x) => x.a.materialUsedInRecommended === true && !redClose(x.r))
      .length;
  const red = ok.filter((x) => x.a.redCloseApplied);
  const lines = addCounts((i) => i.lines);
  return {
    outputs: rows.length,
    modelReturned: rows.filter((r) => r.inspection !== null).length,
    deliverable: deliverable.length,
    openingsEvaluable: ok.length,
    explanationOnlyFailures:
      rows.filter((r) => r.inspection?.explanationOnlyFailure === true).length,
    lines,
    star: addCounts((i) => i.star),
    awkwardPatternLines: awkwardPatternLines(lines),
    nearDuplicatePairs: nearDuplicatePairs(rows),
    openingLength: {
      median: percentile(lengths, 0.5),
      p90: percentile(lengths, 0.9),
      over35: lengths.filter((n) => n > 35).length,
    },
    starTitleTechnique:
      deliverable.filter(({ r }) => r.inspection!.starTitleTechnique).length,
    starExplanationEnglish: sum(
      deliverable,
      ({ r }) => r.inspection!.starExplanationEnglish?.length ?? 0,
    ),
    materialInRecommended: {
      hit: materialHit,
      total: materialTotal,
      /** null＝分母 0、未評估（不是過關）。 */
      pass: materialTotal === 0 ? null : materialHit / materialTotal >= 0.9,
    },
    sheNoReplyGapLines: sum(
      ok.filter((x) => x.r.topicContext?.coldStop === "she_no_reply"),
      (x) => x.a.gapMentionLines,
    ),
    // 我沒回她：道歉、解釋為什麼沒回、提空窗都不寫（ADR #51 產品裁決 5）；五題各算一句。
    iNoReplyExplainLines: sum(
      ok.filter((x) => x.r.topicContext?.coldStop === "i_no_reply"),
      (x) =>
        x.r.inspection!.topics!.filter((t) => explainsSilence(t.openingLine))
          .length,
    ),
    redInviteLines: sum(
      ok.filter((x) => x.r.topicContext?.engagement === "red"),
      (x) => x.a.inviteLines,
    ),
    coldInviteLines: sum(
      ok.filter((x) => x.r.situation === "went_cold"),
      (x) => x.a.inviteLines,
    ),
    /** 基本模式一律不建議約（D9）：基本模式所有句子的邀約字眼。 */
    basicInviteLines: sum(
      ok.filter((x) => x.r.mode === "basic"),
      (x) => x.a.inviteLines,
    ),
    bannedOpenerLines: sum(ok, (x) => x.a.bannedOpenerLines),
    redClose: {
      calls: rows.filter((r) => redClose(r)).length,
      deliverable: red.length,
      modelPickedFirst:
        red.filter((x) => x.r.inspection!.modelRecommendationIndex === 0)
          .length,
      closeCueInFirst: sum(red, (x) => x.a.redCloseCueInFirst ?? 0),
      overridden: red.filter((x) => x.r.inspection!.redCloseOverridden).length,
    },
  };
}

export type ArmMetrics = ReturnType<typeof armMetrics>;

export function metricsByArm(records: EvalRecord[]) {
  const result = {} as Record<
    Arm,
    { all: ArmMetrics; basic: ArmMetrics; advanced: ArmMetrics }
  >;
  for (const arm of ARMS) {
    const rows = records.filter((r) => r.arm === arm);
    result[arm] = {
      all: armMetrics(rows),
      basic: armMetrics(rows.filter((r) => r.mode === "basic")),
      advanced: armMetrics(rows.filter((r) => r.mode === "advanced")),
    };
  }
  return result;
}

/** 每臂的等待時間、停止原因、output token 與實付（模型對照要比的機械項目）。 */
export function armRuntime(rows: EvalRecord[]) {
  const sent = rows.filter((r) => r.status !== "NOT_RUN_CAP_OR_STOP");
  const returned = rows.filter((r) => r.status === "MODEL_RETURNED");
  const elapsed = returned.flatMap((r) =>
    r.elapsedMs === undefined ? [] : [r.elapsedMs]
  );
  const output = returned.flatMap((r) => r.usage ? [r.usage.outputTokens] : []);
  const stop = (reason: string) =>
    returned.filter((r) => r.stopReason === reason).length;
  return {
    sent: sent.length,
    returned: returned.length,
    apiFailed: rows.filter((r) => r.status === "API_FAILED_COST_UNKNOWN")
      .length,
    stopEndTurn: stop("end_turn"),
    stopMaxTokens: stop("max_tokens"),
    stopRefusal: stop("refusal"),
    elapsedMedianMs: percentile(elapsed, 0.5),
    elapsedMaxMs: elapsed.length ? Math.max(...elapsed) : null,
    overDeadline:
      returned.filter((r) =>
        (r.elapsedMs ?? 0) > NEW_TOPIC_GENERATION_DEADLINE_MS
      ).length,
    outputTokensMedian: percentile(output, 0.5),
    outputTokensMax: output.length ? Math.max(...output) : null,
    /** 含成本未知時計入的最壞預留。 */
    costUsd: sent.reduce((n, r) => n + (r.costUsd ?? 0), 0),
    costUnknown: sent.filter((r) => r.costKnown === false).length,
  };
}

export type ArmRuntime = ReturnType<typeof armRuntime>;

export function runtimeByArm(records: EvalRecord[]): Record<Arm, ArmRuntime> {
  return {
    base: armRuntime(records.filter((r) => r.arm === "base")),
    cand: armRuntime(records.filter((r) => r.arm === "cand")),
  };
}

// ---------------------------------------------------------------------------
// 正式驗收的完整度：缺、重複、多出來、沒跑到的都要列出來；有任何一項就不能通過
// ---------------------------------------------------------------------------

export function expectedCodes(
  cases: EvalCase[] = CASES,
  repeat = FORMAL_REPEAT,
): string[] {
  return cases.flatMap((c) =>
    Array.from({ length: repeat }, (_, i) => `${c.id}#${i + 1}`)
  );
}

export function expectedKeys(
  cases: EvalCase[] = CASES,
  repeat = FORMAL_REPEAT,
): string[] {
  return expectedCodes(cases, repeat).flatMap((code) => {
    const [id, attempt] = code.split("#");
    return ARMS.map((arm) => `${id}.${attempt}.${arm}`);
  });
}

/** 清單太長只列前幾個。 */
export function listSome(items: string[], max = 8): string {
  return items.length <= max
    ? items.join("、")
    : `${items.slice(0, max).join("、")}…等 ${items.length} 個`;
}

/** 找出缺少、多出來與重複的項目（重複＝出現超過一次）。 */
export function setProblems(
  label: string,
  got: string[],
  expected: string[],
): string[] {
  const want = new Set(expected);
  const seen = new Map<string, number>();
  for (const item of got) seen.set(item, (seen.get(item) ?? 0) + 1);
  const missing = expected.filter((item) => !seen.has(item));
  const extra = [...seen.keys()].filter((item) => !want.has(item));
  const duplicate = [...seen].filter(([, n]) => n > 1).map(([item]) => item);
  return [
    ...(missing.length
      ? [`${label}少了 ${missing.length} 個：${listSome(missing)}`]
      : []),
    ...(extra.length
      ? [`${label}多出 ${extra.length} 個：${listSome(extra)}`]
      : []),
    ...(duplicate.length
      ? [`${label}重複 ${duplicate.length} 個：${listSome(duplicate)}`]
      : []),
  ];
}

/**
 * records 能不能當正式驗收：每個（案例, 第幾次, 臂）剛好一筆，而且模型都有回（格式壞掉也算有回，
 * 會照實算進可交付率）。回傳問題清單；空的才算完整。
 */
export function recordProblems(
  records: EvalRecord[],
  cases: EvalCase[] = CASES,
  repeat = FORMAL_REPEAT,
): string[] {
  const notReturned = records.filter((r) => r.status !== "MODEL_RETURNED");
  return [
    ...setProblems(
      "records ",
      records.map((r) => r.key),
      expectedKeys(cases, repeat),
    ),
    ...(notReturned.length
      ? [
        `模型沒有回的呼叫 ${notReturned.length} 個：${
          listSome(notReturned.map((r) => `${r.key}（${r.status}）`))
        }`,
      ]
      : []),
  ];
}

/** 規格 §6.5 第 5、6 項：能機械判定的門檻（null＝沒有資料可判）。 */
export function mechanicalAcceptance(
  m: Record<Arm, { all: ArmMetrics }>,
) {
  const base = m.base.all, cand = m.cand.all;
  const rate = (x: ArmMetrics) =>
    x.outputs === 0 ? null : x.deliverable / x.outputs;
  const baseRate = rate(base), candRate = rate(cand);
  return {
    deliverableRate: {
      base: baseRate,
      cand: candRate,
      pass: baseRate === null || candRate === null
        ? null
        : candRate >= baseRate,
    },
    multiQuestionLines: {
      cand: cand.lines.multiQuestionLines,
      pass: cand.lines.multiQuestionLines === 0,
    },
    // 候選 < 基準；基準已是 0 時候選也是 0 就算過（嚴格小於做不到；ADR #51 產品裁決 4）。
    awkwardPatternLines: {
      base: base.awkwardPatternLines,
      cand: cand.awkwardPatternLines,
      pass: cand.awkwardPatternLines < base.awkwardPatternLines ||
        (base.awkwardPatternLines === 0 && cand.awkwardPatternLines === 0),
    },
    nearDuplicatePairs: {
      base: base.nearDuplicatePairs,
      cand: cand.nearDuplicatePairs,
      pass: cand.nearDuplicatePairs <= base.nearDuplicatePairs * 1.5,
    },
    over35: {
      base: base.openingLength.over35,
      cand: cand.openingLength.over35,
      pass: cand.openingLength.over35 <= base.openingLength.over35,
    },
    starTitleTechnique: {
      cand: cand.starTitleTechnique,
      pass: cand.starTitleTechnique === 0,
    },
    starExplanationEnglish: {
      cand: cand.starExplanationEnglish,
      pass: cand.starExplanationEnglish === 0,
    },
  };
}

// ---------------------------------------------------------------------------
// 盲測（給 Bruce）：一份表，每組兩版依 seed 打亂成甲／乙、逐句勾選；解盲表另存
// ---------------------------------------------------------------------------

/** mulberry32：同 seed 同順序。 */
function seededRandom(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = Math.imul(s ^ (s >>> 15), s | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 盲測表的固定字（tally.ts 照這些字解析；改字要一起改）。 */
export const BLIND_FORM = {
  willing: "會傳",
  awkward: "尷尬",
  untrue: "不實",
  fun: "有一句有趣或有個性",
  favorite: "- 十句裡最想傳（填代號如「乙3」；都不想傳填「都不要」）：",
  favoriteNone: "都不要",
  done: "這組評完了",
  noOutput: "（這一版沒有產出可用的五題）",
} as const;

/** 表上的一句：分兩則傳的用 ⏎ 接起來（tally.ts 用它核對表上的句子跟 records 一樣）。 */
export function blindLineText(openingLine: string): string {
  return openingLine.replace(/\n/g, " ⏎ ");
}

const BLIND_INTRO = [
  "# 新話題盲測",
  "",
  "每組是同一個情境的兩版：甲、乙（順序已打亂），各五句開場句。全部評完再看解盲表。",
  "",
  "**怎麼填**：把「[ ]」改成「[x]」，沒勾＝沒有。",
  "",
  "- 每一句三格，各自判斷：",
  `  - ${BLIND_FORM.willing}：你會照原樣直接傳給她。`,
  `  - ${BLIND_FORM.awkward}：讀起來尷尬，例如要猜意思、莫名被評斷或被安排角色、硬編情境。`,
  `  - ${BLIND_FORM.untrue}：寫了上面資料沒有的事，或越界。例如把她的興趣寫成她做過、說過、擁有的事；編你們之間或約會時發生的事；把誰說的、誰做的、被虧的是誰弄反；性化、施壓、冷掉時約她。`,
  `- 每一版：五句裡至少一句有趣或有個性，就勾「${BLIND_FORM.fun}」。`,
  "- 每一組最後：",
  `  - 「十句裡最想傳」填一句的代號（例：乙3）；都不想傳就填「${BLIND_FORM.favoriteNone}」。`,
  `  - 整組看完、勾完，再勾「${BLIND_FORM.done}」。沒勾的組算「未評」，不計分，也不會當成「沒有」。`,
  "- ⏎＝分成兩則傳。表上不標推薦句：推薦句的會傳、尷尬，解盲後從你的逐句勾選算。",
  "- 只改方框和「＿」，不要改句子、組別或甲乙順序。",
  "",
];

function pairedCodes(records: EvalRecord[], cases: EvalCase[]) {
  const pairs: Array<{ c: EvalCase; attempt: number; pair: EvalRecord[] }> = [];
  const unpaired: string[] = [];
  for (const c of cases) {
    const attempts = [
      ...new Set(
        records.filter((r) => r.caseId === c.id).map((r) => r.attempt),
      ),
    ].sort((a, b) => a - b);
    for (const attempt of attempts) {
      const pair = ARMS.map((arm) =>
        records.find((r) =>
          r.caseId === c.id && r.attempt === attempt && r.arm === arm
        )
      );
      if (pair.some((r) => !r || r.inspection === null)) {
        unpaired.push(`${c.id}#${attempt}`);
        continue;
      }
      pairs.push({ c, attempt, pair: pair as EvalRecord[] });
    }
  }
  return { pairs, unpaired };
}

function caseHeader(c: EvalCase): string[] {
  const lines = [
    "對象資料：",
    "```",
    c.partner === null ? "（沒有對象資料）" : PARTNERS[c.partner],
    "```",
    `用戶的回答：${c.label}`,
  ];
  if (c.topicContext?.materialText) {
    lines.push(`用戶寫的那句：「${c.topicContext.materialText}」`);
  }
  return lines;
}

export function blindForm(
  records: EvalRecord[],
  cases: EvalCase[],
  seed: number,
) {
  const rand = seededRandom(seed);
  const reveal: Record<string, { 甲: Arm; 乙: Arm }> = {};
  const { pairs, unpaired } = pairedCodes(records, cases);
  const form = [...BLIND_INTRO];
  for (const { c, attempt, pair } of pairs) {
    const code = `${c.id}#${attempt}`;
    const order = rand() < 0.5 ? pair : [pair[1], pair[0]];
    reveal[code] = { 甲: order[0].arm, 乙: order[1].arm };
    form.push(`## ${code}`, "", ...caseHeader(c), "");
    for (const [i, name] of (["甲", "乙"] as const).entries()) {
      const ins = order[i].inspection!;
      form.push(`### ${name}`);
      // 只壞在解釋欄的照樣列五句（production 修格式會逐字保留）；推薦位置由 tally 取 records。
      if (!ins.openingsEvaluable || !ins.topics) {
        form.push(BLIND_FORM.noOutput, "");
        continue;
      }
      ins.topics.forEach((t, n) =>
        form.push(
          `- ${name}${
            n + 1
          } [ ]${BLIND_FORM.willing} [ ]${BLIND_FORM.awkward} [ ]${BLIND_FORM.untrue}｜${
            blindLineText(t.openingLine)
          }`,
        )
      );
      form.push(`- [ ] ${name}${BLIND_FORM.fun}`, "");
    }
    form.push(
      `${BLIND_FORM.favorite}＿`,
      `- [ ] ${BLIND_FORM.done}（沒勾＝未評，整組不計分）`,
      "",
    );
  }
  return { markdown: form.join("\n"), reveal, unpaired };
}

// ---------------------------------------------------------------------------
// summary
// ---------------------------------------------------------------------------

/** 資料不完整時一律標「未完成」，不管數字看起來過不過。 */
export function acceptanceMark(
  pass: boolean | null,
  complete: boolean,
): string {
  if (!complete) return "未完成";
  return pass === null ? "未評估" : pass ? "✓" : "✗";
}
const pct = (x: number | null) => x === null ? "—" : `${(x * 100).toFixed(0)}%`;

export function summaryMarkdown(input: {
  tag: string;
  candidateHead: string;
  baseSha: string | null;
  now: string;
  calls: number;
  planned: number;
  spentUsd: number;
  budgetUsd: number | null;
  stopped: boolean;
  records: EvalRecord[];
  unpaired: string[];
  comparison?: Comparison;
}): string {
  const comparison = input.comparison ?? "prompt";
  const modelCompare = comparison === "model";
  const m = metricsByArm(input.records);
  const runtime = runtimeByArm(input.records);
  const acc = mechanicalAcceptance(m);
  const problems = recordProblems(input.records);
  const complete = problems.length === 0;
  const mark = (pass: boolean | null) => acceptanceMark(pass, complete);
  const overReservation =
    input.records.filter((r) => r.costExceededReservation === true).length;
  const row = (
    label: string,
    f: (x: ArmMetrics) => string | number,
  ) =>
    `| ${label} | ${f(m.base.all)} | ${f(m.cand.all)} | ${f(m.base.basic)} | ${
      f(m.cand.basic)
    } | ${f(m.base.advanced)} | ${f(m.cand.advanced)} |`;
  const runtimeRow = (
    label: string,
    f: (x: ArmRuntime) => string | number,
  ) => `| ${label} | ${f(runtime.base)} | ${f(runtime.cand)} |`;
  const seconds = (ms: number | null) =>
    ms === null ? "—" : `${(ms / 1000).toFixed(1)} 秒`;
  const overDeadline =
    input.records.filter((r) =>
      (r.elapsedMs ?? 0) > NEW_TOPIC_GENERATION_DEADLINE_MS
    ).length;
  const baseModel = armModel(comparison, "base");
  const candModel = armModel(comparison, "cand");
  const armNames = modelCompare
    ? `base＝${baseModel}、cand＝${candModel}，同一份提示詞`
    : "base＝改前、cand＝改後";
  return [
    modelCompare
      ? `# 新話題模型對照 · ${input.tag} · ${baseModel} vs ${candModel}`
      : `# 新話題成對評測 · ${input.tag} · ${MODEL}`,
    "",
    modelCompare
      ? `- 兩臂同一份提示詞：HEAD ${input.candidateHead}（${NEW_TOPIC_TWO_STAGE_PROMPT_VERSION}，今天＝${input.now}），只差模型與模型參數（model_request_params）。`
      : `- 候選 HEAD ${input.candidateHead}（提示詞 ${NEW_TOPIC_TWO_STAGE_PROMPT_VERSION}，今天＝${input.now}）；基準 ${
        input.baseSha ?? "（沒跑基準臂）"
      }。`,
    `- 實際呼叫 ${input.calls}／規劃 ${input.planned}；計入費用 $${
      input.spentUsd.toFixed(3)
    }（預算 $${input.budgetUsd}，依估計 token 守門、不是嚴格上限；含成本未知的最壞情況）；實付超過預留 ${overReservation} 次；提前停止：${
      input.stopped ? "是" : "否"
    }；超過 production 45 秒期限 ${overDeadline} 次。`,
    modelCompare
      ? "- **這是已知問題的小型診斷（--compare=model），不是 §6.5 驗收，也不是沒看過的案例測試。** 不實、主詞與邏輯、尷尬、推薦能不能原樣傳，要看 records 逐句判斷。"
      : complete
      ? "- 正式驗收資格：資料完整（22 組 × 2 次 × 兩臂，模型都有回）。"
      : `- **正式驗收資格：未完成，不能當正式驗收。** ${problems.join("；")}`,
    "",
    "## 時間與費用（每臂）",
    "",
    `| 項目 | base（${baseModel}） | cand（${candModel}） |`,
    "|---|---|---|",
    runtimeRow(
      "送出／模型有回／API 失敗",
      (x) => `${x.sent}／${x.returned}／${x.apiFailed}`,
    ),
    runtimeRow(
      "停止原因 end_turn／max_tokens／refusal",
      (x) => `${x.stopEndTurn}／${x.stopMaxTokens}／${x.stopRefusal}`,
    ),
    runtimeRow(
      "等待 中位數／最慢／超過 45 秒",
      (x) =>
        `${seconds(x.elapsedMedianMs)}／${
          seconds(x.elapsedMaxMs)
        }／${x.overDeadline}`,
    ),
    runtimeRow(
      "output token 中位數／最多（5.5 含思考）",
      (x) => `${x.outputTokensMedian ?? "—"}／${x.outputTokensMax ?? "—"}`,
    ),
    runtimeRow(
      "實付合計／平均每次（成本未知筆數）",
      (x) =>
        `$${x.costUsd.toFixed(4)}／$${
          x.sent ? (x.costUsd / x.sent).toFixed(4) : "—"
        }（${x.costUnknown}）`,
    ),
    "",
    `## 機械指標（${armNames}）`,
    "",
    "開場句的指標算「開場句可評」的輸出（可交付＋只壞在解釋欄：用戶看得到這五句）；★ 解釋兩項只算可交付。",
    "",
    "| 指標 | base 全部 | cand 全部 | base 基本 | cand 基本 | base 進階 | cand 進階 |",
    "|---|---|---|---|---|---|---|",
    row("可交付／輸出", (x) => `${x.deliverable}/${x.outputs}`),
    row("開場句可評／輸出", (x) => `${x.openingsEvaluable}/${x.outputs}`),
    row("只壞在解釋欄（修格式會保留開場句）", (x) => x.explanationOnlyFailures),
    row("問句", (x) => x.lines.questionLines),
    row("一則兩個以上問句", (x) => x.lines.multiQuestionLines),
    row("假設情境", (x) => x.lines.hypotheticalLines),
    row("安排角色", (x) => x.lines.roleAssignLines),
    row("貼標籤／說她是哪種人", (x) => x.lines.labelJudgmentLines),
    row("比能力", (x) => x.lines.abilityRankLines),
    row("四種尷尬句型合計", (x) => x.awkwardPatternLines),
    row("宣告套話（觀察）", (x) => x.lines.declarationLines),
    row(
      "★ 問句／尷尬句型",
      (x) => `${x.star.questionLines}／${awkwardPatternLines(x.star)}`,
    ),
    row("同案例兩次之間的近似重句對", (x) => x.nearDuplicatePairs),
    row(
      "開場句字數 中位數／P90／超過 35",
      (x) =>
        `${x.openingLength.median ?? "—"}／${
          x.openingLength.p90 ?? "—"
        }／${x.openingLength.over35}`,
    ),
    row("★ 標題有手法字", (x) => x.starTitleTechnique),
    row("★ 解釋夾英文（處）", (x) => x.starExplanationEnglish),
    row(
      "推薦題用到素材（分母含失敗）",
      (x) => `${x.materialInRecommended.hit}/${x.materialInRecommended.total}`,
    ),
    row("她沒回我：提空窗", (x) => x.sheNoReplyGapLines),
    row("我沒回她：道歉、解釋或提空窗", (x) => x.iNoReplyExplainLines),
    row("紅燈：邀約字眼", (x) => x.redInviteLines),
    row("冷掉了：邀約字眼", (x) => x.coldInviteLines),
    row("基本模式：邀約字眼（D9）", (x) => x.basicInviteLines),
    row("在嗎／最近好嗎類", (x) => x.bannedOpenerLines),
    row(
      "紅燈收尾：模型推第一題／伺服器改推",
      (x) =>
        `${x.redClose.modelPickedFirst}／${x.redClose.overridden}（共 ${x.redClose.deliverable}）`,
    ),
    "",
    ...(modelCompare
      ? [
        "## 這份不判定門檻",
        "",
        "模型對照不套 §6.5，也不能取代合併驗收。上面的可交付、字面計數、時間與費用只是機械項目；哪一臂比較好，由 Eric 方看 records 逐句判斷，再決定要不要安排人評。",
      ]
      : [
        "## 規格 §6.5 驗收門檻",
        "",
        "| 門檻 | 結果 |",
        "|---|---|",
        "| 1. 不實（捏造、主詞弄反、越界）：候選 0 句（硬性） | 待 Bruce 盲測＋逐句對照輸入（tally.ts） |",
        "| 2. 尷尬句數：候選 ≤ 基準一半；★ 尷尬：候選次數 ≤ 基準、且至多 1 個情境 | 待 Bruce 盲測（tally.ts） |",
        "| 3. 會傳句數、★ 會傳次數：候選 ≥ 基準；基本、進階分開看，任一邊退步要交代 | 待 Bruce 盲測（tally.ts） |",
        "| 4. 有一句有趣的版本數：候選 ≥ 基準八成；B3、J1、E3 候選每次都要有 | 待 Bruce 盲測（tally.ts） |",
        `| 5a. 可交付率候選 ≥ 基準 | ${mark(acc.deliverableRate.pass)} ${
          pct(acc.deliverableRate.cand)
        } vs ${pct(acc.deliverableRate.base)} |`,
        `| 5b. 一則兩個以上問句：候選 0 | ${
          mark(acc.multiQuestionLines.pass)
        } ${acc.multiQuestionLines.cand} |`,
        `| 5c. 四種尷尬句型合計：候選 < 基準（基準已是 0 時候選也要 0） | ${
          mark(acc.awkwardPatternLines.pass)
        } ${acc.awkwardPatternLines.cand} vs ${acc.awkwardPatternLines.base} |`,
        `| 5d. 近似重句：候選 ≤ 基準 × 1.5 | ${
          mark(acc.nearDuplicatePairs.pass)
        } ${acc.nearDuplicatePairs.cand} vs ${acc.nearDuplicatePairs.base} |`,
        `| 5e. 超過 35 字：候選 ≤ 基準 | ${
          mark(acc.over35.pass)
        } ${acc.over35.cand} vs ${acc.over35.base} |`,
        `| 6a. ★ 標題手法字：候選 0（命中要人工確認） | ${
          mark(acc.starTitleTechnique.pass)
        } ${acc.starTitleTechnique.cand} |`,
        `| 6b. ★ 解釋夾英文：候選 0（命中要人工確認） | ${
          mark(acc.starExplanationEnglish.pass)
        } ${acc.starExplanationEnglish.cand} |`,
      ]),
    "",
    "字面計數只看趨勢，不是語意判定；用戶講自己的句子也可能被算到。只壞在解釋欄的那一版，★ 用主呼叫自己的推薦（production 修格式那一次會重選，可能不同）。",
    input.unpaired.length
      ? `未成對、沒進盲測：${input.unpaired.join("、")}`
      : "所有組都已成對進盲測。",
    "",
  ].join("\n");
}

// ---------------------------------------------------------------------------
// 執行
// ---------------------------------------------------------------------------

async function main(args: string[]): Promise<void> {
  const opts = parseOptions(args);
  const selected = CASES.filter((c) => !opts.only || opts.only.includes(c.id));
  const out = new URL(`./out/${opts.tag}/`, import.meta.url);
  // 不覆寫任何既有證據（dry-run 或付費）。
  try {
    await Deno.stat(out);
    throw new Error(`輸出目錄已存在，請換 --tag：${out.pathname}`);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }

  const candidateHead = await git(["rev-parse", "HEAD"]);
  const dirty =
    (await git(["status", "--porcelain", "--untracked-files=no"])).length > 0;
  if (opts.run && dirty) {
    throw new Error(
      "真跑前要先 commit：追蹤檔有未提交修改，結果無法對應工程版本",
    );
  }
  const routers: Partial<Record<Arm, ArmRouter>> = {};
  let baseSha: string | null = null;
  if (opts.compare === "model") {
    // 模型對照：兩臂同一份提示詞（目前工作樹的 planNewTopicPrompt），不取改前版本。
    for (const arm of opts.arms) routers[arm] = candRouter(opts.nowMs);
  } else {
    if (opts.arms.includes("base")) {
      const base = await materializeRef(opts.baseRef);
      baseSha = base.sha;
      routers.base = baseRouter(await loadBaseModules(base.root));
    }
    if (opts.arms.includes("cand")) routers.cand = candRouter(opts.nowMs);
  }
  const plan = await buildPlan(
    selected,
    opts.repeat,
    routers,
    opts.arms,
    opts.compare,
  );
  const estimate = estimatePlan(plan);

  let apiKey = "";
  if (opts.run) {
    apiKey =
      (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`))
        .trim();
    if (!apiKey) throw new Error("金鑰檔是空的");
  }

  await Deno.mkdir(out, { recursive: true });
  const write = (name: string, value: unknown) =>
    Deno.writeTextFile(
      new URL(name, out),
      typeof value === "string" ? value : JSON.stringify(value, null, 2) + "\n",
    );
  const systemPrompts: Record<string, string> = {};
  for (const call of plan) {
    systemPrompts[await sha256(call.system)] = call.system;
  }
  const sampleBody = requestBody({ system: "<system>", user: "<user>" });
  // 每一臂實際送出的 body 形狀（system／user 換成佔位）：模型對照兩臂只差 model 與模型參數。
  const armRequests = Object.fromEntries(opts.arms.map((arm) => {
    const model = armModel(opts.compare, arm);
    return [arm, {
      model,
      prompt: opts.compare === "model" || arm === "cand"
        ? `HEAD planNewTopicPrompt（${NEW_TOPIC_TWO_STAGE_PROMPT_VERSION}，今天＝${opts.now}）`
        : `基準 ${baseSha} 的 handler 路由（git archive）`,
      bodyShape: requestBody({ system: "<system>", user: "<user>", model }),
      pricing: pricingFor(model),
      typicalOutputTokens: typicalOutputTokensFor(model),
      maxOutputTokens: maxOutputTokensFor(model),
    }];
  }));
  const manifest = {
    status: opts.run ? "RUNNING" : "DRY_RUN_NO_MODEL",
    startedAt: new Date().toISOString(),
    candidateHead,
    candidateDirty: dirty,
    comparison: opts.compare,
    baseRef: opts.compare === "model" ? null : opts.baseRef,
    baseSha,
    now: opts.now,
    model: MODEL,
    armRequests,
    request: {
      headers: REQUEST_HEADERS,
      bodyShape: sampleBody,
      note:
        "同 production 主呼叫（fallback.ts 第一跳）；每次只送一次：不重試、不修格式、不串流、不走備援；API 失敗照最壞預留計費並整批停",
    },
    candidatePromptVersion: NEW_TOPIC_TWO_STAGE_PROMPT_VERSION,
    sha256: {
      cases: await catalogSha256(),
      systemPrompts: Object.keys(systemPrompts),
      userPrompts: await sha256(
        JSON.stringify(plan.map((call) => [call.key, call.user])),
      ),
    },
    pricing: PRICING,
    estimate: {
      ...estimate,
      method:
        `input＝字數×${CJK_TOKENS_PER_CHAR}（估計，不是 tokenizer），全部用該模型最高的 input 單價（快取寫入）；output 一般＝${TYPICAL_OUTPUT_TOKENS}（5.5 另加思考 ${SONNET_5_5_TYPICAL_THINKING_TOKENS}，未實測）、最壞＝該模型 max_tokens 全滿`,
      guard:
        "每次送出前預留＝估計 input×最高 input 單價＋該模型 max_tokens 全滿；已花費＋預留超過 --budget-usd 就整批停。真跑時每字 token 數取 1.5 與實測的較大值。token 是估的，預算不是嚴格上限。",
    },
    options: {
      ...opts,
      nowMs: undefined,
      // 模型對照沒有用到改前版本，不記預設的基準 ref，免得看起來像有比到。
      baseRef: opts.compare === "model" ? null : opts.baseRef,
    },
  };
  await write("manifest.json", manifest);
  await write("system-prompts.json", systemPrompts);
  await write(
    "prompts.json",
    await Promise.all(plan.map(async (call) => ({
      ...baseRecord(call),
      systemPromptSha256: await sha256(call.system),
      estInputTokens: estimateInputTokens(call),
    }))),
  );

  if (!opts.run) {
    const caps = opts.budgetUsd === null
      ? ""
      : `；--budget-usd=${opts.budgetUsd} ${
        estimate.worstUsd <= opts.budgetUsd ? "涵蓋" : "不足以涵蓋"
      }最壞情況`;
    console.log(`=== 估算（dry-run，實際模型呼叫 0）===`);
    console.log(
      `${
        opts.compare === "model" ? "模型對照（兩臂同一份提示詞）" : "提示詞對照"
      }：案例 ${selected.length} × 重複 ${opts.repeat} × ${opts.arms.length} 臂（${
        opts.arms.join("、")
      }）= ${estimate.calls} 次呼叫${caps}`,
    );
    for (const arm of opts.arms) {
      const armEstimate = estimate.byArm[arm]!;
      const { system: _system, messages: _messages, ...params } =
        armRequests[arm].bodyShape;
      console.log(
        `${arm}（${
          armRequests[arm].model
        }）：${armEstimate.calls} 次；送出參數 ${
          JSON.stringify(params)
        }；預估 一般 $${armEstimate.typicalUsd.toFixed(2)}／最壞 $${
          armEstimate.worstUsd.toFixed(2)
        }`,
      );
    }
    console.log(
      `預估 input ${estimate.inputTokens} tokens；output 一般 ${estimate.typicalOutputTokens}／最壞 ${estimate.worstOutputTokens}`,
    );
    console.log(
      `預估費用 一般 $${estimate.typicalUsd.toFixed(2)}／最壞 $${
        estimate.worstUsd.toFixed(2)
      }（input 全部用該模型的快取寫入價、output 照該模型單價；token 是字數估的，不是嚴格上限）`,
    );
    console.log(JSON.stringify({
      status: "DRY_RUN_NO_MODEL",
      comparison: opts.compare,
      candidateHead,
      baseSha,
      cases: selected.length,
      repeat: opts.repeat,
      arms: opts.arms,
      calls: estimate.calls,
      typicalUsd: Number(estimate.typicalUsd.toFixed(4)),
      worstUsd: Number(estimate.worstUsd.toFixed(4)),
      modelCallsMade: 0,
      output: out.pathname,
    }));
    return;
  }

  const records: EvalRecord[] = [];
  let calls = 0, spentUsd = 0, stopped = false;
  // 每字 token 數：先用 1.5，每次回來用實測更新（只會變大），之後的預留跟著變大。
  let tokensPerChar = CJK_TOKENS_PER_CHAR;
  const log = (value: unknown) =>
    Deno.writeTextFile(
      new URL("requests.jsonl", out),
      JSON.stringify(value) + "\n",
      { append: true },
    );
  for (const call of plan) {
    const base = baseRecord(call);
    // 每次送出前預留最壞情況（估計 input×快取寫入價＋max_tokens 全滿）；超過上限就整批停，不再送新呼叫。
    const reservation = reservationUsd(call, tokensPerChar);
    if (
      stopBeforeCall({
        stopped,
        calls,
        maxCalls: opts.maxCalls!,
        spentUsd,
        reservationUsd: reservation,
        budgetUsd: opts.budgetUsd!,
      })
    ) {
      stopped = true;
      records.push({
        ...base,
        status: "NOT_RUN_CAP_OR_STOP",
        inspection: null,
      });
      continue;
    }
    calls++;
    await log({
      key: call.key,
      call: calls,
      reservationUsd: reservation,
      tokensPerChar,
      state: "SENDING",
    });
    const started = Date.now();
    let record: EvalRecord;
    try {
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { ...REQUEST_HEADERS, "x-api-key": apiKey },
        body: JSON.stringify(requestBody(call)),
        signal: AbortSignal.timeout(API_TIMEOUT_MS),
      });
      const data = await response.json().catch(() => null);
      if (!response.ok || data === null) {
        throw new Error(
          `HTTP ${response.status} ${data?.error?.type ?? ""}`.trim(),
        );
      }
      // 取文字同 production 一般路徑（5.5 的思考區塊不算進來）。
      const raw = extractClaudeText(data);
      const u = data.usage;
      const int = (value: unknown) =>
        Number.isInteger(value) ? value as number : 0;
      const usage =
        Number.isInteger(u?.input_tokens) && Number.isInteger(u?.output_tokens)
          ? {
            inputTokens: u.input_tokens as number,
            outputTokens: u.output_tokens as number,
            cacheReadInputTokens: int(u.cache_read_input_tokens),
            cacheCreationInputTokens: int(u.cache_creation_input_tokens),
          }
          : null;
      // usage 缺漏＝成本未知：以最壞情況計入並停止，不當免費。
      if (!usage) stopped = true;
      else tokensPerChar = calibratedTokensPerChar(tokensPerChar, call, usage);
      const costUsd = usage
        ? usd(
          usage.inputTokens,
          usage.outputTokens,
          usage.cacheReadInputTokens,
          usage.cacheCreationInputTokens,
          call.model,
        )
        : reservation;
      spentUsd += costUsd;
      record = {
        ...base,
        status: "MODEL_RETURNED",
        stopReason: data.stop_reason ?? null,
        usage,
        costUsd,
        costKnown: usage !== null,
        reservationUsd: reservation,
        costExceededReservation: costUsd > reservation,
        elapsedMs: Date.now() - started,
        raw,
        inspection: inspectOutput(call, raw),
      };
    } catch (error) {
      spentUsd += reservation;
      stopped = true;
      record = {
        ...base,
        status: "API_FAILED_COST_UNKNOWN",
        error: String(error).slice(0, 300),
        costUsd: reservation,
        costKnown: false,
        reservationUsd: reservation,
        elapsedMs: Date.now() - started,
        inspection: null,
      };
    }
    records.push(record);
    await log({
      key: call.key,
      call: calls,
      state: record.status,
      costUsd: record.costUsd,
      costExceededReservation: record.costExceededReservation ?? false,
    });
    await write("records.json", records);
  }

  const blind = blindForm(records, selected, opts.seed);
  await write("records.json", records);
  await write("blind.md", blind.markdown);
  await write("reveal-map.json", blind.reveal);
  const status = stopped
    ? "STOPPED_BY_CAP_OR_FAILURE"
    : "FINISHED_QUALITY_UNREVIEWED";
  const formalProblems = recordProblems(records);
  const summary = summaryMarkdown({
    tag: opts.tag,
    candidateHead,
    baseSha,
    now: opts.now,
    calls,
    planned: plan.length,
    spentUsd,
    budgetUsd: opts.budgetUsd,
    stopped,
    records,
    unpaired: blind.unpaired,
    comparison: opts.compare,
  });
  await write("summary.md", summary);
  await write("manifest.json", {
    ...manifest,
    status,
    finishedAt: new Date().toISOString(),
    modelCallsMade: calls,
    spentUsd,
    finalTokensPerChar: tokensPerChar,
    // 模型對照不是正式驗收（tally.ts 也會擋）。
    formalComplete: opts.compare === "prompt" && formalProblems.length === 0,
    formalProblems,
    metrics: metricsByArm(records),
    runtime: runtimeByArm(records),
  });
  console.log(summary);
  console.log(
    JSON.stringify({
      status,
      modelCallsMade: calls,
      spentUsd: Number(spentUsd.toFixed(4)),
      stopped,
      output: out.pathname,
    }),
  );
}

if (import.meta.main) await main(Deno.args);

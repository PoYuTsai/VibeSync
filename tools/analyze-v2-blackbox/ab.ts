// Sonnet 5 → 5.5 分析 A/B（2026-10-02）：臂定義、交錯計畫、估價、付費閘、SSE 觀測、
// 每臂彙總、Eric 盲選表。全是純函式、不打網路；真呼叫在 run_blackbox.ts。
import { CORPUS } from "./corpus.ts";
import { evaluateArtifact } from "./evaluate.ts";
import {
  estimateCostUsd,
  SONNET_5_5_PRICING,
  SONNET_5_PRICING,
  type TokenPricing,
} from "../../supabase/functions/_shared/model_pricing.ts";
import { SEMANTIC_CRITIC_MAX_TOKENS } from "../../supabase/functions/_shared/social/semantic_critic.ts";
import {
  maxTokensFor,
  SONNET_5_5_THINKING_HEADROOM_TOKENS,
} from "../../supabase/functions/_shared/model_request_params.ts";

export type ArmId = "A" | "B" | "C";

export interface ArmSpec {
  readonly model: string;
  readonly label: string;
  /// 只有 B：在 fetch 層把 production 組好的 body 改回舊設定。A／C 原樣送出。
  readonly override?: {
    readonly thinking: Readonly<Record<string, unknown>>;
    readonly effort: string;
    readonly extraMaxTokens: number;
  };
}

export const ARMS: Readonly<Record<ArmId, ArmSpec>> = {
  A: {
    model: "claude-sonnet-5",
    label: "Sonnet 5，production 原樣（thinking disabled）",
  },
  B: {
    model: "claude-sonnet-5-5",
    label:
      "Sonnet 5.5，舊 helper（thinking between_tools＋effort medium，max_tokens 不變）",
    override: {
      thinking: { type: "between_tools" },
      effort: "medium",
      extraMaxTokens: -SONNET_5_5_THINKING_HEADROOM_TOKENS,
    },
  },
  C: {
    model: "claude-sonnet-5-5",
    label:
      "Sonnet 5.5，production helper（adaptive thinking＋display omitted＋effort low＋max_tokens +4000）",
  },
};

/// 評審固定 Sonnet 5，不跟著臂換（否則變成 5.5 自己評自己）。
export const JUDGE_MODEL = "claude-sonnet-5";
/// critic 每案實測約 2k 輸入 token（README 3d 首輪），估價取 2 倍。
export const JUDGE_INPUT_TOKENS_EST = 4000;
export const BLIND_SEED = 20261002;
export const BLIND_CASES = 10;

export function applyArmOverride(
  body: Record<string, unknown>,
  arm: ArmSpec,
): Record<string, unknown> {
  const o = arm.override;
  if (!o) return body;
  return {
    ...body,
    max_tokens: Number(body.max_tokens) + o.extraMaxTokens,
    thinking: o.thinking,
    output_config: {
      ...(body.output_config as Record<string, unknown> | undefined),
      effort: o.effort,
    },
  };
}

export function parseArms(value = "A,B"): ArmId[] {
  const arms = [
    ...new Set(value.split(",").map((s) => s.trim()).filter(Boolean)),
  ];
  for (const arm of arms) {
    if (!(arm in ARMS)) throw new Error(`unknown arm: ${arm}`);
  }
  if (arms.length === 0) throw new Error("--arms is empty");
  return arms as ArmId[];
}

function positiveInt(value: string): number {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1) throw new Error(`bad repeat: ${value}`);
  return n;
}

/// `--repeat=2`（每臂同次數）或 `--repeat=A:2,B:2,C:1`（沒列到的臂 1 次）。
export function parseRepeat(
  value: string | undefined,
  arms: readonly ArmId[],
): Record<ArmId, number> {
  const out = Object.fromEntries(arms.map((a) => [a, 1])) as Record<
    ArmId,
    number
  >;
  if (!value) return out;
  if (!value.includes(":")) {
    const n = positiveInt(value);
    for (const arm of arms) out[arm] = n;
    return out;
  }
  for (const part of value.split(",")) {
    const [arm, n] = part.split(":");
    if (!arms.includes(arm as ArmId)) {
      throw new Error(`repeat for arm not in --arms: ${arm}`);
    }
    out[arm as ArmId] = positiveInt(n);
  }
  return out;
}

export interface PlannedCall {
  readonly caseId: string;
  readonly arm: ArmId;
  readonly rep: number;
}

/// 每案內交錯：第 rep 輪依（案序＋rep）輪轉臂的先後，沒有哪一臂固定先跑。
export function planCalls(
  caseIds: readonly string[],
  arms: readonly ArmId[],
  repeat: Readonly<Record<ArmId, number>>,
): PlannedCall[] {
  const calls: PlannedCall[] = [];
  const maxRep = Math.max(...arms.map((a) => repeat[a]));
  caseIds.forEach((caseId, ci) => {
    for (let rep = 1; rep <= maxRep; rep++) {
      for (let k = 0; k < arms.length; k++) {
        const arm = arms[(ci + rep - 1 + k) % arms.length];
        if (rep <= repeat[arm]) calls.push({ caseId, arm, rep });
      }
    }
  });
  return calls;
}

export function pricingFor(model: string): TokenPricing {
  const pricing: Record<string, TokenPricing> = {
    "claude-sonnet-5": SONNET_5_PRICING,
    "claude-sonnet-5-5": SONNET_5_5_PRICING,
  };
  const found = pricing[model];
  if (!found) throw new Error(`no pricing for ${model}`);
  return found;
}

/// 保守 token 估計：非 ASCII（中文）1.2／字、ASCII 0.4／字（實際約 1.0 與 0.3）。
export function estimateTokens(text: string): number {
  let n = 0;
  for (const ch of text) n += ch.charCodeAt(0) > 127 ? 1.2 : 0.4;
  return Math.ceil(n);
}

export interface PromptTokens {
  readonly system: number;
  readonly user: number;
}

/// 單次分析呼叫的費用上界：輸出吃滿 max_tokens；system 以 cache 寫入價計，
/// cached＝同案同臂前一次剛寫入（5 分鐘內）才以讀取價計；user 以一般輸入價。
export function callUpperBoundUsd(
  model: string,
  tokens: PromptTokens,
  maxOutputTokens: number,
  cached: boolean,
): number {
  return estimateCostUsd({
    inputTokens: tokens.user,
    outputTokens: maxOutputTokens,
    cacheReadInputTokens: cached ? tokens.system : 0,
    cacheCreationInputTokens: cached ? 0 : tokens.system,
  }, pricingFor(model));
}

/// 評審一次的上界：輸入以 cache 寫入價（實際不走 cache，是一般價）、輸出吃滿。
export function judgeCallUpperBoundUsd(
  inputTokens = JUDGE_INPUT_TOKENS_EST,
): number {
  return estimateCostUsd({
    inputTokens: 0,
    outputTokens: SEMANTIC_CRITIC_MAX_TOKENS,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: inputTokens,
  }, pricingFor(JUDGE_MODEL));
}

export interface PlanEstimate {
  readonly calls: number;
  readonly perArm: Record<string, { calls: number; usd: number }>;
  readonly mainUsd: number;
  /// 完全不中 cache 的最壞值（只列參考；runtime 閘每次呼叫用這個口徑檢查）。
  readonly mainNoCacheUsd: number;
  /// 期望集合含 send 的案才會有選中卡給評審審，這裡全數計入（上界）。
  readonly judgeCalls: number;
  readonly judgeUsd: number;
  readonly totalUsd: number;
}

export function estimatePlan(
  plan: readonly PlannedCall[],
  tokensByCase: Readonly<Record<string, PromptTokens>>,
  baseMaxTokens: number,
): PlanEstimate {
  const sendable = new Set(
    CORPUS.filter((c) => c.expect.messageDecision.includes("send")).map((c) =>
      c.id
    ),
  );
  const written = new Set<string>();
  const perArm: Record<string, { calls: number; usd: number }> = {};
  let mainUsd = 0;
  let mainNoCacheUsd = 0;
  let judgeCalls = 0;
  for (const call of plan) {
    const arm = ARMS[call.arm];
    const tokens = tokensByCase[call.caseId];
    const maxOut = maxTokensFor(arm.model, baseMaxTokens) +
      (arm.override?.extraMaxTokens ?? 0);
    const key = `${call.caseId}|${call.arm}`;
    const usd = callUpperBoundUsd(arm.model, tokens, maxOut, written.has(key));
    written.add(key);
    mainUsd += usd;
    mainNoCacheUsd += callUpperBoundUsd(arm.model, tokens, maxOut, false);
    const slot = perArm[call.arm] ??= { calls: 0, usd: 0 };
    slot.calls += 1;
    slot.usd += usd;
    if (sendable.has(call.caseId)) judgeCalls += 1;
  }
  const judgeUsd = judgeCalls * judgeCallUpperBoundUsd();
  return {
    calls: plan.length,
    perArm,
    mainUsd,
    mainNoCacheUsd,
    judgeCalls,
    judgeUsd,
    totalUsd: mainUsd + judgeUsd,
  };
}

export interface PaidFlags {
  readonly run: boolean;
  readonly confirmPaid: boolean;
  readonly maxCalls: number | null;
  readonly budgetUsd: number | null;
}

export function parsePaidFlags(args: readonly string[]): PaidFlags {
  const num = (name: string) => {
    const raw = args.find((a) => a.startsWith(`--${name}=`))?.slice(
      name.length + 3,
    );
    const n = Number(raw);
    return raw !== undefined && Number.isFinite(n) && n > 0 ? n : null;
  };
  return {
    run: args.includes("--run"),
    confirmPaid: args.includes("--confirm-paid"),
    maxCalls: num("max-calls"),
    budgetUsd: num("budget-usd"),
  };
}

/// 付費閘：回拒絕理由，null＝可以真呼叫。沒有 --run 一律只做 dry-run。
export function paidGuardError(
  flags: PaidFlags,
  plannedCalls: number,
  estimateUsd: number,
): string | null {
  if (!flags.run) return "dry-run：沒有 --run，不打任何模型";
  if (!flags.confirmPaid) return "拒絕：缺 --confirm-paid";
  if (flags.maxCalls === null) return "拒絕：缺 --max-calls=N";
  if (flags.budgetUsd === null) return "拒絕：缺 --budget-usd=X";
  if (plannedCalls > flags.maxCalls) {
    return `拒絕：計畫 ${plannedCalls} 次 > --max-calls=${flags.maxCalls}`;
  }
  if (estimateUsd > flags.budgetUsd) {
    return `拒絕：估價 $${
      estimateUsd.toFixed(2)
    } > --budget-usd=${flags.budgetUsd}`;
  }
  return null;
}

export interface ProviderUsageTokens {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens: number;
  cache_read_input_tokens: number;
}

/// 一次真正送到 Anthropic 的呼叫（fetch 層看到的，不是 production 轉述的）。
export interface ProviderCall {
  readonly model: string;
  readonly sent: {
    readonly max_tokens: unknown;
    readonly thinking: unknown;
    readonly output_config: unknown;
    readonly temperature: unknown;
  };
  servedModel: string | null;
  httpStatus: number | null;
  error: string | null;
  stopReason: string | null;
  stopDetails: { category?: unknown; explanation?: unknown } | null;
  usage: ProviderUsageTokens;
  providerMs: number | null;
  costUsd: number;
}

export function newProviderCall(body: Record<string, unknown>): ProviderCall {
  return {
    model: String(body.model),
    sent: {
      max_tokens: body.max_tokens,
      thinking: body.thinking ?? null,
      output_config: body.output_config ?? null,
      temperature: body.temperature ?? null,
    },
    servedModel: null,
    httpStatus: null,
    error: null,
    stopReason: null,
    stopDetails: null,
    usage: {
      input_tokens: 0,
      output_tokens: 0,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
    },
    providerMs: null,
    costUsd: 0,
  };
}

/// 吃一個 SSE data JSON：模型、stop_reason／stop_details、usage（output 是累計值）。
// deno-lint-ignore no-explicit-any
export function applySseEvent(call: ProviderCall, event: any): void {
  const usage = event?.type === "message_start"
    ? event.message?.usage
    : event?.type === "message_delta"
    ? event.usage
    : undefined;
  for (const key of Object.keys(call.usage) as (keyof ProviderUsageTokens)[]) {
    if (Number.isFinite(usage?.[key])) call.usage[key] = usage[key];
  }
  if (event?.type === "message_start" && event.message?.model) {
    call.servedModel = String(event.message.model);
  }
  if (event?.type === "message_delta") {
    call.stopReason = event.delta?.stop_reason ?? call.stopReason;
    call.stopDetails = event.delta?.stop_details ?? event.stop_details ??
      call.stopDetails;
  }
  if (event?.type === "error") {
    call.error = String(event.error?.type ?? "stream_error");
  }
  call.costUsd = estimateCostUsd({
    inputTokens: call.usage.input_tokens,
    outputTokens: call.usage.output_tokens,
    cacheReadInputTokens: call.usage.cache_read_input_tokens,
    cacheCreationInputTokens: call.usage.cache_creation_input_tokens,
  }, pricingFor(call.servedModel ?? call.model));
}

/// 付費閘記帳：呼叫前已把上界 reservedUsd 記進 spentUsd；呼叫結束時只有拿到
/// 完整最終 usage（HTTP 200、message_start＋stop_reason 都到、沒有 error 事件）
/// 才把預留換成實際費用，斷線、error、非 200、usage 不全都保留上界；上界是 token
/// 估算、不是嚴格上界，所以 usage 不全但已回報的費用比預留高時，補上差額。回傳新的 spent。
export function settleReservedSpend(
  spentUsd: number,
  reservedUsd: number,
  call: ProviderCall,
): number {
  const complete = call.httpStatus === 200 && call.error === null &&
    call.servedModel !== null && call.stopReason !== null;
  return complete
    ? spentUsd - reservedUsd + call.costUsd
    : spentUsd + Math.max(0, call.costUsd - reservedUsd);
}

export interface CallRecord {
  readonly arm: ArmId;
  readonly caseId: string;
  readonly rep: number;
  readonly model: string;
  /// 端到端（handler 開始到 client NDJSON 讀完），與 evaluate 的延遲 gate 同口徑。
  readonly latencyMs: number;
  readonly costUsd: number;
  readonly providerCalls: readonly ProviderCall[];
  // deno-lint-ignore no-explicit-any
  readonly result: any;
}

/// nearest-rank 百分位；空陣列回 null。
export function percentile(
  values: readonly number[],
  p: number,
): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)];
}

export interface ArmSummary {
  readonly arm: ArmId;
  readonly model: string;
  readonly calls: number;
  readonly evalPassed: number;
  readonly evalFailures: Record<string, number>;
  readonly maxTokens: number;
  readonly refusals: number;
  readonly refusalCategories: Record<string, number>;
  readonly httpErrors: Record<string, number>;
  readonly p50Ms: number | null;
  readonly p95Ms: number | null;
  readonly avgTokens: ProviderUsageTokens;
  readonly costUsd: number;
}

export function summarizeArms(records: readonly CallRecord[]): ArmSummary[] {
  const arms = [...new Set(records.map((r) => r.arm))].sort();
  return arms.map((arm) => {
    const rs = records.filter((r) => r.arm === arm);
    const pcs = rs.flatMap((r) => r.providerCalls);
    const evaluation = evaluateArtifact({ results: rs.map((r) => r.result) });
    const refusalCategories: Record<string, number> = {};
    const httpErrors: Record<string, number> = {};
    for (const pc of pcs) {
      if (pc.stopReason === "refusal") {
        const cat = String(pc.stopDetails?.category ?? "null");
        refusalCategories[cat] = (refusalCategories[cat] ?? 0) + 1;
      }
      if (pc.httpStatus !== null && pc.httpStatus !== 200) {
        const key = String(pc.httpStatus);
        httpErrors[key] = (httpErrors[key] ?? 0) + 1;
      }
    }
    const avg = (key: keyof ProviderUsageTokens) =>
      pcs.length === 0
        ? 0
        : Math.round(pcs.reduce((s, pc) => s + pc.usage[key], 0) / pcs.length);
    const latencies = rs.map((r) => r.latencyMs);
    return {
      arm,
      model: ARMS[arm].model,
      calls: rs.length,
      evalPassed: evaluation.passed,
      evalFailures: evaluation.failures,
      maxTokens: pcs.filter((pc) => pc.stopReason === "max_tokens").length,
      refusals: pcs.filter((pc) => pc.stopReason === "refusal").length,
      refusalCategories,
      httpErrors,
      p50Ms: percentile(latencies, 50),
      p95Ms: percentile(latencies, 95),
      avgTokens: {
        input_tokens: avg("input_tokens"),
        output_tokens: avg("output_tokens"),
        cache_creation_input_tokens: avg("cache_creation_input_tokens"),
        cache_read_input_tokens: avg("cache_read_input_tokens"),
      },
      costUsd: rs.reduce((s, r) => s + r.costUsd, 0),
    };
  });
}

export function renderSummaryMd(
  meta: Record<string, unknown>,
  summaries: readonly ArmSummary[],
): string {
  const sec = (ms: number | null) =>
    ms === null ? "-" : `${(ms / 1000).toFixed(1)}s`;
  const json = (o: Record<string, number>) =>
    Object.keys(o).length === 0 ? "-" : JSON.stringify(o);
  const lines = [
    `# 分析 A/B 彙總：${meta.tag}`,
    "",
    `commit ${meta.commit}（dirty=${meta.worktreeDirty}）；${meta.generatedAt}；備援鏈關閉（每次只打指定模型）。`,
    "語料全是正常聊天：任何 refusal 都算誤擋。",
    "",
    "| 臂 | 設定 | 次數 | evaluate 通過 | max_tokens | 拒答（類別） | HTTP 錯誤 | p50 | p95 | 平均 input／cache 寫／cache 讀／output | 費用 |",
    "|---|---|---|---|---|---|---|---|---|---|---|",
    ...summaries.map((s) =>
      `| ${s.arm} | ${
        ARMS[s.arm].label
      } | ${s.calls} | ${s.evalPassed}/${s.calls} | ${s.maxTokens} | ${s.refusals}（${
        json(s.refusalCategories)
      }） | ${json(s.httpErrors)} | ${sec(s.p50Ms)} | ${
        sec(s.p95Ms)
      } | ${s.avgTokens.input_tokens}／${s.avgTokens.cache_creation_input_tokens}／${s.avgTokens.cache_read_input_tokens}／${s.avgTokens.output_tokens} | $${
        s.costUsd.toFixed(3)
      } |`
    ),
    "",
    "evaluate 失敗 gate：",
    ...summaries.map((s) => `- ${s.arm}：${json(s.evalFailures)}`),
    "",
    `總費用 $${summaries.reduce((t, s) => t + s.costUsd, 0).toFixed(3)}。`,
    "評審（固定 Sonnet 5）另跑：`run_critic.ts <tag>/arm-X.json …`，見 README。",
    "",
  ];
  return lines.join("\n");
}

export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// deno-lint-ignore no-explicit-any
function clientView(result: any): string[] {
  // deno-lint-ignore no-explicit-any
  const events: any[] = String(result?.clientText ?? "").split("\n")
    .filter((l) => l.trim())
    .flatMap((l) => {
      try {
        return [JSON.parse(l)];
      } catch {
        return [];
      }
    });
  const decision = events.find((e) => e.type === "analysis.decision");
  const options = events.filter((e) => e.type === "analysis.reply_option");
  // 與 evaluate 的 stream_completes 同判準：沒走到 done 就是用戶看到錯誤。
  if (
    !decision || result?.status !== 200 ||
    result?.eventTypes?.at(-1) !== "analysis.done"
  ) {
    return ["（這次分析失敗，用戶只會看到錯誤訊息）"];
  }
  const out = [`決定：${decision.messageDecision ?? "?"}`];
  // do_not_send 的備用句在 App 收在「我還是想回」後面，不是教練建議傳的收尾句。
  if (typeof decision.closingMessage === "string") {
    out.push(
      decision.messageDecision === "do_not_send"
        ? `（收在「我還是想回」後）備用句：${decision.closingMessage}`
        : `收尾句：${decision.closingMessage}`,
    );
  }
  if (options.length > 0) {
    out.push(`推薦：${decision.selectedStyle ?? "?"}`);
    for (const o of options) out.push(`- ${o.style}：${o.message}`);
  }
  return out;
}

/// Eric 盲選表：固定種子挑 10 案，每案 A／B 各取第 1 次，隨機排成甲／乙；
/// 對照表另檔，表本身不出現模型名或臂名。
export function buildBlindSheet(
  records: readonly CallRecord[],
  seed = BLIND_SEED,
  count = BLIND_CASES,
): { markdown: string; reveal: Record<string, unknown> } | null {
  const pick = (caseId: string, arm: ArmId) =>
    records.find((r) => r.caseId === caseId && r.arm === arm && r.rep === 1);
  const candidates = CORPUS.map((c) => c.id).filter((id) =>
    pick(id, "A") && pick(id, "B")
  );
  if (candidates.length === 0) return null;
  const rng = mulberry32(seed);
  for (let i = candidates.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [candidates[i], candidates[j]] = [candidates[j], candidates[i]];
  }
  const chosen = candidates.slice(0, count);
  const corpusById = new Map(CORPUS.map((c) => [c.id, c]));
  const reveal: { n: number; caseId: string; 甲: ArmId; 乙: ArmId }[] = [];
  const md = [
    "# 對話分析盲選",
    "",
    "每題兩份分析結果（甲／乙）。判準：付費用戶會不會原封不動直接傳出去。每題圈一個：甲／乙／差不多。",
    "",
  ];
  chosen.forEach((caseId, i) => {
    const aFirst = rng() < 0.5;
    const order: [ArmId, ArmId] = aFirst ? ["A", "B"] : ["B", "A"];
    reveal.push({ n: i + 1, caseId, 甲: order[0], 乙: order[1] });
    md.push(`## 第 ${i + 1} 題`, "", "對話：");
    for (const m of corpusById.get(caseId)!.messages) {
      md.push(`> ${m.isFromMe ? "我" : "她"}：${m.content}`);
    }
    for (const [label, arm] of [["甲", order[0]], ["乙", order[1]]] as const) {
      md.push("", `**${label}**`, "", ...clientView(pick(caseId, arm)!.result));
    }
    md.push("", "選：甲／乙／差不多", "");
  });
  return { markdown: md.join("\n"), reveal: { seed, cases: reveal } };
}

// 對象記憶的付費黑箱（2026-10-18 準備，還沒跑）：拿人工案例（cases.json）只打記憶那一次
// 呼叫，比較 Haiku 5.5（正式）與 Sonnet 5.5（讀局面同一條路）過出處檢查之後的召回、精確、
// 陷阱命中、耗時與每次費用。請求、提示詞與出處檢查都是 production 程式碼
// （guide_v3/model_calls.ts 的 callExtract、memory.ts），不經 Edge、DB、扣費。
//
// 預設 dry-run：不讀金鑰、不連網、不寫檔，只列次數與費用上限（在 repo 根目錄跑）：
//   deno run --allow-read tools/guide-v3-memory-blackbox/run.ts [--models=haiku,sonnet] [--repeat=N] [--only=id,id]
// --fake：fetch 換成替身，「模型」照案例的標準答案回（期望的事實＋陷阱，各附原句），驗證案例寫得
//   對（期望的都過得了出處檢查、陷阱都擋得下）、請求形狀與計價統計接得起來；有一項不對就 exit 1。
//   deno run --allow-read tools/guide-v3-memory-blackbox/run.ts --fake
// 真跑（要 Eric 當次說「跑」）：--run --confirm-paid --max-calls --budget-usd --tag 缺一個就拒絕；
//   追蹤檔有未提交修改、或 out/<tag> 已存在也拒絕。金鑰讀 ~/.config/anthropic/key。
//   deno run --allow-read --allow-env=HOME --allow-run=git \
//     --allow-write=tools/guide-v3-memory-blackbox/out --allow-net=api.anthropic.com \
//     tools/guide-v3-memory-blackbox/run.ts --repeat=2 \
//     --run --confirm-paid --max-calls=<dry-run 印的次數> --budget-usd=<上限> --tag=<名稱>
// 守門：每次送出前預留「估計 input 全用最高的 input 單價＋output 吃滿實際送出的 max_tokens
// （Sonnet 5.5 含思考餘裕）」，已花費＋預留超過 --budget-usd 或到 --max-calls 就停。token 是
// 字數×1.5 估的（跑的時候用實測值往上校正），不是嚴格上限。失敗沒回 usage 就以預留額計入；
// 同一個模型連續 3 次失敗就停掉那個模型。
import catalog from "./cases.json" with { type: "json" };
import {
  maxTokensFor,
  SONNET_5_5_MODEL,
} from "../../supabase/functions/_shared/model_request_params.ts";
import {
  estimateCostUsd,
  HAIKU_5_5_LONG_CONTEXT_PRICING,
  HAIKU_5_5_PRICING,
  SONNET_5_5_PRICING,
  type TokenPricing,
} from "../../supabase/functions/_shared/model_pricing.ts";
import type { ProviderAttemptLogEntry } from "../../supabase/functions/analyze-chat/model_call_budget.ts";
import {
  MEMORY_KINDS,
  MEMORY_SCHEMA,
  type MemoryKind,
  memorySystemPrompt,
  memoryUserPrompt,
  partnerMemoryFrom,
} from "../../supabase/functions/analyze-chat/guide_v3/memory.ts";
import {
  createGuideV3ModelCalls,
  GUIDE_V3_MEMORY_MAX_TOKENS,
  GUIDE_V3_MEMORY_MODEL,
} from "../../supabase/functions/analyze-chat/guide_v3/model_calls.ts";
import { guideMessagesFrom } from "../../supabase/functions/analyze-chat/guide_v3/stream_flow.ts";
import { toTurns } from "../../supabase/functions/analyze-chat/guide_v3/turns.ts";

type Message = {
  isFromMe: boolean;
  content: string;
  quotedReplyPreview?: string;
};
type Fact = {
  kinds?: MemoryKind[];
  value: string;
  evidence: string;
  match: string[];
  optional?: boolean;
  /// --fake 替身給的兩個判斷欄位；沒寫就是 her＋true（陷阱沒寫＝模型標錯的最壞情況，
  /// 要靠出處檢查自己擋下）。
  subject?: string;
  own?: boolean;
};
type Trap = Fact & { type: string };
type Case = {
  id: string;
  background?: string;
  messages: Message[];
  expected: Fact[];
  traps: Trap[];
};

const CASES = catalog.cases as Case[];
export const MODELS: Readonly<Record<string, string>> = {
  haiku: GUIDE_V3_MEMORY_MODEL,
  sonnet: SONNET_5_5_MODEL,
};
const TOKENS_PER_CHAR = 1.5;
const API_URL = "https://api.anthropic.com/v1/messages";
const OUT_ROOT = new URL("./out/", import.meta.url);

type Mode = "dry" | "fake" | "paid";
type Options = {
  mode: Mode;
  models: string[];
  repeat: number;
  only: string[] | null;
  maxCalls: number | null;
  budgetUsd: number | null;
  tag: string | null;
};

export function parseOptions(args: string[]): Options {
  const values = new Map<string, string>();
  const flags = new Set<string>();
  for (const arg of args) {
    const m = arg.match(/^--([a-z-]+)(?:=(.*))?$/);
    if (!m) throw new Error(`看不懂的參數：${arg}`);
    if (m[2] === undefined) flags.add(m[1]);
    else values.set(m[1], m[2]);
  }
  const known = [
    "models",
    "repeat",
    "only",
    "max-calls",
    "budget-usd",
    "tag",
    "fake",
    "run",
    "confirm-paid",
  ];
  for (const key of [...values.keys(), ...flags]) {
    if (!known.includes(key)) throw new Error(`沒有這個參數：--${key}`);
  }
  const models = (values.get("models") ?? "haiku,sonnet").split(",");
  for (const m of models) {
    if (!(m in MODELS)) throw new Error(`--models 只收 haiku、sonnet：${m}`);
  }
  const repeat = Number(values.get("repeat") ?? "1");
  if (!Number.isInteger(repeat) || repeat < 1 || repeat > 5) {
    throw new Error("--repeat 要是 1–5 的整數");
  }
  const only = values.has("only") ? values.get("only")!.split(",") : null;
  for (const id of only ?? []) {
    if (!CASES.some((c) => c.id === id)) throw new Error(`沒有這個案例：${id}`);
  }
  const paid = flags.has("run");
  if (paid && flags.has("fake")) throw new Error("--fake 不能跟 --run 一起用");
  const maxCalls = values.has("max-calls")
    ? Number(values.get("max-calls"))
    : null;
  const budgetUsd = values.has("budget-usd")
    ? Number(values.get("budget-usd"))
    : null;
  const tag = values.get("tag") ?? null;
  if (paid) {
    if (
      !flags.has("confirm-paid") || maxCalls === null || budgetUsd === null ||
      tag === null
    ) {
      throw new Error(
        "真跑必須同時帶 --run --confirm-paid --max-calls=<上限> --budget-usd=<上限> --tag=<名稱>（Eric 當次授權後）",
      );
    }
    if (!Number.isInteger(maxCalls) || maxCalls < 1) {
      throw new Error("--max-calls 要是正整數");
    }
    if (!(budgetUsd > 0)) throw new Error("--budget-usd 要是正數");
    if (!/^[A-Za-z0-9._-]+$/.test(tag)) {
      throw new Error("--tag 只收英數、點、底線、連字號");
    }
  } else if (flags.has("confirm-paid")) {
    throw new Error("--confirm-paid 要跟 --run 一起用");
  }
  return {
    mode: paid ? "paid" : flags.has("fake") ? "fake" : "dry",
    models,
    repeat,
    only,
    maxCalls,
    budgetUsd,
    tag,
  };
}

export type PlannedCall = {
  caseId: string;
  model: string;
  repeat: number;
  system: string;
  user: string;
  promptChars: number;
  maxOutputTokens: number;
};

/// 同一案兩個模型排在一起：中途停下來時兩邊跑到的案例一樣多。
export function buildPlan(opts: Pick<Options, "models" | "repeat" | "only">) {
  const system = memorySystemPrompt();
  const schemaChars = JSON.stringify(MEMORY_SCHEMA).length;
  const plan: PlannedCall[] = [];
  for (let repeat = 1; repeat <= opts.repeat; repeat++) {
    for (const c of CASES) {
      if (opts.only && !opts.only.includes(c.id)) continue;
      const user = memoryUserPrompt(toTurns(guideMessagesFrom(c.messages)));
      for (const alias of opts.models) {
        const model = MODELS[alias];
        plan.push({
          caseId: c.id,
          model,
          repeat,
          system,
          user,
          // schema 也算進 input 估計（結構化輸出會把它帶進請求）。
          promptChars: system.length + user.length + schemaChars,
          maxOutputTokens: maxTokensFor(model, GUIDE_V3_MEMORY_MAX_TOKENS),
        });
      }
    }
  }
  return plan;
}

export function pricingFor(model: string, promptTokens: number): TokenPricing {
  if (model === MODELS.haiku) {
    return promptTokens > 100_000
      ? HAIKU_5_5_LONG_CONTEXT_PRICING
      : HAIKU_5_5_PRICING;
  }
  if (model === MODELS.sonnet) return SONNET_5_5_PRICING;
  throw new Error(`沒有單價：${model}`);
}

/// 送出前的預留：input 全用最高的 input 單價、output 吃滿 max_tokens。
export function reservationUsd(call: PlannedCall, tokensPerChar: number) {
  const input = Math.ceil(call.promptChars * tokensPerChar);
  const p = pricingFor(call.model, input);
  const inputPrice = Math.max(
    p.inputPerMTok,
    p.cacheWritePerMTok,
    p.cacheReadPerMTok,
  );
  return (input * inputPrice + call.maxOutputTokens * p.outputPerMTok) /
    1_000_000;
}

const norm = (s: string) => s.replace(/\s+/g, "").toLowerCase();

function matches(value: string, keywords: readonly string[]): boolean {
  const v = norm(value);
  return keywords.some((k) => {
    const key = norm(k);
    return v.includes(key) || (v.length >= 2 && key.includes(v));
  });
}

const kindOk = (f: Fact, kind: MemoryKind) =>
  !f.kinds || f.kinds.includes(kind);

export type Item = { kind: MemoryKind; value: string };

export type Score = {
  kept: number;
  correct: number;
  matched: string[];
  missed: string[];
  trapHits: string[];
  unexpected: string[];
};

/// 陷阱先比（限同類），再比期望；都不是就是意外項（人工看）。
export function score(c: Case, items: readonly Item[]): Score {
  const hit = new Set<Fact>();
  const s: Score = {
    kept: items.length,
    correct: 0,
    matched: [],
    missed: [],
    trapHits: [],
    unexpected: [],
  };
  for (const item of items) {
    if (
      c.traps.some((t) => kindOk(t, item.kind) && matches(item.value, t.match))
    ) {
      s.trapHits.push(`${item.kind}:${item.value}`);
      continue;
    }
    const facts = c.expected.filter((f) =>
      kindOk(f, item.kind) && matches(item.value, f.match)
    );
    if (facts.length === 0) {
      s.unexpected.push(`${item.kind}:${item.value}`);
      continue;
    }
    s.correct++;
    for (const f of facts) hit.add(f);
  }
  for (const f of c.expected) {
    if (f.optional) continue;
    (hit.has(f) ? s.matched : s.missed).push(f.value);
  }
  return s;
}

function itemsOf(profile: Record<string, unknown> | undefined): Item[] {
  if (!profile) return [];
  return MEMORY_KINDS.flatMap((kind) =>
    ((profile[kind] as string[] | undefined) ?? []).map((value) => ({
      kind,
      value,
    }))
  );
}

/// 出處檢查之前，模型提了幾個陷阱（看檢查擋掉多少）。
function proposedTraps(c: Case, text: string): number {
  try {
    const raw = JSON.parse(text) as Record<string, unknown>;
    return MEMORY_KINDS.reduce((n, kind) => {
      const list = Array.isArray(raw[kind]) ? raw[kind] as unknown[] : [];
      return n + list.filter((cand) => {
        const value = (cand as { value?: unknown })?.value;
        return typeof value === "string" &&
          c.traps.some((t) => kindOk(t, kind) && matches(value, t.match));
      }).length;
    }, 0);
  } catch {
    return 0;
  }
}

/// --fake 的標準答案：期望的事實（含 optional）與陷阱，各附案例寫的原句與兩個判斷欄位。
export function oracleAnswer(c: Case): string {
  const out: Record<MemoryKind, Record<string, unknown>[]> = {
    interests: [],
    traits: [],
    notes: [],
  };
  for (const f of [...c.expected, ...c.traps]) {
    out[f.kinds?.[0] ?? "interests"].push({
      value: f.value,
      evidence: [f.evidence],
      subject: f.subject ?? "her",
      evidenceIsHerOwnStatement: f.own ?? true,
    });
  }
  return JSON.stringify(out);
}

export type CallRecord = {
  caseId: string;
  model: string;
  repeat: number;
  status: "ok" | "failed" | "not_run";
  errorCode: string | null;
  latencyMs: number | null;
  usage: {
    inputTokens: number;
    outputTokens: number;
    cacheCreationTokens: number;
    cacheReadTokens: number;
    complete: boolean;
  } | null;
  costUsd: number | null;
  reservationUsd: number;
  rawText: string | null;
  proposedTraps: number;
  score: Score | null;
};

function errorCode(error: unknown): string {
  const code = (error as { code?: unknown })?.code;
  return typeof code === "string"
    ? code
    : error instanceof Error
    ? error.name
    : "UNKNOWN";
}

async function runCall(
  c: Case,
  call: PlannedCall,
  apiKey: string,
  reservation: number,
): Promise<CallRecord> {
  const entries: ProviderAttemptLogEntry[] = [];
  const calls = createGuideV3ModelCalls({
    apiKey,
    requestType: "analyze",
    tier: "essential",
    recordAiCall: (entry) => entries.push(entry),
    memory: true,
    memoryModel: call.model,
  });
  const started = performance.now();
  let text: string | null = null;
  let code: string | null = null;
  try {
    text = (await calls.callExtract!({
      runId: `memory-blackbox-${call.caseId}-${call.repeat}`,
      system: call.system,
      user: call.user,
      schema: MEMORY_SCHEMA,
      deadlineAtMs: Date.now() + 60_000,
    })).text;
  } catch (error) {
    code = errorCode(error);
  }
  const latencyMs = Math.round(performance.now() - started);
  const sum = (key: keyof ProviderAttemptLogEntry) =>
    entries.reduce((n, e) => n + ((e[key] as number | undefined) ?? 0), 0);
  const complete = entries.length > 0 &&
    entries.every((e) =>
      (e.requestBody as Record<string, unknown> | undefined)?.usageComplete ===
        true
    );
  const usage = {
    inputTokens: sum("inputTokens"),
    outputTokens: sum("outputTokens"),
    cacheCreationTokens: sum("cacheCreationTokens"),
    cacheReadTokens: sum("cacheReadTokens"),
    complete,
  };
  const prompt = usage.inputTokens + usage.cacheCreationTokens +
    usage.cacheReadTokens;
  const costUsd = complete
    ? estimateCostUsd({
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      cacheReadInputTokens: usage.cacheReadTokens,
      cacheCreationInputTokens: usage.cacheCreationTokens,
    }, pricingFor(call.model, prompt))
    : null;
  const memory = text === null ? null : partnerMemoryFrom(text, c.messages);
  return {
    caseId: call.caseId,
    model: call.model,
    repeat: call.repeat,
    status: code === null ? "ok" : "failed",
    errorCode: code,
    latencyMs,
    usage,
    costUsd,
    reservationUsd: reservation,
    rawText: text,
    proposedTraps: text === null ? 0 : proposedTraps(c, text),
    score: memory ? score(c, itemsOf(memory.targetProfile)) : null,
  };
}

function percentile(values: number[], p: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(p * sorted.length) - 1)];
}

const pct = (n: number, d: number) =>
  d === 0 ? "—" : `${(100 * n / d).toFixed(0)}%（${n}/${d}）`;

export function summaryMarkdown(records: CallRecord[], header: string[]) {
  const lines = [...header, ""];
  const columns = [
    "模型",
    "跑了",
    "失敗（代碼）",
    "召回",
    "精確",
    "陷阱命中（檢查前提了）",
    "意外項",
    "p50／p95 ms",
    "平均 in／out token",
    "每次費用",
    "合計",
  ];
  lines.push(
    `| ${columns.join(" | ")} |`,
    `|${"---|".repeat(columns.length)}`,
  );
  const details: string[] = [];
  for (const model of [...new Set(records.map((r) => r.model))]) {
    const rows = records.filter((r) =>
      r.model === model && r.status !== "not_run"
    );
    const ok = rows.filter((r) => r.status === "ok");
    const failed = rows.filter((r) => r.status === "failed");
    const codes = [...new Set(failed.map((r) => r.errorCode))].join("、");
    const scores = ok.map((r) => r.score!).filter(Boolean);
    const matched = scores.reduce((n, s) => n + s.matched.length, 0);
    const required = scores.reduce(
      (n, s) => n + s.matched.length + s.missed.length,
      0,
    );
    const kept = scores.reduce((n, s) => n + s.kept, 0);
    const correct = scores.reduce((n, s) => n + s.correct, 0);
    const traps = scores.reduce((n, s) => n + s.trapHits.length, 0);
    const proposed = ok.reduce((n, r) => n + r.proposedTraps, 0);
    const unexpected = scores.reduce((n, s) => n + s.unexpected.length, 0);
    const latency = rows.map((r) => r.latencyMs!).filter((v) => v !== null);
    const priced = rows.filter((r) => r.costUsd !== null);
    const total = rows.reduce((n, r) => n + (r.costUsd ?? r.reservationUsd), 0);
    const avg = (f: (r: CallRecord) => number) =>
      priced.length === 0
        ? "—"
        : (priced.reduce((n, r) => n + f(r), 0) / priced.length).toFixed(0);
    lines.push(
      `| ${model} | ${rows.length} | ${failed.length}${
        codes ? `（${codes}）` : ""
      } | ${pct(matched, required)} | ${
        pct(correct, kept)
      } | ${traps}（${proposed}） | ${unexpected} | ${
        percentile(latency, 0.5) ?? "—"
      }／${percentile(latency, 0.95) ?? "—"} | ${
        avg((r) =>
          r.usage!.inputTokens + r.usage!.cacheCreationTokens +
          r.usage!.cacheReadTokens
        )
      }／${avg((r) => r.usage!.outputTokens)} | ${
        priced.length === 0
          ? "—"
          : `$${
            (priced.reduce((n, r) => n + r.costUsd!, 0) / priced.length)
              .toFixed(5)
          }`
      } | $${total.toFixed(4)} |`,
    );
    for (const r of ok) {
      const s = r.score!;
      for (const v of s.missed) {
        details.push(`- ${model}／${r.caseId}#${r.repeat} 漏記：${v}`);
      }
      for (const v of s.trapHits) {
        details.push(`- ${model}／${r.caseId}#${r.repeat} 陷阱：${v}`);
      }
      for (const v of s.unexpected) {
        details.push(
          `- ${model}／${r.caseId}#${r.repeat} 意外項（人工看）：${v}`,
        );
      }
    }
  }
  const notRun = records.filter((r) => r.status === "not_run").length;
  if (notRun > 0) lines.push("", `沒跑（到上限或停掉）：${notRun} 次`);
  if (details.length > 0) lines.push("", ...details);
  return lines.join("\n");
}

async function git(args: string[]): Promise<string> {
  const out = await new Deno.Command("git", { args, stdout: "piped" }).output();
  if (!out.success) throw new Error(`git ${args.join(" ")} 失敗`);
  return new TextDecoder().decode(out.stdout).trim();
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// --fake 的 fetch 替身：檢查送出的請求跟 production 一樣，再回標準答案。
function installFakeFetch(state: { answer: string; model: string }) {
  globalThis.fetch = (input, init) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url !== API_URL) throw new Error(`--fake 不該連到：${url}`);
    const body = JSON.parse(String(init?.body));
    const problems: string[] = [];
    if (body.model !== state.model) problems.push(`model=${body.model}`);
    if (
      body.max_tokens !== maxTokensFor(state.model, GUIDE_V3_MEMORY_MAX_TOKENS)
    ) {
      problems.push(`max_tokens=${body.max_tokens}`);
    }
    if (
      JSON.stringify(body.output_config?.format) !==
        JSON.stringify({ type: "json_schema", schema: MEMORY_SCHEMA })
    ) problems.push("output_config.format");
    if (state.model === MODELS.sonnet) {
      if (body.thinking?.type !== "adaptive") problems.push("thinking");
    } else if ("thinking" in body) problems.push("thinking 不該有");
    if (problems.length > 0) {
      return Promise.resolve(
        Response.json({ error: problems.join("; ") }, { status: 400 }),
      );
    }
    const promptChars = JSON.stringify(body.system).length +
      JSON.stringify(body.messages).length;
    return Promise.resolve(Response.json({
      content: [{ type: "text", text: state.answer }],
      stop_reason: "end_turn",
      usage: {
        input_tokens: Math.ceil(promptChars * TOKENS_PER_CHAR),
        output_tokens: Math.ceil(state.answer.length * TOKENS_PER_CHAR),
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0,
      },
    }));
  };
}

async function main(args: string[]): Promise<number> {
  const opts = parseOptions(args);
  const plan = buildPlan(opts);
  const byId = new Map(CASES.map((c) => [c.id, c]));
  const upper = plan.reduce(
    (n, c) => n + reservationUsd(c, TOKENS_PER_CHAR),
    0,
  );
  const perModel = opts.models.map((alias) => {
    const calls = plan.filter((c) => c.model === MODELS[alias]);
    const usd = calls.reduce(
      (n, c) => n + reservationUsd(c, TOKENS_PER_CHAR),
      0,
    );
    return `${MODELS[alias]} ${calls.length} 次、上限 $${
      usd.toFixed(4)
    }（max_tokens ${calls[0]?.maxOutputTokens ?? "—"}）`;
  });
  const casesCount = new Set(plan.map((c) => c.caseId)).size;
  console.log(
    `案例 ${casesCount} 個 × 模型 ${opts.models.length} 個 × 重複 ${opts.repeat} 次＝${plan.length} 次呼叫`,
  );
  for (const line of perModel) console.log(`- ${line}`);
  console.log(
    `費用上限（input 全用最高單價、output 吃滿 max_tokens、每字 ${TOKENS_PER_CHAR} token）：$${
      upper.toFixed(4)
    }`,
  );
  if (opts.mode === "dry") {
    const budget = Math.max(0.1, Math.ceil(upper * 1.5 * 10) / 10);
    console.log(
      [
        "dry-run：沒有讀金鑰、沒有連網、沒有寫檔。真跑（要 Eric 當次說「跑」）：",
        "deno run --allow-read --allow-env=HOME --allow-run=git \\",
        "  --allow-write=tools/guide-v3-memory-blackbox/out --allow-net=api.anthropic.com \\",
        `  tools/guide-v3-memory-blackbox/run.ts${
          opts.models.join(",") === "haiku,sonnet"
            ? ""
            : ` --models=${opts.models.join(",")}`
        }${opts.repeat === 1 ? "" : ` --repeat=${opts.repeat}`}${
          opts.only ? ` --only=${opts.only.join(",")}` : ""
        } \\`,
        `  --run --confirm-paid --max-calls=${plan.length} --budget-usd=${budget} --tag=<名稱>`,
        `（--budget-usd 取上限的 1.5 倍：跑的時候每字 token 數會用實測值往上校正，預留跟著變大）`,
      ].join("\n"),
    );
    return 0;
  }

  let apiKey = "fake-key";
  let outDir: URL | null = null;
  const fakeState = { answer: "", model: "" };
  const header: string[] = [];
  if (opts.mode === "fake") {
    installFakeFetch(fakeState);
    header.push("# 對象記憶黑箱（--fake：模型照標準答案回，驗證案例與統計）");
  } else {
    if (
      (await git(["status", "--porcelain", "--untracked-files=no"])).length > 0
    ) {
      throw new Error("追蹤檔有未提交修改：先提交，結果才對得上 HEAD");
    }
    outDir = new URL(`${opts.tag}/`, OUT_ROOT);
    try {
      await Deno.stat(outDir);
      throw new Error(`out/${opts.tag} 已存在，不覆寫證據`);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    apiKey = (await Deno.readTextFile(
      `${Deno.env.get("HOME")}/.config/anthropic/key`,
    )).trim();
    await Deno.mkdir(outDir, { recursive: true });
    header.push(
      `# 對象記憶黑箱 ${opts.tag}`,
      "",
      `- HEAD：${await git(["rev-parse", "HEAD"])}`,
      `- 案例 sha256：${await sha256(JSON.stringify(catalog))}`,
      `- 系統提示詞 sha256：${await sha256(memorySystemPrompt())}`,
      `- --max-calls=${opts.maxCalls} --budget-usd=${opts.budgetUsd} --repeat=${opts.repeat}`,
    );
  }

  const records: CallRecord[] = [];
  let tokensPerChar = TOKENS_PER_CHAR;
  let spent = 0;
  let made = 0;
  const failStreak = new Map<string, number>();
  for (const call of plan) {
    const c = byId.get(call.caseId)!;
    const reservation = reservationUsd(call, tokensPerChar);
    const stop = opts.mode === "paid" &&
      (made >= opts.maxCalls! || spent + reservation > opts.budgetUsd! ||
        (failStreak.get(call.model) ?? 0) >= 3);
    if (stop) {
      records.push({
        caseId: call.caseId,
        model: call.model,
        repeat: call.repeat,
        status: "not_run",
        errorCode: null,
        latencyMs: null,
        usage: null,
        costUsd: null,
        reservationUsd: reservation,
        rawText: null,
        proposedTraps: 0,
        score: null,
      });
      continue;
    }
    fakeState.answer = oracleAnswer(c);
    fakeState.model = call.model;
    made++;
    const record = await runCall(c, call, apiKey, reservation);
    records.push(record);
    spent += record.costUsd ?? reservation;
    failStreak.set(
      call.model,
      record.status === "failed" ? (failStreak.get(call.model) ?? 0) + 1 : 0,
    );
    if (record.usage?.complete) {
      const prompt = record.usage.inputTokens +
        record.usage.cacheCreationTokens +
        record.usage.cacheReadTokens;
      tokensPerChar = Math.max(tokensPerChar, prompt / call.promptChars);
    }
    if (outDir) {
      await Deno.writeTextFile(
        new URL("records.json", outDir),
        JSON.stringify(records, null, 2),
      );
    }
  }
  const summary = summaryMarkdown(records, [
    ...header,
    "",
    `- 實際打了 ${made} 次，已花費（沒回 usage 的以預留計）$${
      spent.toFixed(4)
    }`,
  ]);
  console.log(summary);
  if (outDir) await Deno.writeTextFile(new URL("summary.md", outDir), summary);
  if (opts.mode === "fake") {
    // 標準答案：期望的（含 optional）都要留下、陷阱都要擋下、沒有失敗。
    const bad = records.filter((r) =>
      r.status !== "ok" || r.score === null || r.score.missed.length > 0 ||
      r.score.trapHits.length > 0 || r.score.unexpected.length > 0 ||
      r.score.correct !==
        byId.get(r.caseId)!.expected.length
    );
    for (const r of bad) {
      console.error(
        `案例沒過：${r.model}／${r.caseId} ${r.errorCode ?? ""} ${
          JSON.stringify(r.score)
        }`,
      );
    }
    console.log(
      bad.length === 0 ? "--fake 自我檢查通過" : "--fake 自我檢查失敗",
    );
    return bad.length === 0 ? 0 : 1;
  }
  return 0;
}

if (import.meta.main) {
  try {
    Deno.exit(await main(Deno.args));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(2);
  }
}

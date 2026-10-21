// 教練「關於我」成對評測的共用程式（規格 PR-6；Bruce 2026-10-20〈「關於我」只給教練〉）。
// 參數與付費守門照 tools/new-topic-two-stage-eval/ 的做法：預設乾跑、不打模型；真跑要
// Eric 當次說「跑」，並同時帶 --run --confirm-paid --max-calls --budget-usd。守門是技術
// 保險，不能取代 Eric 的授權。

import catalog from "./cases.json" with { type: "json" };

// ---------------------------------------------------------------------------
// 案例
// ---------------------------------------------------------------------------

export const GROUPS = [
  "boundary",
  "relevant",
  "unrelated",
  "no_fabrication",
  "honest_emotion",
  "legacy_style",
  "injection",
  "recent_note",
  "no_about_me",
] as const;
export type Group = typeof GROUPS[number];

export type EvalCase = {
  id: string;
  group: Group;
  note: string;
  /** 產生 aboutMe 用的設定（App 端測試逐字比對 buildForCoachFollowUp）。 */
  profile: Record<string, unknown> | null;
  /** App 組字端送出的「關於我」；沒填是 null。 */
  aboutMe: string | null;
  /** 送給 coach-chat 的請求（未經 schema 的原始形狀）。 */
  request: Record<string, unknown>;
};

export const CASES = catalog.cases as EvalCase[];

// ---------------------------------------------------------------------------
// 兩臂與模型參數（照 production：generation.ts 的 runCoachChat 與 callClaudeAPI）
// ---------------------------------------------------------------------------

export const ARMS = ["base", "cand"] as const;
export type Arm = typeof ARMS[number];

/** 改前：規格 PR-4 之前的 main（含 PR-3 的 App 格式）。 */
export const DEFAULT_BASE_REF = "928904cf182d616eac6a334f3f62fba556b00de3";

export const GENERATION_MODEL = "claude-sonnet-5";
export const GENERATION_MAX_TOKENS = 1200;
export const CRITIC_MAX_TOKENS = 260;
/** runCoachChat 最多三次生成、每次通過基本驗證後各一次審稿。 */
export const MAX_CALLS_PER_RUN = 6;
export const TYPICAL_CALLS_PER_RUN = 2;

/** Sonnet 5 單價（_shared/model_pricing.ts 的 SONNET_5_PRICING；教練沒開快取）。 */
export const INPUT_USD_PER_TOKEN = 2 / 1_000_000;
export const OUTPUT_USD_PER_TOKEN = 10 / 1_000_000;
/**
 * 本機沒有 tokenizer：中文每字先抓 2 個 token（實測中文本機估算會低估一到兩成，
 * 見 Dev Brain 坑〈Anthropic中文語料本機token估算會低估…〉）。真跑時用實際 usage
 * 校正，只升不降。
 */
export const INITIAL_TOKENS_PER_CHAR = 2;
export const TYPICAL_GENERATION_OUTPUT_TOKENS = 700;
export const TYPICAL_CRITIC_OUTPUT_TOKENS = 120;
/**
 * 第二、三次生成會在提示詞後面加重寫指示（generation.ts 的 buildAttemptPrompt，最長
 * 一段約 390 字再加違規代碼）；最壞估算每次多算 600 字。逐次預留用實際提示詞，不靠這個。
 */
export const RETRY_SUFFIX_CHARS = 600;

export function callCostUsd(inputTokens: number, outputTokens: number): number {
  return inputTokens * INPUT_USD_PER_TOKEN + outputTokens * OUTPUT_USD_PER_TOKEN;
}

/** 每次送出前的預留：估計 input 全算、output 用 max_tokens 全滿。 */
export function reserveUsd(
  promptChars: number,
  maxTokens: number,
  tokensPerChar: number,
): number {
  return callCostUsd(Math.ceil(promptChars * tokensPerChar), maxTokens);
}

export type Estimate = {
  runs: number;
  typicalCalls: number;
  worstCalls: number;
  typicalUsd: number;
  worstUsd: number;
};

/**
 * 一次 runCoachChat 的估算：一般＝一次生成＋一次審稿；最壞＝三次生成（後兩次加重寫
 * 指示）＋三次審稿、output 全滿。生成的 input 用該臂的提示詞；審稿用最長卡片組出的
 * 審稿提示詞。
 */
export function estimateRuns(
  runs: readonly { generationChars: number; criticChars: number }[],
  tokensPerChar = INITIAL_TOKENS_PER_CHAR,
): Estimate {
  let typicalUsd = 0;
  let worstUsd = 0;
  for (const run of runs) {
    const genIn = Math.ceil(run.generationChars * tokensPerChar);
    const retryIn = Math.ceil(
      (run.generationChars + RETRY_SUFFIX_CHARS) * tokensPerChar,
    );
    const criticIn = Math.ceil(run.criticChars * tokensPerChar);
    typicalUsd += callCostUsd(genIn, TYPICAL_GENERATION_OUTPUT_TOKENS) +
      callCostUsd(criticIn, TYPICAL_CRITIC_OUTPUT_TOKENS);
    worstUsd += callCostUsd(genIn, GENERATION_MAX_TOKENS) +
      2 * callCostUsd(retryIn, GENERATION_MAX_TOKENS) +
      3 * callCostUsd(criticIn, CRITIC_MAX_TOKENS);
  }
  return {
    runs: runs.length,
    typicalCalls: runs.length * TYPICAL_CALLS_PER_RUN,
    worstCalls: runs.length * MAX_CALLS_PER_RUN,
    typicalUsd,
    worstUsd,
  };
}

// ---------------------------------------------------------------------------
// 參數
// ---------------------------------------------------------------------------

export type Options = {
  tag: string;
  repeat: number;
  seed: number;
  only: string[] | null;
  arms: readonly Arm[];
  baseRef: string;
  run: boolean;
  maxCalls: number | null;
  budgetUsd: number | null;
};

const BOOL_FLAGS = ["run", "confirm-paid"];
const VALUE_FLAGS = [
  "tag",
  "repeat",
  "seed",
  "only",
  "arms",
  "base-ref",
  "max-calls",
  "budget-usd",
];

export function parseFlags(
  args: readonly string[],
  boolFlags: readonly string[],
  valueFlags: readonly string[],
): Map<string, string | true> {
  const values = new Map<string, string | true>();
  for (const arg of args) {
    const m = /^--([a-z-]+)(?:=(.+))?$/.exec(arg);
    const key = m?.[1] ?? "";
    const known = m !== null &&
      (m[2] === undefined ? boolFlags.includes(key) : valueFlags.includes(key));
    if (!known || values.has(key)) {
      throw new Error(`未知、重複或格式錯誤的參數：${arg}`);
    }
    values.set(key, m[2] ?? true);
  }
  return values;
}

export function intFlag(
  values: Map<string, string | true>,
  key: string,
  fallback: number,
  max: number,
): number {
  const raw = values.get(key);
  if (raw === undefined) return fallback;
  if (typeof raw !== "string" || !/^\d+$/.test(raw)) {
    throw new Error(`--${key} 要是 1–${max} 的整數`);
  }
  const value = Number(raw);
  if (value < 1 || value > max) throw new Error(`--${key} 要是 1–${max} 的整數`);
  return value;
}

export function tagFlag(values: Map<string, string | true>, fallback: string) {
  const tag = values.get("tag");
  const value = typeof tag === "string" ? tag : fallback;
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(value)) {
    throw new Error("--tag 只能用英數、-、_");
  }
  return value;
}

/** 真跑的守門：四個旗標少一個就拒絕。 */
export function paidFlags(values: Map<string, string | true>): {
  run: boolean;
  maxCalls: number | null;
  budgetUsd: number | null;
} {
  const budgetRaw = values.get("budget-usd");
  const budgetUsd = typeof budgetRaw === "string" ? Number(budgetRaw) : null;
  if (budgetUsd !== null && !(Number.isFinite(budgetUsd) && budgetUsd > 0)) {
    throw new Error("--budget-usd 要是正數");
  }
  const maxCalls = values.has("max-calls")
    ? intFlag(values, "max-calls", 0, 2000)
    : null;
  const run = values.has("run");
  if (
    run && (!values.has("confirm-paid") || maxCalls === null ||
      budgetUsd === null)
  ) {
    throw new Error(
      "真跑必須同時帶 --run --confirm-paid --max-calls=<上限> --budget-usd=<上限>（Eric 當次授權後）",
    );
  }
  return { run, maxCalls, budgetUsd };
}

export function parseOptions(args: readonly string[]): Options {
  const values = parseFlags(args, BOOL_FLAGS, VALUE_FLAGS);
  const onlyRaw = values.get("only");
  const only = typeof onlyRaw === "string" ? onlyRaw.split(",") : null;
  if (
    only &&
    (new Set(only).size !== only.length ||
      only.some((id) => !CASES.some((c) => c.id === id)))
  ) {
    throw new Error("--only 有重複或不存在的案例 ID");
  }
  const armsRaw = values.get("arms") ?? "both";
  const arms = armsRaw === "both" ? ARMS : ARMS.filter((arm) => arm === armsRaw);
  if (arms.length === 0) throw new Error("--arms 只能是 base、cand 或 both");
  // 基準只收 commit SHA：分支名會移動，結果就對不回真正的改前版本。
  const baseRefRaw = values.get("base-ref");
  const baseRef = typeof baseRefRaw === "string" ? baseRefRaw : DEFAULT_BASE_REF;
  if (!/^[0-9a-f]{7,40}$/.test(baseRef)) {
    throw new Error("--base-ref 要是 7–40 位的 commit SHA");
  }
  return {
    tag: tagFlag(values, "dry-run"),
    repeat: intFlag(values, "repeat", 1, 5),
    seed: intFlag(values, "seed", 20261021, 0xffffffff),
    only,
    arms,
    baseRef,
    ...paidFlags(values),
  };
}

// ---------------------------------------------------------------------------
// 網路閘：乾跑一律不連網；真跑只放行有預留的那一次 Anthropic 呼叫
// ---------------------------------------------------------------------------

export const ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages";

export class NetworkGate {
  #allowNext = 0;
  readonly #realFetch: typeof fetch;

  constructor(realFetch: typeof fetch = globalThis.fetch) {
    this.#realFetch = realFetch;
  }

  /** 換掉 globalThis.fetch。要在載入任何會呼叫模型的模組之前裝好。 */
  install(): void {
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
      const url = typeof input === "string"
        ? input
        : input instanceof URL
        ? input.href
        : input.url;
      if (this.#allowNext <= 0 || url !== ANTHROPIC_MESSAGES_URL) {
        return Promise.reject(
          new Error(`評測網路閘：沒有預留的呼叫，拒絕連到 ${url}`),
        );
      }
      this.#allowNext -= 1;
      return this.#realFetch(input, init);
    }) as typeof fetch;
  }

  /** 放行接下來的一次 Anthropic 呼叫（只由 PaidCaller 在預留後呼叫）。 */
  allowOne(): void {
    this.#allowNext += 1;
  }

  revoke(): void {
    this.#allowNext = 0;
  }
}

// ---------------------------------------------------------------------------
// 付費呼叫守門：每次送出前預留最壞情況；超過預算或次數就整批停
// ---------------------------------------------------------------------------

export class BudgetStop extends Error {
  constructor(reason: string) {
    super(`eval_budget_stop: ${reason}`);
  }
}

export type CallLogRow = Record<string, unknown>;

export type ClaudeLikeArgs = {
  model: string;
  prompt: string;
  maxTokens: number;
  timeoutMs: number;
  apiKey: string;
};

export class PaidCaller {
  spentUsd = 0;
  calls = 0;
  tokensPerChar = INITIAL_TOKENS_PER_CHAR;
  stopped: string | null = null;
  overReserveCount = 0;
  readonly #maxCalls: number;
  readonly #budgetUsd: number;
  readonly #gate: NetworkGate | null;
  readonly #log: (row: CallLogRow) => void;

  constructor(opts: {
    maxCalls: number;
    budgetUsd: number;
    gate: NetworkGate | null;
    log: (row: CallLogRow) => void;
  }) {
    this.#maxCalls = opts.maxCalls;
    this.#budgetUsd = opts.budgetUsd;
    this.#gate = opts.gate;
    this.#log = opts.log;
  }

  /**
   * 包住一支 callClaudeAPI 形狀的函式。kind 只是記錄用（generate／critic／judge）。
   * 停了以後的呼叫一律丟 BudgetStop；API 失敗或沒回 usage 時成本當預留額計入並停。
   */
  wrap(
    key: string,
    kind: string,
    call: (args: ClaudeLikeArgs) => Promise<unknown>,
  ): (args: ClaudeLikeArgs) => Promise<unknown> {
    return async (args) => {
      if (this.stopped !== null) throw new BudgetStop(this.stopped);
      if (this.calls + 1 > this.#maxCalls) {
        this.stopped = `max_calls=${this.#maxCalls}`;
        throw new BudgetStop(this.stopped);
      }
      const reserve = reserveUsd(
        args.prompt.length,
        args.maxTokens,
        this.tokensPerChar,
      );
      if (this.spentUsd + reserve > this.#budgetUsd) {
        this.stopped = `budget_usd=${this.#budgetUsd}`;
        throw new BudgetStop(this.stopped);
      }
      this.calls += 1;
      const seq = this.calls;
      this.#log({
        event: "send",
        seq,
        key,
        kind,
        model: args.model,
        promptChars: args.prompt.length,
        maxTokens: args.maxTokens,
        reserveUsd: reserve,
        at: new Date().toISOString(),
      });
      let data: unknown;
      try {
        this.#gate?.allowOne();
        data = await call(args);
      } catch (error) {
        this.#gate?.revoke();
        this.spentUsd += reserve;
        this.stopped = `api_error at #${seq}`;
        this.#log({
          event: "error",
          seq,
          key,
          kind,
          message: error instanceof Error ? error.message : String(error),
          chargedAsUsd: reserve,
        });
        throw error;
      }
      this.#gate?.revoke();
      const usage = (data as { usage?: Record<string, unknown> })?.usage;
      const inputTokens = typeof usage?.input_tokens === "number"
        ? usage.input_tokens
        : null;
      const outputTokens = typeof usage?.output_tokens === "number"
        ? usage.output_tokens
        : null;
      if (inputTokens === null || outputTokens === null) {
        this.spentUsd += reserve;
        this.stopped = `missing_usage at #${seq}`;
        this.#log({ event: "no_usage", seq, key, kind, chargedAsUsd: reserve });
        return data;
      }
      const cost = callCostUsd(inputTokens, outputTokens);
      this.spentUsd += cost;
      if (cost > reserve) this.overReserveCount += 1;
      if (args.prompt.length > 0) {
        this.tokensPerChar = Math.max(
          this.tokensPerChar,
          inputTokens / args.prompt.length,
        );
      }
      this.#log({
        event: "done",
        seq,
        key,
        kind,
        inputTokens,
        outputTokens,
        costUsd: cost,
        overReserve: cost > reserve,
        stopReason: (data as { stop_reason?: unknown })?.stop_reason ?? null,
      });
      return data;
    };
  }
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** 可重現的亂數（mulberry32）：同 seed 同順序。 */
export function seededRandom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export async function git(args: string[], cwd?: string): Promise<string> {
  const out = await new Deno.Command("git", {
    args,
    cwd,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!out.success) {
    throw new Error(
      `git ${args.join(" ")} 失敗：${new TextDecoder().decode(out.stderr)}`,
    );
  }
  return new TextDecoder().decode(out.stdout).trim();
}

/** 用 git archive 把那一版的 supabase/functions 取到暫存目錄（唯讀，不動工作樹）。 */
export async function materializeRef(
  ref: string,
): Promise<{ sha: string; root: URL }> {
  const sha = await git(["rev-parse", "--verify", `${ref}^{commit}`]);
  const tmp = await Deno.makeTempDir({
    prefix: `coach-about-me-eval-base-${sha.slice(0, 8)}-`,
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

/**
 * 評審要用產生回答當時的題庫：run.ts 把 cases.json 原文存成 cases.snapshot.json，
 * manifest 記它的 sha256。對不上就停，免得拿改過的題目評舊回答。
 */
export async function verifyCasesSnapshot(
  manifest: { casesSha256?: unknown },
  snapshotText: string,
): Promise<EvalCase[]> {
  const sha = await sha256Hex(snapshotText);
  if (typeof manifest.casesSha256 !== "string" || manifest.casesSha256 !== sha) {
    throw new Error(
      `題庫快照的 sha256（${sha}）跟產生回答時的 manifest 對不上，停止評審`,
    );
  }
  return (JSON.parse(snapshotText) as { cases: EvalCase[] }).cases;
}

/** 不覆寫既有證據：同名輸出目錄已存在就拒絕。 */
export async function createOutDir(base: URL, tag: string): Promise<URL> {
  const out = new URL(`out/${tag}/`, base);
  try {
    await Deno.stat(out);
    throw new Error(`輸出目錄 out/${tag}/ 已存在，換一個 --tag`);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  await Deno.mkdir(out, { recursive: true });
  return out;
}

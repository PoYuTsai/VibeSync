// 上一輪脈絡黑箱（2026-10-18；這次只準備，付費真跑要 Eric 當次說「跑」）。
//
// cases.json 的 10 個自寫兩輪案例（她回答了他的問題、她換話題、他推進後她變冷、她反問他），
// 每案用新片段的內容跑兩次正式的 v3 分析：一次不帶 previousRound、一次帶（App 會送的那份）。
// 走整個 analyze-chat handler（guide_v3/v3_stream_harness.ts：假 Supabase；ANALYZE_GUIDE_V3 與
// ANALYZE_GUIDE_V3_PREV_ROUND 都是 on、對象記憶關），模型那一跳 dry-run 回假的，真跑才打
// Anthropic（只放行 claude-sonnet-5-5，備援模型一律擋下、記失敗）。
//
// 每次記：決定、燈號、局面判讀、卡片任務與文字、扣了幾則（兩邊要一樣）、帶的那份有沒有真的進
// 讀局面提示詞；卡片有沒有用到只出現在上一輪的詞（contextWords），有沒有照抄上一段的訊息。
// 上一輪不帶「他複製的那張」（主審第 1 輪 P2）；他傳過的那句要讓模型看到，就照真實用法貼進新片段。
// summary.md 列每案兩邊對照給人看。
//
// dry-run（不花錢、不連網、不讀金鑰；寫 out/<tag>/plan.json、manifest.json、records.json，印估價與
// 真跑指令）：
//   deno run --no-prompt --allow-read --allow-env \
//     --allow-write=tools/v3-prev-round-blackbox/out \
//     tools/v3-prev-round-blackbox/run.ts --tag=prev-dry
//
// 真跑（四個旗標缺一個就拒絕；追蹤檔有未提交修改、out/<tag> 已存在也拒絕）：
//   deno run --no-prompt --allow-read --allow-env --allow-run=git \
//     --allow-write=tools/v3-prev-round-blackbox/out --allow-net=api.anthropic.com \
//     tools/v3-prev-round-blackbox/run.ts --tag=prev-r1 \
//     --run --confirm-paid --max-calls=<dry-run 印的次數> --budget-usd=<dry-run 印的上限>
//
// 費用：每次送出前先預留上限（input token＝提示詞字數×2，全部用快取寫入單價；output 用請求的
// max_tokens 全滿），已花費＋預留超過 --budget-usd、或到 --max-calls 就整批停，剩下的記 NOT_RUN；
// 收到 usage 後改記實際費用，字數換 token 的比例只往上校正。API 失敗或沒回 usage 照預留計並停。
// 金鑰讀 ~/.config/anthropic/key（只有真跑才讀）。輸出在 out/<tag>/（已 gitignore）。
import {
  estimateCostUsd,
  SONNET_5_5_PRICING,
} from "../../supabase/functions/_shared/model_pricing.ts";
import { parsePreviousRound } from "../../supabase/functions/analyze-chat/guide_v3/previous_round.ts";
import {
  fakeReadResponse,
  fakeWriteResponse,
  type V3HarnessModel,
  type V3HarnessOutcome,
} from "../../supabase/functions/analyze-chat/guide_v3/v3_stream_harness.ts";

export const MODEL = "claude-sonnet-5-5";
export const TOKENS_PER_CHAR = 2;
/// 10/18 正式程式黑箱的中位數：讀局面約 330、寫卡約 310（含隱藏思考），估一般費用用。
export const TYPICAL_OUTPUT_TOKENS = 350;
export const ARMS = ["without", "with"] as const;
export const SHAPES = [
  "answered",
  "topic_change",
  "cold_after_push",
  "asked_him",
] as const;
export const DEFAULT_REPEAT = 2;
/// 讀局面提示詞裡上一輪那段的標題（guide_v3/previous_round.ts）。
export const PREVIOUS_SECTION_TITLE = "## 上一輪（比下面的對話早）";

const ROOT = new URL("../../", import.meta.url);
const OUT_ROOT = new URL("tools/v3-prev-round-blackbox/out/", ROOT);
const CASES = new URL("tools/v3-prev-round-blackbox/cases.json", ROOT);

type Arm = typeof ARMS[number];
type Shape = typeof SHAPES[number];
type ChatMessage = { readonly isFromMe: boolean; readonly content: string };

export interface BlackboxCase {
  readonly id: string;
  readonly shape: Shape;
  readonly previousRound: Record<string, unknown>;
  readonly now: readonly ChatMessage[];
  readonly contextWords: readonly string[];
  readonly lookFor: string;
}

export interface CaseFile {
  readonly version: number;
  readonly cases: readonly BlackboxCase[];
}

/// 案例檔的自我檢查：至少 10 案、id 不重複、四種形狀都有；上一輪要過伺服器的驗證
///（不然真跑時那份會被整份丟掉，兩邊等於一樣），也不能帶 App 已經不送的「他複製的那張」；
/// 新片段要有她的訊息；contextWords 不能出現在新片段裡（不然「用到上一輪」的計數沒有意義）。
/// 回傳問題清單，空的就是過。
export function validateCases(file: CaseFile): string[] {
  const problems: string[] = [];
  if (file.version !== 1) problems.push("version 要是 1");
  if (file.cases.length < 10) problems.push("至少 10 案");
  const ids = new Set<string>();
  for (const c of file.cases) {
    if (ids.has(c.id)) problems.push(`${c.id}：id 重複`);
    ids.add(c.id);
    if (!SHAPES.includes(c.shape)) problems.push(`${c.id}：不認得的形狀`);
    const parsed = parsePreviousRound(c.previousRound);
    if (parsed.kind !== "ok") {
      problems.push(`${c.id}：上一輪過不了伺服器驗證（${parsed.kind}）`);
    }
    if ("sentCard" in c.previousRound) {
      problems.push(`${c.id}：上一輪不帶 sentCard`);
    }
    if (!c.now.some((m) => !m.isFromMe)) {
      problems.push(`${c.id}：新片段沒有她的訊息`);
    }
    const nowText = c.now.map((m) => m.content).join("\n");
    if (c.contextWords.length === 0) {
      problems.push(`${c.id}：沒有 contextWords`);
    }
    for (const word of c.contextWords) {
      if (nowText.includes(word)) {
        problems.push(`${c.id}：contextWords「${word}」出現在新片段`);
      }
    }
  }
  for (const shape of SHAPES) {
    if (!file.cases.some((c) => c.shape === shape)) {
      problems.push(`缺形狀 ${shape}`);
    }
  }
  return problems;
}

export interface PlannedRun {
  readonly id: string;
  readonly case: BlackboxCase;
  readonly arm: Arm;
  readonly repeat: number;
}

/// 同一案兩邊緊接著跑，快取狀況比較接近。
export function planRuns(
  cases: readonly BlackboxCase[],
  repeat = DEFAULT_REPEAT,
): PlannedRun[] {
  const runs: PlannedRun[] = [];
  for (const c of cases) {
    for (let r = 1; r <= repeat; r++) {
      for (const arm of ARMS) {
        runs.push({ id: `${c.id}|${arm}|${r}`, case: c, arm, repeat: r });
      }
    }
  }
  return runs;
}

/// App 送的 body（analyze_stream_client.dart 的 buildStreamBody 同樣的欄位）。
export function requestBodyFor(run: PlannedRun): Record<string, unknown> {
  return {
    responseMode: "stream",
    messages: run.case.now,
    billingProtocolVersion: 3,
    analysisContractVersion: 3,
    ...(run.arm === "with" ? { previousRound: run.case.previousRound } : {}),
  };
}

function compact(text: string): string {
  return text.replace(/[^\p{L}\p{N}]/gu, "");
}

export interface RunChecks {
  /// 用到只出現在上一輪的詞的卡片張數。
  readonly contextHitCards: number;
  /// 有一則照抄上一段的某則訊息（去掉標點後包含那一則，那則至少 6 字）。
  readonly copiesPreviousMessage: boolean;
}

export function inspectCards(
  c: BlackboxCase,
  cards: readonly { readonly messages: readonly string[] }[],
): RunChecks {
  const previous =
    (Array.isArray(c.previousRound.messages)
      ? c.previousRound.messages as { content?: unknown }[]
      : [])
      .map((m) => compact(String(m.content ?? "")))
      .filter((m) => m.length >= 6);
  return {
    contextHitCards:
      cards.filter((card) =>
        card.messages.some((m) => c.contextWords.some((w) => m.includes(w)))
      ).length,
    copiesPreviousMessage: cards.some((card) =>
      card.messages.some((m) => {
        const message = compact(m);
        return previous.some((p) => message.includes(p));
      })
    ),
  };
}

/// 模型請求的提示詞字數（system 區塊＋使用者那一則）。
export function promptChars(body: Record<string, unknown>): {
  system: number;
  user: number;
} {
  const system = (body.system as { text?: string }[] | undefined ?? [])
    .map((b) => b.text ?? "").join("");
  const user = (body.messages as { content?: unknown }[] | undefined ?? [])
    .map((m) => typeof m.content === "string" ? m.content : "").join("");
  return { system: system.length, user: user.length };
}

/// 保守預留：input 全用快取寫入單價、output 用這次請求的 max_tokens 全滿。
export function reservationUsd(
  chars: number,
  maxTokens: number,
  tokensPerChar = TOKENS_PER_CHAR,
): number {
  return (Math.ceil(chars * tokensPerChar) *
      SONNET_5_5_PRICING.cacheWritePerMTok +
    maxTokens * SONNET_5_5_PRICING.outputPerMTok) / 1_000_000;
}

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

export interface CallShape {
  readonly systemKey: string;
  readonly systemChars: number;
  readonly userChars: number;
  readonly maxTokens: number;
}

export interface PlanEstimate {
  readonly runs: number;
  readonly maxCalls: number;
  readonly typicalUsd: number;
  readonly upperBoundUsd: number;
  /// 建議的 --budget-usd：一般估價加上最大一次預留，再留五成，進位到 0.5，至少 1。
  readonly suggestedBudgetUsd: number;
}

/// 一般：每段的 system 第一次出現寫快取、之後讀快取；使用者那段用一般 input 單價；
/// output 約 350。上限：每次呼叫都用 reservationUsd（不快取、output 全滿）。
export function estimatePlan(
  calls: readonly CallShape[],
  runs: number,
): PlanEstimate {
  const seen = new Set<string>();
  let typical = 0;
  let upper = 0;
  let largest = 0;
  for (const call of calls) {
    const systemTokens = Math.ceil(call.systemChars * TOKENS_PER_CHAR);
    const first = !seen.has(call.systemKey);
    seen.add(call.systemKey);
    typical += estimateCostUsd({
      inputTokens: Math.ceil(call.userChars * TOKENS_PER_CHAR),
      outputTokens: TYPICAL_OUTPUT_TOKENS,
      cacheReadInputTokens: first ? 0 : systemTokens,
      cacheCreationInputTokens: first ? systemTokens : 0,
    }, SONNET_5_5_PRICING);
    const reservation = reservationUsd(
      call.systemChars + call.userChars,
      call.maxTokens,
    );
    upper += reservation;
    largest = Math.max(largest, reservation);
  }
  return {
    runs,
    maxCalls: calls.length,
    typicalUsd: typical,
    upperBoundUsd: upper,
    suggestedBudgetUsd: Math.max(
      1,
      Math.ceil((typical + largest) * 1.5 * 2) / 2,
    ),
  };
}

// ---------------------------------------------------------------------------
// 執行
// ---------------------------------------------------------------------------

interface Options {
  tag: string;
  run: boolean;
  confirmPaid: boolean;
  maxCalls: number | null;
  budgetUsd: number | null;
  repeat: number;
  verbose: boolean;
}

export function parseOptions(args: readonly string[]): Options {
  const values = new Map<string, string>();
  const flags = new Set<string>();
  for (const arg of args) {
    const m = arg.match(/^--([a-z-]+)(?:=(.*))?$/);
    if (!m) throw new Error(`看不懂的參數：${arg}`);
    if (m[2] === undefined) flags.add(m[1]);
    else values.set(m[1], m[2]);
  }
  const known = [
    "tag",
    "run",
    "confirm-paid",
    "max-calls",
    "budget-usd",
    "repeat",
    "verbose",
  ];
  for (const name of [...values.keys(), ...flags]) {
    if (!known.includes(name)) throw new Error(`不認得的參數：--${name}`);
  }
  const tag = values.get("tag") ?? "";
  if (!/^[A-Za-z0-9._-]+$/.test(tag)) {
    throw new Error("--tag 必填，只能用英數、點、底線、連字號");
  }
  const number = (name: string) =>
    values.has(name) ? Number(values.get(name)) : null;
  const maxCalls = number("max-calls");
  const budgetUsd = number("budget-usd");
  const repeat = number("repeat") ?? DEFAULT_REPEAT;
  if (maxCalls !== null && !(Number.isInteger(maxCalls) && maxCalls > 0)) {
    throw new Error("--max-calls 要是正整數");
  }
  if (budgetUsd !== null && !(budgetUsd > 0)) {
    throw new Error("--budget-usd 要是正數");
  }
  if (!(Number.isInteger(repeat) && repeat >= 1 && repeat <= 5)) {
    throw new Error("--repeat 要是 1–5 的整數");
  }
  const run = flags.has("run");
  if (
    run &&
    (!flags.has("confirm-paid") || maxCalls === null || budgetUsd === null)
  ) {
    throw new Error(
      "真跑必須同時帶 --run --confirm-paid --max-calls=<上限> --budget-usd=<上限>（Eric 當次授權後）",
    );
  }
  return {
    tag,
    run,
    confirmPaid: flags.has("confirm-paid"),
    maxCalls,
    budgetUsd,
    repeat,
    verbose: flags.has("verbose"),
  };
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function exists(url: URL): Promise<boolean> {
  try {
    await Deno.stat(url);
    return true;
  } catch {
    return false;
  }
}

async function git(args: string[]): Promise<string> {
  const out = await new Deno.Command("git", { args, cwd: ROOT }).output();
  if (!out.success) throw new Error(`git ${args.join(" ")} 失敗`);
  return new TextDecoder().decode(out.stdout).trim();
}

function blockedResponse(message: string): Response {
  return new Response(
    JSON.stringify({
      type: "error",
      error: { type: "invalid_request_error", message },
    }),
    { status: 400, headers: { "content-type": "application/json" } },
  );
}

/// dry-run 的假讀局面：綠燈、一般分享，流程一定走到出卡。
const FAKE_READ_TAGS = {
  light: "green",
  herMove: "生活",
  herMoodBad: false,
  drunkOrLateNight: false,
  inviteReadiness: "沒機會",
  cancelHasAlternative: false,
  retreating: false,
  declinedOrBoundary: false,
  explicitRejection: false,
  blocked: false,
  risk: false,
  selfHarmSignal: false,
  minorSignal: false,
  needsHisFacts: false,
  identityQuestion: false,
  hisStatedFacts: [],
  hasHisVoiceSample: false,
  replyWillingness: "high",
  worthyBallCount: 1,
  herTurnsPerfunctory: [],
  matchedEntries: [],
  readForUser: "dry-run：假的判讀。",
  waitFor: "",
};

const FAKE_CARD_LINES = [1, 2, 3, 4, 5].map((card) =>
  JSON.stringify({
    card,
    messages: [`dry-run 第 ${card} 張`],
    hasInventedDetail: false,
  })
);

interface ProviderCall {
  stage: "read" | "write";
  model: string;
  status: number | "BLOCKED";
  reservationUsd: number;
  actualUsd: number | null;
  usage: Record<string, number> | null;
}

interface RunRecord {
  id: string;
  caseId: string;
  shape: Shape;
  arm: Arm;
  repeat: number;
  status: number | "NOT_RUN_CAP_OR_STOP";
  errorCode: string | null;
  decision: string | null;
  light: string | null;
  judgment: string | null;
  cards: { slot: number; task: string; messages: string[] }[];
  chargedMessages: number | null;
  /// 讀局面提示詞裡有沒有上一輪那段（with 要有、without 不能有）。
  previousSectionInRead: boolean | null;
  checks: RunChecks | null;
  providerCalls: ProviderCall[];
}

export function recordFrom(
  run: PlannedRun,
  outcome: V3HarnessOutcome,
): Omit<RunRecord, "providerCalls"> {
  const read = outcome.events.find((e) => e.type === "analysis.read");
  const error = outcome.events.find((e) => e.type === "analysis.error");
  const cards = outcome.events
    .filter((e) => e.type === "analysis.card")
    .map((e) => ({
      slot: Number(e.slot),
      task: String(e.task),
      messages: (e.messages as string[]).map(String),
    }));
  const charge = outcome.rpcs.find((r) =>
    r.fn === "charge_stream_analysis_run_v3"
  );
  const readBody = outcome.modelBodies.find((b) => b.stream !== true);
  const readUser = readBody
    ? ((readBody.messages as { content?: unknown }[])[0]?.content ?? "")
    : null;
  return {
    id: run.id,
    caseId: run.case.id,
    shape: run.case.shape,
    arm: run.arm,
    repeat: run.repeat,
    status: outcome.status,
    errorCode: error ? String(error.code) : null,
    decision: read ? String(read.decision) : null,
    light: read ? String(read.light) : null,
    judgment: read ? String(read.judgment ?? "") : null,
    cards,
    chargedMessages: charge ? Number(charge.args.p_message_count) : null,
    previousSectionInRead: readUser === null
      ? null
      : String(readUser).includes(PREVIOUS_SECTION_TITLE),
    checks: read ? inspectCards(run.case, cards) : null,
  };
}

function headersWithoutLength(headers: Headers): Headers {
  const out = new Headers(headers);
  out.delete("content-length");
  out.delete("content-encoding");
  return out;
}

function usageFrom(raw: unknown): Record<string, number> | null {
  const u = raw as Record<string, unknown> | null | undefined;
  if (!u || typeof u.output_tokens !== "number") return null;
  return {
    inputTokens: Number(u.input_tokens ?? 0),
    outputTokens: Number(u.output_tokens),
    cacheReadInputTokens: Number(u.cache_read_input_tokens ?? 0),
    cacheCreationInputTokens: Number(u.cache_creation_input_tokens ?? 0),
  };
}

function pct(n: number, d: number): string {
  return d === 0 ? "—" : `${n}/${d}（${Math.round((n / d) * 100)}%）`;
}

function summarize(
  cases: readonly BlackboxCase[],
  records: readonly RunRecord[],
  spentUsd: number,
  calls: number,
): string {
  const ran = records.filter((r) => r.status !== "NOT_RUN_CAP_OR_STOP");
  const ok = ran.filter((r) => r.decision !== null);
  const byArm = (arm: Arm) => ok.filter((r) => r.arm === arm);
  const count = (rs: readonly RunRecord[], f: (r: RunRecord) => boolean) =>
    rs.filter(f).length;
  const lines = [
    "# 上一輪脈絡黑箱結果",
    "",
    `- 規劃 ${records.length} 次分析；實際跑 ${ran.length} 次；模型呼叫 ${calls} 次，花費約 US$${
      spentUsd.toFixed(4)
    }。`,
    `- 有判讀：${pct(ok.length, ran.length)}`,
    `- 帶的那份有進讀局面提示詞：${
      pct(
        count(byArm("with"), (r) => r.previousSectionInRead === true),
        byArm("with").length,
      )
    }；沒帶的混進去：${
      count(byArm("without"), (r) => r.previousSectionInRead === true)
    } 次`,
    "",
    "| | 沒帶 | 帶 |",
    "| :-- | --: | --: |",
    ...(["send", "close", "hold", "stop", "care"] as const).map((d) =>
      `| 決定 ${d} | ${count(byArm("without"), (r) => r.decision === d)} | ${
        count(byArm("with"), (r) => r.decision === d)
      } |`
    ),
    ...(["green", "yellow", "red"] as const).map((l) =>
      `| 燈號 ${l} | ${count(byArm("without"), (r) => r.light === l)} | ${
        count(byArm("with"), (r) => r.light === l)
      } |`
    ),
    `| 有推進卡的次數 | ${
      count(byArm("without"), (r) => r.cards.some((c) => c.task === "push"))
    } | ${
      count(byArm("with"), (r) => r.cards.some((c) => c.task === "push"))
    } |`,
    `| 用到上一輪的詞（張） | ${
      byArm("without").reduce((n, r) => n + (r.checks?.contextHitCards ?? 0), 0)
    } | ${
      byArm("with").reduce((n, r) => n + (r.checks?.contextHitCards ?? 0), 0)
    } |`,
    `| 照抄上一段的訊息（次） | ${
      count(byArm("without"), (r) => r.checks?.copiesPreviousMessage === true)
    } | ${
      count(byArm("with"), (r) => r.checks?.copiesPreviousMessage === true)
    } |`,
    "",
    "## 每案對照（人工看 lookFor）",
  ];
  for (const c of cases) {
    lines.push("", `### ${c.id}（${c.shape}）`, "", `- 看什麼：${c.lookFor}`);
    for (const r of ran.filter((x) => x.caseId === c.id)) {
      const head = r.decision === null
        ? `${r.status} ${r.errorCode ?? ""}`
        : `${r.light}・${r.decision}・扣 ${r.chargedMessages ?? 0} 則`;
      lines.push(
        `- ${r.arm} #${r.repeat}：${head}；判讀：${r.judgment ?? "—"}`,
      );
      for (const card of r.cards) {
        lines.push(
          `  - ${card.slot}. ${card.task}：${card.messages.join(" ／ ")}`,
        );
      }
    }
  }
  return lines.join("\n") + "\n";
}

async function main(): Promise<void> {
  const options = parseOptions(Deno.args);
  const outDir = new URL(`${options.tag}/`, OUT_ROOT);
  if (await exists(outDir)) {
    throw new Error(`out/${options.tag} 已經存在，不覆寫證據；換一個 --tag`);
  }
  const casesText = await Deno.readTextFile(CASES);
  const caseFile = JSON.parse(casesText) as CaseFile;
  const problems = validateCases(caseFile);
  if (problems.length) throw new Error(`cases.json：\n${problems.join("\n")}`);
  const plan = planRuns(caseFile.cases, options.repeat);

  let head = "";
  let apiKey = "fake-claude-key";
  if (options.run) {
    head = await git(["rev-parse", "HEAD"]);
    const dirty = await git(["status", "--porcelain", "--untracked-files=no"]);
    if (dirty) throw new Error("追蹤檔有未提交修改，結果對不回 commit；先提交");
    const home = Deno.env.get("HOME");
    if (!home) throw new Error("讀不到 HOME，找不到金鑰");
    apiKey = (await Deno.readTextFile(`${home}/.config/anthropic/key`)).trim();
    if (!apiKey) throw new Error("~/.config/anthropic/key 是空的");
  }
  // handler 一載入就讀 env 常數，寫卡的 streaming_fallback 也在載入時存下 fetch：先記下
  // 真的 fetch、裝轉接器、設好 env，最後才載入入口。
  const nativeFetch = globalThis.fetch;
  await import(
    "../../supabase/functions/analyze-chat/test_fetch_dispatcher.ts"
  );
  for (
    const [k, v] of Object.entries({
      SUPABASE_URL: "http://supabase.blackbox",
      SUPABASE_SERVICE_ROLE_KEY: "fake-service-key",
      CLAUDE_API_KEY: apiKey,
      STREAM_ANALYZE_ENABLED: "true",
    })
  ) Deno.env.set(k, v);
  const { createAnalyzeChatHandler } = await import(
    "../../supabase/functions/analyze-chat/index.ts"
  );
  const { runGuideV3StreamThroughHandler } = await import(
    "../../supabase/functions/analyze-chat/guide_v3/v3_stream_harness.ts"
  );

  // handler 會印很多 log；預設關掉，--verbose 才留。
  const print = console.log.bind(console);
  const quiet = () => {
    if (options.verbose) return () => {};
    const saved = [console.log, console.info, console.warn, console.error];
    console.log =
      console.info =
      console.warn =
      console.error =
        () => {};
    return () => {
      [console.log, console.info, console.warn, console.error] = saved;
    };
  };

  await Deno.mkdir(outDir, { recursive: true });
  const requestsLog = new URL("requests.jsonl", outDir);
  const appendLog = (entry: Record<string, unknown>) =>
    Deno.writeTextFile(
      requestsLog,
      JSON.stringify({ at: new Date().toISOString(), ...entry }) + "\n",
      { append: true },
    );

  const records: RunRecord[] = [];
  const callShapes: CallShape[] = [];
  const systemKeys = new Set<string>();
  let spentUsd = 0;
  let calls = 0;
  let stopped = false;
  let tokensPerChar = TOKENS_PER_CHAR;

  for (const run of plan) {
    const record: RunRecord = {
      id: run.id,
      caseId: run.case.id,
      shape: run.case.shape,
      arm: run.arm,
      repeat: run.repeat,
      status: "NOT_RUN_CAP_OR_STOP",
      errorCode: null,
      decision: null,
      light: null,
      judgment: null,
      cards: [],
      chargedMessages: null,
      previousSectionInRead: null,
      checks: null,
      providerCalls: [],
    };
    records.push(record);
    if (stopped) continue;

    const model: V3HarnessModel = async (request, init) => {
      const stage = request.stream === true ? "write" : "read";
      const chars = promptChars(request);
      const systemText = (request.system as { text?: string }[] | undefined ??
        []).map((b) => b.text ?? "").join("");
      const systemKey = await sha256(systemText);
      systemKeys.add(systemKey);
      callShapes.push({
        systemKey,
        systemChars: chars.system,
        userChars: chars.user,
        maxTokens: Number(request.max_tokens),
      });
      if (!options.run) {
        return stage === "read"
          ? fakeReadResponse(FAKE_READ_TAGS)
          : fakeWriteResponse(FAKE_CARD_LINES);
      }
      const call: ProviderCall = {
        stage,
        model: String(request.model),
        status: "BLOCKED",
        reservationUsd: 0,
        actualUsd: null,
        usage: null,
      };
      record.providerCalls.push(call);
      if (request.model !== MODEL) {
        return blockedResponse("blackbox: fallback model blocked");
      }
      const reservation = reservationUsd(
        chars.system + chars.user,
        Number(request.max_tokens),
        tokensPerChar,
      );
      if (
        stopBeforeCall({
          stopped,
          calls,
          maxCalls: options.maxCalls!,
          spentUsd,
          reservationUsd: reservation,
          budgetUsd: options.budgetUsd!,
        })
      ) {
        stopped = true;
        return blockedResponse("blackbox: budget or call cap reached");
      }
      calls++;
      spentUsd += reservation;
      call.reservationUsd = reservation;
      const seq = calls;
      await appendLog({ seq, id: run.id, stage, phase: "send", reservation });
      const settle = (usage: Record<string, number> | null) => {
        if (!usage) {
          // 沒回 usage：照預留算，整批停（不當免費）。
          stopped = true;
          return;
        }
        call.usage = usage;
        call.actualUsd = estimateCostUsd(
          {
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheReadInputTokens: usage.cacheReadInputTokens,
            cacheCreationInputTokens: usage.cacheCreationInputTokens,
          },
          SONNET_5_5_PRICING,
        );
        spentUsd += call.actualUsd - reservation;
        const inputTokens = usage.inputTokens + usage.cacheReadInputTokens +
          usage.cacheCreationInputTokens;
        tokensPerChar = Math.max(
          tokensPerChar,
          inputTokens / Math.max(1, chars.system + chars.user),
        );
      };
      const response = await nativeFetch(
        "https://api.anthropic.com/v1/messages",
        init,
      );
      call.status = response.status;
      if (!response.ok || !response.body) {
        stopped = true;
        await appendLog({
          seq,
          id: run.id,
          phase: "failed",
          status: call.status,
        });
        return response;
      }
      if (stage === "read") {
        const json = await response.json();
        settle(usageFrom(json?.usage));
        await appendLog({
          seq,
          id: run.id,
          phase: "done",
          actualUsd: call.actualUsd,
        });
        return new Response(JSON.stringify(json), {
          status: response.status,
          headers: headersWithoutLength(response.headers),
        });
      }
      // 寫卡（SSE）：原樣轉送，順路記 usage；正常讀完才結帳（中途被取消就保留預留）。
      const decoder = new TextDecoder();
      let buffer = "";
      const usage: Record<string, number> = {};
      let sawOutput = false;
      const scan = (final: boolean) => {
        const lines = buffer.split("\n");
        buffer = final ? "" : lines.pop() ?? "";
        for (const line of lines) {
          if (!line.startsWith("data:")) continue;
          try {
            const event = JSON.parse(line.slice(5).trim());
            const start = usageFrom(event?.message?.usage);
            if (event?.type === "message_start" && start) {
              Object.assign(usage, start);
            }
            if (
              event?.type === "message_delta" &&
              typeof event?.usage?.output_tokens === "number"
            ) {
              usage.outputTokens = event.usage.output_tokens;
              sawOutput = true;
            }
          } catch { /* 不是 JSON 的 data 行：略過 */ }
        }
      };
      const tap = new TransformStream<Uint8Array, Uint8Array>({
        transform(chunk, controller) {
          buffer += decoder.decode(chunk, { stream: true });
          scan(false);
          controller.enqueue(chunk);
        },
        flush() {
          buffer += decoder.decode();
          scan(true);
          settle(
            sawOutput
              ? {
                inputTokens: usage.inputTokens ?? 0,
                outputTokens: usage.outputTokens ?? 0,
                cacheReadInputTokens: usage.cacheReadInputTokens ?? 0,
                cacheCreationInputTokens: usage.cacheCreationInputTokens ?? 0,
              }
              : null,
          );
          void appendLog({
            seq,
            id: run.id,
            phase: "done",
            actualUsd: call.actualUsd,
          });
        },
      });
      return new Response(response.body.pipeThrough(tap), {
        status: response.status,
        headers: response.headers,
      });
    };

    const restore = quiet();
    let outcome: V3HarnessOutcome;
    try {
      outcome = await runGuideV3StreamThroughHandler({
        createHandler: createAnalyzeChatHandler,
        body: requestBodyFor(run),
        env: {
          ANALYZE_GUIDE_V3: "on",
          ANALYZE_GUIDE_V3_PREV_ROUND: "on",
          ANALYZE_GUIDE_V3_MEMORY: undefined,
          MIN_CLIENT_BUILD: undefined,
        },
        model,
      });
    } finally {
      restore();
    }
    Object.assign(record, recordFrom(run, outcome));
    if (options.run) {
      await Deno.writeTextFile(
        new URL("records.json", outDir),
        JSON.stringify(records, null, 2),
      );
      print(
        `${run.id} → ${record.decision ?? record.status}${
          record.errorCode ? ` ${record.errorCode}` : ""
        }（已花 US$${spentUsd.toFixed(4)}）`,
      );
    }
  }

  const estimate = estimatePlan(callShapes, plan.length);
  const manifest = {
    tag: options.tag,
    mode: options.run ? "paid" : "dry-run",
    head: options.run ? head : null,
    model: MODEL,
    repeat: options.repeat,
    cases: caseFile.cases.map((c) => `${c.id}（${c.shape}）`),
    casesSha256: await sha256(casesText),
    systemPromptSha256: [...systemKeys],
    estimate,
    ...(options.run
      ? {
        calls,
        spentUsd,
        tokensPerChar,
        maxCalls: options.maxCalls,
        budgetUsd: options.budgetUsd,
      }
      : {}),
  };
  await Deno.writeTextFile(
    new URL("manifest.json", outDir),
    JSON.stringify(manifest, null, 2),
  );
  await Deno.writeTextFile(
    new URL("records.json", outDir),
    JSON.stringify(records, null, 2),
  );

  if (!options.run) {
    await Deno.writeTextFile(
      new URL("plan.json", outDir),
      JSON.stringify(plan.map((p) => p.id), null, 2),
    );
    // dry-run 的自我檢查：每次都要走到出卡；帶的那份要進讀局面提示詞、沒帶的不能有；
    // 兩邊扣的則數一樣（上一輪不算計費字數）。
    const problems: string[] = [];
    for (const r of records) {
      if (r.status !== 200 || r.decision !== "send" || r.cards.length === 0) {
        problems.push(
          `${r.id}：沒有走到出卡（${r.status} ${r.errorCode ?? ""}）`,
        );
      }
      if (r.previousSectionInRead !== (r.arm === "with")) {
        problems.push(
          `${r.id}：上一輪那段${r.arm === "with" ? "沒進" : "混進"}提示詞`,
        );
      }
    }
    for (const c of caseFile.cases) {
      const charged = new Set(
        records.filter((r) => r.caseId === c.id).map((r) => r.chargedMessages),
      );
      if (charged.size !== 1) problems.push(`${c.id}：兩邊扣的則數不一樣`);
    }
    print(
      [
        `dry-run：${caseFile.cases.length} 案 × 2 邊（沒帶／帶）× ${options.repeat} 次＝${plan.length} 次分析，最多 ${estimate.maxCalls} 次模型呼叫（讀局面＋寫卡；先別回、停只有讀局面）。`,
        `走完整條路徑：${
          problems.length === 0
            ? `${records.length}/${records.length} 次都出卡、上一輪只進「帶」那邊、兩邊扣的則數一樣`
            : `異常：\n${problems.join("\n")}`
        }。`,
        `估價：一般約 US$${
          estimate.typicalUsd.toFixed(2)
        }（system 第一次寫快取、之後讀快取，output 約 ${TYPICAL_OUTPUT_TOKENS}）；最壞上限 US$${
          estimate.upperBoundUsd.toFixed(2)
        }（每次都不快取、output 用 max_tokens 全滿）。`,
        `建議預算上限 --budget-usd=${estimate.suggestedBudgetUsd}：每次送出前預留最壞值，碰到就整批停，實際花費不會超過它。`,
        "真跑（要 Eric 當次說「跑」）：",
        `deno run --no-prompt --allow-read --allow-env --allow-run=git --allow-write=tools/v3-prev-round-blackbox/out --allow-net=api.anthropic.com tools/v3-prev-round-blackbox/run.ts --tag=<新 tag> --run --confirm-paid --max-calls=${estimate.maxCalls} --budget-usd=${estimate.suggestedBudgetUsd}${
          options.repeat === DEFAULT_REPEAT ? "" : ` --repeat=${options.repeat}`
        }`,
      ].join("\n"),
    );
    if (problems.length) Deno.exitCode = 1;
    return;
  }

  await Deno.writeTextFile(
    new URL("summary.md", outDir),
    summarize(caseFile.cases, records, spentUsd, calls),
  );
  print(
    `完成：${calls} 次呼叫，約 US$${
      spentUsd.toFixed(4)
    }；結果在 out/${options.tag}/summary.md`,
  );
}

if (import.meta.main) {
  await main();
}

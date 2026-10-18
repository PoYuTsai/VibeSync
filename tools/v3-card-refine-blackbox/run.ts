// 任務卡「再調一下」黑箱（2026-10-18；這次只準備，付費真跑要 Eric 當次說「跑」）。
//
// 從 v3 重播錄音（supabase/functions/analyze-chat/testdata/guide_v3_replay_fixtures.json）照
// 固定規則挑 20 張卡：全部推進、全部有空格的、收與共鳴各一張、一張照樣寫＋標示。每張用四顆
// 快捷指令（跟 App 的 kGuideV3RefineQuickInstructions 同一組）各跑一次正式的微調路徑：整個
// analyze-chat handler（guide_v3/refine_harness.ts，假 Supabase、免費次數一律授權），模型那一跳
// dry-run 回假的（原句照抄），真跑才打 Anthropic。
//
// 每次檢查：伺服器有沒有擋下（原因）、則數有沒有變、空格有沒有少、推進卡最後一句有沒有變成
// 徵求同意的問句（原卡本來就是的不算退步）、預設口吻有沒有「妳」、到底有沒有改。帶張力的
// 「繃緊再鬆開」沒辦法機械判斷，summary.md 列出前後對照給人看。
//
// dry-run（不花錢、不連網、不讀金鑰；寫 out/<tag>/plan.json、manifest.json，印出估價與真跑指令）：
//   deno run --no-prompt --allow-read --allow-env \
//     --allow-write=tools/v3-card-refine-blackbox/out \
//     tools/v3-card-refine-blackbox/run.ts --tag=refine-dry
//
// 真跑（四個旗標缺一個就拒絕；追蹤檔有未提交修改、out/<tag> 已存在也拒絕）：
//   deno run --no-prompt --allow-read --allow-env --allow-run=git \
//     --allow-write=tools/v3-card-refine-blackbox/out --allow-net=api.anthropic.com \
//     tools/v3-card-refine-blackbox/run.ts --tag=refine-r1 \
//     --run --confirm-paid --max-calls=<dry-run 印的次數> --budget-usd=<dry-run 印的上限>
//
// 費用（保守）：input token＝提示詞字數×1.5（真跑時依實際 usage 只往上校正），全部用快取寫入
// 單價；output 用 max_tokens 全滿；每次微調算兩次呼叫（handler 在 JSON 解析失敗時會再打一次）。
// 每次送出前先預留上限，已花費＋預留超過 --budget-usd、或到 --max-calls 就整批停，剩下的記
// NOT_RUN。只放行 claude-sonnet-5（備援模型一律擋下、記失敗）；API 失敗或沒回 usage 時照預留
// 計費並整批停。金鑰讀 ~/.config/anthropic/key。輸出在 out/<tag>/（已 gitignore）。
import {
  estimateCostUsd,
  SONNET_5_PRICING,
} from "../../supabase/functions/_shared/model_pricing.ts";
import { OPTIMIZE_MESSAGE_MAX_TOKENS } from "../../supabase/functions/analyze-chat/optimize_message_prompt.ts";
import type { RefineHarnessModel } from "../../supabase/functions/analyze-chat/guide_v3/refine_harness.ts";

export const CHIPS = ["短一點", "自然一點", "更直接", "更幽默"] as const;
export const MODEL = "claude-sonnet-5";
export const TOKENS_PER_CHAR = 1.5;
export const TYPICAL_OUTPUT_TOKENS = 250;
/// 一次微調最多兩次付費呼叫：主呼叫＋JSON 解析失敗時的那一次。
export const CALLS_PER_REFINE = 2;

const ROOT = new URL("../../", import.meta.url);
const OUT_ROOT = new URL("tools/v3-card-refine-blackbox/out/", ROOT);
const FIXTURES = new URL(
  "supabase/functions/analyze-chat/testdata/guide_v3_replay_fixtures.json",
  ROOT,
);

export interface FixtureCard {
  readonly slot: number;
  readonly task: string;
  readonly method: string;
  readonly voice: string;
  readonly messages: readonly string[];
  readonly hasBlank: boolean;
}

export interface PickedCard {
  readonly caseName: string;
  readonly conversation: readonly { isFromMe: boolean; content: string }[];
  readonly card: FixtureCard;
}

interface FixtureFile {
  readonly cases: readonly {
    name: string;
    messages: { isFromMe: boolean; content: string }[];
    expected: { events: Record<string, unknown>[] };
  }[];
}

/// 固定規則挑卡：全部推進 → 全部有空格 → 第一張收、第一張共鳴 → 第一張照樣寫＋標示。
export function selectCards(
  fixtures: FixtureFile,
  limit = 20,
): PickedCard[] {
  const all: PickedCard[] = fixtures.cases.flatMap((c) =>
    c.expected.events
      .filter((e) => e.type === "analysis.card")
      .map((e) => ({
        caseName: c.name,
        conversation: c.messages,
        card: e as unknown as FixtureCard,
      }))
  );
  const picked = new Map<string, PickedCard>();
  const key = (p: PickedCard) => `${p.caseName}#${p.card.slot}`;
  const take = (pred: (p: PickedCard) => boolean, max = Infinity) => {
    let added = 0;
    for (const p of all) {
      if (picked.size >= limit || added >= max) return;
      if (!picked.has(key(p)) && pred(p)) {
        picked.set(key(p), p);
        added++;
      }
    }
  };
  take((p) => p.card.task === "push");
  take((p) => p.card.hasBlank);
  take((p) => p.card.task === "close", 1);
  take((p) => p.card.task === "resonate", 1);
  take((p) => p.card.method === "invented", 1);
  return [...picked.values()];
}

export interface PlannedRefine {
  readonly id: string;
  readonly picked: PickedCard;
  readonly chip: typeof CHIPS[number];
}

export function planRefines(cards: readonly PickedCard[]): PlannedRefine[] {
  return cards.flatMap((picked) =>
    CHIPS.map((chip) => ({
      id: `${picked.caseName}#${picked.card.slot}|${chip}`,
      picked,
      chip,
    }))
  );
}

/// App 送的 body（PR 的 analysis_auxiliary_client.dart 一樣的欄位）。
export function requestBodyFor(
  refine: PlannedRefine,
  requestId: string,
): Record<string, unknown> {
  const { card, conversation } = refine.picked;
  return {
    messages: conversation,
    userDraft: card.messages.join("\n"),
    refineInstruction: refine.chip,
    guideV3Card: { task: card.task, voice: card.voice, method: card.method },
    requestId,
    billingProtocolVersion: 3,
  };
}

export function splitLines(text: string): string[] {
  return text.split(/\r?\n/).map((m) => m.trim()).filter(Boolean);
}

function blankRuns(message: string): number {
  return message.match(/＿+/g)?.length ?? 0;
}

const PERMISSION_ASK =
  /(可不可以|可以嗎|方不方便|方便嗎|好不好|好嗎|行不行|行嗎|會不會太|願不願意|要不要)/;

/// 最後一則是不是問句結尾（去掉結尾的語氣符號與表情）。
export function endsWithQuestion(message: string): boolean {
  const tail = message.replace(
    /[\s～~。！!…\p{Extended_Pictographic}\u{FE0F}]+$/u,
    "",
  );
  return /[？?]$/.test(tail);
}

/// 推進卡最後一則用徵求同意的問句收尾（v3 規則不允許）。
export function endsWithPermissionAsk(messages: readonly string[]): boolean {
  const last = messages.at(-1) ?? "";
  return endsWithQuestion(last) && PERMISSION_ASK.test(last);
}

export interface RefineChecks {
  readonly countKept: boolean;
  readonly blanksKept: boolean;
  readonly changed: boolean;
  readonly defaultVoiceHasNi: boolean;
  /// 只有推進卡有值。
  readonly push?: {
    readonly permissionAskBefore: boolean;
    readonly permissionAskAfter: boolean;
    readonly questionBefore: boolean;
    readonly questionAfter: boolean;
  };
}

export function inspect(
  card: FixtureCard,
  after: readonly string[],
): RefineChecks {
  const before = card.messages;
  return {
    countKept: after.length === before.length,
    // 跟伺服器 finalizeRefinedCard 同一條：每一則的空格段數都跟原本一樣。
    blanksKept: after.length === before.length &&
      before.every((m, i) => blankRuns(m) === blankRuns(after[i])),
    changed: after.join("\n") !== before.join("\n"),
    defaultVoiceHasNi: card.voice === "default" &&
      after.some((m) => m.includes("妳")),
    ...(card.task === "push"
      ? {
        push: {
          permissionAskBefore: endsWithPermissionAsk(before),
          permissionAskAfter: endsWithPermissionAsk(after),
          questionBefore: endsWithQuestion(before.at(-1) ?? ""),
          questionAfter: endsWithQuestion(after.at(-1) ?? ""),
        },
      }
      : {}),
  };
}

/// 模型請求的提示詞字數（system 區塊＋使用者那一則）。
export function promptChars(body: Record<string, unknown>): number {
  const system = (body.system as { text?: string }[] | undefined ?? [])
    .map((b) => b.text ?? "").join("");
  const user = (body.messages as { content?: unknown }[] | undefined ?? [])
    .map((m) => typeof m.content === "string" ? m.content : "").join("");
  return system.length + user.length;
}

/// 保守計價：input 全用快取寫入單價、output 用 max_tokens 全滿。
export function reservationUsd(
  chars: number,
  tokensPerChar = TOKENS_PER_CHAR,
  maxTokens = OPTIMIZE_MESSAGE_MAX_TOKENS,
): number {
  return (Math.ceil(chars * tokensPerChar) *
      SONNET_5_PRICING.cacheWritePerMTok +
    maxTokens * SONNET_5_PRICING.outputPerMTok) / 1_000_000;
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

export interface PlanEstimate {
  readonly refines: number;
  readonly maxCalls: number;
  readonly typicalUsd: number;
  readonly upperBoundUsd: number;
}

/// 一般：一次呼叫；system 第一次出現寫快取、之後讀快取；使用者那段用一般 input 單價；
/// output 約 250。上限：每次微調兩次呼叫，各自用 reservationUsd。
export function estimatePlan(
  calls: readonly { systemChars: number; userChars: number }[],
  systemKeys: readonly string[],
): PlanEstimate {
  const seen = new Set<string>();
  let typical = 0;
  let upper = 0;
  calls.forEach((call, i) => {
    const systemTokens = Math.ceil(call.systemChars * TOKENS_PER_CHAR);
    const userTokens = Math.ceil(call.userChars * TOKENS_PER_CHAR);
    const firstSystem = !seen.has(systemKeys[i]);
    seen.add(systemKeys[i]);
    typical += estimateCostUsd({
      inputTokens: userTokens,
      outputTokens: TYPICAL_OUTPUT_TOKENS,
      cacheReadInputTokens: firstSystem ? 0 : systemTokens,
      cacheCreationInputTokens: firstSystem ? systemTokens : 0,
    }, SONNET_5_PRICING);
    upper += CALLS_PER_REFINE *
      reservationUsd(call.systemChars + call.userChars);
  });
  return {
    refines: calls.length,
    maxCalls: calls.length * CALLS_PER_REFINE,
    typicalUsd: typical,
    upperBoundUsd: upper,
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
    "verbose",
  ];
  for (const name of [...values.keys(), ...flags]) {
    if (!known.includes(name)) throw new Error(`不認得的參數：--${name}`);
  }
  const tag = values.get("tag") ?? "";
  if (!/^[A-Za-z0-9._-]+$/.test(tag)) {
    throw new Error("--tag 必填，只能用英數、點、底線、連字號");
  }
  const maxCalls = values.has("max-calls")
    ? Number(values.get("max-calls"))
    : null;
  const budgetUsd = values.has("budget-usd")
    ? Number(values.get("budget-usd"))
    : null;
  if (maxCalls !== null && !(Number.isInteger(maxCalls) && maxCalls > 0)) {
    throw new Error("--max-calls 要是正整數");
  }
  if (budgetUsd !== null && !(budgetUsd > 0)) {
    throw new Error("--budget-usd 要是正數");
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

function modelReplyEcho(draft: string): Response {
  return new Response(
    JSON.stringify({
      id: "msg_refine_dry_run",
      type: "message",
      role: "assistant",
      model: MODEL,
      content: [{
        type: "text",
        text: JSON.stringify({
          optimizedMessage: {
            original: draft,
            optimized: draft,
            reason: "dry-run：原句照抄",
          },
        }),
      }],
      stop_reason: "end_turn",
      usage: { input_tokens: 0, output_tokens: 0 },
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
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

interface ProviderCall {
  model: string;
  status: number | "BLOCKED";
  reservationUsd: number;
  actualUsd: number | null;
  usage: Record<string, number> | null;
}

interface RefineRecord {
  id: string;
  caseName: string;
  slot: number;
  task: string;
  method: string;
  voice: string;
  chip: string;
  before: readonly string[];
  status: number | "NOT_RUN_CAP_OR_STOP";
  code: string | null;
  after: string[] | null;
  reason: string | null;
  checks: RefineChecks | null;
  providerCalls: ProviderCall[];
}

function pct(n: number, d: number): string {
  return d === 0 ? "—" : `${n}/${d}（${Math.round((n / d) * 100)}%）`;
}

function summarize(
  records: readonly RefineRecord[],
  spentUsd: number,
  calls: number,
): string {
  const ran = records.filter((r) => r.status !== "NOT_RUN_CAP_OR_STOP");
  const ok = ran.filter((r) => r.status === 200 && r.checks);
  const blocked = new Map<string, number>();
  for (const r of ran) {
    if (r.status !== 200) {
      const key = `${r.status} ${r.code ?? "?"}`;
      blocked.set(key, (blocked.get(key) ?? 0) + 1);
    }
  }
  const push = ok.filter((r) => r.checks!.push);
  const lines = [
    "# 任務卡「再調一下」黑箱結果",
    "",
    `- 規劃 ${records.length} 次微調；實際跑 ${ran.length} 次、沒跑 ${
      records.length - ran.length
    } 次；模型呼叫 ${calls} 次，花費約 US$${spentUsd.toFixed(4)}。`,
    `- 伺服器給結果：${pct(ok.length, ran.length)}`,
    ...[...blocked].map(([k, n]) => `- 擋下或失敗 ${k}：${n} 次`),
    `- 則數不變：${
      pct(ok.filter((r) => r.checks!.countKept).length, ok.length)
    }`,
    `- 空格沒少：${
      pct(ok.filter((r) => r.checks!.blanksKept).length, ok.length)
    }`,
    `- 真的有改：${pct(ok.filter((r) => r.checks!.changed).length, ok.length)}`,
    `- 預設口吻出現「妳」：${
      ok.filter((r) => r.checks!.defaultVoiceHasNi).length
    } 次`,
    `- 推進卡退步成徵求同意的問句（原卡不是）：${
      pct(
        push.filter((r) =>
          r.checks!.push!.permissionAskAfter &&
          !r.checks!.push!.permissionAskBefore
        ).length,
        push.length,
      )
    }`,
    `- 推進卡最後一句新變成問句（原卡不是；參考用）：${
      pct(
        push.filter((r) =>
          r.checks!.push!.questionAfter && !r.checks!.push!.questionBefore
        ).length,
        push.length,
      )
    }`,
    "",
    "## 每顆快捷指令",
    "",
    "| 指令 | 跑 | 給結果 | 真的有改 |",
    "| :-- | --: | --: | --: |",
    ...CHIPS.map((chip) => {
      const rows = ran.filter((r) => r.chip === chip);
      const good = rows.filter((r) => r.status === 200 && r.checks);
      return `| ${chip} | ${rows.length} | ${good.length} | ${
        good.filter((r) => r.checks!.changed).length
      } |`;
    }),
  ];
  for (const task of ["push", "tension"]) {
    lines.push(
      "",
      task === "push"
        ? "## 推進卡前後對照（看有沒有保住往前推、沒變成請求）"
        : "## 帶張力卡前後對照（看繃緊和鬆開是不是都還在）",
      "",
    );
    for (const r of ran.filter((r) => r.task === task)) {
      lines.push(
        `- ${r.id}：${r.before.join(" ／ ")} → ${
          r.after ? r.after.join(" ／ ") : `（${r.status} ${r.code ?? ""}）`
        }`,
      );
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
  const fixtures = JSON.parse(await Deno.readTextFile(FIXTURES)) as FixtureFile;
  const plan = planRefines(selectCards(fixtures));

  let head = "";
  if (options.run) {
    head = await git(["rev-parse", "HEAD"]);
    const dirty = await git(["status", "--porcelain", "--untracked-files=no"]);
    if (dirty) throw new Error("追蹤檔有未提交修改，結果對不回 commit；先提交");
    const home = Deno.env.get("HOME");
    if (!home) throw new Error("讀不到 HOME，找不到金鑰");
    const key = (await Deno.readTextFile(`${home}/.config/anthropic/key`))
      .trim();
    if (!key) throw new Error("~/.config/anthropic/key 是空的");
    // handler 在載入時讀金鑰，所以先設環境變數再載入。
    Deno.env.set("CLAUDE_API_KEY", key);
  }
  const realFetch = globalThis.fetch;
  const { runRefineThroughHandler } = await import(
    "../../supabase/functions/analyze-chat/guide_v3/refine_harness.ts"
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

  const records: RefineRecord[] = [];
  const promptStats: { systemChars: number; userChars: number }[] = [];
  const systemKeys: string[] = [];
  const systemTexts = new Map<string, string>();
  let spentUsd = 0;
  let calls = 0;
  let stopped = false;
  let tokensPerChar = TOKENS_PER_CHAR;

  for (const refine of plan) {
    const card = refine.picked.card;
    const record: RefineRecord = {
      id: refine.id,
      caseName: refine.picked.caseName,
      slot: card.slot,
      task: card.task,
      method: card.method,
      voice: card.voice,
      chip: refine.chip,
      before: card.messages,
      status: "NOT_RUN_CAP_OR_STOP",
      code: null,
      after: null,
      reason: null,
      checks: null,
      providerCalls: [],
    };
    records.push(record);
    if (stopped) continue;
    const body = requestBodyFor(refine, crypto.randomUUID());
    let firstRequestSeen = false;

    const model: RefineHarnessModel = async (request, init) => {
      const system = (request.system as { text: string }[])[0]?.text ?? "";
      const chars = promptChars(request);
      if (!firstRequestSeen) {
        firstRequestSeen = true;
        const systemKey = await sha256(system);
        systemTexts.set(systemKey, system);
        systemKeys.push(systemKey);
        promptStats.push({
          systemChars: system.length,
          userChars: chars - system.length,
        });
      }
      if (!options.run) return modelReplyEcho(String(body.userDraft));
      const reservation = reservationUsd(chars, tokensPerChar);
      if (request.model !== MODEL) {
        record.providerCalls.push({
          model: String(request.model),
          status: "BLOCKED",
          reservationUsd: 0,
          actualUsd: null,
          usage: null,
        });
        return blockedResponse("blackbox: fallback model blocked");
      }
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
      const seq = calls;
      await appendLog({ seq, id: refine.id, phase: "send", reservation });
      const call: ProviderCall = {
        model: MODEL,
        status: 0,
        reservationUsd: reservation,
        actualUsd: null,
        usage: null,
      };
      record.providerCalls.push(call);
      const response = await realFetch(
        "https://api.anthropic.com/v1/messages",
        init,
      );
      call.status = response.status;
      const data = await response.clone().json().catch(() => null);
      const u = data?.usage;
      if (response.ok && u && typeof u.output_tokens === "number") {
        const usage = {
          inputTokens: u.input_tokens ?? 0,
          outputTokens: u.output_tokens ?? 0,
          cacheReadInputTokens: u.cache_read_input_tokens ?? 0,
          cacheCreationInputTokens: u.cache_creation_input_tokens ?? 0,
        };
        call.usage = usage;
        call.actualUsd = estimateCostUsd(usage, SONNET_5_PRICING);
        spentUsd += call.actualUsd - reservation;
        const actualTokens = usage.inputTokens + usage.cacheReadInputTokens +
          usage.cacheCreationInputTokens;
        tokensPerChar = Math.max(tokensPerChar, actualTokens / chars);
      } else {
        // 失敗或沒回 usage：照預留算，整批停（不當免費）。
        stopped = true;
      }
      await appendLog({
        seq,
        id: refine.id,
        phase: "done",
        status: response.status,
        actualUsd: call.actualUsd,
      });
      return response;
    };

    const restore = quiet();
    let outcome;
    try {
      outcome = await runRefineThroughHandler(body, model);
    } finally {
      restore();
    }
    record.status = outcome.status;
    if (outcome.status === 200) {
      const message = outcome.json.optimizedMessage as Record<string, unknown>;
      record.after = splitLines(String(message.optimized ?? ""));
      record.reason = typeof message.reason === "string"
        ? message.reason
        : null;
      record.checks = inspect(card, record.after);
    } else {
      record.code = typeof outcome.json.code === "string"
        ? outcome.json.code
        : null;
    }
    if (options.run) {
      await Deno.writeTextFile(
        new URL("records.json", outDir),
        JSON.stringify(records, null, 2),
      );
      print(
        `${refine.id} → ${record.status}${
          record.code ? ` ${record.code}` : ""
        }（已花 US$${spentUsd.toFixed(4)}）`,
      );
    }
  }

  const estimate = estimatePlan(promptStats, systemKeys);
  const manifest = {
    tag: options.tag,
    mode: options.run ? "paid" : "dry-run",
    head: options.run ? head : null,
    model: MODEL,
    maxTokens: OPTIMIZE_MESSAGE_MAX_TOKENS,
    chips: CHIPS,
    cards: selectCards(fixtures).map((p) =>
      `${p.caseName}#${p.card.slot} ${p.card.task}/${p.card.method}/${p.card.voice}`
    ),
    fixturesSha256: await sha256(await Deno.readTextFile(FIXTURES)),
    systemPromptSha256: [...systemTexts.keys()],
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

  if (!options.run) {
    await Deno.writeTextFile(
      new URL("plan.json", outDir),
      JSON.stringify(
        plan.map((p) => ({ id: p.id, before: p.picked.card.messages })),
        null,
        2,
      ),
    );
    // dry-run 的假模型照抄原句：每一次都應該拿到 200、則數與空格不變。
    const notOk = records.filter((r) =>
      r.status !== 200 || !r.checks?.countKept || !r.checks?.blanksKept
    );
    const budget = Math.ceil(estimate.upperBoundUsd * 2) / 2;
    print(
      [
        `dry-run：${estimate.refines} 次微調（${
          selectCards(fixtures).length
        } 張卡 × ${CHIPS.length} 顆指令），最多 ${estimate.maxCalls} 次模型呼叫。`,
        `走完整條路徑：${
          records.length - notOk.length
        }/${records.length} 次拿到 200 且則數、空格不變${
          notOk.length ? `；異常：${notOk.map((r) => r.id).join("、")}` : ""
        }。`,
        `估價：一般約 US$${estimate.typicalUsd.toFixed(2)}；上限 US$${
          estimate.upperBoundUsd.toFixed(2)
        }（input 全用快取寫入價、output ${OPTIMIZE_MESSAGE_MAX_TOKENS} 全滿、每次微調兩次呼叫）。`,
        "真跑（要 Eric 當次說「跑」）：",
        `deno run --no-prompt --allow-read --allow-env --allow-run=git --allow-write=tools/v3-card-refine-blackbox/out --allow-net=api.anthropic.com tools/v3-card-refine-blackbox/run.ts --tag=<新 tag> --run --confirm-paid --max-calls=${estimate.maxCalls} --budget-usd=${budget}`,
      ].join("\n"),
    );
    if (notOk.length) Deno.exitCode = 1;
    return;
  }

  await Deno.writeTextFile(
    new URL("summary.md", outDir),
    summarize(records, spentUsd, calls),
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

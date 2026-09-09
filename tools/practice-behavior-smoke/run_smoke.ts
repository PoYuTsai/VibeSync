// 練習室 NPC 行為評測（pre-release 手動跑，刻意不進 CI——需要網路與
// DEEPSEEK_API_KEY，混進 CI 會連紅；坑已登記）。
//
// 跑法（repo 根目錄，預設行為＝原本行為，不帶旗標時逐位元組不變）：
//   deno run --allow-read --allow-net tools/practice-behavior-smoke/run_smoke.ts
//
// 用 production 同款 CHAT_SYSTEM_PROMPT＋deepseek-v4-flash 生 NPC 回覆，
// 先過 bannedPatterns（確定性），再交 LLM 評審（temperature 0）判語意。
// 任何 FAIL → exit 1。NPC 生成溫度 0.7（貼近線上），單發有隨機性：
// FAIL 先重看回覆內容再判是回歸還是抖動。
//
// 2026-09-10 model-compare：加 --model=claude|deepseek|both、--repeat=N、
// --concurrency=N、--cases=id1,id2 四個旗標，跑多發抽樣比對兩條生成模型
// 路線（judge 仍固定 DeepSeek temperature 0，只有生成模型變）。四個旗標都不
// 帶＝走原本那條 legacy 迴圈，行為與輸出格式完全不變。
// claude 臂讀 production 實際在打的 chat-reply 路徑（`chatModelFor` 的
// mixed routing）：CLAUDE_HAIKU_MODEL，不是 claude.ts 檔頭註解暗示的
// sonnet／「只用於 hint/debrief failover」——那句註解在 Phase 4.4 mixed
// routing 上線後已經過時，實際 caller 是 handler.ts 的 chat 生成 `useHaiku`
// 分支（見 handler.ts:5039）。maxTokens／temperature／timeoutMs 三個參數
// 抄自 handler.ts 的 CHAT_MAX_TOKENS／CHAT_TEMPERATURE／DEEPSEEK_TIMEOUT_MS
// （handler.ts 沒 export，這裡是私有常數的鏡像，production 改了要跟著改）。

import {
  buildChatPromptBundle,
  CHAT_SYSTEM_PROMPT,
  type ChatMessage,
} from "../../supabase/functions/practice-chat/prompt.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  callClaude,
  CLAUDE_HAIKU_MODEL,
} from "../../supabase/functions/practice-chat/claude.ts";
import { SMOKE_CASES, type SmokeCase } from "./cases.ts";

// handler.ts 私有常數鏡像（見檔頭說明）。
const PROD_CHAT_MAX_TOKENS = 200;
const PROD_CHAT_TEMPERATURE = 0.9;
const PROD_CLAUDE_TIMEOUT_MS = 30000;

// 2026-09-09：逐人資料類規則（photoScene）在不帶角色的 CHAT_SYSTEM_PROMPT 上
// 根本測不到，所以案例可選帶 profileId → 用 production 同一條
// buildChatPromptBundle 組完整 system prompt（profile 區塊＋鐵則＋錨定），
// 也順便拿到 systemStable（Claude cache 前綴）。沒帶的案例沿用舊行為。
function turnsForCase(c: SmokeCase): { role: "user" | "ai"; text: string }[] {
  return [...(c.priorTurns ?? []), { role: "user", text: c.userText }];
}

function messagesForCase(
  c: SmokeCase,
): { messages: ChatMessage[]; systemStable: string } {
  const turns = turnsForCase(c);
  if (!c.profileId) {
    const messages: ChatMessage[] = [
      { role: "system", content: CHAT_SYSTEM_PROMPT },
      ...turns.map((t) => ({
        role: t.role === "user" ? "user" as const : "assistant" as const,
        content: t.text,
      })),
    ];
    return { messages, systemStable: CHAT_SYSTEM_PROMPT };
  }
  const profile = resolvePracticeProfile({
    profileId: c.profileId,
    difficulty: c.difficulty ?? "normal",
  });
  const bundle = buildChatPromptBundle(
    turns.map((t) => ({ role: t.role, text: t.text })),
    profile,
    { practiceMode: "standard" },
  );
  return { messages: bundle.messages, systemStable: bundle.systemStable };
}

const envText = await Deno.readTextFile(
  new URL("../../supabase/.env", import.meta.url),
);
const deepseekKey = envText.match(/DEEPSEEK_API_KEY=("?)([^"\n]+)\1/)?.[2];
if (!deepseekKey) {
  console.error("DEEPSEEK_API_KEY not found in supabase/.env");
  Deno.exit(2);
}

async function callDeepSeek(opts: {
  messages: ChatMessage[];
  jsonMode?: boolean;
  temperature: number;
}): Promise<string> {
  const res = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${deepseekKey}`,
    },
    body: JSON.stringify({
      model: "deepseek-v4-flash",
      messages: opts.messages.map((m) => ({
        role: m.role,
        content: m.content,
      })),
      max_tokens: 300,
      temperature: opts.temperature,
      stream: false,
      thinking: { type: "disabled" },
      ...(opts.jsonMode ? { response_format: { type: "json_object" } } : {}),
    }),
  });
  const json = await res.json();
  const content = json.choices?.[0]?.message?.content;
  if (typeof content !== "string" || content.length === 0) {
    throw new Error(`deepseek empty reply: ${JSON.stringify(json).slice(0, 200)}`);
  }
  return content;
}

function readClaudeKey(): string {
  const home = Deno.env.get("HOME");
  if (!home) throw new Error("HOME not set, can't find ~/.config/anthropic/key");
  const raw = Deno.readTextFileSync(`${home}/.config/anthropic/key`).trim();
  if (!raw) throw new Error("~/.config/anthropic/key is empty");
  return raw;
}

async function callClaudeGen(
  built: { messages: ChatMessage[]; systemStable: string },
  claudeKey: string,
): Promise<string> {
  return await callClaude({
    apiKey: claudeKey,
    model: CLAUDE_HAIKU_MODEL,
    messages: built.messages,
    maxTokens: PROD_CHAT_MAX_TOKENS,
    temperature: PROD_CHAT_TEMPERATURE,
    timeoutMs: PROD_CLAUDE_TIMEOUT_MS,
    systemCachePrefix: built.systemStable,
  });
}

const JUDGE_SYSTEM =
  "你是行為評測員。給你一句使用者訊息、模擬女生的回覆、與判準。" +
  '嚴格依判準判定，只輸出 JSON：{"pass":true|false,"reason":"20字內"}';

async function judge(
  c: SmokeCase,
  reply: string,
): Promise<{ pass: boolean; reason: string }> {
  const verdictRaw = await callDeepSeek({
    messages: [
      { role: "system", content: JUDGE_SYSTEM },
      {
        role: "user",
        content:
          `使用者訊息：${c.userText}\n她的回覆：${reply}\n判準：${c.criterion}`,
      },
    ],
    jsonMode: true,
    temperature: 0,
  });
  let verdict: { pass?: boolean; reason?: string };
  try {
    verdict = JSON.parse(verdictRaw);
  } catch {
    return { pass: false, reason: `judge unparsable: ${verdictRaw.slice(0, 100)}` };
  }
  return { pass: verdict.pass === true, reason: verdict.reason ?? "no reason" };
}

function bannedHit(c: SmokeCase, reply: string): RegExp | undefined {
  return (c.bannedPatterns ?? []).find((p) => p.test(reply));
}

// ── CLI 旗標解析 ──────────────────────────────────────────────────────
function parseArgs(args: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const a of args) {
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
  }
  return out;
}
const argv = parseArgs(Deno.args);
const legacyMode = !("model" in argv) && !("repeat" in argv) &&
  !("cases" in argv) && !("concurrency" in argv);

if (legacyMode) {
  // ── 原本的行為，一字不動：單發、DeepSeek、全部案例、依序跑 ──
  let failures = 0;
  for (const c of SMOKE_CASES) {
    const reply = await callDeepSeek({
      messages: messagesForCase(c).messages,
      temperature: 0.7,
    });
    const flat = reply.replaceAll("\n", " ⏎ ");

    const banned = bannedHit(c, reply);
    if (banned) {
      failures++;
      console.log(`FAIL ${c.id} [banned ${banned}]\n  她回：${flat}`);
      continue;
    }

    const verdict = await judge(c, reply);
    if (verdict.pass) {
      console.log(`pass ${c.id}\n  她回：${flat}`);
    } else {
      failures++;
      console.log(`FAIL ${c.id} [${verdict.reason}]\n  她回：${flat}`);
    }
  }

  console.log(`\n${SMOKE_CASES.length - failures}/${SMOKE_CASES.length} passed`);
  Deno.exit(failures > 0 ? 1 : 0);
}

// ── model-compare 模式：--model / --repeat / --cases / --concurrency ──
type Arm = "claude" | "deepseek";
const modelArg = argv.model ?? "deepseek";
const arms: Arm[] = modelArg === "both"
  ? ["deepseek", "claude"]
  : [modelArg as Arm];
if (!arms.every((a) => a === "claude" || a === "deepseek")) {
  console.error(`--model must be claude|deepseek|both, got: ${modelArg}`);
  Deno.exit(2);
}
const repeat = argv.repeat ? parseInt(argv.repeat, 10) : 1;
const concurrency = argv.concurrency ? parseInt(argv.concurrency, 10) : 4;
const caseIds = argv.cases ? argv.cases.split(",").map((s) => s.trim()) : null;
const selectedCases = caseIds
  ? SMOKE_CASES.filter((c) => caseIds.includes(c.id))
  : SMOKE_CASES;
if (caseIds && selectedCases.length !== caseIds.length) {
  const found = new Set(selectedCases.map((c) => c.id));
  const missing = caseIds.filter((id) => !found.has(id));
  console.error(`--cases 有找不到的 id: ${missing.join(", ")}`);
  Deno.exit(2);
}

const claudeKey = arms.includes("claude") ? readClaudeKey() : null;

interface RunResult {
  ok: boolean;
  reply: string;
  reason: string;
  error?: string;
}

async function runOnce(c: SmokeCase, arm: Arm): Promise<RunResult> {
  const built = messagesForCase(c);
  const generate = () =>
    arm === "claude"
      ? callClaudeGen(built, claudeKey!)
      : callDeepSeek({ messages: built.messages, temperature: 0.7 });

  let reply: string;
  try {
    reply = await generate();
  } catch (e1) {
    // 最多重試一次（任務要求：不要用重試迴圈吃掉暫時性錯誤）。
    try {
      reply = await generate();
    } catch (e2) {
      const msg = e2 instanceof Error ? e2.message : String(e2);
      return { ok: false, reply: "", reason: `generation error: ${msg}`, error: msg };
    }
  }

  const banned = bannedHit(c, reply);
  if (banned) {
    return { ok: false, reply, reason: `banned pattern: ${banned}` };
  }
  try {
    const verdict = await judge(c, reply);
    return { ok: verdict.pass, reply, reason: verdict.reason };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return { ok: false, reply, reason: `judge error: ${msg}`, error: msg };
  }
}

interface CaseArmStats {
  pass: number;
  total: number;
  fails: { reply: string; reason: string }[];
  log: string[];
}

const stats = new Map<string, Map<Arm, CaseArmStats>>();
for (const c of selectedCases) {
  const m = new Map<Arm, CaseArmStats>();
  for (const arm of arms) m.set(arm, { pass: 0, total: 0, fails: [], log: [] });
  stats.set(c.id, m);
}

interface Task {
  c: SmokeCase;
  arm: Arm;
  i: number;
}
const tasks: Task[] = [];
for (const c of selectedCases) {
  for (const arm of arms) {
    for (let i = 1; i <= repeat; i++) tasks.push({ c, arm, i });
  }
}

let completed = 0;
async function runTask(t: Task) {
  const r = await runOnce(t.c, t.arm);
  const s = stats.get(t.c.id)!.get(t.arm)!;
  s.total++;
  if (r.ok) s.pass++;
  else s.fails.push({ reply: r.reply, reason: r.reason });
  const flat = r.reply.replaceAll("\n", " ⏎ ");
  s.log.push(
    `${r.ok ? "pass" : "FAIL"} ${t.c.id} [${t.arm}] #${t.i} [${r.reason}]\n  她回：${flat}`,
  );
  completed++;
  console.log(
    `[${completed}/${tasks.length}] ${t.c.id} ${t.arm} #${t.i}: ${
      r.ok ? "pass" : "FAIL"
    }`,
  );
}

async function runPool(items: Task[], limit: number) {
  let idx = 0;
  async function worker(): Promise<void> {
    while (idx < items.length) {
      const my = idx++;
      await runTask(items[my]);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, () => worker()),
  );
}

const startedAt = Date.now();
await runPool(tasks, concurrency);
const elapsedSec = ((Date.now() - startedAt) / 1000).toFixed(1);

// ── 結果表 ──────────────────────────────────────────────────────
const lines: string[] = [];
lines.push(`# practice-behavior-smoke model-compare`);
lines.push("");
lines.push(
  `跑於 ${
    new Date().toISOString()
  }，耗時 ${elapsedSec}s，臂＝${arms.join("/")}，repeat=${repeat}，concurrency=${concurrency}`,
);
lines.push("");
lines.push(`| case | ${arms.map((a) => `${a} pass/N`).join(" | ")} |`);
lines.push(`| --- | ${arms.map(() => "---").join(" | ")} |`);
for (const c of selectedCases) {
  const row = arms.map((arm) => {
    const s = stats.get(c.id)!.get(arm)!;
    return `${s.pass}/${s.total}`;
  });
  lines.push(`| ${c.id} | ${row.join(" | ")} |`);
}
lines.push("");

for (const c of selectedCases) {
  for (const arm of arms) {
    const s = stats.get(c.id)!.get(arm)!;
    if (s.fails.length === 0) continue;
    lines.push(`## FAIL 範例：${c.id} [${arm}]（${s.pass}/${s.total} pass）`);
    for (const f of s.fails.slice(0, 2)) {
      lines.push("");
      lines.push("```");
      lines.push(`她回：${f.reply}`);
      lines.push(`理由：${f.reason}`);
      lines.push("```");
    }
    lines.push("");
  }
}

lines.push("## 原始逐發 log");
lines.push("");
lines.push("```");
for (const c of selectedCases) {
  for (const arm of arms) {
    for (const l of stats.get(c.id)!.get(arm)!.log) lines.push(l);
  }
}
lines.push("```");

const report = lines.join("\n");
console.log("\n" + report);

const resultsDir = new URL("./results/", import.meta.url);
await Deno.mkdir(resultsDir, { recursive: true });
const ts = new Date().toISOString().replace(/[:.]/g, "-");
const outPath = new URL(`./${ts}-model-compare.md`, resultsDir);
await Deno.writeTextFile(outPath, report);
console.log(`\n寫入 ${outPath.pathname}`);

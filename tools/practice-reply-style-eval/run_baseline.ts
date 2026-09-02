// 練習室寫實差異化（reply-style-v1）PR-0：跨角色同質化黑箱 baseline。
//
// 目的：同一批固定情境（scenarios.ts）餵給同 persona 的多位女孩，量「人物卡不同、
// 說話骨架卻一樣」到底有多嚴重。difficulty bakeoff 固定一位角色排除人設差異，
// 所以量不到這件事；這支工具反過來固定情境、換角色。
//
// 保真：prompt 走 production 的 buildChatPromptBundle（含 bakeoff 同一份固定 context
// fixture），模型走 production 的 callDeepSeek（deepseek-v4-flash、200 tokens、0.9），
// 回覆後處理照 handler.ts 同序（繁體轉換→內部標籤守門→L4 守門，失敗重試一次）。
// 不自造 prompt。standard 模式（production 不跑分類器、partnerState 為 null）。
//
// 每一輪都是一次真實 DeepSeek 呼叫（Eric 2026-09-02：DeepSeek 隨意調用）。
//
// 跑法：
//   deno run --allow-env --allow-read --allow-write --allow-run=git \
//     --allow-net=api.deepseek.com tools/practice-reply-style-eval/run_baseline.ts \
//     tools/practice-reply-style-eval/out/<date>-<label>.json \
//     [--profiles=a,b] [--scenarios=a,b] [--repeat=2] [--difficulty=normal] [--concurrency=4]

import {
  isPracticeDifficulty,
  type PracticeDifficulty,
  resolvePracticeProfile,
} from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  buildChatPromptBundle,
  PRACTICE_PROMPT_POLICY_VERSION,
} from "../../supabase/functions/practice-chat/prompt.ts";
import {
  nextReplyStyleState,
  type ReplyStyleState,
} from "../../supabase/functions/practice-chat/reply_style_state.ts";
import {
  callDeepSeek,
  DEEPSEEK_MODEL,
} from "../../supabase/functions/practice-chat/deepseek.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import { normalizeLiteralNewlines } from "../../supabase/functions/practice-chat/prompt_sanitizer.ts";
import {
  hasStageDirection,
  rejectL4UnsafeVisibleText,
  rejectVisibleInternalLabelLeak,
  REPLY_STYLE_HIDDEN_HEADINGS,
  stripStageDirections,
} from "../../supabase/functions/practice-chat/visible_text_guard.ts";
import { toTraditionalChinese } from "../../supabase/functions/_shared/traditional_chinese.ts";
import {
  BAKEOFF_FIXED_NOW,
  BAKEOFF_THREAD_ID,
  buildBakeoffContextFixture,
} from "../practice-difficulty-bakeoff/bakeoff.ts";
import {
  isScenarioId,
  renderUserTurn,
  type Scenario,
  type ScenarioFamily,
  SCENARIOS,
} from "./scenarios.ts";

// 照 handler.ts 現用值抄錄（handler 未 export；改 handler 記得同步）。
const CHAT_MAX_TOKENS = 200;
const CHAT_TEMPERATURE = 0.9;
const CHAT_GENERATION_ATTEMPTS = 2;
const MODEL_TIMEOUT_MS = 30000;

// 規格 §4.3：20 位代表角色，五個 persona 各 4 位、稀有度混搭；preset 與 persona 正交。
export const DEFAULT_PROFILE_IDS = [
  // slow_worker
  "practice_girl_001",
  "practice_girl_008",
  "practice_girl_064",
  "practice_girl_077",
  // playful_extrovert
  "practice_girl_007",
  "practice_girl_011",
  "practice_girl_002",
  "practice_girl_083",
  // cool_rational
  "practice_girl_009",
  "practice_girl_012",
  "practice_girl_020",
  "practice_girl_084",
  // teasing_humor
  "practice_girl_004",
  "practice_girl_013",
  "practice_girl_061",
  "practice_girl_089",
  // clear_boundaries
  "practice_girl_006",
  "practice_girl_018",
  "practice_girl_003",
  "practice_girl_091",
] as const;

export interface TurnResult {
  readonly roundIndex: number;
  readonly userText: string;
  readonly reply: string;
  readonly bubbles: readonly string[];
  readonly promptChars: number;
  readonly systemSha256: string;
  readonly elapsedMs: number;
  readonly attempts: number;
  readonly guardRejections: readonly string[];
  readonly stageDirectionRepairs: number;
}

export interface SessionResult {
  readonly profileId: string;
  readonly personaId: string;
  readonly rarity: string;
  readonly scenarioId: ScenarioFamily;
  readonly repeat: number;
  readonly difficulty: PracticeDifficulty;
  readonly sceneId: string;
  readonly replyTempo: string;
  readonly turns: readonly TurnResult[];
  readonly probe: TurnResult | null;
  readonly error?: string;
}

// 鏡像 Flutter practice_chat_screen.dart 的 _splitBubbles（>4 段視為一則）。
export function splitBubbles(text: string): string[] {
  const parts = text.split("\n").map((p) => p.trim()).filter((p) =>
    p.length > 0
  );
  if (parts.length <= 1 || parts.length > 4) return [text.trim()];
  return parts;
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export type ChatCaller = (
  messages: { role: string; content: string }[],
) => Promise<string>;

export async function runScenario(args: {
  callChat: ChatCaller;
  profileId: string;
  scenario: Scenario;
  repeat: number;
  difficulty: PracticeDifficulty;
  style?: boolean;
}): Promise<SessionResult> {
  const profile = resolvePracticeProfile({
    difficulty: args.difficulty,
    profileId: args.profileId,
  });
  const fixture = buildBakeoffContextFixture(profile);
  const chatContext = {
    sceneContext: fixture.sceneContext,
    acquaintanceOrigin: fixture.acquaintanceOrigin,
    memorySummary: fixture.memorySummary,
    timeContext: fixture.timeContext,
    herRecentMomentsBlock: fixture.herRecentMomentsBlock,
  };
  const interest = profile.girl.interestTags[0] ?? "咖啡";
  const turns: PracticeTurn[] = [];
  const results: TurnResult[] = [];
  let styleState: ReplyStyleState | null = null;
  const base = {
    profileId: args.profileId,
    personaId: profile.personaId,
    rarity: profile.girl.rarity,
    scenarioId: args.scenario.id,
    repeat: args.repeat,
    difficulty: args.difficulty,
    sceneId: fixture.sceneContext.id,
    replyTempo: fixture.sceneContext.replyTempo,
  };

  for (let i = 0; i < args.scenario.userTurns.length; i++) {
    const userText = renderUserTurn(args.scenario.userTurns[i], interest);
    turns.push({ role: "user", text: userText });
    // handler.ts:4223-4229 standard 分支：不帶 practiceMode／分數，partnerState null。
    // 同一情境多輪之間帶 reply-style 狀態（模擬 assisted 模式的 thread recent_facts
    // 持久化：拒絕記憶、act 輪替）；旗標關時 bundle 不讀它。
    const bundle = buildChatPromptBundle(turns, profile, {
      partnerState: null,
      replyStyle: args.style ?? false,
      styleState,
      visiblePracticeThreadId: BAKEOFF_THREAD_ID,
      ...chatContext,
    });
    const messages = bundle.messages;
    if (bundle.responsePlan) {
      styleState = nextReplyStyleState(styleState, bundle.responsePlan);
    }
    const promptChars = messages.reduce((sum, m) => sum + m.content.length, 0);
    const systemSha256 = await sha256Hex(messages[0].content);

    const startedAt = Date.now();
    let reply: string | null = null;
    let attempts = 0;
    let stageDirectionRepairs = 0;
    const guardRejections: string[] = [];
    let lastError: unknown;
    for (let attempt = 1; attempt <= CHAT_GENERATION_ATTEMPTS; attempt++) {
      attempts = attempt;
      try {
        let candidate = await args.callChat(messages);
        // handler.ts:4237-4256 同序後處理。
        candidate = toTraditionalChinese(normalizeLiteralNewlines(candidate));
        rejectVisibleInternalLabelLeak(candidate, "chat_internal_label_leak", {
          transcript: turns.map((t) => t.text).join("\n"),
          // 只有 style 層真的注入時才多攔兩個 heading（旗標關閉零改動）。
          ...(args.style
            ? { extraChineseLabels: REPLY_STYLE_HIDDEN_HEADINGS }
            : {}),
        });
        rejectL4UnsafeVisibleText(candidate, "chat_l4_unsafe", {
          fieldClass: "strict",
          spicyAllowed: false,
        });
        // 括號旁白：修補優先（剝掉開頭括號），整段空才重試；記次數。
        // handler.ts chat 迴圈同序（PR-2 已接）。
        if (args.style && hasStageDirection(candidate)) {
          stageDirectionRepairs++;
          candidate = stripStageDirections(candidate, "chat_stage_direction");
        }
        reply = candidate;
        break;
      } catch (e) {
        lastError = e;
        const message = e instanceof Error ? e.message : String(e);
        if (message.startsWith("chat_")) guardRejections.push(message);
        console.error(
          `[reply-style] ${args.profileId}/${args.scenario.id}#${args.repeat} round${
            i + 1
          } 第 ${attempt} 次失敗：${message}`,
        );
      }
    }
    if (reply === null) {
      return {
        ...base,
        turns: results,
        probe: null,
        error: lastError instanceof Error
          ? lastError.message
          : String(lastError),
      };
    }
    const record: TurnResult = {
      roundIndex: i + 1,
      userText,
      reply,
      bubbles: splitBubbles(reply),
      promptChars,
      systemSha256,
      elapsedMs: Date.now() - startedAt,
      attempts,
      guardRejections,
      stageDirectionRepairs,
    };
    results.push(record);
    turns.push({ role: "ai", text: reply });
  }
  return {
    ...base,
    turns: results,
    probe: results[results.length - 1] ?? null,
  };
}

// ── CLI ───────────────────────────────────────────────────────────────────
interface CliOptions {
  outPath: string;
  profileIds: string[];
  scenarios: Scenario[];
  repeat: number;
  difficulty: PracticeDifficulty;
  concurrency: number;
  /** reply-style-v1 對照組：傳 buildChatPromptBundle 的 replyStyle 旗標。 */
  style: boolean;
}

export function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = {
    outPath: new URL("./out/latest.json", import.meta.url).pathname,
    profileIds: [...DEFAULT_PROFILE_IDS],
    scenarios: [...SCENARIOS],
    repeat: 2,
    difficulty: "normal",
    concurrency: 4,
    style: false,
  };
  for (const arg of argv) {
    if (!arg.startsWith("--")) {
      opts.outPath = arg;
      continue;
    }
    const eq = arg.indexOf("=");
    if (eq < 0) {
      throw new Error(
        `reply_style_invalid_cli_arg: "${arg}"（格式 --key=value）`,
      );
    }
    const key = arg.slice(2, eq);
    const value = arg.slice(eq + 1);
    switch (key) {
      case "profiles":
        opts.profileIds = value.split(",").map((s) => s.trim()).filter(Boolean);
        break;
      case "scenarios": {
        const ids = value.split(",").map((s) => s.trim()).filter(Boolean);
        for (const id of ids) {
          if (!isScenarioId(id)) {
            throw new Error(`reply_style_invalid_scenario: "${id}"`);
          }
        }
        opts.scenarios = SCENARIOS.filter((s) => ids.includes(s.id));
        break;
      }
      case "repeat": {
        const n = Number.parseInt(value, 10);
        if (!Number.isInteger(n) || n < 1) {
          throw new Error(`reply_style_invalid_repeat: "${value}"`);
        }
        opts.repeat = n;
        break;
      }
      case "concurrency": {
        const n = Number.parseInt(value, 10);
        if (!Number.isInteger(n) || n < 1) {
          throw new Error(`reply_style_invalid_concurrency: "${value}"`);
        }
        opts.concurrency = n;
        break;
      }
      case "style":
        opts.style = value === "1" || value === "true";
        break;
      case "difficulty":
        if (!isPracticeDifficulty(value)) {
          throw new Error(`reply_style_invalid_difficulty: "${value}"`);
        }
        opts.difficulty = value;
        break;
      default:
        throw new Error(
          `reply_style_unknown_cli_flag: "--${key}"（支援：--profiles、--scenarios、--repeat、--difficulty、--concurrency、--style）`,
        );
    }
  }
  return opts;
}

export async function readDeepSeekKey(): Promise<string> {
  const fromEnv = Deno.env.get("DEEPSEEK_API_KEY");
  if (fromEnv) return fromEnv;
  // 同 practice-behavior-smoke：退回 supabase/.env（repo 內、已 gitignore）。
  const envPath = new URL("../../supabase/.env", import.meta.url).pathname;
  const text = await Deno.readTextFile(envPath).catch(() => "");
  const match = text.match(/DEEPSEEK_API_KEY=("?)([^"\n]+)\1/);
  if (!match) {
    throw new Error(
      "reply_style_missing_key: DEEPSEEK_API_KEY 不在 env 也不在 supabase/.env",
    );
  }
  return match[2];
}

async function git(args: string[]): Promise<string> {
  try {
    const out = await new Deno.Command("git", {
      args,
      cwd: new URL("../../", import.meta.url).pathname,
      stdout: "piped",
      stderr: "null",
    }).output();
    return new TextDecoder().decode(out.stdout).trim();
  } catch {
    return "unknown";
  }
}

async function main(): Promise<void> {
  const opts = parseArgs(Deno.args);
  const apiKey = await readDeepSeekKey();
  const callChat: ChatCaller = (messages) =>
    callDeepSeek({
      apiKey,
      messages: messages as {
        role: "system" | "user" | "assistant";
        content: string;
      }[],
      maxTokens: CHAT_MAX_TOKENS,
      temperature: CHAT_TEMPERATURE,
      timeoutMs: MODEL_TIMEOUT_MS,
    });

  const jobs: { profileId: string; scenario: Scenario; repeat: number }[] = [];
  for (const profileId of opts.profileIds) {
    for (const scenario of opts.scenarios) {
      for (let repeat = 1; repeat <= opts.repeat; repeat++) {
        jobs.push({ profileId, scenario, repeat });
      }
    }
  }
  const results: SessionResult[] = new Array(jobs.length);
  let next = 0;
  const startedAt = Date.now();
  const worker = async () => {
    while (next < jobs.length) {
      const index = next++;
      const job = jobs[index];
      results[index] = await runScenario({
        callChat,
        profileId: job.profileId,
        scenario: job.scenario,
        repeat: job.repeat,
        difficulty: opts.difficulty,
        style: opts.style,
      });
      console.error(
        `[reply-style] ${
          index + 1
        }/${jobs.length} ${job.profileId}/${job.scenario.id}#${job.repeat}` +
          (results[index].error ? ` 失敗：${results[index].error}` : ""),
      );
    }
  };
  await Promise.all(Array.from({ length: opts.concurrency }, worker));

  const artifact = {
    meta: {
      tool: "practice-reply-style-eval/run_baseline",
      commit: await git(["rev-parse", "HEAD"]),
      tree: await git(["rev-parse", "HEAD^{tree}"]),
      worktreeDirty: (await git(["status", "--porcelain"])) !== "",
      promptPolicyVersion: PRACTICE_PROMPT_POLICY_VERSION,
      model: DEEPSEEK_MODEL,
      chat: {
        maxTokens: CHAT_MAX_TOKENS,
        temperature: CHAT_TEMPERATURE,
        attempts: CHAT_GENERATION_ATTEMPTS,
      },
      practiceMode: "standard",
      replyStyle: opts.style,
      difficulty: opts.difficulty,
      fixture: {
        now: BAKEOFF_FIXED_NOW.toISOString(),
        threadId: BAKEOFF_THREAD_ID,
      },
      profileIds: opts.profileIds,
      scenarioIds: opts.scenarios.map((s) => s.id),
      repeat: opts.repeat,
      generatedAt: new Date().toISOString(),
      elapsedMs: Date.now() - startedAt,
      args: Deno.args,
    },
    results,
  };
  const outDir = opts.outPath.includes("/")
    ? opts.outPath.slice(0, opts.outPath.lastIndexOf("/"))
    : ".";
  await Deno.mkdir(outDir, { recursive: true });
  await Deno.writeTextFile(
    opts.outPath,
    JSON.stringify(artifact, null, 2) + "\n",
  );
  const failed = results.filter((r) => r.error).length;
  console.error(
    `[reply-style] 完成 ${results.length} 場（失敗 ${failed}），寫入 ${opts.outPath}`,
  );
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(
      `[reply-style] 致命錯誤：${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    Deno.exit(1);
  });
}

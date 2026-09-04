// 練習室對話主體意識（conversation-agency-v1）Phase 0：黑箱 baseline runner。
//
// 目的：量「她會不會被最新一個名詞牽著走」。固定多輪情境（scenarios.ts，報告
// §10.1 A01–A15 ＋ 兩段真機截圖逐字稿），每個 user turn 走一次 production 生成，
// 只有標了 probe 的那幾輪送進 judge。
//
// 保真：prompt 走 production 的 buildChatPromptBundle（含 difficulty bakeoff 那份
// 固定 context fixture），模型走 production 的 callDeepSeek（deepseek-v4-flash、
// 200 tokens、0.9），回覆後處理照 handler.ts 同序（繁體→內部標籤守門→L4 守門→
// style 開時剝括號旁白）。不自造 prompt。
//
// `--mode=beginner|game` 走 handler.ts 的 assisted 分支（帶 practiceMode＋
// 分數），standard 走另一支（不帶 practiceMode key、partnerState null），與
// production 一致。`--mode=game` 需要 SR 角色（--profiles 指定 rarity==="sr"
// 的 profileId，例如 practice_girl_004；見 practice_persona.ts）。
//
// `--state=1`：assisted 模式跨輪真的帶 agency state（像 handler 一樣用
// nextConversationAgencyState 推下一輪的 agencyState），而不是每輪都傳
// null；這是結構層模擬，不是真的每輪多打一次 classifier 拿 coherence（見
// runAgencyScenario 的 stateSimulation 註解與 README）。artifact meta 記
// `stateSimulation: true`。
//
// 每一輪都是一次真實 DeepSeek 呼叫（Eric 2026-09-02：DeepSeek 隨意調用）。
//
// 跑法：
//   deno run --allow-env --allow-read --allow-write --allow-run=git \
//     --allow-net=api.deepseek.com tools/practice-agency-eval/run_agency.ts \
//     tools/practice-agency-eval/out/<date>-<label>.json \
//     [--profiles=a,b] [--scenarios=A01,A02] [--mode=standard|beginner|game] \
//     [--style=1] [--agency=on] [--repeat=3] [--difficulty=normal] \
//     [--state=1] [--concurrency=6] [--shape=truncate]
//
// `--shape=off|truncate`＝Phase 3.3 形狀實驗臂，對應 production 的
// `PRACTICE_AGENCY_SHAPE_EXPERIMENT`（handler 從 env 讀，這支 runner 直接呼叫
// buildChatPromptBundle／同序後處理，所以像 `--agency` 一樣用旗標值直接餵，
// 解析用 handler 同一支 `agencyShapeExperimentFor`）。artifact meta 記
// `shapeExperiment`。只在 `--agency=on` 且該輪真的介入時有效果。
//
// 已知的非等價（R1 Codex P2，記錄不修）：這支 runner 只是**近似**重現 handler
// 的守門順序——`spicyAllowed` 永遠是 false（handler 會按 Game FSM 本輪熱度
// 給 L3），旁白剝除掛在 `args.style` 而 handler 掛在 `responsePlan` 是否存在
// （角色沒有 style mapping 時兩邊會分岔），Game 的修復優先／現實旗標也沒有
// 關掉 truncate 臂（handler 有，見 handler.ts 截斷處的註解）。跨臂比大小不受
// 影響（兩臂用同一份近似），但這裡的絕對數字不等於 production 行為。

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
import { DEFAULT_PROFILE_IDS } from "../practice-reply-style-eval/run_baseline.ts";
import {
  type AgencyMode,
  type AgencyShapeExperiment,
  agencyShapeExperimentFor,
  type ConversationAgencyState,
  nextConversationAgencyState,
  truncateAgencyShape,
} from "../../supabase/functions/practice-chat/conversation_agency.ts";
import {
  AGENCY_SCENARIOS,
  type AgencyScenario,
  isAgencyScenarioId,
  type ProbeSpec,
} from "./scenarios.ts";

// 照 handler.ts 現用值抄錄（handler 未 export；改 handler 記得同步）。
const CHAT_MAX_TOKENS = 200;
const CHAT_TEMPERATURE = 0.9;
const CHAT_GENERATION_ATTEMPTS = 2;
const MODEL_TIMEOUT_MS = 30000;
// handler.ts assisted 分支在還沒有分類器結果時的注入值（beginner 起始溫度／熟悉度）。
const BEGINNER_TEMPERATURE_SCORE = 40;
const BEGINNER_FAMILIARITY_SCORE = 10;

export type PracticeRunMode = "standard" | "beginner" | "game";

/** judge 的唯一可信自身事實來源（每個 profile×難度一份，artifact 裡去重存）。 */
export interface TrustedSources {
  readonly profileId: string;
  readonly difficulty: PracticeDifficulty;
  readonly interests: readonly string[];
  readonly lifestyle: readonly string[];
  readonly selfIntro: string;
  readonly professionLabel: string;
  readonly displayName: string;
  readonly city: string;
  readonly age: number;
  readonly sceneStatusLine: string;
  readonly scenePromptLine: string;
  readonly memorySummary: string;
  readonly herRecentMomentsBlock: string;
}

export function trustedSourcesFor(
  profileId: string,
  difficulty: PracticeDifficulty,
): TrustedSources {
  const profile = resolvePracticeProfile({ difficulty, profileId });
  const fixture = buildBakeoffContextFixture(profile);
  return {
    profileId,
    difficulty,
    interests: profile.girl.interestTags,
    lifestyle: profile.girl.lifestyleTags,
    selfIntro: profile.girl.selfIntro,
    professionLabel: profile.girl.professionLabel,
    displayName: profile.girl.displayName,
    city: profile.girl.city,
    age: profile.girl.age,
    sceneStatusLine: fixture.sceneContext.statusLine,
    scenePromptLine: fixture.sceneContext.promptLine,
    memorySummary: fixture.memorySummary,
    herRecentMomentsBlock: fixture.herRecentMomentsBlock,
  };
}

export interface AgencyTurnResult {
  readonly roundIndex: number;
  readonly role: "user" | "ai";
  readonly userText: string;
  readonly reply: string;
  readonly bubbles: readonly string[];
  /** 結構事實（不判語意）：這一輪之前她最後一則是不是問句。 */
  readonly previousAiAskedQuestion: boolean;
  /** 她這一則是情境檔寫死的腳本（截圖重播／固定前提），不是模型生成。 */
  readonly scripted: boolean;
  readonly probe: ProbeSpec | null;
  readonly promptChars: number;
  readonly elapsedMs: number;
  readonly attempts: number;
  readonly guardRejections: readonly string[];
  readonly stageDirectionRepairs: number;
  /** Phase 3.3 `--shape=truncate` 丟掉幾則泡泡（`off` 恆為 0）。 */
  readonly shapeDropped: number;
}

export interface AgencySessionResult {
  readonly profileId: string;
  readonly personaId: string;
  readonly rarity: string;
  readonly scenarioId: string;
  readonly repeat: number;
  readonly difficulty: PracticeDifficulty;
  readonly mode: PracticeRunMode;
  readonly sceneId: string;
  readonly turns: readonly AgencyTurnResult[];
  readonly error?: string;
}

/** 鏡像 Flutter practice_chat_screen.dart 的 _splitBubbles（>4 段視為一則）。 */
export function splitBubbles(text: string): string[] {
  const parts = text.split("\n").map((p) => p.trim()).filter((p) =>
    p.length > 0
  );
  if (parts.length <= 1 || parts.length > 4) return [text.trim()];
  return parts;
}

/**
 * 結構事實：她這一則看起來是不是在問問題。只看問號、句尾疑問助詞與疑問詞——
 * 中文問句常常不帶問號（「東東是誰」「那你最想去哪個國家玩」），只看標點會systematically
 * 判錯，反而餵給 judge 一個錯的前提。這裡只當 metadata 與 prompt 提示，語意仍由
 * judge 讀逐字稿決定。
 */
export function looksLikeQuestion(text: string): boolean {
  const t = text.trim();
  return /[?？]/u.test(t) ||
    /(嗎|呢|吧)\s*$/mu.test(t) ||
    /(哪|什麼|甚麼|怎樣|怎麼|為何|為什麼|幾點|幾歲|多少|是誰|誰啊|有沒有|要不要|好不好|可不可以)/u
      .test(t);
}

export type ChatCaller = (
  messages: { role: string; content: string }[],
) => Promise<string>;

export async function runAgencyScenario(args: {
  callChat: ChatCaller;
  profileId: string;
  scenario: AgencyScenario;
  repeat: number;
  difficulty: PracticeDifficulty;
  mode: PracticeRunMode;
  style: boolean;
  /** conversation-agency-v1 旗標（handler 用同一個值餵 buildChatPromptBundle）。 */
  agency: AgencyMode;
  /**
   * Phase 3.3 形狀實驗臂（production 走 `PRACTICE_AGENCY_SHAPE_EXPERIMENT`）：
   * `truncate` 走生成後截斷（與 handler 同序、同一支 `truncateAgencyShape`）。
   * 省略＝`off`，逐字與實驗接線前相同。
   */
  shape?: AgencyShapeExperiment;
  /**
   * 模擬 assisted 模式跨回合真的帶 agency state（像 handler 一樣，決策→
   * nextConversationAgencyState→下一輪 agencyState），而不是每輪都傳 null。
   * 只在 mode !== "standard" 時有意義（standard 本來就不持久化狀態）。
   * 這是**結構層**模擬——用 bundle.agencyDecision（Phase 1 的證據／政策）
   * 推下一個狀態，不是真的再打一次 classifier 拿 coherence／
   * aiChallengedLastTurn（那需要每輪多一次 DeepSeek 呼叫，成本加倍）；
   * artifact meta 標 `stateSimulation: true` 並在 README 註明這個簡化。
   */
  stateSimulation?: boolean;
}): Promise<AgencySessionResult> {
  const difficulty = args.scenario.difficulty ?? args.difficulty;
  const profile = resolvePracticeProfile({
    difficulty,
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
  const turns: PracticeTurn[] = [];
  const results: AgencyTurnResult[] = [];
  // stateSimulation：跨輪真的帶狀態（結構層近似，見上面欄位註解）；否則維持
  // 舊行為，每輪都傳 null（standard 與 production 一致）。
  let agencyState: ConversationAgencyState | null = null;
  const base = {
    profileId: args.profileId,
    personaId: profile.personaId,
    rarity: profile.girl.rarity,
    scenarioId: args.scenario.id,
    repeat: args.repeat,
    difficulty,
    mode: args.mode,
    sceneId: fixture.sceneContext.id,
  };

  for (let i = 0; i < args.scenario.turns.length; i++) {
    const step = args.scenario.turns[i];
    const lastAi = [...turns].reverse().find((t) => t.role === "ai");
    const previousAiAskedQuestion = lastAi
      ? looksLikeQuestion(lastAi.text)
      : false;
    if (step.role === "ai") {
      // 開場腳本（A01 的「AI 先問一句」）：直接進逐字稿，不打模型。
      turns.push({ role: "ai", text: step.text });
      results.push({
        roundIndex: i + 1,
        role: "ai",
        userText: "",
        reply: step.text,
        bubbles: splitBubbles(step.text),
        previousAiAskedQuestion,
        scripted: true,
        probe: null,
        promptChars: 0,
        elapsedMs: 0,
        attempts: 0,
        guardRejections: [],
        stageDirectionRepairs: 0,
        shapeDropped: 0,
      });
      continue;
    }

    turns.push({ role: "user", text: step.text });
    // 下一步是腳本 ai turn＝這一輪她的回覆是寫死的（截圖重播、A04 的固定澄清），
    // 不打模型也不多插一則生成回覆——不然逐字稿會多出一則不存在於截圖的回話。
    const scriptedReply = args.scenario.turns[i + 1];
    if (scriptedReply?.role === "ai") {
      i++;
      turns.push({ role: "ai", text: scriptedReply.text });
      results.push({
        roundIndex: i + 1,
        role: "user",
        userText: step.text,
        reply: scriptedReply.text,
        bubbles: splitBubbles(scriptedReply.text),
        previousAiAskedQuestion,
        scripted: true,
        probe: step.probe ?? null,
        promptChars: 0,
        elapsedMs: 0,
        attempts: 0,
        guardRejections: [],
        stageDirectionRepairs: 0,
        shapeDropped: 0,
      });
      continue;
    }
    // handler.ts:4230-4260：assisted（beginner／game）帶 practiceMode＋分數；
    // standard 完全不帶 practiceMode key 與分數，partnerState 維持 null。
    const bundle = buildChatPromptBundle(turns, profile, {
      replyStyle: args.style,
      agencyMode: args.agency,
      visiblePracticeThreadId: BAKEOFF_THREAD_ID,
      partnerState: null,
      styleState: null,
      // 短期 agency 狀態：standard 或未開 --state 一律從逐字稿現推（與
      // production standard 同）；stateSimulation 才跨輪真的帶狀態。
      agencyState: args.stateSimulation ? agencyState : null,
      ...(args.mode === "beginner" || args.mode === "game"
        ? {
          practiceMode: args.mode,
          temperatureScore: BEGINNER_TEMPERATURE_SCORE,
          familiarityScore: BEGINNER_FAMILIARITY_SCORE,
        }
        : {}),
      ...chatContext,
    });
    const messages = bundle.messages;
    const promptChars = messages.reduce((sum, m) => sum + m.content.length, 0);

    const startedAt = Date.now();
    let reply: string | null = null;
    let attempts = 0;
    let stageDirectionRepairs = 0;
    let shapeDropped = 0;
    const guardRejections: string[] = [];
    let lastError: unknown;
    for (let attempt = 1; attempt <= CHAT_GENERATION_ATTEMPTS; attempt++) {
      attempts = attempt;
      try {
        let candidate = await args.callChat(messages);
        // handler.ts 同序後處理。
        candidate = toTraditionalChinese(normalizeLiteralNewlines(candidate));
        rejectVisibleInternalLabelLeak(candidate, "chat_internal_label_leak", {
          transcript: turns.map((t) => t.text).join("\n"),
          ...(args.style
            ? { extraChineseLabels: REPLY_STYLE_HIDDEN_HEADINGS }
            : {}),
        });
        rejectL4UnsafeVisibleText(candidate, "chat_l4_unsafe", {
          fieldClass: "strict",
          spicyAllowed: false,
        });
        if (args.style && hasStageDirection(candidate)) {
          stageDirectionRepairs++;
          candidate = stripStageDirections(candidate, "chat_stage_direction");
        }
        // Phase 3.3 `truncate` 臂：與 handler 同一支函式、同一個位置（所有
        // 守門與修補之後、落成 reply 之前），所以 judge 讀到的就是截斷後的文字。
        if (args.shape === "truncate") {
          const truncated = truncateAgencyShape(
            candidate,
            bundle.agencyDecision,
          );
          candidate = truncated.text;
          shapeDropped = truncated.dropped;
        }
        reply = candidate;
        break;
      } catch (e) {
        lastError = e;
        const message = e instanceof Error ? e.message : String(e);
        if (message.startsWith("chat_")) guardRejections.push(message);
        console.error(
          `[agency] ${args.profileId}/${args.scenario.id}#${args.repeat} round${
            i + 1
          } 第 ${attempt} 次失敗：${message}`,
        );
      }
    }
    if (reply === null) {
      return {
        ...base,
        turns: results,
        error: lastError instanceof Error
          ? lastError.message
          : String(lastError),
      };
    }
    results.push({
      roundIndex: i + 1,
      role: "user",
      userText: step.text,
      reply,
      bubbles: splitBubbles(reply),
      previousAiAskedQuestion,
      scripted: false,
      probe: step.probe ?? null,
      promptChars,
      elapsedMs: Date.now() - startedAt,
      attempts,
      guardRejections,
      stageDirectionRepairs,
      shapeDropped,
    });
    turns.push({ role: "ai", text: reply });
    // 這一輪的決策決定下一輪帶進去的狀態（結構層近似，見 stateSimulation
    // 欄位註解）；agency 關閉或 shadow 時 bundle.agencyDecision 是 null／
    // applied=false，state 停在原地不動。
    if (args.stateSimulation && bundle.agencyDecision?.applied) {
      agencyState = nextConversationAgencyState(
        agencyState,
        bundle.agencyDecision.decision,
      );
    }
  }
  return { ...base, turns: results };
}

// ── CLI ───────────────────────────────────────────────────────────────────
interface CliOptions {
  outPath: string;
  profileIds: string[];
  scenarios: AgencyScenario[];
  repeat: number;
  difficulty: PracticeDifficulty;
  mode: PracticeRunMode;
  style: boolean;
  agency: AgencyMode;
  /** Phase 3.3 形狀實驗臂（--shape）；`off`＝與實驗接線前逐字相同。 */
  shape: AgencyShapeExperiment;
  concurrency: number;
  /** --state=1：跨輪真的帶 agency state（結構層模擬，見 runAgencyScenario）。 */
  stateSimulation: boolean;
}

export function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = {
    outPath: new URL("./out/latest.json", import.meta.url).pathname,
    profileIds: [...DEFAULT_PROFILE_IDS],
    scenarios: [...AGENCY_SCENARIOS],
    repeat: 3,
    difficulty: "normal",
    mode: "standard",
    style: true,
    agency: "off",
    shape: "off",
    concurrency: 6,
    stateSimulation: false,
  };
  for (const arg of argv) {
    if (!arg.startsWith("--")) {
      opts.outPath = arg;
      continue;
    }
    const eq = arg.indexOf("=");
    if (eq < 0) {
      throw new Error(`agency_invalid_cli_arg: "${arg}"（格式 --key=value）`);
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
          if (!isAgencyScenarioId(id)) {
            throw new Error(`agency_invalid_scenario: "${id}"`);
          }
        }
        opts.scenarios = AGENCY_SCENARIOS.filter((s) => ids.includes(s.id));
        break;
      }
      case "repeat": {
        const n = Number.parseInt(value, 10);
        if (!Number.isInteger(n) || n < 1) {
          throw new Error(`agency_invalid_repeat: "${value}"`);
        }
        opts.repeat = n;
        break;
      }
      case "concurrency": {
        const n = Number.parseInt(value, 10);
        if (!Number.isInteger(n) || n < 1) {
          throw new Error(`agency_invalid_concurrency: "${value}"`);
        }
        opts.concurrency = n;
        break;
      }
      case "mode":
        if (value !== "standard" && value !== "beginner" && value !== "game") {
          throw new Error(`agency_invalid_mode: "${value}"`);
        }
        opts.mode = value;
        break;
      case "style":
        opts.style = value === "1" || value === "true";
        break;
      case "state":
        opts.stateSimulation = value === "1" || value === "true";
        break;
      case "agency":
        // production 旗標的三個有效值＋常用簡寫；其餘一律報錯（不靜默當 off）。
        if (value === "on" || value === "1" || value === "true") {
          opts.agency = "on";
        } else if (value === "shadow") {
          opts.agency = "shadow";
        } else if (value === "off" || value === "0") {
          opts.agency = "off";
        } else {
          throw new Error(`agency_invalid_agency_flag: "${value}"`);
        }
        break;
      case "shape":
        // 用 production 同一支解析（`agencyShapeExperimentFor`），但認不得的值
        // 在 runner 一律報錯——靜默當 off 會讓 artifact meta 說謊。
        if (value !== "off" && agencyShapeExperimentFor(value) === "off") {
          throw new Error(`agency_invalid_shape_experiment: "${value}"`);
        }
        opts.shape = agencyShapeExperimentFor(value);
        break;
      case "difficulty":
        if (!isPracticeDifficulty(value)) {
          throw new Error(`agency_invalid_difficulty: "${value}"`);
        }
        opts.difficulty = value;
        break;
      default:
        throw new Error(
          `agency_unknown_cli_flag: "--${key}"（支援：--profiles、--scenarios、--repeat、--mode、--style、--agency、--shape、--difficulty、--concurrency、--state）`,
        );
    }
  }
  // Codex round-2 P2(d)：`--state=1` 在 standard 是**沒有作用**的旗標
  // （standard 本來就不持久化跨回合狀態，每輪從逐字稿現推）。靜默忽略會讓
  // artifact 的 `stateSimulation: true` 說謊，之後照著 meta 解讀數字就會錯。
  if (opts.stateSimulation && (opts.mode ?? "standard") === "standard") {
    throw new Error(
      "agency_state_requires_assisted_mode: --state=1 只對 --mode=beginner／game 有意義（standard 不持久化跨回合狀態）",
    );
  }
  return opts;
}

export async function readDeepSeekKey(): Promise<string> {
  const fromEnv = Deno.env.get("DEEPSEEK_API_KEY");
  if (fromEnv) return fromEnv;
  const envPath = new URL("../../supabase/.env", import.meta.url).pathname;
  const text = await Deno.readTextFile(envPath).catch(() => "");
  const match = text.match(/DEEPSEEK_API_KEY=("?)([^"\n]+)\1/);
  if (!match) {
    throw new Error(
      "agency_missing_key: DEEPSEEK_API_KEY 不在 env 也不在 supabase/.env",
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

/** 展開 job 清單：情境可以釘死角色（截圖重播），其餘跑 CLI 指定的全部角色。 */
export function buildJobs(
  profileIds: readonly string[],
  scenarios: readonly AgencyScenario[],
  repeat: number,
): { profileId: string; scenario: AgencyScenario; repeat: number }[] {
  const jobs: {
    profileId: string;
    scenario: AgencyScenario;
    repeat: number;
  }[] = [];
  for (const scenario of scenarios) {
    const ids = scenario.profileIds ?? profileIds;
    for (const profileId of ids) {
      for (let r = 1; r <= repeat; r++) {
        jobs.push({ profileId, scenario, repeat: r });
      }
    }
  }
  return jobs;
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

  const jobs = buildJobs(opts.profileIds, opts.scenarios, opts.repeat);
  const results: AgencySessionResult[] = new Array(jobs.length);
  let next = 0;
  const startedAt = Date.now();
  const worker = async () => {
    while (next < jobs.length) {
      const index = next++;
      const job = jobs[index];
      results[index] = await runAgencyScenario({
        callChat,
        profileId: job.profileId,
        scenario: job.scenario,
        repeat: job.repeat,
        difficulty: opts.difficulty,
        mode: opts.mode,
        style: opts.style,
        agency: opts.agency,
        shape: opts.shape,
        stateSimulation: opts.stateSimulation,
      });
      console.error(
        `[agency] ${
          index + 1
        }/${jobs.length} ${job.profileId}/${job.scenario.id}#${job.repeat}` +
          (results[index].error ? ` 失敗：${results[index].error}` : ""),
      );
    }
  };
  await Promise.all(Array.from({ length: opts.concurrency }, worker));

  const trustedKey = (r: AgencySessionResult) =>
    `${r.profileId}|${r.difficulty}`;
  const trustedSources: Record<string, TrustedSources> = {};
  for (const r of results) {
    if (!trustedSources[trustedKey(r)]) {
      trustedSources[trustedKey(r)] = trustedSourcesFor(
        r.profileId,
        r.difficulty,
      );
    }
  }

  const artifact = {
    meta: {
      tool: "practice-agency-eval/run_agency",
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
      practiceMode: opts.mode,
      replyStyle: opts.style,
      conversationAgency: opts.agency,
      // Phase 3.3 形狀實驗臂（`off`／`truncate`）；解讀數字時要跟
      // conversationAgency 一起看——旗標不是 on 時這個臂沒有任何效果。
      shapeExperiment: opts.shape,
      // 這個 artifact 是不是用了跨輪 agency state 結構層模擬（不是真的每輪
      // 都多打一次 classifier）；README／報告引用數字時要標明。
      stateSimulation: opts.stateSimulation,
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
    trustedSources,
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
  const calls = results.reduce(
    (sum, r) =>
      sum + r.turns.filter((t) => t.role === "user" && !t.scripted).length,
    0,
  );
  console.error(
    `[agency] 完成 ${results.length} 場（失敗 ${failed}）、${calls} 次生成，寫入 ${opts.outPath}`,
  );
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(
      `[agency] 致命錯誤：${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    Deno.exit(1);
  });
}

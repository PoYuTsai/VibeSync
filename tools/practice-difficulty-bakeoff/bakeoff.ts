// 練習室難度 bakeoff（上線 gate 工具）。
//
// 目的：難度(easy/normal/challenge) × 腳本(bad_interrogator/average/high_quality) ×
// runs 全跑一輪，量測「同一難度設定在不同使用者輸入下」的 AI 回覆長度、句點/敷衍占比、
// 溫度軌跡、debrief dateChance 分佈，作為難度重設計上線前的量化 gate。
//
// 重要：直接 import practice-chat 的真管線模組（resolvePracticeProfile／buildChatMessages／
// buildDebriefMessages／buildTurnClassifierMessages／parseTurnClassification／
// applyLearningClassification／difficultyTuningFor／parseDebriefCard），絕不自造 prompt
// 或分類邏輯——這樣量到的才是真的會上線的行為，不是這支工具自己腦補的行為。
//
// ⚠️ 模型供應商說明（與 practice-chat 正式環境的差異，任務規格與現況有落差，此為刻意決策）：
// practice-chat 正式環境的 chat/debrief/分類器全部呼叫 DeepSeek（見 handler.ts 的
// DEEPSEEK_MODEL="deepseek-v4-flash"、deps.callDeepSeek、env DEEPSEEK_API_KEY）。但：
//   1. 本機 repo 只有 CLAUDE_API_KEY（supabase/.env），完全沒有 DEEPSEEK_API_KEY，無法
//      离线跑 DeepSeek。
//   2. 本 task 規格文字明講「讀 env CLAUDE_API_KEY」。
// 因此這支工具改打 Anthropic Messages API（CLAUDE_API_KEY + claude-sonnet-4-6，與
// coach-chat/generation.ts、analyze-chat 現用的 Sonnet 常數一致），只重用「同一組
// ChatMessage[] prompt 內容」與「同一套分類/溫度數學」，不重用 DeepSeek 這個 vendor。
// 如果之後要用真正的 DEEPSEEK_API_KEY 重跑一次做交叉驗證，只需要替換 callModel() 的
// 實作（可參考 supabase/functions/practice-chat/deepseek.ts 的 callDeepSeek）。
// 這個落差已在 Task 7 交付時的回報中對 Eric 明講，非隱性偷改規格。

import {
  difficultyTuningFor,
  DEFAULT_PROFILE_ID,
  isPracticeDifficulty,
  type PracticeDifficulty,
  resolvePracticeProfile,
} from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  buildChatMessages,
  buildDebriefMessages,
  type ChatMessage,
} from "../../supabase/functions/practice-chat/prompt.ts";
import {
  applyLearningClassification,
  buildTurnClassifierMessages,
  parseTurnClassification,
  type TurnClassification,
} from "../../supabase/functions/practice-chat/temperature.ts";
import {
  type DebriefCard,
  parseDebriefCard,
} from "../../supabase/functions/practice-chat/debrief_card.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import { isScriptId, SCRIPT_IDS, SCRIPTS, type ScriptId } from "./scripts.ts";

// ── 模型呼叫常數（照 supabase/functions/practice-chat/handler.ts 現用值抄錄；
//    handler.ts 未 export 這些 const，這裡只能複製同一組數值，改 handler 記得同步）──
const CHAT_MAX_TOKENS = 200;
const CHAT_TEMPERATURE = 0.9;
const CHAT_GENERATION_ATTEMPTS = 2;
const DEBRIEF_MAX_TOKENS = 800;
const DEBRIEF_TEMPERATURE = 0.5;
const DEBRIEF_GENERATION_ATTEMPTS = 2;
const TEMPERATURE_JUDGE_MAX_TOKENS = 450;
const TEMPERATURE_JUDGE_TEMPERATURE = 0.2;
const MODEL_TIMEOUT_MS = 30000;

const CLAUDE_MODEL = "claude-sonnet-4-6";
const CLAUDE_ENDPOINT = "https://api.anthropic.com/v1/messages";

const PERFUNCTORY_PATTERN = /^(喔+|嗯+|還好|哈哈+|是喔|喔喔)[。.!?～~]?$/;

// ── Claude 呼叫（全域律：外部 API 必 try-catch、錯誤訊息不得 minified）──────────
interface ClaudeCallArgs {
  apiKey: string;
  messages: ChatMessage[];
  maxTokens: number;
  temperature: number;
  timeoutMs: number;
}

async function callClaude(args: ClaudeCallArgs): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), args.timeoutMs);
  try {
    const system = args.messages
      .filter((m) => m.role === "system")
      .map((m) => m.content)
      .join("\n\n");
    const conversation = args.messages
      .filter((m) => m.role !== "system")
      .map((m) => ({ role: m.role, content: m.content }));
    if (conversation.length === 0) {
      throw new Error(
        "bakeoff_claude_empty_conversation: messages 陣列扣掉 system 之後沒有任何 user/assistant 訊息",
      );
    }

    const res = await fetch(CLAUDE_ENDPOINT, {
      method: "POST",
      headers: {
        "x-api-key": args.apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: CLAUDE_MODEL,
        max_tokens: args.maxTokens,
        temperature: args.temperature,
        system: system.length > 0 ? system : undefined,
        messages: conversation,
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "(讀取 response body 失敗)");
      throw new Error(
        `bakeoff_claude_http_${res.status}: ${body.slice(0, 500)}`,
      );
    }

    const json = await res.json();
    const text = json?.content?.[0]?.text;
    if (typeof text !== "string" || text.trim().length === 0) {
      throw new Error(
        `bakeoff_claude_empty_content: response=${
          JSON.stringify(json).slice(0, 500)
        }`,
      );
    }
    return text.trim();
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new Error(
        `bakeoff_claude_timeout: 超過 ${args.timeoutMs}ms 未回應`,
      );
    }
    throw e instanceof Error
      ? e
      : new Error(`bakeoff_claude_unknown_error: ${String(e)}`);
  } finally {
    clearTimeout(timeout);
  }
}

async function withRetry<T>(
  fn: () => Promise<T>,
  attempts: number,
  label: string,
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn();
    } catch (e) {
      lastError = e;
      console.error(
        `[bakeoff] ${label} 第 ${attempt}/${attempts} 次嘗試失敗：${
          e instanceof Error ? e.message : String(e)
        }`,
      );
    }
  }
  throw lastError instanceof Error
    ? lastError
    : new Error(`bakeoff_retry_exhausted(${label}): ${String(lastError)}`);
}

function strippedLength(text: string): number {
  return text.replace(/\s+/g, "").length;
}

function isPerfunctoryReply(text: string): boolean {
  const trimmed = text.trim();
  if (trimmed.length === 0) return true;
  if (strippedLength(trimmed) <= 10) return true;
  return PERFUNCTORY_PATTERN.test(trimmed);
}

// ── 單輪紀錄／單場紀錄 ────────────────────────────────────────────────────
interface TurnRecord {
  roundIndex: number;
  userText: string;
  aiReply: string;
  replyLength: number;
  isPerfunctory: boolean;
  classification: TurnClassification;
  temperatureBefore: number;
  familiarityBefore: number;
  temperatureAfter: number;
  familiarityAfter: number;
  heatDelta: number;
  familiarityDelta: number;
}

interface RunRecord {
  difficulty: PracticeDifficulty;
  scriptId: ScriptId;
  runIndex: number;
  turns: TurnRecord[];
  debrief: DebriefCard | null;
  debriefError?: string;
  finalTemperature: number | null;
  finalFamiliarity: number | null;
  sessionError?: string;
}

async function runOneSession(args: {
  apiKey: string;
  difficulty: PracticeDifficulty;
  scriptId: ScriptId;
  runIndex: number;
  profileId: string;
}): Promise<RunRecord> {
  const profile = resolvePracticeProfile({
    difficulty: args.difficulty,
    profileId: args.profileId,
  });
  const tuning = difficultyTuningFor(profile.difficulty);
  let temperature = tuning.startTemperature;
  let familiarity = 0;
  const turns: PracticeTurn[] = [];
  const turnRecords: TurnRecord[] = [];
  const userMessages = SCRIPTS[args.scriptId];

  for (let i = 0; i < userMessages.length; i++) {
    const userText = userMessages[i];
    turns.push({ role: "user", text: userText });
    const temperatureBefore = temperature;
    const familiarityBefore = familiarity;

    const reply = await withRetry(
      () =>
        callClaude({
          apiKey: args.apiKey,
          messages: buildChatMessages(turns, profile, {
            practiceMode: "beginner",
            temperatureScore: temperature,
            familiarityScore: familiarity,
          }),
          maxTokens: CHAT_MAX_TOKENS,
          temperature: CHAT_TEMPERATURE,
          timeoutMs: MODEL_TIMEOUT_MS,
        }),
      CHAT_GENERATION_ATTEMPTS,
      `${args.difficulty}/${args.scriptId}/run${args.runIndex}/round${
        i + 1
      } chat`,
    );

    const classification = await withRetry(
      async () => {
        const raw = await callClaude({
          apiKey: args.apiKey,
          messages: buildTurnClassifierMessages({
            turns,
            profile,
            heatScore: temperature,
            familiarityScore: familiarity,
          }),
          maxTokens: TEMPERATURE_JUDGE_MAX_TOKENS,
          temperature: TEMPERATURE_JUDGE_TEMPERATURE,
          timeoutMs: MODEL_TIMEOUT_MS,
        });
        return parseTurnClassification(raw, {});
      },
      CHAT_GENERATION_ATTEMPTS,
      `${args.difficulty}/${args.scriptId}/run${args.runIndex}/round${
        i + 1
      } classify`,
    );

    const judgement = applyLearningClassification(
      { heatScore: temperature, familiarityScore: familiarity },
      classification,
      tuning,
    );

    turns.push({ role: "ai", text: reply });

    turnRecords.push({
      roundIndex: i + 1,
      userText,
      aiReply: reply,
      replyLength: strippedLength(reply),
      isPerfunctory: isPerfunctoryReply(reply),
      classification,
      temperatureBefore,
      familiarityBefore,
      temperatureAfter: judgement.score,
      familiarityAfter: judgement.familiarityScore,
      heatDelta: judgement.delta,
      familiarityDelta: judgement.familiarityDelta,
    });

    temperature = judgement.score;
    familiarity = judgement.familiarityScore;
  }

  let debrief: DebriefCard | null = null;
  let debriefError: string | undefined;
  try {
    const raw = await withRetry(
      () =>
        callClaude({
          apiKey: args.apiKey,
          messages: buildDebriefMessages(turns, profile, {
            practiceMode: "beginner",
            temperatureScore: temperature,
            familiarityScore: familiarity,
          }),
          maxTokens: DEBRIEF_MAX_TOKENS,
          temperature: DEBRIEF_TEMPERATURE,
          timeoutMs: MODEL_TIMEOUT_MS,
        }),
      DEBRIEF_GENERATION_ATTEMPTS,
      `${args.difficulty}/${args.scriptId}/run${args.runIndex} debrief`,
    );
    debrief = parseDebriefCard(raw);
  } catch (e) {
    debriefError = e instanceof Error ? e.message : String(e);
    console.error(`[bakeoff] debrief 失敗（不中斷整場）：${debriefError}`);
  }

  return {
    difficulty: args.difficulty,
    scriptId: args.scriptId,
    runIndex: args.runIndex,
    turns: turnRecords,
    debrief,
    debriefError,
    finalTemperature: temperature,
    finalFamiliarity: familiarity,
  };
}

// ── CLI 參數 ────────────────────────────────────────────────────────────
interface CliOptions {
  runs: number;
  scripts: ScriptId[];
  difficulties: PracticeDifficulty[];
  outDir: string;
  profileId: string;
}

function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = {
    runs: 2,
    scripts: [...SCRIPT_IDS],
    difficulties: ["easy", "normal", "challenge"],
    outDir: "out",
    profileId: DEFAULT_PROFILE_ID,
  };

  for (const arg of argv) {
    const eq = arg.indexOf("=");
    if (!arg.startsWith("--") || eq < 0) {
      throw new Error(
        `bakeoff_invalid_cli_arg: "${arg}"（格式必須是 --key=value，例如 --runs=1）`,
      );
    }
    const key = arg.slice(2, eq);
    const value = arg.slice(eq + 1);
    switch (key) {
      case "runs": {
        const n = Number.parseInt(value, 10);
        if (!Number.isInteger(n) || n < 1) {
          throw new Error(`bakeoff_invalid_runs: "${value}"（必須是 >=1 整數）`);
        }
        opts.runs = n;
        break;
      }
      case "scripts": {
        const ids = value.split(",").map((s) => s.trim()).filter(Boolean);
        for (const id of ids) {
          if (!isScriptId(id)) {
            throw new Error(
              `bakeoff_invalid_script_id: "${id}"（合法值：${
                SCRIPT_IDS.join(", ")
              }）`,
            );
          }
        }
        opts.scripts = ids as ScriptId[];
        break;
      }
      case "difficulties": {
        const ids = value.split(",").map((s) => s.trim()).filter(Boolean);
        for (const id of ids) {
          if (!isPracticeDifficulty(id)) {
            throw new Error(
              `bakeoff_invalid_difficulty: "${id}"（合法值：easy, normal, challenge）`,
            );
          }
        }
        opts.difficulties = ids as PracticeDifficulty[];
        break;
      }
      case "out":
        opts.outDir = value;
        break;
      case "profileId":
        opts.profileId = value;
        break;
      default:
        throw new Error(
          `bakeoff_unknown_cli_flag: "--${key}"（支援：--runs、--scripts、--difficulties、--out、--profileId）`,
        );
    }
  }

  if (opts.scripts.length === 0) {
    throw new Error("bakeoff_invalid_cli_arg: --scripts 不可為空");
  }
  if (opts.difficulties.length === 0) {
    throw new Error("bakeoff_invalid_cli_arg: --difficulties 不可為空");
  }

  return opts;
}

// ── 報表輸出 ────────────────────────────────────────────────────────────
interface GroupStats {
  difficulty: PracticeDifficulty;
  scriptId: ScriptId;
  runsOk: number;
  runsFailed: number;
  avgReplyLength: number | null;
  perfunctoryRate: number | null;
  avgFinalTemperature: number | null;
  avgFinalFamiliarity: number | null;
  temperatureTrajectories: number[][];
  dateChanceCounts: Record<string, number>;
}

function average(values: number[]): number | null {
  if (values.length === 0) return null;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function buildGroupStats(
  difficulties: PracticeDifficulty[],
  scripts: ScriptId[],
  results: RunRecord[],
): GroupStats[] {
  const groups: GroupStats[] = [];
  for (const difficulty of difficulties) {
    for (const scriptId of scripts) {
      const runs = results.filter(
        (r) => r.difficulty === difficulty && r.scriptId === scriptId,
      );
      const okRuns = runs.filter((r) => !r.sessionError);
      const allTurns = okRuns.flatMap((r) => r.turns);
      const replyLengths = allTurns.map((t) => t.replyLength);
      const perfunctoryCount = allTurns.filter((t) => t.isPerfunctory).length;
      const finalTemps = okRuns
        .map((r) => r.finalTemperature)
        .filter((v): v is number => v !== null);
      const finalFams = okRuns
        .map((r) => r.finalFamiliarity)
        .filter((v): v is number => v !== null);
      const dateChanceCounts: Record<string, number> = {};
      for (const r of okRuns) {
        const key = r.debrief?.dateChance ?? (r.debriefError ? "error" : "unknown");
        dateChanceCounts[key] = (dateChanceCounts[key] ?? 0) + 1;
      }
      groups.push({
        difficulty,
        scriptId,
        runsOk: okRuns.length,
        runsFailed: runs.length - okRuns.length,
        avgReplyLength: average(replyLengths),
        perfunctoryRate: allTurns.length > 0
          ? perfunctoryCount / allTurns.length
          : null,
        avgFinalTemperature: average(finalTemps),
        avgFinalFamiliarity: average(finalFams),
        temperatureTrajectories: okRuns.map((r) =>
          r.turns.map((t) => t.temperatureAfter)
        ),
        dateChanceCounts,
      });
    }
  }
  return groups;
}

function fmt(n: number | null, digits = 1): string {
  return n === null ? "N/A" : n.toFixed(digits);
}

function renderReportMarkdown(groups: GroupStats[]): string {
  const lines: string[] = [];
  lines.push("# 練習室難度 bakeoff 報告");
  lines.push("");
  lines.push(
    "> 模型：Claude（claude-sonnet-4-6，經 CLAUDE_API_KEY）——與 practice-chat 正式環境" +
      "的 DeepSeek 不同 vendor，但 prompt／分類器／溫度數學皆為真管線重用。細節見 bakeoff.ts 檔頭註解。",
  );
  lines.push("");
  lines.push(
    "| 難度 | 腳本 | 場次(成功/失敗) | 平均回覆長度(字) | 敷衍輪占比 | 平均終值溫度 | 平均終值熟悉度 | dateChance 分佈 |",
  );
  lines.push("|---|---|---|---|---|---|---|---|");
  for (const g of groups) {
    const dateChance = Object.entries(g.dateChanceCounts)
      .map(([k, v]) => `${k}:${v}`)
      .join(" / ") || "N/A";
    lines.push(
      `| ${g.difficulty} | ${g.scriptId} | ${g.runsOk}/${g.runsFailed} | ${
        fmt(g.avgReplyLength)
      } | ${
        g.perfunctoryRate === null
          ? "N/A"
          : `${(g.perfunctoryRate * 100).toFixed(1)}%`
      } | ${fmt(g.avgFinalTemperature)} | ${
        fmt(g.avgFinalFamiliarity)
      } | ${dateChance} |`,
    );
  }
  lines.push("");
  lines.push("## 溫度逐輪軌跡（每場一列，依 roundIndex 順序）");
  lines.push("");
  for (const g of groups) {
    lines.push(`### ${g.difficulty} × ${g.scriptId}`);
    if (g.temperatureTrajectories.length === 0) {
      lines.push("（無成功場次）");
    } else {
      g.temperatureTrajectories.forEach((traj, idx) => {
        lines.push(`- run ${idx + 1}: [${traj.join(", ")}]`);
      });
    }
    lines.push("");
  }
  return lines.join("\n");
}

async function writeReports(
  outDir: string,
  results: RunRecord[],
  groups: GroupStats[],
): Promise<void> {
  await Deno.mkdir(outDir, { recursive: true });
  await Deno.writeTextFile(
    `${outDir}/raw.json`,
    JSON.stringify({ results, groups }, null, 2),
  );
  await Deno.writeTextFile(
    `${outDir}/report.md`,
    renderReportMarkdown(groups),
  );
}

// ── main ────────────────────────────────────────────────────────────────
async function main(): Promise<void> {
  const apiKey = Deno.env.get("CLAUDE_API_KEY");
  if (!apiKey || apiKey.trim().length === 0) {
    throw new Error(
      "bakeoff_missing_env: 未設定 CLAUDE_API_KEY。跑法：CLAUDE_API_KEY=... deno run " +
        "--allow-net --allow-env --allow-read --allow-write tools/practice-difficulty-bakeoff/bakeoff.ts",
    );
  }

  const opts = parseArgs(Deno.args);
  console.log(
    `[bakeoff] 難度=${opts.difficulties.join(",")} 腳本=${
      opts.scripts.join(",")
    } runs=${opts.runs} profileId=${opts.profileId} outDir=${opts.outDir}`,
  );

  const results: RunRecord[] = [];
  for (const difficulty of opts.difficulties) {
    for (const scriptId of opts.scripts) {
      for (let runIndex = 1; runIndex <= opts.runs; runIndex++) {
        try {
          const record = await runOneSession({
            apiKey,
            difficulty,
            scriptId,
            runIndex,
            profileId: opts.profileId,
          });
          results.push(record);
          console.log(
            `[bakeoff] 完成 ${difficulty} × ${scriptId} run ${runIndex}/${opts.runs}` +
              `（終值溫度=${record.finalTemperature} 熟悉度=${record.finalFamiliarity} dateChance=${
                record.debrief?.dateChance ?? "(debrief失敗)"
              }）`,
          );
        } catch (e) {
          const message = e instanceof Error ? e.message : String(e);
          console.error(
            `[bakeoff] 場次失敗 ${difficulty} × ${scriptId} run ${runIndex}：${message}`,
          );
          results.push({
            difficulty,
            scriptId,
            runIndex,
            turns: [],
            debrief: null,
            finalTemperature: null,
            finalFamiliarity: null,
            sessionError: message,
          });
        }
      }
    }
  }

  const groups = buildGroupStats(opts.difficulties, opts.scripts, results);
  await writeReports(opts.outDir, results, groups);
  console.log(
    `[bakeoff] 全部完成，報告輸出於 ${opts.outDir}/report.md 與 ${opts.outDir}/raw.json`,
  );
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(
      `[bakeoff] 致命錯誤：${e instanceof Error ? e.stack ?? e.message : String(e)}`,
    );
    Deno.exit(1);
  });
}

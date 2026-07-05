// 練習室難度 bakeoff（上線 gate 工具）。
//
// 目的：難度(easy/normal/challenge) × 腳本(bad_interrogator/average/high_quality) ×
// runs 全跑一輪，量測「同一難度設定在不同使用者輸入下」的 AI 回覆長度、句點/敷衍占比、
// 溫度軌跡、debrief dateChance 分佈，作為難度重設計上線前的量化 gate。
//
// 重要：直接 import practice-chat 的真管線模組（resolvePracticeProfile／buildChatMessages／
// buildDebriefMessages／buildTurnClassifierMessages／parseTurnClassification／
// applyLearningClassification／difficultyTuningFor／parseDebriefCard／callDeepSeek），
// 絕不自造 prompt 或分類邏輯——這樣量到的才是真的會上線的行為，不是這支工具自己腦補的行為。
//
// 模型供應商（Eric 2026-07-06 拍板）：
// - 預設 provider = DeepSeek（deepseek-v4-flash），與 practice-chat 正式環境一模一樣：
//   重用 supabase/functions/practice-chat/deepseek.ts 的 callDeepSeek＋DEEPSEEK_MODEL，
//   呼叫形狀（jsonMode／maxTokens／temperature／timeout）照 handler.ts 現用值。
//   key 讀 env DEEPSEEK_API_KEY。正式 gate 只認 DeepSeek 結果。
// - --provider=claude 保留 Claude 路徑（CLAUDE_API_KEY + claude-sonnet-4-6）純作交叉
//   參考，不作 gate 依據。

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
import {
  callDeepSeek,
  DEEPSEEK_MODEL,
} from "../../supabase/functions/practice-chat/deepseek.ts";
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
const MODEL_TIMEOUT_MS = 30000; // = handler DEEPSEEK_TIMEOUT_MS

// 參考用 Claude 路徑（--provider=claude；非 gate）。
const CLAUDE_MODEL = "claude-sonnet-4-6";
const CLAUDE_ENDPOINT = "https://api.anthropic.com/v1/messages";

const PERFUNCTORY_PATTERN = /^(喔+|嗯+|還好|哈哈+|是喔|喔喔)[。.!?～~]?$/;

// ── provider 抽象 ────────────────────────────────────────────────────────
type Provider = "deepseek" | "claude";

interface ModelCallArgs {
  messages: ChatMessage[];
  maxTokens: number;
  temperature: number;
  jsonMode?: boolean;
  timeoutMs: number;
}

type ModelCaller = (args: ModelCallArgs) => Promise<string>;

function modelLabelFor(provider: Provider): string {
  return provider === "deepseek"
    ? `DeepSeek（${DEEPSEEK_MODEL}，prod 同款，正式 gate 依據）`
    : `Claude（${CLAUDE_MODEL}，僅供交叉參考，不作 gate 依據）`;
}

function envKeyNameFor(provider: Provider): string {
  return provider === "deepseek" ? "DEEPSEEK_API_KEY" : "CLAUDE_API_KEY";
}

function makeModelCaller(provider: Provider, apiKey: string): ModelCaller {
  if (provider === "deepseek") {
    // 與 handler 完全同一個 callDeepSeek（同 endpoint/model/jsonMode 形狀）。
    return (args) =>
      callDeepSeek({
        apiKey,
        messages: args.messages,
        maxTokens: args.maxTokens,
        temperature: args.temperature,
        jsonMode: args.jsonMode,
        timeoutMs: args.timeoutMs,
      });
  }
  return (args) => callClaude({ apiKey, ...args });
}

// ── Claude 呼叫（參考路徑；全域律：外部 API 必 try-catch、錯誤訊息不得 minified）──
async function callClaude(
  args: ModelCallArgs & { apiKey: string },
): Promise<string> {
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

    // Anthropic API 無 jsonMode 參數；prompt 本身已要求只輸出 JSON，此處直接忽略。
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
  callModel: ModelCaller;
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
        args.callModel({
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
        const raw = await args.callModel({
          messages: buildTurnClassifierMessages({
            turns,
            profile,
            heatScore: temperature,
            familiarityScore: familiarity,
          }),
          maxTokens: TEMPERATURE_JUDGE_MAX_TOKENS,
          temperature: TEMPERATURE_JUDGE_TEMPERATURE,
          jsonMode: true,
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
        args.callModel({
          messages: buildDebriefMessages(turns, profile, {
            practiceMode: "beginner",
            temperatureScore: temperature,
            familiarityScore: familiarity,
          }),
          maxTokens: DEBRIEF_MAX_TOKENS,
          temperature: DEBRIEF_TEMPERATURE,
          jsonMode: true,
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

// 預設 outDir 相對於這支腳本自己的目錄，絕不是相對 cwd——
// 否則從 repo 根目錄執行會把報告寫進 repo 根目錄的 out/（未被 gitignore，有被誤 commit 的風險）。
// 只有明確帶 --out 才維持舊語意（相對使用者執行時的 cwd）。
const DEFAULT_OUT_DIR = new URL(".", import.meta.url).pathname + "out";

// ── CLI 參數 ────────────────────────────────────────────────────────────
interface CliOptions {
  provider: Provider;
  runs: number;
  scripts: ScriptId[];
  difficulties: PracticeDifficulty[];
  outDir: string;
  profileId: string;
}

function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = {
    provider: "deepseek",
    runs: 2,
    scripts: [...SCRIPT_IDS],
    difficulties: ["easy", "normal", "challenge"],
    outDir: DEFAULT_OUT_DIR,
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
      case "provider": {
        if (value !== "deepseek" && value !== "claude") {
          throw new Error(
            `bakeoff_invalid_provider: "${value}"（合法值：deepseek（預設，prod 同款）、claude（參考用））`,
          );
        }
        opts.provider = value;
        break;
      }
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
          `bakeoff_unknown_cli_flag: "--${key}"（支援：--provider、--runs、--scripts、--difficulties、--out、--profileId）`,
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
        const key = r.debrief?.dateChance ??
          (r.debriefError ? "error" : "unknown");
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

function renderReportMarkdown(
  groups: GroupStats[],
  provider: Provider,
): string {
  const lines: string[] = [];
  lines.push("# 練習室難度 bakeoff 報告");
  lines.push("");
  lines.push(`> 模型：${modelLabelFor(provider)}`);
  if (provider === "claude") {
    lines.push(
      "> ⚠️ 本報告由 Claude 參考路徑產生，**不得**作為正式上線 gate 依據；gate 只認 DeepSeek（prod 同款）結果。",
    );
  }
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
  provider: Provider,
  results: RunRecord[],
  groups: GroupStats[],
): Promise<void> {
  await Deno.mkdir(outDir, { recursive: true });
  await Deno.writeTextFile(
    `${outDir}/raw.json`,
    JSON.stringify({ provider, results, groups }, null, 2),
  );
  await Deno.writeTextFile(
    `${outDir}/report.md`,
    renderReportMarkdown(groups, provider),
  );
}

// ── main ────────────────────────────────────────────────────────────────
async function main(): Promise<void> {
  const opts = parseArgs(Deno.args);

  const envKeyName = envKeyNameFor(opts.provider);
  const apiKey = Deno.env.get(envKeyName);
  if (!apiKey || apiKey.trim().length === 0) {
    throw new Error(
      `bakeoff_missing_env: 未設定 ${envKeyName}（provider=${opts.provider}）。跑法：` +
        `${envKeyName}=... deno run --allow-net --allow-env --allow-read --allow-write ` +
        "tools/practice-difficulty-bakeoff/bakeoff.ts" +
        (opts.provider === "deepseek"
          ? "。預設 provider=deepseek（prod 同款、正式 gate）；本地若尚未有 DEEPSEEK_API_KEY，請先向 Eric 取得（Eric 會放進 supabase/.env）"
          : ""),
    );
  }
  const callModel = makeModelCaller(opts.provider, apiKey);

  console.log(
    `[bakeoff] provider=${opts.provider}（${
      modelLabelFor(opts.provider)
    }）難度=${opts.difficulties.join(",")} 腳本=${
      opts.scripts.join(",")
    } runs=${opts.runs} profileId=${opts.profileId} outDir=${opts.outDir}`,
  );

  const results: RunRecord[] = [];
  for (const difficulty of opts.difficulties) {
    for (const scriptId of opts.scripts) {
      for (let runIndex = 1; runIndex <= opts.runs; runIndex++) {
        try {
          const record = await runOneSession({
            callModel,
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
  await writeReports(opts.outDir, opts.provider, results, groups);
  console.log(
    `[bakeoff] 全部完成，報告輸出於 ${opts.outDir}/report.md 與 ${opts.outDir}/raw.json`,
  );
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(
      `[bakeoff] 致命錯誤：${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    Deno.exit(1);
  });
}

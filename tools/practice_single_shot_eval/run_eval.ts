// 練習室「單發重設計 v2」四路黑箱 eval（Batch H1）。
// 直接 import practice-chat 的生成組件、用 CLAUDE_API_KEY 打真 Anthropic API；
// 絕不打 prod Edge Function、絕不碰 DB／扣費／ledger。
//
// 跑法（全 80 發）：
//   CLAUDE_API_KEY=... deno run --allow-env --allow-net --allow-read --allow-write run_eval.ts
// 開發省錢：
//   deno run ... run_eval.ts --route=game_hint --repeat=1
// 不花錢驗流程（fake callClaude，全 80 發過 buildMessages＋parser）：
//   deno run --allow-env --allow-read --allow-write run_eval.ts --dry-run
import {
  buildHintDecision,
  buildHintMessages,
  HINT_TOOL_SCHEMA,
  hintTrustedFactualEvidence,
  parseHintResult,
} from "../../supabase/functions/practice-chat/hint.ts";
import { buildDebriefMessages } from "../../supabase/functions/practice-chat/prompt.ts";
import {
  DEBRIEF_TOOL_SCHEMA,
  type DebriefCard,
  parseDebriefCard,
} from "../../supabase/functions/practice-chat/debrief_card.ts";
import {
  runSingleShot,
  type SingleShotClaudeCaller,
  SingleShotExhaustedError,
} from "../../supabase/functions/practice-chat/single_shot.ts";
import {
  callClaude,
  CLAUDE_HAIKU_MODEL,
  CLAUDE_SONNET_MODEL,
} from "../../supabase/functions/practice-chat/claude.ts";
import {
  hasL4UnsafeVisibleText,
  hasVisibleInternalLabelLeak,
  hasVisibleTemperatureMechanismLeak,
} from "../../supabase/functions/practice-chat/visible_text_guard.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  ALL_ROUTES,
  type EvalFixture,
  type EvalRoute,
  FIXTURES_BY_ROUTE,
} from "./fixtures/index.ts";
import { makeFakeCallClaude } from "./dry_run_fake.ts";

// ── 復刻 handler.ts 單發參數（真相源＝supabase/functions/practice-chat/handler.ts；
//    改 handler 常數時這裡要跟著對齊）─────────────────────────────────────────
const HINT_MAX_TOKENS = 500;
const HINT_TEMPERATURE = 0.45;
const HINT_SINGLE_SHOT_TIMEOUT_MS = 15000;
const HINT_REQUEST_DEADLINE_MS = 35000;
const DEBRIEF_MAX_TOKENS = 1200;
const DEBRIEF_TEMPERATURE = 0.5;
const DEBRIEF_SINGLE_SHOT_TIMEOUT_MS = 20000;
const DEBRIEF_REQUEST_DEADLINE_MS = 45000;
const SERVER_HINT_DECISION_RATIONALE =
  "只依據本場逐字稿與已知角色資料；貼句已依目前關係階段與邀約路線校驗。";

type ShotOutcome = "first_shot" | "second_shot" | "http_503";

interface ShotRecord {
  route: EvalRoute;
  fixtureId: string;
  repeatIndex: number;
  outcome: ShotOutcome;
  model: string | null;
  durationMs: number;
  attemptFailureCodes: string[];
  /** 對使用者可見的 served 文字（洩漏掃描與人工目檢用）。 */
  servedText: Record<string, string> | null;
}

interface LeakHit {
  route: EvalRoute;
  fixtureId: string;
  repeatIndex: number;
  field: string;
  guard: string;
}

function parseArgs(args: string[]): {
  routes: EvalRoute[];
  repeat: number;
  dryRun: boolean;
} {
  let routes: EvalRoute[] = [...ALL_ROUTES];
  let repeat = 4;
  let dryRun = false;
  for (const arg of args) {
    if (arg === "--dry-run") {
      dryRun = true;
    } else if (arg.startsWith("--route=")) {
      const route = arg.slice("--route=".length) as EvalRoute;
      if (!ALL_ROUTES.includes(route)) {
        throw new Error(
          `unknown --route=${route}（合法值：${ALL_ROUTES.join("|")}）`,
        );
      }
      routes = [route];
    } else if (arg.startsWith("--repeat=")) {
      const value = Number(arg.slice("--repeat=".length));
      if (!Number.isInteger(value) || value < 1 || value > 20) {
        throw new Error("--repeat 必須是 1-20 的整數");
      }
      repeat = value;
    } else {
      throw new Error(`unknown arg: ${arg}`);
    }
  }
  return { routes, repeat, dryRun };
}

function hintServedText(
  result: ReturnType<typeof parseHintResult>,
): Record<string, string> {
  const served: Record<string, string> = { coaching: result.coaching };
  for (const reply of result.replies) {
    served[reply.type === "warm_up" ? "warmUp" : "steady"] = reply.text;
  }
  return served;
}

function debriefServedText(card: DebriefCard): Record<string, string> {
  const served: Record<string, string> = {
    summary: card.summary,
    suggestedLine: card.suggestedLine,
    vibe: card.vibe,
    dateChance: card.dateChance,
    dateChanceReason: card.dateChanceReason,
    nextInviteMove: card.nextInviteMove,
  };
  card.strengths.forEach((value, index) => {
    served[`strengths[${index}]`] = value;
  });
  card.watchouts.forEach((value, index) => {
    served[`watchouts[${index}]`] = value;
  });
  if (card.gameBreakdown) {
    for (const [key, value] of Object.entries(card.gameBreakdown)) {
      served[`gameBreakdown.${key}`] = value;
    }
  }
  return served;
}

async function runHintShot(opts: {
  fixture: EvalFixture;
  repeatIndex: number;
  caller: SingleShotClaudeCaller;
  apiKey: string;
}): Promise<ShotRecord> {
  const { fixture } = opts;
  const profile = resolvePracticeProfile(fixture.profileArgs);
  const messages = buildHintMessages({
    turns: fixture.turns,
    profile,
    practiceMode: fixture.practiceMode,
    temperatureScore: fixture.temperatureScore,
    familiarityScore: fixture.familiarityScore,
    partnerMood: fixture.partnerMood,
    sceneContext: null,
    memorySummary: fixture.memorySummary,
    gameState: fixture.gameState,
  });
  const evidence = hintTrustedFactualEvidence({
    profile,
    practiceMode: fixture.practiceMode,
    sceneContext: null,
    memorySummary: fixture.memorySummary,
  });
  const parseOptions = {
    mode: fixture.practiceMode,
    turns: fixture.turns,
    sharedFactualEvidence: evidence.shared,
    partnerFactualEvidence: evidence.partner,
    trustedFactClaims: evidence.claims,
    enforceGeneratedQuality: true,
  } as const;
  const startedAt = performance.now();
  try {
    const outcome = await runSingleShot<ReturnType<typeof parseHintResult>>({
      callClaude: opts.caller,
      apiKey: opts.apiKey,
      messages,
      forcedTool: {
        name: "emit_hint",
        description:
          "輸出練習室提示：warmUp/steady 兩句可直接貼上的回覆與 coaching 教練講評。",
        inputSchema: HINT_TOOL_SCHEMA as Record<string, unknown>,
      },
      maxTokens: HINT_MAX_TOKENS,
      temperature: HINT_TEMPERATURE,
      perCallTimeoutMs: HINT_SINGLE_SHOT_TIMEOUT_MS,
      deadlineAtMs: performance.now() + HINT_REQUEST_DEADLINE_MS,
      now: () => performance.now(),
      models: [CLAUDE_SONNET_MODEL, CLAUDE_HAIKU_MODEL],
      validate: (raw) => {
        const parsed = parseHintResult(raw, { ...parseOptions });
        return {
          ...parsed,
          replies: parsed.replies.map((reply) => ({
            ...reply,
            decision: buildHintDecision({
              turns: fixture.turns,
              profile,
              practiceMode: fixture.practiceMode,
              temperatureScore: fixture.temperatureScore,
              familiarityScore: fixture.familiarityScore,
              partnerMood: fixture.partnerMood,
              gameState: fixture.gameState,
              replyType: reply.type,
              replyText: reply.text,
              rationale: SERVER_HINT_DECISION_RATIONALE,
            }),
          })) as typeof parsed.replies,
        };
      },
    });
    return {
      route: fixture.route,
      fixtureId: fixture.id,
      repeatIndex: opts.repeatIndex,
      outcome: outcome.attemptFailures.length === 0
        ? "first_shot"
        : "second_shot",
      model: outcome.model,
      durationMs: Math.round(performance.now() - startedAt),
      attemptFailureCodes: outcome.attemptFailures.map((f) => f.code),
      servedText: hintServedText(outcome.result),
    };
  } catch (error) {
    if (!(error instanceof SingleShotExhaustedError)) throw error;
    return {
      route: fixture.route,
      fixtureId: fixture.id,
      repeatIndex: opts.repeatIndex,
      outcome: "http_503",
      model: null,
      durationMs: Math.round(performance.now() - startedAt),
      attemptFailureCodes: error.attemptFailures.map((f) => f.code),
      servedText: null,
    };
  }
}

async function runDebriefShot(opts: {
  fixture: EvalFixture;
  repeatIndex: number;
  caller: SingleShotClaudeCaller;
  apiKey: string;
}): Promise<ShotRecord> {
  const { fixture } = opts;
  const profile = resolvePracticeProfile(fixture.profileArgs);
  // beginner/game 皆為 assisted mode → 走 handler 的 assisted options 分支。
  const messages = buildDebriefMessages(fixture.turns, profile, {
    practiceMode: fixture.practiceMode,
    temperatureScore: fixture.temperatureScore,
    familiarityScore: fixture.familiarityScore,
    partnerState: fixture.partnerMood
      ? { mood: fixture.partnerMood, innerThought: "" }
      : null,
    sceneContext: null,
    memorySummary: fixture.memorySummary,
    gameState: fixture.gameState,
    appliedHintTurns: fixture.appliedHintTurns,
  });
  const evidence = hintTrustedFactualEvidence({
    profile,
    practiceMode: fixture.practiceMode,
    sceneContext: null,
    memorySummary: fixture.memorySummary,
  });
  const parseOptions = {
    allowGameBreakdown: fixture.practiceMode === "game",
    requireCompleteCard: true,
    turns: fixture.turns,
    appliedHintTurns: fixture.appliedHintTurns,
    repairPreservedHintCritique: false,
    sharedFactualEvidence: evidence.shared,
    partnerFactualEvidence: evidence.partner,
    trustedFactClaims: evidence.claims,
    enforceGeneratedQuality: true,
  } as const;
  const startedAt = performance.now();
  try {
    const outcome = await runSingleShot<DebriefCard>({
      callClaude: opts.caller,
      apiKey: opts.apiKey,
      messages,
      forcedTool: {
        name: "emit_debrief_card",
        description:
          "輸出練習拆解卡：總結、亮點、注意點、建議句與邀約評估（Game 模式含拆盤）。",
        inputSchema: DEBRIEF_TOOL_SCHEMA as Record<string, unknown>,
      },
      maxTokens: DEBRIEF_MAX_TOKENS,
      temperature: DEBRIEF_TEMPERATURE,
      perCallTimeoutMs: DEBRIEF_SINGLE_SHOT_TIMEOUT_MS,
      deadlineAtMs: performance.now() + DEBRIEF_REQUEST_DEADLINE_MS,
      now: () => performance.now(),
      models: [CLAUDE_SONNET_MODEL, CLAUDE_HAIKU_MODEL],
      validate: (raw) => parseDebriefCard(raw, { ...parseOptions }),
    });
    return {
      route: fixture.route,
      fixtureId: fixture.id,
      repeatIndex: opts.repeatIndex,
      outcome: outcome.attemptFailures.length === 0
        ? "first_shot"
        : "second_shot",
      model: outcome.model,
      durationMs: Math.round(performance.now() - startedAt),
      attemptFailureCodes: outcome.attemptFailures.map((f) => f.code),
      servedText: debriefServedText(outcome.result),
    };
  } catch (error) {
    if (!(error instanceof SingleShotExhaustedError)) throw error;
    return {
      route: fixture.route,
      fixtureId: fixture.id,
      repeatIndex: opts.repeatIndex,
      outcome: "http_503",
      model: null,
      durationMs: Math.round(performance.now() - startedAt),
      attemptFailureCodes: error.attemptFailures.map((f) => f.code),
      servedText: null,
    };
  }
}

function percentile(sorted: number[], fraction: number): number {
  if (sorted.length === 0) return 0;
  const index = Math.min(
    sorted.length - 1,
    Math.floor(fraction * (sorted.length - 1)),
  );
  return sorted[index];
}

interface RouteSummary {
  route: EvalRoute;
  shots: number;
  p50Ms: number;
  p90Ms: number;
  firstShotCount: number;
  firstShotRate: number;
  secondShotCount: number;
  count503: number;
  gateFailureCounts: Record<string, number>;
}

function summarizeRoute(route: EvalRoute, shots: ShotRecord[]): RouteSummary {
  const routeShots = shots.filter((shot) => shot.route === route);
  const durations = routeShots.map((shot) => shot.durationMs).sort((a, b) =>
    a - b
  );
  const firstShotCount = routeShots.filter((shot) =>
    shot.outcome === "first_shot"
  ).length;
  const gateFailureCounts: Record<string, number> = {};
  for (const shot of routeShots) {
    for (const code of shot.attemptFailureCodes) {
      gateFailureCounts[code] = (gateFailureCounts[code] ?? 0) + 1;
    }
  }
  return {
    route,
    shots: routeShots.length,
    p50Ms: percentile(durations, 0.5),
    p90Ms: percentile(durations, 0.9),
    firstShotCount,
    firstShotRate: routeShots.length === 0
      ? 0
      : firstShotCount / routeShots.length,
    secondShotCount: routeShots.filter((shot) =>
      shot.outcome === "second_shot"
    ).length,
    count503: routeShots.filter((shot) => shot.outcome === "http_503").length,
    gateFailureCounts,
  };
}

function scanLeaks(shots: ShotRecord[]): LeakHit[] {
  const guards: Array<[string, (value: string) => boolean]> = [
    ["INTERNAL_VISIBLE_LABELS", hasVisibleInternalLabelLeak],
    ["L4_UNSAFE_VISIBLE_PATTERNS", hasL4UnsafeVisibleText],
    ["INTERNAL_MECHANISM_PHRASES", hasVisibleTemperatureMechanismLeak],
  ];
  const hits: LeakHit[] = [];
  for (const shot of shots) {
    if (!shot.servedText) continue;
    for (const [field, value] of Object.entries(shot.servedText)) {
      for (const [guard, hasLeak] of guards) {
        if (hasLeak(value)) {
          hits.push({
            route: shot.route,
            fixtureId: shot.fixtureId,
            repeatIndex: shot.repeatIndex,
            field,
            guard,
          });
        }
      }
    }
  }
  return hits;
}

async function main() {
  const { routes, repeat, dryRun } = parseArgs(Deno.args);
  const apiKey = Deno.env.get("CLAUDE_API_KEY") ?? "";
  if (!dryRun && apiKey.length === 0) {
    console.error(
      "缺 CLAUDE_API_KEY（真打 API 用）。要純驗流程請加 --dry-run。",
    );
    Deno.exit(1);
  }

  const shots: ShotRecord[] = [];
  for (const route of routes) {
    const fixtures = FIXTURES_BY_ROUTE[route];
    for (const fixture of fixtures) {
      for (let repeatIndex = 0; repeatIndex < repeat; repeatIndex++) {
        const caller: SingleShotClaudeCaller = dryRun
          ? makeFakeCallClaude(fixture)
          : callClaude;
        const shot = route.endsWith("_hint")
          ? await runHintShot({ fixture, repeatIndex, caller, apiKey })
          : await runDebriefShot({ fixture, repeatIndex, caller, apiKey });
        shots.push(shot);
        const status = shot.outcome === "first_shot"
          ? "OK(1st)"
          : shot.outcome === "second_shot"
          ? "OK(2nd)"
          : "503";
        console.log(
          `[${route}] ${fixture.id} #${repeatIndex + 1} ${status} ` +
            `${shot.durationMs}ms` +
            (shot.attemptFailureCodes.length > 0
              ? ` failures=${shot.attemptFailureCodes.join(",")}`
              : ""),
        );
      }
    }
  }

  const summaries = routes.map((route) => summarizeRoute(route, shots));
  const leaks = scanLeaks(shots);
  const gameHintSamples = shots
    .filter((shot) => shot.route === "game_hint" && shot.servedText)
    .map((shot) => ({
      fixtureId: shot.fixtureId,
      repeatIndex: shot.repeatIndex,
      servedText: shot.servedText,
    }));

  // ── console 摘要表 ─────────────────────────────────────────────────────
  console.log("\n=== 四路摘要（三軸 gate：速度 p50/p90、首發成功率、503）===");
  console.log(
    "route".padEnd(18) + "shots".padEnd(7) + "p50(s)".padEnd(8) +
      "p90(s)".padEnd(8) + "1st%".padEnd(7) + "2nd".padEnd(5) + "503",
  );
  for (const summary of summaries) {
    console.log(
      summary.route.padEnd(18) +
        String(summary.shots).padEnd(7) +
        (summary.p50Ms / 1000).toFixed(1).padEnd(8) +
        (summary.p90Ms / 1000).toFixed(1).padEnd(8) +
        `${Math.round(summary.firstShotRate * 100)}%`.padEnd(7) +
        String(summary.secondShotCount).padEnd(5) +
        String(summary.count503),
    );
    const gateEntries = Object.entries(summary.gateFailureCounts);
    if (gateEntries.length > 0) {
      console.log(
        "  gate 打回分佈: " +
          gateEntries.map(([code, count]) => `${code}×${count}`).join("、"),
      );
    }
  }
  console.log(
    leaks.length === 0
      ? `\n詞表洩漏掃描：0 洩漏（掃 ${shots.length} 發 served 文字）`
      : `\n詞表洩漏掃描：發現 ${leaks.length} 筆洩漏！\n` +
        leaks.map((hit) =>
          `  [${hit.route}] ${hit.fixtureId}#${hit.repeatIndex + 1} ` +
          `${hit.field} 觸發 ${hit.guard}`
        ).join("\n"),
  );

  // ── 結果 JSON 落檔 ─────────────────────────────────────────────────────
  const report = {
    startedAt: new Date().toISOString(),
    mode: dryRun ? "dry-run" : "live",
    repeat,
    routes,
    summaries,
    leakScan: { totalServedShots: shots.length, hits: leaks },
    gameHintSamples,
    shots,
  };
  const resultsDir = new URL("./results/", import.meta.url);
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const resultPath = new URL(`${timestamp}.json`, resultsDir);
  try {
    await Deno.mkdir(resultsDir, { recursive: true });
    await Deno.writeTextFile(
      resultPath,
      JSON.stringify(report, null, 2) + "\n",
    );
    console.log(`\n結果 JSON：${resultPath.pathname}`);
  } catch (error) {
    console.warn(
      `\n結果 JSON 落檔失敗（需要 --allow-write）：${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }

  const total503 = summaries.reduce((sum, s) => sum + s.count503, 0);
  const allFirstShotOk = summaries.every((s) => s.firstShotRate >= 0.95);
  if (leaks.length > 0 || total503 > 0 || !allFirstShotOk) {
    console.log("\n結論：有紅燈（詳見上表），依 Batch H2 gate 回去修。");
    Deno.exit(2);
  }
  console.log("\n結論：本次子集三軸全綠（速度 gate 依 H2 表另行人工核對）。");
}

if (import.meta.main) {
  await main();
}

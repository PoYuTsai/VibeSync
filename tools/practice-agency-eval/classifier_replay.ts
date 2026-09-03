// 練習室對話主體意識 Phase 2：分類器回放（報告 §8）。
//
// 拿 run_agency.ts 的既有 artifact（agency-on 那份，同一批已生成的回覆），對每個
// probe 回合重跑一次 production 的 buildTurnClassifierMessages（agencyEnabled:
// true）＋真實 DeepSeek 呼叫＋parseTurnClassification（requireCoherence:
// true），量：
// - coherence 分佈（整體與逐情境）；
// - disconnected／repetitive 是否仍拿到正 heat（套 applyCoherenceDeltaCap 之後
//   必須是 0%——這是這輪的 gate）；
// - A01／A09（有效短答對照組）是不是仍維持 connected 且 connection 不是
//   defensive／overstepped。
//
// 不寫回 artifact、不影響任何 production 狀態，純只讀 replay。
//
// 用法：
//   deno run --allow-env --allow-read --allow-write --allow-net=api.deepseek.com \
//     tools/practice-agency-eval/classifier_replay.ts <artifact.json> \
//     [--out=<file>] [--concurrency=8]

import { callDeepSeek } from "../../supabase/functions/practice-chat/deepseek.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  applyCoherenceDeltaCap,
  applyLearningClassification,
  buildTurnClassifierMessages,
  parseTurnClassification,
} from "../../supabase/functions/practice-chat/temperature.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import { readDeepSeekKey } from "./run_agency.ts";

interface ArtifactTurn {
  readonly role: "user" | "ai";
  readonly userText: string;
  readonly reply: string;
  readonly scripted: boolean;
  readonly probe: { readonly id: string } | null;
}
interface ArtifactSession {
  readonly profileId: string;
  readonly difficulty: string;
  readonly scenarioId: string;
  readonly repeat: number;
  readonly turns: readonly ArtifactTurn[];
  readonly error?: string;
}

function flag(name: string, fallback: string): string {
  return Deno.args.find((a) => a.startsWith(`--${name}=`))?.slice(
    name.length + 3,
  ) ?? fallback;
}

interface ReplayRow {
  scenarioId: string;
  probeId: string;
  profileId: string;
  coherence: string;
  aiChallengedThisTurn: boolean;
  connection: string;
  heatDelta: number;
  cappedHeatDelta: number;
  capApplied: string;
  error: string | null;
  /** 只有解析失敗時才存：模型原始輸出，用來看失敗形態（Phase 2.6 診斷用）。 */
  raw?: string;
}

async function main() {
  const artifactPath = Deno.args.find((a) => !a.startsWith("--"));
  if (!artifactPath) {
    throw new Error("用法：classifier_replay.ts <artifact.json>");
  }
  const artifact = JSON.parse(await Deno.readTextFile(artifactPath));
  const sessions = (artifact.results as ArtifactSession[]).filter((s) =>
    !s.error
  );
  const apiKey = await readDeepSeekKey();
  const concurrency = Number.parseInt(flag("concurrency", "8"), 10);
  const outPath = flag(
    "out",
    artifactPath.replace(/\.json$/, "-classifier-replay.json"),
  );

  // 展開：每個 probe 回合一個 job，帶上重建到那一輪為止的逐字稿。
  const jobs: {
    profileId: string;
    difficulty: string;
    scenarioId: string;
    probeId: string;
    turns: PracticeTurn[];
    reply: string;
  }[] = [];
  for (const s of sessions) {
    const turns: PracticeTurn[] = [];
    for (const t of s.turns) {
      if (t.role === "ai") {
        turns.push({ role: "ai", text: t.reply });
        continue;
      }
      // role "user"：先把玩家這句放進逐字稿，reply 是她這輪的回覆——分類器要
      // 評的是「玩家這句」，reply 只當 assistantReplyAfterUser 證據，不先併入
      // turns（跟 handler.ts／buildTurnClassifierMessages 的呼叫慣例一致）。
      if (t.probe) {
        jobs.push({
          profileId: s.profileId,
          difficulty: s.difficulty,
          scenarioId: s.scenarioId,
          probeId: t.probe.id,
          turns: [...turns, { role: "user", text: t.userText }],
          reply: t.reply,
        });
      }
      turns.push({ role: "user", text: t.userText });
      turns.push({ role: "ai", text: t.reply });
    }
  }

  // --limit=N：等間隔抽樣（不是取前 N 筆），小規模診斷才涵蓋得到所有情境。
  const limit = Number.parseInt(flag("limit", "0"), 10);
  const sampled = limit > 0 && limit < jobs.length
    ? jobs.filter((_, i) => i % Math.ceil(jobs.length / limit) === 0)
    : jobs;
  jobs.length = 0;
  jobs.push(...sampled);

  const rows: ReplayRow[] = [];
  let next = 0;
  let done = 0;
  const worker = async () => {
    while (next < jobs.length) {
      const job = jobs[next++];
      const profile = resolvePracticeProfile({
        profileId: job.profileId,
        difficulty: job.difficulty as "easy" | "normal" | "challenge",
      });
      let raw = "";
      try {
        const messages = buildTurnClassifierMessages({
          turns: job.turns,
          profile,
          heatScore: 40,
          familiarityScore: 10,
          assistantReply: job.reply,
          agencyEnabled: true,
        });
        raw = await callDeepSeek({
          apiKey,
          messages,
          maxTokens: 400,
          temperature: 0,
          timeoutMs: 30_000,
          jsonMode: true,
        });
        const classification = parseTurnClassification(raw, {
          requireCoherence: true,
        });
        const judgement = applyLearningClassification(
          { heatScore: 40, familiarityScore: 10 },
          classification,
        );
        const { judgement: capped, capApplied } = applyCoherenceDeltaCap(
          judgement,
          40,
          10,
          classification.coherence ?? null,
          {
            // 回放沒有真的跨輪 agency state，這兩個結構欄位只是佔位——
            // cap 現在以分類器的 coherence 為準（Codex round-2 P1-1），
            // 結構近似只在分類器沒給 coherence 時才會被用到。
            repeatedExactToken: false,
            unresolvedCount: 0,
          },
        );
        rows.push({
          scenarioId: job.scenarioId,
          probeId: job.probeId,
          profileId: job.profileId,
          coherence: classification.coherence ?? "connected",
          aiChallengedThisTurn: classification.aiChallengedThisTurn ?? false,
          connection: classification.connection,
          heatDelta: judgement.delta,
          cappedHeatDelta: capped.delta,
          capApplied,
          error: null,
        });
      } catch (e) {
        rows.push({
          scenarioId: job.scenarioId,
          probeId: job.probeId,
          profileId: job.profileId,
          coherence: "error",
          aiChallengedThisTurn: false,
          connection: "error",
          heatDelta: 0,
          cappedHeatDelta: 0,
          capApplied: "none",
          error: e instanceof Error ? e.message : String(e),
          raw,
        });
      }
      done++;
      if (done % 40 === 0) {
        console.error(`[classifier-replay] ${done}/${jobs.length}`);
      }
    }
  };
  await Promise.all(Array.from({ length: concurrency }, worker));

  const ok = rows.filter((r) => !r.error);
  const coherenceDist: Record<string, number> = {};
  for (const r of ok) {
    coherenceDist[r.coherence] = (coherenceDist[r.coherence] ?? 0) + 1;
  }
  const disconnectedOrRepetitive = ok.filter((r) =>
    r.coherence === "disconnected" || r.coherence === "repetitive"
  );
  const positiveHeatAfterCap = disconnectedOrRepetitive.filter((r) =>
    r.cappedHeatDelta > 0
  );
  const a01a09 = ok.filter((r) =>
    r.probeId.startsWith("A01") || r.probeId.startsWith("A09")
  );
  const a01a09NotConnected = a01a09.filter((r) => r.coherence !== "connected");
  const a01a09BadConnection = a01a09.filter((r) =>
    r.connection === "defensive" || r.connection === "overstepped"
  );

  const byScenario: Record<string, Record<string, number>> = {};
  for (const sc of [...new Set(ok.map((r) => r.scenarioId))].sort()) {
    const sub = ok.filter((r) => r.scenarioId === sc);
    const dist: Record<string, number> = { n: sub.length };
    for (const r of sub) dist[r.coherence] = (dist[r.coherence] ?? 0) + 1;
    byScenario[sc] = dist;
  }

  const summary = {
    source: artifactPath,
    total: rows.length,
    errors: rows.length - ok.length,
    coherenceDist,
    // gate：disconnected／repetitive 套 cap 之後絕不能有正 heat。
    disconnectedOrRepetitiveN: disconnectedOrRepetitive.length,
    positiveHeatAfterCapN: positiveHeatAfterCap.length,
    positiveHeatAfterCapRate: disconnectedOrRepetitive.length
      ? Math.round(
        (positiveHeatAfterCap.length / disconnectedOrRepetitive.length) *
          1000,
      ) / 10
      : null,
    // gate：A01／A09 有效短答仍應維持 connected，且不能被判 defensive／overstepped。
    a01a09N: a01a09.length,
    a01a09NotConnectedN: a01a09NotConnected.length,
    a01a09BadConnectionN: a01a09BadConnection.length,
    byScenario,
  };
  await Deno.writeTextFile(
    outPath,
    JSON.stringify({ summary, rows }, null, 2) + "\n",
  );
  console.log(JSON.stringify(summary, null, 2));
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(
      `[classifier-replay] 致命錯誤：${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    Deno.exit(1);
  });
}

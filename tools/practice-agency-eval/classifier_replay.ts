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
import { buildBakeoffContextFixture } from "../practice-difficulty-bakeoff/bakeoff.ts";
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
  /** Phase 3.4：她這一輪有沒有捏造跟玩家的共同過去（認識／共同朋友／一起經歷）。 */
  sharedPastClaim: boolean;
  /**
   * Codex R1 P2：這個 false 是 repair 出來的（模型漏答／吐非布林），不是模型
   * 真的判「沒捏造」——盛行率的分母要扣掉這些筆。
   */
  sharedPastClaimRepaired: boolean;
  /** Phase 3.6：她這一輪替自己補的設定有沒有跟來源矛盾、或明顯迎合玩家丟的詞。 */
  accommodatingSelfFact: boolean;
  accommodatingSelfFactRepaired: boolean;
  connection: string;
  heatDelta: number;
  cappedHeatDelta: number;
  familiarityDelta: number;
  cappedFamiliarityDelta: number;
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
  // `[...jobs]` 不能省：不抽樣時 sampled 若直接指向 jobs，下面清空 jobs 會把
  // 它一起清掉（實際踩過，整支 replay 回 total 0）。
  const sampled = limit > 0 && limit < jobs.length
    ? jobs.filter((_, i) => i % Math.ceil(jobs.length / limit) === 0)
    : [...jobs];
  jobs.length = 0;
  jobs.push(...sampled);
  if (jobs.length === 0) throw new Error("classifier_replay_no_jobs");

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
        // Phase 3.5：跟 run_agency 生成時同一份 fixture 的記憶／貼文餵分類器。
        const fixture = buildBakeoffContextFixture(profile);
        const messages = buildTurnClassifierMessages({
          turns: job.turns,
          profile,
          heatScore: 40,
          familiarityScore: 10,
          assistantReply: job.reply,
          agencyEnabled: true,
          memorySummary: fixture.memorySummary,
          herRecentMoments: fixture.herRecentMoments,
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
        const { judgement: capped, capApplied } = applyCoherenceDeltaCap({
          judgement: judgement,
          currentHeat: 40,
          currentFamiliarity: 10,
          coherence: classification.coherence ?? null,
          structural: {
            // 回放沒有真的跨輪 agency state，這兩個結構欄位只是佔位——
            // cap 現在以分類器的 coherence 為準（Codex round-2 P1-1），
            // 結構近似只在分類器沒給 coherence 時才會被用到。
            repeatedExactToken: false,
            unresolvedCount: 0,
          },
          sharedPastClaim: classification.sharedPastClaim,
          accommodatingSelfFact: classification.accommodatingSelfFact,
        });
        rows.push({
          scenarioId: job.scenarioId,
          probeId: job.probeId,
          profileId: job.profileId,
          coherence: classification.coherence ?? "connected",
          aiChallengedThisTurn: classification.aiChallengedThisTurn ?? false,
          sharedPastClaim: classification.sharedPastClaim ?? false,
          sharedPastClaimRepaired:
            classification.repairedFields?.includes("sharedPastClaim") ?? false,
          accommodatingSelfFact: classification.accommodatingSelfFact ?? false,
          accommodatingSelfFactRepaired:
            classification.repairedFields?.includes("accommodatingSelfFact") ??
              false,
          connection: classification.connection,
          heatDelta: judgement.delta,
          cappedHeatDelta: capped.delta,
          familiarityDelta: judgement.familiarityDelta,
          cappedFamiliarityDelta: capped.familiarityDelta,
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
          sharedPastClaim: false,
          sharedPastClaimRepaired: false,
          accommodatingSelfFact: false,
          accommodatingSelfFactRepaired: false,
          connection: "error",
          heatDelta: 0,
          cappedHeatDelta: 0,
          familiarityDelta: 0,
          cappedFamiliarityDelta: 0,
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
  // Phase 3.4：捏造共同過去的盛行率＋套 cap 之後還拿到正分的筆數（gate）。
  // Codex R1 P2：cap 壓的是 heat **與** familiarity 兩條，gate 只看 heat 會
  // 漏掉「heat 壓到 0、familiarity 還加分」那一半。任一為正就算沒壓住。
  const sharedPast = ok.filter((r) => r.sharedPastClaim);
  const sharedPastPositiveDelta = sharedPast.filter((r) =>
    r.cappedHeatDelta > 0 || r.cappedFamiliarityDelta > 0
  );
  // Codex R1 P2：repair 出來的 false 不是模型的判斷，盛行率分母只算模型真的
  // 吐了布林值的那些筆（explicit）。
  const sharedPastRepaired = ok.filter((r) => r.sharedPastClaimRepaired);
  const sharedPastExplicitN = ok.length - sharedPastRepaired.length;
  // Phase 3.6：迎合式補設定同一套算法（explicit 分母、任一 delta 為正＝沒壓住）。
  const accommodating = ok.filter((r) => r.accommodatingSelfFact);
  const accommodatingPositiveDelta = accommodating.filter((r) =>
    r.cappedHeatDelta > 0 || r.cappedFamiliarityDelta > 0
  );
  const accommodatingRepaired = ok.filter((r) =>
    r.accommodatingSelfFactRepaired
  );
  const accommodatingExplicitN = ok.length - accommodatingRepaired.length;
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
    // Phase 3.4：捏造共同過去（黃金法則明文禁止）的盛行率；套 cap 之後
    // 必須 0 筆還拿得到正 heat 或正 familiarity。
    // `sharedPastClaimRate` 的分母是 **explicit**（模型真的吐了布林值）那些筆，
    // 不是全部成功筆數——repair 出來的 false 是「協定壞掉」，不是「判斷沒捏造」，
    // 混進分母會讓盛行率被系統性稀釋。
    sharedPastClaimN: sharedPast.length,
    sharedPastClaimExplicitN: sharedPastExplicitN,
    sharedPastClaimRepairedN: sharedPastRepaired.length,
    sharedPastClaimRate: sharedPastExplicitN
      ? Math.round((sharedPast.length / sharedPastExplicitN) * 1000) / 10
      : null,
    sharedPastPositiveDeltaN: sharedPastPositiveDelta.length,
    accommodatingSelfFactN: accommodating.length,
    accommodatingSelfFactExplicitN: accommodatingExplicitN,
    accommodatingSelfFactRepairedN: accommodatingRepaired.length,
    accommodatingSelfFactRate: accommodatingExplicitN
      ? Math.round((accommodating.length / accommodatingExplicitN) * 1000) / 10
      : null,
    accommodatingPositiveDeltaN: accommodatingPositiveDelta.length,
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

// 練習室寫實差異化 PR-4：partnerMood 分類器回放（規格 §7.2）。
//
// 拿既有 style 黑箱產物（同一批 assistant replies），對同一段對話各跑一次
// 「舊分類器 prompt」與「新分類器 prompt（帶她的個人基準）」，比較 partnerMood
// 分佈——尤其是「短句型」女孩在非越界情境被判 guarded／annoyed 的比例。
// 沒有人工標記，所以這只能量「解讀有沒有往基準靠」，不能量準確度。
//
// 用法：
//   deno run --allow-env --allow-read --allow-write --allow-net=api.deepseek.com \
//     tools/practice-reply-style-eval/coach_replay.ts <artifact.json> [--out=<file>] [--concurrency=6]

import { callDeepSeek } from "../../supabase/functions/practice-chat/deepseek.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  buildTurnClassifierMessages,
  parseTurnClassification,
} from "../../supabase/functions/practice-chat/temperature.ts";
import { replyStyleFor } from "../../supabase/functions/practice-chat/reply_style.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import { DEFAULT_PROFILE_IDS, readDeepSeekKey } from "./run_baseline.ts";

interface Round {
  userText: string;
  reply: string;
}
interface SessionRecord {
  profileId: string;
  personaId: string;
  scenarioId: string;
  repeat: number;
  turns: Round[];
  probe: Round;
}

const NON_BOUNDARY = new Set([
  "opening",
  "interrogation",
  "interest_hit",
  "daily_share",
  "vulnerability",
  "light_joke",
  "failed_joke",
  "disagreement",
]);

function flag(name: string, fallback: string): string {
  return Deno.args.find((a) => a.startsWith(`--${name}=`))?.slice(
    name.length + 3,
  ) ?? fallback;
}

async function main() {
  const artifactPath = Deno.args.find((a) => !a.startsWith("--"));
  if (!artifactPath) throw new Error("用法：coach_replay.ts <artifact.json>");
  const artifact = JSON.parse(await Deno.readTextFile(artifactPath));
  const results = artifact.results as SessionRecord[];
  const profiles = new Set<string>(DEFAULT_PROFILE_IDS);
  const sessions = results.filter((r) =>
    profiles.has(r.profileId) && r.repeat === 1
  );
  const apiKey = await readDeepSeekKey();
  const concurrency = Number.parseInt(flag("concurrency", "6"), 10);
  const outPath = flag(
    "out",
    artifactPath.replace(/\.json$/, "-coach-replay.json"),
  );

  type Row = {
    profileId: string;
    personaId: string;
    scenarioId: string;
    shortStyle: boolean;
    variant: "baseline" | "withBaseline";
    partnerMood: string | null;
    error: string | null;
  };
  const rows: Row[] = [];
  const jobs = sessions.flatMap((s) =>
    (["baseline", "withBaseline"] as const).map((variant) => ({ s, variant }))
  );
  let next = 0;
  let done = 0;
  const worker = async () => {
    while (next < jobs.length) {
      const { s, variant } = jobs[next++];
      const profile = resolvePracticeProfile({ profileId: s.profileId });
      const style = replyStyleFor(s.profileId);
      const shortStyle = style !== null &&
        (style.turnTaking.bubbleRange[1] <= 1 ||
          style.turnTaking.charRange[1] <= 14);
      const turns: PracticeTurn[] = [];
      for (const r of s.turns) {
        turns.push({ role: "user", text: r.userText });
        turns.push({ role: "ai", text: r.reply });
      }
      turns.push({ role: "user", text: s.probe.userText });
      const messages = buildTurnClassifierMessages({
        turns,
        profile,
        heatScore: 40,
        familiarityScore: 10,
        assistantReply: s.probe.reply,
        replyStyle: variant === "withBaseline" ? style : null,
      });
      let partnerMood: string | null = null;
      let error: string | null = null;
      try {
        const raw = await callDeepSeek({
          apiKey,
          messages,
          maxTokens: 400,
          temperature: 0,
          timeoutMs: 30_000,
        });
        partnerMood = parseTurnClassification(raw).partnerMood ?? null;
      } catch (e) {
        error = e instanceof Error ? e.message : String(e);
      }
      rows.push({
        profileId: s.profileId,
        personaId: s.personaId,
        scenarioId: s.scenarioId,
        shortStyle,
        variant,
        partnerMood,
        error,
      });
      done++;
      if (done % 40 === 0) {
        console.error(`[coach-replay] ${done}/${jobs.length}`);
      }
    }
  };
  await Promise.all(Array.from({ length: concurrency }, worker));

  const summarize = (filter: (r: Row) => boolean) => {
    const out: Record<string, Record<string, number>> = {};
    for (const variant of ["baseline", "withBaseline"]) {
      const sub = rows.filter((r) => r.variant === variant && filter(r));
      const dist: Record<string, number> = {};
      for (const r of sub) {
        const k = r.error ? "error" : (r.partnerMood ?? "null");
        dist[k] = (dist[k] ?? 0) + 1;
      }
      const n = sub.length || 1;
      const guarded = ((dist.guarded ?? 0) + (dist.annoyed ?? 0)) / n;
      out[variant] = {
        n: sub.length,
        guardedOrAnnoyedRate: Math.round(guarded * 1000) / 10,
        ...dist,
      };
    }
    return out;
  };
  const summary = {
    all: summarize(() => true),
    nonBoundaryShortStyle: summarize((r) =>
      r.shortStyle && NON_BOUNDARY.has(r.scenarioId)
    ),
    nonBoundaryOtherStyle: summarize((r) =>
      !r.shortStyle && NON_BOUNDARY.has(r.scenarioId)
    ),
    // 邀約／越界／記憶類（不是全是安全越界；逐情境看下面 byScenario）
    inviteOrBoundaryScenarios: summarize((r) =>
      !NON_BOUNDARY.has(r.scenarioId)
    ),
    byScenario: Object.fromEntries(
      [...new Set(rows.map((r) => r.scenarioId))].sort().map((
        sc,
      ) => [sc, summarize((r) => r.scenarioId === sc)]),
    ),
  };
  await Deno.writeTextFile(
    outPath,
    JSON.stringify(
      { source: artifactPath, sessions: sessions.length, summary, rows },
      null,
      2,
    ),
  );
  console.log(JSON.stringify(summary, null, 2));
}

if (import.meta.main) await main();

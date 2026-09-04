// Phase 4.2（Codex R2 U）：把 (A) 診斷的 15 筆跨輪立場失敗探針，逐筆輸出
// `{beforeBubbles, firstBubbleQuestion, afterBubbles, classification}` 的機器
// 可讀結果，讓 truncate 三分統計（改善／不變／惡化）可重現。
//
// 純離線：分類走 production 的 `truncateAgencyShape`／`isQuestionText`，
// **不打模型**；失敗探針集合則由 `evaluate_agency.ts` 同一套配對條件重算。
// `orderedActs`（challenge／guess／accept／other）是人工標註，寫在下面的表裡，
// 本工具只負責把它跟機器輸出綁在同一筆。
//
//   deno run --allow-read --allow-write --allow-env \
//     tools/practice-agency-eval/stance_bubbles.ts \
//     <run-artifact.json> <judge.json> <out.json>

import {
  agencyPolicyFor,
  agencyThresholdsFor,
  detectAgencyEvidence,
  isQuestionText,
  truncateAgencyShape,
} from "../../supabase/functions/practice-chat/conversation_agency.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import { AGENCY_PROBES } from "./scenarios.ts";
import type { JudgedProbe } from "./evaluate_agency.ts";

const PROBE_ORDER = new Map(AGENCY_PROBES.map((p, i) => [p.id, i]));

/** 人工標註的逐泡泡 ordered acts（計畫檔 Phase 4.2 節的表格，逐筆對得上）。 */
const ORDERED_ACTS: Record<string, readonly string[]> = {
  "practice_girl_064|A06|3": ["challenge+guess"],
  "practice_girl_083|A06|1": ["guess", "challenge"],
  "practice_girl_083|A06|3": ["guess", "guess", "challenge"],
  "practice_girl_004|A06|1": ["guess"],
  "practice_girl_089|A06|3": ["guess"],
  "practice_girl_006|A06|3": ["challenge", "other", "guess"],
  "practice_girl_091|A06|1": ["guess", "challenge"],
  "practice_girl_064|A14|2": ["challenge", "other", "guess"],
  "practice_girl_007|A14|3": ["other", "challenge", "challenge"],
  "practice_girl_002|A14|1": ["challenge", "challenge", "guess"],
  "practice_girl_002|A14|2": ["guess", "challenge", "guess"],
  "practice_girl_083|A14|2": ["challenge", "guess"],
  "practice_girl_012|A14|2": ["challenge", "guess"],
  "practice_girl_013|A14|2": ["challenge", "guess", "other"],
  "practice_girl_061|A14|3": ["challenge", "other+guess"],
};

interface ArtifactTurn {
  readonly role: "user" | "ai";
  readonly userText: string;
  readonly reply: string;
  readonly probe: { readonly id: string } | null;
}

const bubblesOf = (text: string) =>
  text.split("\n").map((p) => p.trim()).filter(Boolean);

/**
 * truncate 三分：`improved`＝砍掉的泡泡裡有猜測而留下的第一顆不是猜測；
 * `worsened`＝留下的第一顆是猜測、砍掉的裡面有質疑；`unchanged`＝沒砍。
 */
export function classifyTruncateEffect(
  ordered: readonly string[],
  dropped: number,
): "improved" | "unchanged" | "worsened" {
  if (dropped === 0) return "unchanged";
  const kept = ordered[0] ?? "other";
  const cut = ordered.slice(1);
  const keptIsGuess = kept.includes("guess") && !kept.includes("challenge");
  const cutHasChallenge = cut.some((a) => a.includes("challenge"));
  const cutHasGuess = cut.some((a) => a.includes("guess"));
  if (keptIsGuess && cutHasChallenge) return "worsened";
  if (!keptIsGuess && cutHasGuess) return "improved";
  return "unchanged";
}

async function main(): Promise<void> {
  const [runPath, judgePath, outPath] = Deno.args.filter((a) =>
    !a.startsWith("--")
  );
  if (!runPath || !judgePath || !outPath) {
    console.error(
      "用法：stance_bubbles.ts <run-artifact.json> <judge.json> <out.json>",
    );
    Deno.exit(2);
  }
  const art = JSON.parse(await Deno.readTextFile(runPath));
  const judge = JSON.parse(await Deno.readTextFile(judgePath));

  // 1) 用 evaluate_agency 的同一套條件挑出失敗配對。
  const bySession = new Map<string, JudgedProbe[]>();
  for (const p of judge.results as JudgedProbe[]) {
    if (!p.labels) continue;
    const key =
      `${p.mode}|${p.difficulty}|${p.profileId}|${p.scenarioId}|${p.repeat}`;
    bySession.set(key, [...(bySession.get(key) ?? []), p]);
  }
  const failures = new Set<string>();
  for (const list of bySession.values()) {
    const ordered = [...list].sort((a, b) =>
      (PROBE_ORDER.get(a.probeId) ?? 0) - (PROBE_ORDER.get(b.probeId) ?? 0)
    );
    for (let i = 1; i < ordered.length; i++) {
      const prev = ordered[i - 1];
      const cur = ordered[i];
      const spec = AGENCY_PROBES.find((s) => s.id === cur.probeId);
      if (!spec?.kinds.includes("stance_followup")) continue;
      if (!prev.labels!.clarify_or_challenge) continue;
      if (
        cur.labels!.adopted_without_asking || cur.labels!.asked_with_guess
      ) {
        failures.add(
          `${cur.profileId}|${cur.scenarioId}|${cur.repeat}|${cur.probeId}`,
        );
      }
    }
  }

  // 2) 對每一筆重算 agency application，跑 production 的 truncateAgencyShape。
  const rows = [];
  for (const s of art.results) {
    const turns: PracticeTurn[] = [];
    for (const t of s.turns as ArtifactTurn[]) {
      if (t.role === "ai") {
        turns.push({ role: "ai", text: t.reply });
        continue;
      }
      turns.push({ role: "user", text: t.userText });
      const key = t.probe
        ? `${s.profileId}|${s.scenarioId}|${s.repeat}|${t.probe.id}`
        : null;
      if (key && failures.has(key)) {
        const decision = agencyPolicyFor(
          detectAgencyEvidence(turns, null),
          agencyThresholdsFor(s.difficulty, s.mode === "game"),
        );
        const agency = {
          decision,
          applied: decision.situation !== null,
          enabled: true,
          profile: null,
        };
        const before = bubblesOf(t.reply);
        const { text, dropped } = truncateAgencyShape(t.reply, agency);
        const sessionKey = `${s.profileId}|${s.scenarioId}|${s.repeat}`;
        const orderedActs = ORDERED_ACTS[sessionKey] ?? [];
        rows.push({
          sessionKey,
          probeId: t.probe!.id,
          profileId: s.profileId,
          scenarioId: s.scenarioId,
          repeat: s.repeat,
          allowedActSetId: decision.allowedActSetId,
          policyMode: decision.policyMode,
          utteranceShape: decision.evidence.utteranceShape,
          unresolvedCount: decision.evidence.unresolvedCount,
          beforeBubbles: before,
          firstBubbleQuestion: before.length > 0
            ? isQuestionText(before[0])
            : false,
          afterBubbles: bubblesOf(text),
          dropped,
          orderedActs,
          classification: classifyTruncateEffect(orderedActs, dropped),
        });
      }
      turns.push({ role: "ai", text: t.reply });
    }
  }
  rows.sort((a, b) => a.sessionKey.localeCompare(b.sessionKey));

  const tally = { improved: 0, unchanged: 0, worsened: 0 };
  for (const r of rows) tally[r.classification]++;
  await Deno.writeTextFile(
    outPath,
    JSON.stringify(
      {
        tool: "practice-agency-eval/stance_bubbles",
        sourceRun: runPath,
        sourceJudge: judgePath,
        note:
          "orderedActs 是人工標註（計畫檔 Phase 4.2 節的逐泡泡表），其餘欄位為機器輸出",
        failures: rows.length,
        truncateTally: tally,
        rows,
      },
      null,
      2,
    ) + "\n",
  );
  console.error(
    `[stance_bubbles] ${rows.length} 筆｜改善 ${tally.improved}／不變 ${tally.unchanged}／惡化 ${tally.worsened} → ${outPath}`,
  );
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(e instanceof Error ? e.stack ?? e.message : String(e));
    Deno.exit(1);
  });
}

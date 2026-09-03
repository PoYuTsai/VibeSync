// 練習室對話主體意識 Phase 2.6：把 judge 標籤按「這一輪走的是哪一條 agency
// policy 路徑」拆開（純函式，不打網路）。
//
// 為什麼需要：Phase 2.5 的 `asked_with_guess` 卡在 18.6% 不動，但「有問但夾帶
// 猜測」在不同 policy 路徑下是完全不同的東西——forced `ask_intent`（planner
// 指定只問一句）夾猜測是真失敗；`NO_OVERRIDE`（agency 這一輪根本沒介入，例如
// 有效短答）夾猜測則跟 agency 無關。不先拆開就下第二刀，等於對著混合分母調參。
//
// 作法：run artifact 的每一輪都帶著原始 turn，policy 是**純函式**
// （detectAgencyEvidence → agencyPolicyFor），所以可以離線重算，不必重跑黑箱，
// 舊 artifact 也適用。standard 模式 agencyState 恆為 null（production 同）；
// `--state=1` 跑出來的 artifact 這裡只能算結構近似，會在輸出標註。
//
//   deno run --allow-read tools/practice-agency-eval/policy_breakdown.ts \
//     <run-artifact.json> <judge.json> [--label=asked_with_guess]

import {
  agencyPolicyFor,
  agencyThresholdsFor,
  detectAgencyEvidence,
} from "../../supabase/functions/practice-chat/conversation_agency.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import type { AgencyLabel } from "./scenarios.ts";
import type { JudgedProbe, RawAgencyLabels } from "./evaluate_agency.ts";

interface ArtifactTurn {
  readonly role: "user" | "ai";
  readonly userText: string;
  readonly reply: string;
  readonly scripted?: boolean;
  readonly probe: { readonly id: string } | null;
}
interface ArtifactSession {
  readonly profileId: string;
  readonly scenarioId: string;
  readonly repeat: number;
  readonly difficulty: string;
  readonly mode: string;
  readonly turns: readonly ArtifactTurn[];
  readonly error?: string;
}

/** 一個探針走到的 policy 路徑（telemetry 上的三分法）。 */
export type PolicyPath = "forced" | "bounded" | "no_override";

export function policyPathOf(
  turns: readonly ArtifactTurn[],
  probeIndex: number,
  difficulty: string,
  mode: string,
): { path: PolicyPath; forcedAct: string; actSetId: string } {
  const history: PracticeTurn[] = [];
  for (let i = 0; i < probeIndex; i++) {
    const t = turns[i];
    if (t.role === "ai") {
      history.push({ role: "ai", text: t.reply });
      continue;
    }
    history.push({ role: "user", text: t.userText });
    history.push({ role: "ai", text: t.reply });
  }
  history.push({ role: "user", text: turns[probeIndex].userText });
  const decision = agencyPolicyFor(
    detectAgencyEvidence(history, null),
    agencyThresholdsFor(
      difficulty as "easy" | "normal" | "challenge",
      mode === "game",
    ),
  );
  return {
    path: decision.situation === null
      ? "no_override"
      : decision.policyMode === "forced"
      ? "forced"
      : "bounded",
    forcedAct: decision.forcedAct ?? "-",
    actSetId: decision.allowedActSetId,
  };
}

interface Row {
  readonly scenarioId: string;
  readonly probeId: string;
  readonly path: PolicyPath;
  readonly forcedAct: string;
  readonly actSetId: string;
  readonly hit: boolean;
}

export function buildRows(
  artifact: { results: readonly ArtifactSession[] },
  judged: readonly JudgedProbe[],
  label: AgencyLabel,
): Row[] {
  const byKey = new Map<string, JudgedProbe>();
  for (const j of judged) {
    byKey.set(`${j.profileId}|${j.scenarioId}|${j.repeat}|${j.probeId}`, j);
  }
  const rows: Row[] = [];
  for (const s of artifact.results) {
    if (s.error) continue;
    for (let i = 0; i < s.turns.length; i++) {
      const t = s.turns[i];
      if (!t.probe || t.scripted) continue;
      const j = byKey.get(
        `${s.profileId}|${s.scenarioId}|${s.repeat}|${t.probe.id}`,
      );
      if (!j?.labels) continue;
      const p = policyPathOf(s.turns, i, s.difficulty, s.mode);
      rows.push({
        scenarioId: s.scenarioId,
        probeId: t.probe.id,
        path: p.path,
        forcedAct: p.forcedAct,
        actSetId: p.actSetId,
        hit: (j.labels as RawAgencyLabels)[
          label as keyof RawAgencyLabels
        ] === true,
      });
    }
  }
  return rows;
}

function tally(rows: readonly Row[], key: (r: Row) => string): string[] {
  const groups = new Map<string, { n: number; hits: number }>();
  for (const r of rows) {
    const k = key(r);
    const g = groups.get(k) ?? { n: 0, hits: 0 };
    g.n++;
    if (r.hit) g.hits++;
    groups.set(k, g);
  }
  return [...groups.entries()]
    .sort((a, b) => b[1].hits - a[1].hits || a[0].localeCompare(b[0]))
    .map(([k, g]) =>
      `${k} | ${g.n} | ${g.hits} | ${(g.hits / g.n * 100).toFixed(1)}%`
    );
}

async function main(): Promise<void> {
  const [runPath, judgePath] = Deno.args.filter((a) => !a.startsWith("--"));
  if (!runPath || !judgePath) {
    console.error(
      "用法：policy_breakdown.ts <run-artifact.json> <judge.json> [--label=…]",
    );
    Deno.exit(2);
  }
  const label = (Deno.args.find((a) => a.startsWith("--label="))?.slice(8) ??
    "asked_with_guess") as AgencyLabel;
  const artifact = JSON.parse(await Deno.readTextFile(runPath));
  const judge = JSON.parse(await Deno.readTextFile(judgePath));
  const rows = buildRows(artifact, judge.results, label);
  console.log(`標籤：${label}｜配對成功 ${rows.length} 筆\n`);
  console.log("policy 路徑 | n | 命中 | 比例");
  for (const line of tally(rows, (r) => r.path)) console.log(line);
  console.log("\nact set（forced act） | n | 命中 | 比例");
  for (
    const line of tally(rows, (r) => `${r.actSetId}（${r.forcedAct}）`)
  ) console.log(line);
  console.log("\n情境 × policy 路徑 | n | 命中 | 比例");
  for (
    const line of tally(rows, (r) => `${r.scenarioId} × ${r.path}`)
  ) console.log(line);
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(e instanceof Error ? e.stack ?? e.message : String(e));
    Deno.exit(1);
  });
}

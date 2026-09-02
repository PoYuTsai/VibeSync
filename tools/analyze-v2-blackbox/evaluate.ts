// Phase 3a：把黑箱 artifact 對照語料期望值與 §19.3 可確定性判定的 gates 打分。
// 不打網路、不動 runtime；任一硬 gate 失敗 exit 1，之後 CI 可對已存 artifact 跑。
//   deno run --allow-read tools/analyze-v2-blackbox/evaluate.ts <artifact.json> [--json]
import { CORPUS, type CorpusCase, type MessageDecision } from "./corpus.ts";

export const MAX_LATENCY_MS = 60_000;
export const MAX_OUTPUT_TOKENS = 6_500;
/// §6.3 字面：「不得 4–5 句同開頭」——同開頭卡數達到這個值才算違規。
export const SAME_OPENING_FAIL_AT = 4;
const PLAN_BODY_MARKERS = [
  "threadFrame",
  "branchPool",
  "associationPath",
  "analysis.divergence_plan",
  "analysisDivergencePlan",
];

export interface CaseGateResult {
  readonly id: string;
  readonly family: string;
  readonly decision: string | null;
  readonly failures: readonly string[];
  readonly planObserved: boolean | null;
}

export interface EvalSummary {
  readonly cases: number;
  readonly passed: number;
  readonly failures: Record<string, number>;
  readonly planObservedRate: number | null;
  readonly results: readonly CaseGateResult[];
}

// deno-lint-ignore no-explicit-any
type Artifact = { meta?: Record<string, unknown>; results: any[] };

// deno-lint-ignore no-explicit-any
function usedBranchExceedsCap(r: any): boolean {
  const plan = r.server?.plan;
  if (!plan || !Array.isArray(plan.branchPool)) return false;
  const distance = new Map<string, number>(
    plan.branchPool.map((b: { id: string; semanticDistance: number }) => [
      b.id,
      b.semanticDistance,
    ]),
  );
  const used = new Set<string>();
  const variants = r.server?.linkage?.variants;
  if (variants && typeof variants === "object") {
    for (
      const v of Object.values(variants) as { selectedBranchIds?: string[] }[]
    ) {
      for (const id of v.selectedBranchIds ?? []) used.add(id);
    }
  } else {
    // 舊 artifact 沒存 linkage：退回原始 option 的 selectedBranchIds／計畫指派。
    for (const l of r.rawLines ?? []) {
      if (l?.type === "analysis.reply_option") {
        for (const id of l.selectedBranchIds ?? []) used.add(id);
      }
    }
    for (const id of Object.values(plan.styleBranchIds ?? {})) {
      used.add(id as string);
    }
  }
  const cap = typeof plan.semanticDistanceCap === "number"
    ? plan.semanticDistanceCap
    : Infinity;
  return [...used].some((id) => (distance.get(id) ?? 0) > cap);
}

export function evaluateArtifact(
  artifact: Artifact,
  corpus: readonly CorpusCase[] = CORPUS,
): EvalSummary {
  const expectById = new Map(corpus.map((c) => [c.id, c]));
  const results: CaseGateResult[] = [];
  const failures: Record<string, number> = {};
  let planSends = 0;
  let planObservedCount = 0;
  for (const r of artifact.results) {
    const id = String(r.name).replace(/#\d+$/, "");
    const spec = expectById.get(id);
    const fails: string[] = [];
    const fail = (gate: string) => {
      fails.push(gate);
      failures[gate] = (failures[gate] ?? 0) + 1;
    };
    const decision: string | null = r.decision?.messageDecision ?? null;
    const plan = r.telemetry?.phase0?.divergencePlan ?? null;
    const attribution = plan?.attribution ?? null;
    const usage = r.telemetry?.usage ?? {};
    const options: { style: string }[] = r.replyOptions ?? [];

    if (r.status !== 200 || r.eventTypes?.at(-1) !== "analysis.done") {
      fail("stream_completes");
    }
    if (!spec) fail("case_in_corpus");
    else if (
      decision === null ||
      !spec.expect.messageDecision.includes(decision as MessageDecision)
    ) {
      fail("decision_in_expected_set");
    }
    if (decision && decision !== "send") {
      if (options.length !== 0) fail("no_send_zero_cards");
    }
    if (decision === "send") {
      const styles = options.map((o) => o.style);
      if (styles.length !== 5 || new Set(styles).size !== 5) {
        fail("send_five_unique_styles");
      }
      planSends += 1;
      if (plan?.status === "observed") {
        planObservedCount += 1;
        if (
          plan.sameOpeningCount !== "unknown" &&
          plan.sameOpeningCount >= SAME_OPENING_FAIL_AT
        ) {
          fail("no_four_same_opening");
        }
        if (plan.questionBudgetExceeded === true) fail("question_budget");
        if (plan.newTopicBudgetExceeded === true) fail("new_topic_budget");
        // 距離 cap 只看風格實際用到的枝；pool 裡刻意列出的被否決路徑不算。
        if (usedBranchExceedsCap(r)) fail("used_branch_within_cap");
        // invalid（缺欄／跨風格手法）依 Eric best-effort 定案只是度量；gate 只看
        // 有沒有解析到枝。
        if ((attribution?.unresolvedCount ?? 0) > 0) {
          fail("attribution_resolved");
        }
      }
    }
    const clientText: string = r.clientText ?? "";
    if (PLAN_BODY_MARKERS.some((m) => clientText.includes(m))) {
      fail("client_no_plan_body");
    }
    if (r.elapsedMs > MAX_LATENCY_MS) fail("latency_under_60s");
    if ((usage.output_tokens ?? 0) > MAX_OUTPUT_TOKENS) fail("output_budget");
    results.push({
      id,
      family: spec?.family ?? "?",
      decision,
      failures: fails,
      planObserved: decision === "send" ? plan?.status === "observed" : null,
    });
  }
  return {
    cases: results.length,
    passed: results.filter((r) => r.failures.length === 0).length,
    failures,
    planObservedRate: planSends > 0 ? planObservedCount / planSends : null,
    results,
  };
}

if (import.meta.main) {
  const path = Deno.args.find((a) => !a.startsWith("--"));
  if (!path) {
    console.error("usage: evaluate.ts <artifact.json> [--json]");
    Deno.exit(2);
  }
  const artifact = JSON.parse(await Deno.readTextFile(path)) as Artifact;
  const summary = evaluateArtifact(artifact);
  if (Deno.args.includes("--json")) {
    console.log(JSON.stringify(summary, null, 2));
  } else {
    for (const r of summary.results) {
      console.log(
        `${r.failures.length === 0 ? "PASS" : "FAIL"} ${r.id.padEnd(28)} ${
          String(r.decision).padEnd(20)
        } plan=${r.planObserved ?? "-"} ${r.failures.join(",")}`,
      );
    }
    console.log(
      `\n${summary.passed}/${summary.cases} pass; plan observed rate ${
        summary.planObservedRate === null
          ? "-"
          : (summary.planObservedRate * 100).toFixed(0) + "%"
      }; failures ${JSON.stringify(summary.failures)}`,
    );
  }
  Deno.exit(summary.passed === summary.cases ? 0 : 1);
}

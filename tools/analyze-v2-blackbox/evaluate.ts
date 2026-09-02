// Phase 3a：把黑箱 artifact 對照語料期望值與 §19.3 可確定性判定的 gates 打分。
// 不打網路、不動 runtime；任一硬 gate 失敗 exit 1，之後 CI 可對已存 artifact 跑。
//   deno run --allow-read tools/analyze-v2-blackbox/evaluate.ts <artifact.json> [--json]
import { CORPUS, type CorpusCase, type MessageDecision } from "./corpus.ts";

export const MAX_LATENCY_MS = 60_000;
export const MAX_OUTPUT_TOKENS = 6_500;
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
        if (plan.sameOpeningCount !== "unknown" && plan.sameOpeningCount > 0) {
          fail("no_same_opening");
        }
        if (plan.questionBudgetExceeded === true) fail("question_budget");
        if (plan.newTopicBudgetExceeded === true) fail("new_topic_budget");
        if (plan.branchExceedsCap === true) fail("semantic_distance_cap");
        if ((attribution?.invalidCount ?? 0) > 0) fail("attribution_valid");
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

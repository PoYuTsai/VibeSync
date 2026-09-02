import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { evaluateArtifact } from "./evaluate.ts";
import { CORPUS } from "./corpus.ts";

const send = (name: string, patch: Record<string, unknown> = {}) => ({
  name,
  status: 200,
  elapsedMs: 30_000,
  eventTypes: ["analysis.decision", "analysis.done"],
  decision: { messageDecision: "send" },
  replyOptions: ["extend", "resonate", "tease", "humor", "coldRead"].map((
    style,
  ) => ({ style, message: "m" })),
  telemetry: {
    usage: { output_tokens: 3000 },
    phase0: {
      divergencePlan: {
        status: "observed",
        sameOpeningCount: 0,
        questionBudgetExceeded: false,
        newTopicBudgetExceeded: "unknown",
        branchExceedsCap: false,
        attribution: { invalidCount: 0, unresolvedCount: 0 },
      },
    },
  },
  clientLeak: {},
  clientText: '{"type":"analysis.done"}',
  ...patch,
});

Deno.test("evaluate: a clean send case passes every gate and a no-send case with cards fails", () => {
  const clean = evaluateArtifact({ results: [send("warm_question_back")] });
  assertEquals(clean.passed, 1);
  assertEquals(clean.planObservedRate, 1);
  const bad = evaluateArtifact({
    results: [
      send("boundary_friend_hint", {
        decision: { messageDecision: "acknowledge_and_stop" },
      }),
    ],
  });
  assertEquals(bad.passed, 0);
  assert(bad.results[0].failures.includes("no_send_zero_cards"));
});

Deno.test("evaluate: each gate trips on its own signal", () => {
  const cases = [
    ["decision_in_expected_set", send("boundary_friend_hint")],
    [
      "no_four_same_opening",
      send("warm_question_back", {
        telemetry: {
          usage: {},
          phase0: {
            divergencePlan: {
              status: "observed",
              sameOpeningCount: 4,
              attribution: {},
            },
          },
        },
      }),
    ],
    [
      "used_branch_within_cap",
      send("warm_question_back", {
        server: {
          plan: {
            semanticDistanceCap: 1,
            branchPool: [
              { id: "br_1", semanticDistance: 1 },
              { id: "br_2", semanticDistance: 2 },
            ],
            styleBranchIds: { humor: "br_2" },
          },
        },
      }),
    ],
    [
      "attribution_resolved",
      send("warm_question_back", {
        telemetry: {
          usage: {},
          phase0: {
            divergencePlan: {
              status: "observed",
              sameOpeningCount: 0,
              attribution: { unresolvedCount: 1 },
            },
          },
        },
      }),
    ],
    [
      "client_no_plan_body",
      send("warm_question_back", {
        clientText: '{"threadFrame":"x"}',
      }),
    ],
    ["latency_under_60s", send("warm_question_back", { elapsedMs: 90_000 })],
    [
      "output_budget",
      send("warm_question_back", {
        telemetry: { usage: { output_tokens: 7000 }, phase0: {} },
      }),
    ],
    ["case_in_corpus", send("not_a_case")],
    [
      "send_five_unique_styles",
      send("warm_question_back", {
        replyOptions: [{ style: "extend" }],
      }),
    ],
  ] as const;
  for (const [gate, artifact] of cases) {
    const summary = evaluateArtifact({ results: [artifact] });
    assert(summary.results[0].failures.includes(gate), gate);
  }
  assert(CORPUS.length >= 21);
  // 三張同開頭、pool 裡未被用到的超 cap 枝、缺欄 invalid：都只是度量，不擋。
  const lenient = evaluateArtifact({
    results: [send("warm_question_back", {
      telemetry: {
        usage: {},
        phase0: {
          divergencePlan: {
            status: "observed",
            sameOpeningCount: 3,
            branchExceedsCap: true,
            attribution: { invalidCount: 2, unresolvedCount: 0 },
          },
        },
      },
      server: {
        plan: {
          semanticDistanceCap: 1,
          branchPool: [
            { id: "br_1", semanticDistance: 1 },
            { id: "br_9", semanticDistance: 3 },
          ],
          styleBranchIds: { extend: "br_1" },
        },
      },
    })],
  });
  assertEquals(lenient.passed, 1);
});

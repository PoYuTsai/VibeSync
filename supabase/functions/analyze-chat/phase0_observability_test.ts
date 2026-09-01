import {
  assertEquals,
  assertFalse,
  assertStrictEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildPhase0ObservabilityTelemetry,
  calibratePhase0EvidenceLinkage,
  emitPhase0Observability,
} from "./phase0_observability.ts";

const OPAQUE_DECISION_ID = "ad_01ARZ3NDEKTSV4RRFFQ69G5FAV";

Deno.test("Phase 0 observability: typed no-send and source IDs are measured without chat content", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        decisionId: OPAQUE_DECISION_ID,
        action: "stop",
        messageDecision: "send",
        replyMode: "none",
        selectedBallIds: ["b_1"],
      },
      analysisInventory: {
        balls: [{
          sourceIndex: 1,
          disposition: "略",
          sourceMessage: "INVENTORY_SECRET",
        }],
      },
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        selectedStyle: "extend",
        variants: {
          extend: {
            sourceIndices: [1],
            sourceBallIds: ["b_1"],
            action: "stop",
            selectedBallIds: ["b_1"],
          },
          tease: {
            sourceIndices: [1],
            sourceBallIds: ["b_2"],
            action: "stop",
            selectedBallIds: ["b_1"],
          },
        },
      },
      replies: {
        extend: "REPLY_SECRET",
        tease: "SECOND_REPLY_SECRET",
      },
    },
  });

  assertEquals(telemetry.noSendConflict, true);
  assertEquals(telemetry.decisionId, OPAQUE_DECISION_ID);
  assertEquals(telemetry.actionMismatch, false);
  assertEquals(telemetry.ballMismatch, false);
  assertEquals(telemetry.meaningfulBallCoverage, { status: "unknown" });
  assertEquals(telemetry.fiveCardSourceDivergence, {
    status: "observed",
    baselineStyle: "extend",
    sourceBallIdEvidence: "complete",
    sourceMessageEvidence: "absent",
    divergentStyles: ["tease"],
    allMatch: false,
  });

  const serialized = JSON.stringify(telemetry);
  assertFalse(serialized.includes("INVENTORY_SECRET"));
  assertFalse(serialized.includes("REPLY_SECRET"));
});

Deno.test("Phase 0 observability: readable ad_-prefixed decision IDs never reach telemetry", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        decisionId: "ad_SOURCE_SECRET",
      },
    },
  });

  assertEquals(telemetry.decisionId, "unknown");
  assertFalse(JSON.stringify(telemetry).includes("ad_SOURCE_SECRET"));
});

Deno.test("Phase 0 observability: action and ball mismatch retain independent partial evidence", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        action: "connect",
        selectedBallIds: ["b_1"],
      },
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        variants: {
          extend: {
            sourceIndices: [1],
            action: "connect",
          },
          tease: {
            sourceIndices: [1],
            action: "invite",
          },
        },
      },
    },
  });

  assertEquals(telemetry.actionMismatch, true);
  assertEquals(telemetry.ballMismatch, "unknown");
  assertEquals("actionBallMismatch" in telemetry, false);
});

Deno.test("Phase 0 observability: ball mismatch remains observed without action evidence", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        selectedBallIds: ["b_1"],
      },
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        variants: {
          extend: {
            sourceIndices: [1],
            selectedBallIds: ["b_2"],
          },
          tease: {
            sourceIndices: [1],
            selectedBallIds: ["b_1"],
          },
        },
      },
    },
  });

  assertEquals(telemetry.actionMismatch, "unknown");
  assertEquals(telemetry.ballMismatch, true);
});

Deno.test("Phase 0 observability: source-less variants retain action, ball, and question evidence", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        action: "connect",
        selectedBallIds: ["b_1"],
      },
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        variants: {
          extend: {
            action: "connect",
            selectedBallIds: ["b_1"],
            questionCount: 2,
          },
          tease: {
            action: "invite",
            selectedBallIds: ["b_2"],
            questionCount: 0,
          },
        },
      },
    },
  });

  assertEquals(telemetry.actionMismatch, true);
  assertEquals(telemetry.ballMismatch, true);
  assertEquals(telemetry.questionCounts, {
    status: "observed",
    byStyle: { extend: 2, tease: 0 },
    maxQuestionCount: 2,
  });
  assertEquals(telemetry.meaningfulBallCoverage, { status: "unknown" });
  assertEquals(telemetry.fiveCardSourceDivergence, { status: "unknown" });
  assertEquals(telemetry.semanticDistance, { status: "unknown" });
});

Deno.test("Phase 0 observability: semantic distance uses only explicit typed evidence", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        variants: {
          extend: { semanticDistance: 0.25 },
          tease: { semanticDistance: 0.75 },
        },
      },
    },
  });

  assertEquals(telemetry.semanticDistance, {
    status: "observed",
    byStyle: { extend: 0.25, tease: 0.75 },
  });
});

Deno.test("Phase 0 observability: beta risk flags never substitute for topic or Solution evidence", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        betaRiskFlags: ["topic_spray", "solution_mode"],
      },
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        variants: {
          extend: { sourceIndices: [1] },
          tease: { sourceIndices: [1] },
        },
      },
    },
  });

  assertEquals(telemetry.betaRiskFlags, ["topic_spray", "solution_mode"]);
  assertEquals(telemetry.topicJump, { status: "unknown" });
  assertEquals(telemetry.solutionMode, { status: "unknown" });
});

Deno.test("Phase 0 observability: legacy decisions are not relabeled and logging is fail-open", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      streamingDecision: {
        action: "connect",
      },
    },
  });
  assertEquals(telemetry.decisionSchema, "unknown");
  assertEquals(telemetry.action, "unknown");

  let emits = 0;
  emitPhase0Observability({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {},
    emit: () => {
      emits += 1;
      throw new Error("telemetry sink unavailable");
    },
  });
  assertEquals(emits, 1);
});

Deno.test("Phase 0 observability: source-message divergence is measured without emitting source text", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        selectedStyle: "extend",
        variants: {
          extend: {
            sourceIndices: [1],
            sourceBallIds: ["b_1"],
          },
          tease: {
            sourceIndices: [1],
            sourceBallIds: ["b_1"],
          },
        },
      },
      replyOptions: {
        extend: {
          messages: [{
            sourceIndex: 1,
            sourceMessage: "FIRST_SOURCE_SECRET",
            reply: "extend reply",
          }],
        },
        tease: {
          messages: [{
            sourceIndex: 1,
            sourceMessage: "SECOND_SOURCE_SECRET",
            reply: "tease reply",
          }],
        },
      },
    },
  });

  assertEquals(telemetry.fiveCardSourceDivergence, {
    status: "observed",
    baselineStyle: "extend",
    sourceBallIdEvidence: "complete",
    sourceMessageEvidence: "complete",
    divergentStyles: ["tease"],
    allMatch: false,
  });

  const serialized = JSON.stringify(telemetry);
  assertFalse(serialized.includes("FIRST_SOURCE_SECRET"));
  assertFalse(serialized.includes("SECOND_SOURCE_SECRET"));
});

Deno.test("Phase 0 observability: incomplete source-message evidence never claims all cards match", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        selectedStyle: "extend",
        variants: {
          extend: {
            sourceIndices: [1],
            sourceBallIds: ["b_1"],
          },
          tease: {
            sourceIndices: [1],
            sourceBallIds: ["b_1"],
          },
        },
      },
    },
  });

  assertEquals(telemetry.fiveCardSourceDivergence, {
    status: "observed",
    baselineStyle: "extend",
    sourceBallIdEvidence: "complete",
    sourceMessageEvidence: "absent",
    divergentStyles: [],
    allMatch: "unknown",
  });
});

Deno.test("Phase 0 observability: a cropped delivered sequence drops raw per-variant claims", () => {
  const finalResult = calibratePhase0EvidenceLinkage({
    analysisInventory: {
      balls: [
        { id: "b_1", sourceIndex: 1 },
        { id: "b_2", sourceIndex: 2 },
      ],
    },
    analysisEvidenceLinkage: {
      schemaVersion: 1,
      selectedStyle: "extend",
      variants: {
        extend: {
          sourceIndices: [1, 2],
          sourceBallIds: ["b_1", "b_2"],
          action: "connect",
          selectedBallIds: ["b_1", "b_2"],
          newTopicCount: 1,
          semanticDistance: 0.8,
          solutionMode: true,
        },
      },
    },
    finalRecommendation: {
      pick: "extend",
      content: "first delivered segment",
      replySegments: [{
        sourceIndex: 1,
        sourceMessage: "source one",
        reply: "first delivered segment",
      }],
    },
  });

  assertEquals(finalResult.analysisEvidenceLinkage, {
    schemaVersion: 1,
    selectedStyle: "extend",
    variants: {
      extend: {
        sourceIndices: [1],
        sourceBallIds: ["b_1"],
        questionCount: 0,
      },
    },
  });
});

Deno.test("Phase 0 observability: a reordered delivered sequence drops raw per-variant claims", () => {
  const finalResult = calibratePhase0EvidenceLinkage({
    analysisInventory: {
      balls: [
        { id: "b_1", sourceIndex: 1 },
        { id: "b_2", sourceIndex: 2 },
      ],
    },
    analysisEvidenceLinkage: {
      schemaVersion: 1,
      selectedStyle: "extend",
      variants: {
        extend: {
          sourceIndices: [1, 2],
          sourceBallIds: ["b_1", "b_2"],
          action: "connect",
          selectedBallIds: ["b_1", "b_2"],
          newTopicCount: 1,
          semanticDistance: 0.8,
          solutionMode: true,
        },
      },
    },
    finalRecommendation: {
      pick: "extend",
      content: "second then first",
      replySegments: [
        {
          sourceIndex: 2,
          sourceMessage: "source two",
          reply: "second",
        },
        {
          sourceIndex: 1,
          sourceMessage: "source one",
          reply: "then first",
        },
      ],
    },
  });

  assertEquals(finalResult.analysisEvidenceLinkage, {
    schemaVersion: 1,
    selectedStyle: "extend",
    variants: {
      extend: {
        sourceIndices: [2, 1],
        sourceBallIds: ["b_2", "b_1"],
        questionCount: 0,
      },
    },
  });
});

Deno.test("Phase 0 observability: an intact repeated-source sequence keeps typed evidence", () => {
  const finalResult = calibratePhase0EvidenceLinkage({
    analysisInventory: {
      balls: [{ id: "b_1", sourceIndex: 1 }],
    },
    analysisEvidenceLinkage: {
      schemaVersion: 1,
      selectedStyle: "extend",
      variants: {
        extend: {
          // Coverage remains unique, while the additive sequence distinguishes
          // two segments sourced from the same ball.
          sourceIndices: [1],
          sourceIndexSequence: [1, 1],
          sourceBallIds: ["b_1"],
          action: "connect",
          selectedBallIds: ["b_1"],
          newTopicCount: 1,
          semanticDistance: 0.8,
          solutionMode: true,
        },
      },
    },
    finalRecommendation: {
      pick: "extend",
      content: "first then second",
      replySegments: [
        {
          sourceIndex: 1,
          sourceMessage: "source one",
          reply: "first",
        },
        {
          sourceIndex: 1,
          sourceMessage: "source one",
          reply: "then second",
        },
      ],
    },
  });

  assertEquals(finalResult.analysisEvidenceLinkage, {
    schemaVersion: 1,
    selectedStyle: "extend",
    variants: {
      extend: {
        sourceIndices: [1],
        sourceBallIds: ["b_1"],
        action: "connect",
        selectedBallIds: ["b_1"],
        newTopicCount: 1,
        semanticDistance: 0.8,
        solutionMode: true,
        questionCount: 0,
      },
    },
  });
});

Deno.test("Phase 0 observability: a cropped repeated-source sequence drops typed evidence", () => {
  const finalResult = calibratePhase0EvidenceLinkage({
    analysisInventory: {
      balls: [{ id: "b_1", sourceIndex: 1 }],
    },
    analysisEvidenceLinkage: {
      schemaVersion: 1,
      selectedStyle: "extend",
      variants: {
        extend: {
          sourceIndices: [1],
          sourceIndexSequence: [1, 1],
          sourceBallIds: ["b_1"],
          action: "connect",
          selectedBallIds: ["b_1"],
          newTopicCount: 1,
          semanticDistance: 0.8,
          solutionMode: true,
        },
      },
    },
    finalRecommendation: {
      pick: "extend",
      content: "first only",
      replySegments: [{
        sourceIndex: 1,
        sourceMessage: "source one",
        reply: "first only",
      }],
    },
  });

  assertEquals(finalResult.analysisEvidenceLinkage, {
    schemaVersion: 1,
    selectedStyle: "extend",
    variants: {
      extend: {
        sourceIndices: [1],
        sourceBallIds: ["b_1"],
        questionCount: 0,
      },
    },
  });
});

Deno.test("Phase 0 observability: calibration exceptions return the original result", () => {
  const throwingReplyOptions = new Proxy({}, {
    ownKeys() {
      throw new Error("deterministic calibration failure");
    },
  });
  const finalResult = {
    analysisEvidenceLinkage: { schemaVersion: 1 },
    replyOptions: throwingReplyOptions,
  };

  assertStrictEquals(
    calibratePhase0EvidenceLinkage(finalResult),
    finalResult,
  );
});

Deno.test("Phase 0 observability: no-send conflict falls back from empty replies to delivered variants or options", () => {
  const telemetryFromVariants = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        messageDecision: "do_not_send",
        replyMode: "none",
      },
      replies: {},
      replyOptions: {
        extend: { messages: [{ reply: "delivered candidate" }] },
      },
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        variants: { extend: { questionCount: 0 } },
      },
    },
  });

  assertEquals(telemetryFromVariants.noSendConflict, true);

  const telemetryFromOptions = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        messageDecision: "do_not_send",
        replyMode: "none",
      },
      replies: {},
      replyOptions: {
        extend: { messages: [{ reply: "delivered candidate" }] },
      },
    },
  });

  assertEquals(telemetryFromOptions.noSendConflict, true);
});

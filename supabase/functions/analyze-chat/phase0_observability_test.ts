import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildPhase0ObservabilityTelemetry,
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

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

Deno.test("Phase 0 observability: legacy give-up banner conflict is measured from v1 fields only", () => {
  const cold = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-legacy",
    finalResult: {
      enthusiasm: { level: "cold", score: 12 },
      warnings: ["對方已讀不回，建議放棄這段對話", { note: "other" }],
      replies: { extend: "REPLY_SECRET", tease: "REPLY_SECRET_2" },
      coachActionHint: {
        actionType: "lowerPressureReply",
        read: "HINT_SECRET",
      },
    },
  });
  assertStrictEquals(cold.legacyGiveUpBanner, true);
  assertStrictEquals(cold.legacyGiveUpConflict, true);
  assertStrictEquals(cold.candidateCount, 2);
  assertStrictEquals(cold.coachActionType, "lowerPressureReply");
  const serialized = JSON.stringify(cold);
  assertFalse(serialized.includes("建議放棄"));
  assertFalse(serialized.includes("SECRET"));

  const warm = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-warm",
    finalResult: {
      enthusiasm: { level: "warm" },
      warnings: ["建議放棄"],
      replies: { extend: "x" },
      coachActionHint: { actionType: "not-an-action" },
    },
  });
  assertStrictEquals(warm.legacyGiveUpBanner, false);
  assertStrictEquals(warm.legacyGiveUpConflict, false);
  assertStrictEquals(warm.coachActionType, "unknown");

  // 冷但沒有放棄字樣：與 App 一樣不顯示橫幅。
  const coldNoWarning = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-cold-quiet",
    finalResult: { enthusiasm: { level: "cold" }, replies: { extend: "x" } },
  });
  assertStrictEquals(coldNoWarning.legacyGiveUpBanner, false);

  const missing = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-missing",
    finalResult: { replies: { extend: "x" } },
  });
  assertEquals(missing.legacyGiveUpBanner, "unknown");
  assertEquals(missing.legacyGiveUpConflict, "unknown");
  assertEquals(missing.coachActionType, "unknown");
});

Deno.test("Phase 2a observability: divergence plan telemetry is numbers and enums only", () => {
  const plan = {
    schemaVersion: 1,
    threadFrame: "PLAN_SECRET",
    anchorSourceIndex: 1,
    supportSourceIndices: [3],
    mergeContextSourceIndices: [2],
    semanticDistanceCap: 1,
    newTopicBudget: 0,
    questionBudget: 1,
    branchPool: [
      {
        id: "br_1",
        sourceIndex: 1,
        method: "affect_evaluation",
        idea: "IDEA_SECRET",
        associationPath: ["PATH_SECRET"],
        semanticDistance: 1,
      },
      {
        id: "br_2",
        sourceIndex: 3,
        method: "association",
        idea: "IDEA_SECRET_2",
        associationPath: [],
        semanticDistance: 2,
      },
    ],
    styleBranchIds: { extend: "br_1" },
  };
  const sendDecision = {
    schemaVersion: 2,
    decisionId: OPAQUE_DECISION_ID,
    messageDecision: "send",
  };
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    contractVersion2: true,
    finalResult: {
      analysisDecisionV2: sendDecision,
      analysisDivergencePlan: plan,
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        selectedStyle: "extend",
        variants: {
          extend: { sourceIndices: [1, 3], questionCount: 1, newTopicCount: 0 },
          tease: { sourceIndices: [3], questionCount: 2, newTopicCount: 1 },
        },
      },
    },
  });
  assertEquals(telemetry.divergencePlan, {
    status: "observed",
    anchorSourceIndex: 1,
    supportCount: 1,
    mergeContextCount: 1,
    branchCount: 2,
    methods: { affect_evaluation: 1, association: 1 },
    semanticDistanceCap: 1,
    maxBranchDistance: 2,
    branchExceedsCap: true,
    questionBudget: 1,
    questionBudgetExceeded: true,
    newTopicBudget: 0,
    newTopicBudgetExceeded: true,
    anchorCoveredByAllStyles: false,
    styleBranchAssigned: 1,
    styleBranchMissing: 1,
    sameOpeningCount: "unknown",
    repairs: { method: 0, sourceIndexKey: 0, line: 0 },
    attribution: { status: "unknown" },
  });
  const serialized = JSON.stringify(telemetry);
  assertFalse(serialized.includes("SECRET"));

  // 不是 v2 request 的 run 連 key 都沒有，就算帶著一份合法計畫也一樣（母數只算 v2 send）。
  const v1 = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-2",
    finalResult: {
      analysisDecisionV2: sendDecision,
      analysisDivergencePlan: plan,
    },
  });
  assertEquals("divergencePlan" in v1, false);
  // v2 但 no-send（含 acknowledge_and_stop）：帶著合法計畫也不算。
  // v2 但 replyMode none（typed no-send 快照）：帶著合法計畫也不算。
  const replyModeNone = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-2a",
    contractVersion2: true,
    finalResult: {
      analysisDecisionV2: { ...sendDecision, replyMode: "none" },
      analysisDivergencePlan: plan,
    },
  });
  assertEquals("divergencePlan" in replyModeNone, false);
  for (
    const messageDecision of [
      "do_not_send",
      "need_context",
      "acknowledge_and_stop",
    ]
  ) {
    const noSendWithPlan = buildPhase0ObservabilityTelemetry({
      user: "user-summary",
      analysisRunId: "run-2b",
      contractVersion2: true,
      finalResult: {
        analysisDecisionV2: { ...sendDecision, messageDecision },
        analysisDivergencePlan: plan,
      },
    });
    assertEquals("divergencePlan" in noSendWithPlan, false, messageDecision);
  }
  // v2 send 卻沒有合法計畫 → unknown（這才是要量的缺席）；send decision 沒宣告
  // schemaVersion 2 也一樣算（模型不一定帶）。
  const v2Missing = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-3",
    contractVersion2: true,
    finalResult: { analysisDecisionV2: sendDecision },
  });
  assertEquals(v2Missing.divergencePlan, { status: "unknown" });
  const v2MissingNoSchema = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-3b",
    contractVersion2: true,
    finalResult: { replies: { extend: "x" } },
  });
  assertEquals(v2MissingNoSchema.divergencePlan, { status: "unknown" });
});

Deno.test("Phase 2b observability: branch attribution telemetry counts sources, branches, moves, intensity, and invalid marks; never text", () => {
  const plan = {
    schemaVersion: 1,
    threadFrame: "PLAN_SECRET",
    anchorSourceIndex: 1,
    supportSourceIndices: [],
    mergeContextSourceIndices: [],
    semanticDistanceCap: 1,
    newTopicBudget: 0,
    questionBudget: 1,
    branchPool: [
      {
        id: "br_1",
        sourceIndex: 1,
        method: "drill_down",
        idea: "IDEA_SECRET",
        associationPath: [],
        semanticDistance: 0,
      },
      {
        id: "br_2",
        sourceIndex: 1,
        method: "association",
        idea: "IDEA_SECRET_2",
        associationPath: [],
        semanticDistance: 1,
      },
    ],
  };
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    contractVersion2: true,
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        decisionId: OPAQUE_DECISION_ID,
        messageDecision: "send",
      },
      analysisDivergencePlan: plan,
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        selectedStyle: "extend",
        divergencePlanRepairs: [
          "br_2:method:exaggeration->association",
          "br_3:sourceIndex1",
          "line:sourceIndex=",
          "TEXT_SECRET not a repair entry",
          "她的話:sourceIndex1",
        ],
        variants: {
          extend: {
            sourceIndices: [1],
            selectedBranchIds: ["br_2", "br_1"],
            branchSource: "option",
            rhetoricalMove: "new_angle",
            styleIntensity: 2,
          },
          tease: {
            sourceIndices: [1],
            selectedBranchIds: ["br_1"],
            branchSource: "anchor",
            branchAttributionInvalid: true,
          },
          humor: {
            sourceIndices: [1],
            selectedBranchIds: ["br_2"],
            branchSource: "plan",
            rhetoricalMove: "not_a_move",
            styleIntensity: 9,
          },
          coldRead: {
            sourceIndices: [1],
            selectedBranchIds: [],
            branchSource: "unresolved",
          },
        },
      },
    },
  });
  const divergence = telemetry.divergencePlan as Record<string, unknown>;
  assertEquals(divergence.repairs, { method: 1, sourceIndexKey: 1, line: 1 });
  assertEquals(divergence.styleBranchMissing, 4);
  assertEquals(divergence.attribution, {
    status: "observed",
    styleCount: 4,
    attributedCount: 3,
    unresolvedCount: 1,
    bySource: { option: 1, plan: 1, anchor: 1, unresolved: 1 },
    distinctBranchCount: 2,
    rhetoricalMoves: { new_angle: 1 },
    styleIntensity: { "2": 1 },
    invalidCount: 1,
  });
  assertEquals(JSON.stringify(telemetry).includes("SECRET"), false);
});

Deno.test("Phase 2b observability: sameOpeningCount counts cards whose normalized first four characters repeat", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-1",
    contractVersion2: true,
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        decisionId: OPAQUE_DECISION_ID,
        messageDecision: "send",
      },
      analysisDivergencePlan: {
        schemaVersion: 1,
        threadFrame: "t",
        anchorSourceIndex: 1,
        supportSourceIndices: [],
        mergeContextSourceIndices: [],
        semanticDistanceCap: 1,
        newTopicBudget: 0,
        questionBudget: 1,
        branchPool: [
          {
            id: "br_1",
            sourceIndex: 1,
            method: "drill_down",
            idea: "i",
            associationPath: [],
            semanticDistance: 0,
          },
          {
            id: "br_2",
            sourceIndex: 1,
            method: "lateral",
            idea: "i",
            associationPath: [],
            semanticDistance: 1,
          },
        ],
      },
      replies: {
        extend: "當然有興趣，週五我可以",
        resonate: "當然有興趣，這票算我一個",
        tease: "當然，有興趣！這人情怎麼還",
        humor: "有興趣到想清空行程",
        coldRead: "我猜妳早就想到我",
      },
    },
  });
  const divergence = telemetry.divergencePlan as Record<string, unknown>;
  // 三張正規化後都是「當然有興」。
  assertEquals(divergence.sameOpeningCount, 3);
});

Deno.test("Phase 3c candidate guard: violations are derived from the delivered result without chat content", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-3c",
    contractVersion2: true,
    finalResult: {
      analysisDecisionV2: {
        schemaVersion: 2,
        messageDecision: "send",
        replyMode: "variants",
        selectedStyle: "extend",
        action: "extend",
        selectedBallIds: ["b_1"],
      },
      analysisInventory: {
        balls: [
          {
            sourceIndex: 1,
            id: "b_1",
            disposition: "接",
            sourceMessage: "INVENTORY_SECRET",
          },
          {
            sourceIndex: 2,
            id: "b_2",
            disposition: "略",
            sourceMessage: "SKIPPED_SECRET",
          },
        ],
      },
      analysisDivergencePlan: {
        schemaVersion: 1,
        threadFrame: "FRAME_SECRET",
        anchorSourceIndex: 1,
        supportSourceIndices: [],
        mergeContextSourceIndices: [],
        semanticDistanceCap: 1,
        newTopicBudget: 0,
        questionBudget: 0,
        branchPool: [
          {
            id: "br_1",
            sourceIndex: 1,
            method: "drill_down",
            idea: "IDEA_SECRET",
            associationPath: ["PATH_SECRET"],
            semanticDistance: 1,
          },
          {
            id: "br_2",
            sourceIndex: 1,
            method: "association",
            idea: "IDEA_SECRET_TWO",
            associationPath: [],
            semanticDistance: 2,
          },
        ],
      },
      analysisEvidenceLinkage: {
        schemaVersion: 1,
        selectedStyle: "extend",
        variants: {
          extend: {
            action: "extend",
            selectedBallIds: ["b_1"],
            selectedBranchIds: ["br_1"],
            branchSource: "option",
          },
          tease: {
            action: "extend",
            selectedBallIds: ["b_1"],
            selectedBranchIds: ["br_2"],
            branchSource: "option",
          },
        },
      },
      replyOptions: {
        extend: {
          messages: [{
            sourceIndex: 1,
            sourceMessage: "HER_SECRET",
            reply: "REPLY_SECRET_ONE",
          }],
        },
        tease: {
          messages: [
            {
              sourceIndex: 1,
              sourceMessage: "HER_SECRET",
              reply: "REPLY_SECRET_TWO？",
            },
            {
              sourceIndex: 2,
              sourceMessage: "SKIPPED_SECRET",
              reply: "REPLY_SECRET [地點]",
            },
          ],
        },
      },
      replies: {
        extend: "REPLY_SECRET_ONE",
        tease: "REPLY_SECRET_TWO？\nREPLY_SECRET [地點]",
      },
    },
  });

  assertEquals(telemetry.candidateGuard, {
    violations: [
      { code: "skipped_ball_used", style: "tease", sourceIndex: 2 },
      { code: "card_source_mismatch", style: "tease" },
      { code: "placeholder", style: "tease" },
      { code: "question_budget", style: "tease" },
      { code: "semantic_distance_cap", style: "tease", branchId: "br_2" },
      { code: "association_without_path", style: "tease", branchId: "br_2" },
    ],
    checked: [
      "reply_mode_card_count",
      "decision_action_conflict",
      "variant_action_drift",
      "variant_ball_drift",
      "source_ball_unknown",
      "skipped_ball_used",
      "merge_ball_isolated",
      "caught_ball_uncovered",
      "card_source_mismatch",
      "placeholder",
      "question_budget",
      "semantic_distance_cap",
      "association_without_path",
      "no_send_with_cards",
    ],
  });
  // 既有的 Phase 0 欄位照舊，guard 清單只是併進同一份 telemetry。
  assertEquals(telemetry.actionMismatch, false);
  assertEquals(telemetry.noSendConflict, "unknown");
  const serialized = JSON.stringify(telemetry);
  for (const secret of ["SECRET", "地點", "FRAME", "IDEA", "PATH_"]) {
    assertFalse(serialized.includes(secret), secret);
  }
});

Deno.test("Phase 3c candidate guard: a v1 result without typed evidence checks only what it can see", () => {
  const telemetry = buildPhase0ObservabilityTelemetry({
    user: "user-summary",
    analysisRunId: "run-v1",
    finalResult: {
      replies: { extend: "REPLY_SECRET", tease: "REPLY_SECRET XX" },
    },
  });
  assertEquals(telemetry.candidateGuard, {
    violations: [{ code: "placeholder", style: "tease" }],
    checked: ["placeholder"],
  });
});

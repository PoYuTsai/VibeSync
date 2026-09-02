import {
  assert,
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  ANALYZE_CRITIC_SHADOW,
  type AnalyzeCriticAiCall,
  analyzeCriticTrigger,
  buildAnalyzeCriticInput,
  runAnalyzeCriticShadow,
  scheduleAnalyzeCriticShadow,
} from "./critic_shadow.ts";

const MESSAGES = [
  { isFromMe: true, content: "嗨" },
  { isFromMe: false, content: "哈囉 你的照片是在哪拍的呀" },
];

/// v2 send：extend 被選中（finalRecommendation.replySegments 是最終來源），
/// 盤點 1 接 2 略，計畫兩枝、選中卡跟 br_1。
function sendResult(
  patch: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    analysisDecisionV2: {
      schemaVersion: 2,
      messageDecision: "send",
      action: "connect",
      selectedBallIds: ["b_1"],
      betaRiskFlags: ["question_only"],
      strategyIntent: "先回地點再留一個小反問",
      solutionModeAllowed: false,
      reason: "REASON_TEXT",
    },
    analysisInventory: {
      type: "analysis.inventory",
      balls: [
        {
          sourceIndex: 1,
          id: "b_1",
          disposition: "接",
          sourceMessage: "哈囉 你的照片是在哪拍的呀",
        },
        { sourceIndex: 2, id: "b_2", disposition: "略", sourceMessage: "嗨" },
      ],
    },
    analysisDivergencePlan: {
      schemaVersion: 1,
      threadFrame: "回地點並補畫面",
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
          idea: "陽明山的雲海",
          associationPath: ["照片", "陽明山", "雲"],
          semanticDistance: 1,
        },
        {
          id: "br_2",
          sourceIndex: 1,
          method: "lateral",
          idea: "UNUSED_BRANCH_IDEA",
          associationPath: ["照片", "相機"],
          semanticDistance: 1,
        },
      ],
    },
    analysisEvidenceLinkage: {
      schemaVersion: 1,
      selectedStyle: "extend",
      variants: {
        extend: {
          selectedBranchIds: ["br_1"],
          branchSource: "option",
          rhetoricalMove: "concrete_detail",
          styleIntensity: 2,
        },
        tease: { selectedBranchIds: ["br_2"], branchSource: "option" },
      },
    },
    finalRecommendation: {
      pick: "extend",
      content: "那張是在陽明山拍的，那天雲很低",
      replySegments: [{
        sourceIndex: 1,
        sourceMessage: "哈囉 你的照片是在哪拍的呀",
        reply: "那張是在陽明山拍的，那天雲很低",
      }],
    },
    replyOptions: {
      extend: {
        messages: [{
          sourceIndex: 1,
          sourceMessage: "哈囉 你的照片是在哪拍的呀",
          reply: "STALE_OPTION_TEXT",
        }],
      },
      tease: {
        messages: [{
          sourceIndex: 1,
          sourceMessage: "哈囉 你的照片是在哪拍的呀",
          reply: "你這是在查我戶口嗎？",
        }],
      },
    },
    replies: {
      extend: "那張是在陽明山拍的，那天雲很低",
      tease: "你這是在查我戶口嗎？",
    },
    ...patch,
  };
}

const phase0 = (patch: Record<string, unknown> = {}) => ({
  candidateGuard: { violations: [], checked: ["placeholder"] },
  divergencePlan: { status: "observed", sameOpeningCount: 0 },
  ...patch,
});

Deno.test("critic trigger: only a send with a selected card can run; risk mode needs a signal", () => {
  const quiet = sendResult({
    analysisDecisionV2: { schemaVersion: 2, messageDecision: "send" },
  });
  assertEquals(analyzeCriticTrigger(quiet, phase0(), "risk"), null);
  assertEquals(analyzeCriticTrigger(quiet, phase0(), "always"), ["always"]);
  // 決策自帶 beta flags 就算風險訊號。
  assertEquals(analyzeCriticTrigger(sendResult(), phase0(), "risk"), [
    "beta:question_only",
  ]);
  assertEquals(
    analyzeCriticTrigger(
      sendResult({
        analysisDecisionV2: {
          schemaVersion: 2,
          messageDecision: "do_not_send",
          action: "pause",
        },
        finalRecommendation: undefined,
        replyOptions: {},
        replies: {},
      }),
      phase0(),
      "always",
    ),
    null,
  );
  assertEquals(
    analyzeCriticTrigger(
      sendResult(),
      phase0({
        candidateGuard: {
          violations: [
            { code: "placeholder", style: "extend" },
            { code: "placeholder", style: "tease" },
            { code: "question_budget", style: "extend" },
          ],
          checked: [],
        },
        divergencePlan: { status: "observed", sameOpeningCount: 4 },
      }),
      "risk",
    ),
    [
      "guard:placeholder",
      "guard:question_budget",
      "beta:question_only",
      "same_opening",
    ],
  );
  // phase0 缺席（telemetry 失敗）時 risk 模式只剩決策自帶的 flags。
  assertEquals(analyzeCriticTrigger(sendResult(), null, "risk"), [
    "beta:question_only",
  ]);
  // 沒有 flags 也沒有 phase0 → 不跑。
  assertEquals(
    analyzeCriticTrigger(
      sendResult({
        analysisDecisionV2: { schemaVersion: 2, messageDecision: "send" },
      }),
      null,
      "risk",
    ),
    null,
  );
});

Deno.test("critic input: the selected card, her balls, the decision, the used branches and the guard codes are assembled from the delivered result", () => {
  const input = buildAnalyzeCriticInput(
    sendResult(),
    [
      ...Array.from({ length: 15 }, (_, i) => ({
        isFromMe: i % 2 === 0,
        content: `OLD_${i}`,
      })),
      ...MESSAGES,
    ],
    ["question_budget"],
  );
  assert(input);
  assertEquals(input.evidence.messages.length, 12);
  assertEquals(input.evidence.messages.at(-1), {
    from: "her",
    text: "哈囉 你的照片是在哪拍的呀",
  });
  assertEquals(input.evidence.inventory, [
    { sourceIndex: 1, disposition: "接", text: "哈囉 你的照片是在哪拍的呀" },
    { sourceIndex: 2, disposition: "略", text: "嗨" },
  ]);
  assertEquals(input.evidence.decision, {
    messageDecision: "send",
    action: "connect",
    selectedBallIds: ["b_1"],
    betaRiskFlags: ["question_only"],
    strategyIntent: "先回地點再留一個小反問",
    solutionModeAllowed: false,
  });
  assertEquals(input.evidence.plan?.threadFrame, "回地點並補畫面");
  assertEquals(input.evidence.plan?.usedBranches.map((b) => b.id), ["br_1"]);
  assertEquals(input.evidence.guardViolations, ["question_budget"]);
  assertEquals(input.candidate, {
    style: "extend",
    rhetoricalMove: "concrete_detail",
    styleIntensity: 2,
    segments: [{
      sourceIndex: 1,
      sourceMessage: "哈囉 你的照片是在哪拍的呀",
      reply: "那張是在陽明山拍的，那天雲很低",
    }],
    questionCount: 0,
  });
  // 只審選中卡：tease 的文字與未用到的枝都不進 prompt 素材。
  const serialized = JSON.stringify(input);
  for (
    const leak of [
      "查我戶口",
      "UNUSED_BRANCH_IDEA",
      "STALE_OPTION_TEXT",
      "REASON_TEXT",
    ]
  ) {
    assertEquals(serialized.includes(leak), false, leak);
  }
});

Deno.test("critic input: a v1 result still yields the selected card with untyped evidence as null", () => {
  const input = buildAnalyzeCriticInput(
    {
      finalRecommendation: { pick: "tease", content: "你這是在查我戶口嗎？" },
      replies: { extend: "那張是在陽明山拍的", tease: "你這是在查我戶口嗎？" },
    },
    MESSAGES,
    [],
  );
  assert(input);
  assertEquals(input.evidence.inventory, null);
  assertEquals(input.evidence.decision, null);
  assertEquals(input.evidence.plan, null);
  assertEquals(input.candidate.style, "tease");
  assertEquals(input.candidate.segments, []);
  assertEquals(input.candidate.questionCount, 1);
  assertEquals(buildAnalyzeCriticInput({ replies: {} }, MESSAGES, []), null);
});

function runner(overrides: Record<string, unknown> = {}) {
  const emitted: [string, Record<string, unknown>][] = [];
  const aiCalls: AnalyzeCriticAiCall[] = [];
  const args = {
    finalResult: sendResult(),
    messages: MESSAGES,
    guardViolations: ["question_budget"],
    trigger: ["guard:question_budget"],
    config: { ...ANALYZE_CRITIC_SHADOW, enabled: true, model: "critic-m" },
    apiKey: "k",
    callCritic: () =>
      Promise.resolve({
        content: [{
          type: "text",
          text:
            '{"verdict":"rewrite","violations":["generic_hook","beta_pattern"]}',
        }],
        usage: { input_tokens: 900, output_tokens: 30 },
      }),
    emit: (event: string, metadata: Record<string, unknown>) => {
      emitted.push([event, metadata]);
    },
    recordAiCall: (entry: AnalyzeCriticAiCall) => {
      aiCalls.push(entry);
      return Promise.resolve();
    },
    ...overrides,
  };
  return { args, emitted, aiCalls };
}

Deno.test("critic shadow runner: a verdict is logged with tokens and recorded as an AI call, never changing the result", async () => {
  const { args, emitted, aiCalls } = runner();
  const before = JSON.stringify(args.finalResult);
  await runAnalyzeCriticShadow(args);
  assertEquals(JSON.stringify(args.finalResult), before);
  assertEquals(emitted.length, 1);
  const [event, metadata] = emitted[0];
  assertEquals(event, "stream_semantic_critic");
  assertEquals(metadata.status, "ok");
  assertEquals(metadata.model, "critic-m");
  assertEquals(metadata.trigger, ["guard:question_budget"]);
  assertEquals(metadata.verdict, "rewrite");
  assertEquals(metadata.violations, ["generic_hook", "beta_pattern"]);
  assertEquals(metadata.inputTokens, 900);
  assertEquals(metadata.outputTokens, 30);
  assert(typeof metadata.latencyMs === "number");
  assertEquals(aiCalls.length, 1);
  assertEquals(aiCalls[0].requestType, "analyze_semantic_critic");
  assertEquals(aiCalls[0].model, "critic-m");
  assertEquals(aiCalls[0].inputTokens, 900);
  assertEquals(aiCalls[0].outputTokens, 30);
  assertEquals(aiCalls[0].status, "success");
  // telemetry 不帶對話或卡片文字。
  const serialized = JSON.stringify(emitted) + JSON.stringify(aiCalls);
  for (const leak of ["陽明山", "照片", "REASON_TEXT"]) {
    assertEquals(serialized.includes(leak), false, leak);
  }
});

Deno.test("critic shadow runner: invalid output, transport failure and emitter failure never throw", async () => {
  const invalid = runner({
    callCritic: () =>
      Promise.resolve({
        content: [{ type: "text", text: "我覺得還不錯" }],
        usage: { input_tokens: 800, output_tokens: 12 },
      }),
  });
  await runAnalyzeCriticShadow(invalid.args);
  assertEquals(invalid.emitted[0][1].status, "invalid");
  assertEquals(invalid.emitted[0][1].inputTokens, 800);
  assertEquals(invalid.aiCalls[0].status, "failed");
  assertEquals(invalid.aiCalls[0].errorCode, "semantic_critic_invalid");
  assertEquals(invalid.aiCalls[0].inputTokens, 800);

  const failed = runner({
    callCritic: () => Promise.reject(new Error("claude_http_529: overloaded")),
  });
  await runAnalyzeCriticShadow(failed.args);
  assertEquals(failed.emitted[0][1].status, "failed");
  assertEquals(failed.emitted[0][1].errorClass, "claude_http_529: overloaded");
  assertEquals(failed.aiCalls[0].status, "failed");
  assertEquals(failed.aiCalls[0].inputTokens, 0);

  const emitterBroken = runner({
    emit: () => {
      throw new Error("logger down");
    },
    recordAiCall: () => Promise.reject(new Error("db down")),
  });
  await runAnalyzeCriticShadow(emitterBroken.args);

  const skipped = runner({
    finalResult: { replies: {} },
  });
  await runAnalyzeCriticShadow(skipped.args);
  assertEquals(skipped.emitted[0][1].status, "skipped");
  assertEquals(skipped.aiCalls.length, 0);
});

Deno.test("critic shadow scheduling: prefers the injected waitUntil and never lets a task rejection escape", async () => {
  const scheduled: Promise<void>[] = [];
  const task = Promise.resolve();
  scheduleAnalyzeCriticShadow((t) => scheduled.push(t), task);
  assertStrictEquals(scheduled[0], task);
  // 沒有排程器（本機測試）：task 直接 detach，不炸。
  scheduleAnalyzeCriticShadow(undefined, Promise.resolve());
  await Promise.all(scheduled);
});

Deno.test("critic shadow config: production default is off, risk-triggered, on the cheap model", () => {
  assertEquals(ANALYZE_CRITIC_SHADOW, {
    enabled: false,
    model: "claude-haiku-4-5-20251001",
    timeoutMs: 12_000,
    trigger: "risk",
  });
});

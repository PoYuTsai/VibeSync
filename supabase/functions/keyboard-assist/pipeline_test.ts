import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  KeyboardAssistPipelineError,
  runKeyboardAssistPipeline,
} from "./pipeline.ts";
import { KeyboardAssistProviderError } from "./provider.ts";

const image = {
  bytes: new Uint8Array([1, 2, 3]),
  base64: "AQID",
  mediaType: "image/png" as const,
};

function compilerOutput(sideConfidence: "high" | "low" = "high") {
  return {
    conversationType: "chat" as const,
    suggestedMySide: "right" as const,
    sideConfidence,
    confidence: "high" as const,
    turnState: "reply_due" as const,
    cue: "對方剛問你週六是否有空。",
    uncertainty: null,
    messages: [
      { index: 0, side: "left" as const, text: "週六有空嗎？" },
      { index: 1, side: "right" as const, text: "我看一下" },
    ],
    candidates: [
      {
        strategy: "keep_pace" as const,
        text: "有啊，你有什麼想法？",
        evidenceIndices: [0],
      },
      {
        strategy: "build_connection" as const,
        text: "有空，聽起來你已經有計畫了 😄",
        evidenceIndices: [0],
      },
      {
        strategy: "move_forward" as const,
        text: "有空，週六下午要不要一起喝杯咖啡？",
        evidenceIndices: [0],
      },
      {
        strategy: "clarify" as const,
        text: "有空，你是想約白天還是晚上？",
        evidenceIndices: [0],
      },
      {
        strategy: "deescalate" as const,
        text: "我還不確定，確認後再跟你說",
        evidenceIndices: [0],
      },
      {
        strategy: "keep_pace" as const,
        text: "有空啊，怎麼了？",
        evidenceIndices: [0],
      },
    ],
  };
}

const judged = {
  contractVersion: "keyboard-assist-v1" as const,
  status: "ready" as const,
  source: {
    scope: "screenshot_plus_global_voice" as const,
    messageCount: 2,
    confidence: "high" as const,
    sideConfidence: "high" as const,
  },
  turnState: "reply_due" as const,
  cue: "對方剛問你週六是否有空。",
  uncertainty: null,
  options: [
    {
      strategy: "keep_pace" as const,
      text: "有啊，你有什麼想法？",
      why: "先接住對方的問題",
      effect: "自然延續",
    },
    {
      strategy: "build_connection" as const,
      text: "有空，聽起來你已經有計畫了 😄",
      why: "接住邀約感並增加溫度",
      effect: "互動感較高",
    },
    {
      strategy: "move_forward" as const,
      text: "有空，週六下午要不要一起喝杯咖啡？",
      why: "直接把邀約變成安排",
      effect: "推進最快",
    },
  ],
};

Deno.test("compiler sees the image once; judge receives normalized text only", async () => {
  let compilerCalls = 0;
  let judgeCalls = 0;
  let judgePayload = "";
  const renewStages: string[] = [];
  const stageTimings: Record<string, number> = {};
  let nowMs = 1000;
  const result = await runKeyboardAssistPipeline({
    image,
    speakerOverride: "none",
    voice: { primary: "steady", secondary: null },
    priorTurn: null,
    pipelineVersion: "compiler-judge-v1",
    signal: new AbortController().signal,
    compiler: (request) => {
      compilerCalls++;
      nowMs += 320;
      assertEquals(request.image, image);
      assertEquals(request.voice, { primary: "steady", secondary: null });
      return Promise.resolve(compilerOutput());
    },
    judge: (request) => {
      judgeCalls++;
      nowMs += 90;
      judgePayload = JSON.stringify(request);
      return Promise.resolve(judged);
    },
    renewLease: (stage) => {
      renewStages.push(stage);
      return Promise.resolve(true);
    },
    recordStageTiming: (timing) => Object.assign(stageTimings, timing),
    nowMs: () => nowMs,
    deadlineAtMs: 41_000,
  });
  assertEquals(result, judged);
  assertEquals(compilerCalls, 1);
  assertEquals(judgeCalls, 1);
  assertEquals(renewStages, ["after_compiler", "after_judge"]);
  assert(!judgePayload.includes("AQID"));
  assert(!judgePayload.includes('"bytes"'));
  assert(judgePayload.includes("週六有空嗎"));
  assertEquals(stageTimings, { compilerMs: 320, judgeMs: 90 });
});

Deno.test("low speaker confidence returns stored no-charge shape without judge", async () => {
  let judgeCalls = 0;
  const result = await runKeyboardAssistPipeline({
    image,
    speakerOverride: "none",
    voice: { primary: null, secondary: null },
    priorTurn: null,
    pipelineVersion: "compiler-judge-v1",
    signal: new AbortController().signal,
    compiler: () => Promise.resolve(compilerOutput("low")),
    judge: () => {
      judgeCalls++;
      return Promise.resolve(judged);
    },
    renewLease: () => Promise.resolve(true),
    nowMs: () => 1000,
    deadlineAtMs: 41_000,
  });
  assertEquals(result, {
    contractVersion: "keyboard-assist-v1",
    status: "needs_speaker_confirmation",
    suggestedMySide: "right",
    sideConfidence: "low",
  });
  assertEquals(judgeCalls, 0);
  assert(!JSON.stringify(result).includes("messages"));
});

Deno.test("speaker override allows low-confidence compiler output to proceed", async () => {
  let judgeCalls = 0;
  await runKeyboardAssistPipeline({
    image,
    speakerOverride: "left_is_me",
    voice: { primary: "steady", secondary: null },
    priorTurn: null,
    pipelineVersion: "compiler-judge-v1",
    signal: new AbortController().signal,
    compiler: () => Promise.resolve(compilerOutput("low")),
    judge: () => {
      judgeCalls++;
      return Promise.resolve({
        ...judged,
        source: { ...judged.source, sideConfidence: "low" as const },
      });
    },
    renewLease: () => Promise.resolve(true),
    nowMs: () => 1000,
    deadlineAtMs: 41_000,
  });
  assertEquals(judgeCalls, 1);
});

Deno.test("non-chat and invalid grounding fail before judge with no result", async () => {
  const nonChat = {
    ...compilerOutput(),
    conversationType: "non_chat" as const,
    cue: "行程公告：明天下午 3 點開會",
    messages: [],
    candidates: [],
  };
  const error = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: null, secondary: null },
        priorTurn: null,
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () => Promise.resolve(nonChat),
        judge: () => Promise.resolve(judged),
        renewLease: () => Promise.resolve(true),
        nowMs: () => 1000,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(error.code, "unsupported_conversation");

  const ungrounded = compilerOutput();
  ungrounded.candidates[0].evidenceIndices = [99];
  const invalid = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: null, secondary: null },
        priorTurn: null,
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () => Promise.resolve(ungrounded),
        judge: () => Promise.resolve(judged),
        renewLease: () => Promise.resolve(true),
        nowMs: () => 1000,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(invalid.code, "provider_invalid_output");
});

Deno.test("our own prior candidates read back as chat stop before judge", async () => {
  const leaked = compilerOutput();
  // The keyboard trims its own panel out of the capture, but a geometry
  // mismatch can leave a previous candidate behind; that transcript describes
  // our UI, not the conversation, and must never reach the judge or a charge.
  leaked.messages = [
    { index: 0, side: "left" as const, text: "週六有空嗎？" },
    { index: 1, side: "right" as const, text: "有空，週六下午要不要一起喝杯咖啡？" },
  ];
  let judgeCalls = 0;
  const error = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: null, secondary: null },
        priorTurn: {
          offeredTexts: [
            "有空，週六下午要不要一起喝杯咖啡？",
            "有空，你是想約白天還是晚上？",
          ],
          insertedText: null,
        },
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () => Promise.resolve(leaked),
        judge: () => {
          judgeCalls += 1;
          return Promise.resolve(judged);
        },
        renewLease: () => Promise.resolve(true),
        nowMs: () => 1000,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(error.code, "unsupported_conversation");
  assertEquals(judgeCalls, 0);
});

Deno.test("a suggestion the user sent is treated as real conversation", async () => {
  const sent = "有空，週六下午要不要一起喝杯咖啡？";
  const followUp = compilerOutput();
  followUp.messages = [
    { index: 0, side: "left" as const, text: "週六有空嗎？" },
    { index: 1, side: "right" as const, text: sent },
  ];
  const result = await runKeyboardAssistPipeline({
    image,
    speakerOverride: "none",
    voice: { primary: "steady", secondary: null },
    priorTurn: {
      offeredTexts: [sent, "有空，你是想約白天還是晚上？"],
      insertedText: sent,
    },
    pipelineVersion: "compiler-judge-v1",
    signal: new AbortController().signal,
    compiler: () => Promise.resolve(followUp),
    judge: () => Promise.resolve(judged),
    renewLease: () => Promise.resolve(true),
    nowMs: () => 1000,
    deadlineAtMs: 41_000,
  });
  assertEquals(result.status, "ready");
});

Deno.test("the prior turn reaches the compiler and never the judge", async () => {
  const priorTurn = {
    offeredTexts: ["有空，你是想約白天還是晚上？"],
    insertedText: null,
  };
  let compilerSaw: unknown = "unset";
  let judgeSaw: unknown = "unset";
  await runKeyboardAssistPipeline({
    image,
    speakerOverride: "none",
    voice: { primary: "steady", secondary: null },
    priorTurn,
    pipelineVersion: "compiler-judge-v1",
    signal: new AbortController().signal,
    compiler: (request) => {
      compilerSaw = (request as { priorTurn: unknown }).priorTurn;
      return Promise.resolve(compilerOutput());
    },
    judge: (request) => {
      judgeSaw = (request as Record<string, unknown>).priorTurn;
      return Promise.resolve(judged);
    },
    renewLease: () => Promise.resolve(true),
    nowMs: () => 1000,
    deadlineAtMs: 41_000,
  });
  assertEquals(compilerSaw, priorTurn);
  assertEquals(judgeSaw, undefined);
});

Deno.test("lost lease and insufficient judge budget stop the stale worker", async () => {
  const stale = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: null, secondary: null },
        priorTurn: null,
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () => Promise.resolve(compilerOutput()),
        judge: () => Promise.resolve(judged),
        renewLease: () => Promise.resolve(false),
        nowMs: () => 1000,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(stale.code, "stale_owner");

  const deadline = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: null, secondary: null },
        priorTurn: null,
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () => Promise.resolve(compilerOutput()),
        judge: () => Promise.resolve(judged),
        renewLease: () => Promise.resolve(true),
        nowMs: () => 37_500,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(deadline.code, "provider_timeout");
});

Deno.test("provider timeout remains distinct from invalid structured output", async () => {
  const timeout = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: null, secondary: null },
        priorTurn: null,
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () =>
          Promise.reject(
            new KeyboardAssistProviderError("timeout", "upstream timeout"),
          ),
        judge: () => Promise.resolve(judged),
        renewLease: () => Promise.resolve(true),
        nowMs: () => 1000,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(timeout.code, "provider_timeout");
});

Deno.test("compiler and judge obey their own absolute deadlines", async () => {
  let compilerCalls = 0;
  const compilerFence = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: null, secondary: null },
        priorTurn: null,
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () => {
          compilerCalls++;
          return Promise.resolve(compilerOutput());
        },
        judge: () => Promise.resolve(judged),
        renewLease: () => Promise.resolve(true),
        nowMs: () => 1000,
        compilerDeadlineAtMs: 999,
        judgeDeadlineAtMs: 36_000,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(compilerFence.code, "provider_timeout");
  assertEquals(compilerCalls, 0);

  const judgeFence = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: null, secondary: null },
        priorTurn: null,
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () => Promise.resolve(compilerOutput()),
        judge: () => Promise.resolve(judged),
        renewLease: () => Promise.resolve(true),
        nowMs: () => 32_500,
        compilerDeadlineAtMs: 35_000,
        judgeDeadlineAtMs: 36_000,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(judgeFence.code, "provider_timeout");
});

Deno.test("judge cannot replace grounded candidates with invented reply text", async () => {
  const invented = {
    ...judged,
    options: judged.options.map((option, index) =>
      index === 0 ? { ...option, text: "我記得你上次說你住台北" } : option
    ),
  };
  const error = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: "steady", secondary: null },
        priorTurn: null,
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () => Promise.resolve(compilerOutput()),
        judge: () => Promise.resolve(invented),
        renewLease: () => Promise.resolve(true),
        nowMs: () => 1000,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(error.code, "provider_invalid_output");
});

Deno.test("off-screen compiler facts fail before judge", async () => {
  const hallucinated = compilerOutput();
  hallucinated.candidates[0].text = "上次在台北那家店很好玩";
  let judgeCalls = 0;

  const error = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: null, secondary: null },
        priorTurn: null,
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () => Promise.resolve(hallucinated),
        judge: () => {
          judgeCalls++;
          return Promise.resolve(judged);
        },
        renewLease: () => Promise.resolve(true),
        nowMs: () => 1000,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );

  assertEquals(error.code, "provider_invalid_output");
  assertEquals(judgeCalls, 0);
});

Deno.test("judge cannot invent off-screen facts in why or effect", async () => {
  const inventedExplanation = {
    ...judged,
    options: judged.options.map((option, index) =>
      index === 0
        ? { ...option, why: "承接上次在台北的共同回憶" }
        : index === 1
        ? { ...option, effect: "方便明天推進" }
        : option
    ),
  };

  const error = await assertRejects(
    () =>
      runKeyboardAssistPipeline({
        image,
        speakerOverride: "none",
        voice: { primary: "steady", secondary: null },
        priorTurn: null,
        pipelineVersion: "compiler-judge-v1",
        signal: new AbortController().signal,
        compiler: () => Promise.resolve(compilerOutput()),
        judge: () => Promise.resolve(inventedExplanation),
        renewLease: () => Promise.resolve(true),
        nowMs: () => 1000,
        deadlineAtMs: 41_000,
      }),
    KeyboardAssistPipelineError,
  );

  assertEquals(error.code, "provider_invalid_output");
});

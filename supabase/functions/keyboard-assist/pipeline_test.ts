import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  KEYBOARD_ASSIST_UNGROUNDED_CUE_FALLBACK,
  KeyboardAssistPipelineError,
  runKeyboardAssistPipeline,
} from "./pipeline.ts";
import { KeyboardAssistProviderError } from "./provider.ts";

const image = {
  bytes: new Uint8Array([1, 2, 3]),
  base64: "AQID",
  mediaType: "image/png" as const,
};

const PIPELINE_VERSION = "compiler-only-v1";

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
        strategy: "extend" as const,
        text: "有啊，你有什麼想法？",
        why: "先接住對方的問題",
        effect: "自然延續",
        evidenceIndices: [0],
      },
      {
        strategy: "flirt" as const,
        text: "有空，聽起來你已經有計畫了 😄",
        why: "接住邀約感並增加溫度",
        effect: "互動感較高",
        evidenceIndices: [0],
      },
      {
        strategy: "humor" as const,
        text: "有空，你是想約白天還是晚上？",
        why: "把球輕輕丟回去",
        effect: "節奏最輕",
        evidenceIndices: [0],
      },
    ],
  };
}

function run(
  overrides: Partial<Parameters<typeof runKeyboardAssistPipeline>[0]> = {},
) {
  return runKeyboardAssistPipeline({
    image,
    speakerOverride: "none",
    voice: { primary: null, secondary: null },
    priorTurn: null,
    pipelineVersion: PIPELINE_VERSION,
    signal: new AbortController().signal,
    compiler: () => Promise.resolve(compilerOutput()),
    renewLease: () => Promise.resolve(true),
    nowMs: () => 1000,
    deadlineAtMs: 41_000,
    ...overrides,
  });
}

Deno.test("one model call produces the whole served result", async () => {
  let compilerCalls = 0;
  const renewStages: string[] = [];
  const stageTimings: Record<string, number> = {};
  let nowMs = 1000;

  const result = await run({
    voice: { primary: "steady", secondary: null },
    compiler: (request) => {
      compilerCalls++;
      nowMs += 320;
      assertEquals(request.image, image);
      assertEquals(request.voice, { primary: "steady", secondary: null });
      return Promise.resolve(compilerOutput());
    },
    renewLease: (stage) => {
      renewStages.push(stage);
      return Promise.resolve(true);
    },
    recordStageTiming: (timing) => Object.assign(stageTimings, timing),
    nowMs: () => nowMs,
  });

  assertEquals(compilerCalls, 1);
  assertEquals(renewStages, ["after_compiler"]);
  assertEquals(stageTimings, { compilerMs: 320 });
  assertEquals(result, {
    contractVersion: "keyboard-assist-v1",
    status: "ready",
    source: {
      scope: "screenshot_plus_global_voice",
      messageCount: 2,
      confidence: "high",
      sideConfidence: "high",
    },
    turnState: "reply_due",
    cue: "對方剛問你週六是否有空。",
    uncertainty: null,
    options: [
      {
        strategy: "extend",
        text: "有啊，你有什麼想法？",
        why: "先接住對方的問題",
        effect: "自然延續",
      },
      {
        strategy: "flirt",
        text: "有空，聽起來你已經有計畫了 😄",
        why: "接住邀約感並增加溫度",
        effect: "互動感較高",
      },
      {
        strategy: "humor",
        text: "有空，你是想約白天還是晚上？",
        why: "把球輕輕丟回去",
        effect: "節奏最輕",
      },
    ],
  });
  // The transcript is working material, not something the user asked for.
  assert(!JSON.stringify(result).includes("evidenceIndices"));
});

Deno.test("an unsure read on which side is me no longer stops the reply", async () => {
  // Every mainstream chat app puts the user on the right, so a low-confidence
  // read is a reason to keep going, not a question to interrupt with. Stopping
  // here made an ordinary screenshot dead-end after the work was already paid
  // for.
  const result = await run({
    compiler: () => Promise.resolve(compilerOutput("low")),
  });

  assertEquals(result.status, "ready");
  if (result.status !== "ready") throw new Error("expected a ready result");
  assertEquals(result.source.sideConfidence, "low");
  assertEquals(result.options.length, 3);
});

Deno.test("a group chat is served like any other conversation", async () => {
  // A misfired group verdict was the single most common way a real two-person
  // screenshot died, and the user had no way to argue with it.
  const result = await run({
    compiler: () =>
      Promise.resolve({
        ...compilerOutput(),
        conversationType: "group" as const,
      }),
  });

  assertEquals(result.status, "ready");
});

Deno.test("a screen with nothing to reply to is still refused, and says which", async () => {
  for (const conversationType of ["social_feed", "non_chat"] as const) {
    const error = await assertRejects(
      () =>
        run({
          compiler: () =>
            Promise.resolve({
              ...compilerOutput(),
              conversationType,
              cue: "行程公告",
              messages: [],
              candidates: [],
            }),
        }),
      KeyboardAssistPipelineError,
    );
    assertEquals(error.code, "unsupported_conversation");
    // The verdict token must survive to telemetry: "there is no conversation
    // here" and "we saw our own panel quoted back" share an error code but need
    // opposite fixes.
    assertEquals(error.detail, conversationType);
  }
});

Deno.test("our own prior candidates read back as chat stop before a charge", async () => {
  const leaked = compilerOutput();
  // The keyboard trims its own panel out of the capture, but a geometry
  // mismatch can leave a previous candidate behind; that transcript describes
  // our UI, not the conversation.
  leaked.messages = [
    { index: 0, side: "left" as const, text: "週六有空嗎？" },
    {
      index: 1,
      side: "right" as const,
      text: "有空，週六下午要不要一起喝杯咖啡？",
    },
  ];

  const error = await assertRejects(
    () =>
      run({
        priorTurn: {
          offeredTexts: [
            "有空，週六下午要不要一起喝杯咖啡？",
            "有空，你是想約白天還是晚上？",
          ],
          insertedText: null,
        },
        compiler: () => Promise.resolve(leaked),
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(error.code, "unsupported_conversation");
  assertEquals(error.detail, "own_prior_candidates");
});

Deno.test("a suggestion the user sent is treated as real conversation", async () => {
  const sent = "有空，週六下午要不要一起喝杯咖啡？";
  const followUp = compilerOutput();
  followUp.messages = [
    { index: 0, side: "left" as const, text: "週六有空嗎？" },
    { index: 1, side: "right" as const, text: sent },
  ];

  const result = await run({
    priorTurn: {
      offeredTexts: [sent, "有空，你是想約白天還是晚上？"],
      insertedText: sent,
    },
    compiler: () => Promise.resolve(followUp),
  });
  assertEquals(result.status, "ready");
});

Deno.test("the prior turn reaches the compiler, which is what dedupes a new batch", async () => {
  // "換一批" is the same call again with what the user has already seen, so the
  // dedupe list has to arrive at the only stage there is.
  const priorTurn = {
    offeredTexts: ["有空，你是想約白天還是晚上？"],
    insertedText: null,
  };
  let compilerSaw: unknown = "unset";

  await run({
    priorTurn,
    compiler: (request) => {
      compilerSaw = request.priorTurn;
      return Promise.resolve(compilerOutput());
    },
  });
  assertEquals(compilerSaw, priorTurn);
});

Deno.test("a lost lease stops the stale worker before it returns a result", async () => {
  const stale = await assertRejects(
    () => run({ renewLease: () => Promise.resolve(false) }),
    KeyboardAssistPipelineError,
  );
  assertEquals(stale.code, "stale_owner");
});

Deno.test("provider timeout remains distinct from invalid structured output", async () => {
  const timeout = await assertRejects(
    () =>
      run({
        compiler: () =>
          Promise.reject(
            new KeyboardAssistProviderError("timeout", "upstream timeout"),
          ),
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(timeout.code, "provider_timeout");
});

Deno.test("the compiler obeys its own absolute deadline", async () => {
  let compilerCalls = 0;
  const beforeStart = await assertRejects(
    () =>
      run({
        compiler: () => {
          compilerCalls++;
          return Promise.resolve(compilerOutput());
        },
        compilerDeadlineAtMs: 999,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(beforeStart.code, "provider_timeout");
  assertEquals(compilerCalls, 0);

  let nowMs = 1000;
  const overran = await assertRejects(
    () =>
      run({
        compiler: () => {
          nowMs = 36_000;
          return Promise.resolve(compilerOutput());
        },
        nowMs: () => nowMs,
        compilerDeadlineAtMs: 35_000,
      }),
    KeyboardAssistPipelineError,
  );
  assertEquals(overran.code, "provider_timeout");
});

Deno.test("an invented reply is refused rather than served", async () => {
  // With one batch there is no slack: one unusable reply already leaves fewer
  // than three, so there is nothing worth charging for.
  const mostlyInvented = compilerOutput();
  mostlyInvented.candidates[0].text = "上次在台北那家店很好玩";

  const error = await assertRejects(
    () => run({ compiler: () => Promise.resolve(mostlyInvented) }),
    KeyboardAssistPipelineError,
  );
  assertEquals(error.code, "provider_invalid_output");
  assertEquals(error.detail, "compiler_grounding_candidate");

  const uncited = compilerOutput();
  uncited.candidates[0].evidenceIndices = [99];
  const invalid = await assertRejects(
    () => run({ compiler: () => Promise.resolve(uncited) }),
    KeyboardAssistPipelineError,
  );
  assertEquals(invalid.detail, "compiler_grounding_candidate");
});

Deno.test("a batch missing one of the three angles says so by name", async () => {
  // The final validator would reject this anyway, but as a nameless 503. The
  // token is what turns "it failed again" into a diagnosable row.
  const collided = compilerOutput();
  collided.candidates[1] = {
    ...collided.candidates[1],
    strategy: "extend" as const,
  };

  const error = await assertRejects(
    () => run({ compiler: () => Promise.resolve(collided) }),
    KeyboardAssistPipelineError,
  );
  assertEquals(error.code, "provider_invalid_output");
  assertEquals(error.detail, "compiler_strategy_collision");
});

Deno.test("an invented explanation is replaced, never served", async () => {
  // The explanation is our commentary on a reply, not the reply. It still must
  // never carry a fact from outside the screenshot to the user — but throwing
  // the whole screenshot away over a sentence of colour is the wrong price.
  const invented = compilerOutput();
  invented.candidates[0].why = "承接上次在台北的共同回憶";
  invented.candidates[1].effect = "方便明天推進";

  const result = await run({
    voice: { primary: "steady", secondary: null },
    compiler: () => Promise.resolve(invented),
  });

  if (result.status !== "ready") throw new Error("expected a ready result");
  const wire = JSON.stringify(result);
  assert(!wire.includes("上次在台北"), "off-screen fact reached the user");
  assert(!wire.includes("方便明天推進"), "off-screen fact reached the user");
  // The replies themselves are untouched; only the explanations changed.
  assertEquals(
    result.options.map((option) => option.text),
    compilerOutput().candidates.map((candidate) => candidate.text),
  );
});

Deno.test("an ungrounded cue is swapped for a factless line, not a failure", async () => {
  const invented = compilerOutput();
  invented.cue = "你們上次在台北聊過這件事";

  const result = await run({ compiler: () => Promise.resolve(invented) });

  if (result.status !== "ready") throw new Error("expected a ready result");
  assertEquals(result.cue, KEYBOARD_ASSIST_UNGROUNDED_CUE_FALLBACK);
  assertEquals(result.options.length, 3);
});

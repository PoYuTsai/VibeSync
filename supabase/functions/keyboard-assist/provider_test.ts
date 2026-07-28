import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { KEYBOARD_ASSIST_COMPILER_PROMPT } from "./compiler_prompt.ts";
import {
  createAnthropicKeyboardAssistProvider,
  KEYBOARD_ASSIST_COMPILER_TIMEOUT_MS,
  KeyboardAssistProviderError,
} from "./provider.ts";

const PIPELINE_VERSION = "compiler-only-v1";

const compilerJson = {
  conversationType: "chat",
  suggestedMySide: "right",
  sideConfidence: "high",
  confidence: "high",
  turnState: "reply_due",
  cue: "對方在問時間。",
  uncertainty: null,
  messages: [{ index: 0, side: "left", text: "週六有空嗎" }],
  candidates: ["extend", "flirt", "humor"].map((strategy, index) => ({
    strategy,
    text: `候選 ${index + 1}`,
    why: "順著對方的問題接",
    effect: "保持自然",
    evidenceIndices: [0],
  })),
};

Deno.test("the prompt declares screenshot-only truth and untrusted evidence", () => {
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("只有這一張截圖"));
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("不要推測截圖外"));
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("voice 只能調整候選措辭"));
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("不可信資料"));
  // Every analysed capture is now taken with our own panel on screen and its
  // bottom trimmed off, so "few messages visible" is the normal case rather
  // than evidence that this is not a conversation.
  assert(
    KEYBOARD_ASSIST_COMPILER_PROMPT.includes(
      "不要因為訊息很少或畫面被截斷就改判 non_chat",
    ),
  );
});

Deno.test("one call now owns the whole result, explanations included", () => {
  // The judge's only remaining contribution was `why` and `effect`; it could
  // neither rewrite a reply nor add one. Asking for them here is what let the
  // second model call go away.
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("正好三個"));
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("extend＝延展"));
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("flirt＝調情"));
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("humor＝幽默"));
  assert(
    KEYBOARD_ASSIST_COMPILER_PROMPT.includes("每個候選還要附上 why 與 effect"),
  );
  assert(
    KEYBOARD_ASSIST_COMPILER_PROMPT.includes(
      "candidate 正好包含 strategy, text, why, effect, evidenceIndices",
    ),
  );
});

Deno.test("a group is described, not turned away, and the side has a default", () => {
  // Both of these were hard stops that killed ordinary screenshots: a misfired
  // group verdict, and an unsure read on which side is the user.
  assert(
    KEYBOARD_ASSIST_COMPILER_PROMPT.includes(
      "chat 與 group 都要照樣產出候選",
    ),
  );
  assert(
    KEYBOARD_ASSIST_COMPILER_PROMPT.includes(
      '預設 suggestedMySide 就是 "right"',
    ),
  );
  assert(
    KEYBOARD_ASSIST_COMPILER_PROMPT.includes("無論高低都要照常產出候選"),
  );
  // A manual correction still wins: it is the only way a user can argue with
  // the layout guess, and it used to be applied at the removed judge stage.
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("speakerOverride"));
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("以使用者說的為準"));
});

Deno.test("Anthropic compiler sends one image and forwards cancellation", async () => {
  const bodies: Array<Record<string, unknown>> = [];
  const signals: AbortSignal[] = [];
  const provider = createAnthropicKeyboardAssistProvider({
    apiKey: "test-key",
    compilerModel: "vision-model",
    fetchImpl: (_input, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      signals.push(init?.signal as AbortSignal);
      return Promise.resolve(
        new Response(
          JSON.stringify({
            content: [{ type: "text", text: JSON.stringify(compilerJson) }],
            stop_reason: "end_turn",
          }),
          { status: 200 },
        ),
      );
    },
  });
  const controller = new AbortController();
  const result = await provider.compiler({
    image: {
      bytes: new Uint8Array([1, 2, 3]),
      base64: "AQID",
      mediaType: "image/png",
    },
    speakerOverride: "none",
    voice: { primary: "playful", secondary: null },
    priorTurn: null,
    signal: controller.signal,
    pipelineVersion: PIPELINE_VERSION,
  });
  assertEquals(result, compilerJson);
  assertEquals(bodies[0].model, "vision-model");
  assertEquals(
    (bodies[0].output_config as {
      format: { type: string };
    }).format.type,
    "json_schema",
  );
  const wire = JSON.stringify(bodies[0]);
  assertEquals((wire.match(/"type":"image"/g) ?? []).length, 1);
  assert(wire.includes("AQID"));
  assert(wire.includes("playful"));
  assertEquals(signals[0].aborted, false);
});

Deno.test("the previous batch travels with the request so a new one can differ", async () => {
  // "換一批" is this same call again. Without the lines the user has already
  // seen, a second run has no way to avoid repeating itself.
  const bodies: Array<Record<string, unknown>> = [];
  const provider = createAnthropicKeyboardAssistProvider({
    apiKey: "test-key",
    compilerModel: "vision-model",
    fetchImpl: (_input, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      return Promise.resolve(
        new Response(
          JSON.stringify({
            content: [{ type: "text", text: JSON.stringify(compilerJson) }],
            stop_reason: "end_turn",
          }),
          { status: 200 },
        ),
      );
    },
  });

  await provider.compiler({
    image: {
      bytes: new Uint8Array([1, 2, 3]),
      base64: "AQID",
      mediaType: "image/png",
    },
    speakerOverride: "right_is_me",
    voice: { primary: null, secondary: null },
    priorTurn: { offeredTexts: ["上一批給過的句子"], insertedText: null },
    signal: new AbortController().signal,
    pipelineVersion: PIPELINE_VERSION,
  });

  const wire = JSON.stringify(bodies[0]);
  assert(wire.includes("上一批給過的句子"));
  assert(wire.includes("right_is_me"));
});

Deno.test("Sonnet 5 disables thinking and omits unsupported sampling parameters", async () => {
  const bodies: Array<Record<string, unknown>> = [];
  const provider = createAnthropicKeyboardAssistProvider({
    apiKey: "test-key",
    compilerModel: "claude-sonnet-5",
    fetchImpl: (_input, init) => {
      bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      return Promise.resolve(
        new Response(
          JSON.stringify({
            content: [{ type: "text", text: JSON.stringify(compilerJson) }],
            stop_reason: "end_turn",
          }),
          { status: 200 },
        ),
      );
    },
  });

  await provider.compiler({
    image: {
      bytes: new Uint8Array([1, 2, 3]),
      base64: "AQID",
      mediaType: "image/png",
    },
    speakerOverride: "none",
    voice: { primary: "steady", secondary: null },
    priorTurn: null,
    signal: new AbortController().signal,
    pipelineVersion: PIPELINE_VERSION,
  });

  assertEquals(bodies.length, 1);
  assertEquals(bodies[0].temperature, undefined);
  assertEquals(bodies[0].thinking, { type: "disabled" });
});

Deno.test("Anthropic structured-output schema uses only supported constraints", async () => {
  const bodies: Array<Record<string, unknown>> = [];
  const provider = createAnthropicKeyboardAssistProvider({
    apiKey: "test-key",
    compilerModel: "vision-model",
    fetchImpl: (_input, init) => {
      bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      return Promise.resolve(
        new Response(
          JSON.stringify({
            content: [{ type: "text", text: JSON.stringify(compilerJson) }],
            stop_reason: "end_turn",
          }),
          { status: 200 },
        ),
      );
    },
  });

  await provider.compiler({
    image: {
      bytes: new Uint8Array([1, 2, 3]),
      base64: "AQID",
      mediaType: "image/png",
    },
    speakerOverride: "none",
    voice: { primary: "steady", secondary: null },
    priorTurn: null,
    signal: new AbortController().signal,
    pipelineVersion: PIPELINE_VERSION,
  });

  assertEquals(bodies.length, 1);
  const schema = (bodies[0].output_config as {
    format: { schema: Record<string, unknown> };
  }).format.schema;
  const wire = JSON.stringify(schema);
  for (
    const unsupported of [
      "minimum",
      "maximum",
      "minLength",
      "maxLength",
      "minItems",
      "maxItems",
    ]
  ) {
    assert(
      !wire.includes(`"${unsupported}"`),
      `schema must not send unsupported Anthropic keyword ${unsupported}`,
    );
  }
  assert(wire.includes('"required"'));
  assert(wire.includes('"additionalProperties":false'));
  assert(wire.includes('"enum"'));
  assert(wire.includes('"anyOf":[{"type":"string"},{"type":"null"}]'));
  // The explanations are part of this call's contract now, not a second one's.
  assert(
    wire.includes(
      '"required":["strategy","text","why","effect","evidenceIndices"]',
    ),
  );
});

Deno.test("a failed model call says why, in a token safe to log", async () => {
  // "service_unavailable" was the whole story for a request that had already
  // spent fourteen seconds of model time. A status code carries no transcript,
  // so there is no reason for it not to reach telemetry.
  const cases: Array<[number, string]> = [
    [401, "http_401"],
    [429, "http_429"],
    [529, "http_529"],
    [418, "http_other"],
  ];
  for (const [status, expected] of cases) {
    const provider = createAnthropicKeyboardAssistProvider({
      apiKey: "test-key",
      compilerModel: "vision-model",
      fetchImpl: () => Promise.resolve(new Response("nope", { status })),
    });
    const error = await assertRejects(
      () =>
        provider.compiler({
          image: {
            bytes: new Uint8Array([1]),
            base64: "AQ==",
            mediaType: "image/png",
          },
          speakerOverride: "none",
          voice: { primary: null, secondary: null },
          priorTurn: null,
          signal: new AbortController().signal,
          pipelineVersion: PIPELINE_VERSION,
        }),
      KeyboardAssistProviderError,
    );
    assertEquals(error.failure, expected);
  }

  // Deno's fetch resolves once headers arrive, so a throw here means the
  // connection died after the model had already spent its time — a different
  // problem from a rejected request, and previously indistinguishable.
  const dropped = createAnthropicKeyboardAssistProvider({
    apiKey: "test-key",
    compilerModel: "vision-model",
    fetchImpl: () => Promise.reject(new TypeError("connection reset")),
  });
  const error = await assertRejects(
    () =>
      dropped.compiler({
        image: {
          bytes: new Uint8Array([1]),
          base64: "AQ==",
          mediaType: "image/png",
        },
        speakerOverride: "none",
        voice: { primary: null, secondary: null },
        priorTurn: null,
        signal: new AbortController().signal,
        pipelineVersion: PIPELINE_VERSION,
      }),
    KeyboardAssistProviderError,
  );
  assertEquals(error.failure, "fetch_failed");
});

Deno.test("the single call's cap fits inside the request deadline", () => {
  // The one call now writes the transcript, the read, three replies and their
  // explanations, so it inherits the budget both stages used to share. It must
  // still fit inside the handler's compiler phase deadline (start + 35s).
  assert(KEYBOARD_ASSIST_COMPILER_TIMEOUT_MS >= 24_000);
  assert(KEYBOARD_ASSIST_COMPILER_TIMEOUT_MS <= 35_000);
});

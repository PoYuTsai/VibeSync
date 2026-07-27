import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { KEYBOARD_ASSIST_COMPILER_PROMPT } from "./compiler_prompt.ts";
import { KEYBOARD_ASSIST_JUDGE_PROMPT } from "./judge_prompt.ts";
import {
  createAnthropicKeyboardAssistProvider,
  type KeyboardAssistJudgeRequest,
} from "./provider.ts";
import type { NormalizedKeyboardAssistCompilerOutput } from "./normalize.ts";

const compilerJson = {
  conversationType: "chat",
  suggestedMySide: "right",
  sideConfidence: "high",
  confidence: "high",
  turnState: "reply_due",
  cue: "對方在問時間。",
  uncertainty: null,
  messages: [{ index: 0, side: "left", text: "週六有空嗎" }],
  candidates: Array.from({ length: 6 }, (_, index) => ({
    strategy: [
      "keep_pace",
      "build_connection",
      "move_forward",
      "clarify",
      "deescalate",
      "keep_pace",
    ][index],
    text: `候選 ${index + 1}`,
    evidenceIndices: [0],
  })),
};

Deno.test("prompts declare screenshot-only truth and untrusted evidence", () => {
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("只有這一張截圖"));
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("不要推測截圖外"));
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes("voice 只能調整候選措辭"));
  // Every analysed capture is now taken with our own panel on screen and its
  // bottom trimmed off, so "few messages visible" is the normal case rather
  // than evidence that this is not a one-to-one chat.
  assert(KEYBOARD_ASSIST_COMPILER_PROMPT.includes('一對一對話請輸出 "chat"'));
  assert(
    KEYBOARD_ASSIST_COMPILER_PROMPT.includes("不要因為訊息很少、畫面被"),
  );
  assert(KEYBOARD_ASSIST_JUDGE_PROMPT.includes("不可信資料"));
  assert(KEYBOARD_ASSIST_JUDGE_PROMPT.includes("兩批各 3 個"));
  // The second batch is what "換一批" serves without a second charge, so it is
  // held to the same bar rather than treated as leftovers.
  assert(KEYBOARD_ASSIST_JUDGE_PROMPT.includes("alternates 要能獨立"));
  assert(KEYBOARD_ASSIST_JUDGE_PROMPT.includes("兩批之間\n的 text 不得重複"));
  assert(KEYBOARD_ASSIST_JUDGE_PROMPT.includes("證據索引"));
  assert(
    KEYBOARD_ASSIST_JUDGE_PROMPT.includes("voice 只調整措辭，不增加事實"),
  );
  assert(
    KEYBOARD_ASSIST_JUDGE_PROMPT.includes("clarify＝在資訊不足時先確認"),
  );
});

Deno.test("Anthropic compiler sends one image and forwards cancellation", async () => {
  const bodies: Array<Record<string, unknown>> = [];
  const signals: AbortSignal[] = [];
  const provider = createAnthropicKeyboardAssistProvider({
    apiKey: "test-key",
    compilerModel: "vision-model",
    judgeModel: "judge-model",
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
    pipelineVersion: "compiler-judge-v1",
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

Deno.test("Anthropic judge is text-only and never receives image base64", async () => {
  const bodies: Array<Record<string, unknown>> = [];
  const provider = createAnthropicKeyboardAssistProvider({
    apiKey: "test-key",
    compilerModel: "vision-model",
    judgeModel: "judge-model",
    fetchImpl: (_input, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      return Promise.resolve(
        new Response(
          JSON.stringify({
            content: [{
              type: "text",
              text: JSON.stringify({
                contractVersion: "keyboard-assist-v1",
                status: "ready",
              }),
            }],
            stop_reason: "end_turn",
          }),
          { status: 200 },
        ),
      );
    },
  });
  const request: KeyboardAssistJudgeRequest = {
    conversation: compilerJson as NormalizedKeyboardAssistCompilerOutput,
    effectiveMySide: "right",
    voice: { primary: "steady", secondary: null },
    signal: new AbortController().signal,
    pipelineVersion: "compiler-judge-v1",
  };
  await provider.judge(request);
  assertEquals(bodies[0].model, "judge-model");
  assertEquals(
    (bodies[0].output_config as {
      format: { type: string };
    }).format.type,
    "json_schema",
  );
  const wire = JSON.stringify(bodies[0]);
  assert(!wire.includes('"type":"image"'));
  assert(!wire.includes("AQID"));
  assert(wire.includes("週六有空嗎"));
  assert(wire.includes("steady"));
});

Deno.test("Sonnet 5 disables thinking and omits unsupported sampling parameters", async () => {
  const bodies: Array<Record<string, unknown>> = [];
  const provider = createAnthropicKeyboardAssistProvider({
    apiKey: "test-key",
    compilerModel: "claude-sonnet-5",
    judgeModel: "claude-sonnet-5",
    fetchImpl: (_input, init) => {
      const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
      bodies.push(body);
      const responseBody = bodies.length === 1 ? compilerJson : {
        contractVersion: "keyboard-assist-v1",
        status: "ready",
      };
      return Promise.resolve(
        new Response(
          JSON.stringify({
            content: [{ type: "text", text: JSON.stringify(responseBody) }],
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
    pipelineVersion: "compiler-judge-v1",
  });
  await provider.judge({
    conversation: compilerJson as NormalizedKeyboardAssistCompilerOutput,
    effectiveMySide: "right",
    voice: { primary: "steady", secondary: null },
    signal: new AbortController().signal,
    pipelineVersion: "compiler-judge-v1",
  });

  assertEquals(bodies.length, 2);
  for (const body of bodies) {
    assertEquals(body.temperature, undefined);
    assertEquals(body.thinking, { type: "disabled" });
  }
});

Deno.test("Anthropic structured-output schemas use only supported constraints", async () => {
  const bodies: Array<Record<string, unknown>> = [];
  const provider = createAnthropicKeyboardAssistProvider({
    apiKey: "test-key",
    compilerModel: "vision-model",
    judgeModel: "judge-model",
    fetchImpl: (_input, init) => {
      const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
      bodies.push(body);
      const responseBody = body.model === "vision-model" ? compilerJson : {
        contractVersion: "keyboard-assist-v1",
        status: "ready",
      };
      return Promise.resolve(
        new Response(
          JSON.stringify({
            content: [{ type: "text", text: JSON.stringify(responseBody) }],
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
    pipelineVersion: "compiler-judge-v1",
  });
  await provider.judge({
    conversation: compilerJson as NormalizedKeyboardAssistCompilerOutput,
    effectiveMySide: "right",
    voice: { primary: "steady", secondary: null },
    signal: new AbortController().signal,
    pipelineVersion: "compiler-judge-v1",
  });

  assertEquals(bodies.length, 2);
  for (const body of bodies) {
    const schema = (body.output_config as {
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
    assert(wire.includes('"enum"') || wire.includes('"const"'));
  }

  const compilerWire = JSON.stringify(
    (bodies[0].output_config as { format: { schema: unknown } }).format.schema,
  );
  const judgeWire = JSON.stringify(
    (bodies[1].output_config as { format: { schema: unknown } }).format.schema,
  );
  assert(compilerWire.includes('"anyOf":[{"type":"string"},{"type":"null"}]'));
  assert(judgeWire.includes('"const":"keyboard-assist-v1"'));
  assert(judgeWire.includes('"const":"ready"'));
});

// v3 的正式模型呼叫：對象記憶那一次的請求形狀、只打一次、ai_logs 分開記；開關沒開
// 就根本沒有這個呼叫。fetch 是替身，不連網。
import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { SONNET_5_5_MODEL } from "../../_shared/model_request_params.ts";
import type { ProviderAttemptLogEntry } from "../model_call_budget.ts";
import { MEMORY_SCHEMA } from "./memory.ts";
import {
  createGuideV3ModelCalls,
  GUIDE_V3_MEMORY_MAX_TOKENS,
  GUIDE_V3_MEMORY_MODEL,
  GUIDE_V3_MEMORY_REQUEST_TYPE,
} from "./model_calls.ts";

type Body = Record<string, unknown> & {
  system: { text: string; cache_control?: unknown }[];
};

async function withFetch<T>(
  respond: () => Response,
  run: (bodies: Body[]) => Promise<T>,
): Promise<T> {
  const original = globalThis.fetch;
  const bodies: Body[] = [];
  globalThis.fetch = (_input, init) => {
    bodies.push(JSON.parse(String(init?.body)));
    return Promise.resolve(respond());
  };
  try {
    return await run(bodies);
  } finally {
    globalThis.fetch = original;
  }
}

const ok = () =>
  Response.json({
    content: [{
      type: "text",
      text: '{"interests":[],"traits":[],"notes":[]}',
    }],
    stop_reason: "end_turn",
    usage: {
      input_tokens: 900,
      output_tokens: 40,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
    },
  });

const request = () => ({
  runId: "run-1",
  system: "記憶系統提示",
  user: "## 對話\n第 1 輪・她：\n- 我每個週末都會去爬山",
  schema: MEMORY_SCHEMA,
  deadlineAtMs: Date.now() + 60_000,
});

function calls(memory?: boolean, memoryModel?: string) {
  const logs: ProviderAttemptLogEntry[] = [];
  return {
    logs,
    ...createGuideV3ModelCalls({
      apiKey: "test-key",
      requestType: "analyze",
      tier: "essential",
      recordAiCall: (entry) => logs.push(entry),
      ...(memory === undefined ? {} : { memory }),
      ...(memoryModel ? { memoryModel } : {}),
    }),
  };
}

Deno.test("開關沒開：沒有記憶呼叫，流程不會多打這一次", () => {
  assertEquals("callExtract" in calls(), false);
  assertEquals("callExtract" in calls(false), false);
  assertEquals(typeof calls(true).callExtract, "function");
});

Deno.test("記憶呼叫：Haiku 5.5、json_schema、不帶思考、system 走快取", async () => {
  const c = calls(true);
  await withFetch(ok, async (bodies) => {
    const res = await c.callExtract!(request());
    assertEquals(res.model, GUIDE_V3_MEMORY_MODEL);
    assertEquals(res.text, '{"interests":[],"traits":[],"notes":[]}');
    assertEquals(bodies.length, 1);
    const body = bodies[0];
    assertEquals(body.model, "claude-haiku-5-5");
    assertEquals(body.max_tokens, GUIDE_V3_MEMORY_MAX_TOKENS);
    assertEquals(body.output_config, {
      format: { type: "json_schema", schema: MEMORY_SCHEMA },
    });
    assertEquals("thinking" in body, false);
    assertEquals("temperature" in body, false);
    assertEquals(body.system[0].text, "記憶系統提示");
    assertEquals(body.system[0].cache_control, { type: "ephemeral" });
    assertEquals(body.messages, [{ role: "user", content: request().user }]);
  });
  assertEquals(c.logs.length, 1);
  const log = c.logs[0];
  assertEquals(log.requestType, GUIDE_V3_MEMORY_REQUEST_TYPE);
  assertEquals(log.requestType, "analyze_memory");
  assertEquals(log.status, "success");
  assertEquals(log.inputTokens, 900);
  assertEquals(log.outputTokens, 40);
  const meta = log.requestBody as Record<string, unknown>;
  assertEquals(meta.stage, "memory");
  assertEquals(meta.purpose, "guide_v3_memory");
  assertEquals(meta.operation, "run-1");
});

Deno.test("記憶呼叫失敗：不重試、不換模型（只打一次），ai_logs 記失敗", async () => {
  const c = calls(true);
  await withFetch(
    () =>
      Response.json({ error: { type: "overloaded_error" } }, { status: 529 }),
    async (bodies) => {
      await assertRejects(() => c.callExtract!(request()));
      assertEquals(bodies.length, 1);
    },
  );
  assertEquals(c.logs.length, 1);
  assertEquals(c.logs[0].requestType, "analyze_memory");
  assertEquals(c.logs[0].status, "failed");
});

Deno.test("黑箱的 Sonnet 5.5 臂照 production 參數：adaptive thinking、effort low、加思考餘裕", async () => {
  const c = calls(true, SONNET_5_5_MODEL);
  await withFetch(ok, async (bodies) => {
    await c.callExtract!(request());
    const body = bodies[0];
    assertEquals(body.model, SONNET_5_5_MODEL);
    assertEquals(body.thinking, { type: "adaptive", display: "omitted" });
    assertEquals(body.output_config, {
      format: { type: "json_schema", schema: MEMORY_SCHEMA },
      effort: "low",
    });
    assert((body.max_tokens as number) > GUIDE_V3_MEMORY_MAX_TOKENS);
  });
});

Deno.test("讀局面的 ai_logs 照舊記這次分析的 request_type", async () => {
  const c = calls(true);
  await withFetch(ok, async () => {
    await c.callRead({ ...request(), system: "讀局面", schema: {} });
  });
  assertEquals(c.logs.length, 1);
  assertEquals(c.logs[0].requestType, "analyze");
  assertEquals(
    (c.logs[0].requestBody as Record<string, unknown>).stage,
    "read",
  );
});

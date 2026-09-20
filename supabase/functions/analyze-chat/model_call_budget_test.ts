import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { ModelCallBudget, ModelCallBudgetError } from "./model_call_budget.ts";
import { AiServiceError, callClaudeWithFallback } from "./fallback.ts";
import { AiStreamingServiceError, callClaudeStreaming } from "./streaming_fallback.ts";

const request = { model: "claude-sonnet-5", max_tokens: 50, system: "fixture", messages: [{ role: "user", content: "synthetic" }] };
const rawUsage = { input_tokens: 10, output_tokens: 5, cache_creation_input_tokens: 20, cache_read_input_tokens: 30 };
const success = (stop_reason = "end_turn") => Response.json({ content: [{ type: "text", text: "{}" }], usage: rawUsage, stop_reason });

Deno.test("C03/C07: fallback and repair share three actual fetches; failed usage is retained once", async () => {
  const old = globalThis.fetch;
  const records: Record<string, unknown>[] = [];
  const budget = new ModelCallBudget(Date.now() + 1000, { stage: "analyze" }, (r) => records.push(r));
  let calls = 0;
  globalThis.fetch = () => Promise.resolve(++calls < 3 ? Response.json({ usage: rawUsage }, { status: 503 }) : success());
  try {
    await callClaudeWithFallback(request, "fake", { maxRetries: 1, budget });
    await assertRejects(() => callClaudeWithFallback(request, "fake", { maxRetries: 1, budget, purpose: "repair" }), ModelCallBudgetError);
    assertEquals(calls, 3);
    assertEquals(records.length, 3);
    assertEquals(records.map((r) => r.status), ["failed", "failed", "success"]);
    assertEquals(records.map((r) => r.model), ["claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]);
    for (const r of records) {
      assertEquals([r.inputTokens, r.cacheCreationTokens, r.cacheReadTokens, r.outputTokens], [10, 20, 30, 5]);
      assertEquals(r.usage_unknown, false);
      assert(typeof r.estimatedCostUsd === "number" && r.estimatedCostUsd > 0);
    }
  } finally { globalThis.fetch = old; }
});

Deno.test("C05/C07: refusal with usage is logged as failure, missing usage stays unknown", async () => {
  const old = globalThis.fetch;
  const records: Record<string, unknown>[] = [];
  const budget = new ModelCallBudget(Date.now() + 1000, {}, (r) => records.push(r));
  globalThis.fetch = () => Promise.resolve(success("refusal"));
  try {
    await assertRejects(() => callClaudeWithFallback(request, "fake", { maxRetries: 1, budget }), AiServiceError);
    globalThis.fetch = () => Promise.resolve(Response.json({ content: [], usage: { input_tokens: 0 } }));
    await callClaudeWithFallback(request, "fake", { budget });
    assertEquals(records[0].status, "failed");
    assertEquals(records[0].outputTokens, 5);
    assertEquals(records[1].inputTokens, 0);
    assertEquals(records[1].outputTokens, null);
    assertEquals(records[1].estimatedCostUsd, null);
    assertEquals(records[1].usage_unknown, true);
  } finally { globalThis.fetch = old; }
});

function sse(events: unknown[]) {
  return new Response(events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join(""));
}
const start = { type: "message_start", message: { usage: rawUsage } };
const text = { type: "content_block_delta", delta: { type: "text_delta", text: "ok" } };

Deno.test("C03/C07/C08: streaming overload usage plus fallback plus repair consumes same budget", async () => {
  const old = globalThis.fetch;
  const records: Record<string, unknown>[] = [];
  const budget = new ModelCallBudget(Date.now() + 1000, {}, (r) => records.push(r));
  let calls = 0;
  const result = await callClaudeStreaming(request, "fake", { budget, fetchImpl: () => Promise.resolve(
    ++calls === 1 ? sse([start, { type: "error", error: { type: "overloaded_error" } }])
      : sse([start, text, { type: "message_delta", usage: { output_tokens: 8 } }, { type: "message_stop" }]),
  ) });
  for await (const _ of result.textStream) { /* consume */ }
  globalThis.fetch = () => { calls++; return Promise.resolve(success()); };
  try {
    await callClaudeWithFallback(request, "fake", { maxRetries: 1, budget, purpose: "repair" });
    await assertRejects(() => callClaudeStreaming(request, "fake", { budget, fetchImpl: globalThis.fetch }), ModelCallBudgetError);
    assertEquals(calls, 3);
    assertEquals(records.map((r) => r.outputTokens), [5, 8, 5]);
    assertEquals(records.map((r) => r.status), ["failed", "success", "success"]);
    assertEquals(records[2].purpose, "repair");
  } finally { globalThis.fetch = old; }
});

Deno.test("C04: shared deadline stops streaming fallback instead of resetting timeout", async () => {
  const originalNow = Date.now;
  let now = originalNow();
  Date.now = () => now;
  const budget = new ModelCallBudget(now + 45_000, {}, () => {});
  let calls = 0;
  try {
    await assertRejects(() => callClaudeStreaming(request, "fake", {
      budget, timeout: 45_000,
      fetchImpl: () => { calls++; now += 45_001; return Promise.resolve(new Response(null, { status: 503 })); },
    }), AiStreamingServiceError);
    assertEquals(calls, 1);
    await assertRejects(() => callClaudeWithFallback(request, "fake", { budget }), ModelCallBudgetError);
  } finally { Date.now = originalNow; }
});

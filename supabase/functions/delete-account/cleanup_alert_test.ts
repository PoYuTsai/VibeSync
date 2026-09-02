import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildCleanupFailureAlert, deliverCleanupAlert } from "./cleanup_alert.ts";

Deno.test("告警文字只帶表名、錯誤碼與雜湊參照，且不在刪帳前宣稱已刪", () => {
  const msg = buildCleanupFailureAlert({ table: "ai_logs", errorCode: "42501", userRef: "abc123def456" });
  assertEquals(msg.split("\n").length, 4);
  assert(msg.includes("Table: ai_logs") && msg.includes("Error: 42501") && msg.includes("User ref: abc123def456"));
  assert(!msg.includes("@"), "不得含 Email");
});

Deno.test("投遞：沒設定 webhook 回 false", async () => {
  assertEquals(await deliverCleanupAlert({ webhookUrl: "", content: "x" }), false);
});

Deno.test("投遞：非 2xx、網路例外、逾時都回 false 且不拋出", async () => {
  const bad = await deliverCleanupAlert({ webhookUrl: "https://example.invalid/w", content: "x", fetchImpl: () => Promise.resolve(new Response("nope", { status: 500 })) });
  assertEquals(bad, false);
  const thrown = await deliverCleanupAlert({ webhookUrl: "https://example.invalid/w", content: "x", fetchImpl: () => Promise.reject(new Error("boom")) });
  assertEquals(thrown, false);
  const hung = await deliverCleanupAlert({ webhookUrl: "https://example.invalid/w", content: "x", timeoutMs: 20,
    fetchImpl: (_u, init) => new Promise((_, reject) => init?.signal?.addEventListener("abort", () => reject(new Error("aborted")))) });
  assertEquals(hung, false);
});

Deno.test("投遞：2xx 回 true，body 帶 content", async () => {
  let seen = "";
  const ok = await deliverCleanupAlert({ webhookUrl: "https://example.invalid/w", content: "hello", fetchImpl: (_u, init) => { seen = String(init?.body); return Promise.resolve(new Response(null, { status: 204 })); } });
  assertEquals(ok, true);
  assert(seen.includes("hello"));
});

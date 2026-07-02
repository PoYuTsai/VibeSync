import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleRequest } from "./index.ts";

Deno.test("GET health returns coach-chat status", async () => {
  const res = await handleRequest(
    new Request("http://localhost/", {
      method: "GET",
    }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.function, "coach-chat");
});

Deno.test("OPTIONS preflight returns CORS headers without auth", async () => {
  const res = await handleRequest(
    new Request("http://localhost/", {
      method: "OPTIONS",
    }),
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("POST without auth returns 401", async () => {
  const res = await handleRequest(
    new Request("http://localhost/", {
      method: "POST",
      body: "{}",
    }),
  );
  assertEquals(res.status, 401);
});

Deno.test({
  name: "quota preflight always gates, no clarification bypass",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // D1：checkQuota preflight 恆跑；額度歸零者不得再蹭免費釐清
    assertEquals(
      source.includes("allowNoChargeClarificationAttempt"),
      false,
    );
    assertEquals(source.includes("if (!gate.ok)"), true);
  },
});

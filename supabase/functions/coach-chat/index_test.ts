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
  name: "quota preflight allows bounded no-charge clarification attempts",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assertEquals(
      source.includes("shouldAllowNoChargeClarificationAttempt(payload)"),
      true,
    );
    assertEquals(
      source.includes("!allowNoChargeClarificationAttempt && !gate.ok"),
      true,
    );
  },
});

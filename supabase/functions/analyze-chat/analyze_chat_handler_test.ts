// createAnalyzeChatHandler 的行為測試：以假 Supabase client 驗證
// streaming-only tombstone 在任何訂閱、額度、模型工作之前 fail-closed。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { createAnalyzeChatHandler } from "./index.ts";

interface FakeCounters {
  from: number;
  rpc: number;
  fetch: number;
}

function fakeSupabase(counters: FakeCounters) {
  return {
    auth: {
      getUser: (_token: string) =>
        Promise.resolve({
          data: {
            user: {
              id: "00000000-0000-4000-8000-000000000001",
              email: "user@example.com",
            },
          },
          error: null,
        }),
    },
    from: (_table: string) => {
      counters.from += 1;
      throw new Error("tombstone path must not touch the database");
    },
    rpc: (_fn: string) => {
      counters.rpc += 1;
      throw new Error("tombstone path must not call quota RPCs");
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

function postRequest(body: Record<string, unknown>): Request {
  return new Request("http://localhost/analyze-chat", {
    method: "POST",
    headers: {
      Authorization: "Bearer fake-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

async function runWithFakes(
  body: Record<string, unknown>,
): Promise<{ response: Response; counters: FakeCounters }> {
  const counters: FakeCounters = { from: 0, rpc: 0, fetch: 0 };
  const handler = createAnalyzeChatHandler({
    createSupabaseClient: () => fakeSupabase(counters),
  });
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () => {
    counters.fetch += 1;
    throw new Error("tombstone path must not call any provider");
  };
  try {
    const response = await handler(postRequest(body));
    return { response, counters };
  } finally {
    globalThis.fetch = originalFetch;
  }
}

const fixtures = JSON.parse(
  await Deno.readTextFile(
    new URL("./baseline_fixtures.json", import.meta.url),
  ),
) as {
  requestModeRejections: Record<string, {
    status: number;
    code: string;
    message: string;
    shouldChargeQuota: boolean;
  }>;
};

Deno.test("handler：CORS preflight 直接回 200", async () => {
  const handler = createAnalyzeChatHandler({
    createSupabaseClient: () => fakeSupabase({ from: 0, rpc: 0, fetch: 0 }),
  });
  const response = await handler(
    new Request("http://localhost/analyze-chat", { method: "OPTIONS" }),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.text(), "ok");
});

Deno.test("handler：缺 Authorization 回 401，不建立 DB 連線", async () => {
  const counters: FakeCounters = { from: 0, rpc: 0, fetch: 0 };
  const handler = createAnalyzeChatHandler({
    createSupabaseClient: () => fakeSupabase(counters),
  });
  const response = await handler(
    new Request("http://localhost/analyze-chat", {
      method: "POST",
      body: JSON.stringify({}),
    }),
  );
  assertEquals(response.status, 401);
  assertEquals(counters.from, 0);
});

Deno.test("handler：quick/full/plain legacy 皆 410 tombstone，且訂閱/額度/模型計數為 0", async () => {
  const cases: Array<[key: string, body: Record<string, unknown>]> = [
    ["quick", {
      responseMode: "quick",
      messages: [{ content: "hi", isFromMe: false }],
    }],
    ["full", {
      responseMode: "full",
      messages: [{ content: "hi", isFromMe: false }],
    }],
    ["plainLegacy", { messages: [{ content: "hi", isFromMe: false }] }],
  ];
  for (const [key, body] of cases) {
    const { response, counters } = await runWithFakes(body);
    const expected = fixtures.requestModeRejections[key];
    assertEquals(response.status, expected.status, `${key}: status`);
    const payload = await response.json();
    assertEquals(payload.code, expected.code, `${key}: code`);
    assertEquals(payload.message, expected.message, `${key}: message`);
    assertEquals(payload.shouldChargeQuota, false, `${key}: 不得扣額度`);
    assertEquals(counters.from, 0, `${key}: 不得查訂閱`);
    assertEquals(counters.rpc, 0, `${key}: 不得動額度`);
    assertEquals(counters.fetch, 0, `${key}: 不得呼叫模型`);
  }
});

Deno.test("handler：不支援的 responseMode 回 400，不碰任何下游", async () => {
  const { response, counters } = await runWithFakes({
    responseMode: "batch",
    messages: [{ content: "hi", isFromMe: false }],
  });
  assertEquals(response.status, 400);
  const payload = await response.json();
  assertEquals(payload.code, "INVALID_RESPONSE_MODE");
  assert(payload.shouldChargeQuota === false);
  assertEquals(counters.from, 0);
  assertEquals(counters.rpc, 0);
  assertEquals(counters.fetch, 0);
});

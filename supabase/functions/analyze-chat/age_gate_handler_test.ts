// 18+ 年齡閘門（AGE-01）接進對話分析 handler 之後：擋下時不查訂閱、不動額度、
// 不呼叫模型；開關 AGE_GATE_ENFORCE 沒設時誰都不擋，成年紀錄任何開關都放行。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  AGE_GATE_BLOCKED_MESSAGE,
  AGE_GATE_REQUIRED_MESSAGE,
} from "../_shared/age_gate.ts";
import { TEST_EMAILS } from "../_shared/quota.ts";
import { createAnalyzeChatHandler } from "./index.ts";

const ENV_KEY = "AGE_GATE_ENFORCE";
const AT = "2026-10-30T08:00:00.000Z";

interface Calls {
  tables: string[];
  rpc: number;
  fetch: number;
}

/// 第一次查資料表（訂閱）就丟錯停下：查到＝已經通過年齡檢查。
function fakeSupabase(
  calls: Calls,
  user: { email: string; app_metadata: Record<string, unknown> },
) {
  return {
    auth: {
      getUser: (_token: string) =>
        Promise.resolve({
          data: {
            user: { id: "00000000-0000-4000-8000-000000000003", ...user },
          },
          error: null,
        }),
    },
    from: (table: string) => {
      calls.tables.push(table);
      throw new Error("age gate test stops at the first DB read");
    },
    rpc: (_fn: string) => {
      calls.rpc += 1;
      throw new Error("age gate test must not call RPCs");
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

async function runHandler(
  enforcement: string | undefined,
  user: { email: string; app_metadata: Record<string, unknown> },
): Promise<{ response: Response; calls: Calls }> {
  const calls: Calls = { tables: [], rpc: 0, fetch: 0 };
  const handler = createAnalyzeChatHandler({
    createSupabaseClient: () => fakeSupabase(calls, user),
  });
  const originalFetch = globalThis.fetch;
  const originalEnv = Deno.env.get(ENV_KEY);
  globalThis.fetch = () => {
    calls.fetch += 1;
    throw new Error("age gate test must not call any provider");
  };
  if (enforcement === undefined) {
    Deno.env.delete(ENV_KEY);
  } else {
    Deno.env.set(ENV_KEY, enforcement);
  }
  try {
    const response = await handler(
      new Request("http://localhost/analyze-chat", {
        method: "POST",
        headers: {
          Authorization: "Bearer fake-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          responseMode: "stream",
          messages: [{ content: "今天好累喔", isFromMe: false }],
          billingProtocolVersion: 3,
          analysisContractVersion: 3,
        }),
      }),
    );
    return { response, calls };
  } finally {
    globalThis.fetch = originalFetch;
    if (originalEnv === undefined) {
      Deno.env.delete(ENV_KEY);
    } else {
      Deno.env.set(ENV_KEY, originalEnv);
    }
  }
}

const noRecord = (email = "user@example.com") => ({
  email,
  app_metadata: { provider: "email" },
});
const withRecord = (result: "adult" | "minor", email = "user@example.com") => ({
  email,
  app_metadata: { provider: "apple", age_gate: { result, policy: 1, at: AT } },
});

function assertZeroCost(calls: Calls, label: string) {
  assertEquals(calls.tables, [], `${label}: 不得查訂閱`);
  assertEquals(calls.rpc, 0, `${label}: 不得動額度`);
  assertEquals(calls.fetch, 0, `${label}: 不得呼叫模型`);
}

Deno.test("handler：全開、沒有年齡紀錄 → 403 AGE_GATE_REQUIRED，零成本", async () => {
  const { response, calls } = await runHandler("on", noRecord());
  assertEquals(response.status, 403);
  assertEquals(await response.json(), {
    error: "AGE_GATE_REQUIRED",
    message: AGE_GATE_REQUIRED_MESSAGE,
  });
  assertZeroCost(calls, "沒有紀錄");
});

Deno.test("handler：全開、未成年 → 403 AGE_GATE_BLOCKED，零成本", async () => {
  const { response, calls } = await runHandler("on", withRecord("minor"));
  assertEquals(response.status, 403);
  assertEquals(await response.json(), {
    error: "AGE_GATE_BLOCKED",
    message: AGE_GATE_BLOCKED_MESSAGE,
  });
  assertZeroCost(calls, "未成年");
});

Deno.test("handler：成年紀錄任何開關都放行；開關沒設時沒有紀錄也放行", async () => {
  for (const enforcement of [undefined, "test", "on"]) {
    const adult = await runHandler(enforcement, withRecord("adult"));
    assertEquals(adult.calls.tables[0], "subscriptions", `成年 ${enforcement}`);
    await adult.response.body?.cancel();
  }
  const off = await runHandler(undefined, noRecord());
  assertEquals(off.calls.tables[0], "subscriptions", "開關沒設");
  await off.response.body?.cancel();
});

Deno.test("handler：test 只擋測試帳號", async () => {
  const regular = await runHandler("test", noRecord());
  assertEquals(regular.calls.tables[0], "subscriptions", "一般帳號放行");
  await regular.response.body?.cancel();

  const tester = await runHandler("test", noRecord(TEST_EMAILS[0]));
  assertEquals(tester.response.status, 403);
  assertEquals((await tester.response.json()).error, "AGE_GATE_REQUIRED");
  assertZeroCost(tester.calls, "測試帳號");
});

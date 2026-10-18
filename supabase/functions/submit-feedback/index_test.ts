// 漏斗購買事件從正式入口 createSubmitFeedbackHandler 走一次（主審 P3，Eric 2026-10-18）：
// 登入的是 B、事件帶的購買者是 A → 400，一筆都不寫；購買者就是 B → 寫一筆，存的那筆
// 沒有 purchaser。資料庫是替身，照權杖認人。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { createSubmitFeedbackHandler } from "./index.ts";

const ACCOUNT_A = "8f14e45f-ceea-4c6b-9a8e-3e4d4b5c6a7f";
const ACCOUNT_B = "2b7c1d3e-4f5a-4b6c-8d7e-9f0a1b2c3d4e";
const TOKENS: Record<string, string> = {
  "token-of-a": ACCOUNT_A,
  "token-of-b": ACCOUNT_B,
};

interface Insert {
  table: string;
  row: Record<string, unknown>;
}

function fakeSupabase(inserts: Insert[]) {
  return {
    auth: {
      getUser: (token: string) => {
        const id = TOKENS[token];
        return Promise.resolve(
          id
            ? { data: { user: { id, email: "user@example.com" } }, error: null }
            : { data: { user: null }, error: { message: "invalid token" } },
        );
      },
    },
    // 漏斗只會 insert；叫到別的方法就丟錯（端點回 500），測試會抓到。
    from: (table: string) => ({
      insert: (row: Record<string, unknown>) => {
        inserts.push({ table, row });
        return Promise.resolve({ error: null });
      },
    }),
  };
}

async function submitFunnel(token: string, event: Record<string, unknown>) {
  const inserts: Insert[] = [];
  const handler = createSubmitFeedbackHandler({
    createSupabaseClient: () => fakeSupabase(inserts) as never,
  });
  const response = await handler(
    new Request("http://localhost/submit-feedback", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ kind: "funnel", event }),
    }),
  );
  return { status: response.status, body: await response.json(), inserts };
}

function purchaseBy(purchaser: string) {
  return {
    event: "paywall_purchase_completed",
    properties: { tier: "essential", entry: "locked_cards", purchaser },
    clientTs: "2026-10-18T08:00:00.000Z",
  };
}

Deno.test("購買事件：登入的是 B、購買者帶 A → 400，一筆都不寫", async () => {
  const out = await submitFunnel("token-of-b", purchaseBy(ACCOUNT_A));
  assertEquals(out.status, 400);
  assertEquals(out.body, { error: "Funnel purchaser mismatch" });
  assertEquals(out.inserts, []);
});

Deno.test("購買事件：購買者就是登入的 B → 寫一筆，存的那筆沒有 purchaser", async () => {
  const out = await submitFunnel("token-of-b", purchaseBy(ACCOUNT_B));
  assertEquals(out.status, 200);
  assertEquals(out.body, { success: true });
  assertEquals(out.inserts, [{
    table: "funnel_events",
    row: {
      user_id: ACCOUNT_B,
      event: "paywall_purchase_completed",
      properties: { tier: "essential", entry: "locked_cards" },
      client_ts: "2026-10-18T08:00:00.000Z",
    },
  }]);
  assert(!("purchaser" in (out.inserts[0].row.properties as object)));
});

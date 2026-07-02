import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { selfHealSubscription } from "./index.ts";

// 首次使用兩請求併發 selfHeal：後到者 insert 撞 unique constraint，
// 必須回讀既有列而非 null（null 會被上游映射成 403 鎖住新用戶）。
function buildRacedSupabaseFake(
  existing: Record<string, unknown> | null,
  insertErrorCode: string,
) {
  return {
    from: (_table: string) => ({
      insert: (_row: unknown) => ({
        select: (_cols: string) => ({
          single: () =>
            Promise.resolve({
              data: null,
              error: {
                code: insertErrorCode,
                message: "insert failed",
              },
            }),
        }),
      }),
      select: (_cols: string) => ({
        eq: (_col: string, _value: string) => ({
          maybeSingle: () => Promise.resolve({ data: existing, error: null }),
        }),
      }),
    }),
  };
}

Deno.test("selfHealSubscription duplicate insert falls back to existing row", async () => {
  const existing = {
    user_id: "user-1",
    tier: "free",
    monthly_messages_used: 2,
    daily_messages_used: 1,
    daily_reset_at: "2026-07-01T00:00:00.000Z",
    monthly_reset_at: "2026-07-01T00:00:00.000Z",
    started_at: "2026-06-01T00:00:00.000Z",
  };
  const sub = await selfHealSubscription(
    buildRacedSupabaseFake(existing, "23505"),
    "user-1",
  );
  assertEquals(sub, existing);
});

Deno.test("selfHealSubscription non-duplicate insert error still returns null", async () => {
  const sub = await selfHealSubscription(
    buildRacedSupabaseFake(null, "42501"),
    "user-1",
  );
  assertEquals(sub, null);
});

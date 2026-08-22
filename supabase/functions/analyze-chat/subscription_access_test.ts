import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { loadSubscriptionAccess } from "./subscription_access.ts";

interface UpdateRecord {
  values: Record<string, unknown>;
  filters: Array<[op: string, column: string, value: unknown]>;
}

function makeFakeSupabase(state: {
  row: Record<string, unknown> | null;
  selectError?: { code?: string; message?: string } | null;
  insertFails?: boolean;
  updates: UpdateRecord[];
  inserted?: Record<string, unknown>;
}) {
  return {
    from(_table: string) {
      return {
        select(_columns: string) {
          return {
            eq(_column: string, _value: unknown) {
              return {
                maybeSingle: () =>
                  Promise.resolve({
                    data: state.row,
                    error: state.selectError ?? null,
                  }),
              };
            },
          };
        },
        insert(values: Record<string, unknown>) {
          state.inserted = values;
          return {
            select: (_columns: string) => ({
              single: () =>
                Promise.resolve(
                  state.insertFails
                    ? { data: null, error: { message: "insert failed" } }
                    : {
                      data: {
                        tier: values.tier,
                        monthly_messages_used: values.monthly_messages_used,
                        daily_messages_used: values.daily_messages_used,
                        daily_reset_at: values.daily_reset_at,
                        monthly_reset_at: values.monthly_reset_at,
                      },
                      error: null,
                    },
                ),
            }),
          };
        },
        update(values: Record<string, unknown>) {
          const record: UpdateRecord = { values, filters: [] };
          state.updates.push(record);
          const builder = {
            eq(column: string, value: unknown) {
              record.filters.push(["eq", column, value]);
              return builder;
            },
            is(column: string, value: unknown) {
              record.filters.push(["is", column, value]);
              return builder;
            },
            // deno-lint-ignore no-explicit-any
            then(resolve: (value: any) => void) {
              resolve({ data: null, error: null });
            },
          };
          return builder;
        },
      };
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

const USER = "00000000-0000-4000-8000-000000000001";

Deno.test("訂閱讀取：同一 UTC 窗口內不觸發 reset，也不改用量", async () => {
  const nowIso = new Date().toISOString();
  const state = {
    row: {
      tier: "starter",
      monthly_messages_used: 5,
      daily_messages_used: 2,
      daily_reset_at: nowIso,
      monthly_reset_at: nowIso,
    },
    updates: [] as UpdateRecord[],
  };
  const result = await loadSubscriptionAccess({
    supabase: makeFakeSupabase(state),
    userId: USER,
  });
  assert(result.ok);
  if (result.ok) {
    assertEquals(result.sub.monthly_messages_used, 5);
    assertEquals(result.sub.daily_messages_used, 2);
  }
  assertEquals(state.updates.length, 0);
});

Deno.test("訂閱缺列：self-heal 插入 free 列並回傳", async () => {
  const state = {
    row: null,
    updates: [] as UpdateRecord[],
    inserted: undefined as Record<string, unknown> | undefined,
  };
  const result = await loadSubscriptionAccess({
    supabase: makeFakeSupabase(state),
    userId: USER,
  });
  assert(result.ok);
  if (result.ok) {
    assertEquals(result.sub.tier, "free");
    assertEquals(result.sub.monthly_messages_used, 0);
  }
  assertEquals(state.inserted?.user_id, USER);
  // 剛插入的列 reset 時間就是現在，不得再觸發 reset 覆寫。
  assertEquals(state.updates.length, 0);
});

Deno.test("訂閱缺列且插入失敗：fail-closed", async () => {
  const state = {
    row: null,
    insertFails: true,
    updates: [] as UpdateRecord[],
  };
  const result = await loadSubscriptionAccess({
    supabase: makeFakeSupabase(state),
    userId: USER,
  });
  assertEquals(result.ok, false);
});

Deno.test("跨 UTC 日/月：CAS 條件化 reset 且本地用量歸零", async () => {
  const oldIso = "2020-01-01T00:00:00.000Z";
  const state = {
    row: {
      tier: "free",
      monthly_messages_used: 9,
      daily_messages_used: 3,
      daily_reset_at: oldIso,
      monthly_reset_at: oldIso,
    },
    updates: [] as UpdateRecord[],
  };
  const result = await loadSubscriptionAccess({
    supabase: makeFakeSupabase(state),
    userId: USER,
  });
  assert(result.ok);
  if (result.ok) {
    assertEquals(result.sub.daily_messages_used, 0);
    assertEquals(result.sub.monthly_messages_used, 0);
  }
  assertEquals(state.updates.length, 2);
  const [daily, monthly] = state.updates;
  assertEquals(daily.values.daily_messages_used, 0);
  // CAS：WHERE user_id ＝我 且 reset_at ＝ 舊值。
  assertEquals(daily.filters[0], ["eq", "user_id", USER]);
  assertEquals(daily.filters[1], ["eq", "daily_reset_at", oldIso]);
  assertEquals(monthly.values.monthly_messages_used, 0);
  assertEquals(monthly.filters[1], ["eq", "monthly_reset_at", oldIso]);
});

Deno.test("reset_at 為 null：CAS 用 IS NULL 而非 eq", async () => {
  const state = {
    row: {
      tier: "free",
      monthly_messages_used: 1,
      daily_messages_used: 1,
      daily_reset_at: null,
      monthly_reset_at: null,
    },
    updates: [] as UpdateRecord[],
  };
  const result = await loadSubscriptionAccess({
    supabase: makeFakeSupabase(state),
    userId: USER,
  });
  assert(result.ok);
  assertEquals(state.updates.length, 2);
  assertEquals(state.updates[0].filters[1], ["is", "daily_reset_at", null]);
  assertEquals(state.updates[1].filters[1], ["is", "monthly_reset_at", null]);
});

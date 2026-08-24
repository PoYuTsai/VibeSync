// 「每日最多 600 次模型呼叫」的 **Edge 側那一半**（PR A 終審 P2-1 欠下的帳）。
//
// migration 的檔頭已經寫清楚：DB 機械保證的只有
//   unique(profile_id, post_date, slot) × CHECK(slot 0..1) × CHECK(attempts 0..3)
//   = 每個 (profile_id, post_date) 最多 6 次。
// DB **不認識角色名冊**，任意字串都會被接受並各自拿到自己的 6 次額度；
// DB 也不知道什麼是台北日，post_date 亂填就能把同一天算成很多天。
//
// 所以 600 = 100 × 6 只有在 Edge 同時保證這兩件事時才成立：
//   (a) profile_id 只可能來自 100 位角色的固定 allowlist；
//   (b) post_date 只可能是 taipeiTimeContextFor(now).isoDate。
// 這支測試就是那兩條的機械證明。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  handlePracticeMoments,
  type MomentsSupabaseClient,
} from "./moments_handler.ts";
import { MOMENT_PROFILE_ALLOWLIST_MAX } from "./moments_constants.ts";
import { GIRL_PROFILES, isProfileId } from "./practice_persona.ts";
import { taipeiTimeContextFor } from "./time_context.ts";

type Row = Record<string, unknown>;

const USER_ID = "11111111-2222-3333-4444-555555555555";
const VALID_BODY = "今天的第一杯咖啡比鬧鐘有用多了，終於覺得自己醒著";

interface Captured {
  fn: string;
  params: Row;
}

function harnessWith(unlockedProfileIds: string[]) {
  const calls: Captured[] = [];
  let tokenSeq = 0;
  const supabase: MomentsSupabaseClient = {
    from() {
      return {
        select() {
          const builder = {
            eq() {
              return builder;
            },
            then(resolve: (value: unknown) => unknown) {
              return Promise.resolve(resolve({
                data: unlockedProfileIds.map((profile_id) => ({
                  profile_id,
                  created_at: "2026-08-01T00:00:00.000Z",
                })),
                error: null,
              }));
            },
          };
          return builder as never;
        },
      };
    },
    rpc(fn: string, params: Row) {
      calls.push({ fn, params });
      if (fn === "list_practice_moment_posts") {
        return Promise.resolve({ data: [], error: null });
      }
      if (fn === "reserve_practice_moment_slot") {
        return Promise.resolve({
          data: [{
            claimed: true,
            token: `token-${tokenSeq++}`,
            attempt_count: 1,
          }],
          error: null,
        });
      }
      if (fn === "commit_practice_moment_post") {
        return Promise.resolve({ data: [{ committed: true }], error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { supabase, calls };
}

function run(
  harness: { supabase: MomentsSupabaseClient },
  now: Date,
) {
  return handlePracticeMoments({
    supabase: harness.supabase,
    userId: USER_ID,
    now,
    isTestAccount: false,
    deps: {
      apiKey: "test-key",
      fillDeadlineMs: 500,
      callDeepSeek: () =>
        Promise.resolve(JSON.stringify({ text: VALID_BODY, imageId: null })),
    },
  });
}

/** 每一個進得了 DB 的 profile_id 參數。 */
function profileIdParams(calls: Captured[]): unknown[] {
  const seen: unknown[] = [];
  for (const call of calls) {
    if ("p_profile_id" in call.params) seen.push(call.params.p_profile_id);
    if (Array.isArray(call.params.p_profile_ids)) {
      seen.push(...call.params.p_profile_ids);
    }
  }
  return seen;
}

// ---------------------------------------------------------------------------
// (a) profile_id 只可能來自 100 位角色的 allowlist
// ---------------------------------------------------------------------------

Deno.test("角色名冊剛好 100 位，與 SQL 的 p_profile_ids 上限一致", () => {
  assertEquals(GIRL_PROFILES.length, MOMENT_PROFILE_ALLOWLIST_MAX);
  assertEquals(new Set(GIRL_PROFILES.map((g) => g.profileId)).size, 100);
});

Deno.test("draw_events 裡的垃圾 profile_id 一個都進不了 RPC", async () => {
  const junk = [
    "practice_girl_999",
    "practice_girl_000",
    "",
    "   ",
    "../../etc/passwd",
    "practice_girl_007; DROP TABLE practice_moment_posts",
    "PRACTICE_GIRL_007",
    "practice_girl_7",
    "a".repeat(200),
  ];
  const harness = harnessWith(junk);
  const result = await run(harness, new Date(Date.UTC(2026, 7, 22, 15, 0, 0)));
  assertEquals(result.status, 200);
  // 一個合法角色都沒有 → 連 list 都不該打。
  assertEquals(harness.calls.length, 0);
});

Deno.test("合法與垃圾混在一起時，只有合法的那些進得了 RPC", async () => {
  const legit = GIRL_PROFILES.slice(0, 4).map((g) => g.profileId);
  const harness = harnessWith([
    ...legit,
    "practice_girl_999",
    "not_a_profile",
    "practice_girl_007 OR 1=1",
  ]);
  await run(harness, new Date(Date.UTC(2026, 7, 22, 15, 0, 0)));
  const seen = profileIdParams(harness.calls);
  assert(seen.length > 0, "抽樣要真的打到 RPC");
  for (const value of seen) {
    assert(
      typeof value === "string" && isProfileId(value),
      `非 allowlist 的 profile_id 流進了 RPC：${JSON.stringify(value)}`,
    );
  }
  const listCall = harness.calls.find((c) =>
    c.fn === "list_practice_moment_posts"
  );
  assertEquals(listCall?.params.p_profile_ids, [...legit].sort());
});

Deno.test("同一位角色被重複抽到也只算一份，p_profile_ids 不會膨脹", async () => {
  const one = GIRL_PROFILES[0].profileId;
  const harness = harnessWith([one, one, one, one, one]);
  await run(harness, new Date(Date.UTC(2026, 7, 22, 15, 0, 0)));
  const listCall = harness.calls.find((c) =>
    c.fn === "list_practice_moment_posts"
  );
  assertEquals(listCall?.params.p_profile_ids, [one]);
});

Deno.test("即使整份名冊都解鎖，p_profile_ids 也不會超過 SQL 的上限", async () => {
  const harness = harnessWith(GIRL_PROFILES.map((g) => g.profileId));
  await run(harness, new Date(Date.UTC(2026, 7, 22, 15, 0, 0)));
  const listCall = harness.calls.find((c) =>
    c.fn === "list_practice_moment_posts"
  );
  const ids = listCall?.params.p_profile_ids as string[];
  assertEquals(ids.length, GIRL_PROFILES.length);
  assert(
    ids.length <= MOMENT_PROFILE_ALLOWLIST_MAX,
    "超過上限的話 list RPC 會直接 RAISE",
  );
});

// ---------------------------------------------------------------------------
// (b) post_date 只可能是正確的台北日
// ---------------------------------------------------------------------------

Deno.test("post_date 與 p_since 一律是台北日，跨日邊界不會算錯", async () => {
  for (
    const [utcIso, expectedTaipeiDay] of [
      // 台北 = UTC+8：15:59:59Z 還是同一天的 23:59:59。
      ["2026-08-22T15:59:59.000Z", "2026-08-22"],
      // 16:00:00Z 就是隔天 00:00 了。
      ["2026-08-22T16:00:00.000Z", "2026-08-23"],
      ["2026-08-22T16:00:01.000Z", "2026-08-23"],
      // UTC 當天的 00:00 在台北已經是早上 8 點，仍是同一天。
      ["2026-08-22T00:00:00.000Z", "2026-08-22"],
      // 跨月、跨年。
      ["2026-08-31T16:00:00.000Z", "2026-09-01"],
      ["2026-12-31T16:00:00.000Z", "2027-01-01"],
    ] as const
  ) {
    const now = new Date(utcIso);
    assertEquals(taipeiTimeContextFor(now).isoDate, expectedTaipeiDay, utcIso);
    const harness = harnessWith(
      GIRL_PROFILES.slice(0, 6).map((g) => g.profileId),
    );
    await run(harness, now);
    for (const call of harness.calls) {
      if ("p_post_date" in call.params) {
        assertEquals(
          call.params.p_post_date,
          expectedTaipeiDay,
          `${utcIso} 的 p_post_date 不是台北日`,
        );
      }
    }
    const listCall = harness.calls.find((c) =>
      c.fn === "list_practice_moment_posts"
    );
    // feed 視窗起點 = 台北日往回推 13 天（含今天共 14 天）。
    const since = listCall?.params.p_since as string;
    assertEquals(
      Math.round(
        (Date.parse(`${expectedTaipeiDay}T00:00:00Z`) -
          Date.parse(`${since}T00:00:00Z`)) / 86400000,
      ),
      13,
      `${utcIso} 的 p_since 視窗長度不對`,
    );
  }
});

Deno.test("同一次請求內所有 RPC 的 post_date 完全一致（不會半夜跨日撕裂）", async () => {
  const now = new Date(Date.UTC(2026, 7, 22, 15, 59, 59));
  const harness = harnessWith(
    GIRL_PROFILES.slice(0, 10).map((g) => g.profileId),
  );
  await run(harness, now);
  const dates = new Set(
    harness.calls
      .filter((call) => "p_post_date" in call.params)
      .map((call) => call.params.p_post_date),
  );
  assert(dates.size > 0, "抽樣要真的打到 reserve/commit");
  assertEquals([...dates], ["2026-08-22"]);
});

Deno.test("p_slot 一律落在 SQL CHECK 的 0..1 內", async () => {
  const harness = harnessWith(
    GIRL_PROFILES.slice(0, 20).map((g) => g.profileId),
  );
  await run(harness, new Date(Date.UTC(2026, 7, 22, 15, 59, 59)));
  const slots = harness.calls
    .filter((call) => "p_slot" in call.params)
    .map((call) => call.params.p_slot);
  assert(slots.length > 0);
  for (const slot of slots) {
    assert(
      typeof slot === "number" && Number.isInteger(slot) && slot >= 0 &&
        slot <= 1,
      `p_slot 超出 SQL CHECK：${JSON.stringify(slot)}`,
    );
  }
});

// ---------------------------------------------------------------------------
// 兩者相乘 = 每日 600
// ---------------------------------------------------------------------------

Deno.test("每日上界 600 的算式在 Edge 與 SQL 兩側都對得起來", () => {
  const perSlotAttempts = 3;
  const slotsPerDay = 2;
  assertEquals(
    MOMENT_PROFILE_ALLOWLIST_MAX * slotsPerDay * perSlotAttempts,
    600,
  );
  // 角色名冊是固定資料，不隨使用者數成長：第 101 位使用者的邊際成本是 0。
  assertEquals(GIRL_PROFILES.length, MOMENT_PROFILE_ALLOWLIST_MAX);
});

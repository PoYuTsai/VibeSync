// 動態貼文生成與 feed handler 的行為契約。
//
// 這支測試守的是整個功能最貴的三件事：**不會重複生成、不會超支、不會寫
// 假內容**。所有 DeepSeek 都是 stub，一次真的模型呼叫都不會發生。
import { renderMomentStyleAdapter } from "./moments_prompt.ts";
import { replyStyleFor } from "./reply_style.ts";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  handlePracticeMoments,
  type MomentsHandlerDeps,
  type MomentsSupabaseClient,
} from "./moments_handler.ts";
import {
  FEED_WINDOW_DAYS,
  MOMENT_FILL_MAX_PER_REQUEST,
} from "./moments_constants.ts";
import { momentPostedAtFor } from "./moments_time.ts";
import { momentFreshnessSlotFor, momentPlanFor } from "./moments_schedule.ts";
import { taipeiTimeContextFor } from "./time_context.ts";
import { getPracticeGirlProfile, GIRL_PROFILES } from "./practice_persona.ts";
import { resolveAvailableMomentImages } from "./moments_image_catalog.ts";

type Row = Record<string, unknown>;

const USER_ID = "11111111-2222-3333-4444-555555555555";
/** 台北 2026-08-22（週六）11:00。 */
const NOON = new Date(Date.UTC(2026, 7, 22, 3, 0, 0));
/** 同一天台北 23:59，讓當天所有時段都已到時間。 */
const END_OF_DAY = new Date(Date.UTC(2026, 7, 22, 15, 59, 0));
/**
 * Queenie 的 production 重現：上一則是台北 8/26 07:05，8/27 10:52
 * 仍只會排到晚上 19:12，兩則可見時間會相隔 36 小時 7 分。
 */
const QUEENIE_STALE_NOW = new Date("2026-08-27T02:52:00.000Z");

const VALID_BODY = "今天的第一杯咖啡比鬧鐘有用多了，終於覺得自己醒著";

interface RpcCall {
  fn: string;
  params: Row;
}

interface HarnessOptions {
  unlocked?: { profileId: string; createdAt?: string }[];
  drawError?: string;
  existing?: Row[];
  listError?: string;
  slotStates?: Row[];
  slotStateError?: string;
  reserve?: (params: Row, index: number) => Row | null;
  commit?: (params: Row) => Row;
  release?: (params: Row) => Row;
  rateLimitError?: string;
  model?: (index: number, timeoutMs: number) => Promise<string>;
  planFor?: MomentsHandlerDeps["planFor"];
}

interface Harness {
  supabase: MomentsSupabaseClient;
  rpcCalls: RpcCall[];
  modelCalls: { timeoutMs: number; system: string }[];
  selects: string[];
  options: HarnessOptions;
}

function makeHarness(options: HarnessOptions): Harness {
  const rpcCalls: RpcCall[] = [];
  const modelCalls: { timeoutMs: number; system: string }[] = [];
  const selects: string[] = [];
  let reserveIndex = 0;

  const supabase: MomentsSupabaseClient = {
    from(table: string) {
      return {
        select(columns: string) {
          selects.push(`${table}:${columns}`);
          const builder = {
            eq() {
              return builder;
            },
            then(resolve: (value: unknown) => unknown) {
              if (options.drawError) {
                return Promise.resolve(
                  resolve({
                    data: null,
                    error: { message: options.drawError },
                  }),
                );
              }
              const rows = (options.unlocked ?? []).map((entry) => ({
                profile_id: entry.profileId,
                created_at: entry.createdAt ?? "2026-08-01T00:00:00.000Z",
              }));
              return Promise.resolve(resolve({ data: rows, error: null }));
            },
          };
          return builder as never;
        },
      };
    },
    rpc(fn: string, params: Row) {
      rpcCalls.push({ fn, params });
      if (fn === "increment_model_usage") {
        return Promise.resolve({
          data: null,
          error: options.rateLimitError
            ? { message: options.rateLimitError }
            : null,
        });
      }
      if (fn === "list_practice_moment_posts") {
        if (options.listError) {
          return Promise.resolve({
            data: null,
            error: { message: options.listError },
          });
        }
        return Promise.resolve({ data: options.existing ?? [], error: null });
      }
      if (fn === "list_practice_moment_slot_states") {
        return Promise.resolve({
          data: options.slotStates ?? [],
          error: options.slotStateError
            ? { message: options.slotStateError }
            : null,
        });
      }
      if (fn === "reserve_practice_moment_slot") {
        // production 的 reserve RPC 會在同一筆 DB transaction 內呼叫
        // increment_model_usage；測試用同一個錯誤入口模擬整筆 rollback。
        if (options.rateLimitError) {
          return Promise.resolve({
            data: null,
            error: { message: options.rateLimitError },
          });
        }
        const row = options.reserve
          ? options.reserve(params, reserveIndex++)
          : {
            claimed: true,
            token: `token-${reserveIndex++}`,
            attempt_count: 1,
          };
        return Promise.resolve({ data: row ? [row] : [], error: null });
      }
      if (fn === "commit_practice_moment_post") {
        return Promise.resolve({
          data: [options.commit ? options.commit(params) : { committed: true }],
          error: null,
        });
      }
      if (fn === "release_practice_moment_slot") {
        return Promise.resolve({
          data: [
            options.release ? options.release(params) : { released: true },
          ],
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };

  return { supabase, rpcCalls, modelCalls, selects, options };
}

let modelIndex = 0;

function run(
  harness: Harness,
  overrides: {
    now?: Date;
    fillDeadlineMs?: number;
    replyStyleEnabled?: boolean;
  } = {},
) {
  modelIndex = 0;
  const model = harness.options.model;
  return handlePracticeMoments({
    supabase: harness.supabase,
    userId: USER_ID,
    now: overrides.now ?? NOON,
    isTestAccount: false,
    deps: {
      apiKey: "test-key",
      replyStyleEnabled: overrides.replyStyleEnabled,
      fillDeadlineMs: overrides.fillDeadlineMs ?? 400,
      planFor: harness.options.planFor,
      randomToken: () => `token-${Math.random().toString(36).slice(2, 10)}`,
      callDeepSeek: async (args) => {
        const index = modelIndex++;
        harness.modelCalls.push({
          timeoutMs: args.timeoutMs,
          system: args.messages[0]?.content ?? "",
        });
        if (model) return await model(index, args.timeoutMs);
        return JSON.stringify({ text: VALID_BODY, imageId: null });
      },
    },
  });
}

function rpcNames(harness: Harness): string[] {
  return harness.rpcCalls.map((call) => call.fn);
}

/**
 * 等一小段時間讓「handler 回應之後才落地」的尾隨呼叫也被記錄下來。
 *
 * 死線那組測試如果不 drain，就只是在驗「release 比回應晚」——那是競態，
 * 不是契約。契約是「release 從頭到尾都不該發生」。
 */
function drain(ms = 120): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function body(result: { body: unknown }): Record<string, unknown> {
  return result.body as Record<string, unknown>;
}

/** 找出在 NOON 這一刻已到時間、且真的有 slot 的角色。 */
function profilesDueAt(now: Date): { profileId: string; slot: number }[] {
  const time = taipeiTimeContextFor(now);
  const due: { profileId: string; slot: number }[] = [];
  for (const girl of GIRL_PROFILES) {
    for (const slot of momentPlanFor({ girl, time }).slots) {
      const at = momentPostedAtFor({
        profileId: girl.profileId,
        isoDate: time.isoDate,
        slot: slot.slot,
        dayPart: slot.dayPart,
      });
      if (at.getTime() <= now.getTime()) {
        due.push({ profileId: girl.profileId, slot: slot.slot });
      }
    }
  }
  return due;
}

// ---------------------------------------------------------------------------
// 零成本路徑
// ---------------------------------------------------------------------------

Deno.test("已解鎖為空 → 零 RPC、零模型呼叫、200 空陣列", async () => {
  const harness = makeHarness({ unlocked: [] });
  const result = await run(harness, {});
  assertEquals(result.status, 200);
  assertEquals(body(result).posts, []);
  assertEquals(body(result).generatedCount, 0);
  assertEquals(body(result).pendingCount, 0);
  assertEquals(harness.rpcCalls.length, 0, "不該打任何 RPC");
  assertEquals(harness.modelCalls.length, 0);
});

Deno.test("所有到時間的 slot 都已 ready → 零模型呼叫（成本模型的基礎）", async () => {
  const time = taipeiTimeContextFor(END_OF_DAY);
  const due = profilesDueAt(END_OF_DAY);
  const unlocked = [...new Set(due.map((entry) => entry.profileId))]
    .slice(0, 5)
    .map((profileId) => ({ profileId }));
  const covered = due.filter((entry) =>
    unlocked.some((u) => u.profileId === entry.profileId)
  );
  assert(covered.length > 0, "抽樣要真的有到時間的 slot");
  const existing = covered.map((entry) => {
    const girl = getPracticeGirlProfile(entry.profileId)!;
    const plan = momentPlanFor({ girl, time }).slots.find((s) =>
      s.slot === entry.slot
    )!;
    return {
      profile_id: entry.profileId,
      post_date: time.isoDate,
      slot: entry.slot,
      day_part: plan.dayPart,
      theme_id: plan.themeId,
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-22T00:00:00.000Z",
    };
  });
  const harness = makeHarness({ unlocked, existing });
  const result = await run(harness, { now: END_OF_DAY });
  assertEquals(result.status, 200);
  assertEquals(harness.modelCalls.length, 0);
  assertEquals(
    rpcNames(harness).includes("reserve_practice_moment_slot"),
    false,
  );
  assertEquals((body(result).posts as unknown[]).length, covered.length);
  assertEquals(body(result).pendingCount, 0);
});

Deno.test("未到時間的 slot 不生成也不回傳", async () => {
  // 台北 08:00：當天絕大多數 slot 都還沒到時間。
  const early = new Date(Date.UTC(2026, 7, 22, 0, 0, 0));
  const time = taipeiTimeContextFor(early);
  const future = GIRL_PROFILES.filter((girl) =>
    momentPlanFor({ girl, time }).slots.some((slot) =>
      momentPostedAtFor({
        profileId: girl.profileId,
        isoDate: time.isoDate,
        slot: slot.slot,
        dayPart: slot.dayPart,
      }).getTime() > early.getTime()
    )
  ).slice(0, 6);
  assert(future.length > 0);
  const harness = makeHarness({
    unlocked: future.map((girl) => ({ profileId: girl.profileId })),
    existing: [
      // 一則未來的貼文即使 DB 裡已經是 ready，也不該提前露出。
      {
        profile_id: future[0].profileId,
        post_date: time.isoDate,
        slot: momentPlanFor({ girl: future[0], time }).slots[0].slot,
        day_part: "late_night",
        theme_id: "late_snack",
        body: VALID_BODY,
        image_id: null,
        created_at: "2026-08-22T00:00:00.000Z",
      },
    ],
  });
  const result = await run(harness, { now: early });
  assertEquals(result.status, 200);
  for (const post of body(result).posts as { postedAt: string }[]) {
    assert(
      Date.parse(post.postedAt) <= early.getTime(),
      `回傳了未到時間的貼文：${post.postedAt}`,
    );
  }
});

Deno.test("整個 feed 超過 24 小時沒更新 → 補一則今天已到時間的保底貼文", async () => {
  const queenieId = "practice_girl_094";
  const girl = getPracticeGirlProfile(queenieId);
  assert(girl);
  const time = taipeiTimeContextFor(QUEENIE_STALE_NOW);
  const normalPlan = momentPlanFor({ girl, time });
  assertEquals(
    normalPlan.slots.map((slotPlan) => slotPlan.slot),
    [0],
    "Queenie fixture 前提：今天只排 slot 0，保底才可驗證不借用未到期排程",
  );
  const normalDue = normalPlan.slots.filter((slotPlan) =>
    momentPostedAtFor({
      profileId: queenieId,
      isoDate: time.isoDate,
      slot: slotPlan.slot,
      dayPart: slotPlan.dayPart,
    }).getTime() <= QUEENIE_STALE_NOW.getTime()
  );
  assertEquals(
    normalDue.length,
    0,
    "Queenie 重現案例必須沒有一般排程已到時間，否則測不到 24 小時保底",
  );
  const fallbackPlan = momentFreshnessSlotFor({ girl, time, slot: 1 });
  const fallbackPostedAt = momentPostedAtFor({
    profileId: queenieId,
    isoDate: time.isoDate,
    slot: 1,
    dayPart: fallbackPlan.dayPart,
  });
  assert(
    fallbackPostedAt.getTime() <= QUEENIE_STALE_NOW.getTime(),
    `Queenie fixture 前提：未排程的 slot 1 必須已到時間，實際 ${fallbackPostedAt.toISOString()}`,
  );
  const harness = makeHarness({
    unlocked: [{ profileId: queenieId }],
    existing: [{
      profile_id: queenieId,
      post_date: "2026-08-26",
      slot: 0,
      day_part: "morning",
      theme_id: "coffee_start",
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-25T23:05:00.000Z",
    }],
  });

  const result = await run(harness, { now: QUEENIE_STALE_NOW });
  const posts = body(result).posts as { postedAt: string }[];
  const reserveCalls = harness.rpcCalls.filter((call) =>
    call.fn === "reserve_practice_moment_slot"
  );

  assertEquals(result.status, 200);
  assertEquals(body(result).generatedCount, 1);
  assertEquals(harness.modelCalls.length, 1);
  assertEquals(reserveCalls.length, 1);
  assertEquals(reserveCalls[0].params.p_profile_id, queenieId);
  assertEquals(reserveCalls[0].params.p_post_date, "2026-08-27");
  assertEquals(
    reserveCalls[0].params.p_slot,
    1,
    "保底不得借用今天稍晚原本排定的 slot 0",
  );
  const freshnessPlan = momentFreshnessSlotFor({
    girl,
    time,
    slot: Number(reserveCalls[0].params.p_slot),
  });
  assertEquals(reserveCalls[0].params.p_day_part, freshnessPlan.dayPart);
  assertEquals(reserveCalls[0].params.p_theme_id, freshnessPlan.themeId);
  assert(
    Number(reserveCalls[0].params.p_slot) >= 0 &&
      Number(reserveCalls[0].params.p_slot) < 2,
    "保底仍必須使用既有每日兩格，不得偷偷擴充成本上限",
  );
  assert(posts.length >= 2, "舊貼文要保留，並新增一則保底貼文");
  const newestAgeMs = QUEENIE_STALE_NOW.getTime() -
    Math.max(...posts.map((post) => Date.parse(post.postedAt)));
  assert(newestAgeMs >= 0, "保底貼文不得使用未來時間");
  assert(
    newestAgeMs <= 24 * 60 * 60 * 1000,
    `最新貼文仍超過 24 小時：${newestAgeMs}ms`,
  );
});

Deno.test("24 小時保底第一格未認領 → 依序改試第二格且只打一通模型", async () => {
  const queenieId = "practice_girl_094";
  const harness = makeHarness({
    unlocked: [{ profileId: queenieId }],
    existing: [{
      profile_id: queenieId,
      post_date: "2026-08-20",
      slot: 0,
      day_part: "morning",
      theme_id: "coffee_start",
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-19T23:05:00.000Z",
    }],
    planFor: ({ girl, time }) => ({
      profileId: girl.profileId,
      isoDate: time.isoDate,
      slots: [],
    }),
    reserve: (_params, index) =>
      index === 0
        ? { claimed: false, token: null, attempt_count: 3 }
        : { claimed: true, token: "token-second", attempt_count: 1 },
  });

  const result = await run(harness, { now: END_OF_DAY });
  const reserveCalls = harness.rpcCalls.filter((call) =>
    call.fn === "reserve_practice_moment_slot"
  );

  assertEquals(result.status, 200);
  assertEquals(reserveCalls.length, 2);
  assertEquals(reserveCalls[0].params.p_slot, 0);
  assertEquals(reserveCalls[1].params.p_slot, 1);
  assertEquals(harness.modelCalls.length, 1);
  assertEquals(body(result).generatedCount, 1);
});

Deno.test("24 小時保底兩格都不可認領 → 只讀狀態，不再重複鎖 reserve", async () => {
  const queenieId = "practice_girl_094";
  const harness = makeHarness({
    unlocked: [{ profileId: queenieId }],
    existing: [{
      profile_id: queenieId,
      post_date: "2026-08-20",
      slot: 0,
      day_part: "morning",
      theme_id: "coffee_start",
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-19T23:05:00.000Z",
    }],
    planFor: ({ girl, time }) => ({
      profileId: girl.profileId,
      isoDate: time.isoDate,
      slots: [],
    }),
    slotStates: [0, 1].map((slot) => ({
      profile_id: queenieId,
      slot,
      claimable: false,
    })),
  });

  const result = await run(harness, { now: END_OF_DAY });
  const stateCalls = harness.rpcCalls.filter((call) =>
    call.fn === "list_practice_moment_slot_states"
  );

  assertEquals(result.status, 200);
  assertEquals(stateCalls.length, 1);
  assertEquals(stateCalls[0].params.p_profile_ids, [queenieId]);
  assertEquals(stateCalls[0].params.p_post_date, "2026-08-22");
  assertEquals(
    rpcNames(harness).includes("reserve_practice_moment_slot"),
    false,
    "已耗盡或有效租約中的格子不得每次開 feed 都再做 FOR UPDATE",
  );
  assertEquals(harness.modelCalls.length, 0);
  assertEquals(body(result).generatedCount, 0);
});

Deno.test("24 小時保底只嘗試 slot-state 標成可認領的格子", async () => {
  const queenieId = "practice_girl_094";
  const harness = makeHarness({
    unlocked: [{ profileId: queenieId }],
    existing: [{
      profile_id: queenieId,
      post_date: "2026-08-20",
      slot: 0,
      day_part: "morning",
      theme_id: "coffee_start",
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-19T23:05:00.000Z",
    }],
    planFor: ({ girl, time }) => ({
      profileId: girl.profileId,
      isoDate: time.isoDate,
      slots: [],
    }),
    slotStates: [
      { profile_id: queenieId, slot: 0, claimable: false },
      { profile_id: queenieId, slot: 1, claimable: true },
    ],
  });

  const result = await run(harness, { now: END_OF_DAY });
  const reserveCalls = harness.rpcCalls.filter((call) =>
    call.fn === "reserve_practice_moment_slot"
  );

  assertEquals(result.status, 200);
  assertEquals(reserveCalls.length, 1);
  assertEquals(reserveCalls[0].params.p_slot, 1);
  assertEquals(harness.modelCalls.length, 1);
  assertEquals(body(result).generatedCount, 1);
});

Deno.test("slot-state 唯讀 RPC 暫時不可用 → 保留原子 reserve 保底路徑", async () => {
  const queenieId = "practice_girl_094";
  const harness = makeHarness({
    unlocked: [{ profileId: queenieId }],
    existing: [{
      profile_id: queenieId,
      post_date: "2026-08-20",
      slot: 0,
      day_part: "morning",
      theme_id: "coffee_start",
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-19T23:05:00.000Z",
    }],
    planFor: ({ girl, time }) => ({
      profileId: girl.profileId,
      isoDate: time.isoDate,
      slots: [],
    }),
    slotStateError: "PGRST202 function not found",
  });

  const result = await run(harness, { now: END_OF_DAY });

  assertEquals(result.status, 200);
  assert(rpcNames(harness).includes("list_practice_moment_slot_states"));
  assert(rpcNames(harness).includes("reserve_practice_moment_slot"));
  assertEquals(harness.modelCalls.length, 1);
  assertEquals(body(result).generatedCount, 1);
});

Deno.test("一般 due slot 已耗盡且 feed stale → 改試另一格保底並只打一通模型", async () => {
  const queenieId = "practice_girl_094";
  const harness = makeHarness({
    unlocked: [{ profileId: queenieId }],
    existing: [{
      profile_id: queenieId,
      post_date: "2026-08-20",
      slot: 0,
      day_part: "morning",
      theme_id: "coffee_start",
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-19T23:05:00.000Z",
    }],
    planFor: ({ girl, time }) => ({
      profileId: girl.profileId,
      isoDate: time.isoDate,
      slots: [momentFreshnessSlotFor({ girl, time, slot: 0 })],
    }),
    reserve: (_params, index) =>
      index === 0
        ? { claimed: false, token: null, attempt_count: 3 }
        : { claimed: true, token: "token-freshness", attempt_count: 1 },
  });

  const result = await run(harness, { now: END_OF_DAY });
  const reserveCalls = harness.rpcCalls.filter((call) =>
    call.fn === "reserve_practice_moment_slot"
  );

  assertEquals(result.status, 200);
  assertEquals(reserveCalls.length, 2);
  assertEquals(reserveCalls[0].params.p_slot, 0);
  assertEquals(reserveCalls[1].params.p_slot, 1);
  assertEquals(harness.modelCalls.length, 1);
  assertEquals(body(result).generatedCount, 1);
});

Deno.test("24 小時保底已認領但生成失敗 → 不再改試下一格燒第二通模型", async () => {
  const queenieId = "practice_girl_094";
  const harness = makeHarness({
    unlocked: [{ profileId: queenieId }],
    existing: [{
      profile_id: queenieId,
      post_date: "2026-08-20",
      slot: 0,
      day_part: "morning",
      theme_id: "coffee_start",
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-19T23:05:00.000Z",
    }],
    planFor: ({ girl, time }) => ({
      profileId: girl.profileId,
      isoDate: time.isoDate,
      slots: [],
    }),
    model: () => Promise.reject(new Error("provider_down")),
  });

  const result = await run(harness, { now: END_OF_DAY });
  const reserveCalls = harness.rpcCalls.filter((call) =>
    call.fn === "reserve_practice_moment_slot"
  );

  assertEquals(result.status, 200);
  assertEquals(reserveCalls.length, 1);
  assertEquals(harness.modelCalls.length, 1);
  assertEquals(body(result).generatedCount, 0);
});

Deno.test("最新貼文剛好 24 小時 → 不啟動保底、不多燒模型", async () => {
  const queenieId = "practice_girl_094";
  const exactly24HoursLater = new Date("2026-08-26T23:05:00.000Z");
  const harness = makeHarness({
    unlocked: [{ profileId: queenieId }],
    existing: [{
      profile_id: queenieId,
      post_date: "2026-08-26",
      slot: 0,
      day_part: "morning",
      theme_id: "coffee_start",
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-25T23:05:00.000Z",
    }],
  });

  const result = await run(harness, { now: exactly24HoursLater });

  assertEquals(result.status, 200);
  assertEquals(body(result).generatedCount, 0);
  assertEquals(harness.modelCalls.length, 0);
  assertEquals(
    rpcNames(harness).includes("reserve_practice_moment_slot"),
    false,
  );
});

// ---------------------------------------------------------------------------
// 生成路徑
// ---------------------------------------------------------------------------

Deno.test("補生成成功 → commit 帶著驗證後的 body，且回應含新貼文", async () => {
  const due = profilesDueAt(NOON);
  assert(due.length > 0);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
  });
  const result = await run(harness, {});
  assertEquals(result.status, 200);
  const commits = harness.rpcCalls.filter((call) =>
    call.fn === "commit_practice_moment_post"
  );
  assertEquals(commits.length, 1);
  assertEquals(commits[0].params.p_body, VALID_BODY);
  assertEquals(commits[0].params.p_profile_id, due[0].profileId);
  assertEquals(body(result).generatedCount, 1);
  assertEquals((body(result).posts as unknown[]).length, 1);
  assertEquals(
    rpcNames(harness).includes("release_practice_moment_slot"),
    false,
  );
});

Deno.test("單一請求最多補 K 則，其餘留給下次（pendingCount 說明剩幾則）", async () => {
  const due = profilesDueAt(NOON);
  const unlocked = [...new Set(due.map((entry) => entry.profileId))]
    .slice(0, MOMENT_FILL_MAX_PER_REQUEST + 4)
    .map((profileId) => ({ profileId }));
  const missing =
    due.filter((entry) => unlocked.some((u) => u.profileId === entry.profileId))
      .length;
  assert(missing > MOMENT_FILL_MAX_PER_REQUEST);
  const harness = makeHarness({ unlocked });
  const result = await run(harness, {});
  assertEquals(harness.modelCalls.length, MOMENT_FILL_MAX_PER_REQUEST);
  assertEquals(body(result).generatedCount, MOMENT_FILL_MAX_PER_REQUEST);
  assertEquals(
    body(result).pendingCount,
    missing - MOMENT_FILL_MAX_PER_REQUEST,
  );
});

Deno.test("沒搶到 latch（別人正在跑）→ 不打模型、不 release", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    reserve: () => ({ claimed: false, token: null, attempt_count: 1 }),
  });
  const result = await run(harness, {});
  assertEquals(result.status, 200);
  assertEquals(harness.modelCalls.length, 0);
  assertEquals(
    rpcNames(harness).includes("increment_model_usage"),
    false,
    "沒有取得全域 slot 就沒有模型呼叫，不得先扣使用者限流額度",
  );
  assertEquals(
    rpcNames(harness).includes("release_practice_moment_slot"),
    false,
  );
  assertEquals(body(result).generatedCount, 0);
  assertEquals(body(result).pendingCount, 1);
});

Deno.test("attempts 用完（reserve 回絕）→ 同一天不再打模型", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    // SQL 第 6 格：轉 exhausted 後一律 claimed = false。
    reserve: () => ({ claimed: false, token: null, attempt_count: 3 }),
  });
  await run(harness, {});
  assertEquals(harness.modelCalls.length, 0);
});

// ---------------------------------------------------------------------------
// no-canned：失敗永不落盤
// ---------------------------------------------------------------------------

Deno.test("模型失敗 → release 被呼叫、commit 一次都沒有、回應不含任何內容", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    model: () => Promise.reject(new Error("deepseek_http_500")),
  });
  const result = await run(harness, {});
  assertEquals(result.status, 200);
  const names = rpcNames(harness);
  assert(names.includes("release_practice_moment_slot"));
  assertEquals(names.includes("commit_practice_moment_post"), false);
  assertEquals(body(result).posts, []);
  assertEquals(body(result).generatedCount, 0);
  assertEquals(body(result).pendingCount, 1);
});

Deno.test("驗證打回（模型寫太長）→ release、不 commit、不落盤", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    model: () =>
      Promise.resolve(
        JSON.stringify({ text: "咖".repeat(200), imageId: null }),
      ),
  });
  const result = await run(harness, {});
  const names = rpcNames(harness);
  assert(names.includes("release_practice_moment_slot"));
  assertEquals(names.includes("commit_practice_moment_post"), false);
  assertEquals(body(result).generatedCount, 0);
});

Deno.test("模型吐出第二人稱 → 一樣打回並 release，不是原樣端出去", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    model: () =>
      Promise.resolve(
        JSON.stringify({
          text: "今天的咖啡好喝到我想推薦給你，下次一起去那間店坐坐吧",
          imageId: null,
        }),
      ),
  });
  const result = await run(harness, {});
  assert(rpcNames(harness).includes("release_practice_moment_slot"));
  assertEquals(body(result).posts, []);
});

// ---------------------------------------------------------------------------
// 死線
// ---------------------------------------------------------------------------

Deno.test("模型全部掛住 → 在死線內回應，且不 release（token 留給租約）", async () => {
  const due = profilesDueAt(NOON);
  const unlocked = [...new Set(due.map((entry) => entry.profileId))]
    .slice(0, 3)
    .map((profileId) => ({ profileId }));
  const harness = makeHarness({
    unlocked,
    model: () => new Promise<string>(() => {}),
  });
  const startedAt = Date.now();
  const result = await run(harness, { fillDeadlineMs: 300 });
  const elapsed = Date.now() - startedAt;
  assertEquals(result.status, 200);
  assert(elapsed < 3000, `死線沒有生效，等了 ${elapsed}ms`);
  await drain();
  assertEquals(
    rpcNames(harness).includes("release_practice_moment_slot"),
    false,
    "死線中止不得 release：那會讓下一個請求立刻接手並多燒一次 attempts",
  );
  assertEquals(body(result).generatedCount, 0);
  assert((body(result).pendingCount as number) > 0);
});

Deno.test("模型在死線上 abort（比照 callDeepSeek 真實行為）→ 仍不得 release", async () => {
  // 上一條用「永遠不 resolve」的 stub，蓋不到 production 的實際路徑：
  // callDeepSeek 的 AbortController 會在 timeoutMs 到點時丟 deepseek_timeout，
  // 也就是說 catch 區塊**會**被執行。死線判斷必須擋在 release 之前。
  const due = profilesDueAt(NOON);
  const unlocked = [...new Set(due.map((entry) => entry.profileId))]
    .slice(0, 3)
    .map((profileId) => ({ profileId }));
  const harness = makeHarness({
    unlocked,
    model: (_index, timeoutMs) =>
      new Promise<string>((_resolve, reject) => {
        setTimeout(() => reject(new Error("deepseek_timeout")), timeoutMs);
      }),
  });
  const result = await run(harness, { fillDeadlineMs: 300 });
  assertEquals(result.status, 200);
  await drain();
  assertEquals(
    rpcNames(harness).includes("release_practice_moment_slot"),
    false,
    "死線上的 abort 屬於死線中止，不是生成失敗：release 會讓下一個請求" +
      "立刻接手並多燒一次 attempts",
  );
  assertEquals(body(result).generatedCount, 0);
});

Deno.test("模型在死線之前就失敗 → 這才是生成失敗，必須 release", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    model: () =>
      new Promise<string>((_resolve, reject) => {
        setTimeout(() => reject(new Error("deepseek_timeout")), 20);
      }),
  });
  await run(harness, { fillDeadlineMs: 2000 });
  await drain();
  assert(rpcNames(harness).includes("release_practice_moment_slot"));
});

Deno.test("1 則成功、其餘掛住 → 回 1 則，pendingCount 記其餘", async () => {
  const due = profilesDueAt(NOON);
  const unlocked = [...new Set(due.map((entry) => entry.profileId))]
    .slice(0, 3)
    .map((profileId) => ({ profileId }));
  const missing =
    due.filter((entry) => unlocked.some((u) => u.profileId === entry.profileId))
      .length;
  const harness = makeHarness({
    unlocked,
    model: (index) =>
      index === 0
        ? Promise.resolve(JSON.stringify({ text: VALID_BODY, imageId: null }))
        : new Promise<string>(() => {}),
  });
  const result = await run(harness, { fillDeadlineMs: 300 });
  assertEquals(body(result).generatedCount, 1);
  assertEquals(body(result).pendingCount, missing - 1);
});

Deno.test("模型逾時上限不得超過剩餘死線", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({ unlocked: [{ profileId: due[0].profileId }] });
  await run(harness, { fillDeadlineMs: 500 });
  assertEquals(harness.modelCalls.length, 1);
  assert(
    harness.modelCalls[0].timeoutMs <= 500,
    `模型逾時 ${harness.modelCalls[0].timeoutMs}ms 超過死線`,
  );
});

// ---------------------------------------------------------------------------
// 限流
// ---------------------------------------------------------------------------

// 2026-08-24 複審 BLOCK 1：這一條原本斷言 429。那是錯的契約——429 會讓 feed
// 已經讀到的既有貼文整包消失，與設計稿「缺貼文時顯示既有內容、不塞罐頭、不報錯」
// 直接衝突。限流命中時正確行為是「跳過補生成」，仍回 200。
Deno.test("限流命中 → 200，既有貼文不受影響，只是不補生成", async () => {
  const due = profilesDueAt(NOON);
  // 兩位角色都解鎖：第一位已有貼文，第二位缺貼文且會撞上限流。
  const withPost = due[0];
  const withoutPost = due[1];
  assert(
    withoutPost && withoutPost.profileId !== withPost.profileId,
    "這條測試需要兩位不同角色",
  );

  const time = taipeiTimeContextFor(NOON);
  const girl = getPracticeGirlProfile(withPost.profileId)!;
  const plan = momentPlanFor({ girl, time }).slots.find((s) =>
    s.slot === withPost.slot
  )!;

  const harness = makeHarness({
    unlocked: [
      { profileId: withPost.profileId },
      { profileId: withoutPost.profileId },
    ],
    existing: [{
      profile_id: withPost.profileId,
      post_date: time.isoDate,
      slot: withPost.slot,
      day_part: plan.dayPart,
      theme_id: plan.themeId,
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-24T00:00:00.000Z",
    }],
    rateLimitError: 'unhandled exception: "MODEL_RATE_LIMITED_MINUTE"',
  });

  const result = await run(harness, {});

  // 關鍵斷言：不是 429，而且既有貼文還在。
  assertEquals(result.status, 200);
  const kept = body(result).posts as { profileId: string }[];
  assertEquals(kept.length, 1);
  assertEquals(kept[0].profileId, withPost.profileId);
  assertEquals(body(result).generatedCount, 0);
  assert(
    (body(result).pendingCount as number) > 0,
    "缺的那則要如實回報為 pending，不能假裝沒事",
  );

  // 限流命中就不該打模型；原子 reserve transaction 會連 attempts 一起 rollback。
  assertEquals(harness.modelCalls.length, 0);
  assertEquals(
    rpcNames(harness).includes("reserve_practice_moment_slot"),
    true,
  );
  assertEquals(
    rpcNames(harness).includes("increment_model_usage"),
    false,
    "handler 不得在 reserve 之外先扣一次限流",
  );

  // 既然不再是 429，就更不該出現訂閱額度鍵誤導成升級 CTA。
  assertEquals("monthlyLimit" in body(result), false);
  assertEquals("dailyLimit" in body(result), false);
});

// 2026-08-24 複審 BLOCK 2：6/min、60/day 必須對得起「模型呼叫次數」。
// 舊實作在 handler 進入點只記 1 次，卻平行打最多 MOMENT_FILL_MAX_PER_REQUEST 次，
// 實際上界被放大成 18/min、180/day。
Deno.test("每次模型呼叫都只由一次原子 reserve gate 授權", async () => {
  const due = profilesDueAt(NOON);
  const unlocked = due.slice(0, MOMENT_FILL_MAX_PER_REQUEST).map((entry) => ({
    profileId: entry.profileId,
  }));
  assert(
    unlocked.length > 1,
    "這條測試需要一次補多於一則，才驗得出放大效果",
  );

  const harness = makeHarness({ unlocked });
  await run(harness, {});

  const reserveCalls =
    rpcNames(harness).filter((n) => n === "reserve_practice_moment_slot")
      .length;
  assertEquals(
    reserveCalls,
    harness.modelCalls.length,
    `原子 gate 放行 ${reserveCalls} 次但打了 ${harness.modelCalls.length} 次模型`,
  );
  assertEquals(
    rpcNames(harness).includes("increment_model_usage"),
    false,
    "per-user usage 必須封裝在原子 reserve transaction，不能由 Edge 提前計數",
  );
  assert(harness.modelCalls.length > 1, "抽樣要真的有補到多於一則");
});

// 2026-08-24 複審 BLOCK 3：死線守門必須在 reserve 之前。reserve 會先把 attempts +1，
// 前置 DB 慢的時候可能一次模型都沒打就白白燒掉一次額度。
Deno.test("死線已過 → 連 reserve 都不做，不浪費 attempts", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({ unlocked: [{ profileId: due[0].profileId }] });

  // 死線設為 0：進到 fillOneSlot 時必定已過期。
  const result = await run(harness, { fillDeadlineMs: 0 });

  assertEquals(result.status, 200);
  assertEquals(harness.modelCalls.length, 0);
  assertEquals(
    rpcNames(harness).includes("reserve_practice_moment_slot"),
    false,
    "死線已過還去 reserve，會白燒一次 attempts",
  );
  assertEquals(body(result).generatedCount, 0);
});

Deno.test("保底在死線前未開始 → telemetry 不記 freshness fill 或 reserve attempt", async () => {
  const queenieId = "practice_girl_094";
  const harness = makeHarness({
    unlocked: [{ profileId: queenieId }],
    existing: [{
      profile_id: queenieId,
      post_date: "2026-08-20",
      slot: 0,
      day_part: "morning",
      theme_id: "coffee_start",
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-19T23:05:00.000Z",
    }],
    planFor: ({ girl, time }) => ({
      profileId: girl.profileId,
      isoDate: time.isoDate,
      slots: [],
    }),
  });
  const events: Record<string, unknown>[] = [];
  const originalLog = console.log;
  console.log = (message?: unknown) => {
    if (typeof message !== "string") return;
    try {
      const parsed = JSON.parse(message);
      if (typeof parsed === "object" && parsed !== null) {
        events.push(parsed as Record<string, unknown>);
      }
    } catch {
      // 只收結構化 logger 輸出。
    }
  };
  try {
    const result = await run(harness, {
      now: END_OF_DAY,
      fillDeadlineMs: 0,
    });
    await drain(20);
    assertEquals(result.status, 200);
  } finally {
    console.log = originalLog;
  }

  assertEquals(
    events.some((event) => event.event === "practice_moments_freshness_fill"),
    false,
    "未開始 reserve 就不應宣稱已啟動 freshness fill",
  );
  const filledEvent = events.find((event) =>
    event.event === "practice_moments_filled"
  );
  assert(filledEvent);
  assertEquals(filledEvent.attempted, 0);
  assertEquals(
    rpcNames(harness).includes("reserve_practice_moment_slot"),
    false,
  );
});

Deno.test("限流與 attempts 封裝在唯一的原子 reserve gate", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({ unlocked: [{ profileId: due[0].profileId }] });
  await run(harness, {});
  const names = rpcNames(harness);
  assert(names.includes("reserve_practice_moment_slot"));
  assertEquals(names.includes("increment_model_usage"), false);
});

Deno.test("原子 gate infra 錯誤 → fail-closed 不燒模型，feed 仍回 200", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    rateLimitError: "connection reset by peer",
  });
  const result = await run(harness, {});
  assertEquals(result.status, 200);
  assertEquals(harness.modelCalls.length, 0);
  assertEquals(body(result).generatedCount, 0);
});

Deno.test("沒有到時間的缺口時，連限流都不打（純讀路徑零成本）", async () => {
  const early = new Date(Date.UTC(2026, 7, 21, 22, 0, 0)); // 台北 06:00
  const harness = makeHarness({
    unlocked: GIRL_PROFILES.slice(0, 10).map((g) => ({
      profileId: g.profileId,
    })),
  });
  const result = await run(harness, { now: early });
  assertEquals(result.status, 200);
  assertEquals(rpcNames(harness).includes("increment_model_usage"), false);
});

// ---------------------------------------------------------------------------
// 韌性
// ---------------------------------------------------------------------------

Deno.test("momentPlanFor 對某一位丟例外 → 其他角色照常，狀態 200", async () => {
  const due = profilesDueAt(NOON);
  const unlocked = [...new Set(due.map((entry) => entry.profileId))].slice(
    0,
    3,
  );
  const broken = unlocked[0];
  const harness = makeHarness({
    unlocked: unlocked.map((profileId) => ({ profileId })),
  });
  const result = await handlePracticeMoments({
    supabase: harness.supabase,
    userId: USER_ID,
    now: NOON,
    isTestAccount: false,
    deps: {
      apiKey: "test-key",
      fillDeadlineMs: 400,
      planFor: (opts) => {
        if (opts.girl.profileId === broken) {
          throw new Error(`moment_schedule_empty_theme_pool:${broken}`);
        }
        return momentPlanFor(opts);
      },
      callDeepSeek: () =>
        Promise.resolve(JSON.stringify({ text: VALID_BODY, imageId: null })),
    },
  });
  assertEquals(result.status, 200);
  const posts = body(result).posts as { profileId: string }[];
  assert(posts.length > 0, "其他角色的貼文必須照常回");
  assertEquals(posts.some((post) => post.profileId === broken), false);
});

Deno.test("讀已解鎖角色失敗 → 500，不繼續往下打模型", async () => {
  const harness = makeHarness({ drawError: "connection refused" });
  const result = await run(harness, {});
  assertEquals(result.status, 500);
  assertEquals(body(result).error, "practice_moments_failed");
  assertEquals(harness.modelCalls.length, 0);
});

Deno.test("讀既有貼文失敗 → 500，不補生成", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    listError: "relation does not exist",
  });
  const result = await run(harness, {});
  assertEquals(result.status, 500);
  assertEquals(harness.modelCalls.length, 0);
});

Deno.test("缺 DeepSeek 金鑰 → 回既有貼文但不生成，不是 500", async () => {
  const time = taipeiTimeContextFor(END_OF_DAY);
  const due = profilesDueAt(END_OF_DAY);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    existing: [],
  });
  const result = await handlePracticeMoments({
    supabase: harness.supabase,
    userId: USER_ID,
    now: END_OF_DAY,
    isTestAccount: false,
    deps: {
      apiKey: "",
      callDeepSeek: () => {
        throw new Error("不該被呼叫");
      },
    },
  });
  assertEquals(result.status, 200);
  assertEquals(body(result).generatedCount, 0);
  assertEquals(
    rpcNames(harness).includes("reserve_practice_moment_slot"),
    false,
  );
  assert(time.isoDate.length > 0);
});

// ---------------------------------------------------------------------------
// 契約細節
// ---------------------------------------------------------------------------

Deno.test("feed 只往回看 FEED_WINDOW_DAYS 天", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({ unlocked: [{ profileId: due[0].profileId }] });
  await run(harness, {});
  const listCall = harness.rpcCalls.find((call) =>
    call.fn === "list_practice_moment_posts"
  );
  assert(listCall);
  assertEquals(listCall.params.p_since, "2026-08-09");
  assertEquals(
    Math.round(
      (Date.parse("2026-08-22") - Date.parse("2026-08-09")) / 86400000,
    ) + 1,
    FEED_WINDOW_DAYS,
  );
});

Deno.test("posts 依 postedAt 遞減排序", async () => {
  const time = taipeiTimeContextFor(END_OF_DAY);
  const due = profilesDueAt(END_OF_DAY).slice(0, 8);
  const existing = due.map((entry) => {
    const girl = getPracticeGirlProfile(entry.profileId)!;
    const plan = momentPlanFor({ girl, time }).slots.find((s) =>
      s.slot === entry.slot
    )!;
    return {
      profile_id: entry.profileId,
      post_date: time.isoDate,
      slot: entry.slot,
      day_part: plan.dayPart,
      theme_id: plan.themeId,
      body: VALID_BODY,
      image_id: null,
      created_at: "2026-08-22T00:00:00.000Z",
    };
  });
  const harness = makeHarness({
    unlocked: [...new Set(due.map((e) => e.profileId))].map((profileId) => ({
      profileId,
    })),
    existing,
  });
  const result = await run(harness, { now: END_OF_DAY });
  const posts = body(result).posts as { postedAt: string }[];
  assert(posts.length > 1);
  for (let i = 1; i < posts.length; i++) {
    assert(
      Date.parse(posts[i - 1].postedAt) >= Date.parse(posts[i].postedAt),
      "posts 沒有依 postedAt 遞減排序",
    );
  }
});

Deno.test("配圖貼文：候選只可能是可用素材，且原樣回給 client", async () => {
  const time = taipeiTimeContextFor(END_OF_DAY);
  // 題材池擴充時，固定角色的雜湊落點可能改變；改從完整角色池找當天確實
  // 想配圖的固定案例，讓測試守住圖片契約而不是綁死某一個題材落點。
  const imageCase = GIRL_PROFILES.map((girl) => ({
    girl,
    slot: momentPlanFor({ girl, time }).slots.find((slot) =>
      slot.wantsImage &&
      resolveAvailableMomentImages(slot.imageCandidates).length > 0
    ),
  })).find((entry) => entry.slot !== undefined);
  assert(imageCase?.slot, "前提：當天至少有一個閘門後仍有候選的配圖 slot");
  const { girl, slot } = imageCase;
  // stub 回「該 slot 閘門後候選的第一個」而不是寫死某個 id：
  // 閘門開關（AVAILABLE_MOMENT_IMAGE_IDS 的內容）不是本測試的受測物，
  // 寫死 id 會讓這條測試隨閘門狀態翻紅（2026-08-25 開閘時抓到過一次）。
  const usable = resolveAvailableMomentImages(slot.imageCandidates);
  assert(usable.length > 0, "前提：閘門後仍有候選（替換語義保證非空）");
  const chosen = usable[0];
  const harness = makeHarness({
    unlocked: [{ profileId: girl.profileId }],
    model: () =>
      Promise.resolve(JSON.stringify({ text: VALID_BODY, imageId: chosen })),
  });
  const result = await run(harness, { now: END_OF_DAY });
  const commits = harness.rpcCalls.filter((call) =>
    call.fn === "commit_practice_moment_post"
  );
  const withImage = commits.find((call) => call.params.p_image_id !== null);
  assert(withImage, "應該有一則帶圖的 commit");
  assertEquals(withImage.params.p_image_id, chosen);
  assert(
    usable.includes(withImage.params.p_image_id as string),
    "commit 的 imageId 必須在閘門後候選內",
  );
  const posts = body(result).posts as { imageId: string | null }[];
  assert(posts.some((post) => post.imageId === chosen));
});

Deno.test("reply-style（PR-5）：deps.replyStyleEnabled 才把她的打字習慣放進貼文 prompt；省略時 system 逐字不變", async () => {
  const queenieId = "practice_girl_094";
  const harnessFor = () =>
    makeHarness({
      unlocked: [{ profileId: queenieId }],
      existing: [{
        profile_id: queenieId,
        post_date: "2026-08-20",
        slot: 0,
        day_part: "morning",
        theme_id: "coffee_start",
        body: VALID_BODY,
        image_id: null,
        created_at: "2026-08-19T23:05:00.000Z",
      }],
      planFor: ({ girl, time }) => ({
        profileId: girl.profileId,
        isoDate: time.isoDate,
        slots: [],
      }),
      slotStates: [
        { profile_id: queenieId, slot: 0, claimable: false },
        { profile_id: queenieId, slot: 1, claimable: true },
      ],
    });
  const off = harnessFor();
  await run(off, { now: END_OF_DAY });
  const on = harnessFor();
  await run(on, { now: END_OF_DAY, replyStyleEnabled: true });
  assertEquals(off.modelCalls.length, 1);
  assertEquals(on.modelCalls.length, 1);
  assert(!off.modelCalls[0].system.includes("你個人的打字習慣"));
  const adapter = renderMomentStyleAdapter(replyStyleFor(queenieId)!);
  assert(on.modelCalls[0].system.includes(adapter));
  assertEquals(
    on.modelCalls[0].system.replace(adapter, ""),
    off.modelCalls[0].system,
  );
});

// 動態貼文生成與 feed handler 的行為契約。
//
// 這支測試守的是整個功能最貴的三件事：**不會重複生成、不會超支、不會寫
// 假內容**。所有 DeepSeek 都是 stub，一次真的模型呼叫都不會發生。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  handlePracticeMoments,
  type MomentsSupabaseClient,
} from "./moments_handler.ts";
import {
  FEED_WINDOW_DAYS,
  MOMENT_FILL_MAX_PER_REQUEST,
} from "./moments_constants.ts";
import { momentPostedAtFor } from "./moments_time.ts";
import { momentPlanFor } from "./moments_schedule.ts";
import { taipeiTimeContextFor } from "./time_context.ts";
import { getPracticeGirlProfile, GIRL_PROFILES } from "./practice_persona.ts";
import { SELF_PORTRAIT_IMAGE_ID } from "./moments_image_catalog.ts";

type Row = Record<string, unknown>;

const USER_ID = "11111111-2222-3333-4444-555555555555";
/** 台北 2026-08-22（週六）11:00。 */
const NOON = new Date(Date.UTC(2026, 7, 22, 3, 0, 0));
/** 同一天台北 23:59，讓當天所有時段都已到時間。 */
const END_OF_DAY = new Date(Date.UTC(2026, 7, 22, 15, 59, 0));

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
  reserve?: (params: Row, index: number) => Row | null;
  commit?: (params: Row) => Row;
  release?: (params: Row) => Row;
  rateLimitError?: string;
  model?: (index: number, timeoutMs: number) => Promise<string>;
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
      if (fn === "reserve_practice_moment_slot") {
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
  overrides: { now?: Date; fillDeadlineMs?: number } = {},
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
      fillDeadlineMs: overrides.fillDeadlineMs ?? 400,
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

Deno.test("限流命中 → 429，且一次 reserve 都沒有", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    rateLimitError: 'unhandled exception: "MODEL_RATE_LIMITED_MINUTE"',
  });
  const result = await run(harness, {});
  assertEquals(result.status, 429);
  assertEquals(harness.modelCalls.length, 0);
  assertEquals(
    rpcNames(harness).includes("reserve_practice_moment_slot"),
    false,
  );
  assertEquals(body(result).retryable, false);
  // 429 絕不帶訂閱額度鍵，否則 client 會把限流誤導成升級 CTA。
  assertEquals("monthlyLimit" in body(result), false);
  assertEquals("dailyLimit" in body(result), false);
});

Deno.test("限流的 RPC 一定排在第一個 reserve 之前", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({ unlocked: [{ profileId: due[0].profileId }] });
  await run(harness, {});
  const names = rpcNames(harness);
  const limitAt = names.indexOf("increment_model_usage");
  const reserveAt = names.indexOf("reserve_practice_moment_slot");
  assert(limitAt >= 0 && reserveAt >= 0);
  assert(limitAt < reserveAt, "限流必須在 reserve 之前");
});

Deno.test("限流 RPC infra 錯誤 → fail-open 放行，不擋 feed", async () => {
  const due = profilesDueAt(NOON);
  const harness = makeHarness({
    unlocked: [{ profileId: due[0].profileId }],
    rateLimitError: "connection reset by peer",
  });
  const result = await run(harness, {});
  assertEquals(result.status, 200);
  assertEquals(harness.modelCalls.length, 1);
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
  // practice_girl_019 在 2026-08-22 的 slot 1 是 wantsImage 的題材。
  const girl = getPracticeGirlProfile("practice_girl_019")!;
  const time = taipeiTimeContextFor(END_OF_DAY);
  const slot = momentPlanFor({ girl, time }).slots.find((s) => s.wantsImage);
  assert(slot, "前提：這位角色當天有想配圖的 slot");
  const harness = makeHarness({
    unlocked: [{ profileId: girl.profileId }],
    model: () =>
      Promise.resolve(
        JSON.stringify({ text: VALID_BODY, imageId: SELF_PORTRAIT_IMAGE_ID }),
      ),
  });
  const result = await run(harness, { now: END_OF_DAY });
  const commits = harness.rpcCalls.filter((call) =>
    call.fn === "commit_practice_moment_post"
  );
  const withImage = commits.find((call) => call.params.p_image_id !== null);
  assert(withImage, "應該有一則帶圖的 commit");
  assertEquals(withImage.params.p_image_id, SELF_PORTRAIT_IMAGE_ID);
  const posts = body(result).posts as { imageId: string | null }[];
  assert(posts.some((post) => post.imageId === SELF_PORTRAIT_IMAGE_ID));
});

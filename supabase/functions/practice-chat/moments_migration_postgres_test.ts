// 練習室模擬社群動態（PR A）資料層的真 Postgres 契約測試。
//
// 為什麼要用 PGlite 而不是字串斷言：`reserve_practice_moment_slot` 的六態轉移表
// 是整個功能「不會重複生成、不會超支、不會寫假內容」的唯一機械證明，而那六格
// 只有在真的 Postgres 交易語義下才驗得出來（FOR UPDATE、ON CONFLICT DO NOTHING、
// RLS 無 policy 的預設拒絕）。PGlite 是 WASM 版 Postgres，跑在測試行程內，
// 不需要任何憑證或連線——範式沿用 practice_ai_no_canned_postgres_test.ts。
//
// 本檔直接載入 migration 原始 SQL，所以它同時是「SQL 真的能套用」的煙霧測試。
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const momentPostsMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260822120000_practice_moment_posts.sql",
    import.meta.url,
  ),
);
const modelRateLimitMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260703170000_model_call_rate_limit.sql",
    import.meta.url,
  ),
);

const PROFILE_ID = "practice_girl_007";
const POST_DATE = "2026-08-22";
const SLOT = 0;
const DAY_PART = "afternoon";
const THEME_ID = "coffee_break";
const USER_ID = "11111111-2222-3333-4444-555555555555";
const CONTENDER_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";

/** 與 migration 內 CHECK (attempts BETWEEN 0 AND 3) 的上界一致。 */
const MAX_MOMENT_ATTEMPTS = 3;

interface ReserveRow {
  claimed: boolean;
  token: string | null;
  attempt_count: number | null;
}

interface PostRow {
  status: string;
  attempts: number;
  body: string | null;
  image_id: string | null;
  generation_token: string | null;
  model: string | null;
  day_part: string;
  theme_id: string;
}

interface UsageRow {
  minute_count: number;
  day_count: number;
}

async function createDatabase(): Promise<PGlite> {
  const db = new PGlite();
  // 忠實重現 Supabase 的角色與預設授權：新建物件會自動拿到 anon/authenticated
  // 的權限，所以 migration 內的 REVOKE 是否真的有效，只有在這個前提下才驗得準。
  await db.exec(`
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (id UUID PRIMARY KEY);
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT ALL ON TABLES TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
  `);
  await db.exec(modelRateLimitMigration);
  await db.exec(momentPostsMigration);
  await db.query(
    `INSERT INTO auth.users(id) VALUES ($1), ($2)`,
    [USER_ID, CONTENDER_USER_ID],
  );
  return db;
}

async function reserve(
  db: PGlite,
  token: string,
  options: {
    slot?: number;
    postDate?: string;
    profileId?: string;
    userId?: string;
    countUserUsage?: boolean;
    minuteLimit?: number;
    dailyLimit?: number;
  } = {},
): Promise<ReserveRow> {
  const result = await db.query<ReserveRow>(
    `SELECT claimed, token, attempt_count
     FROM public.reserve_practice_moment_slot(
       $1, $2::DATE, $3, $4, $5, $6, $7::UUID, $8, $9, $10
     )`,
    [
      options.profileId ?? PROFILE_ID,
      options.postDate ?? POST_DATE,
      options.slot ?? SLOT,
      DAY_PART,
      THEME_ID,
      token,
      options.userId ?? USER_ID,
      options.minuteLimit ?? 6,
      options.dailyLimit ?? 60,
      options.countUserUsage ?? true,
    ],
  );
  return result.rows[0];
}

async function commitPost(
  db: PGlite,
  token: string,
  body: string,
  imageId: string | null = null,
): Promise<boolean> {
  const result = await db.query<{ committed: boolean }>(
    `SELECT committed
     FROM public.commit_practice_moment_post(
       $1, $2::DATE, $3, $4, $5, $6, $7
     )`,
    [PROFILE_ID, POST_DATE, SLOT, token, body, imageId, "deepseek-v4-flash"],
  );
  return result.rows[0].committed;
}

async function release(db: PGlite, token: string): Promise<boolean> {
  const result = await db.query<{ released: boolean }>(
    `SELECT released
     FROM public.release_practice_moment_slot($1, $2::DATE, $3, $4)`,
    [PROFILE_ID, POST_DATE, SLOT, token],
  );
  return result.rows[0].released;
}

/** 讓租約逾時，不動 attempts／token，模擬 worker 中途死掉。 */
async function expireLease(db: PGlite): Promise<void> {
  await db.query(
    `UPDATE public.practice_moment_posts
     SET reserved_at = now() - interval '5 minutes'
     WHERE profile_id = $1 AND post_date = $2::DATE AND slot = $3`,
    [PROFILE_ID, POST_DATE, SLOT],
  );
}

async function readPost(db: PGlite): Promise<PostRow> {
  const result = await db.query<PostRow>(
    `SELECT status, attempts, body, image_id, generation_token, model,
            day_part, theme_id
     FROM public.practice_moment_posts
     WHERE profile_id = $1 AND post_date = $2::DATE AND slot = $3`,
    [PROFILE_ID, POST_DATE, SLOT],
  );
  return result.rows[0];
}

async function countPosts(db: PGlite): Promise<number> {
  const result = await db.query<{ total: number }>(
    `SELECT count(*)::INT AS total FROM public.practice_moment_posts`,
  );
  return result.rows[0].total;
}

async function readUsage(
  db: PGlite,
  userId: string,
): Promise<UsageRow | null> {
  const result = await db.query<UsageRow>(
    `SELECT minute_count, day_count
     FROM public.model_call_rate_limits
     WHERE user_id = $1::UUID AND scope = 'practice_moment'`,
    [userId],
  );
  return result.rows[0] ?? null;
}

// ---------------------------------------------------------------------------
// 六態轉移表（設計報告 §4）：一格一條
// ---------------------------------------------------------------------------

// 轉移表第 1 格。★ 複審點名的坑 #1：首次 INSERT 必須明寫 attempts = 1，
// 不能靠 DEFAULT 0。用 0 的話第一次認領不計數，之後還能再遞增三次 →
// 每 slot 實際跑 4 次而不是 3 次，整體上限上浮 1/3。
// 註（複審 P2-1）：全站每日 600 是「Edge allowlist × DB」共同保證，不是 DB 單獨
// 保證——DB 只機械保證每個 (profile_id, post_date) 最多 2 slot × 3 attempts。
Deno.test("PostgreSQL reserve claims a missing moment slot and counts the first attempt", async () => {
  const db = await createDatabase();
  try {
    const claim = await reserve(db, "token-first");
    assertEquals(claim.claimed, true);
    assertEquals(claim.token, "token-first");
    assertEquals(
      claim.attempt_count,
      1,
      "首次認領就必須計入一次模型呼叫，否則每個 slot 會跑 4 次而不是 3 次（整體上限上浮 1/3）",
    );

    const row = await readPost(db);
    assertEquals(row.status, "reserved");
    assertEquals(
      row.attempts,
      1,
      "落盤的 attempts 必須是 1，不是 DEFAULT 0",
    );
    assertEquals(row.generation_token, "token-first");
    assertEquals(row.body, null);
    assertEquals(row.day_part, DAY_PART);
    assertEquals(row.theme_id, THEME_ID);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL test-account reserve counts the global attempt but bypasses user usage", async () => {
  const db = await createDatabase();
  try {
    const claim = await reserve(db, "token-test-account", {
      countUserUsage: false,
    });
    assertEquals(claim.claimed, true);
    assertEquals(claim.attempt_count, 1);
    assertEquals((await readPost(db)).attempts, 1);
    assertEquals(await readUsage(db, USER_ID), null);
  } finally {
    await db.close();
  }
});

// 轉移表第 2 格。
Deno.test("PostgreSQL reserve refuses a ready moment slot", async () => {
  const db = await createDatabase();
  try {
    const first = await reserve(db, "token-a");
    assertEquals(first.claimed, true);
    assertEquals(
      await commitPost(db, "token-a", "今天的咖啡比鬧鐘有用多了。"),
      true,
    );

    const second = await reserve(db, "token-b");
    assertEquals(second.claimed, false);
    assertEquals(second.token, null);

    const row = await readPost(db);
    assertEquals(row.status, "ready");
    assertEquals(row.attempts, 1, "被拒絕的認領不得消耗 attempts");
    assertEquals(row.body, "今天的咖啡比鬧鐘有用多了。");
  } finally {
    await db.close();
  }
});

// 轉移表第 3 格。
Deno.test("PostgreSQL reserve refuses an exhausted moment slot", async () => {
  const db = await createDatabase();
  try {
    for (let attempt = 1; attempt <= MAX_MOMENT_ATTEMPTS; attempt += 1) {
      const claim = await reserve(db, `token-${attempt}`);
      assertEquals(claim.claimed, true);
      assertEquals(claim.attempt_count, attempt);
      await expireLease(db);
    }

    const exhausting = await reserve(db, "token-4");
    assertEquals(exhausting.claimed, false);
    assertEquals((await readPost(db)).status, "exhausted");

    // 已經是 exhausted 的列，之後每一次認領都必須被擋掉。
    const afterExhausted = await reserve(db, "token-5");
    assertEquals(afterExhausted.claimed, false);
    const row = await readPost(db);
    assertEquals(row.status, "exhausted");
    assertEquals(row.attempts, MAX_MOMENT_ATTEMPTS);
    assertEquals(row.generation_token, null);
  } finally {
    await db.close();
  }
});

// 轉移表第 4 格：別人正在跑，租約仍有效。
Deno.test("PostgreSQL reserve refuses a slot whose lease is still fresh", async () => {
  const db = await createDatabase();
  try {
    assertEquals((await reserve(db, "token-owner")).claimed, true);

    const contender = await reserve(db, "token-contender");
    assertEquals(contender.claimed, false);
    assertEquals(contender.token, null);

    const row = await readPost(db);
    assertEquals(
      row.generation_token,
      "token-owner",
      "租約有效時不得換發 token",
    );
    assertEquals(row.attempts, 1, "被擋下的併發請求不得消耗 attempts");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL contested reserve does not consume the losing user's model usage", async () => {
  const db = await createDatabase();
  try {
    assertEquals((await reserve(db, "token-owner")).claimed, true);
    assertEquals(await readUsage(db, USER_ID), {
      minute_count: 1,
      day_count: 1,
    });

    const contender = await reserve(db, "token-contender", {
      userId: CONTENDER_USER_ID,
    });
    assertEquals(contender.claimed, false);
    assertEquals(
      await readUsage(db, CONTENDER_USER_ID),
      null,
      "沒有取得 slot 就沒有模型呼叫，不得建立或遞增使用者限流計數",
    );
    assertEquals((await readPost(db)).attempts, 1);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL rate-limit rejection rolls back the whole slot claim", async () => {
  const db = await createDatabase();
  try {
    await db.query(
      `INSERT INTO public.model_call_rate_limits(
         user_id, scope, minute_window_start, minute_count,
         day_window_start, day_count
       ) VALUES ($1::UUID, 'practice_moment', now(), 6, now(), 6)`,
      [USER_ID],
    );

    let denied = "";
    try {
      await reserve(db, "token-over-user-limit");
    } catch (error) {
      denied = String(error);
    }
    assert(
      denied.includes("MODEL_RATE_LIMITED_MINUTE"),
      `應由同一筆 transaction 擋下限流，實際：${denied}`,
    );
    assertEquals(
      await countPosts(db),
      0,
      "限流 RAISE 必須連首次 INSERT 與 attempts 一起 rollback",
    );
    assertEquals(await readUsage(db, USER_ID), {
      minute_count: 6,
      day_count: 6,
    });
  } finally {
    await db.close();
  }
});

// 轉移表第 5 格：租約逾時 + attempts < 上限。
Deno.test("PostgreSQL reserve takes over an expired lease and increments attempts", async () => {
  const db = await createDatabase();
  try {
    assertEquals((await reserve(db, "token-dead")).claimed, true);
    await expireLease(db);

    const takeover = await reserve(db, "token-live");
    assertEquals(takeover.claimed, true);
    assertEquals(takeover.token, "token-live");
    assertEquals(takeover.attempt_count, 2);

    const row = await readPost(db);
    assertEquals(row.status, "reserved");
    assertEquals(row.attempts, 2);
    assertEquals(row.generation_token, "token-live");
  } finally {
    await db.close();
  }
});

// 轉移表第 6 格：租約逾時 + attempts 已達上限 → 轉 exhausted。
Deno.test("PostgreSQL reserve exhausts a slot that used up every attempt", async () => {
  const db = await createDatabase();
  try {
    for (let attempt = 1; attempt <= MAX_MOMENT_ATTEMPTS; attempt += 1) {
      assertEquals((await reserve(db, `token-${attempt}`)).claimed, true);
      await expireLease(db);
    }
    assertEquals((await readPost(db)).attempts, MAX_MOMENT_ATTEMPTS);

    const denied = await reserve(db, "token-over-budget");
    assertEquals(denied.claimed, false);
    assertEquals(denied.token, null);

    const row = await readPost(db);
    assertEquals(row.status, "exhausted");
    assertEquals(
      row.attempts,
      MAX_MOMENT_ATTEMPTS,
      "轉 exhausted 不得再多記一次 attempts",
    );
    assertEquals(row.generation_token, null);
    assertEquals(row.body, null, "沒有一次成功過的 slot 永遠不該有 body");
  } finally {
    await db.close();
  }
});

// ---------------------------------------------------------------------------
// ★ 複審點名的坑 #2
// ---------------------------------------------------------------------------

// release 的用途就是「我失敗了，別人不必等租約逾時就能接手」。若 reserve 只看
// 租約時間，被 release 的列會被自己剛剛寫下的新鮮 reserved_at 擋住兩分鐘，
// release 等於完全沒有作用。generation_token IS NULL 必須是獨立的放行分支。
Deno.test("PostgreSQL reserve succeeds immediately after release despite a fresh reserved_at", async () => {
  const db = await createDatabase();
  try {
    assertEquals((await reserve(db, "token-failed")).claimed, true);
    assertEquals(await release(db, "token-failed"), true);

    const beforeRetry = await readPost(db);
    assertEquals(beforeRetry.generation_token, null);
    assertEquals(beforeRetry.status, "reserved");

    // 刻意不呼叫 expireLease()：reserved_at 還是幾毫秒前的值。
    const retry = await reserve(db, "token-retry");
    assertEquals(
      retry.claimed,
      true,
      "release 之後必須能立刻接手，不能被自己新鮮的 reserved_at 擋住",
    );
    assertEquals(retry.token, "token-retry");
    assertEquals(retry.attempt_count, 2);
  } finally {
    await db.close();
  }
});

// ---------------------------------------------------------------------------
// token fencing 與 no-canned 不變式
// ---------------------------------------------------------------------------

Deno.test("PostgreSQL commit refuses a stale token and leaves the body untouched", async () => {
  const db = await createDatabase();
  try {
    assertEquals((await reserve(db, "token-stale")).claimed, true);
    await expireLease(db);
    assertEquals((await reserve(db, "token-current")).claimed, true);

    assertEquals(
      await commitPost(db, "token-stale", "被接手的舊 worker 想寫的內容。"),
      false,
    );
    assertEquals((await readPost(db)).body, null);

    assertEquals(
      await commitPost(db, "token-current", "傍晚的風終於涼下來了。"),
      true,
    );
    assertEquals((await readPost(db)).body, "傍晚的風終於涼下來了。");

    // 遲到的舊 worker 不得覆寫已經 ready 的內容。
    assertEquals(await commitPost(db, "token-stale", "遲到的覆寫。"), false);
    assertEquals((await readPost(db)).body, "傍晚的風終於涼下來了。");
  } finally {
    await db.close();
  }
});

// no-canned 鐵則的資料層證明：生成失敗永不落盤。
Deno.test("PostgreSQL release never writes a body", async () => {
  const db = await createDatabase();
  try {
    assertEquals((await reserve(db, "token-x")).claimed, true);
    assertEquals(await release(db, "token-x"), true);

    const row = await readPost(db);
    assertEquals(row.body, null);
    assertEquals(row.image_id, null);
    assertEquals(row.model, null);
    assertEquals(row.status, "reserved");
    assertEquals(row.attempts, 1, "release 不得回收已經用掉的 attempts");

    // 錯的 token 不得清掉別人的租約。
    assertEquals((await reserve(db, "token-y")).claimed, true);
    assertEquals(await release(db, "token-wrong"), false);
    assertEquals((await readPost(db)).generation_token, "token-y");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL release never deletes the row", async () => {
  const db = await createDatabase();
  try {
    assertEquals((await reserve(db, "token-keep")).claimed, true);
    const before = await countPosts(db);
    assertEquals(before, 1);

    assertEquals(await release(db, "token-keep"), true);
    assertEquals(await countPosts(db), before);

    // attempts 用完時 release 要順手轉 exhausted，但同樣不刪列。
    for (let attempt = 2; attempt <= MAX_MOMENT_ATTEMPTS; attempt += 1) {
      assertEquals((await reserve(db, `token-${attempt}`)).claimed, true);
      assertEquals(await release(db, `token-${attempt}`), true);
    }
    const row = await readPost(db);
    assertEquals(row.status, "exhausted");
    assertEquals(row.attempts, MAX_MOMENT_ATTEMPTS);
    assertEquals(await countPosts(db), before);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL commit stores a ready post within the body length guard", async () => {
  const db = await createDatabase();
  try {
    assertEquals((await reserve(db, "token-ok")).claimed, true);
    assertEquals(
      await commitPost(
        db,
        "token-ok",
        "整理書架時翻到高中的筆記本，字醜得像另一個人。",
        "moment_self_portrait",
      ),
      true,
    );

    const stored = await db.query<{
      status: string;
      body_length: number;
      image_id: string | null;
      model: string | null;
      generation_token: string | null;
      within_guard: boolean;
    }>(
      `SELECT status,
              char_length(body) AS body_length,
              image_id,
              model,
              generation_token,
              (char_length(body) BETWEEN 1 AND 220) AS within_guard
       FROM public.practice_moment_posts
       WHERE profile_id = $1 AND post_date = $2::DATE AND slot = $3`,
      [PROFILE_ID, POST_DATE, SLOT],
    );
    const row = stored.rows[0];
    assertEquals(row.status, "ready");
    assertEquals(row.within_guard, true);
    assertEquals(row.image_id, "moment_self_portrait");
    assertEquals(row.model, "deepseek-v4-flash");
    assertEquals(
      row.generation_token,
      null,
      "已 ready 的列不留 token，避免遲到的 worker 再寫一次",
    );
    assert(row.body_length > 0);
  } finally {
    await db.close();
  }
});

// ---------------------------------------------------------------------------
// 讀取面與權限面
// ---------------------------------------------------------------------------

Deno.test("PostgreSQL list returns only ready posts inside the requested window", async () => {
  const db = await createDatabase();
  try {
    // ready（在窗內）
    assertEquals((await reserve(db, "t-ready")).claimed, true);
    assertEquals(await commitPost(db, "t-ready", "窗內的一則。"), true);

    // reserved（同一位、另一個 slot）→ 不得外流
    assertEquals(
      (await reserve(db, "t-reserved", { slot: 1 })).claimed,
      true,
    );

    // ready 但在窗外
    assertEquals(
      (await reserve(db, "t-old", { postDate: "2026-07-01" })).claimed,
      true,
    );
    await db.query(
      `UPDATE public.practice_moment_posts
       SET status = 'ready', body = '窗外的一則。', generation_token = NULL
       WHERE post_date = '2026-07-01'::DATE`,
    );

    // 另一位角色的 ready 貼文 → 未指名就不得外流
    assertEquals(
      (await reserve(db, "t-other", { profileId: "practice_girl_042" }))
        .claimed,
      true,
    );
    await db.query(
      `UPDATE public.practice_moment_posts
       SET status = 'ready', body = '別人的一則。', generation_token = NULL
       WHERE profile_id = 'practice_girl_042'`,
    );

    const listed = await db.query<{ profile_id: string; body: string }>(
      `SELECT profile_id, body
       FROM public.list_practice_moment_posts($1, $2::DATE)`,
      [[PROFILE_ID], "2026-08-08"],
    );
    assertEquals(listed.rows.length, 1);
    assertEquals(listed.rows[0], {
      profile_id: PROFILE_ID,
      body: "窗內的一則。",
    });

    const both = await db.query<{ profile_id: string }>(
      `SELECT profile_id
       FROM public.list_practice_moment_posts($1, $2::DATE)`,
      [[PROFILE_ID, "practice_girl_042"], "2026-08-08"],
    );
    assertEquals(both.rows.length, 2);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL keeps moment posts and RPCs away from anon and authenticated", async () => {
  const db = await createDatabase();
  try {
    assertEquals((await reserve(db, "token-secret")).claimed, true);
    assertEquals(
      await commitPost(db, "token-secret", "只有 service_role 讀得到。"),
      true,
    );

    for (const role of ["anon", "authenticated"]) {
      await db.exec(`SET ROLE ${role};`);
      // RLS 開啟且無 policy → 即使有 SELECT 權限也讀不到任何列。
      const rows = await db.query<{ total: number }>(
        `SELECT count(*)::INT AS total FROM public.practice_moment_posts`,
      );
      assertEquals(
        rows.rows[0].total,
        0,
        `${role} 不得讀到任何動態貼文`,
      );

      let denied = "";
      try {
        await db.query(
          `SELECT claimed
           FROM public.reserve_practice_moment_slot(
             'practice_girl_001', '2026-08-22'::DATE, 0, 'morning', 'x', 'tok',
             '${USER_ID}'::UUID, 6, 60, TRUE
           )`,
        );
      } catch (error) {
        denied = String(error);
      }
      assert(
        denied.includes("permission denied"),
        `${role} 必須被 REVOKE 擋在 reserve_practice_moment_slot 之外，實際：${denied}`,
      );
      await db.exec(`RESET ROLE;`);
    }
  } finally {
    await db.close();
  }
});

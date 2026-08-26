// 練習室模擬社群動態：生成配圖資料層（PR-2）的真 Postgres 契約測試。
//
// 範式沿用 moments_migration_postgres_test.ts：PGlite 直接載入 migration 原始
// SQL，逐格驗 claim_practice_moment_image 的六態轉移表——那六格只有在真的
// Postgres 交易語義（FOR UPDATE、同交易限流 rollback）下才驗得出來。
// 本檔同時是「新 migration 疊在 0822/0824 之上真的能套用」的煙霧測試
// （含 storage schema 缺席時 bucket 區塊必須是 no-op）。
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  MAX_MOMENT_IMAGE_ATTEMPTS,
  MOMENT_IMAGE_RESERVE_LEASE_MS,
} from "./moments_constants.ts";

const modelRateLimitMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260703170000_model_call_rate_limit.sql",
    import.meta.url,
  ),
);
const momentPostsMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260822120000_practice_moment_posts.sql",
    import.meta.url,
  ),
);
const momentUsageUpgradeMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824063344_practice_moment_reserve_usage_gate.sql",
    import.meta.url,
  ),
);
const momentImagesMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260825120000_practice_moment_images.sql",
    import.meta.url,
  ),
);
const momentImageExpiryGuardMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260825150000_practice_moment_image_expiry_guards.sql",
    import.meta.url,
  ),
);
const momentImageOrphanLedgerMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260826024500_practice_moment_image_orphan_ledger.sql",
    import.meta.url,
  ),
);

const PROFILE_ID = "practice_girl_007";
/** 台北「今天」。DB 端 expiry cutoff 用真實 now() 判定，日期必須相對今天。 */
function taipeiToday(offsetDays = 0): string {
  const taipei = new Date(Date.now() + 8 * 3600_000 + offsetDays * 86_400_000);
  return taipei.toISOString().slice(0, 10);
}
const POST_DATE = taipeiToday();
/** 已出窗的貼文日（窗起點是今天-13，取今天-20 穩在窗外）。 */
const EXPIRED_POST_DATE = taipeiToday(-20);
const SLOT = 0;
const DAY_PART = "afternoon";
const THEME_ID = "coffee_break";
const USER_ID = "11111111-2222-3333-4444-555555555555";
const BODY = "下午的咖啡撐住了整個會議。";
const IMAGE_PATH = `${POST_DATE}/${PROFILE_ID}_${SLOT}_t-x.jpeg`;

interface ClaimRow {
  claimed: boolean;
  token: string | null;
  attempt_count: number | null;
  body: string | null;
  theme_id: string | null;
}

interface ImageRow {
  status: string;
  attempts: number;
  body: string | null;
  image_status: string;
  image_path: string | null;
  image_attempts: number;
  image_token: string | null;
}

async function createDatabase(): Promise<PGlite> {
  const db = new PGlite();
  // 忠實重現 Supabase 的角色與預設授權（比照既有測試），REVOKE 是否有效
  // 只有在這個前提下才驗得準。
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
  await db.exec(momentUsageUpgradeMigration);
  await db.exec(momentImagesMigration);
  await db.exec(momentImageExpiryGuardMigration);
  await db.exec(momentImageOrphanLedgerMigration);
  await db.query(`INSERT INTO auth.users(id) VALUES ($1)`, [USER_ID]);
  return db;
}

/** 走正規路徑鋪一則文字貼文：reserve → commit（可選 wants_image）。 */
async function seedPost(
  db: PGlite,
  opts: { wantsImage?: boolean; imageId?: string | null } = {},
): Promise<void> {
  await db.query(
    `SELECT claimed FROM public.reserve_practice_moment_slot(
       $1, $2::DATE, $3, $4, $5, $6, $7::UUID, 6, 60, FALSE
     )`,
    [PROFILE_ID, POST_DATE, SLOT, DAY_PART, THEME_ID, "seed-token", USER_ID],
  );
  const committed = await db.query<{ committed: boolean }>(
    `SELECT committed FROM public.commit_practice_moment_post(
       $1, $2::DATE, $3, $4, $5, $6, $7, $8
     )`,
    [
      PROFILE_ID,
      POST_DATE,
      SLOT,
      "seed-token",
      BODY,
      opts.imageId ?? null,
      "deepseek-v4-flash",
      opts.wantsImage ?? false,
    ],
  );
  assertEquals(committed.rows[0].committed, true);
}

/** Edge 端 momentImagePath 的同構：token 隔離、每次認領各一條路徑。 */
function tokenPath(token: string, postDate: string = POST_DATE): string {
  return `${postDate}/${PROFILE_ID}_${SLOT}_${token}.jpeg`;
}

async function claimImage(
  db: PGlite,
  token: string,
  options: {
    userId?: string;
    countUserUsage?: boolean;
    minuteLimit?: number;
    dailyLimit?: number;
    postDate?: string;
    imagePath?: string;
  } = {},
): Promise<ClaimRow> {
  const postDate = options.postDate ?? POST_DATE;
  const result = await db.query<ClaimRow>(
    `SELECT claimed, token, attempt_count, body, theme_id
     FROM public.claim_practice_moment_image(
       $1, $2::DATE, $3, $4, $5, $6::UUID, $7, $8, $9
     )`,
    [
      PROFILE_ID,
      postDate,
      SLOT,
      token,
      options.imagePath ?? tokenPath(token, postDate),
      options.userId ?? USER_ID,
      options.minuteLimit ?? 3,
      options.dailyLimit ?? 20,
      options.countUserUsage ?? true,
    ],
  );
  return result.rows[0];
}

/** 讀帳本（清算的唯一持久紀錄）。 */
async function orphanLedger(db: PGlite): Promise<string[]> {
  const result = await db.query<{ image_orphan_paths: string[] }>(
    `SELECT image_orphan_paths FROM public.practice_moment_posts
      WHERE profile_id = $1 AND slot = $2`,
    [PROFILE_ID, SLOT],
  );
  return result.rows[0].image_orphan_paths;
}

async function listOrphans(
  db: PGlite,
  graceSeconds = 0,
  limit = 20,
): Promise<string[]> {
  const result = await db.query<{ orphan_path: string }>(
    `SELECT orphan_path FROM public.list_practice_moment_image_orphans($1, $2)`,
    [limit, graceSeconds],
  );
  return result.rows.map((row) => row.orphan_path);
}

async function commitImage(
  db: PGlite,
  token: string,
  path: string = IMAGE_PATH,
  postDate: string = POST_DATE,
): Promise<boolean> {
  const result = await db.query<{ committed: boolean }>(
    `SELECT committed FROM public.commit_practice_moment_image(
       $1, $2::DATE, $3, $4, $5
     )`,
    [PROFILE_ID, postDate, SLOT, token, path],
  );
  return result.rows[0].committed;
}

async function releaseImage(db: PGlite, token: string): Promise<boolean> {
  const result = await db.query<{ released: boolean }>(
    `SELECT released FROM public.release_practice_moment_image(
       $1, $2::DATE, $3, $4
     )`,
    [PROFILE_ID, POST_DATE, SLOT, token],
  );
  return result.rows[0].released;
}

/**
 * 模擬「時間流逝跨過台北午夜」的等價變換：把列的 post_date 往回撥。
 * DB 端 cutoff 以真實 now() 計算不可注入；所有租約／token 都不看日期，
 * 位移 post_date 與快轉時鐘對這張表等價。
 */
async function shiftRowPostDate(db: PGlite, days: number): Promise<string> {
  const result = await db.query<{ post_date: string }>(
    `UPDATE public.practice_moment_posts
     SET post_date = post_date - $1::INT
     WHERE profile_id = $2 AND post_date = $3::DATE AND slot = $4
     RETURNING post_date::TEXT`,
    [days, PROFILE_ID, POST_DATE, SLOT],
  );
  return result.rows[0].post_date;
}

/** 讓生圖租約逾時，不動 image_attempts／token，模擬 worker 中途死掉。 */
async function expireImageLease(db: PGlite): Promise<void> {
  await db.query(
    `UPDATE public.practice_moment_posts
     SET image_reserved_at = now() - interval '10 minutes'
     WHERE profile_id = $1 AND post_date = $2::DATE AND slot = $3`,
    [PROFILE_ID, POST_DATE, SLOT],
  );
}

async function readRow(db: PGlite): Promise<ImageRow> {
  const result = await db.query<ImageRow>(
    `SELECT status, attempts, body, image_status, image_path,
            image_attempts, image_token
     FROM public.practice_moment_posts
     WHERE profile_id = $1 AND post_date = $2::DATE AND slot = $3`,
    [PROFILE_ID, POST_DATE, SLOT],
  );
  return result.rows[0];
}

async function readRowAt(db: PGlite, postDate: string): Promise<ImageRow> {
  const result = await db.query<ImageRow>(
    `SELECT status, attempts, body, image_status, image_path,
            image_attempts, image_token
     FROM public.practice_moment_posts
     WHERE profile_id = $1 AND post_date = $2::DATE AND slot = $3`,
    [PROFILE_ID, postDate, SLOT],
  );
  return result.rows[0];
}

async function readImageUsage(
  db: PGlite,
): Promise<{ minute_count: number; day_count: number } | null> {
  const result = await db.query<{ minute_count: number; day_count: number }>(
    `SELECT minute_count, day_count
     FROM public.model_call_rate_limits
     WHERE user_id = $1::UUID AND scope = 'practice_moment_image'`,
    [USER_ID],
  );
  return result.rows[0] ?? null;
}

// ---------------------------------------------------------------------------
// 煙霧：疊加套用與預設值
// ---------------------------------------------------------------------------

Deno.test("PostgreSQL image migration applies on top of 0822/0824 and defaults to none", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db);
    const row = await readRow(db);
    assertEquals(row.image_status, "none");
    assertEquals(row.image_path, null);
    assertEquals(row.image_attempts, 0);
    assertEquals(row.image_token, null);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL commit keeps working with the legacy 7-argument call shape", async () => {
  const db = await createDatabase();
  try {
    await db.query(
      `SELECT claimed FROM public.reserve_practice_moment_slot(
         $1, $2::DATE, $3, $4, $5, $6, $7::UUID, 6, 60, FALSE
       )`,
      [PROFILE_ID, POST_DATE, SLOT, DAY_PART, THEME_ID, "t-legacy", USER_ID],
    );
    // 既部署的 Edge 不帶 p_wants_image；DEFAULT FALSE 必須讓行為與舊版全同。
    const committed = await db.query<{ committed: boolean }>(
      `SELECT committed FROM public.commit_practice_moment_post(
         $1, $2::DATE, $3, $4, $5, $6, $7
       )`,
      [PROFILE_ID, POST_DATE, SLOT, "t-legacy", BODY, null, "deepseek-v4-flash"],
    );
    assertEquals(committed.rows[0].committed, true);
    assertEquals((await readRow(db)).image_status, "none");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL commit with wants_image marks the row pending", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    const row = await readRow(db);
    assertEquals(row.status, "ready");
    assertEquals(row.image_status, "pending");
    assertEquals(row.image_attempts, 0, "pending 由 commit 建立，attempts 從 0 起算");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL commit rejects wants_image together with an image_id", async () => {
  const db = await createDatabase();
  try {
    await db.query(
      `SELECT claimed FROM public.reserve_practice_moment_slot(
         $1, $2::DATE, $3, $4, $5, $6, $7::UUID, 6, 60, FALSE
       )`,
      [PROFILE_ID, POST_DATE, SLOT, DAY_PART, THEME_ID, "t-both", USER_ID],
    );
    let denied = "";
    try {
      await db.query(
        `SELECT committed FROM public.commit_practice_moment_post(
           $1, $2::DATE, $3, $4, $5, $6, $7, TRUE
         )`,
        [PROFILE_ID, POST_DATE, SLOT, "t-both", BODY, "moment_coffee_cup", null],
      );
    } catch (error) {
      denied = String(error);
    }
    assert(
      denied.includes("p_wants_image excludes p_image_id"),
      `生成圖與 catalog 圖互斥必須擋在 DB，實際：${denied}`,
    );
  } finally {
    await db.close();
  }
});

// ---------------------------------------------------------------------------
// claim 的六態轉移表：一格一條
// ---------------------------------------------------------------------------

// 第 1 格：列不存在／文字還沒 ready。
Deno.test("PostgreSQL image claim refuses a missing row and an unready post", async () => {
  const db = await createDatabase();
  try {
    assertEquals((await claimImage(db, "t-missing")).claimed, false);

    // reserved（文字生成中）也要拒絕：圖永遠跟在文字後面。
    await db.query(
      `SELECT claimed FROM public.reserve_practice_moment_slot(
         $1, $2::DATE, $3, $4, $5, $6, $7::UUID, 6, 60, FALSE
       )`,
      [PROFILE_ID, POST_DATE, SLOT, DAY_PART, THEME_ID, "t-text", USER_ID],
    );
    assertEquals((await claimImage(db, "t-early")).claimed, false);
    assertEquals(await readImageUsage(db), null, "被拒絕的認領不得計 usage");
  } finally {
    await db.close();
  }
});

// 第 2 格：image_status 不是 pending。
Deno.test("PostgreSQL image claim refuses a text-only post", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: false });
    const refused = await claimImage(db, "t-none");
    assertEquals(refused.claimed, false);
    assertEquals(refused.body, null, "拒絕分支不得外洩 body");
    assertEquals((await readRow(db)).image_attempts, 0);
  } finally {
    await db.close();
  }
});

// 第 4 格（放行）＋坑 #1：首次認領就計數。
Deno.test("PostgreSQL image claim leases a pending job and counts the first attempt", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    const claim = await claimImage(db, "t-first");
    assertEquals(claim.claimed, true);
    assertEquals(claim.token, "t-first");
    assertEquals(
      claim.attempt_count,
      1,
      "首次認領就必須計入一次生圖呼叫，否則每 slot 實際跑 3 次而不是 2 次",
    );
    assertEquals(claim.body, BODY, "claim 要回 body 供 prompt 使用");
    assertEquals(claim.theme_id, THEME_ID);

    const row = await readRow(db);
    assertEquals(row.image_status, "pending");
    assertEquals(row.image_attempts, 1);
    assertEquals(row.image_token, "t-first");
    assertEquals(await readImageUsage(db), { minute_count: 1, day_count: 1 });
  } finally {
    await db.close();
  }
});

// 第 3 格：租約仍有效。
Deno.test("PostgreSQL image claim refuses while another lease is active", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-a")).claimed, true);

    const second = await claimImage(db, "t-b");
    assertEquals(second.claimed, false);
    const row = await readRow(db);
    assertEquals(row.image_attempts, 1, "被拒絕的認領不得消耗 image_attempts");
    assertEquals(row.image_token, "t-a");
  } finally {
    await db.close();
  }
});

// 坑 #2：release 後 token IS NULL 是獨立放行分支，不必等租約逾時。
Deno.test("PostgreSQL image release hands the lease back immediately", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-fail")).claimed, true);
    assertEquals(await releaseImage(db, "t-fail"), true);

    const row = await readRow(db);
    assertEquals(row.image_status, "pending", "attempts 未燒完前 release 留在 pending");
    assertEquals(row.image_token, null);

    const retry = await claimImage(db, "t-retry");
    assertEquals(retry.claimed, true, "release 後不必等租約逾時就能接手");
    assertEquals(retry.attempt_count, 2);
  } finally {
    await db.close();
  }
});

// 租約逾時接手（worker 蒸發的自癒路徑）。
Deno.test("PostgreSQL image claim takes over an expired lease", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-dead")).claimed, true);
    await expireImageLease(db);

    const takeover = await claimImage(db, "t-live");
    assertEquals(takeover.claimed, true);
    assertEquals(takeover.attempt_count, 2);
    assertEquals((await readRow(db)).image_token, "t-live");
  } finally {
    await db.close();
  }
});

// 第 5 格：attempts 燒完 → failed 終態。
Deno.test("PostgreSQL image job fails terminally after exhausting attempts", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    for (let attempt = 1; attempt <= MAX_MOMENT_IMAGE_ATTEMPTS; attempt++) {
      const claim = await claimImage(db, `t-${attempt}`);
      assertEquals(claim.claimed, true);
      assertEquals(claim.attempt_count, attempt);
      assertEquals(await releaseImage(db, `t-${attempt}`), true);
    }
    // 最後一次 release 已把 attempts==max 的列轉 failed。
    const afterRelease = await readRow(db);
    assertEquals(afterRelease.image_status, "failed");
    assertEquals(afterRelease.image_token, null);

    const refused = await claimImage(db, "t-late");
    assertEquals(refused.claimed, false, "failed 是終態，永不再生");
    assertEquals(
      (await readRow(db)).image_attempts,
      MAX_MOMENT_IMAGE_ATTEMPTS,
      "拒絕不得消耗 attempts",
    );
    // 文字面完全不受影響（兩組計數獨立）。
    assertEquals(afterRelease.status, "ready");
    assertEquals(afterRelease.body, BODY);
    assertEquals(afterRelease.attempts, 1);
  } finally {
    await db.close();
  }
});

// 第 5 格的另一條進路：租約逾時且 attempts 已達上限 → claim 自己收屍轉 failed。
Deno.test("PostgreSQL image claim flips an exhausted expired lease to failed", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    for (let attempt = 1; attempt <= MAX_MOMENT_IMAGE_ATTEMPTS; attempt++) {
      assertEquals((await claimImage(db, `t-${attempt}`)).claimed, true);
      if (attempt < MAX_MOMENT_IMAGE_ATTEMPTS) {
        assertEquals(await releaseImage(db, `t-${attempt}`), true);
      }
    }
    // 最後一個 worker 沒 release 就蒸發。
    await expireImageLease(db);
    const refused = await claimImage(db, "t-after-death");
    assertEquals(refused.claimed, false);
    assertEquals((await readRow(db)).image_status, "failed");
  } finally {
    await db.close();
  }
});

// ---------------------------------------------------------------------------
// commit 的 token fencing 與限流 rollback
// ---------------------------------------------------------------------------

Deno.test("PostgreSQL image commit is token fenced and idempotent", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-mine")).claimed, true);

    assertEquals(await commitImage(db, "t-stale"), false, "舊 token 不得覆寫");
    assertEquals((await readRow(db)).image_path, null);

    assertEquals(await commitImage(db, "t-mine"), true);
    const row = await readRow(db);
    assertEquals(row.image_status, "ready");
    assertEquals(row.image_path, IMAGE_PATH);
    assertEquals(row.image_token, null);

    assertEquals(await commitImage(db, "t-mine"), false, "重複回應回 FALSE 不覆寫");
    assertEquals((await claimImage(db, "t-again")).claimed, false, "ready 不再認領");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL image rate-limit rejection rolls back the whole claim", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    await db.query(
      `INSERT INTO public.model_call_rate_limits(
         user_id, scope, minute_window_start, minute_count,
         day_window_start, day_count
       ) VALUES ($1::UUID, 'practice_moment_image', now(), 3, now(), 3)`,
      [USER_ID],
    );

    let denied = "";
    try {
      await claimImage(db, "t-over-limit");
    } catch (error) {
      denied = String(error);
    }
    assert(
      denied.includes("MODEL_RATE_LIMITED_MINUTE"),
      `應由同一筆 transaction 擋下限流，實際：${denied}`,
    );
    const row = await readRow(db);
    assertEquals(row.image_attempts, 0, "限流 RAISE 必須連 attempts 一起 rollback");
    assertEquals(row.image_token, null);
    assertEquals(row.image_status, "pending");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL test-account image claim bypasses user usage but still counts attempts", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    const claim = await claimImage(db, "t-test-account", {
      countUserUsage: false,
    });
    assertEquals(claim.claimed, true);
    assertEquals((await readRow(db)).image_attempts, 1);
    assertEquals(await readImageUsage(db), null);
  } finally {
    await db.close();
  }
});

// ---------------------------------------------------------------------------
// list 的新欄位與清掃流程
// ---------------------------------------------------------------------------

Deno.test("PostgreSQL list exposes image_status and image_path", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-l")).claimed, true);
    assertEquals(await commitImage(db, "t-l"), true);

    const listed = await db.query<{
      image_status: string;
      image_path: string | null;
      image_id: string | null;
    }>(
      `SELECT image_status, image_path, image_id
       FROM public.list_practice_moment_posts($1::TEXT[], $2::DATE)`,
      [[PROFILE_ID], POST_DATE],
    );
    assertEquals(listed.rows.length, 1);
    assertEquals(listed.rows[0], {
      image_status: "ready",
      image_path: IMAGE_PATH,
      image_id: null,
    });
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL expiry sweep lists, marks, and never deletes", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-e")).claimed, true);
    assertEquals(await commitImage(db, "t-e"), true);

    // 窗內：不列。
    const fresh = await db.query<{ image_path: string }>(
      `SELECT image_path
       FROM public.list_expired_practice_moment_images($1::DATE, 20)`,
      [POST_DATE],
    );
    assertEquals(fresh.rows.length, 0, "post_date < p_before 才算出窗");

    // 出窗：列出 → 標記 → 再列為空；列與 path 都還在。
    const dayAfter = taipeiToday(1);
    const expired = await db.query<{ image_path: string }>(
      `SELECT image_path
       FROM public.list_expired_practice_moment_images($1::DATE, 20)`,
      [dayAfter],
    );
    assertEquals(expired.rows.map((r) => r.image_path), [IMAGE_PATH]);

    const marked = await db.query<{ marked_count: number }>(
      `SELECT marked_count
       FROM public.mark_practice_moment_images_expired($1::DATE, $2::TEXT[])`,
      [dayAfter, [IMAGE_PATH]],
    );
    assertEquals(marked.rows[0].marked_count, 1);

    const after = await db.query<{ image_path: string }>(
      `SELECT image_path
       FROM public.list_expired_practice_moment_images($1::DATE, 20)`,
      [dayAfter],
    );
    assertEquals(after.rows.length, 0);

    const row = await readRow(db);
    assertEquals(row.image_status, "expired");
    assertEquals(row.image_path, IMAGE_PATH, "expired 保留 path 作審計與冪等重刪");
    assertEquals(row.status, "ready", "清掃絕不動文字面");
    assertEquals(row.body, BODY);

    // 重複標記冪等：ready 條件擋掉已 expired 的列。
    const again = await db.query<{ marked_count: number }>(
      `SELECT marked_count
       FROM public.mark_practice_moment_images_expired($1::DATE, $2::TEXT[])`,
      [dayAfter, [IMAGE_PATH]],
    );
    assertEquals(again.rows[0].marked_count, 0);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL expiry mark refuses to touch in-window rows", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-w")).claimed, true);
    assertEquals(await commitImage(db, "t-w"), true);

    // 呼叫端傳錯 p_before（窗內日期）也刪不到窗內的圖——第二道保險。
    const marked = await db.query<{ marked_count: number }>(
      `SELECT marked_count
       FROM public.mark_practice_moment_images_expired($1::DATE, $2::TEXT[])`,
      [POST_DATE, [IMAGE_PATH]],
    );
    assertEquals(marked.rows[0].marked_count, 0);
    assertEquals((await readRow(db)).image_status, "ready");
  } finally {
    await db.close();
  }
});

// ---------------------------------------------------------------------------
// 權限與租約常數
// ---------------------------------------------------------------------------

Deno.test("PostgreSQL image RPCs are service_role only and definer mode", async () => {
  const db = await createDatabase();
  try {
    const signatures = [
      "public.commit_practice_moment_post(text,date,integer,text,text,text,text,boolean)",
      "public.list_practice_moment_posts(text[],date)",
      "public.claim_practice_moment_image(text,date,integer,text,text,uuid,integer,integer,boolean,integer,integer)",
      "public.commit_practice_moment_image(text,date,integer,text,text)",
      "public.release_practice_moment_image(text,date,integer,text,integer)",
      "public.list_expired_practice_moment_images(date,integer)",
      "public.mark_practice_moment_images_expired(date,text[])",
      "public.list_practice_moment_image_orphans(integer,integer)",
      "public.clear_practice_moment_image_orphans(text[])",
    ];
    for (const signature of signatures) {
      const security = await db.query<{
        security_definer: boolean;
        anon_execute: boolean;
        authenticated_execute: boolean;
        service_execute: boolean;
      }>(
        `SELECT
           p.prosecdef AS security_definer,
           has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
           has_function_privilege('authenticated', p.oid, 'EXECUTE')
             AS authenticated_execute,
           has_function_privilege('service_role', p.oid, 'EXECUTE')
             AS service_execute
         FROM pg_proc AS p
         WHERE p.oid = to_regprocedure($1)`,
        [signature],
      );
      assertEquals(
        security.rows[0],
        {
          security_definer: true,
          anon_execute: false,
          authenticated_execute: false,
          service_execute: true,
        },
        `權限樣板漂移：${signature}`,
      );
    }

    // 舊 7-arg commit_post 必須已被移除（overload 衛生）。
    const legacy = await db.query<{ legacy_commit: string | null }>(`
      SELECT to_regprocedure(
        'public.commit_practice_moment_post(text,date,integer,text,text,text,text)'
      )::TEXT AS legacy_commit
    `);
    assertEquals(legacy.rows[0].legacy_commit, null);

    // 舊 10-arg claim（沒有帳本參數的那一支）同樣必須消失。
    const legacyClaim = await db.query<{ legacy_claim: string | null }>(`
      SELECT to_regprocedure(
        'public.claim_practice_moment_image(text,date,integer,text,uuid,integer,integer,boolean,integer,integer)'
      )::TEXT AS legacy_claim
    `);
    assertEquals(legacyClaim.rows[0].legacy_claim, null);
    const claimOverloads = await db.query<{ count: number }>(`
      SELECT count(*)::INT AS count
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'claim_practice_moment_image'
    `);
    assertEquals(claimOverloads.rows[0].count, 1, "overload 衛生：只准留一支");
  } finally {
    await db.close();
  }
});

// ---------------------------------------------------------------------------
// 清理競態圍籬（複審 blocking item 3）：出窗列在資料層凍結
// ---------------------------------------------------------------------------

Deno.test("PostgreSQL expired rows can never be claimed again (production call chain)", async () => {
  const db = await createDatabase();
  try {
    // 走正式鏈把一列做成 ready-with-image，再把 post_date 位移到窗外
    // （等價於時間流逝）；cutoff 由 DB 以當下 now() 判定，呼叫端無從注入。
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-x")).claimed, true);
    assertEquals(await commitImage(db, "t-x"), true);
    const expiredDate = await shiftRowPostDate(db, 20);

    const refused = await claimImage(db, "t-late", { postDate: expiredDate });
    assertEquals(refused.claimed, false);
    const row = await readRowAt(db, expiredDate);
    assertEquals(row.image_status, "ready", "拒絕不得改動 ready 列");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL expired pending rows are finalized as failed on claim", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    const expiredDate = await shiftRowPostDate(db, 20);
    const refused = await claimImage(db, "t-late", { postDate: expiredDate });
    assertEquals(refused.claimed, false);
    const row = await readRowAt(db, expiredDate);
    assertEquals(
      row.image_status,
      "failed",
      "出窗的 pending 永遠等不到生成，順手收成終態",
    );
    assertEquals(row.image_attempts, 0, "收屍不得消耗 attempts");
    assertEquals(await readImageUsage(db), null, "收屍不得計 usage");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL sweep window: nothing can mutate an expired ready row except mark", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-s")).claimed, true);
    assertEquals(await commitImage(db, "t-s"), true);
    const expiredDate = await shiftRowPostDate(db, 20);
    const markBefore = taipeiToday(1);

    // 模擬 sweep 已 list、尚未 mark 的窗口：所有寫入嘗試都必須無效——
    // claim 被出窗守衛擋、commit/release 因 token 早已清空而 fenced。
    assertEquals(
      (await claimImage(db, "t-race", { postDate: expiredDate })).claimed,
      false,
    );
    assertEquals(
      await commitImage(db, "t-race", "hack/path.jpeg", expiredDate),
      false,
    );
    const releaseRefused = await db.query<{ released: boolean }>(
      `SELECT released FROM public.release_practice_moment_image(
         $1, $2::DATE, $3, $4
       )`,
      [PROFILE_ID, expiredDate, SLOT, "t-race"],
    );
    assertEquals(releaseRefused.rows[0].released, false);
    const before = await readRowAt(db, expiredDate);
    assertEquals(before.image_status, "ready");
    assertEquals(before.image_path, IMAGE_PATH, "path 不得被任何人改動");

    // mark 是唯一的合法寫入者；之後同列永遠凍在 expired。
    const marked = await db.query<{ marked_count: number }>(
      `SELECT marked_count
       FROM public.mark_practice_moment_images_expired($1::DATE, $2::TEXT[])`,
      [markBefore, [IMAGE_PATH]],
    );
    assertEquals(marked.rows[0].marked_count, 1);
    assertEquals(
      (await claimImage(db, "t-after", { postDate: expiredDate })).claimed,
      false,
    );
    assertEquals((await readRowAt(db, expiredDate)).image_status, "expired");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL full interleaving: claimed pending crosses Taipei midnight, late commit refused and row finalized", async () => {
  const db = await createDatabase();
  try {
    // 1. 窗內認領——完全走 production 呼叫鏈（reserve → commit(wants) →
    //    claim），worker 拿到有效 token。
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-slow")).claimed, true);

    // 2. 時間流逝跨過台北午夜、該列出窗（post_date 位移等價變換；cutoff
    //    由 DB 以當下 now() 判定，呼叫端沒有任何日期參數可撒謊）。
    const expiredDate = await shiftRowPostDate(db, 20);

    // 3. 晚到的 commit **即使 token 有效**也被拒，且列被就地收屍——
    //    出窗列不會再被 feed 接手，不收就永遠掛在 pending。
    assertEquals(
      await commitImage(db, "t-slow", IMAGE_PATH, expiredDate),
      false,
      "晚到 commit 必須被出窗守衛擋下",
    );
    const afterLate = await readRowAt(db, expiredDate);
    assertEquals(afterLate.image_status, "failed", "晚到 commit 被拒時列一併收屍");
    assertEquals(afterLate.image_path, null);
    assertEquals(afterLate.image_token, null, "token 必須清空");
    assertEquals(afterLate.status, "ready", "文字面不受影響");

    // 4. sweep 永遠看不到這一列（從未 image-ready、無 DB 引用物件）；
    //    worker 自己上傳的 token 路徑物件由 Edge 自刪＋出窗 prefix 孤兒
    //    對帳兜底（moments_image_gen／moments_image_sweep 單元測試覆蓋）。
    const listed = await db.query<{ image_path: string }>(
      `SELECT image_path
       FROM public.list_expired_practice_moment_images($1::DATE, 20)`,
      [taipeiToday(1)],
    );
    assertEquals(listed.rows.length, 0);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL release after crossing the cutoff finalizes the row as failed", async () => {
  const db = await createDatabase();
  try {
    // 窗內認領後時間流逝跨過午夜（post_date 位移等價變換），worker 的
    // fal 呼叫失敗走 release——出窗列必須收成 failed，不得放回 pending
    //（feed 不再列出窗列，pending 等於永久擱淺）。
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-cross")).claimed, true);
    const expiredDate = await shiftRowPostDate(db, 20);

    const released = await db.query<{ released: boolean }>(
      `SELECT released FROM public.release_practice_moment_image(
         $1, $2::DATE, $3, $4
       )`,
      [PROFILE_ID, expiredDate, SLOT, "t-cross"],
    );
    assertEquals(released.rows[0].released, true);
    const row = await readRowAt(db, expiredDate);
    assertEquals(row.image_status, "failed", "出窗的 release 必須收成終態");
    assertEquals(row.image_token, null);
    assertEquals(row.image_attempts, 1, "release 絕不回收 attempts");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL image lease default matches the TS constant", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    assertEquals((await claimImage(db, "t-lease")).claimed, true);
    // 把 reserved_at 撥到「差一秒就逾時」：租約必須仍有效。
    await db.query(
      `UPDATE public.practice_moment_posts
       SET image_reserved_at = now() - make_interval(secs => $1)
       WHERE profile_id = $2 AND post_date = $3::DATE AND slot = $4`,
      [MOMENT_IMAGE_RESERVE_LEASE_MS / 1000 - 1, PROFILE_ID, POST_DATE, SLOT],
    );
    assertEquals(
      (await claimImage(db, "t-early-bird")).claimed,
      false,
      "租約未逾時不得接手",
    );
    // 過線後可接手。
    await db.query(
      `UPDATE public.practice_moment_posts
       SET image_reserved_at = now() - make_interval(secs => $1)
       WHERE profile_id = $2 AND post_date = $3::DATE AND slot = $4`,
      [MOMENT_IMAGE_RESERVE_LEASE_MS / 1000 + 1, PROFILE_ID, POST_DATE, SLOT],
    );
    assertEquals((await claimImage(db, "t-on-time")).claimed, true);
  } finally {
    await db.close();
  }
});

// ---------------------------------------------------------------------------
// 孤兒帳本（第四輪複審 P2-2）：可持久重試的閉環
// ---------------------------------------------------------------------------

Deno.test("PostgreSQL claim records the object key in the same transaction", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    assertEquals(await orphanLedger(db), [], "還沒認領就不該有紀錄");
    const claim = await claimImage(db, "tok-1");
    assertEquals(claim.claimed, true);
    assertEquals(
      await orphanLedger(db),
      [tokenPath("tok-1")],
      "租約成立的同一筆交易就要記下這個路徑",
    );
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL successful commit clears exactly its own ledger entry", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    await claimImage(db, "tok-1");
    assertEquals(await commitImage(db, "tok-1", tokenPath("tok-1")), true);
    assertEquals(await orphanLedger(db), [], "被引用的物件不得留在帳本");
    assertEquals(await listOrphans(db), []);
    const row = await readRow(db);
    assertEquals(row.image_status, "ready");
    assertEquals(row.image_path, tokenPath("tok-1"));
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL retry keeps the failed attempt's key and only clears the committed one", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    // 第一次認領後失敗 release（物件可能已經上傳，路徑必須留在帳本）。
    await claimImage(db, "tok-1");
    assertEquals(await releaseImage(db, "tok-1"), true);
    // 第二次認領：帳本累積兩條。
    await claimImage(db, "tok-2");
    assertEquals(await orphanLedger(db), [
      tokenPath("tok-1"),
      tokenPath("tok-2"),
    ]);
    assertEquals(await commitImage(db, "tok-2", tokenPath("tok-2")), true);
    assertEquals(
      await orphanLedger(db),
      [tokenPath("tok-1")],
      "第一次的孤兒不得被第二次的成功一起抹掉",
    );
    assertEquals(await listOrphans(db), [tokenPath("tok-1")]);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL orphan listing respects the grace period", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    await claimImage(db, "tok-1");
    assertEquals(
      await listOrphans(db, 600),
      [],
      "寬限期內的紀錄不得列出——那個 job 可能還在跑",
    );
    assertEquals(await listOrphans(db, 0), [tokenPath("tok-1")]);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL orphan listing never lists a referenced image_path", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    await claimImage(db, "tok-1");
    await commitImage(db, "tok-1", tokenPath("tok-1"));
    // 縱深防禦：就算有 bug 把已被引用的路徑塞回帳本，清算也不得列出它。
    await db.query(
      `UPDATE public.practice_moment_posts
          SET image_orphan_paths = ARRAY[image_path]
        WHERE profile_id = $1 AND slot = $2`,
      [PROFILE_ID, SLOT],
    );
    assertEquals(await orphanLedger(db), [tokenPath("tok-1")]);
    assertEquals(
      await listOrphans(db, 0),
      [],
      "ready 列指著的物件永遠不得被清算刪掉",
    );
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL clear removes only the given keys and no lifecycle column", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    await claimImage(db, "tok-1");
    await releaseImage(db, "tok-1");
    await claimImage(db, "tok-2");
    const before = await readRow(db);
    const cleared = await db.query<{ cleared_count: number }>(
      `SELECT cleared_count FROM public.clear_practice_moment_image_orphans($1)`,
      [[tokenPath("tok-1")]],
    );
    assertEquals(cleared.rows[0].cleared_count, 1);
    assertEquals(await orphanLedger(db), [tokenPath("tok-2")]);
    const after = await readRow(db);
    assertEquals(after.image_status, before.image_status);
    assertEquals(after.image_attempts, before.image_attempts);
    assertEquals(after.image_token, before.image_token);
    assertEquals(after.body, before.body);
    assertEquals(after.status, before.status);
    // 清不存在的路徑是 no-op（清算重試冪等）。
    const again = await db.query<{ cleared_count: number }>(
      `SELECT cleared_count FROM public.clear_practice_moment_image_orphans($1)`,
      [[tokenPath("tok-1")]],
    );
    assertEquals(again.rows[0].cleared_count, 0);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL a rolled-back claim leaves no ledger entry", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    // 限流：整筆交易 rollback，帳本不得留下這一筆。
    let raised = false;
    try {
      await claimImage(db, "tok-1", { minuteLimit: 0 });
    } catch {
      raised = true;
    }
    assert(raised, "limit 0 必須 RAISE");
    assertEquals(await orphanLedger(db), []);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL a refused claim (out of window) records nothing", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    await shiftRowPostDate(db, 20);
    const claim = await claimImage(db, "tok-1", {
      postDate: EXPIRED_POST_DATE,
      imagePath: tokenPath("tok-1", EXPIRED_POST_DATE),
    });
    assertEquals(claim.claimed, false);
    assertEquals(await orphanLedger(db), [], "沒認領就不記帳");
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL ledger input guards", async () => {
  const db = await createDatabase();
  try {
    await seedPost(db, { wantsImage: true });
    // claim 的路徑守門與 commit 同一道。
    for (const bad of ["", "x".repeat(201)]) {
      let raised = false;
      try {
        await claimImage(db, "tok-1", { imagePath: bad });
      } catch {
        raised = true;
      }
      assert(raised, `invalid p_image_path 必須 RAISE：${bad.length} 字`);
    }
    // clear 不接受空陣列（避免呼叫端傳錯掃到整表）。
    let clearRaised = false;
    try {
      await db.query(
        `SELECT cleared_count FROM public.clear_practice_moment_image_orphans($1)`,
        [[]],
      );
    } catch {
      clearRaised = true;
    }
    assert(clearRaised, "空 p_paths 必須 RAISE");
    // list 的上限守門。
    let listRaised = false;
    try {
      await db.query(
        `SELECT orphan_path FROM public.list_practice_moment_image_orphans($1, $2)`,
        [101, 0],
      );
    } catch {
      listRaised = true;
    }
    assert(listRaised, "p_limit 超過硬上界必須 RAISE");
  } finally {
    await db.close();
  }
});

import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260729000000_refine_free_allowance.sql",
    import.meta.url,
  ),
);

/// The last migration to define the function is the one Postgres is running.
const liveFunctionSource = (() => {
  const migrationsDir = new URL("../../migrations/", import.meta.url);
  const names = [...Deno.readDirSync(migrationsDir)]
    .filter((entry) => entry.isFile && entry.name.endsWith(".sql"))
    .map((entry) => entry.name)
    .sort();
  let definition: string | null = null;
  for (const name of names) {
    const source = Deno.readTextFileSync(new URL(name, migrationsDir));
    if (source.includes("FUNCTION public.consume_refine_free_allowance")) {
      definition = source;
    }
  }
  if (definition === null) {
    throw new Error("no migration defines consume_refine_free_allowance");
  }
  return definition;
})();

Deno.test("refine allowance migration owns a single-row-per-user counter", () => {
  assert(
    migrationSource.includes(
      "CREATE TABLE IF NOT EXISTS public.refine_free_allowance",
    ),
  );
  assert(migrationSource.includes("user_id    UUID        NOT NULL PRIMARY KEY"));
  assert(migrationSource.includes("REFERENCES auth.users(id) ON DELETE CASCADE"));
  assert(migrationSource.includes("CHECK (used_count >= 0)"));
  assert(migrationSource.includes("ENABLE ROW LEVEL SECURITY"));
});

Deno.test("allowance table is unreachable from client roles", () => {
  assert(
    migrationSource.includes(
      "REVOKE ALL ON TABLE public.refine_free_allowance FROM anon, authenticated",
    ),
  );
  assert(
    migrationSource.includes(
      "GRANT SELECT ON TABLE public.refine_free_allowance TO service_role",
    ),
  );
  // A counter the client can write is a counter the client can reset.
  assert(
    !/GRANT\s+(ALL|INSERT|UPDATE|DELETE)[^;]*refine_free_allowance[^;]*(anon|authenticated)/i
      .test(migrationSource),
  );
});

Deno.test("the live allowance function still locks the row it increments", () => {
  // Without FOR UPDATE two concurrent requests both read the same used_count
  // and both take the last free slot. Verified locally: the lock-free variant
  // granted 10 of 10 racers a single remaining slot; this one granted 1 of 20.
  //
  // Match the statement, not the words: an earlier version of this assertion
  // searched for "FOR UPDATE" anywhere and stayed green when the lock was
  // deleted, because the comment above it still said "FOR UPDATE".
  assert(
    /SELECT\s+used_count,\s*day_utc\s+INTO[\s\S]{0,200}?WHERE\s+user_id\s*=\s*p_user_id\s+FOR UPDATE;/
      .test(liveFunctionSource),
  );
  assert(liveFunctionSource.includes("SECURITY DEFINER"));
  assert(liveFunctionSource.includes("SET search_path = public"));
});

Deno.test("the live allowance function stays callable by the Edge Function", () => {
  // REVOKE ... FROM PUBLIC also strips service_role's implicit EXECUTE, so the
  // explicit grant is what keeps analyze-chat able to call this at all.
  assert(
    liveFunctionSource.includes(
      "GRANT EXECUTE ON FUNCTION\n  public.consume_refine_free_allowance(UUID, INTEGER, UUID)\n  TO service_role",
    ),
  );
  assert(
    liveFunctionSource.includes(
      "REVOKE EXECUTE ON FUNCTION\n  public.consume_refine_free_allowance(UUID, INTEGER, UUID)\n  FROM anon, authenticated",
    ),
  );
});

Deno.test("the daily limit stays a parameter, not a stored value", () => {
  // The product must be able to change 10 -> 20 by editing an Edge constant.
  // A limit column here would make every change a production migration.
  assert(liveFunctionSource.includes("p_daily_limit INTEGER"));
  assert(!/\blimit_count\b|\bdaily_limit\s+INTEGER\s+NOT NULL/.test(
    migrationSource,
  ));
});

Deno.test("exhausting the allowance refuses rather than raising", () => {
  // granted:false is a normal outcome that flips the caller to charging one
  // message. If this ever became an exception, running out of free refinements
  // would surface to the user as a failed request instead of a paid one.
  assert(liveFunctionSource.includes("'granted', false"));
  assert(liveFunctionSource.includes("'granted', true"));
});

Deno.test("the day window is UTC, matching every other daily counter", () => {
  assert(liveFunctionSource.includes("(now() AT TIME ZONE 'utc')::date"));
});

Deno.test("同一 requestId 的免費授權是冪等的", () => {
  // 併發的同 requestId 重試會兩邊都通過 replay preflight（ledger 還沒寫），
  // 兩邊都打模型、兩邊都呼叫這支函式。ledger 只結算一次，免費計數卻會被扣
  // 兩次——這張表就是補上那把缺席的鑰匙。
  assert(
    migrationSource.includes(
      "CREATE TABLE IF NOT EXISTS public.refine_free_claims",
    ),
  );
  assert(migrationSource.includes("PRIMARY KEY (user_id, request_id)"));
  // 沒有 DEFAULT：可為 NULL 的冪等鍵等於留一條完全沒有去重的靜默路徑，
  // 而這支函式從未部署過，沒有舊呼叫端需要體恤。
  assert(liveFunctionSource.includes("p_request_id  UUID\n) RETURNS JSONB"));
  assert(!liveFunctionSource.includes("p_request_id  UUID DEFAULT"));
  assert(
    liveFunctionSource.includes(
      "RAISE EXCEPTION 'consume_refine_free_allowance: p_request_id is required'",
    ),
  );

  // 順序是這條的全部：必須先拿到 allowance 的 row lock，重複的 requestId 才
  // 會在鎖上等到前一筆 claim 已經 commit。反過來寫兩邊都會查到「沒有 claim」。
  const lock = liveFunctionSource.indexOf(
    "WHERE user_id = p_user_id\n  FOR UPDATE;",
  );
  const claimLookup = liveFunctionSource.indexOf(
    "SELECT granted INTO v_claimed",
  );
  assert(lock >= 0, "allowance row lock missing");
  assert(claimLookup > lock, "claim lookup must happen under the row lock");

  // 已結算的判決原樣回傳，不得再動計數。
  assert(liveFunctionSource.includes("'granted', v_claimed"));
});

Deno.test("claims 表同樣對 client 角色完全關閉", () => {
  assert(
    migrationSource.includes(
      "REVOKE ALL ON TABLE public.refine_free_claims FROM anon, authenticated",
    ),
  );
  assert(
    !/GRANT\s+(ALL|INSERT|UPDATE|DELETE)[^;]*refine_free_claims[^;]*(anon|authenticated)/i
      .test(migrationSource),
  );
});

Deno.test("日界要在拿到鎖之後才判定", () => {
  // 23:59:59 進來的呼叫可能在鎖上等到跨日。若沿用進入函式時算的日期，它會
  // 把贏家已經滾好的 day_utc 當成「不對」，把計數滾回昨天並歸零——等於白送
  // 一整輪十次。拿到鎖之後再讀一次時鐘就沒有這個窗。
  const lock = liveFunctionSource.indexOf(
    "WHERE user_id = p_user_id\n  FOR UPDATE;",
  );
  const reread = liveFunctionSource.indexOf(
    "v_today := (clock_timestamp() AT TIME ZONE 'utc')::date;",
  );
  const rollover = liveFunctionSource.indexOf("IF v_day <> v_today THEN");
  assert(lock >= 0);
  assert(reread > lock, "day must be re-derived after the row lock");
  assert(rollover > reread, "rollover check must use the re-derived day");

  // 必須是 clock_timestamp()，不能是 now()。now() 就是 transaction_timestamp()，
  // 整個交易期間凍結，在鎖上等再久都回同一個瞬間——用它「重讀」等於沒讀。
  // 本機實測：等鎖 3 秒後 now() 差 0 秒、clock_timestamp() 差 3 秒。
  assert(
    !liveFunctionSource.includes("v_today := (now() AT TIME ZONE 'utc')::date;"),
    "now() is frozen per transaction; re-deriving with it is a no-op",
  );
});

Deno.test("先鎖父列再鎖子列，避免與刪帳號互相卡死", () => {
  // 刪帳號是先鎖 auth.users 再 cascade 到子表。函式若先鎖子列、稍後插入
  // claim 才因 FK 去要父列，兩邊順序相反就會 40P01 死鎖，打死微調或打死
  // 帳號刪除。FOR KEY SHARE 是能擋住刪除的最弱鎖。
  const parentLock = liveFunctionSource.indexOf(
    "PERFORM 1 FROM auth.users WHERE id = p_user_id FOR KEY SHARE;",
  );
  const childLock = liveFunctionSource.indexOf(
    "WHERE user_id = p_user_id\n  FOR UPDATE;",
  );
  assert(parentLock >= 0, "parent FK lock missing");
  assert(childLock > parentLock, "parent must be locked before the child row");
});

Deno.test("建外鍵不得無限等待 auth.users 的寫入鎖", () => {
  // 建 FK 會在 auth.users 上拿 SHARE ROW EXCLUSIVE，與一般寫入衝突且等待
  // 無上限；一旦排進佇列，後續登入/註冊會全部塞在它後面。寧可快速失敗改時間重跑。
  assert(migrationSource.includes("SET lock_timeout = '5s';"));
  const timeout = migrationSource.indexOf("SET lock_timeout");
  const firstFk = migrationSource.indexOf("REFERENCES auth.users(id)");
  assert(timeout >= 0 && firstFk > timeout, "lock_timeout must precede the FK");
});

Deno.test("claims 有排程清理，不只靠使用者自己再來一次", () => {
  // 函式內的清理只掃呼叫者自己。用過幾次就流失的帳號，那批列永遠不會被清，
  // 「保留 7 天」就成了沒人執行的承諾。照本專案既有 replay 表的做法排 pg_cron。
  assert(
    migrationSource.includes(
      "CREATE OR REPLACE FUNCTION public.cleanup_expired_refine_free_claims()",
    ),
  );
  assert(migrationSource.includes("CREATE EXTENSION IF NOT EXISTS pg_cron;"));
  assert(migrationSource.includes("'cleanup-expired-refine-free-claims',"));
});

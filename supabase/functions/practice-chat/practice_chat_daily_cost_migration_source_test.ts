// 成本保險絲 migration 的原始碼契約測試（Phase 5 WP2）。
//
// PGlite 測試證明「累加行為對」，這一支證明「權限樣板與隱私鐵則沒有被漏寫」
// ——那些東西在單機 PGlite 裡驗不出來（沒有 Supabase 的角色與 PostgREST），
// 但漏掉任何一條，正式環境就會出現 anon 直連 RPC 或 schema cache 不更新。
// 範式沿用 moments_migration_source_test.ts。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260905120000_practice_chat_daily_cost.sql",
    import.meta.url,
  ),
);

/** 去掉行註解，讓「不得出現」類斷言不會被說明文字誤判。 */
function withoutComments(sql: string): string {
  return sql
    .split("\n")
    .map((line) => {
      const marker = line.indexOf("--");
      return marker >= 0 ? line.slice(0, marker) : line;
    })
    .join("\n");
}

const executable = withoutComments(migration);

Deno.test("保險絲 migration 建出 day 主鍵、非負累計與 updated_at", () => {
  assert(
    executable.includes(
      "CREATE TABLE IF NOT EXISTS public.practice_chat_daily_cost",
    ),
  );
  assert(executable.includes("day        DATE        PRIMARY KEY"));
  assert(executable.includes("CHECK (spent_usd >= 0)"));
  assert(executable.includes("updated_at TIMESTAMPTZ NOT NULL DEFAULT now()"));
});

Deno.test("保險絲表是 service_role only、無 policy", () => {
  assert(
    executable.includes(
      "ALTER TABLE public.practice_chat_daily_cost ENABLE ROW LEVEL SECURITY",
    ),
  );
  assert(
    !executable.includes("CREATE POLICY"),
    "無 policy 才等於預設拒絕；加 policy 會讓 anon 讀到全站花費",
  );
});

Deno.test("保險絲表不得出現任何使用者關聯欄位（只存一個全站數字）", () => {
  for (
    const forbidden of [
      "user_id",
      "session_id",
      "profile_id",
      "email",
      "turns",
      "reply",
    ]
  ) {
    assert(
      !new RegExp(`\\b${forbidden}\\b`).test(executable),
      `migration 不得出現使用者關聯欄位或概念：${forbidden}`,
    );
  }
});

Deno.test("累加 RPC 收尾是 service-role only ＋ SECURITY DEFINER", () => {
  const start = executable.indexOf(
    "CREATE OR REPLACE FUNCTION public.increment_practice_chat_daily_cost(",
  );
  assert(start >= 0, "migration 必須宣告累加 RPC");
  const end = executable.indexOf("\n$$;\n", start);
  assert(end > start, "RPC 必須以 $$; 收尾");
  const body = executable.slice(start, end);

  assert(
    body.includes("SECURITY INVOKER"),
    "建立當下不得先暴露 SECURITY DEFINER 給預設 PUBLIC EXECUTE",
  );
  assert(body.includes("SET search_path = public"));
  assert(body.includes("RETURNS NUMERIC"), "必須回傳累加後的值");
  // 「這一次剛好跨過門檻」要靠回傳值算，不能靠先讀再寫。
  assert(body.includes("ON CONFLICT (day) DO UPDATE"));
  assert(body.includes("SET spent_usd  = c.spent_usd + EXCLUDED.spent_usd"));
  assert(body.includes("RETURNING c.spent_usd INTO v_total"));

  for (
    const grant of [
      "REVOKE ALL ON FUNCTION public.increment_practice_chat_daily_cost(\n  DATE, NUMERIC\n) FROM PUBLIC;",
      "REVOKE ALL ON FUNCTION public.increment_practice_chat_daily_cost(\n  DATE, NUMERIC\n) FROM anon, authenticated;",
      "GRANT EXECUTE ON FUNCTION public.increment_practice_chat_daily_cost(\n  DATE, NUMERIC\n) TO service_role;",
      "ALTER FUNCTION public.increment_practice_chat_daily_cost(\n  DATE, NUMERIC\n) SECURITY DEFINER;",
    ]
  ) {
    assert(executable.includes(grant), `migration 缺少：${grant}`);
  }
});

Deno.test("保險絲 migration 是純加法：不得有 DROP／DELETE／ALTER TABLE ... DROP", () => {
  for (const destructive of ["DROP TABLE", "DROP COLUMN", "DELETE FROM"]) {
    assert(
      !executable.includes(destructive),
      `純加法 migration 不得含 ${destructive}`,
    );
  }
});

Deno.test("migration 結尾要求 PostgREST 重載 schema cache", () => {
  assertEquals(
    executable.trim().endsWith("NOTIFY pgrst, 'reload schema';"),
    true,
  );
});

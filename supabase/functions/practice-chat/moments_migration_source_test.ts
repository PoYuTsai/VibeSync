// 練習室模擬社群動態（PR A）migration 的原始碼契約測試。
//
// PGlite 測試證明「行為對」，這一支證明「權限樣板與鐵則沒有被漏寫」——
// 那些東西在單機 PGlite 裡驗不出來（沒有 Supabase 的角色與 PostgREST），
// 但漏掉任何一條，正式環境就會出現 client 直連 RPC 或 schema cache 不更新。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
// MAX_MOMENT_ATTEMPTS 是全站每日模型呼叫上限的 DB 側分母：每個
// (profile_id, post_date) 最多 2 slot × 3 attempts。全站每日 600 還需要 Edge
// 額外保證 profile_id 只來自 100 位角色的 allowlist、post_date 是正確台北日
// （複審 P2-1）——那半邊的契約測試在 moments_edge_contract_test.ts。
// PR B 起這裡直接 import TS 常數，不再留字面值；SQL↔TS 的雙向比對在
// moments_constants_test.ts。
import { MAX_MOMENT_ATTEMPTS } from "./moments_constants.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260822120000_practice_moment_posts.sql",
    import.meta.url,
  ),
);
const usageGateUpgrade = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824063344_practice_moment_reserve_usage_gate.sql",
    import.meta.url,
  ),
);

const RPC_NAMES = [
  "reserve_practice_moment_slot",
  "commit_practice_moment_post",
  "release_practice_moment_slot",
  "list_practice_moment_posts",
] as const;

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

/** 取單一函式的定義區塊（CREATE ... 到它自己的 $$; 為止）。 */
function functionBodyFrom(sql: string, name: string): string {
  const start = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert(start >= 0, `Migration must declare public.${name}`);
  const end = sql.indexOf("\n$$;\n", start);
  assert(end > start, `public.${name} must be terminated with $$;`);
  return sql.slice(start, end + "\n$$;\n".length);
}

function functionBody(name: string): string {
  return functionBodyFrom(migration, name);
}

Deno.test("moment migration creates the posts table with the cost ceiling and no-canned guards", () => {
  assert(
    executable.includes(
      "CREATE TABLE IF NOT EXISTS public.practice_moment_posts",
    ),
  );
  assert(executable.includes("PRIMARY KEY (profile_id, post_date, slot)"));
  assert(executable.includes("CHECK (slot BETWEEN 0 AND 1)"));
  assert(
    executable.includes("CHECK (status IN ('reserved', 'ready', 'exhausted'))"),
  );
  // 成本上限的 schema 強制點；上界必須與 MAX_MOMENT_ATTEMPTS 相同。
  assert(
    executable.includes(
      `CHECK (attempts BETWEEN 0 AND ${MAX_MOMENT_ATTEMPTS})`,
    ),
    `attempts 的 CHECK 上界必須是 ${MAX_MOMENT_ATTEMPTS}`,
  );
  assert(
    executable.includes(
      "CHECK (body IS NULL OR char_length(body) BETWEEN 1 AND 220)",
    ),
  );
  // ready 一定有真的內容：no-canned 鐵則的資料層版本。
  assert(executable.includes("CONSTRAINT practice_moment_ready_has_body"));
  assert(
    executable.includes(
      "CHECK (status <> 'ready' OR (body IS NOT NULL AND char_length(btrim(body)) > 0))",
    ),
  );
});

Deno.test("moment posts table is service_role only and has no policy", () => {
  assert(
    executable.includes(
      "ALTER TABLE public.practice_moment_posts ENABLE ROW LEVEL SECURITY",
    ),
  );
  assert(
    !executable.includes("CREATE POLICY"),
    "無 policy 才等於預設拒絕；加 policy 會讓 anon/authenticated 讀到全域貼文",
  );
  assert(
    executable.includes(
      "CREATE INDEX IF NOT EXISTS practice_moment_posts_date_idx",
    ),
  );
});

Deno.test("moment migration keeps every post global and free of user-derived columns", () => {
  // 隱私鐵則：貼文是全域的，資料層不得有任何使用者關聯欄位。
  for (
    const forbidden of [
      "user_id",
      "session_id",
      "relationship_thread",
      "memory",
      "hint",
      "debrief",
      "turns",
    ]
  ) {
    assert(
      !new RegExp(`\\b${forbidden}\\b`).test(executable),
      `migration 不得出現使用者關聯欄位或概念：${forbidden}`,
    );
  }
});

Deno.test("moment RPCs all end service-role-only and SECURITY DEFINER", () => {
  for (const name of RPC_NAMES) {
    const body = functionBody(name);
    if (name === "reserve_practice_moment_slot") {
      assert(
        body.includes("SECURITY INVOKER"),
        "reserve 建立當下不得先暴露 SECURITY DEFINER 給預設 PUBLIC EXECUTE",
      );
    } else {
      assert(
        body.includes("SECURITY DEFINER"),
        `${name} 必須是 SECURITY DEFINER`,
      );
    }
    assert(
      body.includes("SET search_path = public"),
      `${name} 必須釘死 search_path`,
    );

    const grants = executable.slice(
      executable.indexOf(
        "REVOKE ALL ON FUNCTION public.reserve_practice_moment_slot",
      ),
    );
    assert(
      grants.includes(`REVOKE ALL ON FUNCTION public.${name}(`),
      `${name} 必須 REVOKE`,
    );
    assert(
      grants.includes(`GRANT EXECUTE ON FUNCTION public.${name}(`),
      `${name} 必須只 GRANT 給 service_role`,
    );
  }

  const revokeFromPublic =
    executable.match(/REVOKE ALL ON FUNCTION[\s\S]*?FROM PUBLIC;/g) ?? [];
  assertEquals(revokeFromPublic.length, RPC_NAMES.length);
  const revokeFromClients = executable.match(
    /REVOKE ALL ON FUNCTION[\s\S]*?FROM anon, authenticated;/g,
  ) ?? [];
  assertEquals(revokeFromClients.length, RPC_NAMES.length);
  const grantsToServiceRole =
    executable.match(/GRANT EXECUTE ON FUNCTION[\s\S]*?TO service_role;/g) ??
      [];
  assertEquals(grantsToServiceRole.length, RPC_NAMES.length);

  assert(
    !/GRANT[\s\S]*?TO (anon|authenticated|PUBLIC)/.test(executable),
    "任何 RPC 都不得授權給 anon/authenticated/PUBLIC",
  );

  const reserveGrant = executable.indexOf(
    "GRANT EXECUTE ON FUNCTION public.reserve_practice_moment_slot",
  );
  const reserveDefiner = executable.indexOf(
    "ALTER FUNCTION public.reserve_practice_moment_slot",
    reserveGrant,
  );
  assert(reserveGrant >= 0 && reserveDefiner > reserveGrant);
  assert(
    executable.slice(reserveDefiner).startsWith(
      "ALTER FUNCTION public.reserve_practice_moment_slot",
    ),
  );
  assert(
    executable.slice(reserveDefiner).includes(") SECURITY DEFINER;"),
    "reserve 只能在 service-role ACL 完成後升成 SECURITY DEFINER",
  );
});

Deno.test("moment migration reloads the PostgREST schema cache last", () => {
  assertEquals(
    executable.trimEnd().endsWith("NOTIFY pgrst, 'reload schema';"),
    true,
    "檔尾必須 NOTIFY pgrst，否則新 RPC 在 PostgREST 的 schema cache 內不存在",
  );
});

Deno.test("corrective migration upgrades the already-recorded production reserve signature", () => {
  const normalized = withoutComments(usageGateUpgrade).replace(/\s+/g, " ");
  const guardIndex = normalized.indexOf("DO $$");
  const dropIndex = normalized.indexOf(
    "DROP FUNCTION IF EXISTS public.reserve_practice_moment_slot",
  );
  assert(
    guardIndex >= 0 && dropIndex > guardIndex,
    "catalog overload guard 必須在任何 DROP 前執行",
  );
  const canonicalReserve = withoutComments(
    functionBody("reserve_practice_moment_slot"),
  ).replace(/\s+/g, " ").trim();
  const upgradedReserve = withoutComments(
    functionBodyFrom(usageGateUpgrade, "reserve_practice_moment_slot"),
  ).replace(/\s+/g, " ").trim();
  assertEquals(
    upgradedReserve,
    canonicalReserve,
    "fresh install 與 production corrective migration 的 reserve 邏輯不得漂移",
  );
  assert(
    normalized.includes(
      "DROP FUNCTION IF EXISTS public.reserve_practice_moment_slot( TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER );",
    ),
    "production 已套過的 8-arg overload 必須由新 migration version 明確移除",
  );
  assert(
    normalized.includes(
      "CREATE OR REPLACE FUNCTION public.reserve_practice_moment_slot( p_profile_id TEXT, p_post_date DATE, p_slot INTEGER, p_day_part TEXT, p_theme_id TEXT, p_generation_token TEXT, p_user_id UUID, p_minute_limit INTEGER, p_daily_limit INTEGER, p_count_user_usage BOOLEAN,",
    ),
  );
  assert(
    normalized.includes(
      "RAISE EXCEPTION 'reserve_practice_moment_slot: unexpected overload(s): %', v_unexpected;",
    ),
    "未知 production overload 必須在 DROP 前 fail closed",
  );
  assert(
    normalized.includes(
      "PERFORM public.increment_model_usage( p_user_id, 'practice_moment', p_minute_limit, p_daily_limit );",
    ),
  );
  assert(
    normalized.includes(
      "REVOKE ALL ON FUNCTION public.reserve_practice_moment_slot( TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER ) FROM PUBLIC;",
    ),
  );
  assert(
    normalized.includes(
      "GRANT EXECUTE ON FUNCTION public.reserve_practice_moment_slot( TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER ) TO service_role;",
    ),
  );
  const grantIndex = normalized.indexOf(
    "GRANT EXECUTE ON FUNCTION public.reserve_practice_moment_slot",
  );
  const definerIndex = normalized.indexOf(
    "ALTER FUNCTION public.reserve_practice_moment_slot",
  );
  assert(
    grantIndex >= 0 && definerIndex > grantIndex,
    "必須先鎖 ACL，再切 SECURITY DEFINER",
  );
  assertEquals(
    normalized.trimEnd().endsWith("NOTIFY pgrst, 'reload schema';"),
    true,
  );
});

Deno.test("reserve anchors the two review-flagged pitfalls in SQL", () => {
  const body = functionBody("reserve_practice_moment_slot");

  // 坑 #1：首次 INSERT 明寫 attempts = 1，不能靠 DEFAULT 0。
  assert(
    body.includes("'reserved', 1, p_generation_token"),
    "首次 INSERT 必須明寫 attempts = 1，否則每 slot 會跑 4 次而不是 3 次",
  );
  assert(body.includes("ON CONFLICT (profile_id, post_date, slot) DO NOTHING"));
  assert(body.includes("FOR UPDATE"));

  // 坑 #2：租約拒絕分支必須同時看 token 非 NULL；token IS NULL 是獨立放行路徑。
  assert(
    body.includes("v_row.generation_token IS NOT NULL") &&
      body.includes(
        "AND v_row.reserved_at > now() - make_interval(secs => p_lease_seconds)",
      ),
    "租約拒絕分支必須是「token 非 NULL 且租約未逾時」，否則 release 會被自己的 reserved_at 擋住",
  );

  // 上限判定使用同一個常數。
  assert(
    body.includes(`p_max_attempts     INTEGER DEFAULT ${MAX_MOMENT_ATTEMPTS}`),
  );
  assert(body.includes("IF v_row.attempts >= p_max_attempts THEN"));
  assert(body.includes("SET status = 'exhausted'"));

  // 使用者限流與 slot attempts 必須是同一筆 transaction。只有兩個真正會
  // claimed=true 的分支能計數；ready／exhausted／fresh lease 都不能先扣額度。
  assertEquals(
    [...body.matchAll(/PERFORM public\.increment_model_usage\(/g)].length,
    2,
  );
  const firstClaimAt = body.indexOf("IF v_inserted = 1 THEN");
  const firstUsageAt = body.indexOf(
    "PERFORM public.increment_model_usage(",
    firstClaimAt,
  );
  const firstReturnAt = body.indexOf("RETURN NEXT;", firstClaimAt);
  assert(
    firstClaimAt < firstUsageAt && firstUsageAt < firstReturnAt,
    "首次 claimed 分支必須先在同一 transaction 計 usage 才能放行",
  );
  const takeoverAt = body.indexOf("-- 第 5 格：接手");
  const takeoverUsageAt = body.indexOf(
    "PERFORM public.increment_model_usage(",
    takeoverAt,
  );
  const takeoverUpdateAt = body.indexOf(
    "UPDATE public.practice_moment_posts AS mp",
    takeoverAt,
  );
  assert(
    takeoverAt < takeoverUsageAt && takeoverUsageAt < takeoverUpdateAt,
    "接手分支必須把 usage 與 attempts 更新包在同一 transaction",
  );
});

Deno.test("release never deletes a row, never writes a body, never refunds attempts", () => {
  const body = functionBody("release_practice_moment_slot");

  assert(
    !executable.includes("DELETE FROM"),
    "整份 migration 不得有任何刪除路徑：attempts 是成本計數，刪列等於無限重試",
  );
  assert(!body.includes("body ="), "release 絕不寫 body（no-canned）");
  assert(!body.includes("attempts ="), "release 絕不回收 attempts");
  assert(
    body.includes("v_row.generation_token IS DISTINCT FROM p_generation_token"),
  );
  assert(body.includes("generation_token = NULL"));
  assert(
    body.includes(`p_max_attempts     INTEGER DEFAULT ${MAX_MOMENT_ATTEMPTS}`),
  );
});

Deno.test("commit is token fenced and clears the token", () => {
  const body = functionBody("commit_practice_moment_post");

  assert(body.includes("FOR UPDATE"));
  assert(body.includes("v_row.status <> 'reserved'"));
  assert(body.includes("v_row.generation_token IS NULL"));
  assert(
    body.includes("v_row.generation_token IS DISTINCT FROM p_generation_token"),
  );
  assert(body.includes("SET status = 'ready'"));
  assert(
    body.includes("generation_token = NULL"),
    "commit 後要清 token，遲到的 worker 才不能再寫一次",
  );
});

Deno.test("list only ever returns ready posts", () => {
  const body = functionBody("list_practice_moment_posts");

  assert(
    body.includes("AND mp.status = 'ready'"),
    "reserved／exhausted 不得外流",
  );
  assert(body.includes("mp.post_date >= p_since"));
  assert(body.includes("mp.profile_id = ANY (p_profile_ids)"));
  assert(body.includes("STABLE"), "唯讀 RPC 標成 STABLE");
});

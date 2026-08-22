// 練習室模擬社群動態（PR A）migration 的原始碼契約測試。
//
// PGlite 測試證明「行為對」，這一支證明「權限樣板與鐵則沒有被漏寫」——
// 那些東西在單機 PGlite 裡驗不出來（沒有 Supabase 的角色與 PostgREST），
// 但漏掉任何一條，正式環境就會出現 client 直連 RPC 或 schema cache 不更新。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260822120000_practice_moment_posts.sql",
    import.meta.url,
  ),
);

/**
 * 與 migration 內 CHECK (attempts BETWEEN 0 AND 3) 的上界一致，也是全站每日
 * 模型呼叫上限（100 角色 × 2 slot × 3 attempts = 600）的分母。
 *
 * TODO(PR B)：PR B 會在 TS 側引入 MAX_MOMENT_ATTEMPTS；那時要把這裡改成
 * 直接 import 該常數做雙向比對，而不是留一份字面值。
 */
const MAX_MOMENT_ATTEMPTS = 3;

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
function functionBody(name: string): string {
  const start = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert(start >= 0, `Migration must declare public.${name}`);
  const end = migration.indexOf("\n$$;\n", start);
  assert(end > start, `public.${name} must be terminated with $$;`);
  return migration.slice(start, end + "\n$$;\n".length);
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
  for (const forbidden of [
    "user_id",
    "session_id",
    "relationship_thread",
    "memory",
    "hint",
    "debrief",
    "turns",
  ]) {
    assert(
      !new RegExp(`\\b${forbidden}\\b`).test(executable),
      `migration 不得出現使用者關聯欄位或概念：${forbidden}`,
    );
  }
});

Deno.test("moment RPCs all carry the SECURITY DEFINER and grant template", () => {
  for (const name of RPC_NAMES) {
    const body = functionBody(name);
    assert(body.includes("SECURITY DEFINER"), `${name} 必須是 SECURITY DEFINER`);
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
  const revokeFromClients =
    executable.match(/REVOKE ALL ON FUNCTION[\s\S]*?FROM anon, authenticated;/g) ?? [];
  assertEquals(revokeFromClients.length, RPC_NAMES.length);
  const grantsToServiceRole =
    executable.match(/GRANT EXECUTE ON FUNCTION[\s\S]*?TO service_role;/g) ?? [];
  assertEquals(grantsToServiceRole.length, RPC_NAMES.length);

  assert(
    !/GRANT[\s\S]*?TO (anon|authenticated|PUBLIC)/.test(executable),
    "任何 RPC 都不得授權給 anon/authenticated/PUBLIC",
  );
});

Deno.test("moment migration reloads the PostgREST schema cache last", () => {
  assertEquals(
    executable.trimEnd().endsWith("NOTIFY pgrst, 'reload schema';"),
    true,
    "檔尾必須 NOTIFY pgrst，否則新 RPC 在 PostgREST 的 schema cache 內不存在",
  );
});

Deno.test("reserve anchors the two review-flagged pitfalls in SQL", () => {
  const body = functionBody("reserve_practice_moment_slot");

  // 坑 #1：首次 INSERT 明寫 attempts = 1，不能靠 DEFAULT 0。
  assert(
    body.includes("'reserved', 1, p_generation_token"),
    "首次 INSERT 必須明寫 attempts = 1，否則每 slot 會跑 4 次、每日上限變 800",
  );
  assert(body.includes("ON CONFLICT (profile_id, post_date, slot) DO NOTHING"));
  assert(body.includes("FOR UPDATE"));

  // 坑 #2：租約拒絕分支必須同時看 token 非 NULL；token IS NULL 是獨立放行路徑。
  assert(
    body.includes("v_row.generation_token IS NOT NULL") &&
      body.includes("AND v_row.reserved_at > now() - make_interval(secs => p_lease_seconds)"),
    "租約拒絕分支必須是「token 非 NULL 且租約未逾時」，否則 release 會被自己的 reserved_at 擋住",
  );

  // 上限判定使用同一個常數。
  assert(
    body.includes(`p_max_attempts     INTEGER DEFAULT ${MAX_MOMENT_ATTEMPTS}`),
  );
  assert(body.includes("IF v_row.attempts >= p_max_attempts THEN"));
  assert(body.includes("SET status = 'exhausted'"));
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

  assert(body.includes("AND mp.status = 'ready'"), "reserved／exhausted 不得外流");
  assert(body.includes("mp.post_date >= p_since"));
  assert(body.includes("mp.profile_id = ANY (p_profile_ids)"));
  assert(body.includes("STABLE"), "唯讀 RPC 標成 STABLE");
});

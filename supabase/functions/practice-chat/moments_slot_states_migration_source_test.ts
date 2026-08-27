// 動態牆 freshness 保底的唯讀 slot-state RPC 原始碼契約。
// 真正的狀態行為另由 moments_migration_postgres_test.ts 以 PGlite 驗證。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260827080000_practice_moment_slot_states.sql",
    import.meta.url,
  ),
);

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
const signature = String
  .raw`public\.list_practice_moment_slot_states\(\s*TEXT\[\]\s*,\s*DATE\s*,\s*INTEGER\s*,\s*INTEGER\s*\)`;

Deno.test("slot-state migration 建立受限的唯讀 RPC", () => {
  assert(
    executable.includes(
      "CREATE OR REPLACE FUNCTION public.list_practice_moment_slot_states(",
    ),
  );
  assert(executable.includes("RETURNS TABLE("));
  assert(/claimable\s+BOOLEAN/.test(executable));
  assert(executable.includes("LANGUAGE plpgsql"));
  assert(executable.includes("STABLE"));
  assert(executable.includes("SECURITY INVOKER"));
  assert(executable.includes("SET search_path = public"));
});

Deno.test("slot-state RPC 驗證批次、日期、attempts 與 lease 參數", () => {
  assert(executable.includes("array_length(p_profile_ids, 1) > 100"));
  assert(executable.includes("p_post_date IS NULL"));
  assert(executable.includes("p_max_attempts <= 0"));
  assert(executable.includes("p_max_attempts > 3"));
  assert(executable.includes("p_lease_seconds <= 0"));
});

Deno.test("slot-state claimable 與 reserve 的三個拒絕條件一致", () => {
  assert(executable.includes("mp.status = 'reserved'"));
  assert(executable.includes("mp.attempts < p_max_attempts"));
  assert(executable.includes("mp.generation_token IS NULL"));
  assert(executable.includes("mp.reserved_at <= now() -"));
  assert(executable.includes("make_interval(secs => p_lease_seconds)"));
  assert(executable.includes("mp.profile_id = ANY (p_profile_ids)"));
  assert(executable.includes("mp.post_date = p_post_date"));
});

Deno.test("slot-state RPC 最終只授權 service_role", () => {
  assert(
    new RegExp(`REVOKE ALL ON FUNCTION\\s+${signature}\\s+FROM PUBLIC`).test(
      executable,
    ),
  );
  assert(
    new RegExp(
      `REVOKE ALL ON FUNCTION\\s+${signature}\\s+FROM anon, authenticated`,
    ).test(executable),
  );
  assert(
    new RegExp(
      `GRANT EXECUTE ON FUNCTION\\s+${signature}\\s+TO service_role`,
    ).test(executable),
  );
  assert(
    new RegExp(`ALTER FUNCTION\\s+${signature}\\s+SECURITY DEFINER`).test(
      executable,
    ),
  );

  const grants = executable.match(/GRANT EXECUTE ON FUNCTION/g) ?? [];
  assertEquals(grants.length, 1);
  assertEquals(
    /GRANT[\s\S]*?TO (anon|authenticated|PUBLIC)/.test(executable),
    false,
  );
});

Deno.test("slot-state migration 最後要求 PostgREST 重載 schema cache", () => {
  assert(executable.includes("NOTIFY pgrst, 'reload schema';"));
});

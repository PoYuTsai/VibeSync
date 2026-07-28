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
      "GRANT EXECUTE ON FUNCTION public.consume_refine_free_allowance(UUID, INTEGER)\n  TO service_role",
    ),
  );
  assert(
    liveFunctionSource.includes(
      "REVOKE EXECUTE ON FUNCTION public.consume_refine_free_allowance(UUID, INTEGER)\n  FROM anon, authenticated",
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

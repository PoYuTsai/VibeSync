// 練習室模擬社群動態：生成配圖 migration（PR-2）的原始碼契約測試。
//
// PGlite 測試證明「行為對」，這一支證明「權限樣板與鐵則沒有被漏寫」，
// 並做 SQL↔TS 常數的雙向比對（範式各沿用 moments_migration_source_test.ts
// 與 moments_constants_test.ts）。任何一邊漂移都會紅。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  MAX_MOMENT_IMAGE_ATTEMPTS,
  MOMENT_IMAGE_PATH_DB_MAX_CHARS,
  MOMENT_IMAGE_RESERVE_LEASE_MS,
  MOMENT_IMAGE_SWEEP_LIMIT,
  MOMENT_RESERVE_LEASE_MS,
} from "./moments_constants.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260825120000_practice_moment_images.sql",
    import.meta.url,
  ),
);
const guardMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260825150000_practice_moment_image_expiry_guards.sql",
    import.meta.url,
  ),
);

/** 本檔新建或改簽名的每一支 RPC。 */
const RPC_NAMES = [
  "commit_practice_moment_post",
  "list_practice_moment_posts",
  "claim_practice_moment_image",
  "commit_practice_moment_image",
  "release_practice_moment_image",
  "list_expired_practice_moment_images",
  "mark_practice_moment_images_expired",
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

/** 從 migration 原文剖出唯一一處符合 pattern 的數字；找不到或矛盾就紅。 */
function soleNumberFromSql(pattern: RegExp, label: string): number {
  const matches = [...migration.matchAll(pattern)];
  assert(matches.length > 0, `migration 內找不到 ${label}`);
  const values = new Set(matches.map((m) => Number(m[1])));
  assertEquals(
    values.size,
    1,
    `${label} 在 migration 內有互相矛盾的值：${[...values].join(", ")}`,
  );
  return [...values][0];
}

// ---------------------------------------------------------------------------
// 權限樣板：每支 RPC 都必須 REVOKE PUBLIC/anon/authenticated、只 GRANT
// service_role，且以 SECURITY INVOKER 建立後由 ALTER 轉 DEFINER
// （statement-by-statement runner 下 CREATE 當下不得已是 DEFINER）。
// ---------------------------------------------------------------------------

Deno.test("每支 RPC 的權限樣板完整", () => {
  for (const name of RPC_NAMES) {
    for (
      const [label, snippet] of [
        ["REVOKE PUBLIC", `REVOKE ALL ON FUNCTION public.${name}(`],
        ["GRANT service_role", `GRANT EXECUTE ON FUNCTION public.${name}(`],
        ["ALTER SECURITY DEFINER", `ALTER FUNCTION public.${name}(`],
      ] as const
    ) {
      assert(
        executable.includes(snippet),
        `${name} 缺 ${label} 樣板`,
      );
    }
    assert(
      executable.includes(`FROM anon, authenticated`),
      `${name} 的 REVOKE 必須含 anon, authenticated`,
    );
  }
  const definerAtCreate = [...executable.matchAll(/SECURITY DEFINER/g)].length;
  const alterCount = [...executable.matchAll(/ALTER FUNCTION public\.\w+\(/g)]
    .length;
  assertEquals(
    definerAtCreate,
    alterCount,
    "SECURITY DEFINER 只允許出現在 ALTER（CREATE 一律 INVOKER 起手）",
  );
});

Deno.test("schema cache 重載通知存在", () => {
  assert(executable.includes(`NOTIFY pgrst, 'reload schema';`));
});

// ---------------------------------------------------------------------------
// 鐵則：本 migration 沒有任何列刪除路徑；overload 稽核 fail-closed；
// bucket 區塊必須有 storage schema 守門（PGlite 直接 exec 本檔）。
// ---------------------------------------------------------------------------

Deno.test("絕無列刪除與整表破壞", () => {
  assert(!executable.includes("DELETE FROM"), "本 migration 不得刪任何列（D6）");
  assert(!executable.includes("DROP TABLE"));
  assert(!executable.includes("TRUNCATE"));
});

Deno.test("改簽名的兩支 RPC 都有 fail-closed overload 稽核", () => {
  for (const name of ["commit_practice_moment_post", "list_practice_moment_posts"]) {
    assert(
      migration.includes(`'${name}: unexpected overload(s): %'`) ||
        migration.includes(`'${name}: unexpected overload(s): %',`),
      `${name} 缺 overload 稽核`,
    );
  }
  assert(
    executable.includes(
      "DROP FUNCTION IF EXISTS public.commit_practice_moment_post(\n  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, TEXT\n)",
    ),
    "舊 7-arg commit 必須被移除",
  );
});

Deno.test("Storage bucket 區塊有 schema 存在守門", () => {
  assert(
    executable.includes("information_schema.tables") &&
      executable.includes("table_schema = 'storage'"),
    "bucket 建立必須包在 storage schema 檢查內，PGlite 測試環境才是 no-op",
  );
  assert(executable.includes("'practice-moment-images'"));
  assert(
    executable.includes("ON CONFLICT (id) DO NOTHING"),
    "bucket 建立必須冪等",
  );
});

Deno.test("狀態機的關鍵寫入都在", () => {
  // wants_image 的唯一效果是 pending；生成圖與 catalog 圖互斥。
  assert(
    executable.includes(
      "image_status = CASE WHEN p_wants_image THEN 'pending' ELSE 'none' END",
    ),
  );
  assert(
    migration.includes("p_wants_image excludes p_image_id"),
  );
  // ready 一定有 path 的資料層守門。
  assert(
    executable.includes("CHECK (image_status <> 'ready' OR image_path IS NOT NULL)"),
  );
  // claim 的同交易 per-user 計數走獨立 scope。
  assert(
    executable.includes("'practice_moment_image'"),
    "claim 必須以 practice_moment_image scope 計數",
  );
  // 清掃絕不動文字面：mark 只寫 image_* 欄位。
  const markStart = executable.indexOf(
    "CREATE OR REPLACE FUNCTION public.mark_practice_moment_images_expired(",
  );
  const markEnd = executable.indexOf("$$;", markStart);
  const markBody = executable.slice(markStart, markEnd);
  for (const forbidden of ["SET status", "body =", "image_attempts ="]) {
    assert(
      !markBody.includes(forbidden),
      `mark 不得寫文字面或計數欄位：${forbidden}`,
    );
  }
});

// ---------------------------------------------------------------------------
// SQL ↔ TS：雙向數字比對
// ---------------------------------------------------------------------------

Deno.test("SQL 的 image_attempts 上界等於 MAX_MOMENT_IMAGE_ATTEMPTS", () => {
  assertEquals(
    soleNumberFromSql(
      /CHECK \(image_attempts BETWEEN 0 AND (\d+)\)/g,
      "CHECK (image_attempts BETWEEN 0 AND N)",
    ),
    MAX_MOMENT_IMAGE_ATTEMPTS,
  );
  assertEquals(
    soleNumberFromSql(
      /p_max_attempts\s+INTEGER DEFAULT (\d+)/g,
      "p_max_attempts DEFAULT",
    ),
    MAX_MOMENT_IMAGE_ATTEMPTS,
  );
  assertEquals(
    soleNumberFromSql(
      /p_max_attempts > (\d+) THEN/g,
      "p_max_attempts 上界防呆",
    ),
    MAX_MOMENT_IMAGE_ATTEMPTS,
  );
});

Deno.test("SQL 的生圖租約秒數等於 MOMENT_IMAGE_RESERVE_LEASE_MS", () => {
  assertEquals(
    soleNumberFromSql(
      /p_lease_seconds\s+INTEGER DEFAULT (\d+)/g,
      "p_lease_seconds DEFAULT",
    ),
    MOMENT_IMAGE_RESERVE_LEASE_MS / 1000,
  );
  assert(
    MOMENT_IMAGE_RESERVE_LEASE_MS > MOMENT_RESERVE_LEASE_MS,
    "生圖租約必須長於文字租約：生圖含外部 API 呼叫加下載上傳，總預算更大",
  );
});

Deno.test("SQL 的 image_path 長度上界等於 MOMENT_IMAGE_PATH_DB_MAX_CHARS", () => {
  assertEquals(
    soleNumberFromSql(
      /char_length\(image_path\) BETWEEN 1 AND (\d+)/g,
      "image_path 欄位 CHECK",
    ),
    MOMENT_IMAGE_PATH_DB_MAX_CHARS,
  );
  assertEquals(
    soleNumberFromSql(
      /char_length\(p_image_path\) > (\d+) THEN/g,
      "commit image 的 path 長度防呆",
    ),
    MOMENT_IMAGE_PATH_DB_MAX_CHARS,
  );
});

Deno.test("清掃上限：Edge 常數 ≤ SQL 硬上界", () => {
  const sqlCap = soleNumberFromSql(
    /p_limit > (\d+) THEN/g,
    "list_expired 的 p_limit 上界",
  );
  assert(
    MOMENT_IMAGE_SWEEP_LIMIT <= sqlCap,
    `Edge 掃描批量 ${MOMENT_IMAGE_SWEEP_LIMIT} 不得超過 SQL 上界 ${sqlCap}`,
  );
  assertEquals(
    soleNumberFromSql(/array_length\(p_paths, 1\) > (\d+) THEN/g, "p_paths 上限"),
    sqlCap,
    "list 與 mark 的批量上界必須一致",
  );
});

Deno.test("每個有 SQL 對應物的 TS 常數都能在 migration 內找到", () => {
  for (
    const [label, snippet] of [
      [
        "image attempts CHECK",
        `CHECK (image_attempts BETWEEN 0 AND ${MAX_MOMENT_IMAGE_ATTEMPTS})`,
      ],
      [
        "image lease default",
        `p_lease_seconds    INTEGER DEFAULT ${MOMENT_IMAGE_RESERVE_LEASE_MS / 1000}`,
      ],
      [
        "image path CHECK",
        `char_length(image_path) BETWEEN 1 AND ${MOMENT_IMAGE_PATH_DB_MAX_CHARS}`,
      ],
    ] as const
  ) {
    assert(
      migration.includes(snippet),
      `${label} 在 migration 內找不到：${snippet}`,
    );
  }
});

// ---------------------------------------------------------------------------
// 出窗守衛 migration（20260825150000）：樣板與圍籬字面
// ---------------------------------------------------------------------------

const executableGuard = withoutComments(guardMigration);

Deno.test("guard migration：權限樣板、overload 稽核與 NOTIFY 齊全", () => {
  for (
    const snippet of [
      "REVOKE ALL ON FUNCTION public.claim_practice_moment_image(",
      "GRANT EXECUTE ON FUNCTION public.claim_practice_moment_image(",
      "ALTER FUNCTION public.claim_practice_moment_image(",
      "NOTIFY pgrst, 'reload schema';",
    ] as const
  ) {
    assert(executableGuard.includes(snippet), `guard migration 缺：${snippet}`);
  }
  assert(
    guardMigration.includes("claim_practice_moment_image: unexpected overload(s): %"),
    "缺 fail-closed overload 稽核",
  );
  assert(
    executableGuard.includes(
      "DROP FUNCTION IF EXISTS public.claim_practice_moment_image(\n  TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER\n)".replace(/\\n/g, "\n"),
    ),
    "舊 10-arg claim 必須被移除",
  );
  const definerAtCreate = [...executableGuard.matchAll(/SECURITY DEFINER/g)].length;
  const alterCount =
    [...executableGuard.matchAll(/ALTER FUNCTION public\.\w+\(/g)].length;
  assertEquals(definerAtCreate, alterCount, "CREATE 一律 INVOKER 起手");
});

Deno.test("guard migration：出窗守衛的關鍵寫入都在", () => {
  assert(
    executableGuard.includes("p_expiry_before IS NULL"),
    "p_expiry_before 必須是必填驗證",
  );
  assert(
    executableGuard.includes("v_row.post_date < p_expiry_before"),
    "出窗判定必須存在",
  );
  // claim 與 commit 兩支都要有守衛（第二輪複審 P2-4：晚到 commit 也要擋）。
  const claimHits =
    [...executableGuard.matchAll(/v_row\.post_date < p_expiry_before/g)].length;
  assert(claimHits >= 2, `claim 與 commit 都必須帶出窗判定（實際 ${claimHits} 處）`);
  assert(
    executableGuard.includes(
      "DROP FUNCTION IF EXISTS public.commit_practice_moment_image(",
    ),
    "舊 5-arg commit_image 必須被移除",
  );
  assert(!executableGuard.includes("DELETE FROM"), "guard migration 不得刪列");
  assert(!executableGuard.includes("DROP TABLE"));
});

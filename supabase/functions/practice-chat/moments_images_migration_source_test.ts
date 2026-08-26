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
  FEED_WINDOW_DAYS,
  MAX_MOMENT_IMAGE_ATTEMPTS,
  MOMENT_IMAGE_ORPHAN_GRACE_SECONDS,
  MOMENT_IMAGE_ORPHAN_LEDGER_LIMIT,
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
const ledgerMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260826024500_practice_moment_image_orphan_ledger.sql",
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
      "REVOKE ALL ON FUNCTION public.commit_practice_moment_image(",
      "ALTER FUNCTION public.commit_practice_moment_image(",
      "NOTIFY pgrst, 'reload schema';",
    ] as const
  ) {
    assert(executableGuard.includes(snippet), `guard migration 缺：${snippet}`);
  }
  for (
    const name of [
      "claim_practice_moment_image",
      "commit_practice_moment_image",
      "release_practice_moment_image",
    ] as const
  ) {
    assert(
      guardMigration.includes(`${name}: unexpected overload(s): %`),
      `${name} 缺 fail-closed overload 稽核`,
    );
  }
  const definerAtCreate = [...executableGuard.matchAll(/SECURITY DEFINER/g)].length;
  const alterCount =
    [...executableGuard.matchAll(/ALTER FUNCTION public\.\w+\(/g)].length;
  assertEquals(definerAtCreate, alterCount, "CREATE 一律 INVOKER 起手");
});

Deno.test("guard migration：DB 端 cutoff 的關鍵寫入都在（第三輪修訂）", () => {
  // cutoff 由 DB 以當下 now() 計算（固定 +8 台北偏移），不吃呼叫端 snapshot；
  // 13 = FEED_WINDOW_DAYS - 1，兩邊釘死。
  const cutoffDecls = [...executableGuard.matchAll(
    /AT TIME ZONE INTERVAL '8 hours'\)::date - (\d+)\)/g,
  )];
  assertEquals(cutoffDecls.length, 3, "claim／commit／release 都必須自算 cutoff");
  for (const match of cutoffDecls) {
    assertEquals(Number(match[1]), FEED_WINDOW_DAYS - 1);
  }
  const guardHits =
    [...executableGuard.matchAll(/v_row\.post_date < v_expiry_cutoff/g)].length;
  assertEquals(guardHits, 3, "claim／commit／release 都必須帶出窗判定");
  assert(
    !executableGuard.includes("p_expiry_before"),
    "cutoff 不得由呼叫端傳入（跨台北午夜會吃到舊值）",
  );
  // 晚到 commit 被拒時必須收屍：commit 本體要有 pending→failed 的 UPDATE。
  const commitStart = executableGuard.indexOf(
    "CREATE OR REPLACE FUNCTION public.commit_practice_moment_image(",
  );
  const commitBody = executableGuard.slice(commitStart);
  assert(
    commitBody.includes("SET image_status = 'failed'"),
    "晚到 commit 被拒時列必須收成 failed，不留永久 pending",
  );
  assert(!executableGuard.includes("DELETE FROM"), "guard migration 不得刪列");
  assert(!executableGuard.includes("DROP TABLE"));
});

// ---------------------------------------------------------------------------
// 孤兒帳本 migration（第四輪複審 P2-2）
// ---------------------------------------------------------------------------

const executableLedger = withoutComments(ledgerMigration);

/** 本檔新建或改簽名的 RPC。 */
const LEDGER_RPC_SIGNATURES = [
  [
    "claim_practice_moment_image",
    "TEXT, DATE, INTEGER, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER",
  ],
  ["commit_practice_moment_image", "TEXT, DATE, INTEGER, TEXT, TEXT"],
  ["list_practice_moment_image_orphans", "INTEGER, INTEGER"],
  ["clear_practice_moment_image_orphans", "TEXT[]"],
] as const;

Deno.test("ledger migration：權限樣板、overload 稽核與 NOTIFY 齊全", () => {
  for (const [name, args] of LEDGER_RPC_SIGNATURES) {
    const normalized = executableLedger.replace(/\s+/g, " ");
    for (const template of [
      `REVOKE ALL ON FUNCTION public.${name}( ${args} ) FROM PUBLIC;`,
      `REVOKE ALL ON FUNCTION public.${name}( ${args} ) FROM anon, authenticated;`,
      `GRANT EXECUTE ON FUNCTION public.${name}( ${args} ) TO service_role;`,
      `ALTER FUNCTION public.${name}( ${args} ) SECURITY DEFINER;`,
    ]) {
      const compact = template.replace(/\( /g, "(").replace(/ \)/g, ")");
      assert(
        normalized.includes(template) || normalized.includes(compact),
        `${name} 缺權限樣板：${template}`,
      );
    }
  }
  // claim 改簽名 → 前後各一次 fail-closed 稽核；commit 換本體 → 一次。
  assert(
    ledgerMigration.includes(
      "claim_practice_moment_image: unexpected overload(s): %",
    ),
    "claim 缺替換前的 overload 稽核",
  );
  assert(
    ledgerMigration.includes(
      "claim_practice_moment_image: unexpected overload(s) after replace: %",
    ),
    "claim 缺替換後的 overload 稽核",
  );
  assert(
    ledgerMigration.includes(
      "claim_practice_moment_image: expected signature missing",
    ),
    "改簽名後必須確認新簽名真的存在（fail-closed）",
  );
  assert(
    ledgerMigration.includes(
      "commit_practice_moment_image: unexpected overload(s): %",
    ),
  );
  assert(
    executableLedger.includes("NOTIFY pgrst, 'reload schema';"),
    "改了函式簽名一定要重載 schema cache",
  );
  const definerAtCreate =
    [...executableLedger.matchAll(/SECURITY DEFINER/g)].length;
  const alterCount =
    [...executableLedger.matchAll(/ALTER FUNCTION public\.\w+\(/g)].length;
  assertEquals(definerAtCreate, alterCount, "CREATE 一律 INVOKER 起手");
});

Deno.test("ledger migration：改簽名走 DROP + CREATE，且只丟舊的那一支", () => {
  const normalized = executableLedger.replace(/\s+/g, " ");
  assert(
    normalized.includes(
      "DROP FUNCTION IF EXISTS public.claim_practice_moment_image( TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER );",
    ),
    "必須明確丟掉舊的 10-arg 簽名（overload 衛生）",
  );
  const drops = [...executableLedger.matchAll(/DROP FUNCTION/g)].length;
  assertEquals(drops, 1, "只准丟這一支；其他函式一律 CREATE OR REPLACE");
  assert(!executableLedger.includes("DROP TABLE"));
  assert(!executableLedger.includes("DELETE FROM"), "帳本清算不得刪列（D6）");
  assert(
    !executableLedger.includes("supabase db push"),
    "production migration 一律走 targeted 流程",
  );
});

Deno.test("ledger migration：記帳與抹帳都在對的那一筆交易裡", () => {
  const claimStart = executableLedger.indexOf(
    "CREATE OR REPLACE FUNCTION public.claim_practice_moment_image(",
  );
  const commitStart = executableLedger.indexOf(
    "CREATE OR REPLACE FUNCTION public.commit_practice_moment_image(",
  );
  assert(claimStart >= 0 && commitStart > claimStart);
  const claimBody = executableLedger.slice(claimStart, commitStart);
  const commitBody = executableLedger.slice(
    commitStart,
    executableLedger.indexOf(
      "CREATE OR REPLACE FUNCTION public.list_practice_moment_image_orphans(",
    ),
  );
  // 認領（＝租約成立）的同一筆 UPDATE 記帳。
  assert(
    claimBody.includes("image_orphan_paths = array_append("),
    "claim 必須在同一筆交易記帳",
  );
  assert(
    claimBody.includes("image_token = p_image_token") &&
      claimBody.includes("image_reserved_at = now()"),
    "記帳必須與換 token／租約同一筆 UPDATE",
  );
  // commit 成功的同一筆 UPDATE 抹帳。
  assert(
    commitBody.includes(
      "image_orphan_paths = array_remove(mp.image_orphan_paths, p_image_path)",
    ),
    "commit 成功必須在同一筆交易抹掉帳本紀錄",
  );
  assert(
    commitBody.includes("image_status = 'ready'"),
    "抹帳必須跟 ready 同一筆 UPDATE（否則會出現引用中的孤兒）",
  );
  // 兩支都還是自算 cutoff（第三輪的圍籬不得被這次改壞）。
  const cutoffDecls = [...executableLedger.matchAll(
    /AT TIME ZONE INTERVAL '8 hours'\)::date - (\d+)\)/g,
  )];
  assertEquals(cutoffDecls.length, 2, "claim／commit 都必須自算 cutoff");
  for (const match of cutoffDecls) {
    assertEquals(Number(match[1]), FEED_WINDOW_DAYS - 1);
  }
  assert(!executableLedger.includes("p_expiry_before"));
});

Deno.test("ledger migration：清算的兩道守門都在", () => {
  const listStart = executableLedger.indexOf(
    "CREATE OR REPLACE FUNCTION public.list_practice_moment_image_orphans(",
  );
  const listBody = executableLedger.slice(
    listStart,
    executableLedger.indexOf(
      "CREATE OR REPLACE FUNCTION public.clear_practice_moment_image_orphans(",
    ),
  );
  assert(
    listBody.includes("GREATEST(p_grace_seconds, 180)"),
    "寬限期守門：在跑的 job 不得被自己的清算刪掉",
  );
  assert(
    listBody.includes("t.path IS DISTINCT FROM mp.image_path"),
    "引用守門：ready 列指著的物件永不列入清算",
  );
});

Deno.test("ledger migration：commit 與孤兒清算共用租約安全下限", () => {
  const leaseSeconds = MOMENT_IMAGE_RESERVE_LEASE_MS / 1000;
  const commitStart = executableLedger.indexOf(
    "CREATE OR REPLACE FUNCTION public.commit_practice_moment_image(",
  );
  const listStart = executableLedger.indexOf(
    "CREATE OR REPLACE FUNCTION public.list_practice_moment_image_orphans(",
  );
  const commitBody = executableLedger.slice(commitStart, listStart);
  const listBody = executableLedger.slice(
    listStart,
    executableLedger.indexOf(
      "CREATE OR REPLACE FUNCTION public.clear_practice_moment_image_orphans(",
    ),
  );
  assert(
    commitBody.includes(
      `image_reserved_at <= now() - make_interval(secs => ${leaseSeconds})`,
    ),
    "過期租約即使 token 尚未輪替也不得 commit",
  );
  assert(
    listBody.includes(`GREATEST(p_grace_seconds, ${leaseSeconds})`),
    "孤兒清算寬限不得短於 commit 租約",
  );
  assert(
    executableLedger.includes(`p_lease_seconds <> ${leaseSeconds}`),
    "claim 的可接受租約必須與 commit／清算的資料層安全邊界一致",
  );
  assert(
    commitBody.indexOf("v_row.post_date < v_expiry_cutoff") <
      commitBody.indexOf("v_row.image_reserved_at IS NULL"),
    "出窗收屍必須早於租約過期 RETURN，避免永久 pending",
  );
});

Deno.test("SQL 的孤兒寬限秒數等於 MOMENT_IMAGE_ORPHAN_GRACE_SECONDS", () => {
  const matches = [...ledgerMigration.matchAll(
    /p_grace_seconds INTEGER DEFAULT (\d+)/g,
  )];
  assertEquals(matches.length, 1, "寬限期預設值只能有一處");
  assertEquals(Number(matches[0][1]), MOMENT_IMAGE_ORPHAN_GRACE_SECONDS);
});

Deno.test("孤兒清算上限：Edge 常數 ≤ SQL 硬上界", () => {
  const listStart = ledgerMigration.indexOf(
    "CREATE OR REPLACE FUNCTION public.list_practice_moment_image_orphans(",
  );
  const listBody = ledgerMigration.slice(listStart);
  const cap = [...listBody.matchAll(/p_limit > (\d+)/g)];
  assert(cap.length > 0, "list RPC 必須有 p_limit 硬上界");
  assert(
    MOMENT_IMAGE_ORPHAN_LEDGER_LIMIT <= Number(cap[0][1]),
    "Edge 傳的清算上限不得超過 SQL 硬上界",
  );
  assert(MOMENT_IMAGE_ORPHAN_LEDGER_LIMIT > 0);
});

Deno.test("帳本路徑與 image_path 共用同一道長度守門", () => {
  const claimStart = ledgerMigration.indexOf(
    "CREATE OR REPLACE FUNCTION public.claim_practice_moment_image(",
  );
  const claimBody = ledgerMigration.slice(
    claimStart,
    ledgerMigration.indexOf(
      "CREATE OR REPLACE FUNCTION public.commit_practice_moment_image(",
    ),
  );
  const matches = [...claimBody.matchAll(
    /char_length\(p_image_path\) > (\d+)/g,
  )];
  assertEquals(matches.length, 1);
  assertEquals(Number(matches[0][1]), MOMENT_IMAGE_PATH_DB_MAX_CHARS);
});

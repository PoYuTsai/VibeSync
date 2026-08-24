// 練習室模擬社群動態：TS 常數與 migration SQL 的**雙向**契約。
//
// PR A 只做了單向守門（source test 內留一份字面值 3，migration 註解記著
// TODO(PR B)）。單向的問題是：TS 側把上限改成 4 時 SQL 沒人擋，SQL 側把
// CHECK 放寬時 TS 也沒人擋。這支測試把兩個方向都釘死：
//   SQL → TS：從 migration 原文剖出每一個數字，逐一比對 TS 常數。
//   TS → SQL：每一個有 SQL 對應物的 TS 常數，都必須在 SQL 內找得到。
// 任何一邊漂移都會紅。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  FEED_WINDOW_DAYS,
  MAX_MOMENT_ATTEMPTS,
  MOMENT_BODY_DB_MAX_CHARS,
  MOMENT_BODY_MAX_CHARS,
  MOMENT_BODY_MIN_CHARS,
  MOMENT_FILL_DEADLINE_MS,
  MOMENT_FILL_MAX_PER_REQUEST,
  MOMENT_PROFILE_ALLOWLIST_MAX,
  MOMENT_PROMPT_MAX_CHARS,
  MOMENT_PROMPT_MIN_CHARS,
  MOMENT_RESERVE_LEASE_MS,
  MOMENT_SLOT_COUNT,
} from "./moments_constants.ts";
import { MAX_MOMENT_SLOTS_PER_DAY } from "./moments_schedule.ts";
import { GIRL_PROFILES } from "./practice_persona.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260822120000_practice_moment_posts.sql",
    import.meta.url,
  ),
);

/** 從 migration 原文剖出唯一一處符合 pattern 的數字；找不到或多於一處就紅。 */
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
// SQL → TS：SQL 內的每一個數字都必須等於對應的 TS 常數
// ---------------------------------------------------------------------------

Deno.test("SQL 的 attempts 上界等於 MAX_MOMENT_ATTEMPTS", () => {
  assertEquals(
    soleNumberFromSql(
      /CHECK \(attempts BETWEEN 0 AND (\d+)\)/g,
      "CHECK (attempts BETWEEN 0 AND N)",
    ),
    MAX_MOMENT_ATTEMPTS,
  );
  // 兩支 RPC 的 p_max_attempts 預設值與硬上界也是同一個數字，否則呼叫端
  // 傳一個更大的值就能繞過成本上限。
  assertEquals(
    soleNumberFromSql(
      /p_max_attempts\s+INTEGER DEFAULT (\d+)/g,
      "p_max_attempts DEFAULT",
    ),
    MAX_MOMENT_ATTEMPTS,
  );
  assertEquals(
    soleNumberFromSql(
      /p_max_attempts > (\d+) THEN/g,
      "p_max_attempts 上界防呆",
    ),
    MAX_MOMENT_ATTEMPTS,
  );
});

Deno.test("SQL 的 slot 上界等於 MOMENT_SLOT_COUNT - 1", () => {
  assertEquals(
    soleNumberFromSql(
      /CHECK \(slot BETWEEN 0 AND (\d+)\)/g,
      "CHECK (slot BETWEEN 0 AND N)",
    ),
    MOMENT_SLOT_COUNT - 1,
  );
  assertEquals(
    soleNumberFromSql(/p_slot > (\d+) THEN/g, "p_slot 上界防呆"),
    MOMENT_SLOT_COUNT - 1,
  );
});

Deno.test("SQL 的 body 長度上界等於 MOMENT_BODY_DB_MAX_CHARS", () => {
  assertEquals(
    soleNumberFromSql(
      /char_length\(body\) BETWEEN 1 AND (\d+)/g,
      "CHECK (char_length(body) BETWEEN 1 AND N)",
    ),
    MOMENT_BODY_DB_MAX_CHARS,
  );
  assertEquals(
    soleNumberFromSql(
      /char_length\(v_body\) > (\d+) THEN/g,
      "commit 的 body 長度防呆",
    ),
    MOMENT_BODY_DB_MAX_CHARS,
  );
});

Deno.test("SQL 的租約秒數預設值等於 MOMENT_RESERVE_LEASE_MS", () => {
  assertEquals(
    soleNumberFromSql(
      /p_lease_seconds\s+INTEGER DEFAULT (\d+)/g,
      "p_lease_seconds DEFAULT",
    ),
    MOMENT_RESERVE_LEASE_MS / 1000,
  );
});

Deno.test("SQL 的 profile_ids 上限等於角色 allowlist 大小", () => {
  // 這一條同時是「每日 600 次上限」的分母：DB 只保證每個 (profile_id,
  // post_date) 最多 6 次，×100 位角色才是 600。SQL 的 100 與 Edge allowlist
  // 的 100 一旦不同步，那個乘法就不成立。
  assertEquals(
    soleNumberFromSql(
      /array_length\(p_profile_ids, 1\) > (\d+) THEN/g,
      "list RPC 的 p_profile_ids 上限",
    ),
    MOMENT_PROFILE_ALLOWLIST_MAX,
  );
  assertEquals(MOMENT_PROFILE_ALLOWLIST_MAX, GIRL_PROFILES.length);
});

// ---------------------------------------------------------------------------
// TS → SQL：TS 常數必須在 SQL 內找得到對應字面值
// ---------------------------------------------------------------------------

Deno.test("每個有 SQL 對應物的 TS 常數都能在 migration 內找到", () => {
  for (
    const [label, snippet] of [
      [
        "attempts CHECK",
        `CHECK (attempts BETWEEN 0 AND ${MAX_MOMENT_ATTEMPTS})`,
      ],
      ["slot CHECK", `CHECK (slot BETWEEN 0 AND ${MOMENT_SLOT_COUNT - 1})`],
      [
        "body CHECK",
        `char_length(body) BETWEEN 1 AND ${MOMENT_BODY_DB_MAX_CHARS}`,
      ],
      [
        "lease default",
        `p_lease_seconds    INTEGER DEFAULT ${MOMENT_RESERVE_LEASE_MS / 1000}`,
      ],
      [
        "profile allowlist",
        `array_length(p_profile_ids, 1) > ${MOMENT_PROFILE_ALLOWLIST_MAX}`,
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
// TS 內部一致性：三層長度、slot 數、死線
// ---------------------------------------------------------------------------

Deno.test("三層長度守門的數字互相對得起來", () => {
  // prompt 指示（20-60）⊂ 產品守門（18-66）⊂ DB 縱深防禦（1-220）。
  assert(
    MOMENT_BODY_MIN_CHARS < MOMENT_PROMPT_MIN_CHARS,
    "驗證下界必須比 prompt 指示更寬，否則 61 字的好貼文會白燒一次 attempts",
  );
  assert(MOMENT_PROMPT_MAX_CHARS < MOMENT_BODY_MAX_CHARS);
  assert(MOMENT_BODY_MAX_CHARS < MOMENT_BODY_DB_MAX_CHARS);
  assertEquals(MOMENT_BODY_MIN_CHARS, 18);
  assertEquals(MOMENT_BODY_MAX_CHARS, 66);
  assertEquals(MOMENT_PROMPT_MIN_CHARS, 20);
  assertEquals(MOMENT_PROMPT_MAX_CHARS, 60);
});

Deno.test("MOMENT_SLOT_COUNT 與排程的每日 slot 上限同步", () => {
  assertEquals(MOMENT_SLOT_COUNT, MAX_MOMENT_SLOTS_PER_DAY);
});

Deno.test("死線、租約與補生成上限的量級關係成立", () => {
  assertEquals(MOMENT_FILL_DEADLINE_MS, 8000);
  assertEquals(MOMENT_FILL_MAX_PER_REQUEST, 3);
  assertEquals(FEED_WINDOW_DAYS, 14);
  assert(
    MOMENT_FILL_DEADLINE_MS < MOMENT_RESERVE_LEASE_MS,
    "死線必須遠短於租約，否則死線中止的列會被下一個請求立刻搶走並多燒一次 attempts",
  );
});

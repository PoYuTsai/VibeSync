// 圖鑑額度列 v2 守門：唯讀 get_practice_draw_status 與 claim RPC 的計數謂詞
// 必須同語意（Codex 雙審 non-blocking：防未來 claim 改動時額度列漂移）。
// 跑法：deno test --allow-read supabase/functions/practice-chat/draw_status_migration_test.ts

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const statusMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260809120000_get_practice_draw_status.sql",
    import.meta.url,
  ),
);
const claimMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260808155210_claim_draw_exclude_sr_ticket.sql",
    import.meta.url,
  ),
);

/** 抽出 free_used 計數謂詞的三行核心（去空白正規化）。 */
function freeUsedPredicates(sql: string): string[] {
  const normalized = sql.replace(/\s+/g, " ");
  const matches = normalized.match(
    /reset_window_start_at = p_reset_window_start_at AND cost_messages = 0 AND bonus_source IS NULL/g,
  );
  return matches ?? [];
}

Deno.test("status 的 free_used 謂詞與 claim 逐字同語意（window＋cost0＋排除券抽）", () => {
  const statusPredicates = freeUsedPredicates(statusMigration);
  const claimPredicates = freeUsedPredicates(claimMigration);
  // status 恰好一處；claim 四處（step 1 / 2a / 3 / unique_violation replay）。
  assertEquals(statusPredicates.length, 1);
  assertEquals(claimPredicates.length, 4);
});

Deno.test("status 的贈抽合併與 remaining 公式與 claim 同語意", () => {
  const bonusCheck = "(b.consumed_at IS NULL) INTO v_bonus_available";
  assert(statusMigration.includes(bonusCheck));
  assert(claimMigration.includes(bonusCheck));
  const remainingFormula = "GREATEST(0, v_allowance - v_free_used)";
  assert(statusMigration.includes(remainingFormula));
  assert(claimMigration.includes(remainingFormula));
});

Deno.test("status RPC 唯讀鐵則：無 INSERT/UPDATE/DELETE/FOR UPDATE，且 service_role only", () => {
  // 只掃有效 SQL：剝掉 `--` 註解（註解裡描述「不 FOR UPDATE」不算違規）。
  const effectiveSql = statusMigration
    .split("\n")
    .map((line) => line.replace(/--.*$/, ""))
    .join("\n");
  for (
    const banned of [
      "INSERT INTO",
      "UPDATE public.",
      "DELETE FROM",
      "FOR UPDATE",
    ]
  ) {
    assert(
      !effectiveSql.includes(banned),
      `唯讀 status migration 不得出現 ${banned}`,
    );
  }
  assert(
    statusMigration.includes(
      "REVOKE ALL ON FUNCTION public.get_practice_draw_status",
    ),
  );
  assert(
    statusMigration.includes(
      "GRANT EXECUTE ON FUNCTION public.get_practice_draw_status(UUID, TIMESTAMPTZ, INTEGER) TO service_role",
    ),
  );
});

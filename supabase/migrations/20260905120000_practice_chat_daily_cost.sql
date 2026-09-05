-- 練習室 Phase 5 WP2 成本保險絲的資料層（純加法，可回滾）。
--
-- 設計來源：docs/plans/2026-09-05-practice-room-phase5-plan.md §4 WP2、§2 D8。
--
-- 這張表只存一個全站數字：某一天 practice-chat 的 Anthropic 估算花費累計。
-- 沒有 user_id、沒有任何對話內容——保險絲要的只是「今天燒掉多少錢」。
-- `day` 是 **UTC 日**（Edge 端用 `new Date().toISOString().slice(0, 10)`，
-- 見 supabase/functions/practice-chat/cost_fuse.ts）：保險絲是成本護欄不是
-- 報表，跨日在哪個時區切不影響「一天燒不超過 N 美金」這件事，用 UTC 可以
-- 免掉時區換算這個額外的出錯面。
--
-- 旗標 `PRACTICE_COST_FUSE_DAILY_USD` 留空時 Edge 端**完全不讀不寫這張表**，
-- 所以關旗標＝表沒人碰，資料留著不影響任何行為（計畫 §5 的回滾鐵則）。
--
-- 契約測試：
--   supabase/functions/practice-chat/practice_chat_daily_cost_migration_source_test.ts
--   supabase/functions/practice-chat/practice_chat_daily_cost_migration_postgres_test.ts

CREATE TABLE IF NOT EXISTS public.practice_chat_daily_cost (
  day        DATE        PRIMARY KEY,
  -- Anthropic 估算花費累計（USD）。單價來源是
  -- supabase/functions/_shared/model_pricing.ts，不是帳單實數。
  -- `>= 0` 擋不住 NaN（PG 的 NaN 在 numeric 排序裡比任何值都大，`NaN >= 0`
  -- 為真），所以另外明寫一條：累計一旦變成 NaN，之後每一次比較都會失真。
  spent_usd  NUMERIC     NOT NULL DEFAULT 0
               CHECK (
                 spent_usd >= 0
                 AND spent_usd <> 'NaN'::NUMERIC
                 AND spent_usd <> 'Infinity'::NUMERIC
                 AND spent_usd <> '-Infinity'::NUMERIC
               ),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Edge Function 以 service role 經 SECURITY DEFINER RPC 累加；讀取走 service
-- role 的直接 select。不開放 anon/authenticated：無 policy = 預設拒絕
-- （沿用 practice_moment_posts 的既有慣例）。
ALTER TABLE public.practice_chat_daily_cost ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 累加：一次 upsert 把本輪估算金額加進當天，回傳**累加後**的值。
-- ---------------------------------------------------------------------------
-- 回傳累加後的值是刻意的：Edge 端要靠 `after - p_usd < budget <= after` 判斷
-- 「這一次剛好跨過門檻」，才能保證 `practice_chat_cost_fuse_blown` 一天恰好
-- 一筆。用「先讀再寫」判斷會在併發下重複寫事件，這裡由單一 statement 的
-- ON CONFLICT DO UPDATE 保證原子。
CREATE OR REPLACE FUNCTION public.increment_practice_chat_daily_cost(
  p_day DATE,
  p_usd NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
-- statement-by-statement runner 安全：先用 caller 權限建立，完成 REVOKE 後
-- 才在檔尾切成 definer，避免 migration 中途留下 PUBLIC 可執行的 definer RPC。
SECURITY INVOKER
-- definer 函式的 search_path 一律清空：函式內每一個表名都已經全限定
-- （`public.practice_chat_daily_cost`），`now()` 也寫成 `pg_catalog.now()`，
-- 所以不需要任何可搜尋 schema。留 `public` 的話，能建 public 物件的角色就有
-- 機會用同名物件劫持 definer 函式。
SET search_path = ''
AS $$
DECLARE
  v_total NUMERIC;
BEGIN
  IF p_day IS NULL THEN
    RAISE EXCEPTION
      'increment_practice_chat_daily_cost: p_day is required';
  END IF;
  -- NaN／±Infinity 都要在寫進去之前擋掉：NaN 會讓之後每一次
  -- `spent_usd >= budget` 比較失真，Infinity 會讓保險絲永久燒斷。
  -- PG 的 numeric NaN 之間**相等**（不是 IEEE 的 NaN <> NaN），所以直接用
  -- `= 'NaN'::NUMERIC` 判；`p_usd <> p_usd` 那種 IEEE 寫法在 numeric 上不成立。
  IF p_usd IS NULL
     OR p_usd = 'NaN'::NUMERIC
     OR p_usd = 'Infinity'::NUMERIC
     OR p_usd = '-Infinity'::NUMERIC
     OR p_usd < 0 THEN
    RAISE EXCEPTION
      'increment_practice_chat_daily_cost: p_usd must be a finite non-negative number';
  END IF;

  INSERT INTO public.practice_chat_daily_cost AS c (day, spent_usd, updated_at)
  VALUES (p_day, p_usd, pg_catalog.now())
  ON CONFLICT (day) DO UPDATE
    SET spent_usd  = c.spent_usd + EXCLUDED.spent_usd,
        updated_at = pg_catalog.now()
  RETURNING c.spent_usd INTO v_total;

  RETURN v_total;
END;
$$;

-- Edge 端的「今天燒掉多少」是一次直接 select（不走 RPC），所以 service_role
-- 需要明確的 SELECT。不依賴 Supabase 的 default privileges——那是專案設定，
-- 不是這份 migration 保證得了的東西。
GRANT SELECT ON TABLE public.practice_chat_daily_cost TO service_role;

REVOKE ALL ON FUNCTION public.increment_practice_chat_daily_cost(
  DATE, NUMERIC
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.increment_practice_chat_daily_cost(
  DATE, NUMERIC
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_practice_chat_daily_cost(
  DATE, NUMERIC
) TO service_role;
ALTER FUNCTION public.increment_practice_chat_daily_cost(
  DATE, NUMERIC
) SECURITY DEFINER;

COMMENT ON FUNCTION public.increment_practice_chat_daily_cost(
  DATE, NUMERIC
) IS
  'Service-role-only accumulator for the practice-chat daily Anthropic cost fuse. Returns the post-increment total.';

NOTIFY pgrst, 'reload schema';

-- 練習室「模擬社群動態」資料層（PR A，純加法）。
--
-- 設計來源：docs/plans/2026-08-21-practice-moments-design.md §4。
-- 貼文是「全域」的：同一位角色、同一天、同一個 slot，所有看得到她的使用者
-- 讀到的是同一則。因此本表沒有 user_id，也永遠不得寫入任何使用者對話、暱稱、
-- hint、debrief 或 relationship thread 衍生的內容（隱私鐵則）。
--
-- 本表是全站每日模型呼叫上限的「DB 側」來源。注意 DB 單獨不足以保證每日 600 次
-- （2026-08-22 複審 P2-1）：
--   DB 機械保證的是「每個 (profile_id, post_date) 最多 6 次」——
--     unique(profile_id, post_date, slot)
--     × CHECK (slot BETWEEN 0 AND 1)      → 每天最多 2 個 slot
--     × CHECK (attempts BETWEEN 0 AND 3)  → 每個 slot 最多 3 次模型呼叫
--   DB 不保證、必須由 Edge 保證的是：
--     · profile_id 只來自 100 位角色的固定 allowlist（DB 不認識角色名冊，
--       任意字串都會被接受並各自獲得自己的 6 次額度）
--     · post_date 是正確的台北日期（否則同一天可被算成多天）
--   兩者相乘才是 100 × 6 = 每日最多 600 次。
--   → Edge 側 allowlist 與台北日的契約測試：
--     supabase/functions/practice-chat/moments_edge_contract_test.ts（PR B 補齊）
--
-- per-user `practice_moment` 限流也在 reserve 的同一筆 transaction 內計數。
-- 只有真正 claimed 的分支會同時增加 attempts 與 user usage；未取得 slot 不計，
-- 超限 RAISE 會讓整筆 claim rollback，避免沒打模型卻先扣額度。
--
-- 契約測試：supabase/functions/practice-chat/moments_migration_postgres_test.ts
--          （PGlite 真 Postgres，逐格驗 reserve 的六態轉移表）
--          supabase/functions/practice-chat/moments_migration_source_test.ts

CREATE TABLE IF NOT EXISTS public.practice_moment_posts (
  profile_id       TEXT        NOT NULL,          -- Edge 以角色 allowlist 驗證
  post_date        DATE        NOT NULL,          -- 台北日
  slot             SMALLINT    NOT NULL CHECK (slot BETWEEN 0 AND 1),
  day_part         TEXT        NOT NULL,
  theme_id         TEXT        NOT NULL,
  status           TEXT        NOT NULL CHECK (status IN ('reserved', 'ready', 'exhausted')),
  -- 已消耗的模型呼叫次數。認領時就 +1（不是失敗時才 +1）：worker 中途死掉
  -- 也算用掉一次，否則 crash loop 仍然無界。這一欄是全域成本上限的來源。
  attempts         SMALLINT    NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
  -- 縱深防禦，不是產品規格：產品長度守門（18-66 字）在 Edge 端。
  body             TEXT        CHECK (body IS NULL OR char_length(body) BETWEEN 1 AND 220),
  image_id         TEXT,                          -- NULL = 純文字貼文
  generation_token TEXT,                          -- token-fenced latch（比照 hint／debrief）
  reserved_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  model            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (profile_id, post_date, slot),
  -- no-canned 的資料層版本：ready 一定有真的內容，失敗永遠不會留下空殼 ready。
  CONSTRAINT practice_moment_ready_has_body
    CHECK (status <> 'ready' OR (body IS NOT NULL AND char_length(btrim(body)) > 0))
);

-- Edge Function 以 service role 經 SECURITY DEFINER RPC 存取；不開放 anon/authenticated。
-- 無 policy = 預設拒絕（沿用 funnel_events 的既有慣例）。
ALTER TABLE public.practice_moment_posts ENABLE ROW LEVEL SECURITY;

-- feed 的讀取樣式固定是「最近 N 天 × 一組已解鎖 profile_id」。
CREATE INDEX IF NOT EXISTS practice_moment_posts_date_idx
  ON public.practice_moment_posts (post_date DESC, profile_id);

-- ---------------------------------------------------------------------------
-- reserve：六態轉移表（設計報告 §4）
-- ---------------------------------------------------------------------------
-- 進入時列狀態                                              動作                         結果
-- 不存在（INSERT 成功）                                      status='reserved'、attempts=1  ✅ 放行
-- ready                                                     不動                          ❌ 拒絕
-- exhausted                                                 不動                          ❌ 拒絕
-- reserved + token 非 NULL + 租約未逾時                      不動                          ❌ 拒絕
-- reserved +（token IS NULL 或租約逾時）+ attempts < 上限     attempts+1、換發 token         ✅ 放行
-- reserved +（token IS NULL 或租約逾時）+ attempts >= 上限    轉 exhausted、清 token         ❌ 拒絕
--
-- 兩個複審點名、很容易寫錯的地方（都有專屬契約測試釘死）：
--   1. 首次 INSERT 必須明寫 attempts = 1，不能靠 DEFAULT 0。用 0 的話第一次認領
--      不計數，之後還能再遞增三次 → 每 slot 實際跑 4 次而不是 3 次，整體上限
--      上浮 1/3（在 Edge allowlist 成立的前提下，全站每日 600 → 800）。
--   2. generation_token IS NULL 必須是獨立的放行分支。release 的用途就是「我失敗
--      了，別人不必等租約逾時就能接手」；若只看租約時間，被 release 的列會被自己
--      剛寫下的新鮮 reserved_at 擋住整個租約，release 等於沒有作用。
CREATE OR REPLACE FUNCTION public.reserve_practice_moment_slot(
  p_profile_id       TEXT,
  p_post_date        DATE,
  p_slot             INTEGER,
  p_day_part         TEXT,
  p_theme_id         TEXT,
  p_generation_token TEXT,
  p_user_id          UUID,
  p_minute_limit     INTEGER,
  p_daily_limit      INTEGER,
  p_count_user_usage BOOLEAN,
  p_max_attempts     INTEGER DEFAULT 3,
  p_lease_seconds    INTEGER DEFAULT 120
)
RETURNS TABLE(claimed BOOLEAN, token TEXT, attempt_count SMALLINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row      public.practice_moment_posts%ROWTYPE;
  v_inserted INTEGER := 0;
  v_attempts SMALLINT;
BEGIN
  -- SECURITY DEFINER 下 RLS 不擋垃圾輸入，逐項明確驗。
  IF p_profile_id IS NULL
     OR char_length(p_profile_id) = 0
     OR char_length(p_profile_id) > 64 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_profile_id';
  END IF;
  IF p_post_date IS NULL THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: p_post_date is required';
  END IF;
  IF p_slot IS NULL OR p_slot < 0 OR p_slot > 1 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_slot';
  END IF;
  IF p_day_part IS NULL
     OR char_length(p_day_part) = 0
     OR char_length(p_day_part) > 32 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_day_part';
  END IF;
  IF p_theme_id IS NULL
     OR char_length(p_theme_id) = 0
     OR char_length(p_theme_id) > 64 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_theme_id';
  END IF;
  IF p_generation_token IS NULL
     OR char_length(p_generation_token) = 0
     OR char_length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_generation_token';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: p_user_id is required';
  END IF;
  IF p_minute_limit IS NULL OR p_minute_limit <= 0 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_minute_limit';
  END IF;
  IF p_daily_limit IS NULL OR p_daily_limit <= 0 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_daily_limit';
  END IF;
  IF p_count_user_usage IS NULL THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: p_count_user_usage is required';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts <= 0 OR p_max_attempts > 3 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_max_attempts';
  END IF;
  IF p_lease_seconds IS NULL OR p_lease_seconds <= 0 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_lease_seconds';
  END IF;

  -- 第 1 格：列不存在。attempts 明寫 1（坑 #1）。
  INSERT INTO public.practice_moment_posts AS mp (
    profile_id, post_date, slot, day_part, theme_id,
    status, attempts, generation_token, reserved_at, created_at, updated_at
  ) VALUES (
    p_profile_id, p_post_date, p_slot::SMALLINT, p_day_part, p_theme_id,
    'reserved', 1, p_generation_token, now(), now(), now()
  )
  ON CONFLICT (profile_id, post_date, slot) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  IF v_inserted = 1 THEN
    -- slot 認領與使用者限流必須在同一筆交易：超限 RAISE 會連 INSERT／
    -- attempts 一起 rollback，沒打模型就不會留下任何一種計數。
    IF p_count_user_usage THEN
      PERFORM public.increment_model_usage(
        p_user_id, 'practice_moment', p_minute_limit, p_daily_limit
      );
    END IF;
    claimed := TRUE;
    token := p_generation_token;
    attempt_count := 1::SMALLINT;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT mp.* INTO v_row
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  FOR UPDATE;

  IF NOT FOUND THEN
    -- 只有在別的交易同時刪列時才會走到這裡；本專案沒有任何刪除路徑。
    claimed := FALSE;
    token := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 第 2、3 格：ready／exhausted 一律不動、不呼叫模型。
  IF v_row.status <> 'reserved' THEN
    claimed := FALSE;
    token := NULL;
    attempt_count := v_row.attempts;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 第 4 格：別人正在跑，租約仍有效。
  IF v_row.generation_token IS NOT NULL
     AND v_row.reserved_at > now() - make_interval(secs => p_lease_seconds) THEN
    claimed := FALSE;
    token := NULL;
    attempt_count := v_row.attempts;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 以下為「token IS NULL（被 release 過）或租約逾時」的接手分支（坑 #2）。
  -- 第 6 格：attempts 已達上限 → 轉 exhausted，之後同一天不再打模型。
  IF v_row.attempts >= p_max_attempts THEN
    UPDATE public.practice_moment_posts AS mp
    SET status = 'exhausted',
        generation_token = NULL,
        updated_at = now()
    WHERE mp.profile_id = p_profile_id
      AND mp.post_date = p_post_date
      AND mp.slot = p_slot::SMALLINT;

    claimed := FALSE;
    token := NULL;
    attempt_count := v_row.attempts;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 第 5 格：接手，並把這一次算進成本。
  -- 先在同一筆交易內拿到 per-user 額度；超限時整筆 rollback，既不換 token，
  -- 也不增加 attempts。
  IF p_count_user_usage THEN
    PERFORM public.increment_model_usage(
      p_user_id, 'practice_moment', p_minute_limit, p_daily_limit
    );
  END IF;
  UPDATE public.practice_moment_posts AS mp
  SET attempts = v_row.attempts + 1,
      generation_token = p_generation_token,
      reserved_at = now(),
      day_part = p_day_part,
      theme_id = p_theme_id,
      updated_at = now()
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  RETURNING mp.attempts INTO v_attempts;

  claimed := TRUE;
  token := p_generation_token;
  attempt_count := v_attempts;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- commit：只有持有當前 token 的 worker 能把貼文寫成 ready
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.commit_practice_moment_post(
  p_profile_id       TEXT,
  p_post_date        DATE,
  p_slot             INTEGER,
  p_generation_token TEXT,
  p_body             TEXT,
  p_image_id         TEXT DEFAULT NULL,
  p_model            TEXT DEFAULT NULL
)
RETURNS TABLE(committed BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row  public.practice_moment_posts%ROWTYPE;
  v_body TEXT;
BEGIN
  IF p_profile_id IS NULL
     OR char_length(p_profile_id) = 0
     OR char_length(p_profile_id) > 64 THEN
    RAISE EXCEPTION 'commit_practice_moment_post: invalid p_profile_id';
  END IF;
  IF p_post_date IS NULL THEN
    RAISE EXCEPTION 'commit_practice_moment_post: p_post_date is required';
  END IF;
  IF p_slot IS NULL OR p_slot < 0 OR p_slot > 1 THEN
    RAISE EXCEPTION 'commit_practice_moment_post: invalid p_slot';
  END IF;
  IF p_generation_token IS NULL
     OR char_length(p_generation_token) = 0
     OR char_length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'commit_practice_moment_post: invalid p_generation_token';
  END IF;

  v_body := btrim(coalesce(p_body, ''));
  IF char_length(v_body) = 0 OR char_length(v_body) > 220 THEN
    RAISE EXCEPTION 'commit_practice_moment_post: invalid p_body';
  END IF;
  IF p_image_id IS NOT NULL
     AND (char_length(p_image_id) = 0 OR char_length(p_image_id) > 64) THEN
    RAISE EXCEPTION 'commit_practice_moment_post: invalid p_image_id';
  END IF;
  IF p_model IS NOT NULL
     AND (char_length(p_model) = 0 OR char_length(p_model) > 64) THEN
    RAISE EXCEPTION 'commit_practice_moment_post: invalid p_model';
  END IF;

  SELECT mp.* INTO v_row
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  FOR UPDATE;

  -- token fencing：被接手的舊 worker、或遲到的重複回應，一律回 FALSE 而不覆寫。
  IF NOT FOUND
     OR v_row.status <> 'reserved'
     OR v_row.generation_token IS NULL
     OR v_row.generation_token IS DISTINCT FROM p_generation_token THEN
    committed := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE public.practice_moment_posts AS mp
  SET status = 'ready',
      body = v_body,
      image_id = p_image_id,
      model = p_model,
      generation_token = NULL,
      updated_at = now()
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT;

  committed := TRUE;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- release：生成失敗時交還租約
-- ---------------------------------------------------------------------------
-- 骨架比照 release_practice_hint_generation（20260711150000）：先 FOR UPDATE 鎖列、
-- token 不符回 released = FALSE。三條鐵則：
--   絕不 DELETE 列（成本計數要留著）、絕不寫 body（no-canned）、絕不回收 attempts。
CREATE OR REPLACE FUNCTION public.release_practice_moment_slot(
  p_profile_id       TEXT,
  p_post_date        DATE,
  p_slot             INTEGER,
  p_generation_token TEXT,
  p_max_attempts     INTEGER DEFAULT 3
)
RETURNS TABLE(released BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.practice_moment_posts%ROWTYPE;
BEGIN
  IF p_profile_id IS NULL
     OR char_length(p_profile_id) = 0
     OR char_length(p_profile_id) > 64 THEN
    RAISE EXCEPTION 'release_practice_moment_slot: invalid p_profile_id';
  END IF;
  IF p_post_date IS NULL THEN
    RAISE EXCEPTION 'release_practice_moment_slot: p_post_date is required';
  END IF;
  IF p_slot IS NULL OR p_slot < 0 OR p_slot > 1 THEN
    RAISE EXCEPTION 'release_practice_moment_slot: invalid p_slot';
  END IF;
  IF p_generation_token IS NULL
     OR char_length(p_generation_token) = 0
     OR char_length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'release_practice_moment_slot: invalid p_generation_token';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts <= 0 OR p_max_attempts > 3 THEN
    RAISE EXCEPTION 'release_practice_moment_slot: invalid p_max_attempts';
  END IF;

  SELECT mp.* INTO v_row
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  FOR UPDATE;

  IF NOT FOUND
     OR v_row.status <> 'reserved'
     OR v_row.generation_token IS NULL
     OR v_row.generation_token IS DISTINCT FROM p_generation_token THEN
    released := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE public.practice_moment_posts AS mp
  SET status = CASE
        WHEN v_row.attempts >= p_max_attempts THEN 'exhausted'
        ELSE 'reserved'
      END,
      generation_token = NULL,
      updated_at = now()
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT;

  released := TRUE;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- list：feed 的唯一讀取路徑，只回 ready
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_practice_moment_posts(
  p_profile_ids TEXT[],
  p_since       DATE
)
RETURNS TABLE(
  profile_id TEXT,
  post_date  DATE,
  slot       SMALLINT,
  day_part   TEXT,
  theme_id   TEXT,
  body       TEXT,
  image_id   TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_profile_ids IS NULL OR array_length(p_profile_ids, 1) IS NULL THEN
    RETURN;
  END IF;
  IF array_length(p_profile_ids, 1) > 100 THEN
    RAISE EXCEPTION 'list_practice_moment_posts: too many p_profile_ids';
  END IF;
  IF p_since IS NULL THEN
    RAISE EXCEPTION 'list_practice_moment_posts: p_since is required';
  END IF;

  RETURN QUERY
  SELECT mp.profile_id,
         mp.post_date,
         mp.slot,
         mp.day_part,
         mp.theme_id,
         mp.body,
         mp.image_id,
         mp.created_at
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = ANY (p_profile_ids)
    AND mp.post_date >= p_since
    AND mp.status = 'ready'
  ORDER BY mp.post_date DESC, mp.profile_id, mp.slot;
END;
$$;

-- ---------------------------------------------------------------------------
-- 權限：一律 service_role only（client 永遠經 Edge）
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.reserve_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN,
  INTEGER, INTEGER
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reserve_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN,
  INTEGER, INTEGER
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN,
  INTEGER, INTEGER
) TO service_role;

REVOKE ALL ON FUNCTION public.commit_practice_moment_post(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.commit_practice_moment_post(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, TEXT
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_practice_moment_post(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, TEXT
) TO service_role;

REVOKE ALL ON FUNCTION public.release_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, INTEGER
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.release_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, INTEGER
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, INTEGER
) TO service_role;

REVOKE ALL ON FUNCTION public.list_practice_moment_posts(TEXT[], DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_practice_moment_posts(TEXT[], DATE) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_practice_moment_posts(TEXT[], DATE) TO service_role;

COMMENT ON TABLE public.practice_moment_posts
IS 'Global practice moment feed posts: one row per (profile_id, post_date, slot). Never stores user-derived content; attempts caps model calls at 3 per (profile_id, post_date, slot), i.e. 6 per profile-day. The daily 600 ceiling also requires the Edge layer to keep profile_id inside the 100-profile allowlist and post_date on the correct Taipei day.';
COMMENT ON FUNCTION public.reserve_practice_moment_slot(TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER)
IS 'Atomically leases one moment slot and, only for a successful claim, increments both attempts and per-user model usage in the same transaction. A rate-limit exception rolls the entire claim back.';
COMMENT ON FUNCTION public.commit_practice_moment_post(TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, TEXT)
IS 'Token-fenced commit of a generated moment post; a stale token returns FALSE and never overwrites a stored body.';
COMMENT ON FUNCTION public.release_practice_moment_slot(TEXT, DATE, INTEGER, TEXT, INTEGER)
IS 'Token-fenced release after a failed generation. Never deletes the row, never writes a body, never refunds attempts.';
COMMENT ON FUNCTION public.list_practice_moment_posts(TEXT[], DATE)
IS 'Reads ready moment posts for the given unlocked profile ids since a date; reserved and exhausted rows never leave the database.';

NOTIFY pgrst, 'reload schema';

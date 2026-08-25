-- 生成配圖清理競態的資料層圍籬（PR #34 複審 blocking item 3）。
--
-- 競態場景：機會式清理的「list → 刪 Storage 物件 → mark expired」三步之間，
-- 若出窗的列還能被重新認領生成（claim → 上傳到同一個決定論 key → commit），
-- 清理就可能刪掉或標記掉「新版」的圖。
--
-- 圍籬做法（兩道，2026-08-25 第二輪複審 P2-4 補強）：
-- 1. claim 加必填 p_expiry_before：post_date < p_expiry_before 的列一律
--    拒絕認領；若它還是 pending，順手轉 'failed' 終態（出窗的 pending
--    本來就永遠等不到生成，掛著只是積壓）。
-- 2. commit_practice_moment_image 加同一道守衛：**已認領、跨過 cutoff 的
--    晚到 commit 也被拒**——舊 worker 連讓出窗列變回 ready 的能力都沒有，
--    Edge 端在被拒後自刪剛上傳的物件（token 隔離路徑，見 moments_image_gen）。
--
-- 有了這道守衛，清理期間出窗列的 image 欄位組**只有 mark 自己能動**
-- （claim 拒絕、commit/release 需要 claim 發的 token、而 token 已不存在），
-- 「list 之後列被取代」在資料層構造上不可達；mark 端原有的
-- path + image_status='ready' + post_date < p_before 三條件維持不變，
-- 兩個方向的競態測試在 moments_images_migration_postgres_test.ts。
--
-- 簽名變更走 0824 的 overload 衛生範式。部署窗安全：claim 只被旗標開啟後
-- 的 Edge 呼叫，而旗標開啟排在本 migration 套用之後（rollout 順序見設計
-- 文件 §12，Eric 2026-08-25 拍板 migration 先行）。

DO $$
DECLARE
  v_unexpected TEXT;
BEGIN
  SELECT string_agg(p.oid::regprocedure::TEXT, ', ' ORDER BY p.oid::regprocedure::TEXT)
  INTO v_unexpected
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'claim_practice_moment_image'
    AND p.oid NOT IN (
      COALESCE(to_regprocedure(
        'public.claim_practice_moment_image(text,date,integer,text,uuid,integer,integer,boolean,integer,integer)'
      )::OID, 0::OID),
      COALESCE(to_regprocedure(
        'public.claim_practice_moment_image(text,date,integer,text,uuid,integer,integer,boolean,date,integer,integer)'
      )::OID, 0::OID)
    );

  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION
      'claim_practice_moment_image: unexpected overload(s): %',
      v_unexpected;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER
);

-- p_expiry_before 必填且插在 DEFAULT 參數之前（PostgreSQL 規定 DEFAULT 之後
-- 的參數必須全部有 DEFAULT）。呼叫端一律 named args，位置不影響相容。
CREATE OR REPLACE FUNCTION public.claim_practice_moment_image(
  p_profile_id       TEXT,
  p_post_date        DATE,
  p_slot             INTEGER,
  p_image_token      TEXT,
  p_user_id          UUID,
  p_minute_limit     INTEGER,
  p_daily_limit      INTEGER,
  p_count_user_usage BOOLEAN,
  p_expiry_before    DATE,
  p_max_attempts     INTEGER DEFAULT 2,
  p_lease_seconds    INTEGER DEFAULT 180
)
RETURNS TABLE(
  claimed       BOOLEAN,
  token         TEXT,
  attempt_count SMALLINT,
  body          TEXT,
  theme_id      TEXT
)
LANGUAGE plpgsql
-- Safe for statement-by-statement migration runners: PUBLIC may receive the
-- default EXECUTE privilege at CREATE time, so keep caller privileges until the
-- REVOKE/GRANT block has completed.  The final ALTER below enables definer mode.
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row      public.practice_moment_posts%ROWTYPE;
  v_attempts SMALLINT;
BEGIN
  IF p_profile_id IS NULL
     OR char_length(p_profile_id) = 0
     OR char_length(p_profile_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_moment_image: invalid p_profile_id';
  END IF;
  IF p_post_date IS NULL THEN
    RAISE EXCEPTION 'claim_practice_moment_image: p_post_date is required';
  END IF;
  IF p_slot IS NULL OR p_slot < 0 OR p_slot > 1 THEN
    RAISE EXCEPTION 'claim_practice_moment_image: invalid p_slot';
  END IF;
  IF p_image_token IS NULL
     OR char_length(p_image_token) = 0
     OR char_length(p_image_token) > 64 THEN
    RAISE EXCEPTION 'claim_practice_moment_image: invalid p_image_token';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_practice_moment_image: p_user_id is required';
  END IF;
  IF p_minute_limit IS NULL OR p_minute_limit <= 0 THEN
    RAISE EXCEPTION 'claim_practice_moment_image: invalid p_minute_limit';
  END IF;
  IF p_daily_limit IS NULL OR p_daily_limit <= 0 THEN
    RAISE EXCEPTION 'claim_practice_moment_image: invalid p_daily_limit';
  END IF;
  IF p_count_user_usage IS NULL THEN
    RAISE EXCEPTION 'claim_practice_moment_image: p_count_user_usage is required';
  END IF;
  IF p_expiry_before IS NULL THEN
    RAISE EXCEPTION 'claim_practice_moment_image: p_expiry_before is required';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts <= 0 OR p_max_attempts > 2 THEN
    RAISE EXCEPTION 'claim_practice_moment_image: invalid p_max_attempts';
  END IF;
  IF p_lease_seconds IS NULL OR p_lease_seconds <= 0 THEN
    RAISE EXCEPTION 'claim_practice_moment_image: invalid p_lease_seconds';
  END IF;

  SELECT mp.* INTO v_row
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  FOR UPDATE;

  -- 第 1 格：列不存在，或文字還沒 ready——圖永遠跟在文字後面。
  IF NOT FOUND OR v_row.status <> 'ready' THEN
    claimed := FALSE;
    token := NULL;
    attempt_count := NULL;
    body := NULL;
    theme_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 出窗守衛（清理競態圍籬）：出窗的列永不再認領；殘留的 pending 順手
  -- 收成 'failed' 終態（本來就永遠等不到生成）。
  IF v_row.post_date < p_expiry_before THEN
    IF v_row.image_status = 'pending' THEN
      UPDATE public.practice_moment_posts AS mp
      SET image_status = 'failed',
          image_token = NULL,
          updated_at = now()
      WHERE mp.profile_id = p_profile_id
        AND mp.post_date = p_post_date
        AND mp.slot = p_slot::SMALLINT;
    END IF;
    claimed := FALSE;
    token := NULL;
    attempt_count := v_row.image_attempts;
    body := NULL;
    theme_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 第 2 格：不在 pending 的一律不動（none／ready／failed／expired）。
  IF v_row.image_status <> 'pending' THEN
    claimed := FALSE;
    token := NULL;
    attempt_count := v_row.image_attempts;
    body := NULL;
    theme_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 第 3 格：別的 worker 正在生圖，租約仍有效。
  IF v_row.image_token IS NOT NULL
     AND v_row.image_reserved_at IS NOT NULL
     AND v_row.image_reserved_at > now() - make_interval(secs => p_lease_seconds) THEN
    claimed := FALSE;
    token := NULL;
    attempt_count := v_row.image_attempts;
    body := NULL;
    theme_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 第 5 格：image_attempts 已達上限 → 'failed' 終態（永久純文字）。
  IF v_row.image_attempts >= p_max_attempts THEN
    UPDATE public.practice_moment_posts AS mp
    SET image_status = 'failed',
        image_token = NULL,
        updated_at = now()
    WHERE mp.profile_id = p_profile_id
      AND mp.post_date = p_post_date
      AND mp.slot = p_slot::SMALLINT;

    claimed := FALSE;
    token := NULL;
    attempt_count := v_row.image_attempts;
    body := NULL;
    theme_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 第 4 格：接手。per-user 額度在同一筆交易內；超限 RAISE 整筆 rollback，
  -- 既不換 token 也不增加 image_attempts。
  IF p_count_user_usage THEN
    PERFORM public.increment_model_usage(
      p_user_id, 'practice_moment_image', p_minute_limit, p_daily_limit
    );
  END IF;
  UPDATE public.practice_moment_posts AS mp
  SET image_attempts = v_row.image_attempts + 1,
      image_token = p_image_token,
      image_reserved_at = now(),
      updated_at = now()
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  RETURNING mp.image_attempts INTO v_attempts;

  claimed := TRUE;
  token := p_image_token;
  attempt_count := v_attempts;
  body := v_row.body;
  theme_id := v_row.theme_id;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- commit_practice_moment_image：加同一道出窗守衛（晚到 commit 拒絕）
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_unexpected TEXT;
BEGIN
  SELECT string_agg(p.oid::regprocedure::TEXT, ', ' ORDER BY p.oid::regprocedure::TEXT)
  INTO v_unexpected
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'commit_practice_moment_image'
    AND p.oid NOT IN (
      COALESCE(to_regprocedure(
        'public.commit_practice_moment_image(text,date,integer,text,text)'
      )::OID, 0::OID),
      COALESCE(to_regprocedure(
        'public.commit_practice_moment_image(text,date,integer,text,text,date)'
      )::OID, 0::OID)
    );

  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION
      'commit_practice_moment_image: unexpected overload(s): %',
      v_unexpected;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.commit_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT
);

CREATE OR REPLACE FUNCTION public.commit_practice_moment_image(
  p_profile_id    TEXT,
  p_post_date     DATE,
  p_slot          INTEGER,
  p_image_token   TEXT,
  p_image_path    TEXT,
  p_expiry_before DATE
)
RETURNS TABLE(committed BOOLEAN)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row public.practice_moment_posts%ROWTYPE;
BEGIN
  IF p_profile_id IS NULL
     OR char_length(p_profile_id) = 0
     OR char_length(p_profile_id) > 64 THEN
    RAISE EXCEPTION 'commit_practice_moment_image: invalid p_profile_id';
  END IF;
  IF p_post_date IS NULL THEN
    RAISE EXCEPTION 'commit_practice_moment_image: p_post_date is required';
  END IF;
  IF p_slot IS NULL OR p_slot < 0 OR p_slot > 1 THEN
    RAISE EXCEPTION 'commit_practice_moment_image: invalid p_slot';
  END IF;
  IF p_image_token IS NULL
     OR char_length(p_image_token) = 0
     OR char_length(p_image_token) > 64 THEN
    RAISE EXCEPTION 'commit_practice_moment_image: invalid p_image_token';
  END IF;
  IF p_image_path IS NULL
     OR char_length(p_image_path) = 0
     OR char_length(p_image_path) > 200 THEN
    RAISE EXCEPTION 'commit_practice_moment_image: invalid p_image_path';
  END IF;
  IF p_expiry_before IS NULL THEN
    RAISE EXCEPTION 'commit_practice_moment_image: p_expiry_before is required';
  END IF;

  SELECT mp.* INTO v_row
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  FOR UPDATE;

  -- token fencing ＋ 出窗守衛：被接手的舊 worker、遲到的重複回應、以及
  -- 「認領後才跨過 cutoff 的晚到 commit」，一律回 FALSE 而不覆寫。
  IF NOT FOUND
     OR v_row.status <> 'ready'
     OR v_row.image_status <> 'pending'
     OR v_row.post_date < p_expiry_before
     OR v_row.image_token IS NULL
     OR v_row.image_token IS DISTINCT FROM p_image_token THEN
    committed := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE public.practice_moment_posts AS mp
  SET image_status = 'ready',
      image_path = p_image_path,
      image_token = NULL,
      updated_at = now()
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT;

  committed := TRUE;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.commit_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT, DATE
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.commit_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT, DATE
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT, DATE
) TO service_role;
ALTER FUNCTION public.commit_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT, DATE
) SECURITY DEFINER;

COMMENT ON FUNCTION public.commit_practice_moment_image(TEXT, DATE, INTEGER, TEXT, TEXT, DATE)
IS 'Token-fenced commit of a stored generated image; a stale token, a replay, or a late commit that crossed the expiry cutoff returns FALSE and never overwrites.';

REVOKE ALL ON FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, DATE, INTEGER, INTEGER
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, DATE, INTEGER, INTEGER
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, DATE, INTEGER, INTEGER
) TO service_role;
ALTER FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, DATE, INTEGER, INTEGER
) SECURITY DEFINER;

COMMENT ON FUNCTION public.claim_practice_moment_image(TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, DATE, INTEGER, INTEGER)
IS 'Atomically leases one pending image job (same-transaction per-user usage; a rate-limit exception rolls the claim back). Rows dated before p_expiry_before can never be claimed again, which freezes expired rows during the sweep''s list-delete-mark window; a leftover expired pending row is finalized as failed.';

NOTIFY pgrst, 'reload schema';

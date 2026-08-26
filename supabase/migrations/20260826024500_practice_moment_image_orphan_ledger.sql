-- 生成配圖的孤兒帳本（PR #34 第四輪複審 P2-2）。
--
-- 要解的洞：Storage 物件的清理原本全靠 Edge 的 best effort——上傳 timeout
-- 的晚到自刪掛在一個 detached promise 上，commit 不確定態則刻意不刪。只要
-- Edge 實例被回收（waitUntil 結束、冷啟動、部署），那個物件就再也沒有人
-- 記得它存在。出窗 prefix 對帳是唯一兜底，而它只掃固定日期帶、又受 Storage
-- list 100 筆上限限制，零流量或大量殘留時可能永久漏掃。
--
-- 做法：把「我即將寫一個物件到這個路徑」記進**同一筆 claim 交易**。
--
--   claim  → array_append(image_orphan_paths, p_image_path)   （租約成立的同一交易）
--   commit → array_remove(image_orphan_paths, p_image_path)   （成功的同一交易）
--   其餘一切結局（失敗、release、不確定態、實例被回收）→ 紀錄留著
--
-- 於是「有物件但沒人引用」在資料層是可查詢的狀態，而不是靠 Edge 記得。
-- 清算走 list → 刪物件 → clear 三步（順序鐵則同主清掃：先刪物件後清帳），
-- 任何一步失敗，帳本原封不動，下一次 feed 請求自然重試——這才是**可持久
-- 重試的閉環**。物件不存在時的刪除是 no-op，重試冪等。
--
-- 為什麼帳本是欄位而不是新表：路徑天生屬於 (profile_id, post_date, slot)
-- 這一列，掛在列上就跟著既有的 token 圍籬與 FOR UPDATE 一起被序列化，
-- 不需要第二套併發推理。image_attempts ≤ 2 也順帶把陣列長度封頂。
--
-- 寬限期（p_grace_seconds，預設 600）：清算只碰**寬限期之外**的紀錄。一個
-- job 的最壞 wall clock 是場景 10s＋fal 30s＋下載 15s＋上傳 15s，租約只有
-- 180s；600s 之外還活著的 worker 不存在，因此清算不可能刪掉正在跑的 job
-- 即將 commit 的物件。第二道保險是 image_path 排除：已被引用的物件永不刪。
--
-- **本檔是新增的後續 migration，不是修改既有 migration。** 20260825120000
-- 與 20260825150000 一旦在任何環境套用過就是不可變的；claim 的簽名在這裡
-- 改變（多一個 p_image_path），所以用 DROP + CREATE 並前後各稽核一次
-- overload，維持 fail-closed。部署窗安全：claim／commit 只在
-- MOMENT_IMAGE_GEN_ENABLED=true 之後才會被呼叫，而旗標開啟排在所有
-- migration 套用之後（rollout 順序見設計文件 §12）。

-- ---------------------------------------------------------------------------
-- 帳本欄位
-- ---------------------------------------------------------------------------
ALTER TABLE public.practice_moment_posts
  ADD COLUMN IF NOT EXISTS image_orphan_paths TEXT[] NOT NULL DEFAULT '{}';

-- 長度封頂（縱深防禦）：一列最多 2 次 attempt，4 是給未來調整的餘裕。
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'practice_moment_image_orphan_paths_bounded'
      AND conrelid = 'public.practice_moment_posts'::regclass
  ) THEN
    ALTER TABLE public.practice_moment_posts
      ADD CONSTRAINT practice_moment_image_orphan_paths_bounded
      CHECK (cardinality(image_orphan_paths) <= 4);
  END IF;
END;
$$;

-- 清算的掃描樣式固定是「帳本非空、且租約時間夠舊」。
CREATE INDEX IF NOT EXISTS practice_moment_posts_image_orphan_idx
  ON public.practice_moment_posts (image_reserved_at)
  WHERE cardinality(image_orphan_paths) > 0;

-- ---------------------------------------------------------------------------
-- claim_practice_moment_image：簽名加 p_image_path，認領同交易記帳
-- ---------------------------------------------------------------------------
-- 前稽核：只容許「舊 10-arg」或「本檔的新 11-arg」存在，其他一律擋下。
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
        'public.claim_practice_moment_image(text,date,integer,text,text,uuid,integer,integer,boolean,integer,integer)'
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

CREATE OR REPLACE FUNCTION public.claim_practice_moment_image(
  p_profile_id       TEXT,
  p_post_date        DATE,
  p_slot             INTEGER,
  p_image_token      TEXT,
  p_image_path       TEXT,
  p_user_id          UUID,
  p_minute_limit     INTEGER,
  p_daily_limit      INTEGER,
  p_count_user_usage BOOLEAN,
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
  v_row           public.practice_moment_posts%ROWTYPE;
  v_attempts      SMALLINT;
  -- 台北日窗起點以**當下**計算（固定 +8 偏移，與 Edge time_context 同構；
  -- 13 = FEED_WINDOW_DAYS - 1）。不吃呼叫端 snapshot，跨午夜不失效。
  v_expiry_cutoff DATE := ((now() AT TIME ZONE INTERVAL '8 hours')::date - 13);
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
  -- 帳本路徑與 commit 的 p_image_path 同一道長度守門。
  IF p_image_path IS NULL
     OR char_length(p_image_path) = 0
     OR char_length(p_image_path) > 200 THEN
    RAISE EXCEPTION 'claim_practice_moment_image: invalid p_image_path';
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
  IF p_max_attempts IS NULL OR p_max_attempts <= 0 OR p_max_attempts > 2 THEN
    RAISE EXCEPTION 'claim_practice_moment_image: invalid p_max_attempts';
  END IF;
  -- commit 與孤兒清算都以 180s 作資料層安全邊界；claim 不得另傳一個較長
  -- 租約，否則仍可能出現「worker 合法、清算卻已可刪圖」的矛盾窗口。
  IF p_lease_seconds IS NULL OR p_lease_seconds <> 180 THEN
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
  IF v_row.post_date < v_expiry_cutoff THEN
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
  -- 既不換 token、不增加 image_attempts，帳本也不會留下這一筆。
  IF p_count_user_usage THEN
    PERFORM public.increment_model_usage(
      p_user_id, 'practice_moment_image', p_minute_limit, p_daily_limit
    );
  END IF;
  UPDATE public.practice_moment_posts AS mp
  SET image_attempts = v_row.image_attempts + 1,
      image_token = p_image_token,
      image_reserved_at = now(),
      -- 記帳與租約同一筆交易：租約成立的瞬間，這個路徑就有人記得了。
      image_orphan_paths = array_append(
        array_remove(mp.image_orphan_paths, p_image_path), p_image_path
      ),
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

-- 後稽核：fail-closed，只准剩下新的 11-arg。
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
        'public.claim_practice_moment_image(text,date,integer,text,text,uuid,integer,integer,boolean,integer,integer)'
      )::OID, 0::OID)
    );

  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION
      'claim_practice_moment_image: unexpected overload(s) after replace: %',
      v_unexpected;
  END IF;

  IF to_regprocedure(
    'public.claim_practice_moment_image(text,date,integer,text,text,uuid,integer,integer,boolean,integer,integer)'
  ) IS NULL THEN
    RAISE EXCEPTION 'claim_practice_moment_image: expected signature missing';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER
) TO service_role;
ALTER FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER
) SECURITY DEFINER;

-- ---------------------------------------------------------------------------
-- commit_practice_moment_image：成功的同一筆交易把帳本紀錄抹掉
-- ---------------------------------------------------------------------------
-- 簽名不變（5-arg），僅替換本體；overload 稽核維持 fail-closed。
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
      )::OID, 0::OID)
    );

  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION
      'commit_practice_moment_image: unexpected overload(s): %',
      v_unexpected;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.commit_practice_moment_image(
  p_profile_id  TEXT,
  p_post_date   DATE,
  p_slot        INTEGER,
  p_image_token TEXT,
  p_image_path  TEXT
)
RETURNS TABLE(committed BOOLEAN)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row           public.practice_moment_posts%ROWTYPE;
  v_expiry_cutoff DATE := ((now() AT TIME ZONE INTERVAL '8 hours')::date - 13);
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

  SELECT mp.* INTO v_row
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  FOR UPDATE;

  -- 第一道只做 token fencing；出窗收屍必須在租約判斷之前，否則同時「出窗
  -- ＋租約過期」的列會提早 RETURN，永遠留在 pending。
  IF NOT FOUND
     OR v_row.status <> 'ready'
     OR v_row.image_status <> 'pending'
     OR v_row.image_token IS NULL
     OR v_row.image_token IS DISTINCT FROM p_image_token THEN
    committed := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 出窗守衛（以**當下** cutoff 判定）：慢 worker 跨過台北午夜後的晚到
  -- commit 即使 token 有效也拒絕；同時把列收屍（pending → 'failed'、清
  -- token）——出窗列不會再被 feed 接手，不收就永遠掛在 pending。
  IF v_row.post_date < v_expiry_cutoff THEN
    UPDATE public.practice_moment_posts AS mp
    SET image_status = 'failed',
        image_token = NULL,
        updated_at = now()
    WHERE mp.profile_id = p_profile_id
      AND mp.post_date = p_post_date
      AND mp.slot = p_slot::SMALLINT;
    committed := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 第二道租約 fencing：即使 token 尚未輪替，超過 180 秒也不得 commit。
  -- 孤兒清算在寬限期後可能已刪掉該路徑；若仍允許過期 worker commit，
  -- 會留下 ready 指向 404。帳本刻意不動，留給 Edge 冪等清算。
  IF v_row.image_reserved_at IS NULL
     OR v_row.image_reserved_at <= now() - make_interval(secs => 180) THEN
    committed := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 成功：路徑從「可能是孤兒」升格為「被引用」，同一筆交易把帳本紀錄
  -- 抹掉。這一步讓清算永遠不可能刪到 ready 列指著的物件。
  UPDATE public.practice_moment_posts AS mp
  SET image_status = 'ready',
      image_path = p_image_path,
      image_token = NULL,
      image_orphan_paths = array_remove(mp.image_orphan_paths, p_image_path),
      updated_at = now()
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT;

  committed := TRUE;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.commit_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.commit_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT
) TO service_role;
ALTER FUNCTION public.commit_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, TEXT
) SECURITY DEFINER;

-- ---------------------------------------------------------------------------
-- 清算：list → （Edge 刪物件）→ clear
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_practice_moment_image_orphans(
  p_limit         INTEGER DEFAULT 20,
  p_grace_seconds INTEGER DEFAULT 600
)
RETURNS TABLE(orphan_path TEXT)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF p_limit IS NULL OR p_limit <= 0 OR p_limit > 100 THEN
    RAISE EXCEPTION 'list_practice_moment_image_orphans: invalid p_limit';
  END IF;
  IF p_grace_seconds IS NULL OR p_grace_seconds < 0 THEN
    RAISE EXCEPTION 'list_practice_moment_image_orphans: invalid p_grace_seconds';
  END IF;

  -- 兩道守門：
  -- 1. 寬限期——image_reserved_at 是最後一次認領的時間；有效寬限期永遠
  --    不短於 180s 租約，避免呼叫端傳 0 時刪到仍可合法 commit 的物件。
  --    production 傳 600s（最壞 wall clock < 90s），再多留一道緩衝。
  -- 2. 排除該列自己的 image_path——被 ready 列引用的物件永不列入清算，
  --    即使某個 bug 讓它留在帳本裡。
  RETURN QUERY
  SELECT t.path
  FROM public.practice_moment_posts AS mp
  CROSS JOIN LATERAL unnest(mp.image_orphan_paths) AS t(path)
  WHERE cardinality(mp.image_orphan_paths) > 0
    AND (
      mp.image_reserved_at IS NULL
      OR mp.image_reserved_at < now() - make_interval(
        secs => GREATEST(p_grace_seconds, 180)
      )
    )
    AND t.path IS DISTINCT FROM mp.image_path
  ORDER BY mp.image_reserved_at NULLS FIRST, t.path
  LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_practice_moment_image_orphans(
  p_paths TEXT[]
)
RETURNS TABLE(cleared_count INTEGER)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_cleared INTEGER := 0;
BEGIN
  IF p_paths IS NULL OR array_length(p_paths, 1) IS NULL THEN
    RAISE EXCEPTION 'clear_practice_moment_image_orphans: p_paths is required';
  END IF;
  IF array_length(p_paths, 1) > 100 THEN
    RAISE EXCEPTION 'clear_practice_moment_image_orphans: too many p_paths';
  END IF;

  -- 只清帳本，不動任何狀態欄位：清算的語義是「這個路徑已經沒有物件了」，
  -- 與貼文本身的生命週期無關。列永不 DELETE（D6）。
  UPDATE public.practice_moment_posts AS mp
  SET image_orphan_paths = COALESCE(
        (SELECT array_agg(u.x ORDER BY u.ord)
           FROM unnest(mp.image_orphan_paths) WITH ORDINALITY AS u(x, ord)
          WHERE NOT (u.x = ANY (p_paths))),
        '{}'::TEXT[]
      ),
      updated_at = now()
  WHERE mp.image_orphan_paths && p_paths;
  GET DIAGNOSTICS v_cleared = ROW_COUNT;

  cleared_count := v_cleared;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.list_practice_moment_image_orphans(INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_practice_moment_image_orphans(INTEGER, INTEGER) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_practice_moment_image_orphans(INTEGER, INTEGER) TO service_role;
ALTER FUNCTION public.list_practice_moment_image_orphans(INTEGER, INTEGER) SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.clear_practice_moment_image_orphans(TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clear_practice_moment_image_orphans(TEXT[]) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clear_practice_moment_image_orphans(TEXT[]) TO service_role;
ALTER FUNCTION public.clear_practice_moment_image_orphans(TEXT[]) SECURITY DEFINER;

COMMENT ON COLUMN public.practice_moment_posts.image_orphan_paths
IS 'Durable ledger of storage object keys this row may have written. A key is appended in the same transaction as the image claim and removed in the same transaction as a successful commit; anything left behind is reconciled by list/clear_practice_moment_image_orphans.';
COMMENT ON FUNCTION public.claim_practice_moment_image(TEXT, DATE, INTEGER, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER)
IS 'Atomically leases one pending image job, records the object key it may write in the same transaction, and increments both image_attempts and per-user practice_moment_image usage. A rate-limit exception rolls the entire claim back.';
COMMENT ON FUNCTION public.commit_practice_moment_image(TEXT, DATE, INTEGER, TEXT, TEXT)
IS 'Token- and lease-fenced commit of a stored generated image. A stale token or expired lease returns FALSE and never creates a ready row that may point at an already reconciled object.';
COMMENT ON FUNCTION public.list_practice_moment_image_orphans(INTEGER, INTEGER)
IS 'Lists storage object keys that were claimed but never committed, older than a grace period that is clamped to at least one image lease, so the Edge can delete the objects before clearing the ledger. Never lists a key referenced by its own row.';
COMMENT ON FUNCTION public.clear_practice_moment_image_orphans(TEXT[])
IS 'Clears reconciled keys from the orphan ledger after their storage objects were deleted. Touches no lifecycle column and never deletes rows.';

NOTIFY pgrst, 'reload schema';

-- 練習室模擬社群動態：生成配圖資料層（PR-2，純加法）。
--
-- 設計來源：docs/plans/2026-08-25-practice-moments-generated-images.md §6。
-- 圖與文字是兩段獨立的生命週期：文字沿用 reserve/commit/release（attempts ≤ 3），
-- 圖用本檔的 claim/commit/release image（image_attempts ≤ 2）。兩組計數完全獨立：
-- 文字重試不燒圖額度，圖失敗不碰文字。
--
-- 成本上界的 DB 側：
--   unique(profile_id, post_date, slot) × CHECK (slot BETWEEN 0 AND 1)
--   × CHECK (image_attempts BETWEEN 0 AND 2) → 每 profile-day 最多 4 次生圖呼叫。
--   乘上 Edge 的 100 角色 allowlist 與「僅 wantsImage slot 進入 pending」，
--   實際量遠低於此（估 ~11 張/天）。per-user 面由 claim 在同一交易內以
--   scope 'practice_moment_image' 計數，超限 RAISE 整筆 rollback。
--
-- 鐵則沿用文字路徑：絕不 DELETE 列（D6：feed 14 天、DB 永久保留——過期只刪
-- Storage 物件並把 image_status 標成 'expired'）、絕不動 body/attempts/status、
-- 失敗絕不落半成品（'failed' 是終態＝該則永久純文字，no-canned 的圖片版）。
--
-- 契約測試：
--   supabase/functions/practice-chat/moments_images_migration_postgres_test.ts
--   supabase/functions/practice-chat/moments_images_migration_source_test.ts

-- ---------------------------------------------------------------------------
-- 欄位（純加法；重跑安全）
-- ---------------------------------------------------------------------------
-- image_status 狀態機：
--   none（純文字或 bundled 素材貼文）
--   → pending（文字 commit 時 p_wants_image=TRUE）
--   → ready（生圖已轉存 Storage，image_path 指向物件）
--   → expired（出 14 天窗，物件已刪、path 留作審計）
--   pending → failed（image_attempts 燒完；終態＝永久純文字）
ALTER TABLE public.practice_moment_posts
  ADD COLUMN IF NOT EXISTS image_status TEXT NOT NULL DEFAULT 'none'
    CHECK (image_status IN ('none', 'pending', 'ready', 'failed', 'expired')),
  ADD COLUMN IF NOT EXISTS image_path TEXT
    CHECK (image_path IS NULL OR char_length(image_path) BETWEEN 1 AND 200),
  ADD COLUMN IF NOT EXISTS image_attempts SMALLINT NOT NULL DEFAULT 0
    CHECK (image_attempts BETWEEN 0 AND 2),
  ADD COLUMN IF NOT EXISTS image_token TEXT,
  ADD COLUMN IF NOT EXISTS image_reserved_at TIMESTAMPTZ;

-- ready 一定有物件可畫（no-canned 的圖片版：不存在「ready 但沒圖」的空殼）。
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'practice_moment_image_ready_has_path'
      AND conrelid = 'public.practice_moment_posts'::regclass
  ) THEN
    ALTER TABLE public.practice_moment_posts
      ADD CONSTRAINT practice_moment_image_ready_has_path
      CHECK (image_status <> 'ready' OR image_path IS NOT NULL);
  END IF;
END;
$$;

-- 機會式清掃的掃描樣式固定是「image_status='ready' 且 post_date 出窗」。
CREATE INDEX IF NOT EXISTS practice_moment_posts_image_expiry_idx
  ON public.practice_moment_posts (post_date)
  WHERE image_status = 'ready';

-- ---------------------------------------------------------------------------
-- Storage bucket（public：無人物 AI 場景圖、全域共用、零使用者資料）
-- ---------------------------------------------------------------------------
-- 寫入僅 service_role（經 Edge 的 Storage API，繞過 RLS）；讀取走 public URL。
-- 包在 storage schema 存在檢查裡：PGlite 契約測試直接 exec 本檔，測試環境
-- 沒有 Supabase 的 storage schema，這一段在那裡必須是 no-op。
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'storage' AND table_name = 'buckets'
  ) THEN
    INSERT INTO storage.buckets (id, name, public)
    VALUES ('practice-moment-images', 'practice-moment-images', TRUE)
    ON CONFLICT (id) DO NOTHING;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- commit_practice_moment_post：加 p_wants_image（overload 衛生比照 20260824063344）
-- ---------------------------------------------------------------------------
-- Fail closed before touching either expected overload.  Production has the
-- 7-argument shape from 20260822120000; a freshly rebuilt database may already
-- have the new 8-argument shape.  Any third shape means catalog drift.
DO $$
DECLARE
  v_unexpected TEXT;
BEGIN
  SELECT string_agg(p.oid::regprocedure::TEXT, ', ' ORDER BY p.oid::regprocedure::TEXT)
  INTO v_unexpected
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'commit_practice_moment_post'
    AND p.oid NOT IN (
      COALESCE(to_regprocedure(
        'public.commit_practice_moment_post(text,date,integer,text,text,text,text)'
      )::OID, 0::OID),
      COALESCE(to_regprocedure(
        'public.commit_practice_moment_post(text,date,integer,text,text,text,text,boolean)'
      )::OID, 0::OID)
    );

  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION
      'commit_practice_moment_post: unexpected overload(s): %',
      v_unexpected;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.commit_practice_moment_post(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, TEXT
);

-- 部署窗相容：既部署的 Edge 以 named params 呼叫且不帶 p_wants_image，
-- 吃 DEFAULT FALSE → 行為與舊版完全相同。
CREATE OR REPLACE FUNCTION public.commit_practice_moment_post(
  p_profile_id       TEXT,
  p_post_date        DATE,
  p_slot             INTEGER,
  p_generation_token TEXT,
  p_body             TEXT,
  p_image_id         TEXT DEFAULT NULL,
  p_model            TEXT DEFAULT NULL,
  p_wants_image      BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(committed BOOLEAN)
LANGUAGE plpgsql
-- Safe for statement-by-statement migration runners: PUBLIC may receive the
-- default EXECUTE privilege at CREATE time, so keep caller privileges until the
-- REVOKE/GRANT block has completed.  The final ALTER below enables definer mode.
SECURITY INVOKER
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
  IF p_wants_image IS NULL THEN
    RAISE EXCEPTION 'commit_practice_moment_post: p_wants_image is required';
  END IF;
  -- 生成圖與 catalog 圖互斥：wants_image 走生成管線（image_id 必為 NULL），
  -- catalog／自拍 sentinel 走 image_id（wants_image 必為 FALSE）。兩者同時出現
  -- 代表呼叫端邏輯壞了，寧可炸也不落一筆歧義列。
  IF p_wants_image AND p_image_id IS NOT NULL THEN
    RAISE EXCEPTION 'commit_practice_moment_post: p_wants_image excludes p_image_id';
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
      image_status = CASE WHEN p_wants_image THEN 'pending' ELSE 'none' END,
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
-- list_practice_moment_posts：回傳表加 image_status／image_path
-- ---------------------------------------------------------------------------
-- return type 變更必須 DROP + CREATE；先 fail-closed 稽核唯一預期的 shape。
DO $$
DECLARE
  v_unexpected TEXT;
BEGIN
  SELECT string_agg(p.oid::regprocedure::TEXT, ', ' ORDER BY p.oid::regprocedure::TEXT)
  INTO v_unexpected
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'list_practice_moment_posts'
    AND p.oid NOT IN (
      COALESCE(to_regprocedure(
        'public.list_practice_moment_posts(text[],date)'
      )::OID, 0::OID)
    );

  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION
      'list_practice_moment_posts: unexpected overload(s): %',
      v_unexpected;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.list_practice_moment_posts(TEXT[], DATE);

-- 既部署的 Edge 只讀已知欄位，多出的兩欄無害（部署窗相容）。
CREATE OR REPLACE FUNCTION public.list_practice_moment_posts(
  p_profile_ids TEXT[],
  p_since       DATE
)
RETURNS TABLE(
  profile_id   TEXT,
  post_date    DATE,
  slot         SMALLINT,
  day_part     TEXT,
  theme_id     TEXT,
  body         TEXT,
  image_id     TEXT,
  image_status TEXT,
  image_path   TEXT,
  created_at   TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
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
         mp.image_status,
         mp.image_path,
         mp.created_at
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = ANY (p_profile_ids)
    AND mp.post_date >= p_since
    AND mp.status = 'ready'
  ORDER BY mp.post_date DESC, mp.profile_id, mp.slot;
END;
$$;

-- ---------------------------------------------------------------------------
-- claim_practice_moment_image：生圖 job 的六態轉移表（鏡像 reserve）
-- ---------------------------------------------------------------------------
-- 進入時列狀態                                                    動作                        結果
-- 列不存在／status <> 'ready'（文字還沒好）                        不動                        ❌ 拒絕
-- image_status <> 'pending'（none／ready／failed／expired）        不動                        ❌ 拒絕
-- pending + image_token 非 NULL + 租約未逾時                       不動                        ❌ 拒絕
-- pending +（token IS NULL 或租約逾時）+ image_attempts < 上限      attempts+1、換發 token       ✅ 放行
-- pending +（token IS NULL 或租約逾時）+ image_attempts >= 上限     轉 'failed'、清 token        ❌ 拒絕
--
-- 與 reserve 相同的兩個坑，這裡同樣成立（各有契約測試釘死）：
--   1. 首次認領就 image_attempts+1（worker 中途死掉也算用掉一次，否則 crash
--      loop 無界）。本函式沒有 INSERT 分支——pending 列由 commit 建立、
--      image_attempts 從 0 起算，首次 UPDATE 到 1。
--   2. image_token IS NULL 是獨立放行分支：被 release 的列不必等租約逾時。
--
-- 回傳連同 body／theme_id：生圖 prompt 的兩個輸入，省呼叫端一次讀。
CREATE OR REPLACE FUNCTION public.claim_practice_moment_image(
  p_profile_id       TEXT,
  p_post_date        DATE,
  p_slot             INTEGER,
  p_image_token      TEXT,
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
-- commit_practice_moment_image：只有持有當前 image_token 的 worker 能標 ready
-- ---------------------------------------------------------------------------
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

  SELECT mp.* INTO v_row
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  FOR UPDATE;

  -- token fencing：被接手的舊 worker、或遲到的重複回應，一律回 FALSE 而不覆寫。
  IF NOT FOUND
     OR v_row.status <> 'ready'
     OR v_row.image_status <> 'pending'
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

-- ---------------------------------------------------------------------------
-- release_practice_moment_image：生圖失敗時交還租約
-- ---------------------------------------------------------------------------
-- 三條鐵則（鏡像 release_practice_moment_slot）：
--   絕不 DELETE 列、絕不動 body／attempts／status、絕不回收 image_attempts。
CREATE OR REPLACE FUNCTION public.release_practice_moment_image(
  p_profile_id   TEXT,
  p_post_date    DATE,
  p_slot         INTEGER,
  p_image_token  TEXT,
  p_max_attempts INTEGER DEFAULT 2
)
RETURNS TABLE(released BOOLEAN)
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
    RAISE EXCEPTION 'release_practice_moment_image: invalid p_profile_id';
  END IF;
  IF p_post_date IS NULL THEN
    RAISE EXCEPTION 'release_practice_moment_image: p_post_date is required';
  END IF;
  IF p_slot IS NULL OR p_slot < 0 OR p_slot > 1 THEN
    RAISE EXCEPTION 'release_practice_moment_image: invalid p_slot';
  END IF;
  IF p_image_token IS NULL
     OR char_length(p_image_token) = 0
     OR char_length(p_image_token) > 64 THEN
    RAISE EXCEPTION 'release_practice_moment_image: invalid p_image_token';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts <= 0 OR p_max_attempts > 2 THEN
    RAISE EXCEPTION 'release_practice_moment_image: invalid p_max_attempts';
  END IF;

  SELECT mp.* INTO v_row
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  FOR UPDATE;

  IF NOT FOUND
     OR v_row.status <> 'ready'
     OR v_row.image_status <> 'pending'
     OR v_row.image_token IS NULL
     OR v_row.image_token IS DISTINCT FROM p_image_token THEN
    released := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE public.practice_moment_posts AS mp
  SET image_status = CASE
        WHEN v_row.image_attempts >= p_max_attempts THEN 'failed'
        ELSE 'pending'
      END,
      image_token = NULL,
      updated_at = now()
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT;

  released := TRUE;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- 機會式清掃：列出出窗的 ready 圖 → Edge 刪 Storage 物件 → 標 expired
-- ---------------------------------------------------------------------------
-- 順序鐵則在 Edge 端：先刪物件、後標記列。標記失敗下輪重掃重刪（Storage 刪除
-- 冪等）；反過來會製造掃不到的孤兒。pending 出窗列沒有物件可刪，不在掃描範圍。
CREATE OR REPLACE FUNCTION public.list_expired_practice_moment_images(
  p_before DATE,
  p_limit  INTEGER
)
RETURNS TABLE(
  profile_id TEXT,
  post_date  DATE,
  slot       SMALLINT,
  image_path TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF p_before IS NULL THEN
    RAISE EXCEPTION 'list_expired_practice_moment_images: p_before is required';
  END IF;
  IF p_limit IS NULL OR p_limit <= 0 OR p_limit > 100 THEN
    RAISE EXCEPTION 'list_expired_practice_moment_images: invalid p_limit';
  END IF;

  RETURN QUERY
  SELECT mp.profile_id,
         mp.post_date,
         mp.slot,
         mp.image_path
  FROM public.practice_moment_posts AS mp
  WHERE mp.image_status = 'ready'
    AND mp.post_date < p_before
  ORDER BY mp.post_date, mp.profile_id, mp.slot
  LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_practice_moment_images_expired(
  p_before DATE,
  p_paths  TEXT[]
)
RETURNS TABLE(marked_count INTEGER)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_marked INTEGER := 0;
BEGIN
  IF p_before IS NULL THEN
    RAISE EXCEPTION 'mark_practice_moment_images_expired: p_before is required';
  END IF;
  IF p_paths IS NULL OR array_length(p_paths, 1) IS NULL THEN
    RAISE EXCEPTION 'mark_practice_moment_images_expired: p_paths is required';
  END IF;
  IF array_length(p_paths, 1) > 100 THEN
    RAISE EXCEPTION 'mark_practice_moment_images_expired: too many p_paths';
  END IF;

  -- image_path 是決定論 key（<post_date>/<profile_id>_<slot>.<ext>），每列唯一。
  -- post_date < p_before 是第二道保險：呼叫端傳錯 path 也刪不到窗內的圖。
  -- 'expired' 保留 image_path 作審計與冪等重刪；列永不 DELETE（D6）。
  UPDATE public.practice_moment_posts AS mp
  SET image_status = 'expired',
      image_token = NULL,
      updated_at = now()
  WHERE mp.image_path = ANY (p_paths)
    AND mp.image_status = 'ready'
    AND mp.post_date < p_before;
  GET DIAGNOSTICS v_marked = ROW_COUNT;

  marked_count := v_marked;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- 權限：一律 service_role only（client 永遠經 Edge）
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.commit_practice_moment_post(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.commit_practice_moment_post(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_practice_moment_post(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN
) TO service_role;
ALTER FUNCTION public.commit_practice_moment_post(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN
) SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.list_practice_moment_posts(TEXT[], DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_practice_moment_posts(TEXT[], DATE) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_practice_moment_posts(TEXT[], DATE) TO service_role;
ALTER FUNCTION public.list_practice_moment_posts(TEXT[], DATE) SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER
) TO service_role;
ALTER FUNCTION public.claim_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER
) SECURITY DEFINER;

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

REVOKE ALL ON FUNCTION public.release_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, INTEGER
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.release_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, INTEGER
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, INTEGER
) TO service_role;
ALTER FUNCTION public.release_practice_moment_image(
  TEXT, DATE, INTEGER, TEXT, INTEGER
) SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.list_expired_practice_moment_images(DATE, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_expired_practice_moment_images(DATE, INTEGER) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_expired_practice_moment_images(DATE, INTEGER) TO service_role;
ALTER FUNCTION public.list_expired_practice_moment_images(DATE, INTEGER) SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.mark_practice_moment_images_expired(DATE, TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_practice_moment_images_expired(DATE, TEXT[]) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_practice_moment_images_expired(DATE, TEXT[]) TO service_role;
ALTER FUNCTION public.mark_practice_moment_images_expired(DATE, TEXT[]) SECURITY DEFINER;

COMMENT ON COLUMN public.practice_moment_posts.image_status
IS 'Generated-image lifecycle: none (text-only or catalog image), pending (awaiting generation), ready (object stored at image_path), failed (attempts exhausted, terminal text-only), expired (object deleted after the feed window; path kept for audit).';
COMMENT ON FUNCTION public.claim_practice_moment_image(TEXT, DATE, INTEGER, TEXT, UUID, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER)
IS 'Atomically leases one pending image job and, only for a successful claim, increments both image_attempts and per-user practice_moment_image usage in the same transaction. A rate-limit exception rolls the entire claim back.';
COMMENT ON FUNCTION public.commit_practice_moment_image(TEXT, DATE, INTEGER, TEXT, TEXT)
IS 'Token-fenced commit of a stored generated image; a stale token returns FALSE and never overwrites.';
COMMENT ON FUNCTION public.release_practice_moment_image(TEXT, DATE, INTEGER, TEXT, INTEGER)
IS 'Token-fenced release after a failed image generation. Never deletes the row, never touches body or text attempts, never refunds image_attempts.';
COMMENT ON FUNCTION public.list_expired_practice_moment_images(DATE, INTEGER)
IS 'Lists ready generated images older than the feed window so the Edge can delete their storage objects before marking them expired.';
COMMENT ON FUNCTION public.mark_practice_moment_images_expired(DATE, TEXT[])
IS 'Marks swept generated images as expired after their storage objects were deleted. Keeps image_path for audit; never deletes rows.';

NOTIFY pgrst, 'reload schema';

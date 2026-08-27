-- 動態牆 freshness 保底：一次唯讀判斷今天的既有 slot 是否值得再試。
--
-- 目的不是取代 reserve，而是避免 stale feed 每次開啟都對已 ready、已耗盡、
-- 或有效租約中的列重複做 FOR UPDATE。查詢與 reserve 之間仍可能有競態，
-- 因此 Edge 後續一定要再走 reserve；attempts 與 per-user usage 的原子 gate
-- 完全不變。

CREATE OR REPLACE FUNCTION public.list_practice_moment_slot_states(
  p_profile_ids   TEXT[],
  p_post_date     DATE,
  p_max_attempts  INTEGER DEFAULT 3,
  p_lease_seconds INTEGER DEFAULT 120
)
RETURNS TABLE(
  profile_id TEXT,
  slot       SMALLINT,
  claimable  BOOLEAN
)
LANGUAGE plpgsql
STABLE
-- statement-by-statement runner 安全：先用 caller 權限建立，完成 REVOKE 後
-- 才在檔尾切成 definer，避免 migration 中途留下 PUBLIC 可執行的 definer RPC。
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF p_profile_ids IS NULL OR array_length(p_profile_ids, 1) IS NULL THEN
    RETURN;
  END IF;
  IF array_length(p_profile_ids, 1) > 100 THEN
    RAISE EXCEPTION
      'list_practice_moment_slot_states: too many p_profile_ids';
  END IF;
  IF p_post_date IS NULL THEN
    RAISE EXCEPTION
      'list_practice_moment_slot_states: p_post_date is required';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts <= 0 OR p_max_attempts > 3 THEN
    RAISE EXCEPTION
      'list_practice_moment_slot_states: invalid p_max_attempts';
  END IF;
  IF p_lease_seconds IS NULL OR p_lease_seconds <= 0 THEN
    RAISE EXCEPTION
      'list_practice_moment_slot_states: invalid p_lease_seconds';
  END IF;

  RETURN QUERY
  SELECT mp.profile_id,
         mp.slot,
         CASE
           WHEN mp.status = 'reserved'
             AND mp.attempts < p_max_attempts
             AND (
               mp.generation_token IS NULL
               OR mp.reserved_at <= now() -
                 make_interval(secs => p_lease_seconds)
             )
             THEN TRUE
           ELSE FALSE
         END AS claimable
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = ANY (p_profile_ids)
    AND mp.post_date = p_post_date
  ORDER BY mp.profile_id, mp.slot;
END;
$$;

REVOKE ALL ON FUNCTION public.list_practice_moment_slot_states(
  TEXT[], DATE, INTEGER, INTEGER
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_practice_moment_slot_states(
  TEXT[], DATE, INTEGER, INTEGER
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_practice_moment_slot_states(
  TEXT[], DATE, INTEGER, INTEGER
) TO service_role;
ALTER FUNCTION public.list_practice_moment_slot_states(
  TEXT[], DATE, INTEGER, INTEGER
) SECURITY DEFINER;

COMMENT ON FUNCTION public.list_practice_moment_slot_states(
  TEXT[], DATE, INTEGER, INTEGER
) IS
  'Service-role-only read hint for freshness fill. Atomic reserve remains authoritative.';

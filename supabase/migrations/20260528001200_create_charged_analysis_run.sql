-- Atomic charge + run insert for two-stage analyze (P1 from Codex Phase 0 review).
--
-- Why this RPC exists:
--   The naive flow is `INSERT analysis_runs(charged=false) → increment_usage →
--   UPDATE charged=true`. Three separate statements give two partial-failure
--   windows that hurt the user:
--     (a) increment_usage commits but the UPDATE never runs (Edge crashes /
--         network drops the response): user is charged but charged=false,
--         so the full path returns RUN_NOT_CHARGED forever.
--     (b) increment_usage commits but client sees error and the rollback
--         deleteRun runs: row gone, quota still ticked → "扣了卻沒分析".
--
-- Doing everything inside a single PL/pgSQL function body wraps the work in
-- an implicit transaction. RAISE EXCEPTION at any step rolls back both the
-- increment_usage call (which is just an UPDATE) and the analysis_runs INSERT.
-- The caller either gets back a row with charged=TRUE and the user's quota
-- ticked, or gets back nothing and the quota stays untouched.

CREATE OR REPLACE FUNCTION public.create_charged_analysis_run(
  p_user_id            UUID,
  p_conversation_hash  TEXT,
  p_quick_result       JSONB,
  p_request_context    JSONB    DEFAULT NULL,
  p_charge_quota       BOOLEAN  DEFAULT TRUE,
  p_message_count      INTEGER  DEFAULT 1
)
RETURNS public.analysis_runs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.analysis_runs;
BEGIN
  -- Input gating. SECURITY DEFINER runs as the function owner so we cannot
  -- rely on RLS to catch garbage input — be explicit.
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'create_charged_analysis_run: p_user_id is required';
  END IF;
  IF p_conversation_hash IS NULL OR length(p_conversation_hash) = 0 THEN
    RAISE EXCEPTION 'create_charged_analysis_run: p_conversation_hash is required';
  END IF;
  IF p_quick_result IS NULL THEN
    RAISE EXCEPTION 'create_charged_analysis_run: p_quick_result is required';
  END IF;
  IF p_charge_quota AND (p_message_count IS NULL OR p_message_count <= 0) THEN
    RAISE EXCEPTION 'create_charged_analysis_run: p_message_count must be positive when charging';
  END IF;

  -- (1) Charge quota if applicable. increment_usage RAISES on bad input and
  -- does its own UPDATE inside the same transaction. If it throws, the whole
  -- function rolls back and step (2) below never runs.
  --
  -- p_charge_quota=false is the explicit branch for test accounts (Codex
  -- requested this be explicit rather than an Edge-side `if`).
  IF p_charge_quota THEN
    PERFORM public.increment_usage(p_user_id, p_message_count);
  END IF;

  -- (2) Insert the run row already-charged. There is no separate UPDATE
  -- step — `charged` is set during INSERT so the row never exists in an
  -- "uncharged" intermediate state visible to other queries.
  INSERT INTO public.analysis_runs (
    user_id,
    conversation_hash,
    quick_result,
    request_context,
    charged
  )
  VALUES (
    p_user_id,
    p_conversation_hash,
    p_quick_result,
    p_request_context,
    TRUE
  )
  RETURNING * INTO result;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_charged_analysis_run(
  UUID, TEXT, JSONB, JSONB, BOOLEAN, INTEGER
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_charged_analysis_run(
  UUID, TEXT, JSONB, JSONB, BOOLEAN, INTEGER
) TO service_role;

NOTIFY pgrst, 'reload schema';

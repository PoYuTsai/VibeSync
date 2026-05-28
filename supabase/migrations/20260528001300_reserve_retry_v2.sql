-- Defense-in-depth on reserve_analysis_run_retry (P2 from Codex Phase 0 review).
--
-- v1 took only (p_run_id, p_max_retries) and trusted the handler to call
-- validateRunForFull first to enforce I3 (RUN_FORBIDDEN) and I5
-- (RUN_CONVERSATION_MISMATCH). That contract is correct in the current
-- handler flow, but a future bug or new caller could call reserve directly
-- and accidentally hand a retry slot to a request that should have been
-- rejected by I3/I5.
--
-- v2 makes the RPC fail-closed on its own by adding user_id and
-- conversation_hash to the WHERE clause. If either mismatches, 0 rows update
-- and the caller gets NULL. The handler still calls validateRunForFull first
-- for clean error codes; this is just a backstop.

-- Drop v1 by exact signature so the two definitions don't coexist as
-- overloads (supabase-js cannot disambiguate by arg list reliably).
DROP FUNCTION IF EXISTS public.reserve_analysis_run_retry(UUID, INTEGER);

CREATE OR REPLACE FUNCTION public.reserve_analysis_run_retry(
  p_run_id              UUID,
  p_user_id             UUID,
  p_conversation_hash   TEXT,
  p_max_retries         INTEGER DEFAULT 3
)
RETURNS public.analysis_runs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.analysis_runs;
BEGIN
  UPDATE public.analysis_runs
     SET retry_count = retry_count + 1,
         consumed_at = COALESCE(consumed_at, now())
   WHERE id = p_run_id
     AND user_id = p_user_id
     AND conversation_hash = p_conversation_hash
     AND charged = TRUE
     AND expires_at > now()
     AND retry_count < p_max_retries
  RETURNING * INTO result;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reserve_analysis_run_retry(
  UUID, UUID, TEXT, INTEGER
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reserve_analysis_run_retry(
  UUID, UUID, TEXT, INTEGER
) TO service_role;

NOTIFY pgrst, 'reload schema';

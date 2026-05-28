-- Atomic retry slot reservation for two-stage analyze (I6).
-- Why this is an RPC: supabase-js does not expose SELECT ... FOR UPDATE.
-- A naive client-side fetch-then-update race window lets two concurrent
-- full requests both think they have an unused slot and both burn tokens.
-- This single SQL statement does the compare-and-swap atomically.

CREATE OR REPLACE FUNCTION public.reserve_analysis_run_retry(
  p_run_id      UUID,
  p_max_retries INTEGER DEFAULT 3
)
RETURNS public.analysis_runs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.analysis_runs;
BEGIN
  -- Eligibility encoded in WHERE: charged, not expired, retry_count below
  -- the cap. If any condition fails, 0 rows update and RETURNING gives NULL.
  UPDATE public.analysis_runs
     SET retry_count = retry_count + 1,
         consumed_at = COALESCE(consumed_at, now())
   WHERE id = p_run_id
     AND charged = TRUE
     AND expires_at > now()
     AND retry_count < p_max_retries
  RETURNING * INTO result;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reserve_analysis_run_retry(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reserve_analysis_run_retry(UUID, INTEGER) TO service_role;

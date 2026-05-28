-- Lock down analysis_runs SECURITY DEFINER function grants (Codex Phase 0 verify).
--
-- Why this exists:
--   Migrations 001000 / 001100 / 001200 / 001300 all did REVOKE EXECUTE ON
--   FUNCTION ... FROM PUBLIC. But Supabase pre-grants EXECUTE to anon and
--   authenticated for new public-schema functions; PUBLIC ≠ anon ∪ authenticated.
--   On the live project, `routine_privileges` still showed anon/authenticated
--   with EXECUTE after the four migrations applied. That meant a client with
--   the anon key could in principle call these SECURITY DEFINER functions —
--   create_charged_analysis_run would tick quota on someone else's behalf,
--   and reserve_analysis_run_retry would let any client probe run state.
--
-- Codex already ran the three REVOKEs by hand against fcmwrmwdoqiqdnbisdpg.
-- This migration repeats them so any future environment (staging, fork, full
-- replay) ends in the same locked-down state. REVOKE is idempotent — running
-- it against a role that no longer has EXECUTE is a no-op, not an error.

REVOKE EXECUTE ON FUNCTION public.cleanup_expired_analysis_runs()
  FROM anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.create_charged_analysis_run(
  UUID, TEXT, JSONB, JSONB, BOOLEAN, INTEGER
) FROM anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.reserve_analysis_run_retry(
  UUID, UUID, TEXT, INTEGER
) FROM anon, authenticated;

-- Tighten convention for the rest of the file too: spell out the explicit
-- service_role grant once more so a future reader doesn't have to chase three
-- migration files to know who can call these functions.
GRANT EXECUTE ON FUNCTION public.cleanup_expired_analysis_runs()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.create_charged_analysis_run(
  UUID, TEXT, JSONB, JSONB, BOOLEAN, INTEGER
) TO service_role;
GRANT EXECUTE ON FUNCTION public.reserve_analysis_run_retry(
  UUID, UUID, TEXT, INTEGER
) TO service_role;

NOTIFY pgrst, 'reload schema';

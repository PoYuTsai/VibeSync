-- Streaming analyze lifecycle: pending -> charged -> done | failed.
-- This table is separate from analysis_runs so the existing two-stage
-- quick/full quota path stays isolated while streaming is dogfooded.

CREATE TABLE IF NOT EXISTS public.analysis_stream_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_hash TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'charged', 'done', 'failed')),
  selected_style TEXT
    CHECK (
      selected_style IS NULL
      OR selected_style IN ('extend', 'resonate', 'tease', 'humor', 'coldRead')
    ),
  recommendation_json JSONB,
  final_result_json JSONB,
  charged_at TIMESTAMPTZ,
  last_error_code TEXT,
  request_context JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 minutes'),
  CONSTRAINT analysis_stream_runs_charged_has_recommendation
    CHECK (
      charged_at IS NULL
      OR (
        recommendation_json IS NOT NULL
        AND jsonb_typeof(recommendation_json) = 'object'
        AND selected_style IS NOT NULL
      )
    ),
  CONSTRAINT analysis_stream_runs_charged_status_has_time
    CHECK (status NOT IN ('charged', 'done') OR charged_at IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS analysis_stream_runs_user_idx
  ON public.analysis_stream_runs (user_id);

CREATE INDEX IF NOT EXISTS analysis_stream_runs_user_expires_idx
  ON public.analysis_stream_runs (user_id, expires_at);

CREATE INDEX IF NOT EXISTS analysis_stream_runs_expires_idx
  ON public.analysis_stream_runs (expires_at);

ALTER TABLE public.analysis_stream_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS analysis_stream_runs_service_role ON public.analysis_stream_runs;
CREATE POLICY analysis_stream_runs_service_role
  ON public.analysis_stream_runs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON TABLE public.analysis_stream_runs FROM PUBLIC;
REVOKE ALL ON TABLE public.analysis_stream_runs FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.analysis_stream_runs TO service_role;

COMMENT ON TABLE public.analysis_stream_runs IS
  'Streaming analyze runs. charged_at non-null means quota was consumed; recommendation_json and selected_style must be durable for resume.';

CREATE OR REPLACE FUNCTION public.cleanup_expired_analysis_stream_runs()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM public.analysis_stream_runs
  WHERE expires_at < now() - interval '1 hour';

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_expired_analysis_stream_runs() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cleanup_expired_analysis_stream_runs() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_analysis_stream_runs() TO service_role;

NOTIFY pgrst, 'reload schema';

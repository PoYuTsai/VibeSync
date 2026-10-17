-- Analyze stage 3 slice 0: let a charged stream run carry a v3 task card
-- instead of one of the five reply styles.
--
-- The v3 guide (Bruce, PR #97) replaces the five reply styles with 3-5 task
-- cards (accept, resonate, tension, push, close) and charges when the first
-- card is delivered (Eric 2026-10-16). Today a charged send run must hold a
-- reply style, so a v3 send run would be an illegal row.
--
-- This migration is additive and backward compatible:
-- - existing rows keep card_task NULL and satisfy every constraint unchanged;
-- - charge_stream_analysis_run (v1), charge_stream_analysis_run_v2 and
--   reserve_stream_analysis_retry are untouched, so deployed Edge code keeps
--   working;
-- - v3 send runs are intentionally NOT retryable (the first version never
--   regenerates; a dropped stream closes with the cards already delivered), so
--   the retry lease keeps refusing them without any change;
-- - Edge v3 code must not ship to main before this migration is verified on
--   production.
--
-- Locking (review round 1): every ALTER below takes ACCESS EXCLUSIVE until
-- commit, so a long-lived open transaction must not stall analyze traffic
-- behind this migration: give up after 5s instead (same pattern as
-- 20260729000000). The CHECKs are added NOT VALID, so no existing row is
-- scanned while the lock is held. That is safe here because every existing row
-- already satisfies them: card_task is a brand-new column that is NULL on every
-- existing row, and the rewritten charged CHECK only adds an OR branch to the
-- validated one it replaces. NOT VALID CHECKs are still enforced on every
-- INSERT and UPDATE. A later migration may VALIDATE them under a weaker lock.

SET LOCAL lock_timeout = '5s';

ALTER TABLE public.analysis_stream_runs
  ADD COLUMN IF NOT EXISTS card_task TEXT;

ALTER TABLE public.analysis_stream_runs
  DROP CONSTRAINT IF EXISTS analysis_stream_runs_card_task_check;
ALTER TABLE public.analysis_stream_runs
  ADD CONSTRAINT analysis_stream_runs_card_task_check
  CHECK (
    card_task IS NULL
    OR card_task IN ('accept', 'resonate', 'tension', 'push', 'close')
  ) NOT VALID;

-- A task card only ever belongs to a send run without a reply style; NULL
-- decision_kind (legacy v1) must read as FALSE here.
ALTER TABLE public.analysis_stream_runs
  DROP CONSTRAINT IF EXISTS analysis_stream_runs_card_task_send_only;
ALTER TABLE public.analysis_stream_runs
  ADD CONSTRAINT analysis_stream_runs_card_task_send_only
  CHECK (
    card_task IS NULL
    OR (selected_style IS NULL AND COALESCE(decision_kind = 'send', FALSE))
  ) NOT VALID;

-- A task card row must carry the send recommendation it was charged with
-- (review round 1): decisionKind 'send' and the same cardTask. A missing key,
-- a JSON null or a non-object reads as NULL and is rejected via COALESCE.
ALTER TABLE public.analysis_stream_runs
  DROP CONSTRAINT IF EXISTS analysis_stream_runs_card_task_recommendation;
ALTER TABLE public.analysis_stream_runs
  ADD CONSTRAINT analysis_stream_runs_card_task_recommendation
  CHECK (
    card_task IS NULL
    OR COALESCE(
      jsonb_typeof(recommendation_json) = 'object'
      AND recommendation_json->>'decisionKind' = 'send'
      AND recommendation_json->>'cardTask' = card_task,
      FALSE
    )
  ) NOT VALID;

-- charged_at non-null => recommendation object AND (reply style OR no-send
-- kind OR v3 task card). Existing rows satisfy this unchanged.
ALTER TABLE public.analysis_stream_runs
  DROP CONSTRAINT IF EXISTS analysis_stream_runs_charged_has_recommendation;
ALTER TABLE public.analysis_stream_runs
  ADD CONSTRAINT analysis_stream_runs_charged_has_recommendation
  CHECK (
    charged_at IS NULL
    OR (
      recommendation_json IS NOT NULL
      AND jsonb_typeof(recommendation_json) = 'object'
      AND (
        selected_style IS NOT NULL
        OR COALESCE(
          decision_kind IN ('do_not_send', 'acknowledge_and_stop', 'need_context'),
          FALSE
        )
        OR card_task IS NOT NULL
      )
    )
  ) NOT VALID;

COMMENT ON COLUMN public.analysis_stream_runs.card_task IS
  'Analyze v3 task of the first (charged) card: accept, resonate, tension, push or close. Only on send runs without a reply style; NULL for legacy v1/v2 rows and no-send runs.';

COMMENT ON TABLE public.analysis_stream_runs IS
  'Streaming analyze runs. charged_at non-null means the run was accepted into the charged lifecycle; recommendation_json plus a reply style (v1/v2 send), a no-send decision_kind, or a v3 card_task must be durable for resume.';

-- v3 charge RPC. v1 and v2 are intentionally left as they are.
CREATE OR REPLACE FUNCTION public.charge_stream_analysis_run_v3(
  p_run_id UUID,
  p_user_id UUID,
  p_conversation_hash TEXT,
  p_recommendation_json JSONB,
  p_decision_kind TEXT,
  p_card_task TEXT DEFAULT NULL,
  p_message_count INTEGER DEFAULT 1,
  p_charge_quota BOOLEAN DEFAULT TRUE
)
RETURNS public.analysis_stream_runs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  stream_run public.analysis_stream_runs;
  should_charge BOOLEAN := COALESCE(p_charge_quota, TRUE);
  is_no_send BOOLEAN;
BEGIN
  IF p_run_id IS NULL THEN
    RAISE EXCEPTION 'charge_stream_analysis_run_v3: p_run_id is required';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'charge_stream_analysis_run_v3: p_user_id is required';
  END IF;

  IF p_conversation_hash IS NULL OR length(btrim(p_conversation_hash)) = 0 THEN
    RAISE EXCEPTION 'charge_stream_analysis_run_v3: p_conversation_hash is required';
  END IF;

  SELECT *
    INTO stream_run
    FROM public.analysis_stream_runs
   WHERE id = p_run_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'STREAM_RUN_NOT_FOUND';
  END IF;

  IF stream_run.user_id <> p_user_id THEN
    RAISE EXCEPTION 'STREAM_RUN_OWNER_MISMATCH';
  END IF;

  IF stream_run.conversation_hash <> p_conversation_hash THEN
    RAISE EXCEPTION 'RUN_CONVERSATION_MISMATCH';
  END IF;

  -- Exactly-once: a charged run replays its durable state, whatever the caller
  -- sends the second time.
  IF stream_run.charged_at IS NOT NULL THEN
    RETURN stream_run;
  END IF;

  -- Payload validation runs only for an uncharged run, after the replay branch
  -- above, so a retried request is never rejected for a payload that no longer
  -- matters.
  IF p_recommendation_json IS NULL
     OR p_recommendation_json = 'null'::jsonb
     OR jsonb_typeof(p_recommendation_json) <> 'object' THEN
    RAISE EXCEPTION 'STREAM_MALFORMED_RECOMMENDATION';
  END IF;

  IF p_decision_kind IS NULL
     OR p_decision_kind NOT IN ('send', 'do_not_send', 'acknowledge_and_stop', 'need_context') THEN
    RAISE EXCEPTION 'STREAM_INVALID_DECISION_KIND';
  END IF;

  is_no_send := p_decision_kind <> 'send';

  IF is_no_send THEN
    -- Same no-send contract as v2: no card, and a non-empty decision that the
    -- resume path can replay.
    IF p_card_task IS NOT NULL THEN
      RAISE EXCEPTION 'STREAM_INVALID_CARD_TASK';
    END IF;
    -- A no-send payload never names a card, so nothing downstream can mistake
    -- it for one.
    IF p_recommendation_json ? 'cardTask' THEN
      RAISE EXCEPTION 'STREAM_MALFORMED_RECOMMENDATION';
    END IF;
    IF p_recommendation_json->>'decisionKind' IS DISTINCT FROM p_decision_kind
       OR COALESCE(length(btrim(p_recommendation_json->>'action')), 0) = 0
       OR COALESCE(length(btrim(p_recommendation_json->>'reason')), 0) = 0
       OR COALESCE(length(btrim(p_recommendation_json->>'stopCondition')), 0) = 0 THEN
      RAISE EXCEPTION 'STREAM_MALFORMED_RECOMMENDATION';
    END IF;
  ELSE
    -- A v3 send run charges on its first delivered card.
    IF p_card_task IS NULL
       OR p_card_task NOT IN ('accept', 'resonate', 'tension', 'push', 'close') THEN
      RAISE EXCEPTION 'STREAM_INVALID_CARD_TASK';
    END IF;
    -- A v3 send payload never names a reply style.
    IF p_recommendation_json->>'decisionKind' IS DISTINCT FROM 'send'
       OR p_recommendation_json->>'cardTask' IS DISTINCT FROM p_card_task
       OR p_recommendation_json ? 'selectedStyle' THEN
      RAISE EXCEPTION 'STREAM_MALFORMED_RECOMMENDATION';
    END IF;
  END IF;

  IF should_charge AND (p_message_count IS NULL OR p_message_count <= 0) THEN
    RAISE EXCEPTION 'charge_stream_analysis_run_v3: p_message_count must be positive when charging';
  END IF;

  IF stream_run.status <> 'pending' THEN
    RAISE EXCEPTION 'STREAM_RUN_NOT_PENDING';
  END IF;

  IF stream_run.expires_at <= now() THEN
    RAISE EXCEPTION 'STREAM_RUN_EXPIRED';
  END IF;

  IF should_charge THEN
    PERFORM public.increment_usage(p_user_id, p_message_count);
  END IF;

  UPDATE public.analysis_stream_runs
     SET status = 'charged',
         charged_at = now(),
         recommendation_json = p_recommendation_json,
         selected_style = NULL,
         decision_kind = p_decision_kind,
         card_task = CASE WHEN is_no_send THEN NULL ELSE p_card_task END,
         last_error_code = NULL
   WHERE id = p_run_id
  RETURNING * INTO stream_run;

  RETURN stream_run;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.charge_stream_analysis_run_v3(
  UUID, UUID, TEXT, JSONB, TEXT, TEXT, INTEGER, BOOLEAN
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.charge_stream_analysis_run_v3(
  UUID, UUID, TEXT, JSONB, TEXT, TEXT, INTEGER, BOOLEAN
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.charge_stream_analysis_run_v3(
  UUID, UUID, TEXT, JSONB, TEXT, TEXT, INTEGER, BOOLEAN
) TO service_role;

COMMENT ON FUNCTION public.charge_stream_analysis_run_v3(
  UUID, UUID, TEXT, JSONB, TEXT, TEXT, INTEGER, BOOLEAN
) IS 'Atomic charge for Analyze v3. send requires a task card (accept, resonate, tension, push, close) matching recommendation cardTask and never a reply style; no-send kinds follow the v2 contract with no card and no cardTask key. Charged runs replay idempotently. v3 send runs are not leasable for retry; v3 no-send runs follow the v2 retry lease like any no-send run.';

NOTIFY pgrst, 'reload schema';

-- Hint replay is certified only after two independent semantic reviewers agree
-- on the interaction kind and both reply/coaching contracts. Keep the database
-- legacy-replacement predicate aligned with that internal Edge certification so
-- an already-paid semantic-quality-v2 snapshot from an older worker is replaced
-- atomically instead of being replayed or charged a second time.
--
-- This migration is safe to apply before the Edge rollout: the previous Edge
-- still accepts its semantic-quality-v2 snapshots through the normal replay path,
-- while the new Edge uses this replacement RPC for snapshots missing the review
-- certification.

DO $$
DECLARE
  v_definition TEXT;
  v_updated TEXT;
  v_old_predicate TEXT :=
    'AND v_request.result ->> ''qualitySchemaVersion'' = ''semantic-quality-v2'';';
  v_new_predicate TEXT :=
    E'AND v_request.result ->> ''qualitySchemaVersion'' = ''semantic-quality-v2''\n' ||
    '    AND v_request.result ->> ''hintReviewSchemaVersion'' = ''dual-semantic-assessment-v1'';';
BEGIN
  SELECT pg_get_functiondef(
    'public.claim_legacy_practice_hint_replacement(uuid,text,text,text,integer)'::regprocedure
  ) INTO v_definition;

  IF position(v_new_predicate IN v_definition) > 0 THEN
    RETURN;
  END IF;
  IF position(v_old_predicate IN v_definition) = 0 THEN
    RAISE EXCEPTION 'claim_legacy_practice_hint_replacement review marker drifted';
  END IF;

  v_updated := replace(v_definition, v_old_predicate, v_new_predicate);
  IF v_updated = v_definition THEN
    RAISE EXCEPTION 'claim_legacy_practice_hint_replacement review marker unchanged';
  END IF;
  EXECUTE v_updated;
END;
$$;

NOTIFY pgrst, 'reload schema';

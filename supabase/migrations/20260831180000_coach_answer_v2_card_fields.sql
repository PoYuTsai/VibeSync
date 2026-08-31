-- Batch B2 (CoachAnswerV2): widen the coach_requests card whitelist with two
-- optional keys — messageDecision ('send'/'hold_off'/'no_message_needed') and
-- evidenceQuality ('none'/'stale_or_partial'/'fresh'). Both are derived
-- deterministically server-side (schemas.ts transform / generation.ts), never
-- model self-reported.
--
-- Compatibility: pure widening. Old cards (keys absent) stay valid — the
-- subtraction whitelist only removes known keys, and the value checks pass on
-- NULL (absent or JSON null both read as SQL NULL via ->>). No row rewrite.
-- Deploy order: this migration MUST be applied and verified on production
-- BEFORE the Edge revision that writes the new keys is pushed to main,
-- otherwise settle_coach_request rejects every new card.

ALTER TABLE public.coach_requests
  DROP CONSTRAINT coach_requests_result_state_consistency;

ALTER TABLE public.coach_requests
  ADD CONSTRAINT coach_requests_result_state_consistency CHECK (
    (
      state = 'pending'
      AND result_json IS NULL
      AND quota_charged = FALSE
    )
    OR
    (
      state = 'done'
      AND result_json IS NOT NULL
      AND jsonb_typeof(result_json) = 'object'
      -- 頂層恰為 200 body 五鍵（envelope），禁夾帶其他鍵。
      AND result_json ?& ARRAY['card','sessionId','provider','model','generatedAt']
      AND (result_json - 'card' - 'sessionId' - 'provider' - 'model' - 'generatedAt') = '{}'::jsonb
      AND result_json ->> 'provider' = 'claude'
      AND jsonb_typeof(result_json -> 'card') = 'object'
      AND (result_json -> 'card' ->> 'responseType') IN ('coachAnswer', 'clarifyingQuestion')
      AND (result_json -> 'card' ->> 'costDeducted') IN ('0', '1')
      -- B2 兩鍵選填：缺席（SQL NULL）放行，有值鎖 enum。
      AND (
        (result_json -> 'card' ->> 'messageDecision') IS NULL
        OR (result_json -> 'card' ->> 'messageDecision')
          IN ('send', 'hold_off', 'no_message_needed')
      )
      AND (
        (result_json -> 'card' ->> 'evidenceQuality') IS NULL
        OR (result_json -> 'card' ->> 'evidenceQuality')
          IN ('none', 'stale_or_partial', 'fresh')
      )
      -- card 欄位白名單＝現行 ResponseCardSchema 全欄位；多任何一鍵即拒
      -- （防 prompt／來源訊息／原始輸出滲入帳本：設計鐵律 8）。
      -- 注意：Postgres 的 + - 優先級高於 ->，必須先括號取 card 再減鍵。
      AND ((result_json -> 'card')
        - 'responseType' - 'mode' - 'headline' - 'answer' - 'userTruth'
        - 'userState' - 'frictionType' - 'nextStep' - 'suggestedLine'
        - 'rewriteDecision' - 'rewriteReason' - 'boundaryReminder'
        - 'needsReflection' - 'reflectionQuestion' - 'costDeducted'
        - 'messageDecision' - 'evidenceQuality') = '{}'::jsonb
    )
  );

-- settle_coach_request：僅入參驗證區塊擴白名單＋enum 檢查，其餘與
-- 20260721120000 版逐字相同（claim/release/cleanup 不動）。
CREATE OR REPLACE FUNCTION public.settle_coach_request(
  p_user_id UUID,
  p_request_id UUID,
  p_input_hash TEXT,
  p_owner_token UUID,
  p_result_json JSONB,
  p_monthly_limit INTEGER,
  p_daily_limit INTEGER,
  p_charge_quota BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.coach_requests%ROWTYPE;
  v_should_charge BOOLEAN := COALESCE(p_charge_quota, TRUE);
BEGIN
  IF p_user_id IS NULL OR p_request_id IS NULL OR p_owner_token IS NULL THEN
    RAISE EXCEPTION 'settle_coach_request: identity is required';
  END IF;
  IF p_input_hash IS NULL OR p_input_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'settle_coach_request: invalid p_input_hash';
  END IF;
  IF p_result_json IS NULL
     OR jsonb_typeof(p_result_json) <> 'object'
     OR NOT (p_result_json ?& ARRAY['card','sessionId','provider','model','generatedAt'])
     OR (p_result_json - 'card' - 'sessionId' - 'provider' - 'model' - 'generatedAt') <> '{}'::jsonb
     OR p_result_json ->> 'provider' <> 'claude'
     OR jsonb_typeof(p_result_json -> 'card') <> 'object'
     OR (p_result_json -> 'card' ->> 'responseType') NOT IN ('coachAnswer', 'clarifyingQuestion')
     OR (p_result_json -> 'card' ->> 'costDeducted') NOT IN ('0', '1')
     OR NOT (
       (p_result_json -> 'card' ->> 'messageDecision') IS NULL
       OR (p_result_json -> 'card' ->> 'messageDecision')
         IN ('send', 'hold_off', 'no_message_needed')
     )
     OR NOT (
       (p_result_json -> 'card' ->> 'evidenceQuality') IS NULL
       OR (p_result_json -> 'card' ->> 'evidenceQuality')
         IN ('none', 'stale_or_partial', 'fresh')
     )
     OR ((p_result_json -> 'card')
       - 'responseType' - 'mode' - 'headline' - 'answer' - 'userTruth'
       - 'userState' - 'frictionType' - 'nextStep' - 'suggestedLine'
       - 'rewriteDecision' - 'rewriteReason' - 'boundaryReminder'
       - 'needsReflection' - 'reflectionQuestion' - 'costDeducted'
       - 'messageDecision' - 'evidenceQuality') <> '{}'::jsonb THEN
    RAISE EXCEPTION 'settle_coach_request: invalid p_result_json';
  END IF;
  IF v_should_charge
     AND (
       p_monthly_limit IS NULL OR p_monthly_limit <= 0
       OR p_daily_limit IS NULL OR p_daily_limit <= 0
     ) THEN
    RAISE EXCEPTION 'settle_coach_request: invalid quota limits';
  END IF;

  SELECT * INTO v_existing
  FROM public.coach_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COACH_REQUEST_SETTLEMENT_MISSING';
  END IF;
  IF v_existing.input_hash IS DISTINCT FROM p_input_hash THEN
    RAISE EXCEPTION 'COACH_REQUEST_REPLAY_MISMATCH';
  END IF;
  IF v_existing.state = 'done' THEN
    RETURN jsonb_build_object(
      'charged', FALSE,
      'result', v_existing.result_json
    );
  END IF;
  IF v_existing.owner_token IS DISTINCT FROM p_owner_token THEN
    RAISE EXCEPTION 'COACH_REQUEST_OWNER_MISMATCH';
  END IF;

  IF v_should_charge THEN
    PERFORM 1
    FROM public.subscriptions
    WHERE user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'COACH_SUBSCRIPTION_MISSING';
    END IF;

    PERFORM public.increment_usage(
      p_user_id,
      1,
      p_monthly_limit,
      p_daily_limit
    );
  END IF;

  UPDATE public.coach_requests
  SET state = 'done',
      result_json = p_result_json,
      quota_charged = v_should_charge,
      updated_at = now()
  WHERE user_id = p_user_id
    AND request_id = p_request_id;

  RETURN jsonb_build_object(
    'charged', v_should_charge,
    'result', p_result_json
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.settle_coach_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.settle_coach_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_coach_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) TO service_role;

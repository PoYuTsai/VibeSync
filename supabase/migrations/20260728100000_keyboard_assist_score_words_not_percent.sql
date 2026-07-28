-- Stop rejecting every percent sign at settlement; gate the score words instead.
--
-- `is_valid_keyboard_assist_result` backs both the
-- `keyboard_assist_requests_check` CHECK constraint and
-- `settle_keyboard_assist_request`, and it refused any result whose JSON text
-- contained `%` or `％` anywhere. The rule exists to keep compatibility scores
-- ("好感度 87%") out of the product, but it fired on every ordinary percentage a
-- conversation can contain — a discount, a battery level, a hit rate — and it
-- fired *after* the model had already answered, so the user paid the full wait
-- and got a bare failure with no reason attached.
--
-- The four score phrases were already refused on their own, so the percent sign
-- added nothing to them; it only widened the blast radius. 契合度 / 匹配度 / 速配
-- join the list to cover the same framing under different words.
--
-- Relaxation only: every result that passed before still passes, so this is
-- backward-compatible with the currently deployed Edge and client code in both
-- directions and needs no staged rollout. Only the final content backstop
-- changes; every other rule is carried over verbatim from
-- `20260728060000_keyboard_assist_three_angles.sql`.
--
-- Keep this list in step with KEYBOARD_ASSIST_DISALLOWED_CONTENT_TOKENS in
-- validate.ts. They are two copies of one rule, and the last time they drifted
-- every valid result was rejected here while the Deno suite stayed green.

CREATE OR REPLACE FUNCTION public.is_valid_keyboard_assist_result(
  p_result JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_distinct_strategies INTEGER;
BEGIN
  IF p_result IS NULL OR jsonb_typeof(p_result) <> 'object' THEN
    RETURN FALSE;
  END IF;

  IF p_result ->> 'status' = 'needs_speaker_confirmation' THEN
    RETURN
      p_result ->> 'contractVersion' = 'keyboard-assist-v1'
      AND p_result ->> 'suggestedMySide' IN ('left', 'right')
      AND p_result ->> 'sideConfidence' = 'low'
      AND p_result = jsonb_build_object(
        'contractVersion', 'keyboard-assist-v1',
        'status', 'needs_speaker_confirmation',
        'suggestedMySide', p_result ->> 'suggestedMySide',
        'sideConfidence', 'low'
      );
  END IF;

  IF p_result ->> 'status' <> 'ready' THEN
    RETURN FALSE;
  END IF;
  IF p_result ->> 'contractVersion' <> 'keyboard-assist-v1' THEN
    RETURN FALSE;
  END IF;
  IF p_result <> jsonb_build_object(
    'contractVersion', 'keyboard-assist-v1',
    'status', 'ready',
    'source', p_result -> 'source',
    'turnState', p_result -> 'turnState',
    'cue', p_result -> 'cue',
    'uncertainty', p_result -> 'uncertainty',
    'options', p_result -> 'options'
  ) THEN
    RETURN FALSE;
  END IF;
  IF jsonb_typeof(p_result -> 'source') <> 'object'
     OR p_result -> 'source' <> jsonb_build_object(
       'scope', p_result #> '{source,scope}',
       'messageCount', p_result #> '{source,messageCount}',
       'confidence', p_result #> '{source,confidence}',
       'sideConfidence', p_result #> '{source,sideConfidence}'
     )
     OR p_result #>> '{source,scope}' NOT IN (
       'screenshot_only', 'screenshot_plus_global_voice'
     )
     OR jsonb_typeof(p_result #> '{source,messageCount}') <> 'number'
     OR (p_result #>> '{source,messageCount}')::NUMERIC <> trunc(
       (p_result #>> '{source,messageCount}')::NUMERIC
     )
     OR (p_result #>> '{source,messageCount}')::INTEGER NOT BETWEEN 1 AND 100
     OR p_result #>> '{source,confidence}' NOT IN ('high', 'medium', 'low')
     OR p_result #>> '{source,sideConfidence}' NOT IN ('high', 'medium', 'low')
     OR p_result ->> 'turnState' NOT IN ('reply_due', 'optional_follow_up')
     OR jsonb_typeof(p_result -> 'cue') <> 'string'
     OR char_length(p_result ->> 'cue') NOT BETWEEN 1 AND 120
     OR btrim(p_result ->> 'cue') <> p_result ->> 'cue'
     OR (
       jsonb_typeof(p_result -> 'uncertainty') NOT IN ('string', 'null')
     )
     OR (
       jsonb_typeof(p_result -> 'uncertainty') = 'string'
       AND (
         char_length(p_result ->> 'uncertainty') NOT BETWEEN 1 AND 120
         OR btrim(p_result ->> 'uncertainty') <> p_result ->> 'uncertainty'
       )
     )
     OR jsonb_typeof(p_result -> 'options') <> 'array'
     OR jsonb_array_length(p_result -> 'options') <> 3 THEN
    RETURN FALSE;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_result -> 'options') AS candidate(option)
    WHERE jsonb_typeof(option) <> 'object'
      OR option <> jsonb_build_object(
        'strategy', option -> 'strategy',
        'text', option -> 'text',
        'why', option -> 'why',
        'effect', option -> 'effect'
      )
      -- 延展 / 調情 / 幽默. Keep this list in step with
      -- KEYBOARD_ASSIST_STRATEGIES in contract.ts and
      -- KeyboardAssistStrategy in KeyboardAssistContracts.swift.
      OR option ->> 'strategy' NOT IN (
        'extend',
        'flirt',
        'humor'
      )
      OR jsonb_typeof(option -> 'text') <> 'string'
      OR char_length(option ->> 'text') NOT BETWEEN 1 AND 100
      OR btrim(option ->> 'text') <> option ->> 'text'
      OR jsonb_typeof(option -> 'why') <> 'string'
      OR char_length(option ->> 'why') NOT BETWEEN 1 AND 80
      OR btrim(option ->> 'why') <> option ->> 'why'
      OR jsonb_typeof(option -> 'effect') <> 'string'
      OR char_length(option ->> 'effect') NOT BETWEEN 1 AND 60
      OR btrim(option ->> 'effect') <> option ->> 'effect'
  ) THEN
    RETURN FALSE;
  END IF;

  SELECT COUNT(DISTINCT option ->> 'strategy')
  INTO v_distinct_strategies
  FROM jsonb_array_elements(p_result -> 'options') AS candidate(option);
  IF v_distinct_strategies <> 3 THEN
    RETURN FALSE;
  END IF;

  -- Narrow deterministic privacy/quality backstop. Broader semantic grounding
  -- remains in the Edge pipeline and human evaluation.
  IF p_result::TEXT ~ '```|好感度|契合度|匹配度|速配|心理診斷|依附型態|人格分析' THEN
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END;
$$;

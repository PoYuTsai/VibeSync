-- New Topic ledger 相容擴充：result_json 允許第四鍵 formulaTopics（0–2 則
-- 公式新話題），legacy 三-key row 繼續合法（2026-07-24 公式回覆計畫 §7.3）。
--
-- Additive only：不修改已部署的 20260724120000_new_topic_exactly_once.sql；
-- claim / release / settle / cleanup / cron / RLS / grants 全部不動。
-- Forward-fix：本 migration 套用後不提供降回 v1 constraint 的 down migration
--（已有四-key row 時降回必然失敗）。
--
-- formulaTopics 形狀（與 TS normalizer／Dart parser 對齊）：
--   * array，長度 0–2。
--   * 每項恰好兩鍵 openingLine / whyItWorks，皆為非空 string。
--   * char_length() hard cap 分別 180／300——PostgreSQL char_length 以字元
--     （Unicode code point）計，與 TypeScript [...text].length、Dart
--     text.runes.length 對齊。
-- 超出任一規則＝整份 result 非法：settle 的 validate RAISE 讓 quota 與
-- result 同 transaction 回滾（fail-closed tripwire，絕不放寬資料庫）。

-- ---------------------------------------------------------------------------
-- 公式陣列深層驗證 helper（table CHECK 與 validate_new_topic_result 共用，
-- 單一事實來源）。
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_new_topic_formula_topics(
  p_formula_topics JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_item JSONB;
  v_opening TEXT;
  v_why TEXT;
BEGIN
  IF p_formula_topics IS NULL
     OR jsonb_typeof(p_formula_topics) <> 'array'
     OR jsonb_array_length(p_formula_topics) > 2 THEN
    RETURN FALSE;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_formula_topics)
  LOOP
    IF jsonb_typeof(v_item) <> 'object'
       OR NOT (v_item ?& ARRAY['openingLine', 'whyItWorks'])
       OR (v_item - 'openingLine' - 'whyItWorks') <> '{}'::jsonb
       OR jsonb_typeof(v_item -> 'openingLine') <> 'string'
       OR jsonb_typeof(v_item -> 'whyItWorks') <> 'string' THEN
      RETURN FALSE;
    END IF;

    v_opening := v_item ->> 'openingLine';
    v_why := v_item ->> 'whyItWorks';
    IF v_opening IS NULL OR char_length(btrim(v_opening)) = 0
       OR char_length(v_opening) > 180
       OR v_why IS NULL OR char_length(btrim(v_why)) = 0
       OR char_length(v_why) > 300 THEN
      RETURN FALSE;
    END IF;
  END LOOP;

  RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_new_topic_formula_topics(JSONB)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validate_new_topic_formula_topics(JSONB)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_new_topic_formula_topics(JSONB)
  TO service_role;

-- ---------------------------------------------------------------------------
-- Table CHECK：重建為 legacy 三-key／新四-key 相容版。
-- 減鍵法多扣一個 formulaTopics（其他未知頂層鍵照拒），formulaTopics 存在時
-- 走 helper 深驗。ADD CONSTRAINT 會重驗既有 rows——legacy 三-key done row
-- 必須原樣通過。
-- ---------------------------------------------------------------------------
ALTER TABLE public.new_topic_requests
  DROP CONSTRAINT new_topic_requests_result_state_consistency;

ALTER TABLE public.new_topic_requests
  ADD CONSTRAINT new_topic_requests_result_state_consistency CHECK (
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
      -- 必備三鍵不變；頂層至多再多一個 formulaTopics，其他鍵照拒。
      AND result_json ?& ARRAY['topics', 'recommendation', 'access']
      AND (result_json - 'topics' - 'recommendation' - 'access'
        - 'formulaTopics') = '{}'::jsonb
      AND jsonb_typeof(result_json -> 'topics') = 'array'
      AND jsonb_typeof(result_json -> 'recommendation') = 'object'
      AND jsonb_typeof(result_json -> 'access') = 'object'
      -- formulaTopics 缺席＝legacy row 合法；存在時深驗 0–2 則公式形狀。
      AND (
        NOT (result_json ? 'formulaTopics')
        OR public.validate_new_topic_formula_topics(
          result_json -> 'formulaTopics'
        )
      )
      -- access 欄位白名單＋totalCount 恆 5。
      AND (result_json -> 'access') ?& ARRAY[
        'servedTier', 'limited', 'totalCount', 'unlockedCount', 'lockedCount'
      ]
      AND ((result_json -> 'access')
        - 'servedTier' - 'limited' - 'totalCount'
        - 'unlockedCount' - 'lockedCount') = '{}'::jsonb
      AND (result_json -> 'access' ->> 'totalCount') = '5'
      -- tier 投影一致性：Free 只存 1 題（鎖 4）、Paid 存 5 題（鎖 0）。
      -- 公式不參與 counts：Free 1 題＋formula 0–2、Paid 5 題＋formula 0–2。
      AND (
        (
          (result_json -> 'access' ->> 'servedTier') = 'free'
          AND (result_json -> 'access' ->> 'limited') = 'true'
          AND (result_json -> 'access' ->> 'unlockedCount') = '1'
          AND (result_json -> 'access' ->> 'lockedCount') = '4'
          AND jsonb_array_length(result_json -> 'topics') = 1
        )
        OR
        (
          (result_json -> 'access' ->> 'servedTier')
            IN ('starter', 'essential')
          AND (result_json -> 'access' ->> 'limited') = 'false'
          AND (result_json -> 'access' ->> 'unlockedCount') = '5'
          AND (result_json -> 'access' ->> 'lockedCount') = '0'
          AND jsonb_array_length(result_json -> 'topics') = 5
        )
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 深層 result 驗證：同步接受 legacy／new shape（settle 入口不變，仍在
-- settle_new_topic_request 內 RAISE → 全 transaction 回滾）。
-- 與 20260724120000 版的唯一差異＝頂層減鍵多扣 formulaTopics＋存在時深驗；
-- topics / recommendation / access 規則逐行未動。
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_new_topic_result(
  p_result_json JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_topic JSONB;
  v_id TEXT;
  v_direction TEXT;
  v_opening TEXT;
  v_why TEXT;
  v_next TEXT;
  v_reason TEXT;
  v_rec_topic_id TEXT;
  v_seen_ids TEXT[] := '{}';
  v_rec_found BOOLEAN := FALSE;
BEGIN
  IF p_result_json IS NULL
     OR jsonb_typeof(p_result_json) <> 'object'
     OR NOT (p_result_json ?& ARRAY['topics', 'recommendation', 'access'])
     OR (p_result_json - 'topics' - 'recommendation' - 'access'
       - 'formulaTopics') <> '{}'::jsonb
     OR jsonb_typeof(p_result_json -> 'topics') <> 'array'
     OR jsonb_typeof(p_result_json -> 'recommendation') <> 'object'
     OR jsonb_typeof(p_result_json -> 'access') <> 'object' THEN
    RETURN FALSE;
  END IF;

  -- formulaTopics 選填：缺席＝legacy；存在時整包深驗，壞一則即整份拒絕
  --（settle 前 canonicalizer 應已清乾淨，這裡是 fail-closed tripwire）。
  IF (p_result_json ? 'formulaTopics')
     AND NOT public.validate_new_topic_formula_topics(
       p_result_json -> 'formulaTopics'
     ) THEN
    RETURN FALSE;
  END IF;

  -- access 形狀（tier/counts 一致性同 table CHECK，重複驗證守 settle 入口）。
  IF NOT ((p_result_json -> 'access') ?& ARRAY[
       'servedTier', 'limited', 'totalCount', 'unlockedCount', 'lockedCount'
     ])
     OR ((p_result_json -> 'access')
       - 'servedTier' - 'limited' - 'totalCount'
       - 'unlockedCount' - 'lockedCount') <> '{}'::jsonb
     OR (p_result_json -> 'access' ->> 'totalCount') <> '5'
     OR NOT (
       (
         (p_result_json -> 'access' ->> 'servedTier') = 'free'
         AND (p_result_json -> 'access' ->> 'limited') = 'true'
         AND (p_result_json -> 'access' ->> 'unlockedCount') = '1'
         AND (p_result_json -> 'access' ->> 'lockedCount') = '4'
         AND jsonb_array_length(p_result_json -> 'topics') = 1
       )
       OR
       (
         (p_result_json -> 'access' ->> 'servedTier')
           IN ('starter', 'essential')
         AND (p_result_json -> 'access' ->> 'limited') = 'false'
         AND (p_result_json -> 'access' ->> 'unlockedCount') = '5'
         AND (p_result_json -> 'access' ->> 'lockedCount') = '0'
         AND jsonb_array_length(p_result_json -> 'topics') = 5
       )
     ) THEN
    RETURN FALSE;
  END IF;

  FOR v_topic IN SELECT * FROM jsonb_array_elements(p_result_json -> 'topics')
  LOOP
    IF jsonb_typeof(v_topic) <> 'object'
       OR NOT (v_topic ?& ARRAY[
         'id', 'direction', 'openingLine', 'whyItWorks', 'nextMove'
       ])
       OR (v_topic
         - 'id' - 'direction' - 'openingLine'
         - 'whyItWorks' - 'nextMove') <> '{}'::jsonb THEN
      RETURN FALSE;
    END IF;

    v_id := v_topic ->> 'id';
    v_direction := v_topic ->> 'direction';
    v_opening := v_topic ->> 'openingLine';
    v_why := v_topic ->> 'whyItWorks';
    v_next := v_topic ->> 'nextMove';

    IF v_id IS NULL OR v_id !~ '^nt_[1-5]$'
       OR v_id = ANY (v_seen_ids)
       OR v_direction IS NULL OR length(btrim(v_direction)) = 0
       OR length(v_direction) > 80
       OR v_opening IS NULL OR length(btrim(v_opening)) = 0
       OR length(v_opening) > 180
       OR v_why IS NULL OR length(btrim(v_why)) = 0
       OR length(v_why) > 400
       OR v_next IS NULL OR length(btrim(v_next)) = 0
       OR length(v_next) > 300 THEN
      RETURN FALSE;
    END IF;
    v_seen_ids := v_seen_ids || v_id;
  END LOOP;

  -- recommendation：topicId 必存在於 stored topics；reason 選填 ≤300。
  IF NOT ((p_result_json -> 'recommendation') ? 'topicId')
     OR ((p_result_json -> 'recommendation') - 'topicId' - 'reason')
       <> '{}'::jsonb THEN
    RETURN FALSE;
  END IF;
  v_rec_topic_id := p_result_json -> 'recommendation' ->> 'topicId';
  v_rec_found := v_rec_topic_id = ANY (v_seen_ids);
  IF NOT v_rec_found THEN
    RETURN FALSE;
  END IF;
  IF (p_result_json -> 'recommendation') ? 'reason' THEN
    v_reason := p_result_json -> 'recommendation' ->> 'reason';
    IF v_reason IS NULL OR length(btrim(v_reason)) = 0
       OR length(v_reason) > 300 THEN
      RETURN FALSE;
    END IF;
  END IF;

  RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_new_topic_result(JSONB)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validate_new_topic_result(JSONB)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_new_topic_result(JSONB)
  TO service_role;

-- ---------------------------------------------------------------------------
-- Contract marker：新 constraint／helper／validator 俱全才回 v2；缺任何一件
-- 降回 v1（v1 件也缺則 incomplete），Edge health 端不得自我宣告 readiness。
-- 功能性探針：v2 validator 必須真的接受四-key sample，防「函式在但還是舊版」。
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.new_topic_contract_version()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN to_regclass('public.new_topic_requests') IS NOT NULL
      AND to_regprocedure(
        'public.claim_new_topic_request(uuid,uuid,text,uuid)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.release_new_topic_claim(uuid,uuid,text,uuid)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.settle_new_topic_request(uuid,uuid,text,uuid,jsonb,integer,integer,boolean)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.validate_new_topic_result(jsonb)'
      ) IS NOT NULL
      AND (
        SELECT count(*) = 4
        FROM pg_attribute
        WHERE attrelid = to_regclass('public.new_topic_requests')
          AND attname = ANY (
            ARRAY['state', 'owner_token', 'lease_expires_at', 'updated_at']
          )
          AND NOT attisdropped
      )
    THEN
      CASE
        WHEN to_regprocedure(
            'public.validate_new_topic_formula_topics(jsonb)'
          ) IS NOT NULL
          AND EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE conrelid = to_regclass('public.new_topic_requests')
              AND conname = 'new_topic_requests_result_state_consistency'
              AND pg_get_constraintdef(oid) LIKE '%formulaTopics%'
          )
          AND public.validate_new_topic_result(
            '{"topics":[{"id":"nt_1","direction":"d","openingLine":"o","whyItWorks":"w","nextMove":"n"}],"recommendation":{"topicId":"nt_1"},"access":{"servedTier":"free","limited":true,"totalCount":5,"unlockedCount":1,"lockedCount":4},"formulaTopics":[{"openingLine":"f","whyItWorks":"w"}]}'::jsonb
          )
        THEN 'new-topic-exactly-once-v2'::TEXT
        ELSE 'new-topic-exactly-once-v1'::TEXT
      END
    ELSE 'incomplete'::TEXT
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.new_topic_contract_version() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.new_topic_contract_version()
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.new_topic_contract_version()
  TO service_role;

NOTIFY pgrst, 'reload schema';

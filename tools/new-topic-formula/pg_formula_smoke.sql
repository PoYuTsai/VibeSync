-- New Topic formulaTopics ledger 相容 PG smoke（2026-07-24 公式回覆計畫 §11.4）。
--
-- 執行前提：目標資料庫已依序套用
--   20260724120000_new_topic_exactly_once.sql
--   20260724180000_new_topic_formula_topics.sql
-- 使用測試帳號 user id（:test_user，psql -v 傳入；prod 用 vibesync.test）。
-- 全程包在單一 transaction、結尾 ROLLBACK——不留 rows、不動 counter。
-- 任何一態失敗即 RAISE EXCEPTION 中斷；全過時輸出 NOTICE 清單。
--
-- 涵蓋態（依計畫 §11.4）：
--   S1  legacy 三-key done row 在新 constraint 下仍合法
--   S2  新四-key row formula 0／1／2 則均合法（Free 與 Paid）
--   S3  三則 formula 被拒
--   S4  缺欄（只有 openingLine）被拒
--   S5  超長（openingLine 181 字）被拒
--   S6  多餘 item key 被拒
--   S7  formulaTopics 非 array 被拒
--   S8  頂層第四鍵不是 formulaTopics 被拒
--   S9  invalid formula settle → RAISE 且 quota/result 同 transaction 回滾
--   S10 legacy shape fresh settle＋claim replay 回同 body
--   S11 new shape fresh settle＋claim replay 回同 body（含 formula）
--   S12 late owner settle done row → stored winner（formula 原封、不再扣）
--   S13 new_topic_contract_version() = 'new-topic-exactly-once-v2'
--   S14 RLS 仍 enabled；anon/authenticated 對新 helper 無 EXECUTE

\set ON_ERROR_STOP on

BEGIN;

-- psql 變數不會在 dollar-quote 內展開：先落到 transaction-local GUC。
SELECT set_config('smoke.test_user', :'test_user', true);

DO $smoke$
DECLARE
  v_user UUID := current_setting('smoke.test_user')::uuid;
  v_req1 UUID := gen_random_uuid();
  v_req2 UUID := gen_random_uuid();
  v_req3 UUID := gen_random_uuid();
  v_owner1 UUID := gen_random_uuid();
  v_owner2 UUID := gen_random_uuid();
  v_hash1 TEXT := repeat('a', 64);
  v_hash2 TEXT := repeat('b', 64);
  v_hash3 TEXT := repeat('c', 64);
  v_legacy JSONB;
  v_paid2 JSONB;
  v_free2 JSONB;
  v_bad JSONB;
  v_claim JSONB;
  v_settle JSONB;
  v_monthly_before INTEGER;
  v_monthly_after INTEGER;
  v_ok BOOLEAN;

  v_topic_fixture CONSTANT JSONB := jsonb_build_object(
    'id', 'nt_1', 'direction', 'd', 'openingLine', 'o',
    'whyItWorks', 'w', 'nextMove', 'n'
  );
BEGIN
  -- 建構 fixtures --------------------------------------------------------
  v_legacy := jsonb_build_object(
    'topics', jsonb_build_array(v_topic_fixture),
    'recommendation', jsonb_build_object('topicId', 'nt_1'),
    'access', jsonb_build_object(
      'servedTier', 'free', 'limited', true, 'totalCount', 5,
      'unlockedCount', 1, 'lockedCount', 4
    )
  );
  v_free2 := v_legacy || jsonb_build_object(
    'formulaTopics', jsonb_build_array(
      jsonb_build_object('openingLine', '公式一', 'whyItWorks', '理由一'),
      jsonb_build_object('openingLine', '公式二', 'whyItWorks', '理由二')
    )
  );
  v_paid2 := jsonb_build_object(
    'topics', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', 'nt_' || n, 'direction', 'd' || n, 'openingLine', 'o' || n,
          'whyItWorks', 'w' || n, 'nextMove', 'n' || n
        )
      ) FROM generate_series(1, 5) AS n
    ),
    'recommendation', jsonb_build_object('topicId', 'nt_1'),
    'access', jsonb_build_object(
      'servedTier', 'essential', 'limited', false, 'totalCount', 5,
      'unlockedCount', 5, 'lockedCount', 0
    ),
    'formulaTopics', jsonb_build_array(
      jsonb_build_object('openingLine', '公式一', 'whyItWorks', '理由一'),
      jsonb_build_object('openingLine', '公式二', 'whyItWorks', '理由二')
    )
  );

  -- S13 contract marker --------------------------------------------------
  IF public.new_topic_contract_version() <> 'new-topic-exactly-once-v2' THEN
    RAISE EXCEPTION 'S13 FAIL: contract version = %',
      public.new_topic_contract_version();
  END IF;
  RAISE NOTICE 'S13 PASS: contract v2';

  -- S1/S2 validator 正向 --------------------------------------------------
  IF NOT public.validate_new_topic_result(v_legacy) THEN
    RAISE EXCEPTION 'S1 FAIL: legacy 三-key 應合法';
  END IF;
  RAISE NOTICE 'S1 PASS: legacy 三-key 合法';

  IF NOT public.validate_new_topic_result(
    v_legacy || jsonb_build_object('formulaTopics', '[]'::jsonb)
  ) THEN
    RAISE EXCEPTION 'S2 FAIL: formula 0 則應合法';
  END IF;
  IF NOT public.validate_new_topic_result(
    v_legacy || jsonb_build_object('formulaTopics', jsonb_build_array(
      jsonb_build_object('openingLine', '公式一', 'whyItWorks', '理由一')
    ))
  ) THEN
    RAISE EXCEPTION 'S2 FAIL: formula 1 則應合法';
  END IF;
  IF NOT public.validate_new_topic_result(v_free2) THEN
    RAISE EXCEPTION 'S2 FAIL: Free 1 題＋formula 2 應合法';
  END IF;
  IF NOT public.validate_new_topic_result(v_paid2) THEN
    RAISE EXCEPTION 'S2 FAIL: Paid 5 題＋formula 2 應合法';
  END IF;
  RAISE NOTICE 'S2 PASS: 0/1/2 則、Free/Paid 全合法';

  -- S3–S8 validator 負向 --------------------------------------------------
  v_bad := v_legacy || jsonb_build_object('formulaTopics', jsonb_build_array(
    jsonb_build_object('openingLine', '一', 'whyItWorks', 'w'),
    jsonb_build_object('openingLine', '二', 'whyItWorks', 'w'),
    jsonb_build_object('openingLine', '三', 'whyItWorks', 'w')
  ));
  IF public.validate_new_topic_result(v_bad) THEN
    RAISE EXCEPTION 'S3 FAIL: 三則 formula 應拒絕';
  END IF;
  RAISE NOTICE 'S3 PASS: 三則拒絕';

  v_bad := v_legacy || jsonb_build_object('formulaTopics', jsonb_build_array(
    jsonb_build_object('openingLine', '只有一欄')
  ));
  IF public.validate_new_topic_result(v_bad) THEN
    RAISE EXCEPTION 'S4 FAIL: 缺欄應拒絕';
  END IF;
  -- Codex 首審 P2＋二審 U+0085：whitespace-only（\t、全形空白 U+3000、
  -- NEL U+0085）必須被 DB 拒絕，空白語意＝JS/Dart trim 聯集。
  IF public.validate_new_topic_formula_topics(jsonb_build_array(
       jsonb_build_object('openingLine', E'\t', 'whyItWorks', '理由')
     ))
     OR public.validate_new_topic_formula_topics(jsonb_build_array(
       jsonb_build_object('openingLine', '句子', 'whyItWorks', U&'\3000')
     ))
     OR public.validate_new_topic_formula_topics(jsonb_build_array(
       jsonb_build_object('openingLine', U&'\0085', 'whyItWorks', '理由')
     )) THEN
    RAISE EXCEPTION 'S4 FAIL: whitespace-only 欄位應拒絕';
  END IF;
  RAISE NOTICE 'S4 PASS: 缺欄＋whitespace-only（\t/U+3000/U+0085）拒絕';

  v_bad := v_legacy || jsonb_build_object('formulaTopics', jsonb_build_array(
    jsonb_build_object(
      'openingLine', repeat('長', 181), 'whyItWorks', '理由'
    )
  ));
  IF public.validate_new_topic_result(v_bad) THEN
    RAISE EXCEPTION 'S5 FAIL: openingLine 181 字應拒絕';
  END IF;
  v_bad := v_legacy || jsonb_build_object('formulaTopics', jsonb_build_array(
    jsonb_build_object(
      'openingLine', '句子', 'whyItWorks', repeat('長', 301)
    )
  ));
  IF public.validate_new_topic_result(v_bad) THEN
    RAISE EXCEPTION 'S5 FAIL: whyItWorks 301 字應拒絕';
  END IF;
  RAISE NOTICE 'S5 PASS: 超長拒絕（char_length 對齊 code points）';

  v_bad := v_legacy || jsonb_build_object('formulaTopics', jsonb_build_array(
    jsonb_build_object(
      'openingLine', '句子', 'whyItWorks', '理由', 'nextMove', 'leak'
    )
  ));
  IF public.validate_new_topic_result(v_bad) THEN
    RAISE EXCEPTION 'S6 FAIL: 多餘 item key 應拒絕';
  END IF;
  RAISE NOTICE 'S6 PASS: 多餘 key 拒絕';

  v_bad := v_legacy || jsonb_build_object(
    'formulaTopics', jsonb_build_object('openingLine', 'x')
  );
  IF public.validate_new_topic_result(v_bad) THEN
    RAISE EXCEPTION 'S7 FAIL: 非 array 應拒絕';
  END IF;
  RAISE NOTICE 'S7 PASS: 非 array 拒絕';

  v_bad := v_legacy || jsonb_build_object('somethingElse', '[]'::jsonb);
  IF public.validate_new_topic_result(v_bad) THEN
    RAISE EXCEPTION 'S8 FAIL: 未知頂層鍵應拒絕';
  END IF;
  RAISE NOTICE 'S8 PASS: 未知頂層鍵拒絕';

  -- S9 invalid formula settle → RAISE＋rollback（子交易模擬）-------------
  SELECT monthly_messages_used INTO v_monthly_before
  FROM public.subscriptions WHERE user_id = v_user;
  IF v_monthly_before IS NULL THEN
    RAISE EXCEPTION 'SMOKE SETUP FAIL: 測試帳號無 subscriptions row';
  END IF;

  v_claim := public.claim_new_topic_request(v_user, v_req1, v_hash1, v_owner1);
  IF v_claim ->> 'kind' <> 'claimed' THEN
    RAISE EXCEPTION 'S9 SETUP FAIL: claim = %', v_claim;
  END IF;
  BEGIN
    PERFORM public.settle_new_topic_request(
      v_user, v_req1, v_hash1, v_owner1,
      v_legacy || jsonb_build_object(
        'formulaTopics', jsonb_build_array(
          jsonb_build_object('openingLine', '', 'whyItWorks', '理由')
        )
      ),
      1000, 1000, TRUE
    );
    RAISE EXCEPTION 'S9 FAIL: invalid formula settle 應 RAISE';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%invalid p_result_json%' THEN
        RAISE EXCEPTION 'S9 FAIL: 非預期錯誤 %', SQLERRM;
      END IF;
  END;
  SELECT monthly_messages_used INTO v_monthly_after
  FROM public.subscriptions WHERE user_id = v_user;
  IF v_monthly_after <> v_monthly_before THEN
    RAISE EXCEPTION 'S9 FAIL: quota 未回滾（% → %）',
      v_monthly_before, v_monthly_after;
  END IF;
  SELECT state = 'pending' AND result_json IS NULL INTO v_ok
  FROM public.new_topic_requests
  WHERE user_id = v_user AND request_id = v_req1;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'S9 FAIL: row 未維持 pending/result null';
  END IF;
  RAISE NOTICE 'S9 PASS: invalid formula settle 同 transaction 回滾';

  -- S10 legacy shape settle＋replay ---------------------------------------
  v_settle := public.settle_new_topic_request(
    v_user, v_req1, v_hash1, v_owner1, v_legacy, 1000, 1000, FALSE
  );
  IF (v_settle -> 'result') <> v_legacy THEN
    RAISE EXCEPTION 'S10 FAIL: legacy settle result 不符';
  END IF;
  v_claim := public.claim_new_topic_request(v_user, v_req1, v_hash1, v_owner2);
  IF v_claim ->> 'kind' <> 'replay'
     OR (v_claim -> 'result') <> v_legacy THEN
    RAISE EXCEPTION 'S10 FAIL: legacy replay 不符：%', v_claim;
  END IF;
  RAISE NOTICE 'S10 PASS: legacy fresh settle＋replay 同 body';

  -- S11 new shape settle＋replay（含 formula）-----------------------------
  v_claim := public.claim_new_topic_request(v_user, v_req2, v_hash2, v_owner1);
  IF v_claim ->> 'kind' <> 'claimed' THEN
    RAISE EXCEPTION 'S11 SETUP FAIL: claim = %', v_claim;
  END IF;
  v_settle := public.settle_new_topic_request(
    v_user, v_req2, v_hash2, v_owner1, v_paid2, 1000, 1000, FALSE
  );
  IF (v_settle -> 'result') <> v_paid2 THEN
    RAISE EXCEPTION 'S11 FAIL: new shape settle result 不符';
  END IF;
  v_claim := public.claim_new_topic_request(v_user, v_req2, v_hash2, v_owner2);
  IF v_claim ->> 'kind' <> 'replay'
     OR (v_claim -> 'result' -> 'formulaTopics')
       <> (v_paid2 -> 'formulaTopics') THEN
    RAISE EXCEPTION 'S11 FAIL: new shape replay formula 不符：%', v_claim;
  END IF;
  RAISE NOTICE 'S11 PASS: new shape fresh settle＋replay formula 一致';

  -- S12 late owner settle done row → stored winner ------------------------
  v_settle := public.settle_new_topic_request(
    v_user, v_req2, v_hash2, v_owner1,
    v_free2, 1000, 1000, FALSE
  );
  IF (v_settle ->> 'charged')::BOOLEAN
     OR (v_settle -> 'result') <> v_paid2 THEN
    RAISE EXCEPTION 'S12 FAIL: done row 應回 stored winner（不再扣）：%',
      v_settle;
  END IF;
  RAISE NOTICE 'S12 PASS: stored winner 原封（formula 不被 late owner 蓋掉）';

  -- S14 RLS＋privileges ----------------------------------------------------
  IF NOT (
    SELECT relrowsecurity FROM pg_class
    WHERE oid = to_regclass('public.new_topic_requests')
  ) THEN
    RAISE EXCEPTION 'S14 FAIL: RLS 未啟用';
  END IF;
  IF has_function_privilege(
       'anon', 'public.validate_new_topic_formula_topics(jsonb)', 'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated', 'public.validate_new_topic_formula_topics(jsonb)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role', 'public.validate_new_topic_formula_topics(jsonb)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'S14 FAIL: 新 helper privilege 矩陣不符';
  END IF;
  RAISE NOTICE 'S14 PASS: RLS enabled＋helper privilege 矩陣正確';

  RAISE NOTICE 'ALL FORMULA SMOKE STATES PASSED (S1–S14)';
END;
$smoke$;

-- 絕不留資料：整包回滾（正式 verified 記錄以 NOTICE 輸出為準）。
ROLLBACK;

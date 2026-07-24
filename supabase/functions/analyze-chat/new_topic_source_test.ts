// 新話題 integration/migration source-scan 回歸（2026-07-24 計畫 §10.5/§11）。
// 深層行為由 payload/billing/prompt 單元測試蓋；這裡鎖 index.ts 分支順序、
// generic gate 排除、settlement 權威與 migration 的 correctness 錨點。
import {
  assert,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const indexSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260724120000_new_topic_exactly_once.sql",
    import.meta.url,
  ),
);
const formulaMigrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260724180000_new_topic_formula_topics.sql",
    import.meta.url,
  ),
);

Deno.test("index：new_topic 不被 generic analyze gates／optimize shape 接管", () => {
  assert(indexSource.includes('const isNewTopicMode = rawMode === "new_topic";'));
  // optimize shape 排除 new_topic（同 opener 前例）。
  assert(indexSource.includes('rawMode !== "opener" &&\n      rawMode !== "new_topic" &&'));
  // generic 月/日 gate 排除（new_topic 用自己的固定 cost 3 gate）。
  const monthlyGate = indexSource.indexOf(
    "!recognizeOnly && !isOpenerMode && !isNewTopicMode && !accountIsTest &&",
  );
  assert(monthlyGate >= 0);
  assert(
    indexSource.indexOf(
      "!recognizeOnly && !isOpenerMode && !isNewTopicMode && !accountIsTest &&",
      monthlyGate + 1,
    ) > monthlyGate,
    "月與日兩個 generic gate 都必須排除 new_topic",
  );
});

Deno.test("index：new_topic branch 固定順序 sanitize→material→config→preflight→claim→quota→rate→renew→generate→settle", () => {
  const branch = indexSource.indexOf("if (isNewTopicMode) {");
  assert(branch >= 0, "new_topic branch 必須存在");
  const openerBranch = indexSource.indexOf("if (isOpenerMode) {");
  assert(branch < openerBranch, "new_topic branch 在 opener branch 之前");

  const anchors = [
    "sanitizeNewTopicRequest(",
    "NEW_TOPIC_CONTEXT_REQUIRED",
    "isStrongNewTopicReplayHmacKey(newTopicHmacSecret)",
    "computeNewTopicInputHash({",
    "classifyNewTopicReplayPreflight(",
    "claimNewTopicRequest({",
    "new_topic_quota_exceeded",
    'scope: "new_topic"',
    // 模型派發前 renew claim（第二個 claimNewTopicRequest 呼叫在 rate gate 後）
    "handleNewTopicClaimOutcome(renewal)",
    "callClaudeWithFallback(",
    "buildNewTopicLedgerResult({",
    "settleNewTopicRequest({",
  ];
  let cursor = branch;
  for (const anchor of anchors) {
    const at = indexSource.indexOf(anchor, cursor);
    assert(
      at > cursor && at < openerBranch + 1000,
      `分支順序錨點缺失或錯位：${anchor}`,
    );
    cursor = at;
  }
});

Deno.test("index：new_topic 契約鐵律錨點", () => {
  const branch = indexSource.slice(
    indexSource.indexOf("if (isNewTopicMode) {"),
    indexSource.indexOf("// ── Opener mode: generate opening lines ──"),
  );
  // 缺 secret 只有 new_topic fail closed。
  assert(branch.includes("NEW_TOPIC_REPLAY_NOT_CONFIGURED"));
  // ledger read 失敗 fail closed（不打模型不扣）。
  assert(branch.includes("NEW_TOPIC_REPLAY_UNAVAILABLE"));
  // repair 用剛才成功輸出的同一 model 且禁 model fallback。
  assert(branch.includes("model: newTopicApiResult.model"));
  assert(branch.includes("allowModelFallback: false"));
  // handler 永遠回 settlement 的 stored result。
  assert(branch.includes("settlement.result as unknown as Record<string, unknown>"));
  // settle transport 不明絕不 release：retryable 分支不得呼叫 release。
  const retryableAt = branch.indexOf('settlement.kind === "retryable"');
  const failedAt = branch.indexOf('// settlement.kind === "failed"');
  assert(retryableAt > 0 && failedAt > retryableAt);
  const retryableBlock = branch.slice(retryableAt, failedAt);
  assert(
    !retryableBlock.includes("releaseNewTopicCurrentClaim"),
    "settlement retryable（結果不明）絕不 release",
  );
  assert(retryableBlock.includes("NEW_TOPIC_SETTLEMENT_PENDING"));
  // fresh 與 replay 成功 body 一致：usage.cost 常數 3。
  assert(branch.includes("usage: { cost: 3 }"));
  // MODEL_RATE_LIMITED 走 verdict payload（無 quota keys），quota 429 帶
  // quotaNeeded: 3。
  assert(branch.includes("quotaNeeded: newTopicCost"));
});

Deno.test("index：telemetry 事件名逐項對齊計畫 §14.1（Eric 2026-07-24 拍板）", () => {
  const branch = indexSource.slice(
    indexSource.indexOf("if (isNewTopicMode) {"),
    indexSource.indexOf("// ── Opener mode: generate opening lines ──"),
  );
  for (
    const event of [
      "new_topic_request_received",
      "new_topic_replay_hit",
      "new_topic_request_pending",
      "new_topic_claim_acquired",
      "new_topic_model_rate_limited",
      "new_topic_response_repaired",
      "new_topic_response_invalid",
      "new_topic_claim_released",
      "new_topic_settlement_succeeded",
      "new_topic_settlement_replayed",
      "new_topic_settlement_pending",
      "new_topic_success",
    ]
  ) {
    assert(branch.includes(`"${event}"`), `§14.1 事件缺席：${event}`);
  }
  // received 只記合法請求（sanitize＋material 過後），400/422 不佔計數。
  const received = branch.indexOf('"new_topic_request_received"');
  const configCheck = branch.indexOf("NEW_TOPIC_REPLAY_NOT_CONFIGURED");
  assert(
    branch.indexOf("NEW_TOPIC_CONTEXT_REQUIRED") < received &&
      received < configCheck,
    "request_received 必須在 material 檢查後、config 檢查前",
  );
  // 禁止記錄面（§14.3）：素材原文欄位絕不進 telemetry payload。
  assertFalse(
    /log(Info|Warn|Error)\("new_topic_[^"]*",\s*\{[^}]*partnerSummary:/s.test(
      branch,
    ),
    "telemetry 不得帶 raw partnerSummary",
  );
});

Deno.test("migration：claim/settle/release/cleanup/contract marker 俱全", () => {
  const claim = migrationSource.indexOf("claim_new_topic_request");
  const settle = migrationSource.indexOf("settle_new_topic_request");
  const increment = migrationSource.indexOf("PERFORM public.increment_usage");
  assert(claim >= 0 && settle > claim && increment > settle);
  assert(migrationSource.includes("PRIMARY KEY (user_id, request_id)"));
  assert(migrationSource.includes("input_hash ~ '^[0-9a-f]{64}$'"));
  assert(migrationSource.includes("state IN ('pending', 'done')"));
  assert(migrationSource.includes("release_new_topic_claim"));
  assert(migrationSource.includes("cleanup_expired_new_topic_requests"));
  assert(migrationSource.includes("new_topic_contract_version"));
  assert(migrationSource.includes("'new-topic-exactly-once-v1'"));
  assert(migrationSource.includes("interval '65 seconds'"));
  assert(migrationSource.includes("interval '24 hours'"));
  assert(migrationSource.includes("'43 * * * *'"));
  assert(migrationSource.includes("SECURITY DEFINER"));
  assert(migrationSource.includes("SET search_path = public"));
  assert(
    migrationSource.includes(
      "REVOKE ALL ON TABLE public.new_topic_requests FROM anon, authenticated",
    ),
  );
  assert(
    migrationSource.includes("GRANT SELECT ON TABLE public.new_topic_requests"),
  );
  assert(migrationSource.includes("TO service_role"));
  assert(migrationSource.includes("NEW_TOPIC_REQUEST_REPLAY_MISMATCH"));
  assert(migrationSource.includes("NEW_TOPIC_REQUEST_OWNER_MISMATCH"));
  assert(migrationSource.includes("AND owner_token = p_owner_token"));
  assert(migrationSource.includes("AND state = 'pending'"));
  assert(migrationSource.includes("NOTIFY pgrst, 'reload schema';"));
});

Deno.test("migration：settle 固定扣 3、result 白名單、tier 投影一致性", () => {
  // 固定成本 3（increment_usage 第二參數）。
  assert(/PERFORM public\.increment_usage\(\s*p_user_id,\s*3,/m.test(migrationSource));
  // 頂層恰三鍵（減鍵法）。
  assert(
    migrationSource.includes("?& ARRAY['topics', 'recommendation', 'access']"),
  );
  assert(
    migrationSource.includes("- 'topics' - 'recommendation' - 'access'"),
  );
  // Free 1 題鎖 4／Paid 5 題鎖 0。
  assert(migrationSource.includes("jsonb_array_length(result_json -> 'topics') = 1"));
  assert(migrationSource.includes("jsonb_array_length(result_json -> 'topics') = 5"));
  // 深層驗證 helper：欄位 cap、nt ID、推薦存在性。
  assert(migrationSource.includes("validate_new_topic_result"));
  assert(migrationSource.includes("'^nt_[1-5]$'"));
  assert(migrationSource.includes("length(v_direction) > 80"));
  assert(migrationSource.includes("length(v_opening) > 180"));
  assert(migrationSource.includes("length(v_why) > 400"));
  assert(migrationSource.includes("length(v_next) > 300"));
  assert(migrationSource.includes("v_rec_topic_id = ANY (v_seen_ids)"));
  // settle 內 lock subscription row＋quota race 同 transaction 回滾。
  assert(migrationSource.includes("FROM public.subscriptions"));
  assert(migrationSource.includes("FOR UPDATE"));
});

// ---------------------------------------------------------------------------
// 20260724180000 formulaTopics additive migration（公式回覆計畫 §7.3）
// ---------------------------------------------------------------------------

Deno.test("formula migration：additive——只動 constraint／validator／marker，不碰 claim/settle/release/cron/RLS", () => {
  // 舊 migration 檔本身不得被改：v1 marker 與原三-key constraint 錨點仍在。
  assert(migrationSource.includes("'new-topic-exactly-once-v1'"));
  assert(
    migrationSource.includes("- 'topics' - 'recommendation' - 'access')"),
    "舊 migration 減鍵法必須維持原樣（不含 formulaTopics）",
  );

  // 新 migration 不得重定義 claim/settle/release/cleanup，也不得動表資料
  // 或 cron（marker 函式內的 to_regprocedure 存在性檢查是合法引用）。
  for (
    const forbidden of [
      "CREATE OR REPLACE FUNCTION public.claim_new_topic_request",
      "CREATE OR REPLACE FUNCTION public.settle_new_topic_request",
      "CREATE OR REPLACE FUNCTION public.release_new_topic_claim",
      "CREATE OR REPLACE FUNCTION public.cleanup_expired_new_topic_requests",
      "cron.schedule",
      "cron.unschedule",
      "increment_usage",
      "CREATE TABLE",
      "DELETE FROM",
      "DROP TABLE",
      "UPDATE public.new_topic_requests",
    ]
  ) {
    assertFalse(
      formulaMigrationSource.includes(forbidden),
      `formula migration 不得出現：${forbidden}`,
    );
  }
});

Deno.test("formula migration：四-key 相容 constraint＋深驗 helper＋v2 marker", () => {
  // constraint 以 DROP＋ADD 重建同名，減鍵法多扣 formulaTopics。
  assert(
    formulaMigrationSource.includes(
      "DROP CONSTRAINT new_topic_requests_result_state_consistency",
    ),
  );
  assert(
    formulaMigrationSource.includes(
      "ADD CONSTRAINT new_topic_requests_result_state_consistency",
    ),
  );
  assert(
    formulaMigrationSource.includes(
      "- 'formulaTopics') = '{}'::jsonb",
    ),
  );
  // legacy 三-key row 缺席 formulaTopics 仍合法。
  assert(
    formulaMigrationSource.includes("NOT (result_json ? 'formulaTopics')"),
  );

  // 深驗 helper：0–2 則、恰兩鍵、非空、char_length caps 180/300。
  assert(
    formulaMigrationSource.includes("validate_new_topic_formula_topics"),
  );
  assert(
    formulaMigrationSource.includes(
      "jsonb_array_length(p_formula_topics) > 2",
    ),
  );
  assert(
    formulaMigrationSource.includes("?& ARRAY['openingLine', 'whyItWorks']"),
  );
  assert(
    formulaMigrationSource.includes(
      "(v_item - 'openingLine' - 'whyItWorks') <> '{}'::jsonb",
    ),
  );
  assert(formulaMigrationSource.includes("char_length(v_opening) > 180"));
  assert(formulaMigrationSource.includes("char_length(v_why) > 300"));

  // validate_new_topic_result 重建為 legacy/new 相容版。
  assert(
    formulaMigrationSource.includes(
      "CREATE OR REPLACE FUNCTION public.validate_new_topic_result",
    ),
  );

  // marker：v2 只在 helper＋constraint＋功能性探針俱全時回；缺件降 v1。
  assert(formulaMigrationSource.includes("'new-topic-exactly-once-v2'"));
  assert(formulaMigrationSource.includes("'new-topic-exactly-once-v1'"));
  assert(formulaMigrationSource.includes("pg_get_constraintdef"));

  // 權限：新 helper 只給 service_role；PostgREST reload。
  assert(
    formulaMigrationSource.includes(
      "GRANT EXECUTE ON FUNCTION public.validate_new_topic_formula_topics(JSONB)",
    ),
  );
  assert(formulaMigrationSource.includes("NOTIFY pgrst, 'reload schema';"));
});

Deno.test("index：new_topic 公式資料流——只認 primary、base 定案後 normalize、公式進 ledger", () => {
  const branch = indexSource.slice(
    indexSource.indexOf("if (isNewTopicMode) {"),
    indexSource.indexOf("// ── Opener mode: generate opening lines ──"),
  );
  // 同一 primary parse 分兩條路；公式只認 primary。
  assert(
    branch.includes(
      "const newTopicPrimaryFormulaRaw = newTopicPrimaryParsed?.formulaTopics;",
    ),
  );
  // 公式 normalize 在 base 502 gate 之後、buildNewTopicLedgerResult 之前，
  // 用五題 openingLine cross-field dedupe＋內部標籤守門。
  const invalidGateAt = branch.indexOf('error: "NEW_TOPIC_RESPONSE_INVALID"');
  const formulaAt = branch.indexOf(
    "const newTopicFormulaOutcome = normalizeFormulaRepliesDetailed(",
  );
  const buildAt = branch.indexOf("buildNewTopicLedgerResult({");
  assert(
    invalidGateAt > 0 && formulaAt > invalidGateAt && buildAt > formulaAt,
    "公式 normalize 必須在 base 定案後、ledger build 前",
  );
  const formulaBlock = branch.slice(formulaAt, buildAt);
  assert(formulaBlock.includes("rejectInternalLabels: true"));
  assert(
    formulaBlock.includes("(topic) => topic.openingLine"),
    "cross-field dedupe 必須用最終五題 openingLine",
  );
  // canonical 公式必須進 ledger（不是只掛 fresh response）。
  assert(
    branch.includes("formulaTopics: newTopicFormulaOutcome.replies,"),
    "formulaTopics 必須傳入 buildNewTopicLedgerResult（replay 才有）",
  );
  // 公式 telemetry 只記數量。
  assert(branch.includes("formulaTopicsCount: newTopicFormulaOutcome.replies.length,"));
  assert(branch.includes("formulaTopicsDroppedCount: newTopicFormulaOutcome.droppedCount,"));
  // Repair 呼叫仍只修 base：repair 分支內不得出現 formula 相關字。
  const repairStart = branch.indexOf("NEW_TOPIC_REPAIR_PROMPT");
  const repairEnd = branch.indexOf("if (!newTopicNormalized.ok) {", repairStart);
  const repairBlock = branch.slice(repairStart, repairEnd);
  assertFalse(
    repairBlock.includes("formula"),
    "repair 分支不得讀寫 formula（repair 只負責 base）",
  );
});

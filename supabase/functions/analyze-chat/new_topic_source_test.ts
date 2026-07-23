// 新話題 integration/migration source-scan 回歸（2026-07-24 計畫 §10.5/§11）。
// 深層行為由 payload/billing/prompt 單元測試蓋；這裡鎖 index.ts 分支順序、
// generic gate 排除、settlement 權威與 migration 的 correctness 錨點。
import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const indexSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260724120000_new_topic_exactly_once.sql",
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

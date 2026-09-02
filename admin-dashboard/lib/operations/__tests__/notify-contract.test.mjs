// B2 聚焦契約測試。這些測試執行可載入的 TS contract，並靜態驗證尚未套用的
// migration 形狀；不宣稱已跑 PostgreSQL 或真實併發 integration。
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  NOTIFY_CHANNELS,
  NOTIFY_EXTERNAL_EVENT_REF_PATTERN,
  NOTIFY_REASON_CODES,
  NOTIFY_TEMPLATES,
  buildNotificationEvent,
} from "../notify-contract.ts";
import {
  AI_ERRORS_CUTOVER_SEQUENCE,
  AI_ERRORS_V2_RPC,
  mapAiErrorRow,
  resolveAiErrorsSource,
} from "../ai-logs-read.ts";
import { isAdminV2Enabled } from "../admin-v2.ts";
import {
  CLIENT_REQUEST_KEY_PATTERN,
  FEEDBACK_MODEL_FAMILIES,
  FEEDBACK_USER_TIERS,
  buildFeedbackV2RpcParams,
  isAdminV2FeedbackEnabled,
  normalizeClientRequestKey,
  sanitizeModelUsed,
  sanitizeUserTier,
} from "../../../../supabase/functions/submit-feedback/feedback_v2.ts";
import { VALID_FEEDBACK_CATEGORIES } from "../../../../supabase/functions/submit-feedback/feedback_utils.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "..");
const MIGRATION = readFileSync(
  join(
    ROOT,
    "supabase/migrations/20260902150000_admin_notify_feedback_breakglass_v2_baseline.sql",
  ),
  "utf8",
);
const INDEX_TS = readFileSync(
  join(ROOT, "supabase/functions/submit-feedback/index.ts"),
  "utf8",
);
const ERRORS_ROUTE = readFileSync(
  join(ROOT, "admin-dashboard/app/api/admin/errors/route.ts"),
  "utf8",
);

const quotedList = (values) => values.map((v) => `'${v}'`).join(", ");

function sqlBlock(name) {
  const start = MIGRATION.indexOf(`CREATE FUNCTION public.${name}`);
  assert.notEqual(start, -1, `migration 缺 ${name}`);
  const rest = MIGRATION.slice(start + 1);
  const end = rest.search(/\n(?:CREATE|ALTER|REVOKE|GRANT) /u);
  return MIGRATION.slice(start, end === -1 ? undefined : start + 1 + end);
}

test("通知事件是固定 schema：外部事件身分、事故身分與 retry channel 都受限", () => {
  const externalEventRef = `feedback:sha256:${"a".repeat(64)}`;
  const valid = buildNotificationEvent({
    template: "yellow",
    reasonCode: "feedback_received",
    externalEventRef,
    incidentId: null,
    userRef: `user:sha256:${"b".repeat(64)}`,
  });
  assert.equal(valid.ok, true);
  assert.equal(valid.event.externalEventRef, externalEventRef);
  assert.equal(valid.event.deliveryClass, "daily_brief");

  for (const invalid of [
    { ...valid.event, externalEventRef: "human readable event" },
    { ...valid.event, externalEventRef: "feedback:sha256:short" },
    { ...valid.event, message: "arbitrary payload" },
    { ...valid.event, deliveryClass: "immediate" },
  ]) {
    assert.equal(buildNotificationEvent(invalid).ok, false);
  }

  assert.equal(
    NOTIFY_EXTERNAL_EVENT_REF_PATTERN,
    "^[a-z][a-z0-9_.]{0,63}:sha256:[0-9a-f]{64}$",
  );
  assert.deepEqual([...NOTIFY_CHANNELS], ["discord", "email_fallback"]);
  assert.ok(MIGRATION.includes(`reason_code IN (${quotedList(NOTIFY_REASON_CODES)})`));
  assert.ok(MIGRATION.includes(`template IN (${quotedList(NOTIFY_TEMPLATES)})`));
  assert.ok(MIGRATION.includes("incident_id        UUID REFERENCES public.admin_ops_incidents"));
  assert.ok(MIGRATION.includes("external_event_ref TEXT NOT NULL UNIQUE"));
  assert.ok(MIGRATION.includes("retry_count        INTEGER NOT NULL DEFAULT 0"));
  assert.ok(MIGRATION.includes("UNIQUE (outbox_id, channel, attempt_no)"));
});

test("outbox 只暴露 operation-specific RPC；generic service-role enqueue 不存在", () => {
  const fnGrants = MIGRATION.match(/^GRANT EXECUTE ON FUNCTION [^;]*;/gmu) ?? [];
  const serviceRoleGrants = fnGrants.filter((grant) => grant.includes("TO service_role"));
  assert.deepEqual(serviceRoleGrants, [
    "GRANT EXECUTE ON FUNCTION public.admin_v2_submit_feedback(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;",
    "GRANT EXECUTE ON FUNCTION public.admin_v2_record_breakglass_runtime_occurrence(TEXT, UUID, TEXT) TO service_role;",
    "GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_capture_trusted_runtime_request(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;",
  ]);
  assert.ok(!MIGRATION.includes("admin_v2_enqueue_notification"));

  const submit = sqlBlock("admin_v2_submit_feedback");
  assert.ok(submit.includes("ON CONFLICT (request_ref) DO NOTHING"));
  assert.ok(submit.includes("IF v_id IS NOT NULL THEN"));
  assert.ok(submit.includes("external_event_ref"));
  assert.ok(submit.includes("ON CONFLICT (external_event_ref) DO UPDATE"));
  assert.ok(!/statuss*=s*'pending'/u.test(
    submit.slice(submit.indexOf("ON CONFLICT (external_event_ref)")),
  ));
});

test("V2 feedback 要求 UUID client key；同 key 重試去重、不同 key 允許同內容", async () => {
  const keyA = "c2b050de-5b7f-4fb0-aabb-ccddeeff0011";
  const keyB = "d3c161ef-6c8f-4fb0-aabb-ccddeeff0011";
  assert.ok(CLIENT_REQUEST_KEY_PATTERN.test(keyA));
  assert.equal(normalizeClientRequestKey(keyA), keyA);
  assert.equal(normalizeClientRequestKey(undefined), undefined);
  assert.equal(normalizeClientRequestKey("user supplied sentence"), undefined);
  assert.equal(normalizeClientRequestKey("person@example.com"), undefined);
  assert.equal(normalizeClientRequestKey("short"), undefined);
  assert.equal(
    normalizeClientRequestKey("c2b050de5b7f4fb0aabbccddeeff0011"),
    undefined,
  );

  const base = {
    userId: "11111111-2222-3333-4444-555555555555",
    clientRequestKey: keyA,
    rating: "negative",
    category: "too_long",
    userTier: "free",
    modelUsed: "claude-sonnet-5",
  };
  const first = await buildFeedbackV2RpcParams(base);
  const retryWithChangedMetadata = await buildFeedbackV2RpcParams({
    ...base,
    rating: "positive",
    category: "other",
    modelUsed: "deepseek-v3",
  });
  const distinctSubmission = await buildFeedbackV2RpcParams({
    ...base,
    clientRequestKey: keyB,
  });

  assert.equal(first.p_request_ref, retryWithChangedMetadata.p_request_ref);
  assert.equal(first.p_user_ref, retryWithChangedMetadata.p_user_ref);
  assert.notEqual(first.p_request_ref, distinctSubmission.p_request_ref);
  assert.notEqual(first.p_user_ref, distinctSubmission.p_user_ref);
  assert.match(first.p_user_ref, /^feedback-user:v1:[0-9a-f]{32}$/u);
  assert.match(first.p_request_ref, /^request:sha256:[0-9a-f]{64}$/u);
  assert.ok(!first.p_user_ref.includes(base.userId));
  assert.deepEqual(Object.keys(first).sort(), [
    "p_category",
    "p_model_used",
    "p_rating",
    "p_request_ref",
    "p_user_ref",
    "p_user_tier",
  ]);
  assert.equal(sanitizeUserTier(" Premium "), "premium");
  assert.equal(sanitizeUserTier("_"), "other");
  assert.equal(sanitizeModelUsed("claude-sonnet-5"), "anthropic");
  assert.equal(sanitizeModelUsed("deepseek-v3"), "deepseek");
  assert.equal(sanitizeModelUsed("glm-5"), "zai");
  assert.equal(sanitizeModelUsed("bad model!"), "other");
});

test("V2 feedback 分流不讀取自由文字；旗標關閉保留 legacy 路徑", () => {
  const gate = INDEX_TS.indexOf('if (isAdminV2FeedbackEnabled(Deno.env.get("ADMIN_V2")))');
  const legacyRaw = INDEX_TS.indexOf("const rawAiResponse = body.aiResponse;");
  const legacyInsert = INDEX_TS.indexOf('from("feedback").insert');
  assert.ok(gate !== -1);
  assert.ok(legacyRaw > gate);
  assert.ok(legacyInsert > gate);

  const v2Branch = INDEX_TS.slice(gate, legacyRaw);
  assert.ok(v2Branch.includes("normalizeClientRequestKey(body?.clientRequestId)"));
  assert.ok(!v2Branch.includes("conversationSnippet"));
  assert.ok(!v2Branch.includes("aiResponse"));
  assert.ok(!v2Branch.includes("comment:"));
  assert.ok(!v2Branch.includes("Discord"));

  for (const value of ["1", "true", "TRUE", " 1 ", "0", "false", "", undefined]) {
    assert.equal(
      isAdminV2FeedbackEnabled(value),
      isAdminV2Enabled({ ADMIN_V2: value }),
    );
  }
});

test("V2 feedback schema與RPC 不含自由文字或弱 summary 欄位", () => {
  const feedbackTable = MIGRATION.slice(
    MIGRATION.indexOf("CREATE TABLE public.admin_feedback_inbox_v2"),
    MIGRATION.indexOf("CREATE TABLE public.admin_breakglass_grants_v2"),
  );
  const submit = sqlBlock("admin_v2_submit_feedback");
  assert.ok(!feedbackTable.includes("summary"));
  assert.ok(!feedbackTable.includes("comment"));
  assert.ok(!feedbackTable.includes("conversation"));
  assert.ok(!feedbackTable.includes("ai_response"));
  assert.ok(!submit.includes("p_summary"));
  assert.ok(!submit.includes("p_comment"));
  assert.ok(!submit.includes("p_conversation"));
  assert.ok(!submit.includes("p_ai_response"));
  assert.ok(
    feedbackTable.includes(
      `category    TEXT CHECK (category IN (${quotedList([...VALID_FEEDBACK_CATEGORIES])}))`,
    ),
  );
  assert.ok(
    feedbackTable.includes(
      `user_tier   TEXT CHECK (user_tier IN (${quotedList(FEEDBACK_USER_TIERS)}))`,
    ),
  );
  assert.ok(
    feedbackTable.includes(
      `model_used  TEXT CHECK (model_used IN (${quotedList(FEEDBACK_MODEL_FAMILIES)}))`,
    ),
  );
  assert.ok(feedbackTable.includes("'^feedback-user:v1:[0-9a-f]{32}$'"));
  assert.ok(!feedbackTable.includes("'^user:sha256:[0-9a-f]{64}$'"));
  assert.ok(submit.includes("feedback 的 request-bound user_ref 只留在 inbox"));
});

test("errors route 在旗標 off/on 都選正確資料邊界，V2 只走 metadata RPC 且永不帶 raw error message", () => {
  const legacy = resolveAiErrorsSource({ ADMIN_V2: "false" });
  const v2 = resolveAiErrorsSource({ ADMIN_V2: "true" });
  assert.deepEqual(legacy, {
    mode: "legacy",
    table: "ai_logs",
    select: "id, created_at, error_code, error_message, request_type, user_id",
  });
  assert.equal(v2.mode, "v2");
  assert.equal(v2.rpc, AI_ERRORS_V2_RPC);
  assert.equal(v2.rpc, "admin_v2_list_error_metadata");

  const row = {
    id: "err-1",
    created_at: "2026-09-01T00:00:00.000Z",
    error_code: "TIMEOUT",
    error_message: "raw user conversation must not leave the view",
    request_type: "coach",
    user_id: "user-1",
  };
  assert.equal(mapAiErrorRow(row, "legacy").error_message, row.error_message);
  assert.equal(mapAiErrorRow(row, "v2").error_message, "");
  assert.ok(ERRORS_ROUTE.includes("resolveAiErrorsSource()"));
  assert.ok(ERRORS_ROUTE.includes("source.mode === \"v2\""));
  assert.ok(ERRORS_ROUTE.includes(".rpc(source.rpc)"));
  assert.ok(ERRORS_ROUTE.includes(".from(source.table)"));
  assert.ok(ERRORS_ROUTE.includes(".select(source.select)"));
  assert.ok(!ERRORS_ROUTE.includes('from("ai_logs")'));
  assert.ok(!ERRORS_ROUTE.includes('select("id, created_at, error_code, error_message'));
});

test("DB cutover 預設關閉；V2 errors 僅限完整 session-gated RPC，且切換順序固定", () => {
  assert.ok(MIGRATION.includes("CREATE TABLE public.admin_v2_settings"));
  assert.ok(MIGRATION.includes("ai_logs_cutover_enabled    BOOLEAN NOT NULL DEFAULT false"));
  assert.ok(MIGRATION.includes("VALUES (true, false)"));
  assert.ok(MIGRATION.includes("CREATE FUNCTION public.admin_v2_ai_logs_cutover_enabled()"));

  const policyStart = MIGRATION.indexOf("CREATE POLICY admin_ai_logs_block_raw_for_v2_admins");
  const policyEnd = MIGRATION.indexOf(";", policyStart);
  const policy = MIGRATION.slice(policyStart, policyEnd);
  assert.ok(policy.includes("public.admin_v2_ai_logs_cutover_enabled()"));
  assert.ok(policy.includes("AND public.admin_v2_is_active_admin()"));

  const metadata = sqlBlock("admin_v2_list_error_metadata");
  assert.ok(metadata.includes("admin_v2_authenticated_session_gate(false)"));
  for (const rawColumn of ["request_body", "response_body", "error_message"]) {
    assert.ok(!metadata.includes(rawColumn), `metadata RPC 不得含 ${rawColumn}`);
  }
  assert.ok(metadata.includes("SELECT l.id, l.created_at, l.error_code, l.request_type, l.user_id"));
  assert.ok(!MIGRATION.includes("CREATE VIEW public.admin_ai_logs_meta_v2"));
  assert.ok(!MIGRATION.includes("GRANT SELECT ON TABLE public.admin_ai_logs_meta_v2"));
  assert.ok(
    MIGRATION.includes(
      "GRANT EXECUTE ON FUNCTION public.admin_v2_list_error_metadata() TO authenticated;",
    ),
  );
  assert.deepEqual(AI_ERRORS_CUTOVER_SEQUENCE, [
    "deploy-v2-metadata-route-and-rpc",
    "enable-db-ai-logs-cutover",
    "disable-db-ai-logs-cutover",
    "disable-admin-v2-route",
  ]);
});

test("所有 authenticated V2 operation 都經完整 B1 session gate；AAL1、撤銷、version 與 timeout fail closed", () => {
  const gate = sqlBlock("admin_v2_authenticated_session_gate");
  for (const required of [
    "auth.uid()",
    "auth.jwt() ->> 'aal'",
    "v_sid_text",
    "a.is_active",
    "a.role IN ('owner', 'founder_admin')",
    "v_session.revoked_at IS NOT NULL",
    "v_session.session_version <> v_account.session_version",
    "INTERVAL '12 hours'",
    "INTERVAL '30 minutes'",
    "INTERVAL '10 minutes'",
    "auth.jwt() -> 'amr'",
    "v_amr #>> '{0,method}'",
    "v_amr #>> '{0,timestamp}'",
    "v_amr_method NOT IN ('totp', 'phone', 'webauthn', 'mfa')",
    "to_timestamp(v_amr_timestamp::double precision)",
  ]) {
    assert.ok(gate.includes(required), `session gate 缺 ${required}`);
  }
  assert.ok(!gate.includes("last_reauth_at"), "fresh reauth 不得信任 session insert timestamp");
  assert.ok(gate.includes("COALESCE(auth.jwt() ->> 'aal', '') <> 'aal2'"), "AAL1 必須拒絕");
  assert.ok(gate.includes("v_session.revoked_at IS NOT NULL"), "revoked 必須拒絕");
  assert.ok(gate.includes("v_session.session_version <> v_account.session_version"), "version mismatch 必須拒絕");
  assert.ok(gate.includes("now() - v_session.created_at > INTERVAL '12 hours'"), "absolute timeout 必須拒絕");
  assert.ok(gate.includes("now() - v_session.last_seen_at > INTERVAL '30 minutes'"), "idle timeout 必須拒絕");
  assert.ok(gate.includes("token_refresh 不能把舊 MFA 變成 fresh"));

  const expected = {
    admin_v2_list_error_metadata: false,
    admin_v2_breakglass_activate: true,
    admin_v2_breakglass_view: false,
    admin_v2_breakglass_export: false,
    admin_v2_breakglass_extend: true,
    admin_v2_breakglass_close: false,
    admin_v2_breakglass_purge_expired: false,
  };
  for (const [name, requiresReauth] of Object.entries(expected)) {
    const block = sqlBlock(name);
    assert.ok(
      block.includes(`admin_v2_authenticated_session_gate(${requiresReauth})`),
      `${name} 必須使用 shared gate`,
    );
  }
  const grants = MIGRATION.match(/^GRANT EXECUTE ON FUNCTION [^;]*;/gmu) ?? [];
  assert.ok(!grants.some((grant) => grant.includes("content_gate")));
  assert.ok(!grants.some((grant) => grant.includes("session_gate")));
  assert.ok(!grants.some((grant) => grant.includes("trusted_runtime_request") && grant.includes("TO authenticated")));
  assert.ok(!grants.some((grant) => grant.includes("runtime_occurrence") && grant.includes("TO authenticated")));
});

test("trusted runtime capture contract 收斂 provenance、future request、retry、三次 cap 與 key/nonce uniqueness", () => {
  const occurrence = sqlBlock("admin_v2_record_breakglass_runtime_occurrence");
  const capture = sqlBlock("admin_v2_breakglass_capture_trusted_runtime_request");
  assert.ok(MIGRATION.includes("UNIQUE (grant_id, request_ref)"));
  assert.ok(MIGRATION.includes("UNIQUE (key_ref, nonce_hex)"));
  assert.ok(!MIGRATION.includes("plaintext_sha256"));
  assert.ok(!MIGRATION.includes("admin_v2_breakglass_record_capture"));
  assert.ok(MIGRATION.includes("CREATE TABLE public.admin_breakglass_request_occurrences_v2"));
  assert.ok(MIGRATION.includes("occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now()"));
  assert.ok(!occurrence.includes("p_occurred_at"));
  assert.ok(occurrence.includes("auth.role() <> 'service_role'"));
  assert.ok(capture.includes("auth.role() <> 'service_role'"));
  assert.ok(!capture.includes("p_scope_user_id"));
  assert.ok(!capture.includes("p_scope_function"));
  assert.ok(capture.includes("v_occurrence.scope_user_id IS DISTINCT FROM v_grant.scope_user_id"));
  assert.ok(capture.includes("v_occurrence.scope_function IS DISTINCT FROM v_grant.scope_function"));
  assert.ok(capture.includes("v_occurrence.occurred_at < v_grant.activated_at"));
  assert.ok(capture.includes("v_occurrence.occurred_at >= v_grant.expires_at"));
  assert.ok(capture.includes("FOR UPDATE"));
  assert.ok(capture.includes("v_grant.captures_used >= v_grant.captures_max"));
  assert.ok(capture.includes("ON CONFLICT (grant_id, request_ref) DO NOTHING"));
  assert.ok(capture.includes("RETURN v_id;"));
  assert.ok(MIGRATION.includes("captures_max            INTEGER NOT NULL DEFAULT 3 CHECK (captures_max = 3)"));
  assert.ok(MIGRATION.includes("nonce_hex      TEXT NOT NULL"));
  assert.ok(MIGRATION.includes("SET ciphertext_b64 = NULL, purged_at = now()"));
  assert.ok(capture.includes("'breakglass.capture'"));
  assert.ok(capture.includes("INSERT INTO public.admin_audit_events_v2"));
});

test("activate 同 scope 只保留一個 open grant；過期未 close grant 先安全收斂", () => {
  const activate = sqlBlock("admin_v2_breakglass_activate");
  assert.ok(MIGRATION.includes("admin_breakglass_grants_v2_one_open_scope_idx"));
  assert.ok(MIGRATION.includes("WHERE closed_at IS NULL"));
  assert.ok(activate.includes("AND g.expires_at <= now()"));
  assert.ok(activate.includes("SET closed_at = now(), closed_by = v_actor.actor_user_id"));
  assert.ok(activate.includes("AND g.expires_at > now()"));
  assert.ok(activate.includes("FOR UPDATE"));
  assert.ok(activate.includes("ON CONFLICT (scope_user_id, scope_function) WHERE closed_at IS NULL DO NOTHING"));
  assert.ok(activate.includes("breakglass grant already active for scope"));
});

test("migration 全部 SECURITY DEFINER 均固定 search_path，且 break-glass audit 仍存在", () => {
  const sqlOnly = MIGRATION
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("--"))
    .join("\n");
  const definers = sqlOnly.match(/SECURITY DEFINER/gu) ?? [];
  const pinned = sqlOnly.match(/SET search_path = ''/gu) ?? [];
  assert.ok(definers.length > 0);
  assert.equal(definers.length, pinned.length);

  for (const [functionName, auditAction] of Object.entries({
    admin_v2_breakglass_activate: "breakglass.activate",
    admin_v2_breakglass_capture_trusted_runtime_request: "breakglass.capture",
    admin_v2_breakglass_view: "breakglass.view",
    admin_v2_breakglass_export: "breakglass.export",
    admin_v2_breakglass_extend: "breakglass.extend",
    admin_v2_breakglass_close: "breakglass.close",
    admin_v2_breakglass_purge_expired: "breakglass.purge",
  })) {
    const block = sqlBlock(functionName);
    assert.ok(block.includes("INSERT INTO public.admin_audit_events_v2"));
    assert.ok(block.includes(`'${auditAction}'`));
  }
});

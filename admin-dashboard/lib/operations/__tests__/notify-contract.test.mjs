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
    "supabase/migrations/20260831180000_admin_notify_feedback_breakglass_v2_baseline.sql",
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
  assert.notEqual(first.p_request_ref, distinctSubmission.p_request_ref);
  assert.match(first.p_user_ref, /^user:sha256:[0-9a-f]{64}$/u);
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
});

test("errors route 在旗標 off/on 都選正確資料邊界，V2 永不帶 raw error message", () => {
  const legacy = resolveAiErrorsSource({ ADMIN_V2: "false" });
  const v2 = resolveAiErrorsSource({ ADMIN_V2: "true" });
  assert.deepEqual(legacy, {
    mode: "legacy",
    table: "ai_logs",
    select: "id, created_at, error_code, error_message, request_type, user_id",
  });
  assert.equal(v2.mode, "v2");
  assert.equal(v2.table, "admin_ai_logs_meta_v2");
  assert.ok(!v2.select.includes("error_message"));

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
  assert.ok(ERRORS_ROUTE.includes(".from(source.table)"));
  assert.ok(ERRORS_ROUTE.includes(".select(source.select)"));
  assert.ok(!ERRORS_ROUTE.includes('from("ai_logs")'));
  assert.ok(!ERRORS_ROUTE.includes('select("id, created_at, error_code, error_message'));
});

test("DB cutover 預設關閉；打開後才封鎖 active V2 raw ai_logs，view 可供 authenticated JWT 使用", () => {
  assert.ok(MIGRATION.includes("CREATE TABLE public.admin_v2_settings"));
  assert.ok(MIGRATION.includes("ai_logs_cutover_enabled    BOOLEAN NOT NULL DEFAULT false"));
  assert.ok(MIGRATION.includes("VALUES (true, false)"));
  assert.ok(MIGRATION.includes("CREATE FUNCTION public.admin_v2_ai_logs_cutover_enabled()"));

  const policyStart = MIGRATION.indexOf("CREATE POLICY admin_ai_logs_block_raw_for_v2_admins");
  const policyEnd = MIGRATION.indexOf(";", policyStart);
  const policy = MIGRATION.slice(policyStart, policyEnd);
  assert.ok(policy.includes("public.admin_v2_ai_logs_cutover_enabled()"));
  assert.ok(policy.includes("AND public.admin_v2_is_active_admin()"));

  const viewStart = MIGRATION.indexOf("CREATE VIEW public.admin_ai_logs_meta_v2");
  const viewEnd = MIGRATION.indexOf(";", viewStart);
  const view = MIGRATION.slice(viewStart, viewEnd);
  for (const rawColumn of ["request_body", "response_body", "error_message"]) {
    assert.ok(!view.includes(rawColumn), `view 不得含 ${rawColumn}`);
  }
  assert.ok(MIGRATION.includes("GRANT SELECT ON TABLE public.admin_ai_logs_meta_v2            TO authenticated;"));
  assert.ok(
    MIGRATION.includes(
      "GRANT EXECUTE ON FUNCTION public.admin_v2_ai_logs_cutover_enabled() TO authenticated;",
    ),
  );
});

test("所有外部 break-glass entry point 都經同一完整 B1 session gate；activate/extend 要 fresh reauth", () => {
  const gate = sqlBlock("admin_v2_breakglass_session_gate");
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
  ]) {
    assert.ok(gate.includes(required), `session gate 缺 ${required}`);
  }

  const expected = {
    admin_v2_breakglass_activate: true,
    admin_v2_breakglass_record_capture: false,
    admin_v2_breakglass_view: false,
    admin_v2_breakglass_export: false,
    admin_v2_breakglass_extend: true,
    admin_v2_breakglass_close: false,
    admin_v2_breakglass_purge_expired: false,
  };
  for (const [name, requiresReauth] of Object.entries(expected)) {
    const block = sqlBlock(name);
    assert.ok(
      block.includes(`admin_v2_breakglass_session_gate(${requiresReauth})`),
      `${name} 必須使用 shared gate`,
    );
  }
  const grants = MIGRATION.match(/^GRANT EXECUTE ON FUNCTION [^;]*;/gmu) ?? [];
  assert.ok(!grants.some((grant) => grant.includes("content_gate")));
  assert.ok(!grants.some((grant) => grant.includes("session_gate")));
});

test("capture contract 靜態收斂 scope、retry、三次 cap 與 key/nonce uniqueness", () => {
  const capture = sqlBlock("admin_v2_breakglass_record_capture");
  assert.ok(MIGRATION.includes("UNIQUE (grant_id, request_ref)"));
  assert.ok(MIGRATION.includes("UNIQUE (key_ref, nonce_hex)"));
  assert.ok(!MIGRATION.includes("plaintext_sha256"));
  assert.ok(capture.includes("p_scope_user_id"));
  assert.ok(capture.includes("p_scope_function"));
  assert.ok(capture.includes("g.scope_user_id = p_scope_user_id"));
  assert.ok(capture.includes("g.scope_function = p_scope_function"));
  assert.ok(capture.includes("g.activated_at <= now()"));
  assert.ok(capture.includes("g.captures_used < g.captures_max"));
  assert.ok(capture.includes("ON CONFLICT (grant_id, request_ref) DO NOTHING"));
  assert.ok(capture.includes("RETURN v_id;"));
  assert.ok(MIGRATION.includes("captures_max            INTEGER NOT NULL DEFAULT 3 CHECK (captures_max = 3)"));
  assert.ok(MIGRATION.includes("nonce_hex      TEXT NOT NULL"));
  assert.ok(MIGRATION.includes("SET ciphertext_b64 = NULL, purged_at = now()"));
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

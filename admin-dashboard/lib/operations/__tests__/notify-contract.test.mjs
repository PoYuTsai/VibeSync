// B2 聚焦測試。執行：cd admin-dashboard && node --test lib/operations/__tests__/notify-contract.test.mjs
// 沿用 B0/B1 作法：.mjs＋Node 22 type stripping 直接載入 .ts 契約，不裝測試框架。
// SQL 側的 enum／pattern／上限與 TS 契約「逐字或同值同源」，用 readFileSync
// 對 migration 原文比對；RPC 的 audit 原子性與 ACL 收斂也在這裡做靜態驗證。
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  NOTIFY_TEMPLATES,
  TEMPLATE_DELIVERY_CLASS,
  YELLOW_ESCALATION,
  NOTIFY_REASON_CODES,
  NOTIFY_CHANNELS,
  NOTIFY_USER_REF_PATTERN,
  NOTIFY_DEDUPE_KEY_PATTERN,
  FEEDBACK_REQUEST_REF_PATTERN,
  buildNotificationEvent,
  BREAKGLASS_GRANT_TTL_MS,
  BREAKGLASS_MAX_CAPTURES,
  BREAKGLASS_CAPTURE_TTL_MS,
  BREAKGLASS_MAX_EXTENSIONS,
  BREAKGLASS_MAX_LIFETIME_MS,
  AUDIT_ACTIONS_WITH_BREAKGLASS,
  AI_LOGS_META_COLUMNS,
  AI_LOGS_RAW_COLUMNS,
} from "../notify-contract.ts";
import { ADMIN_REAUTH_FRESH_MS, AUDIT_ACTIONS } from "../admin-gate.ts";
import { isAdminV2Enabled } from "../admin-v2.ts";
import {
  FEEDBACK_SUMMARY_MAX_LENGTH,
  buildFeedbackRequestKey,
  buildFeedbackV2RpcParams,
  isAdminV2FeedbackEnabled,
  redactFeedbackSummary,
  sanitizeModelUsed,
  sanitizeUserTier,
} from "../../../../supabase/functions/submit-feedback/feedback_v2.ts";

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

const quotedList = (values) => values.map((v) => `'${v}'`).join(", ");

/** 取出一個 CREATE FUNCTION 的完整定義（到下一個頂層 CREATE/ALTER 為止）。 */
function sqlBlock(name) {
  const start = MIGRATION.indexOf(`CREATE FUNCTION public.${name}`);
  assert.notEqual(start, -1, `migration 缺 ${name}`);
  const rest = MIGRATION.slice(start + 1);
  const end = rest.search(/\n(?:CREATE|ALTER|REVOKE|GRANT) /u);
  return MIGRATION.slice(start, end === -1 ? undefined : start + 1 + end);
}

// --- 通知契約 ---

test("通知 enum／pattern 與 migration 逐字同源", () => {
  assert.ok(MIGRATION.includes(`reason_code IN (${quotedList(NOTIFY_REASON_CODES)})`));
  assert.ok(MIGRATION.includes(`channel IN (${quotedList(NOTIFY_CHANNELS)})`));
  assert.ok(MIGRATION.includes(`template IN (${quotedList(NOTIFY_TEMPLATES)})`));
  assert.ok(
    MIGRATION.includes(
      `delivery_class IN (${quotedList(Object.values(TEMPLATE_DELIVERY_CLASS))})`,
    ),
  );
  assert.ok(MIGRATION.includes(NOTIFY_USER_REF_PATTERN));
  assert.ok(MIGRATION.includes(NOTIFY_DEDUPE_KEY_PATTERN));
  assert.ok(MIGRATION.includes(FEEDBACK_REQUEST_REF_PATTERN));
  // red＝立即、yellow＝09:00 brief 的固定對應也在表上 CHECK 強制。
  assert.ok(MIGRATION.includes("template = 'red' AND delivery_class = 'immediate'"));
  assert.ok(MIGRATION.includes("template = 'yellow' AND delivery_class = 'daily_brief'"));
  // 升級門檻是 B4 契約常數：15 分鐘持續／3 次重複。
  assert.deepEqual(YELLOW_ESCALATION, { persistMinutes: 15, repeatCount: 3 });
});

test("通知欄位 allowlist：未知鍵、自由文字與自帶 deliveryClass 一律拒絕", () => {
  const good = {
    template: "yellow",
    reasonCode: "feedback_received",
    dedupeKey: `feedback:sha256:${"a".repeat(64)}`,
    userRef: `user:sha256:${"b".repeat(64)}`,
  };
  const ok = buildNotificationEvent(good);
  assert.equal(ok.ok, true);
  assert.equal(ok.event.deliveryClass, "daily_brief");
  assert.equal(ok.event.incidentId, null);

  const red = buildNotificationEvent({
    template: "red",
    reasonCode: "breakglass_extended",
    dedupeKey: `breakglass_extend:sha256:${"c".repeat(64)}`,
  });
  assert.equal(red.ok, true);
  assert.equal(red.event.deliveryClass, "immediate");

  assert.equal(buildNotificationEvent({ ...good, message: "自由文字" }).ok, false);
  assert.equal(buildNotificationEvent({ ...good, deliveryClass: "immediate" }).ok, false);
  assert.equal(buildNotificationEvent({ ...good, dedupeKey: "隨便一句話" }).ok, false);
  assert.equal(buildNotificationEvent({ ...good, template: "orange" }).ok, false);
  assert.equal(buildNotificationEvent({ ...good, reasonCode: "made_up" }).ok, false);
  assert.equal(buildNotificationEvent({ ...good, userRef: "user@example.com" }).ok, false);
  assert.equal(buildNotificationEvent({ ...good, incidentId: "not-a-uuid" }).ok, false);
});

test("通知 dedupe／冪等：同 dedupe_key 只更新 occurrence，不重複建立外部事件", () => {
  const enqueue = sqlBlock("admin_v2_enqueue_notification");
  assert.ok(enqueue.includes("ON CONFLICT (dedupe_key) DO UPDATE"));
  assert.ok(enqueue.includes("occurrence_count + 1"));
  // dedupe 更新不得重設 status——已送出的事件不會被翻回 pending 重送。
  assert.ok(!/DO UPDATE[\s\S]*status/u.test(enqueue));
  assert.ok(MIGRATION.includes("dedupe_key       TEXT NOT NULL UNIQUE"));
});

test("fallback 建模：只有 discord 與窄 email_fallback，delivery 重試不重複記帳", () => {
  assert.deepEqual([...NOTIFY_CHANNELS], ["discord", "email_fallback"]);
  assert.ok(MIGRATION.includes("UNIQUE (outbox_id, channel, attempt_no)"));
  // 無收件位址、無 URL、無自由文字欄位：deliveries 表只有短 snake_case error_code。
  assert.ok(MIGRATION.includes("error_code   TEXT CHECK (error_code ~ '^[a-z][a-z0-9_]{0,63}$')"));
});

// --- feedback V2 ---

test("feedback category enum 與 submit-feedback VALID_CATEGORIES 逐字同源", () => {
  const fromIndex = [...INDEX_TS.matchAll(/^\s+"([a-z_]+)",$/gmu)]
    .map((m) => m[1])
    .slice(0, 5);
  const fromSql = MIGRATION.match(/category    TEXT CHECK \(category IN \(([^)]+)\)\)/u);
  assert.ok(fromSql, "migration 缺 category CHECK");
  assert.deepEqual(
    fromSql[1].split(", ").map((s) => s.replaceAll("'", "")),
    fromIndex,
  );
});

test("feedback V2 redaction：email 與 JWT 樣式進不了 summary，長度以字元計 200", () => {
  const nasty = `請聯絡 eric.test@example.com 或 token eyJhbGciOiJIUzI1NiJ9.abc 看看${"長".repeat(300)}`;
  const summary = redactFeedbackSummary(nasty);
  assert.ok(summary);
  assert.ok(!summary.includes("@"));
  assert.ok(!summary.includes("eyJ"));
  assert.equal([...summary].length, FEEDBACK_SUMMARY_MAX_LENGTH);
  // surrogate pair 不被切壞。
  const emoji = redactFeedbackSummary("🙂".repeat(300));
  assert.equal([...emoji].length, FEEDBACK_SUMMARY_MAX_LENGTH);
  assert.equal(redactFeedbackSummary("   "), undefined);
  assert.equal(redactFeedbackSummary(123), undefined);
  // metadata 過不了 DB pattern 就丟棄，不讓 RPC 因 CHECK 失敗回 500。
  assert.equal(sanitizeUserTier(" Premium "), "premium");
  assert.equal(sanitizeUserTier("_"), undefined);
  assert.equal(sanitizeModelUsed("claude-sonnet-5"), "claude-sonnet-5");
  assert.equal(sanitizeModelUsed("bad model!"), undefined);
});

test("feedback request_ref：同 payload 重試同 ref（冪等）、不同內容不同 ref、格式不可逆", async () => {
  const base = {
    userId: "11111111-2222-3333-4444-555555555555",
    rating: "negative",
    category: "too_long",
    comment: "回覆太長了",
    conversationSnippet: "（對話片段：只進雜湊）",
    aiResponse: { finalRecommendation: { pick: "coach_chat", content: "建議 A" } },
    userTier: "free",
    modelUsed: "claude-sonnet-5",
  };
  const a = await buildFeedbackV2RpcParams(base);
  const retry = await buildFeedbackV2RpcParams({ ...base });
  assert.equal(a.p_request_ref, retry.p_request_ref);
  assert.equal(a.p_user_ref, retry.p_user_ref);

  // 不同訊息的回饋（aiResponse 內容不同）必須拿到不同 ref，不會被誤去重。
  const other = await buildFeedbackV2RpcParams({
    ...base,
    aiResponse: { finalRecommendation: { pick: "coach_chat", content: "建議 B" } },
  });
  assert.notEqual(a.p_request_ref, other.p_request_ref);
  const otherUser = await buildFeedbackV2RpcParams({
    ...base,
    userId: "99999999-2222-3333-4444-555555555555",
  });
  assert.notEqual(a.p_user_ref, otherUser.p_user_ref);
  assert.notEqual(a.p_request_ref, otherUser.p_request_ref);

  // 輸出即 allowlist：參數表上沒有 snippet／aiResponse 欄位，內容也不外洩。
  assert.deepEqual(Object.keys(a).sort(), [
    "p_category",
    "p_model_used",
    "p_rating",
    "p_request_ref",
    "p_summary",
    "p_user_ref",
    "p_user_tier",
  ]);
  assert.ok(new RegExp(NOTIFY_USER_REF_PATTERN, "u").test(a.p_user_ref));
  assert.ok(new RegExp(FEEDBACK_REQUEST_REF_PATTERN, "u").test(a.p_request_ref));
  assert.ok(!JSON.stringify(a).includes("對話片段"));
  assert.ok(!JSON.stringify(a).includes("建議 A"));

  // 欄位邊界無歧義：JSON 陣列序列化下，值挪位不會撞出同一把鍵。
  assert.notEqual(
    buildFeedbackRequestKey({ userId: "u", rating: "positive", comment: "ab" }),
    buildFeedbackRequestKey({ userId: "u", rating: "positive", userTier: "ab" }),
  );
});

test("feedback V2 RPC：inbox 冪等（重試不重複入列、不重複通知）且與 outbox 同交易", () => {
  const submit = sqlBlock("admin_v2_submit_feedback");
  assert.ok(submit.includes("ON CONFLICT (request_ref) DO NOTHING"));
  // 只有「首次」插入才 enqueue 通知；重試 v_id 為 NULL 直接跳過。
  assert.ok(submit.includes("IF v_id IS NOT NULL THEN"));
  assert.ok(submit.includes("admin_v2_enqueue_notification"));
  assert.ok(submit.includes("'yellow', 'feedback_received'"));
  assert.ok(MIGRATION.includes("request_ref TEXT NOT NULL UNIQUE"));
});

test("旗標語意與 admin-v2.ts isAdminV2Enabled 完全一致", () => {
  for (const v of ["1", "true", "TRUE", " 1 ", "0", "false", "", "yes", undefined]) {
    assert.equal(
      isAdminV2FeedbackEnabled(v),
      isAdminV2Enabled({ ADMIN_V2: v }),
      `ADMIN_V2=${String(v)}`,
    );
  }
});

test("旗標關閉一比一相容：V2 分流有旗標守門，legacy 寫入與 Discord 通知原樣保留", () => {
  const gate = INDEX_TS.indexOf('if (isAdminV2FeedbackEnabled(Deno.env.get("ADMIN_V2")))');
  const legacyInsert = INDEX_TS.indexOf('from("feedback").insert');
  const discord = INDEX_TS.indexOf("await sendDiscordNotification({");
  assert.ok(gate !== -1, "V2 分流必須由 ADMIN_V2 旗標守門");
  assert.ok(legacyInsert > gate, "legacy feedback 寫入必須保留在旗標分支之後");
  assert.ok(discord > legacyInsert, "legacy Discord 通知必須保留");
  // V2 分支內不呼叫 Discord，且 request_ref 不再用每次重試都變的 randomUUID。
  const v2Branch = INDEX_TS.slice(gate, legacyInsert);
  assert.ok(!v2Branch.includes("Discord"));
  assert.ok(!INDEX_TS.includes("randomUUID"));
});

// --- break-glass ---

test("break-glass 常數與 migration 同值：30 分鐘、3 次、72 小時、一次延長、7 天", () => {
  assert.equal(BREAKGLASS_GRANT_TTL_MS, 30 * 60 * 1000);
  assert.equal(BREAKGLASS_MAX_CAPTURES, 3);
  assert.equal(BREAKGLASS_CAPTURE_TTL_MS, 72 * 60 * 60 * 1000);
  assert.equal(BREAKGLASS_MAX_EXTENSIONS, 1);
  assert.equal(BREAKGLASS_MAX_LIFETIME_MS, 7 * 24 * 60 * 60 * 1000);
  assert.ok(MIGRATION.includes("expires_at <= activated_at + INTERVAL '30 minutes'"));
  assert.ok(MIGRATION.includes("now() + INTERVAL '30 minutes'"));
  assert.ok(MIGRATION.includes("captures_max = 3"));
  assert.ok(MIGRATION.includes("now() + INTERVAL '72 hours'"));
  assert.ok(MIGRATION.includes("extension_count IN (0, 1)"));
  assert.ok(MIGRATION.includes("expires_at <= captured_at + INTERVAL '7 days'"));
  assert.ok(MIGRATION.includes("captured_at + INTERVAL '7 days'"));
});

test("break-glass 啟用：owner 專屬＋近期 reauth（與 TS 契約同 10 分鐘）＋固定單一 user/function 範圍", () => {
  const activate = sqlBlock("admin_v2_breakglass_activate");
  assert.ok(activate.includes("a.role = 'owner'"));
  assert.equal(ADMIN_REAUTH_FRESH_MS, 10 * 60 * 1000);
  assert.ok(activate.includes("INTERVAL '10 minutes'"));
  // 未來時間戳不算新鮮（時鐘漂移／偽造），與 TS isReauthFresh 同規則。
  assert.ok(activate.includes("v_session.last_reauth_at > now()"));
  // 範圍欄位 NOT NULL：一位 user＋一項 function。
  assert.ok(MIGRATION.includes("scope_user_id           UUID NOT NULL"));
  assert.ok(/scope_function\s+TEXT NOT NULL CHECK/u.test(MIGRATION));
});

test("break-glass 併發上限：capture 名額用單一原子 UPDATE 遞增且擋過期／已關閉", () => {
  const capture = sqlBlock("admin_v2_breakglass_record_capture");
  assert.ok(capture.includes("SET captures_used = g.captures_used + 1"));
  assert.ok(capture.includes("g.captures_used < g.captures_max"));
  assert.ok(capture.includes("now() < g.expires_at"));
  assert.ok(capture.includes("g.closed_at IS NULL"));
  // 沒有先讀後寫的競態視窗：函式內不得有對 grants 的 SELECT。
  assert.ok(!capture.includes("SELECT * FROM public.admin_breakglass_grants_v2"));
  // 表上 CHECK 是第二道防線。
  assert.ok(MIGRATION.includes("captures_used >= 0 AND captures_used <= captures_max"));
});

test("break-glass 生命週期：六種管理員操作各自同交易寫 audit，延長另留 red 通知", () => {
  const audited = {
    admin_v2_breakglass_activate: "breakglass.activate",
    admin_v2_breakglass_view: "breakglass.view",
    admin_v2_breakglass_export: "breakglass.export",
    admin_v2_breakglass_extend: "breakglass.extend",
    admin_v2_breakglass_close: "breakglass.close",
    admin_v2_breakglass_purge_expired: "breakglass.purge",
  };
  for (const [fn, action] of Object.entries(audited)) {
    const block = sqlBlock(fn);
    assert.ok(
      block.includes("INSERT INTO public.admin_audit_events_v2"),
      `${fn} 必須同交易寫 audit`,
    );
    assert.ok(block.includes(`'${action}'`), `${fn} 的 audit action 必須是 ${action}`);
    // audit 參照一律不可逆 sha256，不落 raw UUID。
    assert.ok(block.includes(":sha256:' || encode(sha256("), `${fn} 的 target_ref 必須雜湊`);
  }
  // 延長：要求 reauth、最多一次、同交易 red 通知（brief：「留下通知與 audit」）。
  const extend = sqlBlock("admin_v2_breakglass_extend");
  assert.ok(extend.includes("INTERVAL '10 minutes'"));
  assert.ok(extend.includes("v_cap.extension_count >= 1"));
  assert.ok(extend.includes("admin_v2_enqueue_notification"));
  assert.ok(extend.includes("'red', 'breakglass_extended'"));
  // 通知 payload 隱私：延長通知不帶 user_ref（連雜湊都不帶）。
  assert.ok(/breakglass_extend:sha256:[^;]*NULL, NULL\)/u.test(extend));
  // capture 是 server-only receipt，不是管理員操作：不寫 audit。
  assert.ok(!sqlBlock("admin_v2_breakglass_record_capture").includes("admin_audit_events_v2"));
  // purge：只清內容、留 receipt。
  const purge = sqlBlock("admin_v2_breakglass_purge_expired");
  assert.ok(purge.includes("SET ciphertext_b64 = NULL, nonce_hex = NULL, purged_at = now()"));
  // audit action enum 與 TS 契約逐字同源（B1 五個＋breakglass 六個）。
  assert.ok(
    MIGRATION.includes(`CHECK (action IN (${quotedList(AUDIT_ACTIONS_WITH_BREAKGLASS)}))`),
  );
  assert.deepEqual(AUDIT_ACTIONS_WITH_BREAKGLASS.slice(0, AUDIT_ACTIONS.length), [
    ...AUDIT_ACTIONS,
  ]);
});

test("break-glass 內容：只收 AEAD envelope，purge 後必無內容、未 purge 必有內容", () => {
  assert.ok(MIGRATION.includes("cipher IN ('aes-256-gcm')"));
  // plaintext 不進 DB：只有 key 參照、nonce、ciphertext 與 plaintext 的 sha256。
  assert.ok(MIGRATION.includes("plaintext_sha256 TEXT NOT NULL CHECK (plaintext_sha256 ~ '^[0-9a-f]{64}$')"));
  assert.ok(MIGRATION.includes("ciphertext_b64 !~ '^eyJ'"));
  assert.ok(
    MIGRATION.includes(
      "(purged_at IS NULL AND ciphertext_b64 IS NOT NULL AND nonce_hex IS NOT NULL)",
    ),
  );
  assert.ok(
    MIGRATION.includes(
      "(purged_at IS NOT NULL AND ciphertext_b64 IS NULL AND nonce_hex IS NULL)",
    ),
  );
});

// --- schema／ACL 安全不變量 ---

test("SECURITY DEFINER 一律固定空 search_path，audit/表新物件全開 RLS 並先收光權限", () => {
  // 只數 SQL 本體（去掉註解行），避免說明文字灌水。
  const sqlOnly = MIGRATION.split("\n").filter((l) => !l.trimStart().startsWith("--")).join("\n");
  const definers = sqlOnly.match(/SECURITY DEFINER/gu) ?? [];
  const pinned = sqlOnly.match(/SET search_path = ''/gu) ?? [];
  assert.ok(definers.length > 0);
  assert.equal(definers.length, pinned.length);
  for (const table of [
    "admin_notification_outbox_v2",
    "admin_notification_deliveries_v2",
    "admin_feedback_inbox_v2",
    "admin_breakglass_grants_v2",
    "admin_breakglass_captures_v2",
  ]) {
    assert.ok(
      new RegExp(`ALTER TABLE public\\.${table}\\s+ENABLE ROW LEVEL SECURITY`, "u").test(
        MIGRATION,
      ),
      `${table} 必須開 RLS`,
    );
    assert.ok(
      new RegExp(`REVOKE ALL PRIVILEGES ON TABLE public\\.${table}\\s+FROM PUBLIC, anon, authenticated, service_role`, "u").test(
        MIGRATION,
      ),
      `${table} 必須先收光權限`,
    );
  }
});

test("最小 ACL：表只開 SELECT、無任何 anon grant、captures 表誰都拿不到常駐權限", () => {
  const tableGrants = MIGRATION.match(/^GRANT [^;]*ON TABLE [^;]*;/gmu) ?? [];
  assert.ok(tableGrants.length > 0);
  for (const g of tableGrants) {
    assert.ok(g.startsWith("GRANT SELECT ON TABLE"), `表 grant 只能是 SELECT：${g}`);
    assert.ok(!g.includes("anon"), `不得 grant 給 anon：${g}`);
  }
  // 內容表完全不 grant：view/export RPC 是唯二受 audit 的入口。
  assert.ok(!tableGrants.some((g) => g.includes("admin_breakglass_captures_v2")));
  // 函式 grant 也不開 anon；generic 寫入口（content gate、enqueue 之外的通用 insert）不存在。
  const fnGrants = MIGRATION.match(/^GRANT EXECUTE ON FUNCTION [^;]*;/gmu) ?? [];
  for (const g of fnGrants) assert.ok(!g.includes("anon"), `不得 grant 給 anon：${g}`);
  assert.ok(!fnGrants.some((g) => g.includes("content_gate")), "content gate 是內部件，不得 grant");
  // server-only 三件組只開 service_role。
  for (const fn of [
    "admin_v2_enqueue_notification",
    "admin_v2_submit_feedback",
    "admin_v2_breakglass_record_capture",
  ]) {
    const grant = fnGrants.find((g) => g.includes(`${fn}(`));
    assert.ok(grant?.includes("TO service_role"), `${fn} 只能開給 service_role`);
  }
});

// --- ai_logs raw telemetry 邊界 ---

test("啟用中的 V2 管理員無 raw ai_logs 路徑：restrictive policy＋metadata-only view", () => {
  assert.ok(MIGRATION.includes("AS RESTRICTIVE"));
  assert.ok(MIGRATION.includes("USING (NOT public.admin_v2_is_active_admin())"));
  const viewStart = MIGRATION.indexOf("CREATE VIEW public.admin_ai_logs_meta_v2");
  assert.notEqual(viewStart, -1);
  const view = MIGRATION.slice(viewStart, MIGRATION.indexOf(";", viewStart));
  assert.ok(
    view.replace(/\s+/gu, " ").includes(`SELECT ${AI_LOGS_META_COLUMNS.join(", ")}`),
  );
  for (const raw of AI_LOGS_RAW_COLUMNS) {
    assert.ok(!view.includes(raw), `metadata view 不得含 ${raw}`);
  }
  assert.deepEqual(
    [...AI_LOGS_RAW_COLUMNS],
    ["request_body", "response_body", "error_message"],
  );
});

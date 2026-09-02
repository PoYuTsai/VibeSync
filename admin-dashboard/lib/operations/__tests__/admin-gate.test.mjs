// B1 聚焦測試。執行：cd admin-dashboard && node --test lib/operations/__tests__/admin-gate.test.mjs
// 沿用 B0 作法：.mjs＋Node 22 type stripping 直接載入 .ts 契約，不裝測試框架。
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import {
  ADMIN_SESSION_ABSOLUTE_MS,
  ADMIN_SESSION_IDLE_MS,
  ADMIN_REAUTH_FRESH_MS,
  AUDIT_ACTIONS,
  AUDIT_TARGET_REF_PATTERN,
  AUDIT_REASON_CODES,
  AUDIT_REQUEST_ID_PATTERN,
  PUBLIC_AUTH_ERROR,
  capabilitiesForRole,
  hasCapability,
  getAalFromAccessToken,
  evaluateAdminSessionV2,
  isReauthFresh,
  canPerformSensitiveOp,
  buildAuditEvent,
  resolveAdminAccess,
} from "../admin-gate.ts";
import {
  loginFailedMessage,
  sessionDenyResponse,
  oauthStartErrorMessage,
  callbackUrlErrorMessage,
  callbackExchangeErrorMessage,
} from "../admin-legacy-visible.ts";

const NOW = new Date("2026-08-31T12:00:00Z");
const MINUTE = 60_000;
const HOUR = 60 * MINUTE;

function iso(msAgo) {
  return new Date(NOW.getTime() - msAgo).toISOString();
}

function forgeJwt(payload) {
  const b64 = (obj) =>
    Buffer.from(JSON.stringify(obj)).toString("base64url");
  return `${b64({ alg: "HS256" })}.${b64(payload)}.sig`;
}

const AAL2_TOKEN = forgeJwt({ aal: "aal2", sub: "user" });
const AAL1_TOKEN = forgeJwt({ aal: "aal1", sub: "user" });

function goodRow(overrides = {}) {
  return {
    role: "owner",
    is_active: true,
    account_session_version: 3,
    session_created_at: iso(HOUR),
    prev_seen_at: iso(5 * MINUTE),
    last_reauth_at: iso(5 * MINUTE),
    session_version: 3,
    revoked_at: null,
    ...overrides,
  };
}

function goodInput(overrides = {}) {
  return {
    aal: "aal2",
    identity: { role: "owner", isActive: true, sessionVersion: 3 },
    session: {
      createdAt: iso(HOUR),
      prevSeenAt: iso(5 * MINUTE),
      lastReauthAt: iso(5 * MINUTE),
      sessionVersion: 3,
      revokedAt: null,
    },
    now: NOW,
    ...overrides,
  };
}

test("旗標關閉：只走 legacy 檢查，完全不碰 v2 RPC，輸出相容", async () => {
  let legacyCalls = 0;
  let touchCalls = 0;
  const allowed = await resolveAdminAccess({
    accessToken: AAL1_TOKEN,
    legacyCheck: async () => {
      legacyCalls += 1;
      return { allowed: true };
    },
    touchSession: async () => {
      touchCalls += 1;
      return { data: [], error: null };
    },
    env: {},
  });
  assert.deepEqual(allowed, { allowed: true, mode: "legacy" });
  assert.equal(legacyCalls, 1);
  assert.equal(touchCalls, 0);

  const denied = await resolveAdminAccess({
    accessToken: AAL1_TOKEN,
    legacyCheck: async () => ({ allowed: false, error: "row lookup failed" }),
    touchSession: async () => ({ data: [], error: null }),
    env: { ADMIN_V2: "0" },
  });
  // legacy deny 帶回 legacyError：session route 靠它一比一重現 pre-B1 detail 欄位。
  assert.deepEqual(denied, {
    allowed: false,
    mode: "legacy",
    status: 403,
    publicError: "Forbidden",
    legacyError: "row lookup failed",
  });
});

test("旗標開啟：禁止 email fallback——RPC 失敗也絕不改走 legacy 檢查", async () => {
  let legacyCalls = 0;
  for (const touchSession of [
    async () => ({ data: null, error: { message: "rpc broke: secret detail" } }),
    async () => {
      throw new Error("network secret");
    },
  ]) {
    const result = await resolveAdminAccess({
      accessToken: AAL2_TOKEN,
      legacyCheck: async () => {
        legacyCalls += 1;
        return { allowed: true };
      },
      touchSession,
      env: { ADMIN_V2: "1" },
      now: NOW,
    });
    assert.equal(result.allowed, false);
    assert.equal(result.status, 401);
    assert.equal(result.publicError, PUBLIC_AUTH_ERROR.unauthorized);
  }
  assert.equal(legacyCalls, 0);
});

test("旗標開啟：user_id 綁定的啟用管理員＋AAL2＋活 session 才放行", async () => {
  const result = await resolveAdminAccess({
    accessToken: AAL2_TOKEN,
    legacyCheck: async () => ({ allowed: false }), // legacy 說不行也無關：v2 不看 email
    touchSession: async () => ({ data: [goodRow()], error: null }),
    env: { ADMIN_V2: "1" },
    now: NOW,
  });
  assert.equal(result.allowed, true);
  assert.equal(result.mode, "v2");
  assert.equal(result.role, "owner");
  assert.ok(result.capabilities.includes("sensitive.execute"));

  // 非管理員：RPC 回 0 列 → 拒絕。
  const notAdmin = await resolveAdminAccess({
    accessToken: AAL2_TOKEN,
    legacyCheck: async () => ({ allowed: true }),
    touchSession: async () => ({ data: [], error: null }),
    env: { ADMIN_V2: "1" },
    now: NOW,
  });
  assert.deepEqual(notAdmin, {
    allowed: false,
    mode: "v2",
    status: 403,
    publicError: "Forbidden",
  });
});

test("role/capability 單一真相：owner 有敏感執行權，founder_admin 沒有", () => {
  assert.deepEqual(
    [...capabilitiesForRole("owner")],
    ["ops.read", "incident.ack", "dual.confirm", "sensitive.execute"],
  );
  assert.deepEqual(
    [...capabilitiesForRole("founder_admin")],
    ["ops.read", "incident.ack", "dual.confirm"],
  );
  assert.equal(hasCapability("owner", "sensitive.execute"), true);
  assert.equal(hasCapability("founder_admin", "sensitive.execute"), false);
  assert.equal(hasCapability("founder_admin", "ops.read"), true);
});

test("MFA/AAL2：aal1、缺 claim、爛 token 一律 fail closed", () => {
  assert.equal(getAalFromAccessToken(AAL2_TOKEN), "aal2");
  assert.equal(getAalFromAccessToken(AAL1_TOKEN), "aal1");
  assert.equal(getAalFromAccessToken(forgeJwt({ sub: "user" })), "unknown");
  assert.equal(getAalFromAccessToken(forgeJwt({ aal: 2 })), "unknown");
  assert.equal(getAalFromAccessToken("not-a-jwt"), "unknown");
  assert.equal(getAalFromAccessToken("a.!!!garbage!!!.c"), "unknown");
  assert.equal(getAalFromAccessToken(null), "unknown");
  assert.equal(getAalFromAccessToken(""), "unknown");

  for (const aal of ["aal1", "unknown"]) {
    const denied = evaluateAdminSessionV2(goodInput({ aal }));
    assert.deepEqual(denied, { ok: false, reason: "mfa-required" });
  }
});

test("身分判定：非管理員、停用、未知角色全部拒絕", () => {
  assert.deepEqual(evaluateAdminSessionV2(goodInput({ identity: null })), {
    ok: false,
    reason: "not-admin",
  });
  assert.deepEqual(
    evaluateAdminSessionV2(
      goodInput({ identity: { role: "owner", isActive: false, sessionVersion: 3 } }),
    ),
    { ok: false, reason: "disabled" },
  );
  assert.deepEqual(
    evaluateAdminSessionV2(
      goodInput({ identity: { role: "super_root", isActive: true, sessionVersion: 3 } }),
    ),
    { ok: false, reason: "invalid-record" },
  );
});

test("absolute timeout：12 小時整還活著，多一毫秒就死", () => {
  const at = (ageMs) =>
    evaluateAdminSessionV2(
      goodInput({
        session: {
          createdAt: iso(ageMs),
          prevSeenAt: iso(MINUTE),
          lastReauthAt: iso(MINUTE),
          sessionVersion: 3,
          revokedAt: null,
        },
      }),
    );
  assert.equal(at(ADMIN_SESSION_ABSOLUTE_MS).ok, true);
  assert.deepEqual(at(ADMIN_SESSION_ABSOLUTE_MS + 1), {
    ok: false,
    reason: "absolute-timeout",
  });
});

test("idle timeout：以觸碰前的 prev_seen_at 判斷，30 分鐘整活、多一毫秒死", () => {
  const at = (idleMs) =>
    evaluateAdminSessionV2(
      goodInput({
        session: {
          createdAt: iso(HOUR),
          prevSeenAt: iso(idleMs),
          lastReauthAt: iso(MINUTE),
          sessionVersion: 3,
          revokedAt: null,
        },
      }),
    );
  assert.equal(at(ADMIN_SESSION_IDLE_MS).ok, true);
  assert.deepEqual(at(ADMIN_SESSION_IDLE_MS + 1), { ok: false, reason: "idle-timeout" });
});

test("撤銷、版本失效、缺 session、爛時間戳全部 fail closed", () => {
  assert.deepEqual(
    evaluateAdminSessionV2(
      goodInput({ session: { ...goodInput().session, revokedAt: iso(MINUTE) } }),
    ),
    { ok: false, reason: "revoked" },
  );
  assert.deepEqual(
    evaluateAdminSessionV2(
      goodInput({ session: { ...goodInput().session, sessionVersion: 2 } }),
    ),
    { ok: false, reason: "version-mismatch" },
  );
  assert.deepEqual(evaluateAdminSessionV2(goodInput({ session: null })), {
    ok: false,
    reason: "invalid-record",
  });
  for (const bad of [null, "garbage"]) {
    assert.deepEqual(
      evaluateAdminSessionV2(
        goodInput({ session: { ...goodInput().session, createdAt: bad } }),
      ),
      { ok: false, reason: "invalid-record" },
    );
    assert.deepEqual(
      evaluateAdminSessionV2(
        goodInput({ session: { ...goodInput().session, prevSeenAt: bad } }),
      ),
      { ok: false, reason: "invalid-record" },
    );
  }
});

test("逾時／版本失效會 best-effort 撤銷 session，不因觸碰復活", async () => {
  for (const row of [
    goodRow({ session_created_at: iso(13 * HOUR) }),
    goodRow({ prev_seen_at: iso(31 * MINUTE) }),
    goodRow({ session_version: 1 }),
  ]) {
    let revokeCalls = 0;
    const result = await resolveAdminAccess({
      accessToken: AAL2_TOKEN,
      legacyCheck: async () => ({ allowed: true }),
      touchSession: async () => ({ data: [row], error: null }),
      revokeSession: async () => {
        revokeCalls += 1;
      },
      env: { ADMIN_V2: "1" },
      now: NOW,
    });
    assert.equal(result.allowed, false);
    assert.equal(revokeCalls, 1);
  }
  // 已撤銷的 session 不需重複撤銷；撤銷 RPC 掛掉也不改變 deny 結果。
  let revokeCalls = 0;
  const revoked = await resolveAdminAccess({
    accessToken: AAL2_TOKEN,
    legacyCheck: async () => ({ allowed: true }),
    touchSession: async () => ({ data: [goodRow({ revoked_at: iso(MINUTE) })], error: null }),
    revokeSession: async () => {
      revokeCalls += 1;
    },
    env: { ADMIN_V2: "1" },
    now: NOW,
  });
  assert.equal(revoked.allowed, false);
  assert.equal(revokeCalls, 0);
  const revokeBroken = await resolveAdminAccess({
    accessToken: AAL2_TOKEN,
    legacyCheck: async () => ({ allowed: true }),
    touchSession: async () => ({ data: [goodRow({ session_version: 1 })], error: null }),
    revokeSession: async () => {
      throw new Error("revoke rpc down");
    },
    env: { ADMIN_V2: "1" },
    now: NOW,
  });
  assert.deepEqual(revokeBroken, {
    allowed: false,
    mode: "v2",
    status: 403,
    publicError: "Forbidden",
  });
});

test("reauth freshness：敏感操作要 owner＋新鮮 reauth，缺一不可", () => {
  assert.equal(isReauthFresh(iso(ADMIN_REAUTH_FRESH_MS), NOW), true);
  assert.equal(isReauthFresh(iso(ADMIN_REAUTH_FRESH_MS + 1), NOW), false);
  assert.equal(isReauthFresh(null, NOW), false);
  assert.equal(isReauthFresh("garbage", NOW), false);
  // 未來時間戳（時鐘漂移或偽造）不算新鮮。
  assert.equal(isReauthFresh(iso(-MINUTE), NOW), false);

  assert.deepEqual(canPerformSensitiveOp("owner", iso(MINUTE), NOW), { ok: true });
  assert.deepEqual(canPerformSensitiveOp("owner", iso(HOUR), NOW), {
    ok: false,
    reason: "reauth-required",
  });
  assert.deepEqual(canPerformSensitiveOp("founder_admin", iso(MINUTE), NOW), {
    ok: false,
    reason: "capability-denied",
  });
});

test("audit allowlist：action/reason 只收固定 enum、target_ref/request_id 只收不透明格式", () => {
  const actor = "11111111-2222-3333-4444-555555555555";
  const hex64 = "0123456789abcdef".repeat(4);
  const ok = buildAuditEvent({
    actorUserId: actor,
    action: "admin.session.revoke",
    result: "success",
    targetRef: `admin_account:sha256:${hex64}`,
    reason: "incident_response",
    requestId: `request:sha256:${hex64}`,
  });
  assert.equal(ok.ok, true);
  assert.equal(ok.event.approverUserId, null);
  // 每個 action／reason code 都要真的過得了驗證（enum 與驗證邏輯同源）。
  for (const action of AUDIT_ACTIONS) {
    assert.equal(buildAuditEvent({ actorUserId: actor, action, result: "success" }).ok, true, action);
  }
  for (const code of AUDIT_REASON_CODES) {
    assert.equal(
      buildAuditEvent({ actorUserId: actor, action: "admin.login", result: "success", reason: code }).ok,
      true,
      code,
    );
  }

  const rejected = [
    // 未知鍵（原文／payload 想混進來的路徑）。
    { actorUserId: actor, action: "admin.login", result: "success", payload: "{}" },
    // reason 是 prose／含空白（舊版收得進來，現在必拒）。
    { actorUserId: actor, action: "admin.login", result: "success", reason: "operator disabled account" },
    // reason 帶 email。
    { actorUserId: actor, action: "admin.login", result: "success", reason: "user alice@example.com" },
    // reason 塞聊天原文／prompt。
    { actorUserId: actor, action: "admin.login", result: "success", reason: "她說：今晚有空嗎？回覆建議如下" },
    // reason 不在 enum（單字也不行）。
    { actorUserId: actor, action: "admin.login", result: "success", reason: "misc" },
    // target_ref 是舊式自由標籤（沒有 sha256）。
    { actorUserId: actor, action: "admin.login", result: "success", targetRef: "admin_accounts_v2:redacted" },
    // target_ref 是電話樣式。
    { actorUserId: actor, action: "admin.login", result: "success", targetRef: "0912345678" },
    { actorUserId: actor, action: "admin.login", result: "success", targetRef: "+886-912-345-678" },
    // target_ref 是 API key／非 JWT secret 樣式。
    { actorUserId: actor, action: "admin.login", result: "success", targetRef: "sk-ant-api03-AAAAAAAA" },
    // target_ref 是 JWT 樣式。
    { actorUserId: actor, action: "admin.login", result: "success", targetRef: "eyJhbGciOiJIUzI1NiJ9" },
    // target_ref 含空白／prose。
    { actorUserId: actor, action: "admin.login", result: "success", targetRef: `user record ${hex64}` },
    // hex 不足 64、大寫 hex、kind 大寫都不行。
    { actorUserId: actor, action: "admin.login", result: "success", targetRef: `user:sha256:${hex64.slice(1)}` },
    { actorUserId: actor, action: "admin.login", result: "success", targetRef: `user:sha256:${hex64.toUpperCase()}` },
    { actorUserId: actor, action: "admin.login", result: "success", targetRef: `User:sha256:${hex64}` },
    // action 不在 enum：舊式合法 pattern、prose、電話、email、key/JWT 樣式全拒。
    { actorUserId: actor, action: "a.b", result: "success" },
    { actorUserId: actor, action: "admin.session.revoke.extra", result: "success" },
    { actorUserId: actor, action: "Delete All Users", result: "success" },
    { actorUserId: actor, action: "0912345678", result: "success" },
    { actorUserId: actor, action: "alice@example.com", result: "success" },
    { actorUserId: actor, action: "sk-ant-api03-AAAAAAAA", result: "success" },
    { actorUserId: actor, action: "eyJhbGciOiJIUzI1NiJ9", result: "success" },
    // request_id 不透明格式以外全拒：舊式自由字串、raw UUID、電話、email、key/JWT、
    // prose、大寫 hex、hex 不足 64。
    { actorUserId: actor, action: "admin.login", result: "success", requestId: "req-123" },
    { actorUserId: actor, action: "admin.login", result: "success", requestId: actor },
    { actorUserId: actor, action: "admin.login", result: "success", requestId: "0912345678" },
    { actorUserId: actor, action: "admin.login", result: "success", requestId: "alice@example.com" },
    { actorUserId: actor, action: "admin.login", result: "success", requestId: "sk-ant-api03-AAAAAAAA" },
    { actorUserId: actor, action: "admin.login", result: "success", requestId: "eyJhbGciOiJIUzI1NiJ9" },
    { actorUserId: actor, action: "admin.login", result: "success", requestId: `she said hi ${hex64}` },
    { actorUserId: actor, action: "admin.login", result: "success", requestId: `request:sha256:${hex64.toUpperCase()}` },
    { actorUserId: actor, action: "admin.login", result: "success", requestId: `request:sha256:${hex64.slice(1)}` },
    // result 不在 enum。
    { actorUserId: actor, action: "admin.login", result: "maybe" },
    // actor 不是 UUID。
    { actorUserId: "eric", action: "admin.login", result: "success" },
    // approver：B1 沒有 approval workflow，連合法 UUID 都是假核准，一律拒絕。
    { actorUserId: actor, action: "admin.login", result: "success", approverUserId: "bruce" },
    {
      actorUserId: actor,
      action: "admin.login",
      result: "success",
      approverUserId: "99999999-8888-7777-6666-555555555555",
    },
  ];
  for (const input of rejected) {
    const result = buildAuditEvent(input);
    assert.equal(result.ok, false, JSON.stringify(input).slice(0, 60));
  }
});

test("generic error：deny 結果與公開錯誤字串不含 email、token、reason 細節", async () => {
  const results = [];
  for (const [env, touchSession] of [
    [{ ADMIN_V2: "1" }, async () => ({ data: null, error: { message: "pg: secret@db failed eyJ" } })],
    [{ ADMIN_V2: "1" }, async () => ({ data: [goodRow({ is_active: false })], error: null })],
    [{ ADMIN_V2: "1" }, async () => ({ data: [], error: null })],
    [{}, async () => ({ data: [], error: null })],
  ]) {
    results.push(
      await resolveAdminAccess({
        accessToken: AAL2_TOKEN,
        legacyCheck: async () => ({ allowed: false }),
        touchSession,
        env,
        now: NOW,
      }),
    );
  }
  for (const result of results) {
    assert.equal(result.allowed, false);
    const serialized = JSON.stringify(result);
    assert.ok(!serialized.includes("@"));
    assert.ok(!serialized.includes("eyJ"));
    assert.ok(!/reason|timeout|revoked|version|mfa|disabled|rpc|secret/iu.test(serialized));
    assert.ok(["Unauthorized", "Forbidden"].includes(result.publicError));
  }
});

test("旗標關閉可見行為：一比一重現 pre-B1 錯誤輸出；開啟才 generic", () => {
  // login route 401：pre-B1 是 `error?.message || "Login failed"`。
  assert.equal(loginFailedMessage(false, "Invalid login credentials"), "Invalid login credentials");
  assert.equal(loginFailedMessage(false, undefined), "Login failed");
  assert.equal(loginFailedMessage(false, ""), "Login failed");
  assert.equal(loginFailedMessage(true, "Invalid login credentials"), "Login failed");

  // session route 403 body：pre-B1 是 { error, email, detail }。
  const legacyDeny = {
    allowed: false,
    mode: "legacy",
    status: 403,
    publicError: "Forbidden",
    legacyError: "row lookup failed",
  };
  assert.deepEqual(sessionDenyResponse(legacyDeny, "eric@example.com"), {
    status: 403,
    body: { error: "Forbidden", email: "eric@example.com", detail: "row lookup failed" },
  });
  // v2 deny：只有 generic error，永不帶 email／detail 鍵。
  const v2Deny = sessionDenyResponse(
    { allowed: false, mode: "v2", status: 403, publicError: "Forbidden" },
    "eric@example.com",
  );
  assert.deepEqual(v2Deny, { status: 403, body: { error: "Forbidden" } });
  assert.ok(!("email" in v2Deny.body) && !("detail" in v2Deny.body));
  const v2Unauthorized = sessionDenyResponse(
    { allowed: false, mode: "v2", status: 401, publicError: "Unauthorized" },
    "eric@example.com",
  );
  assert.deepEqual(v2Unauthorized, { status: 401, body: { error: "Unauthorized" } });

  // login page OAuth 失敗：pre-B1 直接顯示 oauthError.message。
  assert.equal(oauthStartErrorMessage(false, "popup blocked"), "popup blocked");
  assert.equal(oauthStartErrorMessage(true, "popup blocked"), "無法前往 Google 登入，請稍後再試。");

  // callback：pre-B1 直接回顯 URL error／exchangeError.message（含 fallback 字串）。
  assert.equal(callbackUrlErrorMessage(false, "access_denied detail"), "access_denied detail");
  assert.equal(callbackUrlErrorMessage(true, "access_denied detail"), "Google 登入失敗，請回登入頁重試。");
  assert.equal(callbackExchangeErrorMessage(false, "invalid code"), "invalid code");
  assert.equal(callbackExchangeErrorMessage(false, undefined), "Unable to complete Google login");
  assert.equal(callbackExchangeErrorMessage(true, "invalid code"), "無法完成 Google 登入，請重試。");
});

test("auth route 原始碼守門：raw 錯誤與 deny body 只能經 legacy-visible 旗標分流", () => {
  const sessionRoute = readFileSync(
    new URL("../../../app/api/auth/session/route.ts", import.meta.url),
    "utf8",
  );
  const loginRoute = readFileSync(
    new URL("../../../app/api/auth/login/route.ts", import.meta.url),
    "utf8",
  );
  // session route 的 deny body 只能由 sessionDenyResponse 產生（v2 才保證 generic）。
  assert.ok(sessionRoute.includes("sessionDenyResponse(adminAccess, user.email)"));
  assert.ok(!sessionRoute.includes("email: user"), "deny body 組裝不得散落在 route");
  assert.ok(!sessionRoute.includes("detail:"), "deny body 組裝不得散落在 route");
  // login route 的 Supabase 錯誤只能作為 loginFailedMessage 的參數出現一次。
  assert.match(loginRoute, /loginFailedMessage\(isAdminV2Enabled\(\), error\?\.message\)/u);
  assert.equal((loginRoute.match(/error\??\.message/gu) ?? []).length, 1);
});

test("client 頁面旗標：server page 於 request 時下發決策，client 不讀私有 env", () => {
  const pages = ["../../../app/login/page.tsx", "../../../app/auth/callback/page.tsx"].map(
    (p) => readFileSync(new URL(p, import.meta.url), "utf8"),
  );
  for (const src of pages) {
    assert.ok(!src.includes('"use client"'), "旗標決策頁必須是 server component");
    assert.ok(src.includes("isAdminV2Enabled()"), "旗標決策必須在 server 端做");
    assert.ok(src.includes('dynamic = "force-dynamic"'), "旗標必須是 request 時的 runtime 決策");
  }
  const loginClient = readFileSync(
    new URL("../../../app/login/login-client.tsx", import.meta.url),
    "utf8",
  );
  const callbackClient = readFileSync(
    new URL("../../../app/auth/callback/callback-client.tsx", import.meta.url),
    "utf8",
  );
  for (const src of [loginClient, callbackClient]) {
    assert.ok(src.includes('"use client"'));
    assert.ok(!src.includes("ADMIN_V2"), "client 不得直接讀私有旗標 env");
    assert.ok(!src.includes("process.env"), "client 不得讀任何 env");
  }
  assert.ok(loginClient.includes("oauthStartErrorMessage(adminV2"));
  assert.ok(callbackClient.includes("callbackUrlErrorMessage(adminV2"));
  assert.ok(callbackClient.includes("callbackExchangeErrorMessage(adminV2"));
});

test("B1 migration 靜態守則：additive、deny-by-default、definer 固定 search_path", () => {
  const raw = readFileSync(
    new URL(
      "../../../../supabase/migrations/20260902140000_admin_identity_v2_baseline.sql",
      import.meta.url,
    ),
    "utf8",
  );
  const sql = raw
    .split("\n")
    .map((line) => line.replace(/--.*$/u, ""))
    .join("\n");
  // DDL 守則只看頂層 SQL：$$ 函式本體內的 IF NOT EXISTS（存在性檢查）、INSERT 是合法邏輯。
  const topLevel = sql.replace(/\$\$[\s\S]*?\$\$/gu, "");

  // additive：不得條件式建立／取代、不得 DROP、不得改既有物件。
  assert.ok(!/IF\s+NOT\s+EXISTS/iu.test(topLevel), "不得使用 IF NOT EXISTS");
  assert.ok(!/OR\s+REPLACE/iu.test(topLevel), "不得使用 OR REPLACE");
  assert.ok(!/\bDROP\b/iu.test(topLevel), "不得 DROP");
  const alterTargets = [...topLevel.matchAll(/ALTER\s+TABLE\s+(\S+)/giu)].map((m) => m[1]);
  for (const target of alterTargets) {
    assert.match(target, /^public\.admin_(accounts|sessions|audit_events)_v2$/u, "只能 ALTER 本批新表");
  }
  assert.ok(!/ALTER\s+TABLE[^;]*\b(DROP|RENAME|ALTER\s+COLUMN)\b/iu.test(topLevel));

  // 不得 seed 任何列（真實 UUID／憑證都進不來）。
  assert.ok(!/INSERT\s+INTO/iu.test(topLevel), "migration 頂層不得 seed 資料");

  // 每個 SECURITY DEFINER 與 trigger 函式都要固定 search_path。
  const definerCount = (sql.match(/SECURITY DEFINER/gu) ?? []).length;
  const searchPathCount = (sql.match(/SET search_path = ''/gu) ?? []).length;
  const createFunctionCount = (sql.match(/CREATE FUNCTION/gu) ?? []).length;
  assert.equal(definerCount, 3);
  assert.equal(createFunctionCount, 4);
  assert.equal(searchPathCount, createFunctionCount, "每個函式都要 SET search_path = ''");

  // RLS 全開、先 revoke all 再最小 grant；任何 GRANT 不得含 DELETE/TRUNCATE。
  const tables = [
    "public.admin_accounts_v2",
    "public.admin_sessions_v2",
    "public.admin_audit_events_v2",
  ];
  for (const table of tables) {
    const escaped = table.replace(".", "\\.");
    assert.match(sql, new RegExp(String.raw`ALTER TABLE ${escaped}\s+ENABLE ROW LEVEL SECURITY;`, "u"));
    const revokeAt = sql.search(
      new RegExp(
        String.raw`REVOKE ALL PRIVILEGES ON TABLE ${escaped}\s+FROM PUBLIC, anon, authenticated, service_role;`,
        "u",
      ),
    );
    assert.ok(revokeAt >= 0, `缺 revoke all（含 service_role）: ${table}`);
    const grantMatch = sql.match(new RegExp(String.raw`GRANT ([^;]*) ON TABLE ${escaped}\s+TO service_role;`, "u"));
    assert.ok(grantMatch, `缺最小 grant: ${table}`);
    assert.ok(sql.indexOf(grantMatch[0]) > revokeAt, `grant 必須在 revoke all 之後: ${table}`);
  }
  assert.ok(!/CREATE\s+POLICY/iu.test(sql), "deny-by-default：不建任何 policy");
  assert.ok(!/GRANT[^;]*\b(DELETE|TRUNCATE)\b/iu.test(sql), "GRANT 不得含 DELETE/TRUNCATE");
  // audit 是 append-only：連 service_role 都不能 UPDATE。
  assert.ok(!/GRANT[^;]*\bUPDATE\b[^;]*admin_audit_events_v2/iu.test(sql));

  // 函式權限：先收光再只開 EXECUTE 給 authenticated；trigger 函式不開放。
  for (const fn of [
    "public.admin_v2_touch_session\\(\\)",
    "public.admin_v2_revoke_my_session\\(\\)",
  ]) {
    const revokeAt = sql.search(new RegExp(String.raw`REVOKE ALL ON FUNCTION ${fn}\s+FROM PUBLIC, anon, authenticated, service_role;`, "u"));
    const grantAt = sql.search(new RegExp(String.raw`GRANT EXECUTE ON FUNCTION ${fn}\s+TO authenticated;`, "u"));
    assert.ok(revokeAt >= 0, `缺函式 revoke: ${fn}`);
    assert.ok(grantAt > revokeAt, `函式 grant 必須在 revoke 之後: ${fn}`);
  }
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.admin_audit_events_v2_block_mutation\(\)/u);
  assert.ok(!/GRANT[^;]*admin_audit_events_v2_block_mutation/iu.test(sql), "trigger 函式不得 grant");

  // append-only trigger 要同時蓋 UPDATE/DELETE 與 TRUNCATE。
  assert.match(sql, /BEFORE UPDATE OR DELETE ON public\.admin_audit_events_v2/u);
  assert.match(sql, /BEFORE TRUNCATE ON public\.admin_audit_events_v2/u);

  // audit 欄位即 allowlist：不得有 jsonb/自由 payload 欄位。
  const auditBlock = raw.slice(raw.indexOf("admin_audit_events_v2 ("), raw.indexOf("admin_audit_events_v2_actor"));
  assert.ok(!/jsonb/iu.test(auditBlock), "audit 表不得有自由 payload 欄位");
});

test("B1 migration 靜態守則：無 generic audit 寫入口，provenance 由表上守門 trigger 強制", () => {
  const sql = readFileSync(
    new URL(
      "../../../../supabase/migrations/20260902140000_admin_identity_v2_baseline.sql",
      import.meta.url,
    ),
    "utf8",
  );
  // 不得存在任何接受呼叫者自稱 actor/result/approver 的 generic append RPC。
  assert.ok(!/append_audit/iu.test(sql), "不得保留 generic append RPC");
  // 沒有任何函式 EXECUTE 開給 service_role：audit 寫入只能走 B2–B8 的
  // operation-specific 受控函式（屆時同批建立、同批審查）。
  assert.ok(
    !/^\s*GRANT[^;]*ON FUNCTION[^;]*service_role/imu.test(sql),
    "不得把任何函式 EXECUTE 開給 service_role",
  );
  // audit 表對 service_role 只有 SELECT：B1 沒有任何角色拿得到 INSERT。
  const auditGrant = sql.match(/GRANT ([^;]*) ON TABLE public\.admin_audit_events_v2\s+TO service_role;/u);
  assert.equal(auditGrant?.[1].trim(), "SELECT", "audit 表只留最小 SELECT，不得直接 INSERT");
  assert.ok(
    !/GRANT[^;]*\bINSERT\b[^;]*admin_audit_events_v2/iu.test(sql),
    "audit 表不得對任何角色開 INSERT",
  );
  // provenance 守門 trigger 綁在表上：任何未來寫入路徑都逃不掉。
  assert.match(sql, /BEFORE INSERT ON public\.admin_audit_events_v2/u);
  const guardBody = sql.slice(
    sql.indexOf("CREATE FUNCTION public.admin_audit_events_v2_provenance_guard"),
    sql.indexOf("CREATE TRIGGER admin_audit_events_v2_provenance"),
  );
  assert.ok(
    /a\.user_id = NEW\.actor_user_id AND a\.is_active/u.test(guardBody),
    "actor 必須是啟用中的管理員（存在但停用也要拒）",
  );
  assert.ok(
    /IF NEW\.approver_user_id IS NOT NULL THEN\s+RAISE EXCEPTION/u.test(guardBody),
    "B1 沒有 approval workflow：非空 approver 一律拒絕",
  );
  // 守門函式本身收光權限、不 grant 給任何角色。
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.admin_audit_events_v2_provenance_guard\(\)/u);
  assert.ok(!/GRANT[^;]*provenance_guard/iu.test(sql), "守門函式不得 grant");
});

test("B1 migration 靜態守則：audit 隱私規則與 TS 逐字同源", () => {
  const sql = readFileSync(
    new URL(
      "../../../../supabase/migrations/20260902140000_admin_identity_v2_baseline.sql",
      import.meta.url,
    ),
    "utf8",
  );
  // target_ref CHECK 與 AUDIT_TARGET_REF_PATTERN 逐字相同。
  assert.ok(
    sql.includes(`target_ref ~ '${AUDIT_TARGET_REF_PATTERN}'`),
    "SQL target_ref CHECK 必須與 TS pattern 同一份字串",
  );
  // reason CHECK 的 enum 與 AUDIT_REASON_CODES 完全一致（含順序）。
  const reasonIn = sql.match(/reason IN \(([^)]*)\)/u);
  assert.ok(reasonIn, "reason 必須是固定 IN enum CHECK");
  const sqlCodes = reasonIn[1].split(",").map((s) => s.trim().replace(/^'|'$/gu, ""));
  assert.deepEqual(sqlCodes, [...AUDIT_REASON_CODES], "SQL reason enum 必須與 TS 同源");
  // action CHECK 的 enum 與 AUDIT_ACTIONS 完全一致（含順序），不得是自由 pattern。
  const actionIn = sql.match(/action IN \(([^)]*)\)/u);
  assert.ok(actionIn, "action 必須是固定 IN enum CHECK");
  const sqlActions = actionIn[1].split(",").map((s) => s.trim().replace(/^'|'$/gu, ""));
  assert.deepEqual(sqlActions, [...AUDIT_ACTIONS], "SQL action enum 必須與 TS 同源");
  assert.ok(!/action ~/u.test(sql), "action 不得用自由 pattern CHECK");
  // request_id CHECK 與 AUDIT_REQUEST_ID_PATTERN 逐字相同。
  assert.ok(
    sql.includes(`request_id ~ '${AUDIT_REQUEST_ID_PATTERN}'`),
    "SQL request_id CHECK 必須與 TS pattern 同一份字串",
  );
});

test("B1 migration 靜態守則：首次 session 無競態且他人佔用 fail closed", () => {
  const sql = readFileSync(
    new URL(
      "../../../../supabase/migrations/20260902140000_admin_identity_v2_baseline.sql",
      import.meta.url,
    ),
    "utf8",
  );
  const touchBody = sql.slice(
    sql.indexOf("CREATE FUNCTION public.admin_v2_touch_session"),
    sql.indexOf("CREATE FUNCTION public.admin_v2_revoke_my_session"),
  );
  // 建列不用 SELECT-then-INSERT：ON CONFLICT DO NOTHING 讓併發輸家安靜落地。
  assert.ok(touchBody.includes("ON CONFLICT (session_id) DO NOTHING"));
  assert.ok(!/INSERT INTO[^;]*RETURNING/u.test(touchBody), "不得沿用 INSERT ... RETURNING 競態寫法");
  // 重查與所有讀寫都必須同時綁 session_id＋user_id：他人佔用的 session_id 查不到 → 0 列 deny。
  const dualKeyReads = touchBody.match(/s\.session_id = v_sid AND s\.user_id = v_uid/gu) ?? [];
  assert.ok(dualKeyReads.length >= 2, "首查與 INSERT 後重查都要 session_id＋user_id 雙鍵");
  assert.ok(
    /last_seen_at = now\(\)\s+WHERE s\.session_id = v_sid AND s\.user_id = v_uid/u.test(touchBody),
    "touch 更新也只能碰自己的列",
  );
});

// B1 聚焦測試。執行：cd admin-dashboard && node --test lib/operations/__tests__/admin-gate.test.mjs
// 沿用 B0 作法：.mjs＋Node 22 type stripping 直接載入 .ts 契約，不裝測試框架。
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import {
  ADMIN_SESSION_ABSOLUTE_MS,
  ADMIN_SESSION_IDLE_MS,
  ADMIN_REAUTH_FRESH_MS,
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
    legacyCheck: async () => ({ allowed: false }),
    touchSession: async () => ({ data: [], error: null }),
    env: { ADMIN_V2: "0" },
  });
  assert.deepEqual(denied, { allowed: false, status: 403, publicError: "Forbidden" });
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
  assert.deepEqual(notAdmin, { allowed: false, status: 403, publicError: "Forbidden" });
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
  assert.deepEqual(revokeBroken, { allowed: false, status: 403, publicError: "Forbidden" });
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

test("audit allowlist：只收固定欄位，email／token 樣式／超長／未知鍵全拒", () => {
  const actor = "11111111-2222-3333-4444-555555555555";
  const ok = buildAuditEvent({
    actorUserId: actor,
    action: "admin.session.revoke",
    result: "success",
    targetRef: "admin_accounts_v2:redacted",
    reason: "operator disabled account",
    requestId: "req-123",
  });
  assert.equal(ok.ok, true);
  assert.equal(ok.event.approverUserId, null);

  const rejected = [
    // 未知鍵（原文／payload 想混進來的路徑）。
    { actorUserId: actor, action: "a.b", result: "success", payload: "{}" },
    // email。
    { actorUserId: actor, action: "a.b", result: "success", reason: "user alice@example.com" },
    // JWT/secret 樣式。
    { actorUserId: actor, action: "a.b", result: "success", targetRef: "eyJhbGciOiJIUzI1NiJ9" },
    // 換行（塞原文用）。
    { actorUserId: actor, action: "a.b", result: "success", reason: "line1\nline2" },
    // 超長。
    { actorUserId: actor, action: "a.b", result: "success", reason: "x".repeat(501) },
    // action 不符格式（大寫、空白、prose）。
    { actorUserId: actor, action: "Delete All Users", result: "success" },
    // result 不在 enum。
    { actorUserId: actor, action: "a.b", result: "maybe" },
    // actor 不是 UUID。
    { actorUserId: "eric", action: "a.b", result: "success" },
    // approver 不是 UUID。
    { actorUserId: actor, action: "a.b", result: "success", approverUserId: "bruce" },
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

test("auth route 原始碼守門：不再把 email 或底層錯誤訊息塞進 response", () => {
  const sessionRoute = readFileSync(
    new URL("../../../app/api/auth/session/route.ts", import.meta.url),
    "utf8",
  );
  const loginRoute = readFileSync(
    new URL("../../../app/api/auth/login/route.ts", import.meta.url),
    "utf8",
  );
  assert.ok(!sessionRoute.includes("email: user"), "session route 不得回傳 email");
  assert.ok(!sessionRoute.includes("detail:"), "session route 不得回傳 RPC 錯誤細節");
  assert.ok(!loginRoute.includes("error?.message"), "login route 不得轉發 Supabase 錯誤");
  assert.ok(!loginRoute.includes("error.message"), "login route 不得轉發 Supabase 錯誤");
});

test("B1 migration 靜態守則：additive、deny-by-default、definer 固定 search_path", () => {
  const raw = readFileSync(
    new URL(
      "../../../../supabase/migrations/20260831150000_admin_identity_v2_baseline.sql",
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

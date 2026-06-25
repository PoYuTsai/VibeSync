// practice-chat 額度決策測試（server-ledger 為準，不信任 client turns）。
// 跑法：deno test supabase/functions/practice-chat/quota_decision_test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  decideChatGate,
  decideContinuationGate,
  decideDebriefGate,
  isSessionComplete,
  MAX_AI_REPLIES,
  MAX_DEBRIEFS,
  type SessionLedger,
} from "./quota_decision.ts";

function ledger(partial: Partial<SessionLedger> = {}): SessionLedger {
  return {
    exists: true,
    aiCount: 0,
    charged: false,
    debriefCount: 0,
    ...partial,
  };
}

// ── chat preflight：扣費由 server `charged` 決定，與 client turns 脫鉤 ──

Deno.test("chat：全新 session（未扣費、非測試）→ 預判要扣、未達上限", () => {
  assertEquals(
    decideChatGate({
      ledger: ledger({ exists: false, aiCount: 0, charged: false }),
      isTestAccount: false,
    }),
    { atCap: false, shouldChargePreview: true },
  );
});

Deno.test("chat：已扣費過的 session → 同場不再扣（堵重送重扣）", () => {
  assertEquals(
    decideChatGate({
      ledger: ledger({ aiCount: 3, charged: true }),
      isTestAccount: false,
    }),
    { atCap: false, shouldChargePreview: false },
  );
});

Deno.test("chat：測試帳號 → 永不預判扣費（即使未扣費）", () => {
  assertEquals(
    decideChatGate({
      ledger: ledger({ exists: false, charged: false }),
      isTestAccount: true,
    }),
    { atCap: false, shouldChargePreview: false },
  );
});

Deno.test("chat：偽造 client ai turns 不影響扣費判定（只看 server charged）", () => {
  // server 紀錄：尚未扣費 → 不管 client 怎麼謊報，preflight 都判要扣。
  assertEquals(
    decideChatGate({
      ledger: ledger({ exists: true, aiCount: 0, charged: false }),
      isTestAccount: false,
    }).shouldChargePreview,
    true,
  );
});

Deno.test("chat：server aiCount 達上限 → atCap=true（堵少報 turns 繞過 20）", () => {
  assertEquals(
    decideChatGate({
      ledger: ledger({ aiCount: 20, charged: true }),
      isTestAccount: false,
    }).atCap,
    true,
  );
  assertEquals(
    decideChatGate({
      ledger: ledger({ aiCount: 19, charged: true }),
      isTestAccount: false,
    }).atCap,
    false,
  );
});

// ── debrief preflight：須附著於已扣費 session + 有次數上限 ──────────────

Deno.test("debrief：session 不存在 → 拒絕（堵偽造 turns 免費打 debrief）", () => {
  assertEquals(
    decideDebriefGate({ ledger: ledger({ exists: false }) }),
    { allowed: false, reason: "practice_session_not_started" },
  );
});

Deno.test("debrief：session 存在但從未扣費 → 拒絕", () => {
  assertEquals(
    decideDebriefGate({ ledger: ledger({ exists: true, charged: false }) }),
    { allowed: false, reason: "practice_session_not_started" },
  );
});

Deno.test("debrief：已扣費 + 有 AI 回覆 + 未達上限 → 放行", () => {
  assertEquals(
    decideDebriefGate({
      ledger: ledger({ charged: true, aiCount: 4, debriefCount: 0 }),
    }),
    { allowed: true },
  );
});

Deno.test("debrief：已達次數上限 → 拒絕（堵免費成本放大）", () => {
  assertEquals(
    decideDebriefGate({
      ledger: ledger({ charged: true, aiCount: 4, debriefCount: MAX_DEBRIEFS }),
    }),
    { allowed: false, reason: "practice_debrief_limit" },
  );
});

// ── Free 續玩閘（roundIndex>1 的 tier gate）──────────────────────────

Deno.test("續玩：Free + roundIndex 2 → 擋下，reason=upgrade_required", () => {
  assertEquals(
    decideContinuationGate({ tier: "free", roundIndex: 2 }),
    { allowed: false, reason: "upgrade_required" },
  );
});

Deno.test("續玩：Free + roundIndex 1 → 放行（可開新陪練女孩）", () => {
  assertEquals(
    decideContinuationGate({ tier: "free", roundIndex: 1 }),
    { allowed: true },
  );
});

Deno.test("續玩：Free + roundIndex 3 → 擋下", () => {
  assertEquals(
    decideContinuationGate({ tier: "free", roundIndex: 3 }).allowed,
    false,
  );
});

Deno.test("續玩：Starter + roundIndex 2 → 放行", () => {
  assertEquals(
    decideContinuationGate({ tier: "starter", roundIndex: 2 }),
    { allowed: true },
  );
});

Deno.test("續玩：Essential + roundIndex 2 → 放行", () => {
  assertEquals(
    decideContinuationGate({ tier: "essential", roundIndex: 2 }),
    { allowed: true },
  );
});

Deno.test("續玩：未知/缺 tier 視為 free → roundIndex 2 擋下（保守 fail-closed）", () => {
  assertEquals(
    decideContinuationGate({ tier: null, roundIndex: 2 }).allowed,
    false,
  );
  assertEquals(
    decideContinuationGate({ tier: undefined, roundIndex: 2 }).allowed,
    false,
  );
  assertEquals(
    decideContinuationGate({ tier: "garbage", roundIndex: 2 }).allowed,
    false,
  );
});

// ── 20 則上限常數 ────────────────────────────────────────────────────

Deno.test("isSessionComplete：< 20 未滿、>= 20 已滿", () => {
  assertEquals(isSessionComplete(0), false);
  assertEquals(isSessionComplete(19), false);
  assertEquals(isSessionComplete(20), true);
  assertEquals(isSessionComplete(21), true);
  assertEquals(MAX_AI_REPLIES, 20);
});

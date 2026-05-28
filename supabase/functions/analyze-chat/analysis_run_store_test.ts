import {
  assert,
  assertEquals,
  assertFalse,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import {
  AnalysisRun,
  AnalysisRunDriver,
  AnalysisRunStore,
  NewChargedRun,
  ReserveInput,
} from "./analysis_run_store.ts";

// -----------------------------------------------------------------------------
// In-memory driver — simulates the Postgres RPCs we depend on
// (create_charged_analysis_run + reserve_analysis_run_retry) without touching
// real Postgres. Atomicity is trivially proved here by single-threaded JS;
// the real SQL-level guarantee is exercised by Phase 1 integration tests.
//
// Beyond `AnalysisRunDriver`, this driver exposes:
//   - `chargeCalls`: counter so tests can assert quota was/wasn't ticked.
//   - `simulateChargeFailure`: forces the atomic RPC to RAISE during the
//      "increment_usage" step; mirrors what would happen if increment_usage
//      itself threw in PL/pgSQL — caller must see zero side effects.
//   - `seedUncharged`: forcibly inserts a charged=false row to test the
//      defensive RUN_NOT_CHARGED check. Production code can't reach this
//      state via the atomic RPC.
// -----------------------------------------------------------------------------

interface FakeRow {
  id: string;
  user_id: string;
  conversation_hash: string;
  charged: boolean;
  quick_result: Record<string, unknown>;
  request_context: Record<string, unknown> | null;
  retry_count: number;
  created_at: string;
  expires_at: string;
  consumed_at: string | null;
}

interface FakeHarness {
  driver: AnalysisRunDriver;
  table: Map<string, FakeRow>;
  setNow(d: Date): void;
  chargeCalls: { count: number; totalMessages: number };
  simulateChargeFailure(on: boolean): void;
  seedUncharged(input: NewChargedRun): FakeRow;
}

function makeDriver(opts?: {
  now?: () => Date;
  ttlMinutes?: number;
}): FakeHarness {
  const table = new Map<string, FakeRow>();
  let nowFn = opts?.now ?? (() => new Date());
  const ttlMs = (opts?.ttlMinutes ?? 30) * 60 * 1000;
  let seq = 0;
  const newId = () => `run-${++seq}`;
  const chargeCalls = { count: 0, totalMessages: 0 };
  let chargeShouldFail = false;

  const insertRow = (input: NewChargedRun, charged: boolean): FakeRow => {
    const now = nowFn();
    const row: FakeRow = {
      id: newId(),
      user_id: input.userId,
      conversation_hash: input.conversationHash,
      charged,
      quick_result: input.quickResult,
      request_context: input.requestContext ?? null,
      retry_count: 0,
      created_at: now.toISOString(),
      expires_at: new Date(now.getTime() + ttlMs).toISOString(),
      consumed_at: null,
    };
    table.set(row.id, row);
    return row;
  };

  const driver: AnalysisRunDriver = {
    async createChargedRun(input: NewChargedRun): Promise<AnalysisRun> {
      // Mirror PL/pgSQL: charge first; if it throws, the whole call aborts
      // and no row is inserted.
      if (input.chargeQuota) {
        if (chargeShouldFail) {
          throw new Error("increment_usage simulated failure");
        }
        if (!Number.isInteger(input.messageCount) || input.messageCount <= 0) {
          throw new Error("p_message_count must be positive when charging");
        }
        chargeCalls.count += 1;
        chargeCalls.totalMessages += input.messageCount;
      }
      const row = insertRow(input, true);
      return { ...row };
    },

    async selectById(id: string): Promise<AnalysisRun | null> {
      const row = table.get(id);
      return row ? { ...row } : null;
    },

    async delete(id: string): Promise<void> {
      table.delete(id);
    },

    async reserveRetrySlot(
      input: ReserveInput,
      maxRetries: number,
    ): Promise<AnalysisRun | null> {
      // Simulate v2 RPC: UPDATE ... WHERE id=? AND user_id=? AND
      // conversation_hash=? AND charged=true AND expires_at>now() AND
      // retry_count<? RETURNING *
      const row = table.get(input.runId);
      if (!row) return null;
      if (row.user_id !== input.userId) return null;
      if (row.conversation_hash !== input.conversationHash) return null;
      if (!row.charged) return null;
      if (new Date(row.expires_at).getTime() <= nowFn().getTime()) return null;
      if (row.retry_count >= maxRetries) return null;
      row.retry_count += 1;
      if (!row.consumed_at) row.consumed_at = nowFn().toISOString();
      return { ...row };
    },
  };

  return {
    driver,
    table,
    setNow: (d: Date) => {
      nowFn = () => d;
    },
    chargeCalls,
    simulateChargeFailure: (on: boolean) => {
      chargeShouldFail = on;
    },
    seedUncharged: (input: NewChargedRun) => insertRow(input, false),
  };
}

const USER = "user-aaa";
const OTHER = "user-bbb";
const HASH = "hash-xyz";
const OTHER_HASH = "hash-other";

// ============================================================================
// createChargedRun — Codex P1 atomic charge fix
// ============================================================================

Deno.test("createChargedRun charges quota and creates row atomically", async () => {
  const h = makeDriver();
  const store = new AnalysisRunStore(h.driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: { recommendedReply: "hi" },
    chargeQuota: true,
    messageCount: 1,
  });
  assertEquals(run.user_id, USER);
  assert(run.charged, "row must be charged from the moment it exists");
  assertEquals(run.retry_count, 0);
  assertEquals(h.chargeCalls.count, 1);
  assertEquals(h.chargeCalls.totalMessages, 1);
});

Deno.test("createChargedRun skips charge when chargeQuota=false (test/free path)", async () => {
  // Codex P1 required explicit no-charge branch instead of relying on
  // Edge-side conditionals.
  const h = makeDriver();
  const store = new AnalysisRunStore(h.driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  assert(run.charged);
  assertEquals(h.chargeCalls.count, 0);
});

Deno.test("createChargedRun rolls back both charge and insert if charge step fails", async () => {
  // This is the failure mode the atomic RPC exists to prevent: if charge
  // raises, no row may be left behind AND no quota may be ticked.
  const h = makeDriver();
  h.simulateChargeFailure(true);
  const store = new AnalysisRunStore(h.driver);
  await assertRejects(
    () =>
      store.createChargedRun({
        userId: USER,
        conversationHash: HASH,
        quickResult: {},
        chargeQuota: true,
        messageCount: 1,
      }),
    Error,
    "increment_usage simulated failure",
  );
  assertEquals(h.table.size, 0, "no row should exist after rollback");
  assertEquals(h.chargeCalls.count, 0, "quota counter must not advance");
});

Deno.test("createChargedRun rejects messageCount<=0 when chargeQuota=true", () => {
  const h = makeDriver();
  const store = new AnalysisRunStore(h.driver);
  // Validation is sync — failing before driver call saves a network roundtrip
  // and is symmetric with the DB-side RAISE EXCEPTION.
  assertThrows(
    () =>
      store.createChargedRun({
        userId: USER,
        conversationHash: HASH,
        quickResult: {},
        chargeQuota: true,
        messageCount: 0,
      }),
    Error,
    "messageCount must be a positive integer",
  );
});

Deno.test("createChargedRun accepts messageCount=0 when chargeQuota=false", async () => {
  const h = makeDriver();
  const store = new AnalysisRunStore(h.driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  assert(run.charged);
});

Deno.test("deleteRun removes the row (test cleanup helper)", async () => {
  const h = makeDriver();
  const store = new AnalysisRunStore(h.driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  assertEquals(h.table.size, 1);
  await store.deleteRun(run.id);
  assertEquals(h.table.size, 0);
});

// ============================================================================
// validateRunForFull — I2-I5 + I8
// ============================================================================

Deno.test("validate rejects missing runId with MISSING_RUN_ID (I2)", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const result = await store.validateRunForFull({
    runId: null,
    userId: USER,
    conversationHash: HASH,
  });
  assertFalse(result.ok);
  assertEquals(result.ok ? "" : result.error, "MISSING_RUN_ID");
});

Deno.test("validate rejects empty-string runId with MISSING_RUN_ID", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const result = await store.validateRunForFull({
    runId: "",
    userId: USER,
    conversationHash: HASH,
  });
  assertFalse(result.ok);
  assertEquals(result.ok ? "" : result.error, "MISSING_RUN_ID");
});

Deno.test("validate rejects unknown runId with RUN_NOT_FOUND", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const result = await store.validateRunForFull({
    runId: "run-does-not-exist",
    userId: USER,
    conversationHash: HASH,
  });
  assertFalse(result.ok);
  assertEquals(result.ok ? "" : result.error, "RUN_NOT_FOUND");
});

Deno.test("validate rejects other user's runId with RUN_FORBIDDEN (I3)", async () => {
  // Order matters: forbidden must fire BEFORE state-revealing errors so
  // attackers can't probe foreign run state.
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  const result = await store.validateRunForFull({
    runId: run.id,
    userId: OTHER,
    conversationHash: HASH,
  });
  assertFalse(result.ok);
  assertEquals(result.ok ? "" : result.error, "RUN_FORBIDDEN");
});

Deno.test("validate rejects uncharged run with RUN_NOT_CHARGED (defensive)", async () => {
  // Atomic RPC makes this state unreachable in production. We still pin the
  // check so any future regression that re-introduces an uncharged window is
  // caught by tests.
  const h = makeDriver();
  const store = new AnalysisRunStore(h.driver);
  const row = h.seedUncharged({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  const result = await store.validateRunForFull({
    runId: row.id,
    userId: USER,
    conversationHash: HASH,
  });
  assertFalse(result.ok);
  assertEquals(result.ok ? "" : result.error, "RUN_NOT_CHARGED");
});

Deno.test("validate rejects expired run with RUN_EXPIRED (I4)", async () => {
  const fakeNow = new Date("2026-05-28T00:00:00Z");
  const h = makeDriver({ now: () => fakeNow });
  const store = new AnalysisRunStore(h.driver, () => fakeNow);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });

  const later = new Date(fakeNow.getTime() + 31 * 60 * 1000);
  h.setNow(later);
  const laterStore = new AnalysisRunStore(h.driver, () => later);

  const result = await laterStore.validateRunForFull({
    runId: run.id,
    userId: USER,
    conversationHash: HASH,
  });
  assertFalse(result.ok);
  assertEquals(result.ok ? "" : result.error, "RUN_EXPIRED");
});

Deno.test("validate rejects mismatched hash with RUN_CONVERSATION_MISMATCH (I5)", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  const result = await store.validateRunForFull({
    runId: run.id,
    userId: USER,
    conversationHash: "different-hash",
  });
  assertFalse(result.ok);
  assertEquals(result.ok ? "" : result.error, "RUN_CONVERSATION_MISMATCH");
});

Deno.test("validate accepts charged, fresh, matching run", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: { recommendedReply: "hi" },
    chargeQuota: false,
    messageCount: 0,
  });
  const result = await store.validateRunForFull({
    runId: run.id,
    userId: USER,
    conversationHash: HASH,
  });
  assert(result.ok);
  if (result.ok) {
    assertEquals(result.run.id, run.id);
    assertEquals(result.run.quick_result.recommendedReply, "hi");
  }
});

// ============================================================================
// reserveRetrySlot — I6 + Codex P2 defense-in-depth
// ============================================================================

Deno.test("reserveRetrySlot first call returns ok and increments retry_count to 1", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  const r = await store.reserveRetrySlot({
    runId: run.id,
    userId: USER,
    conversationHash: HASH,
  });
  assert(r.ok);
  if (r.ok) assertEquals(r.run.retry_count, 1);
});

Deno.test("reserveRetrySlot returns RUN_RETRY_EXHAUSTED at 4th attempt", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  for (let i = 0; i < 3; i++) {
    const r = await store.reserveRetrySlot({
      runId: run.id,
      userId: USER,
      conversationHash: HASH,
    });
    assert(r.ok, `attempt ${i + 1} should succeed`);
  }
  const fourth = await store.reserveRetrySlot({
    runId: run.id,
    userId: USER,
    conversationHash: HASH,
  });
  assertFalse(fourth.ok);
  assertEquals(fourth.ok ? "" : fourth.error, "RUN_RETRY_EXHAUSTED");
});

Deno.test("reserveRetrySlot refuses if run never charged", async () => {
  // Defense-in-depth: even if a regression created an uncharged row, retry
  // reservation must not silently grant a free analysis slot.
  const h = makeDriver();
  const row = h.seedUncharged({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  const store = new AnalysisRunStore(h.driver);
  const r = await store.reserveRetrySlot({
    runId: row.id,
    userId: USER,
    conversationHash: HASH,
  });
  assertFalse(r.ok);
});

Deno.test("reserveRetrySlot refuses if run expired", async () => {
  const fakeNow = new Date("2026-05-28T00:00:00Z");
  const h = makeDriver({ now: () => fakeNow });
  const store = new AnalysisRunStore(h.driver, () => fakeNow);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });

  const later = new Date(fakeNow.getTime() + 31 * 60 * 1000);
  h.setNow(later);
  const laterStore = new AnalysisRunStore(h.driver, () => later);

  const r = await laterStore.reserveRetrySlot({
    runId: run.id,
    userId: USER,
    conversationHash: HASH,
  });
  assertFalse(r.ok);
});

Deno.test("reserveRetrySlot refuses on user_id mismatch (Codex P2 defense-in-depth)", async () => {
  // Even if a future caller forgets to call validateRunForFull first, reserve
  // must not hand out a slot for a foreign user's run.
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  const r = await store.reserveRetrySlot({
    runId: run.id,
    userId: OTHER, // wrong user
    conversationHash: HASH,
  });
  assertFalse(r.ok);
});

Deno.test("reserveRetrySlot refuses on conversation_hash mismatch (Codex P2 defense-in-depth)", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  const r = await store.reserveRetrySlot({
    runId: run.id,
    userId: USER,
    conversationHash: OTHER_HASH, // wrong hash
  });
  assertFalse(r.ok);
});

Deno.test("reserveRetrySlot tracks attempts independently per run id", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const runA = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  const runB = await store.createChargedRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
    chargeQuota: false,
    messageCount: 0,
  });
  await store.reserveRetrySlot({ runId: runA.id, userId: USER, conversationHash: HASH });
  await store.reserveRetrySlot({ runId: runA.id, userId: USER, conversationHash: HASH });
  const rB = await store.reserveRetrySlot({
    runId: runB.id,
    userId: USER,
    conversationHash: HASH,
  });
  assert(rB.ok);
  if (rB.ok) assertEquals(rB.run.retry_count, 1);
});

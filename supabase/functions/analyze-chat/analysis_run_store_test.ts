import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import {
  AnalysisRun,
  AnalysisRunDriver,
  AnalysisRunStore,
  NewRun,
} from "./analysis_run_store.ts";

// -----------------------------------------------------------------------------
// In-memory driver — simulates the DB behaviour we need to test the store
// without touching real Postgres. Atomicity of reserveRetrySlot is simulated
// by a sync compare-and-swap on a plain object (single-threaded JS) which is
// good enough to prove the contract; the real RLS migration adds the SQL-level
// atomic guarantee.
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

function makeDriver(opts?: { now?: () => Date; ttlMinutes?: number }): {
  driver: AnalysisRunDriver;
  table: Map<string, FakeRow>;
  setNow: (d: Date) => void;
} {
  const table = new Map<string, FakeRow>();
  let nowFn = opts?.now ?? (() => new Date());
  const ttlMs = (opts?.ttlMinutes ?? 30) * 60 * 1000;
  let seq = 0;
  const newId = () => `run-${++seq}`;

  const driver: AnalysisRunDriver = {
    async insert(row: NewRun): Promise<AnalysisRun> {
      const now = nowFn();
      const stored: FakeRow = {
        id: newId(),
        user_id: row.userId,
        conversation_hash: row.conversationHash,
        charged: false,
        quick_result: row.quickResult,
        request_context: row.requestContext ?? null,
        retry_count: 0,
        created_at: now.toISOString(),
        expires_at: new Date(now.getTime() + ttlMs).toISOString(),
        consumed_at: null,
      };
      table.set(stored.id, stored);
      return { ...stored };
    },
    async selectById(id: string): Promise<AnalysisRun | null> {
      const row = table.get(id);
      return row ? { ...row } : null;
    },
    async markCharged(id: string): Promise<void> {
      const row = table.get(id);
      if (!row) throw new Error("not found");
      row.charged = true;
    },
    async delete(id: string): Promise<void> {
      table.delete(id);
    },
    async reserveRetrySlot(id: string, maxRetries: number): Promise<AnalysisRun | null> {
      // Simulate the SQL: UPDATE ... SET retry_count = retry_count + 1
      //   WHERE id = $1 AND retry_count < $2 AND charged = true
      //   AND expires_at > now() RETURNING *;
      const row = table.get(id);
      if (!row) return null;
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
  };
}

const USER = "user-aaa";
const OTHER = "user-bbb";
const HASH = "hash-xyz";

// ---------------------------- createRun --------------------------------------

Deno.test("createRun inserts row with charged=false and retry_count=0", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: { recommendedReply: "hi" },
  });
  assertEquals(run.user_id, USER);
  assertEquals(run.conversation_hash, HASH);
  assertFalse(run.charged);
  assertEquals(run.retry_count, 0);
});

Deno.test("markCharged flips charged to true", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  await store.markCharged(run.id);
  const fetched = await driver.selectById(run.id);
  assert(fetched);
  assert(fetched.charged);
});

Deno.test("deleteRun removes the row (rollback on RPC failure)", async () => {
  const { driver, table } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  assertEquals(table.size, 1);
  await store.deleteRun(run.id);
  assertEquals(table.size, 0);
});

// ---------------------------- validateRunForFull -----------------------------

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
  // Order matters: forbidden must fire BEFORE state-revealing errors
  // (charged / expired / mismatch) so attackers can't probe foreign run state.
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  await store.markCharged(run.id);
  const result = await store.validateRunForFull({
    runId: run.id,
    userId: OTHER,
    conversationHash: HASH,
  });
  assertFalse(result.ok);
  assertEquals(result.ok ? "" : result.error, "RUN_FORBIDDEN");
});

Deno.test("validate rejects uncharged run with RUN_NOT_CHARGED (I8)", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  // intentionally skip markCharged — simulates quick succeeded but quota RPC
  // crashed mid-flight before deleteRun rollback completed.
  const result = await store.validateRunForFull({
    runId: run.id,
    userId: USER,
    conversationHash: HASH,
  });
  assertFalse(result.ok);
  assertEquals(result.ok ? "" : result.error, "RUN_NOT_CHARGED");
});

Deno.test("validate rejects expired run with RUN_EXPIRED (I4)", async () => {
  const fakeNow = new Date("2026-05-28T00:00:00Z");
  const harness = makeDriver({ now: () => fakeNow });
  const store = new AnalysisRunStore(harness.driver, () => fakeNow);
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  await store.markCharged(run.id);

  // Move clock 31 minutes forward (TTL is 30).
  const later = new Date(fakeNow.getTime() + 31 * 60 * 1000);
  harness.setNow(later);
  const laterStore = new AnalysisRunStore(harness.driver, () => later);

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
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  await store.markCharged(run.id);
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
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: { recommendedReply: "hi" },
  });
  await store.markCharged(run.id);
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

// ---------------------------- reserveRetrySlot (I6) --------------------------

Deno.test("reserveRetrySlot first call returns ok and increments retry_count to 1", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  await store.markCharged(run.id);
  const r = await store.reserveRetrySlot(run.id);
  assert(r.ok);
  if (r.ok) assertEquals(r.run.retry_count, 1);
});

Deno.test("reserveRetrySlot returns RUN_RETRY_EXHAUSTED at 4th attempt", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  await store.markCharged(run.id);

  for (let i = 0; i < 3; i++) {
    const r = await store.reserveRetrySlot(run.id);
    assert(r.ok, `attempt ${i + 1} should succeed`);
  }
  const fourth = await store.reserveRetrySlot(run.id);
  assertFalse(fourth.ok);
  assertEquals(fourth.ok ? "" : fourth.error, "RUN_RETRY_EXHAUSTED");
});

Deno.test("reserveRetrySlot refuses if run never charged (must not bypass quota)", async () => {
  // If quick aborted before markCharged, full must NOT silently retry — that
  // would let a client get free analysis. We refuse the reservation.
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  const r = await store.reserveRetrySlot(run.id);
  assertFalse(r.ok);
  assertEquals(r.ok ? "" : r.error, "RUN_RETRY_EXHAUSTED");
});

Deno.test("reserveRetrySlot refuses if run expired (defense-in-depth alongside validate)", async () => {
  const fakeNow = new Date("2026-05-28T00:00:00Z");
  const harness = makeDriver({ now: () => fakeNow });
  const store = new AnalysisRunStore(harness.driver, () => fakeNow);
  const run = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  await store.markCharged(run.id);

  const later = new Date(fakeNow.getTime() + 31 * 60 * 1000);
  harness.setNow(later);
  const laterStore = new AnalysisRunStore(harness.driver, () => later);

  const r = await laterStore.reserveRetrySlot(run.id);
  assertFalse(r.ok);
});

Deno.test("reserveRetrySlot tracks attempts independently per run id", async () => {
  const { driver } = makeDriver();
  const store = new AnalysisRunStore(driver);
  const runA = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  const runB = await store.createRun({
    userId: USER,
    conversationHash: HASH,
    quickResult: {},
  });
  await store.markCharged(runA.id);
  await store.markCharged(runB.id);

  await store.reserveRetrySlot(runA.id);
  await store.reserveRetrySlot(runA.id);
  // runB still has all 3 slots
  const rB = await store.reserveRetrySlot(runB.id);
  assert(rB.ok);
  if (rB.ok) assertEquals(rB.run.retry_count, 1);
});

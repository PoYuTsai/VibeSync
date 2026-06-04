import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import type { StreamRecommendationForCharge } from "./reframer.ts";
import { AnalysisStreamRunStore } from "./stream_run_store.ts";
import type {
  AnalysisStreamRun,
  AnalysisStreamRunDriver,
  ChargeStreamRunDriverInput,
  CreatePendingStreamRunInput,
  GetStreamRunInput,
  MarkStreamRunDoneInput,
  MarkStreamRunFailedInput,
  ReserveStreamRetryInput,
} from "./stream_run_store.ts";

interface FakeHarness {
  driver: AnalysisStreamRunDriver;
  table: Map<string, AnalysisStreamRun>;
  chargeInputs: ChargeStreamRunDriverInput[];
  doneInputs: MarkStreamRunDoneInput[];
  failedInputs: MarkStreamRunFailedInput[];
}

const USER = "user-aaa";
const OTHER = "user-bbb";
const HASH = "hash-xyz";
const OTHER_HASH = "hash-other";
const NOW = "2026-06-03T00:00:00.000Z";
const CHARGED_AT = "2026-06-03T00:00:03.000Z";
const EXPIRES_AT = "2026-06-03T00:30:00.000Z";

const RECOMMENDATION: StreamRecommendationForCharge = {
  selectedStyle: "resonate",
  message: "I hear you. Let's slow down and make this easy to answer.",
  reason: "This keeps the tone warm while respecting the other person's pace.",
  quotedContext: "I have been busy lately and do not want to feel pushed.",
  warnings: ["Do not push for a result."],
  raw: {
    type: "analysis.recommendation",
    style: "resonate",
    message: "I hear you. Let's slow down and make this easy to answer.",
  },
};

function makeDriver(): FakeHarness {
  const table = new Map<string, AnalysisStreamRun>();
  const chargeInputs: ChargeStreamRunDriverInput[] = [];
  const doneInputs: MarkStreamRunDoneInput[] = [];
  const failedInputs: MarkStreamRunFailedInput[] = [];
  let seq = 0;

  const findMatching = (
    runId: string,
    userId: string,
    conversationHash: string,
  ): AnalysisStreamRun => {
    const row = table.get(runId);
    if (!row) throw new Error("STREAM_RUN_NOT_FOUND");
    if (row.user_id !== userId) throw new Error("STREAM_RUN_OWNER_MISMATCH");
    if (row.conversation_hash !== conversationHash) {
      throw new Error("RUN_CONVERSATION_MISMATCH");
    }
    return row;
  };

  const driver: AnalysisStreamRunDriver = {
    async createPendingRun(
      input: CreatePendingStreamRunInput,
    ): Promise<AnalysisStreamRun> {
      const row: AnalysisStreamRun = {
        id: `stream-run-${++seq}`,
        user_id: input.userId,
        conversation_hash: input.conversationHash,
        status: "pending",
        selected_style: null,
        recommendation_json: null,
        final_result_json: null,
        charged_at: null,
        last_error_code: null,
        retry_count: 0,
        request_context: input.requestContext ?? null,
        created_at: NOW,
        expires_at: EXPIRES_AT,
      };
      table.set(row.id, row);
      return { ...row };
    },

    async getRun(input: GetStreamRunInput): Promise<AnalysisStreamRun> {
      return {
        ...findMatching(input.runId, input.userId, input.conversationHash),
      };
    },

    async reserveRetry(
      input: ReserveStreamRetryInput,
    ): Promise<AnalysisStreamRun> {
      const row = findMatching(
        input.runId,
        input.userId,
        input.conversationHash,
      );
      const expired = Date.parse(row.expires_at) <= Date.parse(CHARGED_AT);
      if (
        row.status !== "failed" ||
        !row.charged_at ||
        !row.recommendation_json ||
        !row.selected_style ||
        expired ||
        row.retry_count >= input.maxRetries
      ) {
        throw new Error("STREAM_RETRY_NOT_AVAILABLE");
      }
      row.retry_count += 1;
      row.last_error_code = null;
      return { ...row };
    },

    async chargeRun(
      input: ChargeStreamRunDriverInput,
    ): Promise<AnalysisStreamRun> {
      chargeInputs.push(input);
      const row = findMatching(
        input.runId,
        input.userId,
        input.conversationHash,
      );

      if (row.charged_at) {
        return { ...row };
      }

      if (row.status !== "pending") {
        throw new Error("STREAM_RUN_NOT_PENDING");
      }

      row.status = "charged";
      row.charged_at = CHARGED_AT;
      row.recommendation_json = input.recommendationJson;
      row.selected_style = input.selectedStyle;
      row.last_error_code = null;
      return { ...row };
    },

    async markDone(
      input: MarkStreamRunDoneInput,
    ): Promise<AnalysisStreamRun> {
      doneInputs.push(input);
      const row = findMatching(
        input.runId,
        input.userId,
        input.conversationHash,
      );
      row.status = "done";
      row.final_result_json = input.finalResult;
      row.last_error_code = null;
      return { ...row };
    },

    async markFailed(
      input: MarkStreamRunFailedInput,
    ): Promise<AnalysisStreamRun> {
      failedInputs.push(input);
      const row = findMatching(
        input.runId,
        input.userId,
        input.conversationHash,
      );
      row.status = "failed";
      row.last_error_code = input.code;
      return { ...row };
    },
  };

  return { driver, table, chargeInputs, doneInputs, failedInputs };
}

Deno.test("createPendingRun stores a pending stream run with request context", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);

  const run = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
    requestContext: { source: "dogfood", messageCount: 2 },
  });

  assertEquals(run.status, "pending");
  assertEquals(run.user_id, USER);
  assertEquals(run.conversation_hash, HASH);
  assertEquals(run.request_context, { source: "dogfood", messageCount: 2 });
  assertEquals(run.recommendation_json, null);
  assertEquals(run.charged_at, null);
  assertEquals(h.table.size, 1);
});

Deno.test("createPendingRun rejects blank user and hash before driver call", () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);

  assertThrows(
    () => store.createPendingRun({ userId: " ", conversationHash: HASH }),
    Error,
    "userId must be non-empty",
  );
  assertThrows(
    () => store.createPendingRun({ userId: USER, conversationHash: "" }),
    Error,
    "conversationHash must be non-empty",
  );
  assertEquals(h.table.size, 0);
});

Deno.test("getRun returns only the matching owner and conversation hash", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });

  const run = await store.getRun({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
  });

  assertEquals(run.id, pending.id);
  await assertRejects(
    () =>
      store.getRun({
        runId: pending.id,
        userId: OTHER,
        conversationHash: HASH,
      }),
    Error,
    "STREAM_RUN_OWNER_MISMATCH",
  );
  await assertRejects(
    () =>
      store.getRun({
        runId: pending.id,
        userId: USER,
        conversationHash: OTHER_HASH,
      }),
    Error,
    "RUN_CONVERSATION_MISMATCH",
  );
});

Deno.test("reserveRetry increments retry_count for a failed charged run", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });
  await store.chargeRun({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    recommendation: RECOMMENDATION,
    chargeQuota: true,
    messageCount: 1,
  });
  await store.markFailed({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    code: "STREAM_FINAL_PERSIST_FAILED",
  });

  const retry = await store.reserveRetry({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    maxRetries: 2,
  });

  assertEquals(retry.status, "failed");
  assertEquals(retry.retry_count, 1);
  assertEquals(retry.last_error_code, null);
  assertEquals(
    retry.recommendation_json,
    h.table.get(pending.id)?.recommendation_json,
  );
});

Deno.test("reserveRetry refuses pending, exhausted, or expired stream runs", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });

  await assertRejects(
    () =>
      store.reserveRetry({
        runId: pending.id,
        userId: USER,
        conversationHash: HASH,
        maxRetries: 2,
      }),
    Error,
    "STREAM_RETRY_NOT_AVAILABLE",
  );

  await store.chargeRun({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    recommendation: RECOMMENDATION,
    chargeQuota: true,
    messageCount: 1,
  });
  await store.markFailed({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    code: "STREAM_INTERRUPTED_AFTER_CONTENT",
  });
  h.table.get(pending.id)!.retry_count = 2;
  await assertRejects(
    () =>
      store.reserveRetry({
        runId: pending.id,
        userId: USER,
        conversationHash: HASH,
        maxRetries: 2,
      }),
    Error,
    "STREAM_RETRY_NOT_AVAILABLE",
  );

  h.table.get(pending.id)!.retry_count = 0;
  h.table.get(pending.id)!.expires_at = "2026-06-02T00:00:00.000Z";
  await assertRejects(
    () =>
      store.reserveRetry({
        runId: pending.id,
        userId: USER,
        conversationHash: HASH,
        maxRetries: 2,
      }),
    Error,
    "STREAM_RETRY_NOT_AVAILABLE",
  );
});

Deno.test("chargeRun serializes recommendation into the atomic charge RPC payload", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });

  const charged = await store.chargeRun({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    recommendation: RECOMMENDATION,
    chargeQuota: true,
    messageCount: 1,
  });

  assertEquals(charged.status, "charged");
  assertEquals(charged.charged_at, CHARGED_AT);
  assertEquals(charged.selected_style, "resonate");
  assertEquals(charged.recommendation_json, {
    selectedStyle: "resonate",
    message: "I hear you. Let's slow down and make this easy to answer.",
    reason:
      "This keeps the tone warm while respecting the other person's pace.",
    quotedContext: "I have been busy lately and do not want to feel pushed.",
    warnings: ["Do not push for a result."],
    raw: RECOMMENDATION.raw,
  });
  assertEquals(h.chargeInputs, [{
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    recommendationJson: charged.recommendation_json,
    selectedStyle: "resonate",
    chargeQuota: true,
    messageCount: 1,
  }]);
});

Deno.test("chargeRun rejects non-positive messageCount when chargeQuota=true", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });

  assertThrows(
    () =>
      store.chargeRun({
        runId: pending.id,
        userId: USER,
        conversationHash: HASH,
        recommendation: RECOMMENDATION,
        chargeQuota: true,
        messageCount: 0,
      }),
    Error,
    "chargeRun: messageCount must be a positive integer when chargeQuota=true",
  );
  assertEquals(h.chargeInputs.length, 0);
});

Deno.test("chargeRun allows messageCount=0 when chargeQuota=false", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });

  const charged = await store.chargeRun({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    recommendation: RECOMMENDATION,
    chargeQuota: false,
    messageCount: 0,
  });

  assertEquals(charged.status, "charged");
  assertEquals(h.chargeInputs[0].chargeQuota, false);
  assertEquals(h.chargeInputs[0].messageCount, 0);
});

Deno.test("chargeRun is idempotent after the run is already charged", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });

  const first = await store.chargeRun({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    recommendation: RECOMMENDATION,
    chargeQuota: true,
    messageCount: 1,
  });
  const second = await store.chargeRun({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    recommendation: {
      ...RECOMMENDATION,
      selectedStyle: "extend",
      message: "should not replace",
    },
    chargeQuota: true,
    messageCount: 1,
  });

  assertEquals(second.charged_at, first.charged_at);
  assertEquals(second.selected_style, "resonate");
  assertEquals(second.recommendation_json, first.recommendation_json);
  assertEquals(h.chargeInputs.length, 2);
});

Deno.test("markDone stores final result and clears previous error", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });
  await store.chargeRun({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    recommendation: RECOMMENDATION,
    chargeQuota: true,
    messageCount: 1,
  });
  await store.markFailed({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    code: "STREAM_TIMEOUT",
  });

  const done = await store.markDone({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    finalResult: { finalRecommendation: "Final recommendation" },
  });

  assertEquals(done.status, "done");
  assertEquals(done.final_result_json, {
    finalRecommendation: "Final recommendation",
  });
  assertEquals(done.last_error_code, null);
  assertEquals(h.doneInputs.length, 1);
});

Deno.test("markFailed stores the failure code", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });

  const failed = await store.markFailed({
    runId: pending.id,
    userId: USER,
    conversationHash: HASH,
    code: "STREAM_MODEL_TIMEOUT",
  });

  assertEquals(failed.status, "failed");
  assertEquals(failed.last_error_code, "STREAM_MODEL_TIMEOUT");
  assertEquals(h.failedInputs.length, 1);
});

Deno.test("markDone refuses wrong owner or conversation hash", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });

  await assertRejects(
    () =>
      store.markDone({
        runId: pending.id,
        userId: OTHER,
        conversationHash: HASH,
        finalResult: {},
      }),
    Error,
    "STREAM_RUN_OWNER_MISMATCH",
  );
  await assertRejects(
    () =>
      store.markDone({
        runId: pending.id,
        userId: USER,
        conversationHash: OTHER_HASH,
        finalResult: {},
      }),
    Error,
    "RUN_CONVERSATION_MISMATCH",
  );
});

Deno.test("markFailed rejects a blank error code before driver call", async () => {
  const h = makeDriver();
  const store = new AnalysisStreamRunStore(h.driver);
  const pending = await store.createPendingRun({
    userId: USER,
    conversationHash: HASH,
  });

  assertThrows(
    () =>
      store.markFailed({
        runId: pending.id,
        userId: USER,
        conversationHash: HASH,
        code: " ",
      }),
    Error,
    "code must be non-empty",
  );
  assertEquals(h.failedInputs.length, 0);
});

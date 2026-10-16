// v3 任務卡扣費（charge_stream_analysis_run_v3）的 store 驗證與 Supabase driver 參數。
// RPC 本身的行為由 stream_runs_decision_kind_migration_postgres_test.ts（PGlite）負責。
import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type AnalysisStreamRun,
  type AnalysisStreamRunDriver,
  AnalysisStreamRunStore,
  type ChargeStreamRunV3Input,
  createSupabaseAnalysisStreamRunDriver,
} from "./stream_run_store.ts";

const ROW: AnalysisStreamRun = {
  id: "run-1",
  user_id: "user-1",
  conversation_hash: "hash-1",
  status: "charged",
  selected_style: null,
  decision_kind: "send",
  card_task: "accept",
  recommendation_json: { decisionKind: "send", cardTask: "accept" },
  final_result_json: null,
  charged_at: "2026-10-16T00:00:00.000Z",
  last_error_code: null,
  retry_count: 0,
  request_context: null,
  created_at: "2026-10-16T00:00:00.000Z",
  expires_at: "2026-10-16T00:30:00.000Z",
};

const SEND: ChargeStreamRunV3Input = {
  runId: "run-1",
  userId: "user-1",
  conversationHash: "hash-1",
  recommendationJson: {
    decisionKind: "send",
    cardTask: "accept",
    guideVersion: "v3.3",
  },
  decisionKind: "send",
  cardTask: "accept",
  chargeQuota: true,
  messageCount: 2,
};

const NO_SEND: ChargeStreamRunV3Input = {
  ...SEND,
  recommendationJson: {
    decisionKind: "do_not_send",
    action: "wait",
    reason: "他的訊息是最後一則",
    stopCondition: "等她回",
    guideVersion: "v3.3",
  },
  decisionKind: "do_not_send",
  cardTask: null,
};

function unused(): never {
  throw new Error("not used in this test");
}

function driverWithV3(
  calls: ChargeStreamRunV3Input[],
): AnalysisStreamRunDriver {
  return {
    createPendingRun: unused,
    getRun: unused,
    reserveRetry: unused,
    chargeRun: unused,
    markDone: unused,
    markFailed: unused,
    chargeRunV3: (input) => {
      calls.push(input);
      return Promise.resolve(ROW);
    },
  };
}

Deno.test("chargeRunV3 passes valid send and no-send charges straight to the driver", async () => {
  const calls: ChargeStreamRunV3Input[] = [];
  const store = new AnalysisStreamRunStore(driverWithV3(calls));
  assertEquals(await store.chargeRunV3(SEND), ROW);
  await store.chargeRunV3(NO_SEND);
  // 測試帳號：不扣時 messageCount 不檢查。
  await store.chargeRunV3({ ...SEND, chargeQuota: false, messageCount: 0 });
  assertEquals(calls, [SEND, NO_SEND, {
    ...SEND,
    chargeQuota: false,
    messageCount: 0,
  }]);
});

Deno.test("chargeRunV3 rejects shapes the v3 RPC would reject, before calling the driver", () => {
  const calls: ChargeStreamRunV3Input[] = [];
  const store = new AnalysisStreamRunStore(driverWithV3(calls));
  const bad: ChargeStreamRunV3Input[] = [
    { ...SEND, cardTask: null },
    { ...SEND, cardTask: "flirt" as never },
    { ...SEND, recommendationJson: { decisionKind: "send", cardTask: "push" } },
    { ...SEND, recommendationJson: { cardTask: "accept" } },
    {
      ...SEND,
      recommendationJson: {
        decisionKind: "send",
        cardTask: "accept",
        selectedStyle: "extend",
      },
    },
    { ...NO_SEND, cardTask: "accept" },
    {
      ...NO_SEND,
      recommendationJson: { ...NO_SEND.recommendationJson, cardTask: "accept" },
    },
    {
      ...NO_SEND,
      recommendationJson: {
        ...NO_SEND.recommendationJson,
        decisionKind: "acknowledge_and_stop",
      },
    },
    { ...SEND, messageCount: 0 },
    { ...SEND, runId: " " },
  ];
  for (const input of bad) {
    assertThrows(() => store.chargeRunV3(input));
  }
  assertEquals(calls.length, 0);
});

Deno.test("chargeRunV3 refuses a driver without v3 support instead of falling back to v1/v2", () => {
  const { chargeRunV3: _drop, ...legacy } = driverWithV3([]);
  const store = new AnalysisStreamRunStore(legacy);
  assertThrows(
    () => store.chargeRunV3(SEND),
    Error,
    "driver does not support v3 charges",
  );
});

Deno.test("Supabase driver calls charge_stream_analysis_run_v3 with the migration's parameter names", async () => {
  const rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];
  const driver = createSupabaseAnalysisStreamRunDriver(
    {
      from: unused,
      rpc: (fn: string, args: Record<string, unknown>) => {
        rpcCalls.push({ fn, args });
        return Promise.resolve({ data: ROW, error: null });
      },
    } as unknown as Parameters<typeof createSupabaseAnalysisStreamRunDriver>[0],
  );
  assertEquals(await driver.chargeRunV3!(SEND), ROW);
  assertEquals(rpcCalls, [{
    fn: "charge_stream_analysis_run_v3",
    args: {
      p_run_id: "run-1",
      p_user_id: "user-1",
      p_conversation_hash: "hash-1",
      p_recommendation_json: SEND.recommendationJson,
      p_decision_kind: "send",
      p_card_task: "accept",
      p_message_count: 2,
      p_charge_quota: true,
    },
  }]);

  const failing = createSupabaseAnalysisStreamRunDriver(
    {
      from: unused,
      rpc: () =>
        Promise.resolve({
          data: null,
          error: { message: "STREAM_RUN_EXPIRED" },
        }),
    } as unknown as Parameters<typeof createSupabaseAnalysisStreamRunDriver>[0],
  );
  await assertRejects(
    () => failing.chargeRunV3!(SEND),
    Error,
    "charge_stream_analysis_run_v3 failed",
  );
});

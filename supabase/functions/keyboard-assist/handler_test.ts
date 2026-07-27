import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  createKeyboardAssistHandler,
  type KeyboardAssistHandlerDependencies,
} from "./handler.ts";
import type { KeyboardAssistLedgerResult } from "./contract.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const KEY = btoa("0123456789abcdef0123456789abcdef");
const PNG_DATA =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
const ready: KeyboardAssistLedgerResult = {
  contractVersion: "keyboard-assist-v1",
  status: "ready",
  source: {
    scope: "screenshot_only",
    messageCount: 2,
    confidence: "high",
    sideConfidence: "high",
  },
  turnState: "reply_due",
  cue: "輪到你回覆。",
  uncertainty: null,
  options: [
    {
      strategy: "keep_pace",
      text: "有啊，你有什麼想法？",
      why: "先接住對方的問題",
      effect: "自然延續",
    },
    {
      strategy: "build_connection",
      text: "有空，聽起來你已經有計畫了 😄",
      why: "接住邀約感並增加溫度",
      effect: "互動感較高",
    },
    {
      strategy: "move_forward",
      text: "有空，週六下午要不要一起喝杯咖啡？",
      why: "直接把邀約變成安排",
      effect: "推進最快",
    },
  ],
};
const confirmation: KeyboardAssistLedgerResult = {
  contractVersion: "keyboard-assist-v1",
  status: "needs_speaker_confirmation",
  suggestedMySide: "right",
  sideConfidence: "low",
};

function postBody(overrides: Record<string, unknown> = {}) {
  return {
    contractVersion: "keyboard-assist-v1",
    requestId: REQUEST_ID,
    image: { mediaType: "image/png", data: PNG_DATA },
    speakerOverride: "none",
    voice: { primary: "steady", secondary: null },
    ...overrides,
  };
}

function fakeDependencies() {
  const calls: string[] = [];
  const telemetryRecords: Array<Record<string, string | number | boolean>> = [];
  let row: Awaited<
    ReturnType<KeyboardAssistHandlerDependencies["ledger"]["lookup"]>
  > = null;
  let pipelineResult: KeyboardAssistLedgerResult = ready;
  let quotaAllowed = true;
  let rateAllowed = true;
  let featureEnabled = true;
  let monotonicMs = 1000;
  const deps: KeyboardAssistHandlerDependencies = {
    authenticate: (request) => {
      calls.push("auth");
      return Promise.resolve(
        request.headers.get("authorization") === "Bearer good"
          ? { id: "user-1", email: "user@example.com" }
          : null,
      );
    },
    ledger: {
      lookup: () => {
        calls.push("lookup");
        return Promise.resolve(row);
      },
      claim: () => {
        calls.push("claim");
        return Promise.resolve({ kind: "claimed" });
      },
      renew: () => {
        calls.push("renew");
        return Promise.resolve(true);
      },
      release: () => {
        calls.push("release");
        return Promise.resolve(true);
      },
      settle: (input) => {
        calls.push(`settle:${input.chargeQuota}`);
        return Promise.resolve({
          kind: "settled",
          charged: input.chargeQuota,
          result: input.result,
        });
      },
      expire: () => {
        calls.push("expire");
        row = null;
        return Promise.resolve(true);
      },
    },
    quota: {
      check: () => {
        calls.push("quota");
        return Promise.resolve(
          quotaAllowed
            ? {
              kind: "allowed",
              monthlyLimit: 800,
              dailyLimit: 80,
              chargeQuota: true,
            }
            : { kind: "limited", message: "額度已用完" },
        );
      },
    },
    rateLimit: () => {
      calls.push("rate");
      return Promise.resolve(
        rateAllowed
          ? { kind: "allowed" }
          : { kind: "limited", retryAfterMs: 60_000 },
      );
    },
    runPipeline: (input) => {
      calls.push("pipeline");
      input.recordStageTiming({ compilerMs: 300 });
      if (pipelineResult.status === "ready") {
        input.recordStageTiming({ judgeMs: 150 });
      }
      monotonicMs += 500;
      return Promise.resolve(pipelineResult);
    },
    recordTelemetry: (record) => telemetryRecords.push(record),
    featureEnabled: () => featureEnabled,
    keyring: {
      currentVersion: 1,
      keys: new Map([[1, KEY]]),
    },
    pipelineVersion: "compiler-judge-v1",
    now: () => new Date("2026-07-27T12:00:00.000Z"),
    monotonicNow: () => monotonicMs,
    randomUuid: () => "223e4567-e89b-42d3-a456-426614174000",
  };
  return {
    calls,
    telemetryRecords,
    deps,
    setRow(value: typeof row) {
      row = value;
    },
    setPipelineResult(value: KeyboardAssistLedgerResult) {
      pipelineResult = value;
    },
    setQuotaAllowed(value: boolean) {
      quotaAllowed = value;
    },
    setRateAllowed(value: boolean) {
      rateAllowed = value;
    },
    setFeatureEnabled(value: boolean) {
      featureEnabled = value;
    },
  };
}

function authorizedRequest(
  method: "GET" | "POST",
  body?: unknown,
  query = "",
) {
  return new Request(`https://example.test/keyboard-assist${query}`, {
    method,
    headers: {
      Authorization: "Bearer good",
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

async function responseJson(response: Response) {
  return await response.json() as Record<string, unknown>;
}

Deno.test("JWT auth happens before request parsing", async () => {
  const fake = fakeDependencies();
  const response = await createKeyboardAssistHandler(fake.deps)(
    new Request("https://example.test/keyboard-assist", {
      method: "POST",
      headers: { Authorization: "Bearer bad" },
      body: "{not-json",
    }),
  );
  assertEquals(response.status, 401);
  assertEquals(fake.calls, ["auth"]);
  assertEquals((await responseJson(response)).error, {
    code: "unauthorized",
    retryDisposition: "terminal_clear",
  });
});

Deno.test("GET replays done without image, HMAC, quota, rate, or provider", async () => {
  const fake = fakeDependencies();
  fake.setRow({
    input_hash: "a".repeat(64),
    hmac_key_version: 99,
    state: "done",
    lease_expires_at: "2026-07-27T11:00:00.000Z",
    created_at: "2026-07-27T11:00:00.000Z",
    result_json: ready,
  });
  const response = await createKeyboardAssistHandler(fake.deps)(
    authorizedRequest("GET", undefined, `?requestId=${REQUEST_ID}`),
  );
  assertEquals(response.status, 200);
  assertEquals(await responseJson(response), {
    ...ready,
    requestId: REQUEST_ID,
  });
  assertEquals(fake.calls, ["auth", "lookup"]);
});

Deno.test("capability negotiation happens before any screenshot or ledger lookup", async () => {
  const fake = fakeDependencies();
  fake.setFeatureEnabled(false);
  const response = await createKeyboardAssistHandler(fake.deps)(
    authorizedRequest("GET", undefined, "?capability=1"),
  );
  assertEquals(response.status, 200);
  assertEquals(await responseJson(response), {
    contractVersion: "keyboard-assist-v1",
    enabled: false,
    pipelineVersion: "compiler-judge-v1",
  });
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(fake.calls, ["auth"]);
});

Deno.test("GET maps pending, expired, and missing owner-scoped requests", async () => {
  const pending = fakeDependencies();
  pending.setRow({
    input_hash: "a".repeat(64),
    hmac_key_version: 1,
    state: "pending",
    lease_expires_at: "2026-07-27T12:00:02.000Z",
    created_at: "2026-07-27T11:00:00.000Z",
    result_json: null,
  });
  let response = await createKeyboardAssistHandler(pending.deps)(
    authorizedRequest("GET", undefined, `?requestId=${REQUEST_ID}`),
  );
  assertEquals(response.status, 425);
  assertEquals(
    ((await responseJson(response)).error as Record<string, unknown>).code,
    "request_pending",
  );

  const expired = fakeDependencies();
  expired.setRow({
    input_hash: "a".repeat(64),
    hmac_key_version: 1,
    state: "pending",
    lease_expires_at: "2026-07-27T11:59:59.000Z",
    created_at: "2026-07-27T11:00:00.000Z",
    result_json: null,
  });
  response = await createKeyboardAssistHandler(expired.deps)(
    authorizedRequest("GET", undefined, `?requestId=${REQUEST_ID}`),
  );
  assertEquals(response.status, 410);
  assertEquals(expired.calls, ["auth", "lookup", "expire"]);

  const missing = fakeDependencies();
  response = await createKeyboardAssistHandler(missing.deps)(
    authorizedRequest("GET", undefined, `?requestId=${REQUEST_ID}`),
  );
  assertEquals(response.status, 404);
});

Deno.test("GET infrastructure failures preserve image-free status lookup", async () => {
  const fake = fakeDependencies();
  fake.deps.ledger.lookup = () => {
    fake.calls.push("lookup");
    throw new Error("database unavailable");
  };

  const response = await createKeyboardAssistHandler(fake.deps)(
    authorizedRequest("GET", undefined, `?requestId=${REQUEST_ID}`),
  );
  assertEquals(response.status, 503);
  assertEquals(await responseJson(response), {
    error: {
      code: "service_unavailable",
      retryDisposition: "lookup_same_request",
    },
  });
});

Deno.test("GET auth infrastructure failures preserve status lookup", async () => {
  const fake = fakeDependencies();
  fake.deps.authenticate = () => {
    fake.calls.push("auth");
    throw new Error("authentication service unavailable");
  };

  const response = await createKeyboardAssistHandler(fake.deps)(
    authorizedRequest("GET", undefined, `?requestId=${REQUEST_ID}`),
  );
  assertEquals(response.status, 503);
  assertEquals(await responseJson(response), {
    error: {
      code: "service_unavailable",
      retryDisposition: "lookup_same_request",
    },
  });
});

Deno.test("POST exact replay precedes feature, quota, rate, and provider gates", async () => {
  const fake = fakeDependencies();
  fake.setFeatureEnabled(false);
  const first = await createKeyboardAssistHandler(fake.deps)(
    authorizedRequest("POST", postBody()),
  );
  assertEquals(first.status, 503);
  const claimIndex = fake.calls.indexOf("claim");
  assertEquals(claimIndex, -1);

  // Capture the calculated input HMAC from a claim, then present it as a done
  // row to prove a replay bypasses all mutable gates.
  let capturedHash = "";
  fake.deps.ledger.claim = (input) => {
    capturedHash = input.inputHash;
    return Promise.resolve({ kind: "claimed" });
  };
  fake.setFeatureEnabled(true);
  await createKeyboardAssistHandler(fake.deps)(
    authorizedRequest("POST", postBody()),
  );
  fake.calls.length = 0;
  fake.setFeatureEnabled(false);
  fake.setQuotaAllowed(false);
  fake.setRateAllowed(false);
  fake.setRow({
    input_hash: capturedHash,
    hmac_key_version: 1,
    state: "done",
    lease_expires_at: "2026-07-27T12:00:55.000Z",
    created_at: "2026-07-27T11:00:00.000Z",
    result_json: ready,
  });
  const replay = await createKeyboardAssistHandler(fake.deps)(
    authorizedRequest("POST", postBody()),
  );
  assertEquals(replay.status, 200);
  assertEquals(fake.calls, ["auth", "lookup"]);
});

Deno.test("POST same request ID with changed image is 409 and unchanged", async () => {
  const fake = fakeDependencies();
  fake.setRow({
    input_hash: "b".repeat(64),
    hmac_key_version: 1,
    state: "done",
    lease_expires_at: "2026-07-27T12:00:55.000Z",
    created_at: "2026-07-27T11:00:00.000Z",
    result_json: ready,
  });
  const response = await createKeyboardAssistHandler(fake.deps)(
    authorizedRequest("POST", postBody()),
  );
  assertEquals(response.status, 409);
  assertEquals(fake.calls, ["auth", "lookup"]);
});

Deno.test("ready settles once with quota; speaker confirmation settles zero", async () => {
  const readyFake = fakeDependencies();
  let response = await createKeyboardAssistHandler(readyFake.deps)(
    authorizedRequest("POST", postBody()),
  );
  assertEquals(response.status, 200);
  assertEquals(readyFake.calls.filter((call) => call === "quota").length, 2);
  assertEquals(
    readyFake.calls.filter((call) => call === "pipeline").length,
    1,
  );
  assertEquals(
    readyFake.calls.filter((call) => call === "settle:true").length,
    1,
  );
  assertEquals(readyFake.telemetryRecords, [{
    event: "keyboard_assist_succeeded",
    contractVersion: "keyboard-assist-v1",
    pipelineVersion: "compiler-judge-v1",
    status: "ready",
    compilerMs: 300,
    judgeMs: 150,
    totalMs: 500,
    replay: false,
  }]);
  const telemetryWire = JSON.stringify(readyFake.telemetryRecords);
  for (
    const forbidden of [
      "user-1",
      REQUEST_ID,
      PNG_DATA,
      "messages",
      "transcript",
      "candidate",
    ]
  ) {
    assertFalse(telemetryWire.includes(forbidden));
  }

  const confirmFake = fakeDependencies();
  confirmFake.setPipelineResult(confirmation);
  response = await createKeyboardAssistHandler(confirmFake.deps)(
    authorizedRequest("POST", postBody()),
  );
  assertEquals(response.status, 200);
  assertEquals(confirmFake.calls.includes("settle:false"), true);
  assertEquals(confirmFake.calls.filter((call) => call === "quota").length, 1);
  assertFalse(
    JSON.stringify(await responseJson(response)).includes("messages"),
  );
  assertEquals(confirmFake.telemetryRecords, [{
    event: "keyboard_assist_succeeded",
    contractVersion: "keyboard-assist-v1",
    pipelineVersion: "compiler-judge-v1",
    status: "needs_speaker_confirmation",
    compilerMs: 300,
    totalMs: 500,
    replay: false,
  }]);
});

Deno.test("quota and model rate failures release owner and remain distinct", async () => {
  const quota = fakeDependencies();
  quota.setQuotaAllowed(false);
  let response = await createKeyboardAssistHandler(quota.deps)(
    authorizedRequest("POST", postBody()),
  );
  assertEquals(response.status, 429);
  assertEquals(
    ((await responseJson(response)).error as Record<string, unknown>).code,
    "quota_exhausted",
  );
  assertEquals(quota.calls.includes("release"), true);
  assertEquals(quota.calls.includes("rate"), false);

  const rate = fakeDependencies();
  rate.setRateAllowed(false);
  response = await createKeyboardAssistHandler(rate.deps)(
    authorizedRequest("POST", postBody()),
  );
  const payload = await responseJson(response);
  assertEquals(response.status, 429);
  assertEquals(
    (payload.error as Record<string, unknown>).code,
    "model_rate_limited",
  );
  assertEquals("monthlyLimit" in payload, false);
  assertEquals(rate.calls.includes("release"), true);
});

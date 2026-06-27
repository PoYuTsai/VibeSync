import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  createPracticeChatHandler,
  type DeepSeekCaller,
  type PracticeSupabaseClient,
} from "./handler.ts";
import { temperatureBandFor } from "./temperature.ts";
import { DEEPSEEK_MODEL, type DeepSeekArgs } from "./deepseek.ts";
import { MAX_HINTS_PER_ROUND } from "./quota_decision.ts";

const NOW = new Date("2026-06-28T04:00:00.000Z");
const RESET_AT = "2026-06-28T00:00:00.000Z";

type RpcResult = { data?: unknown; error?: string };

interface FakeOptions {
  user?: { id: string; email?: string | null } | null;
  userError?: string;
  sub?: Record<string, unknown> | null;
  subError?: string;
  ledger?: Record<string, unknown> | null;
  ledgerError?: string;
  rpc?: Record<string, RpcResult[]>;
  deepSeekReplies?: Array<string | Error>;
}

interface FakeState {
  selects: Array<{ table: string; columns: string }>;
  rpcCalls: Array<{ fn: string; params: Record<string, unknown> }>;
  deepSeekCalls: DeepSeekArgs[];
  events: string[];
}

function subscription(overrides: Record<string, unknown> = {}) {
  return {
    tier: "starter",
    monthly_messages_used: 10,
    daily_messages_used: 2,
    daily_reset_at: RESET_AT,
    monthly_reset_at: RESET_AT,
    ...overrides,
  };
}

function ledger(overrides: Record<string, unknown> = {}) {
  return {
    ai_count: 0,
    charged: false,
    debrief_count: 0,
    practice_mode: "standard",
    temperature_score: null,
    hint_count: 0,
    ...overrides,
  };
}

function beginnerStartedLedger(overrides: Record<string, unknown> = {}) {
  return ledger({
    ai_count: 1,
    charged: true,
    practice_mode: "beginner",
    temperature_score: 30,
    hint_count: 0,
    ...overrides,
  });
}

function chatBody(overrides: Record<string, unknown> = {}) {
  return {
    mode: "chat",
    sessionId: "session-1",
    roundIndex: 1,
    turns: [{ role: "user", text: "hi" }],
    ...overrides,
  };
}

function hintBody(overrides: Record<string, unknown> = {}) {
  return {
    mode: "hint",
    sessionId: "session-1",
    turns: [
      { role: "user", text: "hi" },
      { role: "ai", text: "hello" },
    ],
    ...overrides,
  };
}

function validHintJson(overrides: Record<string, string> = {}) {
  return JSON.stringify({
    warmUp: "我喜歡你剛剛那個反應，有點可愛。",
    steady: "哈哈那我先記下來，之後再慢慢觀察。",
    coaching: "先接住對方情緒，再用一點點曖昧推進。",
    ...overrides,
  });
}

function makeRequest(body: unknown) {
  return new Request("http://localhost/practice-chat", {
    method: "POST",
    headers: {
      Authorization: "Bearer test-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function makeFake(options: FakeOptions = {}) {
  const state: FakeState = {
    selects: [],
    rpcCalls: [],
    deepSeekCalls: [],
    events: [],
  };
  const rpcByName = new Map<string, number>();
  let deepSeekIndex = 0;

  // deno-lint-ignore no-explicit-any
  const client: any = {
    auth: {
      getUser(_token: string) {
        if (options.userError) {
          return Promise.resolve({
            data: { user: null },
            error: { message: options.userError },
          });
        }
        return Promise.resolve({
          data: {
            user: options.user === undefined
              ? { id: "user-1", email: "user@example.com" }
              : options.user,
          },
          error: null,
        });
      },
    },
    from(table: string) {
      return {
        select(columns: string) {
          state.selects.push({ table, columns });
          // deno-lint-ignore no-explicit-any
          const builder: any = {
            eq(_column: string, _value: unknown) {
              return builder;
            },
            maybeSingle() {
              if (table === "subscriptions") {
                return Promise.resolve(
                  options.subError
                    ? { data: null, error: { message: options.subError } }
                    : {
                      data: options.sub === undefined
                        ? subscription()
                        : options.sub,
                      error: null,
                    },
                );
              }
              if (table === "practice_chat_sessions") {
                return Promise.resolve(
                  options.ledgerError
                    ? { data: null, error: { message: options.ledgerError } }
                    : {
                      data: options.ledger === undefined
                        ? ledger()
                        : options.ledger,
                      error: null,
                    },
                );
              }
              return Promise.resolve({ data: null, error: null });
            },
          };
          return builder;
        },
        update(_values: Record<string, unknown>) {
          return {
            eq(_column: string, _value: unknown) {
              return Promise.resolve({ data: null, error: null });
            },
          };
        },
      };
    },
    rpc(fn: string, params: Record<string, unknown>) {
      state.rpcCalls.push({ fn, params });
      state.events.push(`rpc:${fn}`);
      const index = rpcByName.get(fn) ?? 0;
      rpcByName.set(fn, index + 1);
      const result = options.rpc?.[fn]?.[index] ??
        (fn === "commit_practice_chat_turn"
          ? { data: { new_ai_count: 1, did_charge: true } }
          : { data: { updated: true, temperature_score: 34 } });
      return Promise.resolve(
        result.error
          ? { data: null, error: { message: result.error } }
          : { data: result.data ?? null, error: null },
      );
    },
  };

  const deepSeek: DeepSeekCaller = (args) => {
    state.deepSeekCalls.push(args);
    state.events.push("deepseek");
    const reply = options.deepSeekReplies?.[deepSeekIndex] ?? "AI reply";
    deepSeekIndex++;
    if (reply instanceof Error) {
      return Promise.reject(reply);
    }
    return Promise.resolve(reply);
  };

  return {
    state,
    handler: createPracticeChatHandler({
      createSupabaseClient: () => client as PracticeSupabaseClient,
      callDeepSeek: deepSeek,
      getEnv: (name) => name === "DEEPSEEK_API_KEY" ? "deepseek-key" : "",
      now: () => NOW,
    }),
  };
}

async function run(options: FakeOptions, body: unknown = chatBody()) {
  const fake = makeFake(options);
  const response = await fake.handler(makeRequest(body));
  const json = await response.json();
  return { ...fake, response, json };
}

function recordHintCalls(state: FakeState) {
  return state.rpcCalls.filter((call) => call.fn === "record_practice_hint");
}

function claimHintCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "claim_practice_hint_generation"
  );
}

function releaseHintCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "release_practice_hint_generation"
  );
}

function commitCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "commit_practice_chat_turn"
  );
}

function temperatureUpdateCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "update_practice_temperature"
  );
}

Deno.test("standard chat response does not include temperature and does not judge or update", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ practice_mode: "standard" }),
  });

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assertEquals("temperature" in json, false);
  assertEquals(
    state.rpcCalls.some((call) => call.fn === "update_practice_temperature"),
    false,
  );
  assertEquals(state.deepSeekCalls.length, 1);
  assertEquals(state.deepSeekCalls[0].jsonMode, undefined);
});

Deno.test("beginner first chat uses initial temp 30 and returns temperature plus hint count", async () => {
  const { response, json, state } = await run({
    ledger: null,
    deepSeekReplies: ["AI reply", `{"delta":4,"reason":"warmer"}`],
  }, chatBody({ practiceMode: "beginner", temperatureScore: 30 }));

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assertEquals(json.hintUsedCount, 0);
  assertEquals(json.temperature, {
    score: 34,
    delta: 4,
    band: temperatureBandFor(34),
    reason: "warmer",
  });
  assert(
    state.deepSeekCalls[0].messages[0].content.includes("30/100"),
    "chat system prompt should include beginner initial temperature",
  );
  assertEquals(
    state.rpcCalls.find((call) => call.fn === "update_practice_temperature")
      ?.params.p_temperature_score,
    34,
  );
});

Deno.test("beginner first chat ignores client temperature and falls back to server initial 30", async () => {
  const { response, json, state } = await run({
    ledger: null,
    deepSeekReplies: ["AI reply", new Error("judge down")],
  }, chatBody({ practiceMode: "beginner", temperatureScore: 100 }));

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 30);
  assertEquals(json.temperature.delta, 0);

  const allDeepSeekPromptText = state.deepSeekCalls
    .flatMap((call) => call.messages)
    .map((message) => message.content)
    .join("\n");
  assert(allDeepSeekPromptText.includes("30/100"));
  assertEquals(allDeepSeekPromptText.includes("100/100"), false);

  const commit = state.rpcCalls.find((call) =>
    call.fn === "commit_practice_chat_turn"
  );
  assert(commit);
  assertEquals(commit.params.p_temperature_score, 30);
  assertEquals("p_initial_temperature_score" in commit.params, false);
});

Deno.test("beginner later chat uses ledger temperature over client sent score", async () => {
  const { response, json, state } = await run({
    ledger: ledger({
      ai_count: 3,
      charged: true,
      practice_mode: "beginner",
      temperature_score: 64,
      hint_count: 2,
    }),
    deepSeekReplies: ["AI reply", `{"delta":-2,"reason":"cooler"}`],
  }, chatBody({ practiceMode: "beginner", temperatureScore: 10 }));

  assertEquals(response.status, 200);
  assertEquals(json.hintUsedCount, 2);
  assertEquals(json.temperature.score, 62);
  assertEquals(json.temperature.delta, -2);
  const systemPrompt = state.deepSeekCalls[0].messages[0].content;
  assert(systemPrompt.includes("64/100"));
  assertEquals(systemPrompt.includes("10/100"), false);
});

Deno.test("chat commit uses practice mode and temperature RPC arguments", async () => {
  const { state } = await run({
    ledger: ledger({ practice_mode: "standard" }),
  }, chatBody({ practiceMode: "standard", temperatureScore: 30 }));

  const commit = state.rpcCalls.find((call) =>
    call.fn === "commit_practice_chat_turn"
  );
  assert(commit);
  assertEquals(commit.params.p_user_id, "user-1");
  assertEquals(commit.params.p_session_id, "session-1");
  assertEquals(commit.params.p_charge_quota, true);
  assertEquals(commit.params.p_max_replies, 20);
  assertEquals(commit.params.p_practice_mode, "standard");
  assertEquals(commit.params.p_temperature_score, 30);
  assertEquals("p_initial_temperature_score" in commit.params, false);
});

Deno.test("existing ledger mode mismatch rejects before DeepSeek and RPC", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ practice_mode: "standard" }),
  }, chatBody({ practiceMode: "beginner", temperatureScore: 30 }));

  assertEquals(response.status, 409);
  assertEquals(json, { error: "practice_mode_locked" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(state.rpcCalls.length, 0);
});

Deno.test("commit PRACTICE_MODE_LOCKED maps to HTTP 409 practice_mode_locked", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ practice_mode: "standard" }),
    rpc: {
      commit_practice_chat_turn: [{ error: "PRACTICE_MODE_LOCKED" }],
    },
  }, chatBody({ practiceMode: "beginner", temperatureScore: 30 }));

  assertEquals(response.status, 409);
  assertEquals(json, { error: "practice_mode_locked" });
  assertEquals(
    state.rpcCalls.some((call) => call.fn === "update_practice_temperature"),
    false,
  );
});

Deno.test("commit PRACTICE_INVALID_MODE maps to HTTP 400 invalid_practiceMode", async () => {
  const { response, json } = await run({
    rpc: {
      commit_practice_chat_turn: [{ error: "PRACTICE_INVALID_MODE" }],
    },
  });

  assertEquals(response.status, 400);
  assertEquals(json, { error: "invalid_practiceMode" });
});

Deno.test("ledger select includes beginner fields and old rows fallback safely", async () => {
  const { response, json, state } = await run({
    ledger: {
      ai_count: 1,
      charged: true,
      debrief_count: 0,
    },
    deepSeekReplies: ["AI reply", `{"delta":1,"reason":"slightly warmer"}`],
  }, chatBody({ practiceMode: "beginner", temperatureScore: 30 }));

  assertEquals(response.status, 200);
  assertEquals(json.hintUsedCount, 0);
  assertEquals(json.temperature.score, 31);
  const ledgerSelect = state.selects.find((select) =>
    select.table === "practice_chat_sessions"
  );
  assert(ledgerSelect);
  assertEquals(
    ledgerSelect.columns,
    "ai_count, charged, debrief_count, practice_mode, temperature_score, hint_count",
  );
});

Deno.test("temperature judge failure is non-fatal and keeps previous temperature", async () => {
  const { response, json, state } = await run({
    ledger: ledger({
      practice_mode: "beginner",
      temperature_score: 55,
      hint_count: 1,
    }),
    deepSeekReplies: ["AI reply", new Error("judge down")],
  }, chatBody({ practiceMode: "beginner", temperatureScore: 30 }));

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assertEquals(json.temperature.score, 55);
  assertEquals(json.temperature.delta, 0);
  assertEquals(json.hintUsedCount, 1);
  assertEquals(
    state.rpcCalls.some((call) => call.fn === "update_practice_temperature"),
    false,
  );
});

Deno.test("successful beginner judge uses JSON mode and updates temperature", async () => {
  const { response, json, state } = await run({
    ledger: ledger({
      practice_mode: "beginner",
      temperature_score: 30,
    }),
    deepSeekReplies: ["AI reply", `{"delta":8,"reason":"much warmer"}`],
  }, chatBody({ practiceMode: "beginner", temperatureScore: 30 }));

  assertEquals(response.status, 200);
  assertEquals(json.temperature, {
    score: 38,
    delta: 8,
    band: temperatureBandFor(38),
    reason: "much warmer",
  });
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[1].jsonMode, true);
  assert(state.deepSeekCalls[1].maxTokens <= 120);
  assert(state.deepSeekCalls[1].temperature <= 0.3);
  assertEquals(
    state.rpcCalls.find((call) => call.fn === "update_practice_temperature")
      ?.params,
    {
      p_user_id: "user-1",
      p_session_id: "session-1",
      p_temperature_score: 38,
    },
  );
});

Deno.test("hint standard practice mode rejects before DeepSeek and record RPC", async () => {
  const { response, json, state } = await run({
    ledger: ledger({
      ai_count: 1,
      charged: true,
      practice_mode: "standard",
      hint_count: 0,
    }),
  }, hintBody({ practiceMode: "standard" }));

  assertEquals(response.status, 403);
  assertEquals(json, { error: "practice_hint_beginner_only" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
  assertEquals(commitCalls(state).length, 0);
  assertEquals(temperatureUpdateCalls(state).length, 0);
});

Deno.test("hint before first AI reply returns session_not_started before provider and record RPC", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger({ ai_count: 0 }),
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 403);
  assertEquals(json, { error: "practice_session_not_started" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("hint over max successful hints returns limit before provider and record RPC", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger({ hint_count: MAX_HINTS_PER_ROUND }),
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 403);
  assertEquals(json, { error: "practice_hint_limit" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("hint quota exceeded returns 429 before provider and record RPC", async () => {
  const { response, json, state } = await run({
    sub: subscription({ monthly_messages_used: 300, daily_messages_used: 2 }),
    ledger: beginnerStartedLedger(),
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 429);
  assertEquals(json.error, "Monthly limit exceeded");
  assertEquals(json.quotaNeeded, 1);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("hint in-flight claim rejects before provider and record RPC", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger({ hint_count: 4 }),
    rpc: {
      claim_practice_hint_generation: [{ error: "PRACTICE_HINT_IN_FLIGHT" }],
    },
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 403);
  assertEquals(json, { error: "practice_hint_in_flight" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(recordHintCalls(state).length, 0);
  assertEquals(releaseHintCalls(state).length, 0);
});

Deno.test("hint DeepSeek failure releases claim and does not record hint", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger(),
    deepSeekReplies: [new Error("deepseek down")],
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 500);
  assertEquals(json, { error: "practice_generation_failed" });
  assertEquals(state.deepSeekCalls.length, 1);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 1);
  assertEquals(recordHintCalls(state).length, 0);
  assertEquals(commitCalls(state).length, 0);
});

Deno.test("hint malformed JSON releases claim and does not record hint", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger(),
    deepSeekReplies: ["not json"],
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 500);
  assertEquals(json, { error: "practice_generation_failed" });
  assertEquals(state.deepSeekCalls.length, 1);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 1);
  assertEquals(recordHintCalls(state).length, 0);
  assertEquals(commitCalls(state).length, 0);
});

Deno.test("successful hint uses ledger temperature, records after parse, and returns response contract", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger({
      temperature_score: 64,
      hint_count: 2,
    }),
    deepSeekReplies: [validHintJson()],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 3, did_charge: true }],
      }],
    },
  }, hintBody({ practiceMode: "beginner", temperatureScore: 5 }));

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  assertEquals(json.replies[0].type, "warm_up");
  assertEquals(json.replies[1].type, "steady");
  assertEquals(typeof json.coaching, "string");
  assertEquals(json.costDeducted, 1);
  assertEquals(json.hintUsedCount, 3);
  assertEquals(json.monthlyRemaining, 289);
  assertEquals(json.dailyRemaining, 47);
  assertEquals(json.provider, "deepseek");
  assertEquals(json.model, DEEPSEEK_MODEL);
  assertEquals(json.generatedAt, NOW.toISOString());

  assertEquals(state.deepSeekCalls.length, 1);
  const hintCall = state.deepSeekCalls[0];
  assertEquals(hintCall.jsonMode, true);
  assertEquals(hintCall.maxTokens, 450);
  assertEquals(hintCall.temperature, 0.45);
  const promptText = hintCall.messages.map((m) => m.content).join("\n");
  assert(promptText.includes("currentTemperatureScore: 64/100"));
  assertEquals(promptText.includes("currentTemperatureScore: 5/100"), false);
  assert(promptText.includes("assistant: hello"));

  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(claimHintCalls(state)[0].params, {
    p_user_id: "user-1",
    p_session_id: "session-1",
    p_max_hints: MAX_HINTS_PER_ROUND,
  });
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(recordHintCalls(state)[0].params, {
    p_user_id: "user-1",
    p_session_id: "session-1",
    p_charge_quota: true,
    p_max_hints: MAX_HINTS_PER_ROUND,
  });
  assertEquals(releaseHintCalls(state).length, 0);
  assertEquals(commitCalls(state).length, 0);
  assertEquals(temperatureUpdateCalls(state).length, 0);
  assertEquals(state.events, [
    "rpc:claim_practice_hint_generation",
    "deepseek",
    "rpc:record_practice_hint",
  ]);
});

Deno.test("successful hint falls back to temperature 30 when ledger has no score", async () => {
  const { response, state } = await run({
    ledger: beginnerStartedLedger({ temperature_score: null }),
    deepSeekReplies: [validHintJson()],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 1, did_charge: true }],
      }],
    },
  }, hintBody({ practiceMode: "beginner", temperatureScore: 88 }));

  assertEquals(response.status, 200);
  const promptText = state.deepSeekCalls[0].messages
    .map((message) => message.content)
    .join("\n");
  assert(promptText.includes("currentTemperatureScore: 30/100"));
  assertEquals(promptText.includes("currentTemperatureScore: 88/100"), false);
});

Deno.test("successful hint charges false for test accounts and trusts record did_charge for remaining counts", async () => {
  const { response, json, state } = await run({
    user: { id: "user-1", email: "vibesync.test@gmail.com" },
    ledger: beginnerStartedLedger(),
    deepSeekReplies: [validHintJson()],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 1, did_charge: false }],
      }],
    },
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 200);
  assertEquals(json.costDeducted, 0);
  assertEquals(json.monthlyRemaining, 290);
  assertEquals(json.dailyRemaining, 48);
  assertEquals(recordHintCalls(state)[0].params.p_charge_quota, false);
});

for (
  const [rpcError, expected] of [
    ["PRACTICE_HINT_LIMIT", "practice_hint_limit"],
    ["PRACTICE_HINT_BEGINNER_ONLY", "practice_hint_beginner_only"],
    ["PRACTICE_SESSION_NOT_STARTED", "practice_session_not_started"],
  ] as const
) {
  Deno.test(`record_practice_hint ${rpcError} maps to 403 ${expected}`, async () => {
    const { response, json, state } = await run({
      ledger: beginnerStartedLedger(),
      deepSeekReplies: [validHintJson()],
      rpc: {
        record_practice_hint: [{ error: rpcError }],
      },
    }, hintBody({ practiceMode: "beginner" }));

    assertEquals(response.status, 403);
    assertEquals(json, { error: expected });
    assertEquals(state.deepSeekCalls.length, 1);
    assertEquals(claimHintCalls(state).length, 1);
    assertEquals(recordHintCalls(state).length, 1);
    assertEquals(releaseHintCalls(state).length, 1);
    assertEquals(commitCalls(state).length, 0);
    assertEquals(temperatureUpdateCalls(state).length, 0);
  });
}

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
import type { DeepSeekArgs } from "./deepseek.ts";

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

Deno.test("hint mode is rejected before env, Supabase reads, DeepSeek, and RPC side effects", async () => {
  let fromCalled = false;
  let rpcCalled = false;
  const handler = createPracticeChatHandler({
    createSupabaseClient: () =>
      ({
        auth: {
          getUser: () =>
            Promise.resolve({
              data: { user: { id: "user-1", email: "user@example.com" } },
              error: null,
            }),
        },
        from: () => {
          fromCalled = true;
          throw new Error("hint should not read tables");
        },
        rpc: () => {
          rpcCalled = true;
          throw new Error("hint should not call RPC");
        },
      }) as unknown as PracticeSupabaseClient,
    callDeepSeek: (() => {
      throw new Error("hint should not call DeepSeek");
    }) as DeepSeekCaller,
    getEnv: () => {
      throw new Error("hint should not read env");
    },
    now: () => NOW,
  });

  const response = await handler(makeRequest(hintBody()));
  const json = await response.json();

  assertEquals(response.status, 403);
  assertEquals(json, { error: "practice_hint_not_available" });
  assertEquals(fromCalled, false);
  assertEquals(rpcCalled, false);
});

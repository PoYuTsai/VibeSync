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
import { MAX_AI_REPLIES, MAX_HINTS_PER_ROUND } from "./quota_decision.ts";

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
    familiarity_score: null,
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

function debriefBody(overrides: Record<string, unknown> = {}) {
  return {
    mode: "debrief",
    sessionId: "session-1",
    turns: [
      { role: "user", text: "hi" },
      { role: "ai", text: "hello" },
    ],
    ...overrides,
  };
}

function validDebriefJson(overrides: Record<string, unknown> = {}) {
  return JSON.stringify({
    summary: "有接住對方情緒",
    strengths: ["語氣輕鬆"],
    watchouts: ["可以少一點急著邀約"],
    suggestedLine: "那你今天最想把哪件事先放下？",
    vibe: "中性",
    dateChance: "medium",
    dateChanceReason: "互動有延續但還需要多一點安全感",
    nextInviteMove: "先接住她的下班狀態，再輕輕丟一個低壓邀約",
    ...overrides,
  });
}

function validHintJson(overrides: Record<string, string> = {}) {
  return JSON.stringify({
    warmUp: "我喜歡你剛剛那個反應，有點可愛。",
    steady: "哈哈那我先記下來，之後再慢慢觀察。",
    coaching: "先接住對方情緒，再用一點點曖昧推進。",
    ...overrides,
  });
}

function obviousChineseOverstepInvite(): string {
  return String.fromCodePoint(
    0x4eca,
    0x665a,
    0x8981,
    0x4e0d,
    0x8981,
    0x76f4,
    0x63a5,
    0x4f86,
    0x6211,
    0x5bb6,
    0x7761,
    0xff1f,
  );
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
      const defaultResult: RpcResult = (() => {
        if (fn === "commit_practice_chat_turn") {
          return { data: { new_ai_count: 1, did_charge: true } };
        }
        if (fn === "update_practice_learning_state") {
          return {
            data: {
              updated: true,
              temperature_score:
                (params.p_expected_temperature_score as number) +
                (params.p_temperature_delta as number),
              familiarity_score:
                (params.p_expected_familiarity_score as number) +
                (params.p_familiarity_delta as number),
            },
          };
        }
        return { data: true };
      })();
      const result = options.rpc?.[fn]?.[index] ?? defaultResult;
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

function learningUpdateCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "update_practice_learning_state"
  );
}

function assertLearningFieldsAndNoDebug(temperature: Record<string, unknown>) {
  assertEquals(typeof temperature.familiarityScore, "number");
  assertEquals(typeof temperature.familiarityDelta, "number");
  assertEquals("classification" in temperature, false);
  assertEquals("stage" in temperature, false);
}

function claimDebriefCalls(state: FakeState) {
  return state.rpcCalls.filter((call) => call.fn === "claim_practice_debrief");
}

Deno.test("standard chat response does not include temperature and does not judge or update", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ practice_mode: "standard" }),
  });

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assertEquals("temperature" in json, false);
  assertEquals(
    state.rpcCalls.some((call) => call.fn === "update_practice_learning_state"),
    false,
  );
  assertEquals(state.deepSeekCalls.length, 1);
  assertEquals(state.deepSeekCalls[0].jsonMode, undefined);
});

Deno.test("chat retries a transient provider failure once before committing", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ practice_mode: "standard" }),
    deepSeekReplies: [new Error("deepseek_timeout"), "AI retry reply"],
  });

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI retry reply");
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[0].jsonMode, undefined);
  assertEquals(state.deepSeekCalls[1].jsonMode, undefined);
  assertEquals(commitCalls(state).length, 1);
});

Deno.test("beginner first chat uses initial temp 30 and returns temperature plus hint count", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      deepSeekReplies: [
        "AI reply",
        `{"category":"event","quality":"ordinary","overstep":false}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      familiarityScore: 0,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assertEquals(json.hintUsedCount, 0);
  assertEquals(json.temperature, {
    score: 33,
    delta: 3,
    band: temperatureBandFor(33),
    reason: "事件導向有助於建立熟悉，先讓對話自然有來有回。",
    familiarityScore: 8,
    familiarityDelta: 8,
    stageLabel: "建立熟悉中",
  });
  assertLearningFieldsAndNoDebug(json.temperature);
  assert(
    state.deepSeekCalls[0].messages[0].content.includes("30/100"),
    "chat system prompt should include beginner initial temperature",
  );
  const classifierPrompt = state.deepSeekCalls[1].messages
    .map((message) => message.content)
    .join("\n");
  assert(classifierPrompt.includes("只分類最後一句 user 訊息"));
  assert(classifierPrompt.includes("事件 / 個人 / 曖昧"));
  assertEquals(classifierPrompt.includes("S__42795075.jpg"), false);
  assertEquals(
    learningUpdateCalls(state)[0]?.params,
    {
      p_user_id: "user-1",
      p_session_id: "session-1",
      p_expected_temperature_score: 30,
      p_expected_familiarity_score: 0,
      p_temperature_delta: 3,
      p_familiarity_delta: 8,
    },
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
  assertEquals(json.temperature.stageLabel, "建立熟悉中");
  assertLearningFieldsAndNoDebug(json.temperature);

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
  assertEquals(commit.params.p_familiarity_score, 0);
  assertEquals("p_initial_temperature_score" in commit.params, false);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 0);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 0);
});

Deno.test("beginner later chat uses ledger learning state over client sent scores", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        ai_count: 3,
        charged: true,
        practice_mode: "beginner",
        temperature_score: 64,
        familiarity_score: 45,
        hint_count: 2,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"personal","quality":"ordinary","overstep":false}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 10,
      familiarityScore: 99,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.hintUsedCount, 2);
  assertEquals(json.temperature.score, 69);
  assertEquals(json.temperature.delta, 5);
  assertEquals(json.temperature.stageLabel, "可以輕推曖昧");
  assertLearningFieldsAndNoDebug(json.temperature);
  const systemPrompt = state.deepSeekCalls[0].messages[0].content;
  assert(systemPrompt.includes("64/100"));
  assertEquals(systemPrompt.includes("10/100"), false);
  const classifierPrompt = state.deepSeekCalls[1].messages
    .map((message) => message.content)
    .join("\n");
  assert(classifierPrompt.includes("目前抽象關係階段：可以輕推曖昧"));
  assertEquals(classifierPrompt.includes("45/100"), false);
  assertEquals(classifierPrompt.includes("99/100"), false);
});

Deno.test("missing dual-axis readiness RPC returns not-ready before DeepSeek", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      rpc: {
        assert_practice_learning_ready: [{
          error:
            "Could not find the function public.assert_practice_learning_ready(p_session_id, p_user_id) in the schema cache",
        }],
      },
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      familiarityScore: 0,
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_learning_not_ready" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(commitCalls(state).length, 0);
  assertEquals(learningUpdateCalls(state).length, 0);
});

Deno.test("standard chat missing dual-axis readiness returns not-ready before DeepSeek", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({ practice_mode: "standard" }),
      rpc: {
        assert_practice_learning_ready: [{
          error: "PRACTICE_LEARNING_NOT_READY: missing dual-axis commit RPC",
        }],
      },
    },
    chatBody({
      practiceMode: "standard",
      temperatureScore: 30,
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_learning_not_ready" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(commitCalls(state).length, 0);
  assertEquals(learningUpdateCalls(state).length, 0);
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
  // standard 模式不再帶 client 溫度值（RPC 本就忽略，防誤導耦合）。
  assertEquals(commit.params.p_temperature_score, null);
  assertEquals(commit.params.p_familiarity_score, null);
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
    state.rpcCalls.some((call) => call.fn === "update_practice_learning_state"),
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
    deepSeekReplies: [
      "AI reply",
      `{"category":"event","quality":"ordinary","overstep":false}`,
    ],
  }, chatBody({ practiceMode: "beginner", temperatureScore: 30 }));

  assertEquals(response.status, 200);
  assertEquals(json.hintUsedCount, 0);
  assertEquals(json.temperature.score, 33);
  assertEquals(json.temperature.stageLabel, "建立熟悉中");
  assertLearningFieldsAndNoDebug(json.temperature);
  const ledgerSelect = state.selects.find((select) =>
    select.table === "practice_chat_sessions"
  );
  assert(ledgerSelect);
  assertEquals(
    ledgerSelect.columns,
    "ai_count, charged, debrief_count, practice_mode, temperature_score, familiarity_score, hint_count",
  );
});

Deno.test("turn classifier failure is non-fatal and keeps non-hint chat flat", async () => {
  const { response, json, state } = await run({
    ledger: ledger({
      practice_mode: "beginner",
      temperature_score: 55,
      familiarity_score: 42,
      hint_count: 1,
    }),
    deepSeekReplies: ["AI reply", new Error("classifier down")],
  }, chatBody({ practiceMode: "beginner", temperatureScore: 30 }));

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assertEquals(json.temperature.score, 55);
  assertEquals(json.temperature.delta, 0);
  assertEquals(json.temperature.stageLabel, "可以輕推曖昧");
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(json.hintUsedCount, 1);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 0);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 0);
});

Deno.test("turn classifier fallback retries stale guarded learning updates", async () => {
  const { response, json, state } = await run({
    ledger: ledger({
      practice_mode: "beginner",
      temperature_score: 55,
      familiarity_score: 42,
      hint_count: 1,
    }),
    rpc: {
      update_practice_learning_state: [
        {
          data: {
            updated: false,
            temperature_score: 58,
            familiarity_score: 50,
          },
        },
        {
          data: {
            updated: true,
            temperature_score: 58,
            familiarity_score: 50,
          },
        },
      ],
    },
    deepSeekReplies: ["AI reply", new Error("classifier down")],
  }, chatBody({ practiceMode: "beginner", temperatureScore: 30 }));

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 58);
  assertEquals(json.temperature.delta, 0);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state).length, 2);
  assertEquals(
    learningUpdateCalls(state)[0].params.p_expected_temperature_score,
    55,
  );
  assertEquals(
    learningUpdateCalls(state)[1].params.p_expected_temperature_score,
    58,
  );
  assertEquals(
    learningUpdateCalls(state)[1].params.p_expected_familiarity_score,
    50,
  );
});

Deno.test("exact applied hint stays non-negative when fallback retry sees stale state", async () => {
  const exactHint = "你剛剛說今天很累，是工作很多嗎？";
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 55,
        familiarity_score: 42,
        hint_count: 1,
      }),
      rpc: {
        update_practice_learning_state: [
          {
            data: {
              updated: false,
              temperature_score: 58,
              familiarity_score: 50,
            },
          },
        ],
      },
      deepSeekReplies: ["AI reply", new Error("classifier down")],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "warm_up",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 58);
  assertEquals(json.temperature.delta, 0);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state).length, 2);
  assertEquals(
    learningUpdateCalls(state)[1].params.p_expected_temperature_score,
    58,
  );
  assertEquals(learningUpdateCalls(state)[1].params.p_temperature_delta, 0);
});

Deno.test("successful beginner classifier uses JSON mode and updates learning state", async () => {
  const { response, json, state } = await run({
    ledger: ledger({
      practice_mode: "beginner",
      temperature_score: 30,
      familiarity_score: 0,
    }),
    deepSeekReplies: [
      "AI reply",
      `{"category":"personal","quality":"good","overstep":false}`,
    ],
  }, chatBody({ practiceMode: "beginner", temperatureScore: 30 }));

  assertEquals(response.status, 200);
  assertEquals(json.temperature, {
    score: 29,
    delta: -1,
    band: temperatureBandFor(29),
    reason: "個人分享接得住對方，熟悉度上升，熱度也比較穩。",
    familiarityScore: 5,
    familiarityDelta: 5,
    stageLabel: "建立熟悉中",
  });
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[1].jsonMode, true);
  assertEquals(state.deepSeekCalls[1].maxTokens, 450);
  assert(state.deepSeekCalls[1].temperature <= 0.3);
  assertEquals(
    learningUpdateCalls(state)[0]?.params,
    {
      p_user_id: "user-1",
      p_session_id: "session-1",
      p_expected_temperature_score: 30,
      p_expected_familiarity_score: 0,
      p_temperature_delta: -1,
      p_familiarity_delta: 5,
    },
  );
});

Deno.test("exact applied warm-up hint stays flat despite classifier overstep", async () => {
  const exactHint = "You said you were tired. Was work heavy today?";
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"flirt","quality":"bad","impact":"strong","overstep":true,"hintAlignment":"none"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "warm_up",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature, {
    score: 30,
    delta: 0,
    band: temperatureBandFor(30),
    reason: "套用提示回覆，維持不降溫",
    familiarityScore: 20,
    familiarityDelta: 0,
    stageLabel: "建立熟悉中",
  });
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 0);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 0);
});

Deno.test("exact applied hint stays flat when classifier falls back", async () => {
  const exactHint = "你剛剛說今天很累，是工作很多嗎？";
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"flirt","quality":"bad","overstep":true}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "warm_up",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 30);
  assertEquals(json.temperature.delta, 0);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 0);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 0);
});

Deno.test("exact applied steady hint shows a small bump when classifier falls back", async () => {
  const exactHint = "聽起來真的很滿，我懂那種一整天被工作追著跑的感覺。";
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"flirt","quality":"bad","overstep":true}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 31);
  assertEquals(json.temperature.delta, 1);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 1);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 1);
});

Deno.test("exact applied warm-up hint does not drop protected beginner temperature", async () => {
  const exactHint =
    "That sounds like a packed day. What part drained you most?";
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"personal","quality":"ordinary","impact":"medium","overstep":true,"hintAlignment":"none"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "warm_up",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature, {
    score: 30,
    delta: 0,
    band: temperatureBandFor(30),
    reason: "套用提示回覆，維持不降溫",
    familiarityScore: 20,
    familiarityDelta: 0,
    stageLabel: "建立熟悉中",
  });
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 0);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 0);
});

Deno.test("exact applied steady hint gets visible credit despite classifier overstep", async () => {
  const exactHint =
    "That sounds like a packed day. What part drained you most?";
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"personal","quality":"ordinary","impact":"medium","overstep":true,"hintAlignment":"none"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 31);
  assertEquals(json.temperature.delta, 1);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 1);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 1);
});

Deno.test("exact applied hint with obvious overstep is not protected", async () => {
  const exactHint = obviousChineseOverstepInvite();
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"event","quality":"ordinary","impact":"minor","overstep":false,"hintAlignment":"none"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 18);
  assertEquals(json.temperature.delta, -12);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, -12);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -8);
});

Deno.test("exact applied steady hint shows a small heat bump when familiarity grows", async () => {
  const exactHint =
    "That sounds like a packed day. What part drained you most?";
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"personal","quality":"ordinary","impact":"medium","overstep":false,"hintAlignment":"none"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 31);
  assertEquals(json.temperature.delta, 1);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 1);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 4);
});

Deno.test("edited applied steady hint aligned with the original gets visible credit", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"personal","quality":"ordinary","impact":"minor","overstep":false,"hintAlignment":"aligned"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: "你剛剛說今天很累，是工作很多嗎？",
      turns: [{ role: "user", text: "你今天很累，是工作很多嗎" }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 31);
  assertEquals(json.temperature.delta, 1);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 1);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 1);
});

Deno.test("english edited applied steady hint with small wording changes gets visible credit", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"personal","quality":"ordinary","impact":"minor","overstep":false,"hintAlignment":"aligned"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: "You said today felt heavy. Was work the hardest part?",
      turns: [{
        role: "user",
        text: "You said today felt heavy - was work the hardest part?",
      }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 31);
  assertEquals(json.temperature.delta, 1);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 1);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 1);
});

Deno.test("edited applied hint with low text similarity is scored normally even when classifier says aligned", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"personal","quality":"ordinary","impact":"minor","overstep":false,"hintAlignment":"aligned"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: "You said you were tired. Was work heavy today?",
      turns: [{ role: "user", text: "I want to change the topic." }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 29);
  assertEquals(json.temperature.delta, -1);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, -1);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 0);
});

Deno.test("edited applied hint with obvious overstep is penalized even when classifier says aligned", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"event","quality":"ordinary","impact":"minor","overstep":false,"hintAlignment":"aligned"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: "You said you were tired. Was work heavy today?",
      turns: [{ role: "user", text: obviousChineseOverstepInvite() }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 18);
  assertEquals(json.temperature.delta, -12);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, -12);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -8);
});

Deno.test("edited applied hint with obvious overstep is penalized when classifier returns old shape", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"event","quality":"ordinary","overstep":false}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: "You said you were tired. Was work heavy today?",
      turns: [{ role: "user", text: obviousChineseOverstepInvite() }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 18);
  assertEquals(json.temperature.delta, -12);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, -12);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -8);
});

Deno.test("edited applied hint marked aligned but overstepping is not protected", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"flirt","quality":"bad","impact":"strong","overstep":true,"hintAlignment":"aligned"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: "You said you were tired. Was work heavy today?",
      turns: [{ role: "user", text: "Come over tonight and sleep here." }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 18);
  assertEquals(json.temperature.delta, -12);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, -12);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -8);
});

Deno.test("edited applied hint with old classifier shape falls back instead of scoring as diverged", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"flirt","quality":"bad","overstep":true}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: "original hint reply",
      turns: [{ role: "user", text: "edited hint reply" }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 30);
  assertEquals(json.temperature.delta, 0);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 0);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 0);
});

Deno.test("edited applied hint that diverges is scored like a normal reply", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"flirt","quality":"bad","impact":"strong","overstep":true,"hintAlignment":"diverged"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: "你剛剛說今天很累，是工作很多嗎？",
      turns: [{ role: "user", text: "那你是不是想我陪你睡" }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 18);
  assertEquals(json.temperature.delta, -12);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, -12);
});

Deno.test("normal low-impact beginner chat can keep the visible temperature flat", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"event","quality":"ordinary","impact":"minor","overstep":false,"hintAlignment":"none"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      turns: [{ role: "user", text: "今天工作很多嗎" }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 30);
  assertEquals(json.temperature.delta, 0);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 0);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 0);
});

Deno.test("low-information reply after a contextual question can cool both learning axes", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 10,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"event","quality":"bad","impact":"minor","overstep":false,"hintAlignment":"none"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      turns: [
        { role: "user", text: "I am tired today." },
        { role: "ai", text: "You said you were tired. Was work heavy today?" },
        { role: "user", text: "hi" },
      ],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 29);
  assertEquals(json.temperature.delta, -1);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, -1);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -1);
  const classifierPrompt = state.deepSeekCalls[1].messages
    .map((message) => message.content)
    .join("\n");
  assert(classifierPrompt.includes("recentContext"));
  assert(classifierPrompt.includes("You said you were tired"));
  assert(classifierPrompt.includes("latestUserText"));
  assert(classifierPrompt.includes("hi"));
});

Deno.test("appliedHintType without original hint text does not receive exact hint protection", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"flirt","quality":"bad","impact":"strong","overstep":true,"hintAlignment":"none"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "warm_up",
      turns: [{
        role: "user",
        text: "I ignored the hint and pushed too hard.",
      }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 18);
  assertEquals(json.temperature.delta, -12);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, -12);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -8);
});

Deno.test("appliedHintType without original hint text cannot receive aligned hint protection", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"flirt","quality":"bad","impact":"strong","overstep":true,"hintAlignment":"aligned"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "warm_up",
      turns: [{ role: "user", text: "I rewrote it into a pushy flirt." }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 18);
  assertEquals(json.temperature.delta, -12);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, -12);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -8);
});

Deno.test("exact applied hint keeps positive temperature judgement", async () => {
  const exactHint = "You said you were tired. Was work heavy today?";
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 10,
        hint_count: 1,
      }),
      deepSeekReplies: [
        "AI reply",
        `{"category":"event","quality":"good","impact":"medium","overstep":false,"hintAlignment":"none"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      appliedHintType: "warm_up",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature, {
    score: 34,
    delta: 4,
    band: temperatureBandFor(34),
    reason: "事件導向有助於建立熟悉，先讓對話自然有來有回。",
    familiarityScore: 20,
    familiarityDelta: 10,
    stageLabel: "建立熟悉中",
  });
  assertEquals("classification" in json.temperature, false);
  assertEquals("stage" in json.temperature, false);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 4);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 10);
});

Deno.test("stale guarded learning update reloads ledger and retries deterministic delta", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 0,
      }),
      rpc: {
        update_practice_learning_state: [
          {
            data: {
              updated: false,
              temperature_score: 40,
              familiarity_score: 40,
            },
          },
          {
            data: {
              updated: true,
              temperature_score: 44,
              familiarity_score: 50,
            },
          },
        ],
      },
      deepSeekReplies: [
        "AI reply",
        `{"category":"event","quality":"good","overstep":false}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      familiarityScore: 0,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 44);
  assertEquals(json.temperature.stageLabel, "可以聊個人");
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state).length, 2);
  assertEquals(
    learningUpdateCalls(state)[0].params.p_expected_temperature_score,
    30,
  );
  assertEquals(
    learningUpdateCalls(state)[0].params.p_expected_familiarity_score,
    0,
  );
  assertEquals(
    learningUpdateCalls(state)[1].params.p_expected_temperature_score,
    40,
  );
  assertEquals(
    learningUpdateCalls(state)[1].params.p_expected_familiarity_score,
    40,
  );
});

Deno.test("stale retry recalculates obvious overstep while still below flirt-ready stage", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 0,
        hint_count: 1,
      }),
      rpc: {
        update_practice_learning_state: [
          {
            data: {
              updated: false,
              temperature_score: 34,
              familiarity_score: 20,
            },
          },
        ],
      },
      deepSeekReplies: [
        "AI reply",
        `{"category":"event","quality":"ordinary","impact":"minor","overstep":false,"hintAlignment":"aligned"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      familiarityScore: 0,
      appliedHintType: "steady",
      appliedHintText: "You said you were tired. Was work heavy today?",
      turns: [{ role: "user", text: obviousChineseOverstepInvite() }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 22);
  assertEquals(json.temperature.delta, -12);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state).length, 2);
  assertEquals(learningUpdateCalls(state)[1].params.p_temperature_delta, -12);
  assertEquals(learningUpdateCalls(state)[1].params.p_familiarity_delta, -8);
});

Deno.test("stale retry does not reuse low-stage overstep override after flirt-ready reload", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 0,
        hint_count: 1,
      }),
      rpc: {
        update_practice_learning_state: [
          {
            data: {
              updated: false,
              temperature_score: 60,
              familiarity_score: 60,
            },
          },
        ],
      },
      deepSeekReplies: [
        "AI reply",
        `{"category":"event","quality":"ordinary","impact":"minor","overstep":false,"hintAlignment":"aligned"}`,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      familiarityScore: 0,
      appliedHintType: "steady",
      appliedHintText: "You said you were tired. Was work heavy today?",
      turns: [{ role: "user", text: obviousChineseOverstepInvite() }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 60);
  assertEquals(json.temperature.delta, 0);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state).length, 2);
  assertEquals(learningUpdateCalls(state)[1].params.p_temperature_delta, 0);
  assertEquals(learningUpdateCalls(state)[1].params.p_familiarity_delta, 0);
});

Deno.test("debrief retries a malformed provider card once before returning the card", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ ai_count: 1, charged: true }),
    deepSeekReplies: ["not json", validDebriefJson()],
  }, debriefBody());

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "有接住對方情緒");
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[0].jsonMode, true);
  assertEquals(state.deepSeekCalls[1].jsonMode, true);
  assertEquals(state.deepSeekCalls[0].maxTokens, 800);
  assertEquals(state.deepSeekCalls[1].maxTokens, 800);
  assertEquals(claimDebriefCalls(state).length, 1);
});

Deno.test("debrief returns generation_failed after exhausting malformed card retries", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ ai_count: 1, charged: true }),
    deepSeekReplies: ["not json", "["],
  }, debriefBody());

  assertEquals(response.status, 500);
  assertEquals(json, { error: "practice_generation_failed" });
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[0].jsonMode, true);
  assertEquals(state.deepSeekCalls[1].jsonMode, true);
  assertEquals(claimDebriefCalls(state).length, 1);
});

Deno.test("debrief accepts beginner ledger when client omits practiceMode", async () => {
  const { response, json, state } = await run({
    ledger: ledger({
      ai_count: 1,
      charged: true,
      practice_mode: "beginner",
    }),
    deepSeekReplies: [validDebriefJson({ summary: "新手拆解成功" })],
  }, debriefBody());

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "新手拆解成功");
  assertEquals(state.deepSeekCalls.length, 1);
  const debriefPrompt = state.deepSeekCalls[0].messages
    .map((message) => message.content)
    .join("\n");
  assert(debriefPrompt.includes("本場抽象關係階段：建立熟悉中"));
  assertEquals(debriefPrompt.includes("familiarity"), false);
  assertEquals(claimDebriefCalls(state).length, 1);
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
  assertEquals(learningUpdateCalls(state).length, 0);
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

Deno.test("hint missing beginner ledger columns returns not-ready before provider", async () => {
  const { response, json, state } = await run({
    ledgerError:
      "Could not find the 'hint_count' column of 'practice_chat_sessions' in the schema cache",
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_hint_not_ready" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("chat missing dual-axis ledger column returns not-ready before provider", async () => {
  const { response, json, state } = await run({
    ledgerError:
      "Could not find the 'familiarity_score' column of 'practice_chat_sessions' in the schema cache",
  }, chatBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_learning_not_ready" });
  assertEquals(state.deepSeekCalls.length, 0);
});

Deno.test("debrief missing dual-axis ledger column returns not-ready before provider", async () => {
  const { response, json, state } = await run({
    ledgerError:
      "Could not find the 'familiarity_score' column of 'practice_chat_sessions' in the schema cache",
  }, debriefBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_learning_not_ready" });
  assertEquals(state.deepSeekCalls.length, 0);
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

Deno.test("hint missing claim RPC returns not-ready before provider", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger(),
    rpc: {
      claim_practice_hint_generation: [{
        error:
          "Could not find the function public.claim_practice_hint_generation(p_max_hints, p_session_id, p_user_id) in the schema cache",
      }],
    },
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_hint_not_ready" });
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
  assertEquals(state.deepSeekCalls.length, 2);
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
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 1);
  assertEquals(recordHintCalls(state).length, 0);
  assertEquals(commitCalls(state).length, 0);
});

Deno.test("hint retries a malformed provider result once before recording", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger(),
    deepSeekReplies: ["not json", validHintJson()],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 1, did_charge: true }],
      }],
    },
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[0].jsonMode, true);
  assertEquals(state.deepSeekCalls[1].jsonMode, true);
  assertEquals(state.deepSeekCalls[0].maxTokens, 650);
  assertEquals(state.deepSeekCalls[1].maxTokens, 650);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 0);
  assertEquals(state.events, [
    "rpc:increment_model_usage",
    "rpc:claim_practice_hint_generation",
    "deepseek",
    "deepseek",
    "rpc:record_practice_hint",
  ]);
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
  assertEquals(hintCall.maxTokens, 650);
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
  assertEquals(learningUpdateCalls(state).length, 0);
  assertEquals(state.events, [
    "rpc:increment_model_usage",
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

// ── hint requestId 冪等 + 聊滿 gate ─────────────────────────────────────

function storedHintResult(overrides: Record<string, unknown> = {}) {
  return {
    replies: [
      { type: "warm_up", text: "先前那句 warm up" },
      { type: "steady", text: "先前那句 steady" },
    ],
    coaching: "先前的 coaching",
    costDeducted: 1,
    hintUsedCount: 2,
    provider: "deepseek",
    model: DEEPSEEK_MODEL,
    generatedAt: NOW.toISOString(),
    monthlyRemaining: 289,
    dailyRemaining: 47,
    ...overrides,
  };
}

Deno.test("hint on a completed session returns 409 practice_session_complete before provider and claim", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger({ ai_count: MAX_AI_REPLIES }),
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 409);
  assertEquals(json, { error: "practice_session_complete" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("hint requestId matching stored ledger snapshot replays without provider, claim, or record", async () => {
  const stored = storedHintResult();
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger({
      last_hint_request_id: "req-1",
      last_hint_result: stored,
    }),
  }, hintBody({ practiceMode: "beginner", requestId: "req-1" }));

  assertEquals(response.status, 200);
  assertEquals(json, stored);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
  assertEquals(releaseHintCalls(state).length, 0);
});

Deno.test("hint requestId replay wins at the hint cap and session cap edge", async () => {
  const stored = storedHintResult({ hintUsedCount: MAX_HINTS_PER_ROUND });
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger({
      ai_count: MAX_AI_REPLIES,
      hint_count: MAX_HINTS_PER_ROUND,
      last_hint_request_id: "req-edge",
      last_hint_result: stored,
    }),
  }, hintBody({ practiceMode: "beginner", requestId: "req-edge" }));

  assertEquals(response.status, 200);
  assertEquals(json, stored);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("hint requestId replay bypasses the quota 429 gate because nothing new is charged", async () => {
  const stored = storedHintResult();
  const { response, json, state } = await run({
    sub: subscription({ monthly_messages_used: 300, daily_messages_used: 2 }),
    ledger: beginnerStartedLedger({
      last_hint_request_id: "req-quota",
      last_hint_result: stored,
    }),
  }, hintBody({ practiceMode: "beginner", requestId: "req-quota" }));

  assertEquals(response.status, 200);
  assertEquals(json, stored);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("hint with a fresh requestId generates normally and threads the id into claim and record", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger({
      last_hint_request_id: "req-old",
      last_hint_result: storedHintResult(),
    }),
    deepSeekReplies: [validHintJson()],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 1, did_charge: true }],
      }],
    },
  }, hintBody({ practiceMode: "beginner", requestId: "req-new" }));

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  assertEquals(json.hintUsedCount, 1);
  assertEquals(state.deepSeekCalls.length, 1);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(claimHintCalls(state)[0].params, {
    p_user_id: "user-1",
    p_session_id: "session-1",
    p_max_hints: MAX_HINTS_PER_ROUND,
    p_request_id: "req-new",
  });
  assertEquals(recordHintCalls(state).length, 1);
  const recordParams = recordHintCalls(state)[0].params;
  assertEquals(recordParams.p_request_id, "req-new");
  const storedPayload = recordParams.p_result as Record<string, unknown>;
  assertEquals(Array.isArray(storedPayload.replies), true);
  assertEquals(typeof storedPayload.coaching, "string");
  assertEquals(storedPayload.costDeducted, 1);
  assertEquals(storedPayload.provider, "deepseek");
  assertEquals(storedPayload.model, DEEPSEEK_MODEL);
  assertEquals(typeof storedPayload.generatedAt, "string");
  assertEquals(typeof storedPayload.monthlyRemaining, "number");
  assertEquals(typeof storedPayload.dailyRemaining, "number");
  // hintUsedCount 由 RPC 在鎖內以權威 new_hint_count merge，client 端不預填。
  assertEquals("hintUsedCount" in storedPayload, false);
});

Deno.test("hint claim-level replay returns the stored result without provider or record", async () => {
  const stored = storedHintResult({ hintUsedCount: 3 });
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger(),
    rpc: {
      claim_practice_hint_generation: [{
        data: [{ current_hint_count: 3, replay: true, stored_result: stored }],
      }],
    },
  }, hintBody({ practiceMode: "beginner", requestId: "req-race" }));

  assertEquals(response.status, 200);
  assertEquals(json, stored);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(recordHintCalls(state).length, 0);
  assertEquals(releaseHintCalls(state).length, 0);
});

Deno.test("hint without requestId keeps legacy claim and record params and stores no result", async () => {
  const { response, state } = await run({
    ledger: beginnerStartedLedger(),
    deepSeekReplies: [validHintJson()],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 1, did_charge: true }],
      }],
    },
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 200);
  assertEquals(claimHintCalls(state)[0].params, {
    p_user_id: "user-1",
    p_session_id: "session-1",
    p_max_hints: MAX_HINTS_PER_ROUND,
  });
  assertEquals(recordHintCalls(state)[0].params, {
    p_user_id: "user-1",
    p_session_id: "session-1",
    p_charge_quota: true,
    p_max_hints: MAX_HINTS_PER_ROUND,
  });
});

Deno.test("standard chat commit passes null temperature instead of the client value", async () => {
  const { response, state } = await run({
    ledger: ledger({ practice_mode: "standard" }),
  }, chatBody({ temperatureScore: 77 }));

  assertEquals(response.status, 200);
  assertEquals(commitCalls(state).length, 1);
  assertEquals(commitCalls(state)[0].params.p_temperature_score, null);
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
    assertEquals(learningUpdateCalls(state).length, 0);
  });
}

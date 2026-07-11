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
  preparedSub?: Record<string, unknown> | null;
  subError?: string;
  ledger?: Record<string, unknown> | null;
  ledgerError?: string;
  hintRequest?: Record<string, unknown> | null;
  hintRequestError?: string;
  thread?: Record<string, unknown> | null;
  threadError?: string;
  drawEvents?: ReadonlyArray<Record<string, unknown>>;
  drawEventsError?: string;
  aiLogsError?: string;
  aiLogsNeverCompletes?: boolean;
  rpc?: Record<string, RpcResult[]>;
  deepSeekReplies?: ReadonlyArray<string | Error>;
  env?: Record<string, string | undefined>;
  randomUUID?: string;
}

interface FakeState {
  selects: Array<{ table: string; columns: string }>;
  inserts: Array<{ table: string; values: Record<string, unknown> }>;
  updates: Array<{ table: string; values: Record<string, unknown> }>;
  rpcCalls: Array<{ fn: string; params: Record<string, unknown> }>;
  deepSeekCalls: DeepSeekArgs[];
  events: string[];
  backgroundTasks: Promise<void>[];
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

function gameStartedLedger(overrides: Record<string, unknown> = {}) {
  return ledger({
    ai_count: 1,
    charged: true,
    practice_mode: "game",
    temperature_score: 30,
    familiarity_score: 0,
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

const CLASSIFIER_CAUGHT_MEDIUM =
  `{"connection":"caught","impact":"medium","testHandling":"none","boundary":"safe","hintAlignment":"none"}`;
const CLASSIFIER_CAUGHT_MINOR =
  `{"connection":"caught","impact":"minor","testHandling":"none","boundary":"safe","hintAlignment":"none"}`;
const CLASSIFIER_NEUTRAL_MINOR =
  `{"connection":"neutral","impact":"minor","testHandling":"none","boundary":"safe","hintAlignment":"none"}`;
const CLASSIFIER_MISSED_MINOR =
  `{"connection":"missed","impact":"minor","testHandling":"none","boundary":"safe","hintAlignment":"none"}`;
const CLASSIFIER_DEFENSIVE_FAILED =
  `{"connection":"defensive","impact":"medium","testHandling":"failed","boundary":"safe","hintAlignment":"none"}`;
const CLASSIFIER_OVERSTEP =
  `{"connection":"overstepped","impact":"strong","testHandling":"none","boundary":"overstep","hintAlignment":"none"}`;
const CLASSIFIER_OVERSTEP_ALIGNED =
  `{"connection":"overstepped","impact":"strong","testHandling":"none","boundary":"overstep","hintAlignment":"aligned"}`;
const CLASSIFIER_OVERSTEP_DIVERGED =
  `{"connection":"overstepped","impact":"strong","testHandling":"none","boundary":"overstep","hintAlignment":"diverged"}`;
const CLASSIFIER_ALIGNED_NEUTRAL_MINOR =
  `{"connection":"neutral","impact":"minor","testHandling":"none","boundary":"safe","hintAlignment":"aligned"}`;
const NEUTRAL_PARTNER_STATE = {
  mood: "neutral",
  innerThought: "",
};
const GUARDED_PARTNER_STATE = {
  mood: "guarded",
  innerThought: "",
};

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
    inserts: [],
    updates: [],
    rpcCalls: [],
    deepSeekCalls: [],
    events: [],
    backgroundTasks: [],
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
        insert(values: Record<string, unknown>) {
          state.inserts.push({ table, values });
          state.events.push(`insert:${table}`);
          if (table === "ai_logs" && options.aiLogsNeverCompletes) {
            return new Promise(() => {});
          }
          return Promise.resolve({
            data: null,
            error: table === "ai_logs" && options.aiLogsError
              ? { message: options.aiLogsError }
              : null,
          });
        },
        select(columns: string) {
          state.selects.push({ table, columns });
          function selectResult() {
            if (table === "practice_profile_draw_events") {
              return Promise.resolve(
                options.drawEventsError
                  ? {
                    data: null,
                    error: { message: options.drawEventsError },
                  }
                  : { data: options.drawEvents ?? [], error: null },
              );
            }
            return Promise.resolve({ data: null, error: null });
          }
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
              if (table === "practice_hint_requests") {
                return Promise.resolve(
                  options.hintRequestError
                    ? {
                      data: null,
                      error: { message: options.hintRequestError },
                    }
                    : {
                      data: options.hintRequest === undefined
                        ? null
                        : options.hintRequest,
                      error: null,
                    },
                );
              }
              if (table === "practice_relationship_threads") {
                return Promise.resolve(
                  options.threadError
                    ? { data: null, error: { message: options.threadError } }
                    : {
                      data: options.thread === undefined
                        ? null
                        : options.thread,
                      error: null,
                    },
                );
              }
              return selectResult();
            },
            then(
              onfulfilled?: (value: unknown) => unknown,
              onrejected?: (reason: unknown) => unknown,
            ) {
              return selectResult().then(onfulfilled, onrejected);
            },
          };
          return builder;
        },
        update(values: Record<string, unknown>) {
          state.updates.push({ table, values });
          state.events.push(`update:${table}`);
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
        if (fn === "prepare_practice_subscription_usage") {
          if (options.subError) return { error: options.subError };
          if (options.preparedSub === null || options.sub === null) {
            return { error: "PRACTICE_SUBSCRIPTION_NOT_FOUND" };
          }
          return {
            data: options.preparedSub ?? options.sub ?? subscription(),
          };
        }
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
              partner_mood: params.p_partner_mood ?? "neutral",
              partner_inner_thought: params.p_partner_inner_thought ?? "",
            },
          };
        }
        if (fn === "record_practice_debrief") {
          return { data: params.p_result };
        }
        if (fn === "claim_practice_hint_generation") {
          return {
            data: {
              current_hint_count: options.ledger?.hint_count ?? 0,
              replay: false,
              stored_result: null,
              stored_charged: null,
            },
          };
        }
        if (fn === "record_practice_hint") {
          const isConsumed = params.p_charged !== false;
          const currentHintCount =
            typeof options.ledger?.hint_count === "number"
              ? options.ledger.hint_count
              : 0;
          const newHintCount = currentHintCount + (isConsumed ? 1 : 0);
          const storedResult = params.p_request_id && params.p_result
            ? {
              ...(params.p_result as Record<string, unknown>),
              hintUsedCount: newHintCount,
            }
            : null;
          return {
            data: {
              new_hint_count: newHintCount,
              did_charge: params.p_charge_quota === true,
              stored_result: storedResult,
              stored_charged: isConsumed,
            },
          };
        }
        if (fn === "settle_prefetched_practice_hint") {
          const currentHintCount =
            typeof options.ledger?.hint_count === "number"
              ? options.ledger.hint_count
              : 0;
          const didCharge = params.p_charge_quota === true;
          return {
            data: {
              new_hint_count: currentHintCount + 1,
              did_charge: didCharge,
              stored_result: {
                ...(options.hintRequest?.result as Record<string, unknown>),
                costDeducted: didCharge ? 1 : 0,
                hintUsedCount: currentHintCount + 1,
              },
              stored_charged: true,
            },
          };
        }
        if (fn === "discard_prefetched_practice_hint") {
          return {
            data: {
              discarded: true,
              replay: false,
              stored_result: null,
              stored_charged: false,
            },
          };
        }
        if (fn === "release_practice_hint_generation") {
          return { data: { released: true } };
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
      getEnv: (name) => {
        if (Object.hasOwn(options.env ?? {}, name)) return options.env?.[name];
        return name === "DEEPSEEK_API_KEY" ? "deepseek-key" : "";
      },
      now: () => NOW,
      randomUUID: () => options.randomUUID ?? "generation-token-1",
      waitUntil: (task) => state.backgroundTasks.push(task),
      telemetryPersistTimeoutMs: options.aiLogsNeverCompletes ? 5 : undefined,
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

function settleHintCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "settle_prefetched_practice_hint"
  );
}

function discardHintCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "discard_prefetched_practice_hint"
  );
}

function hintModelRateCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "increment_model_usage" &&
    call.params.p_scope === "practice_hint"
  );
}

function commitCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "commit_practice_chat_turn"
  );
}

function learningUpdateCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "update_practice_learning_state"
  );
}

function gameStateUpdateCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "update_practice_game_state"
  );
}

function relationshipThreadUpsertCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "upsert_practice_relationship_thread"
  );
}

function assertLearningFieldsAndNoDebug(temperature: Record<string, unknown>) {
  assertEquals(typeof temperature.familiarityScore, "number");
  assertEquals(typeof temperature.familiarityDelta, "number");
  assert("partnerState" in temperature);
  assertEquals("classification" in temperature, false);
  assertEquals("stage" in temperature, false);
}

function claimDebriefCalls(state: FakeState) {
  return state.rpcCalls.filter((call) => call.fn === "claim_practice_debrief");
}

function recordDebriefCalls(state: FakeState) {
  return state.rpcCalls.filter((call) => call.fn === "record_practice_debrief");
}

function aiLogInserts(state: FakeState) {
  return state.inserts.filter((insert) => insert.table === "ai_logs");
}

Deno.test("practice-chat prepares subscription resets through the DB row lock", async () => {
  const { response, state } = await run({
    sub: subscription({
      monthly_messages_used: 99,
      daily_messages_used: 49,
      monthly_reset_at: "2026-05-01T00:00:00.000Z",
      daily_reset_at: "2026-06-27T00:00:00.000Z",
    }),
    preparedSub: subscription({
      monthly_messages_used: 0,
      daily_messages_used: 0,
      monthly_reset_at: "2026-06-01T00:00:00.000Z",
      daily_reset_at: "2026-06-28T00:00:00.000Z",
    }),
    ledger: ledger({ practice_mode: "standard" }),
  });

  assertEquals(response.status, 200);
  const prepareCalls = state.rpcCalls.filter((call) =>
    call.fn === "prepare_practice_subscription_usage"
  );
  assertEquals(prepareCalls.length, 1);
  assertEquals(prepareCalls[0].params, { p_user_id: "user-1" });
  assertEquals(
    state.selects.some((select) => select.table === "subscriptions"),
    false,
  );
  assertEquals(
    state.updates.some((update) => update.table === "subscriptions"),
    false,
  );
  assert(
    state.events.indexOf("rpc:prepare_practice_subscription_usage") <
      state.events.indexOf("deepseek"),
  );
});

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

Deno.test("free continuation spoof with roundIndex 1 is upgrade-gated before provider", async () => {
  const { response, json, state } = await run(
    {
      sub: subscription({ tier: "free" }),
      ledger: null,
    },
    chatBody({
      sessionId: "session-2",
      roundIndex: 1,
      visiblePracticeThreadId: "thread-1",
      turns: [
        { role: "user", text: "hi" },
        { role: "ai", text: "hello" },
        { role: "user", text: "續聊一下" },
      ],
    }),
  );

  assertEquals(response.status, 402);
  assertEquals(json, { error: "upgrade_required" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(commitCalls(state).length, 0);
});

Deno.test("free continuation spoof with memorySummary is upgrade-gated before provider", async () => {
  const { response, json, state } = await run(
    {
      sub: subscription({ tier: "free" }),
      ledger: null,
    },
    chatBody({
      sessionId: "session-2",
      roundIndex: 1,
      visiblePracticeThreadId: "session-2",
      memorySummary: "OLDER_MEMORY_MARKER: she remembered coffee",
      turns: [{ role: "user", text: "hi again" }],
    }),
  );

  assertEquals(response.status, 402);
  assertEquals(json, { error: "upgrade_required" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(commitCalls(state).length, 0);
});

Deno.test("free existing ledger carrying memorySummary is upgrade-gated before provider", async () => {
  const { response, json, state } = await run(
    {
      sub: subscription({ tier: "free" }),
      ledger: ledger({ ai_count: 1, charged: true }),
    },
    chatBody({
      sessionId: "session-1",
      roundIndex: 1,
      visiblePracticeThreadId: "session-1",
      memorySummary: "OLDER_MEMORY_MARKER: she remembered coffee",
      turns: [
        { role: "user", text: "hi" },
        { role: "ai", text: "hello" },
        { role: "user", text: "hi again" },
      ],
    }),
  );

  assertEquals(response.status, 402);
  assertEquals(json, { error: "upgrade_required" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(commitCalls(state).length, 0);
});

Deno.test("free request with more AI history than ledger is upgrade-gated before provider", async () => {
  const { response, json, state } = await run(
    {
      sub: subscription({ tier: "free" }),
      ledger: ledger({ ai_count: 0, charged: true }),
    },
    chatBody({
      sessionId: "session-1",
      roundIndex: 1,
      visiblePracticeThreadId: "session-1",
      turns: [
        { role: "user", text: "hi" },
        { role: "ai", text: "hello" },
        { role: "user", text: "hi again" },
      ],
    }),
  );

  assertEquals(response.status, 402);
  assertEquals(json, { error: "upgrade_required" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(commitCalls(state).length, 0);
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

Deno.test("chat retries a visible internal label leak before committing", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ practice_mode: "standard" }),
    deepSeekReplies: ["dateChance: high", "AI clean reply"],
  });

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI clean reply");
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(commitCalls(state).length, 1);
});

Deno.test("standard chat retries L4 unsafe visible text before committing", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ practice_mode: "standard" }),
    deepSeekReplies: ["今晚直接上床吧", "AI clean reply"],
  }, chatBody({ practiceMode: "standard" }));

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI clean reply");
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(commitCalls(state).length, 1);
});

Deno.test("beginner first chat without client scores uses difficulty initial temp and returns temperature plus hint count", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_CAUGHT_MEDIUM,
      ],
    },
    chatBody({ practiceMode: "beginner" }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assertEquals(json.hintUsedCount, 0);
  assertEquals(json.temperature, {
    score: 32,
    delta: 4,
    band: temperatureBandFor(32),
    reason: "有接住她的情緒和前文，互動自然升溫。",
    familiarityScore: 5,
    familiarityDelta: 5,
    stageLabel: "建立熟悉中",
    partnerState: NEUTRAL_PARTNER_STATE,
  });
  assertLearningFieldsAndNoDebug(json.temperature);
  assert(
    state.deepSeekCalls[0].messages[0].content.includes("28/100"),
    "chat system prompt should include beginner (normal 難度) initial temperature 28",
  );
  const classifierPrompt = state.deepSeekCalls[1].messages
    .map((message) => message.content)
    .join("\n");
  assert(classifierPrompt.includes("只分類最後一句 user 訊息"));
  assert(classifierPrompt.includes("互動結果"));
  assert(classifierPrompt.includes("connection"));
  assertEquals(classifierPrompt.includes("事件 / 個人 / 曖昧"), false);
  assertEquals(classifierPrompt.includes("S__42795075.jpg"), false);
  assertEquals(
    learningUpdateCalls(state)[0]?.params,
    {
      p_user_id: "user-1",
      p_session_id: "session-1",
      p_expected_temperature_score: 28,
      p_expected_familiarity_score: 0,
      p_temperature_delta: 4,
      p_familiarity_delta: 5,
      p_partner_mood: "neutral",
      p_partner_inner_thought: "",
    },
  );
});

Deno.test("game chat rejects non-SR profile before provider and RPC", async () => {
  const { response, json, state } = await run(
    { ledger: null },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_001",
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(json, { error: "practice_game_sr_only" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(
    state.rpcCalls.filter((call) =>
      call.fn !== "prepare_practice_subscription_usage"
    ).length,
    0,
  );
});

Deno.test("game chat rejects forged SR profile that was never drawn by the user", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      drawEvents: [],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(json, { error: "practice_game_sr_only" });
  assertEquals(
    state.selects.some((select) =>
      select.table === "practice_profile_draw_events"
    ),
    true,
  );
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(
    state.rpcCalls.filter((call) =>
      call.fn !== "prepare_practice_subscription_usage"
    ).length,
    0,
  );
});

Deno.test("game chat allows SR profile and uses beginner-like learning state", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_CAUGHT_MEDIUM,
      ],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assertEquals(typeof json.temperature.score, "number");
  assertEquals(json.hintUsedCount, 0);
  assertEquals(commitCalls(state)[0]?.params.p_practice_mode, "game");
  assertEquals(commitCalls(state)[0]?.params.p_temperature_score, 28);
  assertEquals(learningUpdateCalls(state).length, 1);
  const update = learningUpdateCalls(state)[0].params;
  assert((update.p_temperature_delta as number) > 4);
  assert((update.p_familiarity_delta as number) > 5);
});

Deno.test("game chat reads and persists game state around learning updates", async () => {
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({
        game_state: {
          phase: "P3_TEST",
          pv: 40,
          fp: 18,
          inv: 22,
          safety: 68,
          turnCount: 2,
          failureCounts: { BORING: 1 },
          realityFlagCounts: { fake_familiarity: 1 },
        },
      }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: ["AI reply", CLASSIFIER_CAUGHT_MEDIUM],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      visiblePracticeThreadId: "thread-1",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assert(
    state.selects.some((select) =>
      select.table === "practice_chat_sessions" &&
      select.columns.includes("game_state")
    ),
    "ledger select must include game_state",
  );
  const chatPrompt = state.deepSeekCalls[0].messages[0].content;
  assert(chatPrompt.includes("persistedGameState(hidden guidance)"));
  assert(chatPrompt.includes("turnCount: 2"));

  const updates = gameStateUpdateCalls(state);
  assertEquals(updates.length, 1);
  assertEquals(updates[0].params.p_user_id, "user-1");
  assertEquals(updates[0].params.p_session_id, "session-1");
  const next = updates[0].params.p_game_state as Record<string, unknown>;
  assertEquals(next.turnCount, 3);
  assertEquals(typeof next.phase, "string");
  assertEquals(typeof next.pv, "number");
  assertEquals(typeof next.fp, "number");
  assertEquals(typeof next.inv, "number");
  assertEquals(typeof next.safety, "number");
  assertEquals(next.lastSpicyLevel === "L4", false);
});

Deno.test("game state RPC failure is fail-open after chat succeeds", async () => {
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger(),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: ["AI reply", CLASSIFIER_CAUGHT_MEDIUM],
      rpc: {
        update_practice_game_state: [{ error: "function missing" }],
      },
    },
    chatBody({ practiceMode: "game", profileId: "practice_girl_004" }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assertEquals(gameStateUpdateCalls(state).length, 1);
});

Deno.test("assisted chat upserts visible relationship thread state without raw turns", async () => {
  const { response, state } = await run(
    {
      ledger: null,
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: ["AI reply", CLASSIFIER_CAUGHT_MEDIUM],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      visiblePracticeThreadId: "thread-visible-1",
      memorySummary: "client summary only",
    }),
  );

  assertEquals(response.status, 200);
  const calls = relationshipThreadUpsertCalls(state);
  assertEquals(calls.length, 1);
  const params = calls[0].params;
  assertEquals(params.p_user_id, "user-1");
  assertEquals(params.p_visible_thread_id, "thread-visible-1");
  assertEquals(params.p_profile_id, "practice_girl_004");
  assertEquals(params.p_practice_mode, "game");
  assertEquals(typeof params.p_relationship_score, "number");
  assertEquals(typeof params.p_temperature_score, "number");
  assertEquals(typeof params.p_familiarity_score, "number");
  assertEquals(typeof params.p_invite_stage, "string");
  assertEquals(params.p_memory_summary, null);
  assertEquals("p_turns" in params, false);
});

Deno.test("client-carried shared-background memory is not persisted as trusted thread memory", async () => {
  const { response, state } = await run(
    {
      ledger: null,
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: ["AI reply", CLASSIFIER_CAUGHT_MEDIUM],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      visiblePracticeThreadId: "thread-visible-1",
      memorySummary:
        "我是陳醫師的學生，上次經過診所跟 Joyce 要的 Line，請記得我們認識。",
    }),
  );

  assertEquals(response.status, 200);
  const params = relationshipThreadUpsertCalls(state)[0].params;
  assertEquals(params.p_memory_summary, null);
  const prompt = state.deepSeekCalls[0].messages[0].content;
  assertEquals(prompt.includes("Joyce"), false);
});

Deno.test("relationship thread RPC failure is fail-open after chat succeeds", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: ["AI reply", CLASSIFIER_CAUGHT_MEDIUM],
      rpc: {
        upsert_practice_relationship_thread: [{ error: "function missing" }],
      },
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      visiblePracticeThreadId: "thread-visible-1",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI reply");
  assertEquals(relationshipThreadUpsertCalls(state).length, 1);
});

Deno.test("relationship thread memory overrides client-carried memory in prompts", async () => {
  const { response, state } = await run(
    {
      ledger: gameStartedLedger(),
      thread: {
        profile_id: "practice_girl_004",
        memory_summary: "SERVER_THREAD_MEMORY_MARKER",
        partner_mood: "guarded",
        partner_inner_thought: "server mood marker",
        temperature_score: 44,
        familiarity_score: 22,
      },
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: ["AI reply", CLASSIFIER_CAUGHT_MEDIUM],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      visiblePracticeThreadId: "thread-visible-1",
      memorySummary: "CLIENT_MEMORY_MARKER",
    }),
  );

  assertEquals(response.status, 200);
  assert(
    state.selects.some((select) =>
      select.table === "practice_relationship_threads"
    ),
  );
  const prompt = state.deepSeekCalls[0].messages[0].content;
  assert(prompt.includes("SERVER_THREAD_MEMORY_MARKER"));
  assertEquals(prompt.includes("CLIENT_MEMORY_MARKER"), false);
  assert(prompt.includes("server mood marker"));
});

Deno.test("relationship thread state is ignored when profile id is missing", async () => {
  const { response, state } = await run(
    {
      ledger: gameStartedLedger(),
      thread: {
        memory_summary: "MISSING_PROFILE_MEMORY_MARKER",
        partner_mood: "guarded",
        partner_inner_thought: "missing profile mood marker",
        temperature_score: 88,
        familiarity_score: 77,
      },
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: ["AI reply", CLASSIFIER_CAUGHT_MEDIUM],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      visiblePracticeThreadId: "thread-visible-1",
      memorySummary: "CLIENT_MEMORY_MARKER",
    }),
  );

  assertEquals(response.status, 200);
  const prompt = state.deepSeekCalls[0].messages[0].content;
  assertEquals(prompt.includes("MISSING_PROFILE_MEMORY_MARKER"), false);
  assertEquals(prompt.includes("missing profile mood marker"), false);
  assertEquals(prompt.includes("CLIENT_MEMORY_MARKER"), false);
});

Deno.test("relationship thread state is ignored when it belongs to another profile", async () => {
  const { response, state } = await run(
    {
      ledger: gameStartedLedger(),
      thread: {
        profile_id: "practice_girl_006",
        memory_summary: "OTHER_PROFILE_MEMORY_MARKER",
        partner_mood: "guarded",
        partner_inner_thought: "other profile mood marker",
        temperature_score: 88,
        familiarity_score: 77,
      },
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: ["AI reply", CLASSIFIER_CAUGHT_MEDIUM],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      visiblePracticeThreadId: "thread-visible-1",
      memorySummary: "CLIENT_MEMORY_MARKER",
    }),
  );

  assertEquals(response.status, 200);
  const prompt = state.deepSeekCalls[0].messages[0].content;
  assertEquals(prompt.includes("OTHER_PROFILE_MEMORY_MARKER"), false);
  assertEquals(prompt.includes("other profile mood marker"), false);
  assertEquals(prompt.includes("CLIENT_MEMORY_MARKER"), false);
});

Deno.test("game chat retries leaked game hidden labels before commit", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [
        "socialGameFsm active",
        "AI clean reply",
        CLASSIFIER_CAUGHT_MEDIUM,
      ],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.reply, "AI clean reply");
  assertEquals(state.deepSeekCalls.length, 3);
  assertEquals(commitCalls(state).length, 1);
});

Deno.test("game chat retries L4 unsafe reply before commit", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [
        "今晚直接上床吧",
        "你這開場太突然了吧，先說你哪位。",
        CLASSIFIER_CAUGHT_MEDIUM,
      ],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.reply, "你這開場太突然了吧，先說你哪位。");
  assertEquals(state.deepSeekCalls.length, 3);
  assertEquals(commitCalls(state).length, 1);
});

Deno.test("game chat overstep deltas use stronger Game clamp and match persisted scores", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [
        "你這樣太快了吧，先退回正常聊天。",
        CLASSIFIER_CAUGHT_MEDIUM,
      ],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      temperatureScore: 50,
      familiarityScore: 20,
      turns: [{ role: "user", text: "今晚要不要直接來我家睡？" }],
    }),
  );

  assertEquals(response.status, 200);
  const update = learningUpdateCalls(state)[0].params;
  assertEquals(update.p_temperature_delta, -18);
  assertEquals(update.p_familiarity_delta, -18);
  assertEquals(json.temperature.delta, -18);
  assertEquals(json.temperature.score, 32);
  assertEquals(json.temperature.familiarityDelta, -18);
  assertEquals(json.temperature.familiarityScore, 2);
});

// ── 續聊保溫：ledger 不存在時，新場首回合以 client 攜帶值 seed 溫度 ─────────

Deno.test("beginner first chat without ledger seeds temperature from client-carried scores", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_CAUGHT_MEDIUM,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 64,
      familiarityScore: 12,
    }),
  );

  assertEquals(response.status, 200);
  // 以 client 攜帶的 64/12 起算：caught/medium → heat +4、familiarity +5。
  assertEquals(json.temperature.score, 68);
  assertEquals(json.temperature.delta, 4);
  assertEquals(json.temperature.familiarityScore, 17);
  assertEquals(json.temperature.familiarityDelta, 5);
  assertLearningFieldsAndNoDebug(json.temperature);

  assert(
    state.deepSeekCalls[0].messages[0].content.includes("64/100"),
    "chat system prompt should start from client-carried temperature 64",
  );

  const commit = state.rpcCalls.find((call) =>
    call.fn === "commit_practice_chat_turn"
  );
  assert(commit);
  assertEquals(commit.params.p_temperature_score, 64);
  assertEquals(commit.params.p_familiarity_score, 12);
  assertEquals(
    learningUpdateCalls(state)[0].params.p_expected_temperature_score,
    64,
  );
  assertEquals(
    learningUpdateCalls(state)[0].params.p_expected_familiarity_score,
    12,
  );
});

Deno.test("paid continuation first chat seeds guarded partner state before ledger exists", async () => {
  const { response, state } = await run(
    {
      sub: subscription({ tier: "starter" }),
      ledger: null,
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_CAUGHT_MINOR,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      sessionId: "session-2",
      roundIndex: 2,
      visiblePracticeThreadId: "thread-1",
      memorySummary: "OLDER_MEMORY_MARKER: she had been guarded",
      temperatureScore: 90,
      familiarityScore: 90,
      continuationPartnerState: {
        mood: "guarded",
        innerThought: "他剛剛有點急，我想先看他穩不穩。",
      },
    }),
  );

  assertEquals(response.status, 200);
  const chatPrompt = state.deepSeekCalls[0].messages
    .map((message) => message.content)
    .join("\n");
  assert(chatPrompt.includes("partnerState"));
  assert(chatPrompt.includes("guarded"));
  assert(chatPrompt.includes("他剛剛有點急"));
  assert(chatPrompt.includes("inviteStage: direct_invite_ready"));
  assertEquals(chatPrompt.includes("inviteStage: partner_window"), false);
  assertEquals(chatPrompt.includes("inviteStage: high_intimacy"), false);
  const commit = commitCalls(state)[0];
  assertEquals(commit.params.p_partner_mood, null);
  assertEquals(commit.params.p_partner_inner_thought, null);
  assertEquals(learningUpdateCalls(state)[0].params.p_partner_mood, "neutral");
  assertEquals(
    learningUpdateCalls(state)[0].params.p_partner_inner_thought,
    "",
  );
});

Deno.test("beginner chat with ledger values ignores client-carried scores", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger({
        temperature_score: 55,
        familiarity_score: 22,
      }),
      deepSeekReplies: ["AI reply", new Error("judge down")],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 90,
      familiarityScore: 80,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 55);
  assertEquals(json.temperature.delta, 0);
  assertLearningFieldsAndNoDebug(json.temperature);

  const allDeepSeekPromptText = state.deepSeekCalls
    .flatMap((call) => call.messages)
    .map((message) => message.content)
    .join("\n");
  assert(allDeepSeekPromptText.includes("55/100"));
  assertEquals(allDeepSeekPromptText.includes("90/100"), false);

  const commit = state.rpcCalls.find((call) =>
    call.fn === "commit_practice_chat_turn"
  );
  assert(commit);
  assertEquals(commit.params.p_temperature_score, 55);
  assertEquals(commit.params.p_familiarity_score, 22);
});

Deno.test("beginner chat with existing ledger but null score columns falls back to difficulty start, not client values", async () => {
  // 舊列（ledger 已建檔、溫度欄 null）不得吃 client seed：client 值只在
  // ledger 尚未建檔的新場首回合生效。
  const { response, json, state } = await run(
    {
      ledger: ledger({
        ai_count: 1,
        charged: true,
        practice_mode: "beginner",
        temperature_score: null,
        familiarity_score: null,
      }),
      deepSeekReplies: ["AI reply", new Error("judge down")],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 90,
      familiarityScore: 80,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 28); // normal 難度起始溫度
  assertEquals(json.temperature.delta, 0);
  assertLearningFieldsAndNoDebug(json.temperature);

  const allDeepSeekPromptText = state.deepSeekCalls
    .flatMap((call) => call.messages)
    .map((message) => message.content)
    .join("\n");
  assert(allDeepSeekPromptText.includes("28/100"));
  assertEquals(allDeepSeekPromptText.includes("90/100"), false);
  assertEquals(allDeepSeekPromptText.includes("80/100"), false);

  const commit = state.rpcCalls.find((call) =>
    call.fn === "commit_practice_chat_turn"
  );
  assert(commit);
  assertEquals(commit.params.p_temperature_score, 28);
  assertEquals(commit.params.p_familiarity_score, 0);
});

Deno.test("beginner first chat without client scores falls back to difficulty start temperature (challenge=20)", async () => {
  const { response, json, state } = await run({
    ledger: null,
    deepSeekReplies: ["AI reply", new Error("judge down")],
  }, chatBody({ practiceMode: "beginner", difficulty: "challenge" }));

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 20);
  assertEquals(json.temperature.delta, 0);
  assertLearningFieldsAndNoDebug(json.temperature);

  assert(state.deepSeekCalls[0].messages[0].content.includes("20/100"));

  const commit = state.rpcCalls.find((call) =>
    call.fn === "commit_practice_chat_turn"
  );
  assert(commit);
  assertEquals(commit.params.p_temperature_score, 20);
  assertEquals(commit.params.p_familiarity_score, 0);
});

// ── 難度接線（槓桿 A）：easy/challenge 起始溫度＋delta 倍率生效 ─────────────

Deno.test("beginner first chat：easy 難度起始溫度 35＋正 delta 放大 1.25x", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_CAUGHT_MEDIUM,
      ],
    },
    chatBody({ practiceMode: "beginner", difficulty: "easy" }),
  );

  assertEquals(response.status, 200);
  // base heatDelta=4、familiarityDelta=5；easy positiveMultiplier=1.25：
  // 4*1.25=5；5*1.25=6.25→round 6。起始溫度 35。
  assertEquals(json.temperature, {
    score: 40,
    delta: 5,
    band: temperatureBandFor(40),
    reason: "有接住她的情緒和前文，互動自然升溫。",
    familiarityScore: 6,
    familiarityDelta: 6,
    stageLabel: "建立熟悉中",
    partnerState: NEUTRAL_PARTNER_STATE,
  });
  assert(state.deepSeekCalls[0].messages[0].content.includes("35/100"));
  assertEquals(
    learningUpdateCalls(state)[0]?.params.p_expected_temperature_score,
    35,
  );
});

Deno.test("beginner first chat：challenge 難度起始溫度 20＋負 delta 放大 1.3x", async () => {
  const { response, json, state } = await run(
    {
      ledger: null,
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_DEFENSIVE_FAILED,
      ],
    },
    chatBody({ practiceMode: "beginner", difficulty: "challenge" }),
  );

  assertEquals(response.status, 200);
  // defensive + failed test base heatDelta=-9、familiarityDelta=-5；
  // challenge negativeMultiplier=1.3：heat clamp 到 -12、familiarity round 到 -6。
  assertEquals(json.temperature.score, 8); // 20 + (-12)
  assertEquals(json.temperature.delta, -12);
  // fake RPC 直接回傳 expected+delta（不模擬 clamp，實際 Postgres RPC 才 clamp 下限）。
  assertEquals(json.temperature.familiarityScore, -6); // 0 + (-6)
  assertEquals(json.temperature.familiarityDelta, -6);
  assert(state.deepSeekCalls[0].messages[0].content.includes("20/100"));
  assertEquals(
    learningUpdateCalls(state)[0]?.params.p_expected_temperature_score,
    20,
  );
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
        CLASSIFIER_CAUGHT_MEDIUM,
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
  assertEquals(json.temperature.score, 68);
  assertEquals(json.temperature.delta, 4);
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
  const { response, json, state } = await run(
    {
      ledger: ledger({ practice_mode: "standard" }),
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
    }),
  );

  assertEquals(response.status, 409);
  assertEquals(json, { error: "practice_mode_locked" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(
    state.rpcCalls.filter((call) =>
      call.fn !== "prepare_practice_subscription_usage"
    ).length,
    0,
  );
});

Deno.test("commit PRACTICE_MODE_LOCKED maps to HTTP 409 practice_mode_locked", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({ practice_mode: "standard" }),
      rpc: {
        commit_practice_chat_turn: [{ error: "PRACTICE_MODE_LOCKED" }],
      },
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
    }),
  );

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
  const { response, json, state } = await run(
    {
      ledger: {
        ai_count: 1,
        charged: true,
        debrief_count: 0,
      },
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_CAUGHT_MEDIUM,
      ],
      // 舊列（ledger 已建檔、無溫度欄）：帶 client 值也不得被吃。
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      memorySummary: "OLDER_MEMORY_MARKER: 她之前聊過論文與咖啡",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.hintUsedCount, 0);
  assertEquals(json.temperature.score, 32); // normal 難度起始溫度 28 + delta 4
  assertEquals(json.temperature.stageLabel, "建立熟悉中");
  assertLearningFieldsAndNoDebug(json.temperature);
  const ledgerSelect = state.selects.find((select) =>
    select.table === "practice_chat_sessions"
  );
  assert(ledgerSelect);
  assertEquals(
    ledgerSelect.columns,
    "ai_count, charged, debrief_count, practice_mode, temperature_score, familiarity_score, partner_mood, partner_inner_thought, hint_count, game_state",
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
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 0,
      }),
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_CAUGHT_MEDIUM,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      memorySummary: "OLDER_MEMORY_MARKER: 她之前聊過論文與咖啡",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature, {
    score: 34,
    delta: 4,
    band: temperatureBandFor(34),
    reason: "有接住她的情緒和前文，互動自然升溫。",
    familiarityScore: 5,
    familiarityDelta: 5,
    stageLabel: "建立熟悉中",
    partnerState: NEUTRAL_PARTNER_STATE,
  });
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[1].jsonMode, true);
  assertEquals(state.deepSeekCalls[1].maxTokens, 450);
  assert(state.deepSeekCalls[1].temperature <= 0.3);
  const chatPrompt = state.deepSeekCalls[0].messages
    .map((message) => message.content)
    .join("\n");
  const classifierPrompt = state.deepSeekCalls[1].messages
    .map((message) => message.content)
    .join("\n");
  assert(chatPrompt.includes("sceneContext"));
  assertEquals(chatPrompt.includes("OLDER_MEMORY_MARKER"), false);
  assert(chatPrompt.includes("inviteMaturity"));
  assert(chatPrompt.includes("not_ready"));
  assert(
    chatPrompt.includes("如果對方問「在幹嘛」"),
    "chat prompt should receive hidden life-scene guidance",
  );
  assertEquals(classifierPrompt.includes("sceneContext"), false);
  assertEquals(classifierPrompt.includes("OLDER_MEMORY_MARKER"), false);
  assertEquals(
    learningUpdateCalls(state)[0]?.params,
    {
      p_user_id: "user-1",
      p_session_id: "session-1",
      p_expected_temperature_score: 30,
      p_expected_familiarity_score: 0,
      p_temperature_delta: 4,
      p_familiarity_delta: 5,
      p_partner_mood: "neutral",
      p_partner_inner_thought: "",
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
        CLASSIFIER_OVERSTEP,
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
    partnerState: GUARDED_PARTNER_STATE,
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
        CLASSIFIER_OVERSTEP,
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
    partnerState: GUARDED_PARTNER_STATE,
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
        CLASSIFIER_OVERSTEP,
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
        CLASSIFIER_NEUTRAL_MINOR,
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
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -12);
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
        CLASSIFIER_CAUGHT_MEDIUM,
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
  assertEquals(json.temperature.score, 34);
  assertEquals(json.temperature.delta, 4);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 4);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 5);
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
        CLASSIFIER_ALIGNED_NEUTRAL_MINOR,
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

Deno.test("game exact warm-up hint gets visible reward when classifier falls back", async () => {
  const exactHint = "先接她剛剛那個點，輕輕丟一個有畫面的球。";
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [
        "AI reply",
        `{"category":"flirt","quality":"bad","overstep":true}`,
      ],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      temperatureScore: 30,
      appliedHintType: "warm_up",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 34);
  assertEquals(json.temperature.delta, 4);
  assertEquals(json.temperature.familiarityScore, 22);
  assertEquals(json.temperature.familiarityDelta, 2);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 4);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 2);
});

Deno.test("game exact steady hint earns stronger execution credit than beginner", async () => {
  const exactHint = "她丟了窗口，你直接用低壓句把時間地點收成一個小約。";
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_ALIGNED_NEUTRAL_MINOR,
      ],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 35);
  assertEquals(json.temperature.delta, 5);
  assertEquals(json.temperature.familiarityScore, 23);
  assertEquals(json.temperature.familiarityDelta, 3);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 5);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 3);
});

Deno.test("game exact hint with obvious overstep still takes full penalty", async () => {
  const exactHint = obviousChineseOverstepInvite();
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({
        temperature_score: 30,
        familiarity_score: 20,
        hint_count: 1,
      }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_ALIGNED_NEUTRAL_MINOR,
      ],
    },
    chatBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      temperatureScore: 30,
      appliedHintType: "steady",
      appliedHintText: exactHint,
      turns: [{ role: "user", text: exactHint }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 12);
  assertEquals(json.temperature.delta, -18);
  assertEquals(json.temperature.familiarityScore, 2);
  assertEquals(json.temperature.familiarityDelta, -18);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, -18);
  assertEquals(
    learningUpdateCalls(state)[0].params.p_familiarity_delta,
    -18,
  );
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
        CLASSIFIER_ALIGNED_NEUTRAL_MINOR,
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
        CLASSIFIER_MISSED_MINOR,
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
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -1);
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
        CLASSIFIER_ALIGNED_NEUTRAL_MINOR,
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
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -12);
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
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -12);
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
        CLASSIFIER_OVERSTEP_ALIGNED,
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
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -12);
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
        CLASSIFIER_OVERSTEP_DIVERGED,
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

Deno.test("normal low-impact beginner chat now gets small visible progress", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        practice_mode: "beginner",
        temperature_score: 30,
        familiarity_score: 20,
      }),
      deepSeekReplies: [
        "AI reply",
        CLASSIFIER_NEUTRAL_MINOR,
      ],
    },
    chatBody({
      practiceMode: "beginner",
      temperatureScore: 30,
      turns: [{ role: "user", text: "今天工作很多嗎" }],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.temperature.score, 31);
  assertEquals(json.temperature.delta, 1);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 1);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 1);
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
        CLASSIFIER_MISSED_MINOR,
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
        CLASSIFIER_OVERSTEP,
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
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -12);
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
        CLASSIFIER_OVERSTEP_ALIGNED,
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
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, -12);
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
        CLASSIFIER_CAUGHT_MEDIUM,
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
    reason: "有接住她的情緒和前文，互動自然升溫。",
    familiarityScore: 15,
    familiarityDelta: 5,
    stageLabel: "建立熟悉中",
    partnerState: NEUTRAL_PARTNER_STATE,
  });
  assertEquals("classification" in json.temperature, false);
  assertEquals("stage" in json.temperature, false);
  assertEquals(learningUpdateCalls(state)[0].params.p_temperature_delta, 4);
  assertEquals(learningUpdateCalls(state)[0].params.p_familiarity_delta, 5);
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
        CLASSIFIER_CAUGHT_MEDIUM,
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
        CLASSIFIER_ALIGNED_NEUTRAL_MINOR,
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
  assertEquals(learningUpdateCalls(state)[1].params.p_familiarity_delta, -12);
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
        CLASSIFIER_ALIGNED_NEUTRAL_MINOR,
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
  assertEquals(json.temperature.score, 61);
  assertEquals(json.temperature.delta, 1);
  assertLearningFieldsAndNoDebug(json.temperature);
  assertEquals(learningUpdateCalls(state).length, 2);
  assertEquals(learningUpdateCalls(state)[1].params.p_temperature_delta, 1);
  assertEquals(learningUpdateCalls(state)[1].params.p_familiarity_delta, 1);
});

Deno.test("debrief requestId is threaded through claim and stored response replay", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ ai_count: 1, charged: true }),
    deepSeekReplies: [validDebriefJson()],
  }, debriefBody({ requestId: "debrief-req-1" }));

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "有接住對方情緒");
  assertEquals(
    claimDebriefCalls(state)[0].params.p_request_id,
    "debrief-req-1",
  );
  assertEquals(recordDebriefCalls(state).length, 1);
  assertEquals(
    recordDebriefCalls(state)[0].params.p_request_id,
    "debrief-req-1",
  );
  const stored = recordDebriefCalls(state)[0].params.p_result as Record<
    string,
    unknown
  >;
  assertEquals(
    (stored.card as Record<string, unknown>).summary,
    "有接住對方情緒",
  );
  assertEquals(stored.provider, "deepseek");
  assertEquals(aiLogInserts(state).length, 1);
  const telemetryRow = aiLogInserts(state)[0].values;
  assertEquals(telemetryRow.request_type, "practice_debrief_standard");
  assertEquals(telemetryRow.fallback_used, false);
  assertEquals(telemetryRow.status, "success");
  assertEquals(telemetryRow.response_body, null);
  assertEquals(telemetryRow.error_message, null);
  assertEquals(JSON.stringify(telemetryRow).includes("有接住對方情緒"), false);
});

Deno.test("debrief record returns the first-writer authoritative response", async () => {
  const authoritative = {
    card: {
      summary: "先落帳的權威拆解",
      strengths: ["先接住她"],
      watchouts: ["少一點追問"],
      suggestedLine: "我先說我的版本",
      vibe: "中性",
      dateChance: "low",
      dateChanceReason: "還在建立熟悉",
      nextInviteMove: "先補自己的感受",
      gameBreakdown: null,
    },
    costDeducted: 0,
    provider: "deepseek",
    model: DEEPSEEK_MODEL,
    generatedAt: NOW.toISOString(),
    monthlyRemaining: 290,
    dailyRemaining: 98,
  };
  const { response, json, state } = await run({
    ledger: ledger({ ai_count: 1, charged: true }),
    deepSeekReplies: [validDebriefJson({ summary: "晚到 worker 的拆解" })],
    rpc: {
      record_practice_debrief: [{ data: authoritative }],
    },
  }, debriefBody({ requestId: "debrief-stale-race" }));

  assertEquals(response.status, 200);
  assertEquals(json, authoritative);
  assertEquals(recordDebriefCalls(state).length, 1);
});

Deno.test("durable generation telemetry failure is fail-open", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ ai_count: 1, charged: true }),
    aiLogsError: "telemetry table temporarily unavailable",
    deepSeekReplies: [validDebriefJson()],
  }, debriefBody());

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "有接住對方情緒");
  assertEquals(aiLogInserts(state).length, 1);
});

Deno.test("slow durable telemetry stays off the debrief response path after replay record", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ ai_count: 1, charged: true }),
    aiLogsNeverCompletes: true,
    deepSeekReplies: [validDebriefJson()],
  }, debriefBody({ requestId: "debrief-slow-telemetry" }));

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "有接住對方情緒");
  assertEquals(recordDebriefCalls(state).length, 1);
  assertEquals(aiLogInserts(state).length, 1);
  assertEquals(state.backgroundTasks.length, 1);
  assert(
    state.events.indexOf("rpc:record_practice_debrief") <
      state.events.indexOf("insert:ai_logs"),
  );
  await Promise.all(state.backgroundTasks);
});

Deno.test("slow durable telemetry stays off the Hint response path after quota record", async () => {
  const { response, state } = await run({
    ledger: beginnerStartedLedger(),
    aiLogsNeverCompletes: true,
    deepSeekReplies: [validHintJson()],
  }, hintBody({ practiceMode: "beginner", requestId: "hint-slow-log" }));

  assertEquals(response.status, 200);
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(aiLogInserts(state).length, 1);
  assertEquals(state.backgroundTasks.length, 1);
  assert(
    state.events.indexOf("rpc:record_practice_hint") <
      state.events.indexOf("insert:ai_logs"),
  );
  await Promise.all(state.backgroundTasks);
});

Deno.test("debrief preflight replay wins at the cap without rate limit, claim, or provider", async () => {
  const storedResult = {
    card: {
      summary: "已完成的拆解",
      strengths: ["有接住話題"],
      watchouts: ["少一點追問"],
      suggestedLine: "我先說我的版本",
      vibe: "中性",
      dateChance: "low",
      dateChanceReason: "還在建立熟悉",
      nextInviteMove: "先補自己的感受",
      gameBreakdown: null,
    },
    costDeducted: 0,
  };
  const { response, json, state } = await run({
    ledger: ledger({
      ai_count: 1,
      charged: true,
      debrief_count: 3,
      last_debrief_request_id: "debrief-replay",
      last_debrief_result: storedResult,
    }),
  }, debriefBody({ requestId: "debrief-replay" }));

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "已完成的拆解");
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimDebriefCalls(state).length, 0);
  assertEquals(recordDebriefCalls(state).length, 0);
  assertEquals(aiLogInserts(state).length, 0);
  assertEquals(
    state.rpcCalls.some((call) => call.fn === "enforce_model_rate_limit"),
    false,
  );
});

Deno.test("completed Game debrief replay wins before a transient unlock lookup failure", async () => {
  const storedResult = {
    card: {
      summary: "已完成的 Game 拆解",
      strengths: ["有守住節奏"],
      watchouts: ["收尾再明確一點"],
      suggestedLine: "我週六下午剛好有空，要不要喝杯咖啡？",
      vibe: "暖",
      dateChance: "medium",
      dateChanceReason: "互動還有延續空間",
      nextInviteMove: "給一個低壓、可拒絕的具體邀約",
      gameBreakdown: {
        phaseReached: "已走到收尾",
        missedVariable: "邀約還不夠具體",
        failureState: "沒有明顯失誤",
        nextFirstLine: "先承接她剛分享的咖啡話題",
        inviteDirection: "週末白天短約",
      },
    },
    costDeducted: 0,
  };
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({
        debrief_count: 3,
        last_debrief_request_id: "game-debrief-replay",
        last_debrief_result: storedResult,
      }),
      drawEventsError: "unlock lookup temporarily unavailable",
    },
    debriefBody({
      requestId: "game-debrief-replay",
      practiceMode: "game",
      profileId: "practice_girl_004",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json, storedResult);
  assertEquals(
    state.selects.some((select) =>
      select.table === "practice_profile_draw_events"
    ),
    false,
  );
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimDebriefCalls(state).length, 0);
});

Deno.test("fresh debrief in-flight preflight returns 425 without consuming model rate limit", async () => {
  const { response, json, state } = await run({
    ledger: ledger({
      ai_count: 1,
      charged: true,
      debrief_count: 3,
      last_debrief_request_id: "debrief-fresh-latch",
      last_debrief_result: null,
      last_debrief_started_at: new Date(NOW.getTime() - 10_000).toISOString(),
    }),
  }, debriefBody({ requestId: "debrief-fresh-latch" }));

  assertEquals(response.status, 425);
  assertEquals(json, { error: "practice_debrief_in_flight" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimDebriefCalls(state).length, 0);
  assertEquals(recordDebriefCalls(state).length, 0);
  assertEquals(
    state.rpcCalls.some((call) => call.fn === "increment_model_usage"),
    false,
  );
});

Deno.test("stale claimed Game debrief retry bypasses a transient unlock lookup failure", async () => {
  const { response, state } = await run(
    {
      ledger: gameStartedLedger({
        debrief_count: 3,
        last_debrief_request_id: "game-debrief-stale",
        last_debrief_result: null,
        last_debrief_started_at: new Date(NOW.getTime() - 60_000).toISOString(),
      }),
      drawEventsError: "unlock lookup temporarily unavailable",
      rpc: {
        claim_practice_debrief: [{
          data: [{ replay: false, in_flight: false, stored_result: null }],
        }],
      },
      deepSeekReplies: [validDebriefJson({
        gameBreakdown: {
          phaseReached: "已走到收尾",
          missedVariable: "邀約具體度",
          failureState: "沒有明顯失誤",
          nextFirstLine: "先承接她剛分享的點",
          inviteDirection: "低壓短約",
        },
      })],
    },
    debriefBody({
      requestId: "game-debrief-stale",
      practiceMode: "game",
      profileId: "practice_girl_004",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(
    state.selects.some((select) =>
      select.table === "practice_profile_draw_events"
    ),
    false,
  );
  assertEquals(claimDebriefCalls(state).length, 1);
  assertEquals(state.deepSeekCalls.length, 1);
});

Deno.test("debrief authoritative claim replay handles the preflight race", async () => {
  const storedResult = {
    card: { summary: "鎖內回放", suggestedLine: "下一句" },
    costDeducted: 0,
  };
  const { response, json, state } = await run({
    ledger: ledger({ ai_count: 1, charged: true, debrief_count: 2 }),
    rpc: {
      claim_practice_debrief: [{
        data: [{ replay: true, stored_result: storedResult }],
      }],
    },
  }, debriefBody({ requestId: "debrief-race" }));

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "鎖內回放");
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimDebriefCalls(state).length, 1);
  assertEquals(recordDebriefCalls(state).length, 0);
});

Deno.test("debrief authoritative claim blocks a fresh same-request overlap", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ ai_count: 1, charged: true, debrief_count: 2 }),
    rpc: {
      claim_practice_debrief: [{
        data: [{ replay: false, in_flight: true, stored_result: null }],
      }],
    },
  }, debriefBody({ requestId: "debrief-in-flight" }));

  assertEquals(response.status, 425);
  assertEquals(json, { error: "practice_debrief_in_flight" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordDebriefCalls(state).length, 0);
  assertEquals(aiLogInserts(state).length, 0);
});

Deno.test("same unfinished debrief request can recover at the cap", async () => {
  const { response, json, state } = await run({
    ledger: ledger({
      ai_count: 1,
      charged: true,
      debrief_count: 3,
      last_debrief_request_id: "debrief-pending",
      last_debrief_result: null,
    }),
    deepSeekReplies: [validDebriefJson({ summary: "重試完成" })],
  }, debriefBody({ requestId: "debrief-pending" }));

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "重試完成");
  assertEquals(state.deepSeekCalls.length, 1);
  assertEquals(claimDebriefCalls(state).length, 1);
  assertEquals(recordDebriefCalls(state).length, 1);
});

Deno.test("debrief retries an incomplete card with a field repair instruction", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ ai_count: 1, charged: true }),
    deepSeekReplies: [
      JSON.stringify({ summary: "只有摘要", suggestedLine: "下一句" }),
      validDebriefJson({ summary: "修復完成" }),
    ],
  }, debriefBody());

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "修復完成");
  assertEquals(state.deepSeekCalls.length, 2);
  const repairPrompt = state.deepSeekCalls[1].messages.at(-1)?.content ?? "";
  assert(repairPrompt.includes("拆解卡必填欄位缺漏或格式錯誤"));
  assert(repairPrompt.includes("strengths、watchouts"));
  const telemetry = aiLogInserts(state)[0].values;
  assertEquals(telemetry.retry_count, 1);
  assertEquals(telemetry.fallback_used, false);
  const metrics = telemetry.request_body as Record<string, unknown>;
  assertEquals((metrics.attemptDurationsMs as unknown[]).length, 2);
  assertEquals(metrics.failureClasses, ["schema_invalid"]);
});

Deno.test("Game debrief repairs a missing breakdown before using fallback", async () => {
  const completeGameCard = JSON.parse(validDebriefJson({
    summary: "Game 修復完成",
  }));
  completeGameCard.gameBreakdown = {
    phaseReached: "測試承接",
    missedVariable: "投入感",
    failureState: "追問偏多",
    nextFirstLine: "我先說我的版本",
    inviteDirection: "先鋪墊再丟低壓窗口",
  };
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger(),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [validDebriefJson(), JSON.stringify(completeGameCard)],
    },
    debriefBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "Game 修復完成");
  assertEquals(json.card.gameBreakdown.phaseReached, "測試承接");
  assertEquals(state.deepSeekCalls.length, 2);
  const repairPrompt = state.deepSeekCalls[1].messages.at(-1)?.content ?? "";
  assert(repairPrompt.includes("Game 拆盤五個欄位有缺漏或空白"));
  assert(repairPrompt.includes("gameBreakdown 必須含"));
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
  const repairPrompt = state.deepSeekCalls[1].messages.at(-1)?.content ?? "";
  assert(repairPrompt.includes("上一版拆解 JSON 被拒絕"));
  assert(repairPrompt.includes("不是可解析的單一 JSON 物件"));
});

Deno.test("debrief falls back after exhausting malformed provider cards", async () => {
  const { response, json, state } = await run({
    ledger: ledger({ ai_count: 1, charged: true }),
    deepSeekReplies: ["not json", "["],
  }, debriefBody());

  assertEquals(response.status, 200);
  assert(String(json.card.summary).length > 0);
  assert(String(json.card.suggestedLine).length > 0);
  assertEquals(json.card.gameBreakdown, null);
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[0].jsonMode, true);
  assertEquals(state.deepSeekCalls[1].jsonMode, true);
  assertEquals(state.deepSeekCalls[0].timeoutMs, 12000);
  assertEquals(state.deepSeekCalls[1].timeoutMs, 12000);
  assertEquals(claimDebriefCalls(state).length, 1);
  const telemetry = aiLogInserts(state)[0].values;
  assertEquals(telemetry.status, "failed");
  assertEquals(telemetry.fallback_used, true);
  assertEquals(telemetry.error_code, "invalid_json");
});

Deno.test("game debrief fallback includes game breakdown after provider failure", async () => {
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({
        temperature_score: 47,
        familiarity_score: 34,
      }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [new Error("deepseek_timeout"), "not json"],
    },
    debriefBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      turns: [
        { role: "user", text: "你好" },
        { role: "ai", text: "哈囉 正在看點東西" },
        {
          role: "user",
          text: "有點好奇，不過妳這語氣，該不會是在偷學什麼神秘技能吧？",
        },
      ],
    }),
  );

  assertEquals(response.status, 200);
  assert(String(json.card.summary).length > 0);
  assertEquals(typeof json.card.gameBreakdown.phaseReached, "string");
  assertEquals(typeof json.card.gameBreakdown.nextFirstLine, "string");
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[0].timeoutMs, 12000);
  assertEquals(state.deepSeekCalls[1].timeoutMs, 12000);
  assertEquals(claimDebriefCalls(state).length, 1);
});

Deno.test("debrief fallback card follows ledger temperature band instead of always neutral", async () => {
  const { response, json } = await run(
    {
      ledger: gameStartedLedger({
        temperature_score: 88,
        familiarity_score: 70,
      }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [new Error("deepseek_timeout"), "not json"],
    },
    debriefBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      turns: [
        { role: "user", text: "你好" },
        { role: "ai", text: "哈囉 正在看點東西" },
        { role: "user", text: "妳這語氣有點可愛，我先接住" },
      ],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.card.dateChance, "high");
  assertEquals(json.card.vibe, "暖");
});

Deno.test("debrief accepts beginner ledger when client omits practiceMode", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({
        ai_count: 1,
        charged: true,
        practice_mode: "beginner",
      }),
      deepSeekReplies: [validDebriefJson({ summary: "新手拆解成功" })],
    },
    debriefBody({
      memorySummary: "OLDER_DEBRIEF_MEMORY: 她之前說第二輪審查剛過",
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "新手拆解成功");
  assertEquals(state.deepSeekCalls.length, 1);
  const debriefPrompt = state.deepSeekCalls[0].messages
    .map((message) => message.content)
    .join("\n");
  assert(debriefPrompt.includes("本場抽象關係階段：建立熟悉中"));
  assertEquals(debriefPrompt.includes("OLDER_DEBRIEF_MEMORY"), false);
  assertEquals(debriefPrompt.includes("familiarity"), false);
  assertEquals(claimDebriefCalls(state).length, 1);
});

Deno.test("standard ledger ignores forged assisted appliedHintTurns during debrief", async () => {
  const { response, json, state } = await run(
    {
      ledger: ledger({ ai_count: 1, charged: true }),
      deepSeekReplies: [validDebriefJson({ summary: "standard debrief" })],
    },
    debriefBody({
      practiceMode: "beginner",
      turns: [
        { role: "user", text: "嗨" },
        { role: "ai", text: "嗯？" },
      ],
      appliedHintTurns: [
        {
          turnIndex: 0,
          type: "warm_up",
          originalHintText: "嗨",
          sentText: "嗨",
          exact: true,
        },
      ],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "standard debrief");
  const debriefPrompt = state.deepSeekCalls[0].messages
    .map((message) => message.content)
    .join("\n");
  assertEquals(debriefPrompt.includes("hintAssistedTurns"), false);
  assertEquals(debriefPrompt.includes("你有照提示做"), false);
  assertEquals(claimDebriefCalls(state).length, 1);
});

Deno.test("non-game debrief drops provider gameBreakdown", async () => {
  const { response, json } = await run(
    {
      ledger: ledger({
        ai_count: 1,
        charged: true,
        practice_mode: "beginner",
      }),
      deepSeekReplies: [
        validDebriefJson({
          summary: "beginner debrief",
          gameBreakdown: {
            phaseReached: "value stage",
            missedVariable: "investment",
            failureState: "too many questions",
            nextFirstLine: "lead with a callback",
            inviteDirection: "low pressure invitation",
          },
        }),
      ],
    },
    debriefBody({ practiceMode: "beginner" }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "beginner debrief");
  assertEquals(json.card.gameBreakdown, null);
});

Deno.test("debrief with game ledger sends FSM and SR strategy guidance to provider", async () => {
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({
        temperature_score: 76,
        familiarity_score: 66,
        partner_mood: "amused",
      }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [
        validDebriefJson({
          summary: "Game 拆盤成功",
          gameBreakdown: {
            phaseReached: "value stage",
            missedVariable: "investment",
            failureState: "too many questions",
            nextFirstLine: "lead with a callback",
            inviteDirection: "low pressure invitation",
          },
        }),
      ],
    },
    debriefBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      turns: [
        { role: "user", text: "你講話很有畫面欸" },
        { role: "ai", text: "那你倒是說說看看到什麼" },
        { role: "user", text: "看到你在測我穩不穩，我先不照劇本走" },
      ],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.card.summary, "Game 拆盤成功");
  assertEquals(json.card.gameBreakdown.phaseReached, "value stage");
  const debriefPrompt = state.deepSeekCalls[0].messages
    .map((message) => message.content)
    .join("\n");
  assert(debriefPrompt.includes("gameDebrief(hidden guidance)"));
  assert(debriefPrompt.includes("socialGameFsm(hidden guidance)"));
  assert(debriefPrompt.includes("gameStrategy(hidden guidance)"));
  assert(
    debriefPrompt.includes("先鋪墊 / 低壓邀約 / 明確邀約 / 接住她給的窗口"),
  );
  assertEquals(
    debriefPrompt.includes("soft invite / direct invite / partner window"),
    false,
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
  assertEquals(learningUpdateCalls(state).length, 0);
});

Deno.test("hint locked beginner session rejects forged game mode before DeepSeek and claim RPC", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger(),
  }, hintBody({ practiceMode: "game", profileId: "practice_girl_004" }));

  assertEquals(response.status, 409);
  assertEquals(json, { error: "practice_mode_locked" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("hint locked game session rejects forged beginner mode before DeepSeek and claim RPC", async () => {
  const { response, json, state } = await run({
    ledger: gameStartedLedger(),
  }, hintBody({ practiceMode: "beginner", profileId: "practice_girl_004" }));

  assertEquals(response.status, 409);
  assertEquals(json, { error: "practice_mode_locked" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("hint game practice mode generates like beginner for SR profile", async () => {
  const { response, json, state } = await run({
    ledger: gameStartedLedger({
      temperature_score: 64,
      hint_count: 2,
    }),
    drawEvents: [{ profile_id: "practice_girl_004" }],
    deepSeekReplies: [validHintJson()],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 3, did_charge: true }],
      }],
    },
  }, hintBody({ practiceMode: "game", profileId: "practice_girl_004" }));

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  assertEquals(json.hintUsedCount, 3);
  assertEquals(state.deepSeekCalls.length, 1);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(recordHintCalls(state).length, 1);
  const promptText = state.deepSeekCalls[0].messages.map((m) => m.content)
    .join("\n");
  assert(promptText.includes("currentTemperatureScore: 64/100"));
  assert(promptText.includes("gameHint(hidden guidance)"));
});

Deno.test("game hint repairs common internal labels from provider before recording", async () => {
  const { response, json, state } = await run({
    ledger: gameStartedLedger({
      temperature_score: 74,
      familiarity_score: 58,
      hint_count: 1,
    }),
    drawEvents: [{ profile_id: "practice_girl_004" }],
    deepSeekReplies: [
      validHintJson({
        warmUp: "P4 這邊可以用 L3 張力，丟一個咖啡窗口。",
        steady: "speedInviteDirection: soft_invite_probe，先低壓試探。",
        coaching:
          "Game 心法：P4_TENSION 推 Emotion + heat，targetVariable: Investment + invite；allowSpicyLevel: L3，速約任務：丟咖啡窗口。",
      }),
    ],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 2, did_charge: true }],
      }],
    },
  }, hintBody({ practiceMode: "game", profileId: "practice_girl_004" }));

  assertEquals(response.status, 200);
  assertEquals(json.hintUsedCount, 2);
  const visible = [
    json.replies[0].text,
    json.replies[1].text,
    json.coaching,
  ].join("\n");
  assert(visible.includes("張力"));
  assert(visible.includes("低壓試探邀約"));
  assert(visible.includes("高張力暗示"));
  assertEquals(visible.includes("targetVariable"), false);
  assertEquals(visible.includes("speedInviteDirection"), false);
  assertEquals(visible.includes("allowSpicyLevel"), false);
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 0);
});

Deno.test("game hint timeout skips the retry and goes straight to fallback", async () => {
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({
        temperature_score: 47,
        familiarity_score: 34,
        hint_count: 3,
      }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [
        new Error("deepseek_timeout"),
      ],
      rpc: {
        record_practice_hint: [{
          data: [{ new_hint_count: 4, did_charge: true }],
        }],
      },
    },
    hintBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      turns: [
        { role: "user", text: "安" },
        {
          role: "ai",
          text: "嗨 剛回來還在調時差",
        },
      ],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  assertEquals(json.hintUsedCount, 4);
  assert(String(json.coaching).includes("Game 心法"));
  assert(String(json.coaching).includes("速約任務"));
  const visibleFallback = json.replies
    .map((reply: { text: string }) => reply.text)
    .join("\n");
  assert(visibleFallback.includes("調時差"));
  assert(
    visibleFallback.includes("回血") ||
      visibleFallback.includes("時差歸位") ||
      visibleFallback.includes("這趟"),
  );
  assert(
    visibleFallback.includes("咖啡") ||
      visibleFallback.includes("短") ||
      visibleFallback.includes("下次"),
  );
  assertEquals(visibleFallback.includes("妳說「"), false);
  assertEquals(visibleFallback.includes("我先接住"), false);
  assertEquals(visibleFallback.includes("剛剛那句"), false);
  assertEquals(visibleFallback.includes("妳剛剛那個點"), false);
  assertEquals(visibleFallback.includes("妳剛剛那個反應"), false);
  assertEquals(visibleFallback.includes("這題我先不推進"), false);
  // timeout 代表上游慢：原樣重打大機率再逾時，直接跳 fallback 不做第 2 次。
  assertEquals(state.deepSeekCalls.length, 1);
  assertEquals(state.deepSeekCalls[0].timeoutMs, 9000);
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 0);
});

Deno.test("beginner hint timeout also skips the retry and uses beginner fallback", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      deepSeekReplies: [new Error("deepseek_timeout")],
      rpc: {
        record_practice_hint: [{
          data: [{ new_hint_count: 1, did_charge: true }],
        }],
      },
    },
    hintBody({ practiceMode: "beginner" }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  assertEquals(state.deepSeekCalls.length, 1);
  assertEquals(state.deepSeekCalls[0].timeoutMs, 9000);
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 0);
});

Deno.test("beginner hint fallback answers a hostile latest reply with apology-and-space, not warm-up canned lines", async () => {
  // dogfood 實錄 bug：AI 說「你被封鎖也是剛好而已」，罐頭卻回
  // 「我先接住＋哪一段最有感」被一鍵送出，語境全盲。
  const { response, json } = await run(
    {
      ledger: beginnerStartedLedger({ temperature_score: 10 }),
      deepSeekReplies: [new Error("deepseek_timeout")],
      rpc: {
        record_practice_hint: [{
          data: [{ new_hint_count: 1, did_charge: false }],
        }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      turns: [
        { role: "user", text: "睡了嗎" },
        { role: "ai", text: "（你被封鎖也是剛好而已。不用再傳了。）" },
      ],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  const visibleReplies = json.replies
    .map((reply: { text: string }) => reply.text)
    .join("\n");
  // 道歉降溫＋退一步給空間
  assert(
    visibleReplies.includes("抱歉") || visibleReplies.includes("對不起"),
    visibleReplies,
  );
  assert(
    visibleReplies.includes("不吵妳") || visibleReplies.includes("等妳"),
    visibleReplies,
  );
  // 絕不引用她的敵意原句、絕不殘留暖場教練話術
  assertEquals(visibleReplies.includes("封鎖"), false);
  assertEquals(visibleReplies.includes("我先接住"), false);
  assertEquals(visibleReplies.includes("最有感"), false);
  assertEquals(visibleReplies.includes("好奇"), false);
  // coaching 同步改修復向指導
  assert(String(json.coaching).includes("道歉"), String(json.coaching));
});

Deno.test("hint retry after a non-format provider error carries no misleading JSON-rejected instruction", async () => {
  const { response, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      deepSeekReplies: [new Error("deepseek_http_502"), validHintJson()],
      rpc: {
        record_practice_hint: [{
          data: [{ new_hint_count: 1, did_charge: true }],
        }],
      },
    },
    hintBody({ practiceMode: "beginner" }),
  );

  assertEquals(response.status, 200);
  assertEquals(state.deepSeekCalls.length, 2);
  const retryPrompt = state.deepSeekCalls[1].messages
    .map((message) => message.content)
    .join("\n");
  // 上游 5xx 不是「上一版 JSON 被拒絕」：重試不得夾帶誤導性的格式指令。
  assertEquals(retryPrompt.includes("上一版 Hint JSON 被拒絕"), false);
  assertEquals(retryPrompt.includes("格式或安全規則不合格"), false);
});

Deno.test("game hint retries malformed provider result once before recording", async () => {
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({
        temperature_score: 52,
        familiarity_score: 38,
        hint_count: 2,
      }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [
        "not json",
        validHintJson({
          warmUp: "我先給妳我的版本：舒服的節奏要能讓人笑完還想散步。",
          steady: "我先不急著推，妳剛那個脫口秀點我想聽妳怎麼挑。",
          coaching:
            "Game 心法：測試階段先推框架。速約任務：先給自己的品味，再丟低壓窗口。",
        }),
      ],
      rpc: {
        record_practice_hint: [{
          data: [{ new_hint_count: 3, did_charge: true }],
        }],
      },
    },
    hintBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      turns: [
        { role: "user", text: "妳平常看脫口秀嗎" },
        {
          role: "ai",
          text: "最近看一些脫口秀片段，節奏蠻舒服的，你平常會看這類的嗎",
        },
      ],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.hintUsedCount, 3);
  assertEquals(json.replies[0].text.includes("我先給妳我的版本"), true);
  assertEquals(String(json.coaching).includes("速約任務"), true);
  assertEquals(String(json.coaching).includes("這題我先不推進"), false);
  // LLM 全路徑（handler→parse）也不得放行中文 1.2 原詞「框架」招式語境。
  assertEquals(String(json.coaching).includes("框架"), false);
  assertEquals(String(json.coaching).includes("節奏與主見"), true);
  assertEquals(state.deepSeekCalls.length, 2);
  const retryPrompt = state.deepSeekCalls[1].messages
    .map((message) => message.content)
    .join("\n");
  assert(retryPrompt.includes("上一版 Hint JSON 被拒絕"));
  assert(retryPrompt.includes("重新輸出唯一 JSON"));
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 0);
});

Deno.test("game hint falls back when provider keeps returning malformed JSON", async () => {
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({
        temperature_score: 52,
        familiarity_score: 38,
        hint_count: 2,
      }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: ["not json", "still not json"],
      rpc: {
        record_practice_hint: [{
          data: [{ new_hint_count: 3, did_charge: true }],
        }],
      },
    },
    hintBody({
      practiceMode: "game",
      profileId: "practice_girl_004",
      turns: [
        { role: "user", text: "妳平常看脫口秀嗎" },
        {
          role: "ai",
          text: "最近看一些脫口秀片段，節奏蠻舒服的，你平常會看這類的嗎",
        },
      ],
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  assertEquals(json.hintUsedCount, 3);
  assert(String(json.coaching).includes("Game"));
  assert(String(json.coaching).includes("速約任務"));
  const visibleFallback = json.replies
    .map((reply: { text: string }) => reply.text)
    .join("\n");
  assertEquals(visibleFallback.includes("剛剛那句"), false);
  assertEquals(visibleFallback.includes("妳剛剛那個點"), false);
  assertEquals(visibleFallback.includes("妳剛剛那個反應"), false);
  assertEquals(visibleFallback.includes("這題我先不推進"), false);
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[0].timeoutMs, 9000);
  assertEquals(state.deepSeekCalls[1].timeoutMs, 9000);
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 0);
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

Deno.test("debrief missing replay columns returns not-ready before provider", async () => {
  const { response, json, state } = await run({
    ledgerError:
      "Could not find the 'last_debrief_result' column of 'practice_chat_sessions' in the schema cache",
  }, debriefBody({ requestId: "debrief-replay-not-ready" }));

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_debrief_not_ready" });
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimDebriefCalls(state).length, 0);
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

Deno.test("beginner hint falls back after provider failures without game coaching", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger(),
    deepSeekReplies: [new Error("deepseek down"), new Error("deepseek down")],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 1, did_charge: true }],
      }],
    },
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  assertEquals(json.hintUsedCount, 1);
  assertEquals(String(json.coaching).includes("Game"), false);
  assertEquals(String(json.coaching).includes("速約任務"), false);
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(state.deepSeekCalls[0].timeoutMs, 9000);
  assertEquals(state.deepSeekCalls[1].timeoutMs, 9000);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(commitCalls(state).length, 0);
});

Deno.test("beginner hint falls back when provider keeps returning malformed JSON", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger(),
    deepSeekReplies: ["not json", "still not json"],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 1, did_charge: true }],
      }],
    },
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  assertEquals(json.hintUsedCount, 1);
  assertEquals(String(json.coaching).includes("Game"), false);
  assertEquals(String(json.coaching).includes("速約任務"), false);
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 1);
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
    "rpc:prepare_practice_subscription_usage",
    "rpc:claim_practice_hint_generation",
    "rpc:increment_model_usage",
    "deepseek",
    "deepseek",
    "rpc:record_practice_hint",
    "insert:ai_logs",
  ]);
});

Deno.test("successful hint uses ledger temperature, records after parse, and returns response contract", async () => {
  const { response, json, state } = await run(
    {
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
    },
    hintBody({
      practiceMode: "beginner",
      temperatureScore: 5,
      memorySummary: "OLDER_HINT_MEMORY: 她之前聊過巷口咖啡",
    }),
  );

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
  assertEquals(promptText.includes("OLDER_HINT_MEMORY"), false);

  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(claimHintCalls(state)[0].params, {
    p_user_id: "user-1",
    p_session_id: "session-1",
    p_max_hints: MAX_HINTS_PER_ROUND,
    p_prefetch: false,
    p_generation_token: "generation-token-1",
  });
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(recordHintCalls(state)[0].params, {
    p_user_id: "user-1",
    p_session_id: "session-1",
    p_charge_quota: true,
    p_max_hints: MAX_HINTS_PER_ROUND,
    p_charged: true,
    p_monthly_limit: 300,
    p_daily_limit: 50,
    p_max_replies: MAX_AI_REPLIES,
    p_generation_token: "generation-token-1",
  });
  assertEquals(releaseHintCalls(state).length, 0);
  assertEquals(commitCalls(state).length, 0);
  assertEquals(learningUpdateCalls(state).length, 0);
  assertEquals(state.events, [
    "rpc:prepare_practice_subscription_usage",
    "rpc:claim_practice_hint_generation",
    "rpc:increment_model_usage",
    "deepseek",
    "rpc:record_practice_hint",
    "insert:ai_logs",
  ]);
});

Deno.test("successful hint caps invite maturity with ledger partner mood", async () => {
  const { response, state } = await run({
    ledger: beginnerStartedLedger({
      temperature_score: 90,
      familiarity_score: 90,
      partner_mood: "guarded",
    }),
    deepSeekReplies: [validHintJson()],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 1, did_charge: true }],
      }],
    },
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 200);
  const promptText = state.deepSeekCalls[0].messages.map((m) => m.content)
    .join("\n");
  assert(
    promptText.includes(
      "inviteGuidance(hidden evidence; do not reveal labels)",
    ),
  );
  assertEquals(promptText.includes("direct_invite_ready"), false);
  assertEquals(promptText.includes("partner_window"), false);
  assertEquals(promptText.includes("high_intimacy"), false);
});

Deno.test("successful hint falls back to normal 難度初始溫度 28 when ledger has no score", async () => {
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
  assert(promptText.includes("currentTemperatureScore: 28/100"));
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
  assertEquals(recordHintCalls(state)[0].params.p_charged, true);
});

// ── hint fallback 不扣 quota ────────────────────────────────────────────

Deno.test("hint fallback after provider failures records without charging quota", async () => {
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger(),
    deepSeekReplies: [new Error("deepseek down"), new Error("deepseek down")],
  }, hintBody({ practiceMode: "beginner", requestId: "req-fb" }));

  assertEquals(response.status, 200);
  assertEquals(json.replies.length, 2);
  // LLM 全敗只給罐頭：不扣 quota，但 replay 快照仍要寫（冪等不變）。
  assertEquals(recordHintCalls(state).length, 1);
  const recordParams = recordHintCalls(state)[0].params;
  assertEquals(recordParams.p_charge_quota, false);
  assertEquals(recordParams.p_charged, true);
  assertEquals(recordParams.p_request_id, "req-fb");
  const storedPayload = recordParams.p_result as Record<string, unknown>;
  assertEquals(storedPayload.costDeducted, 0);
  assertEquals(storedPayload.monthlyRemaining, 290);
  assertEquals(storedPayload.dailyRemaining, 48);
  assertEquals(json.costDeducted, 0);
  assertEquals(json.monthlyRemaining, 290);
  assertEquals(json.dailyRemaining, 48);
});

Deno.test("game hint timeout fallback records without charging quota", async () => {
  const { response, json, state } = await run(
    {
      ledger: gameStartedLedger({ hint_count: 1 }),
      drawEvents: [{ profile_id: "practice_girl_004" }],
      deepSeekReplies: [new Error("deepseek_timeout")],
      rpc: {
        record_practice_hint: [{
          data: [{ new_hint_count: 2, did_charge: false }],
        }],
      },
    },
    hintBody({ practiceMode: "game", profileId: "practice_girl_004" }),
  );

  assertEquals(response.status, 200);
  assertEquals(recordHintCalls(state)[0].params.p_charge_quota, false);
  assertEquals(recordHintCalls(state)[0].params.p_charged, true);
  assertEquals(json.costDeducted, 0);
});

Deno.test("hint fallback for test accounts also records without charging quota", async () => {
  const { response, json, state } = await run({
    user: { id: "user-1", email: "vibesync.test@gmail.com" },
    ledger: beginnerStartedLedger(),
    deepSeekReplies: [new Error("deepseek down"), new Error("deepseek down")],
    rpc: {
      record_practice_hint: [{
        data: [{ new_hint_count: 1, did_charge: false }],
      }],
    },
  }, hintBody({ practiceMode: "beginner" }));

  assertEquals(response.status, 200);
  assertEquals(recordHintCalls(state)[0].params.p_charge_quota, false);
  assertEquals(recordHintCalls(state)[0].params.p_charged, true);
  assertEquals(json.costDeducted, 0);
});

Deno.test("hint requestId replay of a fallback snapshot does not charge again", async () => {
  const stored = {
    replies: [
      { type: "warm_up", text: "罐頭 warm up" },
      { type: "steady", text: "罐頭 steady" },
    ],
    coaching: "罐頭 coaching",
    costDeducted: 0,
    hintUsedCount: 1,
    provider: "deepseek",
    model: DEEPSEEK_MODEL,
    generatedAt: NOW.toISOString(),
    monthlyRemaining: 290,
    dailyRemaining: 48,
  };
  const { response, json, state } = await run({
    ledger: beginnerStartedLedger(),
    hintRequest: {
      state: "settled",
      charged: true,
      is_prefetch: false,
      claimed_ai_count: 1,
      result: stored,
    },
  }, hintBody({ practiceMode: "beginner", requestId: "req-fb-replay" }));

  assertEquals(response.status, 200);
  assertEquals(json, stored);
  assertEquals(json.costDeducted, 0);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordHintCalls(state).length, 0);
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

for (
  const [mode, options, bodyOverrides] of [
    [
      "beginner",
      { ledger: beginnerStartedLedger() },
      { practiceMode: "beginner" },
    ],
    [
      "game",
      {
        ledger: gameStartedLedger(),
        drawEvents: [{ profile_id: "practice_girl_004" }],
      },
      { practiceMode: "game", profileId: "practice_girl_004" },
    ],
  ] as const
) {
  Deno.test(`${mode} Hint prefetch stores an uncharged snapshot and returns only opaque ack`, async () => {
    const requestId = `prefetch-${mode}`;
    const { response, json, state } = await run(
      {
        ...options,
        env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
        deepSeekReplies: [validHintJson()],
      },
      hintBody({
        ...bodyOverrides,
        requestId,
        prefetch: true,
        expectedAiCount: 1,
      }),
    );

    assertEquals(response.status, 200);
    assertEquals(json, { prefetched: true });
    assertEquals(Object.keys(json), ["prefetched"]);
    assertEquals(state.deepSeekCalls.length, 1);
    assertEquals(hintModelRateCalls(state).length, 1);
    assertEquals(claimHintCalls(state).length, 1);
    assertEquals(claimHintCalls(state)[0].params.p_request_id, requestId);
    assertEquals(claimHintCalls(state)[0].params.p_prefetch, true);
    assertEquals(claimHintCalls(state)[0].params.p_expected_ai_count, 1);
    assertEquals(
      claimHintCalls(state)[0].params.p_generation_token,
      "generation-token-1",
    );
    assertEquals(recordHintCalls(state).length, 1);
    const params = recordHintCalls(state)[0].params;
    assertEquals(params.p_request_id, requestId);
    assertEquals(params.p_charge_quota, false);
    assertEquals(params.p_charged, false);
    assertEquals(params.p_generation_token, "generation-token-1");
    assertEquals(params.p_max_replies, MAX_AI_REPLIES);
    assertEquals(
      (params.p_result as Record<string, unknown>).hintUsedCount,
      0,
    );
    assertEquals(settleHintCalls(state).length, 0);
    assertEquals(releaseHintCalls(state).length, 0);
  });
}

for (
  const [name, options, bodyOverrides, expectedAttempts] of [
    [
      "beginner provider failures",
      {
        ledger: beginnerStartedLedger(),
        deepSeekReplies: [
          new Error("deepseek down"),
          new Error("deepseek down"),
        ],
      },
      { practiceMode: "beginner" },
      2,
    ],
    [
      "game timeout",
      {
        ledger: gameStartedLedger(),
        drawEvents: [{ profile_id: "practice_girl_004" }],
        deepSeekReplies: [new Error("deepseek_timeout")],
      },
      { practiceMode: "game", profileId: "practice_girl_004" },
      1,
    ],
  ] as const
) {
  Deno.test(`Hint prefetch ${name} releases ownership without recording fallback`, async () => {
    const requestId = `prefetch-failure-${expectedAttempts}`;
    const { response, json, state } = await run(
      {
        ...options,
        env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
      },
      hintBody({
        ...bodyOverrides,
        requestId,
        prefetch: true,
      }),
    );

    assertEquals(response.status, 503);
    assertEquals(json, { error: "practice_hint_prefetch_failed" });
    assertEquals(state.deepSeekCalls.length, expectedAttempts);
    assertEquals(recordHintCalls(state).length, 0);
    assertEquals(settleHintCalls(state).length, 0);
    assertEquals(releaseHintCalls(state).length, 1);
    assertEquals(releaseHintCalls(state)[0].params, {
      p_user_id: "user-1",
      p_session_id: "session-1",
      p_request_id: requestId,
      p_generation_token: "generation-token-1",
    });
    assertEquals(aiLogInserts(state).length, 0);
  });
}

Deno.test("Hint prefetch malformed output never records the formal fallback", async () => {
  const { response, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
      deepSeekReplies: ["not json", "still not json"],
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "prefetch-malformed",
      prefetch: true,
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(state.deepSeekCalls.length, 2);
  assertEquals(recordHintCalls(state).length, 0);
  assertEquals(releaseHintCalls(state).length, 1);
});

Deno.test("disabled Hint prefetch stops before claim, rate limit, and provider", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "false" },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "prefetch-disabled",
      prefetch: true,
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_hint_prefetch_disabled" });
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(hintModelRateCalls(state).length, 0);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("missing subscription prepare RPC returns Hint not-ready rollout guard", async () => {
  const { response, json, state } = await run(
    {
      subError:
        "Could not find the function public.prepare_practice_subscription_usage(p_user_id) in the schema cache",
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "prepare-not-ready",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_hint_not_ready" });
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(state.deepSeekCalls.length, 0);
});

Deno.test("fresh Hint rejects a stale client turn before claim or provider work", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger({ ai_count: 2 }),
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "fresh-stale-client-turn",
      expectedAiCount: 1,
      prefetch: false,
    }),
  );

  assertEquals(response.status, 409);
  assertEquals(json, { error: "practice_hint_stale" });
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(hintModelRateCalls(state).length, 0);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("settled Hint replay wins over a stale client turn version", async () => {
  const stored = storedHintResult({ hintUsedCount: 1 });
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger({ ai_count: 2, hint_count: 1 }),
      hintRequest: {
        state: "settled",
        charged: true,
        is_prefetch: false,
        claimed_ai_count: 1,
        result: stored,
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "settled-stale-client-turn",
      expectedAiCount: 1,
      prefetch: false,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json, stored);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(settleHintCalls(state).length, 0);
  assertEquals(state.deepSeekCalls.length, 0);
});

Deno.test("formal Hint consumes an exact prefetched snapshot through settle only", async () => {
  const prefetched = storedHintResult({
    costDeducted: 0,
    hintUsedCount: 1,
    monthlyRemaining: 290,
    dailyRemaining: 48,
  });
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger({ hint_count: 1 }),
      hintRequest: {
        state: "prefetched",
        charged: false,
        is_prefetch: true,
        claimed_ai_count: 1,
        result: prefetched,
      },
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "prefetched-formal",
      expectedAiCount: 1,
      prefetch: false,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.costDeducted, 1);
  assertEquals(json.hintUsedCount, 2);
  assertEquals(json.coaching, prefetched.coaching);
  assertEquals(settleHintCalls(state).length, 1);
  assertEquals(settleHintCalls(state)[0].params.p_charge_quota, true);
  assertEquals(settleHintCalls(state)[0].params.p_expected_ai_count, 1);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(hintModelRateCalls(state).length, 0);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("test account consumes prefetched Hint without charging but still increments count", async () => {
  const prefetched = storedHintResult({
    costDeducted: 0,
    hintUsedCount: 1,
    monthlyRemaining: 290,
    dailyRemaining: 48,
  });
  const { response, json, state } = await run(
    {
      user: { id: "user-1", email: "vibesync.test@gmail.com" },
      ledger: beginnerStartedLedger({ hint_count: 1 }),
      hintRequest: {
        state: "prefetched",
        charged: false,
        is_prefetch: true,
        claimed_ai_count: 1,
        result: prefetched,
      },
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "prefetched-formal-test-account",
      expectedAiCount: 1,
      prefetch: false,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.costDeducted, 0);
  assertEquals(json.hintUsedCount, 2);
  assertEquals(json.monthlyRemaining, 290);
  assertEquals(json.dailyRemaining, 48);
  assertEquals(settleHintCalls(state).length, 1);
  assertEquals(settleHintCalls(state)[0].params.p_charge_quota, false);
  assertEquals(settleHintCalls(state)[0].params.p_expected_ai_count, 1);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(hintModelRateCalls(state).length, 0);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("formal Hint fails closed on an unconfirmed settle response", async () => {
  const prefetched = storedHintResult({ costDeducted: 0, hintUsedCount: 0 });
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      hintRequest: {
        state: "prefetched",
        charged: false,
        is_prefetch: true,
        claimed_ai_count: 1,
        result: prefetched,
      },
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
      rpc: {
        settle_prefetched_practice_hint: [{
          data: {
            new_hint_count: 1,
            did_charge: false,
            stored_result: prefetched,
            stored_charged: false,
          },
        }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "settle-unconfirmed",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_hint_not_ready" });
  assertEquals(settleHintCalls(state).length, 1);
  assertEquals(json.replies, undefined);
});

for (
  const [rpcError, expectedStatus, expectedError] of [
    ["QUOTA_EXCEEDED_DAILY", 429, "Daily limit exceeded"],
    ["PRACTICE_SESSION_COMPLETE", 409, "practice_session_complete"],
  ] as const
) {
  Deno.test(`prefetched Hint settle maps ${rpcError} without exposing content`, async () => {
    const prefetched = storedHintResult({ costDeducted: 0, hintUsedCount: 0 });
    const { response, json, state } = await run(
      {
        ledger: beginnerStartedLedger(),
        hintRequest: {
          state: "prefetched",
          charged: false,
          is_prefetch: true,
          claimed_ai_count: 1,
          result: prefetched,
        },
        env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
        rpc: {
          settle_prefetched_practice_hint: [{ error: rpcError }],
        },
      },
      hintBody({
        practiceMode: "beginner",
        requestId: `settle-${expectedStatus}`,
        prefetch: false,
      }),
    );

    assertEquals(response.status, expectedStatus);
    assertEquals(json.error, expectedError);
    assertEquals(json.replies, undefined);
    assertEquals(settleHintCalls(state).length, 1);
    assertEquals(claimHintCalls(state).length, 0);
    assertEquals(state.deepSeekCalls.length, 0);
    assertEquals(recordHintCalls(state).length, 0);
  });
}

for (
  const [stateName, charged] of [
    ["prefetched", false],
    ["settled", true],
  ] as const
) {
  Deno.test(`prefetch retry of ${stateName} request returns opaque ack without side effects`, async () => {
    const { response, json, state } = await run(
      {
        ledger: beginnerStartedLedger(),
        hintRequest: {
          state: stateName,
          charged,
          is_prefetch: true,
          claimed_ai_count: 1,
          result: storedHintResult({ costDeducted: charged ? 1 : 0 }),
        },
        env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
      },
      hintBody({
        practiceMode: "beginner",
        requestId: `prefetch-retry-${stateName}`,
        prefetch: true,
      }),
    );

    assertEquals(response.status, 200);
    assertEquals(json, { prefetched: true });
    assertEquals(Object.keys(json), ["prefetched"]);
    assertEquals(settleHintCalls(state).length, 0);
    assertEquals(claimHintCalls(state).length, 0);
    assertEquals(hintModelRateCalls(state).length, 0);
    assertEquals(state.deepSeekCalls.length, 0);
    assertEquals(recordHintCalls(state).length, 0);
  });
}

Deno.test("claim-level uncharged replay settles without consuming model rate", async () => {
  const prefetched = storedHintResult({ costDeducted: 0, hintUsedCount: 0 });
  const finalized = storedHintResult({ hintUsedCount: 1 });
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
      rpc: {
        claim_practice_hint_generation: [{
          data: {
            current_hint_count: 0,
            replay: true,
            stored_result: prefetched,
            stored_charged: false,
          },
        }],
        settle_prefetched_practice_hint: [{
          data: {
            new_hint_count: 1,
            did_charge: true,
            stored_result: finalized,
            stored_charged: true,
          },
        }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "claim-race-prefetched",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json, finalized);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(settleHintCalls(state).length, 1);
  assertEquals(hintModelRateCalls(state).length, 0);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("model rate limit after fresh prefetch claim releases exact owner", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
      rpc: {
        increment_model_usage: [{ error: "MODEL_RATE_LIMITED_MINUTE" }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "prefetch-rate-limited",
      prefetch: true,
    }),
  );

  assertEquals(response.status, 429);
  assertEquals(json.code, "MODEL_RATE_LIMITED");
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(hintModelRateCalls(state).length, 1);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordHintCalls(state).length, 0);
  assertEquals(releaseHintCalls(state).length, 1);
  assertEquals(
    releaseHintCalls(state)[0].params.p_request_id,
    "prefetch-rate-limited",
  );
  assertEquals(
    releaseHintCalls(state)[0].params.p_generation_token,
    "generation-token-1",
  );
  assert(
    state.events.indexOf("rpc:claim_practice_hint_generation") <
      state.events.indexOf("rpc:increment_model_usage"),
  );
});

Deno.test("record quota race returns 429 and releases the exact formal owner", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      deepSeekReplies: [validHintJson()],
      rpc: {
        record_practice_hint: [{ error: "QUOTA_EXCEEDED_MONTHLY" }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "formal-quota-race",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 429);
  assertEquals(json.error, "Monthly limit exceeded");
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 1);
  assertEquals(
    releaseHintCalls(state)[0].params.p_request_id,
    "formal-quota-race",
  );
  assertEquals(json.replies, undefined);
});

Deno.test("flag-off formal request discards its pending row before fresh generation", async () => {
  const { response, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      hintRequest: {
        state: "generating",
        charged: false,
        is_prefetch: true,
        claimed_ai_count: 1,
        result: null,
      },
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "false" },
      deepSeekReplies: [validHintJson()],
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "flag-off-pending",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(discardHintCalls(state).length, 1);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(state.deepSeekCalls.length, 1);
  assertEquals(recordHintCalls(state).length, 1);
  assert(
    state.events.indexOf("rpc:discard_prefetched_practice_hint") <
      state.events.indexOf("rpc:claim_practice_hint_generation"),
  );
});

Deno.test("flag-off formal retry never discards a formal generating owner", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      hintRequest: {
        state: "generating",
        charged: false,
        is_prefetch: false,
        claimed_ai_count: 1,
        result: null,
      },
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "false" },
      rpc: {
        claim_practice_hint_generation: [{
          error: "PRACTICE_HINT_IN_FLIGHT",
        }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "formal-owner",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(json, { error: "practice_hint_in_flight" });
  assertEquals(discardHintCalls(state).length, 0);
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("flag-off discard race replays an already-settled result", async () => {
  const stored = storedHintResult({ hintUsedCount: 1 });
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      hintRequest: {
        state: "generating",
        charged: false,
        is_prefetch: true,
        claimed_ai_count: 1,
        result: null,
      },
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "false" },
      rpc: {
        discard_prefetched_practice_hint: [{
          data: {
            discarded: false,
            replay: true,
            stored_result: stored,
            stored_charged: true,
          },
        }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "flag-off-race",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json, stored);
  assertEquals(discardHintCalls(state).length, 1);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("a second prefetch maps current pending snapshot without provider work", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      env: { PRACTICE_HINT_PREFETCH_ENABLED: "true" },
      rpc: {
        claim_practice_hint_generation: [{
          error: "PRACTICE_HINT_PREFETCH_PENDING",
        }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "second-prefetch",
      prefetch: true,
    }),
  );

  assertEquals(response.status, 409);
  assertEquals(json, { error: "practice_hint_prefetch_pending" });
  assertEquals(claimHintCalls(state).length, 1);
  assertEquals(hintModelRateCalls(state).length, 0);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("malformed fresh claim response releases the fenced request owner", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      rpc: {
        claim_practice_hint_generation: [{ data: { unexpected: true } }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "malformed-claim",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_hint_not_ready" });
  assertEquals(releaseHintCalls(state).length, 1);
  assertEquals(
    releaseHintCalls(state)[0].params.p_request_id,
    "malformed-claim",
  );
  assertEquals(
    releaseHintCalls(state)[0].params.p_generation_token,
    "generation-token-1",
  );
  assertEquals(state.deepSeekCalls.length, 0);
});

Deno.test("Hint request ledger schema failure is fail-closed before claim", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      hintRequestError:
        "Could not find the table public.practice_hint_requests in the schema cache",
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "missing-request-ledger",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(json, { error: "practice_hint_not_ready" });
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(state.deepSeekCalls.length, 0);
});

Deno.test("stale formal record releases only its token and returns retryable conflict", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger(),
      deepSeekReplies: [validHintJson()],
      rpc: {
        record_practice_hint: [{ error: "PRACTICE_HINT_STALE" }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "stale-formal",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 409);
  assertEquals(json, { error: "practice_hint_stale" });
  assertEquals(recordHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state).length, 1);
  assertEquals(releaseHintCalls(state)[0].params, {
    p_user_id: "user-1",
    p_session_id: "session-1",
    p_request_id: "stale-formal",
    p_generation_token: "generation-token-1",
  });
});

Deno.test("formal request returns the authoritative first-writer Hint snapshot", async () => {
  const authoritative = storedHintResult({
    coaching: "first writer won",
    hintUsedCount: 4,
  });
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger({ hint_count: 3 }),
      deepSeekReplies: [validHintJson({ coaching: "losing worker" })],
      rpc: {
        record_practice_hint: [{
          data: {
            new_hint_count: 4,
            did_charge: false,
            stored_result: authoritative,
            stored_charged: true,
          },
        }],
      },
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "first-writer",
      prefetch: false,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(json, authoritative);
  assertEquals(json.coaching, "first writer won");
  assertEquals(recordHintCalls(state).length, 1);
});

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
    ledger: beginnerStartedLedger(),
    hintRequest: {
      state: "settled",
      charged: true,
      is_prefetch: false,
      claimed_ai_count: 1,
      result: stored,
    },
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
    }),
    hintRequest: {
      state: "settled",
      charged: true,
      is_prefetch: false,
      claimed_ai_count: MAX_AI_REPLIES,
      result: stored,
    },
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
    ledger: beginnerStartedLedger(),
    hintRequest: {
      state: "settled",
      charged: true,
      is_prefetch: false,
      claimed_ai_count: 1,
      result: stored,
    },
  }, hintBody({ practiceMode: "beginner", requestId: "req-quota" }));

  assertEquals(response.status, 200);
  assertEquals(json, stored);
  assertEquals(state.deepSeekCalls.length, 0);
  assertEquals(claimHintCalls(state).length, 0);
  assertEquals(recordHintCalls(state).length, 0);
});

Deno.test("hint with a fresh requestId generates normally and threads the id into claim and record", async () => {
  const { response, json, state } = await run(
    {
      ledger: beginnerStartedLedger({
        last_hint_request_id: "req-old",
        last_hint_result: storedHintResult(),
      }),
      deepSeekReplies: [validHintJson()],
    },
    hintBody({
      practiceMode: "beginner",
      requestId: "req-new",
      expectedAiCount: 1,
      prefetch: false,
    }),
  );

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
    p_prefetch: false,
    p_generation_token: "generation-token-1",
    p_expected_ai_count: 1,
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
        data: [{
          current_hint_count: 3,
          replay: true,
          stored_result: stored,
          stored_charged: true,
        }],
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
    p_prefetch: false,
    p_generation_token: "generation-token-1",
  });
  assertEquals(recordHintCalls(state)[0].params, {
    p_user_id: "user-1",
    p_session_id: "session-1",
    p_charge_quota: true,
    p_max_hints: MAX_HINTS_PER_ROUND,
    p_charged: true,
    p_monthly_limit: 300,
    p_daily_limit: 50,
    p_max_replies: MAX_AI_REPLIES,
    p_generation_token: "generation-token-1",
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

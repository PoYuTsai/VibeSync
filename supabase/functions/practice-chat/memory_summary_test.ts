// Phase 5 WP3 續聊敘事記憶：`PRACTICE_MEMORY_SUMMARY_WRITE` 旗標的兩面契約。
//
// off（未設／任何非 `true` 值）＝**一個位元組都不改**：debrief 的 system prompt
// 與 tool schema 逐字不變、不多帶 `p_memory_summary`、Response 不多欄位、
// telemetry 不多 key。旗標無關的四面等價由既有的
// `agency_flag_off_equivalence_test.ts` 一起守（那支跑的時候本旗標未設）。
//
// on ＝檢討那支 Sonnet 多吐一段「她記得的事」寫回
// `practice_relationship_threads.memory_summary`；**它永遠不能讓檢討失敗**，
// 缺欄／型別不對／超長只跳過寫入並記 telemetry。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  chatBody,
  debriefBody,
  type FakeOptions,
  type FakeState,
  ledger,
  run,
  validDebriefJson,
} from "./handler_test_fake.ts";
import { buildDebriefMessages } from "./prompt.ts";
import {
  DEBRIEF_MEMORY_SUMMARY_MAX_CHARS,
  DEBRIEF_TOOL_SCHEMA,
  debriefToolSchemaFor,
  parseDebriefMemorySummary,
} from "./debrief_card.ts";
import { resolvePracticeProfile } from "./practice_persona.ts";

const PROFILE_ID = "practice_girl_004";

const profile = resolvePracticeProfile({ profileId: PROFILE_ID });

const turns = [
  { role: "user" as const, text: "今天忙到剛下班" },
  { role: "ai" as const, text: "我也剛下班，只想散步放空" },
];

function threadUpsertCalls(state: FakeState) {
  return state.rpcCalls.filter((call) =>
    call.fn === "upsert_practice_relationship_thread"
  );
}

/** 檢討成功那一行 telemetry（`practice_chat_succeeded` ＋ mode debrief）。 */
async function runDebrief(options: FakeOptions, body: unknown) {
  const logs: Record<string, unknown>[] = [];
  const warns: Record<string, unknown>[] = [];
  const collect = (into: Record<string, unknown>[]) => (...args: unknown[]) => {
    if (typeof args[0] === "string" && args[0].startsWith("{")) {
      try {
        into.push(JSON.parse(args[0]));
      } catch {
        // 非 JSON 行忽略。
      }
    }
  };
  const originalLog = console.log;
  const originalWarn = console.warn;
  console.log = collect(logs);
  console.warn = collect(warns);
  try {
    const result = await run(options, body);
    const succeeded = logs.find((line) =>
      line.event === "practice_chat_succeeded" && line.mode === "debrief"
    );
    return { ...result, succeeded, warns };
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
  }
}

function debriefOptions(
  overrides: Partial<FakeOptions> = {},
): FakeOptions {
  return {
    ledger: ledger({ ai_count: 4, charged: true }),
    thread: {
      profile_id: PROFILE_ID,
      memory_summary: null,
      partner_mood: "neutral",
      partner_inner_thought: "",
      practice_mode: "standard",
      relationship_score: 51,
      temperature_score: 42,
      familiarity_score: 33,
      recent_facts: { source: "practice_chat", aiTurnCount: 4, keepMe: 1 },
    },
    claudeReplies: [validDebriefJson()],
    ...overrides,
  };
}

const HER_MEMORY =
  "他說今天忙到剛下班，她提到只想散步放空，兩人還沒約定下次見面。";

Deno.test("WP3 旗標 off：debrief system prompt 與 tool schema 逐位元組不變", () => {
  const base = buildDebriefMessages(turns, profile, {});
  assertEquals(
    buildDebriefMessages(turns, profile, { memorySummaryWrite: false }),
    base,
  );
  assertEquals(base[0].content.includes("memorySummary（選填"), false);

  const schema = debriefToolSchemaFor({ game: false });
  assertEquals(schema, DEBRIEF_TOOL_SCHEMA as Record<string, unknown>);
  assertEquals(
    "memorySummary" in (schema.properties as Record<string, unknown>),
    false,
  );
});

Deno.test("WP3 旗標 on：debrief system prompt 有欄位說明與不捏造規則，schema 多一個選填欄位", () => {
  const messages = buildDebriefMessages(turns, profile, {
    memorySummaryWrite: true,
  });
  const system = messages[0].content;
  assert(system.includes("memorySummary（選填"));
  assert(system.includes("她記得的事"));
  assert(system.includes("Reality Anchoring"));
  assert(system.includes("不得捏造"));
  // 檢討本文的欄位一個都沒少。
  assert(system.includes('"suggestedLine"'));

  const schema = debriefToolSchemaFor({ game: true, memorySummary: true });
  const properties = schema.properties as Record<string, unknown>;
  assert("memorySummary" in properties);
  assertEquals(
    (properties.memorySummary as Record<string, unknown>).maxLength,
    DEBRIEF_MEMORY_SUMMARY_MAX_CHARS,
  );
  // 選填：required 名單與 Game 變體逐字相同。
  assertEquals(
    schema.required,
    debriefToolSchemaFor({ game: true }).required,
  );
});

Deno.test("WP3 parseDebriefMemorySummary：缺欄／型別／超長都只跳過，不丟例外", () => {
  assertEquals(
    parseDebriefMemorySummary(validDebriefJson({ memorySummary: HER_MEMORY })),
    { summary: HER_MEMORY, skipped: null },
  );
  assertEquals(parseDebriefMemorySummary(validDebriefJson()), {
    summary: null,
    skipped: "missing",
  });
  assertEquals(
    parseDebriefMemorySummary(validDebriefJson({ memorySummary: "   " })),
    { summary: null, skipped: "missing" },
  );
  assertEquals(
    parseDebriefMemorySummary(validDebriefJson({ memorySummary: 12 })),
    { summary: null, skipped: "not_string" },
  );
  assertEquals(
    parseDebriefMemorySummary(
      validDebriefJson({
        memorySummary: "記".repeat(DEBRIEF_MEMORY_SUMMARY_MAX_CHARS + 1),
      }),
    ),
    { summary: null, skipped: "too_long" },
  );
  assertEquals(parseDebriefMemorySummary("not json at all"), {
    summary: null,
    skipped: "missing",
  });
});

Deno.test("WP3 旗標 on：模型吐 memorySummary → 帶 p_memory_summary 寫回、Response 帶、telemetry 記字數", async () => {
  const { response, json, state, succeeded } = await runDebrief(
    debriefOptions({
      env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
      claudeReplies: [validDebriefJson({ memorySummary: HER_MEMORY })],
    }),
    debriefBody({ requestId: "wp3-write", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  const upserts = threadUpsertCalls(state);
  assertEquals(upserts.length, 1);
  assertEquals(upserts[0].params.p_memory_summary, HER_MEMORY);
  // `= EXCLUDED` 的四欄與整包覆寫的 recent_facts 必須原樣帶回，
  // 不然這一發會把 thread 上別的狀態清掉。
  assertEquals(upserts[0].params.p_practice_mode, "standard");
  assertEquals(upserts[0].params.p_relationship_score, 51);
  assertEquals(upserts[0].params.p_temperature_score, 42);
  assertEquals(upserts[0].params.p_familiarity_score, 33);
  assertEquals(upserts[0].params.p_recent_facts, {
    source: "practice_chat",
    aiTurnCount: 4,
    keepMe: 1,
  });

  assertEquals(json.memorySummary, HER_MEMORY);
  assertEquals(succeeded?.memorySummaryChars, HER_MEMORY.length);
  assertEquals("memorySummarySkipped" in (succeeded ?? {}), false);
});

Deno.test("WP3 旗標 on：模型沒吐欄位 → 不寫入、telemetry 記 missing、檢討照樣 200", async () => {
  const { response, json, state, succeeded } = await runDebrief(
    debriefOptions({ env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" } }),
    debriefBody({ requestId: "wp3-missing", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  assertEquals(threadUpsertCalls(state).length, 0);
  assertEquals("memorySummary" in json, false);
  assertEquals(succeeded?.memorySummaryChars, 0);
  assertEquals(succeeded?.memorySummarySkipped, "missing");
  assertEquals(
    json.card.summary,
    "你說今天忙到剛下班，她接著分享只想散步放空。",
  );
});

Deno.test("WP3 旗標 on：超長 → 不截斷不寫入，telemetry 記 too_long", async () => {
  const { response, state, succeeded } = await runDebrief(
    debriefOptions({
      env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
      claudeReplies: [
        validDebriefJson({
          memorySummary: "記".repeat(DEBRIEF_MEMORY_SUMMARY_MAX_CHARS + 1),
        }),
      ],
    }),
    debriefBody({ requestId: "wp3-too-long", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  assertEquals(threadUpsertCalls(state).length, 0);
  assertEquals(succeeded?.memorySummarySkipped, "too_long");
});

Deno.test("WP3 旗標 on：寫回 RPC 失敗只 warn，檢討照樣 200", async () => {
  const { response, json, warns } = await runDebrief(
    debriefOptions({
      env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
      claudeReplies: [validDebriefJson({ memorySummary: HER_MEMORY })],
      rpc: {
        upsert_practice_relationship_thread: [{ error: "thread write boom" }],
      },
    }),
    debriefBody({ requestId: "wp3-rpc-fail", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.memorySummary, HER_MEMORY);
  assert(
    warns.some((line) =>
      line.event === "practice_relationship_thread_upsert_failed"
    ),
  );
});

Deno.test("WP3 旗標 off：模型就算吐了欄位也不寫、不回、不記", async () => {
  const { response, json, state, succeeded } = await runDebrief(
    debriefOptions({
      claudeReplies: [validDebriefJson({ memorySummary: HER_MEMORY })],
    }),
    debriefBody({ requestId: "wp3-off", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  assertEquals(threadUpsertCalls(state).length, 0);
  assertEquals("memorySummary" in json, false);
  assertEquals("memorySummaryChars" in (succeeded ?? {}), false);
  assertEquals("memorySummarySkipped" in (succeeded ?? {}), false);
  // schema 也不能多欄位（模型看不到這個欄位才是旗標 off 的真正契約）。
  const schema = state.claudeCalls[0].forcedTool?.inputSchema as Record<
    string,
    unknown
  >;
  assertEquals(
    "memorySummary" in (schema.properties as Record<string, unknown>),
    false,
  );
});

Deno.test("WP3 下一場：thread 上的 memory_summary 走既有 chat prompt 路徑（零改動）", async () => {
  const { response, state } = await run(
    debriefOptions({
      thread: {
        profile_id: PROFILE_ID,
        memory_summary: HER_MEMORY,
        partner_mood: "neutral",
        partner_inner_thought: "",
      },
      claudeReplies: undefined,
      deepSeekReplies: ["AI reply", "not json"],
    }),
    chatBody({ profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  const system = state.deepSeekCalls[0].messages[0].content;
  assert(
    system.includes(
      `<older_memory_untrusted>\n${HER_MEMORY}\n</older_memory_untrusted>`,
    ),
  );
});

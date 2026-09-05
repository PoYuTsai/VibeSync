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
//
// ── 已知風險：捏造會被持久化（Eric 2026-09-05 判定接受）─────────────────
// 本檔**沒有**、也刻意不加事實核對測試：server 只驗形態，不驗內容。模型若在
// memorySummary 裡捏造這場沒發生的事，會被寫進 thread 並在下一場當成「更早的
// 對話」餵回去。沒有便宜的決定論核對法（人名／事件比對會誤殺真的講過的內容），
// 所以防線在**讀取端**：`prompt.ts:133` 的 `memorySummaryPrompt` 把它包成
// `<older_memory_untrusted>` 並附 Reality Anchoring 未驗證清單
// （`prompt.ts:121` / `prompt.ts:130` 兩份 tail），生成端規則在
// `DEBRIEF_MEMORY_SUMMARY_DIRECTIVE`。最後一支測試守讀取端那個信封格式。
//
// ── 已接受、不修的兩件事（Eric 2026-09-05 對 Codex R2 的裁決）──────────
// 1. 不走整列 upsert、UPDATE 不建列：thread 列一定在第一輪聊天就由既有路徑建好
//    （beginner／game 的 inviteMaturity 那條與 standard 分類器那條，production
//    兩支旗標都開），而檢討必在聊天之後；真的命中 0 列會記
//    `memorySummarySkipped: "thread_missing"`，是可觀測的。
// 2. 同一場兩次檢討反序完成＝last-writer-wins：一場實務上只檢討一次，接受。
//
// ── 寫回為什麼是單欄 UPDATE 不是 upsert RPC（Codex R1 P1）───────────────
// 檢討是長跑請求：它在請求開頭讀到的 thread 快照，寫回時可能已被同一個 thread
// 的聊天輪次更新過。走 `upsert_practice_relationship_thread` 會把讀取時的
// mode／分數／心情／整包 recent_facts 一起帶回去覆寫。改成只 UPDATE
// `memory_summary` 一欄、WHERE 綁 user_id ＋ visible_thread_id ＋ profile_id。

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

function threadMemoryUpdates(state: FakeState) {
  return state.updates.filter((update) =>
    update.table === "practice_relationship_threads"
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
  // 專有名詞（名字／寵物／職業）要優先照原字記（9/6 實測摘要漏掉「豆豆」）。
  assert(system.includes("寵物"));
  assert(system.includes("職業"));
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

Deno.test("WP3 長度用碼點算（Codex R1 P2）：501 個 emoji 過，1001 個不過", () => {
  const under = "🙂".repeat(501);
  // `.length` 是 UTF-16 code unit：這一串是 1002，碼點只有 501。
  assertEquals(under.length, 1002);
  assertEquals(
    parseDebriefMemorySummary(validDebriefJson({ memorySummary: under })),
    { summary: under, skipped: null },
  );
  assertEquals(
    parseDebriefMemorySummary(
      validDebriefJson({
        memorySummary: "🙂".repeat(DEBRIEF_MEMORY_SUMMARY_MAX_CHARS + 1),
      }),
    ),
    { summary: null, skipped: "too_long" },
  );
});

Deno.test("WP3 旗標 on：模型吐 memorySummary → 只 UPDATE 一欄、WHERE 綁三欄、Response 帶、telemetry 記碼點數", async () => {
  const { response, json, state, succeeded } = await runDebrief(
    debriefOptions({
      env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
      claudeReplies: [validDebriefJson({ memorySummary: HER_MEMORY })],
    }),
    debriefBody({ requestId: "wp3-write", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  // 並發覆蓋（Codex R1 P1）：不得走整列覆寫的 upsert RPC。
  assertEquals(threadUpsertCalls(state).length, 0);
  const updates = threadMemoryUpdates(state);
  assertEquals(updates.length, 1);
  // payload 只有一個 key：讀取時的 mode／分數／心情／recent_facts 一個都不帶回，
  // 所以檢討跑的期間聊天輪次寫進去的新值不會被蓋掉。
  assertEquals(Object.keys(updates[0].values), ["memory_summary"]);
  assertEquals(updates[0].values.memory_summary, HER_MEMORY);
  assertEquals(updates[0].where, [
    ["user_id", "user-1"],
    ["visible_thread_id", "session-1"],
    ["profile_id", PROFILE_ID],
  ]);

  assertEquals(json.memorySummary, HER_MEMORY);
  assertEquals(succeeded?.memorySummaryChars, [...HER_MEMORY].length);
  assertEquals("memorySummarySkipped" in (succeeded ?? {}), false);
});

Deno.test("WP3 並發（Codex R1 P1）：檢討讀到 A，寫回不得把 A 的任何欄位帶回去蓋掉聊天寫的 B", async () => {
  // 檢討在請求開頭讀到的是 A（下面 thread 的分數／心情／recent_facts）。
  // 它跑 Sonnet 的期間，同一個 thread 的聊天輪次可能已經把那些欄位寫成 B。
  // 只要寫回的 payload 不含這些欄位，B 就活得下來——所以這裡直接斷言
  // 「A 的每一個欄位名都不在 payload 裡」。
  const { response, state } = await runDebrief(
    debriefOptions({
      env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
      claudeReplies: [validDebriefJson({ memorySummary: HER_MEMORY })],
    }),
    debriefBody({ requestId: "wp3-race", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  const payload = threadMemoryUpdates(state)[0].values;
  assertEquals(Object.keys(payload), ["memory_summary"]);
  for (
    const column of [
      "practice_mode",
      "relationship_score",
      "temperature_score",
      "familiarity_score",
      "partner_mood",
      "partner_inner_thought",
      "invite_stage",
      "recent_facts",
      "profile_id",
    ]
  ) {
    assertEquals(column in payload, false, `${column} 不得被寫回覆蓋`);
  }
  // 整列覆寫的 RPC 一次都不能被呼叫。
  assertEquals(threadUpsertCalls(state).length, 0);
});

Deno.test("WP3 旗標 on：UPDATE 命中 0 列（thread 不存在／角色已換）→ telemetry thread_missing，檢討 200", async () => {
  const { response, succeeded } = await runDebrief(
    debriefOptions({
      env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
      claudeReplies: [validDebriefJson({ memorySummary: HER_MEMORY })],
      threadUpdate: { rows: 0 },
    }),
    debriefBody({ requestId: "wp3-missing-row", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  assertEquals(succeeded?.memorySummarySkipped, "thread_missing");
});

Deno.test("WP3 旗標 on：模型沒吐欄位 → 不寫入、telemetry 記 missing、檢討照樣 200", async () => {
  const { response, json, state, succeeded } = await runDebrief(
    debriefOptions({ env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" } }),
    debriefBody({ requestId: "wp3-missing", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  assertEquals(threadMemoryUpdates(state).length, 0);
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
  assertEquals(threadMemoryUpdates(state).length, 0);
  assertEquals(succeeded?.memorySummarySkipped, "too_long");
});

Deno.test("WP3 旗標 on：寫回回 error 只 warn，telemetry write_failed，檢討照樣 200", async () => {
  const { response, json, succeeded, warns } = await runDebrief(
    debriefOptions({
      env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
      claudeReplies: [validDebriefJson({ memorySummary: HER_MEMORY })],
      threadUpdate: { error: "thread write boom" },
    }),
    debriefBody({ requestId: "wp3-write-error", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.memorySummary, HER_MEMORY);
  assertEquals(succeeded?.memorySummarySkipped, "write_failed");
  assert(
    warns.some((line) =>
      line.event === "practice_relationship_thread_memory_write_failed"
    ),
  );
});

Deno.test("WP3 旗標 on：寫回整個 reject（不是回 error）也不能炸掉檢討", async () => {
  const { response, json, succeeded, warns } = await runDebrief(
    debriefOptions({
      env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
      claudeReplies: [validDebriefJson({ memorySummary: HER_MEMORY })],
      threadUpdate: { rejects: true },
    }),
    debriefBody({ requestId: "wp3-write-reject", profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  assertEquals(json.memorySummary, HER_MEMORY);
  assertEquals(succeeded?.memorySummarySkipped, "write_failed");
  assert(
    warns.some((line) =>
      line.event === "practice_relationship_thread_memory_write_failed"
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
  assertEquals(threadMemoryUpdates(state).length, 0);
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

Deno.test("WP3 換角色（Codex R2 P1）：同一個 visible thread 換人時，舊角色的記憶被清成 NULL", async () => {
  // 這一列是 A 角色的（帶著 A 的摘要），這次請求是 B 角色。assisted 的 upsert
  // 路徑下一步會把 profile_id 改成 B、memory_summary 走 COALESCE 留著 A 的
  // 摘要——所以旗標 on 時要先把舊角色那一列的記憶清掉。
  const { response, state } = await run(
    {
      env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
      ledger: ledger({ ai_count: 1, charged: true }),
      thread: {
        profile_id: "practice_girl_006",
        memory_summary: HER_MEMORY,
        partner_mood: "neutral",
        partner_inner_thought: "",
      },
      deepSeekReplies: ["AI reply", "not json"],
    },
    chatBody({ profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  const updates = threadMemoryUpdates(state);
  assertEquals(updates.length, 1);
  assertEquals(Object.keys(updates[0].values), ["memory_summary"]);
  assertEquals(updates[0].values.memory_summary, null);
  // WHERE 綁的是**舊角色**的 profileId，不是這次請求的角色。
  assertEquals(updates[0].where, [
    ["user_id", "user-1"],
    ["visible_thread_id", "session-1"],
    ["profile_id", "practice_girl_006"],
  ]);
  // 這一輪的 prompt 本來就讀不到（profile 不符 → thread state 直接當 null）。
  const system = state.deepSeekCalls[0].messages[0].content;
  assertEquals(system.includes("<older_memory_untrusted>"), false);
});

Deno.test("WP3 換角色：旗標 off 時不清、不多發任何 UPDATE（逐位元組不變）", async () => {
  const { response, state } = await run(
    {
      ledger: ledger({ ai_count: 1, charged: true }),
      thread: {
        profile_id: "practice_girl_006",
        memory_summary: HER_MEMORY,
        partner_mood: "neutral",
        partner_inner_thought: "",
      },
      deepSeekReplies: ["AI reply", "not json"],
    },
    chatBody({ profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  assertEquals(threadMemoryUpdates(state).length, 0);
});

Deno.test("WP3 同一角色續聊：旗標 on 也不清，記憶照樣進 prompt", async () => {
  const { response, state } = await run(
    {
      env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
      ledger: ledger({ ai_count: 1, charged: true }),
      thread: {
        profile_id: PROFILE_ID,
        memory_summary: HER_MEMORY,
        partner_mood: "neutral",
        partner_inner_thought: "",
      },
      deepSeekReplies: ["AI reply", "not json"],
    },
    chatBody({ profileId: PROFILE_ID }),
  );

  assertEquals(response.status, 200);
  assertEquals(threadMemoryUpdates(state).length, 0);
  assert(
    state.deepSeekCalls[0].messages[0].content.includes(HER_MEMORY),
  );
});

Deno.test("WP3 檢討不會被 memorySummary 的形態問題打回：非字串與 1001 碼點都走完整驗證路徑仍回原卡", async () => {
  // 本 repo 的 `callClaude` 對 tool_use input 不做任何 schema 驗證（只
  // JSON.stringify），所以 schema 的 `maxLength`／`type` 擋不到 server 端；
  // 唯一的守門是 `parseDebriefCard` ＋ `parseDebriefMemorySummary`。這一條
  // 走真實的 validate/runSingleShot 路徑把它釘住。
  for (
    const [name, value] of [
      ["not_string", 12],
      ["too_long", "記".repeat(DEBRIEF_MEMORY_SUMMARY_MAX_CHARS + 1)],
    ] as const
  ) {
    const { response, json, state, succeeded } = await runDebrief(
      debriefOptions({
        env: { PRACTICE_MEMORY_SUMMARY_WRITE: "true" },
        claudeReplies: [validDebriefJson({ memorySummary: value })],
      }),
      debriefBody({ requestId: `wp3-shape-${name}`, profileId: PROFILE_ID }),
    );

    assertEquals(response.status, 200, name);
    // 只發一次（沒有因為欄位形態而重試第二個模型）。
    assertEquals(state.claudeCalls.length, 1, name);
    assertEquals(
      json.card.summary,
      "你說今天忙到剛下班，她接著分享只想散步放空。",
      name,
    );
    assertEquals("memorySummary" in json, false, name);
    assertEquals(threadMemoryUpdates(state).length, 0, name);
    assertEquals(succeeded?.memorySummarySkipped, name);
  }
});

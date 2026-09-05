// conversation-agency-v1 Phase 4.5b：standard 模式的每輪 agency 分類器。
//
// 旗標關閉時的四面等價由 `agency_flag_off_equivalence_test.ts` 多枚舉的
// `PRACTICE_STANDARD_AGENCY_CLASSIFIER` 維度守（未設／off／亂填四面全等，含
// agency on 的情形）。這一支守的是**旗標開著時**的正向行為：
//
//   1. 精簡 prompt（只問四個 agency 欄位，判準文字與逐輪分類器同一份常數）。
//   2. thread 寫入把既有 row 的每一個 `= EXCLUDED` 欄位原樣帶回。
//   3. 狀態真的回流：這一輪分類器判「她在澄清」→ 下一輪裸詞被 4.3 強制質疑。
//   4. fail-open：分類器壞掉不擋聊天，telemetry 記 `standardClassifier:"failed"`。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  chatBody,
  debriefBody,
  type FakeOptions,
  ledger,
  makeFake,
  makeRequest,
  validDebriefJson,
} from "./handler_test_fake.ts";
import {
  AGENCY_CLASSIFIER_RULES,
  buildStandardAgencyClassifierMessages,
} from "./temperature.ts";
import { resolvePracticeProfile } from "./practice_persona.ts";
import type { PracticeTurn } from "./validate.ts";

const AGENCY_ENV = "PRACTICE_CONVERSATIONAL_AGENCY_ENABLED";
const STANDARD_CLASSIFIER_ENV = "PRACTICE_STANDARD_AGENCY_CLASSIFIER";

/** 玩家丟片段、她問了、玩家又丟一個不相干的詞（agency 會介入的典型形狀）。 */
const FRAGMENT_TURNS = [
  { role: "user", text: "東東" },
  { role: "ai", text: "東東是誰" },
  { role: "user", text: "阿布達比" },
];

/** 精簡分類器的合法回覆（四個欄位，零 repair）。 */
function slimClassifier(opts: {
  coherence?: string;
  aiChallengedThisTurn?: boolean;
  sharedPastClaim?: boolean;
  accommodatingSelfFact?: boolean;
} = {}): string {
  return JSON.stringify({
    coherence: opts.coherence ?? "disconnected",
    aiChallengedThisTurn: opts.aiChallengedThisTurn ?? false,
    sharedPastClaim: opts.sharedPastClaim ?? false,
    accommodatingSelfFact: opts.accommodatingSelfFact ?? false,
  });
}

interface RunResult {
  status: number;
  /** 這一輪真的送出去的回覆（read_only 那一輪是「（已讀）」）。 */
  reply: string;
  state: ReturnType<typeof makeFake>["state"];
  telemetry: Record<string, unknown>[];
}

async function runStandardTurn(options: FakeOptions, body: unknown): Promise<
  RunResult
> {
  const fake = makeFake({ ...options, monotonicNowValues: [0] });
  const lines: string[] = [];
  const originalLog = console.log;
  const originalWarn = console.warn;
  let response: Response;
  try {
    console.log = (...args: unknown[]) =>
      lines.push(args.map((a) => String(a)).join(" "));
    console.warn = console.log;
    response = await fake.handler(makeRequest(body));
    await Promise.allSettled(fake.state.backgroundTasks);
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
  }
  const telemetry: Record<string, unknown>[] = [];
  for (const line of lines) {
    try {
      telemetry.push(JSON.parse(line) as Record<string, unknown>);
    } catch {
      // ai_logs 背景寫入等非 JSON 行不進來。
    }
  }
  const payload = await response.json().catch(() => ({})) as {
    reply?: string;
  };
  return {
    status: response.status,
    reply: payload.reply ?? "",
    state: fake.state,
    telemetry,
  };
}

function succeeded(r: RunResult): Record<string, unknown> {
  const row = r.telemetry.find((t) => t.event === "practice_chat_succeeded");
  assert(row, "缺少 practice_chat_succeeded");
  return row;
}

function agencyTelemetry(r: RunResult): Record<string, unknown> {
  const row = succeeded(r).conversationAgency as Record<string, unknown> | null;
  assert(row, "缺少 conversationAgency telemetry");
  return row;
}

function threadUpsert(r: RunResult): Record<string, unknown> {
  const calls = r.state.rpcCalls.filter((c) =>
    c.fn === "upsert_practice_relationship_thread"
  );
  assertEquals(calls.length, 1, "standard 這一輪應恰好寫一次 thread");
  return calls[0].params;
}

const STANDARD_ENV = {
  [AGENCY_ENV]: "true",
  [STANDARD_CLASSIFIER_ENV]: "true",
};

/** 既有 beginner thread row：每一個 `= EXCLUDED` 欄位都有非預設值。 */
const EXISTING_BEGINNER_ROW = {
  profile_id: "practice_girl_001",
  practice_mode: "beginner",
  relationship_score: 55,
  temperature_score: 42,
  familiarity_score: 17,
  partner_mood: "curious",
  partner_inner_thought: "他今天怪怪的",
  invite_stage: "soft_invite_ready",
  memory_summary: "先前聊過她加班與貓",
  // Codex R1 P2-2：每一格都刻意**不是**本檔會寫出來的預設值——`source` 不是
  // "practice_chat"、`aiTurnCount` 不是這一輪的 `newAiCount`（fake 的 commit 回
  // 1）、`replyStyle` 裡有一個 `parseReplyStyleState` 不認識的巢狀 key、頂層有
  // 兩個未知 key。這樣「原樣帶回」才不是恆真斷言。
  recent_facts: {
    source: "another_writer",
    aiTurnCount: 42,
    inviteStage: "soft_invite_ready",
    replyStyle: {
      version: 1,
      priorDecline: true,
      recentActs: ["acknowledge"],
      futureNested: { keep: "me" },
    },
    futureFeature: { nested: ["keep", 1] },
    unknownScalar: "keep-me",
  },
};

Deno.test("Phase 4.5b：standard 旗標開時多打一次**精簡**分類器（只問四個 agency 欄位、判準與逐輪分類器同源、不寫 learning state）", async () => {
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    thread: null,
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", slimClassifier()],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));

  assertEquals(r.status, 200);
  assertEquals(r.state.deepSeekCalls.length, 2, "生成 1 次 ＋ 精簡分類器 1 次");
  const system = r.state.deepSeekCalls[1].messages[0].content;
  assert(system.includes(AGENCY_CLASSIFIER_RULES), "判準文字必須是同一份常數");
  assert(
    system.includes(
      '{"coherence":"connected","aiChallengedThisTurn":false,"sharedPastClaim":false,"accommodatingSelfFact":false}',
    ),
    "JSON stub 只有四個 agency 欄位",
  );
  for (const core of ['"partnerMood"', '"connection"', '"innerThought"']) {
    assert(!system.includes(core), `精簡分類器不得問核心欄位 ${core}`);
  }
  // 逐字稿、她這一輪的回覆與可信自我來源都要餵進去。
  const user = r.state.deepSeekCalls[1].messages[1].content;
  assert(user.includes("阿布達比"));
  assert(user.includes("assistantReplyAfterUser:\n好啊"));
  assert(user.includes("<her_self_sources>"));
  // 溫度／分數管線一步都不能碰。
  assertEquals(
    r.state.rpcCalls.filter((c) => c.fn === "update_practice_learning_state")
      .length,
    0,
  );
  assertEquals(succeeded(r).temperatureAfter, null);

  const agency = agencyTelemetry(r);
  assertEquals(agency.standardClassifier, "ok");
  assertEquals(agency.coherence, "disconnected");
  assertEquals(agency.aiChallengedThisTurn, false);
  assertEquals(agency.sharedPastClaim, false);
  assertEquals(agency.accommodatingSelfFact, false);
  assert(typeof agency.standardClassifierDurationMs === "number");
});

Deno.test("Phase 4.5b：既有 beginner row 下，standard 一輪的 thread RPC params 除了 recent_facts.conversationAgency 以外逐欄位相同", async () => {
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    thread: EXISTING_BEGINNER_ROW,
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", slimClassifier()],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));

  assertEquals(r.status, 200);
  const params = threadUpsert(r);
  // RPC 的 ON CONFLICT 對這四欄是 `= EXCLUDED`（不是 COALESCE）：帶錯就等於
  // 把 beginner 累積的模式與分數清掉。
  assertEquals(params.p_practice_mode, "beginner");
  assertEquals(params.p_relationship_score, 55);
  assertEquals(params.p_temperature_score, 42);
  assertEquals(params.p_familiarity_score, 17);
  // COALESCE 的那幾欄也原樣帶回（規則一致，不留逐欄位的例外表）。
  assertEquals(params.p_partner_mood, "curious");
  assertEquals(params.p_partner_inner_thought, "他今天怪怪的");
  assertEquals(params.p_invite_stage, "soft_invite_ready");
  assertEquals(params.p_memory_summary, "先前聊過她加班與貓");
  assertEquals(params.p_profile_id, "practice_girl_001");

  // Codex R1 P2-2：整份 `p_recent_facts` 精確比對，白名單只有三個 key 可變
  // （`source`／`aiTurnCount` 是既有寫入語意，`conversationAgency` 是本刀新增）。
  // 特別是 `replyStyle`：**原始物件原樣穿過**，`parseReplyStyleState` 不認識的
  // 巢狀 key 不得被靜默清掉（Codex R1 U2）。
  const recentFacts = params.p_recent_facts as Record<string, unknown>;
  assert("conversationAgency" in recentFacts, "唯一該新增的 key");
  assertEquals(recentFacts, {
    ...EXISTING_BEGINNER_ROW.recent_facts,
    source: "practice_chat",
    aiTurnCount: 1,
    conversationAgency: recentFacts.conversationAgency,
  });
  assertEquals(
    recentFacts.replyStyle,
    EXISTING_BEGINNER_ROW.recent_facts.replyStyle,
    "replyStyle 必須是原始物件（含未知巢狀 key），不是 parse 後重建的",
  );
});

Deno.test("Phase 4.5b（Codex R1 P1-1）：thread 上是**別的角色**的列時，standard 完全不寫 thread（分類器照跑）", async () => {
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    // 同一個 visible thread，但列上是 practice_girl_008 的關係狀態。
    thread: { ...EXISTING_BEGINNER_ROW, profile_id: "practice_girl_008" },
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", slimClassifier()],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));

  assertEquals(r.status, 200);
  // 舊版會拿新角色的 profileId 去 upsert：四個 `= EXCLUDED` 欄位被寫 null
  // （舊角色的分數與模式沒了），partner／invite／memory 走 COALESCE 留著舊角色
  // 的值＝兩個角色攪在一起。現在一次 RPC 都不發。
  assertEquals(
    r.state.rpcCalls.filter((c) =>
      c.fn === "upsert_practice_relationship_thread"
    ).length,
    0,
    "profile 不符時不得碰別的角色那一列",
  );
  // 分類器仍然跑，telemetry 誠實標示狀態沒落地。
  assertEquals(r.state.deepSeekCalls.length, 2);
  const agency = agencyTelemetry(r);
  assertEquals(agency.standardClassifier, "ok");
  assertEquals(agency.statePersisted, false);
  assertEquals(agency.stateSkipReason, "profile_mismatch");
  assert(
    r.telemetry.some((t) =>
      t.event === "practice_relationship_thread_profile_mismatch"
    ),
  );
});

Deno.test("Phase 4.5b：沒有既有 row 時建立 mode standard、分數留空的 thread（beginner 的 resolveLearningSeed 對 null 分數有既有退路）", async () => {
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    thread: null,
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", slimClassifier()],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));

  const params = threadUpsert(r);
  assertEquals(params.p_practice_mode, "standard");
  assertEquals(params.p_relationship_score, null);
  assertEquals(params.p_temperature_score, null);
  assertEquals(params.p_familiarity_score, null);
  assertEquals(params.p_invite_stage, null);
  assertEquals(params.p_memory_summary, null);
  const recentFacts = params.p_recent_facts as Record<string, unknown>;
  assert(
    !("inviteStage" in recentFacts),
    "沒有階梯可算時不得把 recent_facts.inviteStage 寫成 null",
  );
  // 「沒有 row」與「profile 不符」是兩條路：這一條照樣建列。
  assertEquals(agencyTelemetry(r).statePersisted, true);
});

Deno.test("Phase 4.5b：狀態真的回流——這一輪分類器判她在澄清，下一輪裸詞被 4.3 強制 challenge_relevance", async () => {
  const first = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    thread: null,
    env: STANDARD_ENV,
    deepSeekReplies: [
      "你在說什麼？",
      slimClassifier({ aiChallengedThisTurn: true }),
    ],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));
  assertEquals(first.status, 200);
  const written = (threadUpsert(first).p_recent_facts as Record<
    string,
    unknown
  >).conversationAgency as Record<string, unknown>;
  assertEquals(
    written.aiClarifiedLastTurn,
    true,
    "分類器訊號沒有進持久化狀態的話，4.3 的死守邊界在 standard 永遠點不了火",
  );

  // 第二輪：她剛問完（帶句尾標記＝嚴格問句），他又丟一個裸詞。
  const second = await runStandardTurn(
    {
      ledger: ledger({ practice_mode: "standard", ai_count: 1, charged: true }),
      thread: {
        ...EXISTING_BEGINNER_ROW,
        recent_facts: { conversationAgency: written },
      },
      env: STANDARD_ENV,
      deepSeekReplies: ["？", slimClassifier({ aiChallengedThisTurn: true })],
    },
    chatBody({
      practiceMode: "standard",
      turns: [
        ...FRAGMENT_TURNS,
        { role: "ai", text: "你在說什麼？" },
        { role: "user", text: "日本" },
      ],
    }),
  );
  assertEquals(second.status, 200);
  const agency = agencyTelemetry(second);
  assertEquals(agency.policyMode, "forced");
  assertEquals(agency.forcedAct, "challenge_relevance");
  assert(
    String(agency.allowedActSetId).startsWith("clarify_ignored"),
    `預期 clarify_ignored_*，拿到 ${agency.allowedActSetId}`,
  );
});

Deno.test("Phase 4.5b（反例）：同一段逐字稿在旗標關著時仍是 bounded——上一支測試鎖住的是旗標帶來的差異", async () => {
  const r = await runStandardTurn(
    {
      ledger: ledger({ practice_mode: "standard", ai_count: 1, charged: true }),
      thread: null,
      env: { [AGENCY_ENV]: "true" },
      deepSeekReplies: ["？"],
    },
    chatBody({
      practiceMode: "standard",
      turns: [
        ...FRAGMENT_TURNS,
        { role: "ai", text: "你在說什麼？" },
        { role: "user", text: "日本" },
      ],
    }),
  );
  assertEquals(r.status, 200);
  assertEquals(r.state.deepSeekCalls.length, 1, "旗標關著時不打分類器");
  assertEquals(
    r.state.rpcCalls.filter((c) =>
      c.fn === "upsert_practice_relationship_thread"
    ).length,
    0,
    "旗標關著時 standard 不寫 thread",
  );
  assertEquals(agencyTelemetry(r).policyMode, "bounded");
});

Deno.test("Phase 4.5b：分類器壞掉＝fail-open（照樣 200、照樣寫狀態、telemetry 記 failed、留一筆沒有逐字稿的 warn）", async () => {
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    thread: null,
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", "抱歉我不太確定"],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));

  assertEquals(r.status, 200);
  const agency = agencyTelemetry(r);
  assertEquals(agency.standardClassifier, "failed");
  assertEquals(agency.coherence, null, "訊號缺席＝退回結構近似，不是假值");
  assertEquals(agency.aiChallengedThisTurn, null);
  assert(!("sharedPastClaim" in agency));
  // 狀態仍然推進（純結構近似），而且 `aiClarifiedLastTurn` 不留欄位。
  const written = (threadUpsert(r).p_recent_facts as Record<string, unknown>)
    .conversationAgency as Record<string, unknown>;
  assert(!("aiClarifiedLastTurn" in written));
  const warn = r.telemetry.find((t) =>
    t.event === "practice_chat_standard_agency_classifier_failed"
  );
  assert(warn, "缺少 fail-open 的 warn");
  assertEquals(
    Object.keys(warn).sort(),
    ["errorClass", "event", "level", "user"],
  );
  assertEquals(warn.errorClass, "parse");
  for (const secret of ["阿布達比", "東東", "deepseek-key"]) {
    assert(!JSON.stringify(warn).includes(secret));
  }
});

Deno.test("Phase 4.5b（Codex R2 U）：分類器失敗的 warn 只記固定錯誤類別，不得帶出模型原文", async () => {
  // 壞 JSON 裡塞一個唯一 marker：`JSON.parse` 的錯誤訊息會把原文片段帶進來，
  // 舊版直接記 `getErrorMessage(e)` 就會把它印進 log。
  const marker = "ZZ_LEAK_MARKER_9137";
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    thread: null,
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", `{"coherence": ${marker} }`],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));

  assertEquals(r.status, 200);
  assertEquals(agencyTelemetry(r).standardClassifier, "failed");
  const warn = r.telemetry.find((t) =>
    t.event === "practice_chat_standard_agency_classifier_failed"
  )!;
  assert(warn, "缺少 fail-open 的 warn");
  assert(
    !JSON.stringify(warn).includes(marker),
    `warn 洩漏了模型原文：${JSON.stringify(warn)}`,
  );
  assertEquals(warn.errorClass, "parse");
  // 整輪的 telemetry 都不得出現那個 marker（不只那一行）。
  assert(!JSON.stringify(r.telemetry).includes(marker));
});

Deno.test("Phase 4.5b（Codex R2 P1）：thread 讀取失敗時 standard 完全不寫（不能把「不知道」當成「確定沒有列」）", async () => {
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    threadError: "connection reset",
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", slimClassifier()],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));

  assertEquals(r.status, 200);
  assertEquals(
    r.state.rpcCalls.filter((c) =>
      c.fn === "upsert_practice_relationship_thread"
    ).length,
    0,
    "讀不到那一列時不得覆寫它",
  );
  // 分類器照跑，telemetry 誠實區分原因。
  assertEquals(r.state.deepSeekCalls.length, 2);
  const agency = agencyTelemetry(r);
  assertEquals(agency.standardClassifier, "ok");
  assertEquals(agency.statePersisted, false);
  assertEquals(agency.stateSkipReason, "fetch_failed");
});

Deno.test("Phase 4.5b（Codex R2 P2）：thread upsert RPC 失敗時 statePersisted 必須是 false（不得因為 fail-open 就報成功）", async () => {
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    thread: null,
    env: STANDARD_ENV,
    rpc: {
      upsert_practice_relationship_thread: [{ error: "deadlock detected" }],
    },
    deepSeekReplies: ["好啊", slimClassifier()],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));

  assertEquals(r.status, 200, "寫入失敗仍然 fail-open，不擋聊天");
  assertEquals(threadUpsert(r).p_practice_mode, "standard", "RPC 有真的送出");
  const agency = agencyTelemetry(r);
  assertEquals(agency.statePersisted, false);
  // 這一格不是「跳過」，所以不該有 stateSkipReason。
  assert(!("stateSkipReason" in agency));
  assert(
    r.telemetry.some((t) =>
      t.event === "practice_relationship_thread_upsert_failed"
    ),
  );
});

Deno.test("Phase 4.5b：repair-first 走既有事件與既有 telemetry key（模型漏答四個欄位）", async () => {
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    thread: null,
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", "{}"],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));

  const agency = agencyTelemetry(r);
  assertEquals(agency.standardClassifier, "ok");
  assertEquals(agency.coherence, "ambiguous");
  assertEquals(agency.sharedPastClaimRepaired, true);
  assertEquals(agency.accommodatingSelfFactRepaired, true);
  const repaired = r.telemetry.find((t) =>
    t.event === "practice_chat_learning_classifier_repaired"
  );
  assert(repaired, "repair 要走 assisted 路徑同一個事件名");
  assertEquals(repaired.fields, [
    "coherence",
    "aiChallengedThisTurn",
    "sharedPastClaim",
    "accommodatingSelfFact",
  ]);
});

// ── Codex R1 P1-3：telemetry 契約（分面）────────────────────────────────────
//
// 這一支把三種分類器結果的 **key set 與事件名列表**釘死，不是只挑幾個欄位看。
// 契約本身寫在計畫檔 Phase 4.5b 節。

/** 這一輪 `conversationAgency` 的 key 集合。 */
function agencyKeys(r: RunResult): string[] {
  return Object.keys(agencyTelemetry(r)).sort();
}

/** 這一輪印出來的事件名（依序）。 */
function eventNames(r: RunResult): string[] {
  return r.telemetry.map((t) => String(t.event));
}

/** 旗標開時 `conversationAgency` 一定會有的既有 key（Phase 4.5b 之前就有）。 */
const BASE_AGENCY_KEYS = [
  "agencyVersion",
  "aiChallengedThisTurn",
  "allowedActSetId",
  "applied",
  "askUserForced",
  "coherence",
  "coherenceBefore",
  "deltaCapApplied",
  "forcedAct",
  "policyMode",
  "priorChallengeIssued",
  "profile",
  "unresolvedCount",
  "utteranceShape",
];

Deno.test("Phase 4.5b（Codex R1 P1-3 ＋ R2 P2）：telemetry 契約——旗標關＝零新 key 零新事件；三種分類器結果的欄位存在性與事件名列表逐項釘死", async () => {
  const body = chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS });
  const base: FakeOptions = {
    ledger: ledger({ practice_mode: "standard" }),
    thread: null,
  };

  // (a) 旗標關（agency on）：零新 key、零新事件。
  const off = await runStandardTurn({
    ...base,
    env: { [AGENCY_ENV]: "true" },
    deepSeekReplies: ["好啊"],
  }, body);
  assertEquals(agencyKeys(off), BASE_AGENCY_KEYS.slice().sort());
  const offEvents = eventNames(off);
  // 事件名列表直接與明確預期陣列比對（Codex R2 P3：不要跟自己比）。
  assertEquals(offEvents, ["practice_chat_succeeded"]);

  // 三種分類器結果的**欄位存在性**逐項比對（Codex R2 P2：`coherence`／
  // `aiChallengedThisTurn` 由 generic block 寫，失敗時存在且為 null——與
  // beginner 分類器失敗時逐字相同；只有另外兩欄缺席）。
  const cases: Array<{
    label: string;
    classifierReply: string;
    expectKeys: string[];
    expectEvents: string[];
    expect: Record<string, unknown>;
    absent: string[];
  }> = [
    {
      label: "合法 JSON",
      classifierReply: slimClassifier(),
      expectKeys: [
        ...BASE_AGENCY_KEYS,
        "accommodatingSelfFact",
        "sharedPastClaim",
        "standardClassifier",
        "standardClassifierDurationMs",
        "statePersisted",
      ],
      expectEvents: offEvents,
      expect: {
        standardClassifier: "ok",
        statePersisted: true,
        coherence: "disconnected",
        aiChallengedThisTurn: false,
        sharedPastClaim: false,
        accommodatingSelfFact: false,
      },
      absent: [
        "sharedPastClaimRepaired",
        "accommodatingSelfFactRepaired",
        "stateSkipReason",
      ],
    },
    {
      label: "{}（四欄全 repair）",
      classifierReply: "{}",
      expectKeys: [
        ...BASE_AGENCY_KEYS,
        "accommodatingSelfFact",
        "accommodatingSelfFactRepaired",
        "sharedPastClaim",
        "sharedPastClaimRepaired",
        "standardClassifier",
        "standardClassifierDurationMs",
        "statePersisted",
      ],
      // 允許多出的事件只有 repaired 那一個（與 beginner 同名）。
      expectEvents: [
        "practice_chat_learning_classifier_repaired",
        ...offEvents,
      ],
      expect: {
        standardClassifier: "ok",
        // 修過的 coherence 退到最保守的一格；`*Repaired` 只有另外兩欄有
        // （coherence／aiChallengedThisTurn 修過只進 repaired 事件）。
        coherence: "ambiguous",
        aiChallengedThisTurn: false,
        sharedPastClaimRepaired: true,
        accommodatingSelfFactRepaired: true,
      },
      absent: ["coherenceRepaired", "aiChallengedThisTurnRepaired"],
    },
    {
      label: "非法 JSON（分類器整個失敗）",
      classifierReply: "抱歉我不太確定",
      expectKeys: [
        ...BASE_AGENCY_KEYS,
        "standardClassifier",
        "standardClassifierDurationMs",
        "statePersisted",
      ],
      expectEvents: [
        "practice_chat_standard_agency_classifier_failed",
        ...offEvents,
      ],
      expect: {
        standardClassifier: "failed",
        // 逐字鏡射 beginner 分類器失敗：這兩格**存在且為 null**。
        coherence: null,
        aiChallengedThisTurn: null,
      },
      absent: ["sharedPastClaim", "accommodatingSelfFact"],
    },
  ];

  for (const c of cases) {
    const r = await runStandardTurn({
      ...base,
      env: STANDARD_ENV,
      deepSeekReplies: ["好啊", c.classifierReply],
    }, body);
    const agency = agencyTelemetry(r);
    assertEquals(agencyKeys(r), c.expectKeys.slice().sort(), c.label);
    assertEquals(eventNames(r), c.expectEvents, `${c.label}：事件名列表`);
    for (const [key, value] of Object.entries(c.expect)) {
      assert(Object.hasOwn(agency, key), `${c.label}：缺少 ${key}`);
      assertEquals(agency[key], value, `${c.label}／${key}`);
    }
    for (const key of c.absent) {
      assert(!Object.hasOwn(agency, key), `${c.label}：不該有 ${key}`);
    }
  }
});

Deno.test("Phase 4.5b（Codex R1 U1）：request 完全不帶 practiceMode 時（validateRequest 正規化成 standard）分類器一樣開、狀態一樣寫", async () => {
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    thread: null,
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", slimClassifier()],
    // 注意 body 裡沒有 practiceMode key。
  }, chatBody({ turns: FRAGMENT_TURNS }));

  assertEquals(r.status, 200);
  assertEquals(r.state.deepSeekCalls.length, 2, "正規化後的 standard 也要開");
  assertEquals(threadUpsert(r).p_practice_mode, "standard");
  assertEquals(agencyTelemetry(r).standardClassifier, "ok");
});

// ── Codex R1 P2-3：多輪端到端（狀態每輪餵回去）──────────────────────────────

/**
 * 跑 n 輪 standard：每一輪把上一輪 RPC 寫出去的 `recent_facts` 當成下一輪的
 * thread row（＝production 的先讀後寫），回傳每一輪的 `forcedAct`。
 */
async function runLadder(difficulty: string): Promise<string[]> {
  // 玩家一路丟不相干的地名，她每一輪都直接問「你在說什麼？」（帶句尾標記
  // ＝`aiQuestionedInLoop` 成立，欠債輪的強制格才進得去）。
  const bare = ["東東", "阿布達比", "日本", "清邁", "韓國", "峇里島", "沖繩"];
  const forced: string[] = [];
  const classifierReply = slimClassifier({ aiChallengedThisTurn: true });
  let recentFacts: Record<string, unknown> | null = null;
  const turns: Array<{ role: string; text: string }> = [];
  for (let i = 0; i < bare.length; i++) {
    // `checkedOut` 一旦成立就一路 `read_only`，所以上一輪是 check_out／read_only
    // 就代表這一輪不會打生成模型（下面的斷言會抓到猜錯）。
    const last = forced[forced.length - 1];
    const readOnlyExpected = last === "check_out" || last === "read_only";
    turns.push({ role: "user", text: bare[i] });
    const r = await runStandardTurn(
      {
        ledger: ledger({
          practice_mode: "standard",
          ai_count: i,
          charged: i > 0,
        }),
        thread: recentFacts
          ? { profile_id: "practice_girl_001", recent_facts: recentFacts }
          : null,
        env: STANDARD_ENV,
        // 她每一輪都在問「你在說什麼？」，分類器據實回報 `aiChallengedThisTurn`
        // ——這正是 Phase 4.3 死守邊界的點火條件（她澄清了、他又丟一個詞）。
        // `read_only` 那一輪 handler **完全跳過生成模型**，所以那一輪的第一發
        // DeepSeek 就是分類器（fake 的回覆是照呼叫順序取的）。
        deepSeekReplies: readOnlyExpected
          ? [classifierReply]
          : ["你在說什麼？", classifierReply],
      },
      chatBody({
        practiceMode: "standard",
        difficulty,
        turns: turns.slice(),
      }),
    );
    assertEquals(r.status, 200);
    const act = String(agencyTelemetry(r).forcedAct);
    assertEquals(
      act === "read_only",
      readOnlyExpected,
      `第 ${i + 1} 輪猜錯了會不會打生成模型（act=${act}）`,
    );
    forced.push(act);
    const writes = r.state.rpcCalls.filter((c) =>
      c.fn === "upsert_practice_relationship_thread"
    );
    if (writes.length) {
      recentFacts = writes[0].params.p_recent_facts as Record<string, unknown>;
    }
    // 把她**實際送出**的那一則接回逐字稿（read_only 那一輪是「（已讀）」）。
    turns.push({ role: "ai", text: r.reply });
  }
  return forced;
}

Deno.test("Phase 4.5b（Codex R1 P2-3）：standard 多輪端到端——挑戰難度連續裸詞走到 check_out 再 read_only", async () => {
  const challenge = await runLadder("challenge");
  const checkOutAt = challenge.indexOf("check_out");
  assert(checkOutAt >= 0, `沒有走到 check_out：${challenge.join("／")}`);
  assert(
    challenge.indexOf("read_only") > checkOutAt,
    `read_only 必須在 check_out 之後：${challenge.join("／")}`,
  );
});

Deno.test("Phase 4.5b（Codex R1 P2-3 反例）：同一段序列在 easy／normal 不得出現 check_out／read_only", async () => {
  for (const difficulty of ["easy", "normal"]) {
    const forced = await runLadder(difficulty);
    for (const act of ["check_out", "read_only"]) {
      assert(
        !forced.includes(act),
        `${difficulty} 不該出現 ${act}：${forced.join("／")}`,
      );
    }
  }
});

Deno.test("Phase 4.5b（Codex R2 P3）：多出來的那一次分類器呼叫，messages 逐位元組等於 buildStandardAgencyClassifierMessages 對同一輸入的輸出；thread upsert 的 params 等於預期物件", async () => {
  const reply = "好啊";
  const r = await runStandardTurn({
    ledger: ledger({ practice_mode: "standard" }),
    thread: null,
    env: STANDARD_ENV,
    deepSeekReplies: [reply, slimClassifier()],
  }, chatBody({ practiceMode: "standard", turns: FRAGMENT_TURNS }));

  assertEquals(r.status, 200);
  assertEquals(r.state.deepSeekCalls.length, 2);
  // messages：不是「包含某個字串」，而是與純函式對同一輸入的輸出逐位元組相同。
  assertEquals(
    r.state.deepSeekCalls[1].messages,
    buildStandardAgencyClassifierMessages({
      turns: FRAGMENT_TURNS as PracticeTurn[],
      profile: resolvePracticeProfile({}),
      assistantReply: reply,
      memorySummary: null,
      herRecentMoments: [],
    }),
  );

  // rpc params：整份等於預期物件（沒有既有 row，所以四個 `= EXCLUDED` 欄位都是
  // null；`recent_facts` 只有 source／aiTurnCount／conversationAgency）。
  const params = threadUpsert(r);
  const agencyState = (params.p_recent_facts as Record<string, unknown>)
    .conversationAgency;
  assertEquals(params, {
    p_user_id: "user-1",
    p_visible_thread_id: "session-1",
    p_profile_id: "practice_girl_001",
    p_practice_mode: "standard",
    p_relationship_score: null,
    p_temperature_score: null,
    p_familiarity_score: null,
    p_partner_mood: null,
    p_partner_inner_thought: null,
    p_invite_stage: null,
    p_memory_summary: null,
    p_recent_facts: {
      source: "practice_chat",
      aiTurnCount: 1,
      conversationAgency: agencyState,
    },
  });
  // 那一格自己也要是預期的狀態機輸出（不是隨便一個物件）。
  assertEquals(agencyState, {
    version: 1,
    lastCoherence: "disconnected",
    unresolvedCount: 1,
    priorChallengeIssued: false,
    lastAgencyAct: null,
    aiClarifiedLastTurn: false,
  });
});

// ── Phase 4.5c 刀 2：debrief 也吃 standard 的持久化 agency 狀態 ────────────
/** A25 型逐字稿（六則玩家訊息全部是裸地名）。 */
const A25_DEBRIEF_TURNS = [
  { role: "user", text: "東東" },
  { role: "ai", text: "東東？誰啊" },
  { role: "user", text: "阿布打比" },
  { role: "ai", text: "蛤 你打什麼 看不懂" },
  { role: "user", text: "清邁" },
  { role: "ai", text: "喔 清邁\n我還沒去過那邊\n聽說食物很讚" },
  { role: "user", text: "好市多" },
  {
    role: "ai",
    text:
      "你怎麼突然跳這麼多地方\n一下東東一下阿布達比\n現在又好市多\n到底在講哪個",
  },
  { role: "user", text: "曼谷" },
  { role: "ai", text: "你是在背地名嗎\n我快跟不上你了啦" },
  { role: "user", text: "馬尼拉" },
  { role: "ai", text: "好 你慢慢背\n我累了先這樣" },
];

/** A25 逐字稿裡她講了幾則（＝逐字稿完整時 ledger 的 `ai_count`）。 */
const A25_AI_TURNS =
  A25_DEBRIEF_TURNS.filter((turn) => turn.role === "ai").length;

/** thread row；`repairedAtUserTurns` 給 null＝有 agency 狀態但沒有修復點。 */
const rowWithRepair = (options: {
  profileId?: string;
  practiceMode?: string;
  repairedAtUserTurns?: number | null;
} = {}) => ({
  profile_id: options.profileId ?? "practice_girl_001",
  practice_mode: options.practiceMode ?? "standard",
  recent_facts: {
    source: "practice_chat",
    conversationAgency: {
      version: 1,
      lastCoherence: "ambiguous",
      unresolvedCount: 0,
      priorChallengeIssued: false,
      lastAgencyAct: null,
      ...(options.repairedAtUserTurns === null
        ? {}
        : { repairedAtUserTurns: options.repairedAtUserTurns ?? 2 }),
    },
  },
});

/** debrief 走 `practice_chat_generation_outcome`（不是 chat 的 succeeded）。 */
function debriefAgencyTelemetry(r: RunResult): Record<string, unknown> {
  const row = r.telemetry.find((t) =>
    t.event === "practice_chat_generation_outcome" && t.mode === "debrief"
  );
  assert(row, "缺少 debrief 的 practice_chat_generation_outcome");
  const agency = row.conversationAgency as Record<string, unknown> | undefined;
  assert(agency, "缺少 conversationAgency telemetry");
  return agency;
}

async function runDebriefWithThread(options: {
  env: Record<string, string | undefined>;
  practiceMode?: string;
  profileId?: string;
  repairedAtUserTurns?: number | null;
  /** ledger 的 `ai_count`；與逐字稿的 ai 則數不同＝server 眼中逐字稿被截過。 */
  aiCount?: number;
}) {
  return await runStandardTurn(
    {
      ledger: ledger({
        practice_mode: options.practiceMode ?? "standard",
        ai_count: options.aiCount ?? A25_AI_TURNS,
        charged: true,
      }),
      drawEvents: [],
      thread: rowWithRepair(options),
      env: options.env,
      claudeReplies: [validDebriefJson()],
    },
    debriefBody({
      turns: A25_DEBRIEF_TURNS,
      ...(options.profileId ? { profileId: options.profileId } : {}),
    }),
  );
}

async function runStandardDebrief(env: Record<string, string | undefined>) {
  return await runDebriefWithThread({ env });
}

Deno.test("Phase 4.5c 刀 2：standard debrief 在分類器旗標開著時吃 thread 上的修復點（第 2 則之後才重算欠債）", async () => {
  const r = await runStandardDebrief(STANDARD_ENV);
  assertEquals(r.status, 200);
  // 期望值是手算的（`debriefAgencyLedgerFor` 的第 2 則修復點把第 2、3 則排除），
  // 不是拿被驗對象自己算一次——見 `agency_coaching_test.ts` 的同一組數字。
  assertEquals(debriefAgencyTelemetry(r), {
    applied: true,
    fragmentTurns: 1,
    topicShiftTurns: 3,
    loopTurns: 0,
    repairTurnCount: 4,
  });
});

Deno.test("Phase 4.5c 刀 2（反例）：分類器旗標關著時 standard debrief 不讀 thread 狀態，維持 4.1 的純結構回放", async () => {
  // 旗標關著時 standard 這一輪根本不會寫 agency 狀態，讀它等於吃到別條路徑的
  // 殘值；所以帳必須留在六則全記的 4.1 基準。
  for (const flag of [undefined, "off", "亂填"]) {
    const r = await runStandardDebrief({
      [AGENCY_ENV]: "true",
      [STANDARD_CLASSIFIER_ENV]: flag,
    });
    assertEquals(r.status, 200, String(flag));
    assertEquals(debriefAgencyTelemetry(r), {
      applied: true,
      fragmentTurns: 1,
      topicShiftTurns: 5,
      loopTurns: 0,
      repairTurnCount: 6,
    }, String(flag));
  }
});

Deno.test("Phase 4.5c 刀 2（R1 P1-1 反例）：beginner／game 的 debrief 一律不吃 thread 的修復點——有／無 marker 逐欄位相同", async () => {
  // 差分比對，不是拿手算數字對拍：同一段逐字稿、同一份 thread，只差 thread 上
  // 有沒有 `repairedAtUserTurns`。assisted 兩種模式都必須完全看不出差別
  // （`agency_coaching_test.ts` 已證明這個 marker 會把帳從 6 輪變 4 輪，所以
  // 「相同」是有內容的斷言）。
  const cases = [
    { practiceMode: "beginner", profileId: "practice_girl_001" },
    { practiceMode: "game", profileId: "practice_girl_004" },
  ];
  for (const c of cases) {
    const withMarker = await runDebriefWithThread({
      ...c,
      env: STANDARD_ENV,
      repairedAtUserTurns: 2,
    });
    const without = await runDebriefWithThread({
      ...c,
      env: STANDARD_ENV,
      repairedAtUserTurns: null,
    });
    assertEquals(withMarker.status, 200, c.practiceMode);
    assertEquals(without.status, 200, c.practiceMode);
    assertEquals(
      debriefAgencyTelemetry(withMarker),
      debriefAgencyTelemetry(without),
      c.practiceMode,
    );
    // prompt 也要一模一樣（telemetry 只是計數，messages 才是模型真的看到的）。
    assertEquals(
      withMarker.state.claudeCalls[0].messages,
      without.state.claudeCalls[0].messages,
      c.practiceMode,
    );
    // 而且維持 4.1 的六輪基準（＝沒有從別的入口偷偷吃到狀態）。
    assertEquals(
      debriefAgencyTelemetry(withMarker).repairTurnCount,
      6,
      c.practiceMode,
    );
  }
});

Deno.test("Phase 4.5c 刀 2（R1 U1）：逐字稿不完整（ai 則數 ≠ ledger.aiCount）時不注入 marker", async () => {
  // client 的 `_turnDtosForPrompt()` 只送最後 80 則，超過就是 suffix；marker 是
  // 整場的絕對序號，套在 suffix 上會偏右＝少算介入輪。server 用自己的帳
  // （ledger 累計的 ai 則數）判完整性，對不上就 fail-safe 不注入。
  const truncated = await runDebriefWithThread({
    env: STANDARD_ENV,
    aiCount: A25_AI_TURNS + 3, // 這次只帶上來 6 則，ledger 記 9 則＝被截過
  });
  assertEquals(truncated.status, 200);
  assertEquals(debriefAgencyTelemetry(truncated).repairTurnCount, 6);

  // 反向：ledger 對得上就照常注入（上面那支已經證明 4；這裡確認閘門是
  // 「完整性」而不是把整條路關掉）。
  const complete = await runDebriefWithThread({ env: STANDARD_ENV });
  assertEquals(debriefAgencyTelemetry(complete).repairTurnCount, 4);
});

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
  type FakeOptions,
  ledger,
  makeFake,
  makeRequest,
} from "./handler_test_fake.ts";
import { AGENCY_CLASSIFIER_RULES } from "./temperature.ts";

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
    ["error", "event", "level", "user"],
  );
  for (const secret of ["阿布達比", "東東", "deepseek-key"]) {
    assert(!JSON.stringify(warn).includes(secret));
  }
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

Deno.test("Phase 4.5b（Codex R1 P1-3）：telemetry 契約——旗標關＝零新 key 零新事件；旗標開的三種分類器結果各自的 key set 與事件名釘死", async () => {
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
  for (
    const forbidden of [
      "practice_chat_standard_agency_classifier_failed",
      "practice_chat_learning_classifier_repaired",
    ]
  ) {
    assert(!offEvents.includes(forbidden), forbidden);
  }

  // (b1) 旗標開＋分類器成功、零 repair：多兩個管理欄位 ＋ 四個判斷欄位，
  //      `*Repaired` 都不存在；事件名與旗標關那一輪完全相同。
  const ok = await runStandardTurn({
    ...base,
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", slimClassifier()],
  }, body);
  assertEquals(
    agencyKeys(ok),
    [
      ...BASE_AGENCY_KEYS,
      "accommodatingSelfFact",
      "sharedPastClaim",
      "standardClassifier",
      "standardClassifierDurationMs",
      "statePersisted",
    ].sort(),
  );
  assertEquals(eventNames(ok), offEvents);

  // (b2) 分類器回 `{}`：四個欄位全部 repair。**只有** sharedPastClaim／
  //      accommodatingSelfFact 有 `*Repaired` key（與 beginner 相同——
  //      coherence／aiChallengedThisTurn 修過只進 repaired 事件）。
  const repaired = await runStandardTurn({
    ...base,
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", "{}"],
  }, body);
  assertEquals(
    agencyKeys(repaired),
    [
      ...BASE_AGENCY_KEYS,
      "accommodatingSelfFact",
      "accommodatingSelfFactRepaired",
      "sharedPastClaim",
      "sharedPastClaimRepaired",
      "standardClassifier",
      "standardClassifierDurationMs",
      "statePersisted",
    ].sort(),
  );
  assertEquals(
    eventNames(repaired),
    // (c) 允許多出的事件只有這一個（與 beginner 同名）。
    [...offEvents.slice(0, -1), "practice_chat_learning_classifier_repaired"]
        .concat(offEvents.slice(-1)).length === eventNames(repaired).length
      ? eventNames(repaired)
      : [],
  );
  assertEquals(
    eventNames(repaired).filter((e) => !offEvents.includes(e)),
    ["practice_chat_learning_classifier_repaired"],
  );

  // (b3) 分類器整個失敗：四個判斷欄位**缺席**（與 beginner 分類器失敗時相同），
  //      只留兩個管理欄位；允許多出的事件只有 fail-open 那一個。
  const failed = await runStandardTurn({
    ...base,
    env: STANDARD_ENV,
    deepSeekReplies: ["好啊", "抱歉我不太確定"],
  }, body);
  assertEquals(
    agencyKeys(failed),
    [
      ...BASE_AGENCY_KEYS,
      "standardClassifier",
      "standardClassifierDurationMs",
      "statePersisted",
    ].sort(),
  );
  assertEquals(
    eventNames(failed).filter((e) => !offEvents.includes(e)),
    ["practice_chat_standard_agency_classifier_failed"],
  );

  // 三種情形都不得出現任何其他新事件（把 union 也釘住）。
  const allNew = new Set(
    [...eventNames(ok), ...eventNames(repaired), ...eventNames(failed)].filter(
      (e) => !offEvents.includes(e),
    ),
  );
  assertEquals([...allNew].sort(), [
    "practice_chat_learning_classifier_repaired",
    "practice_chat_standard_agency_classifier_failed",
  ]);
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

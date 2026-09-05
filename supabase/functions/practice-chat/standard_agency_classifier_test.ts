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
  return { status: response.status, state: fake.state, telemetry };
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
  recent_facts: {
    source: "practice_chat",
    aiTurnCount: 3,
    inviteStage: "soft_invite_ready",
    replyStyle: { version: 1, priorDecline: true, recentActs: ["acknowledge"] },
    futureFeature: { nested: ["keep", 1] },
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

  const recentFacts = params.p_recent_facts as Record<string, unknown>;
  assert("conversationAgency" in recentFacts, "唯一該新增的 key");
  const { conversationAgency: _agency, ...rest } = recentFacts;
  assertEquals(rest, {
    ...EXISTING_BEGINNER_ROW.recent_facts,
    // 回合數本來就每輪推進（既有語意，不是本刀改的）。
    aiTurnCount: rest.aiTurnCount,
  });
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

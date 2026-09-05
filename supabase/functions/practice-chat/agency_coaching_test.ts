// Phase 4.1 純函式門檻的兩側正反例。逐字稿全部是合成的，不打任何模型。
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  debriefAgencyLedgerFor,
  hintAgencyCoachingFor,
} from "./agency_coaching.ts";
import {
  agencyPolicyFor,
  agencyThresholdsFor,
  detectAgencyEvidence,
  INITIAL_CONVERSATION_AGENCY_STATE,
  nextConversationAgencyState,
} from "./conversation_agency.ts";
import { agencyProfileFor } from "./agency_profile.ts";
import type { PracticeTurn } from "./validate.ts";
import type { AgencyCoachingContext } from "./agency_coaching.ts";

const t = (role: "user" | "ai", text: string): PracticeTurn =>
  ({ role, text }) as PracticeTurn;

// 中性基準：practice_girl_008 的 agency profile（skepticism 2）不位移 holdAt，
// 所以這一組 ctx 算出來的門檻就是一般難度表本身。
const CTX: AgencyCoachingContext = {
  difficulty: "normal",
  isGame: false,
  profileId: "practice_girl_008",
};

// ── 渲染層：有／無教練證據時，prompt 只差那一行／那一段 ──────────────────
import { buildHintMessages } from "./hint.ts";
import { buildDebriefMessages } from "./prompt.ts";
import { resolvePracticeProfile } from "./practice_persona.ts";
import type { DebriefAgencyLedger } from "./agency_coaching.ts";

const testProfile = resolvePracticeProfile({ profileId: "practice_girl_004" });
const HINT_TURNS = [
  t("user", "東東"),
  t("ai", "東東是誰"),
  t("user", "阿布達比"),
  t("ai", "阿布達比？那是哪裡"),
];

const joined = (messages: { role: string; content: string }[]) =>
  messages.map((m) => `${m.role}\n${m.content}`).join("\n\n");

function hintPrompt(
  coaching?: Parameters<typeof buildHintMessages>[0]["agencyCoaching"],
) {
  return joined(buildHintMessages({
    turns: HINT_TURNS,
    profile: testProfile,
    practiceMode: "beginner",
    temperatureScore: 40,
    agencyCoaching: coaching,
  }));
}

Deno.test("hint coaching：她剛問完＋玩家丟片段 → answer_her_question", () => {
  const turns = [
    t("user", "東東"),
    t("ai", "東東是誰"),
    t("user", "阿布達比"),
    t("ai", "阿布達比？那是哪裡"),
  ];
  assertEquals(hintAgencyCoachingFor(turns, null, CTX), {
    kind: "answer_her_question",
    unresolvedCount: 1,
  });
});

Deno.test("hint coaching：有效短答（她問→他答、零欠債）→ none", () => {
  const turns = [
    t("user", "我今天去看了場電影"),
    t("ai", "什麼片"),
    t("user", "沙丘"),
    t("ai", "好看嗎"),
  ];
  assertEquals(hintAgencyCoachingFor(turns, null, CTX), {
    kind: "none",
    unresolvedCount: 0,
  });
});

Deno.test("hint coaching：她沒問過、玩家丟無前文片段 → none（不亂點火）", () => {
  const turns = [t("user", "台北"), t("ai", "哈哈")];
  const got = hintAgencyCoachingFor(turns, null, CTX);
  assertEquals(got.kind, "none");
  assertEquals(got.unresolvedCount, 0);
});

Deno.test("hint coaching：欠債 ≥2 → stop_dropping_words（比 answer 優先）", () => {
  const turns = [
    t("user", "東東"),
    t("ai", "東東是誰"),
    t("user", "阿布達比"),
    t("ai", "那是哪裡"),
    t("user", "韓國"),
    t("ai", "怎麼突然講韓國"),
  ];
  const got = hintAgencyCoachingFor(turns, null, CTX);
  assertEquals(got.kind, "stop_dropping_words");
  assertEquals(got.unresolvedCount >= 2, true);
});

Deno.test("hint coaching：同一個詞原樣再丟一次 → stop_dropping_words", () => {
  const turns = [
    t("user", "阿布達比"),
    t("ai", "那是哪裡"),
    t("user", "阿布達比"),
    t("ai", "你在說什麼"),
  ];
  assertEquals(
    hintAgencyCoachingFor(turns, null, CTX).kind,
    "stop_dropping_words",
  );
});

Deno.test("hint coaching：她上一則沒有問句標記，但狀態記得她問過意圖 → answer_her_question", () => {
  const turns = [
    t("user", "台北"),
    t("ai", "喔"),
    t("user", "高雄"),
    t("ai", "喔"),
  ];
  assertEquals(
    hintAgencyCoachingFor(turns, {
      ...INITIAL_CONVERSATION_AGENCY_STATE,
      lastAgencyAct: "ask_intent",
    }, CTX).kind,
    "answer_her_question",
  );
  // 同一份逐字稿、沒有狀態＝她沒問過 → 不點火。
  assertEquals(hintAgencyCoachingFor(turns, null, CTX).kind, "none");
});

Deno.test("debrief ledger：連環丟詞的場記到序號與分類", () => {
  const turns = [
    t("user", "東東"),
    t("ai", "東東是誰"),
    t("user", "阿布達比"),
    t("ai", "那是哪裡"),
    t("user", "韓國"),
    t("ai", "怎麼突然講韓國"),
  ];
  const ledger = debriefAgencyLedgerFor(turns, CTX);
  assertEquals(ledger.repairTurns, [1, 2, 3]);
  assertEquals(
    ledger.fragmentTurns + ledger.topicShiftTurns + ledger.loopTurns,
    3,
  );
  assertEquals(ledger.fragmentTurns, 1);
});

Deno.test("debrief ledger：正常對話全 0", () => {
  const turns = [
    t("user", "我今天下班超累的"),
    t("ai", "怎麼了"),
    t("user", "開了一整天的會"),
    t("ai", "辛苦欸"),
    t("user", "妳今天呢"),
    t("ai", "還好啦"),
  ];
  assertEquals(debriefAgencyLedgerFor(turns, CTX), {
    fragmentTurns: 0,
    topicShiftTurns: 0,
    loopTurns: 0,
    repairTurns: [],
    repairTurnCount: 0,
  });
});

Deno.test("debrief ledger：序號清單最多 10 個，計數不設上限", () => {
  const turns: PracticeTurn[] = [];
  for (let i = 0; i < 12; i++) {
    turns.push(t("user", `城市${i}`));
    turns.push(t("ai", "那是哪裡"));
  }
  const ledger = debriefAgencyLedgerFor(turns, CTX);
  assertEquals(ledger.repairTurns.length, 10);
  assertEquals(
    ledger.fragmentTurns + ledger.topicShiftTurns + ledger.loopTurns,
    12,
  );
  // Codex R1 P2：telemetry 記的是真實總數，不是被 10 截過的清單長度。
  assertEquals(ledger.repairTurnCount, 12);
  // prompt 那一段仍然只列 10 個序號。
  const rendered = joined(
    buildDebriefMessages(turns, testProfile, {
      practiceMode: "beginner",
      agencyLedger: ledger,
    }),
  );
  assertEquals(rendered.includes("第 1、2、3、4、5、6、7、8、9、10 則"), true);
  assertEquals(rendered.includes("、11、"), false);
});

Deno.test("buildHintMessages：不傳 agencyCoaching 與傳 none 時 prompt 逐字相同", () => {
  const base = hintPrompt();
  assertEquals(hintPrompt(null), base);
  assertEquals(hintPrompt({ kind: "none", unresolvedCount: 0 }), base);
});

Deno.test("buildHintMessages：兩個 kind 各自只多一行，其餘逐字不變", () => {
  const base = hintPrompt();
  for (const kind of ["answer_her_question", "stop_dropping_words"] as const) {
    const withLine = hintPrompt({ kind, unresolvedCount: 2 });
    const diff = withLine.split("\n").filter((line) =>
      !base.split("\n").includes(line)
    );
    assertEquals(diff.length, 1, `${kind} 應該只多一行，實際 ${diff.length}`);
    assertEquals(diff[0].startsWith("這輪先處理沒接上："), true);
    // 移掉那一行之後必須跟 base 逐字相同。
    assertEquals(withLine.replace(`${diff[0]}\n`, ""), base);
    assertEquals(withLine.length - base.length < 300, true);
  }
});

function debriefPrompt(
  ledger?: DebriefAgencyLedger | null,
) {
  return joined(buildDebriefMessages(HINT_TURNS, testProfile, {
    practiceMode: "beginner",
    agencyLedger: ledger,
  }));
}

Deno.test("buildDebriefMessages：不傳 ledger 與全 0 ledger 時 prompt 逐字相同", () => {
  const base = debriefPrompt();
  assertEquals(debriefPrompt(null), base);
  assertEquals(
    debriefPrompt({
      fragmentTurns: 0,
      topicShiftTurns: 0,
      loopTurns: 0,
      repairTurns: [],
      repairTurnCount: 0,
    }),
    base,
  );
});

Deno.test("buildDebriefMessages：有介入輪時只多一段，含序號與『不算他的分』", () => {
  const base = debriefPrompt();
  const withLedger = debriefPrompt(debriefAgencyLedgerFor(HINT_TURNS, CTX));
  assertEquals(withLedger === base, false);
  assertEquals(withLedger.includes("agencyStructuralLedger"), true);
  assertEquals(withLedger.includes("第 1、2 則"), true);
  assertEquals(withLedger.includes("這些需要她補救的輪次不算他的分"), true);
  assertEquals(withLedger.length - base.length < 300, true);
});

// ── 門檻同源：難度／角色 profile 真的會改變這份帳（派 Codex 前先修的 P1）──
// 逐字稿取自 `tools/practice-agency-eval/out/2026-09-05-p40-beginner-on.json`
// 的 A25（連環丟地名），只保留文字。
const A25_TURNS: PracticeTurn[] = [
  t("user", "東東"),
  t("ai", "東東？誰啊"),
  t("user", "阿布打比"),
  t("ai", "蛤 你打什麼 看不懂"),
  t("user", "清邁"),
  t("ai", "喔 清邁\n我還沒去過那邊\n聽說食物很讚"),
  t("user", "好市多"),
  t(
    "ai",
    "你怎麼突然跳這麼多地方\n一下東東一下阿布達比\n現在又好市多\n到底在講哪個",
  ),
  t("user", "曼谷"),
  t("ai", "你是在背地名嗎\n我快跟不上你了啦"),
  t("user", "馬尼拉"),
  t("ai", "好 你慢慢背\n我累了先這樣"),
];

Deno.test("debrief ledger：真實 A25 逐字稿上門檻不改變分帳（誠實的天花板，不是沒接線）", () => {
  // `holdAt` 只在 `aiQuestionedInLoop`（**嚴格**問句判準）＋`bare_fragment`
  // 同時成立時才打得開，而這一段 A25 裡她的每一句反問都是中文無標記問句
  // （「東東？誰啊」「到底在講哪個」），`aiAskedQuestionStrict` 全判 false。
  // 所以難度／profile 在這一段上真的算不出差別——這是判準的既有天花板
  // （`conversation_agency.ts` 檔頭寫明的「接受的代價」），不是門檻沒接進來。
  const neutral = debriefAgencyLedgerFor(A25_TURNS, CTX);
  for (
    const ctx of [
      { ...CTX, difficulty: "easy" as const },
      { ...CTX, difficulty: "challenge" as const },
      { ...CTX, profileId: "practice_girl_001" },
      { ...CTX, profileId: "practice_girl_003" },
    ]
  ) {
    assertEquals(debriefAgencyLedgerFor(A25_TURNS, ctx), neutral);
  }
  assertEquals(neutral.repairTurns, [1, 2, 3, 4, 5, 6]);
  assertEquals(neutral.loopTurns, 0);
});

// 同樣的形態，但她的反問帶句尾標記（「呢」），強制格的閘門才打得開。
const MARKED_QUESTION_TURNS: PracticeTurn[] = [
  t("ai", "你最想去哪裡呢"),
  t("user", "韓國"),
  t("ai", "喔 我也想去"),
  t("user", "好市多"),
  t("ai", "嗯"),
  t("user", "曼谷"),
];

Deno.test("debrief ledger：閘門打得開時，難度與角色 skepticism 真的改變 loop／shift 分帳", () => {
  const neutral = debriefAgencyLedgerFor(MARKED_QUESTION_TURNS, CTX);
  // 一般難度（holdAt 2）：第 3 則玩家訊息落進低連貫迴圈。
  assertEquals(neutral.repairTurns, [2, 3]);
  assertEquals(neutral.loopTurns, 1);
  assertEquals(neutral.topicShiftTurns, 0);
  for (
    const ctx of [
      // 輕鬆難度 holdAt 3：同一則變成「跳題」而不是「收掉迴圈」。
      { ...CTX, difficulty: "easy" as const },
      // practice_girl_003：skepticism 1 → 一般難度的 holdAt 被位移成 3。
      { ...CTX, profileId: "practice_girl_003" },
    ]
  ) {
    const shifted = debriefAgencyLedgerFor(MARKED_QUESTION_TURNS, ctx);
    assertEquals(shifted.repairTurns, neutral.repairTurns);
    assertEquals(shifted.loopTurns, 0);
    assertEquals(shifted.topicShiftTurns, 1);
  }
  // Game 模式套挑戰門檻（`agencyThresholdsFor` 的既有規則），與一般難度在這一段
  // 同分帳（holdAt 1 與 2 都在第 3 則觸發）。
  assertEquals(
    debriefAgencyLedgerFor(MARKED_QUESTION_TURNS, { ...CTX, isGame: true }),
    debriefAgencyLedgerFor(MARKED_QUESTION_TURNS, {
      ...CTX,
      difficulty: "challenge",
    }),
  );
});

// ── Codex R1 P2／U 的三個補測 ─────────────────────────────────────────────

// 兩個座標系必須看得出不同：連續兩則 AI 訊息讓「逐字稿 index」與「第 N 則玩家
// 訊息」錯開（第 3 則玩家訊息的 index 是 5）。
const OVERLAP_TURNS: PracticeTurn[] = [
  t("user", "東東"),
  t("ai", "東東是誰"),
  t("ai", "還是你打錯字"),
  t("user", "阿布達比"),
  t("ai", "那是哪裡"),
  t("user", "清邁"),
  t("ai", "喔"),
];

Deno.test("debrief ledger prompt：重疊輪次換算成同一個座標（玩家序號）後明列", () => {
  // `AppliedHintTurn.turnIndex` 是**逐字稿 index**（`validate.ts` 以
  // `turns[turnIndex]?.role !== "user"` 驗），`repairTurns` 是第 N 則玩家訊息。
  // index 5 ＝ 第 3 則玩家訊息，兩個數字刻意不同（Codex R2 U）。
  assertEquals(OVERLAP_TURNS[5].role, "user");
  const applied = [{
    turnIndex: 5,
    type: "steady" as const,
    originalHintText: "清邁",
    sentText: "清邁",
    exact: true,
  }];
  const ledger = debriefAgencyLedgerFor(OVERLAP_TURNS, CTX);
  assertEquals(ledger.repairTurns.includes(3), true);
  const text = joined(
    buildDebriefMessages(OVERLAP_TURNS, testProfile, {
      practiceMode: "beginner",
      appliedHintTurns: applied,
      agencyLedger: ledger,
    }),
  );
  assertEquals(text.includes("hintAssistedTurns"), true);
  assertEquals(text.includes("agencyStructuralLedger"), true);
  // 明列的是換算後的玩家序號 3，不是 hint 自己的 turnIndex 5。
  assertEquals(
    text.includes(
      "其中第 3 則是他照 Hint 送出的，照 hintAssistedTurns 的歸責規則歸給「這輪教練路線」，不算他的缺口。",
    ),
    true,
  );
  assertEquals(text.includes("其中第 5 則是他照 Hint"), false);
  assertEquals(text.includes("上面的最終 dateChance 判準也適用這一條。"), true);
  const withoutLedger = joined(
    buildDebriefMessages(OVERLAP_TURNS, testProfile, {
      practiceMode: "beginner",
      appliedHintTurns: applied,
    }),
  );
  assertEquals(text.length - withoutLedger.length < 300, true);
});

Deno.test("debrief ledger prompt：沒有交集時不印那一句（規則不落空）", () => {
  const applied = [{
    turnIndex: 0,
    type: "warm_up" as const,
    originalHintText: "東東",
    sentText: "東東",
    exact: true,
  }];
  const ledger = debriefAgencyLedgerFor(OVERLAP_TURNS, CTX);
  const text = joined(
    buildDebriefMessages(OVERLAP_TURNS, testProfile, {
      practiceMode: "beginner",
      // 第 1 則玩家訊息若不在 repairTurns 裡就沒有交集；在的話這個案例改用
      // 一個不存在的 index。
      appliedHintTurns: ledger.repairTurns.includes(1)
        ? [{ ...applied[0], turnIndex: 999 }]
        : applied,
      agencyLedger: ledger,
    }),
  );
  assertEquals(text.includes("照 Hint 送出的"), false);
  assertEquals(text.includes("agencyStructuralLedger"), true);
});

Deno.test("debrief prompt 順序：最終 dateChance 判準在 agencyStructuralLedger 之前（越後越終局）", () => {
  const text = joined(
    buildDebriefMessages(A25_TURNS, testProfile, {
      practiceMode: "beginner",
      agencyLedger: debriefAgencyLedgerFor(A25_TURNS, CTX),
    }),
  );
  assertEquals(
    text.indexOf("最終 dateChance 判準") <
      text.indexOf("agencyStructuralLedger"),
    true,
  );
});

Deno.test("hint 教練行：不預設一定有建議句（allowNoPasteableReply），也不改本輪方向", () => {
  for (const kind of ["answer_her_question", "stop_dropping_words"] as const) {
    const text = joined(buildHintMessages({
      allowNoPasteableReply: true,
      turns: HINT_TURNS,
      profile: testProfile,
      practiceMode: "beginner",
      temperatureScore: 40,
      agencyCoaching: { kind, unresolvedCount: 2 },
    }));
    // no-pasteable 的既有出口還在，agency 行不得寫死「兩顆球都要」。
    assertEquals(text.includes("noPasteableReason"), true);
    assertEquals(text.includes("建議句（若有）"), true);
    assertEquals(text.includes("兩顆球都要"), false);
    assertEquals(text.includes("這一行不改本輪方向與邀約判斷。"), true);
  }
});

Deno.test("hint 教練行：Game 模式的本輪方向與邀約段不被覆蓋", () => {
  const gameOpts = {
    turns: HINT_TURNS,
    profile: testProfile,
    practiceMode: "game" as const,
    temperatureScore: 40,
    hintsRemaining: 3,
  };
  const base = joined(buildHintMessages(gameOpts));
  const withLine = joined(buildHintMessages({
    ...gameOpts,
    agencyCoaching: { kind: "answer_her_question", unresolvedCount: 1 },
  }));
  assertEquals(base.includes("本輪方向："), true);
  // 既有段落逐字保留，只多那一行。
  const added = withLine.split("\n").filter((line) =>
    !base.split("\n").includes(line)
  );
  assertEquals(added.length, 1);
  assertEquals(added[0].startsWith("這輪先處理沒接上："), true);
  assertEquals(withLine.replace(`${added[0]}\n`, ""), base);
});

Deno.test("hint 用真正持久化的 state 不會把同一輪的欠債再算一次（Codex R2 U）", () => {
  // 1) chat 那一輪：逐字稿以玩家訊息結尾，結構層算出欠債 1。
  const chatTurns: PracticeTurn[] = [
    t("ai", "你最想去哪裡呢"),
    t("user", "韓國"),
    t("ai", "喔 我也想去"),
    t("user", "好市多"),
  ];
  const thresholds = agencyThresholdsFor(
    CTX.difficulty,
    CTX.isGame,
    agencyProfileFor(CTX.profileId),
  );
  const chatEvidence = detectAgencyEvidence(chatTurns, null);
  const chatDecision = agencyPolicyFor(chatEvidence, thresholds);
  assertEquals(chatEvidence.unresolvedCount, 1);
  assertEquals(chatDecision.situation, "abrupt_topic_shift");

  // 2) handler 把這一輪的決策推進成持久化狀態（`classifierSignal` 用 chat 路徑
  //    真的會帶的形狀之一：分類器判 disconnected）。
  const persisted = nextConversationAgencyState(null, chatDecision, {
    coherence: "disconnected",
  });
  assertEquals(persisted.unresolvedCount, 1);

  // 3) 同一場的 hint：逐字稿多了她的回覆，state 是上面那一份。
  const hintTurns: PracticeTurn[] = [...chatTurns, t("ai", "好市多？")];
  const coaching = hintAgencyCoachingFor(hintTurns, persisted, CTX);
  // `detectAgencyEvidence` 一律從逐字稿重算，不把 `prev.unresolvedCount` 當
  // 起點，所以不會變成 2；欠債 1 ＋ 她剛問了 → 先回答她。
  assertEquals(coaching.unresolvedCount, chatEvidence.unresolvedCount);
  assertEquals(coaching.kind, "answer_her_question");
  // 反證：真的多算一次的話會跨過門檻升成 stop_dropping_words。
  assertEquals(
    hintAgencyCoachingFor(hintTurns, null, CTX).unresolvedCount,
    coaching.unresolvedCount,
  );
});

// ── Phase 4.5c 刀 2：debrief 回放吃 thread 上的持久化修復點 ────────────────
/** 帶 `repairedAtUserTurns` 的最小合法狀態；其餘欄位刻意是中性預設。 */
const stateWithRepairAt = (n: number) => ({
  version: 1 as const,
  lastCoherence: "ambiguous" as const,
  unresolvedCount: 0 as const,
  priorChallengeIssued: false,
  lastAgencyAct: null,
  repairedAtUserTurns: n,
});

Deno.test("Phase 4.5c 刀 2：省略／null 的持久化狀態＝逐字沿用 4.1 的純結構回放", () => {
  assertEquals(
    debriefAgencyLedgerFor(A25_TURNS, CTX),
    debriefAgencyLedgerFor(A25_TURNS, CTX, null),
  );
  // 4.1 的基準（A25 六則玩家訊息全部被判成需要她補救）。
  assertEquals(debriefAgencyLedgerFor(A25_TURNS, CTX), {
    fragmentTurns: 1,
    topicShiftTurns: 5,
    loopTurns: 0,
    repairTurns: [1, 2, 3, 4, 5, 6],
    repairTurnCount: 6,
  });
});

Deno.test("Phase 4.5c 刀 2：持久化的修復點真的注回回放——第 2 則之後才重新算欠債", () => {
  // 分類器在第 2 則判 `connected`：第 2、3 則不再算成介入輪，帳從 6 掉到 4。
  assertEquals(debriefAgencyLedgerFor(A25_TURNS, CTX, stateWithRepairAt(2)), {
    fragmentTurns: 1,
    topicShiftTurns: 3,
    loopTurns: 0,
    repairTurns: [1, 4, 5, 6],
    repairTurnCount: 4,
  });
});

Deno.test("Phase 4.5c 刀 2：定位不到的修復點（比這次逐字稿的玩家則數大）＝當成沒有", () => {
  // 逐字稿被截窗時 marker 會指到不存在的位置——寧可不用，也不要指錯地方
  // （與 `detectAgencyEvidence`／`nextConversationAgencyState` 的 R1 P1-4a 同規則）。
  for (const n of [7, 99]) {
    assertEquals(
      debriefAgencyLedgerFor(A25_TURNS, CTX, stateWithRepairAt(n)),
      debriefAgencyLedgerFor(A25_TURNS, CTX, null),
      `marker=${n}`,
    );
  }
  // 只有 `repairedAtUserTurns` 被消費：其餘欄位（結尾的累積值）不得影響回放。
  assertEquals(
    debriefAgencyLedgerFor(A25_TURNS, CTX, {
      ...stateWithRepairAt(2),
      lastCoherence: "connected",
      unresolvedCount: 3,
      priorChallengeIssued: true,
      lastAgencyAct: "hold_position",
      lowValueStreak: 3,
      checkedOut: true,
    }),
    debriefAgencyLedgerFor(A25_TURNS, CTX, stateWithRepairAt(2)),
  );
});

Deno.test("Phase 4.5c 刀 2：standard 與 beginner 同源——同一份 turns／ctx／state 一定同一份帳（函式沒有 practiceMode 分支）", () => {
  // 4.5b 之後 standard 也會寫 `repairedAtUserTurns`，所以兩種模式的差別只剩
  // handler 要不要把 state 傳進來（旗標閘門），不是這支函式自己有近似分支。
  for (const n of [null, 1, 2, 4, 6]) {
    const state = n === null ? null : stateWithRepairAt(n);
    assertEquals(
      debriefAgencyLedgerFor(A25_TURNS, CTX, state),
      debriefAgencyLedgerFor(A25_TURNS, { ...CTX }, state),
      `marker=${n}`,
    );
  }
});

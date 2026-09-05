import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  AGENCY_THRESHOLDS,
  type AgencyApplication,
  type AgencyEvidence,
  agencyModeFor,
  agencyPolicyFor,
  agencyShapeExperimentFor,
  agencyThresholdsFor,
  aiAskedQuestion,
  aiAskedQuestionStrict,
  aiAskedYesNoQuestion,
  type ConversationAgencyState,
  detectAgencyEvidence,
  isAcceptingPlanAct,
  isClarifyingAct,
  isQuestionText,
  isQuestionTextTolerant,
  isYesNoShortAnswer,
  nextConversationAgencyState,
  parseConversationAgencyState,
  truncateAgencyShape,
  utteranceShapeOf,
} from "./conversation_agency.ts";
import {
  AGENCY_SET_LINE,
  computeAgencyDecision,
} from "./turn_response_plan.ts";
import { buildRelationshipThreadRpcParams } from "./relationship_thread.ts";
import type { PracticeTurn } from "./validate.ts";

const u = (text: string): PracticeTurn => ({ role: "user", text });
const a = (text: string): PracticeTurn => ({ role: "ai", text });
const policy = (turns: PracticeTurn[]) =>
  agencyPolicyFor(detectAgencyEvidence(turns));
const policyAt = (
  turns: PracticeTurn[],
  difficulty: "easy" | "normal" | "challenge",
  isGame = false,
  prev: ConversationAgencyState | null = null,
) =>
  agencyPolicyFor(
    detectAgencyEvidence(turns, prev),
    agencyThresholdsFor(difficulty, isGame),
  );

/**
 * Phase 4.3：assisted 模式走過一輪之後的狀態。`aiClarified` 就是分類器對
 * **她上一則實際生成文字**回報的 `aiChallengedThisTurn`；`coherence` 是同一輪
 * 分類器的連貫度判斷。這兩個是 `clarify_ignored` 強制格唯一吃的跨輪訊號。
 */
const stateWith = (
  aiClarified: boolean | null,
  coherence: ConversationAgencyState["lastCoherence"] = "disconnected",
): ConversationAgencyState => ({
  version: 1,
  lastCoherence: coherence,
  unresolvedCount: 1,
  priorChallengeIssued: false,
  lastAgencyAct: null,
  ...(aiClarified === null ? {} : { aiClarifiedLastTurn: aiClarified }),
});

Deno.test("utteranceShape：明示換題 > 問句 > 招呼 > 第一人稱 > 短答候選 > 裸片段", () => {
  assertEquals(
    utteranceShapeOf("對了 講到韓國 我看到機票特價", true),
    "explicit_pivot",
  );
  assertEquals(utteranceShapeOf("你平常在幹嘛", false), "question");
  assertEquals(utteranceShapeOf("哈哈哈", false), "reaction");
  assertEquals(utteranceShapeOf("嗨嗨", false), "reaction");
  assertEquals(utteranceShapeOf("我最近開始練重訓", false), "self_share");
  assertEquals(utteranceShapeOf("韓國", true), "answer_candidate");
  assertEquals(utteranceShapeOf("韓國", false), "bare_fragment");
  assertEquals(utteranceShapeOf("   ", false), "unknown");
});

Deno.test("utteranceShape 沒有任何字數條件（Codex round-2 P1-1）：長裸敘述仍是片段、短有效答不是", () => {
  // 40 個字、沒有問句標記、沒有第一人稱、不是明示換題、她上一則沒在問問題
  // ——結構線索全空集合，照樣是 bare_fragment。舊版靠「≤8 code units」判，
  // 這句會被放行；現在不會。
  const longBare = "路上那間店的招牌昨天換成新的顏色看起來怪怪的整條街都變了";
  assert(longBare.length >= 25);
  assertEquals(utteranceShapeOf(longBare, false), "bare_fragment");
  // 反向：兩個字的「韓國」在她剛問完問題時是有效短答（A01），不是片段家族裡
  // 需要被質疑的那一種——判準是「她上一則在問問題」，不是「這句很短」。
  assertEquals(utteranceShapeOf("韓國", true), "answer_candidate");
  assertEquals(
    agencyPolicyFor(
      detectAgencyEvidence([a("那你最想去哪個國家玩"), u("韓國")]),
    ).situation,
    null,
  );
  // Codex round-2 P1-1：同一個長裸敘述當開場，**不再** forced 只問意思。
  // 「路上那間店的招牌換了顏色」是完整、可理解的第三人稱陳述句，強制澄清
  // 就是誤判；結構層分不出它跟真正的亂丟詞，所以兩個選項都給、由看得到全文
  // 的她挑。強制只留給信心最高的兩格（同詞原樣再丟一次、欠債到門檻）。
  const longDecision = agencyPolicyFor(detectAgencyEvidence([u(longBare)]));
  assertEquals(longDecision.situation, "ambiguous_fragment");
  assertEquals(longDecision.policyMode, "bounded");
  assertEquals(longDecision.forcedAct, null);
  assertEquals(longDecision.allowedActs, ["acknowledge", "ask_intent"]);
});

Deno.test("明示換題詞：否定、引用、慣用語不算宣告轉場（Codex P1）", () => {
  // 否定：「先不要換個話題」不是宣告轉場（不是 explicit_pivot；落到其他 shape
  // 是合理的，「我還沒講完」本身是第一人稱分享）。
  assertEquals(
    utteranceShapeOf("先不要換個話題 我還沒講完", false),
    "self_share",
  );
  // 不再判成 explicit_pivot 之後落到 bare_fragment（短句、非第一人稱、非問句）
  // 是合理的下一層——重點只是「不再被當成明示換題」。
  assertEquals(utteranceShapeOf("不要換個話題啦", false), "bare_fragment");
  // 「說到一半」是抱怨被打斷，不是宣告轉場（落到 bare_fragment 是合理的
  // 下一層——重點只是「不再被當成明示換題」）。
  assertEquals(
    utteranceShapeOf("你每次都說到一半就不講了", false),
    "bare_fragment",
  );
  // 引號內引用別人講過的詞，不是自己在宣告轉場。
  assertEquals(
    utteranceShapeOf("他那時候就說「對了」然後就不說了", false),
    "bare_fragment",
  );
  // 正常宣告轉場照樣要判到。
  assertEquals(utteranceShapeOf("對了 你看新聞了嗎", false), "explicit_pivot");
  assertEquals(utteranceShapeOf("話說 你今天吃了嗎", false), "explicit_pivot");
});

Deno.test("結構證據：連續同角色 turn 也只取最後 8 則玩家訊息（Codex P1）", () => {
  // 連續 10 則玩家訊息、中間沒有 AI 插話：window 必須是最後 8 則，不是
  // 「最後 16 則 turns 裡湊出來的」。前兩則（會被 window 排除）如果是低資訊
  // 片段，不該影響第 9、10 則的 unresolvedCount。
  const manyUserTurns: PracticeTurn[] = [
    u("A"), // 會被排除在 window 外
    u("B"), // 會被排除在 window 外
    u("我最近在忙一個新專案 進度有點卡"), // self_share，重置未解計數
    u("韓國"),
    u("東京"),
    u("清邁"),
    u("曼谷"),
    u("巴黎"),
    u("倫敦"),
    u("柏林"),
  ];
  const e = detectAgencyEvidence(manyUserTurns);
  // window 只看最後 8 則：self_share 之後累積 6 個低資訊片段，clamp 在 3。
  assertEquals(e.unresolvedCount, 3);

  // 連續 AI 訊息也一樣：只看最後 8 則玩家訊息，不受中間插的 AI 則數影響。
  const manyAiTurns: PracticeTurn[] = [
    u("嗨嗨 剛看到你的自介"),
    a("哈囉"),
    a("在幹嘛"),
    a("怎麼不說話"),
    u("我最近開始練重訓 一週去三次"),
    a("哇 好厲害"),
    u("hyrox"),
  ];
  const e2 = detectAgencyEvidence(manyAiTurns);
  assertEquals(e2.unresolvedCount, 0);
  assertEquals(e2.precedingUserContext, true);
});

Deno.test("結構證據：未解片段累加、被完整訊息清零、同詞重複、前文有無", () => {
  const alice = [
    u("東東"),
    a("東東是誰"),
    u("阿布打比"),
    a("阿布達比？你有去那邊玩喔？"),
    u("清邁"),
    a("清邁很讚欸 我上個月才去過"),
    u("好市多"),
  ];
  const e = detectAgencyEvidence(alice);
  assertEquals(e.unresolvedCount, 3);
  // Codex round-2 P1-2：standard 沒有持久化的 lastAgencyAct，「連續兩則未解
  // ＝一定質疑過」那個近似值已經拿掉，未帶 prev 時一律 false。
  assertEquals(e.priorChallengeIssued, false);
  assertEquals(e.precedingUserContext, false);
  assertEquals(e.repeatedExactToken, false);

  // 玩家解釋（第一人稱長句）把未解片段清零（報告 §7.5）。
  const repaired = detectAgencyEvidence([
    u("韓國"),
    a("嗯？"),
    u("啊抱歉 我在列我下個月可能會去的地方 想到什麼打什麼"),
    a("喔喔"),
    u("日本"),
  ]);
  assertEquals(repaired.unresolvedCount, 0);
  assertEquals(repaired.precedingUserContext, true);
  assertEquals(repaired.priorChallengeIssued, false);

  const repeated = detectAgencyEvidence([u("好市多"), a("？"), u("好市多")]);
  assertEquals(repeated.repeatedExactToken, true);
  // 空白差異不算新東西。
  assertEquals(
    detectAgencyEvidence([u("好市多"), a("？"), u(" 好 市多 ")])
      .repeatedExactToken,
    true,
  );
});

Deno.test("有效短答與明示換題永遠不介入（A01／A03／A07／A09 對照組）", () => {
  // A01：她剛問完問題、前面沒有未解片段 → 有效短答。
  const a01 = policy([a("那你最想去哪個國家玩"), u("韓國")]);
  assertEquals(a01.evidence.utteranceShape, "answer_candidate");
  assertEquals(a01.situation, null);
  assertEquals(a01.allowedActs, []);

  // A03：明示換題。
  const a03 = policy([
    u("嗨嗨 今天過得還好嗎"),
    a("還可以啊 你呢"),
    u("對了 講到韓國 我最近一直看到韓國機票在特價"),
  ]);
  assertEquals(a03.evidence.utteranceShape, "explicit_pivot");
  assertEquals(a03.situation, null);

  // A07／A09：玩家先給了前文，片段緊接著出現（unresolvedCount＝0、有前文）→
  // 結構上跟 A01／A03 同一等級：完全不介入，allowedActs 必須是空集合
  // （Codex P1：舊版仍把 ask_intent 放進候選清單，測試只斷言排除
  // challenge_relevance，不足以證明「結構上永遠不會質疑」——現在四個質疑／
  // 收尾型 act 逐一斷言排除，不再只挑一個）。
  for (
    const turns of [
      [u("我最近在學日文 發音真的有夠難"), a("真的 我也覺得"), u("紅豆泥")],
      [u("我最近開始練重訓 一週去三次"), a("哇 好厲害"), u("hyrox")],
    ]
  ) {
    const d = policy(turns);
    assertEquals(d.situation, null);
    assertEquals(d.allowedActs, []);
    assertEquals(d.forcedAct, null);
    for (
      const act of [
        "ask_intent",
        "challenge_relevance",
        "hold_position",
        "end_low_value_loop",
      ] as const
    ) {
      assert(!d.allowedActs.includes(act), `A07/A09 不得包含 ${act}`);
    }
  }

  // 她剛問完問題，玩家用第一人稱回答＝分享，一樣不介入。
  assertEquals(
    policy([u("嗨嗨 剛看到你的自介"), a("哈囉"), u("我在台中做設計的")])
      .situation,
    null,
  );
  // A15：玩家道歉並回到原題（第一人稱長句）→ 不介入，不會被強制 hold。
  assertEquals(
    policy([
      u("好市多"),
      a("？"),
      u("曼谷"),
      a("你在幹嘛"),
      u("抱歉啦 剛剛在跟朋友傳訊息傳錯視窗了 我們剛剛聊到哪"),
    ]).situation,
    null,
  );
});

Deno.test("forced 只留給同詞重複與欠債到門檻；第一個片段一律 bounded（Codex R2 P1-1）", () => {
  // 無前文裸片段（A02／A08）：結構條件全部是「線索不存在」，但那個集合也抓得到
  // 完整的第三人稱陳述句，所以**不再** forced，改成兩選一 bounded。
  const a02 = policy([u("韓國")]);
  assertEquals(a02.situation, "ambiguous_fragment");
  assertEquals(a02.allowedActSetId, "fragment_no_context_v1");
  assertEquals(a02.policyMode, "bounded");
  assertEquals(a02.forcedAct, null);
  assertEquals(a02.allowedActs, ["acknowledge", "ask_intent"]);

  // A04：她問了問題、玩家丟別的詞 → 結構上這仍是 answer_candidate（她剛問完），
  // 所以走 P1-c 那條 bounded：永遠有「接住」，也永遠有「拉回你剛才問的」。
  // 結構層分不出「阿布達比」跟「貓」哪個算答案（那是語意），只保證兩邊都在
  // 候選清單裡，由看得到全文的她挑（Codex round-1 P1-c）。
  const a04 = policy([u("東東"), a("東東是誰"), u("阿布達比")]);
  assertEquals(a04.situation, "abrupt_topic_shift");
  assertEquals(a04.allowedActSetId, "answer_or_challenge_v1");
  assertEquals(a04.policyMode, "bounded");
  assertEquals(a04.forcedAct, null);
  // Phase 3.0：接受仍在候選裡，但是**有條件的**——「他這句真的接得上就接受」，
  // 不是無條件的 acknowledge（那正是 Eric 回報的「她把新詞當成答案順著聊」）。
  assertEquals(a04.allowedActs, [
    "accept_if_answered",
    "challenge_relevance",
  ]);
  assert(a04.allowedActs.some(isAcceptingPlanAct));

  // 她**沒有**問問題、玩家連丟詞 → topic_shift_v1。Codex round-1（新項）P1-2：
  // 這個清單也必須含「接住」——結構層看不出第二句是不是連貫的敘事，不能
  // deterministic 地把「順著聊」從候選裡拿掉。
  const shift = policy([u("好市多"), a("喔"), u("曼谷")]);
  assertEquals(shift.situation, "abrupt_topic_shift");
  assertEquals(shift.allowedActSetId, "answer_or_challenge_v1");
  assertEquals(shift.policyMode, "bounded");
  assertEquals(shift.allowedActs, [
    "accept_if_answered",
    "challenge_relevance",
  ]);

  // 連續三則未解、而且她中間真的問過（「怎麼了？」）→ 一般難度 forced
  // hold_position（Phase 3.0：第三個未解片段就停止供應解讀）。
  // R1 P1-1：強制格的問句判準收成「寬鬆判準 ＋ 句尾問句標記」，所以這裡的
  // 問句必須帶標記（問號或嗎／呢／吧）；無標記的「怎麼了」從此只走 bounded。
  const a06 = policy([u("韓國"), a("怎麼了？"), u("東京"), a("蛤"), u("淺草")]);
  assertEquals(a06.situation, "repeated_low_coherence");
  assertEquals(a06.policyMode, "forced");
  assertEquals(a06.forcedAct, "hold_position");
  assertEquals(a06.allowedActSetId, "hold_after_challenge_v1");

  // 同樣三則未解，但她一次都沒問過（「真的欸」「喔」）→ 不強制，留在
  // bounded 的條件式（Phase 3.0 的 aiQuestionedInLoop 閘門）。
  const neverAsked = policy([
    u("韓國"),
    a("真的欸"),
    u("東京"),
    a("喔"),
    u("淺草"),
  ]);
  assertEquals(neverAsked.policyMode, "bounded");
  assertEquals(neverAsked.allowedActSetId, "answer_or_challenge_v1");

  // 同一個詞原樣再丟一次＝高信心低價值迴圈。
  const repeated = policy([u("好市多"), a("？"), u("好市多")]);
  assertEquals(repeated.policyMode, "forced");
  assertEquals(repeated.forcedAct, "end_low_value_loop");
});

Deno.test("澄清型 act 不吃問題預算；hold／收尾不是問句", () => {
  for (
    const act of [
      "ask_intent",
      "challenge_relevance",
      "return_to_topic",
      "clarify",
    ] as const
  ) {
    assert(isClarifyingAct(act), act);
  }
  for (
    const act of ["acknowledge", "hold_position", "end_low_value_loop"] as const
  ) {
    assert(!isClarifyingAct(act), act);
  }
});

Deno.test("parseConversationAgencyState：缺 key 回 null；任何欄位壞掉整份 null", () => {
  const ok: ConversationAgencyState = {
    version: 1,
    lastCoherence: "ambiguous",
    unresolvedCount: 2,
    priorChallengeIssued: true,
    lastAgencyAct: "ask_intent",
  };
  assertEquals(parseConversationAgencyState(null), null);
  assertEquals(parseConversationAgencyState({}), null);
  assertEquals(parseConversationAgencyState({ conversationAgency: ok }), ok);
  assertEquals(
    parseConversationAgencyState({
      conversationAgency: { ...ok, lastAgencyAct: null },
    }),
    { ...ok, lastAgencyAct: null },
  );
  for (
    const bad of [
      "x",
      [],
      { ...ok, version: 2 },
      { ...ok, lastCoherence: "connected2" },
      { ...ok, unresolvedCount: 4 },
      { ...ok, unresolvedCount: 1.5 },
      { ...ok, unresolvedCount: "2" },
      { ...ok, priorChallengeIssued: "yes" },
      { ...ok, lastAgencyAct: "acknowledge" },
      { ...ok, lastAgencyAct: 1 },
    ]
  ) {
    assertEquals(
      parseConversationAgencyState({ conversationAgency: bad }),
      null,
      JSON.stringify(bad),
    );
  }
});

Deno.test("nextConversationAgencyState：只存 enum／布林／小整數，修好之後質疑旗標會歸零（Codex R2 P1-5）", () => {
  // Phase 3.0：第三個未解片段（unresolvedCount=2）在一般難度是 forced
  // hold_position，所以這一輪 lastAgencyAct／priorChallengeIssued 都會推進
  // ——那是 planner **強制**下的決定，不是「允許過」（Codex round-1 P1 的界線
  // 沒有改：bounded 輪仍然不得灌 priorChallengeIssued，見下面 bounded 那格）。
  const held = nextConversationAgencyState(
    null,
    policy([u("韓國"), a("怎麼了？"), u("東京"), a("蛤"), u("淺草")]),
  );
  assertEquals(held, {
    version: 1,
    lastCoherence: "repetitive",
    unresolvedCount: 2,
    priorChallengeIssued: true,
    lastAgencyAct: "hold_position",
    // Phase 4.5a 刀 3：收尾格的那一輪 streak +1（連續三輪就 check_out）。
    lowValueStreak: 1,
  });
  // bounded 輪（第二個未解片段，允許清單裡有質疑但沒有強制）：旗標不得被
  // 「允許過」灌成 true。
  const boundedTurn = nextConversationAgencyState(
    null,
    policy([u("韓國"), a("怎麼了"), u("東京")]),
  );
  assertEquals(boundedTurn.priorChallengeIssued, false);
  assertEquals(boundedTurn.lastAgencyAct, null);
  // 玩家講清楚了（她剛問完、他答了、前面沒欠債＝有效短答免疫格）：
  // Codex round-2 P1-5——舊版永久 OR 會讓上一段 episode 的質疑污染這一段，
  // 下一則新片段一出現就直接 forced hold_position。修好就歸零。
  const carried = {
    ...held,
    priorChallengeIssued: true,
    lastAgencyAct: "hold_position" as const,
  };
  const recovered = nextConversationAgencyState(
    carried,
    policy([a("那你最想去哪個國家玩"), u("韓國")]),
  );
  assertEquals(recovered.lastCoherence, "connected");
  assertEquals(recovered.unresolvedCount, 0);
  assertEquals(recovered.priorChallengeIssued, false);
  assertEquals(recovered.lastAgencyAct, "hold_position");
  // 分類器讀完她這一輪的回覆判 connected（A15／A19 的 repair）也一樣歸零，
  // 就算這一輪結構上還是個片段。
  const classifierRepair = nextConversationAgencyState(
    carried,
    policy([u("韓國"), a("怎麼了"), u("東京")]),
    { coherence: "connected", aiChallengedThisTurn: false },
  );
  assertEquals(classifierRepair.priorChallengeIssued, false);
  // 但這一輪自己真的又質疑了（分類器回報）就重新變 true。
  const challengedAgain = nextConversationAgencyState(
    carried,
    policy([u("韓國"), a("怎麼了"), u("東京")]),
    { coherence: "connected", aiChallengedThisTurn: true },
  );
  assertEquals(challengedAgain.priorChallengeIssued, true);
});

Deno.test("nextConversationAgencyState：分類器缺失／ambiguous 時退回結構近似，不是永遠不修復（Codex R1 新項 P1-1）", () => {
  const carried: ConversationAgencyState = {
    version: 1,
    lastCoherence: "repetitive",
    unresolvedCount: 2,
    priorChallengeIssued: true,
    lastAgencyAct: "hold_position",
  };
  // 一般修復輪（自我分享／問句／明示換題，situation:null）＋分類器訊號缺失
  // （null／{}／ambiguous）：舊版只認 classifierSignal.coherence==="connected"，
  // 缺訊號時舊旗標永遠出不去；現在要退回本檔自己算好的 structuralCoherence
  // （situation:null → "connected"）。
  const repairTurnSets: readonly PracticeTurn[][] = [
    [a("哈囉"), u("我最近開始練重訓")], // self_share
    [a("哈囉"), u("你平常在幹嘛")], // question
    [a("哈囉"), u("對了 講到韓國 我看到機票特價")], // explicit_pivot
  ];
  for (const signal of [null, {}, { coherence: "ambiguous" as const }]) {
    for (const turns of repairTurnSets) {
      const decision = policy(turns);
      assertEquals(decision.situation, null, JSON.stringify(turns));
      const next = nextConversationAgencyState(carried, decision, signal);
      assertEquals(
        next.priorChallengeIssued,
        false,
        JSON.stringify({ signal, turns }),
      );
      assertEquals(next.unresolvedCount, 0, JSON.stringify({ signal, turns }));
    }
  }
  // 對照組：同樣缺分類器訊號，但這一輪結構上是裸片段（situation 非
  // null，structuralCoherence 是 "ambiguous" 不是 "connected"）——不應被
  // 結構近似誤修復，舊旗標要留著。
  const bareFragment = policy([a("嗯"), u("東京")]);
  assertEquals(bareFragment.situation, "ambiguous_fragment");
  for (const signal of [null, {}, { coherence: "ambiguous" as const }]) {
    const next = nextConversationAgencyState(carried, bareFragment, signal);
    assertEquals(next.priorChallengeIssued, true, JSON.stringify(signal));
  }
});

Deno.test("agencyModeFor：只認 true／shadow／test，其餘一律 off", () => {
  assertEquals(agencyModeFor("true", false), "on");
  assertEquals(agencyModeFor("shadow", false), "shadow");
  assertEquals(agencyModeFor("test", false), "off");
  assertEquals(agencyModeFor("test", true), "on");
  assertEquals(agencyModeFor(undefined, true), "off");
  assertEquals(agencyModeFor("off", true), "off");
  assertEquals(agencyModeFor("1", true), "off");
});

Deno.test("持久化的 priorChallengeIssued 會被吃進證據（assisted 跨回合）", () => {
  const turns = [u("嗨嗨 剛看到你的自介"), a("哈囉"), u("韓國")];
  const fresh: AgencyEvidence = detectAgencyEvidence(turns, null);
  assertEquals(fresh.priorChallengeIssued, false);
  const carried = detectAgencyEvidence(turns, {
    version: 1,
    lastCoherence: "disconnected",
    unresolvedCount: 2,
    priorChallengeIssued: true,
    lastAgencyAct: "challenge_relevance",
  });
  assertEquals(carried.priorChallengeIssued, true);
  // 但未解計數一律從逐字稿重算，不會被上一輪的狀態灌大：這段逐字稿只有
  // 「嗨嗨 剛看到你的自介」一則低資訊前文，所以是 1，不是持久化的 2。
  assertEquals(carried.unresolvedCount, 1);
});

// ── 難度門檻（報告 §7.4）：只調門檻與第一個片段的候選 act，不關掉 agency，
// 不動有效短答的免疫。────────────────────────────────────────────────────

Deno.test("難度門檻：第一個無前文片段在每一種難度都是兩選一 bounded（Codex R2 P1-1）", () => {
  // 難度差異改由 topicShiftAt／lowCoherenceAt／forceEndLoopBeforeChallenge
  // 三個後段門檻承擔（下面兩條測試），不再放在第一則的強制與否。
  const fragment = [u("韓國")];
  for (const d of ["easy", "normal", "challenge"] as const) {
    const decision = policyAt(fragment, d);
    assertEquals(decision.policyMode, "bounded", d);
    assertEquals(decision.forcedAct, null, d);
    assertEquals(decision.allowedActs, ["acknowledge", "ask_intent"], d);
  }
  // Game 套挑戰門檻，第一則同樣是 bounded。
  const game = policyAt(fragment, "normal", true);
  assertEquals(game.policyMode, "bounded");
  assertEquals(game.allowedActs, ["acknowledge", "ask_intent"]);
});

Deno.test("難度門檻（Phase 3.0）：一般第 2 個未解片段要指出他沒回答，第 3 個停止解讀；易晚一步", () => {
  // Eric 2026-09-04 的真機體感定義寫成可執行斷言。逐字稿刻意用她**真的問過**
  // 的形態（強制格的 aiQuestionedInLoop 閘門），並讓最後一則的前一句不是問句
  // （強制格的 bare_fragment 閘門，Codex P1-c）。
  assertEquals(
    policyAt([u("韓國")], "normal").allowedActSetId,
    "fragment_no_context_v1",
  );

  // 第 2 個未解片段（unresolvedCount=1）。**Phase 4.3 起**：她上一則帶句尾標記
  // 問過（「怎麼突然講韓國？」）、他又丟一個沒有結構線索的詞 → 這一格從 bounded
  // 二選一升級成 forced `challenge_relevance`（Eric 2026-09-05：「第二、三輪對方
  // 打很奇怪無關的東西，正常女生會回『？』」）。難度只差在口氣（set id 三檔）。
  const second = [u("韓國"), a("怎麼突然講韓國？"), u("東京")];
  // R2（Codex P1-2）：強制格只在**分類器說她上一則真的在澄清**時成立，所以
  // 這幾格都要帶 assisted 的訊號；不帶訊號（standard）維持 bounded，見下面。
  const normalSecond = policyAt(second, "normal", false, stateWith(true));
  assertEquals(normalSecond.evidence.unresolvedCount, 1);
  assertEquals(normalSecond.evidence.utteranceShape, "answer_candidate");
  assertEquals(normalSecond.policyMode, "forced");
  assertEquals(normalSecond.forcedAct, "challenge_relevance");
  assertEquals(normalSecond.allowedActSetId, "clarify_ignored_v1");
  // 難度口氣：easy 溫和、challenge／Game 可以只回一個「？」。
  const easySecond = policyAt(second, "easy", false, stateWith(true));
  assertEquals(easySecond.forcedAct, "challenge_relevance");
  assertEquals(easySecond.allowedActSetId, "clarify_ignored_easy_v1");
  assertEquals(
    policyAt(second, "challenge", false, stateWith(true)).allowedActSetId,
    "clarify_ignored_cold_v1",
  );
  assertEquals(
    policyAt(second, "normal", true, stateWith(true)).allowedActSetId,
    "clarify_ignored_cold_v1",
  );
  // P2-3 對照（Codex R1）：同一份逐字稿，只要分類器說她上一則**不是**在澄清
  // （＝她問的是內容問題），就仍然是 Phase 3.0 的 bounded 二選一——證明改的是
  // 判準來源，不是把尺放寬。
  const secondContentQ = policyAt(second, "normal", false, stateWith(false));
  assertEquals(secondContentQ.policyMode, "bounded");
  assertEquals(secondContentQ.allowedActSetId, "answer_or_challenge_v1");
  assert(
    policyAt(second, "easy", false, stateWith(false)).allowedActs.includes(
      "acknowledge",
    ),
  );
  // R2 P1-2：沒有分類器訊號（standard／分類器失敗）＝也是 bounded，與 4.3 前相同。
  assertEquals(
    policyAt(second, "normal").allowedActSetId,
    "answer_or_challenge_v1",
  );

  // 她那一則**沒有**句尾問句標記（中文最常見的無標記問句）時，強制格的
  // `aiQuestionedInLoop` 閘門不成立 → 維持 Phase 3.0 的 bounded 二選一，
  // easy 仍多一個無條件的「接住」。
  const unmarked = [u("韓國"), a("怎麼突然講韓國"), u("東京")];
  assertEquals(
    policyAt(unmarked, "normal", false, stateWith(true)).allowedActSetId,
    "answer_or_challenge_v1",
  );
  assert(
    policyAt(unmarked, "easy", false, stateWith(true)).allowedActs.includes(
      "acknowledge",
    ),
  );

  // 第 3 個未解片段（unresolvedCount=2）：一般停止供應解讀（forced）；
  // 挑戰／Game 同一格改成直接收掉；易仍在條件式窗口。
  const third = [...second, a("你沒回答我欸"), u("清邁")];
  const normalThird = policyAt(third, "normal");
  assertEquals(normalThird.evidence.unresolvedCount, 2);
  assertEquals(normalThird.policyMode, "forced");
  assertEquals(normalThird.forcedAct, "hold_position");
  assertEquals(policyAt(third, "challenge").forcedAct, "end_low_value_loop");
  assertEquals(policyAt(third, "normal", true).forcedAct, "end_low_value_loop");
  assertEquals(
    policyAt(third, "easy").allowedActSetId,
    "answer_or_challenge_easy_v1",
  );

  // 第 4 個（unresolvedCount=3）：易難度這時才停止供應解讀，比一般晚一步。
  const fourth = [...third, a("嗯"), u("曼谷")];
  const easyFourth = policyAt(fourth, "easy");
  assertEquals(easyFourth.policyMode, "forced");
  assertEquals(easyFourth.forcedAct, "hold_position");
});

Deno.test("難度門檻：挑戰／game 在停止解讀那一格直接收掉（不是維持立場），一般／易仍是維持立場", () => {
  const threeFragments = [
    u("韓國"),
    a("怎麼突然講韓國？"),
    u("東京"),
    a("你沒回答我欸"),
    u("清邁"),
  ];
  const normal = policyAt(threeFragments, "normal");
  assertEquals(normal.policyMode, "forced");
  assertEquals(normal.forcedAct, "hold_position");
  assertEquals(normal.allowedActSetId, "hold_after_challenge_v1");

  const challenge = policyAt(threeFragments, "challenge");
  assertEquals(challenge.policyMode, "forced");
  assertEquals(challenge.forcedAct, "end_low_value_loop");
  // Codex R1（新項）P2：這支收尾是欠債到門檻，不是「同一個詞原樣再丟一次」
  // （repeatedExactToken）——set id 要是獨立的 low_value_loop_v1。
  assertEquals(challenge.allowedActSetId, "low_value_loop_v1");
  assert(!challenge.evidence.repeatedExactToken);

  const game = policyAt(threeFragments, "normal", true);
  assertEquals(game.policyMode, "forced");
  assertEquals(game.forcedAct, "end_low_value_loop");
  assertEquals(game.allowedActSetId, "low_value_loop_v1");

  // Phase 3.0 的強制閘門：欠債到門檻但她這段迴圈裡**一次都沒問過**
  // （aiQuestionedInLoop=false）→ 任何難度都不強制，留在 bounded 條件式。
  const neverAsked: AgencyEvidence = {
    utteranceShape: "bare_fragment",
    previousAiAskedQuestion: false,
    explicitPivot: false,
    repeatedExactToken: false,
    unresolvedCount: 2,
    priorChallengeIssued: false,
    precedingUserContext: false,
    aiQuestionedInLoop: false,
    userTurnCount: 3,
    aiClarifiedLastTurn: null,
    priorCoherence: null,
    answeredYesNo: false,
    lowValueStreak: 0,
    checkedOut: false,
  };
  for (
    const thresholds of [
      AGENCY_THRESHOLDS.easy,
      AGENCY_THRESHOLDS.normal,
      AGENCY_THRESHOLDS.challenge,
    ]
  ) {
    const d = agencyPolicyFor(neverAsked, thresholds);
    assertEquals(d.policyMode, "bounded");
    assertEquals(d.forcedAct, null);
    assert(d.allowedActs.some(isAcceptingPlanAct));
  }
  // 同一份證據，只把「她問過」打開 → 強制格才成立。
  const asked: AgencyEvidence = { ...neverAsked, aiQuestionedInLoop: true };
  assertEquals(
    agencyPolicyFor(asked, AGENCY_THRESHOLDS.normal).forcedAct,
    "hold_position",
  );
  assertEquals(
    agencyPolicyFor(asked, AGENCY_THRESHOLDS.challenge).forcedAct,
    "end_low_value_loop",
  );
  // 她剛問完、他回了一句沒有結構線索的話（answer_candidate）：
  //   - Codex round-1 P1-c 的原始界線是「永遠不得 forced」，因為結構層分不出
  //     那是不是答案；
  //   - Phase 4.3（Eric 2026-09-05 定調）把界線改成「**她這段迴圈裡真的問過**
  //     ＋已經有欠債」時就強制質疑（`clarify_ignored_*`），不再是 hold／收尾格
  //     那一路。她一次都沒問過（`aiQuestionedInLoop=false`）時仍然 bounded。
  const maybeAnswer: AgencyEvidence = {
    ...asked,
    utteranceShape: "answer_candidate",
    previousAiAskedQuestion: true,
    // R2 P1-2：強制格只認分類器明確說「她上一則真的在澄清」。
    aiClarifiedLastTurn: true,
  };
  for (
    const thresholds of [AGENCY_THRESHOLDS.normal, AGENCY_THRESHOLDS.challenge]
  ) {
    const d = agencyPolicyFor(maybeAnswer, thresholds);
    assertEquals(d.policyMode, "forced");
    assertEquals(d.forcedAct, "challenge_relevance");
    assert(!d.allowedActs.some(isAcceptingPlanAct));
  }
  for (
    const bounded of [
      // 她一次都沒問過。
      { ...maybeAnswer, aiQuestionedInLoop: false },
      // P2-3 對照：她問過，但分類器說那一則**不是**澄清（內容問題）。
      { ...maybeAnswer, aiClarifiedLastTurn: false },
      // R2 P1-2：沒有分類器訊號（standard／分類器失敗）＝一律不強制。
      { ...maybeAnswer, aiClarifiedLastTurn: null },
      // 協調者指定的顯式閘門：上一輪分類器判 connected。
      { ...maybeAnswer, priorCoherence: "connected" as const },
    ] satisfies AgencyEvidence[]
  ) {
    for (
      const thresholds of [
        AGENCY_THRESHOLDS.normal,
        AGENCY_THRESHOLDS.challenge,
      ]
    ) {
      const d = agencyPolicyFor(bounded, thresholds);
      assertEquals(d.policyMode, "bounded");
      assert(d.allowedActs.some(isAcceptingPlanAct));
    }
  }
});

Deno.test("難度門檻：有效短答免疫在每個難度都成立（A01／A03／A07／A09）", () => {
  const cases: PracticeTurn[][] = [
    [a("那你最想去哪個國家玩"), u("韓國")], // A01
    [
      u("嗨嗨 今天過得還好嗎"),
      a("還可以啊 你呢"),
      u("對了 講到韓國 我最近一直看到韓國機票在特價"),
    ], // A03
    [u("我最近在學日文 發音真的有夠難"), a("真的 我也覺得"), u("紅豆泥")], // A07
    [u("我最近開始練重訓 一週去三次"), a("哇 好厲害"), u("hyrox")], // A09
  ];
  for (const turns of cases) {
    for (const difficulty of ["easy", "normal", "challenge"] as const) {
      for (const isGame of [false, true]) {
        const d = policyAt(turns, difficulty, isGame);
        assertEquals(
          d.situation,
          null,
          `${difficulty}/game=${isGame} 不得介入`,
        );
        assertEquals(d.allowedActs, []);
      }
    }
  }
});

Deno.test("AGENCY_THRESHOLDS：三個難度都定義齊全，game 沿用 challenge", () => {
  for (const key of ["easy", "normal", "challenge"] as const) {
    assert(AGENCY_THRESHOLDS[key].firstFragmentActs.length > 0);
  }
  assertEquals(agencyThresholdsFor("easy", true), AGENCY_THRESHOLDS.challenge);
  assertEquals(agencyThresholdsFor("normal", false), AGENCY_THRESHOLDS.normal);
});

Deno.test("Codex round-2 P0-3：只有旗標 on 保留未知 key，off／shadow 都從零重建", () => {
  // 保留未知 key 是 agency 分支帶進來的行為改動。旗標關著時 payload 必須跟
  // main 逐字相同——main 從零重建 recent_facts，別人寫的 key 本來就會掉。
  // shadow 也算「關著」：它的契約是只算證據與 telemetry，thread payload 必須
  // 與 off 逐位元組相同（Codex round-2 P0-3）。
  const base = {
    userId: "u",
    visibleThreadId: "t",
    practiceMode: "beginner" as const,
    relationshipScore: 40,
    inviteStage: "not_ready" as const,
    aiTurnCount: 2,
    existingRecentFacts: {
      someOtherFeature: { keep: true },
      source: "practice_chat",
      aiTurnCount: 1,
      inviteStage: "not_ready",
    },
  };
  const facts = (
    over: Parameters<typeof buildRelationshipThreadRpcParams>[0],
  ): Record<string, unknown> =>
    buildRelationshipThreadRpcParams(over).p_recent_facts as Record<
      string,
      unknown
    >;
  const mainPayload: Record<string, unknown> = {
    source: "practice_chat",
    aiTurnCount: 2,
    inviteStage: "not_ready",
  };
  // 省略 agencyMode＝其餘呼叫端，逐字跟 main 相同。
  assertEquals(facts(base), mainPayload);
  for (const agencyMode of ["off", "shadow"] as const) {
    assertEquals(facts({ ...base, agencyMode }), mainPayload, agencyMode);
  }
  assertEquals(facts({ ...base, agencyMode: "on" }), {
    ...mainPayload,
    someOtherFeature: { keep: true },
  });
});

Deno.test("Codex round-2 P1-3：重複只算在同一段未解迴圈裡，中間修好過就不算重複", () => {
  // 早期講過「貓」→ 中間完整聊完別的事（self_share 把未解歸零）→ 她問
  // 「你最喜歡什麼動物」→ 再答一次「貓」。這不是低價值迴圈，是有效短答。
  const repaired = detectAgencyEvidence([
    u("貓"),
    a("蛤"),
    u("我昨天去朋友家看到一隻超肥的橘貓"),
    a("你最喜歡什麼動物"),
    u("貓"),
  ]);
  assertEquals(repaired.repeatedExactToken, false);
  assertEquals(repaired.utteranceShape, "answer_candidate");
  assertEquals(repaired.unresolvedCount, 0);
  assertEquals(agencyPolicyFor(repaired).situation, null);

  // 同一段迴圈裡原樣再丟一次，照舊是最高信心的結構事實。
  const looping = detectAgencyEvidence([u("好市多"), a("？"), u("好市多")]);
  assertEquals(looping.repeatedExactToken, true);
  assertEquals(agencyPolicyFor(looping).forcedAct, "end_low_value_loop");

  // 距離超過 3 則玩家訊息（短期工作記憶窗口外）也不算重複。
  const faraway = detectAgencyEvidence([
    u("好市多"),
    u("東京"),
    u("清邁"),
    u("曼谷"),
    u("好市多"),
  ]);
  assertEquals(faraway.repeatedExactToken, false);
});

Deno.test("Codex round-1 P1-c：有欠債的有效短答仍然一定有「接住」這個選項，永不 forced 質疑", () => {
  // 她上一則在問問題 → 這一句就有可能是答案，不管前面累積了多少未解片段。
  // 舊版丟進 topic_shift_v1（三個 act 全是質疑／拉回），等於結構保證誤質疑。
  const turns: PracticeTurn[] = [
    u("好市多"), // 前面先欠一則低資訊。
    a("你在說什麼"),
    u("你喜歡什麼動物"),
    a("你喜歡什麼動物？我喜歡貓欸"),
    u("貓"), // 她剛問完 → answer_candidate，但 unresolvedCount > 0。
  ];
  const evidence = detectAgencyEvidence(turns);
  assertEquals(evidence.utteranceShape, "answer_candidate");
  assert(evidence.unresolvedCount > 0, "這一案要有欠債才測得到");
  for (
    const thresholds of [
      AGENCY_THRESHOLDS.easy,
      AGENCY_THRESHOLDS.normal,
      AGENCY_THRESHOLDS.challenge,
    ]
  ) {
    const decision = agencyPolicyFor(evidence, thresholds);
    // Phase 3.0：候選裡永遠有一個「接受」的出口——差別是它現在是**條件式**的
    // （`accept_if_answered`：真的接得上才接受），不是無條件的 acknowledge。
    // 「貓」如果真的回答了「你喜歡什麼動物」，這個清單允許她直接接受。
    assert(
      decision.allowedActs.some(isAcceptingPlanAct),
      `${decision.allowedActSetId} 少了「接受」出口`,
    );
    assertEquals(decision.forcedAct, null, decision.allowedActSetId);
    assertEquals(decision.policyMode, "bounded");
  }

  // 唯一例外（刻意保留）：同一個字串原樣再丟一次。這是這一層信心最高的結構
  // 事實，forced act 也是「短短收掉」而不是質疑，所以仍然照舊收掉迴圈。
  const repeated = detectAgencyEvidence([...turns, a("蛤 是哪一種"), u("貓")]);
  assertEquals(repeated.utteranceShape, "answer_candidate");
  assert(repeated.repeatedExactToken);
  assertEquals(
    agencyPolicyFor(repeated, AGENCY_THRESHOLDS.challenge).forcedAct,
    "end_low_value_loop",
  );
});

Deno.test("Codex round-1（新項）P1-2：連續兩則完整第三人稱敘述，任何難度的候選清單都含「接住」", () => {
  // `bare_fragment` 的定義是「每一個結構線索都不存在」，這個集合抓得到完整、
  // 連貫、可理解的第三人稱敘事——它沒有問號、沒有語尾助詞、沒有第一人稱，也
  // 沒有明示換題詞。normal／challenge 的 `topicShiftAt` 是 1，所以第二句就會
  // 進 topic_shift_v1；舊版那個清單裡一個「接住」都沒有，等於結構層
  // deterministic 地不准她順著聊正常敘事。難度只能調口氣與門檻，不能沒收
  // 「順著接」這個選項。
  const narration = [
    u("路上那間店的招牌昨天換成新的顏色了"),
    a("真的欸"),
    u("隔壁那家也重新裝潢了"),
  ];
  for (const difficulty of ["easy", "normal", "challenge"] as const) {
    for (const isGame of [false, true]) {
      const decision = policyAt(narration, difficulty, isGame);
      const label = `${difficulty}${isGame ? "/game" : ""}`;
      // situation 可能是 null（easy 的門檻還沒到＝完全不介入）或
      // abrupt_topic_shift；只要有介入，就必須留著「接住」而且不是 forced。
      if (decision.situation === null) {
        assertEquals(decision.allowedActs, [], label);
        continue;
      }
      assertEquals(decision.situation, "abrupt_topic_shift", label);
      assertEquals(decision.policyMode, "bounded", label);
      assertEquals(decision.forcedAct, null, label);
      // Phase 3.0：她一路「真的欸」沒問過任何東西，所以 aiQuestionedInLoop
      // 是 false——強制格不會觸發（連挑戰難度也不會），清單裡也一定有一個
      // 「接受」的出口。
      assertEquals(decision.evidence.aiQuestionedInLoop, false, label);
      assert(
        decision.allowedActs.some(isAcceptingPlanAct),
        `${label}：候選清單少了「接受」出口`,
      );
    }
  }
});

Deno.test("Codex round-1（新項）P1-2：片段／跳題路徑上不得把 bounded 偷偷變成 forced", () => {
  const boundedCases = [
    [u("韓國")],
    [u("東東"), a("東東是誰"), u("阿布達比")],
    [u("好市多"), a("喔"), u("曼谷")],
    [
      u("路上那間店的招牌昨天換成新的顏色了"),
      a("真的欸"),
      u("隔壁那家也重新裝潢了"),
    ],
  ];
  for (const difficulty of ["easy", "normal", "challenge"] as const) {
    for (const turns of boundedCases) {
      const d = policyAt(turns, difficulty);
      if (d.situation === null) continue;
      assertEquals(
        d.policyMode,
        "bounded",
        `${difficulty}／${turns.at(-1)!.text} 不該是 forced`,
      );
      assert(
        d.allowedActs.some(isAcceptingPlanAct),
        `${difficulty}／${turns.at(-1)!.text} 少了「接受」出口`,
      );
    }
  }
  // forced 仍然只有兩格：同詞原樣再丟一次、欠債到門檻；act 都不是質疑。
  for (
    const turns of [
      [u("好市多"), a("？"), u("好市多")],
      [u("韓國"), a("怎麼了？"), u("東京"), a("蛤"), u("淺草")],
    ]
  ) {
    for (const difficulty of ["easy", "normal", "challenge"] as const) {
      const d = policyAt(turns, difficulty);
      if (d.policyMode !== "forced") continue;
      assert(
        d.forcedAct === "end_low_value_loop" || d.forcedAct === "hold_position",
        `${difficulty}：forced act 只能是收尾或立場，不是質疑`,
      );
    }
  }
});

Deno.test("Phase 3.2 P1-1：強制格的問句閘門是寬鬆判準的真子集＋句尾問句標記", () => {
  // R1 P1-1（Codex）：嚴格判準**必須是寬鬆判準的子集**。舊版自己列疑問詞的
  // 頭尾條件，結果「誰都可以」「如何都行」寬鬆 false／嚴格 true，等於自己造出
  // 一組新的假強制停。現在一律 `aiAskedQuestion() && 句尾標記`。
  const strictTrue = [
    "你是說阿布達比嗎",
    "東東？你朋友嗎",
    "你在講什麼？",
    "所以呢",
  ];
  const strictFalse = [
    "誰都可以",
    "如何都行",
    "我知道他是誰",
    "我不知道為什麼會這樣",
    // 中文最常見的無標記問句：接受它們拿不到強制格（安全方向，判漏只會退回
    // bounded 條件式，由看得到全文的她判）。
    "東東是誰",
    "你最想去哪",
    "怎麼突然講韓國",
    "怎麼了",
    "真的欸",
    "喔",
    "你沒回答我欸",
    "",
  ];
  for (const text of strictTrue) {
    assert(aiAskedQuestionStrict(text), `應判成問過：${text}`);
  }
  for (const text of strictFalse) {
    assert(!aiAskedQuestionStrict(text), `不該判成問過：${text}`);
  }
  // 子集性質本身也釘住：嚴格為真的一定寬鬆也為真。
  for (const text of [...strictTrue, ...strictFalse]) {
    assert(
      !aiAskedQuestionStrict(text) || aiAskedQuestion(text),
      `嚴格判準不得比寬鬆寬：${text}`,
    );
  }
  // 反向確認這幾個案子確實是「寬鬆 false」，不是靠嚴格自己擋掉的。
  for (const text of ["誰都可以", "如何都行"]) {
    assert(!aiAskedQuestion(text), `這一案的寬鬆判準本來就該是 false：${text}`);
  }

  // 端到端（Codex 的完整序列）：她一句都沒問，欠債累到一般難度的門檻也不得
  // 強制停止解讀。
  const neverAsked = policy([
    u("韓國"),
    a("誰都可以"),
    u("東京"),
    a("嗯"),
    u("淺草"),
  ]);
  assertEquals(neverAsked.evidence.unresolvedCount, 2);
  assertEquals(neverAsked.evidence.aiQuestionedInLoop, false);
  assertEquals(neverAsked.policyMode, "bounded");
  assertEquals(neverAsked.forcedAct, null);

  // 陳述句含「為什麼」的那一組同樣不得強制（寬鬆 true、嚴格 false）。
  const statementOnly = policy([
    u("韓國"),
    a("我不知道為什麼會這樣"),
    u("東京"),
    a("嗯"),
    u("淺草"),
  ]);
  assert(aiAskedQuestion("我不知道為什麼會這樣"));
  assertEquals(statementOnly.evidence.aiQuestionedInLoop, false);
  assertEquals(statementOnly.policyMode, "bounded");
  assertEquals(statementOnly.forcedAct, null);
});

Deno.test("Phase 3.2 P1-2：真問句後面接一則「嗯」，她問過這件事不得被吃掉", () => {
  // 「她問 → 他回嗯 → 她講了句不是問句的話 → 他丟片段」：舊版在 reaction 那一
  // 則先 continue 才讀 `previousAiAskedQuestion`，整段迴圈都不算她問過。
  const shortForm = detectAgencyEvidence([
    a("東東是誰啊？"),
    u("嗯"),
    a("喔喔"),
    u("阿布達比"),
  ]);
  assertEquals(shortForm.aiQuestionedInLoop, true);

  // 同一個形態累到一般難度的門檻：她問過 ＋ 這一則是 bare_fragment → forced。
  const held = policy([
    a("東東是誰啊？"),
    u("嗯"),
    a("喔喔"),
    u("阿布達比"),
    a("蛤"),
    u("清邁"),
    a("嗯"),
    u("曼谷"),
  ]);
  assertEquals(held.evidence.aiQuestionedInLoop, true);
  assertEquals(held.evidence.unresolvedCount, 2);
  assertEquals(held.policyMode, "forced");
  assertEquals(held.forcedAct, "hold_position");

  // 反向：中間玩家真的把話講清楚了（結構修復）就要清掉，不是永久旗標。
  const repaired = detectAgencyEvidence([
    a("東東是誰啊？"),
    u("嗯"),
    a("喔喔"),
    u("我剛剛在想別的事 抱歉"),
    a("沒事啦"),
    u("清邁"),
  ]);
  assertEquals(repaired.aiQuestionedInLoop, false);
});

Deno.test("Phase 3.2 放寬：免疫只給這一段迴圈裡的第一組一問一答，之後同樣算欠債", () => {
  // 第一組：她問（無標記問句「東東是誰」——放寬用的是**寬鬆**判準，嚴格判準
  // 不認它，所以這一串不會走到強制格，只證明放寬本身）→ 他丟無標記句 →
  // 免疫，不介入。
  const first = policy([a("東東是誰"), u("阿布達比")]);
  assertEquals(first.evidence.utteranceShape, "answer_candidate");
  assertEquals(first.evidence.unresolvedCount, 0);
  assertEquals(first.situation, null);
  assertEquals(first.allowedActs, []);

  // 第二組：她又問了一次，他又丟一個無標記句 → 這次算欠債 1（舊版是 0，因為
  // 「她上一句是問句」就直接放行）。仍然是 bounded 的二選一，不是 forced。
  const second = agencyPolicyFor(
    detectAgencyEvidence([
      a("東東是誰"),
      u("阿布達比"),
      a("所以你是說韓國嗎"),
      u("東京"),
    ], stateWith(true)),
  );
  assertEquals(second.evidence.utteranceShape, "answer_candidate");
  assertEquals(second.evidence.unresolvedCount, 1);
  // Phase 4.3：她這一則帶句尾標記（「嗎」）＝`aiQuestionedInLoop` 成立，
  // 加上已經有欠債 → 從 bounded 二選一升級成 forced `challenge_relevance`。
  assertEquals(second.policyMode, "forced");
  assertEquals(second.forcedAct, "challenge_relevance");
  assertEquals(second.allowedActSetId, "clarify_ignored_v1");
  // P2-3 對照：分類器說她上一則是內容問題（沒在澄清）→ 仍是 Phase 3.2 的
  // bounded 二選一，接受回答那條路留著。
  const secondContentQ = agencyPolicyFor(
    detectAgencyEvidence([
      a("東東是誰"),
      u("阿布達比"),
      a("所以你是說韓國嗎"),
      u("東京"),
    ], stateWith(false)),
  );
  assertEquals(secondContentQ.policyMode, "bounded");
  assert(secondContentQ.allowedActs.some(isAcceptingPlanAct));

  // 第三則片段（她這一則不是問句）→ 欠債 2 ＝ 一般難度的 holdAt，而且她這段
  // 迴圈裡真的問過 → forced hold_position。
  const third = policy([
    a("東東是誰"),
    u("阿布達比"),
    a("所以你是說韓國嗎"),
    u("東京"),
    a("蛤"),
    u("清邁"),
  ]);
  assertEquals(third.evidence.utteranceShape, "bare_fragment");
  assertEquals(third.evidence.unresolvedCount, 2);
  assertEquals(third.evidence.aiQuestionedInLoop, true);
  assertEquals(third.policyMode, "forced");
  assertEquals(third.forcedAct, "hold_position");

  // 界線：中間他真的把話講清楚（結構修復）就重新開始算，下一組一問一答又免疫。
  const afterRepair = policy([
    a("東東是誰"),
    u("阿布達比"),
    a("所以你是說韓國嗎"),
    u("我剛剛在列想去的地方 想到什麼打什麼"),
    a("那你最想去哪"),
    u("日本"),
  ]);
  assertEquals(afterRepair.evidence.unresolvedCount, 0);
  assertEquals(afterRepair.situation, null);
});

Deno.test("Phase 3.2 P1-3：分類器判 connected 的位置會持久化，下一輪不得讓舊欠債復活", () => {
  // assisted 的修復是語意的（他這句到底有沒有接上），結構層看不到，所以分類器
  // 判 connected 那一輪要把位置記下來。舊版只有「prev.lastCoherence ===
  // connected → 當輪 unresolved 歸零」，下一輪分類器改口（disconnected）時
  // 同一批逐字稿被重算，修復點之前的片段整批復活。
  const turns: PracticeTurn[] = [
    u("好市多"),
    a("你在說什麼"),
    u("東京"), // ← 分類器在這一輪判 connected（第 2 則玩家訊息）
    a("那你最喜歡哪個國家"),
    u("日本"),
    a("蛤"),
    u("清邁"),
  ];
  const disconnected: ConversationAgencyState = {
    version: 1,
    lastCoherence: "disconnected",
    unresolvedCount: 2,
    priorChallengeIssued: false,
    lastAgencyAct: null,
  };
  // 沒有修復點（舊 row）：整段重算 → 舊片段全部復活。
  assertEquals(detectAgencyEvidence(turns, disconnected).unresolvedCount, 3);
  // 有修復點：只從第 2 則玩家訊息之後開始算。
  const repaired = detectAgencyEvidence(turns, {
    ...disconnected,
    repairedAtUserTurns: 2,
  });
  // 修復點之後只剩「日本」（她問過 → 免疫）與「清邁」（再一個無標記片段 →
  // 欠債 1）。重點是它從修復點重新起算，不是把修復點之前的片段算回來（3）。
  assertEquals(repaired.unresolvedCount, 1);
  assertEquals(repaired.aiQuestionedInLoop, false);
  // 位置定位不到（逐字稿被截短）就當成沒有修復點，寧可少修不要指錯地方。
  assertEquals(
    detectAgencyEvidence(turns, { ...disconnected, repairedAtUserTurns: 99 })
      .unresolvedCount,
    3,
  );
  // standard 一律 prev=null，這條完全不生效。
  assertEquals(detectAgencyEvidence(turns, null).unresolvedCount, 3);

  // 同詞重複的視窗也不得越過修復點：修復點之前講過的「好市多」不算重複。
  const repeatAcrossRepair: PracticeTurn[] = [
    u("好市多"),
    a("你在說什麼"),
    u("東京"),
    a("蛤"),
    u("好市多"),
  ];
  assert(
    detectAgencyEvidence(repeatAcrossRepair, disconnected).repeatedExactToken,
  );
  assertEquals(
    detectAgencyEvidence(repeatAcrossRepair, {
      ...disconnected,
      repairedAtUserTurns: 2,
    }).repeatedExactToken,
    false,
  );
});

Deno.test("Phase 3.2 P1-3：修復點只由分類器 connected 寫入，並且會被沿用與容錯解析", () => {
  const decision = policy([u("韓國"), a("怎麼突然講韓國"), u("東京")]);
  assertEquals(decision.evidence.userTurnCount, 2);

  // 分類器判 connected → 記下當時的玩家訊息則數。
  const connected = nextConversationAgencyState(null, decision, {
    coherence: "connected",
  });
  assertEquals(connected.repairedAtUserTurns, 2);
  // 分類器改口／缺訊號 → 沿用上一個修復點（那一段還沒修好）。
  for (const signal of [null, {}, { coherence: "disconnected" as const }]) {
    assertEquals(
      nextConversationAgencyState(connected, decision, signal)
        .repairedAtUserTurns,
      2,
      JSON.stringify(signal),
    );
  }
  // 從來沒有 connected 過 → 完全不寫這個 key（不是 undefined 值）。
  const never = nextConversationAgencyState(null, decision, null);
  assert(!("repairedAtUserTurns" in never), JSON.stringify(never));

  // 解析：缺 key＝沒有修復點；壞值一律整份 null（跟其餘欄位同一個規則）。
  const ok = {
    version: 1,
    lastCoherence: "ambiguous",
    unresolvedCount: 2,
    priorChallengeIssued: false,
    lastAgencyAct: null,
  };
  const parsedWithout = parseConversationAgencyState({
    conversationAgency: ok,
  });
  assert(parsedWithout !== null);
  assert(!("repairedAtUserTurns" in parsedWithout));
  assertEquals(
    parseConversationAgencyState({
      conversationAgency: { ...ok, repairedAtUserTurns: 4 },
    })?.repairedAtUserTurns,
    4,
  );
  for (const bad of [-1, 1.5, "2", null, {}]) {
    assertEquals(
      parseConversationAgencyState({
        conversationAgency: { ...ok, repairedAtUserTurns: bad },
      }),
      null,
      JSON.stringify(bad),
    );
  }
});

Deno.test("Phase 3.2 R1 P1-2：放寬用的「她問過」是寬鬆判準，無標記問句也算", () => {
  // 中文最常見的無標記問句（「那你最想去哪個國家玩」）拿不到強制格是刻意的，
  // 但**放寬**這一格只會走 bounded 的二選一條件式（真的回答了就接受），
  // 過度偵測是安全方向，所以這裡用寬鬆判準。
  const secondAnswer = policy([
    a("那你最想去哪個國家玩"),
    u("日本"),
    a("那第二想去哪個國家玩"),
    u("韓國"),
  ]);
  assertEquals(secondAnswer.evidence.utteranceShape, "answer_candidate");
  assertEquals(secondAnswer.evidence.unresolvedCount, 1);
  assertEquals(secondAnswer.allowedActSetId, "answer_or_challenge_v1");
  // 但它仍然不是強制格：兩則 AI 訊息都沒有句尾問句標記。
  assertEquals(secondAnswer.evidence.aiQuestionedInLoop, false);
  assertEquals(secondAnswer.policyMode, "bounded");
});

Deno.test("Phase 3.2 R1 P1-3：前置裸片段是那唯一一次通融，A04 型序列本來就該落在條件式", () => {
  // Codex 質疑「韓國 → 她問 → 阿布達比」為什麼不是免疫格。這是 Phase 3.0 的
  // 設計，不是 3.2 的放寬造成的：`told` 的語意是「上一則玩家訊息是不是一個她
  // 得自己想辦法處理的低資訊片段」，開頭那個沒有前文的「韓國」就是那一次通融，
  // 所以下一則不管她有沒有問，都已經在欠債格裡。A04（東東 → 她問東東是誰 →
  // 阿布達比）正是**必須**走到二選一條件式的案例，不是有效短答免疫。
  const leadingFragment = policy([u("韓國"), a("東東是誰"), u("阿布達比")]);
  assertEquals(leadingFragment.evidence.utteranceShape, "answer_candidate");
  assertEquals(leadingFragment.evidence.unresolvedCount, 1);
  assertEquals(leadingFragment.policyMode, "bounded");
  assertEquals(leadingFragment.allowedActSetId, "answer_or_challenge_v1");
  assert(leadingFragment.allowedActs.some(isAcceptingPlanAct));

  // 對照：沒有那個前置裸片段時，第一組一問一答仍然完全免疫。
  const noLeading = policy([a("東東是誰"), u("阿布達比")]);
  assertEquals(noLeading.evidence.unresolvedCount, 0);
  assertEquals(noLeading.situation, null);
});

Deno.test("Phase 3.2 R1 P1-3：中間夾一則「嗯」不算他答過，下一則才是第一組一問一答", () => {
  // 她問 → 他只回「嗯」（reaction，不是答案，也不是欠債）→ 她再問 → 他答。
  // 這一則「日本」是這段迴圈裡第一組真正的一問一答，所以免疫。
  const firstRealAnswer = policy([
    a("你想去哪"),
    u("嗯"),
    a("那你最想去哪"),
    u("日本"),
  ]);
  assertEquals(firstRealAnswer.evidence.utteranceShape, "answer_candidate");
  assertEquals(firstRealAnswer.evidence.unresolvedCount, 0);
  assertEquals(firstRealAnswer.situation, null);

  // 再下一則無標記片段就是欠債 1（Phase 3.2 的放寬：她已經問過了）。
  const nextFragment = policy([
    a("你想去哪"),
    u("嗯"),
    a("那你最想去哪"),
    u("日本"),
    a("嗯"),
    u("清邁"),
  ]);
  assertEquals(nextFragment.evidence.unresolvedCount, 1);
  assertEquals(nextFragment.allowedActSetId, "answer_or_challenge_v1");
});

Deno.test("Phase 3.2 R1 P1-4a：定位不到的修復點不得被繼續往下傳", () => {
  // 逐字稿比記錄當時短（client 截窗／換 thread）：這一輪已經不採用它，
  // 下一輪的狀態也不能再把這個指不到任何位置的數字傳下去。
  const decision = policy([u("韓國"), a("怎麼突然講韓國？"), u("東京")]);
  assertEquals(decision.evidence.userTurnCount, 2);
  const stale: ConversationAgencyState = {
    version: 1,
    lastCoherence: "disconnected",
    unresolvedCount: 2,
    priorChallengeIssued: false,
    lastAgencyAct: null,
    repairedAtUserTurns: 5,
  };
  const next = nextConversationAgencyState(stale, decision, null);
  assert(!("repairedAtUserTurns" in next), JSON.stringify(next));
  // 定位得到的就照舊沿用。
  assertEquals(
    nextConversationAgencyState(
      { ...stale, repairedAtUserTurns: 2 },
      decision,
      null,
    ).repairedAtUserTurns,
    2,
  );
});

Deno.test("Phase 3.2 R2 P1：同詞重複視窗不得被修復點之前的結構訊息拉回去", () => {
  // Codex R2 的序列：修復點（第 3 則玩家訊息）**之前**有一則完整敘述
  // （「我昨天去逛街」），舊版 `repairedAt = i + 1` 會被它覆寫成 1，
  // 重複視窗又跨回修復點之前，把修復點之前講過的「好市多」算成原樣重複，
  // 於是 forced `end_low_value_loop`。
  const turns: PracticeTurn[] = [
    u("我昨天去逛街"),
    a("喔"),
    u("好市多"),
    a("你在說什麼"),
    u("東京"), // ← 分類器判 connected（第 3 則玩家訊息）
    a("嗯"),
    u("嗯"),
    a("蛤"),
    u("好市多"),
  ];
  const prev: ConversationAgencyState = {
    version: 1,
    lastCoherence: "connected",
    unresolvedCount: 0,
    priorChallengeIssued: false,
    lastAgencyAct: null,
    repairedAtUserTurns: 3,
  };
  const decision = agencyPolicyFor(detectAgencyEvidence(turns, prev));
  assertEquals(decision.evidence.repeatedExactToken, false);
  assertEquals(decision.forcedAct, null);
  // 這一輪的結論是「完全不介入」（前面有真實前文的無欠債片段）：NO_OVERRIDE
  // 的 policyMode 欄位本來就是 "forced"＋空清單，判斷「有沒有被強制」要看
  // `forcedAct`／`situation`，不是 policyMode。
  assertEquals(decision.situation, null);
  assertEquals(decision.allowedActs, []);

  // 對照：沒有修復點時，同一段逐字稿確實是同詞重複（證明這個測試測得到東西）。
  assertEquals(
    detectAgencyEvidence(turns, { ...prev, repairedAtUserTurns: undefined })
      .repeatedExactToken,
    true,
  );
});

Deno.test("Phase 3.2 R2 P2：舊 row 的 connected 退路只對沒有修復點的 row 生效", () => {
  // 有修復點時 `unresolved` 已經是「修復點之後」重新算出來的新欠債，
  // 舊那條無條件歸零會把它整個擦掉。
  const turns: PracticeTurn[] = [
    u("我昨天去逛街"),
    a("喔"),
    u("好市多"), // ← 修復點（第 2 則玩家訊息）之前
    a("你要去哪？"),
    u("甲"),
    a("蛤"),
    u("乙"),
    a("蛤"),
    u("丙"),
  ];
  const connectedWithMarker: ConversationAgencyState = {
    version: 1,
    lastCoherence: "connected",
    unresolvedCount: 0,
    priorChallengeIssued: false,
    lastAgencyAct: null,
    repairedAtUserTurns: 2,
  };
  assertEquals(
    detectAgencyEvidence(turns, connectedWithMarker).unresolvedCount,
    2,
  );
  // 沒有 marker 的舊 row 照舊走那條退路（行為不變）。
  assertEquals(
    detectAgencyEvidence(turns, {
      ...connectedWithMarker,
      repairedAtUserTurns: undefined,
    }).unresolvedCount,
    0,
  );
});

// ── Phase 3.3：形狀實驗旋鈕與 truncate 臂 ─────────────────────────────────
const appliedAgency = (turns: PracticeTurn[]): AgencyApplication => ({
  decision: policy(turns),
  applied: true,
  enabled: true,
  profile: null,
});
// Eric 2026-09-04 回報的那一格：她問過一次，他又丟一個不相干的地名。
const FRAGMENT_DEBT_TURNS = [u("東東"), a("東東是誰"), u("阿布達比")];

Deno.test("Phase 3.3 旋鈕：只認 truncate，其餘（含未設、亂填、已刪的 prompt 臂）一律 off", () => {
  assertEquals(agencyShapeExperimentFor(undefined), "off");
  assertEquals(agencyShapeExperimentFor("off"), "off");
  assertEquals(agencyShapeExperimentFor("true"), "off");
  assertEquals(agencyShapeExperimentFor("prompt"), "off");
  assertEquals(agencyShapeExperimentFor("truncate"), "truncate");
});

Deno.test("Phase 3.3 truncate：第一則是問句時只留第一則，順口自曝的後續整段丟掉", () => {
  const agency = appliedAgency(FRAGMENT_DEBT_TURNS);
  // 這一格正是「接受仍合法」的候選組（clarify-only 壓不到形狀）。
  assertEquals(agency.decision.allowedActSetId, "answer_or_challenge_v1");
  const result = truncateAgencyShape(
    "你是說阿布達比嗎\n我剛從那邊飛回來耶",
    agency,
  );
  assertEquals(result.text, "你是說阿布達比嗎");
  assertEquals(result.dropped, 1);
});

Deno.test("Phase 4.3 刀 2：第一顆問句帶句尾 emoji／裝飾時也要截斷（4.2 量到的失效點）", () => {
  const agency = appliedAgency(FRAGMENT_DEBT_TURNS);
  for (
    const first of [
      "你是說阿布達比嗎😂",
      "你在報地名嗎 😆",
      "是玩猜謎嗎～",
      "你到底想說什麼？？",
    ]
  ) {
    const result = truncateAgencyShape(
      `${first}\n我剛從那邊飛回來耶`,
      agency,
    );
    assertEquals(result.text, first, first);
    assertEquals(result.dropped, 1, first);
  }
  // 語助詞結尾仍然不算問句（她是接住了，不是在問）→ 一個字都不動。
  const kept = "阿布達比喔😂\n我飛香港的時候會順便去逛街";
  assertEquals(truncateAgencyShape(kept, agency).dropped, 0);
});

Deno.test("Phase 3.3 truncate：第一則不是問句（她接住了）就一個字都不動", () => {
  const reply = "阿布達比喔\n我飛香港的時候會順便去逛街";
  const result = truncateAgencyShape(reply, appliedAgency(FRAGMENT_DEBT_TURNS));
  assertEquals(result.text, reply);
  assertEquals(result.dropped, 0);
});

Deno.test("Phase 3.3 truncate：agency 沒介入（applied=false／situation=null）一律不動", () => {
  const reply = "你是說阿布達比嗎\n我剛從那邊飛回來耶";
  const shadow: AgencyApplication = {
    ...appliedAgency(FRAGMENT_DEBT_TURNS),
    applied: false,
    enabled: false,
  };
  assertEquals(truncateAgencyShape(reply, shadow).text, reply);
  assertEquals(truncateAgencyShape(reply, null).dropped, 0);
  // 有效短答（她剛問完、他答了、沒有欠債）＝situation null，決策不介入。
  const validShortAnswer = appliedAgency([a("你喜歡哪種動物"), u("貓")]);
  assertEquals(validShortAnswer.decision.situation, null);
  assertEquals(truncateAgencyShape(reply, validShortAnswer).text, reply);
});

Deno.test("Phase 3.3 R1：situation=null 就算被硬標成 applied、候選組也符合，一樣不截斷", () => {
  // 呼叫端自己組出來的矛盾狀態（applied=true 但 situation=null）。免疫要靠
  // situation 明寫，不能只靠 applied 的定義隱含。
  const base = appliedAgency(FRAGMENT_DEBT_TURNS);
  const contradictory: AgencyApplication = {
    ...base,
    decision: { ...base.decision, situation: null },
  };
  assertEquals(
    contradictory.decision.allowedActSetId,
    "answer_or_challenge_v1",
  );
  const reply = "你是說阿布達比嗎\n我剛從那邊飛回來耶";
  assertEquals(truncateAgencyShape(reply, contradictory).text, reply);
  assertEquals(truncateAgencyShape(reply, contradictory).dropped, 0);
});

Deno.test("Phase 3.3 truncate：泡泡切法跟 client 同一套（單則不動、超過 4 則不拆也不截）", () => {
  const agency = appliedAgency(FRAGMENT_DEBT_TURNS);
  assertEquals(truncateAgencyShape("你是說阿布達比嗎", agency).dropped, 0);
  const fiveBubbles = ["你是說阿布達比嗎", "甲", "乙", "丙", "丁"].join("\n");
  assertEquals(truncateAgencyShape(fiveBubbles, agency).text, fiveBubbles);
  assertEquals(truncateAgencyShape(fiveBubbles, agency).dropped, 0);
});

Deno.test("Phase 3.8 askedAboutUser：parse 只認布林、false 不落欄位；nextConversationAgencyState 黏住不歸零", () => {
  const ok: ConversationAgencyState = {
    version: 1,
    lastCoherence: "connected",
    unresolvedCount: 0,
    priorChallengeIssued: false,
    lastAgencyAct: null,
  };
  assertEquals(
    parseConversationAgencyState({
      conversationAgency: { ...ok, askedAboutUser: true },
    }),
    { ...ok, askedAboutUser: true },
  );
  assertEquals(
    parseConversationAgencyState({
      conversationAgency: { ...ok, askedAboutUser: false },
    }),
    ok,
  );
  assertEquals(
    parseConversationAgencyState({
      conversationAgency: { ...ok, askedAboutUser: "yes" },
    }),
    null,
  );
  const decision = computeAgencyDecision({
    turns: [{ role: "user", text: "嗨嗨" }, { role: "ai", text: "嗨" }, {
      role: "user",
      text: "今天超熱的",
    }],
    situation: "neutral",
    agencyMode: "on",
  })!.decision;
  const first = nextConversationAgencyState(null, decision, null, true);
  assertEquals(first.askedAboutUser, true);
  const later = nextConversationAgencyState(first, decision, null, false);
  assertEquals(later.askedAboutUser, true);
  const never = nextConversationAgencyState(null, decision, null, false);
  assert(!("askedAboutUser" in never));
});

// ── Phase 4.3（Eric 2026-09-05 定調）────────────────────────────────────────
Deno.test("Phase 4.3 刀 1：她澄清過＋已有欠債＋他又丟一個沒線索的詞 → forced challenge_relevance（難度只差口氣）", () => {
  const fires = [u("韓國"), a("你在說什麼？"), u("日本")];
  const d = policyAt(fires, "normal", false, stateWith(true));
  assertEquals(d.evidence.utteranceShape, "answer_candidate");
  assertEquals(d.evidence.unresolvedCount, 1);
  assertEquals(d.evidence.aiQuestionedInLoop, true);
  assertEquals(d.evidence.precedingUserContext, false);
  assertEquals(d.situation, "abrupt_topic_shift");
  assertEquals(d.policyMode, "forced");
  assertEquals(d.forcedAct, "challenge_relevance");
  assertEquals(d.allowedActs, ["challenge_relevance"]);
  assertEquals(d.allowedActSetId, "clarify_ignored_v1");
  assertEquals(
    policyAt(fires, "easy", false, stateWith(true)).allowedActSetId,
    "clarify_ignored_easy_v1",
  );
  assertEquals(
    policyAt(fires, "challenge", false, stateWith(true)).allowedActSetId,
    "clarify_ignored_cold_v1",
  );
  assertEquals(
    policyAt(fires, "normal", true, stateWith(true)).allowedActSetId,
    "clarify_ignored_cold_v1",
  );

  // 閘門 1：她那一則沒有句尾問句標記（中文無標記問句）→ 嚴格判準不成立，
  // 維持 Phase 3.0 的 bounded 二選一。
  const unmarked = policyAt(
    [u("韓國"), a("你在說什麼"), u("日本")],
    "normal",
    false,
    stateWith(true),
  );
  assertEquals(unmarked.evidence.aiQuestionedInLoop, false);
  assertEquals(unmarked.policyMode, "bounded");

  // 閘門 2（R2 P1-2）：她澄清過就強制，**不看**他前面聊得多好。
  const withContext = policyAt(
    [u("我今天上班超累的"), a("嗯嗯"), u("韓國"), a("你在說什麼？"), u("日本")],
    "normal",
    false,
    stateWith(true),
  );
  assertEquals(withContext.evidence.precedingUserContext, true);
  assertEquals(withContext.policyMode, "forced");

  // 閘門 3（R2 P1-1，撤回後的行為）：肯定／否定短詞**不是** reaction。她澄清
  // 之後回一個「不是」＝沒回答，照樣進強制格；只有「她問是非題＋沒有欠債」
  // 那一格才走既有的有效短答免疫。
  for (const no of ["對", "對啊", "是", "不是", "沒有"]) {
    const afterClarify = policyAt(
      [u("韓國"), a("你在說什麼？"), u(no)],
      "normal",
      false,
      stateWith(true),
    );
    assertEquals(afterClarify.evidence.utteranceShape, "answer_candidate", no);
    assertEquals(afterClarify.forcedAct, "challenge_relevance", no);
    // 對照：她問的是內容是非題、而且沒有欠債 → 有效短答免疫。
    const validShort = policyAt(
      [a("你是說韓國嗎？"), u(no)],
      "normal",
      false,
      stateWith(true),
    );
    assertEquals(validShort.evidence.unresolvedCount, 0, no);
    assertEquals(validShort.situation, null, no);
  }
  // 真正的招呼／情緒反應詞仍然是 reaction（本輪沒有動它們）。
  for (const yes of ["嗯", "好", "喔", "哈哈"]) {
    const r = policyAt(
      [u("韓國"), a("你在說什麼？"), u(yes)],
      "normal",
      false,
      stateWith(true),
    );
    assertEquals(r.evidence.utteranceShape, "reaction", yes);
    assertEquals(r.situation, null, yes);
  }

  // 閘門 4（R2 P1-3）：澄清之後給的**完整解釋**帶字面解釋標記 → self_share，
  // 不落 answer_candidate，也就進不了強制格。
  for (
    const explain of [
      "因為下個月要去首爾出差",
      "我是說剛剛那個",
      "意思是想找人一起去",
      "就是說那邊比較便宜啦",
    ]
  ) {
    const d2 = policyAt(
      [u("韓國"), a("你在說什麼？"), u(explain)],
      "normal",
      false,
      stateWith(true),
    );
    assertEquals(d2.evidence.utteranceShape, "self_share", explain);
    assertEquals(d2.situation, null, explain);
  }
  // 成對反例：同一格丟一個沒有解釋標記的地名仍然強制。
  assertEquals(
    policyAt(
      [u("韓國"), a("你在說什麼？"), u("清邁")],
      "normal",
      false,
      stateWith(true),
    )
      .forcedAct,
    "challenge_relevance",
  );

  // 有效短答免疫一字未動：她剛問、他答、沒有欠債 → 任何難度都不介入。
  for (const difficulty of ["easy", "normal", "challenge"] as const) {
    const immune = policyAt(
      [a("那你最想去哪個國家玩？"), u("韓國")],
      difficulty,
      false,
      stateWith(true),
    );
    assertEquals(immune.evidence.unresolvedCount, 0, difficulty);
    assertEquals(immune.situation, null, difficulty);
  }
});

Deno.test("Phase 4.3 刀 1：Eric 真機序列（挑戰 Game）逐輪，帶分類器訊號", () => {
  // Eric 2026-09-05 的原話：「第二、三輪對方打很奇怪無關的東西，正常女生會回
  // 『？』『你在講什麼』或直接冷淡，不可能尬聊。」這一支把那條序列釘成回歸鎖。
  // `signal` ＝分類器讀完**她上一則實際生成文字**後的 `aiChallengedThisTurn`。
  const turns: PracticeTurn[] = [];
  const step = (t: PracticeTurn[], aiClarified: boolean | null) => {
    turns.push(...t);
    return policyAt(
      [...turns],
      "normal",
      true,
      aiClarified === null ? null : stateWith(aiClarified),
    );
  };
  // 第 1 輪「韓國」：無前文片段，bounded（維持 Phase 2.7，不因本刀變嚴）。
  const s1 = step([u("韓國")], null);
  assertEquals(s1.allowedActSetId, "fragment_no_context_v1");
  assertEquals(s1.policyMode, "bounded");

  // 第 2 輪「日本」：她上一則「你在說什麼？」＝分類器判她真的在澄清 → forced。
  // 這就是 Eric 要守的那一格。
  const s2 = step([a("你在說什麼？"), u("日本")], true);
  assertEquals(s2.policyMode, "forced");
  assertEquals(s2.forcedAct, "challenge_relevance");
  assertEquals(s2.allowedActSetId, "clarify_ignored_cold_v1");

  // 第 3 輪「清邁」：她上一則問的是**內容**問題（「日本還是韓國？」）。
  // 分類器判 `aiChallengedThisTurn=false` → **不強制**，留在 bounded 由她判
  // （Codex R1 P1-1：結構層分不出「清邁」與「想去日本」，不硬判）。
  const s3ContentQ = step([a("日本還是韓國？"), u("清邁")], false);
  assertEquals(s3ContentQ.policyMode, "bounded");
  assert(s3ContentQ.allowedActs.some(isAcceptingPlanAct));
  // 同一格，只把「她上一則真的在澄清」打開 → forced。
  assertEquals(
    policyAt([...turns], "normal", true, stateWith(true)).forcedAct,
    "challenge_relevance",
  );

  // 第 4 輪「哈哈」：純反應詞，結構層不介入（Phase 4.2 的停滯輪界線）。
  const s4 = step([a("你到底想說什麼"), u("哈哈")], true);
  assertEquals(s4.evidence.utteranceShape, "reaction");
  assertEquals(s4.situation, null);

  // 第 5 輪「阿布達比」：反應詞不修復也不清掉「她問過」，欠債續算 → 挑戰／Game
  // 在 holdAt=1 直接收掉這串（既有 Phase 3.0 行為，本刀沒有蓋掉它）。
  const s5 = step([a("嗯"), u("阿布達比")], true);
  assertEquals(s5.evidence.utteranceShape, "bare_fragment");
  assertEquals(s5.policyMode, "forced");
  assertEquals(s5.forcedAct, "end_low_value_loop");
});

// ── Phase 4.3 Codex R1 P2-4：REACTION_RE 是全域語意變更，序列副作用要封住 ──
Deno.test("Phase 4.3 R2 P1-1：肯定／否定短詞的撤回後行為——1～4 次 × 三種前文", () => {
  // 4.3 一度把這些詞加進 `REACTION_RE`，R2 判定那違反頂層契約（「不是」回得了
  // 「你是說韓國嗎？」，回不了「你在說什麼？」，而 reaction 分支在看前一句是
  // 哪種問題之前就把兩者一起豁免）。整批撤回後，這一支釘的是**撤回後**的行為。
  const tokens = ["對", "對啊", "是", "是啊", "不對", "不是", "沒有", "沒錯"];
  const leads: [string, string, string][] = [
    // [名稱, 她那一則, 期望形狀]
    ["陳述", "我今天差點睡過頭", "bare_fragment"],
    ["是非問句", "你今天也很累嗎？", "answer_candidate"],
    ["開放問句", "那你比較想去哪裡？", "answer_candidate"],
  ];
  for (const token of tokens) {
    for (const [leadName, leadText, shape] of leads) {
      for (let n = 1; n <= 4; n++) {
        const turns: PracticeTurn[] = [];
        for (let k = 0; k < n; k++) {
          turns.push(a(leadText), u(token));
        }
        const label = `${token}×${n}｜${leadName}`;
        const d = policyAt([...turns], "normal", false, stateWith(true));
        // (a) 形狀回到 4.2 前：不是 reaction。
        assertEquals(d.evidence.utteranceShape, shape, label);
        // (b) 第 1 次是這一段迴圈的第一組一問一答／第一個片段 → 欠債 0；
        //     第 2 次起開始累積（不再永久免疫，R2 P1-1 的驗證步驟第 3 條）。
        //     **Phase 4.5a 刀 1 的唯一例外**：她那一則是**是非問句**（句尾
        //     「嗎／吧／嘛」）時，「對／不是」就是答案，連丟幾次都不累積欠債。
        //     陳述句與開放問句（「那你比較想去哪裡？」）逐字維持 4.3 行為。
        const yesNoLead = leadName === "是非問句";
        assertEquals(
          d.evidence.unresolvedCount,
          yesNoLead ? 0 : n === 1 ? 0 : n - 1,
          label,
        );
        assertEquals(d.evidence.answeredYesNo, yesNoLead, label);
        if (yesNoLead) assertEquals(d.situation, null, label);
        // (c) 消耗內容窗口（回到 Phase 4.2 契約表的原始值）。
        assert(utteranceShapeOf(token, false) !== "reaction", label);
      }
    }
  }
  // 她澄清之後回「不是」＝沒回答 → 強制格；她問是非題、沒有欠債 → 免疫。
  assertEquals(
    policyAt(
      [u("韓國"), a("你在說什麼？"), u("不是")],
      "normal",
      false,
      stateWith(true),
    )
      .forcedAct,
    "challenge_relevance",
  );
  assertEquals(
    policyAt([a("你是說韓國嗎？"), u("不是")], "normal", false, stateWith(true))
      .situation,
    null,
  );
});

Deno.test("Phase 4.3 P2-4／U-9：reaction 與問句判定都容忍句尾標點／emoji（含 ZWJ、膚色、keycap、variation selector）", () => {
  // 真正的招呼／情緒反應詞（本輪沒有動它們）帶裝飾時仍然是 reaction。
  for (
    const t of [
      "嗯嗯!!",
      "好喔😅😅",
      "哈哈…",
      "了解。",
      "收到～",
      "笑死👨‍👩‍👧‍👦", // ZWJ 家庭（U+200D 不在 Emoji_Presentation 裡，要單獨放進字元類）
      "嗯👍🏽", // 膚色修飾
      "喔❤️", // variation selector（U+FE0F）
      "好☺️👌🏻", // 多個 emoji ＋ VS ＋ 膚色
      "哈哈😂。", // emoji 後面還接標點
    ]
  ) {
    assertEquals(utteranceShapeOf(t, false), "reaction", t);
  }
  // 整則就是 emoji 時仍走既有的純 emoji 分支（剝到空字串要退回原字串）。
  for (const t of ["😂", "😂😂😂", "👍🏽", "👨‍👩‍👧‍👦"]) {
    assertEquals(utteranceShapeOf(t, false), "reaction", t);
  }
  // keycap（U+FE0F U+20E3）只剝掉組合字元，**數字本身是內容**。
  assert(utteranceShapeOf("嗯1️⃣", false) !== "reaction");
  // 界線：帶內容的版本不是純短詞。
  for (const t of ["嗯 我剛下班", "好啦 那就東京"]) {
    assert(utteranceShapeOf(t, false) !== "reaction", t);
  }
  // 玩家自己的問句帶 emoji 也要判成問句（P2-5：`utteranceShapeOf` 換成容忍版）。
  for (const t of ["所以你是說我很閒嗎😂", "你到底想幹嘛？？", "吃飽沒～"]) {
    assertEquals(utteranceShapeOf(t, false), "question", t);
  }
});

Deno.test("Phase 4.3 R2 U-10：連續丟同一個「不是」會累積欠債，不會永久免疫", () => {
  for (const token of ["不是", "沒有", "對啊"]) {
    // 她澄清 → 他回 token → 她再問 → 他又回同一個 token。
    const turns: PracticeTurn[] = [
      u("韓國"),
      a("你在說什麼？"),
      u(token),
      a("到底是什麼意思？"),
      u(token),
    ];
    const d = policyAt(turns, "normal", false, stateWith(true));
    assert(d.evidence.unresolvedCount >= 1, token);
    // 同一個詞原樣再丟一次 → 既有的重複收尾格（比 clarify_ignored 更前面）。
    assertEquals(d.evidence.repeatedExactToken, true, token);
    assertEquals(d.forcedAct, "end_low_value_loop", token);
  }
  // 對照：裸詞原樣再丟一次仍然強制收尾（既有行為未被削弱）。
  const repeated = policyAt(
    [u("韓國"), a("你在說什麼？"), u("東京"), a("嗯"), u("東京")],
    "normal",
    false,
    stateWith(true),
  );
  assertEquals(repeated.evidence.repeatedExactToken, true);
  assertEquals(repeated.forcedAct, "end_low_value_loop");
});

Deno.test("Phase 4.3 刀 2：問句判定容忍句尾 emoji／裝飾，但不放寬語助詞", () => {
  // 真超集：`isQuestionText` 判 true 的，容忍版一定也 true。
  for (
    const t of [
      "你在報地名嗎",
      "所以你是說韓國嗎",
      "你到底想幹嘛?",
      "吃飽沒",
      "你住哪啊",
    ]
  ) {
    assertEquals(isQuestionText(t), true, t);
    assertEquals(isQuestionTextTolerant(t), true, t);
  }
  // 句尾裝飾（emoji／`～`／`…`／標點）只有容忍版認得——Phase 4.2 逐泡泡診斷
  // 量到 truncate 因此大量失效的那一組。
  for (
    const t of [
      "你在報地名嗎😂",
      "你是在玩地名接龍嗎😂",
      "是玩猜謎嗎～",
      "你是一直在報地名嗎😆",
      "你到底想說什麼？？",
    ]
  ) {
    assertEquals(isQuestionTextTolerant(t), true, t);
  }
  // P3-8（Codex R1）：同一組裝飾 fixture 同時斷言**舊判準 false、新判準 true**
  // ——證明差異真的來自剝裝飾，不是 fixture 本來就兩邊都過。
  for (
    const t of [
      "你在報地名嗎😂",
      "你是在玩地名接龍嗎😂",
      "是玩猜謎嗎～",
      "你是一直在報地名嗎😆",
      "你吃飽沒❤️",
    ]
  ) {
    assertEquals(isQuestionText(t), false, `舊判準應為 false：${t}`);
    assertEquals(isQuestionTextTolerant(t), true, `新判準應為 true：${t}`);
  }
  // 語助詞不是問句標記：不得因為容忍裝飾就把「好喔」「地名喔」判成問句。
  for (
    const t of ["好喔", "阿你是在測試我懂不懂地名喔", "我剛下班耶", "笑死啦"]
  ) {
    assertEquals(isQuestionTextTolerant(t), false, t);
    assertEquals(isQuestionText(t), false, t);
  }
});

// ── Phase 4.3 Codex R1 P1-1／P1-2：產品不變量（獨立於內部欄位）─────────────
//
// 契約：**只要當輪文字確實回答她上一個內容問題，就不得 forced challenge。**
// 結構層分不出「想去日本」與「清邁」，所以判斷交給模型——這裡消費的是分類器
// 讀完**她上一則實際生成文字**後的 `aiChallengedThisTurn`（＝她那句到底是在
// 澄清，還是在問一個內容問題）。
Deno.test("Phase 4.3 P1-1：她上一則是內容問題（分類器 aiChallenged=false）→ 正當短答不得 forced challenge", () => {
  // Codex 的五輪反例逐字稿。
  const codexCase: PracticeTurn[] = [
    u("韓國"),
    a("你在說什麼？"),
    u("東京"),
    a("那你比較想去哪裡？"),
    u("想去日本"),
  ];
  for (const answer of ["想去日本", "日本", "比較喜歡韓國"]) {
    const turns = [...codexCase.slice(0, 4), u(answer)];
    // 她上一則是內容問題 → 不強制，且候選裡仍留著「接受回答」這條路。
    const contentQ = policyAt(turns, "normal", false, stateWith(false));
    assertEquals(contentQ.policyMode, "bounded", answer);
    assertEquals(contentQ.forcedAct, null, answer);
    assert(contentQ.allowedActs.some(isAcceptingPlanAct), answer);
    // 同一句話、同一份逐字稿，只把「她上一則真的在澄清」打開 → 才強制。
    const clarified = policyAt(turns, "normal", false, stateWith(true));
    assertEquals(clarified.policyMode, "forced", answer);
    assertEquals(clarified.forcedAct, "challenge_relevance", answer);
  }
});

Deno.test("Phase 4.3 P1-1：涵蓋欠債 0／1／2 × 有無前文——分類器說她沒澄清就一律不得 forced challenge", () => {
  // 欠債 0（有效短答免疫格）、1、2 各一組，前文有／無各一種。
  const withoutContext: PracticeTurn[][] = [
    [a("那你最想去哪個國家玩？"), u("日本")], // 欠債 0
    [u("韓國"), a("那你比較想去哪裡？"), u("日本")], // 欠債 1
    [u("韓國"), a("是喔"), u("東京"), a("那你比較想去哪裡？"), u("日本")], // 欠債 2
  ];
  const withContext = withoutContext.map((
    t,
  ) => [u("我今天上班超累的 剛到家"), ...t]);
  for (const [i, turns] of [...withoutContext, ...withContext].entries()) {
    const label = `case${i}`;
    const d = policyAt(turns, "normal", false, stateWith(false));
    assert(
      d.forcedAct !== "challenge_relevance",
      `${label} 不得 forced challenge`,
    );
    // 沒被強制時，接受回答一定還在路徑上（NO_OVERRIDE 或含 accept 的候選組）。
    assert(
      d.situation === null || d.allowedActs.some(isAcceptingPlanAct),
      `${label} 必須保留接受回答的路徑`,
    );
  }
});

Deno.test("Phase 4.3 P1-2：她澄清過就強制，不管他前面聊得多好（拿掉 precedingUserContext 豁免）", () => {
  // Codex R1 P1-2：舊版只要最近八則有真內容就整批豁免，等於「先正常聊一輪，
  // 之後連丟兩個無關詞」永遠不強制。把那句真內容放在最近第 1～8 個玩家位置，
  // 第二個無關詞都要被攔下來。
  // R2 P3-7：完整交替（每個玩家訊息之間都有一則她的回覆），不再出現連續兩則
  // user；`gap` ＝那句真內容與「韓國」之間隔幾個玩家訊息。
  for (let gap = 0; gap < 8; gap++) {
    const filler: PracticeTurn[] = [];
    for (let k = 0; k < gap; k++) {
      filler.push(a("嗯嗯"), u("嗯"));
    }
    const turns: PracticeTurn[] = [
      u("我今天上班超累的 剛到家"),
      ...filler,
      a("是喔 辛苦了"),
      u("韓國"),
      a("你在說什麼？"),
      u("日本"),
    ];
    // 逐字稿必須嚴格交替（不得有連續兩則同角色）。
    for (let i = 1; i < turns.length; i++) {
      assert(turns[i].role !== turns[i - 1].role, `gap=${gap} 第 ${i} 則`);
    }
    const d = policyAt(turns, "normal", false, stateWith(true));
    assertEquals(d.policyMode, "forced", `gap=${gap}`);
    assertEquals(d.forcedAct, "challenge_relevance", `gap=${gap}`);
    // gap ≤ 5 時那句真內容還在 RECENT_USER_WINDOW（8 則）裡，`precedingUserContext`
    // 仍是 true——證明強制**不是**靠它滑出窗口才成立的。
    if (gap <= 5) {
      assertEquals(d.evidence.precedingUserContext, true, `gap=${gap}`);
    }
  }
});

Deno.test("Phase 4.3 R2 P1-2：四種來源（false／true／null／standard）對同一批逐字稿", () => {
  // R2 P1-2：同一份逐字稿不得只因為 mode 或分類器可用性就改變安全邊界。
  // `null`（分類器缺席／解析失敗）與 standard（本來就沒有 state）必須同結果，
  // 而且都是 4.3 之前的 bounded 二選一。
  const cases: [string, PracticeTurn[]][] = [
    ["澄清後丟詞", [u("韓國"), a("你在說什麼？"), u("日本")]],
    ["澄清後丟詞＋前文", [
      u("我今天上班超累的"),
      a("嗯嗯"),
      u("韓國"),
      a("你在說什麼？"),
      u("日本"),
    ]],
    ["內容問題後的短答", [
      u("韓國"),
      a("是喔"),
      u("東京"),
      a("日本還是韓國？"),
      u("日本"),
    ]],
    ["內容問題後的短答＋前文", [
      u("我今天上班超累的"),
      a("嗯嗯"),
      u("韓國"),
      a("是喔"),
      u("東京"),
      a("日本還是韓國？"),
      u("日本"),
    ]],
  ];
  for (const [label, turns] of cases) {
    const byArm = {
      // assisted：分類器說她上一則真的在澄清。
      true: policyAt(turns, "normal", false, stateWith(true)),
      // assisted：分類器說她上一則是內容問題。
      false: policyAt(turns, "normal", false, stateWith(false)),
      // assisted：分類器缺席／解析失敗。
      null: policyAt(turns, "normal", false, stateWith(null)),
      // standard：根本沒有持久化狀態。
      standard: policyAt(turns, "normal"),
    };
    // null 與 standard 必須逐格相同。
    assertEquals(byArm.null.policyMode, byArm.standard.policyMode, label);
    assertEquals(byArm.null.forcedAct, byArm.standard.forcedAct, label);
    assertEquals(
      byArm.null.allowedActSetId,
      byArm.standard.allowedActSetId,
      label,
    );
    // 沒有訊號時一律不強制質疑（維持 4.3 之前的行為）。
    assert(byArm.null.forcedAct !== "challenge_relevance", label);
    assert(byArm.false.forcedAct !== "challenge_relevance", label);
    // `true` 臂在四份逐字稿上都會強制——**這正是本刀唯一的判別器**：結構層
    // 分不出「日本」是回答還是跳題，所以完全跟著分類器走。也就是說邊界的
    // 安全性等於分類器把「日本還是韓國？」判成 false 的準確率（judge prompt
    // 已補反例定義，見 temperature.ts；真實準確率要黑箱才量得到）。
    assertEquals(byArm.true.forcedAct, "challenge_relevance", label);
  }
});

Deno.test("Phase 4.3：priorCoherence === connected 的閘門今天是冗餘的（欠債已被歸零）", () => {
  // 協調者指定「classifier connected → 不強制」。實際上分類器判 connected 會
  // 寫下 repairedAtUserTurns（或走舊 row 的歸零退路），欠債因此是 0，上游的
  // 有效短答免疫格就已經接走。這一支證明它今天恆真，留在條件式裡只是把契約
  // 寫明白，不是靠另一個檔案的副作用。
  const turns = [u("韓國"), a("你在說什麼？"), u("日本")];
  const connectedLegacy: ConversationAgencyState = {
    version: 1,
    lastCoherence: "connected",
    unresolvedCount: 2,
    priorChallengeIssued: true,
    lastAgencyAct: "challenge_relevance",
    aiClarifiedLastTurn: true,
  };
  const d = policyAt(turns, "normal", false, connectedLegacy);
  assertEquals(d.evidence.unresolvedCount, 0);
  assertEquals(d.situation, null);
  // 有修復點的那條路徑同樣把欠債清到 0。
  const connectedMarker: ConversationAgencyState = {
    ...connectedLegacy,
    repairedAtUserTurns: 1,
  };
  assertEquals(
    policyAt(turns, "normal", false, connectedMarker).evidence.unresolvedCount,
    0,
  );
});

Deno.test("Phase 4.3 P3-7：只有三個 clarify_ignored_* 會在 forced act 說明後面附加 set 級文字", () => {
  // 快照：把每一種會走到 forced 的 set id 都列出來，斷言 `AGENCY_SET_LINE`
  // 只認得 clarify_ignored 那三個。多一個 forced set id 想附文字就會撞到這裡。
  const forcedSetIds = [
    "repeated_token_v1",
    "hold_after_challenge_v1",
    "low_value_loop_v1",
    "fragment_no_context_v1",
    "clarify_ignored_easy_v1",
    "clarify_ignored_v1",
    "clarify_ignored_cold_v1",
    // Phase 4.5a 刀 3 的三個新 forced set id 一起列進來。
    "cold_return_v1",
    "read_only_v1",
    "check_out_v1",
  ];
  const withSetLine = forcedSetIds.filter((id) =>
    AGENCY_SET_LINE[id] !== undefined
  );
  assertEquals(withSetLine, [
    "clarify_ignored_easy_v1",
    "clarify_ignored_v1",
    "clarify_ignored_cold_v1",
    // Phase 4.5a 刀 3：`check_out_v1` 補一句口氣；`cold_return_v1`／
    // `read_only_v1` 刻意**不給** set 級文字。
    "check_out_v1",
  ]);
  // bounded 的候選組說明維持原樣（四個），沒有被本刀動到。
  assertEquals(
    Object.keys(AGENCY_SET_LINE).filter((k) =>
      !k.startsWith("clarify_ignored")
    ),
    [
      "answer_or_challenge_v1",
      "answer_or_challenge_easy_v1",
      "answer_or_challenge_persist_v1",
      "answer_or_challenge_persist_easy_v1",
      "check_out_v1",
    ],
  );
});

Deno.test("Phase 4.3 R2 U-8：aiClarifiedLastTurn 的 round-trip——缺席／false／true／字面 null", () => {
  const base = {
    version: 1,
    lastCoherence: "disconnected",
    unresolvedCount: 1,
    priorChallengeIssued: false,
    lastAgencyAct: null,
    repairedAtUserTurns: 2,
    askedAboutUser: true,
  };
  // 缺席：舊 row。整份 state 仍然解析得出來，evidence 端是 null。
  const absent = parseConversationAgencyState({ conversationAgency: base })!;
  assertEquals(absent.aiClarifiedLastTurn, undefined);
  // false／true：原樣保留（兩者意思不同，不得折疊）。
  for (const v of [false, true]) {
    const parsed = parseConversationAgencyState({
      conversationAgency: { ...base, aiClarifiedLastTurn: v },
    })!;
    assertEquals(parsed.aiClarifiedLastTurn, v);
    // 其餘欄位不受影響。
    assertEquals(parsed.repairedAtUserTurns, 2);
    assertEquals(parsed.askedAboutUser, true);
  }
  // 字面 null（JSONB round-trip／RPC／client 可能把省略補成 null）：視同缺席，
  // **不得**讓整份 state 解析失敗把欠債與修復點一起丟掉。
  const nulled = parseConversationAgencyState({
    conversationAgency: { ...base, aiClarifiedLastTurn: null },
  });
  assertEquals(nulled !== null, true);
  assertEquals(nulled!.aiClarifiedLastTurn, undefined);
  assertEquals(nulled!.repairedAtUserTurns, 2);
  assertEquals(nulled!.unresolvedCount, 1);
  // 真的型別不對才整份作廢（既有規則不變）。
  assertEquals(
    parseConversationAgencyState({
      conversationAgency: { ...base, aiClarifiedLastTurn: "true" },
    }),
    null,
  );
  // writer 端：分類器缺席時不落欄位、給了布林就原樣寫（含 false）。
  const decision = agencyPolicyFor(detectAgencyEvidence([u("韓國")]));
  assertEquals(
    nextConversationAgencyState(null, decision, null).aiClarifiedLastTurn,
    undefined,
  );
  for (const v of [false, true]) {
    assertEquals(
      nextConversationAgencyState(null, decision, { aiChallengedThisTurn: v })
        .aiClarifiedLastTurn,
      v,
    );
  }
});

// ── Phase 4.5a（Eric 2026-09-05 拍板：「像真人——真人不會一直陪你耗」）────────
Deno.test("Phase 4.5a 刀 1：是非問句判準只認句尾「嗎／吧／嘛」，容忍句尾裝飾", () => {
  for (
    const yes of [
      "你該不會是要跟我聊韓國吧",
      "你今天也很累嗎",
      "你是說韓國嗎？",
      "是玩猜謎嗎～",
      "你在報地名嗎😂",
      "所以你剛剛在忙喔？現在有空了嘛",
    ]
  ) assertEquals(aiAskedYesNoQuestion(yes), true, yes);
  for (
    const no of [
      "你在說什麼？",
      "那你比較想去哪裡？",
      "你最想去哪",
      "你怎麼了呢",
      "我今天差點睡過頭",
      "",
      // Codex R1 P1-3：句尾有「吧／嘛」但根本不是在問他的兩種形態。
      // 「我先去忙吧」＝她自己的收尾提議（沒有第二人稱）；
      // 「這本來就是韓國嘛」＝陳述（連寬鬆問句判準都不成立）。
      "我先去忙吧",
      "這本來就是韓國嘛",
      "那我先睡了吧",
      "反正就是這樣嘛",
    ]
  ) assertEquals(aiAskedYesNoQuestion(no), false, no);
  // 短答判準：整則錨定，只容忍句尾裝飾。
  for (const t of ["對", "對啊", "不是", "沒錯", "好啊", "對！", "不是😂"]) {
    assertEquals(isYesNoShortAnswer(t), true, t);
  }
  for (
    const t of ["對了我今天有去健身房", "不是啦 我是說剛剛那個", "韓國", "嗯嗯"]
  ) {
    assertEquals(isYesNoShortAnswer(t), false, t);
  }
});

Deno.test("Phase 4.5a 刀 1：她問是非題、他回「對」＝回答了，任何欠債都不得質疑", () => {
  // Eric 的原案：她自己猜「你該不會是要跟我聊韓國吧」，他回「對」。
  const answered = policyAt(
    [u("韓國"), a("你該不會是要跟我聊韓國吧"), u("對")],
    "normal",
    false,
    stateWith(true),
  );
  assertEquals(answered.evidence.utteranceShape, "answer_candidate");
  assertEquals(answered.evidence.answeredYesNo, true);
  assertEquals(answered.situation, null);
  // 挑戰／Game／easy 都一樣（跟有效短答免疫同一個層級，不受難度翻轉）。
  for (const difficulty of ["easy", "normal", "challenge"] as const) {
    assertEquals(
      policyAt(
        [u("韓國"), a("你該不會是要跟我聊韓國吧"), u("對")],
        difficulty,
        difficulty === "challenge",
        stateWith(true),
      ).situation,
      null,
      difficulty,
    );
  }
  // 成對反例 1：她那一則是**開放**問句 → 照 Phase 4.3（分類器說她在澄清就強制）。
  assertEquals(
    policyAt(
      [u("韓國"), a("你在說什麼？"), u("不是")],
      "normal",
      false,
      stateWith(true),
    ).forcedAct,
    "challenge_relevance",
  );
  // 成對反例 2：明示換題不受影響（「對了」開頭不是純肯定短詞）。
  const pivot = policyAt(
    [u("韓國"), a("你該不會是要跟我聊韓國吧"), u("對了我今天去健身房")],
    "normal",
    false,
    stateWith(true),
  );
  assertEquals(pivot.evidence.utteranceShape, "explicit_pivot");
  assertEquals(pivot.evidence.answeredYesNo, false);
  // 成對反例 3：同一個「對」原樣連丟兩次也不算同詞重複的收尾格。
  assertEquals(
    policyAt(
      [a("你是要聊韓國吧"), u("對"), a("你是說真的吧"), u("對")],
      "challenge",
      true,
      stateWith(true),
    ).situation,
    null,
  );
  // `contentUserTurnCount` 那支 caller（`utteranceShapeOf(t, false)`）不受影響：
  // 少一個參數＝逐字沿用 4.3 形狀，「對」仍然算內容、不是 reaction。
  assertEquals(utteranceShapeOf("對", false), "bare_fragment");
  assertEquals(utteranceShapeOf("對", true), "answer_candidate");
  assertEquals(utteranceShapeOf("對", false, true), "answer_candidate");
});

Deno.test("Phase 4.5a 刀 3：收尾格連三輪 → check_out → 已讀；他給內容才「回來但冷」", () => {
  // 逐輪走 production 的兩步（policy → nextConversationAgencyState），
  // 分類器訊號固定成「她一直在澄清、玩家一直沒接上」。
  const turns: PracticeTurn[] = [];
  let state: ConversationAgencyState | null = null;
  const step = (next: PracticeTurn[]) => {
    turns.push(...next);
    const evidence = detectAgencyEvidence(turns, state);
    const decision = agencyPolicyFor(
      evidence,
      agencyThresholdsFor("challenge", true),
    );
    state = nextConversationAgencyState(state, decision, {
      coherence: "disconnected",
      aiChallengedThisTurn: true,
    });
    return decision;
  };
  // Eric 真機序列：韓國 → 日本 → 清邁 → 哈哈 → 阿布達比 → …
  // 第 1 輪：無前文裸詞 → bounded；`ask_intent` 都還沒強制，streak 不動。
  const s1 = step([u("韓國")]);
  assertEquals(s1.allowedActSetId, "fragment_no_context_v1");
  assertEquals(state!.lowValueStreak, undefined);
  // 第 2／3 輪：forced `challenge_relevance` 也算不收斂（CTO 2026-09-05 擴大
  // 入口），streak 0→1→2。
  for (
    const [i, [lead, token]] of ([
      ["你在說什麼？", "日本"],
      ["你到底在講什麼", "清邁"],
    ] as const).entries()
  ) {
    const d = step([a(lead), u(token)]);
    assertEquals(d.forcedAct, "challenge_relevance", token);
    assertEquals(d.evidence.lowValueStreak, i, token);
  }
  // 第 4 輪「哈哈」：純反應詞不介入，streak **保持**（不歸零也不加）。
  assertEquals(step([a("？"), u("哈哈")]).situation, null);
  assertEquals(state!.lowValueStreak, 2);
  // 第 5 輪：收尾格 → streak 到 3。
  const loop = step([a("嗯"), u("阿布達比")]);
  assertEquals(loop.forcedAct, "end_low_value_loop");
  assertEquals(loop.evidence.lowValueStreak, 2);
  // 第 6 輪：streak 已達 3 → 她先去忙了。
  const checkOut = step([a("嗯"), u("曼谷")]);
  assertEquals(checkOut.evidence.lowValueStreak, 3);
  assertEquals(checkOut.forcedAct, "check_out");
  assertEquals(checkOut.allowedActSetId, "check_out_v1");
  assertEquals(state!.checkedOut, true);
  // 第 7～9 輪：他又丟沒內容的東西 → 直接一則「（已讀）」，不打模型。
  for (const token of ["馬尼拉", "銅鑼灣", "東東"]) {
    const d = step([a("嗯"), u(token)]);
    assertEquals(d.forcedAct, "read_only", token);
    assertEquals(d.allowedActSetId, "read_only_v1");
  }
  // 第 10 輪：他終於解釋 → 回來但冷，階梯整條歸零。
  const back = step([a("嗯"), u("我在列下個月可能去的地方啦")]);
  assertEquals(back.evidence.utteranceShape, "self_share");
  assertEquals(back.forcedAct, "cold_return");
  assertEquals(back.allowedActSetId, "cold_return_v1");
  assertEquals(back.situation, "cold_return");
  assertEquals(state!.lastCoherence, "disconnected");
  assertEquals(state!.checkedOut, undefined);
  assertEquals(state!.lowValueStreak, undefined);
});

Deno.test("Phase 4.5a 刀 3：forced `ask_intent` 不算不收斂（第一個裸詞不記帳）", () => {
  // 低容忍分人（`ambiguityTolerance <= 1`）的第一個無前文裸詞是 forced
  // `ask_intent`——她才剛問第一次，不該被記成「又耗了一輪」。
  const thresholds = agencyThresholdsFor("normal", false, {
    initiative: 2,
    topicPersistence: 2,
    ambiguityTolerance: 1,
    skepticism: 2,
  });
  const turns = [u("韓國")];
  const d = agencyPolicyFor(detectAgencyEvidence(turns, null), thresholds);
  assertEquals(d.forcedAct, "ask_intent");
  const next = nextConversationAgencyState(null, d, null);
  assertEquals(next.lowValueStreak, undefined);
  // 成對反例：同一個位置換成 forced `challenge_relevance` 就記帳。
  const challenged = agencyPolicyFor(
    detectAgencyEvidence(
      [u("韓國"), a("你在說什麼？"), u("日本")],
      stateWith(true),
    ),
    agencyThresholdsFor("normal", false),
  );
  assertEquals(challenged.forcedAct, "challenge_relevance");
  assertEquals(
    nextConversationAgencyState(null, challenged, null).lowValueStreak,
    1,
  );
});

Deno.test("Phase 4.5a 刀 3：階梯只吃持久化狀態——standard（prev=null）永遠走不到", () => {
  // 同一批逐字稿，standard 沒有 thread state ⇒ streak／checkedOut 恆 0／false。
  const turns: PracticeTurn[] = [u("韓國")];
  for (const t of ["日本", "清邁", "阿布達比", "曼谷", "馬尼拉", "銅鑼灣"]) {
    turns.push(a("嗯"), u(t));
  }
  const standard = agencyPolicyFor(
    detectAgencyEvidence(turns, null),
    agencyThresholdsFor("challenge", true),
  );
  assertEquals(standard.evidence.lowValueStreak, 0);
  assertEquals(standard.evidence.checkedOut, false);
  assert(standard.forcedAct !== "check_out");
  assert(standard.forcedAct !== "read_only");
  assert(standard.forcedAct !== "cold_return");
  // 反應詞在 checkedOut 之後也算低價值（她說要先忙了，一句「哈哈」不是接回來）。
  const checkedOut: ConversationAgencyState = {
    version: 1,
    lastCoherence: "repetitive",
    unresolvedCount: 0,
    priorChallengeIssued: true,
    lastAgencyAct: "check_out",
    checkedOut: true,
  };
  assertEquals(
    agencyPolicyFor(
      detectAgencyEvidence([a("我先去忙了"), u("哈哈")], checkedOut),
      agencyThresholdsFor("challenge", false),
    ).forcedAct,
    "read_only",
  );
  // 但問句／分享／回答是非題都算內容 → cold_return（不是已讀）。
  for (
    const [text, lead] of [
      ["你在忙什麼？", "我先去忙了"],
      ["我剛剛在想事情啦", "我先去忙了"],
      ["對", "你是不是在耍我吧"],
      // Codex R1 P3-2：不含第一人稱的**解釋句**（`EXPLANATION_RE` 的
      // 「因為」）在 `utteranceShapeOf` 就已經是 `self_share`，所以階梯把它
      // 當內容——釘住這條，不要在重構時掉回 `read_only`。
      ["因為剛剛在列旅遊清單", "我先去忙了"],
      ["就是說剛剛那幾個地名啦", "我先去忙了"],
    ]
  ) {
    assertEquals(
      utteranceShapeOf(text, false) === "self_share" ||
        utteranceShapeOf(text, false) === "question" ||
        text === "對",
      true,
      text,
    );
    assertEquals(
      agencyPolicyFor(
        detectAgencyEvidence([a(lead), u(text)], checkedOut),
        agencyThresholdsFor("challenge", false),
      ).forcedAct,
      "cold_return",
      text,
    );
  }

  // Codex R1 P1-3：她收尾說「我先去忙吧」，玩家回一句「好」**不得**解除
  // checked-out（那不是內容，她也不是在問是非題）。
  const notUnlocked = agencyPolicyFor(
    detectAgencyEvidence([a("我先去忙吧"), u("好")], checkedOut),
    agencyThresholdsFor("challenge", false),
  );
  assertEquals(notUnlocked.evidence.answeredYesNo, false);
  assertEquals(notUnlocked.forcedAct, "read_only");
  assertEquals(
    nextConversationAgencyState(checkedOut, notUnlocked, null).checkedOut,
    true,
  );
  // 成對：真的是非問句仍然算回答了。
  assertEquals(
    detectAgencyEvidence([a("你是說韓國嗎？"), u("不是")], null).answeredYesNo,
    true,
  );
});

Deno.test("Phase 4.5a 刀 3（Codex R1 P1-2）：beginner 的 easy／normal 難度不強制結束", () => {
  // 軌跡 a：連續三次 forced `challenge_relevance`（easy 也會 forced，
  // `clarify_ignored_easy_v1`）→ streak 到 3，但**不得** check_out。
  const turns: PracticeTurn[] = [];
  let state: ConversationAgencyState | null = null;
  const step = (next: PracticeTurn[], difficulty: "easy" | "normal") => {
    turns.push(...next);
    const decision = agencyPolicyFor(
      detectAgencyEvidence(turns, state),
      agencyThresholdsFor(difficulty, false),
    );
    state = nextConversationAgencyState(state, decision, {
      coherence: "disconnected",
      aiChallengedThisTurn: true,
    });
    return decision;
  };
  step([u("韓國")], "easy");
  for (
    const [lead, token] of [
      ["你在說什麼？", "日本"],
      ["你到底在講什麼", "清邁"],
      ["？", "曼谷"],
    ] as const
  ) {
    const d = step([a(lead), u(token)], "easy");
    assert(d.forcedAct !== "check_out", token);
    assert(d.forcedAct !== "read_only", token);
  }
  assertEquals(state!.lowValueStreak, 3);
  assertEquals(state!.checkedOut, undefined);
  // streak 已經滿了，再丟一則低價值仍然不得結束（easy／normal 都測）。
  for (const difficulty of ["easy", "normal"] as const) {
    const d = agencyPolicyFor(
      detectAgencyEvidence([...turns, a("嗯"), u("馬尼拉")], state),
      agencyThresholdsFor(difficulty, false),
    );
    assert(d.forcedAct !== "check_out", difficulty);
    assert(d.forcedAct !== "read_only", difficulty);
    assertEquals(
      nextConversationAgencyState(state, d, null).checkedOut,
      undefined,
      difficulty,
    );
  }
  // 軌跡 b（防禦性）：thread row 被直接種成 streak 3／checkedOut true，
  // easy／normal 一樣不得強制結束；換成挑戰或 Game 才會。
  const seeded: ConversationAgencyState = {
    version: 1,
    lastCoherence: "repetitive",
    unresolvedCount: 3,
    priorChallengeIssued: true,
    lastAgencyAct: "end_low_value_loop",
    lowValueStreak: 3,
    checkedOut: true,
  };
  for (const difficulty of ["easy", "normal"] as const) {
    const d = agencyPolicyFor(
      detectAgencyEvidence([u("韓國"), a("嗯"), u("東京")], seeded),
      agencyThresholdsFor(difficulty, false),
    );
    assert(d.forcedAct !== "check_out", difficulty);
    assert(d.forcedAct !== "read_only", difficulty);
  }
  assertEquals(
    agencyPolicyFor(
      detectAgencyEvidence([u("韓國"), a("嗯"), u("東京")], seeded),
      agencyThresholdsFor("challenge", false),
    ).forcedAct,
    "read_only",
  );
  assertEquals(
    agencyPolicyFor(
      detectAgencyEvidence([u("韓國"), a("嗯"), u("東京")], seeded),
      agencyThresholdsFor("normal", true),
    ).forcedAct,
    "read_only",
  );
});

Deno.test("Phase 4.5a 刀 3：state round-trip——舊 row 缺欄位＝0／false，壞型別整份 null", () => {
  const base = {
    version: 1,
    lastCoherence: "repetitive",
    unresolvedCount: 2,
    priorChallengeIssued: true,
    lastAgencyAct: "hold_position",
  };
  const old = parseConversationAgencyState({ conversationAgency: base });
  assertEquals(old?.lowValueStreak, undefined);
  assertEquals(old?.checkedOut, undefined);
  assertEquals(
    detectAgencyEvidence([u("韓國")], old).lowValueStreak,
    0,
  );
  assertEquals(detectAgencyEvidence([u("韓國")], old).checkedOut, false);
  // 字面 null 視同缺席（同 R2 U-8）；0／false 不落欄位。
  for (
    const raw of [
      { ...base, lowValueStreak: null, checkedOut: null },
      { ...base, lowValueStreak: 0, checkedOut: false },
    ]
  ) {
    const parsed = parseConversationAgencyState({ conversationAgency: raw });
    assert(parsed !== null, JSON.stringify(raw));
    assert(!("lowValueStreak" in parsed!), JSON.stringify(raw));
    assert(!("checkedOut" in parsed!), JSON.stringify(raw));
  }
  assertEquals(
    parseConversationAgencyState({
      conversationAgency: { ...base, lowValueStreak: 2, checkedOut: true },
    }),
    { ...base, lowValueStreak: 2, checkedOut: true } as ConversationAgencyState,
  );
  // Codex R1 P2-2：讀回來就 clamp 在 3（外部寫入的 4／999 不得原樣進 state）。
  for (const raw of [4, 999]) {
    assertEquals(
      parseConversationAgencyState({
        conversationAgency: { ...base, lowValueStreak: raw },
      })?.lowValueStreak,
      3,
      String(raw),
    );
  }
  for (
    const bad of [
      { ...base, lowValueStreak: "2" },
      { ...base, lowValueStreak: -1 },
      { ...base, lowValueStreak: 1.5 },
      { ...base, checkedOut: "true" },
    ]
  ) {
    assertEquals(
      parseConversationAgencyState({ conversationAgency: bad }),
      null,
      JSON.stringify(bad),
    );
  }
});

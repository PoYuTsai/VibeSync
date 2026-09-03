import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  AGENCY_THRESHOLDS,
  type AgencyEvidence,
  agencyModeFor,
  agencyPolicyFor,
  agencyThresholdsFor,
  type ConversationAgencyState,
  detectAgencyEvidence,
  isClarifyingAct,
  nextConversationAgencyState,
  parseConversationAgencyState,
  utteranceShapeOf,
} from "./conversation_agency.ts";
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
) =>
  agencyPolicyFor(
    detectAgencyEvidence(turns),
    agencyThresholdsFor(difficulty, isGame),
  );

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
  assertEquals(a04.situation, "ambiguous_fragment");
  assertEquals(a04.allowedActSetId, "answer_candidate_with_debt_v1");
  assertEquals(a04.policyMode, "bounded");
  assertEquals(a04.forcedAct, null);
  assertEquals(a04.allowedActs, ["acknowledge", "return_to_topic"]);

  // 她**沒有**問問題、玩家連丟詞 → topic_shift_v1。Codex round-1（新項）P1-2：
  // 這個清單也必須含「接住」——結構層看不出第二句是不是連貫的敘事，不能
  // deterministic 地把「順著聊」從候選裡拿掉。
  const shift = policy([u("好市多"), a("喔"), u("曼谷")]);
  assertEquals(shift.situation, "abrupt_topic_shift");
  assertEquals(shift.allowedActSetId, "topic_shift_v1");
  assertEquals(shift.policyMode, "bounded");
  assertEquals(shift.allowedActs, [
    "acknowledge",
    "ask_intent",
    "challenge_relevance",
    "return_to_topic",
  ]);

  // 連續兩則未解、standard 沒有持久化的「已質疑過」→ 三選一 bounded
  // （Codex round-2 P1-2：不再用假旗標把它推成 forced hold_position）。
  const a06 = policy([u("韓國"), a("怎麼了"), u("東京"), a("蛤"), u("淺草")]);
  assertEquals(a06.situation, "repeated_low_coherence");
  assertEquals(a06.policyMode, "bounded");
  assertEquals(a06.allowedActSetId, "low_coherence_v1");
  assert(a06.allowedActs.length >= 2);

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
  const held = nextConversationAgencyState(
    null,
    policy([u("韓國"), a("怎麼了"), u("東京"), a("蛤"), u("淺草")]),
  );
  // standard 這一輪是 bounded（沒有 forcedAct），所以 lastAgencyAct 不變、
  // priorChallengeIssued 也不會被「允許過」灌成 true（Codex round-1 P1）。
  assertEquals(held, {
    version: 1,
    lastCoherence: "repetitive",
    unresolvedCount: 2,
    priorChallengeIssued: false,
    lastAgencyAct: null,
  });
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
      assertEquals(next.priorChallengeIssued, false, JSON.stringify({ signal, turns }));
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

Deno.test("難度門檻：易難度指出跳題延後到第 2–3 則未解，一般／挑戰第 2 則就進入", () => {
  // 兩個裸片段連續（第二則 unresolvedCount＝1）：一般／挑戰已經進
  // topic_shift_v1（指出跳題）；易難度還在「跟第一則一樣寬容」的窗口內，
  // 沒有前文時仍是 fragment_no_context_v1 bounded，不是 topic_shift_v1。
  const twoFragments = [u("韓國"), u("東京")];
  const normalSecond = policyAt(twoFragments, "normal");
  assertEquals(normalSecond.allowedActSetId, "topic_shift_v1");
  const challengeSecond = policyAt(twoFragments, "challenge");
  assertEquals(challengeSecond.allowedActSetId, "topic_shift_v1");
  // 易難度：第二則（unresolvedCount=1）既沒到 topicShiftAt，也不再落到
  // fragment_no_context_v1——Codex round-2 P1-1 把那條收緊成「未解計數真的
  // 是 0」的全空集合，所以這一格改成完全不介入。
  const easySecond = policyAt(twoFragments, "easy");
  assertEquals(easySecond.situation, null);
  assertEquals(easySecond.allowedActSetId, "none");

  // 第三個裸片段（unresolvedCount＝2）：一般／挑戰已經進入
  // repeated_low_coherence；易難度這時才第一次進 topic_shift_v1。
  const threeFragments = [u("韓國"), u("東京"), u("清邁")];
  const normalThird = policyAt(threeFragments, "normal");
  assertEquals(normalThird.situation, "repeated_low_coherence");
  const easyThird = policyAt(threeFragments, "easy");
  assertEquals(easyThird.allowedActSetId, "topic_shift_v1");

  // 第四個裸片段（unresolvedCount＝3）：易難度這時才第一次進
  // repeated_low_coherence——比一般／挑戰晚兩則，符合「2–3 則才指出模式」。
  const fourFragments = [u("韓國"), u("東京"), u("清邁"), u("曼谷")];
  const easyFourth = policyAt(fourFragments, "easy");
  assertEquals(easyFourth.situation, "repeated_low_coherence");
});

Deno.test("難度門檻：挑戰／game 在達到低連貫門檻時直接收掉（不是維持立場），一般／易仍是維持立場", () => {
  // 真的走 detectAgencyEvidence：三個地名連丟，第三則（unresolvedCount=2）
  // 一般難度已達 lowCoherenceAt。forceEndLoopBeforeChallenge 獨立於
  // priorChallengeIssued 判斷，挑戰／game 在真實流量下也一定選到
  // end_low_value_loop，不會被「已質疑過」蓋成 hold_position。
  const threeFragments = [u("韓國"), u("東京"), u("清邁")];
  // Codex round-2 P1-2：standard 不再假裝「已經質疑過」，一般難度落在三選一
  // bounded（維持立場仍在選項裡）；挑戰／game 的 forceEndLoopBeforeChallenge
  // 獨立於那個旗標，照樣直接收掉。
  const normal = policyAt(threeFragments, "normal");
  assertEquals(normal.policyMode, "bounded");
  assert(normal.allowedActs.includes("hold_position"));

  const challenge = policyAt(threeFragments, "challenge");
  assertEquals(challenge.policyMode, "forced");
  assertEquals(challenge.forcedAct, "end_low_value_loop");

  const game = policyAt(threeFragments, "normal", true);
  assertEquals(game.policyMode, "forced");
  assertEquals(game.forcedAct, "end_low_value_loop");

  // 還沒質疑過（手動組 evidence；detectAgencyEvidence 在 standard 模式結構上
  // 幾乎不會產生這個組合，見 agencyPolicyFor 內註解）：一般難度先給一輪
  // bounded 機會，挑戰／game 仍然直接收掉。
  const notYetChallenged: AgencyEvidence = {
    utteranceShape: "bare_fragment",
    previousAiAskedQuestion: false,
    explicitPivot: false,
    repeatedExactToken: false,
    unresolvedCount: 2,
    priorChallengeIssued: false,
    precedingUserContext: false,
  };
  const normalFirstTime = agencyPolicyFor(
    notYetChallenged,
    AGENCY_THRESHOLDS.normal,
  );
  assertEquals(normalFirstTime.policyMode, "bounded");
  assertEquals(normalFirstTime.allowedActSetId, "low_coherence_v1");
  const challengeFirstTime = agencyPolicyFor(
    notYetChallenged,
    AGENCY_THRESHOLDS.challenge,
  );
  assertEquals(challengeFirstTime.policyMode, "forced");
  assertEquals(challengeFirstTime.forcedAct, "end_low_value_loop");
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
    assertEquals(decision.policyMode, "bounded");
    assertEquals(decision.forcedAct, null);
    assertEquals(decision.allowedActs, ["acknowledge", "return_to_topic"]);
    assertEquals(decision.allowedActSetId, "answer_candidate_with_debt_v1");
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
      assert(
        decision.allowedActs.includes("acknowledge"),
        `${label}：候選清單少了 acknowledge`,
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
        d.allowedActs.includes("acknowledge"),
        `${difficulty}／${turns.at(-1)!.text} 少了 acknowledge`,
      );
    }
  }
  // forced 仍然只有兩格：同詞原樣再丟一次、欠債到門檻；act 都不是質疑。
  for (
    const turns of [
      [u("好市多"), a("？"), u("好市多")],
      [u("韓國"), a("怎麼了"), u("東京"), a("蛤"), u("淺草")],
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

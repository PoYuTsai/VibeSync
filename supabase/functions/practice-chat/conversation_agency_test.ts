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
  // 同一個長裸敘述當開場：normal 直接 forced 只問意思。
  const longDecision = agencyPolicyFor(detectAgencyEvidence([u(longBare)]));
  assertEquals(longDecision.situation, "ambiguous_fragment");
  assertEquals(longDecision.policyMode, "forced");
  assertEquals(longDecision.forcedAct, "ask_intent");
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

Deno.test("forced 只給結構線索的全空集合；其餘 bounded 真的有兩個以上選項", () => {
  // 無前文裸片段（A02／A08）：七個結構條件全部是「線索不存在」（見
  // agencyPolicyFor 的註解），信心夠高 → 一般難度 forced「只問意思」。
  // 這裡沒有任何字數條件，上面「長裸敘述」那條測試證明了同一件事。
  const a02 = policy([u("韓國")]);
  assertEquals(a02.situation, "ambiguous_fragment");
  assertEquals(a02.allowedActSetId, "fragment_no_context_v1");
  assertEquals(a02.policyMode, "forced");
  assertEquals(a02.forcedAct, "ask_intent");

  // A04：她問了問題、玩家丟別的詞（前面還有未解片段）→ 真 bounded（3 選 1）。
  const a04 = policy([u("東東"), a("東東是誰"), u("阿布達比")]);
  assertEquals(a04.situation, "abrupt_topic_shift");
  assertEquals(a04.allowedActSetId, "topic_shift_v1");
  assertEquals(a04.policyMode, "bounded");
  assert(a04.allowedActs.length >= 2, "bounded 至少要有兩個選項才叫 bounded");
  assert(!a04.allowedActs.includes("acknowledge"), "沒回答就不供應新解讀");

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

Deno.test("nextConversationAgencyState：只存 enum／布林／小整數，質疑過就不會退回", () => {
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
  // 玩家講清楚了：coherence 回 connected、未解歸零；質疑歷史沿用前一份狀態。
  const recovered = nextConversationAgencyState(
    { ...held, priorChallengeIssued: true, lastAgencyAct: "hold_position" },
    policy([a("那你最想去哪個國家玩"), u("韓國")]),
  );
  assertEquals(recovered.lastCoherence, "connected");
  assertEquals(recovered.unresolvedCount, 0);
  assertEquals(recovered.priorChallengeIssued, true);
  assertEquals(recovered.lastAgencyAct, "hold_position");
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

Deno.test("難度門檻：第一個無前文片段——易仍是兩選一 bounded，一般／挑戰／Game 強制只問意思", () => {
  const fragment = [u("韓國")];
  const easy = policyAt(fragment, "easy");
  assertEquals(easy.policyMode, "bounded");
  assertEquals(easy.forcedAct, null);
  assertEquals(easy.allowedActs, ["acknowledge", "ask_intent"]);

  for (const d of ["normal", "challenge"] as const) {
    const decision = policyAt(fragment, d);
    assertEquals(decision.policyMode, "forced", d);
    assertEquals(decision.forcedAct, "ask_intent", d);
  }

  // Game 套挑戰門檻。
  const game = policyAt(fragment, "normal", true);
  assertEquals(game.policyMode, "forced");
  assertEquals(game.forcedAct, "ask_intent");
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
  const easySecond = policyAt(twoFragments, "easy");
  assertEquals(easySecond.allowedActSetId, "fragment_no_context_v1");

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

Deno.test("Codex round-1 P1-a：旗標 off 的 recent_facts 從零重建（未知 key 掉），≠off 才保留", () => {
  // 保留未知 key 是 agency 分支帶進來的行為改動。旗標關著時 payload 必須跟
  // main 逐字相同——main 從零重建 recent_facts，別人寫的 key 本來就會掉。
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
  assertEquals(facts({ ...base, agencyMode: "off" }), mainPayload);
  for (const agencyMode of ["shadow", "on"] as const) {
    assertEquals(facts({ ...base, agencyMode }), {
      ...mainPayload,
      someOtherFeature: { keep: true },
    });
  }
});

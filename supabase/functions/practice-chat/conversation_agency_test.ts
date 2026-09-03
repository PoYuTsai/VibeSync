import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type AgencyEvidence,
  agencyModeFor,
  agencyPolicyFor,
  type ConversationAgencyState,
  detectAgencyEvidence,
  isClarifyingAct,
  nextConversationAgencyState,
  parseConversationAgencyState,
  utteranceShapeOf,
} from "./conversation_agency.ts";
import type { PracticeTurn } from "./validate.ts";

const u = (text: string): PracticeTurn => ({ role: "user", text });
const a = (text: string): PracticeTurn => ({ role: "ai", text });
const policy = (turns: PracticeTurn[]) =>
  agencyPolicyFor(detectAgencyEvidence(turns));

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
  // 長句沒有第一人稱也不是問句＝unknown（不介入，不硬判成亂聊）。
  assertEquals(
    utteranceShapeOf("嗨 看你自介好像蠻喜歡到處跑的", false),
    "unknown",
  );
  assertEquals(utteranceShapeOf("   ", false), "unknown");
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
  // 「說到一半」是抱怨被打斷，不是宣告轉場。
  assertEquals(
    utteranceShapeOf("你每次都說到一半就不講了", false),
    "unknown",
  );
  // 引號內引用別人講過的詞，不是自己在宣告轉場。
  assertEquals(
    utteranceShapeOf("他那時候就說「對了」然後就不說了", false),
    "unknown",
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
  assertEquals(e.priorChallengeIssued, true);
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

Deno.test("forced 只給高信心結構；其餘一律 bounded", () => {
  // 這一場完全沒有前文的裸片段（A02／A08）：Codex P1——長度／無前文不是高信心
  // 結構，不能強制她一定要問；改成 bounded，acknowledge／ask_intent 都給，
  // 由看得到全文的生成模型自己判斷（「今天好熱喔」這種看得懂的開場也是這個
  // 分支，不該被逼問）。
  const a02 = policy([u("韓國")]);
  assertEquals(a02.situation, "ambiguous_fragment");
  assertEquals(a02.allowedActSetId, "fragment_no_context_v1");
  assertEquals(a02.policyMode, "bounded");
  assertEquals(a02.forcedAct, null);
  assert(a02.allowedActs.includes("ask_intent"), "必須提供可以問清楚的選項");
  assert(a02.allowedActs.includes("acknowledge"), "必須允許她看得懂就接住");

  // A04：她問了問題、玩家丟別的詞（前面還有未解片段）。
  const a04 = policy([u("東東"), a("東東是誰"), u("阿布達比")]);
  assertEquals(a04.situation, "abrupt_topic_shift");
  assertEquals(a04.allowedActSetId, "topic_shift_v1");
  assert(!a04.allowedActs.includes("acknowledge"), "沒回答就不供應新解讀");

  // 連續兩則未解＋已質疑過 → 強制維持立場（跨輪立場）。
  const a06 = policy([u("韓國"), a("怎麼了"), u("東京"), a("蛤"), u("淺草")]);
  assertEquals(a06.situation, "repeated_low_coherence");
  assertEquals(a06.policyMode, "forced");
  assertEquals(a06.forcedAct, "hold_position");

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
  assertEquals(held, {
    version: 1,
    lastCoherence: "repetitive",
    unresolvedCount: 2,
    priorChallengeIssued: true,
    lastAgencyAct: "hold_position",
  });
  // 玩家講清楚了：coherence 回 connected、未解歸零，但質疑歷史保留。
  const recovered = nextConversationAgencyState(
    held,
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
  // 但未解計數一律從逐字稿重算，不會被上一輪的狀態灌大。
  assertEquals(carried.unresolvedCount, 0);
});

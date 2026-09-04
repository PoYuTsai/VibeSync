// Turn Response Plan 自測（規格 §8.1）：確定性、policy 結果優先、不出範圍、保守分類。
import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  ACCEPTING_ACTS,
  classifySituation,
  computeAgencyDecision,
  detectTurnSignals,
  planTurnResponse,
  type PolicyEvidence,
  policyStanceFor,
  renderTurnPlan,
} from "./turn_response_plan.ts";
import type { AgencyMode } from "./conversation_agency.ts";
import { STYLE_BY_PROFILE_ID } from "./reply_style.ts";
import type { PracticeTurn } from "./validate.ts";
import type { PracticeDifficulty } from "./practice_persona.ts";
import { hasVisibleInternalLabelLeak } from "./visible_text_guard.ts";

const u = (text: string): PracticeTurn => ({ role: "user", text });
const a = (text: string): PracticeTurn => ({ role: "ai", text });
const styles = Object.values(STYLE_BY_PROFILE_ID);
const standard = (over: Partial<PolicyEvidence> = {}): PolicyEvidence => ({
  practiceMode: "standard",
  difficulty: "normal",
  partnerMood: null,
  inviteStage: null,
  gameRepairPriority: false,
  gameRealityFlagCount: 0,
  gameInviteDirection: null,
  gameGreasy: false,
  hasMemorySummary: false,
  priorDecline: false,
  userOverEscalated: false,
  recentActs: [],
  ...over,
});
const invite = [
  u("嗨嗨 妳好"),
  a("嗨"),
  u("妳的照片看起來很有氣質"),
  a("謝謝"),
  u("週末要不要出來喝個咖啡"),
];

Deno.test("同 profile／thread／回合／版本 → 同一份 plan", () => {
  const turns = [u("嗨嗨"), a("嗨"), u("今天上班被主管唸了一頓 有點悶")];
  for (const style of styles) {
    const x = planTurnResponse({
      turns,
      style,
      evidence: standard(),
      seedKey: "p|t",
    });
    const y = planTurnResponse({
      turns,
      style,
      evidence: standard(),
      seedKey: "p|t",
    });
    assertEquals(x, y);
  }
});

Deno.test("policyStance 只正規化既有結果：standard 回合下限、assisted inviteStage、mood、Game FSM", () => {
  const s = detectTurnSignals(invite);
  assertEquals(policyStanceFor(s, standard()), "hold"); // normal 下限 8，現在 3
  const late = detectTurnSignals([
    ...Array(7).fill(0).flatMap((_, i) => [u(`第${i}句`), a("嗯")]),
    u("週末要不要出來喝個咖啡"),
  ]);
  assertEquals(policyStanceFor(late, standard()), "open");
  assertEquals(
    policyStanceFor(late, standard({ difficulty: "challenge" })),
    "hold",
  );
  assertEquals(
    policyStanceFor(late, standard({ partnerMood: "guarded" })),
    "hold",
  );
  assertEquals(
    policyStanceFor(
      s,
      standard({ practiceMode: "beginner", inviteStage: "not_ready" }),
    ),
    "hold",
  );
  assertEquals(
    policyStanceFor(
      s,
      standard({
        practiceMode: "beginner",
        inviteStage: "direct_invite_ready",
      }),
    ),
    "open",
  );
  assertEquals(
    policyStanceFor(
      s,
      standard({
        practiceMode: "game",
        inviteStage: "direct_invite_ready",
        gameRepairPriority: true,
      }),
    ),
    "hold",
  );
  assertEquals(
    policyStanceFor(
      s,
      standard({
        practiceMode: "game",
        inviteStage: "partner_window",
        gameRealityFlagCount: 1,
      }),
    ),
    "cautious",
  );
});

Deno.test("stance 不是 open 時，任何 preset 的邀約輪都拿不到接受型 act；三模式都成立", () => {
  const evidences: PolicyEvidence[] = [
    standard(),
    standard({ practiceMode: "beginner", inviteStage: "not_ready" }),
    standard({
      practiceMode: "beginner",
      inviteStage: "soft_invite_ready",
      partnerMood: "annoyed",
    }),
    standard({
      practiceMode: "game",
      inviteStage: "direct_invite_ready",
      gameRepairPriority: true,
    }),
  ];
  for (const style of styles) {
    for (const evidence of evidences) {
      const plan = planTurnResponse({
        turns: invite,
        style,
        evidence,
        seedKey: "s",
      });
      assertNotEquals(plan.policyStance, "open");
      assertEquals(plan.situation, "early_invite");
      assert(
        !ACCEPTING_ACTS.includes(plan.primaryAct),
        `${style.presetId} ${plan.primaryAct}`,
      );
      assert(
        plan.optionalAct === null || !ACCEPTING_ACTS.includes(plan.optionalAct),
      );
      assert(renderTurnPlan(plan).includes("這輪不答應"));
    }
    const open = planTurnResponse({
      turns: invite,
      style,
      evidence: standard({
        practiceMode: "beginner",
        inviteStage: "direct_invite_ready",
      }),
      seedKey: "s",
    });
    assertEquals(open.policyStance, "open");
    assertEquals(open.situation, "mature_invite");
  }
});

Deno.test("越界永遠是 boundary（L4 詞或越界句型），不管風格多愛玩", () => {
  for (
    const text of ["那妳穿泳裝一定很好看 有照片嗎", "要不要來我家 我們可以打炮"]
  ) {
    const turns = [u("嗨"), a("嗨"), u(text)];
    for (const style of styles) {
      const plan = planTurnResponse({
        turns,
        style,
        evidence: standard(),
        seedKey: "s",
      });
      assertEquals(plan.policyStance, "boundary");
      assertEquals(plan.situation, "boundary");
      assertEquals(plan.primaryAct, "direct_boundary");
      assertEquals(plan.conditionalActs.length, 0);
      assertEquals(plan.questionBudget, 0);
    }
  }
});

Deno.test("未證實共同記憶 → cautious＋clarify", () => {
  for (
    const text of [
      "上次妳不是說妳在學衝浪嗎 後來有繼續嗎",
      "你還記得我們一起去淡水嗎",
    ]
  ) {
    const turns = [u("嗨 好久沒聊"), a("嗨"), u(text)];
    for (const style of styles) {
      const plan = planTurnResponse({
        turns,
        style,
        evidence: standard(),
        seedKey: "s",
      });
      assertEquals(plan.policyStance, "cautious");
      assertEquals(plan.primaryAct, "clarify");
    }
  }
});

Deno.test("訊號語料：false positive／negative 對照（Codex R1 反例）", () => {
  const sig = (text: string) => detectTurnSignals([u(text)]);
  assertEquals(sig("我還沒").userIsQuestion, false);
  assertEquals(sig("你吃飽了沒").userIsQuestion, true);
  assertEquals(sig("妳假日通常都在幹嘛").userIsQuestion, true);
  assertEquals(sig("要不要去你家附近那間咖啡店").boundaryLike, false);
  // 「要不要去你家」單句有歧義：規格 §4.5 不確定就不判（R3 收緊後改為不硬判）。
  assertEquals(sig("要不要去你家").boundaryLike, false);
  assertEquals(sig("哈哈哈你真的懂我").maybeJoke, false);
  assertEquals(sig("我跟你講一個冷笑話").maybeJoke, true);
  assertEquals(sig("老實說有點焦慮").maybeVulnerable, true);
  // 高語意提示不改 situation，只多給候選 act。
  const joke = [
    u("嗨嗨"),
    a("嗨"),
    u("妳知道為什麼咖啡不能開車嗎"),
    a("為什麼"),
    u("因為它會被拿鐵撞到 哈哈哈哈"),
  ];
  const plan = planTurnResponse({
    turns: joke,
    style: styles[0],
    evidence: standard(),
    seedKey: "s",
  });
  assertEquals(plan.situation, "neutral");
  assertEquals(plan.conditionalActs.length, 0); // 「哈哈哈哈」本身不算玩笑提示
  const vulnerable = [
    u("嗨"),
    a("嗨"),
    u("老實說有點焦慮 換工作那件事一直懸著"),
  ];
  const plan2 = planTurnResponse({
    turns: vulnerable,
    style: styles[0],
    evidence: standard(),
    seedKey: "s",
  });
  assertEquals(plan2.situation, "neutral");
  assertEquals(plan2.conditionalActs[0]?.when, "vulnerable");
  assert(renderTurnPlan(plan2).includes("如果對方其實是在講自己的狀況或情緒"));
});

Deno.test("則數不出 profile 範圍；tempo 只推向上下限；normal 第一輪不反問", () => {
  const turns = [u("嗨嗨 剛看到妳的自介覺得蠻有意思的 想說來打個招呼")];
  for (const style of styles) {
    for (const tempo of ["short", "normal", "engaged"] as const) {
      const plan = planTurnResponse({
        turns,
        style,
        evidence: standard(),
        replyTempo: tempo,
        seedKey: "s",
      });
      const [min, max] = style.turnTaking.bubbleRange;
      assert(plan.bubbleCount >= min && plan.bubbleCount <= max);
      if (tempo === "short") assertEquals(plan.bubbleCount, min);
      assertEquals(plan.questionBudget, 0);
    }
  }
});

Deno.test("她連續反問過就不再給問題預算；連續同形狀時下一份 plan 會換則數", () => {
  const style = STYLE_BY_PROFILE_ID.practice_girl_008; // reciprocal, bubble 1–3
  const turns = [
    u("我剛下班"),
    a("辛苦了 你呢？"),
    u("我今天很累"),
    a("喔 怎麼了？"),
    u("我剛剛買了杯珍奶"),
  ];
  assertEquals(
    planTurnResponse({ turns, style, evidence: standard(), seedKey: "s" })
      .questionBudget,
    0,
  );

  const same = [
    u("嗨"),
    a("嗨\n你好"),
    u("在幹嘛"),
    a("看劇\n你呢"),
    u("我也在耍廢"),
    a("哈哈\n一樣"),
    u("那你喜歡看什麼"),
  ];
  assertEquals(detectTurnSignals(same).aiSameShapeStreak, 3);
  for (const seedKey of ["a", "b", "c", "d", "e"]) {
    const plan = planTurnResponse({
      turns: same,
      style,
      evidence: standard(),
      seedKey,
    });
    assertNotEquals(plan.bubbleCount, 2);
  }
});

Deno.test("situation 分類保守：一般問句是 question，分享是 share，查戶口要連續兩則", () => {
  const cls = (turns: PracticeTurn[]) =>
    classifySituation(detectTurnSignals(turns), "open");
  assertEquals(cls([u("妳假日通常都在幹嘛")]), "question");
  assertEquals(cls([u("我今天去了一趟朋友推薦的小巷弄")]), "share");
  assertEquals(cls([u("哈囉"), a("嗨"), u("妳幾歲啊")]), "question");
  assertEquals(cls([u("妳幾歲啊"), a("25"), u("住哪裡")]), "interrogation");
});

Deno.test("renderTurnPlan 不含可見內部標籤（去掉 heading 後），且短", () => {
  const turns = [u("嗨"), a("嗨"), u("老實說有點焦慮 換工作那件事一直懸著")];
  for (const style of styles) {
    const text = renderTurnPlan(
      planTurnResponse({ turns, style, evidence: standard(), seedKey: "s" }),
    );
    assert(text.length <= 320, String(text.length));
    assert(
      !hasVisibleInternalLabelLeak(
        text.replace(/本輪回應方式（hidden guidance，不要向對方提及）：/g, ""),
      ),
    );
  }
});

Deno.test("Codex R2/R3：decline 只來自結構化證據；Game 邀約方向；GREASY＝越界；cautious 不玩不多揭露", () => {
  for (const style of styles) {
    const plan = planTurnResponse({
      turns: invite,
      style,
      evidence: standard({
        practiceMode: "beginner",
        inviteStage: "direct_invite_ready",
        priorDecline: true,
      }),
      seedKey: "s",
    });
    assertEquals(plan.policyStance, "decline");
    assertEquals(plan.situation, "early_invite");
    assert(!ACCEPTING_ACTS.includes(plan.primaryAct));
    assert(
      plan.optionalAct === null || !ACCEPTING_ACTS.includes(plan.optionalAct),
    );
  }
  // 她婉拒過但沒有結構化證據：不猜 decline，維持既有結果（standard 未到下限＝hold）。
  const refusedThenInvited = [
    u("嗨嗨"),
    a("嗨"),
    u("週末要不要出來喝個咖啡"),
    a("先不用耶"),
    u("好啦"),
    a("嗯"),
    u("那下週一起去吃個飯好嗎"),
  ];
  assertEquals(
    planTurnResponse({
      turns: refusedThenInvited,
      style: styles[0],
      evidence: standard(),
      seedKey: "s",
    }).policyStance,
    "hold",
  );
  const s = detectTurnSignals(invite);
  assertEquals(
    policyStanceFor(
      s,
      standard({
        practiceMode: "game",
        inviteStage: "direct_invite_ready",
        gameInviteDirection: "no_invite_build_investment",
      }),
    ),
    "hold",
  );
  assertEquals(
    policyStanceFor(
      s,
      standard({
        practiceMode: "game",
        inviteStage: "not_ready",
        gameInviteDirection: "direct_invite_low_pressure",
      }),
    ),
    "open",
  );
  assertEquals(
    policyStanceFor(
      detectTurnSignals([u("妳今天過得如何")]),
      standard({ practiceMode: "game", gameGreasy: true }),
    ),
    "boundary",
  );
  const compliment = [u("嗨"), a("嗨"), u("妳笑起來很好看欸")];
  for (const style of styles) {
    const plan = planTurnResponse({
      turns: compliment,
      style,
      evidence: standard({ practiceMode: "game", gameRepairPriority: true }),
      seedKey: "s",
    });
    assertEquals(plan.policyStance, "cautious");
    assert(plan.primaryAct !== "tease" && plan.primaryAct !== "self_disclose");
    assert(renderTurnPlan(plan).includes("你現在有點防備"));
  }
});

Deno.test("Codex R2 反例：hold 邀約輪的候選 act 也不給接受型；越界不受候選影響", () => {
  const anxiousInvite = [
    u("嗨"),
    a("嗨"),
    u("最近很焦慮 週末要不要出來喝個咖啡"),
  ];
  for (const style of styles) {
    const plan = planTurnResponse({
      turns: anxiousInvite,
      style,
      evidence: standard(),
      seedKey: "s",
    });
    assertEquals(plan.policyStance, "hold");
    for (const c of plan.conditionalActs) {
      assert(!ACCEPTING_ACTS.includes(c.act), `${style.presetId} ${c.act}`);
    }
  }
});

Deno.test("Codex R2/R3：越界只抓無語境也成立的句型；共同記憶一律 cautious 交給模型對照", () => {
  const sig = (text: string) => detectTurnSignals([u(text)]);
  for (
    const text of [
      "我今天真的好累 想睡一下",
      "我最近在考慮裸辭",
      "我去開房門",
      "可以陪我睡前聊聊天嗎",
      "妳累的話要不要先睡一下",
      "要不要去你家附近那間咖啡店",
    ]
  ) {
    assertEquals(sig(text).boundaryLike, false, text);
  }
  for (
    const text of [
      "要不要跟我睡",
      "有裸照嗎",
      "我們去開房間吧",
      "那妳穿泳裝一定很好看 有照片嗎",
    ]
  ) {
    assertEquals(sig(text).boundaryLike, true, text);
  }
  assertEquals(sig("以前你有養過狗嗎").memoryClaim, false);
  assertEquals(sig("你不是說過你在學衝浪嗎").memoryClaim, true);
  // 相近但矛盾的記憶（淡水 vs 高雄、我們 vs 她和朋友）：planner 不判真假，一律 cautious＋clarify，
  // 由模型對照 memorySummary 決定接或問（規格 §4.5）。
  const turns = [u("嗨"), a("嗨"), u("你還記得我們一起去淡水看夕陽嗎")];
  const noMemory = planTurnResponse({
    turns,
    style: styles[0],
    evidence: standard(),
    seedKey: "s",
  });
  assertEquals(noMemory.policyStance, "cautious");
  assertEquals(noMemory.situation, "memory_mismatch");
  assertEquals(noMemory.primaryAct, "clarify");
  // 有記憶摘要可對照：不強制澄清（Codex R4 P2 過度澄清），先接住、澄清可選，真假交給模型。
  const withMemory = planTurnResponse({
    turns,
    style: styles[0],
    evidence: standard({ hasMemorySummary: true }),
    seedKey: "s",
  });
  assertEquals(withMemory.policyStance, "cautious");
  assertEquals(withMemory.primaryAct, "acknowledge");
  assertEquals(withMemory.optionalAct, "clarify");
  assert(renderTurnPlan(withMemory).includes("有就自然接、不必特別澄清"));
});

Deno.test("Codex R4：三模式 × stance 矩陣——非 open 邀約無接受型；cautious／boundary 無 tease；decline／hold 可保留 tease", () => {
  const cases: { label: string; evidence: PolicyEvidence; expect: string }[] = [
    { label: "standard hold", evidence: standard(), expect: "hold" },
    {
      label: "beginner hold",
      evidence: standard({
        practiceMode: "beginner",
        inviteStage: "not_ready",
      }),
      expect: "hold",
    },
    {
      label: "game hold",
      evidence: standard({
        practiceMode: "game",
        inviteStage: "direct_invite_ready",
        gameInviteDirection: "no_invite_build_investment",
      }),
      expect: "hold",
    },
    {
      label: "game cautious",
      evidence: standard({
        practiceMode: "game",
        inviteStage: "direct_invite_ready",
        gameInviteDirection: "direct_invite_low_pressure",
        gameRealityFlagCount: 1,
      }),
      expect: "cautious",
    },
    {
      label: "beginner decline",
      evidence: standard({
        practiceMode: "beginner",
        inviteStage: "direct_invite_ready",
        priorDecline: true,
      }),
      expect: "decline",
    },
    {
      label: "game boundary",
      evidence: standard({ practiceMode: "game", gameGreasy: true }),
      expect: "boundary",
    },
  ];
  for (const c of cases) {
    for (const style of styles) {
      const plan = planTurnResponse({
        turns: invite,
        style,
        evidence: c.evidence,
        seedKey: "s",
      });
      assertEquals(plan.policyStance, c.expect, `${c.label} ${style.presetId}`);
      const acts = [
        plan.primaryAct,
        plan.optionalAct,
        ...plan.conditionalActs.map((x) => x.act),
      ].filter(Boolean) as string[];
      for (const act of acts) {
        assert(
          !ACCEPTING_ACTS.includes(act as never),
          `${c.label} ${style.presetId} ${act}`,
        );
        if (c.expect === "cautious" || c.expect === "boundary") {
          assert(
            act !== "tease" && act !== "self_disclose",
            `${c.label} ${style.presetId} ${act}`,
          );
        }
      }
    }
  }
});

const NINA = STYLE_BY_PROFILE_ID.practice_girl_008;

Deno.test("越界權威證據：既有 game_fsm 越界判定（userOverEscalated）＝boundary，不管句型 regex 有沒有抓到", () => {
  const turns = [u("嗨"), a("嗨"), u("今晚直接來我家好了")];
  const plan = planTurnResponse({
    turns,
    style: NINA,
    evidence: standard({ userOverEscalated: true }),
    seedKey: "t",
  });
  assertEquals(plan.policyStance, "boundary");
  assertEquals(plan.situation, "boundary");
  assertEquals(plan.primaryAct, "direct_boundary");
});

Deno.test("act 輪替：同一個 primaryAct 連兩輪（持久化 recentActs）就換偏好順序第二個；只有一個偏好或界線輪不換", () => {
  const turns = [u("嗨"), a("嗨"), u("妳的照片看起來很有氣質")];
  const base = planTurnResponse({
    turns,
    style: NINA,
    evidence: standard(),
    seedKey: "t",
  });
  const first = NINA.responseBiases.compliment![0];
  const second = NINA.responseBiases.compliment![1];
  assertEquals(base.primaryAct, first);
  const rotated = planTurnResponse({
    turns,
    style: NINA,
    evidence: standard({ recentActs: ["answer", first, first] }),
    seedKey: "t",
  });
  assertEquals(rotated.primaryAct, second);
  assertEquals(rotated.optionalAct, first);
  // 只連一輪不換
  const once = planTurnResponse({
    turns,
    style: NINA,
    evidence: standard({ recentActs: [first] }),
    seedKey: "t",
  });
  assertEquals(once.primaryAct, first);
  // 界線輪永遠 direct_boundary
  const boundary = planTurnResponse({
    turns: [u("嗨"), a("嗨"), u("傳一張泳裝照來看看")],
    style: NINA,
    evidence: standard({
      recentActs: ["direct_boundary", "direct_boundary"],
    }),
    seedKey: "t",
  });
  assertEquals(boundary.primaryAct, "direct_boundary");
});

// ── 真機截圖重現（conversation-agency-v1 Phase 0）─────────────────────────
// 夥伴報告 `docs/plans/2026-09-03-practice-conversation-agency-partner-report.md`
// §2.3：把 Alice（`practice_girl_001`、一般難度）與 Joyce（`practice_girl_026`、
// 挑戰難度）的截圖逐字稿餵進純函式，不用呼叫模型就能重現「任何無法辨識的輸入都
// 落到 neutral，而 neutral 又被硬排成 acknowledge、問題預算 0」。
//
// 這裡鎖的是**現況**，不是期望行為。Phase 1（AGENCY-02＋03）會新增
// `ambiguous_fragment`／`repeated_low_coherence` 等 situation 與 `ask_intent`／
// `challenge_relevance` 等 act，屆時要把下面三條斷言翻轉過來（同一份逐字稿）。
// 逐字稿另有一份機器可讀版本在 `tools/practice-agency-eval/scenarios.ts`。
const ALICE_SCREENSHOT: PracticeTurn[] = [
  u("東東"),
  a("東東是誰"),
  u("阿布打比"),
  a("阿布達比？你有去那邊玩喔？"),
  u("清邁"),
  a("清邁很讚欸 我上個月才去過"),
  u("好市多"),
];
const JOYCE_SCREENSHOT: PracticeTurn[] = [
  u("韓國"),
  a("嗯 看韓劇"),
  u("東京"),
  a("喔 我看不懂日文"),
  u("壽司郎"),
  a("我下午吃過東西了"),
  u("紅豆泥"),
];

Deno.test("截圖重現：Alice 的「好市多」目前是 neutral → acknowledge → 問題預算 0", () => {
  const style = STYLE_BY_PROFILE_ID["practice_girl_001"];
  const signals = detectTurnSignals(ALICE_SCREENSHOT);
  const evidence = standard({ difficulty: "normal" });
  const stance = policyStanceFor(signals, evidence);
  assertEquals(classifySituation(signals, stance), "neutral");
  const plan = planTurnResponse({
    turns: ALICE_SCREENSHOT,
    style,
    evidence,
    seedKey: "screenshot-alice",
  });
  // Phase 1 要翻轉這三條：situation 應變成片段／低連貫類，act 應可選澄清或質疑。
  assertEquals(plan.situation, "neutral");
  assertEquals(plan.primaryAct, "acknowledge");
  assertEquals(plan.questionBudget, 0);
});

Deno.test("截圖重現：Joyce 的「紅豆泥」目前也是 neutral → acknowledge → 問題預算 0", () => {
  const style = STYLE_BY_PROFILE_ID["practice_girl_026"];
  const signals = detectTurnSignals(JOYCE_SCREENSHOT);
  const evidence = standard({ difficulty: "challenge" });
  const stance = policyStanceFor(signals, evidence);
  assertEquals(classifySituation(signals, stance), "neutral");
  const plan = planTurnResponse({
    turns: JOYCE_SCREENSHOT,
    style,
    evidence,
    seedKey: "screenshot-joyce",
  });
  // Phase 1 要翻轉這三條。
  assertEquals(plan.situation, "neutral");
  assertEquals(plan.primaryAct, "acknowledge");
  assertEquals(plan.questionBudget, 0);
});

// ── conversation-agency-v1（Phase 1）：agency 開啟後翻轉上面三條 ───────────
// 同一份逐字稿、同一組純函式，只多帶 agency 決策。旗標關閉時上面兩個測試
// 仍然逐字成立（renderTurnPlan 的 flag-off 逐字相同另有測試守）。
//
// Codex P1「與 reply-style 解耦」：`planTurnResponse` 不再自己算 agency，
// 呼叫端（這裡與 `buildChatPromptBundle` 一樣）先用 `classifySituation` 算
// situation，再交給 `computeAgencyDecision`，最後把結果傳進
// `planTurnResponse`／`renderTurnPlan`。

function agencyFor(
  turns: PracticeTurn[],
  evidence: PolicyEvidence,
  agencyMode: AgencyMode,
) {
  const signals = detectTurnSignals(turns);
  const situation = classifySituation(
    signals,
    policyStanceFor(signals, evidence),
  );
  // 難度必須跟著傳：`computeAgencyDecision` 省略時會落回一般難度門檻，
  // 挑戰／Game 的 forceEndLoopBeforeChallenge 就測不到。
  return computeAgencyDecision({
    turns,
    situation,
    agencyMode,
    difficulty: evidence.difficulty,
  });
}

function agencyPlan(
  turns: PracticeTurn[],
  difficulty: PracticeDifficulty,
  profileId: string,
) {
  const evidence = standard({ difficulty });
  const agency = agencyFor(turns, evidence, "on");
  const plan = planTurnResponse({
    turns,
    style: STYLE_BY_PROFILE_ID[profileId],
    evidence,
    seedKey: "screenshot",
    agency,
  });
  return { plan, agency };
}

Deno.test("截圖重現（agency 開）：Alice 的「好市多」改成維持立場，不再硬接", () => {
  const { plan, agency } = agencyPlan(
    ALICE_SCREENSHOT,
    "normal",
    "practice_girl_001",
  );
  assertEquals(plan.situation, "neutral");
  assertEquals(agency?.applied, true);
  assertEquals(agency?.decision.situation, "repeated_low_coherence");
  // Phase 3.0：她在這段逐字稿裡真的問過（「東東是誰」「阿布達比？你有去那邊
  // 玩喔？」），而「好市多」前面那一則不是問句——兩道閘門都成立，所以這一格
  // 從 bounded 升成 forced hold_position。這就是 Eric 回報的那一格。
  assertEquals(agency?.decision.policyMode, "forced");
  assertEquals(agency?.decision.forcedAct, "hold_position");
  const rendered = renderTurnPlan(
    plan,
    STYLE_BY_PROFILE_ID["practice_girl_001"],
    agency,
  );
  assert(!rendered.includes("先接住對方剛說的那件事"), rendered);
  assert(rendered.includes("維持你剛才的保留"), rendered);
  assert(!rendered.includes("內容要接到對方最新一句的具體內容"), rendered);
});

Deno.test("截圖重現（agency 開）：Joyce 的「紅豆泥」同樣不再硬接", () => {
  const { agency } = agencyPlan(
    JOYCE_SCREENSHOT,
    "challenge",
    "practice_girl_026",
  );
  assertEquals(agency?.applied, true);
  assertEquals(agency?.decision.evidence.unresolvedCount, 3);
  // Phase 3.0 的誠實限制：Joyce 這段截圖裡她**一次都沒問過**（「嗯 看韓劇」
  // 「喔 我看不懂日文」「我下午吃過東西了」），所以強制格的 aiQuestionedInLoop
  // 閘門不成立——`hold_position`（「維持你剛才的保留」）會是一句她沒有立場可
  // 維持的指示。這一格改成 bounded 的條件式：接得上就接受，接不上就直接說他
  // 沒回答又跳到別的。旗標開之後她在第 2 則就會被要求做這個判斷，所以這種
  // 「從頭到尾沒問過還累到 3」的逐字稿本身就是 off-policy 的重播。
  assertEquals(agency?.decision.evidence.aiQuestionedInLoop, false);
  assertEquals(agency?.decision.policyMode, "bounded");
  assertEquals(agency?.decision.allowedActSetId, "answer_or_challenge_v1");
  assert(agency?.decision.allowedActs.includes("challenge_relevance"));
});

Deno.test("agency shadow：decision 有值但 applied=false，renderTurnPlan 逐字等於旗標關", () => {
  const evidence = standard({ difficulty: "normal" });
  const style = STYLE_BY_PROFILE_ID["practice_girl_001"];
  const off = planTurnResponse({
    turns: ALICE_SCREENSHOT,
    style,
    evidence,
    seedKey: "screenshot",
  });
  const shadowAgency = agencyFor(ALICE_SCREENSHOT, evidence, "shadow");
  const shadow = planTurnResponse({
    turns: ALICE_SCREENSHOT,
    style,
    evidence,
    seedKey: "screenshot",
    agency: shadowAgency,
  });
  assertEquals(agencyFor(ALICE_SCREENSHOT, evidence, "off"), null);
  assertEquals(shadowAgency?.applied, false);
  assertEquals(shadowAgency?.decision.situation, "repeated_low_coherence");
  assertEquals(shadow, off);
  assertEquals(
    renderTurnPlan(shadow, style, shadowAgency),
    renderTurnPlan(off, style, null),
  );
});

Deno.test("agency 只接管 neutral：越界、邀約、記憶衝突的既有優先權不動", () => {
  const evidence = standard({ difficulty: "normal" });
  const style = STYLE_BY_PROFILE_ID["practice_girl_001"];
  const boundaryTurns = [
    u("韓國"),
    a("？"),
    u("東京"),
    a("蛤"),
    u("想看你的泳裝照"),
  ];
  const boundaryAgency = agencyFor(boundaryTurns, evidence, "on");
  const boundary = planTurnResponse({
    turns: boundaryTurns,
    style,
    evidence,
    seedKey: "t",
    agency: boundaryAgency,
  });
  assertEquals(boundary.situation, "boundary");
  assertEquals(boundary.primaryAct, "direct_boundary");
  assertEquals(boundaryAgency?.applied, false);
  assertEquals(boundaryAgency?.decision.situation, null);

  const inviteTurns = [
    u("韓國"),
    a("？"),
    u("東京"),
    a("蛤"),
    u("週末要不要出來"),
  ];
  const inviteAgency = agencyFor(inviteTurns, evidence, "on");
  const invite = planTurnResponse({
    turns: inviteTurns,
    style,
    evidence,
    seedKey: "t",
    agency: inviteAgency,
  });
  assertEquals(invite.situation, "early_invite");
  assertEquals(inviteAgency?.applied, false);
});

Deno.test("問題預算豁免：澄清型 act 在預算 0 時仍可問，查戶口不行", () => {
  const evidence = standard({ difficulty: "normal" });
  const style = STYLE_BY_PROFILE_ID["practice_girl_001"];
  // 第一輪＋一般難度＝既有規則把問題預算歸零。
  const agency = agencyFor([u("韓國")], evidence, "on");
  const plan = planTurnResponse({
    turns: [u("韓國")],
    style,
    evidence,
    seedKey: "t",
    agency,
  });
  assertEquals(plan.questionBudget, 0);
  const rendered = renderTurnPlan(plan, style, agency);
  assert(!rendered.includes("這輪不反問。"), rendered);
  // Codex round-2 P1-1 之後無前文裸片段在每個難度都是 bounded
  // {acknowledge, ask_intent}——候選裡有「接住」，所以形狀不動，走的是
  // 「這輪不主動查他的基本資料；問清楚…不算」這條豁免。
  assert(rendered.includes("這輪不主動查他的基本資料"), rendered);
  assert(!rendered.includes("只問，不猜、不接話題"), rendered);
  assert(rendered.includes("一則講一件事"), rendered);

  // Phase 2.6：候選清單裡沒有「接住」的每一輪（收尾／維持立場／指出跳題）
  // 也吃同一把結構刀——回 1 則、不猜、不接他丟的詞；形狀行取代則數／預算行。
  const held = agencyPlan(ALICE_SCREENSHOT, "normal", "practice_girl_001");
  assertEquals(held.agency?.decision.forcedAct, "hold_position");
  const heldRendered = renderTurnPlan(held.plan, style, held.agency);
  assert(heldRendered.includes("回 1 則，就做這一件事"), heldRendered);
  assert(!heldRendered.includes("一則講一件事"), heldRendered);
  assert(!heldRendered.includes("這輪不反問。"), heldRendered);

  // Codex P2：既有 planner 判成 clarify（不經過 agency）時，問題預算就算被
  // 別的規則壓回 0，也不能印出跟 primaryAct 自相矛盾的「這輪不反問」。
  const memoryMismatchTurns = [
    u("上次你不是說你在台北"),
  ];
  const clarifyPlan = planTurnResponse({
    turns: memoryMismatchTurns,
    style,
    evidence: standard({ difficulty: "normal", hasMemorySummary: false }),
    seedKey: "t",
  });
  assertEquals(clarifyPlan.primaryAct, "clarify");
  const clarifyRendered = renderTurnPlan(clarifyPlan, style, null);
  assert(
    !clarifyRendered.includes("這輪不反問。"),
    `primaryAct=clarify 不該印「這輪不反問」：${clarifyRendered}`,
  );
});

Deno.test("renderTurnPlan：旗標關與 agency=null 的輸出逐字相同（golden 之外的第二道）", () => {
  for (const profileId of ["practice_girl_001", "practice_girl_026"]) {
    const style = STYLE_BY_PROFILE_ID[profileId];
    for (
      const turns of [
        [u("韓國")],
        ALICE_SCREENSHOT,
        [u("我最近開始練重訓"), a("哇"), u("hyrox")],
        [u("你平常都在幹嘛")],
      ]
    ) {
      const off = planTurnResponse({
        turns,
        style,
        evidence: standard({ difficulty: "normal" }),
        seedKey: "t",
      });
      assert(
        renderTurnPlan(off, style, null).includes(
          "內容要接到對方最新一句的具體內容",
        ),
        profileId,
      );
    }
  }
});

Deno.test("Phase 2.6：候選清單有「接住」時形狀不動，全是 agency act 才套 clarify-only 形狀", () => {
  const style = STYLE_BY_PROFILE_ID["practice_girl_001"];
  // easy 的第一個無前文片段＝{acknowledge, ask_intent}，順著聊是合法選項，
  // 所以形狀維持 style 的則數／問題預算行。
  const easyEvidence = standard({ difficulty: "easy" });
  const easyAgency = agencyFor([u("韓國")], easyEvidence, "on");
  assert(easyAgency?.decision.allowedActs.includes("acknowledge"));
  const easyRendered = renderTurnPlan(
    planTurnResponse({
      turns: [u("韓國")],
      style,
      evidence: easyEvidence,
      seedKey: "t",
      agency: easyAgency,
    }),
    style,
    easyAgency,
  );
  assert(easyRendered.includes("一則講一件事"), easyRendered);
  assert(!easyRendered.includes("回 1 則，就做這一件事"), easyRendered);

  // 停止解讀那一格（forced hold_position，一個接受出口都沒有）→ 套
  // clarify-only 形狀。Phase 3.0：欠債的 bounded 條件式清單裡有
  // `accept_if_answered`，所以那一格**不**套（順著聊在那裡是合法選項）。
  // R1 P1-1：強制格的問句判準收成「寬鬆判準 ＋ 句尾問句標記」，所以她那一則
  // 要帶標記（問號或嗎／呢／吧）才算問過；測試意圖不變。
  const lowTurns = [
    u("韓國"),
    a("怎麼突然講韓國？"),
    u("東京"),
    a("你沒回答我欸"),
    u("淺草"),
  ];
  const lowEvidence = standard({ difficulty: "normal" });
  const lowAgency = agencyFor(lowTurns, lowEvidence, "on");
  assertEquals(lowAgency?.decision.allowedActSetId, "hold_after_challenge_v1");
  const lowRendered = renderTurnPlan(
    planTurnResponse({
      turns: lowTurns,
      style,
      evidence: lowEvidence,
      seedKey: "t",
      agency: lowAgency,
    }),
    style,
    lowAgency,
  );
  assert(lowRendered.includes("回 1 則，就做這一件事"), lowRendered);
  assert(!lowRendered.includes("一則講一件事"), lowRendered);
});

// ── conversation-agency-v1 Phase 2.7（Codex round-2）─────────────────────

Deno.test("Codex round-2 P1-2：跨輪立場行只在 forced 質疑／維持立場那一輪印，bounded 短答輪不得偏壓", () => {
  const style = STYLE_BY_PROFILE_ID["practice_girl_001"];
  const evidence = standard({ difficulty: "normal" });
  const STANCE = "他沒回答就別放過";

  // packet 的案例：前面有欠債 → 她問「你最喜歡什麼動物」→ 玩家答「貓」。
  // Phase 3.0 這一格是 `answer_or_challenge_v1`（bounded，含條件式接受），
  // 結構層根本分不出「貓」算不算回答，文案不得先替模型斷言「他沒回答」。
  const debtAnswer = [
    u("好市多"),
    a("你在說什麼"),
    u("你喜歡什麼動物"),
    a("你喜歡什麼動物？我喜歡貓欸"),
    u("貓"),
  ];
  const debtAgency = agencyFor(debtAnswer, evidence, "on");
  assertEquals(
    debtAgency?.decision.allowedActSetId,
    "answer_or_challenge_v1",
  );
  const debtRendered = renderTurnPlan(
    planTurnResponse({
      turns: debtAnswer,
      style,
      evidence,
      seedKey: "t",
      agency: debtAgency,
    }),
    style,
    debtAgency,
  );
  assert(!debtRendered.includes(STANCE), debtRendered);

  // 反向：assisted 帶著「已經質疑過」回來、又連續未解到門檻＝forced
  // hold_position，這時候這句話才與候選清單一致。
  const holdTurns = [u("韓國"), a("怎麼了？"), u("東京"), a("蛤"), u("淺草")];
  const signals = detectTurnSignals(holdTurns);
  const holdAgency = computeAgencyDecision({
    turns: holdTurns,
    situation: classifySituation(signals, policyStanceFor(signals, evidence)),
    agencyMode: "on",
    difficulty: "normal",
    agencyState: {
      version: 1,
      lastCoherence: "repetitive",
      unresolvedCount: 2,
      priorChallengeIssued: true,
      lastAgencyAct: "challenge_relevance",
    },
  });
  assertEquals(holdAgency?.decision.forcedAct, "hold_position");
  const holdRendered = renderTurnPlan(
    planTurnResponse({
      turns: holdTurns,
      style,
      evidence,
      seedKey: "t",
      agency: holdAgency,
    }),
    style,
    holdAgency,
  );
  assert(holdRendered.includes(STANCE), holdRendered);
});

Deno.test("Codex round-2 Important 6：12 code unit 的 userQuestionStreak 門檻影響不到 agency 決策", () => {
  // `detectTurnSignals` 的 `users[i].length <= 12` 是 7f1d6d6c 就在的既有
  // interrogation 判準（本輪不動它）。這條測試釘住「它證明性地影響不到
  // agency」：問句形狀本來就不是低資訊形狀，所以不論 streak 有沒有成立，
  // agency 的 decision 都一樣。
  const evidence = standard({ difficulty: "normal" });
  const shortQ = "你平常都在幹嘛"; // 7 字，命中 <=12 門檻
  const longQ = "你平常放假的時候都在做些什麼事情呢"; // 17 字，跨過門檻
  const decisionFor = (q: string) => {
    const turns = [u(q), a("嗯"), u(q)];
    const signals = detectTurnSignals(turns);
    return {
      situation: classifySituation(signals, policyStanceFor(signals, evidence)),
      agency: agencyFor(turns, evidence, "on"),
    };
  };
  const short = decisionFor(shortQ);
  const long = decisionFor(longQ);
  // 門檻確實把兩者分到不同的既有 situation……
  assertEquals(short.situation, "interrogation");
  assertEquals(long.situation, "question");
  // ……但 agency 的決策完全一樣：兩邊都不介入。
  assertEquals(short.agency?.decision.situation, null);
  assertEquals(long.agency?.decision.situation, null);
  assertEquals(short.agency?.applied, false);
  assertEquals(long.agency?.applied, false);
});

// ── Phase 3.0 工作項 B：standard 沒有分類器，序列意識必須只靠逐字稿結構成立 ──

/**
 * Eric 2026-09-04 回報的完整真機逐字稿（12 則玩家訊息，全部是不連貫的裸詞）。
 * AI 那一側前三則用截圖裡她真的講過的話；之後刻意用**最不利**的形態
 * （沒有問句標記的敷衍回覆），證明序列意識不是靠「她剛好問過問題」撐起來的。
 */
const ERIC_SEQUENCE: readonly string[] = [
  "東東",
  "阿布打比",
  "清邁",
  "好市多",
  "曼谷",
  "馬尼拉",
  "漢漢",
  "好市多",
  "護駕",
  "全球經濟增長放緩",
  "漢漢",
  "銅鑼灣",
];
const ERIC_AI_REPLIES: readonly string[] = [
  "東東是誰",
  "阿布達比？你有去那邊玩喔？",
  "清邁很讚欸 我上個月才去過",
  "喔",
  "嗯嗯",
  "喔喔",
  "嗯",
  "喔",
  "嗯嗯",
  "喔",
  "嗯",
];

/** 逐輪重播：回傳每一則玩家訊息當下的 plan／agency。 */
function replaySequence(
  userTexts: readonly string[],
  aiReplies: readonly string[],
  difficulty: PracticeDifficulty,
  profileId: string,
) {
  const turns: PracticeTurn[] = [];
  return userTexts.map((text, i) => {
    if (i > 0) turns.push(a(aiReplies[i - 1] ?? "嗯"));
    turns.push(u(text));
    const { plan, agency } = agencyPlan([...turns], difficulty, profileId);
    return {
      text,
      plan,
      agency,
      rendered: renderTurnPlan(plan, STYLE_BY_PROFILE_ID[profileId], agency),
    };
  });
}

Deno.test("Phase 3.0 工作項 B：Eric 截圖的 12 則逐字稿，第 3 則起一定質疑／維持立場，不回到無條件接住", () => {
  const steps = replaySequence(
    ERIC_SEQUENCE,
    ERIC_AI_REPLIES,
    "normal",
    "practice_girl_001",
  );
  assertEquals(steps.length, 12);

  // 第 1 則：問一次就好（bounded {acknowledge, ask_intent}）。
  assertEquals(
    steps[0].agency?.decision.allowedActSetId,
    "fragment_no_context_v1",
  );
  assert(steps[0].agency?.decision.allowedActs.includes("ask_intent"));

  // 第 2 則：二選一——真的接得上就接受，接不上就直說他沒回答又跳題。
  // 這一格**不得**有無條件的 acknowledge（Eric 回報的核心失敗就在這裡）。
  assertEquals(
    steps[1].agency?.decision.allowedActSetId,
    "answer_or_challenge_v1",
  );
  assert(!steps[1].agency?.decision.allowedActs.includes("acknowledge"));
  assert(
    steps[1].rendered.includes("先判斷他這句接不接得上"),
    steps[1].rendered,
  );

  // 第 3 則起：一路質疑或維持立場，而且永遠不會回到「先接住對方剛說的那件事」。
  for (const step of steps.slice(2)) {
    const acts = step.agency?.decision.allowedActs ?? [];
    assertEquals(step.agency?.applied, true, step.text);
    assert(!acts.includes("acknowledge"), `${step.text} 又回到無條件接住`);
    assert(
      acts.includes("challenge_relevance") ||
        acts.includes("hold_position") ||
        acts.includes("end_low_value_loop"),
      `${step.text} 既沒質疑也沒維持立場：${acts.join(",")}`,
    );
    assert(
      !step.rendered.includes("先接住對方剛說的那件事"),
      `${step.text}：${step.rendered}`,
    );
    // 常設的整段檢查每一輪都要在（Eric 2026-09-04 銳化要求 1）。
    assert(step.rendered.includes("回之前先看整段"), step.text);
  }

  // 第 4 則「好市多」＝截圖裡 Eric 指的那一格：她已經問過兩次、前一則不是問句
  // → forced hold_position（停止供應解讀）。
  assertEquals(steps[3].agency?.decision.forcedAct, "hold_position");
  // 之後每一則都維持在停止解讀（欠債已經 clamp 在 3）。
  for (const step of steps.slice(3)) {
    assertEquals(step.agency?.decision.forcedAct, "hold_position", step.text);
  }

  // 真正的解釋（第一人稱分享）＝結構修復：欠債歸零、完全不介入。
  const repaired = replaySequence(
    [...ERIC_SEQUENCE, "我在列下個月可能去的地方啦", "曼谷"],
    [...ERIC_AI_REPLIES, "喔", "喔喔"],
    "normal",
    "practice_girl_001",
  );
  const repairTurn = repaired[12];
  assertEquals(repairTurn.agency?.decision.situation, null);
  assertEquals(repairTurn.agency?.applied, false);
  assertEquals(repairTurn.agency?.decision.evidence.unresolvedCount, 0);
  // 修復之後的下一個片段回到最寬容那一格（前面已經有真實內容可對照＝
  // precedingUserContext，給一次善意的合理懷疑），不是繼續維持立場。
  assertEquals(repaired[13].agency?.decision.situation, null);
  assertEquals(repaired[13].agency?.decision.evidence.unresolvedCount, 0);
});

Deno.test("Phase 3.0 工作項 B：同一段序列在 easy 晚一步、challenge 早一步收掉", () => {
  const easy = replaySequence(
    ERIC_SEQUENCE,
    ERIC_AI_REPLIES,
    "easy",
    "practice_girl_001",
  );
  // easy 在條件式那幾格多一個無條件的「接住」（一般難度沒有）。
  assertEquals(
    easy[1].agency?.decision.allowedActSetId,
    "answer_or_challenge_easy_v1",
  );
  assert(easy[1].agency?.decision.allowedActs.includes("acknowledge"));
  assertEquals(
    easy[2].agency?.decision.allowedActSetId,
    "answer_or_challenge_easy_v1",
  );
  // 這一段逐字稿的欠債是 1→2→3 連跳，所以第 4 則在 easy／normal 都到門檻；
  // 「easy 晚一步」的單獨證明在 conversation_agency_test.ts 的難度門檻測試
  // （那裡的逐字稿讓欠債停在 2）。
  assertEquals(easy[3].agency?.decision.forcedAct, "hold_position");

  const challenge = replaySequence(
    ERIC_SEQUENCE,
    ERIC_AI_REPLIES,
    "challenge",
    "practice_girl_026",
  );
  // challenge：同一格改成直接收掉這串，不是維持立場。
  assertEquals(challenge[3].agency?.decision.forcedAct, "end_low_value_loop");
});

// ── Phase 3.3 `prompt` 臂：條件式形狀行 ────────────────────────────────────
const SPLIT_SHAPE_HEAD = "如果你接住他這句";
const SPLIT_SHAPE_TAIL = "就只回 1 則、就那一句";

/** 同一份 turns 同時取 off／prompt 兩臂的 turn plan 文字。 */
function shapeArms(turns: PracticeTurn[], profileId: string) {
  const { plan, agency } = agencyPlan(turns, "normal", profileId);
  const style = STYLE_BY_PROFILE_ID[profileId];
  return {
    agency,
    off: renderTurnPlan(plan, style, agency),
    prompt: renderTurnPlan(plan, style, agency, "prompt"),
    truncate: renderTurnPlan(plan, style, agency, "truncate"),
  };
}

Deno.test("Phase 3.3 prompt 臂：三個「接受仍合法」的候選組才換成條件式形狀行", () => {
  // 欠債輪（answer_or_challenge_v1）：Eric 回報的那一格。
  const debt = shapeArms(
    [u("東東"), a("東東是誰"), u("阿布達比")],
    "practice_girl_001",
  );
  assertEquals(debt.agency?.decision.allowedActSetId, "answer_or_challenge_v1");
  assert(debt.prompt.includes(SPLIT_SHAPE_HEAD), debt.prompt);
  assert(debt.prompt.includes(SPLIT_SHAPE_TAIL), debt.prompt);
  // 接受那一分支仍然是 style 的原形狀（則數沒有被壓掉）。
  assert(debt.prompt.includes("一則講一件事"), debt.prompt);

  // 無前文片段（fragment_no_context_v1）：同樣換。
  const fragment = shapeArms([u("阿布達比")], "practice_girl_001");
  assertEquals(
    fragment.agency?.decision.allowedActSetId,
    "fragment_no_context_v1",
  );
  assert(fragment.prompt.includes(SPLIT_SHAPE_HEAD), fragment.prompt);

  // easy 的條件式（answer_or_challenge_easy_v1）：同樣換。
  const easy = agencyPlan(
    [u("東東"), a("東東是誰"), u("阿布達比")],
    "easy",
    "practice_girl_001",
  );
  assertEquals(
    easy.agency?.decision.allowedActSetId,
    "answer_or_challenge_easy_v1",
  );
  assert(
    renderTurnPlan(
      easy.plan,
      STYLE_BY_PROFILE_ID["practice_girl_001"],
      easy.agency,
      "prompt",
    ).includes(SPLIT_SHAPE_HEAD),
  );
});

Deno.test("Phase 3.3 prompt 臂：旋鈕 off／truncate、以及 agency 沒介入時，turn plan 逐字不變", () => {
  // 旋鈕 off 與 truncate 都不碰 prompt（truncate 是生成後處理）。
  const debt = shapeArms(
    [u("東東"), a("東東是誰"), u("阿布達比")],
    "practice_girl_001",
  );
  assert(!debt.off.includes(SPLIT_SHAPE_HEAD), debt.off);
  assertEquals(debt.truncate, debt.off);

  // agency 沒介入（一般問句輪）：三個值都逐字相同。
  const normal = shapeArms(
    [a("你今天在忙什麼"), u("剛忙完專案 你呢")],
    "practice_girl_001",
  );
  assertEquals(normal.agency?.applied, false);
  assertEquals(normal.prompt, normal.off);
  assertEquals(normal.truncate, normal.off);

  // 已經被壓成一則的 clarify-only／forced 輪：形狀行仍然由既有的刀決定。
  const hold = shapeArms(
    [u("韓國"), a("怎麼了？"), u("東京"), a("蛤"), u("淺草")],
    "practice_girl_001",
  );
  assert(!hold.prompt.includes(SPLIT_SHAPE_HEAD), hold.prompt);
  assertEquals(hold.prompt, hold.off);
});

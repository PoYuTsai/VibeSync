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
  const situation = classifySituation(signals, policyStanceFor(signals, evidence));
  return computeAgencyDecision({ turns, situation, agencyMode });
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
  assertEquals(agency?.decision.forcedAct, "hold_position");
  assertEquals(agency?.decision.evidence.unresolvedCount, 3);
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
  assert(rendered.includes("這輪不主動查他的基本資料"), rendered);
  assert(rendered.includes("問清楚他這句的意思或拉回前一題不算"), rendered);

  // 強制 hold／收尾沒有澄清型 act＝仍然是原本的「這輪不反問」。
  const held = agencyPlan(ALICE_SCREENSHOT, "normal", "practice_girl_001");
  assert(
    renderTurnPlan(held.plan, style, held.agency).includes("這輪不反問。"),
  );

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

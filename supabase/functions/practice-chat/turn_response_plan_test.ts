// Turn Response Plan 自測（規格 §8.1）：確定性、policy 結果優先、不出範圍、保守分類。
import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  ACCEPTING_ACTS,
  classifySituation,
  detectTurnSignals,
  planTurnResponse,
  type PolicyEvidence,
  policyStanceFor,
  renderTurnPlan,
} from "./turn_response_plan.ts";
import { STYLE_BY_PROFILE_ID } from "./reply_style.ts";
import type { PracticeTurn } from "./validate.ts";
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
      assert(["direct_boundary", "soft_deflect"].includes(plan.primaryAct));
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
  assertEquals(sig("要不要去你家").boundaryLike, true);
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

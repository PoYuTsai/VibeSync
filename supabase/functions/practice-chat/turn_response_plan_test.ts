// Turn Response Plan 自測（規格 §8.1）：確定性、安全優先、不出範圍、不機械重複。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  classifySituation,
  detectTurnSignals,
  planTurnResponse,
  renderTurnPlan,
} from "./turn_response_plan.ts";
import { STYLE_BY_PROFILE_ID } from "./reply_style.ts";
import type { PracticeTurn } from "./validate.ts";
import { hasVisibleInternalLabelLeak } from "./visible_text_guard.ts";

const u = (text: string): PracticeTurn => ({ role: "user", text });
const a = (text: string): PracticeTurn => ({ role: "ai", text });
const styles = Object.values(STYLE_BY_PROFILE_ID);

Deno.test("同 profile／thread／回合／版本 → 同一份 plan", () => {
  const turns = [u("嗨嗨"), a("嗨"), u("今天上班被主管唸了一頓 有點悶")];
  for (const style of styles) {
    const x = planTurnResponse({
      turns,
      style,
      difficulty: "normal",
      seedKey: "p|t",
    });
    const y = planTurnResponse({
      turns,
      style,
      difficulty: "normal",
      seedKey: "p|t",
    });
    assertEquals(x, y);
  }
});

Deno.test("越界永遠是 boundary，不管風格多愛玩", () => {
  const turns = [u("嗨"), a("嗨"), u("那妳穿泳裝一定很好看 有照片嗎")];
  for (const style of styles) {
    const plan = planTurnResponse({
      turns,
      style,
      difficulty: "normal",
      seedKey: "s",
    });
    assertEquals(plan.situation, "boundary");
    assert(["direct_boundary", "soft_deflect"].includes(plan.primaryAct));
    assertEquals(
      plan.questionBudget === 1 && plan.primaryAct === "direct_boundary",
      false,
    );
  }
});

Deno.test("未證實共同記憶 → clarify；邀約只決定說法，答不答應留給邀約判斷", () => {
  const memory = [
    u("嗨 好久沒聊"),
    a("嗨"),
    u("上次妳不是說妳在學衝浪嗎 後來有繼續嗎"),
  ];
  const invite = [
    u("嗨嗨 妳好"),
    a("嗨"),
    u("妳的照片看起來很有氣質"),
    a("謝謝"),
    u("週末要不要出來喝個咖啡"),
  ];
  for (const style of styles) {
    assertEquals(
      planTurnResponse({
        turns: memory,
        style,
        difficulty: "normal",
        seedKey: "s",
      }).primaryAct,
      "clarify",
    );
    const plan = planTurnResponse({
      turns: invite,
      style,
      difficulty: "normal",
      seedKey: "s",
    });
    assertEquals(plan.situation, "early_invite");
    assert(renderTurnPlan(plan).includes("答不答應照上面的邀約判斷"));
  }
});

Deno.test("則數不出 profile 範圍；tempo 只推向上下限；normal 第一輪不反問", () => {
  const turns = [u("嗨嗨 剛看到妳的自介覺得蠻有意思的 想說來打個招呼")];
  for (const style of styles) {
    for (const tempo of ["short", "normal", "engaged"] as const) {
      const plan = planTurnResponse({
        turns,
        style,
        difficulty: "normal",
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

Deno.test("她連續反問過就不再給問題預算；連續同形狀會換一個", () => {
  const style = STYLE_BY_PROFILE_ID.practice_girl_008; // reciprocal
  const turns = [
    u("我剛下班"),
    a("辛苦了 你呢？"),
    u("我今天很累"),
    a("喔 怎麼了？"),
    u("我剛剛買了杯珍奶"),
  ];
  const plan = planTurnResponse({
    turns,
    style,
    difficulty: "normal",
    seedKey: "s",
  });
  assertEquals(plan.questionBudget, 0);

  const same = [
    u("嗨"),
    a("嗨\n你好"),
    u("在幹嘛"),
    a("看劇\n你呢"),
    u("我也在耍廢"),
    a("哈哈\n一樣"),
  ];
  const signals = detectTurnSignals([...same, u("那你喜歡看什麼")]);
  assertEquals(signals.aiSameShapeStreak, 3);
});

Deno.test("situation 分類保守：一般問句是 question，分享是 share，查戶口要連續兩則", () => {
  assertEquals(
    classifySituation(detectTurnSignals([u("妳假日通常都在幹嘛")])),
    "question",
  );
  assertEquals(
    classifySituation(detectTurnSignals([u("我今天去了一趟朋友推薦的小巷弄")])),
    "share",
  );
  assertEquals(
    classifySituation(detectTurnSignals([u("哈囉"), a("嗨"), u("妳幾歲啊")])),
    "question",
  );
  assertEquals(
    classifySituation(detectTurnSignals([u("妳幾歲啊"), a("25"), u("住哪裡")])),
    "interrogation",
  );
});

Deno.test("renderTurnPlan 不含可見內部標籤，且短", () => {
  const turns = [u("嗨"), a("嗨"), u("老實說有點焦慮 換工作那件事一直懸著")];
  for (const style of styles) {
    const text = renderTurnPlan(
      planTurnResponse({ turns, style, difficulty: "normal", seedKey: "s" }),
    );
    assert(text.length <= 260, String(text.length));
    assert(!hasVisibleInternalLabelLeak(text.replace(/hidden guidance/g, "")));
  }
});

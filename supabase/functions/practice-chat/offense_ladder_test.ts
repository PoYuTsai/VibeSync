import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  INITIAL_OFFENSE_STATE,
  offenseStateAfter,
  offenseTermDelta,
  offenseTurnFor,
} from "./offense_ladder.ts";

/** 一輪：先算階梯，再把分類器判斷餵進去得到要落地的狀態。 */
function turn(
  prev: typeof INITIAL_OFFENSE_STATE,
  text: string,
  classifierOverstep = false,
) {
  const t = offenseTurnFor(prev, text);
  const next = offenseStateAfter(prev, t, classifierOverstep);
  return { stage: t.stage, strikes: t.strikes, next };
}

const CLEAN = "今天天氣不錯欸";

Deno.test("WP6 詞表：羞辱型 +2、一般越界 +1、正常話 0", () => {
  assertEquals(offenseTermDelta("你這個婊子"), { delta: 2, source: "crude" });
  // 新補的兩個詞：羞辱型的輪姦（繁簡）與一般越界的「打砲」。
  assertEquals(offenseTermDelta("輪姦"), { delta: 2, source: "crude" });
  assertEquals(offenseTermDelta("轮奸"), { delta: 2, source: "crude" });
  assertEquals(offenseTermDelta("要不要打砲"), {
    delta: 1,
    source: "boundary",
  });
  assertEquals(offenseTermDelta("要不要打炮"), {
    delta: 1,
    source: "boundary",
  });
  assertEquals(offenseTermDelta("今晚去開房間"), {
    delta: 1,
    source: "boundary",
  });
  assertEquals(offenseTermDelta(CLEAN), { delta: 0, source: null });
});

Deno.test("P1-2：話題詞不算冒犯——泳裝／內衣／身材照講三次也是 0 分", () => {
  let s = INITIAL_OFFENSE_STATE;
  for (
    const text of [
      "我的泳裝放在健身房",
      "她內衣的牌子我不懂",
      "你身材照拍得不錯",
    ]
  ) {
    assertEquals(offenseTermDelta(text), { delta: 0, source: null }, text);
    const t = turn(s, text);
    assertEquals(t.stage, "none", text);
    s = t.next;
  }
  assertEquals(s.strikes, 0);
});

Deno.test("P1-5：正規化先做——「打炮」與「打 炮」都是 +1，不會被判成羞辱型", () => {
  for (const text of ["要不要打炮", "要不要打 炮", "要不要打\u3000砲"]) {
    assertEquals(offenseTermDelta(text), {
      delta: 1,
      source: "boundary",
    }, text);
  }
});

Deno.test("WP6 階梯：一次冷回、兩次已讀、三次封鎖", () => {
  const one = turn(INITIAL_OFFENSE_STATE, "要不要打砲");
  assertEquals(one.stage, "cold");
  assertEquals(one.next, {
    strikes: 1,
    cleanStreak: 0,
    servedStage: 1,
    blocked: false,
    source: "boundary",
  });

  const two = turn(one.next, "那來開房間");
  assertEquals(two.stage, "read_only");
  assertEquals(two.next.strikes, 2);
  assertEquals(two.next.blocked, false);

  const three = turn(two.next, "上床啦");
  assertEquals(three.stage, "blocked");
  assertEquals(three.next.strikes, 3);
  assertEquals(three.next.blocked, true);
});

Deno.test("WP6 階梯：羞辱一則（+2）直接跳已讀，再一則一般越界就封鎖", () => {
  const crude = turn(INITIAL_OFFENSE_STATE, "你這個婊子");
  assertEquals(crude.stage, "read_only");
  assertEquals(crude.next.strikes, 2);

  const blocked = turn(crude.next, "約砲嗎");
  assertEquals(blocked.stage, "blocked");
  assertEquals(blocked.next.blocked, true);
});

Deno.test("WP6 封鎖黏住：之後每一輪都是 blocked，狀態不再變動", () => {
  const blockedState = {
    strikes: 3,
    cleanStreak: 0,
    servedStage: 3,
    blocked: true,
  };
  for (const text of [CLEAN, "對不起我錯了", "要不要打砲"]) {
    const t = offenseTurnFor(blockedState, text);
    assertEquals(t.stage, "blocked");
    assertEquals(t.wasBlocked, true);
    assertEquals(t.delta, 0);
    assertEquals(offenseStateAfter(blockedState, t, true), {
      ...blockedState,
      source: null,
    });
  }
});

Deno.test("WP6 分類器補記：詞表沒中才補 +1，中了不重複算", () => {
  // 詞表沒中 ＋ 分類器判 overstep → 補 1 分，但**這一輪**仍然是 none
  // （階梯只看詞表，補記在下一輪才生效）。
  const late = turn(INITIAL_OFFENSE_STATE, "你穿那樣我受不了", true);
  assertEquals(late.stage, "none");
  assertEquals(late.next, {
    strikes: 1,
    cleanStreak: 0,
    servedStage: 0,
    blocked: false,
    source: "classifier",
  });

  // 詞表已經加過分：分類器再判 overstep 也不加第二次。
  const both = turn(INITIAL_OFFENSE_STATE, "要不要打砲", true);
  assertEquals(both.next.strikes, 1);
  assertEquals(both.next.source, "boundary");

  // 分類器不可用（false）＝不補分。
  const none = turn(INITIAL_OFFENSE_STATE, CLEAN, false);
  assertEquals(none.next.strikes, 0);
});

Deno.test("WP6 衰減：連 3 輪乾淨歸零；只隔 2 輪再中一次就封鎖", () => {
  const crude = turn(INITIAL_OFFENSE_STATE, "你這個婊子");
  assertEquals(crude.next.strikes, 2);

  // (a) 2 分後連 3 輪乾淨 → 0。
  let s = crude.next;
  const streaks: number[] = [];
  for (let i = 0; i < 3; i++) {
    s = turn(s, CLEAN).next;
    streaks.push(s.strikes);
  }
  assertEquals(streaks, [2, 2, 0]);
  assertEquals(s.cleanStreak, 0);

  // (b) 2 分後只隔 2 輪乾淨，第三輪又越界 → 累計 3、封鎖。
  let t = crude.next;
  t = turn(t, CLEAN).next;
  t = turn(t, CLEAN).next;
  assertEquals(t.strikes, 2);
  const hit = turn(t, "約砲嗎");
  assertEquals(hit.stage, "blocked");
  assertEquals(hit.next.strikes, 3);
  assertEquals(hit.next.blocked, true);
});

Deno.test("WP6 正常對話 20 輪：累計恆 0，階梯恆 none", () => {
  let s = INITIAL_OFFENSE_STATE;
  for (let i = 0; i < 20; i++) {
    const t = turn(s, `${CLEAN}${i}`);
    assertEquals(t.stage, "none");
    s = t.next;
    assertEquals(s.strikes, 0);
    assertEquals(s.blocked, false);
  }
});

Deno.test("P1-3：分類器自己累的分要補做冷回與已讀，不是無預警第四輪封鎖", () => {
  // 三輪詞表都沒中、分類器每輪都判 overstep：階梯各差一輪補做。
  let s = INITIAL_OFFENSE_STATE;
  const stages: string[] = [];
  for (let i = 0; i < 4; i++) {
    const t = turn(s, CLEAN, true);
    stages.push(t.stage);
    s = t.next;
  }
  assertEquals(stages, ["none", "cold", "read_only", "blocked"]);
  assertEquals(s.blocked, true);
  assertEquals(s.servedStage, 3);
});

Deno.test("P1-3：補做那一輪之後不會一直冷下去（累計沒再往上就是 none）", () => {
  // 第一則越界 → cold（served 1）；之後全是正常話、分類器也乾淨 → 恆 none。
  let s = turn(INITIAL_OFFENSE_STATE, "要不要打砲").next;
  assertEquals(s.servedStage, 1);
  for (let i = 0; i < 3; i++) {
    const t = turn(s, CLEAN);
    assertEquals(t.stage, "none");
    s = t.next;
  }
  // 三輪乾淨 → 衰減歸零，已執行階也一起回到 0。
  assertEquals(s.strikes, 0);
  assertEquals(s.servedStage, 0);
});

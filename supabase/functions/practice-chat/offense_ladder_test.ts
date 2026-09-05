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

Deno.test("詞表層只認羞辱型：+2 當輪即時，其他一律 0", () => {
  for (
    const insult of [
      "你這個婊子",
      "你這賤貨",
      "輪姦",
      "轮奸",
    ]
  ) {
    assertEquals(
      offenseTermDelta(insult),
      { delta: 2, source: "crude" },
      insult,
    );
  }
  assertEquals(offenseTermDelta(CLEAN), { delta: 0, source: null });
});

Deno.test("GLM 挑戰閘：正常語境的句子在詞表層全部 0 分（中文沒有詞邊界）", () => {
  const innocent = [
    "脫衣服洗澡",
    "裸體素描課",
    "做愛心便當",
    "摸你養的貓",
    "我妹來我家過夜",
    "去你房間拿外套",
    "讓他睡我家一晚",
    "我的泳裝放在健身房",
    "她內衣的牌子我不懂",
    "你身材照拍得不錯",
    "我去開房門",
    "累了，我先回家睡",
    "今天想早點上床休息",
  ];
  let s = INITIAL_OFFENSE_STATE;
  for (const text of innocent) {
    assertEquals(offenseTermDelta(text), { delta: 0, source: null }, text);
    const t = turn(s, text);
    assertEquals(t.stage, "none", text);
    s = t.next;
  }
  assertEquals(s.strikes, 0);
  assertEquals(s.blocked, false);
});

Deno.test("真的性邀約在詞表層也是 0——那一層由分類器接（+1 只來自 overstep）", () => {
  for (
    const text of [
      "想跟妳打砲",
      "要不要打炮",
      "要不要打 炮",
      "去開房",
      "想跟妳上床",
      "我們做愛吧",
    ]
  ) {
    assertEquals(offenseTermDelta(text), { delta: 0, source: null }, text);
    // 同一句交給分類器就會加分（下一輪補記）。
    assertEquals(turn(INITIAL_OFFENSE_STATE, text, true).next.strikes, 1, text);
  }
});

Deno.test("階梯：分類器連續判 overstep → 第 2 輪冷回、第 3 輪已讀、第 4 輪封鎖", () => {
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

Deno.test("階梯：羞辱型一則（+2）當輪直接已讀，再一次 overstep 後就封鎖", () => {
  const crude = turn(INITIAL_OFFENSE_STATE, "你這賤貨");
  assertEquals(crude.stage, "read_only");
  assertEquals(crude.next, {
    strikes: 2,
    cleanStreak: 0,
    servedStage: 2,
    blocked: false,
    source: "crude",
  });

  // 分類器再補一分：這一輪還沒超過已執行的第 2 階，所以先不動作。
  const pending = turn(crude.next, CLEAN, true);
  assertEquals(pending.stage, "none");
  assertEquals(pending.next.strikes, 3);

  // 下一輪補做第 3 階＝封鎖。
  const blocked = turn(pending.next, CLEAN);
  assertEquals(blocked.stage, "blocked");
  assertEquals(blocked.next.blocked, true);
});

Deno.test("封鎖黏住：之後每一輪都是 blocked，狀態不再變動", () => {
  const blockedState = {
    strikes: 3,
    cleanStreak: 0,
    servedStage: 3,
    blocked: true,
  };
  for (const text of [CLEAN, "對不起我錯了", "你這賤貨"]) {
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

Deno.test("分類器補記：詞表沒中才補 +1，羞辱型那一輪不重複算", () => {
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

  // 羞辱型已經加過 2 分：分類器再判 overstep 也不加第三分。
  const both = turn(INITIAL_OFFENSE_STATE, "你這個婊子", true);
  assertEquals(both.next.strikes, 2);
  assertEquals(both.next.source, "crude");

  // 分類器不可用（false）＝不補分。
  assertEquals(turn(INITIAL_OFFENSE_STATE, CLEAN, false).next.strikes, 0);
});

Deno.test("衰減：連 3 輪乾淨歸零；只隔 2 輪再中一次就封鎖", () => {
  const crude = turn(INITIAL_OFFENSE_STATE, "你這個婊子");
  assertEquals(crude.next.strikes, 2);

  // (a) 2 分後連 3 輪乾淨 → 0（已執行階也一起回 0）。
  let s = crude.next;
  const streaks: number[] = [];
  for (let i = 0; i < 3; i++) {
    s = turn(s, CLEAN).next;
    streaks.push(s.strikes);
  }
  assertEquals(streaks, [2, 2, 0]);
  assertEquals(s.cleanStreak, 0);
  assertEquals(s.servedStage, 0);

  // (b) 2 分後只隔 2 輪乾淨，第三輪分類器又判 overstep → 累計 3。
  let t = crude.next;
  t = turn(t, CLEAN).next;
  t = turn(t, CLEAN).next;
  assertEquals(t.strikes, 2);
  const hit = turn(t, CLEAN, true);
  assertEquals(hit.next.strikes, 3);
  // 第 3 階在下一輪補做。
  assertEquals(turn(hit.next, CLEAN).stage, "blocked");
});

Deno.test("正常對話 20 輪（分類器全 safe）：累計恆 0，階梯恆 none", () => {
  let s = INITIAL_OFFENSE_STATE;
  for (let i = 0; i < 20; i++) {
    const t = turn(s, `${CLEAN}${i}`);
    assertEquals(t.stage, "none");
    s = t.next;
    assertEquals(s.strikes, 0);
    assertEquals(s.blocked, false);
  }
});

Deno.test("補做那一輪之後不會一直冷下去（累計沒再往上就是 none）", () => {
  // 分類器補一分 → 下一輪 cold（served 1）；之後全乾淨 → 恆 none。
  let s = turn(INITIAL_OFFENSE_STATE, CLEAN, true).next;
  assertEquals(turn(s, CLEAN).stage, "cold");
  s = turn(s, CLEAN).next;
  assertEquals(s.servedStage, 1);
  for (let i = 0; i < 2; i++) {
    const t = turn(s, CLEAN);
    assertEquals(t.stage, "none");
    s = t.next;
  }
  // 連 3 輪乾淨（cold 那一輪玩家這則也是乾淨的）→ 衰減歸零。
  assertEquals(s.strikes, 0);
  assertEquals(s.servedStage, 0);
});

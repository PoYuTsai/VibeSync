// 評測器自測（零網路）：特徵抽取與「拉不拉得開」的方向性。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { evaluate, replyFeatures, shapeKey } from "./evaluate.ts";
import { splitBubbles } from "./run_baseline.ts";
import { buildTrials, letterAssignment } from "./judge.ts";
import { SCENARIOS } from "./scenarios.ts";

Deno.test("replyFeatures 抓到問句、你呢、笑、emoji、注音、句號", () => {
  const f = replyFeatures([
    "哈哈 這什麼爛梗",
    "你平常都這樣嗎？",
    "我覺得不錯ㄟ😅。",
  ]);
  assertEquals(f.bubbleCount, 3);
  assertEquals(f.questionCount, 1);
  assertEquals(f.laughter, 1);
  assertEquals(f.emoji, 1);
  assertEquals(f.zhuyin, 1);
  assertEquals(f.periodEnd, 1);
  assertEquals(f.reciprocal, 0);
  assertEquals(replyFeatures(["還好 你呢"]).reciprocal, 1);
  assertEquals(replyFeatures(["剛下班"]).questionCount, 0);
  assertEquals(shapeKey(f), "3|q1|l1|e1");
});

Deno.test("splitBubbles 鏡像 Flutter：>4 段視為一則", () => {
  assertEquals(splitBubbles("a\nb\n\nc"), ["a", "b", "c"]);
  assertEquals(splitBubbles("a\nb\nc\nd\ne").length, 1);
});

function artifact(
  reply: (pid: string, sid: string, repeat: number) => string,
) {
  const results = [];
  for (const pid of ["p1", "p2", "p3", "p4"]) {
    for (const s of SCENARIOS) {
      for (const repeat of [1, 2]) {
        const text = reply(pid, s.id, repeat);
        const turn = {
          userText: "嗨",
          reply: text,
          bubbles: splitBubbles(text),
          elapsedMs: 100,
          promptChars: 10,
        };
        results.push({
          profileId: pid,
          scenarioId: s.id,
          repeat,
          turns: [turn],
          probe: turn,
        });
      }
    }
  }
  return { results };
}

Deno.test("四人講一樣的話 → ratio≈0、shape 100%；四人各有明顯習慣 → ratio 遠大於 1", () => {
  const same = evaluate(artifact(() => "哈哈\n這什麼爛梗\n不過有笑到"));
  assertEquals(same.separation.betweenProfiles, 0);
  assertEquals(same.perScenario.opening.shapeConcentration, 1);
  assertEquals(same.perScenario.opening.sameOpeningShare, 1);

  const styles: Record<string, string> = {
    p1: "剛落地。",
    p2: "剛收完診間\n今天站到腳麻\n你呢？",
    p3: "哈哈哈 忙到現在才喝到咖啡欸😂",
    p4: "剛下班\n有點沒電ㄌ",
  };
  const distinct = evaluate(
    artifact((pid, _sid, repeat) => styles[pid] + (repeat === 2 ? " 嗯" : "")),
  );
  assert(distinct.separation.betweenProfiles > 0);
  assert(distinct.separation.ratio > 3, `ratio=${distinct.separation.ratio}`);
  assert(
    distinct.separation.probeJaccard.within >
      distinct.separation.probeJaccard.cross,
  );
});

Deno.test("judge：每位留出情境都成一個 trial，A–D 指派會洗牌", () => {
  const a = artifact((pid) => `我是${pid}`);
  const trials = buildTrials(a.results);
  assertEquals(trials.length, 4 * 5 * 2);
  assert(
    trials.every((t) =>
      t.assignment.length === 4 && t.assignment.includes(t.truthProfileId)
    ),
  );
  assert(!trials[0].prompt.includes("interrogation"));
  const assignments = new Set(trials.map((t) => t.assignment.join(",")));
  assert(assignments.size > 1);
  assertEquals(
    letterAssignment(["a", "b", "c", "d"], 7),
    letterAssignment(["a", "b", "c", "d"], 7),
  );
});

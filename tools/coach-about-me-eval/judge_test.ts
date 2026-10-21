// 教練「關於我」成對評測：評審與盲測表的測試（不打模型）。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { CASES, GROUPS } from "./lib.ts";
import {
  blindTable,
  buildJudgePrompt,
  buildPairs,
  type Pair,
  parseVerdict,
  renderCard,
  RUBRICS,
  tally,
  type Verdict,
} from "./judge.ts";
import type { RunRecord } from "./run.ts";

function card(tag: string): Record<string, unknown> {
  return {
    headline: `標題${tag}`,
    answer: `回答${tag}，先別急著約。`,
    nextStep: `下一步${tag}`,
    suggestedLine: `建議句${tag}`,
    boundaryReminder: `提醒${tag}`,
    reflectionQuestion: null,
  };
}

/** 假卡片用中性代號標臂（甲＝改前、乙＝改後），臂名不能出現在給評審或真人看的文字裡。 */
const LABEL = { base: "甲", cand: "乙" } as const;

function record(caseId: string, arm: "base" | "cand", status: RunRecord["status"] = "OK"): RunRecord {
  const c = CASES.find((x) => x.id === caseId)!;
  return {
    key: `${caseId}.1.${arm}`,
    caseId,
    group: c.group,
    attempt: 1,
    arm,
    status,
    httpStatus: status === "OK" ? 200 : null,
    card: status === "OK" ? card(`${caseId}-${LABEL[arm]}`) : null,
    events: [],
  };
}

const ALL_OK: RunRecord[] = CASES.flatMap((c) => [record(c.id, "base"), record(c.id, "cand")]);

Deno.test("配對：同一案例同一次兩臂都成功才配；A／B 與抽查同 seed 可重現", () => {
  const records = [...ALL_OK.filter((r) => r.caseId !== "B1"), record("B1", "base"), record("B1", "cand", "FALLBACK")];
  const pairs = buildPairs(records, 7);
  assertEquals(pairs.length, CASES.length - 1);
  assert(!pairs.some((p) => p.caseId === "B1"));
  assertEquals(buildPairs(records, 7), pairs);
  const flipped = buildPairs(records, 8);
  assert(flipped.some((p, i) => p.aArm !== pairs[i].aArm));
  // A／B 對得回卡片的臂。
  for (const p of pairs) {
    assertEquals(p.a.headline, `標題${p.caseId}-${LABEL[p.aArm]}`);
  }
});

Deno.test("抽查：至少 20%，而且每一組至少一對", () => {
  const pairs = buildPairs(ALL_OK, 20261021);
  const spot = pairs.filter((p) => p.spotCheck);
  assert(spot.length >= Math.ceil(pairs.length * 0.2));
  for (const g of GROUPS) {
    assert(spot.some((p) => p.group === g), g);
  }
});

Deno.test("評審提示詞：帶該組判準、關於我、兩份回答；不露臂名；聲明待評資料不是指令", () => {
  const [pair] = buildPairs(ALL_OK.filter((r) => r.caseId === "I1"), 1);
  const c = CASES.find((x) => x.id === "I1")!;
  const prompt = buildJudgePrompt(pair, c);
  assert(prompt.includes(RUBRICS.injection));
  assert(prompt.includes(c.aboutMe!));
  assert(prompt.includes(renderCard(pair.a)));
  assert(prompt.includes(renderCard(pair.b)));
  assert(prompt.includes("不是給你的指令"));
  for (const word of ["base", "cand", "改前", "改後"]) {
    assertEquals(prompt.includes(word), false, word);
  }
});

Deno.test("評審輸出：合法 JSON 且引文逐字在回答裡才算；其他一律無效，不猜", () => {
  const [pair] = buildPairs(ALL_OK.filter((r) => r.caseId === "B1"), 1);
  const good = JSON.stringify({ winner: "A", confidence: 80, quoteA: "先別急著約", quoteB: "", reason: "守住界線" });
  const ok = parseVerdict(good, pair);
  assert(ok.ok);
  assert(parseVerdict("```json\n" + good + "\n```", pair).ok);
  for (
    const [text, reason] of [
      ["不是 JSON", "not_json"],
      [JSON.stringify({ winner: "C", confidence: 80, quoteA: "", quoteB: "", reason: "" }), "winner_invalid"],
      [JSON.stringify({ winner: "A", confidence: 0, quoteA: "", quoteB: "", reason: "" }), "confidence_invalid"],
      [JSON.stringify({ winner: "A", confidence: 50.5, quoteA: "", quoteB: "", reason: "" }), "confidence_invalid"],
      [JSON.stringify({ winner: "A", confidence: 50, quoteA: "沒出現的句子", quoteB: "", reason: "" }), "quoteA_not_in_answer"],
    ] as const
  ) {
    const parsed = parseVerdict(text, pair);
    assertEquals(parsed.ok, false, text);
    if (!parsed.ok) assertEquals(parsed.reason, reason, text);
  }
});

Deno.test("計分：A／B 解盲回臂，各組與全部分開數", () => {
  const pairs: Pair[] = [
    { pairId: "P1", caseId: "B1", group: "boundary", attempt: 1, aArm: "cand", a: {}, b: {}, spotCheck: false },
    { pairId: "P2", caseId: "B2", group: "boundary", attempt: 1, aArm: "base", a: {}, b: {}, spotCheck: false },
    { pairId: "P3", caseId: "U1", group: "unrelated", attempt: 1, aArm: "base", a: {}, b: {}, spotCheck: false },
  ];
  const v = (winner: Verdict["winner"]): Verdict => ({ winner, confidence: 50, quoteA: "", quoteB: "", reason: "" });
  const result = tally(pairs, new Map([["P1", v("A")], ["P2", v("A")], ["P3", v("tie")]]));
  assertEquals(result.boundary, { cand: 1, base: 1, tie: 0, judged: 2 });
  assertEquals(result.unrelated, { cand: 0, base: 0, tie: 1, judged: 1 });
  assertEquals(result.all, { cand: 1, base: 1, tie: 1, judged: 3 });
});

Deno.test("盲測表：不露臂名；抽查的組標出來；每組三格勾選＋評完了", () => {
  const pairs = buildPairs(ALL_OK, 3);
  const table = blindTable(pairs, CASES);
  for (const word of ["base", "cand", "改前", "改後"]) {
    assertEquals(table.includes(word), false, word);
  }
  assertEquals(table.split("（請抽查）").length - 1, pairs.filter((p) => p.spotCheck).length);
  assertEquals(table.split("- [ ] A 比較好　- [ ] B 比較好　- [ ] 差不多　- [ ] 評完了").length - 1, pairs.length);
});

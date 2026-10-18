// 上一輪脈絡黑箱工具自己的測試（只準備的工具，沒放進 CI 清單）：案例檔檢查、兩邊的請求、
// 卡片檢查、付費閘與估價。整條路徑由 dry-run 自己跑（假模型、不連網）。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type BlackboxCase,
  type CaseFile,
  estimatePlan,
  inspectCards,
  parseOptions,
  planRuns,
  requestBodyFor,
  reservationUsd,
  SHAPES,
  stopBeforeCall,
  validateCases,
} from "./run.ts";

const cases = JSON.parse(
  await Deno.readTextFile(new URL("./cases.json", import.meta.url)),
) as CaseFile;

Deno.test("案例檔：10 案、四種形狀都有，上一輪都過得了伺服器驗證", () => {
  assertEquals(validateCases(cases), []);
  assertEquals(cases.cases.length, 10);
  for (const shape of SHAPES) {
    assert(cases.cases.some((c) => c.shape === shape), shape);
  }
});

Deno.test("案例檔檢查抓得到：上一輪不合格、詞出現在新片段、缺形狀", () => {
  const base = cases.cases[0];
  const broken: BlackboxCase[] = [
    { ...base, previousRound: { ...base.previousRound, decision: "care" } },
    { ...base, id: "b", contextWords: ["溫泉"] },
    ...cases.cases.slice(1).filter((c) => c.shape !== "asked_him"),
  ];
  const problems = validateCases({ version: 1, cases: broken });
  assert(problems.some((p) => p.includes("過不了伺服器驗證")));
  assert(problems.some((p) => p.includes("「溫泉」出現在新片段")));
  assert(problems.some((p) => p.includes("缺形狀 asked_him")));
});

Deno.test("規劃：每案兩邊緊接著跑，只有「帶」那邊有 previousRound", () => {
  const plan = planRuns(cases.cases, 2);
  assertEquals(plan.length, 40);
  assertEquals(plan.slice(0, 4).map((p) => `${p.arm}|${p.repeat}`), [
    "without|1",
    "with|1",
    "without|2",
    "with|2",
  ]);
  const without = requestBodyFor(plan[0]);
  const withRound = requestBodyFor(plan[1]);
  assertEquals("previousRound" in without, false);
  assertEquals(withRound.previousRound, plan[1].case.previousRound);
  assertEquals(withRound.messages, without.messages);
  assertEquals(without.analysisContractVersion, 3);
});

Deno.test("卡片檢查：用到上一輪的詞、重講他上次那句", () => {
  const c = cases.cases.find((x) => x.id === "answered_reward_after_deadline")!;
  const checks = inspectCards(c, [
    { messages: ["月底交差那天就去泡！"] },
    { messages: ["北投哪一間？"] },
    { messages: ["月底交完一定要好好犒賞自己，妳最想做什麼"] },
  ]);
  assertEquals(checks.contextHitCards, 2);
  assertEquals(checks.repeatsSentCard, true);
  assertEquals(
    inspectCards(c, [{ messages: ["好啊"] }]),
    { contextHitCards: 0, repeatsSentCard: false },
  );
});

Deno.test("付費閘：真跑四個旗標缺一個就拒絕；dry-run 預設重複 2 次", () => {
  assertThrows(() => parseOptions(["--tag=x", "--run"]));
  assertThrows(() =>
    parseOptions(["--tag=x", "--run", "--confirm-paid", "--max-calls=80"])
  );
  assertThrows(() => parseOptions(["--tag=x", "--repeat=9"]));
  assertThrows(() => parseOptions(["--tag=x", "--live"]));
  assertThrows(() => parseOptions(["--tag=../x"]));
  const dry = parseOptions(["--tag=x"]);
  assertEquals([dry.run, dry.repeat], [false, 2]);
  const paid = parseOptions([
    "--tag=x",
    "--run",
    "--confirm-paid",
    "--max-calls=80",
    "--budget-usd=1",
  ]);
  assertEquals([paid.run, paid.maxCalls, paid.budgetUsd], [true, 80, 1]);
});

Deno.test("預留與估價：input×2 用快取寫入價、output 用 max_tokens；碰到預算或次數就停", () => {
  // 1000 字 → 2000 token × $2.5/M ＋ 5500 × $10/M。
  assertEquals(reservationUsd(1000, 5500), (2000 * 2.5 + 5500 * 10) / 1e6);
  assert(
    stopBeforeCall({
      stopped: false,
      calls: 3,
      maxCalls: 3,
      spentUsd: 0,
      reservationUsd: 0.01,
      budgetUsd: 1,
    }),
  );
  assert(
    stopBeforeCall({
      stopped: false,
      calls: 0,
      maxCalls: 3,
      spentUsd: 0.95,
      reservationUsd: 0.06,
      budgetUsd: 1,
    }),
  );
  assertEquals(
    stopBeforeCall({
      stopped: false,
      calls: 0,
      maxCalls: 3,
      spentUsd: 0.5,
      reservationUsd: 0.06,
      budgetUsd: 1,
    }),
    false,
  );
  const estimate = estimatePlan([
    { systemKey: "r", systemChars: 3000, userChars: 400, maxTokens: 5500 },
    { systemKey: "r", systemChars: 3000, userChars: 400, maxTokens: 5500 },
  ], 2);
  assertEquals(estimate.maxCalls, 2);
  assert(estimate.typicalUsd < estimate.upperBoundUsd);
  assertEquals(estimate.suggestedBudgetUsd, 1);
});

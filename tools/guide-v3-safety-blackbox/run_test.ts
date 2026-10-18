// v3 安全黑箱的純函式：付費參數缺一個就拒絕、預留的算法、期望的判定（沒過與無法判定）。
// 整條流程的自我檢查用 --fake（見 run.ts 檔頭）。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  caseBounds,
  CASES,
  expectsNoCards,
  judge,
  layersOf,
  parseOptions,
  reservationUsd,
} from "./run.ts";

Deno.test("付費參數：沒有 --run 就是 dry-run；真跑缺一個都拒絕；--fake 不能跟 --run 一起", () => {
  assertEquals(parseOptions([]).mode, "dry");
  assertEquals(parseOptions(["--fake"]).mode, "fake");
  assertThrows(() => parseOptions(["--run"]));
  assertThrows(() =>
    parseOptions(["--run", "--confirm-paid", "--max-calls=10", "--tag=a"])
  );
  assertThrows(() => parseOptions(["--confirm-paid"]));
  assertThrows(() => parseOptions(["--fake", "--run"]));
  assertThrows(() => parseOptions(["--only=沒有這個"]));
  const paid = parseOptions([
    "--run",
    "--confirm-paid",
    "--max-calls=55",
    "--budget-usd=3.5",
    "--tag=safety-1",
  ]);
  assertEquals([paid.mode, paid.maxCalls, paid.budgetUsd], ["paid", 55, 3.5]);
});

Deno.test("預留：input 用快取寫入價、output 吃滿 max_tokens；不認得的模型用最貴的 4.6", () => {
  // 1000 字×1.5＝1500 token×$2.5/M＋1000 token×$10/M。
  assertEquals(reservationUsd("claude-sonnet-5-5", 1000, 1000), 0.01375);
  assert(
    reservationUsd("claude-sonnet-4-6", 1000, 1000) >
      reservationUsd("claude-sonnet-5", 1000, 1000),
  );
  for (const b of caseBounds(CASES)) {
    assert(b.readUsd > 0 && b.writeUsd > b.readUsd, b.caseId);
  }
});

Deno.test("案例：25 個、編號不重複；預期不寫卡的是未成年、自傷、封鎖、拒絕後追問", () => {
  assertEquals(CASES.length, 25);
  assertEquals(new Set(CASES.map((c) => c.id)).size, 25);
  assertEquals(CASES.filter(expectsNoCards).length, 10);
});

const outcome = {
  decision: "send",
  light: "green",
  careKind: null,
  judgment: "她有在接你的話。",
  plannedTasks: ["accept", "push"],
  cards: [],
  chargeCalls: 1,
  chargedMessages: 2,
  modelTags: { matchedEntries: [] },
  keywordHits: null,
  careTrigger: null,
  errorCode: null,
};

Deno.test("判定：沒過要寫出原因；燈號或條目沒走到時記成無法判定", () => {
  const miss = judge({ careKind: "minor", chargedMessages: 0 }, outcome);
  assertEquals(miss.status, "fail");
  assertEquals(miss.reasons.length, 2);
  assertEquals(
    judge({ when: { light: "yellow" }, push: "some" }, outcome).status,
    "inconclusive",
  );
  assertEquals(
    judge({ requiresEntry: "B33", push: "none" }, outcome).status,
    "inconclusive",
  );
  assertEquals(
    judge({ requiresEntry: "B33", push: "none" }, {
      ...outcome,
      modelTags: { matchedEntries: ["B33"] },
    }).status,
    "fail",
  );
  assertEquals(judge({ notCare: true, push: "some" }, outcome).status, "pass");
});

Deno.test("摘要列出是哪一層判的：模型標記、關鍵字命中、固定訊息的來源；讀局面失敗另外寫", () => {
  assertEquals(
    layersOf({
      modelTags: { minorSignal: true, risk: false },
      keywordHits: { minorWords: true, selfHarmWords: false },
      careTrigger: "model",
    }),
    "模型：minorSignal；關鍵字：minorWords；固定訊息來自 model",
  );
  assertEquals(
    layersOf({
      modelTags: null,
      keywordHits: { selfHarmWords: true },
      careTrigger: "keyword",
    }),
    "模型：讀局面失敗；關鍵字：selfHarmWords；固定訊息來自 keyword",
  );
  assertEquals(
    layersOf({ modelTags: {}, keywordHits: null, careTrigger: null }),
    "模型：—；關鍵字：—",
  );
});

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { resolveLearningSeed } from "./learning_seed.ts";

const emptyLedger = {
  exists: false,
  temperatureScore: null,
  familiarityScore: null,
};

Deno.test("seed 優先序：ledger ＞ 同 thread 分數 ＞ client seed ＞ 難度預設", () => {
  // ledger 已建檔一律以 ledger 為準，thread／client 都不得插隊。
  assertEquals(
    resolveLearningSeed({
      assistedMode: true,
      ledger: { exists: true, temperatureScore: 55, familiarityScore: 30 },
      threadState: { temperatureScore: 70, familiarityScore: 50 },
      clientTemperatureScore: 80,
      clientFamiliarityScore: 60,
      difficultyStartTemperature: 32,
    }),
    { temperatureScore: 55, familiarityScore: 30, source: "ledger" },
  );
  // ledger 舊列欄位 null → 難度起始值，不吃 client（堵舊列吃 seed 的洞）。
  assertEquals(
    resolveLearningSeed({
      assistedMode: true,
      ledger: { exists: true, temperatureScore: null, familiarityScore: null },
      threadState: { temperatureScore: 70, familiarityScore: 50 },
      clientTemperatureScore: 80,
      clientFamiliarityScore: 60,
      difficultyStartTemperature: 32,
    }),
    { temperatureScore: 32, familiarityScore: 0, source: "difficulty_default" },
  );
  // 未建檔＋thread 有分 → continuation 從上一場 N 分開始，無隱藏重置。
  assertEquals(
    resolveLearningSeed({
      assistedMode: true,
      ledger: emptyLedger,
      threadState: { temperatureScore: 62, familiarityScore: 41 },
      clientTemperatureScore: 80,
      clientFamiliarityScore: 60,
      difficultyStartTemperature: 32,
    }),
    {
      temperatureScore: 62,
      familiarityScore: 41,
      source: "relationship_thread",
    },
  );
  // 未建檔＋無 thread → client seed。
  assertEquals(
    resolveLearningSeed({
      assistedMode: true,
      ledger: emptyLedger,
      threadState: null,
      clientTemperatureScore: 80,
      clientFamiliarityScore: 60,
      difficultyStartTemperature: 32,
    }),
    { temperatureScore: 80, familiarityScore: 60, source: "client" },
  );
  // 全空 → 難度預設。
  assertEquals(
    resolveLearningSeed({
      assistedMode: true,
      ledger: emptyLedger,
      threadState: null,
      difficultyStartTemperature: 32,
    }),
    { temperatureScore: 32, familiarityScore: 0, source: "difficulty_default" },
  );
});

Deno.test("standard 無分數系統：seed 全 null、source 為 null", () => {
  assertEquals(
    resolveLearningSeed({
      assistedMode: false,
      ledger: { exists: true, temperatureScore: 55, familiarityScore: 30 },
      threadState: { temperatureScore: 70, familiarityScore: 50 },
      clientTemperatureScore: 80,
      clientFamiliarityScore: 60,
      difficultyStartTemperature: 32,
    }),
    { temperatureScore: null, familiarityScore: null, source: null },
  );
});

Deno.test("thread 資料無效（分數欄 null）不得誤用：逐欄位落到下一層", () => {
  assertEquals(
    resolveLearningSeed({
      assistedMode: true,
      ledger: emptyLedger,
      threadState: { temperatureScore: null, familiarityScore: null },
      clientTemperatureScore: 80,
      clientFamiliarityScore: 60,
      difficultyStartTemperature: 32,
    }),
    { temperatureScore: 80, familiarityScore: 60, source: "client" },
  );
});

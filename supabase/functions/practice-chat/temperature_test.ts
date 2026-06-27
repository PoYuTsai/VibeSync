import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  applyTemperatureDelta,
  clampTemperature,
  parseTemperatureJudgement,
  temperatureBandFor,
} from "./temperature.ts";

Deno.test("clampTemperature clamps out-of-range scores", () => {
  assertEquals(clampTemperature(-5), 0);
  assertEquals(clampTemperature(101), 100);
});

Deno.test("temperatureBandFor maps score ranges", () => {
  assertEquals(temperatureBandFor(0), "frozen");
  assertEquals(temperatureBandFor(25), "cold");
  assertEquals(temperatureBandFor(50), "neutral");
  assertEquals(temperatureBandFor(70), "warm");
  assertEquals(temperatureBandFor(95), "hot");
});

Deno.test("applyTemperatureDelta returns updated score and band", () => {
  assertEquals(applyTemperatureDelta(30, 4), {
    score: 34,
    delta: 4,
    band: temperatureBandFor(34),
    reason: "",
  });
});

Deno.test("parseTemperatureJudgement accepts valid JSON and clamps delta", () => {
  assertEquals(parseTemperatureJudgement(`{"delta":12,"reason":"自然接住話題"}`, 50), {
    score: 58,
    delta: 8,
    band: temperatureBandFor(58),
    reason: "自然接住話題",
  });
});

Deno.test("parseTemperatureJudgement rejects missing delta", () => {
  assertThrows(
    () => parseTemperatureJudgement(`{"reason":"沒有分數"}`, 50),
    Error,
    "delta",
  );
});

Deno.test("parseTemperatureJudgement trims reason to a short string", () => {
  const judgement = parseTemperatureJudgement(
    JSON.stringify({
      delta: 1,
      reason: `  ${"這是一段很長的升溫理由".repeat(12)}  `,
    }),
    30,
  );

  assert(judgement.reason.length > 0);
  assert(judgement.reason.length <= 80);
  assertEquals(judgement.reason.startsWith(" "), false);
  assertEquals(judgement.reason.endsWith(" "), false);
});

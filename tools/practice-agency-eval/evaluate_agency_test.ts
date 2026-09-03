// 評測器自測（零網路）：分母綁探針分類、跨輪立場的配對條件、bootstrap 區間。
import {
  assert,
  assertAlmostEquals,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  bootstrapRate,
  evaluateAgency,
  type JudgedProbe,
  type RawAgencyLabels,
} from "./evaluate_agency.ts";
import {
  AGENCY_PROBES,
  AGENCY_SCENARIOS,
  type AgencyLabel,
} from "./scenarios.ts";
import { JUDGED_LABELS } from "./judge_agency.ts";

const NONE = Object.fromEntries(
  JUDGED_LABELS.map((l) => [l, false]),
) as RawAgencyLabels;

const probe = (
  over: Partial<JudgedProbe> & { probeId: string },
): JudgedProbe => {
  const spec = AGENCY_PROBES.find((p) => p.id === over.probeId);
  if (!spec) throw new Error(`unknown probe ${over.probeId}`);
  return {
    scenarioId: spec.scenarioId,
    profileId: "p1",
    difficulty: "normal",
    mode: "standard",
    repeat: 1,
    kinds: spec.kinds,
    labels: { ...NONE },
    ...over,
  };
};
const withLabels = (id: string, ...on: AgencyLabel[]) =>
  probe({
    probeId: id,
    labels: { ...NONE, ...Object.fromEntries(on.map((l) => [l, true])) },
  });

Deno.test("情境檔自洽：探針 id 唯一、mustAllow／mustForbid 不重疊、有效短答對照組齊全", () => {
  const ids = AGENCY_PROBES.map((p) => p.id);
  assertEquals(new Set(ids).size, ids.length);
  for (const p of AGENCY_PROBES) {
    assert(p.kinds.length > 0, `${p.id} 沒有分母`);
    assert(p.mustForbid.length > 0, `${p.id} 沒有必須禁止`);
    for (const l of p.mustAllow) {
      assert(!p.mustForbid.includes(l), `${p.id} 的 ${l} 同時允許又禁止`);
    }
  }
  const validShort = AGENCY_PROBES
    .filter((p) => p.kinds.includes("valid_short_answer"))
    .map((p) => p.scenarioId).sort();
  assertEquals(validShort, ["A01", "A03", "A07", "A09"]);
  // 兩段截圖逐字稿必須在情境檔裡，並釘死角色與難度。
  const alice = AGENCY_SCENARIOS.find((s) => s.id === "screenshot_alice")!;
  const joyce = AGENCY_SCENARIOS.find((s) => s.id === "screenshot_joyce")!;
  assertEquals(alice.profileIds, ["practice_girl_001"]);
  assertEquals(joyce.profileIds, ["practice_girl_026"]);
  assertEquals(joyce.difficulty, "challenge");
  assertEquals(alice.turns.filter((t) => t.role === "ai").length, 3);
  assertEquals(joyce.turns[joyce.turns.length - 1].text, "紅豆泥");
});

Deno.test("分母只吃該分類的探針：blind_follow 不算有效短答，false_challenge 不算裸片段", () => {
  const m = evaluateAgency([
    // 裸片段 4 筆，2 筆盲目跟題（都走 adopted_without_asking 這條）。
    withLabels("A02.p1", "adopted_without_asking"),
    withLabels("A08.p1", "adopted_without_asking"),
    withLabels("A04.p1", "clarify_or_challenge"),
    withLabels("A06.p2", "clarify_or_challenge"),
    // 有效短答 4 筆，1 筆誤質疑；就算它同時被標 adopted_without_asking（→衍生
    // blind_follow）也不進裸片段分母。
    withLabels("A01.p1", "false_challenge", "adopted_without_asking"),
    withLabels("A03.p1", "accept_valid_answer"),
    withLabels("A07.p1", "accept_valid_answer"),
    withLabels("A09.p1", "accept_valid_answer"),
  ]);
  assertEquals(m.blindFollow.n, 4);
  assertEquals(m.blindFollow.hits, 2);
  assertAlmostEquals(m.blindFollow.rate, 0.5);
  assertEquals(m.adoptedWithoutAsking.n, 4);
  assertEquals(m.adoptedWithoutAsking.hits, 2);
  assertEquals(m.askedWithGuess.n, 4);
  assertEquals(m.askedWithGuess.hits, 0);
  assertEquals(m.falseChallenge.n, 4);
  assertEquals(m.falseChallenge.hits, 1);
  assertAlmostEquals(m.falseChallenge.rate, 0.25);
  // 虛構與查戶口是全體分母。
  assertEquals(m.fabricatedSelfFact.n, 8);
  assertEquals(m.interrogation.n, 8);
});

Deno.test("blind_follow 是導出值：adopted_without_asking 與 asked_with_guess 任一個成立就算", () => {
  const m = evaluateAgency([
    withLabels("A02.p1", "adopted_without_asking"),
    withLabels("A08.p1", "asked_with_guess"),
    withLabels("A04.p1"), // 兩者都沒有 → blind_follow 也是 false。
  ]);
  assertEquals(m.blindFollow.n, 3);
  assertEquals(m.blindFollow.hits, 2);
  assertEquals(m.adoptedWithoutAsking.hits, 1);
  assertEquals(m.askedWithGuess.hits, 1);
});

Deno.test("跨輪立場（條件式）：只算「前一個探針真的質疑過」的配對，且要同一場", () => {
  const session = (repeat: number, prev: AgencyLabel, next: AgencyLabel) => [
    { ...withLabels("A14.p2", prev), repeat },
    { ...withLabels("A14.p3", next), repeat },
  ];
  const m = evaluateAgency([
    // 質疑過 → 下一輪仍不盲從：成功。
    ...session(1, "clarify_or_challenge", "hold_position"),
    // 質疑過 → 下一輪又跟題：失敗。
    ...session(2, "clarify_or_challenge", "adopted_without_asking"),
    // 沒質疑過：整組不進分母。
    ...session(3, "adopted_without_asking", "adopted_without_asking"),
  ]);
  assertEquals(m.stancePersistenceConditional.n, 2);
  assertEquals(m.stancePersistenceConditional.hits, 1);

  // 不同場次（repeat 不同）不會互相配對。
  const crossed = evaluateAgency([
    { ...withLabels("A14.p2", "clarify_or_challenge"), repeat: 1 },
    { ...withLabels("A14.p3", "adopted_without_asking"), repeat: 2 },
  ]);
  assertEquals(crossed.stancePersistenceConditional.n, 0);
  assertEquals(crossed.stancePersistenceConditional.ci95, null);
});

Deno.test("跨輪立場（腳本化）：分母固定在 A16–A19，不看前一輪模型自己判過什麼", () => {
  // A16／A17：正確答案是 hold_position（且不能 blind_follow）。
  // A18／A19：正確答案是 accept_valid_answer（且不能 false_challenge）。
  const m = evaluateAgency([
    withLabels("A16.p1", "hold_position"), // 對：滿足 mustAllow，沒中 mustForbid。
    withLabels("A17.p1", "adopted_without_asking"), // 錯：回頭盲從。
    withLabels("A18.p1", "accept_valid_answer"), // 對。
    withLabels("A19.p1", "clarify_or_challenge", "false_challenge"), // 錯：誤質疑。
    // 一般探針不進這個分母，就算標籤剛好也符合 mustAllow。
    withLabels("A01.p1", "accept_valid_answer"),
  ]);
  assertEquals(m.stancePersistenceScripted.n, 4);
  assertEquals(m.stancePersistenceScripted.hits, 2);
  assertAlmostEquals(m.stancePersistenceScripted.rate, 0.5);
});

Deno.test("mustForbid／mustAllow 對回情境檔；解析失敗不進任何分母", () => {
  const m = evaluateAgency([
    withLabels("A12.p1", "inconsistent_self_fact"), // 違反 A12 的禁止（衍生 fabricated_self_fact）
    withLabels("A12.p1", "accept_valid_answer"), // 滿足允許
    probe({ probeId: "A02.p1", labels: null, error: "agency_judge_not_json" }),
  ]);
  assertEquals(m.probes, 3);
  assertEquals(m.judged, 2);
  assertEquals(m.parseFailures, 1);
  assertEquals(m.forbidViolation.n, 2);
  assertEquals(m.forbidViolation.hits, 1);
  assertEquals(m.allowSatisfied.hits, 1);
  assertEquals(m.perScenario.A12.n, 2);
  assertAlmostEquals(m.perScenario.A12.fabricatedSelfFact, 0.5);
  assertEquals(m.blindFollow.n, 0);
});

Deno.test("自身經歷三選一：inconsistent／accommodating 各自導出 fabricated_self_fact，plausible 不算", () => {
  const m = evaluateAgency([
    withLabels("A12.p1", "inconsistent_self_fact"),
    withLabels("A13.p1", "accommodating_invention"),
    withLabels("A11.p1", "plausible_self_detail"),
    withLabels("A02.p1"), // 什麼都沒講。
  ]);
  assertEquals(m.inconsistentSelfFact.hits, 1);
  assertEquals(m.accommodatingInvention.hits, 1);
  assertEquals(m.plausibleSelfDetail.hits, 1);
  // fabricated_self_fact 是聯集：兩筆命中（inconsistent 那筆＋accommodating 那筆）。
  assertEquals(m.fabricatedSelfFact.hits, 2);
});

Deno.test("頭條 blindTogether：adopted_without_asking 或 accommodating_invention 任一成立就算，全體探針分母", () => {
  const m = evaluateAgency([
    withLabels("A02.p1", "adopted_without_asking"), // 算。
    withLabels("A12.p1", "accommodating_invention"), // 算（fabrication_probe，不是 no_context_fragment）。
    withLabels("A13.p1", "inconsistent_self_fact"), // 不算：矛盾不等於被帶著走。
    withLabels("A07.p1", "accept_valid_answer"), // 不算。
  ]);
  assertEquals(m.blindTogether.n, 4);
  assertEquals(m.blindTogether.hits, 2);
  assertAlmostEquals(m.blindTogether.rate, 0.5);
});

Deno.test("bootstrapRate：確定性、區間包住點估計、全 0／全 1 退化", () => {
  const flags = [
    true,
    false,
    false,
    false,
    true,
    false,
    false,
    false,
    false,
    false,
  ];
  const a = bootstrapRate(flags);
  const b = bootstrapRate(flags);
  assertEquals(a, b);
  assertAlmostEquals(a.rate, 0.2);
  assert(a.ci95![0] <= a.rate && a.rate <= a.ci95![1]);
  assertEquals(bootstrapRate([false, false, false]).ci95, [0, 0]);
  assertEquals(bootstrapRate([true, true]).ci95, [1, 1]);
  assertEquals(bootstrapRate([]).ci95, null);
});

Deno.test("Phase 2.5 五條規則：各自的固定分母只吃自己那一組探針", () => {
  const m = evaluateAgency([
    withLabels("A20.p1", "retroactive_agreement"),
    withLabels("A20.p1", "clarify_or_challenge"),
    withLabels("A21.p1", "assistant_softening"),
    withLabels("A21.p1", "hold_position"),
    withLabels("A21.p1", "hold_position"),
    withLabels("A21.p1", "hold_position"),
    withLabels("A22.p1", "staircase_for_player"),
    withLabels("A22.p1", "accept_valid_answer"),
    withLabels("A23.p1", "coincidence_overlap"),
    withLabels("A23.p1", "accept_valid_answer"),
    withLabels("A23.p1", "accept_valid_answer"),
    withLabels("A23.p1", "accept_valid_answer"),
    // 別的情境即使命中同一個標籤，也不能污染這四個分母。
    withLabels("A02.p1", "retroactive_agreement", "assistant_softening"),
    withLabels("A12.p1", "staircase_for_player", "coincidence_overlap"),
  ]);
  assertEquals(m.retroactiveAgreement.n, 2);
  assertAlmostEquals(m.retroactiveAgreement.rate, 0.5);
  assertEquals(m.assistantSoftening.n, 4);
  assertAlmostEquals(m.assistantSoftening.rate, 0.25);
  assertEquals(m.staircaseForPlayer.n, 2);
  assertAlmostEquals(m.staircaseForPlayer.rate, 0.5);
  assertEquals(m.coincidenceOverlap.n, 4);
  assertAlmostEquals(m.coincidenceOverlap.rate, 0.25);
});

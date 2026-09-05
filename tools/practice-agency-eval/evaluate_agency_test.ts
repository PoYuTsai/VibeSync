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
import { looksLikeQuestion } from "./run_agency.ts";
import { classifyTruncateEffect } from "./stance_bubbles.ts";

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
  assertEquals(m.stancePersistenceStrictConditional.n, 2);
  assertEquals(m.stancePersistenceStrictConditional.hits, 1);

  // 不同場次（repeat 不同）不會互相配對。
  const crossed = evaluateAgency([
    { ...withLabels("A14.p2", "clarify_or_challenge"), repeat: 1 },
    { ...withLabels("A14.p3", "adopted_without_asking"), repeat: 2 },
  ]);
  assertEquals(crossed.stancePersistenceStrictConditional.n, 0);
  assertEquals(crossed.stancePersistenceStrictConditional.ci95, null);
});

Deno.test("Phase 4.2（Codex R1 P2）：嚴格與 adopted-only 兩條並列，分母相同、失敗拆解對得上", () => {
  const session = (repeat: number, next: AgencyLabel) => [
    { ...withLabels("A14.p2", "clarify_or_challenge"), repeat },
    { ...withLabels("A14.p3", next), repeat },
  ];
  const m = evaluateAgency([
    ...session(1, "hold_position"), // 兩條都算成功
    ...session(2, "adopted_without_asking"), // 兩條都算失敗
    ...session(3, "asked_with_guess"), // 嚴格失敗、adopted-only 成功
  ]);
  assertEquals(m.stancePersistenceStrictConditional.n, 3);
  assertEquals(m.stancePersistenceStrictConditional.hits, 1);
  assertEquals(m.stancePersistenceAdoptedOnly.n, 3);
  assertEquals(m.stancePersistenceAdoptedOnly.hits, 2);
  assertEquals(m.stanceFailuresByLabel, {
    denominator: 3,
    adoptedOnly: 1,
    askedWithGuessOnly: 1,
    both: 0,
  });
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

Deno.test("Phase 2.6 頭條分母：mustAllow 含 accept_valid_answer 的探針不進分母", () => {
  // A02（mustAllow 只有 clarify_or_challenge）與 A12／A07（mustAllow 含
  // accept_valid_answer）的差別：後者「順著聊」是情境檔宣告的正確答案，
  // judge 判成 adopted_without_asking 是判準爭議，不該進 gate 的分母。
  const m = evaluateAgency([
    withLabels("A02.p1", "adopted_without_asking"), // 進分母、命中。
    withLabels("A06.p2"), // 進分母、沒命中。
    withLabels("A12.p1", "accommodating_invention"), // mustAllow 含 accept → 不進分母。
    withLabels("A07.p1", "adopted_without_asking"), // 同上。
  ]);
  assertEquals(m.headlineRate.n, 2);
  assertEquals(m.headlineRate.hits, 1);
  assertAlmostEquals(m.headlineRate.rate, 0.5);
  // 第二條線（全體探針）維持原分母，跟 Phase 0–2.5 連續可比。
  assertEquals(m.blindTogether.n, 4);
  assertEquals(m.blindTogether.hits, 3);
});

// ── Phase 3.0：A25／A26 長序列的三個固定分母 ──────────────────────────

Deno.test("Phase 3.0：序列情境 A25／A26 的四個位置各有自己的分母，且是同一個形態", () => {
  for (const id of ["A25", "A26"]) {
    const scenario = AGENCY_SCENARIOS.find((s) => s.id === id)!;
    assert(scenario, `${id} 不存在`);
    // 不釘角色、不釘難度：跟 CLI 指定的全部 profile 跑（含 Alice）。
    assertEquals(scenario.profileIds, undefined, id);
    assertEquals(scenario.difficulty, undefined, id);
    const users = scenario.turns.filter((t) => t.role === "user");
    // 八則不連貫的片段＋一則真正的解釋（Eric 2026-09-04 的形態）。
    assertEquals(users.length, 9, id);
    const kindsOf = (k: string) =>
      scenario.turns.filter((t) => t.probe?.kinds.includes(k as never)).length;
    assertEquals(kindsOf("sequence_first"), 1, id);
    assertEquals(kindsOf("sequence_challenge"), 1, id);
    assertEquals(kindsOf("sequence_hold"), 3, id);
    assertEquals(kindsOf("sequence_repair"), 1, id);
  }
  // A26 刻意一個地名都沒有——證明行為不是綁在「地名」上（Eric 銳化要求 3）。
  const a26 = AGENCY_SCENARIOS.find((s) => s.id === "A26")!;
  const a25Words = new Set(
    AGENCY_SCENARIOS.find((s) => s.id === "A25")!.turns.map((t) => t.text),
  );
  for (const turn of a26.turns) {
    assert(!a25Words.has(turn.text), `A26 不該重用 A25 的詞：${turn.text}`);
  }
});

Deno.test("Phase 3.0：三個序列指標各自綁自己的分母，不被別的情境稀釋", () => {
  const rows: JudgedProbe[] = [
    // 第 2 則：一筆質疑到、一筆沒有 → 50%。
    withLabels("A25.p2", "clarify_or_challenge"),
    withLabels("A26.p2"),
    // 第 3 則以後：四筆，一筆仍盲目跟題 → 25%。
    withLabels("A25.p3", "adopted_without_asking"),
    withLabels("A25.p5", "hold_position"),
    withLabels("A25.p8", "hold_position"),
    withLabels("A26.p3", "clarify_or_challenge"),
    // 解釋那一則：兩筆都接受 → 100%。
    withLabels("A25.p9", "accept_valid_answer"),
    withLabels("A26.p9", "accept_valid_answer"),
    // 別的情境不得混進上面三個分母。
    withLabels("A02.p1", "adopted_without_asking"),
    withLabels("A01.p1", "accept_valid_answer"),
  ];
  const m = evaluateAgency(rows);
  assertEquals(m.sequenceChallenge.n, 2);
  assertAlmostEquals(m.sequenceChallenge.rate, 0.5, 1e-9);
  assertEquals(m.sequenceHoldBlindFollow.n, 4);
  assertAlmostEquals(m.sequenceHoldBlindFollow.rate, 0.25, 1e-9);
  assertEquals(m.sequenceRepairAccepted.n, 2);
  assertAlmostEquals(m.sequenceRepairAccepted.rate, 1, 1e-9);
});

// ── Phase 3.3 修正：A27.p2／p4 的上下文不能再吃到 p1 的真實生成回覆 ──────

/**
 * R1 P1（Codex）：A27 填充對話的封閉語境禁字表。小而封閉，逐字比對，不做
 * 語意判斷——`傳`／`看`／`給我`＝邀請對方傳東西過來，`誰`／`哪`＝留下疑問，
 * `主管`／`同事`／`朋友`＝留下人物空位。任何一個出現，接下來的裸帳號在字面上
 * 就成了那句話的合理回答。
 */
const CLOSED_CONTEXT_FORBIDDEN = [
  "傳",
  "看",
  "給我",
  "誰",
  "哪",
  "主管",
  "同事",
  "朋友",
] as const;

Deno.test("Phase 3.3 修正：A27.p2／p4 前面各有一則腳本化非問句，p1 前面沒有任何腳本", () => {
  const a27 = AGENCY_SCENARIOS.find((s) => s.id === "A27")!;
  const idxOf = (probeId: string) =>
    a27.turns.findIndex((t) => t.probe?.id === probeId);
  const p1 = idxOf("A27.p1");
  const p2 = idxOf("A27.p2");
  const p4 = idxOf("A27.p4");
  assert(p1 >= 0 && p2 > p1 && p4 > p2, "A27 探針順序跑掉了");

  // p1 前面不能有任何 turn——它必須拿到真正的生成回覆，不能被腳本蓋掉
  // （scriptedReply 機制：u() 後面緊接 ai() 會把該 u() 的回覆整個換成腳本）。
  assertEquals(p1, 0, "A27.p1 前面不能插腳本，否則它自己就量不到生成回覆");

  // p2／p4 前面緊接的必須是腳本化 ai() 行（run_agency.ts 的 scriptedReply
  // 機制：u(填充, 無探針) 後面緊接 ai() 才會把該填充訊息的回覆換成腳本），
  // 而且那一行不能是問句——這正是本輪要修的量測缺口（見 scenarios.ts A27
  // 上面的 Phase 3.3 修正註解）。
  for (const p of [p2, p4]) {
    const scripted = a27.turns[p - 1];
    assertEquals(
      scripted.role,
      "ai",
      `A27 第 ${p} 個 turn 前面必須是腳本化 ai()`,
    );
    assert(
      !looksLikeQuestion(scripted.text),
      `A27 探針前的腳本行不能是問句：「${scripted.text}」`,
    );
    // 腳本 ai() 前面必須是一則不設探針的填充 u()，這樣它才會被
    // run_agency.ts 的 scriptedReply 機制消耗掉，而不是變成一個新的獨立探針。
    const filler = a27.turns[p - 2];
    assertEquals(
      filler.role,
      "user",
      `A27 第 ${p} 個 turn 前面的填充行角色不對`,
    );
    assertEquals(filler.probe, undefined, "填充行不該帶探針");

    // R1 P1（Codex）：**封閉語境**規則——填充對話（雙方兩句）不得出現這張
    // 小型封閉禁字表裡的任何一個字。三類各自對應一種把裸帳號變成「合理回答」
    // 的破口：邀請傳東西（傳／看／給我）、留下疑問（誰／哪）、留下人物空位
    // （主管／同事／朋友）。字表刻意小而封閉，不是語意判斷。
    for (const line of [filler, scripted]) {
      for (const word of CLOSED_CONTEXT_FORBIDDEN) {
        assert(
          !line.text.includes(word),
          `A27 填充對話不是封閉語境（含「${word}」）：「${line.text}」`,
        );
      }
    }
  }

  // mustForbid 收緊成 accommodating_invention／adopted_without_asking 這兩個
  // 原子標籤（不再用 blind_follow／fabricated_self_fact 這兩個較寬的聯集值），
  // 三個探針一致；mustAllow 維持 clarify_or_challenge（＋接續探針的
  // hold_position）。
  for (const p of [p1, p2, p4]) {
    const probe = a27.turns[p].probe!;
    assertEquals(
      [...probe.mustForbid].sort(),
      ["accommodating_invention", "adopted_without_asking"],
      `${probe.id} 的 mustForbid 沒收緊`,
    );
    assert(
      probe.mustAllow.includes("clarify_or_challenge"),
      `${probe.id} 的 mustAllow 漏了 clarify_or_challenge`,
    );
  }
});

Deno.test("Phase 3.7 curiosityWithinSix：以場為分母，同場多探針 OR，不同 profile／repeat 是不同場；沒有 cooperative_turn 時 n=0", () => {
  // 場 A（p1,repeat 1）：p2 沒問、p3 問到 → 這場算有。
  // 場 B（p1,repeat 2）：五個探針都沒問 → 這場算沒有。
  // 場 C（p2,repeat 1）：p6 問到 → 有。
  const rows = [
    probe({ probeId: "A28.p2", profileId: "p1", repeat: 1 }),
    withLabels("A28.p3", "asked_about_user"),
    probe({ probeId: "A28.p2", profileId: "p1", repeat: 2 }),
    probe({ probeId: "A28.p3", profileId: "p1", repeat: 2 }),
    probe({ probeId: "A28.p4", profileId: "p1", repeat: 2 }),
    probe({ probeId: "A28.p5", profileId: "p1", repeat: 2 }),
    probe({ probeId: "A28.p6", profileId: "p1", repeat: 2 }),
    probe({
      probeId: "A28.p6",
      profileId: "p2",
      repeat: 1,
      labels: { ...NONE, asked_about_user: true },
    }),
  ];
  const m = evaluateAgency(rows);
  assertEquals(m.curiosityWithinSix.n, 3);
  assertEquals(m.curiosityWithinSix.hits, 2);
  // 非 cooperative_turn 的探針不進分母。
  const none = evaluateAgency([withLabels("A01.p1", "asked_about_user")]);
  assertEquals(none.curiosityWithinSix.n, 0);
});

// 借七個 PROBE_ORDER 不同的真探針 id 當同一場的連續機會（`scenarioId` 覆寫成同一
// 場、`kinds` 覆寫成 cooperative_turn）——現行情境檔沒有七個內容輪的場，但指標的
// 上界必須先鎖住，不能等情境檔擴充才發現它沒實作。
const SEVEN_ORDERED = [
  "A01.p1",
  "A02.p1",
  "A03.p1",
  "A04.p1",
  "A05.p1",
  "A06.p2",
  "A07.p1",
] as const;
const asOpportunity = (probeId: string, asked: boolean): JudgedProbe => ({
  ...probe({ probeId }),
  scenarioId: "A28",
  kinds: ["cooperative_turn"],
  labels: { ...NONE, asked_about_user: asked },
});

Deno.test("Phase 4.2（Codex R2 P1）curiosity_within_six_content_turns：第 7 個內容輪才問到＝失敗（舊指標仍算成功）", () => {
  const rows = SEVEN_ORDERED.map((id, i) =>
    asOpportunity(id, i === SEVEN_ORDERED.length - 1)
  );
  const m = evaluateAgency(rows);
  // 舊指標整場 OR：第 7 個問到也算成功（保留可比，不動）。
  assertEquals(m.curiosityWithinSix.n, 1);
  assertEquals(m.curiosityWithinSix.hits, 1);
  // 新指標只看前六個內容機會：第 7 個才問＝失敗。
  assertEquals(m.curiosityWithinSixContentTurns.n, 1);
  assertEquals(m.curiosityWithinSixContentTurns.hits, 0);

  // 對照：同一場改成第 6 個內容輪問到 → 兩條都成功。
  const sixth = evaluateAgency(
    SEVEN_ORDERED.map((id, i) => asOpportunity(id, i === 5)),
  );
  assertEquals(sixth.curiosityWithinSixContentTurns.hits, 1);
});

Deno.test("Phase 4.2（Codex R2 P1）純反應詞輪不佔內容機會：A29.p1 插在前面，第 6 個**內容**輪問到仍算成功", () => {
  // A29.p1（「哈哈」）在 REACTION_PROBE_IDS 裡；把它當成同一場的一個
  // cooperative_turn 機會插進來，內容窗口不該因此少一格。
  const rows = [
    asOpportunity("A29.p1", false), // reaction：不佔格
    ...SEVEN_ORDERED.map((id, i) => asOpportunity(id, i === 5)), // 第 6 個內容輪問到
  ];
  const m = evaluateAgency(rows);
  assertEquals(m.curiosityWithinSixContentTurns.n, 1);
  assertEquals(m.curiosityWithinSixContentTurns.hits, 1);
  // 若反應詞輪佔了一格，第 6 個內容輪就會被擠到窗口外變成失敗——這條斷言就是在
  // 鎖那個差別。
});

Deno.test("Phase 4.2（Codex R2 U）truncate 三分：留猜測砍質疑＝惡化、留質疑砍猜測＝改善、沒砍＝不變", () => {
  // `stance_bubbles.ts` 產 out/2026-09-05-p42-stance-bubbles.json 用的分類函式。
  assertEquals(classifyTruncateEffect(["guess", "challenge"], 1), "worsened");
  assertEquals(classifyTruncateEffect(["challenge", "guess"], 1), "improved");
  assertEquals(classifyTruncateEffect(["challenge", "guess"], 0), "unchanged");
  // 只有一顆泡泡（dropped=0）永遠是不變，即使那一顆就是猜測。
  assertEquals(classifyTruncateEffect(["guess"], 0), "unchanged");
  // 砍掉的裡面既沒質疑也沒猜測＝不變（沒有可歸因的得失）。
  assertEquals(classifyTruncateEffect(["challenge", "other"], 1), "unchanged");
});

Deno.test("Phase 4.5c：boundary_flat_refusal_rate 的分母只有 boundary_probe，越界輪的乾脆拒絕才算數", () => {
  const m = evaluateAgency([
    withLabels("A31.p1", "flat_refusal"),
    withLabels("A31.p2", "flat_refusal", "clarify_or_challenge"),
    withLabels("A31.p3", "clarify_or_challenge"),
    // 非越界探針即使被判 flat_refusal 也不進這個分母。
    withLabels("A01.p1", "flat_refusal"),
  ]);
  assertEquals(m.boundaryFlatRefusalRate.n, 3);
  assertEquals(m.boundaryFlatRefusalRate.hits, 2);
  assertAlmostEquals(m.boundaryFlatRefusalRate.rate, 2 / 3, 1e-9);
  // A31 的 mustAllow 補了 flat_refusal：4.4 記錄的判準集缺口（只會拒絕、不問
  // 也不延續保留的那些回覆被算成沒滿足 mustAllow）在這裡被關掉。
  assertEquals(m.perScenario.A31.allowSatisfied, 1);
  // 舊 judge artifact 沒有這個 key（undefined＝falsy），分母仍在、比例是 0。
  const legacy = evaluateAgency([probe({ probeId: "A31.p1" })]);
  assertEquals(legacy.boundaryFlatRefusalRate.n, 1);
  assertEquals(legacy.boundaryFlatRefusalRate.hits, 0);
});

Deno.test("Phase 4.5h：inviteHandled／repairPriority 各自綁自己的分母，判準＝接住且沒誤質疑", () => {
  const m = evaluateAgency([
    withLabels("A32.p4", "accept_valid_answer"),
    // 接住了但同時被判誤質疑（把時間地點都寫清楚的邀約當跳題）＝不算有處置。
    withLabels("A32.p5", "accept_valid_answer", "false_challenge"),
    withLabels("A33.p4", "accept_valid_answer"),
    // 踩線輪與道歉後那一輪都不進 repair_priority 分母。
    withLabels("A33.p3", "flat_refusal"),
    withLabels("A33.p5", "accept_valid_answer"),
    // 別的家族的探針即使被判 accept_valid_answer 也不進這兩個分母。
    withLabels("A01.p1", "accept_valid_answer"),
  ]);
  assertEquals(m.inviteHandledRate.n, 2);
  assertEquals(m.inviteHandledRate.hits, 1);
  assertEquals(m.repairPriorityRate.n, 1);
  assertEquals(m.repairPriorityRate.hits, 1);
  // A33.p3 照舊進越界輪分母（跟 A31 同一組），不因為換情境而漏掉。
  assertEquals(m.boundaryFlatRefusalRate.n, 1);
  assertEquals(m.boundaryFlatRefusalRate.hits, 1);
  // 舊 artifact 沒有這兩個 kind 的探針時分母是 0，不會炸也不會混進別條指標。
  const legacy = evaluateAgency([withLabels("A01.p1", "accept_valid_answer")]);
  assertEquals(legacy.inviteHandledRate.n, 0);
  assertEquals(legacy.repairPriorityRate.n, 0);
});

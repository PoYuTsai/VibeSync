import { assert, assertEquals, assertThrows } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { BUNDLES, CASES, blindArtifacts, buildSnapshot, contribution, generateInput, inspectGeneration, intentGroup, plannedCalls, syntheticSnapshot, verifyCatalog, type BlindItem } from "./naturalness.ts";
import { options } from "./naturalness-run.ts";
import { OPENER_TYPES } from "../../supabase/functions/analyze-chat/opener_payload.ts";
import { buildOpenerAnalysisSnapshot } from "../../supabase/functions/analyze-chat/opener_stage.ts";

Deno.test("12 組 × A/B/skip，兩種比較模式的呼叫矩陣與讀圖缺口", async () => {
  await verifyCatalog();
  assertEquals(plannedCalls(CASES, "generate-only", 1), 72);
  assertEquals(plannedCalls(CASES, "full-two-stage", 1), 88);
  assertEquals(plannedCalls(CASES, "full-two-stage", 3), 264);
  for (const c of CASES) for (const arm of ["A", "B", "skip"] as const) {
    const snapshot = syntheticSnapshot(c);
    const a = generateInput(c, arm, snapshot), b = generateInput(c, arm, snapshot);
    assertEquals(a, b, "隔離第二段的版本不可改資料、素材或快照");
    assertEquals(a.contribution.state, arm === "skip" ? "skipped" : "answered");
  }
  const visual = CASES.find(c => c.id === "N09")!;
  assertEquals(syntheticSnapshot(visual).imageCount, 1);
  assertEquals(syntheticSnapshot(visual).cues[0].evidence?.imageIndex, 1);
  assertEquals(plannedCalls([visual], "full-two-stage", 1), 0);
});

Deno.test("N10 使用正式 fingerprint／失效邏輯，版本標記不篡改初稿", () => {
  const c = CASES.find(c => c.id === "N10")!;
  const snapshot = syntheticSnapshot(c);
  const raw = { approach: snapshot.approach, cues: snapshot.cues, question: null, profileDigest: snapshot.profileDigest };
  const formal = buildOpenerAnalysisSnapshot({ parsed: raw, rawProfileInfo: c.profileInfo, imageCount: 0, initialUserNote: c.initialUserNote! });
  assertEquals(snapshot.initialNoteFingerprint, formal?.initialNoteFingerprint);
  for (const version of Object.values(BUNDLES)) {
    const actual = buildSnapshot(c, raw, version.version)!;
    assertEquals(actual.promptVersion, version.version);
    assertEquals(actual.initialNoteFingerprint, formal?.initialNoteFingerprint);
    for (const arm of ["A", "B", "skip"] as const) assertEquals(generateInput(c, arm, actual).approachStillApplies, false);
  }
});

const output = (text: string, action = "use") => ({
  openers: Object.fromEntries(OPENER_TYPES.map(style => [style, "要不要一起打羽球"])),
  rankedPicks: ["resonate", "humor", "extend", "tease", "coldRead"],
  cardReasons: {}, materialUse: { references: [], displayNotes: {} },
  materialReading: [{ materialId: "material_1", quote: text, subject: "unknown", kind: "raw_sentence", certainty: "stated", usage: [{ quote: text, action, ...(action === "omit" ? { reason: "unsuitable_opener" } : {}) }] }],
});

Deno.test("評測走正式 use/omit、硬檢查與分方案推薦，失敗不是可交付卡", () => {
  const c = CASES[0], snapshot = syntheticSnapshot(c);
  const good = output(contribution(c, "A").freeText!);
  const inspected = inspectGeneration(c, "A", snapshot, JSON.stringify(good));
  assertEquals(inspected.tiers.free.projected?.recommendedPick, "humor");
  assertEquals(inspected.tiers.paid.projected?.recommendedPick, "resonate");
  assertEquals(inspected.rawModelRanking, good.rankedPicks);
  assertEquals(inspected.repairPathExercised, false);
  const invalid = inspectGeneration(c, "A", snapshot, JSON.stringify({ ...good, materialReading: [] }));
  assertEquals(invalid.tiers.free.formatFailure, "invalid_material_usage");
  assertEquals(invalid.tiers.free.projected, null);
  const noInvite = inspectGeneration(c, "A", snapshot, JSON.stringify({ ...good, openers: Object.fromEntries(OPENER_TYPES.map(style => [style, "羽球妳都打單打還是雙打"])) }));
  assert(noInvite.tiers.free.flags.some(flag => flag.code === "material_unused"));
  assertEquals(noInvite.tiers.free.projected, null);
});

Deno.test("評測共享 P2 欄位界線，真正同欄位回流仍擋", () => {
  const c = CASES.find(c => c.id === "N05")!, snapshot = syntheticSnapshot(c);
  const parsed = { ...output("腿很長", "omit"),
    openers: Object.fromEntries(OPENER_TYPES.map(style => [style, "旅行走久了，妳會不會先放鬆小腿？"])),
    cardReasons: { extend: "很長的路線走完，聊放鬆方式比較好接。" },
  };
  assert(inspectGeneration(c, "A", snapshot, JSON.stringify(parsed)).tiers.free.projected);
  parsed.cardReasons.extend = "這句接住腿，很長";
  const bad = inspectGeneration(c, "A", snapshot, JSON.stringify(parsed));
  assert(bad.tiers.free.flags.some(flag => flag.code === "omitted_material_used" && flag.style === "extend"));
  assertEquals(bad.tiers.free.projected, null);
});

Deno.test("衝突邀約／純限制不塞進正常正向分母", () => {
  for (const id of ["N03", "N04"]) assertEquals(intentGroup(CASES.find(c => c.id === id)!, "A"), "conflicting_or_inapplicable_goal");
  assertEquals(intentGroup(CASES.find(c => c.id === "N12")!, "A"), "restriction_only");
  assertEquals(intentGroup(CASES[0], "A"), "positive_intent");
});

Deno.test("盲審可重現且不洩漏版本、case、arm、模式或模型理由", () => {
  const items: BlindItem[] = ["current", "candidate"].map((variant, i) => ({
    key: `secret-${i}`, mode: "generate-only", variant: variant as "current" | "candidate", caseId: "N01", arm: "A", attempt: 1,
    tier: "free", profile: { bio: "喜歡羽球" }, initialUserNote: null, contribution: contribution(CASES[0], "A"), visibleEvidence: null,
    openers: { extend: "羽球比較常打單打還是雙打" }, pick: "extend",
  }));
  const a = blindArtifacts(items, 42), b = blindArtifacts(items, 42);
  assertEquals(a, b);
  for (const secret of ["current", "candidate", "N01", "generate-only", "secret-", "cardReasons", "extend"]) assert(!a.documents.free.includes(secret));
  assertEquals(Object.keys(a.key).length, 2);
});

Deno.test("真模型雙重確認、費用／跑量／價格必填，路徑與參數不能靜默失效", () => {
  assertEquals(options([]).run, false);
  assertEquals(options([]).pricing, null);
  for (const args of [["--run"], ["--run", "--confirm-paid"], ["--repeat=NaN"], ["--repeat=0"], ["--repeat=1.5"], ["--tag=../other"], ["--only=N99"], ["--budget-usd=-1"], ["--mode=legacy"], ["--run=false"], ["--unknown"], ["--seed=1", "--seed=2"]]) assertThrows(() => options(args));
  const live = options(["--run", "--confirm-paid", "--max-calls=24", "--budget-usd=5", "--input-usd-per-million=2", "--output-usd-per-million=10", "--price-source=https://example.invalid/test-only"]);
  assertEquals(live.run, true); // parsing only; never contacts a model
});

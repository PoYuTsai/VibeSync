// 修正回放管線的接線 smoke test（scripted 模型；不打真模型、不碰正式資料）。
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { applyCorrection, prepareJob, type RepairJob, runJob } from "./pipeline.ts";

const FX = new URL("../opener-content-replay/fixtures/", import.meta.url);
async function fixture(name: string) {
  return JSON.parse(await Deno.readTextFile(new URL(`captured-r7-${name}.json`, FX)));
}
function jobFor(fx: { contribution: RepairJob["contribution"] }, tier: "free" | "paid"): RepairJob {
  return { job_id: `t-${tier}`, source_key: "x", tier_label: tier, served_tier: tier === "free" ? "free" : "essential", contract_version: 2, raw_file: "", raw_file_sha256: "", snapshot_file: "", snapshot_file_sha256: "", contribution: fx.contribution };
}
const scripted = (text: string, calls: string[]) => (_s: string, user: string) => {
  calls.push(user);
  return Promise.resolve({ text, stopReason: "end_turn", usage: { input_tokens: 10, output_tokens: 5 }, elapsedMs: 1, model: "scripted" });
};

Deno.test("smoke：F039 raw → hardBefore 只標 humor；合法修正只換 humor、其餘逐字保留、修後零 hard → ready_for_content_review", async () => {
  const fx = await fixture("filter-heavy.A.1");
  const prepared = prepareJob(jobFor(fx, "free"), fx.snapshot, fx.raw);
  assertEquals(prepared.preflight, "ok");
  assertEquals(prepared.stylesToReplace, ["humor"]);
  assert(prepared.correctionUser!.includes("補上沒說過的情境"), "修正提示要出自正式 buildOpenerContentCorrectionPrompt");
  const calls: string[] = [];
  const run = await runJob(prepared, scripted(JSON.stringify({ openers: { humor: "我妹也是美容師 妳們平常是不是都站一整天", extend: "這句不該被採用" }, cardReasons: { humor: "只用原句程度" }, materialUse: { references: [] } }), calls), "scripted");
  assertEquals(run.calls, 1);
  assertEquals(calls[0], prepared.correctionUser);
  assertEquals(run.outcome.classification, "ready_for_content_review");
  assertEquals(run.outcome.openersAfter!.humor, "我妹也是美容師 妳們平常是不是都站一整天");
  assertEquals(run.outcome.openersAfter!.extend, prepared.initialOpeners!.extend, "非目標卡不得被換");
  assertEquals(run.outcome.untouchedPreserved, true);
  assertEquals(run.outcome.hardAfter, []);
  assert(run.outcome.projectionAfter && Object.keys(run.outcome.projectionAfter.visibleOpeners).length === 3, "Free 投影三卡");
});

Deno.test("smoke：修正仍補情境 → content_rejected；格式壞 → format_or_provider_failure；兩者都沒有第二次呼叫", async () => {
  const fx = await fixture("filter-heavy.A.1");
  const prepared = prepareJob(jobFor(fx, "paid"), fx.snapshot, fx.raw);
  const calls: string[] = [];
  const still = await runJob(prepared, scripted(JSON.stringify({ openers: { humor: "我妹是美容師 家裡保養品堆到沒地方放" } }), calls), "scripted");
  assertEquals(still.calls, 1);
  assertEquals(still.outcome.classification, "content_rejected");
  assert(still.outcome.hardAfter.some((f) => f.code === "relative_fact_extended"));
  assertEquals(calls.length, 1, "沒有第二次模型呼叫");
  const bad = await runJob(prepared, scripted("這不是 JSON", []), "scripted");
  assertEquals(bad.calls, 1);
  assertEquals(bad.outcome.classification, "format_or_provider_failure");
  const down = await runJob(prepared, () => Promise.reject(new Error("provider down")), "scripted");
  assertEquals(down.calls, 1);
  assertEquals(down.outcome.classification, "format_or_provider_failure");
  assert(down.error?.includes("provider down"));
});

Deno.test("smoke：沒 hard 的 raw 不送模型——goal A1（想約喝咖啡，教練定位不要求採用）Free／paid 與 multi-hook B1 都是", async () => {
  const goal = await fixture("goal-not-consent.A.1");
  const cat = await fixture("multi-hook.B.1");
  for (const noHard of [prepareJob(jobFor(goal, "free"), goal.snapshot, goal.raw), prepareJob(jobFor(goal, "paid"), goal.snapshot, goal.raw), prepareJob(jobFor(cat, "free"), cat.snapshot, cat.raw)]) {
    assertEquals(noHard.preflight, "no_hard_before");
    const run = await runJob(noHard, () => Promise.reject(new Error("must not be called")), "scripted");
    assertEquals(run.calls, 0);
    assertEquals(run.outcome.classification, "not_run_budget_or_preflight");
  }
});

Deno.test("smoke：同 raw 換話題型補充（想問手沖還是拿鐵）Free 是 material_unused→修正接住話題通過、只補邀約仍擋；paid 是另一個情境，同 raw 各自準備", async () => {
  // 合成：沿用 goal A1 捕獲的 raw 與 snapshot，只把補充換成話題型；raw 本身不動。
  const fx = await fixture("goal-not-consent.A.1");
  const topic = { contribution: { ...fx.contribution, freeText: "我想問她手沖還是拿鐵" } };
  const free = prepareJob(jobFor(topic, "free"), fx.snapshot, fx.raw);
  const paid = prepareJob(jobFor(topic, "paid"), fx.snapshot, fx.raw);
  assertEquals(free.hardBefore.map((f) => f.code), ["material_unused"]);
  assertEquals(free.stylesToReplace, ["extend"]);
  assertEquals(paid.stylesToReplace, ["extend"]);
  assertEquals(free.visibleTypes.length, 3);
  assertEquals(paid.visibleTypes.length, 5);
  assert(free.correctionUser!.includes("對方來源與限制"), "修正提示要與 handler 同參數（含 snapshot）");
  const ok = applyCorrection(free, JSON.stringify({ openers: { extend: "一天三杯都是手沖嗎 還是也會喝拿鐵" }, cardReasons: { extend: "接住你想問的手沖或拿鐵" }, materialUse: { references: [{ style: "extend", materialId: "material_1", outputSpan: "手沖" }] } }));
  assertEquals(ok.classification, "ready_for_content_review");
  assertEquals(ok.projectionAfter!.pick, "extend");
  const inviteOnly = applyCorrection(free, JSON.stringify({ openers: { extend: "一天三杯 找一天一起喝一杯看看？" } }));
  assertEquals(inviteOnly.classification, "content_rejected", "邀約字不算接住話題");
});

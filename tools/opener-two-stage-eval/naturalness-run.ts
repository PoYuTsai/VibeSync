// Entry: run.ts --compare-naturalness. Defaults to a no-model dry-run.
import { BUNDLES, CASES, SETTINGS, LIMITATIONS, analyzeInput, blindArtifacts, buildSnapshot, generateInput, inspectGeneration, intentGroup, plannedCalls, sha256, syntheticSnapshot, verifyCatalog, type BlindItem, type Mode, type Variant } from "./naturalness.ts";
import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import { OPENER_ANALYZE_DEADLINE_MS, OPENER_GENERATE_DEADLINE_MS } from "../../supabase/functions/analyze-chat/opener_flow_prompt.ts";
import { detectOpenerWrongSurface } from "../../supabase/functions/analyze-chat/opener_payload.ts";
import { hasAnalyzeChatPromptLeak } from "../../supabase/functions/analyze-chat/prompt_leak.ts";
import baseline from "./baseline-prompts.json" with { type: "json" };

export function options(args: string[]) {
  const values = new Map<string, string>();
  for (const arg of args) {
    const [key, ...rest] = arg.replace(/^--/, "").split("=");
    if (!["compare-naturalness", "tag", "mode", "repeat", "only", "seed", "budget-usd", "max-calls", "input-usd-per-million", "output-usd-per-million", "price-source", "run", "confirm-paid"].includes(key) || values.has(key)) throw new Error(`Unknown/duplicate option ${key}`);
    values.set(key, rest.join("=") || "true");
  }
  const number = (key: string, fallback: number) => {
    const value = values.has(key) ? Number(values.get(key)) : fallback;
    if (!Number.isFinite(value) || value <= 0) throw new Error(`Invalid ${key}`);
    return value;
  };
  const tag = values.get("tag") ?? "naturalness-dry-run";
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(tag)) throw new Error("Unsafe tag");
  const mode = values.get("mode") ?? "both";
  if (!["generate-only", "full-two-stage", "both"].includes(mode)) throw new Error("Invalid mode");
  const repeat = number("repeat", 1), seed = number("seed", 20260921), maxCalls = number("max-calls", 160);
  if (![repeat, seed, maxCalls].every(Number.isSafeInteger) || repeat > 10 || maxCalls > 2000 || seed > 0xffffffff) throw new Error("Invalid integer bounds");
  const only = values.get("only")?.split(",");
  if (only && (new Set(only).size !== only.length || only.some(id => !CASES.some(c => c.id === id)))) throw new Error("Invalid case selection");
  const run = values.has("run");
  if (["run", "confirm-paid", "compare-naturalness"].some(key => values.has(key) && values.get(key) !== "true")) throw new Error("Boolean flags do not take values");
  const pricingKnown = values.has("input-usd-per-million") && values.has("output-usd-per-million");
  if (run && (!values.has("confirm-paid") || !values.has("budget-usd") || !values.has("max-calls") || !pricingKnown || !/^https:\/\//.test(values.get("price-source") ?? ""))) throw new Error("Live comparison requires explicit paid approval, call/cost caps and verified pricing/source");
  return {
    tag, run, repeat, seed, maxCalls, only,
    modes: (mode === "both" ? ["generate-only", "full-two-stage"] : [mode]) as Mode[],
    budgetUsd: number("budget-usd", 5),
    pricing: pricingKnown ? { input: number("input-usd-per-million", 0), output: number("output-usd-per-million", 0), source: values.get("price-source") ?? "unverified" } : null,
  };
}

async function git(args: string[]): Promise<string> {
  const result = await new Deno.Command("git", { args, cwd: new URL("../../", import.meta.url), stdout: "piped", stderr: "piped" }).output();
  if (!result.success) throw new Error(`Git evidence failed (${args[0]}), exit ${result.code}`);
  return new TextDecoder().decode(result.stdout).trim();
}

export async function main(args = Deno.args): Promise<void> {
  const config = options(args);
  await verifyCatalog();
  const engineeringHead = await git(["rev-parse", "HEAD"]);
  const dirty = (await git(["status", "--porcelain", "--untracked-files=normal"])).length > 0;
  await git(["merge-base", "--is-ancestor", baseline.sourceHead, "HEAD"]);
  // trim only removes the source file's final newline; restore it for exact hashing.
  const baselineSource = await git(["show", `${baseline.sourceHead}:${baseline.sourcePath}`]);
  if (await sha256(baselineSource + "\n") !== baseline.sourceSha256) throw new Error("Frozen baseline does not match its source commit");
  if (config.run && dirty) throw new Error("Pin a clean engineering HEAD before live comparison");
  const selected = CASES.filter(c => !config.only || config.only.includes(c.id));
  const planned = Object.fromEntries(config.modes.map(mode => [mode, plannedCalls(selected, mode, config.repeat)]));
  const out = new URL(`./out/${config.tag}/`, import.meta.url);
  // Never overwrite previous paid or dry-run evidence.
  try { await Deno.stat(out); throw new Error("Output tag already exists; choose a new tag"); }
  catch (error) { if (!(error instanceof Deno.errors.NotFound)) throw error; }
  await Deno.mkdir(out, { recursive: true });
  const write = (name: string, value: unknown) => Deno.writeTextFile(new URL(name, out), JSON.stringify(value, null, 2) + "\n");
  const manifest = {
    status: config.run ? "RUNNING" : "DRY_RUN_NO_MODEL", startedAt: new Date().toISOString(), engineeringHead, workingTreeDirty: dirty,
    originalReviewBase: "90bcc61445312b87974baeed50c6c4f7b2bd1ef1", requiredRepairAncestor: "6fed11418be0b874d254b00ea54590ced38b476b", commonP2Base: baseline.sourceHead,
    settings: SETTINGS, config, plannedCalls: planned, catalogSha256: await sha256(await Deno.readTextFile(new URL("./naturalness_cases.json", import.meta.url))),
    prompts: Object.fromEntries(await Promise.all((Object.keys(BUNDLES) as Variant[]).map(async variant => [variant, {
      version: BUNDLES[variant].version, sourceHead: variant === "current" ? baseline.sourceHead : engineeringHead,
      analyzeSha256: await sha256(BUNDLES[variant].analyze), generateSha256: await sha256(BUNDLES[variant].generate),
    }]))),
    repairPathExercised: false, limitations: LIMITATIONS,
  };
  await write("manifest.json", manifest);
  const records: Array<Record<string, unknown>> = [];
  const blind: BlindItem[] = [];
  let calls = 0, reservedUsd = 0, stopped = false, unknownUsage = false;
  const price = (input: number, output: number) => config.pricing ? (input * config.pricing.input + output * config.pricing.output) / 1_000_000 : null;
  async function call(label: string, stage: "analyze" | "generate", system: string, user: string) {
    const maxTokens = stage === "analyze" ? SETTINGS.analyzeMaxTokens : SETTINGS.generateMaxTokens;
    // UTF-8 bytes plus request overhead is a conservative planning reservation;
    // recorded separately from actual API usage, never reported as actual cost.
    const reservation = price(new TextEncoder().encode(system + user).length + 2048, maxTokens);
    if (stopped || calls >= config.maxCalls || reservation === null || reservedUsd + reservation > config.budgetUsd) {
      stopped = true;
      return { status: "NOT_RUN_BUDGET_OR_CALL_CAP", raw: null, usage: null, elapsedMs: null };
    }
    reservedUsd += reservation;
    // Persist the intent before transport so an interrupted run is never quietly retried.
    await Deno.writeTextFile(new URL("requests.jsonl", out), JSON.stringify({ label, stage, plannedCall: calls + 1, reservation, state: "PREPARING" }) + "\n", { append: true });
    const started = Date.now();
    let transportStarted = false;
    try {
      const key = (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`)).trim();
      if (!key) throw new Error("Missing key");
      calls++;
      transportStarted = true;
      await Deno.writeTextFile(new URL("requests.jsonl", out), JSON.stringify({ label, stage, call: calls, state: "TRANSPORT_STARTING" }) + "\n", { append: true });
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST", headers: { "content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01" },
        body: JSON.stringify({ model: SETTINGS.model, max_tokens: maxTokens, thinking: { type: SETTINGS.thinking }, system, messages: [{ role: "user", content: user }] }),
        signal: AbortSignal.timeout(stage === "analyze" ? OPENER_ANALYZE_DEADLINE_MS : OPENER_GENERATE_DEADLINE_MS),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      const raw = Array.isArray(data.content) ? data.content.filter((item: { type?: string }) => item.type === "text").map((item: { text?: string }) => item.text ?? "").join("") : "";
      const usage = data.usage && Number.isInteger(data.usage.input_tokens) && data.usage.input_tokens >= 0 && Number.isInteger(data.usage.output_tokens) && data.usage.output_tokens >= 0
        ? { inputTokens: data.usage.input_tokens, outputTokens: data.usage.output_tokens } : null;
      const actualCost = usage ? price(usage.inputTokens, usage.outputTokens) : null;
      if (actualCost !== null) reservedUsd += actualCost - reservation;
      else { unknownUsage = true; stopped = true; }
      const result = { status: "MODEL_RETURNED", raw, usage, elapsedMs: Date.now() - started, actualCostUsd: actualCost, budgetReservationUsd: reservation, stopReason: data.stop_reason ?? null };
      await Deno.writeTextFile(new URL("requests.jsonl", out), JSON.stringify({ label, stage, call: calls, ...result }) + "\n", { append: true });
      return result;
    } catch {
      unknownUsage ||= transportStarted;
      stopped = true;
      if (!transportStarted) reservedUsd -= reservation;
      const result = { status: transportStarted ? "API_FAILED_USAGE_UNKNOWN" : "PREPARATION_FAILED_NO_CALL", raw: null, usage: null, elapsedMs: Date.now() - started, actualCostUsd: transportStarted ? null : 0, budgetReservationUsd: transportStarted ? reservation : 0 };
      await Deno.writeTextFile(new URL("requests.jsonl", out), JSON.stringify({ label, stage, call: calls, ...result }) + "\n", { append: true });
      return result;
    }
  }

  for (const mode of config.modes) for (const [caseIndex, c] of selected.entries()) for (let attempt = 1; attempt <= config.repeat; attempt++) {
    if (mode === "full-two-stage" && c.inputSurface !== "text") {
      for (const variant of ["current", "candidate"] as const) for (const arm of ["A", "B", "skip"] as const) {
        records.push({ mode, caseId: c.id, variant, arm, attempt, engineeringHead, promptVersion: BUNDLES[variant].version, settings: SETTINGS, status: "NOT_RUN_REQUIRES_ACTUAL_IMAGE", plannedModelCalls: 0, rawGeneration: null, inspection: null, usage: null, elapsedMs: null, repairPathExercised: false });
      }
      continue;
    }
    const variants: Variant[] = (caseIndex + attempt + config.seed) % 2 ? ["candidate", "current"] : ["current", "candidate"];
    for (const variant of variants) {
      const bundle = BUNDLES[variant];
      const prefix = `${mode}.${c.id}.${attempt}.${variant}`;
      let snapshot = mode === "generate-only" ? syntheticSnapshot(c) : null;
      let analysisRecord: Record<string, unknown> | null = null;
      if (mode === "full-two-stage") {
        const result = config.run ? await call(`${prefix}.analysis`, "analyze", bundle.analyze, analyzeInput(c)) : { status: "NOT_RUN_DRY", raw: null, usage: null, elapsedMs: null };
        const parsed = result.raw ? parseJsonObjectFromText(result.raw) : null;
        const wrongSurface = parsed ? detectOpenerWrongSurface(parsed, 0) : null;
        if (parsed && !wrongSurface && !hasAnalyzeChatPromptLeak(result.raw ?? "")) snapshot = buildSnapshot(c, parsed, bundle.version);
        analysisRecord = { ...result, mode, caseId: c.id, variant, promptVersion: bundle.version, engineeringHead, attempt, user: analyzeInput(c), snapshot, wrongSurface, repairPathExercised: false, validSnapshot: !!snapshot };
        await write(`${prefix}.analysis.json`, analysisRecord);
      }
      for (const arm of ["A", "B", "skip"] as const) {
        const input = snapshot ? generateInput(c, arm, snapshot) : null;
        const base = {
          key: `${prefix}.${arm}`, mode, caseId: c.id, variant, arm, attempt, engineeringHead, promptVersion: bundle.version, settings: SETTINGS,
          snapshotProvenance: mode === "generate-only" ? "synthetic_production_builder_shared_by_both_variants" : `${prefix}.analysis.json`,
          snapshot, input, snapshotSha256: snapshot ? await sha256(JSON.stringify(snapshot)) : null,
          intentGroup: intentGroup(c, arm), initialUserNote: c.initialUserNote ?? null,
          humanChecks: [...c.humanChecks, ...((c.armChecks as Record<string, string[]>)[arm] ?? [])],
          repairPathExercised: false, formatRepairCalls: 0, contentRepairCalls: 0, repairedOutput: null,
        };
        const result = !config.run ? { status: "NOT_RUN_DRY", raw: null, usage: null, elapsedMs: null }
          : input ? await call(base.key, "generate", bundle.generate, input.user)
          : { status: "NOT_RUN_INVALID_OR_MISSING_ANALYSIS", raw: null, usage: null, elapsedMs: null };
        const inspected = result.raw !== null && snapshot ? inspectGeneration(c, arm, snapshot, result.raw) : null;
        const record = { ...base, ...result, rawGeneration: result.raw, inspection: inspected, analysisStatus: analysisRecord?.status ?? "SYNTHETIC_CONTROL" };
        records.push(record);
        await write(`${base.key}.json`, record);
        if (inspected && input) for (const tier of ["free", "paid"] as const) {
          const projected = inspected.tiers[tier].projected;
          if (projected) blind.push({ key: base.key, mode, caseId: c.id, variant, arm, attempt, tier, profile: c.profileInfo, initialUserNote: c.initialUserNote ?? null, contribution: input.contribution, visibleEvidence: c.syntheticSnapshotEvidence?.profileDigest ?? null, openers: projected.openers, pick: projected.recommendedPick });
        }
      }
    }
  }
  const artifacts = blindArtifacts(blind, config.seed);
  if (config.run) {
    for (const tier of ["free", "paid"]) await Deno.writeTextFile(new URL(`blind_${tier}.md`, out), artifacts.documents[tier]);
    await write("reveal-map.json", artifacts.key);
  }
  await write("records.json", records);
  await write("manifest.json", { ...manifest, status: config.run ? "FINISHED_WITH_UNVERIFIED_QUALITY" : "DRY_RUN_NO_MODEL", finishedAt: new Date().toISOString(), modelCallsMade: calls, budgetAccountedUsd: config.run ? reservedUsd : null, usageUnknown: unknownUsage, stoppedByCapOrUnknown: stopped, blindItems: blind.length });
  const lines = [
    "# Opener 第一階段成對評測", "",
    `狀態：${config.run ? "已執行；品質待盲審" : "無模型 dry-run；不是品質結果"}`,
    `工程 HEAD：${engineeringHead}${dirty ? "（含未提交修改）" : ""}`,
    `候選版本：${BUNDLES.candidate.version}；控制版本：${BUNDLES.current.version}`,
    `情境 ${selected.length}；A/B/skip；每臂 ${config.repeat} 次。規劃呼叫：${JSON.stringify(planned)}；實際模型呼叫 ${calls}。`,
    `費用上限提案 $${config.budgetUsd}；價格${config.pricing ? "由參數提供，見 manifest" : "未核實，因此不估成 0，也不允許真跑"}。`,
    "格式／內容修正：本工具未實跑；handler scripted 回歸另附。長度只記錄，不用 15–45 字當硬門檻。",
    "N03/N04 衝突或不適用目標、N12 純限制與正常正向想法分組；失敗保留，不從品質樣本中悄悄刪除。",
    "", ...LIMITATIONS.map(value => `- ${value}`), "",
  ];
  await Deno.writeTextFile(new URL("summary.md", out), lines.join("\n"));
  console.log(JSON.stringify({ engineeringHead, cases: selected.length, plannedCalls: planned, modelCallsMade: calls, output: out.pathname, status: config.run ? "QUALITY_UNVERIFIED" : "DRY_RUN_NO_MODEL" }));
}

// Phase 3d：離線 critic 評測。對既有黑箱 artifact 的 send 案（只審選中卡）跑真的
// 第二層語意審核呼叫，存 verdict／violations／token／延遲；不重跑主分析、不動
// runtime。每案一次真呼叫會產生費用，跑前要 Eric 明確授權。
//   deno run --allow-env --allow-read --allow-write=tools/analyze-v2-blackbox/out \
//     --allow-net=api.anthropic.com tools/analyze-v2-blackbox/run_critic.ts \
//     <artifact.json> <out.json> [--model=claude-sonnet-5] [--only=a,b] [--dry-run]
// --dry-run：只組 prompt、列案數與字數、估成本，不呼叫 API（列參數給 Eric 看）。
import { CORPUS, type CorpusCase } from "./corpus.ts";
import { artifactCaseFinalResult } from "./evaluate.ts";
import {
  buildAnalyzeCriticInput,
  callClaudeJson,
} from "../../supabase/functions/analyze-chat/critic_shadow.ts";
import { candidateGuardFromFinalResult } from "../../supabase/functions/analyze-chat/phase0_observability.ts";
import {
  ANALYZE_CRITIC_VIOLATIONS,
  type AnalyzeCriticCandidate,
  type AnalyzeCriticEvidence,
  buildAnalyzeCriticPrompt,
  parseSemanticCriticUsage,
  parseSemanticCriticVerdict,
  SEMANTIC_CRITIC_MAX_TOKENS,
} from "../../supabase/functions/_shared/social/semantic_critic.ts";

export interface CriticCase {
  readonly id: string;
  readonly evidence: AnalyzeCriticEvidence;
  readonly candidate: AnalyzeCriticCandidate;
}

/// 從 artifact 一案組出 critic 輸入：語料訊息＋重建的結果（選中卡＋用到的枝）＋
/// 3c guard 碼。非 send、不在語料、重建不出來 → null。
export function criticCaseFromArtifact(
  // deno-lint-ignore no-explicit-any
  r: any,
  corpusById: ReadonlyMap<string, CorpusCase>,
): CriticCase | null {
  const id = String(r.name).replace(/#\d+$/, "");
  const spec = corpusById.get(id);
  if (!spec || r.decision?.messageDecision !== "send") return null;
  const finalResult = artifactCaseFinalResult(r);
  if (!finalResult) return null;
  const guardViolations = candidateGuardFromFinalResult(finalResult).violations
    .map((v) => v.code);
  const input = buildAnalyzeCriticInput(
    finalResult,
    spec.messages,
    guardViolations,
  );
  return input ? { id, ...input } : null;
}

if (import.meta.main) {
  const positional = Deno.args.filter((a) => !a.startsWith("--"));
  const flag = (name: string) =>
    Deno.args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
  if (positional.length < 2) {
    console.error(
      "usage: run_critic.ts <artifact.json> <out.json> [--model=…] [--only=a,b]",
    );
    Deno.exit(2);
  }
  const [artifactPath, outPath] = positional;
  const model = flag("model") ?? "claude-sonnet-5";
  const only = flag("only")?.split(",").filter(Boolean);
  const dryRun = Deno.args.includes("--dry-run");
  const artifact = JSON.parse(await Deno.readTextFile(artifactPath)) as {
    meta?: Record<string, unknown>;
    // deno-lint-ignore no-explicit-any
    results: any[];
  };
  const corpusById = new Map(CORPUS.map((c) => [c.id, c]));
  const built = artifact.results
    .map((r) => ({ r, built: criticCaseFromArtifact(r, corpusById) }))
    .filter((
      x,
    ): x is { r: (typeof artifact.results)[number]; built: CriticCase } =>
      x.built !== null && (!only || only.includes(x.built.id))
    );
  if (dryRun) {
    // 粗估：CJK 約 1 token/字，英文 JSON key 約 0.3 token/字；用 0.8 當上界。
    const promptChars = built.map(({ built: b }) =>
      buildAnalyzeCriticPrompt(b.evidence, b.candidate).length
    );
    const inputTokens = Math.round(
      promptChars.reduce((a, b) => a + b, 0) * 0.8,
    );
    const outputTokens = built.length * SEMANTIC_CRITIC_MAX_TOKENS;
    const price = model === "claude-sonnet-5"
      ? { input: 2, output: 10 }
      : { input: 0.8, output: 4 };
    for (const [i, { built: b }] of built.entries()) {
      console.error(
        `${b.id.padEnd(28)} ${b.candidate.style.padEnd(9)} guard=[${
          b.evidence.guardViolations.join(",")
        }] promptChars=${promptChars[i]}`,
      );
    }
    console.error(JSON.stringify({
      dryRun: true,
      model,
      cases: built.length,
      promptCharsTotal: promptChars.reduce((a, b) => a + b, 0),
      estInputTokens: inputTokens,
      maxOutputTokens: outputTokens,
      estCostUsdUpperBound: Number(
        ((inputTokens * price.input + outputTokens * price.output) / 1e6)
          .toFixed(3),
      ),
    }));
    Deno.exit(0);
  }
  const apiKey = (await Deno.readTextFile(
    `${Deno.env.get("HOME")}/.config/anthropic/key`,
  )).trim();
  const results = [];
  for (const { r, built: b } of built) {
    const prompt = buildAnalyzeCriticPrompt(b.evidence, b.candidate);
    const started = Date.now();
    let raw: unknown = null;
    let status = "ok";
    let error: string | undefined;
    try {
      raw = await callClaudeJson({
        model,
        prompt,
        maxTokens: SEMANTIC_CRITIC_MAX_TOKENS,
        timeoutMs: 30_000,
        apiKey,
      });
    } catch (e) {
      status = "failed";
      error = (e instanceof Error ? e.message : String(e)).slice(0, 200);
    }
    const latencyMs = Date.now() - started;
    let verdict: { verdict: string; violations: readonly string[] } | null =
      null;
    if (status === "ok") {
      try {
        verdict = parseSemanticCriticVerdict(raw, ANALYZE_CRITIC_VIOLATIONS);
      } catch {
        status = "invalid";
      }
    }
    const entry = {
      id: b.id,
      name: r.name,
      style: b.candidate.style,
      guardViolations: b.evidence.guardViolations,
      status,
      ...(error ? { error } : {}),
      verdict: verdict?.verdict ?? null,
      violations: verdict?.violations ?? null,
      usage: parseSemanticCriticUsage(raw),
      latencyMs,
      // 讓人工複核看得到 critic 看到的東西（本機檔，不進 telemetry）。
      candidate: b.candidate,
      rawText: status === "ok"
        ? null
        : JSON.stringify(raw)?.slice(0, 400) ?? null,
    };
    results.push(entry);
    console.error(
      `${entry.status.padEnd(7)} ${entry.id.padEnd(28)} ${
        entry.style.padEnd(9)
      } ${String(entry.verdict).padEnd(8)} ${
        (entry.violations ?? []).join(",")
      } ${entry.latencyMs}ms`,
    );
  }
  const tally: Record<string, number> = {};
  for (const r of results) {
    for (const v of r.violations ?? []) tally[v] = (tally[v] ?? 0) + 1;
  }
  const meta = {
    artifact: artifactPath,
    artifactCommit: artifact.meta?.commit ?? null,
    model,
    generatedAt: new Date().toISOString(),
    cases: results.length,
    rewrite: results.filter((r) => r.verdict === "rewrite").length,
    invalid: results.filter((r) => r.status !== "ok").length,
    violations: tally,
    inputTokens: results.reduce((s, r) => s + (r.usage?.inputTokens ?? 0), 0),
    outputTokens: results.reduce((s, r) => s + (r.usage?.outputTokens ?? 0), 0),
  };
  await Deno.writeTextFile(outPath, JSON.stringify({ meta, results }, null, 2));
  console.error(JSON.stringify(meta));
}

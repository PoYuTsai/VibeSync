// 教練「關於我」成對評測：產生回答（規格 PR-6；Bruce 2026-10-20）。
// 兩臂都呼叫正式的 runCoachChat：base＝改前（git archive 取出 --base-ref 那一版），
// cand＝目前工作樹。同一個案例、同一次重複，兩臂送同一份請求。預設乾跑：只組提示詞、
// 估費用，不打模型、不讀金鑰、不連網。用法與守門見 README.md。

import {
  type Arm,
  ARMS,
  CASES,
  createOutDir,
  CRITIC_MAX_TOKENS,
  estimateRuns,
  type EvalCase,
  GENERATION_MAX_TOKENS,
  GENERATION_MODEL,
  git,
  type Group,
  INITIAL_TOKENS_PER_CHAR,
  materializeRef,
  NetworkGate,
  type Options,
  PaidCaller,
  parseOptions,
  sha256Hex,
} from "./lib.ts";

type CoachRequest = Record<string, unknown>;
type CoachResult = { status: number; body: Record<string, unknown> };

export type ArmModules = {
  runCoachChat: (
    input: Record<string, unknown>,
    deps: Record<string, unknown>,
  ) => Promise<CoachResult>;
  callClaudeAPI: (args: Record<string, unknown>) => Promise<unknown>;
  buildCoachChatPrompt: (request: CoachRequest, now?: Date) => string;
  buildSemanticCriticPrompt: (
    request: CoachRequest,
    card: Record<string, unknown>,
  ) => string;
  parseRequest: (raw: unknown) => CoachRequest;
};

/** 載入某一版的 coach-chat（root 底下要有 supabase/functions）。 */
export async function loadArm(root: URL): Promise<ArmModules> {
  const dir = new URL("supabase/functions/coach-chat/", root);
  const load = (name: string) =>
    import(new URL(name, dir).href) as Promise<Record<string, unknown>>;
  const [generation, prompts, critic, schemas] = await Promise.all([
    load("generation.ts"),
    load("prompts.ts"),
    load("semantic_critic.ts"),
    load("schemas.ts"),
  ]);
  const schema = schemas.RequestSchema as { parse: (raw: unknown) => unknown };
  return {
    runCoachChat: generation.runCoachChat as ArmModules["runCoachChat"],
    callClaudeAPI: generation.callClaudeAPI as ArmModules["callClaudeAPI"],
    buildCoachChatPrompt: prompts
      .buildCoachChatPrompt as ArmModules["buildCoachChatPrompt"],
    buildSemanticCriticPrompt: critic
      .buildSemanticCriticPrompt as ArmModules["buildSemanticCriticPrompt"],
    parseRequest: (raw) => schema.parse(raw) as CoachRequest,
  };
}

/** 估審稿 input 用：每個欄位都到上限的卡片（ResponseCardSchema 的 max）。 */
export const LONGEST_CARD: Record<string, unknown> = {
  responseType: "coachAnswer",
  mode: "reply",
  headline: "字".repeat(32),
  answer: "字".repeat(360),
  userTruth: "字".repeat(120),
  userState: "字".repeat(100),
  frictionType: "unclearIntent",
  nextStep: "字".repeat(100),
  suggestedLine: "字".repeat(160),
  rewriteDecision: "light_edit",
  rewriteReason: "字".repeat(100),
  boundaryReminder: "字".repeat(100),
  needsReflection: true,
  reflectionQuestion: "字".repeat(90),
};

export type PlannedRun = {
  key: string;
  caseId: string;
  group: Group;
  attempt: number;
  arm: Arm;
  request: CoachRequest;
  generationPrompt: string;
  criticChars: number;
};

/** 每案例 × 每次重複 × 選定的臂。請求先過該臂的正式 RequestSchema。 */
export function buildPlan(
  cases: readonly EvalCase[],
  repeat: number,
  arms: readonly Arm[],
  modules: Partial<Record<Arm, ArmModules>>,
): PlannedRun[] {
  const plan: PlannedRun[] = [];
  for (const c of cases) {
    for (let attempt = 1; attempt <= repeat; attempt++) {
      for (const arm of arms) {
        const m = modules[arm];
        if (!m) throw new Error(`沒有 ${arm} 臂的程式`);
        const request = m.parseRequest(c.request);
        plan.push({
          key: `${c.id}.${attempt}.${arm}`,
          caseId: c.id,
          group: c.group,
          attempt,
          arm,
          request,
          generationPrompt: m.buildCoachChatPrompt(request),
          criticChars: m.buildSemanticCriticPrompt(request, LONGEST_CARD).length,
        });
      }
    }
  }
  return plan;
}

/** 同一案例兩臂的生成提示詞差在哪幾行（給審查看改動是不是只有預期的字）。 */
export function promptLineDiff(base: string, cand: string): {
  identical: boolean;
  onlyBase: string[];
  onlyCand: string[];
} {
  const a = base.split("\n");
  const b = cand.split("\n");
  const inB = new Set(b);
  const inA = new Set(a);
  return {
    identical: base === cand,
    onlyBase: a.filter((line) => !inB.has(line)),
    onlyCand: b.filter((line) => !inA.has(line)),
  };
}

export type RunRecord = {
  key: string;
  caseId: string;
  group: Group;
  attempt: number;
  arm: Arm;
  status:
    | "OK"
    | "FALLBACK"
    | "HTTP_ERROR"
    | "STOPPED_BUDGET"
    | "NOT_RUN_CAP_OR_STOP";
  httpStatus: number | null;
  card: Record<string, unknown> | null;
  events: string[];
  error?: string;
};

export type CoachLogEntry = { event: string; data?: Record<string, unknown> };

/** 把一次 runCoachChat 的結果整理成紀錄。備援卡、預算停下都不進盲比。 */
export function classifyRun(
  planned: PlannedRun,
  result: CoachResult | null,
  logs: readonly CoachLogEntry[],
  stoppedDuringRun: boolean,
  error?: string,
): RunRecord {
  const base = {
    key: planned.key,
    caseId: planned.caseId,
    group: planned.group,
    attempt: planned.attempt,
    arm: planned.arm,
    events: logs.map((entry) => entry.event),
  };
  if (stoppedDuringRun) {
    return {
      ...base,
      status: "STOPPED_BUDGET",
      httpStatus: result?.status ?? null,
      card: null,
      ...(error ? { error } : {}),
    };
  }
  if (result === null || result.status !== 200) {
    return {
      ...base,
      status: "HTTP_ERROR",
      httpStatus: result?.status ?? null,
      card: null,
      ...(error ? { error } : {}),
    };
  }
  const card = (result.body.card ?? null) as Record<string, unknown> | null;
  const fallback = logs.some((entry) =>
    entry.event === "coach_chat_fallback_used"
  );
  return {
    ...base,
    status: fallback || card === null ? "FALLBACK" : "OK",
    httpStatus: 200,
    card,
  };
}

async function main() {
  const options: Options = parseOptions(Deno.args);
  const gate = new NetworkGate();
  // 網路閘要在載入任何會呼叫模型的模組之前裝好。
  gate.install();

  const toolDir = new URL("./", import.meta.url);
  const repoRoot = new URL("../../", toolDir);
  const candSha = await git(["rev-parse", "HEAD"]);
  const dirty =
    (await git(["status", "--porcelain", "--untracked-files=no"])).length > 0;
  if (options.run && dirty) {
    throw new Error("追蹤檔有未提交修改，真跑的結果要能對回 HEAD：先 commit");
  }

  const modules: Partial<Record<Arm, ArmModules>> = {};
  let baseSha: string | null = null;
  if (options.arms.includes("base")) {
    const base = await materializeRef(options.baseRef);
    baseSha = base.sha;
    modules.base = await loadArm(base.root);
  }
  if (options.arms.includes("cand")) modules.cand = await loadArm(repoRoot);

  const cases = options.only
    ? CASES.filter((c) => options.only!.includes(c.id))
    : CASES;
  const plan = buildPlan(cases, options.repeat, options.arms, modules);
  const estimate = estimateRuns(plan.map((p) => ({
    generationChars: p.generationPrompt.length,
    criticChars: p.criticChars,
  })));

  const out = await createOutDir(toolDir, options.tag);
  const casesText = await Deno.readTextFile(new URL("cases.json", toolDir));
  const manifest = {
    tool: "coach-about-me-eval",
    tag: options.tag,
    createdAt: new Date().toISOString(),
    mode: options.run ? "run" : "dry-run",
    candHead: candSha,
    candDirty: dirty,
    baseRef: options.baseRef,
    baseSha,
    arms: options.arms,
    repeat: options.repeat,
    cases: cases.map((c) => c.id),
    casesSha256: await sha256Hex(casesText),
    model: GENERATION_MODEL,
    generationMaxTokens: GENERATION_MAX_TOKENS,
    criticMaxTokens: CRITIC_MAX_TOKENS,
    tokensPerCharForEstimate: INITIAL_TOKENS_PER_CHAR,
    estimate,
    maxCalls: options.maxCalls,
    budgetUsd: options.budgetUsd,
  };
  await Deno.writeTextFile(
    new URL("manifest.json", out),
    JSON.stringify(manifest, null, 2),
  );
  await Deno.writeTextFile(
    new URL("prompts.json", out),
    JSON.stringify(
      plan.map((p) => ({
        key: p.key,
        arm: p.arm,
        caseId: p.caseId,
        promptChars: p.generationPrompt.length,
        prompt: p.generationPrompt,
      })),
      null,
      2,
    ),
  );
  if (modules.base && modules.cand) {
    const diffs = cases.map((c) => {
      const b = plan.find((p) => p.caseId === c.id && p.arm === "base")!;
      const k = plan.find((p) => p.caseId === c.id && p.arm === "cand")!;
      return { caseId: c.id, ...promptLineDiff(b.generationPrompt, k.generationPrompt) };
    });
    await Deno.writeTextFile(
      new URL("prompt-diff.json", out),
      JSON.stringify(diffs, null, 2),
    );
  }

  console.log(
    `${options.run ? "真跑" : "乾跑"}：${plan.length} 次 runCoachChat（${cases.length} 案例 × ${options.repeat} 次 × ${options.arms.length} 臂）`,
  );
  console.log(
    `估算：一般 ${estimate.typicalCalls} 次呼叫約 US$${estimate.typicalUsd.toFixed(2)}；最壞 ${estimate.worstCalls} 次約 US$${estimate.worstUsd.toFixed(2)}`,
  );
  if (!options.run) {
    console.log(`輸出：tools/coach-about-me-eval/out/${options.tag}/（manifest、prompts、prompt-diff）`);
    return;
  }

  const apiKey =
    (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`))
      .trim();
  const requestsLog = new URL("requests.jsonl", out);
  const caller = new PaidCaller({
    maxCalls: options.maxCalls!,
    budgetUsd: options.budgetUsd!,
    gate,
    log: (row) =>
      Deno.writeTextFileSync(requestsLog, JSON.stringify(row) + "\n", {
        append: true,
      }),
  });
  const records: RunRecord[] = [];
  const recordsPath = new URL("records.json", out);
  for (const planned of plan) {
    if (caller.stopped !== null) {
      records.push({
        key: planned.key,
        caseId: planned.caseId,
        group: planned.group,
        attempt: planned.attempt,
        arm: planned.arm,
        status: "NOT_RUN_CAP_OR_STOP",
        httpStatus: null,
        card: null,
        events: [],
      });
      continue;
    }
    const m = modules[planned.arm]!;
    const logs: CoachLogEntry[] = [];
    const logger = {
      info: (event: string, data?: Record<string, unknown>) =>
        logs.push({ event, data }),
      warn: (event: string, data?: Record<string, unknown>) =>
        logs.push({ event, data }),
    };
    const stoppedBefore = caller.stopped;
    let result: CoachResult | null = null;
    let error: string | undefined;
    try {
      result = await m.runCoachChat(
        {
          userId: "coach-about-me-eval",
          request: planned.request,
          tier: "essential",
          accountIsTest: true,
          apiKey,
        },
        {
          callClaude: caller.wrap(planned.key, "generate", m.callClaudeAPI),
          callSemanticCritic: caller.wrap(
            planned.key,
            "critic",
            m.callClaudeAPI,
          ),
          deductCredit: () => Promise.resolve(),
          logger,
          now: () => Date.now(),
        },
      );
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    }
    records.push(
      classifyRun(
        planned,
        result,
        logs,
        stoppedBefore === null && caller.stopped !== null,
        error,
      ),
    );
    await Deno.writeTextFile(recordsPath, JSON.stringify(records, null, 2));
  }
  const summary = {
    calls: caller.calls,
    spentUsd: caller.spentUsd,
    stopped: caller.stopped,
    overReserveCount: caller.overReserveCount,
    tokensPerChar: caller.tokensPerChar,
    byStatus: Object.fromEntries(
      ["OK", "FALLBACK", "HTTP_ERROR", "STOPPED_BUDGET", "NOT_RUN_CAP_OR_STOP"]
        .map((s) => [s, records.filter((r) => r.status === s).length]),
    ),
    byArm: Object.fromEntries(
      ARMS.map((arm) => [
        arm,
        records.filter((r) => r.arm === arm && r.status === "OK").length,
      ]),
    ),
  };
  await Deno.writeTextFile(
    new URL("run-summary.json", out),
    JSON.stringify(summary, null, 2),
  );
  console.log(
    `完成：${caller.calls} 次呼叫，實付約 US$${caller.spentUsd.toFixed(3)}；${caller.stopped ? `已停：${caller.stopped}` : "沒有觸發上限"}`,
  );
}

if (import.meta.main) {
  await main();
}

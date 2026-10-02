// 本機黑箱：真模型、v2 契約（noSendDecisions）、essential 五風格。
// 走 handleAnalyzeStream 本體（system prompt＋knowledge atoms＋divergence plan
// 全是 production 程式碼），只 stub DB store 與 supabase telemetry。
// 2026-10-02 起是 A/B 工具：--arms 臂（ab.ts）、每案交錯、預設 dry-run；
// 真呼叫要 --run --confirm-paid --max-calls --budget-usd --tag 全帶（見 README）。
import {
  applyArmOverride,
  applySseEvent,
  type ArmId,
  ARMS,
  type ArmSpec,
  buildBlindSheet,
  type CallRecord,
  countTokensRequestBody,
  estimatePlan,
  estimateTokens,
  JUDGE_MODEL,
  newProviderCall,
  paidGuardError,
  parseArms,
  parsePaidFlags,
  parseRepeat,
  planCalls,
  type PlannedCall,
  preflightPaidCall,
  type ProviderCall,
  renderSummaryMd,
  settleReservedSpend,
  summarizeArms,
} from "./ab.ts";
import {
  CORPUS,
  corpusMessages,
  type Msg,
  REFUSAL_PROBE_IDS,
} from "./corpus.ts";

const ROOT =
  new URL("../../supabase/functions/analyze-chat", import.meta.url).pathname;
const flag = (name: string) =>
  Deno.args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
// --refusal-probe：只跑 C 臂（production 5.5）、只跑曖昧／邀約案（corpus.ts REFUSAL_PROBE_IDS）。
const PROBE = Deno.args.includes("--refusal-probe");
const ARM_IDS: ArmId[] = PROBE ? ["C"] : parseArms(flag("arms"));
// --repeat=N 或 --repeat=A:2,B:2,C:1；--only=a,b 只跑指定案。
const REPEAT = parseRepeat(flag("repeat"), ARM_IDS);
const ONLY = PROBE
  ? [...REFUSAL_PROBE_IDS]
  : flag("only")?.split(",").filter(Boolean) ?? null;
const TAG = flag("tag");
const PAID = parsePaidFlags(Deno.args);

const realFetch = globalThis.fetch;
/// 目前這一案的臂與它實際送出的 provider 呼叫；null＝不在計畫內，一律不放行。
let active: { arm: ArmSpec; calls: ProviderCall[] } | null = null;
let spentUsd = 0;
let providerCallCount = 0;
let guardTripped = false;

/// 原樣轉送 SSE，順路記 stop_reason／stop_details／usage／耗時；串流正常讀完時
/// 呼叫 onEnd（被取消就不呼叫，預留的上界留在 spent 裡）。
function tapSse(
  call: ProviderCall,
  started: number,
  onEnd: () => void,
): TransformStream<Uint8Array, Uint8Array> {
  const decoder = new TextDecoder();
  let buffer = "";
  const scan = (final: boolean) => {
    const lines = buffer.split("\n");
    buffer = final ? "" : lines.pop() ?? "";
    for (const line of lines) {
      if (!line.startsWith("data:")) continue;
      try {
        applySseEvent(call, JSON.parse(line.slice(5).trim()));
      } catch { /* 非 JSON data 行（例如 [DONE]）：略過 */ }
    }
  };
  return new TransformStream({
    transform(chunk, controller) {
      buffer += decoder.decode(chunk, { stream: true });
      scan(false);
      call.providerMs = Date.now() - started;
      controller.enqueue(chunk);
    },
    flush() {
      buffer += decoder.decode();
      scan(true);
      call.providerMs = Date.now() - started;
      onEnd();
    },
  });
}

// Anthropic：只在計畫內、付費閘內放行，C 臂改寫 body；其他 fetch（logAiCall 寫
// supabase）只記 body，不外送。
let sideBodies: string[] = [];
globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = typeof input === "string"
    ? input
    : input instanceof URL
    ? input.href
    : input.url;
  if (url.startsWith("https://api.anthropic.com/")) {
    if (!active) throw new TypeError("blackbox: Anthropic call outside plan");
    const body = applyArmOverride(JSON.parse(String(init?.body)), active.arm);
    // 先打 count_tokens（免費）＋餘量預留上界：斷線、error、usage 不全時就以上界計。
    // 查不到輸入 token 或超出次數／預算就不發付費請求。
    const pre = await preflightPaidCall({
      countTokens: async () => {
        const r = await realFetch(
          "https://api.anthropic.com/v1/messages/count_tokens",
          {
            method: "POST",
            headers: init?.headers,
            body: JSON.stringify(countTokensRequestBody(body)),
          },
        );
        return { status: r.status, json: await r.json().catch(() => null) };
      },
      model: String(body.model),
      maxTokens: Number(body.max_tokens),
      spentUsd,
      callCount: providerCallCount,
      flags: PAID,
    });
    if (!pre.ok) {
      guardTripped = true;
      throw new TypeError(`blackbox paid guard: ${pre.reason}`);
    }
    const upper = pre.upperUsd;
    providerCallCount += 1;
    spentUsd = pre.spentUsd;
    const call = newProviderCall(body);
    active.calls.push(call);
    const started = Date.now();
    const res = await realFetch(input, { ...init, body: JSON.stringify(body) });
    call.httpStatus = res.status;
    if (!res.ok || !res.body) {
      call.error = (await res.clone().text().catch(() => "")).slice(0, 400);
      return res;
    }
    const settle = () => {
      spentUsd = settleReservedSpend(spentUsd, upper, call);
    };
    return new Response(res.body.pipeThrough(tapSse(call, started, settle)), {
      status: res.status,
      headers: res.headers,
    });
  }
  if (typeof init?.body === "string") sideBodies.push(init.body);
  return new Response("{}", {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}) as typeof fetch;

const { handleAnalyzeStream } = await import(
  `${ROOT}/analyze_stream_handler.ts`
);
const { markLatestAnalysisFragment } = await import(`${ROOT}/stream_prompt.ts`);
const { STREAM_STYLES } = await import(`${ROOT}/stream_events.ts`);
const { streamAnalyzeMaxTokensForStyleCount } = await import(
  `${ROOT}/stream_budget.ts`
);
const { callClaudeStreaming } = await import(`${ROOT}/streaming_fallback.ts`);
const { buildAnalyzeStreamSystemPrompt } = await import(
  `${ROOT}/analyze_prompt.ts`
);
const { selectAnalyzeSocialKnowledge } = await import(
  `${ROOT}/knowledge_adapter.ts`
);
const { ANALYZE_CRITIC_SHADOW } = await import(`${ROOT}/critic_shadow.ts`);
// 結果檔綁定：repo commit、v2 五風格 system prompt 雜湊、模型、時間，讓 artifact
// 自己就能證明對應哪個快照（審查 P2）。
async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
async function git(args: string[]): Promise<string> {
  try {
    const out = await new Deno.Command("git", {
      args,
      cwd: new URL("../..", import.meta.url).pathname,
      stdout: "piped",
    }).output();
    return new TextDecoder().decode(out.stdout).trim();
  } catch {
    return "unknown";
  }
}
/// 每次真呼叫實際送出的 system prompt 雜湊與 request 模型（不是重建、不是常數）。
const sentRequests: { model: string; systemSha256: string }[] = [];
const CASES: Record<string, Msg[]> = corpusMessages();

function latestIncomingRunStart(messages: Msg[]): number {
  let i = messages.length - 1;
  if (messages[i]?.isFromMe) return messages.length - 1;
  while (i > 0 && !messages[i - 1].isFromMe) i--;
  return i;
}

function buildUserPrompt(messages: Msg[]): string {
  const lines = messages.map((m) =>
    `${m.isFromMe ? "Me" : "Her"}: ${m.content}`
  );
  return [
    "Analyze the conversation below and return the structured JSON response.",
    "## Recent Conversation",
    markLatestAnalysisFragment(lines, latestIncomingRunStart(messages)),
  ].join("\n\n");
}

function extractTokenUsage(bodies: string[]): Record<string, number> | null {
  for (const body of bodies) {
    try {
      const parsed = JSON.parse(body);
      const row = Array.isArray(parsed) ? parsed[0] : parsed;
      if (!row || typeof row !== "object") continue;
      const out: Record<string, number> = {};
      for (const [key, value] of Object.entries(row)) {
        if (/token/i.test(key) && typeof value === "number") out[key] = value;
      }
      if (Object.keys(out).length > 0) return out;
    } catch { /* not json */ }
  }
  return null;
}

async function runCase(
  name: string,
  messages: Msg[],
  model: string,
  apiKey: string,
) {
  const logs: unknown[][] = [];
  const origLog = console.log;
  console.log = (...args: unknown[]) => logs.push(args);
  let markDoneFinal: Record<string, unknown> | undefined;
  let charged = false;
  let rawText = "";
  const run = {
    id: `run-${name}`,
    status: "pending",
    retry_count: 0,
    conversation_hash: "h",
    final_result: null,
  };
  const styles = [...STREAM_STYLES];
  const deps = {
    store: {
      getRun: () => Promise.resolve(run),
      reserveRetry: () => Promise.resolve(run),
      createPendingRun: () => Promise.resolve(run),
      chargeRun: () => {
        charged = true;
        return Promise.resolve();
      },
      markDone: (args: { finalResult: Record<string, unknown> }) => {
        markDoneFinal = args.finalResult;
        return Promise.resolve();
      },
      markFailed: () => Promise.resolve({ ...run, status: "failed" }),
    },
    userId: "00000000-0000-4000-8000-0000000000bb",
    analysisRunId: null,
    requestType: "analyze",
    analyzeMode: "normal",
    expectedTier: "essential",
    effectiveTier: "essential",
    accountIsTest: true,
    allowedFeatures: styles,
    noSendDecisions: true,
    quotaUsage: {
      shouldChargeQuota: true,
      quotaReason: "analyze_message_based",
      quotaUnit: "messages",
      chargedMessageCount: 1,
      estimatedMessageCount: 1,
    },
    monthlyLimit: 999,
    dailyLimit: 999,
    subMonthlyUsed: 0,
    subDailyUsed: 0,
    selectedModel: model,
    userMessageContent: buildUserPrompt(messages),
    requestObservability: {},
    messages,
    hashInput: {
      messages,
      userDraft: undefined,
      partnerSummary: undefined,
      sessionContext: undefined,
      conversationSummary: undefined,
      effectiveStyleContext: undefined,
      knownContactName: undefined,
      analysisFragmentStartIndex: latestIncomingRunStart(messages),
    },
    claudeApiKey: apiKey,
    supabaseUrl: "http://stub.invalid",
    supabaseServiceKey: "stub",
    callModel: (async (
      request: Parameters<typeof callClaudeStreaming>[0] & {
        model: string;
        system: string;
      },
      key: string,
      options: Record<string, unknown> = {},
    ) => {
      sentRequests.push({
        model: request.model,
        systemSha256: await sha256Hex(request.system),
      });
      // 備援鏈關閉：每次只打這一臂的模型，失敗就記失敗，不讓 4.6 混進來。
      const result = await callClaudeStreaming(request, key, {
        ...options,
        allowModelFallback: false,
      });
      const source = result.textStream;
      async function* tee(): AsyncGenerator<string> {
        for await (const chunk of source) {
          rawText += chunk;
          yield chunk;
        }
      }
      return { ...result, textStream: tee() };
    }) as typeof callClaudeStreaming,
    // critic 影子關閉：評審另用 run_critic.ts 固定 Sonnet 5 跑。
    criticShadow: { ...ANALYZE_CRITIC_SHADOW, enabled: false },
  };
  sideBodies = [];
  const started = Date.now();
  const startedAt = new Date().toISOString();
  let text = "";
  let status = 0;
  const eventTimes: { type: string; style?: string; atMs: number }[] = [];
  try {
    const response = await handleAnalyzeStream(deps as never);
    status = response.status;
    // 逐行讀 client NDJSON 並記到達時間：量「第一張卡／選中卡／全部完成」各在第幾秒。
    const reader = response.body?.getReader();
    if (reader) {
      const decoder = new TextDecoder();
      let buffer = "";
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let newline: number;
        while ((newline = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, newline);
          buffer = buffer.slice(newline + 1);
          text += line + "\n";
          if (!line.trim()) continue;
          try {
            const parsed = JSON.parse(line);
            eventTimes.push({
              type: String(parsed.type ?? "?"),
              ...(typeof parsed.style === "string"
                ? { style: parsed.style }
                : {}),
              atMs: Date.now() - started,
            });
          } catch { /* unparseable line：不計時 */ }
        }
      }
      text += buffer;
    } else {
      text = await response.text();
    }
  } finally {
    console.log = origLog;
  }
  const events = text.split("\n").filter((l) => l.trim()).map((l) => {
    try {
      return JSON.parse(l);
    } catch {
      return { type: "UNPARSEABLE", raw: l.slice(0, 120) };
    }
  });
  const find = (name: string) =>
    logs.find((e) => e[0] === `[analyze-chat] ${name}`)?.[1] as
      | Record<string, unknown>
      | undefined;
  const decision = events.find((e) => e.type === "analysis.decision");
  const done = events.find((e) => e.type === "analysis.done");
  const options = events.filter((e) => e.type === "analysis.reply_option");
  const maxTokens = streamAnalyzeMaxTokensForStyleCount(styles.length, {
    divergencePlan: true,
  });
  const completed = find("stream_completed") ?? find("stream_done") ?? {};
  const selectedStyle = typeof decision?.selectedStyle === "string"
    ? decision.selectedStyle
    : null;
  const at = (pred: (e: { type: string; style?: string }) => boolean) =>
    eventTimes.find(pred)?.atMs ?? null;
  const optionTimes = eventTimes.filter((e) =>
    e.type === "analysis.reply_option"
  );
  const milestonesMs = {
    started: at((e) => e.type === "analysis.started"),
    inventory: at((e) => e.type === "analysis.inventory"),
    decision: at((e) => e.type === "analysis.decision"),
    recommendation: at((e) => e.type === "analysis.recommendation"),
    firstCard: optionTimes[0]?.atMs ?? null,
    selectedCard: selectedStyle
      ? at((e) =>
        e.type === "analysis.reply_option" && e.style === selectedStyle
      )
      : null,
    allCards: optionTimes.length > 0 ? optionTimes.at(-1)!.atMs : null,
    done: at((e) => e.type === "analysis.done"),
  };
  // 模型原始輸出的字元去向：按事件 type，再看 reply_option 內欄位（不存內容）。
  const rawTypeChars: Record<string, number> = {};
  const rawOptionFieldChars: Record<string, number> = {};
  // 模型 done.finalResult 各欄位大小（不存內容）：看它重寫了什麼、伺服器用不用。
  const rawDoneFieldChars: Record<string, number> = {};
  for (const l of rawText.split("\n")) {
    if (!l.trim()) continue;
    let parsed: Record<string, unknown> | null = null;
    try {
      parsed = JSON.parse(l);
    } catch {
      rawTypeChars["UNPARSEABLE"] = (rawTypeChars["UNPARSEABLE"] ?? 0) +
        l.length;
      continue;
    }
    const t = String(parsed?.type ?? "?");
    rawTypeChars[t] = (rawTypeChars[t] ?? 0) + l.length;
    if (t === "analysis.done" && parsed) {
      const fr = parsed.finalResult;
      if (fr && typeof fr === "object") {
        for (const [k, v] of Object.entries(fr as Record<string, unknown>)) {
          rawDoneFieldChars[k] = (rawDoneFieldChars[k] ?? 0) +
            JSON.stringify(v).length;
        }
      }
    }
    if (t === "analysis.reply_option" && parsed) {
      for (const [k, v] of Object.entries(parsed)) {
        if (k === "segments" && Array.isArray(v)) {
          for (const seg of v) {
            for (const [sk, sv] of Object.entries(seg ?? {})) {
              const key = `segment.${sk}`;
              rawOptionFieldChars[key] = (rawOptionFieldChars[key] ?? 0) +
                JSON.stringify(sv).length;
            }
          }
        } else {
          rawOptionFieldChars[k] = (rawOptionFieldChars[k] ?? 0) +
            JSON.stringify(v).length;
        }
      }
    }
  }
  return {
    milestonesMs,
    eventTimes,
    rawChars: rawText.length,
    rawTypeChars,
    rawOptionFieldChars,
    rawDoneFieldChars,
    name,
    startedAt,
    sentRequests: sentRequests.splice(0),
    status,
    elapsedMs: Date.now() - started,
    charged,
    eventTypes: events.map((e) => e.type),
    decision: decision
      ? {
        messageDecision: decision.messageDecision,
        replyMode: decision.replyMode,
        selectedStyle: decision.selectedStyle,
        reason: decision.reason,
      }
      : null,
    replyOptions: options.map((o) => ({ style: o.style, message: o.message })),
    doneKeys: done ? Object.keys(done.finalResult ?? {}).sort() : null,
    clientLeak: {
      divergencePlanEvent: events.some((e) =>
        e.type === "analysis.divergence_plan"
      ),
      divergenceInDone: !!done?.finalResult?.analysisDivergencePlan,
      // 計畫本文欄位名；linkage 的 divergencePlanRepairs 等 id／enum 不算外洩。
      textMentionsPlan: text.includes("threadFrame") ||
        text.includes("branchPool") || text.includes("associationPath"),
    },
    server: {
      markDoneHasPlan: !!markDoneFinal?.analysisDivergencePlan,
      plan: markDoneFinal?.analysisDivergencePlan ?? null,
      linkage: markDoneFinal?.analysisEvidenceLinkage ?? null,
      decisionV2: markDoneFinal?.analysisDecisionV2 ?? null,
    },
    telemetry: {
      knowledge: find("stream_knowledge_selected"),
      phase0: find("stream_phase0_observability"),
      completedKeys: Object.keys(completed),
      usage: extractTokenUsage(sideBodies),
      maxTokens,
    },
    logNames: [...new Set(logs.map((e) => String(e[0])))],
    // 完整 client NDJSON：外洩判定要能被獨立複核。
    clientText: text,
    // 模型原始 JSONL（評審 run_critic 靠它重建選中卡）。
    rawLines: rawText.split("\n").filter((l) => l.trim()).map((l) => {
      try {
        const parsed = JSON.parse(l);
        return parsed.type === "analysis.divergence_plan" ||
            parsed.type === "analysis.reply_option" ||
            parsed.type === "analysis.decision" ||
            // 3c：盤點球留全文，evaluate 才能離線重跑球面 gates。
            parsed.type === "analysis.inventory"
          ? parsed
          : { type: parsed.type };
      } catch {
        return { type: "UNPARSEABLE", raw: l };
      }
    }),
  };
}

function promptTokens(messages: Msg[]) {
  const atoms = selectAnalyzeSocialKnowledge({
    messages,
    previousStage: undefined,
    userDraft: undefined,
    conversationSummary: undefined,
    effectiveStyleContext: undefined,
  });
  const system = buildAnalyzeStreamSystemPrompt([...STREAM_STYLES], {
    noSendDecisions: true,
    // deno-lint-ignore no-explicit-any
    situationKnowledge: atoms.map((a: any) => a.guidance),
    divergencePlan: true,
  });
  return {
    system: estimateTokens(system),
    user: estimateTokens(buildUserPrompt(messages)),
  };
}

const unknownIds = (ONLY ?? []).filter((id) => !CASES[id]);
if (unknownIds.length > 0) {
  console.error(`unknown case ids: ${unknownIds.join(",")}`);
  Deno.exit(2);
}
const caseIds = CORPUS.map((c) => c.id).filter((id) =>
  !ONLY || ONLY.includes(id)
);
const plan: PlannedCall[] = planCalls(caseIds, ARM_IDS, REPEAT);
const baseMaxTokens = streamAnalyzeMaxTokensForStyleCount(
  STREAM_STYLES.length,
  { divergencePlan: true },
);
const estimate = estimatePlan(
  plan,
  Object.fromEntries(caseIds.map((id) => [id, promptTokens(CASES[id])])),
  baseMaxTokens,
);
for (const id of caseIds) {
  console.log(
    `${id.padEnd(28)} ${
      plan.filter((c) => c.caseId === id).map((c) => `${c.arm}${c.rep}`)
        .join(" ")
    }`,
  );
}
const usd = (n: number) => Number(n.toFixed(2));
console.log(JSON.stringify(
  {
    probe: PROBE,
    arms: Object.fromEntries(ARM_IDS.map((a) => [a, ARMS[a]])),
    repeat: REPEAT,
    calls: estimate.calls,
    perArm: Object.fromEntries(
      Object.entries(estimate.perArm).map((
        [a, v],
      ) => [a, { calls: v.calls, usd: usd(v.usd) }]),
    ),
    baseMaxTokens,
    mainUsd: usd(estimate.mainUsd),
    mainNoCacheUsd: usd(estimate.mainNoCacheUsd),
    judge: {
      model: JUDGE_MODEL,
      calls: estimate.judgeCalls,
      usd: usd(estimate.judgeUsd),
    },
    totalUsd: usd(estimate.totalUsd),
  },
  null,
  2,
));
const refusal = paidGuardError(PAID, plan.length, estimate.mainUsd);
if (refusal) {
  console.error(refusal);
  Deno.exit(PAID.run ? 2 : 0);
}
if (!TAG || !/^\w[\w.-]*$/.test(TAG)) {
  console.error("拒絕：真呼叫要 --tag=<名稱>（英數、. _ -）");
  Deno.exit(2);
}
const outDir = new URL(`./out/${TAG}/`, import.meta.url).pathname;
try {
  await Deno.mkdir(outDir);
} catch (error) {
  if (!(error instanceof Deno.errors.AlreadyExists)) throw error;
  console.error(`拒絕：${outDir} 已存在，不覆寫`);
  Deno.exit(2);
}
const apiKey =
  (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`))
    .trim();

const meta = {
  tag: TAG,
  commit: await git(["rev-parse", "HEAD"]),
  tree: await git(["rev-parse", "HEAD^{tree}"]),
  worktreeDirty: (await git(["status", "--porcelain"])) !== "",
  // 每案實際送出的 model／system prompt 雜湊在 results[].sentRequests；實際
  // thinking／effort／max_tokens 在 records[].providerCalls[].sent。
  v2SystemPromptSha256Rebuilt: await sha256Hex(
    buildAnalyzeStreamSystemPrompt([...STREAM_STYLES], {
      noSendDecisions: true,
      situationKnowledge: [],
      divergencePlan: true,
    }),
  ),
  generatedAt: new Date().toISOString(),
  args: Deno.args,
  probe: PROBE,
  arms: Object.fromEntries(ARM_IDS.map((a) => [a, ARMS[a]])),
  repeat: REPEAT,
  allowModelFallback: false,
  judgeModel: JUDGE_MODEL,
  estimate,
  maxCalls: PAID.maxCalls,
  budgetUsd: PAID.budgetUsd,
};
const records: CallRecord[] = [];
for (const [i, call] of plan.entries()) {
  if (guardTripped) break;
  const arm = ARMS[call.arm];
  active = { arm, calls: [] };
  const result = await runCase(
    `${call.caseId}#${call.rep}`,
    CASES[call.caseId],
    arm.model,
    apiKey,
  );
  const calls = active.calls;
  active = null;
  // spentUsd 已在 fetch 層逐次預留／結算；這裡只記 provider 回報的實際費用。
  const costUsd = calls.reduce((s, c) => s + c.costUsd, 0);
  records.push({
    arm: call.arm,
    caseId: call.caseId,
    rep: call.rep,
    model: arm.model,
    latencyMs: result.elapsedMs,
    costUsd,
    providerCalls: calls,
    result,
  });
  // 每案寫一次：中途壞掉也留得住已付費的結果。
  await Deno.writeTextFile(
    `${outDir}records.json`,
    JSON.stringify({ meta, records }, null, 2),
  );
  console.error(
    `${i + 1}/${plan.length} ${call.arm} ${call.caseId}#${call.rep} stop=${
      calls.map((c) => c.stopReason ?? c.httpStatus ?? c.error).join(",") ||
      "-"
    } ${(result.elapsedMs / 1000).toFixed(1)}s $${costUsd.toFixed(3)} total $${
      spentUsd.toFixed(2)
    }`,
  );
}
for (const arm of ARM_IDS) {
  await Deno.writeTextFile(
    `${outDir}arm-${arm}.json`,
    JSON.stringify(
      {
        meta: { ...meta, arm, model: ARMS[arm].model },
        results: records.filter((r) => r.arm === arm).map((r) => r.result),
      },
      null,
      2,
    ),
  );
}
await Deno.writeTextFile(
  `${outDir}summary.md`,
  renderSummaryMd(meta, summarizeArms(records)) +
    (guardTripped ? "\n**付費閘中途停止：max-calls 或 budget 用完。**\n" : ""),
);
const blind = buildBlindSheet(records);
if (blind) {
  await Deno.writeTextFile(`${outDir}blind.md`, blind.markdown);
  await Deno.writeTextFile(
    `${outDir}blind-reveal.json`,
    JSON.stringify(blind.reveal, null, 2),
  );
}
console.error(`wrote ${outDir}（spent $${spentUsd.toFixed(3)}）`);

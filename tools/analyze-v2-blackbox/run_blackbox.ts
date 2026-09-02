// 本機黑箱：真 Sonnet 5、v2 契約（noSendDecisions）、essential 五風格。
// 走 handleAnalyzeStream 本體（system prompt＋knowledge atoms＋divergence plan
// 全是 production 程式碼），只 stub DB store 與 supabase telemetry。
const ROOT =
  new URL("../../supabase/functions/analyze-chat", import.meta.url).pathname;
const positional = Deno.args.filter((a) => !a.startsWith("--"));
const flag = (name: string) =>
  Deno.args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const OUT = positional[0] ??
  new URL("./out/latest.json", import.meta.url).pathname;
// --only=a,b 只跑指定案；--repeat=N 每案跑 N 次（看邊界案穩不穩）。
const ONLY = flag("only")?.split(",").filter(Boolean) ?? null;
const REPEAT = Number(flag("repeat") ?? "1");

const realFetch = globalThis.fetch;
// 非 Anthropic 的 fetch（logAiCall 寫 supabase）只記 body，不外送。
let sideBodies: string[] = [];
globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
  const url = typeof input === "string"
    ? input
    : input instanceof URL
    ? input.href
    : input.url;
  if (url.startsWith("https://api.anthropic.com/")) {
    return realFetch(input, init);
  }
  if (typeof init?.body === "string") sideBodies.push(init.body);
  return Promise.resolve(
    new Response("{}", {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
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
// --raw=1：把模型原始 JSONL 存進結果（看 parser 為什麼丟掉某行）。
const RAW = flag("raw") === "1";

const apiKey =
  (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`))
    .trim();

import { corpusMessages, type Msg } from "./corpus.ts";
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

async function runCase(name: string, messages: Msg[]) {
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
    selectedModel: "claude-sonnet-5",
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
      options?: Parameters<typeof callClaudeStreaming>[2],
    ) => {
      sentRequests.push({
        model: request.model,
        systemSha256: await sha256Hex(request.system),
      });
      const result = await callClaudeStreaming(request, key, options);
      const source = result.textStream;
      async function* tee(): AsyncGenerator<string> {
        for await (const chunk of source) {
          rawText += chunk;
          yield chunk;
        }
      }
      return { ...result, textStream: tee() };
    }) as typeof callClaudeStreaming,
  };
  sideBodies = [];
  const started = Date.now();
  const startedAt = new Date().toISOString();
  let text = "";
  let status = 0;
  try {
    const response = await handleAnalyzeStream(deps as never);
    status = response.status;
    text = await response.text();
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
  return {
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
    ...(RAW
      ? {
        rawLines: rawText.split("\n").filter((l) => l.trim()).map((l) => {
          try {
            const parsed = JSON.parse(l);
            return parsed.type === "analysis.divergence_plan" ||
                parsed.type === "analysis.reply_option" ||
                parsed.type === "analysis.decision"
              ? parsed
              : { type: parsed.type };
          } catch {
            return { type: "UNPARSEABLE", raw: l };
          }
        }),
      }
      : {}),
  };
}

const STYLES_FOR_HASH = [...STREAM_STYLES];
const meta = {
  commit: await git(["rev-parse", "HEAD"]),
  tree: await git(["rev-parse", "HEAD^{tree}"]),
  worktreeDirty: (await git(["status", "--porcelain"])) !== "",
  // 每案實際送出的 model／system prompt 雜湊在 results[].sentRequests；這裡的
  // 重建值只供對照。
  v2SystemPromptSha256Rebuilt: await sha256Hex(
    buildAnalyzeStreamSystemPrompt(STYLES_FOR_HASH, {
      noSendDecisions: true,
      situationKnowledge: [],
      divergencePlan: true,
    }),
  ),
  generatedAt: new Date().toISOString(),
  args: Deno.args,
};
const results = [];
for (const [name, messages] of Object.entries(CASES)) {
  if (ONLY && !ONLY.includes(name)) continue;
  for (let i = 0; i < REPEAT; i++) {
    results.push(
      await runCase(REPEAT > 1 ? `${name}#${i + 1}` : name, messages),
    );
    console.error(`done ${name} ${i + 1}/${REPEAT}`);
  }
}
await Deno.writeTextFile(
  OUT,
  JSON.stringify({ meta, results }, null, 2),
);
console.error(`wrote ${OUT}`);

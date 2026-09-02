// 本機黑箱：真 Sonnet 5、v2 契約（noSendDecisions）、essential 五風格。
// 走 handleAnalyzeStream 本體（system prompt＋knowledge atoms＋divergence plan
// 全是 production 程式碼），只 stub DB store 與 supabase telemetry。
const ROOT =
  new URL("../../supabase/functions/analyze-chat", import.meta.url).pathname;
const OUT = Deno.args[0] ??
  new URL("./out/latest.json", import.meta.url).pathname;

const realFetch = globalThis.fetch;
globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
  const url = typeof input === "string"
    ? input
    : input instanceof URL
    ? input.href
    : input.url;
  if (url.startsWith("https://api.anthropic.com/")) {
    return realFetch(input, init);
  }
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

const apiKey =
  (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`))
    .trim();

type Msg = { isFromMe: boolean; content: string };
const CASES: Record<string, Msg[]> = {
  soft_reject_after_invite: [
    { isFromMe: false, content: "你週末都在幹嘛啊" },
    { isFromMe: true, content: "通常會去爬山或找朋友吃飯，你呢" },
    { isFromMe: false, content: "我都在家耍廢哈哈" },
    { isFromMe: true, content: "那這週六要不要一起去吃那家新開的義大利麵" },
    { isFromMe: false, content: "這週有點忙耶" },
    { isFromMe: false, content: "下次再看看" },
  ],
  warm_question_back: [
    { isFromMe: false, content: "剛看完你說的那部片 真的有被嚇到" },
    { isFromMe: true, content: "哈哈我就說吧 第二幕那段我看兩次還是會抖" },
    { isFromMe: false, content: "你平常都看這種的嗎？還是有別的推薦" },
    { isFromMe: false, content: "我最近有點片荒" },
  ],
  thin_opening: [
    { isFromMe: true, content: "嗨" },
    { isFromMe: false, content: "哈囉" },
  ],
};

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

async function runCase(name: string, messages: Msg[]) {
  const logs: unknown[][] = [];
  const origLog = console.log;
  console.log = (...args: unknown[]) => logs.push(args);
  let markDoneFinal: Record<string, unknown> | undefined;
  let charged = false;
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
  };
  const started = Date.now();
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
      textMentionsPlan: text.includes("divergence") ||
        text.includes("branchPool"),
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
      usage: (completed as Record<string, unknown>).usage ??
        (completed as Record<string, unknown>).tokenUsage ?? null,
      maxTokens,
    },
    logNames: [...new Set(logs.map((e) => String(e[0])))],
  };
}

const results = [];
for (const [name, messages] of Object.entries(CASES)) {
  results.push(await runCase(name, messages));
  console.error(`done ${name}`);
}
await Deno.writeTextFile(OUT, JSON.stringify(results, null, 2));
console.error(`wrote ${OUT}`);

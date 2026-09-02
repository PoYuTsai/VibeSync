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
async function gitHead(): Promise<string> {
  try {
    const out = await new Deno.Command("git", {
      args: ["rev-parse", "HEAD"],
      cwd: new URL("../..", import.meta.url).pathname,
      stdout: "piped",
    }).output();
    return new TextDecoder().decode(out.stdout).trim();
  } catch {
    return "unknown";
  }
}
// --raw=1：把模型原始 JSONL 存進結果（看 parser 為什麼丟掉某行）。
const RAW = flag("raw") === "1";

const apiKey =
  (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`))
    .trim();

type Msg = { isFromMe: boolean; content: string };
const CASES: Record<string, Msg[]> = {
  thin_opening: [
    { isFromMe: true, content: "嗨" },
    { isFromMe: false, content: "哈囉" },
  ],
  first_message_after_match: [
    { isFromMe: false, content: "嗨 你的照片是在哪拍的呀 好美" },
  ],
  warm_question_back: [
    { isFromMe: false, content: "剛看完你說的那部片 真的有被嚇到" },
    { isFromMe: true, content: "哈哈我就說吧 第二幕那段我看兩次還是會抖" },
    { isFromMe: false, content: "你平常都看這種的嗎？還是有別的推薦" },
    { isFromMe: false, content: "我最近有點片荒" },
  ],
  soft_reject_after_invite: [
    { isFromMe: false, content: "你週末都在幹嘛啊" },
    { isFromMe: true, content: "通常會去爬山或找朋友吃飯，你呢" },
    { isFromMe: false, content: "我都在家耍廢哈哈" },
    { isFromMe: true, content: "那這週六要不要一起去吃那家新開的義大利麵" },
    { isFromMe: false, content: "這週有點忙耶" },
    { isFromMe: false, content: "下次再看看" },
  ],
  defer_vague_busy: [
    { isFromMe: true, content: "禮拜五晚上有空嗎 想約妳吃飯" },
    { isFromMe: false, content: "最近有點忙欸" },
    { isFromMe: false, content: "再說吧" },
  ],
  defer_with_alternative: [
    { isFromMe: true, content: "禮拜五晚上有空嗎 想約妳吃飯" },
    { isFromMe: false, content: "禮拜五要加班耶" },
    { isFromMe: false, content: "禮拜天可以嗎" },
  ],
  defer_polite_reason: [
    { isFromMe: true, content: "這週末要不要一起去看那個展" },
    { isFromMe: false, content: "好像不錯" },
    { isFromMe: false, content: "不過我這週末已經約了朋友 之後再看看好了" },
  ],
  cold_one_word_replies: [
    { isFromMe: true, content: "今天天氣超好 有出門嗎" },
    { isFromMe: false, content: "沒" },
    { isFromMe: true, content: "那在家做什麼" },
    { isFromMe: false, content: "躺著" },
    { isFromMe: true, content: "哈哈 週末就是要耍廢 你平常有什麼興趣嗎" },
    { isFromMe: false, content: "還好" },
  ],
  she_invites_first: [
    { isFromMe: false, content: "我朋友給了我兩張週五的演唱會票" },
    { isFromMe: false, content: "你有興趣嗎" },
    { isFromMe: false, content: "是那個你之前說喜歡的樂團" },
  ],
  after_meetup_followup: [
    { isFromMe: true, content: "到家了嗎" },
    { isFromMe: false, content: "到了 今天謝謝你" },
    { isFromMe: false, content: "那家店真的很好吃 下次換我請" },
  ],
  she_shares_bad_day: [
    { isFromMe: false, content: "今天被主管當眾罵 超級丟臉" },
    { isFromMe: false, content: "明明不是我的錯" },
    { isFromMe: false, content: "覺得好累" },
  ],
  she_asks_personal_question: [
    { isFromMe: true, content: "你的貓超可愛" },
    { isFromMe: false, content: "哈哈牠很黏人" },
    { isFromMe: false, content: "對了 你是做什麼工作的啊" },
    { isFromMe: false, content: "感覺你很常出差" },
  ],
  long_conversation_35: [
    { isFromMe: false, content: "嗨 你也喜歡爬山喔" },
    { isFromMe: true, content: "對啊 你最近有去哪" },
    { isFromMe: false, content: "上個月去了合歡山" },
    { isFromMe: true, content: "哇 那邊日出很讚" },
    { isFromMe: true, content: "你平常都幾點起床" },
    { isFromMe: false, content: "我都七點多" },
    { isFromMe: false, content: "你呢" },
    { isFromMe: true, content: "我也差不多哈哈" },
    { isFromMe: true, content: "週末通常在幹嘛" },
    { isFromMe: false, content: "看書或跑步" },
    { isFromMe: false, content: "你呢" },
    { isFromMe: true, content: "我也差不多哈哈" },
    { isFromMe: true, content: "你喜歡吃辣嗎" },
    { isFromMe: false, content: "超愛 越辣越好" },
    { isFromMe: false, content: "你呢" },
    { isFromMe: true, content: "我也差不多哈哈" },
    { isFromMe: true, content: "有養寵物嗎" },
    { isFromMe: false, content: "有一隻貓 叫布丁" },
    { isFromMe: false, content: "你呢" },
    { isFromMe: true, content: "我也差不多哈哈" },
    { isFromMe: true, content: "你是台北人嗎" },
    { isFromMe: false, content: "對 但老家在台中" },
    { isFromMe: false, content: "你呢" },
    { isFromMe: true, content: "我也差不多哈哈" },
    { isFromMe: true, content: "最近在追什麼劇" },
    { isFromMe: false, content: "在看一部日劇" },
    { isFromMe: false, content: "你呢" },
    { isFromMe: true, content: "我也差不多哈哈" },
    { isFromMe: true, content: "你會煮飯嗎" },
    { isFromMe: false, content: "會一點 蛋炒飯專家" },
    { isFromMe: false, content: "你呢" },
    { isFromMe: true, content: "我也差不多哈哈" },
    { isFromMe: true, content: "喜歡海邊還是山上" },
    { isFromMe: false, content: "山上 海邊太曬" },
    { isFromMe: false, content: "你呢" },
    { isFromMe: true, content: "我也差不多哈哈" },
    { isFromMe: false, content: "欸 對了" },
    { isFromMe: false, content: "你上次說的那家咖啡廳在哪" },
    { isFromMe: false, content: "我這週末想去" },
  ],
  user_over_investing: [
    { isFromMe: true, content: "早安 今天要加油喔" },
    { isFromMe: true, content: "你昨天說的簡報還順利嗎" },
    { isFromMe: true, content: "如果需要幫忙可以跟我說" },
    { isFromMe: false, content: "嗯 還可以 謝謝" },
  ],
  she_double_texts: [
    { isFromMe: true, content: "我先去洗澡 等等聊" },
    { isFromMe: false, content: "好～" },
    { isFromMe: false, content: "欸 我剛想到 你上次說的那家拉麵我今天去吃了" },
    { isFromMe: false, content: "真的超好吃 你品味不錯欸" },
  ],
  logistics_confirm: [
    { isFromMe: true, content: "那週六下午三點 捷運忠孝敦化站三號出口見？" },
    { isFromMe: false, content: "好啊" },
    { isFromMe: false, content: "我可能會晚十分鐘 要先去拿東西" },
  ],
  she_teases_him: [
    { isFromMe: true, content: "我週末跑了十公里" },
    { isFromMe: false, content: "哇 這麼厲害" },
    { isFromMe: false, content: "該不會是跑去便利商店然後回來吧 哈哈" },
  ],
  she_returns_after_silence: [
    { isFromMe: true, content: "最近好嗎" },
    { isFromMe: false, content: "抱歉之前太忙沒回" },
    { isFromMe: false, content: "這陣子在趕案子 現在終於結束了" },
    { isFromMe: false, content: "你最近怎樣" },
  ],
  boundary_friend_hint: [
    { isFromMe: true, content: "我覺得跟你聊天很開心 想多認識你" },
    { isFromMe: false, content: "我也覺得你人很好" },
    { isFromMe: false, content: "不過我現在還不太想談感情 我們先當朋友可以嗎" },
  ],
  she_asks_his_opinion: [
    { isFromMe: false, content: "我在考慮要不要換工作" },
    { isFromMe: false, content: "新的薪水高很多 但要搬去新竹" },
    { isFromMe: false, content: "你覺得呢" },
  ],
  hobby_common_ground: [
    { isFromMe: false, content: "你也有在玩攝影喔 我看你照片" },
    { isFromMe: true, content: "對啊 但都是隨手拍" },
    { isFromMe: false, content: "我最近在學底片 沖出來都糊掉哈哈" },
    { isFromMe: false, content: "你有推薦的入門機嗎" },
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
      request: Parameters<typeof callClaudeStreaming>[0],
      key: string,
      options?: Parameters<typeof callClaudeStreaming>[2],
    ) => {
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
  commit: await gitHead(),
  model: "claude-sonnet-5",
  v2SystemPromptSha256: await sha256Hex(
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

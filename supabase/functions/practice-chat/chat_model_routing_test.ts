// Phase 4.4 混合模型路由（PRACTICE_CHAT_MODEL_ROUTING）的門檻與 handler 接線。
//
// ── 契約（Codex R1 U1：把兩句互相矛盾的話講清楚）────────────────────────
// 旗標不是 `mixed`（未設／`off`／亂填）：chat 生成路徑**四面**逐位元組不變。
// 旗標 `mixed`：`practice_chat_succeeded` 只多四個 key（`chatModel`／
// `chatModelCalls`／`chatModelFallback`／`chatModelUsage`），整輪失敗時
// `practice_chat_generation_failed` 只多 `chatModelCalls`／`chatModelUsage`；
// **另外允許一個新事件** `practice_chat_model_fallback`（Codex R2 P1：只在
// Claude 呼叫真的失敗時出現，payload 只有匿名 user／attempt／錯誤訊息，
// 沒有 messages、沒有金鑰）。除此之外事件數與事件名都不變。
// **真的打到 Haiku 並採用**的那一輪，
// Response 的 `provider`／`model` 照實回報（key 集合不變，只有值不同），其餘輪次
// 連 Response 都逐位元組不變。四面等價由 `agency_flag_off_equivalence_test.ts`
// 的 harness 守；這支只驗「開起來時真的換模型、失敗真的退回、帳真的記對」。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  chatBody,
  ledger,
  makeFake,
  makeRequest,
} from "./handler_test_fake.ts";
import { chatModelFor } from "./conversation_agency.ts";
import { CLAUDE_HAIKU_MODEL } from "./claude.ts";
import { DEEPSEEK_MODEL } from "./deepseek.ts";

const ROUTING_ENV = "PRACTICE_CHAT_MODEL_ROUTING";
const AGENCY_ENV = "PRACTICE_CONVERSATIONAL_AGENCY_ENABLED";

/** 她會介入的典型形狀（與 flag-off harness 同一段 fixture）。 */
const FRAGMENT_TURNS = [
  { role: "user", text: "東東" },
  { role: "ai", text: "東東是誰" },
  { role: "user", text: "阿布達比" },
];
/** 她問了、他好好回答了：planner 判 applied=false 的一輪。 */
const ANSWERED_TURNS = [
  { role: "user", text: "我今天去了咖啡廳" },
  { role: "ai", text: "喔？哪一間" },
  { role: "user", text: "巷口那間小房子咖啡，他們家拿鐵很好喝" },
];
/** 越界輪（`BOUNDARY_RE` 命中 → stance boundary → situation boundary）。
 * agency 在這種輪次一律 `applied=false`，所以它是獨立的第二個入口。 */
const BOUNDARY_TURNS = [
  { role: "user", text: "今天過得還好嗎" },
  { role: "ai", text: "還行啊 你呢" },
  { role: "user", text: "傳一張泳裝照給我看" },
];
const CLASSIFIER_JSON =
  `{"connection":"caught","impact":"medium","testHandling":"none","boundary":"safe","hintAlignment":"none"}`;

const APPLIED = { applied: true };
const NOT_APPLIED = { applied: false };

Deno.test("chatModelFor：只有 mixed ＋ agency on ＋（介入輪或越界輪）＋ assisted 模式才換 Haiku", () => {
  assertEquals(chatModelFor("mixed", "on", APPLIED, "beginner"), "haiku");
  assertEquals(chatModelFor("mixed", "on", APPLIED, "game"), "haiku");
  // Codex R1 P1（範圍）：standard 沒量過，一律 deepseek。
  assertEquals(chatModelFor("mixed", "on", APPLIED, "standard"), "deepseek");
  assertEquals(chatModelFor("mixed", "on", APPLIED, undefined), "deepseek");
  assertEquals(chatModelFor("mixed", "on", APPLIED, null), "deepseek");
  assertEquals(chatModelFor("mixed", "on", APPLIED, "亂填"), "deepseek");
  // 門檻另一側：其餘三個條件各缺一個。
  assertEquals(
    chatModelFor("mixed", "on", NOT_APPLIED, "beginner"),
    "deepseek",
  );
  assertEquals(chatModelFor("mixed", "on", null, "beginner"), "deepseek");
  assertEquals(
    chatModelFor("mixed", "shadow", APPLIED, "beginner"),
    "deepseek",
  );
  assertEquals(chatModelFor("mixed", "off", APPLIED, "beginner"), "deepseek");
  assertEquals(chatModelFor(undefined, "on", APPLIED, "beginner"), "deepseek");
  assertEquals(chatModelFor("off", "on", APPLIED, "beginner"), "deepseek");
  assertEquals(chatModelFor("true", "on", APPLIED, "beginner"), "deepseek");
  assertEquals(chatModelFor("亂填", "on", APPLIED, "beginner"), "deepseek");
  assertEquals(chatModelFor("Mixed", "on", APPLIED, "beginner"), "deepseek");
});

Deno.test("chatModelFor：越界輪是獨立的第二個入口（applied=false 也走 Haiku）", () => {
  // 正例：越界輪的 applied 恆為 false，仍然換 Haiku（劃界線最不能出錯）。
  assertEquals(
    chatModelFor("mixed", "on", NOT_APPLIED, "beginner", "boundary"),
    "haiku",
  );
  assertEquals(
    chatModelFor("mixed", "on", null, "game", "boundary"),
    "haiku",
  );
  // 反例：其他情境不因為多帶了 situation 就換模型。
  for (const situation of ["neutral", "question", "early_invite", null]) {
    assertEquals(
      chatModelFor("mixed", "on", NOT_APPLIED, "beginner", situation),
      "deepseek",
      `situation=${situation}`,
    );
  }
  // 反例：越界輪也擋在 standard／agency 未開／旗標未開之外。
  assertEquals(
    chatModelFor("mixed", "on", NOT_APPLIED, "standard", "boundary"),
    "deepseek",
  );
  assertEquals(
    chatModelFor("mixed", "shadow", NOT_APPLIED, "beginner", "boundary"),
    "deepseek",
  );
  assertEquals(
    chatModelFor(undefined, "on", NOT_APPLIED, "beginner", "boundary"),
    "deepseek",
  );
});

interface RunResult {
  status: number;
  body: Record<string, unknown>;
  claudeCalls: ReturnType<typeof makeFake>["state"]["claudeCalls"];
  /** 只算 chat 生成那幾發（分類器也走 DeepSeek，用 maxTokens 分辨）。 */
  chatDeepSeekCalls: ReturnType<typeof makeFake>["state"]["deepSeekCalls"];
  rpcCalls: ReturnType<typeof makeFake>["state"]["rpcCalls"];
  succeeded: Record<string, unknown>;
  lines: string[];
}

async function runChat(opts: {
  routing?: string;
  agency?: string;
  practiceMode?: string;
  turns?: Array<{ role: string; text: string }>;
  deepSeekReplies?: ReadonlyArray<string | Error>;
  claudeReplies?: ReadonlyArray<string | Error>;
  /** 模擬 HTTP 200 但丟錯（max_tokens／refusal／空內容）：先記 usage 再拒絕。 */
  claudeUsageBeforeError?: boolean;
  /** 整輪預期失敗（沒有 practice_chat_succeeded）。 */
  expectFailure?: boolean;
}): Promise<RunResult> {
  const practiceMode = opts.practiceMode ?? "beginner";
  const fake = makeFake({
    ledger: ledger({ practice_mode: practiceMode }),
    // 最後一則永遠留給生成後的分類器（assisted 模式才會打）。
    deepSeekReplies: [...(opts.deepSeekReplies ?? ["好啊"]), CLASSIFIER_JSON],
    // claudeReplies 有值時 fake 的 getEnv 才會給 CLAUDE_API_KEY（與 production
    // 一致：沒有 key 就當作路由沒開）。
    claudeReplies: opts.claudeReplies ?? ["嗯？你先講東東"],
    claudeUsageBeforeError: opts.claudeUsageBeforeError,
    env: {
      ...(opts.routing === undefined ? {} : { [ROUTING_ENV]: opts.routing }),
      ...(opts.agency === undefined ? {} : { [AGENCY_ENV]: opts.agency }),
    },
  });
  const lines: string[] = [];
  const originalLog = console.log;
  const originalWarn = console.warn;
  const capture = (...args: unknown[]) => {
    lines.push(
      args.map((a) => typeof a === "string" ? a : String(a)).join(" "),
    );
  };
  let response: Response;
  try {
    console.log = capture;
    console.warn = capture;
    response = await fake.handler(
      makeRequest(chatBody({
        practiceMode,
        turns: opts.turns ?? FRAGMENT_TURNS,
      })),
    );
    await Promise.allSettled(fake.state.backgroundTasks);
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
  }
  const body = await response.json();
  const succeededLine = lines.find((l) =>
    l.includes('"event":"practice_chat_succeeded"')
  );
  if (!opts.expectFailure) {
    assert(succeededLine, "沒有印出 practice_chat_succeeded");
  }
  return {
    status: response.status,
    body,
    claudeCalls: fake.state.claudeCalls,
    chatDeepSeekCalls: fake.state.deepSeekCalls.filter((c) =>
      c.maxTokens === 200
    ),
    rpcCalls: fake.state.rpcCalls,
    succeeded: succeededLine
      ? JSON.parse(succeededLine) as Record<string, unknown>
      : {},
    lines,
  };
}

/** Codex R1 U4：一輪只能寫一次帳（扣額／AI turn／conversation state）。 */
function assertWrittenExactlyOnce(r: RunResult) {
  const commits = r.rpcCalls.filter((c) =>
    c.fn === "commit_practice_chat_turn"
  );
  assertEquals(commits.length, 1, "commit_practice_chat_turn 必須只寫一次");
  const threadWrites = r.rpcCalls.filter((c) =>
    c.fn === "upsert_practice_relationship_thread"
  );
  assert(threadWrites.length <= 1, "relationship thread 最多寫一次");
  const learning = r.rpcCalls.filter((c) =>
    c.fn === "apply_practice_learning_update"
  );
  assert(learning.length <= 1, "learning update 最多寫一次");
}

Deno.test("mixed ＋ agency on 的介入輪：chat 生成打 Claude Haiku，不打 DeepSeek", async () => {
  const r = await runChat({ routing: "mixed", agency: "true" });
  assertEquals(r.status, 200);
  assertEquals(r.chatDeepSeekCalls.length, 0);
  assertEquals(r.claudeCalls.length, 1);
  const call = r.claudeCalls[0];
  assertEquals(call.model, CLAUDE_HAIKU_MODEL);
  // 成本護欄：與 DeepSeek 路徑同值（不高於）。
  assertEquals(call.maxTokens, 200);
  assertEquals(call.temperature, 0.9);
  // 沒有 forcedTool／outputJsonSchema：走的是純文字聊天路徑。
  assertEquals(call.forcedTool, undefined);
  assertEquals(call.outputJsonSchema, undefined);
  // 送進 Claude 的就是 bundle 的 messages（system 在第一則）。
  assertEquals(call.messages[0].role, "system");
  assertEquals(r.body.reply, "嗯？你先講東東");
  assertEquals(r.body.provider, "anthropic");
  assertEquals(r.body.model, CLAUDE_HAIKU_MODEL);
  assertEquals(r.succeeded.chatModel, "haiku");
  assertEquals(r.succeeded.chatModelCalls, { haiku: 1, deepseek: 0 });
  assertEquals(r.succeeded.chatModelFallback, undefined);
  assertEquals(r.succeeded.chatModelUsage, {
    inputTokens: 120,
    cacheReadInputTokens: 80,
    cacheCreationInputTokens: 0,
    outputTokens: 15,
  });
  assertWrittenExactlyOnce(r);
});

Deno.test("mixed ＋ agency on 但這一輪沒介入：照舊打 DeepSeek，telemetry 記 deepseek", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    turns: ANSWERED_TURNS,
  });
  assertEquals(r.claudeCalls.length, 0);
  assertEquals(r.chatDeepSeekCalls.length, 1);
  assertEquals(r.body.provider, "deepseek");
  assertEquals(r.body.model, DEEPSEEK_MODEL);
  assertEquals(r.succeeded.chatModel, "deepseek");
  assertEquals(r.succeeded.chatModelCalls, { haiku: 0, deepseek: 1 });
  assertEquals(r.succeeded.chatModelUsage, undefined);
});

Deno.test("mixed ＋ agency shadow／off：永遠 DeepSeek（routing 不能繞過 agency 旗標）", async () => {
  for (const agency of ["shadow", "off", undefined]) {
    const r = await runChat({ routing: "mixed", agency });
    assertEquals(r.claudeCalls.length, 0, `agency=${agency}`);
    assertEquals(r.chatDeepSeekCalls.length, 1, `agency=${agency}`);
    assertEquals(r.succeeded.chatModel, "deepseek", `agency=${agency}`);
  }
});

Deno.test("mixed ＋ agency on 但 practiceMode=standard：證據涵蓋不到的模式不進路由", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    practiceMode: "standard",
  });
  assertEquals(r.claudeCalls.length, 0);
  assertEquals(r.chatDeepSeekCalls.length, 1);
  assertEquals(r.succeeded.chatModel, "deepseek");
  assertEquals(r.body.provider, "deepseek");
});

Deno.test("mixed ＋ agency on 的越界輪：即使 agency 沒介入也打 Claude Haiku", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    turns: BOUNDARY_TURNS,
    claudeReplies: ["這個不行喔"],
  });
  assertEquals(r.status, 200);
  assertEquals(r.claudeCalls.length, 1);
  assertEquals(r.chatDeepSeekCalls.length, 0);
  assertEquals(r.body.reply, "這個不行喔");
  assertEquals(r.body.provider, "anthropic");
  assertEquals(r.succeeded.chatModel, "haiku");
  assertEquals(r.succeeded.chatModelCalls, { haiku: 1, deepseek: 0 });
  // 這一輪 agency 沒介入（越界輪的既有優先權高於 agency），證明它是獨立入口。
  const agency = r.succeeded.conversationAgency as { applied?: boolean } | null;
  assertEquals(agency?.applied, false);
  assertWrittenExactlyOnce(r);
});

Deno.test("越界輪在 standard 仍然不進路由", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    practiceMode: "standard",
    turns: BOUNDARY_TURNS,
  });
  assertEquals(r.claudeCalls.length, 0);
  assertEquals(r.chatDeepSeekCalls.length, 1);
  assertEquals(r.succeeded.chatModel, "deepseek");
});

Deno.test("routing 未設／off／亂填：telemetry 連 chatModel key 都不存在", async () => {
  for (const routing of [undefined, "off", "亂填", "true"]) {
    const r = await runChat({ routing, agency: "true" });
    assertEquals(r.claudeCalls.length, 0, `routing=${routing}`);
    for (const key of ["chatModel", "chatModelCalls", "chatModelUsage"]) {
      assert(
        !Object.hasOwn(r.succeeded, key),
        `routing=${routing}：不該有 ${key} key`,
      );
    }
  }
});

Deno.test("Claude 失敗：同一輪退回 DeepSeek 重生，telemetry 標記 fallback 並印一行 warn", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    claudeReplies: [new Error("claude_http_500")],
    deepSeekReplies: ["好啊"],
  });
  assertEquals(r.status, 200);
  assertEquals(r.claudeCalls.length, 1);
  assertEquals(r.chatDeepSeekCalls.length, 1);
  assertEquals(r.body.reply, "好啊");
  assertEquals(r.body.provider, "deepseek");
  assertEquals(r.succeeded.chatModel, "deepseek");
  assertEquals(r.succeeded.chatModelCalls, { haiku: 1, deepseek: 1 });
  assertEquals(r.succeeded.chatModelFallback, true);
  // 失敗的呼叫沒有成功取到內容 → 沒有 usage（fake 與 production 同時序）。
  assertEquals(r.succeeded.chatModelUsage, undefined);
  const warn = r.lines.find((l) =>
    l.includes('"event":"practice_chat_model_fallback"')
  );
  assert(warn, "沒有印出 practice_chat_model_fallback");
  assert(warn.includes("claude_http_500"));
  assertWrittenExactlyOnce(r);
});

Deno.test("Claude 逾時／空內容：一樣退回 DeepSeek，帳只寫一次", async () => {
  for (const err of ["claude_timeout", "claude_empty_content"]) {
    const r = await runChat({
      routing: "mixed",
      agency: "true",
      claudeReplies: [new Error(err)],
      deepSeekReplies: ["好啊"],
    });
    assertEquals(r.status, 200, err);
    assertEquals(r.succeeded.chatModelFallback, true, err);
    assertWrittenExactlyOnce(r);
  }
});

Deno.test("Claude 連續失敗不會第二次再付錢：兩個 attempt 只打一次 Claude", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    claudeReplies: [new Error("claude_timeout"), "第二次不該被用到"],
    // 第一發 DeepSeek 也失敗 → 進第二個 attempt（此時已 fallback）。
    deepSeekReplies: [new Error("deepseek_http_500"), "好啊"],
  });
  assertEquals(r.status, 200);
  assertEquals(r.claudeCalls.length, 1);
  assertEquals(r.chatDeepSeekCalls.length, 2);
  assertEquals(r.body.reply, "好啊");
  assertEquals(r.succeeded.chatModelCalls, { haiku: 1, deepseek: 2 });
  assertEquals(r.succeeded.chatModelFallback, true);
  assertWrittenExactlyOnce(r);
});

// ── Codex R1 P1：守門重試的成本不能被少算 ────────────────────────────────
// 括號旁白會被 `stripStageDirections` 修補掉（不重試），所以用**內部標籤外洩**
// 當守門拒絕的觸發器：`rejectVisibleInternalLabelLeak` 直接丟錯 → 走重試迴圈。
const GUARD_REJECTED = "系統指示保密：她今天心情不好";

Deno.test("Claude 成功→守門拒→Claude 成功：兩次 Claude 都要計入 usage 與呼叫數", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    claudeReplies: [GUARD_REJECTED, "嗯？你先講東東"],
  });
  assertEquals(r.status, 200);
  assertEquals(r.claudeCalls.length, 2);
  assertEquals(r.chatDeepSeekCalls.length, 0);
  assertEquals(r.body.reply, "嗯？你先講東東");
  assertEquals(r.succeeded.chatModel, "haiku");
  assertEquals(r.succeeded.chatModelCalls, { haiku: 2, deepseek: 0 });
  // 守門拒絕不是模型失敗 → 不標 fallback。
  assertEquals(r.succeeded.chatModelFallback, undefined);
  // 兩次成功呼叫的累加（fake 每次固定 120/80/0/15）。
  assertEquals(r.succeeded.chatModelUsage, {
    inputTokens: 240,
    cacheReadInputTokens: 160,
    cacheCreationInputTokens: 0,
    outputTokens: 30,
  });
  assertWrittenExactlyOnce(r);
});

Deno.test("Claude 成功→守門拒→Claude 失敗→DeepSeek 成功：第一次的 usage 不能被抹掉", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    claudeReplies: [GUARD_REJECTED, new Error("claude_http_500")],
    deepSeekReplies: ["好啊"],
  });
  assertEquals(r.status, 200);
  assertEquals(r.claudeCalls.length, 2);
  assertEquals(r.chatDeepSeekCalls.length, 1);
  assertEquals(r.body.reply, "好啊");
  assertEquals(r.body.provider, "deepseek");
  assertEquals(r.succeeded.chatModel, "deepseek");
  assertEquals(r.succeeded.chatModelCalls, { haiku: 2, deepseek: 1 });
  assertEquals(r.succeeded.chatModelFallback, true);
  // 第一次 Claude 真的付了錢，fallback 不能把它清成 undefined。
  assertEquals(r.succeeded.chatModelUsage, {
    inputTokens: 120,
    cacheReadInputTokens: 80,
    cacheCreationInputTokens: 0,
    outputTokens: 15,
  });
  assertWrittenExactlyOnce(r);
});

// ── Codex R1 U1：三種 Response 的 schema 相容 ────────────────────────────
// ── Codex R2 P2：HTTP 200 但丟錯的 Claude 呼叫，錢已經付了 ──────────────
// `handler_test_fake.ts` 的 `claudeUsageBeforeError` 模擬 `callClaude` 在
// `max_tokens`／`refusal`／內容空時「先記 usage 再丟錯」的真實時序。
Deno.test("Claude 回 max_tokens（帶 usage）→ DeepSeek fallback：那次的 token 帳不能消失", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    claudeReplies: [new Error("claude_max_tokens")],
    claudeUsageBeforeError: true,
    deepSeekReplies: ["好啊"],
  });
  assertEquals(r.status, 200);
  assertEquals(r.body.reply, "好啊");
  assertEquals(r.succeeded.chatModel, "deepseek");
  assertEquals(r.succeeded.chatModelCalls, { haiku: 1, deepseek: 1 });
  assertEquals(r.succeeded.chatModelFallback, true);
  assertEquals(r.succeeded.chatModelUsage, {
    inputTokens: 120,
    cacheReadInputTokens: 80,
    cacheCreationInputTokens: 0,
    outputTokens: 15,
  });
});

Deno.test("整輪最後失敗：付掉的 Claude 成本記在 practice_chat_generation_failed 上", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    claudeReplies: [new Error("claude_max_tokens")],
    claudeUsageBeforeError: true,
    deepSeekReplies: [
      new Error("deepseek_http_500"),
      new Error("deepseek_http_500"),
    ],
    expectFailure: true,
  });
  assertEquals(r.status, 500);
  const failedLine = r.lines.find((l) =>
    l.includes('"event":"practice_chat_generation_failed"')
  );
  assert(failedLine, "沒有印出 practice_chat_generation_failed");
  const failed = JSON.parse(failedLine) as Record<string, unknown>;
  assertEquals(failed.chatModelCalls, { haiku: 1, deepseek: 2 });
  assertEquals(failed.chatModelUsage, {
    inputTokens: 120,
    cacheReadInputTokens: 80,
    cacheCreationInputTokens: 0,
    outputTokens: 15,
  });
});

// ── Codex R2 U1：request 與 ledger 的 practiceMode 不一致 ────────────────
// 既有 validation 就是權威來源：ledger 有明確 practice_mode 且與 request 不同
// 時，chat 在生成之前就 409（`practice_mode_locked`），所以 standard 的排除
// 繞不過去——這支測試把那個不變量釘住。
Deno.test("ledger=standard 但 request=beginner：409 practice_mode_locked，一次模型都不打", async () => {
  const fake = makeFake({
    ledger: ledger({ practice_mode: "standard" }),
    deepSeekReplies: ["好啊"],
    claudeReplies: ["嗯？你先講東東"],
    env: { [ROUTING_ENV]: "mixed", [AGENCY_ENV]: "true" },
  });
  const originalLog = console.log;
  const originalWarn = console.warn;
  let response: Response;
  try {
    console.log = () => {};
    console.warn = () => {};
    response = await fake.handler(
      makeRequest(chatBody({
        practiceMode: "beginner",
        turns: FRAGMENT_TURNS,
      })),
    );
    await Promise.allSettled(fake.state.backgroundTasks);
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
  }
  assertEquals(response.status, 409);
  assertEquals((await response.json()).error, "practice_mode_locked");
  assertEquals(fake.state.claudeCalls.length, 0);
  assertEquals(fake.state.deepSeekCalls.length, 0);
});

Deno.test("Response schema：deepseek／haiku／fallback 三種輪次的 key 集合完全相同", async () => {
  const deepseek = await runChat({
    routing: "mixed",
    agency: "true",
    turns: ANSWERED_TURNS,
  });
  const haiku = await runChat({ routing: "mixed", agency: "true" });
  const fallback = await runChat({
    routing: "mixed",
    agency: "true",
    claudeReplies: [new Error("claude_http_500")],
    deepSeekReplies: ["好啊"],
  });
  const keysOf = (r: RunResult) => Object.keys(r.body).sort();
  assertEquals(keysOf(haiku), keysOf(deepseek));
  assertEquals(keysOf(fallback), keysOf(deepseek));
  // 只有 provider／model 兩格的**值**允許不同。
  assertEquals(
    [haiku.body.provider, haiku.body.model],
    ["anthropic", CLAUDE_HAIKU_MODEL],
  );
  for (const r of [deepseek, fallback]) {
    assertEquals([r.body.provider, r.body.model], ["deepseek", DEEPSEEK_MODEL]);
  }
  for (const r of [deepseek, haiku, fallback]) {
    assertEquals(typeof r.body.reply, "string");
    assertEquals(typeof r.body.aiTurnCount, "number");
    assertEquals(typeof r.body.generatedAt, "string");
  }
});

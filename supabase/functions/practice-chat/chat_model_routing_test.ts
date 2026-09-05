// Phase 4.4 混合模型路由（PRACTICE_CHAT_MODEL_ROUTING）的門檻與 handler 接線。
//
// 旗標未設／off／亂填時的**四面等價**由 `agency_flag_off_equivalence_test.ts`
// 的 harness 守（那裡多枚舉了一維 routing env）；這支只驗「開起來時真的換模型、
// 失敗真的退回 DeepSeek、telemetry 真的多那幾個 key」。

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

const APPLIED = { applied: true };
const NOT_APPLIED = { applied: false };

Deno.test("chatModelFor：只有 mixed ＋ agency on ＋ 這一輪 applied 才換 Haiku", () => {
  assertEquals(chatModelFor("mixed", "on", APPLIED), "haiku");
  // 門檻另一側：三個條件各缺一個。
  assertEquals(chatModelFor("mixed", "on", NOT_APPLIED), "deepseek");
  assertEquals(chatModelFor("mixed", "on", null), "deepseek");
  assertEquals(chatModelFor("mixed", "shadow", APPLIED), "deepseek");
  assertEquals(chatModelFor("mixed", "off", APPLIED), "deepseek");
  assertEquals(chatModelFor(undefined, "on", APPLIED), "deepseek");
  assertEquals(chatModelFor("off", "on", APPLIED), "deepseek");
  assertEquals(chatModelFor("true", "on", APPLIED), "deepseek");
  assertEquals(chatModelFor("亂填", "on", APPLIED), "deepseek");
  assertEquals(chatModelFor("Mixed", "on", APPLIED), "deepseek");
});

interface RunResult {
  status: number;
  body: Record<string, unknown>;
  claudeCalls: ReturnType<typeof makeFake>["state"]["claudeCalls"];
  deepSeekCalls: ReturnType<typeof makeFake>["state"]["deepSeekCalls"];
  succeeded: Record<string, unknown>;
  lines: string[];
}

async function runChat(opts: {
  routing?: string;
  agency?: string;
  turns?: Array<{ role: string; text: string }>;
  deepSeekReplies?: ReadonlyArray<string | Error>;
  claudeReplies?: ReadonlyArray<string | Error>;
}): Promise<RunResult> {
  const fake = makeFake({
    ledger: ledger(),
    deepSeekReplies: opts.deepSeekReplies ?? ["好啊"],
    // claudeReplies 有值時 fake 的 getEnv 才會給 CLAUDE_API_KEY（與 production
    // 一致：沒有 key 就當作路由沒開）。
    claudeReplies: opts.claudeReplies ?? ["嗯？你先講東東"],
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
      makeRequest(chatBody({ turns: opts.turns ?? FRAGMENT_TURNS })),
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
  assert(succeededLine, "沒有印出 practice_chat_succeeded");
  return {
    status: response.status,
    body,
    claudeCalls: fake.state.claudeCalls,
    deepSeekCalls: fake.state.deepSeekCalls,
    succeeded: JSON.parse(succeededLine) as Record<string, unknown>,
    lines,
  };
}

Deno.test("mixed ＋ agency on 的介入輪：chat 生成打 Claude Haiku，不打 DeepSeek", async () => {
  const r = await runChat({ routing: "mixed", agency: "true" });
  assertEquals(r.status, 200);
  assertEquals(r.deepSeekCalls.length, 0);
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
  assertEquals(r.succeeded.chatModelFallback, undefined);
  assertEquals(r.succeeded.chatModelUsage, {
    inputTokens: 120,
    cacheReadInputTokens: 80,
    cacheCreationInputTokens: 0,
    outputTokens: 15,
  });
});

Deno.test("mixed ＋ agency on 但這一輪沒介入：照舊打 DeepSeek，telemetry 記 deepseek", async () => {
  const r = await runChat({
    routing: "mixed",
    agency: "true",
    // 她問了、他好好回答了：planner 判 applied=false 的一輪。
    turns: [
      { role: "user", text: "我今天去了咖啡廳" },
      { role: "ai", text: "喔？哪一間" },
      { role: "user", text: "巷口那間小房子咖啡，他們家拿鐵很好喝" },
    ],
  });
  assertEquals(r.claudeCalls.length, 0);
  assertEquals(r.deepSeekCalls.length, 1);
  assertEquals(r.body.provider, "deepseek");
  assertEquals(r.body.model, DEEPSEEK_MODEL);
  assertEquals(r.succeeded.chatModel, "deepseek");
  assertEquals(r.succeeded.chatModelUsage, undefined);
});

Deno.test("mixed ＋ agency shadow／off：永遠 DeepSeek（routing 不能繞過 agency 旗標）", async () => {
  for (const agency of ["shadow", "off", undefined]) {
    const r = await runChat({ routing: "mixed", agency });
    assertEquals(r.claudeCalls.length, 0, `agency=${agency}`);
    assertEquals(r.deepSeekCalls.length, 1, `agency=${agency}`);
    assertEquals(r.succeeded.chatModel, "deepseek", `agency=${agency}`);
  }
});

Deno.test("routing 未設／off／亂填：telemetry 連 chatModel key 都不存在", async () => {
  for (const routing of [undefined, "off", "亂填", "true"]) {
    const r = await runChat({ routing, agency: "true" });
    assertEquals(r.claudeCalls.length, 0, `routing=${routing}`);
    assert(
      !Object.hasOwn(r.succeeded, "chatModel"),
      `routing=${routing}：不該有 chatModel key`,
    );
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
  assertEquals(r.deepSeekCalls.length, 1);
  assertEquals(r.body.reply, "好啊");
  assertEquals(r.body.provider, "deepseek");
  assertEquals(r.succeeded.chatModel, "deepseek");
  assertEquals(r.succeeded.chatModelFallback, true);
  assertEquals(r.succeeded.chatModelUsage, undefined);
  const warn = r.lines.find((l) =>
    l.includes('"event":"practice_chat_model_fallback"')
  );
  assert(warn, "沒有印出 practice_chat_model_fallback");
  assert(warn.includes("claude_http_500"));
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
  assertEquals(r.deepSeekCalls.length, 2);
  assertEquals(r.body.reply, "好啊");
  assertEquals(r.succeeded.chatModelFallback, true);
});

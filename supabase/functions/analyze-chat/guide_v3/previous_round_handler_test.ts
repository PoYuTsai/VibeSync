// 上一輪脈絡走整個 handler（guide_v3/v3_stream_harness.ts：假 Supabase、假模型）：
// 開關沒開時送給模型的請求跟沒帶這個欄位一模一樣；開了才在兩段提示詞多一段；
// 格式不對整份不用、分析照跑；扣費則數、對話雜湊、run 的紀錄都不受影響。
//
// 寫卡的 streaming_fallback.ts 一載入就存下 fetch：轉接器要放第一個 import，入口模組
// 也要在 env 裝好之後才動態載入（STREAM_ANALYZE_ENABLED 是載入時讀的常數）。
import "../test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { TEST_EMAILS } from "../../_shared/quota.ts";
import {
  parsePreviousRound,
  previousRoundReadSection,
  previousRoundWriteSection,
} from "./previous_round.ts";
import {
  fakeReadResponse,
  fakeWriteResponse,
  runGuideV3StreamThroughHandler,
  type V3HarnessOutcome,
} from "./v3_stream_harness.ts";

const IMPORT_ENV: Record<string, string> = {
  SUPABASE_URL: "http://supabase.test",
  SUPABASE_SERVICE_ROLE_KEY: "fake-service-key",
  CLAUDE_API_KEY: "fake-claude-key",
  STREAM_ANALYZE_ENABLED: "true",
};
const savedEnv = Object.keys(IMPORT_ENV).map((k) => [k, Deno.env.get(k)]);
for (const [k, v] of Object.entries(IMPORT_ENV)) Deno.env.set(k, v);
const { createAnalyzeChatHandler } = await import("../index.ts");
for (const [k, v] of savedEnv) {
  if (v === undefined) Deno.env.delete(k!);
  else Deno.env.set(k!, v);
}

const FLAG = "ANALYZE_GUIDE_V3_PREV_ROUND";

/// 這次的對話 89 字（計費 3 則）；上一輪接近 600 字，算進去就會跳到 10 則。
const MESSAGES = [
  { isFromMe: true, content: "上次說的那間早午餐，我查了一下週六早上有位子" },
  {
    isFromMe: false,
    content:
      "哇你真的去查了喔，我最近都睡到中午欸，週六早上可能爬不起來，但是那間的鬆餅我真的很想吃",
  },
  {
    isFromMe: false,
    content: "如果改成下午茶呢？三點左右我應該就醒了，你覺得呢",
  },
];

const PREVIOUS_ROUND = {
  decision: "send",
  light: "green",
  judgment: "她主動提到想吃鬆餅，給了很明確的機會，球在你這邊。".padEnd(
    120,
    "。",
  ),
  messages: [
    { isFromMe: false, content: "最近好想吃鬆餅喔".padEnd(120, "～") },
    { isFromMe: true, content: "哪一種的？厚的還是薄的".padEnd(120, "？") },
    { isFromMe: false, content: "厚的！越厚越好".padEnd(120, "！") },
    {
      isFromMe: false,
      content: "東區那間排隊名店我還沒去過".padEnd(120, "～"),
    },
  ],
};

const TAGS = {
  light: "green",
  herMove: "開窗",
  herMoodBad: false,
  drunkOrLateNight: false,
  inviteReadiness: "明確答應",
  cancelHasAlternative: false,
  retreating: false,
  declinedOrBoundary: false,
  explicitRejection: false,
  blocked: false,
  risk: false,
  selfHarmSignal: false,
  needsHisFacts: false,
  identityQuestion: false,
  hisStatedFacts: [],
  hasHisVoiceSample: true,
  replyWillingness: "high",
  worthyBallCount: 1,
  herTurnsPerfunctory: [],
  matchedEntries: [],
  readForUser: "她把時間改成下午，等於答應了，只是換個時段。",
  waitFor: "",
};

const CARD_LINES = [1, 2, 3, 4, 5].map((card) =>
  JSON.stringify({
    card,
    messages: [`那就下午三點，我先訂位（${card}）`],
    hasInventedDetail: false,
  })
);

function body(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    responseMode: "stream",
    messages: MESSAGES,
    billingProtocolVersion: 3,
    analysisContractVersion: 3,
    ...extra,
  };
}

function run(
  requestBody: Record<string, unknown>,
  flag: string | undefined,
  email?: string,
): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    body: requestBody,
    env: {
      ANALYZE_GUIDE_V3: "on",
      ANALYZE_GUIDE_V3_MEMORY: undefined,
      [FLAG]: flag,
    },
    ...(email ? { email } : {}),
    model: (modelBody) =>
      Promise.resolve(
        modelBody.stream === true
          ? fakeWriteResponse(CARD_LINES)
          : fakeReadResponse(TAGS),
      ),
  });
}

function userPrompt(out: V3HarnessOutcome, index: number): string {
  const messages = out.modelBodies[index].messages as { content: string }[];
  return messages[0].content;
}

function chargeRpc(out: V3HarnessOutcome): Record<string, unknown> {
  const charge = out.rpcs.find((r) => r.fn === "charge_stream_analysis_run_v3");
  assert(charge, "要有扣費");
  return charge.args;
}

function assertDone(out: V3HarnessOutcome) {
  assertEquals(out.status, 200);
  assertEquals(out.events.at(-1)?.type, "analysis.done");
  assertEquals(out.modelBodies.length, 2, "讀局面＋寫卡各一次");
}

Deno.test("上一輪開關沒開（沒設、off、打錯、test 但不是測試帳號）：送給模型的請求跟沒帶一模一樣", async () => {
  const without = await run(body(), undefined);
  assertDone(without);
  for (const flag of [undefined, "off", "maybe", "test"]) {
    const withField = await run(body({ previousRound: PREVIOUS_ROUND }), flag);
    assertDone(withField);
    assertEquals(withField.modelBodies, without.modelBodies, String(flag));
    assertEquals(withField.createdRuns, without.createdRuns, String(flag));
    assertEquals(withField.rpcs, without.rpcs, String(flag));
    assertEquals(
      "previousRound" in
        (withField.finalResult?.guideV3Trace as Record<string, unknown>),
      false,
    );
  }
});

Deno.test("上一輪開關 on：兩段提示詞各多一段標明的背景，系統提示詞不變", async () => {
  const without = await run(body(), "on");
  // 舊版 App 可能還帶「他複製的那張」：不收、不進提示詞（主審第 1 輪 P2）。
  const withField = await run(
    body({
      previousRound: { ...PREVIOUS_ROUND, sentCard: "那週六去吃早午餐？" },
    }),
    "on",
  );
  assertDone(without);
  assertDone(withField);
  const parsed = parsePreviousRound(PREVIOUS_ROUND);
  assert(parsed.kind === "ok");
  const [readSection] = previousRoundReadSection(parsed.round);
  const [writeSection] = previousRoundWriteSection(parsed.round);
  assertEquals(
    userPrompt(withField, 0),
    userPrompt(without, 0).replace("## 對話\n", `${readSection}\n\n## 對話\n`),
  );
  assertEquals(
    userPrompt(withField, 1),
    userPrompt(without, 1).replace("## 對話\n", `${writeSection}\n\n## 對話\n`),
  );
  for (const i of [0, 1]) {
    assertEquals(
      withField.modelBodies[i].system,
      without.modelBodies[i].system,
    );
  }
});

Deno.test("上一輪開關 on：不算計費字數、不進對話雜湊，trace 只記數量", async () => {
  const without = await run(body(), "on");
  const withField = await run(body({ previousRound: PREVIOUS_ROUND }), "on");
  // 這次對話本身要扣 3 則；上一輪約 600 字，算進去會變 10 則。
  assertEquals(chargeRpc(without).p_message_count, 3);
  assertEquals(chargeRpc(withField).p_message_count, 3);
  assertEquals(chargeRpc(withField).p_charge_quota, true);
  assertEquals(
    chargeRpc(withField).p_conversation_hash,
    chargeRpc(without).p_conversation_hash,
  );
  assertEquals(withField.createdRuns, without.createdRuns);
  const usage = withField.events.at(-1)?.finalResult as {
    usage: { messagesUsed: number };
  };
  assertEquals(usage.usage.messagesUsed, 3);
  const trace = withField.finalResult?.guideV3Trace as Record<string, unknown>;
  assertEquals(trace.previousRound, {
    messages: 4,
    chars: 600,
    judgment: true,
  });
  // 落帳的結果裡找不到上一輪的任何字。
  const stored = JSON.stringify(withField.finalResult);
  for (const piece of ["好想吃鬆餅", "越厚越好", "排隊名店", "給了很明確"]) {
    assert(!stored.includes(piece), piece);
  }
});

Deno.test("上一輪開關 test：只有測試帳號會用", async () => {
  const testEmail = TEST_EMAILS[0];
  const withField = await run(
    body({ previousRound: PREVIOUS_ROUND }),
    "test",
    testEmail,
  );
  const without = await run(body(), "test", testEmail);
  assertDone(withField);
  assertNotEquals(userPrompt(withField, 0), userPrompt(without, 0));
  assert(userPrompt(withField, 0).includes("## 上一輪（比下面的對話早）"));
});

Deno.test("上一輪開關 on、格式不對：整份不用，分析照跑，請求跟沒帶一樣", async () => {
  const without = await run(body(), "on");
  const bad = [
    { ...PREVIOUS_ROUND, decision: "care" },
    { ...PREVIOUS_ROUND, judgment: `${PREVIOUS_ROUND.judgment}多` },
    { ...PREVIOUS_ROUND, messages: "她：好" },
    "上一輪",
  ];
  for (const previousRound of bad) {
    const out = await run(body({ previousRound }), "on");
    assertDone(out);
    assertEquals(out.modelBodies, without.modelBodies);
    assertEquals(out.rpcs, without.rpcs);
  }
});

Deno.test("上一輪只接在 v3 入口：開關讀一次，不進對話雜湊、不碰計費訊息", async () => {
  const source = await Deno.readTextFile(
    new URL("../analyze_chat_handler.ts", import.meta.url),
  );
  const at = (needle: string) => {
    const index = source.indexOf(needle);
    assert(index >= 0, `找不到：${needle}`);
    return index;
  };
  const v3Call = at("return await handleGuideV3Stream({");
  const v2Dispatch = at(
    'if (responseMode === "stream") {\n      return await handleAnalyzeStream({',
  );
  const flagRead = `Deno.env.get("${FLAG}")`;
  assertEquals(source.split(flagRead).length - 1, 1);
  assertEquals(source.split("requestBody.previousRound").length - 1, 1);
  const flagAt = at(flagRead);
  assert(v3Call < flagAt && flagAt < v2Dispatch);
  // 讀到的值只交給 shouldUseGuideV3PreviousRound，沒開就不碰這個欄位。
  assert(
    source.slice(v3Call, v2Dispatch).includes(
      `previousRound: shouldUseGuideV3PreviousRound({\n            mode: guideV3Mode(${flagRead}),\n            accountIsTest,\n          })\n          ? acceptedPreviousRound(`,
    ),
  );
  assert(
    v3Call < at("requestBody.previousRound") &&
      at("requestBody.previousRound") < v2Dispatch,
  );
  const hashInput = source.slice(
    at("const streamHashInput = {"),
    at("// 對話分析 v3（第 3 階段）"),
  );
  assertEquals(hashInput.includes("previousRound"), false);
  const billing = source.slice(
    at("const billingMessages = billingMessagesFor(messages, {"),
    at("const estimatedMessageCount = recognizeOnly"),
  );
  assertEquals(billing.includes("previousRound"), false);
});

Deno.test("上一輪開關 on：模型把上一輪原句抄進讀局面標記、判讀與卡片，trace 也不放任何字（主審第 1 輪 P1）", async () => {
  const quote = "我在竹科做夜班";
  const previousRound = {
    decision: "send",
    light: "green",
    judgment: "他講了自己的工作，她有興趣。",
    messages: [
      { isFromMe: true, content: quote },
      { isFromMe: false, content: "難怪你都這麼晚回" },
    ],
  };
  // 假模型把上一輪那句抄進每一個自由文字欄位，卡片也抄（含「妳」，預設口吻會留原文）。
  const echoTags = {
    ...TAGS,
    hisStatedFacts: [quote],
    matchedEntries: [quote, "B05"],
    readForUser: `他上次說${quote}，她現在約下午。`,
    waitFor: `等她回${quote}`,
  };
  const echoCards = [1, 2, 3, 4, 5].map((card) =>
    JSON.stringify({
      card,
      messages: [`妳記得${quote}這件事啊（${card}）`],
      hasInventedDetail: false,
    })
  );
  const runEcho = (previous?: Record<string, unknown>) =>
    runGuideV3StreamThroughHandler({
      createHandler: createAnalyzeChatHandler,
      body: body(previous ? { previousRound: previous } : {}),
      env: {
        ANALYZE_GUIDE_V3: "on",
        ANALYZE_GUIDE_V3_MEMORY: undefined,
        [FLAG]: "on",
      },
      model: (modelBody) =>
        Promise.resolve(
          modelBody.stream === true
            ? fakeWriteResponse(echoCards)
            : fakeReadResponse(echoTags),
        ),
    });

  const withField = await runEcho(previousRound);
  assertDone(withField);
  const trace = withField.finalResult?.guideV3Trace as Record<string, unknown>;
  assertEquals(JSON.stringify(trace).includes("竹科"), false);
  const tags = trace.tags as Record<string, unknown>;
  for (const key of ["hisStatedFacts", "readForUser", "waitFor"]) {
    assertEquals(key in tags, false, key);
  }
  assertEquals(tags.hisStatedFactsCount, 1);
  assertEquals(tags.matchedEntries, ["B05"]);
  assertEquals(tags.light, "green");
  const raws = trace.rawMessages as Record<string, unknown>[];
  assert(raws.length > 0, "預設口吻的卡要有原文紀錄");
  for (const raw of raws) {
    assertEquals(Object.keys(raw).sort(), ["messageCount", "slot"]);
  }
  // 給用戶看的判讀與卡是產品輸出，照存在結果裡。
  const read = withField.finalResult?.read as { judgment: string };
  assert(read.judgment.includes("竹科"));
  const cards = withField.finalResult?.cards as { messages: string[] }[];
  assert(cards.some((c) => c.messages.join("").includes("竹科")));

  // 沒帶上一輪：trace 跟今天一樣保留完整標記與原文。
  const without = await runEcho();
  const plain = without.finalResult?.guideV3Trace as Record<string, unknown>;
  assertEquals((plain.tags as Record<string, unknown>).hisStatedFacts, [quote]);
  assert(
    (plain.rawMessages as { messages?: string[] }[]).every((r) =>
      Array.isArray(r.messages)
    ),
  );
});

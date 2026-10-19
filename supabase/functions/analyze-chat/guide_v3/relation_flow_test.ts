// 關係訊號開關開（ANALYZE_GUIDE_V3_RELATION，Bruce 2026-10-19 路線二）時的整個 v3 流程：讀局面請求
// 換成多三欄的提示詞與 schema；三欄不合格只拿掉那一欄、記 log；決定、卡與扣費都跟沒開一樣。
// 模型與資料庫都是替身，不連網。
//
// 寫卡的 streaming_fallback.ts 一載入就存下 fetch：轉接器要放第一個 import。
import "../test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { TEST_EMAILS } from "../../_shared/quota.ts";
import {
  READ_TAGS_SCHEMA_WITH_RELATION,
  readSystemPromptWithRelation,
} from "./relation.ts";
import {
  fixtureCase,
  type FlowCase,
  runFlow,
  withReadTags,
} from "./relation_flow_harness.ts";
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

type Rec = Record<string, unknown>;

const DIMENSIONS = {
  engagement: 70,
  topicDepth: 55,
  replyWillingness: 65,
  emotionalConnection: 50,
};
/// 模型照多三欄的 schema 回的樣子。
const RELATION_TAGS = {
  gameStage: "qualification",
  heatScore: 62,
  dimensions: DIMENSIONS,
};
const RELATION_KEYS = Object.keys(RELATION_TAGS);

/// 去掉所有叫 relation 的欄位，拿來比「除了關係訊號以外都一樣」。
function stripRelation<T>(value: T): T {
  return JSON.parse(
    JSON.stringify(value, (key, v) => key === "relation" ? undefined : v),
  );
}

function trace(outcome: Rec): Rec {
  return (outcome.markDone as Rec).guideV3Trace as Rec;
}

function relationLogs(outcome: Rec): unknown[] {
  return (outcome.logs as { event: string }[]).filter((l) =>
    l.event === "guide_v3_relation_dropped"
  );
}

/// 開關開、讀局面多回三欄，跟開關沒開、同一份對話與同一份標記（over 是兩邊都改的標記）比：
/// 送出的事件、扣費、log 除了關係訊號都一樣；trace 只多 relation，標記多模型原樣回的三欄。
async function assertSameExceptRelation(
  name: string,
  relationTags: Rec,
  over: Rec = {},
): Promise<Rec> {
  const off = await runFlow(withReadTags(name, over));
  const on = await runFlow(withReadTags(name, { ...over, ...relationTags }), {
    relation: true,
  });
  assertEquals(on.calls, off.calls);
  assertEquals(stripRelation(on.events), off.events);
  assertEquals(stripRelation(on.charges), off.charges);
  const onRequests = on.requests as Rec;
  const offRequests = off.requests as Rec;
  assertEquals(onRequests.write, offRequests.write);
  assertEquals(onRequests.requestContext, offRequests.requestContext);
  assertEquals(
    (onRequests.read as Rec).user,
    (offRequests.read as Rec).user,
  );
  const { relation: _r, tags: onTags, ...onTrace } = trace(on);
  const { tags: offTags, ...offTrace } = trace(off);
  assertEquals(onTrace, offTrace);
  assertEquals(onTags, { ...(offTags as Rec), ...relationTags });
  const { guideV3Trace: _onT, ...onDone } = on.markDone as Rec;
  const { guideV3Trace: _offT, ...offDone } = off.markDone as Rec;
  assertEquals(stripRelation(onDone), offDone);
  assertEquals(
    (on.logs as { event: string }[]).filter((l) =>
      l.event !== "guide_v3_relation_dropped"
    ),
    off.logs,
  );
  return on;
}

Deno.test("開關開：讀局面換成多三欄的提示詞與 schema，使用者那一則不變", async () => {
  const on = await runFlow(withReadTags("she_teases_him#1", RELATION_TAGS), {
    relation: true,
  });
  const read = (on.requests as Rec).read as Rec;
  assertEquals(read.system, readSystemPromptWithRelation());
  assertEquals(read.schema, READ_TAGS_SCHEMA_WITH_RELATION);
});

Deno.test("開關開：出卡、收尾、先別回、停的決定、卡、扣費與 log 都跟沒開一樣，trace 記通過檢查的三欄", async () => {
  for (
    const name of [
      "she_teases_him#1",
      "soft_reject_after_invite#1",
      "cold_one_word_replies#1",
    ]
  ) {
    const on = await assertSameExceptRelation(name, RELATION_TAGS);
    assertEquals(trace(on).relation, {
      stage: "qualification",
      heat: 62,
      dimensions: DIMENSIONS,
      dropped: [],
    }, name);
    assertEquals(relationLogs(on), [], name);
  }
  const stop = await assertSameExceptRelation(
    "she_teases_him#1",
    RELATION_TAGS,
    { explicitRejection: true },
  );
  assertEquals(
    (stop.events as Rec[]).find((e) => e.type === "analysis.read")?.decision,
    "stop",
  );
});

Deno.test("開關開、三欄不合格：只拿掉那一欄、記一筆 error log，分析照常出卡、照常扣", async () => {
  const bad = { ...RELATION_TAGS, gameStage: "dating", heatScore: 150 };
  const on = await assertSameExceptRelation("she_teases_him#1", bad);
  const dropped = [
    { field: "gameStage", reason: "invalid" },
    { field: "heatScore", reason: "invalid" },
  ];
  assertEquals(trace(on).relation, { dimensions: DIMENSIONS, dropped });
  assertEquals(relationLogs(on), [{
    event: "guide_v3_relation_dropped",
    metadata: { analysisRunId: "flow-run", dropped },
    level: "error",
  }]);
  assert(
    (on.events as Rec[]).filter((e) => e.type === "analysis.card").length > 0,
  );
});

Deno.test("開關開、讀局面沒回三欄（例如開關剛打開前錄的輸出）：三欄都記 missing，分析照常", async () => {
  const on = await runFlow(fixtureCase("she_teases_him#1"), {
    relation: true,
  });
  const off = await runFlow(fixtureCase("she_teases_him#1"));
  assertEquals(stripRelation(on.events), off.events);
  assertEquals(stripRelation(on.charges), off.charges);
  const dropped = RELATION_KEYS.map((field) => ({ field, reason: "missing" }));
  assertEquals(trace(on).relation, { dropped });
  assertEquals(relationLogs(on).length, 1);
});

Deno.test("開關開、讀局面壞掉：照舊當讀局面失敗、不扣，沒有關係訊號；關鍵字後援的關心也沒有", async () => {
  const broken: FlowCase = {
    ...fixtureCase("she_teases_him#1"),
    readText: "不是 JSON",
  };
  const on = await runFlow(broken, { relation: true });
  const off = await runFlow(broken);
  assertEquals(on.events, off.events);
  assertEquals(on.calls, off.calls);
  assertEquals(
    (on.events as Rec[]).find((e) => e.type === "analysis.error")?.code,
    "GUIDE_V3_READ_INVALID",
  );
  assertEquals(relationLogs(on), []);
  const care: FlowCase = {
    ...broken,
    messages: [...broken.messages, { isFromMe: false, content: "我不想活了" }],
  };
  const careOn = await runFlow(care, { relation: true });
  const careOff = await runFlow(care);
  for (const key of ["events", "calls", "charges", "markDone", "logs"]) {
    assertEquals(careOn[key], careOff[key], key);
  }
  assertEquals("relation" in trace(careOn), false);
});

Deno.test("開關開、帶了上一輪：trace 只留白名單，關係訊號照留（只有代碼與數字），模型寫的字不留", async () => {
  const previousRound = {
    decision: "send" as const,
    light: "green" as const,
    judgment: "她主動分享週末行程。",
    messages: [{ isFromMe: false, content: "週末想去走走" }],
  };
  const on = await runFlow(withReadTags("she_teases_him#1", RELATION_TAGS), {
    relation: true,
    previousRound,
  });
  const t = trace(on);
  assertEquals(t.relation, {
    stage: "qualification",
    heat: 62,
    dimensions: DIMENSIONS,
    dropped: [],
  });
  // 標記的白名單照舊：數字留著，字串只留固定選項，物件不留。
  const tags = t.tags as Rec;
  assertEquals(tags.heatScore, 62);
  assertEquals("gameStage" in tags, false);
  assertEquals("dimensions" in tags, false);
  assertEquals("readForUser" in tags, false);
});

// ---- 走整個 handler（假 Supabase、假模型） ----

const HANDLER_MESSAGES = [
  { isFromMe: true, content: "週末去哪玩" },
  { isFromMe: false, content: "去爬山，腿快斷了，你呢？" },
];
const HANDLER_TAGS = JSON.parse(fixtureCase("she_teases_him#1").readText);
const HANDLER_CARDS = [1, 2, 3, 4, 5].map((card) =>
  JSON.stringify({
    card,
    messages: [`爬完還能打字，體力不錯（${card}）`],
    hasInventedDetail: false,
  })
);

function runHandler(
  flag: string | undefined,
  email?: string,
): Promise<V3HarnessOutcome> {
  return runGuideV3StreamThroughHandler({
    createHandler: createAnalyzeChatHandler,
    body: {
      responseMode: "stream",
      messages: HANDLER_MESSAGES,
      billingProtocolVersion: 3,
      analysisContractVersion: 3,
    },
    env: {
      ANALYZE_GUIDE_V3: "on",
      ANALYZE_GUIDE_V3_MEMORY: undefined,
      ANALYZE_GUIDE_V3_PREV_ROUND: undefined,
      ANALYZE_GUIDE_V3_RELATION: flag,
    },
    ...(email ? { email } : {}),
    model: (modelBody) =>
      Promise.resolve(
        modelBody.stream === true
          ? fakeWriteResponse(HANDLER_CARDS)
          : fakeReadResponse({ ...HANDLER_TAGS, ...RELATION_TAGS }),
      ),
  });
}

function readBody(out: V3HarnessOutcome): Rec {
  const body = out.modelBodies.find((b) => b.stream !== true);
  assert(body, "要有讀局面請求");
  return body;
}

Deno.test("開關 on，或 test＋測試帳號：走 handler 時讀局面請求換成多三欄的提示詞與 schema，其他欄位與寫卡請求不變", async () => {
  const off = await runHandler(undefined);
  const offRead = readBody(off);
  const offWrite = off.modelBodies.find((b) => b.stream === true);
  for (
    const [flag, email] of [
      ["on", undefined],
      [" ON ", undefined],
      ["test", TEST_EMAILS[0]],
    ] as const
  ) {
    const out = await runHandler(flag, email);
    assertEquals(out.status, 200, flag);
    assertEquals(out.events.at(-1)?.type, "analysis.done", flag);
    const read = readBody(out);
    assertEquals(
      (read.system as { text: string }[])[0].text,
      readSystemPromptWithRelation(),
      flag,
    );
    assertEquals(
      ((read.output_config as Rec).format as Rec).schema,
      READ_TAGS_SCHEMA_WITH_RELATION,
      flag,
    );
    // 系統提示詞與 schema 以外（模型、max_tokens、思考設定、使用者那一則）都不變。
    const { system: _s, output_config: onConfig, ...onRest } = read;
    const { system: _o, output_config: offConfig, ...offRest } = offRead;
    assertEquals(onRest, offRest, flag);
    const { format: _f1, ...onEffort } = onConfig as Rec;
    const { format: _f2, ...offEffort } = offConfig as Rec;
    assertEquals(onEffort, offEffort, flag);
    assertEquals(
      out.modelBodies.find((b) => b.stream === true),
      offWrite,
      flag,
    );
  }
});

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
  RELATION_FLOW_T0,
  runFlow,
  runFlowWithRun,
  withReadTags,
} from "./relation_flow_harness.ts";
import {
  GUIDE_V3_STALE_AFTER_MS,
  guideV3ResumeSnapshot,
  recoveredGuideV3Result,
} from "./run_shape.ts";
import {
  fakeReadResponse,
  fakeWriteResponse,
  runGuideV3StreamThroughHandler,
  type V3HarnessOutcome,
} from "./v3_stream_harness.ts";
import { HER_MOVE_CODE } from "./wire.ts";
import { HOLD_WAIT_FALLBACK } from "./plan.ts";

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

// ---- 判讀帶 relation（合約見 COMMON2：stage、heat、dimensions、herMove、willingness） ----

/// 讀局面標記與三欄 → 判讀裡應該出現的 relation（欄位順序照合約）。
function expectedRelation(name: string, over: Rec = {}): Rec {
  const tags = { ...JSON.parse(fixtureCase(name).readText), ...over };
  return {
    stage: "qualification",
    heat: 62,
    dimensions: { heat: 62, ...DIMENSIONS },
    herMove: HER_MOVE_CODE[tags.herMove as keyof typeof HER_MOVE_CODE],
    willingness: tags.replyWillingness,
  };
}

function readEventOf(outcome: Rec): Rec {
  const read = (outcome.events as Rec[]).find((e) =>
    e.type === "analysis.read"
  );
  assert(read, "要有判讀");
  return read;
}

/// relation 出現的每個地方：判讀事件、done 的兩份結果、扣費內容、落帳結果。
function relationCopies(outcome: Rec): unknown[] {
  const done = (outcome.events as Rec[]).find((e) =>
    e.type === "analysis.done"
  )!;
  return [
    readEventOf(outcome).relation,
    ((done.finalResult as Rec).read as Rec).relation,
    ((done.result as Rec).read as Rec).relation,
    ...(outcome.charges as Rec[]).map((c) =>
      ((c.recommendationJson as Rec).read as Rec).relation
    ),
    ((outcome.markDone as Rec).read as Rec).relation,
  ];
}

Deno.test("開關開、出卡：判讀在最後多一個 relation，形狀照合約；done、扣費內容、落帳結果都是同一份", async () => {
  const name = "she_teases_him#1";
  const on = await assertSameExceptRelation(name, RELATION_TAGS);
  const expected = expectedRelation(name);
  assertEquals(expected.herMove, "teasing");
  const read = readEventOf(on);
  // 用 JSON 字串比，連欄位順序一起鎖住；relation 排在判讀最後，前面的欄位不動。
  assertEquals(JSON.stringify(read.relation), JSON.stringify(expected));
  const off = await runFlow(fixtureCase(name));
  assertEquals(Object.keys(read), [
    ...Object.keys(readEventOf(off)),
    "relation",
  ]);
  const copies = relationCopies(on);
  assertEquals(copies.length, 5);
  for (const copy of copies) assertEquals(copy, expected);
  // 判讀照舊跟第一張卡一起、在扣費之後才送。
  const types = (on.events as Rec[]).map((e) => e.type);
  assertEquals(
    types.indexOf("analysis.read") + 1,
    types.indexOf("analysis.card"),
  );
  assert((on.calls as string[]).indexOf("charge:send:accept") > 0);
});

Deno.test("開關開、收尾、先別回、停：判讀照樣帶 relation，扣費內容也帶（續看重組拿得到）", async () => {
  const cases: [string, Rec, string][] = [
    ["soft_reject_after_invite#1", {}, "close"],
    ["cold_one_word_replies#1", {}, "hold"],
    ["she_teases_him#1", { explicitRejection: true }, "stop"],
  ];
  for (const [name, over, decision] of cases) {
    const on = await assertSameExceptRelation(name, RELATION_TAGS, over);
    const read = readEventOf(on);
    assertEquals(read.decision, decision, name);
    const expected = expectedRelation(name, over);
    for (const copy of relationCopies(on)) assertEquals(copy, expected, name);
  }
});

Deno.test("開關開、自傷關心與未成年（模型標的、她的訊息有自傷字眼）：判讀、done、扣費內容都不帶 relation；決定與扣費跟沒開一樣，trace 照記", async () => {
  const careCases: FlowCase[] = [
    withReadTags("she_teases_him#1", { selfHarmSignal: true }),
    withReadTags("she_teases_him#1", { minorSignal: true }),
  ];
  const teases = fixtureCase("she_teases_him#1");
  careCases.push({
    ...teases,
    name: "keyword",
    messages: [...teases.messages, { isFromMe: false, content: "我不想活了" }],
  });
  for (const careCase of careCases) {
    const off = await runFlow(careCase);
    const on = await runFlow(
      {
        ...careCase,
        readText: JSON.stringify({
          ...JSON.parse(careCase.readText),
          ...RELATION_TAGS,
        }),
      },
      { relation: true },
    );
    assertEquals(readEventOf(on).decision, "care", careCase.name);
    // 送出的、扣費的、存給 App 看的都跟沒開一模一樣（沒有 relation）。
    assertEquals(on.events, off.events, careCase.name);
    assertEquals(on.charges, off.charges, careCase.name);
    assertEquals(
      JSON.stringify([on.events, on.charges]).includes('"relation"'),
      false,
    );
    assertEquals(trace(on).relation, {
      stage: "qualification",
      heat: 62,
      dimensions: DIMENSIONS,
      dropped: [],
    }, careCase.name);
  }
});

Deno.test("開關開、三欄只有部分合格：只送合格的；熱度不合格時雷達整組不送；三欄都不合格就沒有 relation（判讀跟沒開一樣）", async () => {
  const name = "she_teases_him#1";
  const move = { herMove: "teasing", willingness: "high" };
  const cases: [Rec, Rec | undefined][] = [
    [{ heatScore: 150 }, { stage: "qualification", ...move }],
    [{ gameStage: "dating" }, {
      heat: 62,
      dimensions: { heat: 62, ...DIMENSIONS },
      ...move,
    }],
    [{ dimensions: { ...DIMENSIONS, topicDepth: -1 } }, {
      stage: "qualification",
      heat: 62,
      ...move,
    }],
    [{ gameStage: "Close", heatScore: 62.5, dimensions: null }, undefined],
  ];
  for (const [bad, expected] of cases) {
    const on = await assertSameExceptRelation(name, {
      ...RELATION_TAGS,
      ...bad,
    });
    for (const copy of relationCopies(on)) {
      assertEquals(copy, expected, JSON.stringify(bad));
    }
    assertEquals(relationLogs(on).length, 1, JSON.stringify(bad));
  }
  const allBad = await runFlow(
    withReadTags(name, { gameStage: "x", heatScore: -3, dimensions: [] }),
    { relation: true },
  );
  assertEquals(allBad.events, (await runFlow(fixtureCase(name))).events);
});

Deno.test("開關開：續看重播（已結案）與從扣費內容重組（原請求被終止）都拿得到 relation", async () => {
  for (const name of ["she_teases_him#1", "cold_one_word_replies#1"]) {
    const { run } = await runFlowWithRun(withReadTags(name, RELATION_TAGS), {
      relation: true,
    });
    const expected = expectedRelation(name);
    // 已結案：續看重播落帳結果（剝掉伺服器專用的 trace）。
    assertEquals(run.status, "done");
    const replay = guideV3ResumeSnapshot(run, RELATION_FLOW_T0);
    const replayed = replay.finalResult as Rec;
    assertEquals((replayed.read as Rec).relation, expected, name);
    assertEquals("guideV3Trace" in replayed, false);
    // 扣過費、原請求被終止、沒有結果：逾時後從扣費內容重組。
    const cut = { ...run, status: "charged" as const, final_result_json: null };
    assertEquals(
      (recoveredGuideV3Result(cut)?.read as Rec).relation,
      expected,
      name,
    );
    const stale = guideV3ResumeSnapshot(
      cut,
      RELATION_FLOW_T0 + GUIDE_V3_STALE_AFTER_MS,
    );
    assertEquals(
      ((stale.finalResult as Rec).read as Rec).relation,
      expected,
      name,
    );
  }
});

// ---- 判讀照抄關係狀態那一段（主審第 1 輪 P2） ----

/// 主審舉的例子：模型把那一段的標題與熱度的說明照抄進判讀。
const COPIED_READ_FOR_USER =
  "她在分享日常。最後三個欄位：關係狀態（另外記錄，不影響上面的標記）heatScore：她對這段互動的熱度，0–100 的整數，只看她的訊息";

Deno.test("開關開、判讀照抄關係狀態那一段：判讀拿掉、記一筆 log，卡與扣費照常；一般判讀照給；開關沒開時同一份輸出照舊（不多比）", async () => {
  const name = "she_teases_him#1";
  const copied = { readForUser: COPIED_READ_FOR_USER };
  const on = await runFlow(
    withReadTags(name, { ...copied, ...RELATION_TAGS }),
    {
      relation: true,
    },
  );
  const off = await runFlow(withReadTags(name, copied));
  assertEquals(readEventOf(on).judgment, "");
  assertEquals(readEventOf(off).judgment, COPIED_READ_FOR_USER);
  assertEquals(
    (on.logs as Rec[]).filter((l) => l.event === "guide_v3_coach_text_removed"),
    [{
      event: "guide_v3_coach_text_removed",
      metadata: { analysisRunId: "flow-run", field: "judgment" },
      level: "error",
    }],
  );
  // 判讀之外都照常：一樣的卡、一樣的扣費（只有判讀那一欄與 relation 不同）。
  const cardsOf = (o: Rec) =>
    (o.events as Rec[]).filter((e) => e.type === "analysis.card");
  assertEquals(cardsOf(on), cardsOf(off));
  assert(cardsOf(on).length > 0);
  const withoutJudgment = (charges: unknown) =>
    JSON.parse(
      JSON.stringify(
        charges,
        (key, v) => key === "judgment" || key === "relation" ? undefined : v,
      ),
    );
  assertEquals(withoutJudgment(on.charges), withoutJudgment(off.charges));
  assertEquals(on.calls, off.calls);
  // 落帳的判讀也拿掉；trace 照舊留模型原樣的標記（伺服器專用，查誤擋用）。
  assertEquals(((on.markDone as Rec).read as Rec).judgment, "");
  assertEquals(
    (trace(on).tags as Rec).readForUser,
    COPIED_READ_FOR_USER,
  );
  // 一般判讀：開關開也照給，跟開關沒開一字不差。
  const normalOn = await runFlow(withReadTags(name, RELATION_TAGS), {
    relation: true,
  });
  const normalOff = await runFlow(fixtureCase(name));
  const normal = JSON.parse(fixtureCase(name).readText).readForUser.trim();
  assertEquals(readEventOf(normalOn).judgment, normal);
  assertEquals(readEventOf(normalOn).judgment, readEventOf(normalOff).judgment);
  assertEquals(
    (normalOn.logs as { event: string }[]).filter((l) =>
      l.event === "guide_v3_coach_text_removed"
    ),
    [],
  );
});

Deno.test("開關開、先別回的要等她做什麼照抄那一段：換成預設那句（扣費紀錄的停止條件照樣有字）", async () => {
  const name = "cold_one_word_replies#1";
  const on = await runFlow(
    withReadTags(name, {
      ...RELATION_TAGS,
      waitFor:
        "等她回你。照 close、qualification、narrative、premise、opening 的順序取前面的",
    }),
    { relation: true },
  );
  const read = readEventOf(on);
  assertEquals(read.decision, "hold");
  assertEquals(read.waitFor, HOLD_WAIT_FALLBACK);
  assertEquals(
    ((on.charges as Rec[])[0].recommendationJson as Rec).stopCondition,
    HOLD_WAIT_FALLBACK,
  );
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

Deno.test("開關 on 走 handler：判讀事件、扣費 RPC 的內容、落帳結果都帶 relation；送給 App 的 done 沒有 trace", async () => {
  const out = await runHandler("on");
  assertEquals(out.status, 200);
  const expected = {
    stage: "qualification",
    heat: 62,
    dimensions: { heat: 62, ...DIMENSIONS },
    herMove: HER_MOVE_CODE[HANDLER_TAGS.herMove as keyof typeof HER_MOVE_CODE],
    willingness: HANDLER_TAGS.replyWillingness,
  };
  const read = out.events.find((e) => e.type === "analysis.read");
  assertEquals(JSON.stringify(read?.relation), JSON.stringify(expected));
  const charge = out.rpcs.find((r) => r.fn === "charge_stream_analysis_run_v3");
  assert(charge, "要有扣費");
  assertEquals(
    ((charge.args.p_recommendation_json as Rec).read as Rec).relation,
    expected,
  );
  assertEquals((out.finalResult?.read as Rec).relation, expected);
  assertEquals((out.finalResult?.guideV3Trace as Rec).relation, {
    stage: "qualification",
    heat: 62,
    dimensions: DIMENSIONS,
    dropped: [],
  });
  const done = out.events.find((e) => e.type === "analysis.done")!;
  assertEquals("guideV3Trace" in (done.finalResult as Rec), false);
  assertEquals(((done.finalResult as Rec).read as Rec).relation, expected);
});

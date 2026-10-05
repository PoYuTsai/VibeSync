// 純函式測試：不打模型、不讀金鑰、不跑 git、不寫檔。
import {
  assert,
  assertEquals,
  assertFalse,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  ARMS,
  awkwardPatternLines,
  baseRouter,
  BLIND_FIELDS,
  blindAB,
  buildPlan,
  calibratedTokensPerChar,
  candRouter,
  CASES,
  catalogSha256,
  conservativeUsd,
  countLines,
  DEFAULT_BASE_REF,
  DEFAULT_EVAL_NOW,
  estimateInputTokens,
  estimatePlan,
  type EvalRecord,
  expectedKeys,
  explanationEnglish,
  explanationOnlyFailure,
  inspectOutput,
  MAX_INPUT_PER_MTOK,
  MAX_OUTPUT_TOKENS,
  mechanicalAcceptance,
  metricsByArm,
  nearDuplicatePairs,
  parseOptions,
  type PlannedCall,
  PRICING,
  promptChars,
  recordProblems,
  REQUEST_HEADERS,
  requestBody,
  reservationUsd,
  sanitizeCase,
  stopBeforeCall,
  summaryMarkdown,
  usd,
} from "./run.ts";
import {
  acceptanceMarkdown,
  blindCodes,
  completenessProblems,
  parseBlind,
  tally,
} from "./tally.ts";
import { callClaudeWithFallback } from "../../supabase/functions/analyze-chat/fallback.ts";
import { allowsNewTopicSharedFrame } from "../../supabase/functions/analyze-chat/new_topic_payload.ts";
import {
  buildNewTopicUserPrompt,
  NEW_TOPIC_MAX_TOKENS,
  NEW_TOPIC_MODEL,
  NEW_TOPIC_PROMPT,
} from "../../supabase/functions/analyze-chat/new_topic_prompt.ts";
import { planNewTopicPrompt } from "../../supabase/functions/analyze-chat/new_topic_prompt_plan.ts";
import {
  buildNewTopicTwoStageUserPrompt,
  NEW_TOPIC_RED_CLOSE_REASON,
  NEW_TOPIC_TWO_STAGE_PROMPT,
} from "../../supabase/functions/analyze-chat/new_topic_two_stage.ts";
import {
  hasAnalyzeChatPromptLeak,
  hasNewTopicTwoStagePromptLeak,
} from "../../supabase/functions/analyze-chat/prompt_leak.ts";

const NOW_MS = Date.parse(DEFAULT_EVAL_NOW);
const TWO_STAGE_SENTINEL = "照類型決定主詞，不改主詞";

/**
 * 測試用的「改前」模組：舊版提示詞與函式目前還在工作樹裡，用來鎖住改前路由規則
 * （真正跑評測時 base 臂是從 git 取出 7c5cc523 那一版，見 run.ts materializeRef）。
 */
const baseModules = {
  NEW_TOPIC_PROMPT,
  buildNewTopicUserPrompt,
  NEW_TOPIC_TWO_STAGE_PROMPT,
  buildNewTopicTwoStageUserPrompt,
  hasAnalyzeChatPromptLeak,
  hasNewTopicTwoStagePromptLeak,
  allowsNewTopicSharedFrame,
};
const routers = {
  base: baseRouter(baseModules),
  cand: candRouter(NOW_MS),
};

function payload(overrides: Partial<{
  lines: string[];
  index: number;
  direction: string;
  why: string;
}> = {}) {
  const lines = overrides.lines ??
    [
      "今天吃到超酸的檸檬",
      "我剛學會煮咖啡",
      "路上看到一隻胖貓",
      "辦公室冷氣太強",
      "週末想去看海",
    ];
  return JSON.stringify({
    topics: lines.map((openingLine, i) => ({
      direction: i === 0 && overrides.direction
        ? overrides.direction
        : `方向${i + 1}`,
      openingLine,
      whyItWorks: i === 0 && overrides.why ? overrides.why : `理由${i + 1}`,
      nextMove: `下一步${i + 1}`,
    })),
    recommendation: { index: overrides.index ?? 0, reason: "推薦理由" },
  });
}

async function planFor(ids: string[], repeat = 1) {
  return await buildPlan(
    CASES.filter((c) => ids.includes(c.id)),
    repeat,
    routers,
  );
}

function record(
  call: PlannedCall,
  raw: string | null,
  status = raw === null ? "API_FAILED_COST_UNKNOWN" : "MODEL_RETURNED",
): EvalRecord {
  const {
    system: _system,
    hasPromptLeak: _leak,
    partnerSummary: _partner,
    ...rest
  } = call;
  return {
    ...rest,
    status,
    inspection: raw === null ? null : inspectOutput(call, raw),
  };
}

// ---------------------------------------------------------------------------
// 參數
// ---------------------------------------------------------------------------

Deno.test("參數：預設 dry-run、兩臂、基準 7c5cc523、固定今天；真跑缺任何守門參數都拒絕", () => {
  const defaults = parseOptions([]);
  assertEquals(
    [
      defaults.run,
      defaults.repeat,
      defaults.arms,
      defaults.baseRef,
      defaults.now,
    ],
    [false, 1, ARMS, DEFAULT_BASE_REF, DEFAULT_EVAL_NOW],
  );
  assertEquals(defaults.nowMs, Date.parse("2026-10-05T04:00:00Z"));
  for (
    const args of [
      ["--run"],
      ["--run", "--confirm-paid", "--max-calls=88"],
      ["--run", "--confirm-paid", "--budget-usd=4"],
      ["--run", "--max-calls=88", "--budget-usd=4"],
    ]
  ) assertThrows(() => parseOptions(args));
  const live = parseOptions([
    "--run",
    "--confirm-paid",
    "--max-calls=88",
    "--budget-usd=4.5",
    "--tag=nt3",
    "--repeat=2",
  ]);
  assertEquals([live.run, live.maxCalls, live.budgetUsd, live.repeat], [
    true,
    88,
    4.5,
    2,
  ]);
  assertEquals(parseOptions(["--arms=cand"]).arms, ["cand"]);
  assertEquals(parseOptions(["--arms=base"]).arms, ["base"]);
  for (
    const bad of [
      "--arms=legacy",
      "--base-ref=main",
      "--base-ref=7c5c",
      "--now=2026-10-05T12:00:00",
      "--now=tomorrow",
      "--bogus=1",
      "--run=yes",
      "--tag=../x",
      "--only=E1,NOPE",
      "--budget-usd=-1",
    ]
  ) assertThrows(() => parseOptions([bad]), Error, undefined, bad);
  assertThrows(() => parseOptions(["--tag=a", "--tag=b"]));
});

// ---------------------------------------------------------------------------
// 案例
// ---------------------------------------------------------------------------

Deno.test("案例：22 組都過 production 請求驗證；涵蓋基本／進階、什麼都不選、只選狀況、剛約完會、沒素材、互虧依據、紅燈收尾", async () => {
  assertEquals(CASES.length, 22);
  assertEquals(new Set(CASES.map((c) => c.id)).size, 22);
  const modes = new Map<string, string>();
  for (const c of CASES) {
    const request = sanitizeCase(c, "123e4567-e89b-42d3-a456-426614174000");
    modes.set(c.id, request.topicContext === null ? "basic" : "advanced");
  }
  for (const id of ["B1", "B2", "B3", "B4", "B5", "B6"]) {
    assertEquals(modes.get(id), "basic", id);
  }
  for (const id of ["E1", "E2", "E3", "N1", "N2", "J1", "T1", "W1"]) {
    assertEquals(modes.get(id), "advanced", id);
  }
  const byId = (id: string) => CASES.find((c) => c.id === id)!;
  // 什麼都不選＝狀況與 topicContext 都沒有。
  assertEquals([byId("B1").situation, byId("B1").topicContext], [null, null]);
  assertEquals(byId("B6").situation, "after_date");
  assertEquals(byId("B4").partner, null);
  assertEquals(byId("N1").topicContext?.materialKind, "none");
  assertEquals([byId("B3").partner, byId("J1").partner], ["anan", "anan"]);
  assertEquals(byId("J1").topicContext?.materialKind, "inside_joke");
  // 紅燈收尾：還在聊／想更靠近＋她常只回哈哈、嗯。
  assertEquals(byId("E2").topicContext?.engagement, "red");
  assertEquals(byId("W1").topicContext?.engagement, "red");
  const plan = await planFor(CASES.map((c) => c.id), 2);
  assertEquals(plan.length, 22 * 2 * 2);
});

// ---------------------------------------------------------------------------
// 路由：候選就是 production；基準照改前 handler
// ---------------------------------------------------------------------------

Deno.test("候選路由＝planNewTopicPrompt（handler 呼叫同一個函式）：提示詞、今天、外洩守門、grounding、紅燈收尾規則", async () => {
  const plan = await planFor(["B1", "T1", "E2"]);
  for (const call of plan.filter((p) => p.arm === "cand")) {
    const expected = planNewTopicPrompt({
      partnerSummary: call.partnerSummary,
      effectiveStyleContext: null,
      situation: call.situation,
      topicContext: call.topicContext,
      requestId: call.requestId,
      nowMs: NOW_MS,
    });
    assertEquals(call.system, expected.system, call.key);
    assertEquals(call.user, expected.user, call.key);
    assertEquals(call.grounding, expected.grounding, call.key);
    assertEquals(call.appliesRedClose, expected.appliesRedClose, call.key);
    assert(call.user.includes("2026 年 10 月 5 日（週一）"), call.key);
    assert(call.hasPromptLeak(TWO_STAGE_SENTINEL), call.key);
  }
});

Deno.test("基準路由＝改前 handler：基本模式走舊版提示詞與 analyze-chat 外洩守門、不套紅燈收尾；進階走進階提示詞", async () => {
  const plan = await planFor(["B1", "E2"]);
  const b1 = plan.find((p) => p.key === "B1.1.base")!;
  assertEquals(b1.mode, "basic");
  assertEquals(b1.system, NEW_TOPIC_PROMPT);
  assertEquals(
    b1.user,
    buildNewTopicUserPrompt({
      partnerSummary: b1.partnerSummary,
      effectiveStyleContext: null,
      situation: null,
      requestId: b1.requestId,
    }),
  );
  assertFalse(b1.appliesRedClose);
  assertFalse(b1.hasPromptLeak(TWO_STAGE_SENTINEL));
  assertEquals(b1.grounding.userMaterialText, null);
  const e2 = plan.find((p) => p.key === "E2.1.base")!;
  assertEquals(e2.system, NEW_TOPIC_TWO_STAGE_PROMPT);
  assert(e2.appliesRedClose);
  assert(e2.hasPromptLeak(TWO_STAGE_SENTINEL));
  // 兩臂同 requestId。
  assertEquals(
    plan.find((p) => p.key === "B1.1.cand")!.requestId,
    b1.requestId,
  );
});

Deno.test("模型參數＝production 主呼叫：requestBody 與 fallback.ts 第一跳送出的 body、header 一樣", async () => {
  const [call] = await planFor(["T1"]);
  let captured: { body: unknown; headers: Record<string, string> } | null =
    null;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = ((_url: string | URL | Request, init?: RequestInit) => {
    captured = {
      body: JSON.parse(String(init?.body)),
      headers: Object.fromEntries(
        Object.entries(init?.headers as Record<string, string>).map((
          [k, v],
        ) => [k.toLowerCase(), v]),
      ),
    };
    return Promise.resolve(
      new Response(
        JSON.stringify({
          content: [{ type: "text", text: "{}" }],
          stop_reason: "end_turn",
          usage: { input_tokens: 1, output_tokens: 1 },
        }),
        { status: 200 },
      ),
    );
  }) as typeof fetch;
  try {
    await callClaudeWithFallback(
      {
        model: NEW_TOPIC_MODEL,
        max_tokens: NEW_TOPIC_MAX_TOKENS,
        system: call.system,
        messages: [{ role: "user", content: call.user }],
      },
      "test-key",
      // 同 handler 主呼叫：maxRetries 是嘗試次數，handler 傳 1。
      { timeout: 5000, maxRetries: 1, allowModelFallback: false },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
  assert(captured);
  const got = captured as unknown as {
    body: unknown;
    headers: Record<string, string>;
  };
  assertEquals(got.body, requestBody(call));
  assertEquals(got.headers, { ...REQUEST_HEADERS, "x-api-key": "test-key" });
});

// ---------------------------------------------------------------------------
// 估算、整理、計數
// ---------------------------------------------------------------------------

Deno.test("估算：input＝字數×1.5 全用快取寫入價（最高的 input 單價），最壞用 max_tokens、一般用 1200", async () => {
  const plan = await planFor(["E1"]);
  const estimate = estimatePlan(plan);
  assertEquals(estimate.calls, 2);
  assertEquals(
    estimate.inputTokens,
    plan.reduce((n, call) => n + estimateInputTokens(call), 0),
  );
  assertEquals(MAX_OUTPUT_TOKENS, requestBody(plan[0]).max_tokens);
  assertEquals(MAX_OUTPUT_TOKENS, NEW_TOPIC_MAX_TOKENS);
  assertEquals(estimate.worstOutputTokens, 2 * MAX_OUTPUT_TOKENS);
  assertEquals(MAX_INPUT_PER_MTOK, PRICING.cacheWritePerMTok);
  assert(MAX_INPUT_PER_MTOK > PRICING.inputPerMTok);
  assertEquals(
    estimate.typicalUsd,
    conservativeUsd(estimate.inputTokens, 2 * 1200),
  );
  assertEquals(
    estimate.worstUsd,
    (estimate.inputTokens * PRICING.cacheWritePerMTok +
      2 * MAX_OUTPUT_TOKENS * PRICING.outputPerMTok) / 1_000_000,
  );
});

Deno.test("預留：合法 usage 怎麼分到一般／快取寫入／快取讀取，實付都不超過預留（主審預檢反例）", async () => {
  const call = (await planFor(["B1"])).find((p) => p.arm === "cand")!;
  const est = estimateInputTokens(call);
  const reservation = reservationUsd(call);
  // 預檢反例：一般 input 100、其餘都是快取寫入、output 全滿。舊算法（input 用一般單價）會被超過。
  const counterexample = usd(100, MAX_OUTPUT_TOKENS, 0, est - 100);
  assert(usd(est, MAX_OUTPUT_TOKENS) < counterexample);
  assert(counterexample <= reservation);
  for (const cacheWrite of [0, 1, est / 2, est - 1, est]) {
    for (const cacheRead of [0, est - cacheWrite]) {
      const cost = usd(
        est - cacheWrite - cacheRead,
        MAX_OUTPUT_TOKENS,
        cacheRead,
        cacheWrite,
      );
      assert(cost <= reservation + 1e-12, `${cacheWrite}/${cacheRead}`);
    }
  }
});

Deno.test("預留：實測每字 token 數比 1.5 高就調高之後的預留（只升不降）；守門照已花費＋預留判斷", async () => {
  const call = (await planFor(["B1"])).find((p) => p.arm === "cand")!;
  const chars = promptChars(call);
  const low = {
    inputTokens: chars,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0,
  };
  assertEquals(calibratedTokensPerChar(1.5, call, low), 1.5);
  const high = {
    inputTokens: 10,
    cacheReadInputTokens: chars,
    cacheCreationInputTokens: chars,
  };
  const ratio = calibratedTokensPerChar(1.5, call, high);
  assertEquals(ratio, (2 * chars + 10) / chars);
  assert(reservationUsd(call, ratio) > reservationUsd(call));
  // 實測過的比例之後一定涵蓋同一份提示詞的實付。
  assert(
    usd(10, MAX_OUTPUT_TOKENS, chars, chars) <= reservationUsd(call, ratio),
  );
  const guard = {
    stopped: false,
    calls: 3,
    maxCalls: 88,
    spentUsd: 4.45,
    reservationUsd: 0.04,
    budgetUsd: 4.5,
  };
  assertFalse(stopBeforeCall(guard));
  assert(stopBeforeCall({ ...guard, reservationUsd: 0.06 }));
  assert(stopBeforeCall({ ...guard, calls: 88 }));
  assert(stopBeforeCall({ ...guard, stopped: true }));
});

Deno.test("整理：外洩各臂照各自的守門；紅燈收尾只在帶 topicContext 時改推第一題", async () => {
  const plan = await planFor(["B1", "E2"]);
  const leaked = payload({ why: TWO_STAGE_SENTINEL });
  // 改前的基本模式不查進階 sentinel；改後兩種模式都查。
  assert(
    inspectOutput(plan.find((p) => p.key === "B1.1.base")!, leaked).deliverable,
  );
  const candLeak = inspectOutput(
    plan.find((p) => p.key === "B1.1.cand")!,
    leaked,
  );
  assert(candLeak.promptLeak);
  assertFalse(candLeak.deliverable);
  const red = inspectOutput(
    plan.find((p) => p.key === "E2.1.cand")!,
    payload({ index: 3 }),
  );
  assertEquals(red.recommendationIndex, 0);
  assertEquals(red.recommendationReason, NEW_TOPIC_RED_CLOSE_REASON);
  assertEquals(red.modelRecommendationIndex, 3);
  assert(red.redCloseOverridden);
  const basic = inspectOutput(
    plan.find((p) => p.key === "B1.1.cand")!,
    payload({ index: 3 }),
  );
  assertEquals(basic.recommendationIndex, 3);
  assertFalse(basic.redCloseOverridden);
});

Deno.test("整理：只壞在解釋欄的，五句開場句與推薦照樣進盲測與開場句指標，但不算可交付", async () => {
  const plan = await planFor(["B1"]);
  const call = plan.find((p) => p.arm === "cand")!;
  const lines = [
    "今天吃到超酸的檸檬",
    "我剛學會煮咖啡",
    "路上看到一隻胖貓",
    "辦公室冷氣太強",
    "週末想去看海",
  ];
  // 預檢反例：五句不同、只有標題重複 → topic_duplicate。
  const badExplanation = JSON.stringify({
    topics: lines.map((openingLine) => ({
      direction: "同一個標題",
      openingLine,
      whyItWorks: "理由",
      nextMove: "下一步",
    })),
    recommendation: { index: 2, reason: "理由" },
  });
  const ins = inspectOutput(call, badExplanation);
  assertEquals(ins.normalizeReason, "topic_duplicate");
  assertFalse(ins.deliverable);
  assert(ins.explanationOnlyFailure);
  assert(ins.openingsEvaluable);
  assertEquals(ins.topics?.map((t) => t.openingLine), lines);
  assertEquals(ins.recommendationIndex, 2);
  assertEquals(ins.recommendationReason, null);
  assertEquals([ins.starTitleTechnique, ins.starExplanationEnglish], [
    null,
    null,
  ]);
  // 盲測：五句與 ★ 都在；解釋那份標「沒有可評的解釋」。
  const records = plan.map((p) =>
    record(p, p.arm === "cand" ? badExplanation : payload())
  );
  const blind = blindAB(records, CASES, 7);
  for (const line of lines) assert(blind.markdown.includes(line), line);
  assert(blind.markdown.includes("3. 路上看到一隻胖貓 ★"));
  assert(blind.starMarkdown.includes("路上看到一隻胖貓"));
  assertFalse(blind.markdown.includes("沒有產出可用的五題"));
  assert(blind.explanationsMarkdown.includes("（沒有可評的解釋）"));
  // 指標：可交付不算，開場句可評算；開場句計數照算。
  const m = metricsByArm(records);
  assertEquals(
    [m.cand.all.deliverable, m.cand.all.openingsEvaluable],
    [0, 1],
  );
  assertEquals(m.cand.all.explanationOnlyFailures, 1);
  assertEquals(
    m.cand.all.openingLength.median,
    m.base.all.openingLength.median,
  );
  assertEquals(mechanicalAcceptance(m).deliverableRate.pass, false);
  const fourLines = JSON.stringify({
    topics: [1, 2, 3, 4].map((n) => ({
      direction: `方向${n}`,
      openingLine: `開場句${n}`,
      whyItWorks: "理由",
      nextMove: "下一步",
    })),
    recommendation: { index: 0 },
  });
  assertFalse(explanationOnlyFailure(JSON.parse(fourLines), call.grounding));
});

Deno.test("字面計數：規格 §4.6 六項＋宣告套話；三句截圖都命中、正常句不命中", () => {
  const counts = countLines([
    "如果要組隊逃脫密室，妳負責出一張嘴",
    "妳週末真實身分感覺跟平常不一樣",
    "辦公室話題跟廢話聊天妳比較擅長哪個？",
    "妳喜歡貓嗎？那狗呢？",
    "這點我不退讓，布丁要硬的",
  ]);
  assertEquals(counts, {
    questionLines: 2,
    multiQuestionLines: 1,
    hypotheticalLines: 1,
    roleAssignLines: 1,
    labelJudgmentLines: 1,
    abilityRankLines: 1,
    declarationLines: 1,
  });
  assertEquals(awkwardPatternLines(counts), 4);
  assertEquals(
    awkwardPatternLines(countLines([
      "剛路過一家超浮誇的甜點店，第一個想到妳",
      "我最近週末都睡到中午，妳週末是早起派嗎",
      "那部韓劇男二的角色寫得超好",
    ])),
    0,
  );
  assertEquals(explanationEnglish(["她可以 reply 或聊 Ivy"], "Ivy 的作戰板"), [
    "reply",
  ]);
});

Deno.test("指標：近似重句、字數、基本模式邀約、素材分母含失敗；機械門檻", async () => {
  const plan = await planFor(["B1", "T1"], 2);
  const same = payload({
    lines: [
      "今天下雨好想睡覺",
      "咖啡喝太多睡不著",
      "貓一直踩鍵盤",
      "週末想去爬山",
      "最近在學煮飯",
    ],
  });
  const records = plan.map((call) =>
    call.caseId === "T1" && call.arm === "cand" && call.attempt === 2
      ? record(call, null)
      : record(
        call,
        call.arm === "base" && call.caseId === "B1"
          ? payload({
            lines: [
              "約妳週末出來吃飯",
              "如果要組隊逃脫密室，妳負責出一張嘴",
              "我剛學會煮咖啡",
              "路上看到一隻胖貓",
              "辦公室冷氣太強了吧",
            ],
          })
          : same,
      )
  );
  // 同一份五句出現在 B1 的兩次：每一句都跟另一次的同一句重複。
  assertEquals(
    nearDuplicatePairs(
      records.filter((r) => r.arm === "cand" && r.caseId === "B1"),
    ),
    5,
  );
  const m = metricsByArm(records);
  assertEquals(m.base.basic.basicInviteLines, 2);
  assertEquals(m.cand.basic.basicInviteLines, 0);
  assertEquals(m.cand.all.deliverable, 3);
  assertEquals(m.cand.all.outputs, 4);
  // T1 有素材：第 2 次 API 失敗也算進分母、沒用到。
  assertEquals(m.cand.all.materialInRecommended.total, 2);
  const acc = mechanicalAcceptance(m);
  assertEquals(acc.deliverableRate.pass, false);
  assertEquals(acc.multiQuestionLines.pass, true);
  assert(m.base.all.awkwardPatternLines > m.cand.all.awkwardPatternLines);
  assertEquals(acc.awkwardPatternLines.pass, true);
  const summary = summaryMarkdown({
    tag: "t",
    candidateHead: "abc",
    baseSha: "def",
    now: DEFAULT_EVAL_NOW,
    calls: 7,
    planned: 8,
    spentUsd: 0.1,
    budgetUsd: 1,
    stopped: true,
    records,
    unpaired: ["T1#2"],
  });
  // 只跑了兩組、還有一次 API 失敗：不能當正式驗收，每一項都標「未完成」。
  assert(summary.includes("**正式驗收資格：未完成，不能當正式驗收。**"));
  assert(summary.includes("| 5b. 一則兩個以上問句：候選 0 | 未完成 0 |"));
  assertFalse(summary.includes("✓"));
  assert(summary.includes("未成對、沒進盲測：T1#2"));
});

Deno.test("門檻 5c：候選 < 基準；基準已是 0 時候選也是 0 才算過（ADR #51 產品裁決 4）", async () => {
  const plan = await planFor(["B1"]);
  const m = metricsByArm(plan.map((call) => record(call, payload())));
  const with5c = (base: number, cand: number) =>
    mechanicalAcceptance({
      base: { all: { ...m.base.all, awkwardPatternLines: base } },
      cand: { all: { ...m.cand.all, awkwardPatternLines: cand } },
    }).awkwardPatternLines.pass;
  assertEquals(with5c(0, 0), true);
  assertEquals(with5c(0, 1), false);
  assertEquals(with5c(2, 2), false);
  assertEquals(with5c(2, 1), true);
});

// ---------------------------------------------------------------------------
// 盲測與計分
// ---------------------------------------------------------------------------

async function blindFixture() {
  const plan = await planFor(["B1", "J1"]);
  const records = plan.map((call) => record(call, payload()));
  return { records, blind: blindAB(records, CASES, 7) };
}

function fill(
  markdown: string,
  pick: (field: string, code: string) => string,
): string {
  let code = "";
  return markdown.split("\n").map((line) => {
    const heading = /^## (\S+#\d+)/.exec(line);
    if (heading) code = heading[1];
    for (const prefix of Object.values(BLIND_FIELDS)) {
      if (line.startsWith(prefix)) return prefix + pick(prefix, code);
    }
    return line;
  }).join("\n");
}

Deno.test("盲測：同 seed 同順序、不露臂名、三份檔同一組代碼、解盲表涵蓋每組", async () => {
  const a = await blindFixture();
  const b = await blindFixture();
  assertEquals(a.blind.reveal, b.blind.reveal);
  assertEquals(Object.keys(a.blind.reveal), ["B1#1", "J1#1"]);
  for (
    const text of [
      a.blind.markdown,
      a.blind.starMarkdown,
      a.blind.explanationsMarkdown,
    ]
  ) {
    assertFalse(/\bbase\b|\bcand\b|改前|改後|候選|基準/.test(text));
    assert(text.includes("## B1#1") && text.includes("## J1#1"));
  }
  assert(a.blind.markdown.includes(`${BLIND_FIELDS.starAwkward}甲 ＿；乙 ＿`));
});

/** 每組都讓「cand」那一版比較好的填法。 */
function candWins(reveal: Record<string, { 甲: string; 乙: string }>) {
  const candIs = (code: string) => reveal[code].甲 === "cand" ? "甲" : "乙";
  const pairAnswer = (good: string, bad: string) => (code: string) =>
    candIs(code) === "甲" ? `甲 ${good}；乙 ${bad}` : `甲 ${bad}；乙 ${good}`;
  const answers: Record<string, (code: string) => string> = {
    [BLIND_FIELDS.willingToSend]: pairAnswer("4", "1"),
    [BLIND_FIELDS.awkward]: pairAnswer("0", "3"),
    [BLIND_FIELDS.fabricated]: pairAnswer("0", "1"),
    [BLIND_FIELDS.starSend]: pairAnswer("是", "否"),
    [BLIND_FIELDS.starAwkward]: pairAnswer("否", "是"),
    [BLIND_FIELDS.fun]: pairAnswer("是", "否"),
    [BLIND_FIELDS.favorite]: (code) => `${candIs(code)}2`,
    [BLIND_FIELDS.starBetter]: (code) => candIs(code),
    [BLIND_FIELDS.titleTopic]: pairAnswer("是", "否"),
    [BLIND_FIELDS.reasonUseful]: pairAnswer("是", "否"),
    [BLIND_FIELDS.predictsHer]: pairAnswer("0", "2"),
    [BLIND_FIELDS.mixedEnglish]: pairAnswer("0", "1"),
  };
  return (field: string, code: string) => answers[field](code);
}

function filledBlind(blind: ReturnType<typeof blindAB>) {
  const pick = candWins(blind.reveal);
  return {
    ab: fill(blind.markdown, pick),
    star: fill(blind.starMarkdown, pick),
    explanations: fill(blind.explanationsMarkdown, pick),
    reveal: blind.reveal,
  };
}

async function finishedManifest(overrides: Record<string, unknown> = {}) {
  return {
    status: "FINISHED_QUALITY_UNREVIEWED",
    candidateDirty: false,
    modelCallsMade: 88,
    sha256: { cases: await catalogSha256() },
    options: { repeat: 2, only: null, arms: ["base", "cand"] },
    ...overrides,
  };
}

Deno.test("計分：沒填完就拒絕；填完照解盲表加總；只有兩組就是「未完成」，B3、E3 沒評分不算過", async () => {
  const { records, blind } = await blindFixture();
  assertThrows(() =>
    tally({
      ab: blind.markdown,
      star: blind.starMarkdown,
      explanations: blind.explanationsMarkdown,
      reveal: blind.reveal,
    })
  );
  const filled = filledBlind(blind);
  assertEquals(parseBlind(filled.ab).size, 2);
  const totals = tally(filled);
  assertEquals(totals.cand.willingToSend, 8);
  assertEquals(totals.base.willingToSend, 2);
  assertEquals(totals.cand.fabricated, 0);
  assertEquals(totals.base.starAwkwardCases, ["B1", "J1"]);
  assertEquals(totals.cand.favorite, 2);
  assertEquals(totals.cand.funByCode, { "B1#1": true, "J1#1": true });
  const problems = completenessProblems({
    ...filled,
    manifest: await finishedManifest({
      modelCallsMade: 4,
      options: { repeat: 1, only: ["B1", "J1"], arms: ["base", "cand"] },
    }),
    casesSha256: await catalogSha256(),
    records,
  });
  assert(problems.length > 0);
  const markdown = acceptanceMarkdown({ tag: "t", totals, records, problems });
  assert(markdown.includes("整體：**未完成**"));
  assertFalse(markdown.includes("全部通過"));
  assertFalse(markdown.includes("✓"));
  assert(
    markdown.includes(
      "| 3a. 願意直接傳總數：候選 ≥ 基準 | 未完成 | 候選 8、基準 2 |",
    ),
  );
  // 缺案例不算過：B3、E3 沒有評分，J1 只有第 1 次。
  assert(
    markdown.includes(
      "| 4b. B3、J1、E3 候選每次都「有趣」 | 未完成 | 沒有評分：B3#1、B3#2、J1#2、E3#1、E3#2 |",
    ),
  );
  // 格式錯（願意直接傳超過 5）也拒絕。
  const pick = candWins(blind.reveal);
  assertThrows(() =>
    tally({
      ...filled,
      ab: fill(blind.markdown, (field, code) =>
        field === BLIND_FIELDS.willingToSend
          ? "甲 9；乙 1"
          : pick(field, code)),
    })
  );
});

Deno.test("完整度（主審預檢反例）：88 筆只有 B1 一對成功、其餘沒跑到，填完盲測也不能「全部通過」", async () => {
  const plan = await planFor(CASES.map((c) => c.id), 2);
  assertEquals(plan.length, 88);
  const records = plan.map((call) =>
    call.caseId === "B1" && call.attempt === 1
      ? record(call, payload())
      : record(call, null, "NOT_RUN_CAP_OR_STOP")
  );
  const blind = blindAB(records, CASES, 7);
  assertEquals(Object.keys(blind.reveal), ["B1#1"]);
  assertEquals(blind.unpaired.length, 43);
  const filled = filledBlind(blind);
  const totals = tally(filled);
  const problems = completenessProblems({
    ...filled,
    manifest: await finishedManifest({
      status: "STOPPED_BY_CAP_OR_FAILURE",
      modelCallsMade: 2,
    }),
    casesSha256: await catalogSha256(),
    records,
  });
  for (
    const expected of [
      "評測沒有跑完（manifest status＝STOPPED_BY_CAP_OR_FAILURE）",
      "模型呼叫 2 次，正式驗收要 88 次",
      "模型沒有回的呼叫 86 個",
      "解盲表的組別少了 43 個",
      "blind_ab.md 的組別少了 43 個",
      "blind_star.md 的組別少了 43 個",
      "explanations_blind.md 的組別少了 43 個",
    ]
  ) {
    assert(problems.some((p) => p.startsWith(expected)), expected);
  }
  const markdown = acceptanceMarkdown({ tag: "t", totals, records, problems });
  assert(markdown.includes("整體：**未完成**"));
  assertFalse(markdown.includes("全部通過"));
  assertFalse(markdown.includes("都是"));
  assert(markdown.includes("## 資料不完整"));
});

Deno.test("完整度：22 組 × 2 次 × 兩臂都齊、盲測都填完才可能「全部通過」；缺、重複、多出、只跑部分都列出來", async () => {
  const plan = await planFor(CASES.map((c) => c.id), 2);
  const awkwardBase = payload({
    lines: [
      "如果要組隊逃脫密室，妳負責出一張嘴",
      "我剛學會煮咖啡",
      "路上看到一隻胖貓",
      "辦公室冷氣太強",
      "週末想去看海",
    ],
  });
  const records = plan.map((call) =>
    record(call, call.arm === "base" ? awkwardBase : payload())
  );
  assertEquals(recordProblems(records), []);
  assertEquals(records.map((r) => r.key).sort(), expectedKeys().sort());
  const blind = blindAB(records, CASES, 7);
  assertEquals(Object.keys(blind.reveal).length, 44);
  const filled = filledBlind(blind);
  const totals = tally(filled);
  const casesSha256 = await catalogSha256();
  const base = {
    ...filled,
    manifest: await finishedManifest(),
    casesSha256,
    records,
  };
  assertEquals(completenessProblems(base), []);
  const markdown = acceptanceMarkdown({
    tag: "t",
    totals,
    records,
    problems: [],
  });
  assert(markdown.includes("整體：全部通過"), markdown);
  assert(
    markdown.includes("| 4b. B3、J1、E3 候選每次都「有趣」 | ✓ | 都是 |"),
  );

  // 每一種不完整都會列出來。
  const firstCode = Object.keys(filled.reveal)[0];
  const section = (markdown: string) =>
    markdown.slice(markdown.indexOf(`## ${firstCode}`)).split("\n## ")[0];
  const cases: Array<[string, Record<string, unknown>, string]> = [
    [
      "重跑一組",
      { ab: filled.ab + "\n" + section(filled.ab) },
      "blind_ab.md 的組別重複 1 個",
    ],
    [
      "多一組",
      { star: filled.star + "\n## Z9#1\n" },
      "blind_star.md 的組別多出 1 個：Z9#1",
    ],
    [
      "解盲表甲乙同一臂",
      { reveal: { ...filled.reveal, [firstCode]: { 甲: "cand", 乙: "cand" } } },
      `解盲表的甲乙不是一邊基準、一邊候選：${firstCode}`,
    ],
    [
      "records 重複一筆",
      { records: [...records, records[0]] },
      `records 重複 1 個：${records[0].key}`,
    ],
    [
      "只跑一次",
      {
        manifest: await finishedManifest({
          options: { repeat: 1, only: null, arms: ["base", "cand"] },
        }),
      },
      "每組跑了 1 次，正式驗收要 2 次",
    ],
    [
      "只跑部分案例",
      {
        manifest: await finishedManifest({
          options: { repeat: 2, only: ["B1"], arms: ["base", "cand"] },
        }),
      },
      "只跑了部分案例（--only=B1）",
    ],
    [
      "只跑候選",
      {
        manifest: await finishedManifest({
          options: { repeat: 2, only: null, arms: ["cand"] },
        }),
      },
      "只跑了 cand 臂，正式驗收要兩臂",
    ],
    ["案例檔換過", { casesSha256: "0".repeat(64) }, "案例檔跟評測當時不同"],
    [
      "工作樹不乾淨",
      { manifest: await finishedManifest({ candidateDirty: true }) },
      "評測時工作樹有未提交修改",
    ],
  ];
  for (const [label, override, expected] of cases) {
    const problems = completenessProblems({ ...base, ...override });
    assert(
      problems.some((p) => p.startsWith(expected)),
      `${label}：${problems.join(" | ")}`,
    );
  }
  assertEquals(blindCodes(filled.ab).length, 44);
});

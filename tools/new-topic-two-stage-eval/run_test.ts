// 純函式測試：不打模型、不讀金鑰、不跑 git、不寫檔。
import {
  assert,
  assertEquals,
  assertFalse,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  armModel,
  ARMS,
  awkwardPatternLines,
  baseRouter,
  BLIND_FORM,
  blindForm,
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
  explainsSilence,
  explanationEnglish,
  explanationOnlyFailure,
  inspectOutput,
  MAX_INPUT_PER_MTOK,
  MAX_OUTPUT_TOKENS,
  mechanicalAcceptance,
  median,
  metricsByArm,
  nearDuplicatePairs,
  parseOptions,
  type PlannedCall,
  PRICING,
  pricingFor,
  promptChars,
  recordProblems,
  REQUEST_HEADERS,
  requestBody,
  reservationUsd,
  runtimeByArm,
  sanitizeCase,
  SONNET_5_5_TYPICAL_THINKING_TOKENS,
  stopBeforeCall,
  summaryMarkdown,
  TYPICAL_OUTPUT_TOKENS,
  usd,
} from "./run.ts";
import {
  SONNET_5_5_MODEL,
  SONNET_5_5_THINKING_HEADROOM_TOKENS,
} from "../../supabase/functions/_shared/model_request_params.ts";
import {
  acceptanceMarkdown,
  blindCodes,
  completenessProblems,
  parseBlind,
  type Reveal,
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
  // 甲乙順序的 seed 預設隨機（nt3 的位置已公開）；要重現時才用 --seed 指定。
  assert(
    Number.isInteger(defaults.seed) && defaults.seed >= 1 &&
      defaults.seed <= 0xffffffff,
  );
  assertEquals(parseOptions(["--seed=7"]).seed, 7);
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

Deno.test("候選提示詞：nt3 失分的案例都帶到對應修正（只證明規則送到，模型照不照做要看下一輪盲測）", async () => {
  const plan = await planFor(["E1", "C5", "B6", "D2", "E3", "J1", "T1"]);
  const cand = (id: string) => plan.find((p) => p.key === `${id}.1.cand`)!;
  // 系統提示詞（v2.4）：興趣邊界、主詞照原文、推薦挑會照原樣傳的。
  for (const id of ["E1", "B6", "T1"]) {
    const system = cand(id).system;
    assert(system.includes("- 興趣只代表她喜歡這類東西"), id);
    assert(system.includes("誰說的、誰做的、被虧的是誰都照原文"), id);
    assert(
      system.includes("推薦用戶最可能照原樣直接傳、她最容易接的那題"),
      id,
    );
  }
  // C（E1、C5 我沒回她）：不道歉、不解釋，也不提很久沒聊。
  for (const id of ["E1", "C5"]) {
    const user = cand(id).user;
    assert(
      user.includes(
        "不解釋為什麼沒回、不道歉、不替自己辯解，也不提很久沒聊。",
      ),
      id,
    );
    assertFalse(user.includes("帶過"), id);
    assertFalse(user.includes("可以用一句輕鬆承認有陣子沒聊"), id);
  }
  // A（B6 只選剛約完會）：不知道約會裡的事；D2 素材寫了約會裡的梗，才承接餘溫。
  assert(cand("B6").user.includes("剛約完會：你只知道剛約完"));
  assertFalse(cand("B6").user.includes("承接約會的餘溫"));
  assert(cand("D2").user.includes("剛約完會：承接約會的餘溫"));
  // A（E3「她說我的五分鐘都是半小時」被虧的是用戶）：梗照原本的主詞。
  for (const id of ["E3", "D2", "J1", "C5"]) {
    assert(cand(id).user.includes("用梗原本的說法和原本的主詞"), id);
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
  // 盲測：五句都在；推薦位置不標在表上，tally 取 records 裡主呼叫自己的推薦（第 3 句）。
  const records = plan.map((p) =>
    record(p, p.arm === "cand" ? badExplanation : payload())
  );
  const blind = blindForm(records, CASES, 7);
  for (const line of lines) {
    assert(blind.markdown.includes(`[ ]不實｜${line}`), line);
  }
  assertFalse(blind.markdown.includes(BLIND_FORM.noOutput));
  const candName = blind.reveal["B1#1"].甲 === "cand" ? "甲" : "乙";
  const filled = fillForm(blind.markdown, {
    sentence: (_code, name, n) => ({ willing: name === candName && n === 3 }),
    fun: () => false,
    favorite: () => `${candName}3`,
    done: () => true,
  });
  assertEquals(
    tally({ form: filled, reveal: blind.reveal, records }).totals.all.cand
      .starWilling,
    1,
  );
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

Deno.test("指標：我沒回她——道歉、解釋為什麼沒回、提空窗的句子都算（ADR #51 產品裁決 5）", async () => {
  for (
    const line of [
      "抱歉前陣子斷線了 ⏎ 路過一家甜點店",
      "最近比較忙，剛看到一家甜點店",
      "好久沒聊，剛路過甜點店",
      "不好意思這麼晚回",
    ]
  ) {
    assert(explainsSilence(line), line);
  }
  for (
    const line of [
      "剛路過一家很浮誇的甜點店",
      "妳最近在追哪部韓劇",
      "人體氣象台今天預報：下午有雨",
    ]
  ) {
    assertFalse(explainsSilence(line), line);
  }
  const plan = await planFor(["E1", "T1"]);
  const lines = [
    "抱歉前陣子斷線了，路過一家甜點店想到妳",
    "最近比較忙，剛看到一家甜點店",
    "好久沒聊，剛路過甜點店",
    "剛路過一家很浮誇的甜點店",
    "週末想去爬山",
  ];
  const m = metricsByArm(plan.map((call) => record(call, payload({ lines }))));
  // 只算我沒回她（E1）；T1 是聊著聊著就停了，不算。
  assertEquals(m.cand.all.openingsEvaluable, 2);
  assertEquals(
    [m.cand.all.iNoReplyExplainLines, m.base.all.iNoReplyExplainLines],
    [3, 3],
  );
});

// ---------------------------------------------------------------------------
// 盲測與計分
// ---------------------------------------------------------------------------

type Name = "甲" | "乙";
type Marks = { willing?: boolean; awkward?: boolean; untrue?: boolean };
type Filler = {
  sentence: (code: string, name: Name, n: number) => Marks;
  fun: (code: string, name: Name) => boolean;
  favorite: (code: string) => string;
  done: (code: string) => boolean;
};

async function blindFixture(
  ids = ["B1", "J1"],
  raw: (call: PlannedCall) => string = () => payload(),
) {
  const plan = await planFor(ids);
  const records = plan.map((call) => record(call, raw(call)));
  return { records, blind: blindForm(records, CASES, 7) };
}

const tick = (on: boolean | undefined) => on ? "[x]" : "[ ]";

/** 照 filler 填盲測表：只改方框和「＿」，跟 Bruce 填的方式一樣。 */
function fillForm(markdown: string, filler: Filler): string {
  let code = "";
  return markdown.split("\n").map((line) => {
    const heading = /^## (\S+#\d+)$/.exec(line);
    if (heading) code = heading[1];
    const sentence = /^- (甲|乙)([1-5]) \[ \]會傳 \[ \]尷尬 \[ \]不實｜(.*)$/
      .exec(line);
    if (sentence) {
      const name = sentence[1] as Name;
      const m = filler.sentence(code, name, Number(sentence[2]));
      return `- ${name}${sentence[2]} ${tick(m.willing)}會傳 ${
        tick(m.awkward)
      }尷尬 ${tick(m.untrue)}不實｜${sentence[3]}`;
    }
    const fun = /^- \[ \] (甲|乙)有一句有趣或有個性$/.exec(line);
    if (fun) {
      return `- ${tick(filler.fun(code, fun[1] as Name))} ${
        fun[1]
      }有一句有趣或有個性`;
    }
    if (line === `${BLIND_FORM.favorite}＿`) {
      return BLIND_FORM.favorite + filler.favorite(code);
    }
    if (line.startsWith("- [ ] 這組評完了")) {
      return line.replace("[ ]", tick(filler.done(code)));
    }
    return line;
  }).join("\n");
}

/**
 * 候選每句都會傳、有一句有趣；基準第 1 句尷尬（payload 推的就是第 1 句）、第 2 句會傳、第 3、4 句尷尬、
 * 第 5 句不實、沒有有趣的一句。
 */
function candWins(reveal: Reveal): Filler {
  const isCand = (code: string, name: Name) => reveal[code][name] === "cand";
  return {
    sentence: (code, name, n) =>
      isCand(code, name) ? { willing: true } : {
        willing: n === 2,
        awkward: n === 1 || n === 3 || n === 4,
        untrue: n === 5,
      },
    fun: isCand,
    favorite: (code) => `${isCand(code, "甲") ? "甲" : "乙"}2`,
    done: () => true,
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

Deno.test("盲測表：同 seed 同順序、不露臂名、不標推薦句；逐句三格、每版一格有趣、最想傳、評完了", async () => {
  const a = await blindFixture();
  const b = await blindFixture();
  assertEquals(a.blind.reveal, b.blind.reveal);
  assertEquals(Object.keys(a.blind.reveal), ["B1#1", "J1#1"]);
  const form = a.blind.markdown;
  assertFalse(/\bbase\b|\bcand\b|改前|改後|候選|基準/.test(form));
  assertFalse(form.includes("★"));
  assertEquals(blindCodes(form), ["B1#1", "J1#1"]);
  for (const name of ["甲", "乙"]) {
    assert(
      form.includes(`- ${name}1 [ ]會傳 [ ]尷尬 [ ]不實｜今天吃到超酸的檸檬`),
    );
    assertEquals(form.split(`- [ ] ${name}有一句有趣或有個性`).length, 3);
  }
  assertEquals(
    form.match(/^- (甲|乙)[1-5] \[ \]會傳 \[ \]尷尬 \[ \]不實｜/gm)?.length,
    20,
  );
  assertEquals(form.split(`${BLIND_FORM.favorite}＿`).length, 3);
  assertEquals(
    form.split("- [ ] 這組評完了（沒勾＝未評，整組不計分）").length,
    3,
  );
  // 「不實」要對照輸入：對象資料與用戶寫的那句照樣附上。
  assert(form.includes("用戶寫的那句：「她說我每次點飲料都點最怪的口味」"));
  assert(form.includes("[對象作戰板：安安]"));
  // 還沒填的表：每組都是「未評」，不是「沒有」。
  const empty = tally({ form, reveal: a.blind.reveal, records: a.records });
  assertEquals(empty.unrated, ["B1#1", "J1#1"]);
  assertEquals(empty.rated, []);
  assertEquals(empty.totals.all.cand.versions, 0);
});

Deno.test("計分：逐句勾選照解盲表加總、基本／進階分開；未評的組不計分，評完沒勾才是「沒有」", async () => {
  const { records, blind } = await blindFixture();
  const filled = fillForm(blind.markdown, candWins(blind.reveal));
  const result = tally({ form: filled, reveal: blind.reveal, records });
  assertEquals(result.rated, ["B1#1", "J1#1"]);
  assertEquals(result.unrated, []);
  assertEquals(result.mismatches, []);
  const { cand, base } = result.totals.all;
  assertEquals(
    [cand.versions, cand.sentences, cand.willing, cand.awkward, cand.untrue],
    [2, 10, 10, 0, 0],
  );
  assertEquals([base.willing, base.awkward, base.untrue], [2, 6, 2]);
  // payload 推第 1 句：候選的第 1 句會傳，基準的第 1 句尷尬。
  assertEquals([cand.starWilling, cand.starAwkward], [2, 0]);
  assertEquals([base.starWilling, base.starAwkward], [0, 2]);
  assertEquals(base.starAwkwardCases, ["B1", "J1"]);
  assertEquals(cand.funByCode, { "B1#1": true, "J1#1": true });
  assertEquals([cand.favorite, base.favorite], [2, 0]);
  assertEquals(base.untrueLines.length, 2);
  assert(base.untrueLines[0].endsWith("5：週末想去看海"), base.untrueLines[0]);
  // B1 是基本模式、J1 是進階。
  assertEquals(result.totals.basic.cand.willing, 5);
  assertEquals(result.totals.advanced.base.awkward, 3);

  // J1 沒勾「這組評完了」：未評，不計分，也不當成「沒有」。
  const partial = tally({
    form: fillForm(blind.markdown, {
      ...candWins(blind.reveal),
      done: (code) => code !== "J1#1",
    }),
    reveal: blind.reveal,
    records,
  });
  assertEquals([partial.rated, partial.unrated], [["B1#1"], ["J1#1"]]);
  assertEquals(partial.totals.all.cand.versions, 1);
  assertEquals(partial.totals.advanced.cand.versions, 0);

  // 評完但一格都沒勾、都不想傳：算「沒有」，分母照算。
  const none = tally({
    form: fillForm(blind.markdown, {
      sentence: () => ({}),
      fun: () => false,
      favorite: () => "都不要",
      done: () => true,
    }),
    reveal: blind.reveal,
    records,
  });
  assertEquals(none.rated.length, 2);
  assertEquals(none.favoriteNone, 2);
  const c = none.totals.all.cand;
  assertEquals([c.versions, c.sentences, c.willing, c.fun, c.favorite], [
    2,
    10,
    0,
    0,
    0,
  ]);
});

Deno.test("計分：★ 取用戶看到的推薦——推第 4 句就看第 4 句；紅燈收尾改推第 1 句就看第 1 句", async () => {
  const { records, blind } = await blindFixture(
    ["B1", "E2"],
    () => payload({ index: 3 }),
  );
  const filled = fillForm(blind.markdown, {
    sentence: (_code, _name, n) => ({ willing: n === 1, awkward: n === 4 }),
    fun: () => true,
    favorite: () => "甲1",
    done: () => true,
  });
  const { totals } = tally({ form: filled, reveal: blind.reveal, records });
  for (const arm of ARMS) {
    // B1（基本）：推第 4 句。
    assertEquals(
      [totals.basic[arm].starWilling, totals.basic[arm].starAwkward],
      [0, 1],
      arm,
    );
    // E2 是紅燈收尾：用戶看到的推薦改成第 1 句。
    assertEquals(
      [totals.advanced[arm].starWilling, totals.advanced[arm].starAwkward],
      [1, 0],
      arm,
    );
  }
});

Deno.test("計分：看不懂就拒絕，不猜；全形方框、大寫 X、v、✓ 都算勾，空的都算沒勾", async () => {
  const parsed = parseBlind([
    "## B1#1",
    "對象資料：",
    "```",
    "- 甲1 這行在程式碼區塊裡，不看",
    "```",
    "### 甲",
    "- 甲1 ［ｘ］會傳 [X]尷尬 [v]不實｜一",
    "- 甲2 [ ]會傳 [　]尷尬 []不實｜二",
    "- [✓] 甲有一句有趣或有個性",
    "### 乙",
    BLIND_FORM.noOutput,
    `${BLIND_FORM.favorite}甲２`,
    "- [x] 這組評完了（沒勾＝未評，整組不計分）",
  ].join("\n")).get("B1#1")!;
  assertEquals(
    parsed.甲.sentences.map((s) => [s.willing, s.awkward, s.untrue, s.text]),
    [[true, true, true, "一"], [false, false, false, "二"]],
  );
  assertEquals([parsed.甲.fun, parsed.乙.fun], [true, null]);
  assertEquals(parsed.乙.sentences, []);
  assertEquals([parsed.favorite, parsed.done], ["甲2", true]);

  const rejects = (label: string, lines: string[]) =>
    assertThrows(() => parseBlind(["## B1#1", ...lines].join("\n")), label);
  rejects("方框看不懂", ["### 甲", "- 甲1 [?]會傳 [ ]尷尬 [ ]不實｜一"]);
  rejects("方框被改壞", ["### 甲", "- 甲1 x]會傳 [ ]尷尬 [ ]不實｜一"]);
  rejects("句子放錯版", ["### 乙", "- 甲1 [ ]會傳 [ ]尷尬 [ ]不實｜一"]);
  rejects("句子順序不對", ["### 甲", "- 甲2 [ ]會傳 [ ]尷尬 [ ]不實｜二"]);
  rejects("有趣那格放錯版", ["### 甲", "- [x] 乙有一句有趣或有個性"]);
  rejects("最想傳看不懂", [`${BLIND_FORM.favorite}乙9`]);
  rejects("評完了那格看不懂", ["- [好] 這組評完了（沒勾＝未評，整組不計分）"]);

  const { records, blind } = await blindFixture();
  const good = fillForm(blind.markdown, candWins(blind.reveal));
  const run = (form: string) => tally({ form, reveal: blind.reveal, records });
  // 勾了評完，卻沒填最想傳，或少了有趣那一行：拒絕。
  assertThrows(() =>
    run(fillForm(blind.markdown, {
      ...candWins(blind.reveal),
      favorite: () => "＿",
    }))
  );
  assertThrows(() =>
    run(good.replace(/^- \[[ x]\] 甲有一句有趣或有個性\n/m, ""))
  );

  // 沒有可用五題的那一版：最想傳不能指到它；版本照算（分母不偷刪）、句子 0、★ 不算會傳。
  const broken = await blindFixture(
    ["B1"],
    (call) => call.arm === "cand" ? "不是 JSON" : payload(),
  );
  assert(broken.blind.markdown.includes(BLIND_FORM.noOutput));
  const candName = broken.blind.reveal["B1#1"].甲 === "cand" ? "甲" : "乙";
  const baseName = candName === "甲" ? "乙" : "甲";
  const fillBroken = (favorite: string) =>
    tally({
      form: fillForm(broken.blind.markdown, {
        sentence: () => ({ willing: true }),
        fun: () => true,
        favorite: () => favorite,
        done: () => true,
      }),
      reveal: broken.blind.reveal,
      records: broken.records,
    });
  assertThrows(() => fillBroken(`${candName}3`));
  const c = fillBroken(`${baseName}1`).totals.all.cand;
  assertEquals([c.versions, c.sentences, c.starWilling, c.fun], [1, 0, 0, 0]);
});

Deno.test("計分：表上的句子跟 records 不一樣（改過字、拿錯表），那組不計分，整份未完成", async () => {
  const { records, blind } = await blindFixture();
  const filled = fillForm(blind.markdown, candWins(blind.reveal));
  const edited = filled.replace("｜今天吃到超酸的檸檬", "｜今天吃到超甜的檸檬");
  const result = tally({ form: edited, reveal: blind.reveal, records });
  assertEquals(result.mismatches, ["B1#1 甲"]);
  assertEquals(result.rated, ["J1#1"]);
  const problems = completenessProblems({
    manifest: await finishedManifest(),
    casesSha256: await catalogSha256(),
    records,
    reveal: blind.reveal,
    form: edited,
    result,
  });
  assert(
    problems.some((p) =>
      p.startsWith("表上的句子跟 records 不一樣（這些組不計分）1 處：B1#1 甲")
    ),
    problems.join(" | "),
  );
});

Deno.test("計分：只有兩組就是「未完成」，B3、E3 沒評分不算過", async () => {
  const { records, blind } = await blindFixture();
  const form = fillForm(blind.markdown, candWins(blind.reveal));
  const result = tally({ form, reveal: blind.reveal, records });
  const problems = completenessProblems({
    manifest: await finishedManifest({
      modelCallsMade: 4,
      options: { repeat: 1, only: ["B1", "J1"], arms: ["base", "cand"] },
    }),
    casesSha256: await catalogSha256(),
    records,
    reveal: blind.reveal,
    form,
    result,
  });
  assert(problems.length > 0);
  const markdown = acceptanceMarkdown({ tag: "t", result, records, problems });
  assert(markdown.includes("整體：**未完成**"));
  assertFalse(markdown.includes("全部通過"));
  assertFalse(markdown.includes("✓"));
  assert(
    markdown.includes(
      "| 3a. 會傳句數：候選 ≥ 基準 | 未完成 | 候選 10、基準 2（基本 候選 5、基準 1；進階 候選 5、基準 1） |",
    ),
    markdown,
  );
  // 缺案例不算過：B3、E3 沒有評分，J1 只有第 1 次。
  assert(
    markdown.includes(
      "| 4b. B3、J1、E3 候選每次都有一句有趣 | 未完成 | 沒有評分：B3#1、B3#2、J1#2、E3#1、E3#2 |",
    ),
  );
  // 不實的句子解盲後逐句列出來（候選沒有）。
  assert(
    markdown.includes(
      "## 候選被勾「不實」的句子（逐句對照輸入確認）\n\n- 沒有",
    ),
  );
  assert(markdown.includes("★ 解釋的人工評分：這輪暫緩、未評"));
});

Deno.test("完整度（主審預檢反例）：88 筆只有 B1 一對成功、其餘沒跑到，填完盲測也不能「全部通過」", async () => {
  const plan = await planFor(CASES.map((c) => c.id), 2);
  assertEquals(plan.length, 88);
  const records = plan.map((call) =>
    call.caseId === "B1" && call.attempt === 1
      ? record(call, payload())
      : record(call, null, "NOT_RUN_CAP_OR_STOP")
  );
  const blind = blindForm(records, CASES, 7);
  assertEquals(Object.keys(blind.reveal), ["B1#1"]);
  assertEquals(blind.unpaired.length, 43);
  const form = fillForm(blind.markdown, candWins(blind.reveal));
  const result = tally({ form, reveal: blind.reveal, records });
  const problems = completenessProblems({
    manifest: await finishedManifest({
      status: "STOPPED_BY_CAP_OR_FAILURE",
      modelCallsMade: 2,
    }),
    casesSha256: await catalogSha256(),
    records,
    reveal: blind.reveal,
    form,
    result,
  });
  for (
    const expected of [
      "評測沒有跑完（manifest status＝STOPPED_BY_CAP_OR_FAILURE）",
      "模型呼叫 2 次，正式驗收要 88 次",
      "模型沒有回的呼叫 86 個",
      "解盲表的組別少了 43 個",
      "blind.md 的組別少了 43 個",
    ]
  ) {
    assert(problems.some((p) => p.startsWith(expected)), expected);
  }
  const markdown = acceptanceMarkdown({ tag: "t", result, records, problems });
  assert(markdown.includes("整體：**未完成**"));
  assertFalse(markdown.includes("全部通過"));
  assertFalse(markdown.includes("| 都有 |"));
  assert(markdown.includes("## 資料不完整"));
});

Deno.test("完整度：22 組 × 2 次 × 兩臂都齊、每組評完才可能「全部通過」；缺、重複、多出、未評、只跑部分都列出來", async () => {
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
  const blind = blindForm(records, CASES, 7);
  assertEquals(Object.keys(blind.reveal).length, 44);
  const form = fillForm(blind.markdown, candWins(blind.reveal));
  const result = tally({ form, reveal: blind.reveal, records });
  assertEquals(result.rated.length, 44);
  const casesSha256 = await catalogSha256();
  const base = {
    manifest: await finishedManifest(),
    casesSha256,
    records,
    reveal: blind.reveal,
    form,
    result,
  };
  assertEquals(completenessProblems(base), []);
  const markdown = acceptanceMarkdown({
    tag: "t",
    result,
    records,
    problems: [],
  });
  assert(markdown.includes("整體：全部通過"), markdown);
  assert(
    markdown.includes("| 4b. B3、J1、E3 候選每次都有一句有趣 | ✓ | 都有 |"),
  );
  // ★ 尷尬分兩個分母列：44 次產出、22 個情境。
  assert(
    markdown.includes(
      "| 2b. ★ 尷尬：候選次數 ≤ 基準，且至多 1 個情境（同情境兩次任一次算） | ✓ | 候選 0／44 次、0／22 個情境（無）；基準 44／44 次、22／22 個情境 |",
    ),
    markdown,
  );

  // ★ 尷尬次數比基準少，但落在兩個情境：2b 不過。
  const wins = candWins(blind.reveal);
  const twoSituations = tally({
    form: fillForm(blind.markdown, {
      ...wins,
      sentence: (code, name, n) =>
        blind.reveal[code][name] === "cand" && n === 1 &&
          (code === "B1#1" || code === "J1#1")
          ? { awkward: true }
          : wins.sentence(code, name, n),
    }),
    reveal: blind.reveal,
    records,
  });
  assert(
    acceptanceMarkdown({
      tag: "t",
      result: twoSituations,
      records,
      problems: [],
    }).includes(
      "| 2b. ★ 尷尬：候選次數 ≤ 基準，且至多 1 個情境（同情境兩次任一次算） | ✗ | 候選 2／44 次、2／22 個情境（B1、J1）",
    ),
  );

  // 進階退步、靠基本拉高總數：總數過關，但 3c 標「需交代」，不能寫全部通過。
  const advanced = (code: string) =>
    CASES.find((c) => c.id === code.split("#")[0])!.topicContext !== null;
  const regress = tally({
    form: fillForm(blind.markdown, {
      ...wins,
      sentence: (code, name, n) =>
        advanced(code)
          ? {
            willing: blind.reveal[code][name] === "cand"
              ? n === 3
              : n === 2 || n === 3,
          }
          : wins.sentence(code, name, n),
    }),
    reveal: blind.reveal,
    records,
  });
  const regressMarkdown = acceptanceMarkdown({
    tag: "t",
    result: regress,
    records,
    problems: [],
  });
  assert(
    regressMarkdown.includes(
      "| 3a. 會傳句數：候選 ≥ 基準 | ✓ | 候選 92、基準 76",
    ),
    regressMarkdown,
  );
  assert(
    regressMarkdown.includes(
      "| 3c. 3a、3b 基本與進階分開看：任一邊退步要交代 | 需交代 | 進階會傳句數 候選 32 < 基準 64 |",
    ),
    regressMarkdown,
  );
  assert(
    regressMarkdown.includes("整體：有未通過、未評估或需交代的項目"),
  );

  // 每一種不完整都會列出來。
  const firstCode = Object.keys(blind.reveal)[0];
  const section = (markdown: string) =>
    markdown.slice(markdown.indexOf(`## ${firstCode}`)).split("\n## ")[0];
  const cases: Array<[string, Record<string, unknown>, string]> = [
    [
      "重跑一組",
      { form: form + "\n" + section(form) },
      "blind.md 的組別重複 1 個",
    ],
    [
      "多一組",
      { form: form + "\n## Z9#1\n" },
      "blind.md 的組別多出 1 個：Z9#1",
    ],
    [
      "一組沒評完",
      {
        result: tally({
          form: fillForm(blind.markdown, {
            ...wins,
            done: (code) => code !== firstCode,
          }),
          reveal: blind.reveal,
          records,
        }),
      },
      `未評（沒勾「這組評完了」）1 組：${firstCode}`,
    ],
    [
      "解盲表甲乙同一臂",
      { reveal: { ...blind.reveal, [firstCode]: { 甲: "cand", 乙: "cand" } } },
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
    [
      "模型對照（同一份提示詞換模型）",
      {
        manifest: await finishedManifest({
          comparison: "model",
          options: {
            repeat: 2,
            only: null,
            arms: ["base", "cand"],
            compare: "model",
          },
        }),
      },
      "這是模型對照（--compare=model），不是 §6.5 驗收",
    ],
  ];
  for (const [label, override, expected] of cases) {
    const problems = completenessProblems({ ...base, ...override });
    assert(
      problems.some((p) => p.startsWith(expected)),
      `${label}：${problems.join(" | ")}`,
    );
  }
  assertEquals(blindCodes(form).length, 44);
});

// ---------------------------------------------------------------------------
// 模型對照（Eric 2026-10-08：同一份提示詞，Sonnet 5 vs 5.5）
// ---------------------------------------------------------------------------

const MODEL_COMPARE_CASES = ["B4", "E3", "J1", "S1", "D1", "C2"];

async function modelComparePlan(ids: string[], repeat: number) {
  const cand = candRouter(NOW_MS);
  return await buildPlan(
    CASES.filter((c) => ids.includes(c.id)),
    repeat,
    { base: cand, cand },
    ARMS,
    "model",
  );
}

/** 用 production 的 fallback.ts 送一跳（不備援），抓下實際送出的 body。 */
async function firstHopBody(model: string, call: PlannedCall) {
  let captured: unknown = null;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = ((_url: string | URL | Request, init?: RequestInit) => {
    captured = JSON.parse(String(init?.body));
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
        model,
        max_tokens: NEW_TOPIC_MAX_TOKENS,
        system: call.system,
        messages: [{ role: "user", content: call.user }],
      },
      "test-key",
      { timeout: 5000, maxRetries: 1, allowModelFallback: false },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
  return captured;
}

Deno.test("模型對照：--compare=model 兩臂同一份提示詞、同 requestId，只換模型；不收 --base-ref", async () => {
  assertEquals(parseOptions([]).compare, "prompt");
  const opts = parseOptions([
    "--compare=model",
    `--only=${MODEL_COMPARE_CASES.join(",")}`,
    "--repeat=2",
  ]);
  assertEquals([opts.compare, opts.repeat, opts.only], [
    "model",
    2,
    MODEL_COMPARE_CASES,
  ]);
  assertThrows(() => parseOptions(["--compare=both"]));
  assertThrows(() => parseOptions(["--compare=model", "--base-ref=7c5cc523"]));

  const plan = await modelComparePlan(MODEL_COMPARE_CASES, 2);
  assertEquals(plan.length, 24);
  assertEquals(
    [...new Set(plan.filter((c) => c.arm === "base").map((c) => c.model))],
    [NEW_TOPIC_MODEL],
  );
  assertEquals(
    [...new Set(plan.filter((c) => c.arm === "cand").map((c) => c.model))],
    [SONNET_5_5_MODEL],
  );
  for (const b of plan.filter((c) => c.arm === "base")) {
    const c = plan.find((x) =>
      x.arm === "cand" && x.caseId === b.caseId && x.attempt === b.attempt
    )!;
    assertEquals(
      [c.system, c.user, c.requestId, c.grounding, c.appliesRedClose],
      [b.system, b.user, b.requestId, b.grounding, b.appliesRedClose],
    );
  }
  // 提示詞對照（預設）兩臂都是 production 的模型。
  assertEquals((await planFor(["E1"])).map((c) => c.model), [
    NEW_TOPIC_MODEL,
    NEW_TOPIC_MODEL,
  ]);
  assertEquals(armModel("prompt", "cand"), NEW_TOPIC_MODEL);
  assertEquals(armModel("model", "cand"), SONNET_5_5_MODEL);
});

Deno.test("模型對照：5.5 的 body 跟 fallback.ts 送 5.5 那一跳一樣（adaptive 思考不回傳、effort low、max_tokens 多 4000、不送 temperature）", async () => {
  const [call] = await planFor(["T1"]);
  const five = requestBody(call) as Record<string, unknown>;
  assertEquals([five.model, five.max_tokens, five.thinking], [
    NEW_TOPIC_MODEL,
    NEW_TOPIC_MAX_TOKENS,
    { type: "disabled" },
  ]);
  assertFalse("output_config" in five);
  assertEquals(await firstHopBody(NEW_TOPIC_MODEL, call), five);

  const fiveFive = requestBody({ ...call, model: SONNET_5_5_MODEL }) as Record<
    string,
    unknown
  >;
  assertEquals(fiveFive.model, SONNET_5_5_MODEL);
  assertEquals(
    fiveFive.max_tokens,
    NEW_TOPIC_MAX_TOKENS + SONNET_5_5_THINKING_HEADROOM_TOKENS,
  );
  assertEquals(fiveFive.thinking, { type: "adaptive", display: "omitted" });
  assertEquals(fiveFive.output_config, { effort: "low" });
  assertFalse("temperature" in fiveFive);
  assertEquals(fiveFive.system, five.system);
  assertEquals(fiveFive.messages, five.messages);
  assertEquals(await firstHopBody(SONNET_5_5_MODEL, call), fiveFive);
});

Deno.test("模型對照：估算與預留照各自模型——5.5 最壞是 max_tokens 7000 全滿、一般另加 1000 思考", async () => {
  const plan = await modelComparePlan(["E1"], 1);
  const base = plan.find((c) => c.arm === "base")!;
  const cand = plan.find((c) => c.arm === "cand")!;
  const input = estimateInputTokens(base);
  assertEquals(estimateInputTokens(cand), input);
  assertEquals(
    reservationUsd(base),
    conservativeUsd(input, NEW_TOPIC_MAX_TOKENS),
  );
  assertEquals(
    reservationUsd(cand),
    conservativeUsd(
      input,
      NEW_TOPIC_MAX_TOKENS + SONNET_5_5_THINKING_HEADROOM_TOKENS,
      SONNET_5_5_MODEL,
    ),
  );
  assert(reservationUsd(cand) > reservationUsd(base));
  const estimate = estimatePlan(plan);
  assertEquals(
    [
      estimate.byArm.base!.typicalOutputTokens,
      estimate.byArm.base!.worstOutputTokens,
    ],
    [TYPICAL_OUTPUT_TOKENS, NEW_TOPIC_MAX_TOKENS],
  );
  assertEquals(
    [
      estimate.byArm.cand!.typicalOutputTokens,
      estimate.byArm.cand!.worstOutputTokens,
    ],
    [
      TYPICAL_OUTPUT_TOKENS + SONNET_5_5_TYPICAL_THINKING_TOKENS,
      NEW_TOPIC_MAX_TOKENS + SONNET_5_5_THINKING_HEADROOM_TOKENS,
    ],
  );
  assertEquals(
    estimate.worstUsd,
    estimate.byArm.base!.worstUsd + estimate.byArm.cand!.worstUsd,
  );
  // 兩個模型同價（_shared/model_pricing.ts）；實付照各自的單價算。
  assertEquals(pricingFor(SONNET_5_5_MODEL), PRICING);
  assertEquals(usd(100, 200, 0, 0, SONNET_5_5_MODEL), usd(100, 200));
});

Deno.test("模型對照：摘要列每臂時間、停止原因與實付，寫明不是 §6.5 驗收；提示詞對照照舊有門檻表", async () => {
  const plan = await modelComparePlan(["E1"], 2);
  // 順序：E1.1.base、E1.1.cand、E1.2.base、E1.2.cand。
  const records: EvalRecord[] = plan.map((call, i) => ({
    ...record(call, payload()),
    stopReason: i === 3 ? "max_tokens" : "end_turn",
    usage: {
      inputTokens: 100,
      outputTokens: 1000 + i * 500,
      cacheReadInputTokens: 0,
      cacheCreationInputTokens: 0,
    },
    costUsd: 0.01 * (i + 1),
    costKnown: true,
    elapsedMs: [12_000, 30_000, 14_000, 46_000][i],
  }));
  const runtime = runtimeByArm(records);
  assertEquals(
    [
      runtime.base.sent,
      runtime.base.elapsedMedianMs,
      runtime.base.elapsedMaxMs,
      runtime.base.outputTokensMax,
    ],
    [2, 13_000, 14_000, 2000],
  );
  assertEquals(
    [
      runtime.cand.overDeadline,
      runtime.cand.stopMaxTokens,
      runtime.cand.stopEndTurn,
    ],
    [1, 1, 1],
  );
  assertEquals(Number(runtime.cand.costUsd.toFixed(4)), 0.06);
  const input = {
    tag: "m",
    candidateHead: "h",
    baseSha: null,
    now: DEFAULT_EVAL_NOW,
    calls: 4,
    planned: 4,
    spentUsd: 0.1,
    budgetUsd: 2,
    stopped: false,
    records,
    unpaired: [],
  };
  const summary = summaryMarkdown({ ...input, comparison: "model" });
  assert(
    summary.includes(
      `# 新話題模型對照 · m · ${NEW_TOPIC_MODEL} vs ${SONNET_5_5_MODEL}`,
    ),
    summary,
  );
  assert(summary.includes("不是 §6.5 驗收"));
  assertFalse(summary.includes("## 規格 §6.5 驗收門檻"));
  assert(
    summary.includes(
      "| 停止原因 end_turn／max_tokens／refusal | 2／0／0 | 1／1／0 |",
    ),
    summary,
  );
  assert(
    summary.includes(
      "| 等待（所有送出的請求）中位數／最慢／超過 45 秒 | 13.0 秒／14.0 秒／0 |",
    ),
  );
  const promptSummary = summaryMarkdown(input);
  assert(promptSummary.includes("## 規格 §6.5 驗收門檻"));
  assert(promptSummary.includes("## 時間與費用（每臂）"));
});

Deno.test("時間統計：API 逾時失敗也算進最慢與超過 45 秒；有回、失敗分開數；中位數是算術中位數", async () => {
  const plan = await modelComparePlan(["E1"], 2);
  // 順序：E1.1.base、E1.1.cand、E1.2.base、E1.2.cand（最後一筆 60 秒逾時失敗）。
  const records: EvalRecord[] = plan.map((call, i) =>
    i === 3
      ? {
        ...record(call, null),
        elapsedMs: 60_000,
        costUsd: 0.09,
        costKnown: false,
      }
      : {
        ...record(call, payload()),
        stopReason: "end_turn",
        usage: {
          inputTokens: 100,
          outputTokens: 1000,
          cacheReadInputTokens: 0,
          cacheCreationInputTokens: 0,
        },
        costUsd: 0.01,
        costKnown: true,
        elapsedMs: [12_000, 20_000, 14_000][i],
      }
  );
  const runtime = runtimeByArm(records);
  assertEquals(
    [runtime.cand.sent, runtime.cand.returned, runtime.cand.apiFailed],
    [2, 1, 1],
  );
  assertEquals(
    [
      runtime.cand.elapsedMaxMs,
      runtime.cand.overDeadline,
      runtime.cand.elapsedMedianMs,
      runtime.cand.costUnknown,
    ],
    [60_000, 1, 40_000, 1],
  );
  assertEquals(runtime.base.elapsedMedianMs, 13_000);
  assertEquals(
    [median([]), median([3]), median([14, 12]), median([1, 5, 3])],
    [null, 3, 13, 3],
  );
});

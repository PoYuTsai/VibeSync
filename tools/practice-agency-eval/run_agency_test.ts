// run_agency.ts CLI 自測（零網路）：parseArgs 的新旗標（--mode=game、--state）＋
// Phase 3.3 修正後 A27 的迴圈行為（用假 callChat，不打 DeepSeek）。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  addHaikuUsage,
  callHaikuChat,
  estimateHaikuCostUsd,
  parseArgs,
  runAgencyScenario,
  runnerChatModelFor,
  saltedThreadId,
  tallyChatModelRounds,
  threadSaltOfArtifactMeta,
  ZERO_HAIKU_USAGE_TOTALS,
} from "./run_agency.ts";
import { AGENCY_SCENARIOS, type AgencyScenario } from "./scenarios.ts";
import {
  chatModelFor,
  READ_ONLY_REPLY_TEXT,
} from "../../supabase/functions/practice-chat/conversation_agency.ts";
import { AGENCY_CLASSIFIER_RULES } from "../../supabase/functions/practice-chat/temperature.ts";
import { callClaude } from "../../supabase/functions/practice-chat/claude.ts";
import {
  chatBody,
  ledger as fakeLedger,
  makeFake,
  makeRequest,
} from "../../supabase/functions/practice-chat/handler_test_fake.ts";
import { buildChatPromptBundle } from "../../supabase/functions/practice-chat/prompt.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import {
  BAKEOFF_THREAD_ID,
  buildBakeoffContextFixture,
} from "../practice-difficulty-bakeoff/bakeoff.ts";

Deno.test("parseArgs：--mode 接受 standard／beginner／game，其餘拒絕", () => {
  assertEquals(parseArgs([]).mode, "standard");
  assertEquals(parseArgs(["--mode=beginner"]).mode, "beginner");
  assertEquals(parseArgs(["--mode=game"]).mode, "game");
  assertThrows(
    () => parseArgs(["--mode=challenge"]),
    Error,
    "agency_invalid_mode",
  );
});

Deno.test("parseArgs：--state 省略或非 1/true 一律 false，1/true 才開", () => {
  assertEquals(parseArgs([]).stateSimulation, false);
  assertEquals(parseArgs(["--state=0"]).stateSimulation, false);
  assertEquals(
    parseArgs(["--mode=beginner", "--state=1"]).stateSimulation,
    true,
  );
  assertEquals(
    parseArgs(["--mode=game", "--state=true"]).stateSimulation,
    true,
  );
});

Deno.test("parseArgs：Phase 4.5b 後 --state=1 搭 standard 合法（對應 PRACTICE_STANDARD_AGENCY_CLASSIFIER）", () => {
  // Codex round-2 P2-d 當時 standard 不持久化跨回合狀態，所以這個組合被擋掉。
  // Phase 4.5b 之後 standard 也有每輪（精簡）分類器與 thread 狀態，
  // `--mode=standard --state=1` 就是那條 production 路徑的黑箱對應。
  for (const args of [["--state=1"], ["--mode=standard", "--state=true"]]) {
    const opts = parseArgs(args);
    assertEquals(opts.mode, "standard");
    assertEquals(opts.stateSimulation, true);
  }
});

Deno.test("parseArgs：未知旗標仍拒絕（新旗標沒有意外放寬白名單）", () => {
  assertThrows(
    () => parseArgs(["--bogus=1"]),
    Error,
    "agency_unknown_cli_flag",
  );
});

Deno.test("parseArgs：--mode=game 可以搭配 --state=1 與 --agency=on 一起解析", () => {
  const opts = parseArgs(["--mode=game", "--state=1", "--agency=on"]);
  assert(opts.mode === "game" && opts.stateSimulation && opts.agency === "on");
});

Deno.test("parseArgs：--shape 省略＝off，只認 truncate，亂填（含已刪的 prompt 臂）直接報錯", () => {
  // 靜默當 off 會讓 artifact meta 的 shapeExperiment 說謊（跟 --state 同理）。
  assertEquals(parseArgs([]).shape, "off");
  assertEquals(parseArgs(["--shape=off"]).shape, "off");
  assertEquals(
    parseArgs(["--agency=on", "--shape=truncate"]).shape,
    "truncate",
  );
  for (const bad of ["--shape=1", "--shape=prompt"]) {
    assertThrows(
      () => parseArgs([bad]),
      Error,
      "agency_invalid_shape_experiment",
    );
  }
});

Deno.test("runAgencyScenario：A27.p2／p4 的 previousAiAskedQuestion 吃到腳本非問句，不是 p1 真實生成的問句（Phase 3.3 修正）", async () => {
  const scenario = AGENCY_SCENARIOS.find((s) => s.id === "A27")!;
  let calls = 0;
  // p1 模擬 README 記過的真實觀察：對裸帳號幾乎必問「你是？」。修正前這句會
  // 直接變成 p2 的 previousAiAskedQuestion=true；修正後 p1／p2 之間夾了腳本
  // 化非問句，p2 不該再吃到這一句。
  const replies = ["你是？我不認識你欸", "喔 好啊 那你最近好嗎", "嗯嗯 好喔"];
  const result = await runAgencyScenario({
    callChat: () => Promise.resolve(replies[calls++]),
    profileId: "practice_girl_001",
    scenario,
    repeat: 1,
    difficulty: "normal",
    mode: "standard",
    style: false,
    agency: "off",
  });
  assertEquals(result.error, undefined);
  assertEquals(calls, 3, "只有 p1／p2／p4 三個真探針該打模型，填充行要走腳本");

  const byProbe = (id: string) => result.turns.find((t) => t.probe?.id === id)!;
  assertEquals(byProbe("A27.p1").previousAiAskedQuestion, false);
  assertEquals(byProbe("A27.p1").reply, replies[0]);
  // 核心斷言：p2 前面最後一則不是 p1 那句真實生成的問句，是腳本化非問句。
  assertEquals(byProbe("A27.p2").previousAiAskedQuestion, false);
  assertEquals(byProbe("A27.p2").reply, replies[1]);
  assertEquals(byProbe("A27.p4").previousAiAskedQuestion, false);
  assertEquals(byProbe("A27.p4").reply, replies[2]);

  // 兩則填充行本身要是腳本（不打模型、不進 judge），內容釘死成 scenarios.ts
  // 裡寫的那兩句非問句閒聊。
  const scripted = result.turns.filter((t) => t.scripted && t.probe === null);
  assertEquals(scripted.map((t) => t.reply), [
    "我也在耍廢 等等要洗澡了",
    "對啊 我也是 電費要爆了",
  ]);
});

// ── Phase 4.2 `--thread-salt`（見 `saltedThreadId` 的註解）────────────────────

Deno.test("parseArgs：--thread-salt 省略＝空字串（thread id 逐字沿用舊行為）", () => {
  assertEquals(parseArgs([]).threadSalt, "");
  assertEquals(saltedThreadId("", 3), BAKEOFF_THREAD_ID);
  assertEquals(parseArgs(["--thread-salt=r1"]).threadSalt, "r1");
  assertEquals(saltedThreadId("r1", 2), `${BAKEOFF_THREAD_ID}|r1|2`);
  // 同一個 salt 的不同 repeat 要拿到不同 thread id，否則骰子還是同一面。
  assert(saltedThreadId("r1", 1) !== saltedThreadId("r1", 2));
});

Deno.test("thread-salt 讓 initiative 分支量得到：5 個**不同**的 salt 打同一位角色，已知有 salt 命中 self_disclose、有 salt 不命中", () => {
  // 兩輪黑箱（Phase 4.0／Phase 4 完整矩陣）在 A29 都是 0/40——固定 thread id 讓
  // `fnv1a(seedKey|回合|initiative) % 5` 在這個探針位置恆為同一個值。這支測試
  // 不打模型，也**不宣稱機率**：下面是這一版 FNV-1a、這位角色、這段逐字稿的
  // deterministic fixture，鎖的是「換 salt 會換骰面」這件事本身（Codex R1 P3）。
  const profile = resolvePracticeProfile({
    profileId: "practice_girl_007", // Ava：initiative 4（agency_profile.ts）
    difficulty: "normal",
  });
  const fx = buildBakeoffContextFixture(profile);
  // A29 的形狀：她先講自己的事，玩家連兩則純反應詞（第 2 個 user 回合才是量測點）。
  const turns: PracticeTurn[] = [
    { role: "ai", text: "我今天差點睡過頭 昨晚追劇追到三點才睡" },
    { role: "user", text: "哈哈" },
    { role: "ai", text: "對啊 現在整個很累" },
    { role: "user", text: "嗯嗯" },
  ];
  const disclosesFor = (threadId: string) =>
    buildChatPromptBundle(turns, profile, {
      replyStyle: true,
      agencyMode: "on",
      visiblePracticeThreadId: threadId,
      partnerState: null,
      styleState: null,
      agencyState: null,
      practiceMode: "beginner",
      temperatureScore: 40,
      familiarityScore: 10,
      sceneContext: fx.sceneContext,
      acquaintanceOrigin: fx.acquaintanceOrigin,
      memorySummary: fx.memorySummary,
      timeContext: fx.timeContext,
      herRecentMomentsBlock: fx.herRecentMomentsBlock,
    }).responsePlan!.optionalAct === "self_disclose";

  const salts = ["s1", "s2", "s3", "s4", "s5"];
  const hits = salts.map((salt) => disclosesFor(saltedThreadId(salt, 1)));
  // Codex R2 P3：CLI 的典型形態是**一個 salt 配多個 repeat**，所以也要證明那一組
  // fixture 同時含命中與不命中，不能只證「五個不同 salt 會分岔」。
  const oneSaltRepeats = [1, 2, 3, 4, 5].map((repeat) =>
    disclosesFor(saltedThreadId("p42", repeat))
  );
  assert(
    oneSaltRepeats.some(Boolean) && oneSaltRepeats.some((h) => !h),
    `固定 salt、repeat 1～5 應同時含命中與不命中：${
      JSON.stringify(oneSaltRepeats)
    }`,
  );
  // 沒有鹽的那一面（兩輪黑箱實際打到的那一格）是 false——這就是 0/40 的來源。
  assertEquals(disclosesFor(saltedThreadId("", 1)), false);
  // 5 個不同的鹽裡，已知至少一個命中、至少一個不命中：證明 salt 真的換骰面，
  // 而不是把整組推成同一個結果。
  assert(hits.some(Boolean), `五個 salt 應有命中：${JSON.stringify(hits)}`);
  assert(hits.some((h) => !h), `五個 salt 應有不命中：${JSON.stringify(hits)}`);
});

Deno.test("Phase 4.2（Codex R1 P3）：Phase 4.2 之前的舊 artifact 沒有 meta.fixture.threadSalt，回放要退回 BAKEOFF_THREAD_ID", async () => {
  const oldArtifact = JSON.parse(
    await Deno.readTextFile(
      new URL("./out/2026-09-04-p36-mini-artifact.json", import.meta.url),
    ),
  );
  // 真的是舊格式：fixture 只有 now／threadId。
  assertEquals(oldArtifact.meta.fixture.threadSalt, undefined);
  const salt = threadSaltOfArtifactMeta(oldArtifact.meta);
  assertEquals(salt, "");
  assertEquals(
    saltedThreadId(salt, oldArtifact.results[0].repeat),
    BAKEOFF_THREAD_ID,
  );
  // 壞形狀（meta 缺 fixture、threadSalt 不是字串）也一律退回空字串。
  assertEquals(threadSaltOfArtifactMeta(undefined), "");
  assertEquals(threadSaltOfArtifactMeta({}), "");
  assertEquals(threadSaltOfArtifactMeta({ fixture: { threadSalt: 7 } }), "");
  assertEquals(
    threadSaltOfArtifactMeta({ fixture: { threadSalt: "r1" } }),
    "r1",
  );
});

// ── 模型 A/B：`--chat-model=deepseek|haiku`（deepseek＝逐字舊行為）────────────

Deno.test("parseArgs：--chat-model 省略＝deepseek（逐字舊行為），只認 deepseek／haiku", () => {
  assertEquals(parseArgs([]).chatModel, "deepseek");
  assertEquals(parseArgs(["--chat-model=deepseek"]).chatModel, "deepseek");
  assertEquals(parseArgs(["--chat-model=haiku"]).chatModel, "haiku");
  assertThrows(
    () => parseArgs(["--chat-model=gpt"]),
    Error,
    "agency_invalid_chat_model",
  );
});

Deno.test("parseArgs：--chat-model 不影響其餘旗標的預設值（等價於沒加這個旗標）", () => {
  const withoutFlag = parseArgs([]);
  const withDefault = parseArgs(["--chat-model=deepseek"]);
  assertEquals(
    { ...withoutFlag, chatModel: undefined },
    { ...withDefault, chatModel: undefined },
  );
});

Deno.test("callHaikuChat：system 併成一段並掛 ephemeral cache_control，訊息角色對映 user/assistant，不打真網路", async () => {
  const original = globalThis.fetch;
  const bodies: Array<Record<string, unknown>> = [];
  globalThis.fetch = (_input, init) => {
    bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
    return Promise.resolve(
      new Response(
        JSON.stringify({
          content: [{ type: "text", text: "喔 好啊" }],
          usage: {
            input_tokens: 120,
            cache_read_input_tokens: 80,
            cache_creation_input_tokens: 0,
            output_tokens: 15,
          },
        }),
        { status: 200 },
      ),
    );
  };
  try {
    const result = await callHaikuChat({
      apiKey: "k",
      messages: [
        { role: "system", content: "你是 Alice。" },
        { role: "system", content: "情境：咖啡廳。" },
        { role: "user", content: "嗨" },
        { role: "assistant", content: "嗨嗨" },
        { role: "user", content: "在幹嘛" },
      ],
      maxTokens: 200,
      temperature: 0.9,
      timeoutMs: 1000,
    });
    assertEquals(result.text, "喔 好啊");
    assertEquals(result.usage, {
      inputTokens: 120,
      cacheReadInputTokens: 80,
      cacheCreationInputTokens: 0,
      outputTokens: 15,
    });
    assertEquals(bodies.length, 1);
    const body = bodies[0];
    assertEquals(body.model, "claude-haiku-4-5-20251001");
    assertEquals(body.max_tokens, 200);
    assertEquals(body.temperature, 0.9);
    assertEquals(body.system, [{
      type: "text",
      text: "你是 Alice。\n\n情境：咖啡廳。",
      cache_control: { type: "ephemeral" },
    }]);
    assertEquals(body.messages, [
      { role: "user", content: "嗨" },
      { role: "assistant", content: "嗨嗨" },
      { role: "user", content: "在幹嘛" },
    ]);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("callHaikuChat：max_tokens／refusal／空字串走跟 callClaude 一致的錯誤語意", async () => {
  const original = globalThis.fetch;
  const cases: Array<[unknown, string]> = [
    [{ stop_reason: "max_tokens", content: [] }, "claude_max_tokens"],
    [{ stop_reason: "refusal", content: [] }, "claude_refusal"],
    [{ content: [] }, "claude_empty_content"],
  ];
  try {
    for (const [payload, expected] of cases) {
      globalThis.fetch = () =>
        Promise.resolve(new Response(JSON.stringify(payload), { status: 200 }));
      let message = "";
      try {
        await callHaikuChat({
          apiKey: "k",
          messages: [{ role: "user", content: "hi" }],
          maxTokens: 10,
          temperature: 0.5,
          timeoutMs: 1000,
        });
      } catch (e) {
        message = e instanceof Error ? e.message : String(e);
      }
      assertEquals(message, expected);
    }
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("addHaikuUsage／estimateHaikuCostUsd：純函式累加與估價（不打網路）", () => {
  const afterOne = addHaikuUsage(ZERO_HAIKU_USAGE_TOTALS, {
    inputTokens: 1000,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0,
    outputTokens: 1000,
  });
  assertEquals(afterOne.calls, 1);
  // Phase 4.5c：單價改吃 pricing.ts 的官方牌價（$1／$5 每 M token，之前抄的是
  // logger.ts 那組過期的 $0.80／$4）。input 1K@$1/M + output 1K@$5/M = $0.006。
  assert(Math.abs(estimateHaikuCostUsd(afterOne) - 0.006) < 1e-9);
  const afterTwo = addHaikuUsage(afterOne, {
    inputTokens: 0,
    cacheReadInputTokens: 1000,
    cacheCreationInputTokens: 0,
    outputTokens: 0,
  });
  assertEquals(afterTwo.calls, 2);
  assert(estimateHaikuCostUsd(afterTwo) > estimateHaikuCostUsd(afterOne));
});

// ── Phase 4.3 步驟 0：分類器訊號真的餵進 nextConversationAgencyState ──────────

/** 假 DeepSeek `/chat/completions` 回應：只有 `runAgencyScenario` 內建的分類器
 * 呼叫端會打 fetch（`callChat` 在下面兩支測試都是純 stub，不經過網路），所以
 * 這支不必分辨請求種類。 */
function fakeClassifierResponse(
  aiChallengedThisTurn: boolean,
  coherence = "disconnected",
): Response {
  return new Response(
    JSON.stringify({
      choices: [{
        finish_reason: "stop",
        message: {
          content: JSON.stringify({
            connection: "neutral",
            impact: "minor",
            testHandling: "none",
            boundary: "safe",
            hintAlignment: "none",
            partnerMood: "neutral",
            moodConfidence: 0.7,
            innerThought: "他又丟一個地名。",
            coherence,
            aiChallengedThisTurn,
            sharedPastClaim: false,
            accommodatingSelfFact: false,
          }),
        },
      }],
    }),
    { status: 200 },
  );
}

/** 兩則連續裸地名：第一則她的回覆是明確問句（滿足 aiQuestionedInLoop），第二則
 * 再丟一個地名（answer_candidate，unresolvedCount>=1）——這是計畫檔 Phase 4.3
 * R2 規則最終形唯一的判別器：`aiClarifiedLastTurn===true` 才 forced
 * `challenge_relevance`／`clarify_ignored_*`，`null`（缺席）一律 bounded。 */
const CLASSIFIER_WIRING_SCENARIO: AgencyScenario = {
  id: "TEST-p43-classifier-wiring",
  title: "測試用：兩則裸地名，只驗證分類器訊號有沒有接進 state",
  turns: [
    { role: "user", text: "韓國" },
    { role: "user", text: "日本" },
  ],
};

Deno.test("Phase 4.3 步驟 0：--state=1 的 assisted 模式生成後真的打分類器，結果餵進 nextConversationAgencyState（不再是硬編碼 null），不打真網路", async () => {
  const original = globalThis.fetch;
  let classifierCalls = 0;
  globalThis.fetch = () => {
    classifierCalls++;
    return Promise.resolve(fakeClassifierResponse(true));
  };
  let chatCalls = 0;
  const replies = ["你在說什麼？", "喔 好"];
  try {
    const result = await runAgencyScenario({
      callChat: () => Promise.resolve(replies[chatCalls++]),
      profileId: "practice_girl_001",
      scenario: CLASSIFIER_WIRING_SCENARIO,
      repeat: 1,
      difficulty: "normal",
      mode: "beginner",
      style: false,
      agency: "on",
      stateSimulation: true,
      classifierApiKey: "test-key",
    });
    assertEquals(result.error, undefined);
    assertEquals(chatCalls, 2);
    assertEquals(
      classifierCalls,
      2,
      "assisted＋--state=1 時每一輪生成後都該打一次分類器（handler.ts 同序）",
    );

    const round1 = result.turns[0];
    assertEquals(round1.classifierSignal, {
      coherence: "disconnected",
      aiChallengedThisTurn: true,
    });
    assertEquals(
      round1.agencyStateAfter?.aiClarifiedLastTurn,
      true,
      "修正前這裡永遠是 undefined（runner 把第三個參數硬編碼傳 null）",
    );

    // 核心斷言：round2 只有在拿到 round1 的分類器訊號後才會被 4.3 的規則
    // 強制成 challenge_relevance／clarify_ignored_*（見下面的反例測試）。
    const round2 = result.turns[1];
    assertEquals(round2.policyMode, "forced");
    assertEquals(round2.forcedAct, "challenge_relevance");
    assert(
      round2.allowedActSetId?.startsWith("clarify_ignored"),
      `預期 clarify_ignored_*，拿到 ${round2.allowedActSetId}`,
    );
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("Phase 4.3 步驟 0（反例）：沒有 classifierApiKey 時退回舊行為（signal 缺席＝null），round2 不會被 4.3 強制——證明上面那支測試真的鎖住了修正前後的差異", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => {
    throw new Error("不該打到 fetch：沒有 classifierApiKey 就不該呼叫分類器");
  };
  let chatCalls = 0;
  const replies = ["你在說什麼？", "喔 好"];
  try {
    const result = await runAgencyScenario({
      callChat: () => Promise.resolve(replies[chatCalls++]),
      profileId: "practice_girl_001",
      scenario: CLASSIFIER_WIRING_SCENARIO,
      repeat: 1,
      difficulty: "normal",
      mode: "beginner",
      style: false,
      agency: "on",
      stateSimulation: true,
      // classifierApiKey 省略：這是修正前 run_agency.ts 的舊行為（第三個
      // 參數永遠傳 null）。
    });
    assertEquals(result.error, undefined);
    const round1 = result.turns[0];
    assertEquals(round1.classifierSignal, undefined);
    assertEquals(round1.agencyStateAfter?.aiClarifiedLastTurn, undefined);
    const round2 = result.turns[1];
    assertEquals(
      round2.policyMode,
      "bounded",
      "沒有分類器訊號時 4.3 的 forced 分支不成立，維持既有 bounded 二選一",
    );
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("Phase 4.5b：--mode=standard --state=1 真的打**精簡**分類器（不是硬編碼 null），訊號接進 state 讓下一輪裸詞 forced challenge_relevance", async () => {
  const original = globalThis.fetch;
  const bodies: string[] = [];
  globalThis.fetch = (_url: string | URL | Request, init?: RequestInit) => {
    bodies.push(String(init?.body));
    return Promise.resolve(fakeClassifierResponse(true));
  };
  let chatCalls = 0;
  const replies = ["你在說什麼？", "喔 好"];
  try {
    const result = await runAgencyScenario({
      callChat: () => Promise.resolve(replies[chatCalls++]),
      profileId: "practice_girl_001",
      scenario: CLASSIFIER_WIRING_SCENARIO,
      repeat: 1,
      difficulty: "normal",
      mode: "standard",
      style: false,
      agency: "on",
      stateSimulation: true,
      classifierApiKey: "test-key",
    });
    assertEquals(result.error, undefined);
    assertEquals(bodies.length, 2, "standard 每一輪生成後也要打一次分類器");
    // 精簡分類器：system prompt 只問四個 agency 欄位（沒有 connection／
    // partnerMood／innerThought 那些核心欄位的 stub）。
    const system = (JSON.parse(bodies[0]) as {
      messages: { role: string; content: string }[];
    }).messages[0].content;
    assert(
      system.includes(
        '{"coherence":"connected","aiChallengedThisTurn":false,"sharedPastClaim":false,"accommodatingSelfFact":false}',
      ),
      "standard 必須走精簡分類器的 JSON stub",
    );
    assert(
      !system.includes('"partnerMood":"neutral"'),
      "精簡分類器不得帶核心分數欄位",
    );
    // 判準文字與逐輪分類器同一份常數。
    assert(system.includes(AGENCY_CLASSIFIER_RULES));

    assertEquals(result.turns[0].classifierSignal, {
      coherence: "disconnected",
      aiChallengedThisTurn: true,
    });
    assertEquals(result.turns[0].agencyStateAfter?.aiClarifiedLastTurn, true);
    const round2 = result.turns[1];
    assertEquals(round2.policyMode, "forced");
    assertEquals(round2.forcedAct, "challenge_relevance");
    assert(round2.allowedActSetId?.startsWith("clarify_ignored"));
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("Phase 4.5b（反例）：standard 未開 --state 時一次分類器都不打，round2 維持 bounded", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => {
    throw new Error("不該打到 fetch：未開 --state 的 standard 不呼叫分類器");
  };
  let chatCalls = 0;
  const replies = ["你在說什麼？", "喔 好"];
  try {
    const result = await runAgencyScenario({
      callChat: () => Promise.resolve(replies[chatCalls++]),
      profileId: "practice_girl_001",
      scenario: CLASSIFIER_WIRING_SCENARIO,
      repeat: 1,
      difficulty: "normal",
      mode: "standard",
      style: false,
      agency: "on",
      stateSimulation: false,
      classifierApiKey: "test-key",
    });
    assertEquals(result.error, undefined);
    assertEquals(result.turns[0].classifierSignal, undefined);
    assertEquals(result.turns[1].policyMode, "bounded");
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("Phase 4.5b：runnerChatModelFor 的 standard 路由與 production chatModelFor 全矩陣逐項相同", () => {
  for (const standardOn of [false, true]) {
    for (const applied of [false, true]) {
      for (const situation of [null, "neutral", "boundary"]) {
        assertEquals(
          runnerChatModelFor({
            chatModel: "mixed",
            agency: "on",
            mode: "standard",
            applied,
            situation,
            standardAgencyClassifier: standardOn,
          }),
          chatModelFor(
            "mixed",
            "on",
            { applied },
            "standard",
            situation,
            standardOn,
          ),
        );
      }
    }
  }
  // 旗標關著時 standard 一律 deepseek（Phase 4.4 的既有範圍不變）。
  assertEquals(
    runnerChatModelFor({
      chatModel: "mixed",
      agency: "on",
      mode: "standard",
      applied: true,
      situation: "neutral",
    }),
    "deepseek",
  );
});

// ── Phase 4.3 步驟 1：`--chat-model=mixed` ────────────────────────────────

Deno.test("parseArgs：--chat-model 接受 mixed，其餘沿用既有拒絕清單", () => {
  assertEquals(parseArgs(["--chat-model=mixed"]).chatModel, "mixed");
  assertThrows(
    () => parseArgs(["--chat-model=gpt"]),
    Error,
    "agency_invalid_chat_model",
  );
});

Deno.test("runAgencyScenario：--chat-model=mixed 只在 bundle.agencyDecision.applied===true 那一輪換 callChatHaiku，其餘用 callChat（DeepSeek），不打真網路", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => Promise.resolve(fakeClassifierResponse(true));
  let deepseekCalls = 0;
  let haikuCalls = 0;
  try {
    const result = await runAgencyScenario({
      callChat: () => {
        deepseekCalls++;
        return Promise.resolve("嗯嗯 好喔");
      },
      callChatHaiku: () => {
        haikuCalls++;
        return Promise.resolve("你在說什麼啦");
      },
      profileId: "practice_girl_001",
      scenario: CLASSIFIER_WIRING_SCENARIO,
      repeat: 1,
      difficulty: "normal",
      mode: "beginner",
      style: false,
      agency: "on",
      stateSimulation: true,
      classifierApiKey: "test-key",
      chatModel: "mixed",
    });
    assertEquals(result.error, undefined);
    // 逐輪 chatModelUsed 都要是合法值；實際「哪一輪換了 Haiku」由下面用
    // callChat／callChatHaiku 各自的呼叫次數交叉驗證，不在這裡假設固定值。
    for (const t of result.turns) {
      assert(
        t.chatModelUsed === "deepseek" || t.chatModelUsed === "haiku",
        `chatModelUsed 應為 deepseek／haiku，拿到 ${t.chatModelUsed}`,
      );
    }
    assertEquals(
      deepseekCalls + haikuCalls,
      result.turns.length,
      "兩支 caller 合計次數要等於總輪數，沒有漏呼叫也沒有兩邊都打",
    );
    assertEquals(
      result.turns.filter((t) => t.chatModelUsed === "haiku").length,
      haikuCalls,
    );
    assertEquals(
      result.turns.filter((t) => t.chatModelUsed === "deepseek").length,
      deepseekCalls,
    );
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("runAgencyScenario：--chat-model=haiku（非 mixed）逐字沿用舊行為，全程只用 callChat，不讀 callChatHaiku", async () => {
  let calls = 0;
  const result = await runAgencyScenario({
    callChat: () => {
      calls++;
      return Promise.resolve("嗯嗯 好喔");
    },
    // 不提供 callChatHaiku：non-mixed 分支若誤讀它就會在這裡炸掉（undefined
    // 不是函式）。
    profileId: "practice_girl_001",
    scenario: CLASSIFIER_WIRING_SCENARIO,
    repeat: 1,
    difficulty: "normal",
    mode: "beginner",
    style: false,
    agency: "on",
    chatModel: "haiku",
  });
  assertEquals(result.error, undefined);
  assertEquals(calls, 2);
  assertEquals(result.turns.map((t) => t.chatModelUsed), ["haiku", "haiku"]);
});

// ── Phase 4.4：production 的 mixed 路由與黑箱 haiku 臂送出的 request 逐位元組相同 ──
//
// 這是「黑箱結論搬得回 production」的唯一硬證據：同一份 bundle messages 進
// handler 的 Claude 呼叫端與 runner 的 haiku 臂，打出去的 body 必須一模一樣。
// 兩邊現在都走 `claude.ts` 的 `callClaude`，這支測試守住「哪天有人在其中一邊
// 多塞一個參數」。
Deno.test("Phase 4.4：handler 走 mixed 路由送進 Claude 的 request body 與黑箱 haiku 臂逐位元組相同（不打真網路）", async () => {
  const fake = makeFake({
    // routing 只在 assisted 模式生效（Codex R1 P1 範圍限制），所以走 beginner；
    // 最後一則 DeepSeek 回覆留給生成後的分類器。
    ledger: fakeLedger({ practice_mode: "beginner" }),
    deepSeekReplies: [
      "好啊",
      `{"connection":"caught","impact":"medium","testHandling":"none","boundary":"safe","hintAlignment":"none"}`,
    ],
    claudeReplies: ["嗯？你先講東東"],
    env: {
      PRACTICE_CHAT_MODEL_ROUTING: "mixed",
      PRACTICE_CONVERSATIONAL_AGENCY_ENABLED: "true",
    },
  });
  const originalLog = console.log;
  const originalWarn = console.warn;
  try {
    console.log = () => {};
    console.warn = () => {};
    await fake.handler(
      makeRequest(chatBody({
        practiceMode: "beginner",
        turns: [
          { role: "user", text: "東東" },
          { role: "ai", text: "東東是誰" },
          { role: "user", text: "阿布達比" },
        ],
      })),
    );
    await Promise.allSettled(fake.state.backgroundTasks);
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
  }
  assertEquals(fake.state.claudeCalls.length, 1);
  const handlerArgs = fake.state.claudeCalls[0];

  // Codex R2 P3：存**原始字串**再比，才真的是逐位元組（JSON.parse 之後比物件
  // 只證明語意相同，key 順序／escaping／空白的差異看不出來）。
  const bodies: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (_input, init) => {
    bodies.push(String(init?.body));
    return Promise.resolve(
      new Response(
        JSON.stringify({ content: [{ type: "text", text: "嗯" }] }),
        { status: 200 },
      ),
    );
  };
  try {
    // production：handler 實際交給 callClaude 的那一組參數。
    await callClaude({ ...handlerArgs, apiKey: "k", timeoutMs: 1000 });
    // 黑箱 haiku 臂：runner 的 CHAT_MAX_TOKENS／CHAT_TEMPERATURE 直接寫死在這裡
    // （run_agency.ts 的兩個模組常數），這樣 handler 那邊改了數字就會被抓到。
    await callHaikuChat({
      apiKey: "k",
      messages: handlerArgs.messages,
      maxTokens: 200,
      temperature: 0.9,
      timeoutMs: 1000,
      // Phase 4.5b 刀 B：production 從 `bundle.systemStable` 拿這一格，runner
      // 從 `ChatCaller` 的第二個參數拿——兩邊都是同一個 bundle 欄位。
      systemCachePrefix: handlerArgs.systemCachePrefix,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
  assertEquals(bodies.length, 2);
  assertEquals(bodies[0], bodies[1]);
  // UTF-8 bytes 也對一遍（字串相等已蘊含，但把宣稱寫死在斷言裡）。
  assertEquals(
    new TextEncoder().encode(bodies[0]),
    new TextEncoder().encode(bodies[1]),
  );
  assertEquals(
    (JSON.parse(bodies[0]) as { model?: string }).model,
    "claude-haiku-4-5-20251001",
  );
  // Phase 4.5b 刀 B：system 真的是兩個 block（前綴掛 cache、當輪尾巴不掛），
  // 而且拼起來等於 handler 交出去的那一份 system。
  const system = (JSON.parse(bodies[0]) as {
    system: Array<{ text: string; cache_control?: unknown }>;
  }).system;
  assertEquals(system.length, 2);
  assert(system[0].cache_control);
  assertEquals(system[1].cache_control, undefined);
  assertEquals(
    system[0].text + system[1].text,
    handlerArgs.messages.filter((m) => m.role === "system")
      .map((m) => m.content).join("\n\n").trim(),
  );

  // 上面兩個數字真的是 runner 的常數（不是這支測試自己編的）。
  const runnerSource = await Deno.readTextFile(
    new URL("./run_agency.ts", import.meta.url),
  );
  assert(runnerSource.includes("const CHAT_MAX_TOKENS = 200;"));
  assert(runnerSource.includes("const CHAT_TEMPERATURE = 0.9;"));
});

// Codex R1 U2：要證明的不只是「選了 Haiku 之後 body 相同」，而是「何時選 Haiku
// 相同」。runner 的 mixed 臂選模入口就是 production 的 `chatModelFor`，這支測試
// 對整個矩陣逐項比對，順便釘住 deepseek／haiku 兩個純臂的舊行為。
Deno.test("Phase 4.4：runner 的選模入口與 production chatModelFor 在整個矩陣上逐項相等", () => {
  const arms = [undefined, "deepseek", "haiku", "mixed"] as const;
  const agencyModes = ["on", "shadow", "off"] as const;
  const modes = ["standard", "beginner", "game"] as const;
  const applieds = [true, false, undefined];
  const situations = ["boundary", "neutral", "question", undefined];
  let mixedHaiku = 0;
  let boundaryHaiku = 0;
  for (const arm of arms) {
    for (const agency of agencyModes) {
      for (const mode of modes) {
        for (const applied of applieds) {
          for (const situation of situations) {
            const actual = runnerChatModelFor({
              chatModel: arm,
              agency,
              mode,
              applied,
              situation,
            });
            const expected = arm === "haiku"
              ? "haiku"
              : arm === "mixed"
              ? chatModelFor(
                "mixed",
                agency,
                applied === undefined ? null : { applied },
                mode,
                situation,
              )
              : "deepseek";
            const label =
              `arm=${arm} agency=${agency} mode=${mode} applied=${applied} situation=${situation}`;
            assertEquals(actual, expected, label);
            if (arm === "mixed" && actual === "haiku") {
              mixedHaiku++;
              if (applied !== true) boundaryHaiku++;
            }
          }
        }
      }
    }
  }
  // 非空洞：mixed 臂真的有格子選到 Haiku——介入輪（agency=on × beginner/game ×
  // applied=true × 四個 situation）＝8 格，越界輪（applied 非 true × boundary）
  // ＝ 2 模式 × 2 個非 true 的 applied ＝ 4 格。
  assertEquals(mixedHaiku, 12);
  assertEquals(boundaryHaiku, 4);
});

Deno.test("Phase 4.5c：tallyChatModelRounds 正確吃 chatModelUsed=none（不算模型、不進分母、不除以零）", () => {
  const t = tallyChatModelRounds([
    {
      turns: [
        // 腳本前文與 ai turn 都不是生成輪。
        { role: "ai", chatModelUsed: "haiku" },
        { role: "user", scripted: true, chatModelUsed: "haiku" },
        { role: "user", chatModelUsed: "haiku" },
        { role: "user", chatModelUsed: "deepseek" },
        // Phase 4.5a 之後 production 對 forced read_only 那一輪的值。
        { role: "user", chatModelUsed: "none" },
        { role: "user", chatModelUsed: "none" },
        // Phase 4.3 之前的舊 artifact 沒有這個欄位。
        { role: "user" },
      ],
    },
    // 失敗的場次整場不算。
    { error: "boom", turns: [{ role: "user", chatModelUsed: "haiku" }] },
  ]);
  assertEquals(t.haiku, 1);
  assertEquals(t.deepseek, 1);
  assertEquals(t.none, 2);
  assertEquals(t.unknown, 1);
  // none／unknown 都不進「真的打了生成模型」的分母。
  assertEquals(t.modelRounds, 2);
  assertEquals(t.haikuShare, 0.5);
});

Deno.test("Phase 4.5c：整批都是 none 時 haikuShare 是 null，不是 0，也不會除以零", () => {
  const t = tallyChatModelRounds([
    {
      turns: [
        { role: "user", chatModelUsed: "none" },
        { role: "user", chatModelUsed: "none" },
      ],
    },
  ]);
  assertEquals(t.none, 2);
  assertEquals(t.modelRounds, 0);
  assertEquals(t.haikuShare, null);
  assertEquals(tallyChatModelRounds([]).haikuShare, null);
});

Deno.test("Phase 4.5e：forced read_only 那一輪不打生成模型，回覆逐字是「（已讀）」、chatModel=none（不打真網路）", async () => {
  // A25（連續裸地名）× game × `--state=1`：階梯走
  // ask_intent → challenge_relevance ×3 → check_out → read_only ×3，
  // 跟 production Game 黑箱 artifact（out/2026-09-05-p45c-game-mixed.json 的
  // A25/practice_girl_004#1）同一條軌跡。
  const scenario = AGENCY_SCENARIOS.find((s) => s.id === "A25")!;
  const original = globalThis.fetch;
  // 分類器每輪都回 disconnected＋已質疑，階梯才推得動（真實那場也是這樣）。
  globalThis.fetch = () => Promise.resolve(fakeClassifierResponse(true));
  // 這一場只有 6 輪該打模型（9 個 user turn 扣掉 3 輪 read_only）。上限抓
  // `MODEL_ROUNDS × CHAT_GENERATION_ATTEMPTS`：Phase 4.5g 的 check_out 結構
  // 後檢查會讓那一輪用掉既有的第二發（下面這支 fake 每輪都回問句），所以
  // 呼叫數不再等於輪數；「read_only 輪沒打模型」改由 `attempts === 0` 直接證明。
  const MODEL_ROUNDS = 6;
  let chatCalls = 0;
  try {
    const result = await runAgencyScenario({
      callChat: () => {
        chatCalls++;
        if (chatCalls > MODEL_ROUNDS * 2) {
          throw new Error("model_called_on_read_only_turn");
        }
        // 問句形狀：她真的問了才會進 `aiQuestionedInLoop`／推進階梯。
        return Promise.resolve(`你在講什麼啊${chatCalls}？`);
      },
      profileId: "practice_girl_004",
      scenario,
      repeat: 1,
      difficulty: "normal",
      mode: "game",
      style: true,
      agency: "on",
      shape: "truncate",
      stateSimulation: true,
      classifierApiKey: "test-key",
      chatModel: "deepseek",
    });
    assertEquals(result.error, undefined);
    const generated = result.turns.filter((t) =>
      t.role === "user" && !t.scripted
    );
    const readOnly = generated.filter((t) => t.forcedAct === "read_only");
    assert(readOnly.length > 0, "這一場沒有跑到 read_only，測試沒有守到東西");
    // 短路成立：打過模型的**輪數**＝總輪數扣掉 read_only 輪，而生成呼叫數
    // 恰好是各輪 `attempts` 的總和（read_only 輪的 attempts 是 0）。
    assertEquals(generated.length - readOnly.length, MODEL_ROUNDS);
    assertEquals(
      chatCalls,
      generated.reduce((sum, t) => sum + t.attempts, 0),
    );
    for (const t of readOnly) {
      // 逐字＝production 的 READ_ONLY_REPLY_TEXT（style 臂的括號旁白守門不得
      // 把它剝掉——`hasStageDirection`／`stripStageDirections` 要吃到白名單）。
      assertEquals(t.reply, READ_ONLY_REPLY_TEXT);
      assertEquals(t.reply, "（已讀）");
      assertEquals(t.chatModelUsed, "none");
      assertEquals(t.readOnlyReply, true);
      assertEquals(t.attempts, 0);
      assertEquals(t.promptChars, 0);
      assertEquals(t.guardRejections, []);
    }
    // 其餘輪次照舊打模型、照舊記 deepseek。
    for (const t of generated.filter((x) => x.forcedAct !== "read_only")) {
      assertEquals(t.chatModelUsed, "deepseek");
      assertEquals(t.readOnlyReply, undefined);
      assert(t.promptChars > 0);
    }
    // `tallyChatModelRounds` 接得上：read_only 進 none，不進 modelRounds 分母。
    const tally = tallyChatModelRounds([result]);
    assertEquals(tally.none, readOnly.length);
    assertEquals(tally.deepseek, MODEL_ROUNDS);
    assertEquals(tally.modelRounds, MODEL_ROUNDS);
    assertEquals(tally.haikuShare, 0);
  } finally {
    globalThis.fetch = original;
  }
});

// ── Phase 4.5h：`--temperature`／`--familiarity` ──────────────────────────

Deno.test("parseArgs：--temperature／--familiarity 省略＝handler 的 beginner 起始值 40／10", () => {
  assertEquals(parseArgs([]).temperatureScore, 40);
  assertEquals(parseArgs([]).familiarityScore, 10);
  assertEquals(parseArgs(["--temperature=80"]).temperatureScore, 80);
  assertEquals(parseArgs(["--familiarity=70"]).familiarityScore, 70);
  assertEquals(
    parseArgs(["--temperature=0", "--familiarity=100"]).temperatureScore,
    0,
  );
});

Deno.test("parseArgs：分數超出 0–100、非整數、帶雜訊一律報錯（不靜默 clamp，meta 才不會說謊）", () => {
  for (
    const bad of [
      "--temperature=101",
      "--temperature=-1",
      "--temperature=abc",
      "--temperature=80.5",
      "--temperature=80x",
    ]
  ) {
    assertThrows(() => parseArgs([bad]), Error, "agency_invalid_temperature");
  }
  for (
    const bad of ["--familiarity=101", "--familiarity=-1", "--familiarity="]
  ) {
    assertThrows(() => parseArgs([bad]), Error, "agency_invalid_familiarity");
  }
});

Deno.test("runAgencyScenario：game 臂的起始分數真的進 prompt——省略＝not_ready，給高分＝direct_invite_ready", async () => {
  const scenario = AGENCY_SCENARIOS.find((s) => s.id === "A32")!;
  const promptOf = async (
    scores?: { temperatureScore: number; familiarityScore: number },
  ) => {
    const seen: string[] = [];
    const result = await runAgencyScenario({
      callChat: (messages) => {
        seen.push(messages.map((m) => m.content).join("\n"));
        return Promise.resolve("嗯嗯");
      },
      profileId: "practice_girl_001",
      scenario,
      repeat: 1,
      difficulty: "normal",
      mode: "game",
      style: false,
      agency: "off",
      ...(scores ?? {}),
    });
    assertEquals(result.error, undefined);
    return seen;
  };
  // 省略旗標＝逐位元組舊行為：溫度 40／熟悉 10 → 成熟度 28 → not_ready。
  for (const prompt of await promptOf()) {
    assert(
      prompt.includes("inviteStage: not_ready"),
      "省略旗標時不該離開 not_ready",
    );
  }
  // 高分開場（80／70 → 成熟度 76）：整場都在可直接邀約那一階，spicy 上限也跟著開。
  const high = await promptOf({ temperatureScore: 80, familiarityScore: 70 });
  for (const prompt of high) {
    assert(
      prompt.includes("inviteStage: direct_invite_ready"),
      "高分開場沒有進到 direct_invite_ready",
    );
  }
  // 邀約那一輪（第 4 句）才會走到 direct_invite_low_pressure——那是玩家自己的
  // 邀約句觸發的（`looksLikeGameSoftInvite`），不是分數。分數在聊天 prompt 這條
  // 路上進的是 inviteMaturity／allowSpicyLevel／phase 三個區塊，見 README。
  assert(high[3].includes("speedInviteDirection: direct_invite_low_pressure"));
  assert(
    high[0].includes("allowSpicyLevel: L3"),
    "高分開場沒有把 spicy 上限開到 L3",
  );
  const low = await promptOf();
  assert(
    low[0].includes("allowSpicyLevel: L1"),
    "省略旗標時 spicy 上限不該是 L3",
  );
});

Deno.test("Phase 4.5g：runner 與 production 同源——forced check_out 那一輪第一發含問句就重試，第二發合格就採用（不打真網路）", async () => {
  // 與上面 4.5e 同一條 A25 × game 軌跡：階梯的 check_out 落在 round5。
  const scenario = AGENCY_SCENARIOS.find((s) => s.id === "A25")!;
  const original = globalThis.fetch;
  globalThis.fetch = () => Promise.resolve(fakeClassifierResponse(true));
  let chatCalls = 0;
  try {
    const result = await runAgencyScenario({
      callChat: () => {
        chatCalls++;
        // 每一發都先回問句；只有被 check_out 後檢查丟掉、重試的那一發回
        // 合格的收尾句，證明「真的丟掉第一發、真的採用第二發」。
        return Promise.resolve(
          chatCalls === 6 ? "先忙了" : `你在講什麼啊${chatCalls}？`,
        );
      },
      profileId: "practice_girl_004",
      scenario,
      repeat: 1,
      difficulty: "normal",
      mode: "game",
      style: true,
      agency: "on",
      shape: "truncate",
      stateSimulation: true,
      classifierApiKey: "test-key",
      chatModel: "deepseek",
    });
    assertEquals(result.error, undefined);
    const checkOut = result.turns.filter((t) => t.forcedAct === "check_out");
    assertEquals(checkOut.length, 1);
    const t = checkOut[0];
    assertEquals(t.reply, "先忙了");
    assertEquals(t.attempts, 2);
    assertEquals(t.checkOutRetry, true);
    assertEquals(t.checkOutStructuralFail, undefined);
    assertEquals(t.guardRejections, ["chat_agency_check_out_shape"]);
    // 其餘輪次一發就過，兩個欄位連 key 都沒有。
    for (
      const other of result.turns.filter((x) => x.forcedAct !== "check_out")
    ) {
      assertEquals(other.checkOutRetry, undefined, other.reply);
      assertEquals(other.checkOutStructuralFail, undefined, other.reply);
    }
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("Phase 4.5g（P2-1 對拍）：shape=truncate 的 check_out 輪兩發都違規時，runner 的 fail-open 字面＝handler 的字面", async () => {
  // 對拍固定輸入／期望值與 `chat_model_routing_test.ts` 的
  // `CHECK_OUT_PAIR_INPUT`／`CHECK_OUT_PAIR_EXPECTED` 同字面：先 truncate
  // （第一顆是問句 → 丟掉「先忙了」），後檢查仍命中（問句）→ fail-open。
  const CHECK_OUT_PAIR_INPUT = "你在忙嗎？\n先忙了";
  const CHECK_OUT_PAIR_EXPECTED = "你在忙嗎？";
  const scenario = AGENCY_SCENARIOS.find((s) => s.id === "A25")!;
  const original = globalThis.fetch;
  globalThis.fetch = () => Promise.resolve(fakeClassifierResponse(true));
  try {
    const result = await runAgencyScenario({
      callChat: () => Promise.resolve(CHECK_OUT_PAIR_INPUT),
      profileId: "practice_girl_004",
      scenario,
      repeat: 1,
      difficulty: "normal",
      mode: "game",
      style: true,
      agency: "on",
      shape: "truncate",
      stateSimulation: true,
      classifierApiKey: "test-key",
      chatModel: "deepseek",
    });
    assertEquals(result.error, undefined);
    const checkOut = result.turns.filter((t) => t.forcedAct === "check_out");
    assertEquals(checkOut.length, 1);
    const t = checkOut[0];
    assertEquals(t.reply, CHECK_OUT_PAIR_EXPECTED);
    assertEquals(t.shapeDropped, 1);
    assertEquals(t.attempts, 2);
    assertEquals(t.checkOutRetry, true);
    assertEquals(t.checkOutStructuralFail, true);
  } finally {
    globalThis.fetch = original;
  }
});

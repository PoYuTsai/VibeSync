// bakeoff 工具自測（零外部 API 呼叫）：驗證工具對 production 管線的保真度，
// 不驗模型行為。fake ModelCaller 記錄每一次呼叫，斷言呼叫形狀與順序。
import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  BAKEOFF_MEMORY_SUMMARY,
  BAKEOFF_MOMENT_BODY,
  buildBakeoffContextFixture,
  runOneSession,
} from "./bakeoff.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import { taipeiNowLabel } from "../../supabase/functions/practice-chat/time_context.ts";
import { SCRIPTS } from "./scripts.ts";

interface RecordedCall {
  kind: "chat" | "classify" | "debrief";
  promptText: string;
}

const DEFAULT_CLASSIFICATION = {
  connection: "neutral",
  impact: "minor",
  testHandling: "none",
  boundary: "safe",
  partnerMood: "amused",
  moodConfidence: 1,
  innerThought: "她覺得這個人還算有趣",
};

// jsonMode + maxTokens 區分三種呼叫（與 bakeoff 常數同值：classify 450、debrief 800）。
// classifyResponses 依 classify 次序覆寫回傳（測逐輪累積用）；不足時用預設。
function makeFakeCaller(
  calls: RecordedCall[],
  classifyResponses: Record<string, unknown>[] = [],
) {
  return (args: {
    messages: { role: string; content: string }[];
    maxTokens: number;
    jsonMode?: boolean;
  }): Promise<string> => {
    const promptText = args.messages.map((m) => m.content).join("\n");
    if (!args.jsonMode) {
      calls.push({ kind: "chat", promptText });
      return Promise.resolve(
        `回覆${calls.filter((c) => c.kind === "chat").length}號`,
      );
    }
    if (args.maxTokens === 450) {
      const index = calls.filter((c) => c.kind === "classify").length;
      calls.push({ kind: "classify", promptText });
      return Promise.resolve(
        JSON.stringify(classifyResponses[index] ?? DEFAULT_CLASSIFICATION),
      );
    }
    calls.push({ kind: "debrief", promptText });
    // 故意回不完整卡：debrief 失敗是 fail-open（記 debriefError，不中斷整場）。
    return Promise.resolve("{}");
  };
}

async function runFake(
  contextMode: "minimal" | "full",
  opts: {
    difficulty?: "easy" | "normal" | "challenge";
    classifyResponses?: Record<string, unknown>[];
  } = {},
) {
  const calls: RecordedCall[] = [];
  const record = await runOneSession({
    callModel: makeFakeCaller(calls, opts.classifyResponses ?? []),
    difficulty: opts.difficulty ?? "challenge",
    scriptId: "low_signal_polite",
    runIndex: 1,
    profileId: "practice_girl_001",
    contextMode,
  });
  return { calls, record };
}

Deno.test("分類器在取得回覆之後呼叫，且看得到剛生成的女孩回覆", async () => {
  const { calls } = await runFake("minimal");
  const rounds = SCRIPTS.low_signal_polite.length;
  // 每輪嚴格 chat → classify 交錯，最後一筆是 debrief。
  for (let i = 0; i < rounds; i++) {
    assertEquals(calls[i * 2].kind, "chat");
    assertEquals(calls[i * 2 + 1].kind, "classify");
    // 分類 prompt 內含同一輪剛生成的回覆（assistantReply 有傳）。
    assert(
      calls[i * 2 + 1].promptText.includes(`回覆${i + 1}號`),
      `round ${i + 1} 分類器看不到該輪回覆`,
    );
  }
  assertEquals(calls.at(-1)?.kind, "debrief");
});

Deno.test("partner state 逐輪累積（低信心輪沿用前輪 mood/innerThought），並回灌 prompt", async () => {
  // 第 1 輪高信心 amused；第 2 輪低信心＋空 innerThought——
  // applyPartnerStateUpdate 應沿用第 1 輪狀態（累積），不是被第 2 輪覆蓋。
  const { calls, record } = await runFake("minimal", {
    classifyResponses: [
      { ...DEFAULT_CLASSIFICATION, innerThought: "第一輪：她覺得有趣" },
      {
        ...DEFAULT_CLASSIFICATION,
        partnerMood: "neutral",
        moodConfidence: 0,
        innerThought: "",
      },
    ],
  });
  // 第一輪 chat prompt 尚無 partner state；第二輪起帶第一輪結果。
  assert(!calls[0].promptText.includes("mood: amused"));
  assert(calls[2].promptText.includes("mood: amused"));
  assert(calls[2].promptText.includes("第一輪：她覺得有趣"));
  // 第三輪 chat prompt（calls[4]）＝第二輪低信心後仍是累積下來的第一輪狀態。
  assert(calls[4].promptText.includes("mood: amused"), "低信心輪不得洗掉 mood");
  assert(
    calls[4].promptText.includes("第一輪：她覺得有趣"),
    "空 innerThought 不得洗掉前輪想法",
  );
  assertEquals(record.turns[0].partnerMood, "amused");
  assertEquals(record.turns[1].partnerMood, "amused");
});

Deno.test("full context 逐區塊注入 chat prompt；minimal 全數不注入", async () => {
  const full = await runFake("full");
  const minimal = await runFake("minimal");
  const fullPrompt = full.calls[0].promptText;
  const minimalPrompt = minimal.calls[0].promptText;
  const fixture = buildBakeoffContextFixture(
    resolvePracticeProfile({
      difficulty: "challenge",
      profileId: "practice_girl_001",
    }),
  );
  // 五個 production 區塊逐一斷言（mutation-test 等級：少注入任一塊就會紅）。
  const blocks: [string, string][] = [
    ["記憶摘要", BAKEOFF_MEMORY_SUMMARY],
    ["朋友圈貼文", BAKEOFF_MOMENT_BODY],
    ["生活情境", fixture.sceneContext.statusLine],
    ["認識管道", fixture.acquaintanceOrigin.sharedFact],
    ["台北時間", taipeiNowLabel(fixture.timeContext)],
  ];
  for (const [name, text] of blocks) {
    assert(text.length > 0, `${name} fixture 內容為空，斷言無效`);
    assert(fullPrompt.includes(text), `full chat prompt 缺${name}`);
    assert(!minimalPrompt.includes(text), `minimal chat prompt 不該有${name}`);
  }
  assertEquals(full.record.contextMode, "full");
  assert(
    full.record.turns[0].promptChars > minimal.record.turns[0].promptChars,
  );
});

Deno.test("debrief prompt：full 帶記憶／情境／管道／時間，但不帶朋友圈（對齊 handler）", async () => {
  const full = await runFake("full");
  const debriefPrompt = full.calls.find((c) => c.kind === "debrief")!
    .promptText;
  const fixture = buildBakeoffContextFixture(
    resolvePracticeProfile({
      difficulty: "challenge",
      profileId: "practice_girl_001",
    }),
  );
  assert(debriefPrompt.includes(BAKEOFF_MEMORY_SUMMARY), "debrief 缺記憶摘要");
  assert(
    debriefPrompt.includes(fixture.acquaintanceOrigin.sharedFact) ||
      debriefPrompt.includes(fixture.acquaintanceOrigin.debriefStandard),
    "debrief 缺認識管道",
  );
  assert(
    !debriefPrompt.includes(BAKEOFF_MOMENT_BODY),
    "debrief 不該帶朋友圈貼文（production 形狀）",
  );
});

Deno.test("同一 fixture 三難度共用：fixture 內容與難度無關", () => {
  const fixtures = (["easy", "normal", "challenge"] as const).map(
    (difficulty) =>
      JSON.stringify(buildBakeoffContextFixture(
        resolvePracticeProfile({
          difficulty,
          profileId: "practice_girl_001",
        }),
      )),
  );
  assertEquals(fixtures[0], fixtures[1]);
  assertEquals(fixtures[1], fixtures[2]);
});

Deno.test("debrief 失敗 fail-open：整場保留、記 debriefError", async () => {
  const { record } = await runFake("minimal");
  assertEquals(record.debrief, null);
  assertNotEquals(record.debriefError, undefined);
  assertEquals(record.turns.length, SCRIPTS.low_signal_polite.length);
});

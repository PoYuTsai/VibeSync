// bakeoff 工具自測（零網路）：驗證工具對 production 管線的保真度，
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
import { SCRIPTS } from "./scripts.ts";

interface RecordedCall {
  kind: "chat" | "classify" | "debrief";
  promptText: string;
}

// jsonMode + maxTokens 區分三種呼叫（與 bakeoff 常數同值：classify 450、debrief 800）。
function makeFakeCaller(calls: RecordedCall[]) {
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
      calls.push({ kind: "classify", promptText });
      return Promise.resolve(JSON.stringify({
        connection: "neutral",
        impact: "minor",
        testHandling: "none",
        boundary: "safe",
        partnerMood: "amused",
        moodConfidence: 1,
        innerThought: "她覺得這個人還算有趣",
      }));
    }
    calls.push({ kind: "debrief", promptText });
    // 故意回不完整卡：debrief 失敗是 fail-open（記 debriefError，不中斷整場）。
    return Promise.resolve("{}");
  };
}

async function runFake(
  contextMode: "minimal" | "full",
  difficulty: "easy" | "normal" | "challenge" = "challenge",
) {
  const calls: RecordedCall[] = [];
  const record = await runOneSession({
    callModel: makeFakeCaller(calls),
    difficulty,
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

Deno.test("partner state 逐輪累積並回灌下一輪 chat prompt", async () => {
  const { calls, record } = await runFake("minimal");
  // 第一輪 chat prompt 尚無 partner state；第二輪起帶上一輪的 mood/innerThought。
  assert(!calls[0].promptText.includes("mood: amused"));
  assert(calls[2].promptText.includes("mood: amused"));
  assert(calls[2].promptText.includes("她覺得這個人還算有趣"));
  assertEquals(record.turns[0].partnerMood, "amused");
});

Deno.test("full context 注入所有 production 區塊；minimal 沒有", async () => {
  const full = await runFake("full");
  const minimal = await runFake("minimal");
  const fullPrompt = full.calls[0].promptText;
  const minimalPrompt = minimal.calls[0].promptText;
  // 記憶摘要與朋友圈貼文是 fixture 自帶字串，最能直接證明注入成立。
  assert(fullPrompt.includes(BAKEOFF_MEMORY_SUMMARY), "缺記憶摘要");
  assert(fullPrompt.includes(BAKEOFF_MOMENT_BODY), "缺朋友圈貼文");
  assert(!minimalPrompt.includes(BAKEOFF_MEMORY_SUMMARY));
  assert(!minimalPrompt.includes(BAKEOFF_MOMENT_BODY));
  // full 的 prompt 明顯比 minimal 長（時間／情境／管道區塊都在裡面）。
  assert(fullPrompt.length > minimalPrompt.length + 100);
  assertEquals(full.record.contextMode, "full");
  assert(
    full.record.turns[0].promptChars > minimal.record.turns[0].promptChars,
  );
});

Deno.test("同一 fixture 三難度共用：fixture 內容與難度無關", () => {
  const easy = buildBakeoffContextFixture(
    resolvePracticeProfile({
      difficulty: "easy",
      profileId: "practice_girl_001",
    }),
  );
  const challenge = buildBakeoffContextFixture(
    resolvePracticeProfile({
      difficulty: "challenge",
      profileId: "practice_girl_001",
    }),
  );
  assertEquals(JSON.stringify(easy), JSON.stringify(challenge));
});

Deno.test("debrief 失敗 fail-open：整場保留、記 debriefError", async () => {
  const { record } = await runFake("minimal");
  assertEquals(record.debrief, null);
  assertNotEquals(record.debriefError, undefined);
  assertEquals(record.turns.length, SCRIPTS.low_signal_polite.length);
});

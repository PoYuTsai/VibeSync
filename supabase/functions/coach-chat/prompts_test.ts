import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildCoachChatPrompt } from "./prompts.ts";

Deno.test("buildCoachChatPrompt includes coach 1:1 positioning and JSON contract", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "我是不是太急？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [{ sender: "partner", text: "你感覺很有故事" }],
    dataQualityFlagged: false,
  });
  assertStringIncludes(prompt, "VibeSync Coach 1:1");
  assertStringIncludes(prompt, "不是套殼聊天機器人");
  assertStringIncludes(prompt, "收斂狀態機");
  assertStringIncludes(prompt, "不是幫他發散更多劇本");
  assertStringIncludes(prompt, "記憶使用規則");
  assertStringIncludes(prompt, "自然點出一個具體依據");
  assertStringIncludes(prompt, "不要寫成「我參考了 A/B/C」的報告");
  assertStringIncludes(prompt, '"mode"');
  assertStringIncludes(prompt, '"responseType"');
  assertStringIncludes(prompt, '"boundaryReminder"');
});

Deno.test("buildCoachChatPrompt carries active coaching turns and clarification rule", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    sessionId: "s1",
    userQuestion: "我其實想回她，但怕太裝",
    activeSessionTurns: [
      {
        role: "user",
        kind: "question",
        content: "她說我很有故事是什麼意思？",
      },
      {
        role: "coach",
        kind: "clarification",
        content: "你聽到她這句話後，心裡第一個反應是什麼？",
      },
    ],
    forceAnswer: false,
    rawReplyDraft: "哈哈哪有",
    recentMessages: [],
    dataQualityFlagged: false,
  });
  assertStringIncludes(prompt, "本次教練室對話");
  assertStringIncludes(prompt, "使用者原本想怎麼回");
  assertStringIncludes(prompt, "clarifyingQuestion 的 costDeducted 必須是 0");
  assertStringIncludes(prompt, "硬改使用者原句");
  assertStringIncludes(prompt, "1.8x 黃金法則");
  assertStringIncludes(prompt, "明顯錯字");
  assertStringIncludes(prompt, "不要照抄明顯錯字");
  assertStringIncludes(prompt, "使用者(question)：她說我很有故事是什麼意思？");
  assertStringIncludes(
    prompt,
    "教練(clarification)：你聽到她這句話後，心裡第一個反應是什麼？",
  );
});

Deno.test("buildCoachChatPrompt carries data-quality warning instead of traits", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "她到底什麼意思？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [],
    dataQualityFlagged: true,
    partnerHint: { name: "Candy" },
  });
  assertStringIncludes(prompt, "資料品質被標記為不可靠");
  assertEquals(prompt.includes("已知特質"), false);
});

Deno.test("buildCoachChatPrompt teaches sexual tension without shame or pressure", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "我想短期但不想讓她不舒服",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [],
    dataQualityFlagged: false,
  });
  assertStringIncludes(prompt, "承認慾望正常");
  assertStringIncludes(prompt, "避免製造性羞愧");
  assertStringIncludes(prompt, "絕不教施壓");
});

Deno.test("buildCoachChatPrompt converges line meaning into one working judgment", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "她說我很有故事是什麼意思？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [{ sender: "partner", text: "你感覺很有故事的人" }],
    dataQualityFlagged: false,
  });
  assertStringIncludes(prompt, "最多列 2 種合理含義");
  assertStringIncludes(prompt, "立刻選一個最可能的工作判斷");
  assertStringIncludes(prompt, "不要展開成選項清單");
});

Deno.test("buildCoachChatPrompt frames attached-partner invitations as role and cost judgment", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "她有男友還約我，我要不要去？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [],
    dataQualityFlagged: false,
  });
  assertStringIncludes(prompt, "對方有男友/女友/伴侶");
  assertStringIncludes(prompt, "時間成本");
});

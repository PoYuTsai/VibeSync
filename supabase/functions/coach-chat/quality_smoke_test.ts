import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildCoachChatPrompt } from "./prompts.ts";

function assertCoreSpec6Contract(prompt: string) {
  assertStringIncludes(prompt, "VibeSync Coach 1:1");
  assertStringIncludes(prompt, "收斂狀態機");
  assertStringIncludes(prompt, "記憶使用規則");
  assertStringIncludes(prompt, "一個工作判斷");
  assertStringIncludes(prompt, "一個最小下一步");
  assertStringIncludes(prompt, "不是幫他發散更多劇本");
}

Deno.test("Spec 6 smoke: line-meaning question uses memory and converges", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "spec6-line-meaning",
    userQuestion: "她說我很有故事是什麼意思？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [
      { sender: "partner", text: "你感覺是個很有故事的人" },
      { sender: "me", text: "哈哈哪有那麼誇張" },
    ],
    conversationSummary: "她前面會接話，但回覆速度偏慢。",
    analysisSnapshot: {
      heatScore: 64,
      stage: "升溫",
      summary: "對方有好奇，但還在觀察你的穩定度。",
      nextStep: "承認一半，再丟一個輕反問。",
      keySignals: ["人格觀察", "好奇但保留"],
    },
    effectiveStyleContext: "使用者偏自然、短句，不適合油膩撩法。",
    partnerHint: { name: "Candy", traits: ["慢熱", "觀察型"] },
    dataQualityFlagged: false,
  });

  assertCoreSpec6Contract(prompt);
  assertStringIncludes(prompt, "你感覺是個很有故事的人");
  assertStringIncludes(prompt, "熱度 64");
  assertStringIncludes(prompt, "使用者偏自然、短句");
  assertStringIncludes(prompt, "慢熱");
  assertStringIncludes(prompt, "最多列 2 種合理含義");
  assertStringIncludes(prompt, "立刻選一個最可能的工作判斷");
  assertStringIncludes(prompt, "不要展開成選項清單");
});

Deno.test("Spec 6 smoke: invite anxiety asks for intent before pushing", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "spec6-invite",
    userQuestion: "我想約她，但怕太急，怎麼問？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [
      { sender: "partner", text: "最近工作有點累，想找地方放空" },
      { sender: "me", text: "我也想找個地方休息一下" },
    ],
    analysisSnapshot: {
      heatScore: 72,
      stage: "深入",
      keySignals: ["生活窗口", "可輕邀約"],
    },
    dataQualityFlagged: false,
  });

  assertCoreSpec6Contract(prompt);
  assertStringIncludes(prompt, "我想約她，但怕太急");
  assertStringIncludes(
    prompt,
    "若缺少使用者感受、原本想回、真正目的或可承擔成本",
  );
  assertStringIncludes(prompt, "只問一個免費追問");
  assertStringIncludes(prompt, "該回、該問、該推進、該收");
});

Deno.test("Spec 6 smoke: reply polish preserves user's voice instead of over-rewriting", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "spec6-reply-polish",
    userQuestion: "我有想說的，幫我優化",
    rawReplyDraft: "其實我也想見你，但我怕太突然哈哈",
    activeSessionTurns: [],
    forceAnswer: true,
    recentMessages: [{ sender: "partner", text: "那你下次要不要直接約我" }],
    effectiveStyleContext: "使用者習慣輕鬆、真誠，不要變成制式話術。",
    dataQualityFlagged: false,
  });

  assertCoreSpec6Contract(prompt);
  assertStringIncludes(prompt, "使用者原本想怎麼回");
  assertStringIncludes(prompt, "其實我也想見你");
  assertStringIncludes(prompt, "不要為了看起來專業而硬改使用者原句");
  assertStringIncludes(prompt, "keep_original 或 light_edit");
  assertStringIncludes(prompt, "rewriteDecision");
  assertStringIncludes(prompt, "1.8x 黃金法則");
});

Deno.test("Spec 6 smoke: flagged profile only allows this conversation", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "spec6-flagged",
    userQuestion: "她是不是對我沒興趣？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [{ sender: "partner", text: "最近真的有點忙" }],
    partnerHint: { name: "Candy" },
    dataQualityFlagged: true,
  });

  assertCoreSpec6Contract(prompt);
  assertStringIncludes(prompt, "資料品質被標記為不可靠");
  assertStringIncludes(prompt, "以這段對話看");
  assertStringIncludes(prompt, "不要引用長期對象特質");
  assertEquals(prompt.includes("已知特質"), false);
});

Deno.test("Spec 6 smoke: attached-partner case prioritizes role, boundary, and cost", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "spec6-attached",
    userQuestion: "她有男友還約我單獨喝酒，我要去嗎？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [
      { sender: "partner", text: "我男友最近很忙，不然我們去喝一杯？" },
    ],
    dataQualityFlagged: false,
  });

  assertCoreSpec6Contract(prompt);
  assertStringIncludes(prompt, "對方有男友/女友/伴侶");
  assertStringIncludes(prompt, "朋友邀約、曖昧試探、情緒空洞、界線模糊");
  assertStringIncludes(prompt, "讓使用者看清自己想站的位置與時間成本");
  assertStringIncludes(prompt, "界線、成本或風險提醒");
});

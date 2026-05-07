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
  assertStringIncludes(prompt, "hesitatesToMoveForward");
  assertStringIncludes(prompt, "fearOfMistake");
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

Deno.test("Spec 6 smoke: adult same-night escalation stays concrete and consent-first", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "spec6-adult-close",
    userQuestion: "酒吧聊得不錯，我想今晚收尾，怎麼自然轉場？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [
      { sender: "partner", text: "這裡太吵了，我有點聽不到你說話" },
      { sender: "me", text: "那我們等等換個地方？" },
    ],
    analysisSnapshot: {
      heatScore: 78,
      stage: "升溫",
      keySignals: ["願意轉場", "酒吧局"],
    },
    dataQualityFlagged: false,
  });

  assertCoreSpec6Contract(prompt);
  assertStringIncludes(prompt, "成人約會與場景判讀");
  assertStringIncludes(prompt, "支持成年人之間合意、清醒、可拒絕、可停止");
  assertStringIncludes(prompt, "先想好自然下一站、路線、時間感與退路");
  assertStringIncludes(prompt, "低壓轉場");
  assertStringIncludes(prompt, "戴套");
  assertStringIncludes(prompt, "絕不教突破拒絕");
});

Deno.test("Spec 6 smoke: explicit sex technique stays health-and-communication framed", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "spec6-explicit-sex",
    userQuestion: "她問我喜歡什麼姿勢，我想講得色色但不要瞎聊",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [
      { sender: "partner", text: "你看起來很會，但不知道是不是真的" },
      { sender: "me", text: "那要看你想怎麼驗證" },
    ],
    dataQualityFlagged: false,
  });

  assertCoreSpec6Contract(prompt);
  assertStringIncludes(prompt, "很露骨的性詞彙");
  assertStringIncludes(prompt, "成熟性健康/親密溝通教練");
  assertStringIncludes(prompt, "不要寫色情故事");
  assertStringIncludes(prompt, "問對方感受");
  assertStringIncludes(prompt, "不要假裝每個人都適合同一招");
});

Deno.test("Spec 6 smoke: session state prevents repeated clarification", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "spec6-session-state",
    sessionId: "coach-c1-1",
    userQuestion: "等等，我現在有點困惑，你剛剛不是說已經約她了嗎？",
    activeSessionTurns: [
      {
        role: "user",
        kind: "question",
        content: "她這樣是不是想約我？",
      },
      {
        role: "coach",
        kind: "clarification",
        content: "你聽到她這句話後，心裡第一個反應是什麼？",
      },
    ],
    forceAnswer: false,
    recentMessages: [
      { sender: "partner", text: "下次可以一起去那家店" },
      { sender: "me", text: "可以啊，我也想去看看" },
    ],
    dataQualityFlagged: false,
  });

  assertCoreSpec6Contract(prompt);
  assertStringIncludes(prompt, "本輪教練狀態");
  assertStringIncludes(prompt, "本輪已追問過");
  assertStringIncludes(prompt, "不要重複同一個追問");
  assertStringIncludes(prompt, "先承認並整合前後脈絡");
  assertStringIncludes(prompt, "修正後的一個工作判斷");
});

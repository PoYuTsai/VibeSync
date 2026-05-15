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
  assertStringIncludes(prompt, '"frictionType"');
  assertStringIncludes(prompt, "fearOfMistake");
  assertStringIncludes(prompt, "30 秒到 5 分鐘內可做完");
  assertStringIncludes(prompt, '"boundaryReminder"');
});

Deno.test("buildCoachChatPrompt carries outcome digest as auxiliary memory", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "我下一句要怎麼接？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [{ sender: "partner", text: "最近工作有點忙" }],
    outcomeDigestContext:
      "本地結果摘要：最近 3 次教練建議回報，對方有接 2、冷回 1。",
    dataQualityFlagged: false,
  });
  assertStringIncludes(prompt, "教練結果記憶");
  assertStringIncludes(prompt, "僅作輔助線索");
  assertStringIncludes(prompt, "對方有接 2");
  assertStringIncludes(prompt, "不可過度推論對方性格");
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
  assertStringIncludes(prompt, "本輪教練狀態");
  assertStringIncludes(prompt, "本輪已追問過");
  assertStringIncludes(prompt, "使用者正在補充：我其實想回她，但怕太裝");
  assertStringIncludes(prompt, "不要重複同一個追問");
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

Deno.test("buildCoachChatPrompt handles adult intimacy logistics with consent and safety", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "我想約砲，今晚怎麼自然帶去旅館？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [],
    dataQualityFlagged: false,
  });

  assertStringIncludes(prompt, "約砲");
  assertStringIncludes(prompt, "帶去旅館");
  assertStringIncludes(prompt, "短期親密意圖");
  assertStringIncludes(prompt, "低壓轉場或確認句");
  assertStringIncludes(prompt, "清醒同意");
  assertStringIncludes(prompt, "戴套");
  assertStringIncludes(prompt, "不要利用酒精/壓力/承諾");
});

Deno.test("buildCoachChatPrompt reframes resistance language as consent calibration", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "最後一分鐘抵抗怎麼處理？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [],
    dataQualityFlagged: false,
  });

  assertStringIncludes(prompt, "最後一分鐘抵抗");
  assertStringIncludes(prompt, "不要照抄成技巧");
  assertStringIncludes(prompt, "可能就是不想");
  assertStringIncludes(prompt, "絕不教突破拒絕");
  assertStringIncludes(prompt, "說不要");
  assertStringIncludes(prompt, "suggestedLine 用停止/照顧/送回安全處");
});

Deno.test("buildCoachChatPrompt covers social venue and hostess context without moralizing", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "KTV多人局或去酒店遇到坐檯妹，要怎麼互動？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [],
    dataQualityFlagged: false,
  });

  assertStringIncludes(prompt, "夜店/KTV/多人局");
  assertStringIncludes(prompt, "不要只盯單一目標");
  assertStringIncludes(prompt, "酒店/坐檯");
  assertStringIncludes(prompt, "情緒勞動或服務");
  assertStringIncludes(prompt, "金錢、時間與自尊成本");
  assertStringIncludes(prompt, "不高道德、不說教");
});

Deno.test("buildCoachChatPrompt treats explicit sex questions as practical intimacy coaching", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "如果她問我想用什麼性愛姿勢，怎麼聊比較不瞎？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [],
    dataQualityFlagged: false,
  });

  assertStringIncludes(prompt, "很露骨的性詞彙");
  assertStringIncludes(prompt, "性愛姿勢");
  assertStringIncludes(prompt, "成熟性健康/親密溝通教練");
  assertStringIncludes(prompt, "不要寫色情故事");
  assertStringIncludes(prompt, "不要做角色扮演");
  assertStringIncludes(prompt, "溝通、舒適度、身體訊號、安全、節奏");
  assertStringIncludes(prompt, "疼痛就停");
  assertStringIncludes(prompt, "用潤滑");
  assertStringIncludes(prompt, "戴套");
});

Deno.test("buildCoachChatPrompt routes sexual health risks to safety guidance", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    userQuestion: "保險套破了或她說會痛怎麼辦？",
    activeSessionTurns: [],
    forceAnswer: false,
    recentMessages: [],
    dataQualityFlagged: false,
  });

  assertStringIncludes(prompt, "疼痛、出血、性功能障礙、性病症狀、避孕失誤");
  assertStringIncludes(prompt, "降低撩感");
  assertStringIncludes(prompt, "健康安全建議");
  assertStringIncludes(prompt, "就醫/篩檢/緊急避孕");
  assertStringIncludes(prompt, "不要診斷");
  assertStringIncludes(prompt, "不要保證沒有風險");
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

Deno.test("buildCoachChatPrompt makes force-answer session state explicit", () => {
  const prompt = buildCoachChatPrompt({
    conversationId: "c1",
    sessionId: "s1",
    userQuestion: "她是什麼意思？",
    activeSessionTurns: [
      {
        role: "user",
        kind: "question",
        content: "她是什麼意思？",
      },
      {
        role: "coach",
        kind: "clarification",
        content: "你聽到後第一個反應是什麼？",
      },
    ],
    forceAnswer: true,
    recentMessages: [],
    dataQualityFlagged: false,
  });

  assertStringIncludes(prompt, "使用者選擇直接看正式建議");
  assertStringIncludes(prompt, "本回合必須輸出 coachAnswer");
  assertStringIncludes(prompt, "不要再問 clarifyingQuestion");
  assertStringIncludes(prompt, "低信心");
});

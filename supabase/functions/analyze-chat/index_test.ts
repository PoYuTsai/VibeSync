// supabase/functions/analyze-chat/index_test.ts
// Note: Edge Function tests run via Deno test

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

// 訊息計算函數
function countMessages(messages: Array<{ content: string }>): number {
  let total = 0;
  for (const msg of messages) {
    const charCount = msg.content.trim().length;
    total += Math.max(1, Math.ceil(charCount / 200));
  }
  return Math.max(1, total);
}

// 模型選擇函數
function selectModel(context: {
  conversationLength: number;
  enthusiasmLevel: string | null;
  hasComplexEmotions: boolean;
  isFirstAnalysis: boolean;
  tier: string;
}): string {
  if (context.tier === "essential") {
    return "claude-sonnet-4-20250514";
  }

  if (
    context.conversationLength > 20 ||
    context.enthusiasmLevel === "cold" ||
    context.hasComplexEmotions ||
    context.isFirstAnalysis
  ) {
    return "claude-sonnet-4-20250514";
  }

  return "claude-3-5-haiku-20241022";
}

// Test countMessages function
Deno.test("countMessages - single short message", () => {
  const messages = [{ content: "你好" }];
  assertEquals(countMessages(messages), 1);
});

Deno.test("countMessages - multiple messages", () => {
  const messages = [
    { content: "你好" },
    { content: "在嗎" },
    { content: "吃飯了嗎" },
  ];
  assertEquals(countMessages(messages), 3);
});

Deno.test("countMessages - long message splits by 200 chars", () => {
  const longContent = "a".repeat(450); // 450 chars = ceil(450/200) = 3
  const messages = [{ content: longContent }];
  assertEquals(countMessages(messages), 3);
});

Deno.test("countMessages - exactly 200 chars is 1 message", () => {
  const content = "a".repeat(200);
  const messages = [{ content }];
  assertEquals(countMessages(messages), 1);
});

Deno.test("countMessages - 201 chars is 2 messages", () => {
  const content = "a".repeat(201);
  const messages = [{ content }];
  assertEquals(countMessages(messages), 2);
});

Deno.test("countMessages - empty message counts as 1", () => {
  const messages = [{ content: "" }];
  assertEquals(countMessages(messages), 1);
});

Deno.test("countMessages - whitespace only message counts as 1", () => {
  const messages = [{ content: "   " }];
  assertEquals(countMessages(messages), 1);
});

// Test selectModel function
Deno.test("selectModel - essential tier always uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 5,
    enthusiasmLevel: "hot",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "essential",
  });
  assertEquals(model, "claude-sonnet-4-20250514");
});

Deno.test("selectModel - first analysis uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 3,
    enthusiasmLevel: null,
    hasComplexEmotions: false,
    isFirstAnalysis: true,
    tier: "free",
  });
  assertEquals(model, "claude-sonnet-4-20250514");
});

Deno.test("selectModel - cold enthusiasm uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 10,
    enthusiasmLevel: "cold",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "starter",
  });
  assertEquals(model, "claude-sonnet-4-20250514");
});

Deno.test("selectModel - long conversation uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 25,
    enthusiasmLevel: "warm",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "free",
  });
  assertEquals(model, "claude-sonnet-4-20250514");
});

Deno.test("selectModel - simple conversation uses Haiku", () => {
  const model = selectModel({
    conversationLength: 10,
    enthusiasmLevel: "warm",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "free",
  });
  assertEquals(model, "claude-3-5-haiku-20241022");
});

Deno.test("selectModel - complex emotions uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 5,
    enthusiasmLevel: "warm",
    hasComplexEmotions: true,
    isFirstAnalysis: false,
    tier: "starter",
  });
  assertEquals(model, "claude-sonnet-4-20250514");
});

Deno.test({
  name:
    "SYSTEM_PROMPT locks personality-observation replies into half-agree + image + question",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("情境2.6: 人格觀察/輕鬆貼標籤"));
    assert(source.includes("承認一半 + 補一個具體畫面 + 反問她是哪一派"));
    assert(source.includes("finalRecommendation.content 不能只是認同或附和"));
    assert(source.includes("replies.extend 也必須是「可直接送出」的句子"));
    assert(source.includes("每張卡都要是可直接送出的回覆"));
    assert(source.includes("1.8x 是節奏護欄，不是保守無聊的理由"));
    assert(source.includes("personality_observation"));
    assert(source.includes("被妳發現了，我會在飲料櫃前思考人生"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT forces all five reply styles to be sendable next-turn messages",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("五種回覆品質契約"));
    assert(source.includes("接球三步"));
    assert(source.includes("接住她的情緒或具體可接球點"));
    assert(source.includes("加一點互動感"));
    assert(source.includes("順勢延伸下一輪"));
    assert(source.includes("coachActionHint.catchablePoint"));
    assert(source.includes("五種 replies 都要優先圍繞同一個球點"));
    assert(source.includes("extend（延展）：接住她的具體話題"));
    assert(source.includes("resonate（共鳴）：先命名或貼近她的情緒"));
    assert(source.includes("tease（調情）：用安全的誤讀"));
    assert(source.includes("humor（幽默）：用自嘲、荒謬畫面"));
    assert(source.includes("coldRead（冷讀）：根據她剛說的具體線索"));
    assert(source.includes("禁止輸出這類「報告腔」"));
    assert(source.includes("絕命毒師很會讓人一集接一集欸"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT selects the best cues from multi-message life updates",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("多句連續分享的選球規則"));
    assert(source.includes("不要逐句查戶口"));
    assert(source.includes("先做「選球」"));
    assert(source.includes("通常只選 1-2 顆球，最多 3 顆"));
    assert(source.includes("把 2 顆球自然串成一則可送出的訊息"));
    assert(source.includes("finalRecommendation.reason 要簡短說明"));
    assert(source.includes("接住她對 F1 的興奮，再順到夜市行程"));
    assert(source.includes("白天看人差點打起來"));
    assert(source.includes("樂華夜市最後會帶什麼罪惡美食回家"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT preserves userDraft intent instead of answering latest partner message",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("這是用戶真正想表達的主要意圖"));
    assert(source.includes("不要為了接上一句而改掉主題"));
    assert(source.includes("不得把 userDraft 改寫成回答對方最後一題"));
    assert(source.includes("感覺你潛水很厲害"));
    assert(source.includes("不要回答「你有在健身嗎」"));
    assert(source.includes("不要新增 userDraft 沒有的事實"));
    assert(source.includes("「草稿潤飾」代表使用者期待你把原句變得更好"));
    assert(source.includes("optimized 必須是可直接送出的訊息"));
    assert(source.includes("更口語、更順、更有情緒溫度、更好接球"));
    assert(source.includes("妳潛水看起來蠻有架式欸"));
    assert(source.includes("不可改成「有在勤，但不算很勤勞"));
    assert(source.includes("Preserve the draft's main topic and intent"));
    assert(
      source.includes("Actually improve the draft into a sendable message"),
    );
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT aligns analyze-chat with VibeSync memory coach positioning",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("你是 VibeSync：有記憶的 AI 約會教練"));
    assert(
      source.includes(
        "不只回答「怎麼回」，也要判斷「要不要回」「值不值得投入」「該推進還是該收」",
      ),
    );
    assert(
      source.includes(
        "健康的主動性 = 清楚表達意願 + 尊重對方反應 + 能承擔被拒絕",
      ),
    );
    assert(source.includes("決策流程（必須由上而下）"));
    assert(source.includes("Go / No-Go 判斷"));
    assert(source.includes("RelationshipRiskAndTimeCostFrame"));
    assert(source.includes("可見輸出禁用內部術語"));
    assert(source.includes("不要把一次玩笑、一次情緒或一次敷衍推測成長期人格"));
    assert(source.includes("go_no_go"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT requires coachActionHint to cite a concrete catchable point",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("可接球點教練卡 (coachActionHint)"));
    assert(source.includes("這張卡會貼在聊天窗正下方"));
    assert(source.includes("真的讀懂上方對話"));
    assert(source.includes("catchablePoint"));
    assert(source.includes("在家追劇 / 絕命毒師"));
    assert(source.includes("不要把 heat score 放在第一句"));
    assert(source.includes("finalRecommendation 才給可送出的句子"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT acknowledges short-term intimacy intent without teaching manipulation",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("情境10: 短期關係 / 約炮 / 炮友意圖"));
    assert(source.includes("不要忽略、羞辱或假裝他想認真交往"));
    assert(
      source.includes(
        "清楚同意、誠實期待、關係透明、安全措施、情緒後果、可退出邊界",
      ),
    );
    assert(source.includes("可以給低壓邀約或釐清期待的訊息"));
    assert(source.includes("不提供推進成親密關係的路線"));
    assert(source.includes("我現在比較適合輕鬆、低壓、不急著定義的相處"));
    assert(source.includes("教用戶騙對方、吊著對方、用承諾換親密、灌酒推進"));
    assert(source.includes("若用戶出現性羞愧"));
    assert(source.includes("成熟的男人不是沒有慾望"));
    assert(source.includes("有慾望很正常"));
    assert(source.includes("性與親密是成人關係中正常的一部分"));
  },
});

Deno.test({
  name: "SYSTEM_PROMPT keeps flirtation calibrated without becoming explicit",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("情境11: 聊騷尺度 / 曖昧張力"));
    assert(source.includes("不要裝沒看到，也不要立刻升級成露骨性內容"));
    assert(source.includes("繁中語境重點"));
    assert(source.includes("幽默、隱喻、留白、反差與具體畫面感"));
    assert(source.includes("激起好奇與想靠近的期待"));
    assert(source.includes("調情、暗示、留白、承認吸引、轉向見面"));
    assert(source.includes("不輸出 Level 3 露骨性描寫"));
    assert(source.includes("如果氣氛對，我應該不會假裝沒想過"));
    assert(
      source.includes("具體性器官、性行為細節、命令式挑逗、線上性愛式長文"),
    );
  },
});

Deno.test({
  name: "SYSTEM_PROMPT handles complex emotional dynamics in main analysis",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("情境12: 複雜情緒 / 關係修復 / 全局判讀"));
    assert(source.includes("先同理用戶，也同理對方可能處境"));
    assert(source.includes("不要直接套邀約或技巧"));
    assert(
      source.includes(
        "先判斷用戶情緒、對方處境、關係位置、時間成本與下一步風險",
      ),
    );
    assert(
      source.includes("回覆、暫停、道歉、低成本釐清、降低投入，或完全不赴局"),
    );
    assert(source.includes("把對方反應和用戶價值拆開"));
    assert(source.includes("同理上頭感，但提醒降速"));
    assert(source.includes("保住尊嚴，不糾纏、不追問原因"));
    assert(source.includes("不要鼓勵控制、查勤、逼問或試探"));
    assert(source.includes("短、誠實、不求立刻原諒"));
    assert(source.includes("人生低潮或非感情壓力"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT uses relationship risk and time-cost triage without over-expanding",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("RelationshipRiskAndTimeCostFrame"));
    assert(
      source.includes("關係是否透明、目的是否清楚、時間/金錢成本是否合理"),
    );
    assert(source.includes("關係透明：對方是否單身 / 是否公開透明"));
    assert(
      source.includes("目的清楚：這是朋友局、工作局、情緒空窗，還是曖昧邀約"),
    );
    assert(source.includes("金錢/利用風險"));
    assert(source.includes("借錢、投資、訂房、機票、送禮、一直要求請客"));
    assert(source.includes("減法原則（不要補這些）"));
    assert(source.includes("不補 PUA 技巧庫"));
    assert(source.includes("不做人格診斷"));
    assert(source.includes("不把所有問題都導向邀約、聊騷或短期親密"));
    assert(source.includes("risk_time_cost"));
    assert(source.includes("complex_emotion"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT treats qualificationSignal as investment, not proving herself",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("興趣 / 投入訊號 (qualificationSignal)"));
    assert(source.includes("不是「她在證明自己」"));
    assert(source.includes("感覺你是個很有故事的人"));
    assert(source.includes("這代表好奇和觀察，但不是她在展示自己"));
    assert(source.includes('"qualificationSignal": false'));
  },
});

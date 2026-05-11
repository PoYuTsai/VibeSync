// supabase/functions/analyze-chat/index_test.ts
// Note: Edge Function tests run via Deno test

import {
  assert,
  assertEquals,
  assertFalse,
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
    assert(
      source.includes("replyOptions.extend.messages 也必須是可複製的自然訊息"),
    );
    assert(source.includes("每張卡都要同時有可執行接法與可複製訊息組"));
    assert(source.includes("1.8x 是節奏護欄，不是保守無聊的理由"));
    assert(source.includes("1.8x 不是死板字數公式"));
    assert(source.includes("投入感比例"));
    assert(source.includes("多句連續分享：不要只拿最後一條算長度"));
    assert(source.includes("1.8x 是上限，不是目標"));
    assert(source.includes("用最少的字接住最值得接的球"));
    assert(source.includes("自然引用原則"));
    assert(source.includes("personality_observation"));
    assert(source.includes("被妳發現了，我會在飲料櫃前思考人生"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT forces all five reply styles to be approach plus message groups",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("五種回覆品質契約"));
    assert(source.includes("推薦接法 + 訊息組"));
    assert(source.includes("接球三步"));
    assert(source.includes("接住她的情緒或具體可接球點"));
    assert(source.includes("加一點互動感"));
    assert(source.includes("順勢延伸下一輪"));
    assert(source.includes("coachActionHint.catchablePoint"));
    assert(source.includes("五種 replyOptions 都要優先圍繞同一個球點"));
    assert(source.includes("混合式回覆卡規則"));
    assert(source.includes("不要只給「直接貼上」的長文"));
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
  name: "SYSTEM_PROMPT selects the best cues from multi-message life updates",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("多句連續分享的選球規則"));
    assert(source.includes("不要逐句查戶口"));
    assert(source.includes("先做「選球」"));
    assert(source.includes("通常只選 1-2 顆球，最多 3 顆"));
    assert(source.includes("不要把 4-5 則內容硬擠成一句"));
    assert(source.includes("replyOptions：五種風格的主要輸出"));
    assert(source.includes("messages 每段都盡量有 sourceMessage"));
    assert(source.includes("finalRecommendation.reason 要簡短說明"));
    assert(source.includes("接住她對 F1 的興奮，再順到夜市行程"));
    assert(source.includes("白天看人差點打起來"));
    assert(source.includes("樂華夜市最後會帶什麼罪惡美食回家"));
    assert(source.includes("可用換行表示 2-3 則真人訊息，但不要放 ①②"));
    assertFalse(source.includes("finalRecommendation.content 必須分句標註"));
    assertFalse(source.includes("① 回「她的原文關鍵詞」"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT treats Mandarin questions as functional cues, not mandatory answers",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("中文問句框架判斷"));
    assert(source.includes("問號不等於必答題"));
    assert(source.includes("真問題 / 資訊需求"));
    assert(source.includes("情緒球 / 求共鳴"));
    assert(source.includes("互動測試 / 框架問題"));
    assert(source.includes("玩笑反問 / 語氣球"));
    assert(source.includes("查戶口 / 低價值問題"));
    assert(source.includes("邊界 / 安全 / 關係風險問題"));
    assert(source.includes("答、半答、重框、略過、反丟"));
    assert(source.includes("不要點對點自證"));
    assert(source.includes("這題比較像測框架，不必認真自證"));
    assert(source.includes("你是不是很會撩？"));
    assert(source.includes("太認真回答就不好玩了"));
    assert(source.includes("中文問句不一定都是必答題"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT supports structured split replies with quoted source messages",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("分段引用與 emoji 畫龍點睛"));
    assert(source.includes("一句總回"));
    assert(source.includes("分開回"));
    assert(source.includes("finalRecommendation.replySegments"));
    assert(source.includes("replyOptions.*.messages 也要套用同樣規則"));
    assert(source.includes("sourceMessage"));
    assert(source.includes("sourceIndex"));
    assert(source.includes("replySegments 最多 3 段"));
    assert(source.includes("讓 App 顯示引用原句與分段複製"));
    assert(source.includes("可直接複製送出的那句"));
    assert(source.includes("emoji 是畫龍點睛，不是裝飾品"));
    assert(source.includes("一則回覆最多 0-1 個 emoji"));
    assert(source.includes("不要用太多愛心、火、色色符號"));
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
    "SYSTEM_PROMPT keeps draft polish natural, bounded, and non-AI sounding",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("emoji 只在補語氣、補情緒或降低壓力時使用"));
    assert(source.includes("最多 0-1 個"));
    assert(source.includes("不要把用戶口吻過度美化成文青、客服或 AI 腔"));
    assert(source.includes("慾望、邀約、親密、短期意圖或推進意圖"));
    assert(source.includes("清楚、低壓、可拒絕、不越界"));
    assert(source.includes("Keep the user's natural voice"));
    assert(source.includes("do not over-polish into poetic"));
    assert(source.includes("keeping consent/exit room clear"));
  },
});

Deno.test({
  name:
    "MY_MESSAGE_PROMPT provides concrete branch planning without invented topics",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("你是 VibeSync 的「我說模式」教練"));
    assert(source.includes("這不是完整分析報告，也不是算命"));
    assert(source.includes("下一句可以直接拿來接的方案"));
    assert(source.includes("如果她冷淡回覆：保住尊嚴、降低壓力"));
    assert(source.includes("suggestion 必須像可以直接拿來接的下一句"));
    assert(source.includes("備用話題只能來自"));
    assert(source.includes("不要編造她喜歡咖啡"));
    assert(source.includes("目前備用話題不足"));
  },
});

Deno.test({
  name:
    "OPENER_PROMPT prioritizes visible cues and replyability over personality guesses",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("你是 VibeSync 的開場救星先鋒教練"));
    assert(source.includes("開場白的北極星：低壓、具體、可回、像真人"));
    assert(source.includes("每天可能收到很多罐頭訊息"));
    assert(source.includes("推薦開場必須有一點好奇心鉤子"));
    assert(source.includes("更偏玩咖"));
    assert(source.includes("這男的是怎樣？我來跟他尬一下"));
    assert(source.includes("VibeSync 是教練，不是話術產生器"));
    assert(source.includes("回話只是示範，框架大於話術"));
    assert(source.includes("怎麼丟球、怎麼維持男人框架、怎麼讓女生有球可以回"));
    assert(
      source.includes(
        "先讀資料，再開場（Profile Read → Frame → Hook → Opener）",
      ),
    );
    assert(source.includes("先避開 avoidTopics"));
    assert(source.includes("判斷框架 frameRead"));
    assert(source.includes("界線要被內化，不一定要被唸出來"));
    assert(source.includes("可接線索 positiveHooks"));
    assert(source.includes("高手觀察 masterObservation"));
    assert(source.includes("好奇心鉤子 curiosityHook"));
    assert(source.includes("推薦策略 openingStrategy"));
    assert(source.includes("如果自介明確說不要問工作、不要約酒、討厭沒誠意"));
    assert(source.includes("中文語境注意：「不約」通常表示不要低成本約砲"));
    assert(source.includes("不是「永遠不見面」或「不能認識」"));
    assert(source.includes("不要在 opener 或 reason 裡主動提「不約」"));
    assert(source.includes("讓對話自然走到可約"));
    assert(source.includes("可見線索優先"));
    assert(source.includes("不要假裝看出很深的人格"));
    assert(source.includes("profileAnalysis.avoidTopics"));
    assert(source.includes("profileAnalysis.frameRead"));
    assert(source.includes("profileAnalysis.positiveHooks"));
    assert(source.includes("profileAnalysis.masterObservation"));
    assert(source.includes("profileAnalysis.curiosityHook"));
    assert(source.includes("profileAnalysis.openingStrategy"));
    assert(source.includes("場景分流"));
    assert(source.includes("自介資訊量分流"));
    assert(source.includes("自介很長、界線很多"));
    assert(source.includes("自介只有一句話"));
    assert(source.includes("幾乎沒有自介、只有自拍"));
    assert(source.includes("脫穎而出：好奇心鉤子"));
    assert(source.includes("二選一"));
    assert(source.includes("小反差"));
    assert(source.includes("輕自嘲"));
    assert(source.includes("畫面感"));
    assert(source.includes("輕微挑戰"));
    assert(source.includes("可愛地怪"));
    assert(source.includes("實戰高手特質：借優點，不借操控"));
    assert(source.includes("鬆弛、自信、框架感、輕微推拉、非乞求感"));
    assert(source.includes("平等框架"));
    assert(source.includes("輕判斷可反駁"));
    assert(source.includes("非乞求感"));
    assert(source.includes("先畫面再問題"));
    assert(source.includes("少字有勁"));
    assert(source.includes("少字有勁：可複製內容不要長"));
    assert(source.includes("openers 本身是要讓用戶直接貼出去的訊息"));
    assert(source.includes("每個 opener 建議 12-38 個中文字"));
    assert(source.includes("特殊情況最多 45 個中文字"));
    assert(source.includes("不要解釋招式，不要鋪墊，不要自證有看自介"));
    assert(source.includes("觀察 + 小框架 + 好回出口"));
    assert(source.includes("高手觀察法：規則是背景，反差才是入口"));
    assert(source.includes("真正高手會看，但不會拿來逐條回覆"));
    assert(source.includes("規則只是背景紅線"));
    assert(source.includes("妳是不是那種明明該補眠，結果又突然開一個新坑的人"));
    assert(source.includes("玩咖但有邊界"));
    assert(source.includes("旁路冷讀：不要把線索原文講破"));
    assert(source.includes("從資料旁邊長出一個合理但不明說的推測"));
    assert(source.includes("不要直接說「妳在酒吧上班」或問上班"));
    assert(source.includes("妳感覺蠻會唱歌"));
    assert(source.includes("優先讓 coldRead 風格使用旁路冷讀"));
    assert(source.includes("三層優先級：來回 > 男人框架 > 幽默"));
    assert(source.includes("像羽毛球一樣能來來回回"));
    assert(source.includes("不要把球打死"));
    assert(source.includes("你也在觀察她，而不是單方面求她認可"));
    assert(source.includes("不刻意的幽默才有吸引力"));
    assert(source.includes("她有球可以打回來"));
    assert(source.includes("框架大於話術"));
    assert(source.includes("所有 opener 都是示範，不是唯一正解"));
    assert(source.includes("這句在丟哪顆球"));
    assert(
      source.includes("recommendation.reason 必須說明「這句示範了什麼框架」"),
    );
    assert(source.includes("兩顆球策略：不必每次都押一句神回"));
    assert(source.includes("第一球：微拉、畫面感、輕微挑戰"));
    assert(source.includes("初期只能微拉，不要重拉"));
    assert(source.includes("第二球：冷讀、觀察、可被反駁"));
    assert(source.includes("實戰短句範例"));
    assert(source.includes("調情：「沒到微胖吧，挺辣，謙虛了。」"));
    assert(source.includes("沒到微胖吧，挺辣，謙虛了"));
    assert(source.includes("只在她自介/標籤/用戶描述已經提到微胖"));
    assert(source.includes("妳感覺蠻會唱歌"));
    assert(source.includes("短、留白、可反駁、可接球"));
    assert(source.includes("長自介 / 規則多 / 仍有正向線索的範例"));
    assert(source.includes("如果她自介很長，不要誤判成「線索少」"));
    assert(
      source.includes(
        "妳自介寫那麼完整，我反而比較想問：最近最想學的新東西是什麼？",
      ),
    );
    assert(source.includes("不是難聊，是不想把時間浪費在罐頭對話上"));
    assert(source.includes("自介有點像入境規定"));
    assert(source.includes("走私罐頭訊息"));
    assert(source.includes("五種風格各有任務"));
    assert(source.includes("不要把它們全部做成同一種玩咖推拉"));
    assert(source.includes("用戶看到的名稱是「調情」"));
    assert(source.includes("不要輸出「微拉」這個內部術語"));
    assert(source.includes("目標質感接近「沒到微胖吧，挺辣，謙虛了。」"));
    assert(source.includes("目標質感接近「妳感覺蠻會唱歌。」"));
    assert(source.includes("不把線索原文說破"));
    assert(source.includes("初期陌生開場只能微拉"));
    assert(source.includes("這張卡在 UI 叫「調情」"));
    assert(source.includes("不要把內部術語「微拉」寫給用戶"));
    assert(source.includes("幽默是加分項，不是必要項"));
    assert(source.includes("優先保留來回感與男人框架"));
    assert(source.includes("Specialness Gate：不特別就重寫"));
    assert(source.includes("如果輸出只是一般人也會問的安全句，產品就失去價值"));
    assert(source.includes("拿掉對方資料仍然能套在任何人身上"));
    assert(source.includes("最 special、最有機會從一百則訊息裡跳出來"));
    assert(source.includes("Female Reply Check：換位思考女生會不會回"));
    assert(source.includes("想笑、想反駁、想補充、想問「你怎麼知道」"));
    assert(source.includes("低成本回覆入口"));
    assert(source.includes("我只會已讀、不知道回什麼、覺得他在自嗨"));
    assert(source.includes("讓女生真的有可能回"));
    assert(source.includes("先鋒備案：開場不是終點"));
    assert(source.includes("開場救星是產品的「先鋒」"));
    assert(source.includes("ifCold"));
    assert(source.includes("ifShortPositive"));
    assert(source.includes("ifEngaged"));
    assert(source.includes("handoff"));
    assert(source.includes("貼回對話分析"));
    assert(source.includes("問 1:1 coach"));
    assert(source.includes("opener_quota_exceeded"));
    assert(source.includes("本月額度不足，升級方案可取得更多開場與分析額度。"));
    assert(source.includes("交友軟體"));
    assert(source.includes("IG / 限動"));
    assert(source.includes("現實認識"));
    assert(source.includes("先不踩雷 > 有看資料 > 對方好回 > 有一點個人味"));
    assert(source.includes("不要為了安全犧牲人的味道"));
    assert(source.includes("推薦開場要在心裡避開禁忌"));
    assert(source.includes("不要把禁忌本身拿出來講"));
    assert(source.includes("不要總是使用「我有認真看完自介」"));
    assert(source.includes("至少要有一個好奇心鉤子"));
    assert(source.includes("不喜歡被問工作、不愛喝酒、喜歡學習嘗試新事物"));
    assert(source.includes("心裡刪掉工作與酒局題庫"));
    assert(source.includes("資訊不足：明說線索不足"));
    assert(
      source.includes("這句示範了什麼框架 + 接住哪個可回線索 + 為什麼容易被回"),
    );
    assert(source.includes("如果內部避開的是「不約」"));
    assert(source.includes("明確標示可見線索不足"));
    assert(source.includes("不假裝洞察"));
    assert(source.includes("只使用明確線索，不要補不存在的人格或共同點"));
    assert(
      source.includes("請先讀取自介文字、明確禁忌、可接線索與照片中的具體場景"),
    );
    assertFalse(source.includes("### Big Five 照片特徵映射"));
    assertFalse(source.includes("穿搭風格 → 性格推斷"));
    assertFalse(source.includes("請生成通用但有趣的開場白"));
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

Deno.test({
  name:
    "SYSTEM_PROMPT demotes old technique library and keeps visible fields coach-like",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("備用技巧工具箱（服從狀態機）"));
    assert(source.includes("不是必套模板"));
    assert(source.includes("先判斷這回合卡點"));
    assert(source.includes("可見輸出不要寫技巧名"));
    assert(source.includes("可見輸出欄位語氣規則"));
    assert(source.includes("不要寫成報表、心理學課、技巧教科書"));
    assert(source.includes("finalRecommendation.reason：一句教練式判斷"));
    assert(
      source.includes(
        "finalRecommendation.psychology：雖然欄位名叫 psychology",
      ),
    );
    assert(source.includes("strategy：只寫這回合的工作判斷"));
    assert(source.includes("healthCheck：只有當目前對話真的有明顯雷點才輸出"));
    assert(source.includes("最多 1 個 issue + 1 個 suggestion"));
    assert(source.includes("不要每次都像老師批改作業"));
    assert(source.includes("互動判斷：對方為什麼比較容易接"));
  },
});

Deno.test({
  name: "opener mode rejects raw JSON/code-fence text before charging quota",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("function parseJsonObjectFromText"));
    assert(source.includes("function normalizeOpenerPayload"));
    assert(source.includes("function sanitizeOpenerText"));
    assert(source.includes('lower.includes(\'"profileanalysis"\')'));
    assert(source.includes('lower.includes(\'"openers"\')'));
    assert(source.includes("opener_response_invalid"));
    assert(source.includes("本次不會扣額度"));
    assertFalse(source.includes("parsed = { openers: { extend: rawText } }"));
  },
});

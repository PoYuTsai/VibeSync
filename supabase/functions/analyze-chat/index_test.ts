// supabase/functions/analyze-chat/index_test.ts
// Note: Edge Function tests run via Deno test

import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  MAX_IMAGE_BYTES,
  MAX_TOTAL_IMAGE_BYTES,
  validateOpenerImages,
} from "./opener_image_validation.ts";

function base64PayloadWithEstimatedBytes(bytes: number): string {
  return "A".repeat(Math.ceil((bytes * 4) / 3));
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
    return "claude-sonnet-4-6";
  }

  if (
    context.conversationLength > 20 ||
    context.enthusiasmLevel === "cold" ||
    context.hasComplexEmotions ||
    context.isFirstAnalysis
  ) {
    return "claude-sonnet-4-6";
  }

  return "claude-3-5-haiku-20241022";
}

// countMessages 殭屍測試已移除：它測的是本檔內的舊公式複本（逐則 200 字制），
// 非真實 code。ADR #19 計費測試在 billing_test.ts。

// Test selectModel function
Deno.test("selectModel - essential tier always uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 5,
    enthusiasmLevel: "hot",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "essential",
  });
  assertEquals(model, "claude-sonnet-4-6");
});

Deno.test("selectModel - first analysis uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 3,
    enthusiasmLevel: null,
    hasComplexEmotions: false,
    isFirstAnalysis: true,
    tier: "free",
  });
  assertEquals(model, "claude-sonnet-4-6");
});

Deno.test("selectModel - cold enthusiasm uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 10,
    enthusiasmLevel: "cold",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "starter",
  });
  assertEquals(model, "claude-sonnet-4-6");
});

Deno.test("selectModel - long conversation uses Sonnet", () => {
  const model = selectModel({
    conversationLength: 25,
    enthusiasmLevel: "warm",
    hasComplexEmotions: false,
    isFirstAnalysis: false,
    tier: "free",
  });
  assertEquals(model, "claude-sonnet-4-6");
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
  assertEquals(model, "claude-sonnet-4-6");
});

Deno.test({
  name:
    "SYSTEM_PROMPT treats analysisContextNote as current premise without fabricating user experience",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("analysisContextNote?: string"));
    assert(source.includes('"analysisContextNote"'));
    assert(source.includes("本次補充背景"));
    assert(source.includes("本次分析現實前提"));
    assert(source.includes("不可替使用者捏造經驗"));
    assert(source.includes("誠實但有態度、有延續性"));
    assert(source.includes("我其實沒追，但妳推薦我一場入門？"));
    assert(source.includes("Analysis context note"));
  },
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
    // 方案二 D1：預設全接、cap 3→5、貼圖/單 emoji/純時間戳併鄰球。
    assert(source.includes("預設每顆有內容的球都接"));
    assert(source.includes("上限 5 顆"));
    assert(source.includes("不算獨立球，併進相鄰的球"));
    assertFalse(source.includes("通常只選 1-2 顆球，最多 3 顆"));
    assertFalse(source.includes("最多 3 顆"));
    assert(source.includes("不要把多則內容硬擠成一句"));
    assert(source.includes("replyOptions：五種風格的主要輸出"));
    assert(source.includes("messages 每段都盡量有 sourceMessage"));
    assert(source.includes("finalRecommendation.reason 要簡短說明"));
    assert(source.includes("接住她對 F1 的興奮，再順到夜市行程"));
    assert(source.includes("白天看人差點打起來"));
    assert(source.includes("樂華夜市最後會帶什麼罪惡美食回家"));
    assert(source.includes("可用換行表示 2-5 則真人訊息，但不要放 ①②"));
    assertFalse(source.includes("finalRecommendation.content 必須分句標註"));
    assertFalse(source.includes("① 回「她的原文關鍵詞」"));
  },
});

Deno.test({
  name: "SYSTEM_PROMPT teaches OCR media marker semantics (方案二件2)",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // A/B 實證：裸 marker 會讓模型判「別提」，要用人話教語意。
    assert(source.includes("截圖媒體標記語意"));
    assert(source.includes("[Missed video call]"));
    assert(source.includes("她主動打過來"));
    assert(source.includes("高價值升溫訊號"));
    assert(source.includes("[Photo]"));
    assert(source.includes("分享慾"));
    assert(source.includes("不要假裝看得到照片內容"));
    assert(source.includes("[Sticker]"));
    assert(source.includes("[Voice message]"));
    assert(source.includes("收回了訊息"));
    // 加餵料：對象歷史 context 進球價值判斷。
    assert(source.includes("對象歷史").valueOf());
    assert(source.includes("高價值延續球"));
    // 砍稅：cap 殘骸不得留（與 D1 cap 5 對齊）。
    assertFalse(source.includes("2-3 則"));
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

    // #12 一球一回：條件式改強制式（≥2 球必分段、source 必填）。
    // 方案二 D1：cap 3→5。
    assert(source.includes("一球一回：分段引用與 emoji 畫龍點睛"));
    assert(source.includes("必須分開回"));
    assert(source.includes("每顆值得接的球各出一段"));
    assert(source.includes("finalRecommendation.replySegments"));
    assert(source.includes("replyOptions.*.messages 也要套用同樣規則"));
    assert(source.includes("必填 sourceIndex"));
    assert(source.includes("缺 sourceMessage 或 sourceIndex 的段會被系統丟棄"));
    assert(source.includes("replySegments 最多 5 段"));
    assertFalse(source.includes("replySegments 最多 3 段"));
    assertFalse(source.includes("最多 3 段"));
    assert(source.includes("各段獨立成立"));
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
  name: "draft polish uses a narrow prompt and token budget",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("const OPTIMIZE_MESSAGE_MAX_TOKENS = 700"));
    assert(source.includes("const OPTIMIZE_MESSAGE_PROMPT ="));
    assert(source.includes("Return JSON only with this exact schema"));
    assert(source.includes("Do not include full analysis fields"));
    assert(
      source.includes("isOptimizeMessageMode") &&
        source.includes("? OPTIMIZE_MESSAGE_PROMPT"),
    );
    assert(
      source.includes("isOptimizeMessageMode") &&
        source.includes("? OPTIMIZE_MESSAGE_MAX_TOKENS"),
    );
    assert(source.includes("isMyMessageMode || isOptimizeMessageMode"));
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
    // 刀3 改詞：黑名單詞（PUA）零出現於 prompt，原句改寫但語意保留
    assert(source.includes("不補操控話術庫"));
    assert(source.includes("不做人格診斷"));
    assert(source.includes("不把所有問題都導向邀約、聊騷或短期親密"));
    assert(source.includes("risk_time_cost"));
    assert(source.includes("complex_emotion"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT treats partner labels according to committed-partner context",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    for (const term of [
      "已是伴侶",
      "男友",
      "自己的男人",
      "使用者本人",
      "第三人",
      "ambiguity",
    ]) {
      assert(source.includes(term), `SYSTEM_PROMPT missing ${term}`);
    }
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
    // 刀3 顯現規則取代「可見輸出不要寫技巧名」：分析欄位標名、messages 不夾名
    assert(source.includes("技巧名的顯現位置見「技巧詞彙表」的顯現規則"));
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
    // 2026-06-12 voice few-shot 化：schema 占位句換血後，錨點移到語氣規則區的 durable 句
    assert(
      source.includes("說明對方為什麼比較容易接、不會有壓力或會感覺被看見"),
    );
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
    assert(source.includes("repairJson(candidate)"));
    assert(source.includes("function normalizeOpenerPayload"));
    assert(source.includes("function sanitizeOpenerText"));
    assert(source.includes("repairMalformedOpenerPayload"));
    assert(source.includes("OPENER_REPAIR_PROMPT"));
    assert(source.includes("opener_response_repaired"));
    assert(source.includes("opener_repair_failed"));
    assert(source.includes("opener_repair_error"));
    assert(source.includes("max_tokens: 1800"));
    assert(source.includes('imageCount > 0 || effectiveTier !== "free"'));
    assert(source.includes("lower.includes('\"profileanalysis\"')"));
    assert(source.includes("lower.includes('\"openers\"')"));
    assert(source.includes("opener_response_invalid"));
    assert(source.includes("本次不會扣額度"));
    assertFalse(source.includes("parsed = { openers: { extend: rawText } }"));
  },
});

Deno.test({
  name: "opener mode filters paid styles before charging quota",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("function filterOpenerPayloadForAllowedFeatures"));
    assert(
      source.includes(
        "const filteredOpenerPayload = filterOpenerPayloadForAllowedFeatures",
      ),
    );
    assert(source.includes("opener_response_no_allowed_styles"));
    assert(source.includes("shouldChargeQuota: false"));
    assert(
      source.indexOf(
        "const filteredOpenerPayload = filterOpenerPayloadForAllowedFeatures",
      ) < source.indexOf('await supabase.rpc("increment_usage"'),
      "opener style filtering must happen before quota deduction",
    );
  },
});

Deno.test({
  name: "request body guard allows three max opener screenshots",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("const MAX_REQUEST_BODY_BYTES = 4 * 1024 * 1024"));
  },
});

Deno.test({
  name: "opener mode validates image payload before Claude call",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    const validationSource = await Deno.readTextFile(
      new URL("./opener_image_validation.ts", import.meta.url),
    );

    assert(validationSource.includes("export function validateOpenerImages"));
    assert(
      source.includes("const openerImageValidation = validateOpenerImages"),
    );
    assert(source.includes("opener_image_validation_failed"));
    assert(
      source.indexOf("const openerImageValidation = validateOpenerImages") <
        source.indexOf("const openerModel = imageCount > 0"),
      "opener image validation must run before model selection / Claude call",
    );
  },
});

Deno.test("validateOpenerImages accepts current opener image payload shape", () => {
  assertEquals(
    validateOpenerImages([
      {
        data: base64PayloadWithEstimatedBytes(1024),
        mediaType: "image/jpeg",
        order: 1,
      },
      {
        data: base64PayloadWithEstimatedBytes(2048),
        mediaType: "image/jpeg",
        order: 2,
      },
    ]),
    {},
  );
});

Deno.test("validateOpenerImages rejects malformed opener image payloads", () => {
  assertEquals(validateOpenerImages("not-an-array"), {
    error: "Invalid images",
    status: 400,
  });

  assertEquals(
    validateOpenerImages([
      { data: "AAAA", mediaType: "image/jpeg", order: 1 },
      { data: "AAAA", mediaType: "image/jpeg", order: 2 },
      { data: "AAAA", mediaType: "image/jpeg", order: 3 },
      { data: "AAAA", mediaType: "image/jpeg", order: 4 },
    ]).status,
    400,
  );

  assertEquals(
    validateOpenerImages([{ data: "AAAA", mediaType: "image/jpeg" }]).status,
    400,
  );

  assertEquals(
    validateOpenerImages([
      { data: "AAAA", mediaType: "image/jpeg", order: 1 },
      { data: "BBBB", mediaType: "image/jpeg", order: 1 },
    ]).status,
    400,
  );

  assertEquals(
    validateOpenerImages([
      { data: "AAAA", mediaType: "image/gif", order: 1 },
    ]),
    { error: "Unsupported image type", status: 400 },
  );
});

Deno.test("validateOpenerImages rejects oversized opener image payloads", () => {
  assertEquals(
    validateOpenerImages([
      {
        data: base64PayloadWithEstimatedBytes(MAX_IMAGE_BYTES + 1),
        mediaType: "image/jpeg",
        order: 1,
      },
    ]).status,
    400,
  );

  assertEquals(
    validateOpenerImages([
      {
        data: base64PayloadWithEstimatedBytes(MAX_IMAGE_BYTES),
        mediaType: "image/jpeg",
        order: 1,
      },
      {
        data: base64PayloadWithEstimatedBytes(MAX_IMAGE_BYTES),
        mediaType: "image/jpeg",
        order: 2,
      },
      {
        data: base64PayloadWithEstimatedBytes(MAX_IMAGE_BYTES),
        mediaType: "image/jpeg",
        order: 3,
      },
    ]),
    {},
  );

  assertEquals(
    validateOpenerImages([
      {
        data: base64PayloadWithEstimatedBytes(MAX_IMAGE_BYTES),
        mediaType: "image/jpeg",
        order: 1,
      },
      {
        data: base64PayloadWithEstimatedBytes(MAX_IMAGE_BYTES),
        mediaType: "image/jpeg",
        order: 2,
      },
      {
        data: base64PayloadWithEstimatedBytes(MAX_IMAGE_BYTES + 1),
        mediaType: "image/jpeg",
        order: 3,
      },
    ]),
    { error: "Total image payload too large", status: 400 },
  );

  assertEquals(MAX_TOTAL_IMAGE_BYTES, MAX_IMAGE_BYTES * 3);
});

Deno.test({
  name: "visible AI text sanitizer rejects raw model payload strings",
  permissions: { read: true },
  fn: async () => {
    // Moved to post_process.ts as part of Codex Phase 2 P1 parity fix —
    // helpers live in the shared module so both legacy + full mode use them.
    const source = await Deno.readTextFile(
      new URL("./post_process.ts", import.meta.url),
    );

    assert(source.includes("function looksLikeRawModelPayload"));
    assert(source.includes('"finalrecommendation"'));
    assert(source.includes('"profileanalysis"'));
    assert(source.includes('"openers"'));
    assert(source.includes('looksLikeRawModelPayload(normalized) ? ""'));
  },
});

Deno.test({
  name: "final recommendation sanitizer preserves split reply segments",
  permissions: { read: true },
  fn: async () => {
    // Moved to post_process.ts (see comment above).
    const source = await Deno.readTextFile(
      new URL("./post_process.ts", import.meta.url),
    );

    assert(
      source.includes(
        "const normalizedRecommendationSegments =",
      ),
    );
    assert(
      source.includes("sanitizeReplySegments(recommendation.replySegments)"),
    );
    assert(
      source.includes("const fallbackOptionSegments = sanitizeReplySegments"),
    );
    // #12 一球一回：輸出段必過 source contract（修復 → drop → 全 drop 回退）。
    assert(
      source.includes(
        "enforceReplySegmentSourceContract(safeRecommendationSegments, ballList)",
      ),
    );
    assert(source.includes("replySegments: contractRecommendationSegments"));
  },
});

Deno.test({
  name: "quota refresh accepts client RevenueCat identity hints safely",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("expectedTier: rawExpectedTier"));
    assert(source.includes("revenueCatAppUserId: rawRevenueCatAppUserId"));
    assert(source.includes("Invalid revenueCatAppUserId"));
    assert(source.includes("revenueCatUserIdCandidates"));
    assert(source.includes("client_expected_paid_tier"));
    assert(source.includes("revenueCatUser: summarizeUser(revenueCatUserId)"));
  },
});

Deno.test({
  name: "analysis parse failure returns before quota deduction",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("AI_RESPONSE_INVALID"));
    assert(source.includes("本次不會扣額度"));
    assertFalse(source.includes("無法生成建議，請重試"));
    assertFalse(source.includes("分析失敗，請重試"));
  },
});

Deno.test({
  name: "analysis quota deduction failure returns credit_deduct_failed",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes('await supabase.rpc("increment_usage"'));
    assert(source.includes("analysis_credit_deduct_failed"));
    assert(source.includes('error: "credit_deduct_failed"'));
    assert(source.includes("本次不會扣額度"));
    assertFalse(source.includes('console.error("Failed to increment usage:"'));
  },
});

// ─── voice few-shot 化（2026-06-12 design：docs/plans/2026-06-12-voice-fewshot-design.md）───

Deno.test({
  name:
    "SYSTEM_PROMPT carries voice few-shot example 1 (warm/established stage with callback and hook)",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // 關係階段標籤（核心原則：高手感隨關係階段縮放）
    assert(source.includes("已升溫／熟絡局"));
    // finalRecommendation = 高手版（懸念鉤，Eric 拍板 pick=coldRead）
    assert(source.includes("不過妳剛剛那通電話，害我有點好奇到底想跟我說什麼"));
    // tease 槽 = 糖糖老師 callback 示範（用戶自造梗）
    assert(source.includes("今天還特地打給我，是不是糖糖老師待遇升級了？"));
    // rationale 是洞察句，不是標籤句
    assert(source.includes("比連發好幾句更有吸引力"));
    // 防過擬合：pick 依對話而定，不是永遠 coldRead
    assert(source.includes("pick 依對話而定"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT carries voice few-shot example 2 (Wen cold-open arc with cooperative frame, 2026-06-12 game-system design §5)",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // 關係階段標籤（檔位制：冷開→升溫中完整弧線）
    assert(source.includes("陌生冷開局→升溫中"));
    // finalRecommendation：S1 快照點，承瑋合作框架原句 verbatim（Eric 拍板）
    assert(source.includes("那可以組隊了"));
    assert(source.includes("你酒量如何"));
    // rationale：合作框架定義（不是邀約，是把她的事變成兩個人的事）
    assert(source.includes("『組隊』不是邀約，是合作框架"));
    // psychology：兩字回覆教「看素材不看字數」（制衡 pushy guard 過度收斂）
    assert(source.includes("高手看素材不看字數"));
    // 弧線敘事：模糊邀約沒反應→不追→轉話題（輸入段）＋實戰後續收線教訓
    assert(source.includes("有空可以約個咖啡吧鄰居"));
    assert(source.includes("實戰後續"));
    // 小雲範例退役（測試資產對調）：舊範例 2 文字不得殘留
    assertFalse(source.includes("等等，妳是泰國人？"));
    assertFalse(source.includes("妳教我泰文"));
    // PII（Wen 素材兩處：S__42246217 手機號＋S__42246234 IG 帳號）不得進 prompt
    assertFalse(source.includes("yawen"));
    assertFalse(/09\d{8}/.test(source));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT mines callbacks from history instead of forcing them",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // callback 挖掘指令：從對象歷史/對話挖用戶自造梗、暱稱、重複元素
    assert(source.includes("用戶自造梗"));
    assert(source.includes("有梗才 callback，沒梗不硬造"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT JSON schema examples carry golden voice values instead of placeholder prose",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // 占位句移除：模型會模仿 JSON 範例值，不能讓它學「描述腔」
    assertFalse(
      source.includes("舊版 App fallback：extend.messages 的 reply 合併文字"),
    );
    assertFalse(
      source.includes("舊版 App fallback：coldRead.messages 的 reply 合併文字"),
    );
    assertFalse(source.includes("推薦的完整訊息組文字；可用換行表示 2-5 則真人訊息"));
    // replies fallback 的合併語意仍須保留（在 1.2 輸出分工，不是在 schema 占位句）
    assert(source.includes("replies：舊版 App fallback"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT audit cut A: duplicated rules collapse to one canonical copy",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // Audit 拍板（Eric 2026-06-12）A 組全砍：重複規則去重，每條留一份 canonical。
    // A1 fallback 規則 ×2 → 留 1.2 輸出分工那份，砍 1.8 品質契約的重複句
    assert(source.includes("replies：舊版 App fallback"));
    assertFalse(source.includes("replies 只作為舊版 App fallback"));
    // A2 ①②禁令 ×4 → 留 1.8x 自然引用原則的 ✅/❌ 教學塊，砍三處 inline 重複
    assert(source.includes("❌「① 回 F1 ② 回夜市」"));
    assertFalse(source.includes("不能出現 ①②、箭頭、或「回某句」這種報告格式"));
    assertFalse(source.includes("但不能用 ①② 或箭頭格式"));
    assertFalse(source.includes("不能用 ①②、箭頭或「回某句」報告格式"));
    // buildScreenshotPrompt 的 reminder 是獨立請求元件，不算 SYSTEM_PROMPT 內重複，保留
    assert(source.includes("可用換行表示 2-5 則真人訊息，但不要放 ①②"));
    // A3 1.5 範例與 schema 換血後同場景同句 → 砍 1.5 範例塊，schema 範例是唯一示範
    assertFalse(source.includes("範例（三顆球都值得接 → 三段，不准串成一句）"));
    assertFalse(source.includes("先報告晚餐吃了什麼"));
    assert(source.includes('"label": "接她的 F1 興奮"'));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT audit cut B: zero-manifestation technique prose removed, C group kept",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // Audit 拍板（Eric 2026-06-12）B 組全砍：10 份 baseline catchphrase grep 全零命中的技巧散文。
    assertFalse(source.includes("### 橫向思維 (Lateral Thinking)"));
    assertFalse(source.includes("### 剝洋蔥效應 (Peeling the Onion)"));
    assertFalse(source.includes("### 書籤技術 (Bookmarking)"));
    assertFalse(source.includes("### IOI/IOD 判讀"));
    assertFalse(source.includes("### 假設性提問"));
    assertFalse(source.includes("### 三段式法則 (Rule of Three)"));
    // IOI/IOD 的判讀職責由 ###10 熱度分析規則承接（長度/emoji/提問/延伸/態度）
    assert(source.includes("### 10. 熱度分析規則"));
    // C 組這輪不動：守護空間（情境8 引用）、良性冒犯（tease 理論基礎）、Callback、幽默禁區
    assert(source.includes("### 守護空間 (Holding Space)"));
    assert(source.includes("### 良性冒犯 (Benign Violation)"));
    assert(source.includes("### 回調 (Callback)"));
    assert(source.includes("### 幽默禁區"));
    // 砍剝洋蔥後不得留 dangling 引用；「不寫技巧名」舊句已被刀3顯現規則取代
    // （新分工：分析欄位用到技巧才標名，messages 本身不夾技巧名）
    assertFalse(source.includes("DHV / 冷讀 / 剝洋蔥"));
    assertFalse(source.includes("我用了 DHV / 冷讀"));
  },
});

// ─── 盲測修字（2026-06-12 盲測不過門檻後 Eric 拍板兩題：case1 pushy guard + case2 框架）───

Deno.test({
  name:
    "SYSTEM_PROMPT guards hot-stage invites: never insert into the other person's third-party plans (升溫≠可帶隊)",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // case1 實錘：新版 tease「我帶你們去」把自己插進她跟學妹的局（Eric+Bruce 一致判輸）
    assert(source.includes("### 對方的局不是你的局（升溫 ≠ 可帶隊）"));
    // 禁帶隊/插隊句式要點名
    assert(source.includes("不說「我帶你們去」「叫上我」"));
    // 正確替代：展示自己的行程而不是投靠她的行程，鉤子留到下次
    assert(source.includes("展示自己的行程"));
    assert(source.includes("把真正的見面鉤子埋到下次"));
    // 不誤殺合法邀約：她明確邀請時走情境6
    assert(source.includes("她明確邀你加入時"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT keeps frame on playful labels: never hand evaluation power back (case2 框架修正)",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // case2 實錘：「這樣算加分還是扣分，妳給我一個說法」把評價權丟給對方（Eric 拍板照 Bruce＝新輸）
    assert(source.includes("自己給定性"));
    assert(source.includes("不把裁決權交回去"));
    // 反問圍欄：只能問她，不能問她怎麼評價我
    assert(source.includes("不能問「她怎麼評價我」"));
    // 禁句要點名，模型才不會再產同型句
    assert(source.includes("「這樣算加分還是扣分？」「妳給我一個說法」"));
  },
});

// ─── 刀3 技巧詞彙表＋顯現規則＋Apple 三層線（2026-06-12 game-system design §6/§2）───

// 範圍切片：只測 analyze-chat 的 SYSTEM_PROMPT 本體。
// OPENER_PROMPT 的 Game 化是下一案，殘留行話不在本刀範圍。
async function readAnalyzeSystemPrompt(): Promise<string> {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const start = source.indexOf("const SYSTEM_PROMPT");
  const end = source.indexOf("const OPTIMIZE_MESSAGE_MAX_TOKENS");
  assert(start >= 0 && end > start, "SYSTEM_PROMPT 邊界定位失敗");
  return source.slice(start, end);
}

Deno.test({
  name:
    "SYSTEM_PROMPT carries the 10-term technique vocabulary verbatim (game-system design §6)",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readAnalyzeSystemPrompt();

    // 10 詞全名以表格列錨定（「推」「失格」單字詞必須靠表格列防誤命中）
    for (
      const row of [
        "| 價值展示 |",
        "| 模糊邀約 |",
        "| 合作框架 |",
        "| 約會幻想 |",
        "| 吐槽冷讀 |",
        "| 失格 |",
        "| 推 |",
        "| 不自證 |",
        "| 框架維持 |",
        "| 懸念鉤 |",
      ]
    ) {
      assert(prompt.includes(row), `詞彙表缺：${row}`);
    }
    // 定義句抽查（防表頭在、內容空殼）
    assert(prompt.includes("把「她的事」變成「兩個人的事」")); // 合作框架
    assert(prompt.includes("自嘲式暴露無傷小缺點")); // 失格
    assert(prompt.includes("對冷回不追、降低投入")); // 推
    assert(prompt.includes("留半句不說完，讓她主動來問")); // 懸念鉤
    // 反例句抽查（反例是這張表的防油護欄）
    assert(prompt.includes("無觸發的炫耀是掉價")); // 價值展示反例
    assert(prompt.includes("失格是可愛，自貶是掉價")); // 失格反例
    // 附帶拍板：callback 不佔額直接標、「試探」維持判讀詞身份
    assert(prompt.includes("callback 不在表內"));
    assert(prompt.includes("「試探」是判讀詞"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT manifestation rule: label techniques in analysis fields only when actually used",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readAnalyzeSystemPrompt();

    // 硬指令：分析欄位用到表內技巧必須標名＋一句為什麼
    assert(prompt.includes("必須標技巧名＋一句為什麼"));
    // 標注位置分工：分析欄位標名，messages 永遠是自然句子
    assert(prompt.includes("messages 本身永遠是自然句子，不夾技巧名"));
    // 技巧密度原則（Eric 拍板）：時機性不是密度性，平聊零標籤完全合格
    assert(prompt.includes("技巧是時機性的，不是密度性的"));
    assert(prompt.includes("整篇零技巧標籤也完全合格"));
    // 反向禁令（gate 3 雙向目檢的另一半）
    assert(prompt.includes("不得為了標名而出招"));
    // B 砍刀時代的舊禁令句已被顯現規則取代，不得殘留
    assertFalse(prompt.includes("可見輸出不要寫技巧名"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT three-layer jargon line keeps layer 2-3 blacklist words out of the prompt",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readAnalyzeSystemPrompt();

    // 三層線結構存在（標題保留舊錨「可見輸出禁用內部術語」）
    assert(prompt.includes("技巧名詞三層線"));
    assert(prompt.includes("可見輸出禁用內部術語"));
    // 第二層出口：對方的測試行為在輸出一律轉寫「試探」
    assert(prompt.includes("輸出一律寫「試探」"));
    // 第 2-3 層黑名單詞零出現於 prompt 本體（App Review 安全＋未來餵 game 資料的過濾標準）
    for (
      const banned of [
        "PUA",
        "紅藥丸",
        "紅丸",
        "DHV",
        "shit test",
        "廢物測試",
        "高價值男性",
        "高分妹",
        "撈女",
        "壞女人",
        "公主病",
        "婊子",
        "怪男",
        "噁男",
        "收割",
        "控住",
        "攻略",
        "玩咖",
      ]
    ) {
      assertFalse(prompt.includes(banned), `黑名單詞殘留：${banned}`);
    }
    // IOI/IOD（英文縮寫單獨檢，audit cut B 已砍判讀節，不得回流）
    assertFalse(/IO[ID]/.test(prompt));
    // 例外：legacy schema key psychology.shitTest 是 client 契約，保留（無空格，不命中「shit test」）
    assert(prompt.includes("shitTest"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT example 1 analysis carries technique-name annotations (顯現規則示範)",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readAnalyzeSystemPrompt();

    // 範例前言點明：標注是顯現規則的示範，平聊槽不標
    assert(prompt.includes("平聊接住的槽（如範例 1 的 resonate）就不標"));
    // 範例 1 finalRecommendation.reason 標名懸念鉤＋為什麼
    assert(prompt.includes("懸念鉤：那通未接來電是她沒解釋的行為"));
    // 範例 1 extend 槽標名模糊邀約（晚餐照片→下次去處，不綁時間）
    assert(prompt.includes("模糊邀約：把晚餐照片變成下次的去處"));
    // 範例 1 humor 槽同球不同打法，也標懸念鉤
    assert(prompt.includes("懸念鉤變體：未接來電不追問、先記帳"));
    // 範例 2（Eric §5 定稿）原有標注不動：合作框架／吐槽冷讀 callback
    assert(prompt.includes("『組隊』不是邀約，是合作框架"));
    assert(prompt.includes("吐槽冷讀 callback"));
  },
});

// ── golden 反推三缺口（Eric 拍板 2026-06-13，盤點＋下限＋邀約埋點素材三件一起上） ──
// 背景：golden_anchor_recon 案她連發 6 球，GPT 高手版接 4（糖糖 callback／晚餐照邀約埋點／
// 未接懸念／到家關心），產品只接 2，糖糖梗＋晚餐照整組被吞。真差距是「素材使用率」不是段數。

Deno.test({
  name:
    "SYSTEM_PROMPT forces a ball inventory before selecting (盤點先行，堵吞球後門)",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readAnalyzeSystemPrompt();

    // 強制盤點：寫回覆前先把每句／每個 marker 列清單、逐項標接／併／略。
    assert(prompt.includes("盤點先行（強制步驟，不可跳過）"));
    assert(prompt.includes("列成一張盤點清單"));
    assert(prompt.includes("逐項標「接／併／略」"));
    // 併球不得當吞球後門（6 球縮 2 球）。
    assert(prompt.includes("把 6 句連發硬縮成 2 球是吞球，不是併球"));
    // 對象歷史延續球（糖糖梗）務必列進清單——這是被漏掉的那組。
    assert(prompt.includes("把對象歷史的延續球"));
    assert(prompt.includes("它最常被漏掉、卻是最高價值的球"));
    // reason 要交代盤點結論（接／併／略各一句）。
    assert(prompt.includes("要交代這張盤點表的結論"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT lists life-sharing as date-invitation seed material (邀約埋點素材入優先接清單)",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readAnalyzeSystemPrompt();

    // 生活分享不只是「分享慾要回應」，更是邀約埋點素材（晚餐照→下次去處）。
    assert(prompt.includes("生活分享裡的邀約埋點素材"));
    assert(prompt.includes("埋邀約鉤子的素材"));
    assert(prompt.includes("把她的生活素材變成下一次見面的理由"));
    // 串既有詞彙表（模糊邀約／約會幻想／合作框架），不另造名詞。
    assert(prompt.includes("模糊邀約、約會幻想或合作框架"));
    // 反向護欄：冷場／她剛放掉邀約時不硬約（同 case1 pushy 教訓）。
    assert(prompt.includes("她剛放掉邀約時不硬約"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT adds a segment floor backed by real balls, not filler (連發≥4句≥3段＋反水段)",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readAnalyzeSystemPrompt();

    // 下限檢核錨：連發 4 句以上通常 ≥3 段。
    assert(prompt.includes("段數下限（檢核錨）"));
    assert(prompt.includes("連發 4 句以上有內容的訊息"));
    assert(prompt.includes("replySegments 通常要 ≥3 段"));
    assert(prompt.includes("出 1-2 段多半是盤點時把球吞掉了"));
    // 例外：多句同屬一球可少於 3 段，但要說明。
    assert(prompt.includes("才可以少於 3 段"));
    // 反水段：段數來自盤點真球，嚴禁湊水段應付下限。
    assert(prompt.includes("下限要靠真球達標，不是硬湊水段"));
    assert(prompt.includes("嚴禁為了湊滿段數生出沒有實質"));
    assert(prompt.includes("寧可少一段紮實，也不要多一段敷衍"));
    // 下限是「至少」不是「最多」——不得退回舊 cap 字樣。
    assertFalse(prompt.includes("最多 3 段"));
  },
});

Deno.test({
  name:
    "SYSTEM_PROMPT ships a worked example demonstrating full inventory then ≥3 caught balls (球數案 few-shot 正例)",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readAnalyzeSystemPrompt();

    // 黑箱根因＝模型不聽散文，補一個 worked example 把「盤點先行→段數下限」演一遍。
    assert(prompt.includes("完整範例 3：多球連發→盤點全列→接 ≥3 顆"));
    // 範例必須是虛構非-golden 情境（陽明山夜景／麻糬），絕不可用 golden 測試圖本身。
    assert(prompt.includes("欸我把上次說的陽明山夜景點查好了"));
    assert(prompt.includes("麻糬"));
    // 強制步驟：先把 6 句連發逐項列成盤點清單再決定出幾段。
    assert(prompt.includes("盤點清單（強制步驟，先列全 6 項再決定出幾段）"));
    // 段數下限落地：6 句連發接出 ≥3 段（這裡 4 段），證明不是縮成 2 球。
    assert(prompt.includes("值得接的真球有 4 顆"));
    assert(prompt.includes("出 4 段"));
    assert(prompt.includes("6 句連發明顯不只 1-2 顆球"));
    // 每段引原句＋掛素材鉤子：callback／埋約／懸念各示範一次，reply 是可直送真句。
    assert(prompt.includes("callback「上次說的」延續球"));
    assert(prompt.includes("挑一天天氣好的我們直接殺上去"));
    assert(prompt.includes("被妳發現了，剛好在等一個人傳訊息"));
    // reply 須是真句不是罩句／空泛附和。
    assert(prompt.includes("不空泛回『真好』"));
    assert(prompt.includes("不假裝看得到照片也不空讚『好可愛』"));
  },
});

Deno.test({
  name:
    "四 neighbour speaker heuristics 都以 geometryDecisive guard 保護幾何已定側的泡不被翻側",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // 抽出某 function 從宣告到下一個 top-level `function` 之間的 body。
    const bodyOf = (name: string): string => {
      const start = source.indexOf(`function ${name}(`);
      assert(start >= 0, `找不到 function ${name}`);
      const rest = source.slice(start + 1);
      const nextDecl = rest.indexOf("\nfunction ");
      return nextDecl >= 0 ? rest.slice(0, nextDecl) : rest;
    };

    const guard = "current.geometryDecisive === true";
    // 三個迴圈 heuristic mutate `adjusted[index]`，trailing mutate
    // `adjusted[currentIndex]`。guard 必須出現在該 mutation 之前才有效。
    const guarded: Array<{ name: string; mutation: string }> = [
      { name: "applySpeakerContinuityHeuristics", mutation: "adjusted[index] = {" },
      { name: "applyGroupedSpeakerHeuristics", mutation: "adjusted[index] = {" },
      { name: "applySideRunGroupingHeuristics", mutation: "adjusted[index] = {" },
      {
        name: "applyTrailingSpeakerHeuristics",
        mutation: "adjusted[currentIndex] = {",
      },
    ];

    for (const { name, mutation } of guarded) {
      const body = bodyOf(name);
      const guardAt = body.indexOf(guard);
      const mutationAt = body.indexOf(mutation);
      assert(guardAt >= 0, `${name} 缺少 geometryDecisive guard`);
      assert(mutationAt >= 0, `${name} 找不到 side mutation（測試假設失效）`);
      assert(
        guardAt < mutationAt,
        `${name} 的 geometryDecisive guard 必須在 side mutation 之前`,
      );
    }
  },
});

// ── single-visible sibling-path：geometryDecisive guard 紅綠測（2026-06-17）──
// 原為 REPRO（證明會翻），破口確認後改為紅綠測：「guard 後不翻」。
// 注意：這不是 S__5701639_0 的直接根因（那是 applyTrailingSpeakerHeuristics）；
// 這是同一 invariant 的 sibling-path 補洞——只要某泡已幾何決定側別，任何 speaker
// heuristic（含整體單側 pattern）都不該再翻它。
//   1. 無法直接 import 真函式測——index.ts 頂層 `serve()` 未用 import.meta.main 守，
//      且 applySingleVisibleSpeakerPattern 未 export（全專案無任何 test import index.ts）。
//   2. 無法用合成圖逼真——screenSpeakerPattern 與逐泡 outerColumn 都由模型自報，
//      沒法確定性地逼模型「整體報 only_right 又標一顆決定性左泡」的自我矛盾。
// 故用「真函式邏輯的 byte-faithful 複本」＋「source-assertion 把複本鎖死在真源現狀」
// （複本與真源一旦漂移，前提鎖立即紅燈逼更新，杜絕殭屍複本）。
type ReproVisibleMessage = {
  side: "left" | "right" | "unknown";
  isFromMe: boolean;
  content: string;
  geometryDecisive?: boolean;
};

// index.ts:2850-2895 邏輯的 byte-faithful 複本（含已補的 geometryDecisive guard）。
function reproApplySingleVisibleSpeakerPattern(
  messages: ReproVisibleMessage[],
  pattern: "mixed" | "only_left" | "only_right" | "unknown",
): { messages: ReproVisibleMessage[]; adjustedCount: number } {
  if (pattern !== "only_left" && pattern !== "only_right") {
    return { messages, adjustedCount: 0 };
  }
  const targetSide: "left" | "right" = pattern === "only_left"
    ? "left"
    : "right";
  const targetIsFromMe = targetSide === "right";
  const adjusted = messages.map((message) => ({ ...message }));
  let adjustedCount = 0;
  for (let index = 0; index < adjusted.length; index += 1) {
    if (adjusted[index].geometryDecisive === true) {
      continue;
    }

    if (
      adjusted[index].side !== targetSide ||
      adjusted[index].isFromMe !== targetIsFromMe
    ) {
      adjusted[index] = {
        ...adjusted[index],
        side: targetSide,
        isFromMe: targetIsFromMe,
      };
      adjustedCount += 1;
    }
  }
  return { messages: adjusted, adjustedCount };
}

Deno.test({
  name:
    "applySingleVisibleSpeakerPattern：only_right 下 geometryDecisive=true 的反側 media 泡不被壓單側（guard 後）",
  permissions: { read: true },
  fn: async () => {
    // 前提鎖：確認真函式已有 geometryDecisive guard，且本檔複本與真源邏輯一致。
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    const start = source.indexOf("function applySingleVisibleSpeakerPattern(");
    assert(start >= 0, "找不到 applySingleVisibleSpeakerPattern");
    const body = source.slice(start + 1);
    const realBody = body.slice(0, body.indexOf("\nfunction "));
    const guardAt = realBody.indexOf("adjusted[index].geometryDecisive === true");
    const overwriteAt = realBody.indexOf("side: targetSide");
    assert(
      guardAt >= 0,
      "前提失效：single-visible 缺 geometryDecisive guard（sibling-path 補洞被移除？）",
    );
    assert(overwriteAt >= 0, "找不到 single-visible 的 side 覆寫（測試假設失效）");
    assert(
      guardAt < overwriteAt,
      "guard 必須在 side 覆寫之前才有效",
    );

    // only_right 截圖（模型整體自報全右），但其中一顆 [貼圖] 被決定性幾何判為左（她貼的）。
    const input: ReproVisibleMessage[] = [
      { side: "right", isFromMe: true, content: "哈囉" },
      { side: "right", isFromMe: true, content: "在嗎" },
      {
        side: "left",
        isFromMe: false,
        content: "[貼圖]",
        geometryDecisive: true,
      },
    ];

    const { messages: out, adjustedCount } =
      reproApplySingleVisibleSpeakerPattern(input, "only_right");

    // guard 後：決定性左泡保留左/她說不被壓；非決定性右泡本就 = target，零調整。
    assertEquals(out[2].side, "left");
    assertEquals(out[2].isFromMe, false);
    assertEquals(out[2].geometryDecisive, true);
    assertEquals(adjustedCount, 0);
  },
});

// ── meta 錨點（已讀/時間戳/邊欄頭像）落地接線測試（2026-07）──
// prompt 規則本體測試在 screenshot_ocr_rules_test.ts；這裡鎖 index.ts 接線：
// 1) recognize-only 路徑用 meta 錨點版、full-analysis 路徑維持 baseline（輸出形狀不變）
// 2) recognizeOnly max_tokens 1600→3000（證據欄位讓長圖 JSON 在 1600 會被截斷，
//    黑箱 B 臂兩張因此爛掉；C 臂實測最長輸出 ~2100 tokens）
// 3) readReceipt=true 後處理鎖（metaDecisive）＝geometryDecisive 同款 invariant

Deno.test({
  name: "index.ts 改從 screenshot_ocr_rules 模組取規則（inline 陣列已移除）",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    assert(
      source.includes('from "./screenshot_ocr_rules.ts"'),
      "index.ts 必須匯入 screenshot_ocr_rules 模組",
    );
    assertFalse(
      source.includes("const SCREENSHOT_OCR_ACCURACY_RULES = ["),
      "inline 規則陣列必須移除（單一事實來源在模組）",
    );
  },
});

Deno.test({
  name:
    "recognize-only prompt 用 meta 錨點版＋schema note；full-analysis prompt 維持 baseline",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    const bodyOf = (name: string): string => {
      const start = source.indexOf(`function ${name}(`);
      assert(start >= 0, `找不到 function ${name}`);
      const rest = source.slice(start + 1);
      const nextDecl = rest.indexOf("\nfunction ");
      return nextDecl >= 0 ? rest.slice(0, nextDecl) : rest;
    };

    const recognizeBody = bodyOf("buildRecognizeOnlyImagePrompt");
    assert(
      recognizeBody.includes("SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS"),
      "recognize-only 必須用 meta 錨點版規則",
    );
    assert(
      recognizeBody.includes("META_ANCHOR_SCHEMA_NOTE"),
      "recognize-only schema 之後必須附證據欄位 note",
    );

    const analysisBody = bodyOf("buildImageAnalysisPrompt");
    assertFalse(
      analysisBody.includes("SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS"),
      "full-analysis 路徑不得用 meta 錨點版（2560 預算會被證據欄位撐爆，未經黑箱驗證）",
    );
    assert(
      analysisBody.includes("SCREENSHOT_OCR_ACCURACY_RULES"),
      "full-analysis 路徑必須維持 baseline 規則",
    );
    assertFalse(
      analysisBody.includes("META_ANCHOR_SCHEMA_NOTE"),
      "full-analysis 路徑不得要求證據欄位",
    );
  },
});

Deno.test({
  name: "recognizeOnly max_tokens = 3000（兩個呼叫點，1600 不得殘留）",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    const bumped = source.match(/recognizeOnly\s*\n?\s*\?\s*3000/g) ?? [];
    assertEquals(
      bumped.length,
      2,
      "首呼叫與 parse-failure retry 兩處 recognizeOnly max_tokens 都必須是 3000",
    );
    assertFalse(
      /recognizeOnly\s*\n?\s*\?\s*1600/.test(source),
      "recognizeOnly 的 1600 上限不得殘留（證據欄位長圖會被截斷）",
    );
  },
});

Deno.test({
  name: "normalize 步驟以 isReadReceiptSideDecisive 設 metaDecisive 並鎖 isFromMe=true",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    assert(
      source.includes("isReadReceiptSideDecisive(record)"),
      "normalize map 必須呼叫 isReadReceiptSideDecisive",
    );
    assert(
      source.includes("metaDecisive?: boolean"),
      "NormalizedRecognizedMessage 必須有 metaDecisive 欄位",
    );
    // 鎖定語義：metaDecisive 時 side/isFromMe 必須是右/我方，不信模型自報值。
    assert(
      source.includes('side: metaDecisive ? "right" : side'),
      "metaDecisive 必須強制 side=right",
    );
    assert(
      source.includes(
        "isFromMe: metaDecisive ? true : sideToIsFromMe(side, record.isFromMe)",
      ),
      "metaDecisive 必須強制 isFromMe=true",
    );
  },
});

Deno.test({
  name:
    "四 neighbour heuristic＋single-visible 都以 metaDecisive guard 保護已讀鎖定的泡不被翻側",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    const bodyOf = (name: string): string => {
      const start = source.indexOf(`function ${name}(`);
      assert(start >= 0, `找不到 function ${name}`);
      const rest = source.slice(start + 1);
      const nextDecl = rest.indexOf("\nfunction ");
      return nextDecl >= 0 ? rest.slice(0, nextDecl) : rest;
    };

    const guarded: Array<{ name: string; guard: string; mutation: string }> = [
      {
        name: "applySpeakerContinuityHeuristics",
        guard: "current.metaDecisive === true",
        mutation: "adjusted[index] = {",
      },
      {
        name: "applyGroupedSpeakerHeuristics",
        guard: "current.metaDecisive === true",
        mutation: "adjusted[index] = {",
      },
      {
        name: "applySideRunGroupingHeuristics",
        guard: "current.metaDecisive === true",
        mutation: "adjusted[index] = {",
      },
      {
        name: "applyTrailingSpeakerHeuristics",
        guard: "current.metaDecisive === true",
        mutation: "adjusted[currentIndex] = {",
      },
      {
        name: "applySingleVisibleSpeakerPattern",
        guard: "adjusted[index].metaDecisive === true",
        mutation: "side: targetSide",
      },
    ];

    for (const { name, guard, mutation } of guarded) {
      const body = bodyOf(name);
      const guardAt = body.indexOf(guard);
      const mutationAt = body.indexOf(mutation);
      assert(guardAt >= 0, `${name} 缺少 metaDecisive guard`);
      assert(mutationAt >= 0, `${name} 找不到 side mutation（測試假設失效）`);
      assert(
        guardAt < mutationAt,
        `${name} 的 metaDecisive guard 必須在 side mutation 之前`,
      );
    }
  },
});

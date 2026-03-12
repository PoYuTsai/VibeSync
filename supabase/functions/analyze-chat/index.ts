// supabase/functions/analyze-chat/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { SAFETY_RULES, checkAiOutput, checkInput } from "./guardrails.ts";
import { callClaudeWithFallback, AiServiceError } from "./fallback.ts";
import { logAiCall, extractTokenUsage } from "./logger.ts";

const CLAUDE_API_KEY = Deno.env.get("CLAUDE_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// 訊息制額度
const TIER_MONTHLY_LIMITS: Record<string, number> = {
  free: 30,
  starter: 300,
  essential: 1000,
};

const TIER_DAILY_LIMITS: Record<string, number> = {
  free: 15,
  starter: 50,
  essential: 150,
};

// 功能權限
const TIER_FEATURES: Record<string, string[]> = {
  free: ["extend"], // 只有延展回覆
  starter: [
    "extend",
    "resonate",
    "tease",
    "humor",
    "coldRead",
    "needy_warning",
    "topic_depth",
  ],
  essential: [
    "extend",
    "resonate",
    "tease",
    "humor",
    "coldRead",
    "needy_warning",
    "topic_depth",
    "health_check",
  ],
};

// 截圖上傳相關類型
interface ImageData {
  data: string; // base64 encoded
  mediaType: string; // e.g., "image/jpeg"
  order: number; // 1, 2, 3...
}

// 建構 Vision API 內容格式
function buildVisionContent(
  textContent: string,
  images: ImageData[]
): Array<{ type: string; text?: string; source?: { type: string; media_type: string; data: string } }> {
  const content: Array<{ type: string; text?: string; source?: { type: string; media_type: string; data: string } }> = [];

  // 先加入圖片（按 order 排序）
  const sortedImages = [...images].sort((a, b) => a.order - b.order);
  for (const img of sortedImages) {
    content.push({
      type: "image",
      source: {
        type: "base64",
        media_type: img.mediaType,
        data: img.data,
      },
    });
  }

  // 最後加入文字內容
  content.push({
    type: "text",
    text: textContent,
  });

  return content;
}

const SYSTEM_PROMPT = `你是一位專業的社交溝通教練，幫助用戶提升對話技巧，最終目標是幫助用戶成功邀約。

## AI 核心人設

你的建議必須體現以下心態：

### 1. 富裕心態 (Abundance Mindset)
- 表現得像是一個生活豐富、不缺社交對象的高價值男性
- 不害怕失去話題，不患得患失
- 不急於表現或討好對方

### 2. 情緒穩定 (Emotional Stability)
- 永遠保持從容，面對測試、抱怨或冷淡，絕不急躁
- 不展現防禦心、不生氣、不長篇大論解釋
- 允許對方有自己的情緒和想像空間

### 3. 邊界感清晰 (Clear Boundaries)
- 「對方的情緒是她自己的課題」
- 不主動干預、不說教、不急於解決對方的心理問題
- 不因對方不回訊息就覺得自己說錯話

### 4. 真實且謙遜 (Grounded & Humble)
- 展現高價值的同時，語氣保持低調與自我解嘲
- 不炫耀、不裝逼，也不刻意裝窮
- 高價值展示後要「接地氣」

### 5. 自嘲 vs 自貶（極重要）
- ✅ 自嘲：從高位往下輕鬆看自己，不當真
  - 「我就是這麼隨性」「沒事亂問的哈哈」
- ❌ 自貶：真的覺得自己不好、道歉、求認可
  - 「變成了怪人」「可能我太奇怪了」「不好意思讓你覺得奇怪」
- 自嘲保持框架，自貶丟失框架

### 6. 正常人說話原則
- 回覆要像正常朋友聊天，不要像 AI 或機器人
- 不要用太文縐縐或太刻意的措辭
- 簡單直接 > 複雜修飾
- ❌ 「沒什麼特別原因，就是想當個有趣的人結果變成了怪人」
- ✅ 「沒事亂問的，我就是這麼隨性哈哈」

## GAME 五階段框架

分析對話處於哪個階段：
1. Opening (打開) - 破冰階段
2. Premise (前提) - 進入男女框架，建立張力
3. Qualification (評估) - 她證明自己配得上用戶
4. Narrative (敘事) - 個性樣本、說故事
5. Close (收尾) - 模糊邀約 → 確立邀約

## 場景觸發矩陣

根據對話情境自動識別並給出對應策略：

### 情境1: 目的性測試
- 觸發: 詢問交友軟體使用目的（如：「你玩這個是為了交友還是...？」）
- 策略: 模糊化與幽默感，不正面回答，留白讓對方腦補
- 範例: 「這個不好說。」「找飯搭子啊。」「如果說是為了性，會不會顯得我很膚淺？」

### 情境2: 情緒試探與抱怨
- 觸發: 抱怨回覆太慢、指責沒有邊界感、說氣話
- 策略: 陳述事實，不解釋不道歉，保持中立
- 範例: 「剛到家。」「你觀察蠻仔細的，晚安。」

### 情境2.5: 被質疑/輕微測試
- 觸發: 「為什麼會這樣問」「你怎麼會問這個」等質疑
- 策略: 輕鬆帶過，不防禦、不道歉、不自貶
- ✅ 正確範例: 「沒事亂問的，我就是這麼隨性哈哈」「好奇嘛」「想到就問了」
- ❌ 錯誤範例: 「不好意思讓你覺得奇怪」「我變成怪人了」「可能問得太突然」

### 情境3: 展示冷淡/狀態差
- 觸發: 表達不想出門、覺得累、沒興趣約會
- 策略: 提供情緒價值，不把冷淡當作針對自己，用玩笑輕鬆帶過
- 範例: 「那太虧了，妳都是怎麼度過的呀？」「擺爛也是一種選擇。」

### 情境4: 模糊邀約
- 觸發: 給出不明確的見面暗示（如：「等天氣暖和一點我們見面吧」）
- 策略: 保持隨緣，不顯飢渴，同意但不急著敲定時間
- 範例: 「隨緣吧。」「要不今晚夢裡見也行，夢裡什麼都能幹還不用負責。」

### 情境5: 斷聯後的破冰
- 觸發: 超過一週以上沒有互動
- 策略: 低壓力環境分享，不提過去為何沒聊，直接分享當下的正面日常
- 範例: 「這兩天天氣好好。」「最近工作忙嗎？」

### 情境6: 正式確立邀約
- 觸發: 對方明確同意碰面
- 策略: 展現帶領力，不再反問對方意見，直接給出明確的人事時地物選項
- 範例: 「約這裡怎麼樣？幾點方便？」（搭配地點截圖）

## 最高指導原則

### 1. 1.8x 黃金法則
所有建議回覆的字數必須 ≤ 對方「單條」訊息字數 × 1.8
這條規則不可違反。

### 1.2 多條訊息處理規則
如果對方連續發了多條訊息，根據訊息類型決定是否回覆：

| 訊息類型 | 是否回覆 | 範例 |
|----------|----------|------|
| 肯定句/是非句 | ❌ 不需回覆 | 「對啊」「嗯嗯」「好」 |
| 陳述句 | 熱度 > 50 才回覆 | 「我今天去看電影」 |
| 疑問句 | ✅ 必須回覆 | 「你呢？」「為什麼？」 |
| 圖片/貼圖 | ✅ 必須回覆 | [圖片] |

**輸出格式**：當對方有多條訊息時，針對每條需要回覆的訊息分別給建議。

### 1.5 回覆結構指南
**優先考慮兩段式**（在 1.8x 限制內）：
- 第一部分：回應/共鳴/觀察
- 第二部分：延伸/提問/冷讀
- ✅ 「Laufey的聲音確實很有質感，你最近的主打歌是哪首？」

**但以下情況用簡短一句更好**：
- 幽默/調侃時：簡短更有力 → 「那太虧了吧」
- 對方訊息很短時：配合節奏 → 「隨緣吧」
- 維持框架時：不解釋不道歉 → 「剛到家。」
- 推拉/抽離時：故意簡短 → 「是喔」

**判斷標準**：對話是否能自然延續？太單薄就加第二句，夠豐富就保持簡潔。

### 2. 70/30 法則
好的對話是 70% 聆聽 + 30% 說話
- 用戶不該一直問問題 (索取)
- 要適時分享故事 (提供)

### 3. 具體化原則
- ❌ 「有特別喜歡哪個歌手嗎？」(太泛、面試感)
- ✅ 「你是 Taylor Swift 粉嗎？」(具體、有話題延伸性)
- 用具體名字/事物而非泛問

### 4. 小服從性訓練
- 讓對方做小事，建立投入感
- ✅ 「你最近的主打歌是哪首？我聽聽」(請她分享)
- ✅ 「推薦一家你覺得不錯的？」(請她推薦)

### 5. 假設代替問句
- ❌ 「你是做什麼工作的？」(面試感)
- ✅ 「感覺你是做創意相關的工作？」(冷讀)

### 6. 陳述優於問句
朋友間直接問句比較少，陳述句讓對話更自然

### 7. Topic Depth Ladder
- Level 1: Event-oriented (Events) - 剛認識
- Level 2: Personal-oriented (Personal) - 有基本認識
- Level 3: Intimate-oriented (Intimate) - 熱度 > 60
- 原則：不可越級，循序漸進

### 8. 細緻化優先
- 不要一直換話題
- 針對對方回答深入挖掘

### 9. 不查戶口
- 絕對禁止詢問對方的隱私（身高體重、過往情史等）
- 當沒有好話題時，可以回覆：「暫時沒想到要問什麼」

### 10. 熱度分析規則
熱度 (enthusiasm) 只根據「她」的訊息判斷，不考慮「我」的發言：
- 回覆長度：長回覆 > 短回覆
- 表情符號：多 emoji/顏文字 = 較熱
- 主動提問：她問你問題 = 好奇/有興趣
- 話題延伸：她主動延伸話題 = 投入
- 回應態度：敷衍單字 vs 認真回應
- 不要因為「我」說了很多就拉高熱度

## 核心技巧

### 隱性價值展示 (DHV)
- 一句話帶過，不解釋
- 例：「剛從北京出差回來」而非「我很常出國」
- 展示後要保持謙遜，適當自嘲

### 框架控制
- 不因對方攻擊/挑釁/廢測而改變
- 不用點對點回答問題
- 可以跳出問題框架思考

### 廢物測試 (Shit Test)
- 廢測是好事，代表她在評估用戶
- 橡膠球理論：讓它彈開
- 回應方式：幽默曲解 / 直球但維持框架 / 忽略

### 淺溝通解讀
- 女生文字背後的意思 > 字面意思
- 一致性測試藏在文字裡

## 進階對話技巧

### 橫向思維 (Lateral Thinking)
- 用「這讓我想到...」連結不相關的事物
- 創造意想不到的連結，展現創意與幽默
- ❌ 她：「我週末去爬山」→「哪座山？」
- ✅ 她：「我週末去爬山」→「這讓我想到，我小時候以為山頂住著神仙」

### 剝洋蔥效應 (Peeling the Onion)
- 問「為什麼」而非「什麼」，挖掘深層動機
- 人們喜歡談論自己的原因，而非事實
- ❌ 「你做什麼工作？」→「工程師」→「在哪家公司？」
- ✅ 「你做什麼工作？」→「工程師」→「什麼讓你選擇這行？」

### 守護空間 (Holding Space)
- 當她分享負面情緒時，不急著給建議或解決
- 先共情、傾聽，讓她感覺被理解
- ❌ 她：「工作壓力好大」→「你應該換工作」
- ✅ 她：「工作壓力好大」→「聽起來真的很累，最近發生什麼事了？」

### 書籤技術 (Bookmarking)
- 標記有趣話題，稍後回來深入
- 「這個等下一定要聽你說」「先記住這個，回頭聊」
- 創造期待感，展現你在認真聽

### IOI/IOD 判讀
**IOI (興趣指標)**：
- 主動延伸話題、問你問題
- 用 emoji/顏文字、回覆速度快
- 分享個人資訊、笑聲（哈哈、XD）

**IOD (無興趣指標)**：
- 回覆簡短單字、長時間已讀不回
- 不問你問題、敷衍語氣
- 頻繁結束話題

### 假設性提問
- 用有趣假設打破乾聊
- 「如果你有超能力，你會選什麼？」
- 「如果明天不用上班，你第一件事做什麼？」
- 注意：只在對話卡住時使用，不要連續用

## 幽默機制

### 良性冒犯 (Benign Violation)
- 輕微打破規範，但不傷人
- 自嘲、輕微調侃、預期翻轉
- 「我很會做飯，前提是你不介意吃黑暗料理」

### 三段式法則 (Rule of Three)
- 前兩個建立模式，第三個打破預期
- 「我週末三大愛好：睡覺、追劇、假裝有社交生活」

### 回調 (Callback)
- 引用之前對話的內容製造笑點
- 建立共同記憶，展現你有在聽
- 「哈，這又讓我想到你說的那個神仙山」

### 幽默禁區
- 不嘲笑她在意的事
- 不開她外表/身材的玩笑
- 不用貶低他人來逗笑

## 對話平衡

### 不要搶話
- 她分享經驗時，不要馬上說「我也是」然後講自己
- 先深入她的話題，再自然分享
- ❌ 她：「我最近學滑板」→「我也會滑板，我還⋯⋯」
- ✅ 她：「我最近學滑板」→「真的嗎？是什麼讓你想學的？」

### 給予空間
- 不要每句話都回得很長
- 有時候簡短回應讓她有空間說更多
- 「然後呢？」「說來聽聽」也是好回覆

## 個人化原則
如果有提供用戶風格，回覆建議要符合該風格的說話方式：
- 幽默型：多用輕鬆俏皮的語氣
- 穩重型：沉穩內斂，不輕浮
- 直球型：簡單直接，不繞圈子
- 溫柔型：細膩體貼，照顧對方感受
- 調皮型：帶點挑逗，製造小驚喜

如果有提供對方特質，策略要考慮對方的個性。

## 冰點特殊處理
當熱度 0-30 且判斷機會渺茫時：
- 不硬回
- 可建議「已讀不回」
- 鼓勵開新對話

## 輸出格式 (JSON)
{
  "gameStage": {
    "current": "premise",
    "status": "正常進行",
    "nextStep": "可以開始評估階段"
  },
  "scenarioDetected": "normal | purpose_test | emotion_test | cold_display | vague_invite | reconnect | confirm_invite",
  "enthusiasm": { "score": 75, "level": "hot" },
  "topicDepth": { "current": "Personal-oriented", "suggestion": "可以往曖昧導向推進" },
  "psychology": {
    "subtext": "她這句話背後的意思是：對你有興趣",
    "shitTest": {
      "detected": false,
      "type": null,
      "suggestion": null
    },
    "qualificationSignal": true
  },
  "herMessages": [
    {
      "content": "她的第一條訊息",
      "type": "question",
      "shouldReply": true,
      "replies": {
        "extend": "...",
        "resonate": "...",
        "tease": "...",
        "humor": "...",
        "coldRead": "..."
      }
    }
  ],
  "replies": {
    "extend": "針對最後一條訊息的回覆",
    "resonate": "...",
    "tease": "...",
    "humor": "...",
    "coldRead": "..."
  },
  "finalRecommendation": {
    "pick": "tease",
    "content": "推薦的完整回覆內容（可能包含多條訊息的回應）",
    "reason": "為什麼推薦這個回覆",
    "psychology": "心理學依據"
  },
  "warnings": [],
  "healthCheck": {
    "issues": ["面試式提問過多"],
    "suggestions": ["用假設代替問句"]
  },
  "strategy": "簡短策略說明",
  "reminder": "記得用你的方式說，見面才自然"
}

## 用戶訊息優化功能
如果用戶提供了「想說的內容」(userDraft)，根據以上原則優化：
1. 套用 1.8x 法則（依據她最後一則訊息長度）
2. 避免自貶，改用自嘲
3. 套用兩段式結構（如適用）
4. 符合用戶風格設定
5. 保持正常人說話的語氣

輸出 optimizedMessage 欄位：
{
  "optimizedMessage": {
    "original": "用戶原本想說的",
    "optimized": "優化後的版本",
    "reason": "簡短說明優化了什麼"
  }
}

**reason 欄位規則（重要）**：
- ❌ 禁止提及「1.8x法則」、「黃金法則」或任何字數計算公式
- ❌ 禁止顯示「她X字，建議≤Y字」這類計算
- ✅ 用自然的描述：「縮短讓訊息更簡潔」「精簡字數」
- ✅ 範例：「精簡字數、用『耶』讓語氣更自然」

${SAFETY_RULES}`;

// 「我說」模式的 System Prompt（話題延續建議）
const MY_MESSAGE_PROMPT = `你是一位專業的社交溝通教練。用戶剛剛發送了一則訊息給對方，現在需要你根據對話脈絡，提供話題延續的建議。

## 你的任務

根據：
1. 用戶剛發送的訊息
2. 之前對話中了解到的「她」的特質、興趣、話題
3. 目前的對話熱度和階段

提供：
1. 如果她冷淡回覆，可以怎麼延續
2. 如果她熱情回覆，可以怎麼深入
3. 備用話題方向（根據她之前提過的興趣）
4. 注意事項（避免踩雷）

## 輸出格式 (JSON)

{
  "myMessageAnalysis": {
    "sentMessage": "用戶剛發送的訊息",
    "ifColdResponse": {
      "prediction": "她可能的冷淡回覆",
      "suggestion": "你可以這樣接"
    },
    "ifWarmResponse": {
      "prediction": "她可能的熱情回覆",
      "suggestion": "你可以這樣深入"
    },
    "backupTopics": [
      "根據她之前提過喜歡咖啡 → 可以聊最近喝到的好店",
      "她說過週末喜歡追劇 → 可以問最近在看什麼"
    ],
    "warnings": [
      "她之前對工作話題反應冷淡，避免再提"
    ]
  },
  "enthusiasm": { "score": 50, "level": "warm" }
}

## 重要原則
- 建議要具體可執行，不要泛泛而談
- 備用話題要根據對話中「她」提過的內容
- 如果對話太短沒有足夠資訊，就說「對話還太短，多聊幾輪後會更了解她」

${SAFETY_RULES}`;

// 訊息計算函數
function countMessages(messages: Array<{ content: string }>): number {
  let total = 0;
  for (const msg of messages) {
    const charCount = msg.content.trim().length;
    total += Math.max(1, Math.ceil(charCount / 200));
  }
  return Math.max(1, total);
}

// 測試模式：強制使用 Haiku + 不扣額度
const TEST_MODE = Deno.env.get("TEST_MODE") === "true";
// 測試帳號白名單 (不扣額度)
const TEST_EMAILS = ["vibesync.test@gmail.com"];

// 模型選擇函數 (設計規格 4.9)
function selectModel(context: {
  conversationLength: number;
  enthusiasmLevel: string | null;
  hasComplexEmotions: boolean;
  isFirstAnalysis: boolean;
  tier: string;
}): string {
  // 🧪 測試模式：強制使用 Haiku (省錢)
  if (TEST_MODE) {
    return "claude-haiku-4-5-20251001";
  }

  // Essential 用戶優先使用 Sonnet
  if (context.tier === "essential") {
    return "claude-sonnet-4-20250514";
  }

  // 使用 Sonnet 的情況 (30%)
  if (
    context.conversationLength > 20 || // 長對話
    context.enthusiasmLevel === "cold" || // 冷淡需要策略
    context.hasComplexEmotions || // 複雜情緒
    context.isFirstAnalysis // 首次分析建立基準
  ) {
    return "claude-sonnet-4-20250514";
  }

  // 預設使用 Haiku (70%)
  return "claude-haiku-4-5-20251001";
}

// CORS headers for all responses
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, x-client-info, apikey",
};

// Helper to create JSON response with CORS
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse({ error: "Invalid token" }, 401);
    }

    // 測試帳號：不檢查額度、不扣額度
    const isTestAccount = TEST_EMAILS.includes(user.email || "");

    // Check subscription
    const { data: sub } = await supabase
      .from("subscriptions")
      .select(
        "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at"
      )
      .eq("user_id", user.id)
      .single();

    if (!sub) {
      return jsonResponse({ error: "No subscription found" }, 403);
    }

    // Check if daily reset needed
    const now = new Date();
    const dailyResetAt = new Date(sub.daily_reset_at);
    if (now.toDateString() !== dailyResetAt.toDateString()) {
      await supabase
        .from("subscriptions")
        .update({ daily_messages_used: 0, daily_reset_at: now.toISOString() })
        .eq("user_id", user.id);
      sub.daily_messages_used = 0;
    }

    // Check monthly reset needed
    const monthlyResetAt = new Date(sub.monthly_reset_at);
    if (
      now.getMonth() !== monthlyResetAt.getMonth() ||
      now.getFullYear() !== monthlyResetAt.getFullYear()
    ) {
      await supabase
        .from("subscriptions")
        .update({
          monthly_messages_used: 0,
          monthly_reset_at: now.toISOString(),
        })
        .eq("user_id", user.id);
      sub.monthly_messages_used = 0;
    }

    // Check monthly limit (測試帳號跳過)
    const monthlyLimit = TIER_MONTHLY_LIMITS[sub.tier];
    if (!isTestAccount && sub.monthly_messages_used >= monthlyLimit) {
      return jsonResponse({
        error: "Monthly limit exceeded",
        monthlyLimit,
        used: sub.monthly_messages_used,
      }, 429);
    }

    // Check daily limit (測試帳號跳過)
    const dailyLimit = TIER_DAILY_LIMITS[sub.tier];
    if (!isTestAccount && sub.daily_messages_used >= dailyLimit) {
      return jsonResponse({
        error: "Daily limit exceeded",
        dailyLimit,
        used: sub.daily_messages_used,
        resetAt: "tomorrow",
      }, 429);
    }

    // Parse request
    const { messages, images, sessionContext, userDraft, forceModel, analyzeMode } = await req.json();
    // analyzeMode: "normal" (default) | "my_message" (用戶剛說完，給話題延續建議)
    // images: optional array of ImageData for screenshot analysis
    if (!messages || !Array.isArray(messages)) {
      return jsonResponse({ error: "Invalid messages" }, 400);
    }

    // Validate images if provided
    const hasImages = images && Array.isArray(images) && images.length > 0;
    if (hasImages) {
      if (images.length > 3) {
        return jsonResponse({ error: "最多上傳 3 張截圖" }, 400);
      }
      // Validate each image
      for (const img of images) {
        if (!img.data || !img.mediaType || typeof img.order !== "number") {
          return jsonResponse({ error: "圖片格式錯誤" }, 400);
        }
        // Check base64 size (rough estimate: ~1.33x of actual bytes)
        const estimatedBytes = (img.data.length * 3) / 4;
        if (estimatedBytes > 600 * 1024) { // 600KB limit per image
          return jsonResponse({ error: "圖片太大，請壓縮後重試" }, 400);
        }
      }
    }

    // Check input for safety (AI 護欄)
    const inputCheck = checkInput(messages);
    if (!inputCheck.safe) {
      return jsonResponse({
        error: inputCheck.reason,
        code: "UNSAFE_INPUT",
      }, 400);
    }

    // Format session context for Claude
    let contextInfo = "";
    if (sessionContext) {
      contextInfo = `
## 情境資訊
- 認識場景：${sessionContext.meetingContext || "未知"}
- 認識時長：${sessionContext.duration || "未知"}
- 用戶目標：${sessionContext.goal || "約出來"}
- 用戶風格：${sessionContext.userStyle || "未提供"}
- 用戶興趣：${sessionContext.userInterests || "未提供"}
- 對方特質：${sessionContext.targetDescription || "未提供"}
`;
    }

    // 對話記憶策略：最近 30 則訊息完整保留（約 15 輪）
    // 超過時，保留開頭 + 最近對話，中間省略
    const MAX_RECENT_MESSAGES = 30;
    const OPENING_MESSAGES = 4; // 保留最初的 4 則（破冰階段）
    let conversationText = "";

    if (messages.length > MAX_RECENT_MESSAGES + OPENING_MESSAGES) {
      // 長對話：保留開頭 + 最近
      const openingMessages = messages.slice(0, OPENING_MESSAGES);
      const recentMessages = messages.slice(-MAX_RECENT_MESSAGES);
      const skippedCount = messages.length - OPENING_MESSAGES - MAX_RECENT_MESSAGES;

      const openingText = openingMessages
        .map(
          (m: { isFromMe: boolean; content: string }) =>
            `${m.isFromMe ? "我" : "她"}: ${m.content}`
        )
        .join("\n");

      const recentText = recentMessages
        .map(
          (m: { isFromMe: boolean; content: string }) =>
            `${m.isFromMe ? "我" : "她"}: ${m.content}`
        )
        .join("\n");

      conversationText = `## 對話開頭（破冰階段）
${openingText}

---（中間省略 ${skippedCount} 則訊息）---

## 最近對話
${recentText}`;
    } else {
      // 訊息數量在限制內，完整送出
      conversationText = messages
        .map(
          (m: { isFromMe: boolean; content: string }) =>
            `${m.isFromMe ? "我" : "她"}: ${m.content}`
        )
        .join("\n");
    }

    // Select model based on complexity (or force for testing)
    // 有圖片時強制使用 Sonnet (Vision 功能需要)
    const VALID_MODELS = ["claude-haiku-4-5-20251001", "claude-sonnet-4-20250514"];
    const model = hasImages
      ? "claude-sonnet-4-20250514" // Vision 強制 Sonnet
      : (forceModel && VALID_MODELS.includes(forceModel))
        ? forceModel
        : selectModel({
            conversationLength: messages.length,
            enthusiasmLevel: null, // 首次分析前不知道
            hasComplexEmotions: false,
            isFirstAnalysis: messages.length <= 5,
            tier: sub.tier,
          });

    // Get available features for this tier
    const allowedFeatures = TIER_FEATURES[sub.tier] || TIER_FEATURES.free;

    // 檢查「我說」模式權限（只限 Essential）
    const isMyMessageMode = analyzeMode === "my_message";
    if (isMyMessageMode && sub.tier !== "essential") {
      return jsonResponse({
        error: "「我說」分析功能僅限 Essential 方案",
        code: "FEATURE_NOT_AVAILABLE",
        requiredTier: "essential",
      }, 403);
    }

    // 選擇 System Prompt
    const systemPrompt = isMyMessageMode ? MY_MESSAGE_PROMPT : SYSTEM_PROMPT;

    // 組合用戶訊息
    let userPrompt = isMyMessageMode
      ? `${contextInfo}\n\n## 對話紀錄\n${conversationText}\n\n請根據用戶剛發送的最後一則訊息，提供話題延續建議。`
      : `${contextInfo}\n分析以下對話並提供建議：\n\n${conversationText}`;

    // 如果有截圖，加入截圖識別指示
    if (hasImages) {
      const imageCount = images.length;
      userPrompt = `## 截圖分析任務

你收到了 ${imageCount} 張聊天截圖，請先識別截圖中的對話內容，然後進行分析。

### 截圖識別規則：
1. 識別每張截圖中的訊息，判斷是「我」還是「她」發送的
2. 按照截圖順序（1, 2, 3...）和訊息時間順序整理
3. 如果截圖有重疊的訊息，請去重
4. 忽略系統訊息、時間戳記、未讀標記等非對話內容

### 輸出格式（在原本的 JSON 中增加）：
{
  "recognizedConversation": {
    "messageCount": 10,
    "summary": "識別到 10 則訊息（我: 4, 她: 6）",
    "messages": [
      { "isFromMe": true, "content": "訊息內容" },
      { "isFromMe": false, "content": "訊息內容" }
    ]
  },
  // ...其他原有欄位
}

${contextInfo}

${conversationText ? `## 用戶手動輸入的對話（作為參考）\n${conversationText}\n\n` : ""}請識別截圖中的對話，並提供分析建議。`;
    }

    // 如果有用戶草稿，加入優化請求（只在 normal 模式）
    if (!isMyMessageMode && userDraft && typeof userDraft === "string" && userDraft.trim()) {
      userPrompt += `\n\n## 用戶想說的內容（請優化）\n「${userDraft.trim()}」\n請在 optimizedMessage 欄位提供優化版本。`;
    }

    // 「我說」模式用 Haiku 省成本（但有圖片時強制 Sonnet）
    const selectedModel = hasImages
      ? "claude-sonnet-4-20250514"
      : isMyMessageMode
        ? "claude-haiku-4-5-20251001"
        : model;

    // 建構 user message content（純文字或 Vision 格式）
    const userMessageContent = hasImages
      ? buildVisionContent(userPrompt, images as ImageData[])
      : userPrompt;

    const startTime = Date.now();
    let claudeResult;
    try {
      claudeResult = await callClaudeWithFallback(
        {
          model: selectedModel,
          max_tokens: hasImages ? 2048 : (isMyMessageMode ? 512 : 1024), // 截圖分析需要更多 tokens
          system: systemPrompt,
          messages: [
            {
              role: "user",
              content: userMessageContent,
            },
          ],
        },
        CLAUDE_API_KEY
      );
    } catch (error) {
      const latencyMs = Date.now() - startTime;

      if (error instanceof AiServiceError) {
        // Log failed request
        await logAiCall(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
          userId: user.id,
          model,
          inputTokens: 0,
          outputTokens: 0,
          latencyMs,
          status: "failed",
          errorCode: error.code,
          errorMessage: error.message,
        });

        return jsonResponse({
          error: error.message,
          code: error.code,
          retryable: error.retryable,
        }, 502);
      }
      throw error;
    }

    const content = claudeResult.data.content[0]?.text;
    const actualModel = claudeResult.model;
    const latencyMs = Date.now() - startTime;
    const tokenUsage = extractTokenUsage(claudeResult.data);

    // Parse Claude's response
    let result;
    try {
      const jsonMatch = content.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        console.error("No JSON found in AI response:", content?.substring(0, 500));
        throw new Error("No JSON in response");
      }
      result = JSON.parse(jsonMatch[0]);
    } catch (parseError) {
      console.error("JSON parse error:", parseError, "Content:", content?.substring(0, 500));
      result = {
        enthusiasm: { score: 50, level: "warm" },
        replies: {
          extend: "無法生成建議，請重試",
        },
        warnings: [],
        strategy: "分析失敗，請重試",
        // 如果有 userDraft，也返回 fallback
        ...(userDraft ? {
          optimizedMessage: {
            original: userDraft,
            optimized: "優化失敗，請重試",
            reason: "AI 回應解析錯誤",
          }
        } : {}),
      };
    }

    // 檢查截圖識別是否失敗
    if (hasImages && (!result.recognizedConversation || result.recognizedConversation.messageCount === 0)) {
      // Log failed recognition
      await logAiCall(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
        userId: user.id,
        model: actualModel,
        inputTokens: tokenUsage.inputTokens,
        outputTokens: tokenUsage.outputTokens,
        latencyMs,
        status: "recognition_failed",
      });

      return jsonResponse({
        error: "無法識別截圖中的對話內容",
        code: "RECOGNITION_FAILED",
        message: "請確保截圖清晰且為聊天畫面，支援 LINE、iMessage、WhatsApp 等常見通訊軟體",
        shouldChargeQuota: false,
      }, 400);
    }

    // Check AI output for safety (AI 護欄)
    const originalResult = { ...result };
    result = checkAiOutput(result);
    const wasFiltered = result.warnings?.some((w: { type: string }) => w.type === "safety_filter");

    // Log successful request
    await logAiCall(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      userId: user.id,
      model: actualModel,
      inputTokens: tokenUsage.inputTokens,
      outputTokens: tokenUsage.outputTokens,
      latencyMs,
      status: wasFiltered ? "filtered" : "success",
      fallbackUsed: claudeResult.fallbackUsed,
      retryCount: claudeResult.retries,
    });

    // Filter replies based on tier
    if (result?.replies) {
      const filteredReplies: Record<string, string> = {};
      for (const [key, value] of Object.entries(result.replies)) {
        if (allowedFeatures.includes(key)) {
          filteredReplies[key] = value as string;
        }
      }
      result.replies = filteredReplies;
    }

    // Remove health check if not allowed
    if (!allowedFeatures.includes("health_check")) {
      delete result.healthCheck;
    }

    // Calculate message count
    const messageCount = countMessages(messages);

    // Update usage count (測試帳號不扣額度)
    if (!isTestAccount) {
      await supabase
        .from("subscriptions")
        .update({
          monthly_messages_used: sub.monthly_messages_used + messageCount,
          daily_messages_used: sub.daily_messages_used + messageCount,
        })
        .eq("user_id", user.id);

      // Update user stats
      await supabase.rpc("increment_usage", {
        p_user_id: user.id,
        p_messages: messageCount,
      });
    }

    // Add usage info to response
    result.usage = {
      messagesUsed: messageCount,
      monthlyRemaining: isTestAccount ? 999999 : monthlyLimit - sub.monthly_messages_used - messageCount,
      dailyRemaining: isTestAccount ? 999999 : dailyLimit - sub.daily_messages_used - messageCount,
      model: actualModel,
      fallbackUsed: claudeResult.fallbackUsed,
      retries: claudeResult.retries,
      imagesUsed: hasImages ? images.length : 0,
      isTestAccount, // 標記是否為測試帳號
    };

    return jsonResponse(result);
  } catch (error) {
    console.error("Error:", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});

// Prompt Caching enabled
// Last deployed: 2026-03-06

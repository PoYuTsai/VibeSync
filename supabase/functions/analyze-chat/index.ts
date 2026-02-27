// supabase/functions/analyze-chat/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { SAFETY_RULES, checkAiOutput, checkInput } from "./guardrails.ts";
import { callClaudeWithFallback, AiServiceError } from "./fallback.ts";

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

const SYSTEM_PROMPT = `你是一位專業的社交溝通教練，幫助用戶提升對話技巧，最終目標是幫助用戶成功邀約。

## GAME 五階段框架

你必須分析對話處於哪個階段：
1. Opening (打開) - 破冰階段
2. Premise (前提) - 進入男女框架，建立張力
3. Qualification (評估) - 她證明自己配得上用戶
4. Narrative (敘事) - 個性樣本、說故事
5. Close (收尾) - 模糊邀約 → 確立邀約

## 最高指導原則

### 1. 1.8x 黃金法則
所有建議回覆的字數必須 ≤ 對方最後訊息字數 × 1.8
這條規則不可違反。

### 2. 82/18 原則
好的對話是 82% 聆聽 + 18% 說話
- 用戶不該一直問問題 (索取)
- 要適時分享故事 (提供)

### 3. 假設代替問句
- ❌ 「你是做什麼工作的？」(面試感)
- ✅ 「感覺你是做創意相關的工作？」(冷讀)

### 4. 陳述優於問句
朋友間直接問句比較少，陳述句讓對話更自然

### 5. 話題深度階梯
- Level 1: 事件導向 (Facts) - 剛認識
- Level 2: 個人導向 (Personal) - 有基本認識
- Level 3: 曖昧導向 (Intimate) - 熱度 > 60
- 原則：不可越級，循序漸進

### 6. 細緻化優先
- 不要一直換話題
- 針對對方回答深入挖掘

## 核心技巧

### 隱性價值展示 (DHV)
- 一句話帶過，不解釋
- 例：「剛從北京出差回來」而非「我很常出國」

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
  "enthusiasm": { "score": 75, "level": "hot" },
  "topicDepth": { "current": "personal", "suggestion": "可以往曖昧導向推進" },
  "psychology": {
    "subtext": "她這句話背後的意思是：對你有興趣",
    "shitTest": {
      "detected": false,
      "type": null,
      "suggestion": null
    },
    "qualificationSignal": true
  },
  "replies": {
    "extend": "...",
    "resonate": "...",
    "tease": "...",
    "humor": "...",
    "coldRead": "..."
  },
  "finalRecommendation": {
    "pick": "tease",
    "content": "推薦的完整回覆內容",
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

// 模型選擇函數 (設計規格 4.9)
function selectModel(context: {
  conversationLength: number;
  enthusiasmLevel: string | null;
  hasComplexEmotions: boolean;
  isFirstAnalysis: boolean;
  tier: string;
}): string {
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
  return "claude-3-5-haiku-20241022";
}

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Check subscription
    const { data: sub } = await supabase
      .from("subscriptions")
      .select(
        "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at"
      )
      .eq("user_id", user.id)
      .single();

    if (!sub) {
      return new Response(JSON.stringify({ error: "No subscription found" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
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

    // Check monthly limit
    const monthlyLimit = TIER_MONTHLY_LIMITS[sub.tier];
    if (sub.monthly_messages_used >= monthlyLimit) {
      return new Response(
        JSON.stringify({
          error: "Monthly limit exceeded",
          monthlyLimit,
          used: sub.monthly_messages_used,
        }),
        { status: 429, headers: { "Content-Type": "application/json" } }
      );
    }

    // Check daily limit
    const dailyLimit = TIER_DAILY_LIMITS[sub.tier];
    if (sub.daily_messages_used >= dailyLimit) {
      return new Response(
        JSON.stringify({
          error: "Daily limit exceeded",
          dailyLimit,
          used: sub.daily_messages_used,
          resetAt: "tomorrow",
        }),
        { status: 429, headers: { "Content-Type": "application/json" } }
      );
    }

    // Parse request
    const { messages, sessionContext } = await req.json();
    if (!messages || !Array.isArray(messages)) {
      return new Response(JSON.stringify({ error: "Invalid messages" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Check input for safety (AI 護欄)
    const inputCheck = checkInput(messages);
    if (!inputCheck.safe) {
      return new Response(
        JSON.stringify({
          error: inputCheck.reason,
          code: "UNSAFE_INPUT",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    // Format session context for Claude
    let contextInfo = "";
    if (sessionContext) {
      contextInfo = `
## 情境資訊
- 認識場景：${sessionContext.meetingContext || "未知"}
- 認識時長：${sessionContext.duration || "未知"}
- 用戶目標：${sessionContext.goal || "約出來"}
`;
    }

    // Format messages for Claude
    const conversationText = messages
      .map(
        (m: { isFromMe: boolean; content: string }) =>
          `${m.isFromMe ? "我" : "她"}: ${m.content}`
      )
      .join("\n");

    // Select model based on complexity
    const model = selectModel({
      conversationLength: messages.length,
      enthusiasmLevel: null, // 首次分析前不知道
      hasComplexEmotions: false,
      isFirstAnalysis: messages.length <= 5,
      tier: sub.tier,
    });

    // Get available features for this tier
    const allowedFeatures = TIER_FEATURES[sub.tier] || TIER_FEATURES.free;

    // Call Claude API with fallback
    let claudeResult;
    try {
      claudeResult = await callClaudeWithFallback(
        {
          model,
          max_tokens: 1024,
          system: SYSTEM_PROMPT,
          messages: [
            {
              role: "user",
              content: `${contextInfo}\n分析以下對話並提供建議：\n\n${conversationText}`,
            },
          ],
        },
        CLAUDE_API_KEY
      );
    } catch (error) {
      if (error instanceof AiServiceError) {
        return new Response(
          JSON.stringify({
            error: error.message,
            code: error.code,
            retryable: error.retryable,
          }),
          {
            status: 502,
            headers: { "Content-Type": "application/json" },
          }
        );
      }
      throw error;
    }

    const content = claudeResult.data.content[0]?.text;
    const actualModel = claudeResult.model;

    // Parse Claude's response
    let result;
    try {
      const jsonMatch = content.match(/\{[\s\S]*\}/);
      result = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      result = {
        enthusiasm: { score: 50, level: "warm" },
        replies: {
          extend: "無法生成建議，請重試",
        },
        warnings: [],
        strategy: "分析失敗，請重試",
      };
    }

    // Check AI output for safety (AI 護欄)
    result = checkAiOutput(result);

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

    // Update usage count
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

    // Add usage info to response
    result.usage = {
      messagesUsed: messageCount,
      monthlyRemaining: monthlyLimit - sub.monthly_messages_used - messageCount,
      dailyRemaining: dailyLimit - sub.daily_messages_used - messageCount,
      model: actualModel,
      fallbackUsed: claudeResult.fallbackUsed,
      retries: claudeResult.retries,
    };

    return new Response(JSON.stringify(result), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

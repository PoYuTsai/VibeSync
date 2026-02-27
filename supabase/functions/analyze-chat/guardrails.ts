// supabase/functions/analyze-chat/guardrails.ts

// 安全規則 - 加入 System Prompt
export const SAFETY_RULES = `
## 安全規則 (不可違反)

### 絕對禁止建議：
- 任何形式的騷擾、跟蹤、強迫行為
- 未經同意的身體接觸暗示
- 操控、威脅、情緒勒索的言語
- 持續聯繫已明確拒絕的對象
- 任何違法行為

### 冰點情境處理：
當熱度 < 30 且對方明顯不感興趣時：
- 建議用戶「尊重對方意願」
- 可建議「開新對話，認識其他人」
- 絕不建議「再試一次」或「換個方式追」

### 輸出原則：
- 所有建議必須基於「雙方舒適」
- 鼓勵真誠表達，而非操控技巧
`;

// 禁止詞彙模式
const BLOCKED_PATTERNS = [
  /跟蹤|stalking/i,
  /不要放棄.*一直/i,
  /她說不要.*但其實/i,
  /強迫|逼.*答應/i,
  /騷擾|harassment/i,
  /威脅|勒索/i,
  /死纏爛打/i,
  /不尊重.*意願/i,
  /忽視.*拒絕/i,
];

// 安全回覆 (當觸發護欄時)
const SAFE_REPLIES: Record<string, Record<string, string>> = {
  cold: {
    extend: "可以聊聊最近有什麼有趣的事嗎？",
    resonate: "我理解，每個人都有自己的步調",
    tease: "好吧，那我先忙我的囉",
    humor: "看來今天運氣不太好呢",
    coldRead: "感覺你現在比較忙？",
  },
  warm: {
    extend: "這個話題蠻有趣的，可以多說一點嗎？",
    resonate: "我懂你的意思",
    tease: "你這樣說讓我很好奇欸",
    humor: "哈哈，你很有趣耶",
    coldRead: "感覺你是個很有想法的人",
  },
  hot: {
    extend: "繼續聊這個，我覺得很有意思",
    resonate: "對啊，我也這麼覺得",
    tease: "你這樣說，讓我更想認識你了",
    humor: "跟你聊天很開心耶",
    coldRead: "我覺得我們蠻合的",
  },
  very_hot: {
    extend: "我們可以找時間見面聊",
    resonate: "真的很開心認識你",
    tease: "那我們來約個時間吧",
    humor: "再聊下去我要愛上你了",
    coldRead: "我有預感我們會很合",
  },
};

// 熱度等級映射
function getEnthusiasmLevel(score: number): string {
  if (score <= 30) return "cold";
  if (score <= 60) return "warm";
  if (score <= 80) return "hot";
  return "very_hot";
}

// 取得安全回覆
export function getSafeReplies(level: string): Record<string, string> {
  return SAFE_REPLIES[level] || SAFE_REPLIES.warm;
}

// 分析結果介面
export interface AnalysisResult {
  enthusiasm: { score: number; level: string };
  replies: Record<string, string>;
  warnings: Array<{ type: string; message: string }>;
  [key: string]: unknown;
}

// 檢查 AI 輸出是否安全
export function checkAiOutput(result: AnalysisResult): AnalysisResult {
  if (!result?.replies) {
    return result;
  }

  const allReplies = Object.values(result.replies).join(" ");

  for (const pattern of BLOCKED_PATTERNS) {
    if (pattern.test(allReplies)) {
      const level = getEnthusiasmLevel(result.enthusiasm?.score || 50);
      return {
        ...result,
        replies: getSafeReplies(level),
        warnings: [
          ...(result.warnings || []),
          {
            type: "safety_filter",
            message: "部分建議因安全考量已調整",
          },
        ],
      };
    }
  }

  return result;
}

// 檢查輸入是否包含敏感內容
export function checkInput(messages: Array<{ content: string }>): {
  safe: boolean;
  reason?: string;
} {
  const combinedText = messages.map((m) => m.content).join(" ");

  // 檢查是否詢問如何騷擾/跟蹤
  const dangerousPatterns = [
    /如何.*跟蹤/i,
    /怎麼.*強迫/i,
    /她不願意.*怎麼/i,
    /拒絕.*還是想/i,
  ];

  for (const pattern of dangerousPatterns) {
    if (pattern.test(combinedText)) {
      return {
        safe: false,
        reason: "偵測到不當意圖，無法提供建議",
      };
    }
  }

  return { safe: true };
}

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
    extend: "這個有畫面欸，你是怎麼想到的？",
    resonate: "有點準，但我想聽聽你為什麼這樣覺得",
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

/**
 * 使用者會原樣送出的訊息用的樣式，與 BLOCKED_PATTERNS 刻意分開。
 *
 * BLOCKED_PATTERNS 擋的是「教練建議」的措辭（「不要放棄，一直約她」），
 * 拿去掃第一人稱訊息會大量誤傷：「我不是要逼你答應」「你這樣讓我覺得被
 * 騷擾」「我不想死纏爛打」都是正當、甚至正是在設界線的句子，擋掉等於幫
 * 施壓的一方消音。所以這裡只擋句構明確的脅迫，不擋單一詞彙。
 */
const OUTBOUND_COERCION_PATTERNS = [
  // 條件式威脅：你不 X 我就 Y。
  // 「去死」要排除「去死心」；「死給你看」是模型真的寫得出來的說法。
  /你(要是|如果|若)?不[^。！？\n]{0,16}我就[^。！？\n]{0,16}(去死(?!心)|死給你看|自殺|傷害|報復)/,
  // 以自傷作為籌碼。「不想活」要排除「不想活在怨恨裡」這類正常敘述。
  /(沒有你|你不理我|你離開我)[^。！？\n]{0,12}我(就)?(去死(?!心)|死給你看|自殺|活不下去|不想活(?!在|得|成|像))/,
  // 威脅散布私密內容。必須有條件式脅迫的引子，否則「我不會把照片傳出去，
  // 你放心」這種安撫句會被誤擋；中文動賓順序兩種都要涵蓋。
  // 引子要排除「你不想／你不希望」——那是在替對方著想，不是威脅。
  /(你不(?!想|希望|願意|願)|再不|不然|否則)[^。！？\n]{0,20}((照片|影片|截圖|對話|私密照)[^。！？\n]{0,8}(公開|散布|傳出去|外流|讓大家看|讓大家知道)|(公開|散布|傳出去|外流|讓大家看|讓大家知道)[^。！？\n]{0,8}(照片|影片|截圖|對話|私密照))/,
  // 宣告掌握行蹤。**不能含「知道」**——「我知道你住哪區比較方便，下次約
  // 中間點」是完全正常的約會訊息。威脅感來自「查」這個動作，或直接講出
  // 「地址」。
  /我(已經)?(查到|查得到)[^。！？\n]{0,10}你[^。！？\n]{0,8}(住哪|家在哪|地址)|我(已經)?知道你(家的?|的)?地址/,
];

/** 被 outbound 守門攔下時掛在 warnings 上的型別，供呼叫端做觀測。 */
export const OUTBOUND_SAFETY_WARNING_TYPE = "safety_filter_outbound";

export function hasOutboundSafetyWarning(result: unknown): boolean {
  const warnings = (result as { warnings?: unknown })?.warnings;
  if (!Array.isArray(warnings)) return false;
  return warnings.some(
    (warning) =>
      (warning as { type?: unknown })?.type === OUTBOUND_SAFETY_WARNING_TYPE,
  );
}

// 分析結果介面
export interface AnalysisResult {
  enthusiasm: { score: number; level: string };
  replies: Record<string, string>;
  warnings: Array<{ type: string; message: string }>;
  [key: string]: unknown;
}

/**
 * 草稿潤飾／回覆微調的輸出是 `optimizedMessage`，沒有 `replies`，
 * 以往會在 checkAiOutput 開頭直接返回，等於完全沒有輸出守門。
 *
 * 攔下時不塞罐頭文字——那對「幫我改這句話」毫無意義。改成清空 optimized，
 * 讓呼叫端既有的 `hasUsableOptimizedMessage` 判為無效結果：不寫 ledger、
 * 不扣額度、回可讀的錯誤。
 */
function checkOptimizedMessage(result: AnalysisResult): AnalysisResult {
  const optimizedMessage = result.optimizedMessage;
  if (
    !optimizedMessage || typeof optimizedMessage !== "object" ||
    Array.isArray(optimizedMessage)
  ) {
    return result;
  }
  const optimized = (optimizedMessage as Record<string, unknown>).optimized;
  if (typeof optimized !== "string" || optimized.trim().length === 0) {
    return result;
  }

  for (const pattern of OUTBOUND_COERCION_PATTERNS) {
    if (pattern.test(optimized)) {
      return {
        ...result,
        optimizedMessage: {
          ...(optimizedMessage as Record<string, unknown>),
          optimized: "",
        },
        // 模型可能把 warnings 回成物件而不是陣列；直接展開會丟 TypeError
        // 把整個請求變成 500。既有 replies 路徑有同樣的寫法（既有問題，
        // 本次不動），新路徑至少自己守住。
        warnings: [
          ...(Array.isArray(result.warnings) ? result.warnings : []),
          {
            type: OUTBOUND_SAFETY_WARNING_TYPE,
            message: "這次的結果因安全考量未提供",
          },
        ],
      };
    }
  }

  return result;
}

// 檢查 AI 輸出是否安全
export function checkAiOutput(result: AnalysisResult): AnalysisResult {
  if (!result?.replies) {
    return result ? checkOptimizedMessage(result) : result;
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

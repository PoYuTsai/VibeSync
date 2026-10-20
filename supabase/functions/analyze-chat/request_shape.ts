// analyze-chat 的請求形狀分類：把 index.ts 裡散落的 inline booleans 收斂成
// 單一 discriminated union。分類只看 request body 的原始欄位，發生在訂閱、
// 額度、模型工作之前。
//
// 優先序完全鏡射既有 handler 的分支順序（fc8bbe84 行為基準）：
//   new_topic > opener > opener_analyze > opener_generate > recognize >
//   my_message > optimize_message /
//   draft_with_images_analyze > plain_analyze
//
// 兩個容易踩錯的既有契約，改這裡等於改計費邊界：
// - optimize_message 形狀要求「沒有圖」；draft＋圖是另一個活形狀
//   （legacy 按訊息數計費的 analyze_with_images），不得被 optimize 或
//   streaming-only guard 接管。
// - recognizeOnlyRequested 是 raw 旗標：opener/new_topic 分支雖然無視它，
//   但 paid-tier sync gate 以 raw 旗標判斷（歷史行為），因此 raw 值必須
//   與 dispatch 形狀分開回傳。

export type AnalyzeChatRequestShape =
  | { kind: "new_topic" }
  | { kind: "opener" }
  // 兩段式（2026-09-17）：先分析（免費、不回開場白）、再依用戶補充生成。
  | { kind: "opener_analyze" }
  | { kind: "opener_generate" }
  | { kind: "recognize" }
  | { kind: "my_message" }
  | { kind: "optimize_message" }
  | { kind: "draft_with_images_analyze" }
  | { kind: "plain_analyze" };

export type RequestShapeResolution =
  | {
    ok: true;
    shape: AnalyzeChatRequestShape;
    /// request body 的 recognizeOnly 原始旗標（與 dispatch 無關的歷史語意）。
    recognizeOnlyRequested: boolean;
  }
  | { ok: false; error: "INVALID_RECOGNIZE_ONLY" };

export interface RequestShapeInput {
  recognizeOnly?: unknown;
  mode?: unknown;
  analyzeMode?: unknown;
  userDraft?: unknown;
  images?: unknown;
}

export function classifyAnalyzeChatRequest(
  input: RequestShapeInput,
): RequestShapeResolution {
  if (input.recognizeOnly != null && typeof input.recognizeOnly !== "boolean") {
    return { ok: false, error: "INVALID_RECOGNIZE_ONLY" };
  }
  const recognizeOnlyRequested = input.recognizeOnly === true;
  const hasImages = Array.isArray(input.images) && input.images.length > 0;
  const hasDraft = typeof input.userDraft === "string" &&
    input.userDraft.trim().length > 0;

  const shape: AnalyzeChatRequestShape = input.mode === "new_topic"
    ? { kind: "new_topic" }
    : input.mode === "opener"
    ? { kind: "opener" }
    : input.mode === "opener_analyze"
    ? { kind: "opener_analyze" }
    : input.mode === "opener_generate"
    ? { kind: "opener_generate" }
    : recognizeOnlyRequested
    ? { kind: "recognize" }
    : input.analyzeMode === "my_message"
    ? { kind: "my_message" }
    : hasDraft
    ? (hasImages
      ? { kind: "draft_with_images_analyze" }
      : { kind: "optimize_message" })
    : { kind: "plain_analyze" };

  return { ok: true, shape, recognizeOnlyRequested };
}

/// 「關於我」只給 Coach 1:1（2026-08-04 決定）。舊版 App 仍可能帶
/// effectiveStyleContext：合法值只留在重送指紋裡，部署前後同一筆請求的重試才
/// 對得上、不會重複扣額度；不合法的值（不是字串、超過 1,200 字）當作沒帶，不再
/// 回 400，因為它不會交給模型。2026-10-20 起舊單段開場救星（mode: opener）走
/// 這條規則；新話題的請求驗證照舊嚴格（不合法回 400），合法值一樣只留指紋
///（new_topic_payload.ts）。
export function legacyStyleContextForHash(
  validation: { effectiveStyleContext?: string; error?: string },
): string | undefined {
  return validation.error ? undefined : validation.effectiveStyleContext;
}

/// 目前還會把舊值交給模型的只剩輔助寫訊息（my_message、optimize／refine）；
/// 這兩條改成只留指紋之前，行為照舊。主分析（含截圖）一律丟棄，不能影響分數、
/// 階段與風格。開場救星與新話題在 handler 呼叫這裡之前就分流，2026-10-20 起只
/// 把舊值留在指紋（opener_handler.ts、new_topic_payload.ts）。
export function acceptsUserStyleContext(
  shape: AnalyzeChatRequestShape,
): boolean {
  return shape.kind === "my_message" || shape.kind === "optimize_message";
}

export function routeUserStyleContext(
  shape: AnalyzeChatRequestShape,
  validation: { effectiveStyleContext?: string; error?: string },
): {
  modelValue?: string;
  hashValue?: string;
  error?: string;
} {
  if (acceptsUserStyleContext(shape)) {
    return {
      modelValue: validation.effectiveStyleContext,
      hashValue: validation.effectiveStyleContext,
      error: validation.error,
    };
  }
  // Main analysis ignores About Me even when an old client still sends it.
  // A valid legacy value remains hash-only so an in-flight run created before
  // this deployment can reconnect without becoming a second paid analysis.
  return validation.error
    ? {}
    : { hashValue: validation.effectiveStyleContext };
}

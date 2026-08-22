// analyze-chat 的請求形狀分類：把 index.ts 裡散落的 inline booleans 收斂成
// 單一 discriminated union。分類只看 request body 的原始欄位，發生在訂閱、
// 額度、模型工作之前。
//
// 優先序完全鏡射既有 handler 的分支順序（fc8bbe84 行為基準）：
//   new_topic > opener > recognize > my_message > optimize_message /
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

/// About Me / voice preferences belong to auxiliary reply-writing paths.
/// Main AnalyzeChat (including screenshot analysis) must ignore the field even
/// when an older client still sends it, so it cannot affect score/stage/style.
export function acceptsUserStyleContext(
  shape: AnalyzeChatRequestShape,
): boolean {
  return shape.kind === "my_message" || shape.kind === "optimize_message" ||
    shape.kind === "new_topic" || shape.kind === "opener";
}

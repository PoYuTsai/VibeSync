// AnalyzeChat 模型選擇：production 一律 Sonnet 5（舊模型只活在 outage
// fallback chain）；forceModel 只開放測試帳號／TEST_MODE 的基準測試。
// 位元組以 fc8bbe84 基準 hash 鎖定（baseline_contract_test.ts）。

const VALID_FORCE_MODELS = new Set([
  "claude-haiku-4-5-20251001",
  "claude-sonnet-4-6",
  "claude-sonnet-5",
]);

// 模型選擇函數 (設計規格 4.9)
function selectModel(context: {
  conversationLength: number;
  enthusiasmLevel: string | null;
  hasComplexEmotions: boolean;
  isFirstAnalysis: boolean;
  tier: string;
}): string {
  // Free 分析固定提供延展＋調情，並使用最新 Sonnet 守住首次體驗品質。
  if (context.tier === "free") {
    return "claude-sonnet-5";
  }

  // Starter / Essential 與 Free 分析都以最新 Sonnet 作為主模型；
  // 4.6 僅保留在 fallback chain，避免上游短暫異常直接失敗。
  if (context.tier === "starter" || context.tier === "essential") {
    return "claude-sonnet-5";
  }

  // 使用 Sonnet 的情況 (30%)
  if (
    context.conversationLength > 20 || // 長對話
    context.enthusiasmLevel === "cold" || // 冷淡需要策略
    context.hasComplexEmotions || // 複雜情緒
    context.isFirstAnalysis // 首次分析建立基準
  ) {
    return "claude-sonnet-5";
  }

  // 未知但已通過訂閱正規化的 tier 也維持 Sonnet 5，避免新增方案時
  // 靜默降級到舊模型。舊模型只存在於明確的 outage fallback chain。
  return "claude-sonnet-5";
}

export { selectModel, VALID_FORCE_MODELS };

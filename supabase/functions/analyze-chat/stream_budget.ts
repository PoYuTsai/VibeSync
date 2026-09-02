export const STREAM_ANALYZE_BASE_MAX_TOKENS = 4500;
export const STREAM_ANALYZE_FULL_STYLE_MAX_TOKENS = 6000;

/// Free requests currently emit two reply styles, while paid requests emit the
/// complete five-style contract. The full contract can contain up to five
/// segments per style plus inventory, metrics, report sections, and the final
/// completion anchor, so it must not share the smaller two-style budget.
export function streamAnalyzeMaxTokensForStyleCount(
  replyStyleCount: number,
  options: { divergencePlan?: boolean } = {},
): number {
  const base = replyStyleCount > 2
    ? STREAM_ANALYZE_FULL_STYLE_MAX_TOKENS
    : STREAM_ANALYZE_BASE_MAX_TOKENS;
  return base + (options.divergencePlan ? DIVERGENCE_PLAN_EXTRA_TOKENS : 0);
}

/// Phase 2a：v2 多吐一個 analysis.divergence_plan（最多 12 枝、每枝含
/// associationPath），不加預算會擠掉 report sections 或最後一張 reply_option。
export const DIVERGENCE_PLAN_EXTRA_TOKENS = 500;

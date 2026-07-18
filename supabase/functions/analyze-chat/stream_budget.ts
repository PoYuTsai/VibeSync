export const STREAM_ANALYZE_BASE_MAX_TOKENS = 3200;
export const STREAM_ANALYZE_FULL_STYLE_MAX_TOKENS = 6000;

/// Free requests currently emit two reply styles, while paid requests emit the
/// complete five-style contract. The full contract can contain up to five
/// segments per style plus inventory, metrics, report sections, and the final
/// completion anchor, so it must not share the smaller two-style budget.
export function streamAnalyzeMaxTokensForStyleCount(
  replyStyleCount: number,
): number {
  return replyStyleCount > 2
    ? STREAM_ANALYZE_FULL_STYLE_MAX_TOKENS
    : STREAM_ANALYZE_BASE_MAX_TOKENS;
}

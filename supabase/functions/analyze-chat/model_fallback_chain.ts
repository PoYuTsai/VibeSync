// 依主模型決定的備援鏈（fallback.ts 與 streaming_fallback.ts 共用）。
// ADR #24／#28／#49／#55：4.6 留在 Sonnet 5 之後；5.5 先退回 Sonnet 5。
// 主模型是 5.5 時只走 5.5 → Sonnet 5 → 4.6；每個模型只試一次時（正式呼叫點
// 都設 maxRetries 1）含主模型共 3 次，等於 ModelCallBudget 每請求的呼叫上限。
// Sonnet 5 當主模型的鏈不變。
// 鏈只看主模型：退到 Sonnet 5 之後不會接上 Sonnet 5 自己那條鏈的 Haiku。

import {
  SONNET_5_5_MODEL,
  SONNET_5_MODEL,
} from "../_shared/model_request_params.ts";

const SONNET_4_6_MODEL = "claude-sonnet-4-6";
const HAIKU_4_5_MODEL = "claude-haiku-4-5-20251001";

const FALLBACK_CHAINS: Readonly<Record<string, readonly string[]>> = {
  [SONNET_5_5_MODEL]: [SONNET_5_MODEL, SONNET_4_6_MODEL],
  [SONNET_5_MODEL]: [SONNET_4_6_MODEL, HAIKU_4_5_MODEL],
  [SONNET_4_6_MODEL]: [HAIKU_4_5_MODEL],
};

function chainFor(primary: string): readonly string[] {
  return Object.hasOwn(FALLBACK_CHAINS, primary)
    ? [primary, ...FALLBACK_CHAINS[primary]]
    : [primary];
}

/// 主模型 `primary` 的鏈上，`current` 的下一跳；鏈尾或不在鏈上回 undefined。
export function nextFallbackModel(
  primary: string,
  current: string,
): string | undefined {
  const chain = chainFor(primary);
  const index = chain.indexOf(current);
  return index < 0 ? undefined : chain[index + 1];
}

/// 這個主模型最多打幾次 provider（備援鏈長度，含自己）；ai_logs 記這個值。
export function providerMaxAttempts(primary: string): number {
  return chainFor(primary).length;
}

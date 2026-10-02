// 依模型決定 Anthropic messages 請求的 thinking／effort／temperature 欄位。
// 換模型時只改這裡，不在各呼叫點各自判斷模型名。
//   - Sonnet 5：thinking 預設關（{type:"disabled"}），呼叫端可指定；不送 temperature。
//   - Sonnet 5.5：送 disabled 或非預設 temperature 都回 400。最低設定是
//     between_tools（不帶工具時＝不先想就答），effort 要明講（API 預設 high）。
//   - 其他模型（Sonnet 4.6、Haiku 4.5）：照舊不帶 thinking，temperature 照呼叫端給。

export const SONNET_5_MODEL = "claude-sonnet-5";
export const SONNET_5_5_MODEL = "claude-sonnet-5-5";
/// 5.5 不先想就答時的 effort；between_tools 只收 low／medium／high。
export const SONNET_5_5_EFFORT = "medium";

export type ClaudeThinkingParam = {
  type: "disabled" | "adaptive" | "between_tools";
};

export interface ModelRequestParams {
  thinking?: ClaudeThinkingParam;
  output_config?: Record<string, unknown>;
  temperature?: number;
}

/// 回傳可直接展開進 request body 的欄位。`outputConfig`（例如 structured output
/// 的 format）原樣保留，5.5 再併入 effort。
export function modelRequestParams(
  model: string,
  caller: {
    thinking?: { type: "disabled" | "adaptive" };
    outputConfig?: Record<string, unknown>;
    temperature?: number;
  } = {},
): ModelRequestParams {
  const outputConfig = caller.outputConfig
    ? { output_config: caller.outputConfig }
    : {};
  if (model === SONNET_5_MODEL) {
    return {
      thinking: caller.thinking ?? { type: "disabled" },
      ...outputConfig,
    };
  }
  if (model === SONNET_5_5_MODEL) {
    return {
      thinking: { type: "between_tools" },
      output_config: { ...caller.outputConfig, effort: SONNET_5_5_EFFORT },
    };
  }
  return caller.temperature === undefined
    ? outputConfig
    : { ...outputConfig, temperature: caller.temperature };
}

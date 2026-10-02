// 依模型決定 Anthropic messages 請求的 thinking／effort／temperature 欄位與
// max_tokens 餘裕。換模型時只改這裡，不在各呼叫點各自判斷模型名。
//   - Sonnet 5：thinking 預設關（{type:"disabled"}），呼叫端可指定；不送 temperature。
//   - Sonnet 5.5：送 disabled、非預設 temperature、強制 tool_choice 都回 400。
//     一律 adaptive thinking（display omitted，不回思考內容）＋effort low（設定 C，
//     2026-10-02 黑箱 QA 通過）。思考 token 算在 max_tokens 裡，所以每次呼叫
//     要用 maxTokensFor 多給 4000，備援到別的模型時回到原本的值。
//   - 其他模型（Sonnet 4.6、Haiku 4.5）：照舊不帶 thinking，temperature 照呼叫端給。

export const SONNET_5_MODEL = "claude-sonnet-5";
export const SONNET_5_5_MODEL = "claude-sonnet-5-5";
export const SONNET_5_5_EFFORT = "low";
/// 5.5 adaptive thinking 吃掉的 max_tokens 餘裕（可見輸出預算不變）。
export const SONNET_5_5_THINKING_HEADROOM_TOKENS = 4000;

export type ClaudeThinkingParam = {
  type: "disabled" | "adaptive";
  display?: "omitted";
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
      thinking: { type: "adaptive", display: "omitted" },
      output_config: { ...caller.outputConfig, effort: SONNET_5_5_EFFORT },
    };
  }
  return caller.temperature === undefined
    ? outputConfig
    : { ...outputConfig, temperature: caller.temperature };
}

/// 這次呼叫實際送的 max_tokens：`base` 是可見輸出預算，只有 5.5 加思考餘裕。
export function maxTokensFor(model: string, base: number): number {
  return model === SONNET_5_5_MODEL
    ? base + SONNET_5_5_THINKING_HEADROOM_TOKENS
    : base;
}

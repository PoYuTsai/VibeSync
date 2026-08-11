// DeepSeek 呼叫（OpenAI 相容 /chat/completions）。
// 全域律：外部 API 必 try-catch、錯誤訊息不得 minified。

import type { ChatMessage } from "./prompt.ts";

export const DEEPSEEK_MODEL = "deepseek-v4-flash";
export const DEEPSEEK_ENDPOINT = "https://api.deepseek.com/chat/completions";

export interface DeepSeekArgs {
  apiKey: string;
  messages: ChatMessage[];
  maxTokens: number;
  temperature: number;
  jsonMode?: boolean;
  /** V4 defaults to thinking enabled; latency-sensitive binary checks opt out. */
  thinking?: { type: "enabled" | "disabled" };
  timeoutMs: number;
  endpoint?: string;
  model?: string;
}

/**
 * 呼叫 DeepSeek，回傳 assistant 訊息純文字。
 * 任何 HTTP / 逾時 / 空回覆都丟出帶可讀訊息的 Error，由 handler 轉 5xx（未扣額度）。
 */
export async function callDeepSeek(args: DeepSeekArgs): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), args.timeoutMs);
  try {
    const body: Record<string, unknown> = {
      model: args.model ?? DEEPSEEK_MODEL,
      messages: args.messages,
      max_tokens: args.maxTokens,
      temperature: args.temperature,
      stream: false,
    };
    if (args.jsonMode) {
      body.response_format = { type: "json_object" };
    }
    // 呼叫端沒明講就一律關 thinking（2026-08-11，用真 DeepSeek 跑離線黑箱抓到）。
    // V4 預設開 thinking，而 reasoning tokens 是算在 completion 裡的；本專案每個
    // 呼叫端的 max_tokens 都是照「只輸出可見文字」估的（分類器 450／聊天 200）。
    // 實測 reasoning 就吃掉 380-415：分類器 6/6 輪 finish_reason=length →
    // 丟 deepseek_max_tokens → 溫度／熟悉度整場不動；聊天 1/3 回空字串燒掉重試。
    // 關掉之後分類器 completion 62 tokens、finish_reason=stop，又快又便宜。
    // 真的需要 thinking 的呼叫端自己傳 { type: "enabled" }。
    body.thinking = args.thinking ?? { type: "disabled" };

    const res = await fetch(args.endpoint ?? DEEPSEEK_ENDPOINT, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${args.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    if (!res.ok) {
      // 只保留 status：response body 可能含 provider 端細節，不寫進錯誤訊息
      // （handler 會 log 此訊息）。body 讀掉避免連線懸置。
      await res.text().catch(() => "");
      throw new Error(`deepseek_http_${res.status}`);
    }

    const json = await res.json();
    const choice = json?.choices?.[0];
    if (choice?.finish_reason === "length") {
      throw new Error("deepseek_max_tokens");
    }
    const content = choice?.message?.content;
    if (typeof content !== "string" || content.trim().length === 0) {
      throw new Error("deepseek_empty_content");
    }
    return content.trim();
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new Error("deepseek_timeout");
    }
    throw e instanceof Error ? e : new Error(String(e));
  } finally {
    clearTimeout(timeout);
  }
}

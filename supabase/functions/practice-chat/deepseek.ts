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
    const content = json?.choices?.[0]?.message?.content;
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

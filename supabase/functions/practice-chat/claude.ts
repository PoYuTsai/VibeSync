// Claude Messages API caller used only as a generated failover for
// practice Hint/Debrief. It never returns canned content.
import type { ChatMessage } from "./prompt.ts";

export const CLAUDE_HAIKU_MODEL = "claude-haiku-4-5-20251001";
export const CLAUDE_SONNET_MODEL = "claude-sonnet-5";
export const CLAUDE_ENDPOINT = "https://api.anthropic.com/v1/messages";

export interface ClaudeArgs {
  apiKey: string;
  messages: ChatMessage[];
  maxTokens: number;
  temperature: number;
  timeoutMs: number;
  /** Optional provider-level JSON shape. Product semantics stay in the parser. */
  outputJsonSchema?: Readonly<Record<string, unknown>>;
  endpoint?: string;
  model: string;
}

function claudeRequestMessages(messages: ChatMessage[]): {
  system: string;
  messages: Array<{ role: "user" | "assistant"; content: string }>;
} {
  const system = messages
    .filter((message) => message.role === "system")
    .map((message) => message.content)
    .join("\n\n")
    .trim();
  const conversation = messages
    .filter((message) => message.role !== "system")
    .map((message) => ({
      role: message.role === "assistant"
        ? "assistant" as const
        : "user" as const,
      content: message.content,
    }));
  return { system, messages: conversation };
}

/** Calls Claude and returns only assistant text. Provider bodies never leak. */
export async function callClaude(args: ClaudeArgs): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), args.timeoutMs);
  try {
    const prompt = claudeRequestMessages(args.messages);
    const isSonnet5 = args.model === CLAUDE_SONNET_MODEL;
    const response = await fetch(args.endpoint ?? CLAUDE_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": args.apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: args.model,
        max_tokens: args.maxTokens,
        ...(isSonnet5
          ? { thinking: { type: "disabled" } }
          : { temperature: args.temperature }),
        // Prompt caching：同一段 system 文字（byte-for-byte 不變）改包成
        // content-block 陣列掛 ephemeral cache_control；空 system 維持原樣
        // （Anthropic 拒絕空 text block）。
        system: prompt.system
          ? [{
            type: "text",
            text: prompt.system,
            cache_control: { type: "ephemeral" },
          }]
          : prompt.system,
        messages: prompt.messages,
        ...(args.outputJsonSchema
          ? {
            output_config: {
              format: {
                type: "json_schema",
                schema: args.outputJsonSchema,
              },
            },
          }
          : {}),
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      await response.text().catch(() => "");
      throw new Error(`claude_http_${response.status}`);
    }

    const json = await response.json();
    if (json?.stop_reason === "refusal") {
      throw new Error("claude_refusal");
    }
    if (json?.stop_reason === "max_tokens") {
      throw new Error("claude_max_tokens");
    }
    const blocks = Array.isArray(json?.content) ? json.content : [];
    const content = blocks
      .filter((block: unknown) =>
        typeof block === "object" && block !== null &&
        (block as { type?: unknown }).type === "text" &&
        typeof (block as { text?: unknown }).text === "string"
      )
      .map((block: { text: string }) => block.text)
      .join("")
      .trim();
    if (!content) throw new Error("claude_empty_content");
    return content;
  } catch (error) {
    if (
      (error instanceof DOMException && error.name === "AbortError") ||
      (error instanceof Error && error.name === "AbortError")
    ) {
      throw new Error("claude_timeout");
    }
    throw error instanceof Error ? error : new Error(String(error));
  } finally {
    clearTimeout(timeout);
  }
}

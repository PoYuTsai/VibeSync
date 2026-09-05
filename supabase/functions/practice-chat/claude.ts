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
  /**
   * Forced tool_use schema：帶了就強制模型呼叫該 tool，回傳值改為
   * tool_use input 的 JSON 字串（下游 parser 沿用「收字串」契約）。
   */
  forcedTool?: {
    name: string;
    description?: string;
    inputSchema: Readonly<Record<string, unknown>>;
  };
  endpoint?: string;
  model: string;
  /**
   * 這一次呼叫的 token 帳（provider 回的 `usage`）。只在**成功**取到內容時
   * 呼叫一次；不傳就完全不影響行為（hint／debrief 都不傳）。
   */
  onUsage?: (usage: ClaudeUsage) => void;
}

/** Anthropic `usage` 的四格（cache read／write 分開，才算得出真實成本）。 */
export interface ClaudeUsage {
  readonly inputTokens: number;
  readonly cacheReadInputTokens: number;
  readonly cacheCreationInputTokens: number;
  readonly outputTokens: number;
}

/**
 * `ChatMessage[]`（含 system）→ Claude 的 system／messages 形狀。
 * export 是為了讓黑箱 runner 與 production 共用同一份對映（Phase 4.4：
 * runner 原本自己抄了一份，兩邊會漂）。
 */
export function claudeRequestMessages(messages: ChatMessage[]): {
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
        ...(args.forcedTool
          ? {
            tools: [{
              name: args.forcedTool.name,
              ...(args.forcedTool.description
                ? { description: args.forcedTool.description }
                : {}),
              input_schema: args.forcedTool.inputSchema,
            }],
            tool_choice: { type: "tool", name: args.forcedTool.name },
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
    // Codex R1 P2：契約是「只在成功取到內容時呼叫一次」，所以必須放在 content
    // 解析與驗證**之後**——HTTP 200 但內容空／格式錯時 callback 一次都不能響。
    const emitUsage = () => {
      const u = json?.usage ?? {};
      args.onUsage?.({
        inputTokens: Number(u.input_tokens) || 0,
        cacheReadInputTokens: Number(u.cache_read_input_tokens) || 0,
        cacheCreationInputTokens: Number(u.cache_creation_input_tokens) || 0,
        outputTokens: Number(u.output_tokens) || 0,
      });
    };
    const blocks = Array.isArray(json?.content) ? json.content : [];
    if (args.forcedTool) {
      const toolBlock = blocks.find((block: unknown) =>
        typeof block === "object" && block !== null &&
        (block as { type?: unknown }).type === "tool_use" &&
        typeof (block as { input?: unknown }).input === "object" &&
        (block as { input?: unknown }).input !== null
      );
      if (!toolBlock) throw new Error("claude_no_tool_use");
      emitUsage();
      return JSON.stringify((toolBlock as { input: unknown }).input);
    }
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
    emitUsage();
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

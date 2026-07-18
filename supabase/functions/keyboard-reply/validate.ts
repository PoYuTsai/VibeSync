import { containsBannedToken } from "../_shared/banned_tokens.ts";
import {
  isValidKeyboardReplyRequestId,
  KEYBOARD_REPLY_STYLES,
  type KeyboardReplyStyle,
} from "./contract.ts";

export { KEYBOARD_REPLY_STYLES, type KeyboardReplyStyle } from "./contract.ts";

export interface KeyboardReplyRequest {
  message: string;
  style: KeyboardReplyStyle;
  requestId: string | null;
}

export function validateRequest(value: unknown): KeyboardReplyRequest {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_request_body");
  }
  const body = value as Record<string, unknown>;
  if (typeof body.message !== "string") throw new Error("invalid_message");
  const message = body.message.trim();
  if (message.length < 1 || message.length > 2000) {
    throw new Error("invalid_message_length");
  }
  if (
    typeof body.style !== "string" ||
    !KEYBOARD_REPLY_STYLES.includes(body.style as KeyboardReplyStyle)
  ) {
    throw new Error("invalid_style");
  }
  if (
    body.requestId !== undefined &&
    !isValidKeyboardReplyRequestId(body.requestId)
  ) {
    throw new Error("invalid_request_id");
  }
  return {
    message,
    style: body.style as KeyboardReplyStyle,
    requestId: typeof body.requestId === "string" ? body.requestId : null,
  };
}

export function parseAndValidateReply(value: unknown): string {
  if (!value || typeof value !== "object") throw new Error("schema_invalid");
  const envelope = value as {
    content?: Array<{ type?: string; text?: string }>;
    stop_reason?: string | null;
  };
  if (envelope.stop_reason === "max_tokens") throw new Error("max_tokens");
  if (envelope.stop_reason === "model_context_window_exceeded") {
    throw new Error("model_context_window_exceeded");
  }
  if (envelope.stop_reason === "refusal") throw new Error("model_refusal");
  let raw = (envelope.content ?? [])
    .filter((block) => block.type === undefined || block.type === "text")
    .map((block) => block.text ?? "")
    .join("")
    .trim();
  raw = raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("schema_invalid");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("schema_invalid");
  }
  const reply = (parsed as Record<string, unknown>).reply;
  if (typeof reply !== "string") throw new Error("schema_invalid");
  const normalized = reply.trim();
  if (normalized.length < 1 || normalized.length > 100) {
    throw new Error("reply_length_invalid");
  }
  if (/^[\[{]|```|"reply"\s*:/i.test(normalized)) {
    throw new Error("raw_model_payload");
  }
  const banned = containsBannedToken(normalized);
  if (banned != null) throw new Error("banned_token");
  return normalized;
}

export const KEYBOARD_ASSIST_CONTRACT_VERSION = "keyboard-assist-v1";

export const KEYBOARD_ASSIST_MEDIA_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
] as const;
export type KeyboardAssistMediaType =
  typeof KEYBOARD_ASSIST_MEDIA_TYPES[number];

export const KEYBOARD_ASSIST_SPEAKER_OVERRIDES = [
  "none",
  "left_is_me",
  "right_is_me",
] as const;
export type KeyboardAssistSpeakerOverride =
  typeof KEYBOARD_ASSIST_SPEAKER_OVERRIDES[number];

export const KEYBOARD_ASSIST_VOICES = [
  "steady",
  "direct",
  "humorous",
  "gentle",
  "playful",
] as const;
export type KeyboardAssistVoice = typeof KEYBOARD_ASSIST_VOICES[number];

export const KEYBOARD_ASSIST_CONFIDENCES = ["high", "medium", "low"] as const;
export type KeyboardAssistConfidence =
  typeof KEYBOARD_ASSIST_CONFIDENCES[number];

export const KEYBOARD_ASSIST_STRATEGIES = [
  "keep_pace",
  "build_connection",
  "move_forward",
  "clarify",
  "deescalate",
] as const;
export type KeyboardAssistStrategy = typeof KEYBOARD_ASSIST_STRATEGIES[number];

export const KEYBOARD_ASSIST_TURN_STATES = [
  "reply_due",
  "optional_follow_up",
] as const;
export type KeyboardAssistTurnState =
  typeof KEYBOARD_ASSIST_TURN_STATES[number];

export type KeyboardAssistV1Request = {
  contractVersion: typeof KEYBOARD_ASSIST_CONTRACT_VERSION;
  requestId: string;
  image: {
    mediaType: KeyboardAssistMediaType;
    data: string;
  };
  speakerOverride: KeyboardAssistSpeakerOverride;
  voice: {
    primary: KeyboardAssistVoice | null;
    secondary: KeyboardAssistVoice | null;
  };
};

export type KeyboardAssistReadyResult = {
  contractVersion: typeof KEYBOARD_ASSIST_CONTRACT_VERSION;
  status: "ready";
  source: {
    scope: "screenshot_only" | "screenshot_plus_global_voice";
    messageCount: number;
    confidence: KeyboardAssistConfidence;
    sideConfidence: KeyboardAssistConfidence;
  };
  turnState: KeyboardAssistTurnState;
  cue: string;
  uncertainty: string | null;
  options: Array<{
    strategy: KeyboardAssistStrategy;
    text: string;
    why: string;
    effect: string;
  }>;
};

export type KeyboardAssistSpeakerConfirmationResult = {
  contractVersion: typeof KEYBOARD_ASSIST_CONTRACT_VERSION;
  status: "needs_speaker_confirmation";
  suggestedMySide: "left" | "right";
  sideConfidence: "low";
};

export type KeyboardAssistLedgerResult =
  | KeyboardAssistReadyResult
  | KeyboardAssistSpeakerConfirmationResult;

export type KeyboardAssistResponse = KeyboardAssistLedgerResult & {
  requestId: string;
};

export type KeyboardAssistRetryDisposition =
  | "lookup_same_request"
  | "retry_same_payload"
  | "new_request_after_user_change"
  | "terminal_clear";

export const KEYBOARD_ASSIST_ERROR_CODES = [
  "invalid_request",
  "image_too_large",
  "unsupported_image",
  "unauthorized",
  "quota_exhausted",
  "model_rate_limited",
  "request_pending",
  "request_replay_mismatch",
  "request_not_found",
  "request_expired_no_charge",
  "unsupported_conversation",
  "provider_timeout",
  "provider_invalid_output",
  "settlement_uncertain",
  "service_unavailable",
] as const;
export type KeyboardAssistErrorCode =
  typeof KEYBOARD_ASSIST_ERROR_CODES[number];

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isValidKeyboardAssistRequestId(
  value: unknown,
): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

import {
  KEYBOARD_ASSIST_CONFIDENCES,
  KEYBOARD_ASSIST_STRATEGIES,
  KEYBOARD_ASSIST_TURN_STATES,
  type KeyboardAssistConfidence,
  type KeyboardAssistStrategy,
  type KeyboardAssistTurnState,
} from "./contract.ts";

export type NormalizedKeyboardAssistCompilerOutput = {
  conversationType: "chat" | "group" | "social_feed" | "non_chat";
  suggestedMySide: "left" | "right";
  sideConfidence: KeyboardAssistConfidence;
  confidence: KeyboardAssistConfidence;
  turnState: KeyboardAssistTurnState;
  cue: string;
  uncertainty: string | null;
  messages: Array<{
    index: number;
    side: "left" | "right";
    text: string;
  }>;
  candidates: Array<{
    strategy: KeyboardAssistStrategy;
    text: string;
    evidenceIndices: number[];
  }>;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(
  value: Record<string, unknown>,
  expected: readonly string[],
): boolean {
  const actual = Object.keys(value).sort();
  const canonical = [...expected].sort();
  return actual.length === canonical.length &&
    actual.every((key, index) => key === canonical[index]);
}

function boundedText(value: unknown, max: number): value is string {
  return typeof value === "string" && value.trim() === value &&
    [...value].length >= 1 && [...value].length <= max;
}

export function normalizeKeyboardAssistCompilerOutput(
  value: unknown,
): NormalizedKeyboardAssistCompilerOutput | null {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, [
      "conversationType",
      "suggestedMySide",
      "sideConfidence",
      "confidence",
      "turnState",
      "cue",
      "uncertainty",
      "messages",
      "candidates",
    ]) ||
    !["chat", "group", "social_feed", "non_chat"].includes(
      String(value.conversationType),
    ) ||
    !["left", "right"].includes(String(value.suggestedMySide)) ||
    !KEYBOARD_ASSIST_CONFIDENCES.includes(
      value.sideConfidence as KeyboardAssistConfidence,
    ) ||
    !KEYBOARD_ASSIST_CONFIDENCES.includes(
      value.confidence as KeyboardAssistConfidence,
    ) ||
    !KEYBOARD_ASSIST_TURN_STATES.includes(
      value.turnState as KeyboardAssistTurnState,
    ) ||
    !boundedText(value.cue, 120) ||
    !(value.uncertainty === null || boundedText(value.uncertainty, 120)) ||
    !Array.isArray(value.messages) ||
    value.messages.length > 40 ||
    !Array.isArray(value.candidates) ||
    value.candidates.length > 6
  ) return null;
  const isChat = value.conversationType === "chat";
  if (
    isChat &&
    (value.messages.length < 1 || value.candidates.length !== 6)
  ) return null;

  const messages: NormalizedKeyboardAssistCompilerOutput["messages"] = [];
  const seenIndices = new Set<number>();
  for (const message of value.messages) {
    if (
      !isRecord(message) ||
      !hasExactKeys(message, ["index", "side", "text"]) ||
      !Number.isInteger(message.index) ||
      (message.index as number) < 0 ||
      (message.index as number) > 99 ||
      seenIndices.has(message.index as number) ||
      !["left", "right"].includes(String(message.side)) ||
      !boundedText(message.text, 500)
    ) return null;
    seenIndices.add(message.index as number);
    messages.push({
      index: message.index as number,
      side: message.side as "left" | "right",
      text: message.text,
    });
  }

  const candidates: NormalizedKeyboardAssistCompilerOutput["candidates"] = [];
  for (const candidate of value.candidates) {
    if (
      !isRecord(candidate) ||
      !hasExactKeys(candidate, [
        "strategy",
        "text",
        "evidenceIndices",
      ]) ||
      !KEYBOARD_ASSIST_STRATEGIES.includes(
        candidate.strategy as KeyboardAssistStrategy,
      ) ||
      !boundedText(candidate.text, 100) ||
      !Array.isArray(candidate.evidenceIndices) ||
      candidate.evidenceIndices.length < 1 ||
      candidate.evidenceIndices.length > 8 ||
      !candidate.evidenceIndices.every((index) =>
        Number.isInteger(index) && (index as number) >= 0
      )
    ) return null;
    candidates.push({
      strategy: candidate.strategy as KeyboardAssistStrategy,
      text: candidate.text,
      evidenceIndices: [...new Set(candidate.evidenceIndices as number[])],
    });
  }

  return {
    conversationType: value
      .conversationType as NormalizedKeyboardAssistCompilerOutput[
        "conversationType"
      ],
    suggestedMySide: value.suggestedMySide as "left" | "right",
    sideConfidence: value.sideConfidence as KeyboardAssistConfidence,
    confidence: value.confidence as KeyboardAssistConfidence,
    turnState: value.turnState as KeyboardAssistTurnState,
    cue: value.cue,
    uncertainty: value.uncertainty as string | null,
    messages,
    candidates,
  };
}

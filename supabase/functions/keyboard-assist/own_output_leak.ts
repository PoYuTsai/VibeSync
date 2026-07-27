import type { KeyboardAssistPriorTurn } from "./contract.ts";
import type { NormalizedKeyboardAssistCompilerOutput } from "./normalize.ts";

/// Short fragments collide by accident ("好啊", "嗯嗯"), so an overlap only
/// counts once it is long enough to be a real sentence rather than a greeting.
const MINIMUM_OVERLAP_CODE_POINTS = 8;

function compact(value: string): string {
  return value.normalize("NFKC").replace(/\s+/gu, "");
}

function codePointLength(value: string): number {
  return [...value].length;
}

function overlaps(left: string, right: string): boolean {
  return left.includes(right) || right.includes(left);
}

/**
 * Detects our own previous suggestions being read back as conversation.
 *
 * The keyboard trims its own panel out of the capture before uploading, but a
 * geometry mismatch can leave a sliver of the previous candidates behind. A
 * suggestion the user actually sent is a legitimate part of the chat and must
 * be kept — it is the strongest signal that the previous turn landed. Any other
 * prior candidate showing up as a message means the transcript describes our
 * own UI, so the whole result is untrustworthy and no charge may be taken for
 * it.
 */
export function containsOwnPriorCandidates(
  normalized: NormalizedKeyboardAssistCompilerOutput,
  priorTurn: KeyboardAssistPriorTurn | null,
): boolean {
  if (priorTurn === null) return false;
  const sent = priorTurn.insertedText === null
    ? null
    : compact(priorTurn.insertedText);
  const leakable = priorTurn.offeredTexts
    .map(compact)
    .filter((text) =>
      text !== sent && codePointLength(text) >= MINIMUM_OVERLAP_CODE_POINTS
    );
  if (leakable.length === 0) return false;

  return normalized.messages.some((message) => {
    const text = compact(message.text);
    if (codePointLength(text) < MINIMUM_OVERLAP_CODE_POINTS) return false;
    if (sent !== null && overlaps(text, sent)) return false;
    return leakable.some((candidate) => overlaps(candidate, text));
  });
}

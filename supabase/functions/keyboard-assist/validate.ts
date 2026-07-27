import {
  isValidKeyboardAssistRequestId,
  KEYBOARD_ASSIST_CONFIDENCES,
  KEYBOARD_ASSIST_CONTRACT_VERSION,
  KEYBOARD_ASSIST_MAX_PRIOR_OFFERED_TEXTS,
  KEYBOARD_ASSIST_MAX_PRIOR_TEXT_LENGTH,
  KEYBOARD_ASSIST_MEDIA_TYPES,
  KEYBOARD_ASSIST_SPEAKER_OVERRIDES,
  KEYBOARD_ASSIST_STRATEGIES,
  KEYBOARD_ASSIST_TURN_STATES,
  KEYBOARD_ASSIST_VOICES,
  type KeyboardAssistErrorCode,
  type KeyboardAssistLedgerResult,
  type KeyboardAssistMediaType,
  type KeyboardAssistReadyResult,
  type KeyboardAssistStrategy,
  type KeyboardAssistV1Request,
  type KeyboardAssistVoice,
} from "./contract.ts";

export const KEYBOARD_ASSIST_MAX_IMAGE_BYTES = 900 * 1024;
export const KEYBOARD_ASSIST_MAX_DIMENSION = 8192;
export const KEYBOARD_ASSIST_MAX_PIXELS = 20_000_000;

export class KeyboardAssistValidationError extends Error {
  constructor(
    public readonly code: KeyboardAssistErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "KeyboardAssistValidationError";
  }
}

type ImageDimensions = { width: number; height: number };

export type ValidatedKeyboardAssistRequest = {
  request: KeyboardAssistV1Request;
  imageBytes: Uint8Array;
  imageDimensions: ImageDimensions;
};

export function unicodeCodePointLength(value: string): number {
  return [...value].length;
}

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

/// Same strictness as `hasExactKeys` for everything required, while letting a
/// named additive field be absent. A keyboard build that predates the field
/// keeps working; anything unrecognised is still rejected.
function hasExactKeysAllowingOptional(
  value: Record<string, unknown>,
  required: readonly string[],
  optional: readonly string[],
): boolean {
  const actual = Object.keys(value);
  const allowed = new Set([...required, ...optional]);
  if (actual.some((key) => !allowed.has(key))) return false;
  return required.every((key) => actual.includes(key));
}

function invalid(message: string): never {
  throw new KeyboardAssistValidationError("invalid_request", message);
}

function decodeStrictBase64(data: unknown): Uint8Array {
  if (
    typeof data !== "string" || data.length === 0 || data.length % 4 !== 0 ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/
      .test(data)
  ) {
    throw new KeyboardAssistValidationError(
      "unsupported_image",
      "image.data must be canonical base64",
    );
  }
  try {
    const binary = atob(data);
    if (btoa(binary) !== data) {
      throw new Error("non-canonical base64");
    }
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    if (bytes.length > KEYBOARD_ASSIST_MAX_IMAGE_BYTES) {
      throw new KeyboardAssistValidationError(
        "image_too_large",
        "decoded image exceeds 900 KiB",
      );
    }
    return bytes;
  } catch (error) {
    if (error instanceof KeyboardAssistValidationError) throw error;
    throw new KeyboardAssistValidationError(
      "unsupported_image",
      "image.data is not valid base64",
    );
  }
}

function readUint16Be(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

function readUint24Le(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16);
}

function readUint32Be(bytes: Uint8Array, offset: number): number {
  return ((bytes[offset] << 24) | (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) | bytes[offset + 3]) >>> 0;
}

function sniffPng(bytes: Uint8Array): ImageDimensions | null {
  if (
    bytes.length < 24 ||
    ![137, 80, 78, 71, 13, 10, 26, 10].every((b, i) => bytes[i] === b) ||
    String.fromCharCode(...bytes.slice(12, 16)) !== "IHDR"
  ) return null;
  return {
    width: readUint32Be(bytes, 16),
    height: readUint32Be(bytes, 20),
  };
}

function sniffJpeg(bytes: Uint8Array): ImageDimensions | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) return null;
    while (bytes[offset] === 0xff) offset++;
    const marker = bytes[offset++];
    if (marker === 0xd8 || marker === 0x01) continue;
    if (marker === 0xd9 || marker === 0xda) break;
    if (offset + 2 > bytes.length) return null;
    const segmentLength = readUint16Be(bytes, offset);
    if (segmentLength < 2 || offset + segmentLength > bytes.length) return null;
    const isStartOfFrame = marker >= 0xc0 && marker <= 0xcf &&
      ![0xc4, 0xc8, 0xcc].includes(marker);
    if (isStartOfFrame) {
      if (segmentLength < 7) return null;
      return {
        height: readUint16Be(bytes, offset + 3),
        width: readUint16Be(bytes, offset + 5),
      };
    }
    offset += segmentLength;
  }
  return null;
}

function sniffWebp(bytes: Uint8Array): ImageDimensions | null {
  if (
    bytes.length < 30 ||
    String.fromCharCode(...bytes.slice(0, 4)) !== "RIFF" ||
    String.fromCharCode(...bytes.slice(8, 12)) !== "WEBP"
  ) return null;
  const chunk = String.fromCharCode(...bytes.slice(12, 16));
  if (chunk === "VP8X") {
    return {
      width: 1 + readUint24Le(bytes, 24),
      height: 1 + readUint24Le(bytes, 27),
    };
  }
  if (
    chunk === "VP8 " && bytes.length >= 30 &&
    bytes[23] === 0x9d && bytes[24] === 0x01 && bytes[25] === 0x2a
  ) {
    return {
      width: (bytes[26] | (bytes[27] << 8)) & 0x3fff,
      height: (bytes[28] | (bytes[29] << 8)) & 0x3fff,
    };
  }
  if (chunk === "VP8L" && bytes[20] === 0x2f && bytes.length >= 25) {
    const bits = (bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) |
      (bytes[24] << 24)) >>> 0;
    return {
      width: (bits & 0x3fff) + 1,
      height: ((bits >>> 14) & 0x3fff) + 1,
    };
  }
  return null;
}

function sniffDimensions(
  bytes: Uint8Array,
  mediaType: KeyboardAssistMediaType,
): ImageDimensions {
  const dimensions = mediaType === "image/png"
    ? sniffPng(bytes)
    : mediaType === "image/jpeg"
    ? sniffJpeg(bytes)
    : sniffWebp(bytes);
  if (!dimensions) {
    throw new KeyboardAssistValidationError(
      "unsupported_image",
      "declared image MIME does not match decodable bytes",
    );
  }
  const { width, height } = dimensions;
  if (
    !Number.isInteger(width) || !Number.isInteger(height) ||
    width < 1 || height < 1 || width > KEYBOARD_ASSIST_MAX_DIMENSION ||
    height > KEYBOARD_ASSIST_MAX_DIMENSION ||
    width * height > KEYBOARD_ASSIST_MAX_PIXELS
  ) {
    throw new KeyboardAssistValidationError(
      "unsupported_image",
      "image dimensions exceed the supported bounds",
    );
  }
  return dimensions;
}

function parseVoice(value: unknown): KeyboardAssistV1Request["voice"] {
  if (!isRecord(value) || !hasExactKeys(value, ["primary", "secondary"])) {
    return invalid("voice must contain explicit primary and secondary fields");
  }
  const validVoice = (voice: unknown): voice is KeyboardAssistVoice | null =>
    voice === null ||
    typeof voice === "string" &&
      KEYBOARD_ASSIST_VOICES.includes(voice as KeyboardAssistVoice);
  if (!validVoice(value.primary) || !validVoice(value.secondary)) {
    return invalid("voice is outside the bounded enum");
  }
  if (value.primary === null && value.secondary !== null) {
    return invalid("secondary voice requires a primary voice");
  }
  if (value.primary !== null && value.primary === value.secondary) {
    return invalid("primary and secondary voice must be different");
  }
  return {
    primary: value.primary,
    secondary: value.secondary,
  };
}

export function validateKeyboardAssistRequest(
  value: unknown,
): ValidatedKeyboardAssistRequest {
  if (
    !isRecord(value) ||
    !hasExactKeysAllowingOptional(
      value,
      [
        "contractVersion",
        "requestId",
        "image",
        "speakerOverride",
        "voice",
      ],
      ["priorTurn"],
    )
  ) return invalid("request must use the exact v1 shape");
  if (value.contractVersion !== KEYBOARD_ASSIST_CONTRACT_VERSION) {
    return invalid("unsupported contractVersion");
  }
  if (!isValidKeyboardAssistRequestId(value.requestId)) {
    return invalid("requestId must be a UUID");
  }
  if (
    typeof value.speakerOverride !== "string" ||
    !KEYBOARD_ASSIST_SPEAKER_OVERRIDES.includes(
      value.speakerOverride as KeyboardAssistV1Request["speakerOverride"],
    )
  ) return invalid("speakerOverride is outside the bounded enum");
  if (
    !isRecord(value.image) ||
    !hasExactKeys(value.image, ["mediaType", "data"]) ||
    typeof value.image.mediaType !== "string" ||
    !KEYBOARD_ASSIST_MEDIA_TYPES.includes(
      value.image.mediaType as KeyboardAssistMediaType,
    )
  ) return invalid("image must contain one supported mediaType and data");

  const voice = parseVoice(value.voice);
  const priorTurn = parsePriorTurn(value.priorTurn);
  const imageBytes = decodeStrictBase64(value.image.data);
  const mediaType = value.image.mediaType as KeyboardAssistMediaType;
  const imageDimensions = sniffDimensions(imageBytes, mediaType);
  return {
    request: {
      contractVersion: KEYBOARD_ASSIST_CONTRACT_VERSION,
      requestId: value.requestId,
      image: {
        mediaType,
        data: value.image.data as string,
      },
      speakerOverride: value.speakerOverride as KeyboardAssistV1Request[
        "speakerOverride"
      ],
      voice,
      priorTurn,
    },
    imageBytes,
    imageDimensions,
  };
}

function parsePriorTurn(
  value: unknown,
): KeyboardAssistV1Request["priorTurn"] {
  if (value === undefined || value === null) return null;
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["offeredTexts", "insertedText"]) ||
    !Array.isArray(value.offeredTexts) ||
    value.offeredTexts.length < 1 ||
    value.offeredTexts.length > KEYBOARD_ASSIST_MAX_PRIOR_OFFERED_TEXTS
  ) return invalid("priorTurn must use the exact bounded shape");

  const offeredTexts: string[] = [];
  for (const text of value.offeredTexts) {
    if (
      !hasBoundedText(text, 1, KEYBOARD_ASSIST_MAX_PRIOR_TEXT_LENGTH) ||
      offeredTexts.includes(text)
    ) return invalid("priorTurn.offeredTexts must be bounded and unique");
    offeredTexts.push(text);
  }

  const insertedText = value.insertedText;
  if (insertedText === null) return { offeredTexts, insertedText: null };
  if (
    !hasBoundedText(
      insertedText,
      1,
      KEYBOARD_ASSIST_MAX_PRIOR_TEXT_LENGTH,
    ) ||
    // The inserted line is the one candidate allowed to reappear as a real
    // message, so it may only name something we actually offered.
    !offeredTexts.includes(insertedText)
  ) return invalid("priorTurn.insertedText must be one of offeredTexts");
  return { offeredTexts, insertedText };
}

function hasBoundedText(
  value: unknown,
  min: number,
  max: number,
): value is string {
  if (typeof value !== "string" || value.trim() !== value) return false;
  const length = unicodeCodePointLength(value);
  return length >= min && length <= max;
}

const DISALLOWED_GENERATED_PATTERN =
  /```|(?:^|\s)[#>*_]{1,3}|(?:^|\n)\s*[-+]\s|[%％]|好感度|心理診斷|依附型態|人格分析/u;

function isSafeGeneratedText(
  value: unknown,
  min: number,
  max: number,
): value is string {
  return hasBoundedText(value, min, max) &&
    !DISALLOWED_GENERATED_PATTERN.test(value);
}

function isReadyResult(
  result: Record<string, unknown>,
): result is KeyboardAssistReadyResult {
  if (
    !hasExactKeys(result, [
      "contractVersion",
      "status",
      "source",
      "turnState",
      "cue",
      "uncertainty",
      "options",
    ]) ||
    !isRecord(result.source) ||
    !hasExactKeys(result.source, [
      "scope",
      "messageCount",
      "confidence",
      "sideConfidence",
    ]) ||
    !["screenshot_only", "screenshot_plus_global_voice"].includes(
      String(result.source.scope),
    ) ||
    !Number.isInteger(result.source.messageCount) ||
    (result.source.messageCount as number) < 1 ||
    (result.source.messageCount as number) > 100 ||
    !KEYBOARD_ASSIST_CONFIDENCES.includes(
      result.source.confidence as (typeof KEYBOARD_ASSIST_CONFIDENCES)[number],
    ) ||
    !KEYBOARD_ASSIST_CONFIDENCES.includes(
      result.source
        .sideConfidence as (typeof KEYBOARD_ASSIST_CONFIDENCES)[number],
    ) ||
    !KEYBOARD_ASSIST_TURN_STATES.includes(
      result.turnState as (typeof KEYBOARD_ASSIST_TURN_STATES)[number],
    ) ||
    !isSafeGeneratedText(result.cue, 1, 120) ||
    !(result.uncertainty === null ||
      isSafeGeneratedText(result.uncertainty, 1, 120)) ||
    !Array.isArray(result.options) ||
    result.options.length !== 3
  ) return false;

  const strategies = new Set<KeyboardAssistStrategy>();
  for (const option of result.options) {
    if (
      !isRecord(option) ||
      !hasExactKeys(option, ["strategy", "text", "why", "effect"]) ||
      !KEYBOARD_ASSIST_STRATEGIES.includes(
        option.strategy as KeyboardAssistStrategy,
      ) ||
      !isSafeGeneratedText(option.text, 1, 100) ||
      !isSafeGeneratedText(option.why, 1, 80) ||
      !isSafeGeneratedText(option.effect, 1, 60)
    ) return false;
    strategies.add(option.strategy as KeyboardAssistStrategy);
  }
  return strategies.size === 3;
}

export function validateKeyboardAssistLedgerResult(
  value: unknown,
): value is KeyboardAssistLedgerResult {
  if (
    !isRecord(value) ||
    value.contractVersion !== KEYBOARD_ASSIST_CONTRACT_VERSION ||
    typeof value.status !== "string"
  ) return false;
  if (value.status === "ready") return isReadyResult(value);
  if (value.status === "needs_speaker_confirmation") {
    return hasExactKeys(value, [
      "contractVersion",
      "status",
      "suggestedMySide",
      "sideConfidence",
    ]) &&
      (value.suggestedMySide === "left" ||
        value.suggestedMySide === "right") &&
      value.sideConfidence === "low";
  }
  return false;
}

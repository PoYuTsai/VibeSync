import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  KEYBOARD_ASSIST_CONTRACT_VERSION,
  KEYBOARD_ASSIST_SPEAKER_OVERRIDES,
  KEYBOARD_ASSIST_VOICES,
} from "./contract.ts";
import {
  KeyboardAssistValidationError,
  validateKeyboardAssistRequest,
} from "./validate.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
// 1 x 1 transparent PNG.
const PNG_DATA =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";

function validRequest() {
  return {
    contractVersion: "keyboard-assist-v1",
    requestId: REQUEST_ID,
    image: {
      mediaType: "image/png",
      data: PNG_DATA,
    },
    speakerOverride: "none",
    voice: {
      primary: "steady",
      secondary: null,
    },
  };
}

Deno.test("keyboard assist freezes the public v1 enums", () => {
  assertEquals(KEYBOARD_ASSIST_CONTRACT_VERSION, "keyboard-assist-v1");
  assertEquals(KEYBOARD_ASSIST_SPEAKER_OVERRIDES, [
    "none",
    "left_is_me",
    "right_is_me",
  ]);
  assertEquals(KEYBOARD_ASSIST_VOICES, [
    "steady",
    "direct",
    "humorous",
    "gentle",
    "playful",
  ]);
});

Deno.test("keyboard assist accepts exactly one strict image contract", () => {
  const parsed = validateKeyboardAssistRequest(validRequest());
  assertEquals(parsed.request.requestId, REQUEST_ID);
  assertEquals(parsed.request.image.mediaType, "image/png");
  assertEquals(parsed.imageBytes.length > 0, true);
  assertEquals(parsed.imageDimensions, { width: 1, height: 1 });
});

Deno.test("prior turn is additive and defaults to absent", () => {
  // A keyboard build that predates the field must keep working.
  assertEquals(validateKeyboardAssistRequest(validRequest()).request.priorTurn, null);
  assertEquals(
    validateKeyboardAssistRequest({ ...validRequest(), priorTurn: null })
      .request.priorTurn,
    null,
  );

  const offered = ["那我把八月十五那天空下來", "熱氣球我一直都很想去看看"];
  const accepted = validateKeyboardAssistRequest({
    ...validRequest(),
    priorTurn: { offeredTexts: offered, insertedText: offered[0] },
  });
  assertEquals(accepted.request.priorTurn, {
    offeredTexts: offered,
    insertedText: offered[0],
  });
});

Deno.test("prior turn stays bounded and self-consistent", () => {
  const offered = ["那我把八月十五那天空下來"];
  assertValidationCode(
    { ...validRequest(), priorTurn: { offeredTexts: offered } },
    "invalid_request",
  );
  assertValidationCode(
    { ...validRequest(), priorTurn: { offeredTexts: [], insertedText: null } },
    "invalid_request",
  );
  assertValidationCode(
    {
      ...validRequest(),
      priorTurn: { offeredTexts: [...offered, ...offered], insertedText: null },
    },
    "invalid_request",
  );
  assertValidationCode(
    {
      ...validRequest(),
      priorTurn: {
        offeredTexts: Array.from({ length: 7 }, (_, index) => `候選${index}`),
        insertedText: null,
      },
    },
    "invalid_request",
  );
  assertValidationCode(
    { ...validRequest(), priorTurn: { offeredTexts: offered, insertedText: "沒提供過的句子" } },
    "invalid_request",
  );
  assertValidationCode(
    {
      ...validRequest(),
      priorTurn: { offeredTexts: ["a".repeat(101)], insertedText: null },
    },
    "invalid_request",
  );
});

Deno.test("keyboard assist rejects omitted nullable fields and hidden context", () => {
  const missingSecondary = validRequest() as Record<string, unknown>;
  missingSecondary.voice = { primary: "steady" };
  assertValidationCode(missingSecondary, "invalid_request");

  assertValidationCode(
    { ...validRequest(), messages: [{ text: "secret history" }] },
    "invalid_request",
  );
  assertValidationCode(
    { ...validRequest(), partnerSummary: "not allowed in v1" },
    "invalid_request",
  );
  assertValidationCode(
    { ...validRequest(), images: [validRequest().image] },
    "invalid_request",
  );
});

Deno.test("keyboard assist enforces bounded voice and speaker enums", () => {
  assertValidationCode(
    { ...validRequest(), speakerOverride: "auto" },
    "invalid_request",
  );
  assertValidationCode(
    { ...validRequest(), voice: { primary: "romantic", secondary: null } },
    "invalid_request",
  );
  assertValidationCode(
    {
      ...validRequest(),
      voice: { primary: "steady", secondary: "steady" },
    },
    "invalid_request",
  );
  const noVoice = validateKeyboardAssistRequest({
    ...validRequest(),
    voice: { primary: null, secondary: null },
  });
  assertEquals(noVoice.request.voice.primary, null);
  assertValidationCode(
    {
      ...validRequest(),
      voice: { primary: null, secondary: "gentle" },
    },
    "invalid_request",
  );
});

Deno.test("keyboard assist uses strict base64 and verifies the declared MIME", () => {
  assertValidationCode(
    {
      ...validRequest(),
      image: { mediaType: "image/png", data: `${PNG_DATA}\n` },
    },
    "unsupported_image",
  );
  assertValidationCode(
    {
      ...validRequest(),
      image: { mediaType: "image/jpeg", data: PNG_DATA },
    },
    "unsupported_image",
  );
});

function assertValidationCode(value: unknown, expected: string) {
  const error = assertThrows(
    () => validateKeyboardAssistRequest(value),
    KeyboardAssistValidationError,
  );
  assertEquals(error.code, expected);
}

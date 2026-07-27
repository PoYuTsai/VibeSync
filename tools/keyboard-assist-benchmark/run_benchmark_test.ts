import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildAssistRequest,
  mimeTypeForPath,
  parseBenchmarkArgs,
  validateCaseDefinition,
} from "./run_benchmark.ts";

Deno.test("buildAssistRequest emits only the frozen v1 screenshot contract", () => {
  const request = buildAssistRequest({
    requestId: "550e8400-e29b-41d4-a716-446655440000",
    imageBytes: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
    mediaType: "image/jpeg",
    speakerOverride: "none",
    voice: { primary: "steady", secondary: null },
  });

  assertEquals(Object.keys(request).sort(), [
    "contractVersion",
    "image",
    "requestId",
    "speakerOverride",
    "voice",
  ]);
  assertEquals(request.contractVersion, "keyboard-assist-v1");
  assertEquals(request.image.mediaType, "image/jpeg");
  assertEquals(request.image.data, "/9j/2Q==");
  assertEquals(request.voice, { primary: "steady", secondary: null });
});

Deno.test("validateCaseDefinition rejects hidden context and missing local image", () => {
  assertEquals(
    validateCaseDefinition({
      id: "safe-case",
      suite: "synthetic",
      imageFile: "../ocr-golden/synthetic/mid-light.png",
      repetitions: 3,
      speakerOverride: "none",
      voice: { primary: "steady", secondary: null },
      forbiddenSubstrings: [],
      quotedPreviewInstances: 0,
    }),
    [],
  );

  const issues = validateCaseDefinition({
    id: "unsafe-case",
    suite: "real",
    imageFile: "",
    repetitions: 1,
    speakerOverride: "none",
    voice: { primary: "steady", secondary: null },
    partnerSummary: "must never enter v1",
  });

  assert(issues.includes("image_file_required"));
  assert(issues.includes("additional_property:partnerSummary"));
});

Deno.test("mimeTypeForPath supports only the contract image types", async () => {
  assertEquals(mimeTypeForPath("case.jpg"), "image/jpeg");
  assertEquals(mimeTypeForPath("case.PNG"), "image/png");
  assertEquals(mimeTypeForPath("case.webp"), "image/webp");
  assertThrows(
    () => mimeTypeForPath("case.gif"),
    Error,
    "unsupported benchmark image extension",
  );
});

Deno.test("parseBenchmarkArgs requires explicit endpoint and never accepts token on CLI", () => {
  const args = parseBenchmarkArgs([
    "--endpoint",
    "http://127.0.0.1:54321/functions/v1/keyboard-assist",
    "--manifest",
    "cases/synthetic.json",
    "--out",
    "results",
  ]);

  assertEquals(
    args.endpoint,
    "http://127.0.0.1:54321/functions/v1/keyboard-assist",
  );
  assertEquals(args.manifests, ["cases/synthetic.json"]);
  assertEquals(args.outDir, "results");
  assertThrows(
    () =>
      parseBenchmarkArgs([
        "--endpoint",
        "https://example.invalid",
        "--token",
        "secret",
      ]),
    Error,
    "token must be supplied through KEYBOARD_ASSIST_TOKEN",
  );
});

import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { sanitizeKeyboardAssistTelemetry } from "./telemetry.ts";

Deno.test("keyboard assist telemetry is scalar allowlist only", () => {
  const sanitized = sanitizeKeyboardAssistTelemetry({
    event: "keyboard_assist_succeeded",
    contractVersion: "keyboard-assist-v1",
    pipelineVersion: "compiler-only-v1",
    cohort: "internal",
    imageBytesBucket: "250-500K",
    dimensionClass: "phone",
    compilerMs: 8000,
    // The second stage is gone; a stray reading from it must not survive.
    judgeMs: 3000,
    totalMs: 12000,
    status: "ready",
    replay: false,
    image: "base64-private",
    imageHash: "private",
    prompt: "private",
    messages: ["private"],
    transcript: "private",
    reply: "private",
    contactName: "private",
  });
  assertEquals(sanitized, {
    event: "keyboard_assist_succeeded",
    contractVersion: "keyboard-assist-v1",
    pipelineVersion: "compiler-only-v1",
    cohort: "internal",
    imageBytesBucket: "250-500K",
    dimensionClass: "phone",
    compilerMs: 8000,
    totalMs: 12000,
    status: "ready",
    replay: false,
  });
  const wire = JSON.stringify(sanitized);
  for (
    const forbidden of [
      "base64-private",
      "imageHash",
      "prompt",
      "messages",
      "transcript",
      "reply",
      "contactName",
    ]
  ) {
    assertFalse(wire.includes(forbidden));
  }
});

Deno.test("keyboard assist telemetry keeps the rejection detail token", () => {
  assertEquals(
    sanitizeKeyboardAssistTelemetry({
      event: "keyboard_assist_failed",
      status: "failed",
      errorCode: "unsupported_conversation",
      rejectDetail: "own_prior_candidates",
    }),
    {
      event: "keyboard_assist_failed",
      status: "failed",
      errorCode: "unsupported_conversation",
      rejectDetail: "own_prior_candidates",
    },
  );
});

Deno.test("keyboard assist telemetry drops a rejection detail outside the allowlist", () => {
  const sanitized = sanitizeKeyboardAssistTelemetry({
    event: "keyboard_assist_failed",
    status: "failed",
    errorCode: "unsupported_conversation",
    // A free-text reason could carry transcript content, so only the fixed
    // tokens survive.
    rejectDetail: "他昨天說要約週末",
  });
  assertEquals(sanitized, {
    event: "keyboard_assist_failed",
    status: "failed",
    errorCode: "unsupported_conversation",
  });
});

Deno.test("keyboard assist telemetry drops arbitrary objects and non-finite values", () => {
  assertEquals(
    sanitizeKeyboardAssistTelemetry({
      event: "keyboard_assist_failed",
      status: "failed",
      totalMs: Number.POSITIVE_INFINITY,
      provider: { secret: true },
      errorCode: "provider_timeout",
    }),
    {
      event: "keyboard_assist_failed",
      status: "failed",
      errorCode: "provider_timeout",
    },
  );
});

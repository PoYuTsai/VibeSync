import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("keyboard assist index is JWT-authenticated and flag-off by default", () => {
  assert(source.includes("client.auth.getUser"));
  assert(source.includes('Deno.env.get("KEYBOARD_SCREENSHOT_V1_ENABLED")'));
  assert(source.includes('=== "true"'));
  assert(source.includes("createKeyboardAssistHandler"));
  assert(!source.includes("analyze-chat/"));
});

Deno.test("keyboard assist index wires versioned ledger and image-free status", () => {
  assert(source.includes('.from("keyboard_assist_requests")'));
  assert(source.includes("claimKeyboardAssistRequest"));
  assert(source.includes("renewKeyboardAssistClaim"));
  assert(source.includes("releaseKeyboardAssistClaim"));
  assert(source.includes("settleKeyboardAssistRequest"));
  assert(source.includes("expireKeyboardAssistRequest"));
  assert(source.includes("keyboard_assist_contract_version"));
  assert(source.includes("keyboard_assist_hmac_key_versions"));
});

Deno.test("keyboard assist index keeps quota, rate, and provider identities distinct", () => {
  assert(source.includes("checkQuota({"));
  assert(source.includes('scope: "keyboard_assist"'));
  assert(source.includes("createAnthropicKeyboardAssistProvider"));
  assert(source.includes("runKeyboardAssistPipeline"));
  assert(source.includes("KEYBOARD_ASSIST_COMPILER_MODEL"));
  assert(source.includes("KEYBOARD_ASSIST_JUDGE_MODEL"));
  assert(source.includes("KEYBOARD_SCREENSHOT_PIPELINE_VERSION"));
  assert(source.includes("KEYBOARD_ASSIST_HMAC_KEYS_JSON"));
  assert(source.includes("KEYBOARD_ASSIST_HMAC_CURRENT_VERSION"));
  assert(source.includes("recordTelemetry"));
  assert(source.includes("keyboard_assist_telemetry"));
});

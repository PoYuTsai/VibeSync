import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const genericDeployWorkflow = await Deno.readTextFile(
  new URL(
    "../../../.github/workflows/deploy-edge-function.yml",
    import.meta.url,
  ),
);
const secretPreflight = await Deno.readTextFile(
  new URL(
    "../../../tools/preflight/check-supabase-secrets.ps1",
    import.meta.url,
  ),
);
const supabaseConfig = await Deno.readTextFile(
  new URL("../../config.toml", import.meta.url),
);

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
  // One call, so one model to negotiate. A leftover judge-model requirement
  // would fail capability negotiation closed over a stage that no longer runs.
  assert(!source.includes("KEYBOARD_ASSIST_JUDGE_MODEL"));
  assert(source.includes("KEYBOARD_SCREENSHOT_PIPELINE_VERSION"));
  assert(source.includes("KEYBOARD_ASSIST_HMAC_KEYS_JSON"));
  assert(source.includes("KEYBOARD_ASSIST_HMAC_CURRENT_VERSION"));
  assert(source.includes("recordTelemetry"));
  assert(source.includes("keyboard_assist_telemetry"));
  assert(source.includes('Deno.env.get("CLAUDE_API_KEY")'));
  assert(!source.includes('Deno.env.get("ANTHROPIC_API_KEY")'));
  assert(source.includes('Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")'));
  assert(source.includes('KEYBOARD_ASSIST_MODEL_ID = "claude-sonnet-5"'));
  assert(
    source.includes(
      "KEYBOARD_ASSIST_COMPILER_MODEL === KEYBOARD_ASSIST_MODEL_ID",
    ),
  );
  // The stored result's ledger key carries the pipeline that produced it, so a
  // two-stage result cannot be replayed as a one-stage one.
  assert(source.includes('"compiler-only-v1"'));
});

Deno.test("keyboard assist stays migration-gated and release preflight checks its config", () => {
  assert(
    genericDeployWorkflow.includes(
      "- '!supabase/functions/keyboard-assist/**'",
    ),
  );
  assert(
    !genericDeployWorkflow.includes(
      "- '.github/workflows/deploy-edge-function.yml'",
    ),
  );
  const functionConfig = supabaseConfig.match(
    /\[functions\.keyboard-assist\]([\s\S]*?)(?=\n\[|$)/,
  )?.[1];
  assert(
    functionConfig == null ||
      !/verify_jwt\s*=\s*false/.test(functionConfig),
  );
  for (
    const secret of [
      "KEYBOARD_ASSIST_COMPILER_MODEL",
      "KEYBOARD_ASSIST_HMAC_CURRENT_VERSION",
      "KEYBOARD_ASSIST_HMAC_KEYS_JSON",
      "KEYBOARD_SCREENSHOT_PIPELINE_VERSION",
      "KEYBOARD_SCREENSHOT_V1_ALLOWLIST",
      "KEYBOARD_SCREENSHOT_V1_ENABLED",
    ]
  ) {
    assert(secretPreflight.includes(`"${secret}"`));
  }
  // The judge stage is gone. Keeping its model in the required list makes
  // preflight fail on a healthy project and tempts whoever hits it to re-create
  // a secret nothing reads.
  assert(!secretPreflight.includes("KEYBOARD_ASSIST_JUDGE_MODEL"));
});

Deno.test("批 B：keyboard-assist 訪客接線（免重置＋訪客 limits＋訪客文案）", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assert(source.includes("user.isAnonymous === true"));
  assert(source.includes("? noResetResult(sub)"));
  assert(!source.includes("resolveLimits(sub.tier);"));
  assert(source.includes("resolveLimits(sub.tier, { anonymous })"));
  assert(source.includes("quotaExceededMessage(gate.reason, anonymous)"));
  assert(source.includes("isAnonymousAuthUser(data.user)"));
});

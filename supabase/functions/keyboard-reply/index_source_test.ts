import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

Deno.test("index preserves auth, replay, claim, quota, and settlement ordering", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assert(source.includes("client.auth.getUser"));
  assert(source.includes("checkQuota({"));
  assert(source.includes('scope: "keyboard_reply"'));
  assert(source.includes('.from("keyboard_reply_requests")'));
  assert(source.includes("keyboardReplyReplayCutoffIso()"));
  assert(source.includes("claimKeyboardReplyRequest({"));
  assert(source.includes("releaseKeyboardReplyClaim({"));
  assert(source.includes("settleKeyboardReplyRequest({"));
  assert(source.includes('client.rpc("increment_usage"'));
  assert(
    source.indexOf('.from("keyboard_reply_requests")') <
      source.indexOf("checkQuota({"),
  );
  const claim = source.indexOf(
    "const claim = await claimKeyboardReplyRequest({",
  );
  const entitlementGate = source.indexOf("let gate = checkQuota({");
  const terminalQuotaGate = source.indexOf("if (!gate.ok) {", claim);
  const rateGate = source.indexOf("const rate = await enforceModelRateLimit({");
  const renewal = source.indexOf(
    "const renewal = await claimKeyboardReplyRequest({",
  );
  const run = source.indexOf("const result = await runKeyboardReply(");
  const settle = source.indexOf(
    "const settlement = await settleKeyboardReplyRequest({",
  );
  assert(
    entitlementGate >= 0 && claim > entitlementGate &&
      terminalQuotaGate > claim && rateGate > terminalQuotaGate &&
      renewal > rateGate && run > renewal && settle > run,
  );
  const release = source.indexOf("if (!await releaseCurrentClaim())", claim);
  const safeToClear = source.indexOf("safeToClear: true", release);
  assert(release > claim && safeToClear > release);
  assert(source.includes('code: "QUOTA_EXCEEDED"'));
  assert(source.includes("safeToClear: true"));
  assert(source.includes('code: "KEYBOARD_REPLY_REQUEST_PENDING"'));
  assert(source.includes("KEYBOARD_REPLAY_HMAC_KEY"));
  assert(!source.includes("analyze-chat/"));
});

Deno.test("health checks the database-owned exactly-once capability", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assert(source.includes('"keyboard_reply_contract_version"'));
  assert(
    source.includes(
      "databaseContractVersion !== KEYBOARD_REPLY_CONTRACT_VERSION",
    ),
  );
  assert(source.includes("contractVersion: KEYBOARD_REPLY_CONTRACT_VERSION"));
});

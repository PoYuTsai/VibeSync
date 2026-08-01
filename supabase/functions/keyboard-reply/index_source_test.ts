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
  assert(
    source.includes("handleRequestWithinDeadline(request, requestDeadlineAt)"),
  );
  assert(source.includes("Promise.race(["));
  assert(source.includes("keyboardGenerationBudgetRemaining("));
  assert(source.includes("generationBudgetMs:"));
  assert(source.includes("performance.now() >= requestDeadlineAt"));
  assert(source.includes('"KEYBOARD_REPLY_REQUEST_TIMEOUT"'));
  const release = source.indexOf("if (!await releaseCurrentClaim())", claim);
  const safeToClear = source.indexOf("safeToClear: true", release);
  assert(release > claim && safeToClear > release);
  const knownGenerationFailure = source.indexOf(
    'result.status === 500 && result.body.error === "generation_failed"',
    run,
  );
  const generationRelease = source.indexOf(
    "if (!await releaseCurrentClaim())",
    knownGenerationFailure,
  );
  const knownPreSettlementFailure = source.indexOf(
    'result.body.code === "KEYBOARD_REPLY_PRESETTLEMENT_RETRYABLE"',
    run,
  );
  const ambiguousSettlement = source.indexOf(
    '"KEYBOARD_REPLY_SETTLEMENT_RETRYABLE"',
    run,
  );
  assert(
    knownGenerationFailure > run && generationRelease > knownGenerationFailure,
  );
  assert(knownPreSettlementFailure > knownGenerationFailure);
  assert(
    ambiguousSettlement > run && ambiguousSettlement < knownGenerationFailure,
  );
  assert(
    !source.slice(run, knownGenerationFailure).includes(
      "releaseCurrentClaim()",
    ),
  );
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

Deno.test("批 B：keyboard-reply 訪客接線（免重置＋訪客 limits＋guest 429）", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assert(source.includes("isAnonymousAuthUser(user)"));
  assert(source.includes("? noResetResult(sub)"));
  assert(source.includes("? noResetResult(latest)"));
  // resolveLimits 全部帶 anonymous（不得殘留裸呼叫）
  assert(!source.includes("resolveLimits(sub.tier);"));
  assert(!source.includes("resolveLimits(latest.tier);"));
  assert(source.includes("resolveLimits(sub.tier, { anonymous })"));
});

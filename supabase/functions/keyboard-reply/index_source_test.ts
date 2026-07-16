import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

Deno.test("index preserves auth, quota, rate-limit and deduct ordering contracts", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assert(source.includes("client.auth.getUser"));
  assert(source.includes("checkQuota({"));
  assert(source.includes('scope: "keyboard_reply"'));
  assert(source.includes('.from("keyboard_reply_requests")'));
  assert(source.includes("keyboardReplyReplayCutoffIso()"));
  assert(source.includes("settleKeyboardReplyRequest({"));
  assert(source.includes('client.rpc("increment_usage"'));
  assert(
    source.indexOf('.from("keyboard_reply_requests")') <
      source.indexOf("checkQuota({"),
  );
  const run = source.indexOf("const result = await runKeyboardReply(");
  assert(run >= 0);
  assert(
    source.indexOf(
      "const settlement = await settleKeyboardReplyRequest({",
      run,
    ) > run,
  );
  assert(source.includes('error: "KEYBOARD_REPLY_SETTLEMENT_RETRYABLE"'));
  assert(!source.includes("analyze-chat/"));
});

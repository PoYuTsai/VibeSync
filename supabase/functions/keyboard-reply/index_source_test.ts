import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

Deno.test("index preserves auth, quota, rate-limit and deduct ordering contracts", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assert(source.includes("client.auth.getUser"));
  assert(source.includes("checkQuota({"));
  assert(source.includes('scope: "keyboard_reply"'));
  assert(source.includes('client.rpc("increment_usage"'));
  assert(
    source.indexOf("runKeyboardReply(") <
      source.indexOf('client.rpc("increment_usage"'),
  );
  assert(!source.includes("analyze-chat/"));
});

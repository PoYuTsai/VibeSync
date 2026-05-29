import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { hashConversation } from "./conversation_hash.ts";

Deno.test("identical inputs produce identical hash", async () => {
  const a = await hashConversation({
    messages: [{ isFromMe: true, content: "hi" }],
    userDraft: "test",
    partnerSummary: "alice loves jazz",
    sessionContext: { meetingContext: "tinder" },
  });
  const b = await hashConversation({
    messages: [{ isFromMe: true, content: "hi" }],
    userDraft: "test",
    partnerSummary: "alice loves jazz",
    sessionContext: { meetingContext: "tinder" },
  });
  assertEquals(a, b);
});

Deno.test("different userDraft produces different hash", async () => {
  const a = await hashConversation({ messages: [], userDraft: "v1" });
  const b = await hashConversation({ messages: [], userDraft: "v2" });
  assertNotEquals(a, b);
});

Deno.test("different partnerSummary produces different hash", async () => {
  // D3: hash must include partnerSummary so client can't swap it between
  // quick and full to anchor on stale partner context.
  const a = await hashConversation({ messages: [], partnerSummary: "alice" });
  const b = await hashConversation({ messages: [], partnerSummary: "bob" });
  assertNotEquals(a, b);
});

Deno.test("key order does not affect hash", async () => {
  const a = await hashConversation({ userDraft: "a", messages: [] });
  const b = await hashConversation({ messages: [], userDraft: "a" });
  assertEquals(a, b);
});

Deno.test("nested object key order does not affect hash", async () => {
  const a = await hashConversation({
    sessionContext: { meetingContext: "tinder", platform: "ios" },
    messages: [],
  });
  const b = await hashConversation({
    sessionContext: { platform: "ios", meetingContext: "tinder" },
    messages: [],
  });
  assertEquals(a, b);
});

Deno.test("hash is 64-char lowercase hex", async () => {
  const h = await hashConversation({ messages: [] });
  assertEquals(h.length, 64);
  assert(/^[a-f0-9]{64}$/.test(h), `expected 64-char hex, got ${h}`);
});

Deno.test("Unicode NFD vs NFC produce same hash", async () => {
  // "café" can be encoded as NFC (precomposed é = U+00E9) or
  // NFD (e + combining acute U+0301). Without normalization the
  // byte sequences differ and the hash diverges, which would falsely
  // trigger RUN_CONVERSATION_MISMATCH on visually identical text.
  const nfc = "café"; // é precomposed
  const nfd = "café"; // e + combining acute
  assertNotEquals(nfc, nfd, "test fixture is broken if these are equal");
  const a = await hashConversation({ messages: [], userDraft: nfc });
  const b = await hashConversation({ messages: [], userDraft: nfd });
  assertEquals(a, b);
});

Deno.test("CJK NFC normalization is idempotent for typical input", async () => {
  const text = "她剛剛說「最近在追《絕命毒師》」";
  const a = await hashConversation({ messages: [], userDraft: text });
  const b = await hashConversation({ messages: [], userDraft: text });
  assertEquals(a, b);
});

Deno.test("string with leading/trailing whitespace is normalized", async () => {
  // Trim is part of normalize — client text inputs often carry stray spaces
  // from copy/paste. Hash should be stable across them.
  const a = await hashConversation({ messages: [], userDraft: "hello" });
  const b = await hashConversation({ messages: [], userDraft: "  hello  " });
  assertEquals(a, b);
});

Deno.test("missing optional fields default to empty (deterministic)", async () => {
  const a = await hashConversation({ messages: [] });
  const b = await hashConversation({
    messages: [],
    userDraft: "",
    partnerSummary: "",
    sessionContext: null,
    conversationSummary: "",
    effectiveStyleContext: "",
    knownContactName: "",
  });
  assertEquals(a, b);
});

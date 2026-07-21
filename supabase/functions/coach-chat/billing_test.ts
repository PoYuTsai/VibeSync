import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  COACH_CONTRACT_VERSION,
  coachReplayCutoffIso,
  computeCoachInputHash,
  deriveCoachScopeKey,
  isStrongCoachReplayHmacKey,
  normalizeCoachRequestId,
} from "./billing.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const HMAC_KEY = btoa("0123456789abcdef0123456789abcdef");

Deno.test("coach contract version, replay window, and request id are fixed", () => {
  assertEquals(COACH_CONTRACT_VERSION, "coach-exactly-once-v1");
  assertEquals(
    coachReplayCutoffIso(new Date("2026-07-21T12:00:00.000Z")),
    "2026-07-20T12:00:00.000Z",
  );
  assertEquals(normalizeCoachRequestId(REQUEST_ID), REQUEST_ID);
  // 大寫 UUID 合法且 normalize 成小寫（zod .uuid() 收大小寫混寫）。
  assertEquals(
    normalizeCoachRequestId("123E4567-E89B-42D3-A456-426614174000"),
    REQUEST_ID,
  );
  assertEquals(normalizeCoachRequestId("not-a-uuid"), null);
  assertEquals(normalizeCoachRequestId(null), null);
  assertEquals(normalizeCoachRequestId(undefined), null);
});

Deno.test("coach scope key prefers explicit scope then conversation fallback", () => {
  assertEquals(
    deriveCoachScopeKey({
      scope: { type: "conversation", conversationId: "conv-1" },
      conversationId: "conv-1",
    }),
    "conversation:conv-1",
  );
  assertEquals(
    deriveCoachScopeKey({
      scope: { type: "partner", partnerId: "partner-9" },
      conversationId: "conv-1",
    }),
    "partner:partner-9",
  );
  assertEquals(
    deriveCoachScopeKey({ scope: null, conversationId: "conv-2" }),
    "conversation:conv-2",
  );
  assertEquals(
    deriveCoachScopeKey({ scope: undefined, conversationId: "conv-3" }),
    "conversation:conv-3",
  );
  assertEquals(
    deriveCoachScopeKey({ scope: null, conversationId: "" }),
    "none",
  );
  assertEquals(
    deriveCoachScopeKey({ scope: null, conversationId: null }),
    "none",
  );
});

Deno.test("coach HMAC binds every identity-relevant input field", async () => {
  const baseInput = {
    userId: "user-1",
    userQuestion: "我該怎麼回她",
    sessionId: "session-1",
    activeSessionTurns: [
      { role: "user", kind: "question", content: "她已讀不回" },
    ],
    forceAnswer: false,
    scopeKey: "conversation:conv-1",
    lifecyclePhase: "chatStalled",
    secret: HMAC_KEY,
  } as const;
  const first = await computeCoachInputHash(baseInput);
  const same = await computeCoachInputHash({ ...baseInput });
  assertEquals(first, same);
  assert(/^[0-9a-f]{64}$/.test(first));

  const variants = await Promise.all([
    computeCoachInputHash({ ...baseInput, userId: "user-2" }),
    computeCoachInputHash({ ...baseInput, userQuestion: "換個問題" }),
    computeCoachInputHash({ ...baseInput, sessionId: null }),
    computeCoachInputHash({
      ...baseInput,
      activeSessionTurns: [
        { role: "user", kind: "question", content: "她回了" },
      ],
    }),
    computeCoachInputHash({ ...baseInput, forceAnswer: true }),
    computeCoachInputHash({ ...baseInput, scopeKey: "partner:p-1" }),
    computeCoachInputHash({ ...baseInput, lifecyclePhase: null }),
    computeCoachInputHash({
      ...baseInput,
      secret: btoa("abcdef0123456789abcdef0123456789"),
    }),
  ]);
  for (const variant of variants) {
    assert(variant !== first);
  }

  assert(isStrongCoachReplayHmacKey(HMAC_KEY));
  assertFalse(isStrongCoachReplayHmacKey("short-secret"));
  assertFalse(isStrongCoachReplayHmacKey(undefined));
});

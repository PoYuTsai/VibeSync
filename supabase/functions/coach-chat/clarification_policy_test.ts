import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  countCoachClarifications,
  mustClarifyFirstRound,
  shouldForceCoachAnswerAfterClarifications,
} from "./clarification_policy.ts";

Deno.test("coach clarification policy allows at most three no-charge clarifications", () => {
  const twoClarifications = [
    { role: "user", kind: "question" },
    { role: "coach", kind: "clarification" },
    { role: "user", kind: "supplement" },
    { role: "coach", kind: "clarification" },
  ];
  const threeClarifications = [
    ...twoClarifications,
    { role: "user", kind: "supplement" },
    { role: "coach", kind: "clarification" },
  ];

  assertEquals(countCoachClarifications(twoClarifications), 2);
  assertEquals(
    shouldForceCoachAnswerAfterClarifications({
      activeSessionTurns: twoClarifications,
    }),
    false,
  );

  assertEquals(countCoachClarifications(threeClarifications), 3);
  assertEquals(
    shouldForceCoachAnswerAfterClarifications({
      activeSessionTurns: threeClarifications,
    }),
    true,
  );
});

Deno.test("coach clarification policy treats explicit forceAnswer as formal answer", () => {
  assertEquals(
    shouldForceCoachAnswerAfterClarifications({
      forceAnswer: true,
      activeSessionTurns: [],
    }),
    true,
  );
});

Deno.test("mustClarifyFirstRound looks at the current thread, not seeded memory (2026-09-07)", () => {
  const base = {
    forceAnswer: false,
    scope: { type: "global" },
    recentMessages: [],
  };
  // client 把上一題的問答種回 turns（24h resume／跨天摘要）：不算本題脈絡。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      activeSessionTurns: [
        { role: "user", kind: "question" },
        { role: "coach", kind: "answer" },
      ],
    }),
    true,
  );
  // 上一題釐清過、已給答案，這一題重新開始：仍要先釐清。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      activeSessionTurns: [
        { role: "user", kind: "question" },
        { role: "coach", kind: "clarification" },
        { role: "user", kind: "supplement" },
        { role: "coach", kind: "answer" },
      ],
    }),
    true,
  );
  // 本題已釐清過（在最後一張答案之後）：交回模型判斷。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      activeSessionTurns: [
        { role: "user", kind: "question" },
        { role: "coach", kind: "answer" },
        { role: "user", kind: "question" },
        { role: "coach", kind: "clarification" },
      ],
    }),
    false,
  );
  // partner 同一套。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      scope: { type: "partner" },
      activeSessionTurns: [
        { role: "user", kind: "question" },
        { role: "coach", kind: "answer" },
      ],
    }),
    true,
  );
});

Deno.test("mustClarifyFirstRound gates only contextless global first rounds", () => {
  const gated = {
    forceAnswer: false,
    scope: { type: "global" },
    activeSessionTurns: [],
    recentMessages: [],
  };
  assertEquals(mustClarifyFirstRound(gated), true);
  // 逃生門：直接看正式建議。
  assertEquals(mustClarifyFirstRound({ ...gated, forceAnswer: true }), false);
  // 已有本輪脈絡。
  assertEquals(
    mustClarifyFirstRound({
      ...gated,
      activeSessionTurns: [{ role: "coach", kind: "clarification" }],
    }),
    false,
  );
  // 已有對話訊息。
  assertEquals(
    mustClarifyFirstRound({ ...gated, recentMessages: [{}] }),
    false,
  );
  // conversation scope 不受閘門影響。
  assertEquals(
    mustClarifyFirstRound({
      ...gated,
      scope: { type: "conversation" },
    }),
    false,
  );
  assertEquals(mustClarifyFirstRound({ ...gated, scope: null }), false);
});

Deno.test("mustClarifyFirstRound gates evidence-less partner first rounds (Batch A)", () => {
  const gated = {
    forceAnswer: false,
    scope: { type: "partner" },
    activeSessionTurns: [],
    recentMessages: [],
    conversationSummary: null,
    analysisSnapshot: null,
  };
  assertEquals(mustClarifyFirstRound(gated), true);
  // 逃生門與各種「已有個案證據」都放行。
  assertEquals(mustClarifyFirstRound({ ...gated, forceAnswer: true }), false);
  assertEquals(
    mustClarifyFirstRound({ ...gated, recentMessages: [{}] }),
    false,
  );
  assertEquals(
    mustClarifyFirstRound({
      ...gated,
      activeSessionTurns: [{ role: "coach", kind: "clarification" }],
    }),
    false,
  );
  assertEquals(
    mustClarifyFirstRound({ ...gated, conversationSummary: "上次聊到爬山" }),
    false,
  );
  assertEquals(
    mustClarifyFirstRound({ ...gated, analysisSnapshot: { stage: "曖昧" } }),
    false,
  );
});

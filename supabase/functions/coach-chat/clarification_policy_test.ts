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
  // 非 global scope 不受閘門影響。
  assertEquals(
    mustClarifyFirstRound({
      ...gated,
      scope: { type: "conversation" },
    }),
    false,
  );
  assertEquals(mustClarifyFirstRound({ ...gated, scope: null }), false);
});

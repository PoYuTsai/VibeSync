import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  countCoachClarifications,
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

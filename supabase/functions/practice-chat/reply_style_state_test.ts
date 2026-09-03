import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  nextReplyStyleState,
  parseReplyStyleState,
} from "./reply_style_state.ts";
import { buildRelationshipThreadRpcParams } from "./relationship_thread.ts";
import type { TurnResponsePlan } from "./turn_response_plan.ts";

const plan = (over: Partial<TurnResponsePlan> = {}): TurnResponsePlan => ({
  styleVersion: "reply-style-v1",
  presetId: "concise_observer",
  policyStance: "open",
  situation: "neutral",
  primaryAct: "acknowledge",
  optionalAct: null,
  conditionalActs: [],
  bubbleCount: 1,
  questionBudget: 0,
  disclosureDepth: "none",
  seed: 1,
  agency: null,
  ...over,
});

Deno.test("parseReplyStyleState：缺 key 回 null；任何欄位缺、型別錯、未知 act 都整份 null；合法才收，最多留 3 筆", () => {
  assertEquals(parseReplyStyleState(null), null);
  assertEquals(parseReplyStyleState({}), null);
  assertEquals(parseReplyStyleState({ replyStyle: "x" }), null);
  assertEquals(parseReplyStyleState({ replyStyle: [] }), null);
  assertEquals(parseReplyStyleState({ replyStyle: { version: 2 } }), null);
  const ok = {
    version: 1 as const,
    priorDecline: true,
    recentActs: ["answer" as const],
  };
  assertEquals(parseReplyStyleState({ replyStyle: ok }), ok);
  for (
    const bad of [
      { ...ok, priorDecline: "yes" },
      { ...ok, priorDecline: undefined },
      { ...ok, recentActs: undefined },
      { ...ok, recentActs: "answer" },
      { ...ok, recentActs: ["answer", 3] },
      { ...ok, recentActs: ["answer", "not_an_act"] },
      { ...ok, recentActs: ["raw_user_text"] },
    ]
  ) {
    assertEquals(
      parseReplyStyleState({ replyStyle: bad }),
      null,
      JSON.stringify(bad),
    );
  }
  assertEquals(
    parseReplyStyleState({
      replyStyle: {
        version: 1,
        priorDecline: false,
        recentActs: ["answer", "tease", "clarify", "acknowledge"],
      },
    }),
    {
      version: 1,
      priorDecline: false,
      recentActs: ["tease", "clarify", "acknowledge"],
    },
  );
});

Deno.test("nextReplyStyleState：明確拒絕只認 stance decline 或邀約輪 direct_boundary；一旦拒絕過就保留；recentActs 滾動 3 筆", () => {
  const s1 = nextReplyStyleState(null, plan({ primaryAct: "answer" }));
  assertEquals(s1, { version: 1, priorDecline: false, recentActs: ["answer"] });
  const soft = nextReplyStyleState(
    s1,
    plan({ situation: "early_invite", primaryAct: "soft_deflect" }),
  );
  assertEquals(soft.priorDecline, false);
  const declined = nextReplyStyleState(
    soft,
    plan({ situation: "early_invite", primaryAct: "direct_boundary" }),
  );
  assertEquals(declined.priorDecline, true);
  assertEquals(declined.recentActs, [
    "answer",
    "soft_deflect",
    "direct_boundary",
  ]);
  const later = nextReplyStyleState(declined, plan({ primaryAct: "tease" }));
  assertEquals(later.priorDecline, true);
  assertEquals(later.recentActs, ["soft_deflect", "direct_boundary", "tease"]);
  const byStance = nextReplyStyleState(null, plan({ policyStance: "decline" }));
  assertEquals(byStance.priorDecline, true);
});

Deno.test("buildRelationshipThreadRpcParams：省略 replyStyleState 時 recent_facts 與舊版逐字相同；提供時多 replyStyle 一個 key", () => {
  const base = {
    userId: "u",
    visibleThreadId: "t",
    practiceMode: "beginner" as const,
    relationshipScore: 40,
    inviteStage: "not_ready" as const,
    aiTurnCount: 2,
  };
  assertEquals(buildRelationshipThreadRpcParams(base).p_recent_facts, {
    source: "practice_chat",
    aiTurnCount: 2,
    inviteStage: "not_ready",
  });
  assertEquals(
    buildRelationshipThreadRpcParams({ ...base, replyStyleState: null })
      .p_recent_facts,
    { source: "practice_chat", aiTurnCount: 2, inviteStage: "not_ready" },
  );
  const state = {
    version: 1 as const,
    priorDecline: true,
    recentActs: ["answer" as const],
  };
  assertEquals(
    buildRelationshipThreadRpcParams({ ...base, replyStyleState: state })
      .p_recent_facts,
    {
      source: "practice_chat",
      aiTurnCount: 2,
      inviteStage: "not_ready",
      replyStyle: state,
    },
  );
});

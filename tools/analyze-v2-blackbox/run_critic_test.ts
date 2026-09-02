import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { CORPUS } from "./corpus.ts";
import { criticCaseFromArtifact } from "./run_critic.ts";

const PLAN = {
  schemaVersion: 1,
  threadFrame: "f",
  anchorSourceIndex: 1,
  supportSourceIndices: [],
  mergeContextSourceIndices: [],
  semanticDistanceCap: 1,
  newTopicBudget: 0,
  questionBudget: 0,
  branchPool: [
    {
      id: "br_1",
      sourceIndex: 1,
      method: "drill_down",
      idea: "i",
      associationPath: ["p"],
      semanticDistance: 1,
    },
    {
      id: "br_2",
      sourceIndex: 1,
      method: "lateral",
      idea: "j",
      associationPath: ["q"],
      semanticDistance: 1,
    },
  ],
};

const byId = new Map(CORPUS.map((c) => [c.id, c]));

function sendCase(name = "warm_question_back") {
  return {
    name,
    decision: { messageDecision: "send", selectedStyle: "tease" },
    server: { plan: PLAN, decisionV2: null },
    rawLines: [
      { type: "analysis.inventory" },
      {
        type: "analysis.decision",
        messageDecision: "send",
        selectedStyle: "tease",
      },
      {
        type: "analysis.reply_option",
        style: "extend",
        selectedBranchIds: ["br_2"],
        segments: [{ sourceIndex: 1, sourceMessage: "m", reply: "a" }],
      },
      {
        type: "analysis.reply_option",
        style: "tease",
        selectedBranchIds: ["br_1"],
        segments: [{ sourceIndex: 1, sourceMessage: "m", reply: "b？？" }],
      },
    ],
  };
}

Deno.test("critic harness: a send case yields the selected card, corpus messages and the guard codes", () => {
  const built = criticCaseFromArtifact(sendCase(), byId);
  assert(built);
  assertEquals(built.id, "warm_question_back");
  assertEquals(built.candidate.style, "tease");
  assertEquals(built.candidate.segments, [{
    sourceIndex: 1,
    sourceMessage: "m",
    reply: "b？？",
  }]);
  assertEquals(built.candidate.questionCount, 2);
  assertEquals(
    built.evidence.messages,
    byId.get("warm_question_back")!.messages.map((m) => ({
      from: m.isFromMe ? "me" : "her",
      text: m.content,
    })),
  );
  assertEquals(built.evidence.plan?.usedBranches.map((b) => b.id), ["br_1"]);
  assertEquals(built.evidence.guardViolations, ["question_budget"]);
});

Deno.test("critic harness: no-send cases, unknown ids and repeats are handled", () => {
  assertEquals(
    criticCaseFromArtifact(
      { ...sendCase(), decision: { messageDecision: "do_not_send" } },
      byId,
    ),
    null,
  );
  assertEquals(criticCaseFromArtifact(sendCase("not_in_corpus"), byId), null);
  assertEquals(
    criticCaseFromArtifact(sendCase("warm_question_back#2"), byId)?.id,
    "warm_question_back",
  );
});

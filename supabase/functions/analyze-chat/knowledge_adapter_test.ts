import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  ANALYZE_KNOWLEDGE_BUDGET,
  buildAnalyzeSocialKnowledgeInput,
  detectAnalyzeSocialKnowledgeSignals,
  selectAnalyzeSocialKnowledge,
} from "./knowledge_adapter.ts";

const messages = [
  { isFromMe: true, content: "週末要不要去喝咖啡？" },
  { isFromMe: false, content: "這週沒空耶" },
  { isFromMe: false, content: "哈哈" },
];

Deno.test("analyze adapter maps isFromMe to sender and adds no ambient typed signal", () => {
  const input = buildAnalyzeSocialKnowledgeInput({ messages });
  assertEquals(input.userQuestion, "");
  assertEquals(input.recentMessages?.map((message) => message.sender), [
    "me",
    "partner",
    "partner",
  ]);
  assertEquals(input.typedSignals, []);
  const signals = detectAnalyzeSocialKnowledgeSignals({ messages });
  assert(signals.includes("reply"));
  assert(signals.includes("rejection"));
  assert(signals.includes("low_investment"));
});

Deno.test("analyze adapter turns a close stage prior into the invite signal only", () => {
  const closeInput = buildAnalyzeSocialKnowledgeInput({
    messages,
    previousStage: "close",
  });
  assert(closeInput.typedSignals?.includes("invite"));
  for (const stage of ["narrative", "CLOSE", "closing", undefined]) {
    const input = buildAnalyzeSocialKnowledgeInput({
      messages,
      previousStage: stage,
    });
    assertFalse(input.typedSignals?.includes("invite"));
  }
});

Deno.test("analyze selection is deterministic and inside the §11.2 budget", () => {
  const input = { messages, previousStage: "close" };
  const first = selectAnalyzeSocialKnowledge(input);
  const second = selectAnalyzeSocialKnowledge(input);
  assertEquals(first.map((atom) => atom.id), second.map((atom) => atom.id));
  assert(first.length >= 6 && first.length <= 10, `got ${first.length}`);
  const rendered = first.map((atom) => `- ${atom.guidance}`).join("\n");
  assert(rendered.length <= 1_400);
  for (const { match, cap } of ANALYZE_KNOWLEDGE_BUDGET.caps ?? []) {
    assert(first.filter(match).length <= cap);
  }
  assert(first.filter((atom) => atom.id.startsWith("core.")).length <= 3);
  // 拒絕邀約＋沒給替代時間：專用 invite 規則要進得來。
  assert(first.some((atom) => atom.id === "invite.no_alternative_once"));
});

Deno.test("analyze adapter with no messages returns only the capped core, uncertainty first", () => {
  const atoms = selectAnalyzeSocialKnowledge({ messages: [] });
  assertEquals(atoms.length, 3);
  assert(atoms.every((atom) => atom.id.startsWith("core.")));
  // evidence_sparse 讓 core.uncertainty 靠雙訊號加分排到第一。
  assertEquals(atoms[0].id, "core.uncertainty");
  assert(atoms.some((atom) => atom.id === "core.one_judgment"));
});

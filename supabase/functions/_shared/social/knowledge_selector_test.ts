import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { SOCIAL_KNOWLEDGE_REGISTRY } from "./knowledge_registry.ts";
import {
  detectSocialKnowledgeSignals,
  renderSelectedSocialKnowledge,
  selectSocialKnowledge,
} from "./knowledge_selector.ts";

Deno.test("social knowledge registry has exactly 62 unique typed atoms", () => {
  assertEquals(SOCIAL_KNOWLEDGE_REGISTRY.length, 62);
  assertEquals(
    new Set(SOCIAL_KNOWLEDGE_REGISTRY.map((atom) => atom.id)).size,
    62,
  );
  for (const atom of SOCIAL_KNOWLEDGE_REGISTRY) {
    assert(atom.id.length > 0);
    assert(atom.guidance.length > 0);
    assert(atom.signals.length > 0);
    assert(atom.priority >= 0 && atom.priority <= 100);
  }
});

Deno.test("selector is deterministic, bounded, and routes invite knowledge", () => {
  const input = {
    userQuestion: "她上次說沒空也沒給時間，我還要再約她喝咖啡嗎？",
    lifecyclePhase: "prepareInvite" as const,
    recentMessages: [
      { sender: "me" as const, text: "週末要不要去喝咖啡？" },
      { sender: "partner" as const, text: "這週沒空耶" },
    ],
  };
  const first = selectSocialKnowledge(input);
  const second = selectSocialKnowledge(input);
  assertEquals(first.map((atom) => atom.id), second.map((atom) => atom.id));
  assert(first.length <= 12);
  assert(first.some((atom) => atom.id === "invite.window_first"));
  assert(first.some((atom) => atom.id === "invite.no_alternative_once"));
  assert(!first.some((atom) => atom.id === "health.escalation"));
});

Deno.test("selector derives low versus high partner investment from recent turns", () => {
  const low = detectSocialKnowledgeSignals({
    userQuestion: "我怎麼回？",
    recentMessages: [
      { sender: "me", text: "我昨天去看展，裡面有一區超像你之前說的那種風格" },
      { sender: "partner", text: "哈哈" },
    ],
  });
  assert(low.has("low_investment"));
  assert(!low.has("high_investment"));

  const high = detectSocialKnowledgeSignals({
    userQuestion: "我怎麼回？",
    recentMessages: [
      { sender: "me", text: "我昨天去看展" },
      { sender: "partner", text: "哪一個展？你最喜歡哪一區？" },
    ],
  });
  assert(high.has("high_investment"));
  assert(!high.has("low_investment"));
});

Deno.test("boundary and intimacy query selects fail-safe knowledge", () => {
  const selected = selectSocialKnowledge({
    userQuestion: "她喝醉又沉默，我可以繼續親密推進嗎？",
  });
  const ids = new Set(selected.map((atom) => atom.id));
  assert(ids.has("boundary.consent"));
  assert(ids.has("boundary.stop_signals"));
  assert(ids.has("boundary.no_pressure"));
  assert(ids.has("boundary.alcohol"));
});

Deno.test("renderer respects whole-atom character budget", () => {
  const rendered = renderSelectedSocialKnowledge(
    { userQuestion: "她已讀沒回，我要怎麼重啟對話？" },
    { maxAtoms: 20, maxChars: 300 },
  );
  assert(rendered.length <= 300);
  assert(rendered.split("\n").every((line) => line.startsWith("- ")));
  assert(!rendered.endsWith("…"));
});

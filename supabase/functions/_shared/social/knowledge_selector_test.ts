import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { SOCIAL_KNOWLEDGE_REGISTRY } from "./knowledge_registry.ts";
import {
  detectSocialKnowledgeSignals,
  domainCap,
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

Deno.test("selector keeps specialized knowledge inside the 12-atom cap", () => {
  const humor = selectSocialKnowledge({
    userQuestion: "我想幽默回她但不要油。",
  });
  assert(humor.some((atom) => atom.id === "humor.not_oily"));

  const powerBoundary = detectSocialKnowledgeSignals({
    userQuestion: "這是主管和下屬的權力關係，我該怎麼推進？",
  });
  assert(powerBoundary.has("boundary"));

  const compatibility = detectSocialKnowledgeSignals({
    userQuestion: "我不想只因一個人格標籤就淘汰她。",
  });
  assert(compatibility.has("compatibility"));
});

Deno.test("renderer respects whole-atom character budget", () => {
  const input = { userQuestion: "她已讀沒回，我要怎麼重啟對話？" };
  const rendered = renderSelectedSocialKnowledge(
    input,
    { maxAtoms: 20, maxChars: 300 },
  );
  assert(rendered.length <= 300);
  assert(rendered.split("\n").every((line) => line.startsWith("- ")));
  assert(!rendered.endsWith("…"));

  const defaultRendered = renderSelectedSocialKnowledge(input);
  assert(defaultRendered.length <= 1_400);
});

Deno.test("renderer counts newline separators inside the exact character budget", () => {
  const input = { userQuestion: "她已讀沒回，我要怎麼重啟對話？" };
  const firstTwo = selectSocialKnowledge(input, {
    maxAtoms: 2,
    maxChars: 4_000,
  });
  assertEquals(firstTwo.length, 2);

  // 這個上限刻意只等於兩個 bullet 本身，不含兩者之間的換行；舊實作會
  // 選進兩條後渲染成 budget + 1。
  const withoutJoiner = firstTwo.reduce(
    (sum, atom) => sum + atom.guidance.length + 2,
    0,
  );
  const rendered = renderSelectedSocialKnowledge(input, {
    maxAtoms: 2,
    maxChars: withoutJoiner,
  });
  assert(rendered.length <= withoutJoiner);
});

Deno.test("typed signals union with regex detection and domain caps bound each bucket", () => {
  const base = {
    userQuestion: "",
    recentMessages: [
      { sender: "partner" as const, text: "剛健身完累死了" },
      { sender: "me" as const, text: "練完那種腿不是自己的感覺很真實" },
    ],
  };
  const withoutTyped = detectSocialKnowledgeSignals(base);
  assert(!withoutTyped.has("invite"));
  const withTyped = detectSocialKnowledgeSignals({
    ...base,
    typedSignals: ["invite", "interpretation"],
  });
  assert(withTyped.has("invite"));
  assert(withTyped.has("interpretation"));
  // 只加不減：regex 偵測到的 reply 仍在。
  assert(withTyped.has("reply"));

  const capped = selectSocialKnowledge(
    { ...base, typedSignals: ["invite", "interpretation"] },
    {
      maxAtoms: 10,
      caps: [
        domainCap("decision", 2),
        domainCap("evidence", 1),
        domainCap("voice", 0),
      ],
    },
  );
  const count = (domain: string) =>
    capped.filter((atom) => atom.domain === domain).length;
  assert(capped.length <= 10);
  assert(count("decision") <= 2);
  assert(count("evidence") <= 1);
  assertEquals(count("voice"), 0);
  // 被 cap 擠掉的桶不會讓整體停下：其他 domain 仍照排名補進來。
  assert(count("action") >= 1);
});

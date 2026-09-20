// R3a（第二輪獨立複核）：assert_sender_fact 的授權必須來自用戶實際看見並選取的那句話。
// 走正式路徑：模型輸出 → buildOpenerAnalysisSnapshot（選項清洗）→ buildOpenerMaterials
// → renderMaterialsForPrompt；隱藏的 statement 不得夾帶用戶沒看過的新經歷。
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildOpenerAnalysisSnapshot, type OpenerAnalysisSnapshot } from "./opener_stage.ts";
import { buildOpenerMaterials, renderMaterialsForPrompt } from "./opener_material.ts";

function snapshotWith(cueLabel: string, options: Array<Record<string, unknown>>): OpenerAnalysisSnapshot | null {
  return buildOpenerAnalysisSnapshot({
    parsed: {
      profileDigest: `自介：${cueLabel}`,
      approach: { mode: "anchor_hooks", summary: `可以從${cueLabel}開`, avoid: [] },
      cues: [{ id: "cue_1", label: cueLabel, source: "profile_text", evidence: { field: "bio", quote: cueLabel } }],
      question: { affects: "sender_fact", text: `你跟${cueLabel}這件事比較接近哪種？`, options },
    },
    rawProfileInfo: { bio: cueLabel },
    imageCount: 0,
    initialUserNote: null,
  });
}

function senderFactTexts(snapshot: OpenerAnalysisSnapshot): string[] {
  const out: string[] = [];
  for (const option of snapshot.question?.options ?? []) {
    if (option.meaning !== "assert_sender_fact") continue;
    const set = buildOpenerMaterials({
      snapshot,
      contribution: { state: "answered", questionId: snapshot.question!.id, selectedOptionId: option.id, freeText: null },
      option,
    });
    assert(set.senderFactAllowed);
    out.push(set.materials[0].originalText, renderMaterialsForPrompt(set));
  }
  return out;
}

Deno.test("R3a-2：label「我對咖啡有興趣」配隱藏 statement「我是咖啡師」→ 只授權用戶看見的那句，咖啡師不得進原料", () => {
  const snapshot = snapshotWith("咖啡", [
    { label: "我對咖啡有興趣", meaning: "assert_sender_fact", cueId: "cue_1", statement: "我是咖啡師" },
    { label: "沒喝，但好奇", meaning: "curious_without_experience", cueId: "cue_1" },
  ]);
  assert(snapshot?.question);
  const texts = senderFactTexts(snapshot);
  for (const t of texts) assert(!t.includes("咖啡師"), `不得出現用戶沒看過的經歷：${t}`);
  const fact = snapshot.question.options.find((o) => o.meaning === "assert_sender_fact");
  if (fact) assertEquals(fact.statement, "我對咖啡有興趣");
});

Deno.test("R3a-2：label「我剛開始養狗」配 statement「我養狗十年」→ 年數不得進原料", () => {
  const snapshot = snapshotWith("養狗", [
    { label: "我剛開始養狗", meaning: "assert_sender_fact", cueId: "cue_1", statement: "我養狗十年" },
    { label: "沒養，但有興趣", meaning: "curious_without_experience", cueId: "cue_1" },
  ]);
  assert(snapshot?.question);
  for (const t of senderFactTexts(snapshot)) assert(!t.includes("十年"), `不得出現用戶沒看過的經歷：${t}`);
  const fact = snapshot.question.options.find((o) => o.meaning === "assert_sender_fact");
  if (fact) assertEquals(fact.statement, "我剛開始養狗");
});

Deno.test("R3a-2：label 不是完整第一人稱陳述（「有養」）→ 無法確認就不授權新的個人經歷", () => {
  const snapshot = snapshotWith("養狗", [
    { label: "有養", meaning: "assert_sender_fact", cueId: "cue_1", statement: "我有養狗" },
    { label: "沒養，但有興趣", meaning: "curious_without_experience", cueId: "cue_1" },
    { label: "其實想聊別的", meaning: "change_direction" },
  ]);
  assert(snapshot?.question);
  assertEquals(snapshot.question.options.filter((o) => o.meaning === "assert_sender_fact"), []);
});

Deno.test("R3a-2：合法自述保留——label「我自己有養狗」被選取就是授權原句；否定與家人主體仍不授權", () => {
  const snapshot = snapshotWith("養狗", [
    { label: "我自己有養狗", meaning: "assert_sender_fact", cueId: "cue_1", statement: "我有養狗" },
    { label: "沒養，但有興趣", meaning: "assert_sender_fact", cueId: "cue_1", statement: "我有養狗" },
    { label: "我妹有養狗", meaning: "assert_sender_fact", cueId: "cue_1", statement: "我妹有養狗" },
    { label: "其實想聊別的", meaning: "change_direction" },
  ]);
  assert(snapshot?.question);
  const facts = snapshot.question.options.filter((o) => o.meaning === "assert_sender_fact");
  assertEquals(facts.map((o) => o.statement), ["我自己有養狗"]);
  const [text] = senderFactTexts(snapshot);
  assertEquals(text, "我自己有養狗");
});

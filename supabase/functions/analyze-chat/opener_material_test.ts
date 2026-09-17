// opener_material.ts：原料整理與確定性檢核（附件 F03–F10、F14、§10.7）。
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildOpenerMaterials,
  checkOpenersAgainstMaterials,
  extractExcludedTopics,
  extractNegatedFacts,
  hardFlags,
  isNoPreferenceText,
  renderMaterialsForPrompt,
  sanitizeMaterialReading,
  sanitizeMaterialReferences,
} from "./opener_material.ts";
import type { OpenerAnalysisSnapshot, OpenerContribution, OpenerQuestionOption } from "./opener_stage.ts";

const SNAPSHOT: OpenerAnalysisSnapshot = {
  approach: { mode: "anchor_hooks", summary: "可以從她的狗開", avoid: [] },
  cues: [
    { id: "cue_1", label: "養狗", source: "profile_text", subject: "recipient", evidence: { field: "bio", quote: "有養一隻狗" } },
    { id: "cue_2", label: "咖啡", source: "profile_text", subject: "recipient" },
    { id: "cue_3", label: "旅遊", source: "profile_text", subject: "recipient" },
  ],
  question: {
    id: "question_1",
    affects: "sender_fact",
    text: "你跟養狗這件事比較接近哪種？",
    options: [
      { id: "option_1", label: "我自己有養", meaning: "assert_sender_fact", cueId: "cue_1", statement: "我有養狗" },
      { id: "option_2", label: "沒養，但有興趣", meaning: "curious_without_experience", cueId: "cue_1" },
      { id: "option_3", label: "其實想聊別的", meaning: "change_direction" },
      { id: "option_4", label: "先聊狗就好", meaning: "pick_cue", cueId: "cue_1" },
    ],
  },
  profileDigest: "有養一隻狗；咖啡；旅遊",
  profileText: { bio: "有養一隻狗" },
  imageCount: 0,
  initialNoteProvided: false,
  promptVersion: "v1",
};

function option(id: string): OpenerQuestionOption {
  return SNAPSHOT.question!.options.find((o) => o.id === id)!;
}
function answered(optionId: string | null, freeText: string | null): OpenerContribution {
  return { state: "answered", questionId: optionId ? "question_1" : null, selectedOptionId: optionId, freeText };
}

Deno.test("F03：選「狗」（pick_cue）只代表主題，不授權第一人稱事實", () => {
  const set = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: answered("option_4", null), option: option("option_4") });
  assertEquals(set.inputState, "answered");
  assertEquals(set.senderFactAllowed, false);
  assertEquals(set.materials[0].kind, "interest");
  assert(set.materials[0].allowedUse.includes("topic") && !set.materials[0].allowedUse.includes("sender_fact"));
  const flags = checkOpenersAgainstMaterials({ extend: "牠散步會自己選路嗎", resonate: "我家那隻也一樣愛帶路" }, set);
  assertEquals(hardFlags(flags).map((f) => [f.code, f.style]), [["fabricated_sender_fact", "resonate"]]);
});

Deno.test("F04：「沒養，只是好奇」→ 所有卡都不得編養狗經歷", () => {
  const set = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: answered("option_2", "沒養過，只想知道牠散步會不會自己選路"), option: option("option_2") });
  // 用戶原文存在 → 第一人稱事實可能合法（他說了「沒養過」），但否定不得反轉。
  assertEquals(set.negatedFacts, ["養過"]);
  const flags = checkOpenersAgainstMaterials({
    extend: "牠散步會自己選路嗎",
    resonate: "我也養過狗所以懂",
    humor: "我沒養過狗但很想知道牠會不會帶路",
  }, set);
  assertEquals(hardFlags(flags).map((f) => [f.code, f.style]), [["negation_reversed", "resonate"]]);
});

Deno.test("F05／F07：自由補充原樣保留成 raw_sentence 原料，主體與目標由模型讀、程式不改寫", () => {
  const set = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: answered(null, "我妹也是美容師，我想約她喝咖啡"), option: null });
  assertEquals(set.materials.length, 1);
  assertEquals(set.materials[0].origin, "user_text");
  assertEquals(set.materials[0].kind, "raw_sentence");
  assertEquals(set.materials[0].originalText, "我妹也是美容師，我想約她喝咖啡");
  assertEquals(set.materials[0].subject, "unknown");
  assert(renderMaterialsForPrompt(set).includes("「我妹也是美容師，我想約她喝咖啡」"));
  assert(renderMaterialsForPrompt(set).includes("目標（想約、想問）不得寫成她的意願"));
});

Deno.test("F06：「我以前養過，現在沒有」→ 否定片段抽出，寫成現在有養就是反轉", () => {
  assertEquals(extractNegatedFacts("我以前養過狗，現在沒有養了"), ["養了"]);
  assertEquals(extractNegatedFacts("我沒去過沖繩，只是想問"), ["去沖繩"]);
  assertEquals(extractNegatedFacts("我對這個沒有興趣"), []);
});

Deno.test("F09：選「都沒興趣」→ 排除第一段全部線索、方向改為另開話題", () => {
  const set = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: answered("option_3", null), option: option("option_3") });
  assertEquals(set.directionOverride, "fresh_topic");
  assertEquals(set.excludedTopics, ["養狗", "咖啡", "旅遊"]);
  const flags = checkOpenersAgainstMaterials({ extend: "妳的旅遊照拍得很有畫面", humor: "板橋有沒有妳願意再吃一次的店" }, set);
  assertEquals(hardFlags(flags).map((f) => [f.code, f.detail]), [["excluded_topic_used", "旅遊"]]);
});

Deno.test("F10：略過、沒回答、「都可以」三種狀態可分辨，都不算取得有效原料", () => {
  const skipped = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: { state: "skipped", questionId: null, selectedOptionId: null, freeText: null }, option: null });
  assertEquals(skipped.inputState, "skipped");
  const noAnswer = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: { state: "no_answer", questionId: null, selectedOptionId: null, freeText: null }, option: null });
  assertEquals(noAnswer.inputState, "no_answer");
  const whatever = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: answered(null, "都可以"), option: null });
  assertEquals(whatever.inputState, "no_preference");
  assertEquals(whatever.hasEffectiveMaterial, false);
  assert(isNoPreferenceText("不知道～"));
  assert(!isNoPreferenceText("不知道她那家店在哪，想問"));
  assert(renderMaterialsForPrompt(skipped).includes("不要假裝有取得用戶個人想法"));
});

Deno.test("排除字眼：「不想聊她的工作」「先不要提我工作」「別問住哪」", () => {
  assertEquals(extractExcludedTopics("我最近在找板橋晚餐店，不想聊她的工作"), ["工作"]);
  assertEquals(extractExcludedTopics("先不要提我工作，可以聊狗"), ["工作"]);
  assertEquals(extractExcludedTopics("別問住哪"), ["住哪"]);
});

Deno.test("assert_sender_fact 選項＝合法自述來源；只能用原句，程式不擋「我也養狗」", () => {
  const set = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: answered("option_1", null), option: option("option_1") });
  assertEquals(set.senderFactAllowed, true);
  assertEquals(set.materials[0].originalText, "我有養狗");
  assertEquals(hardFlags(checkOpenersAgainstMaterials({ resonate: "我也養狗，妳那隻散步會帶路嗎" }, set)), []);
});

Deno.test("F14：合法人物關係不被清洗——「我妹也是美容師」在有用戶原文時不算捏造", () => {
  const set = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: answered(null, "我妹也是美容師"), option: null });
  assertEquals(hardFlags(checkOpenersAgainstMaterials({ extend: "我妹也是美容師，妳做這行多久了" }, set)), []);
});

Deno.test("來源紀錄：ID 出自本局且片段真的在句子裡才算；對不上就丟＋soft flag", () => {
  const set = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: answered(null, "沒養過，只想知道牠散步會不會自己選路"), option: null });
  const openers = { extend: "牠散步會自己選路嗎", humor: "妳家狗是導航派還是隨機派" };
  const { references, flags } = sanitizeMaterialReferences([
    { style: "extend", materialId: "material_1", outputSpan: "散步會自己選路" },
    { style: "humor", materialId: "material_1", outputSpan: "不在句子裡" },
    { style: "tease", materialId: "material_1", outputSpan: "x" },
    { style: "extend", materialId: "material_99", outputSpan: "散步" },
  ], openers, set.materials);
  assertEquals(references, [{ style: "extend", materialId: "material_1", outputSpan: "散步會自己選路" }]);
  assertEquals(flags.length, 3);
  const reading = sanitizeMaterialReading([
    { materialId: "material_1", subject: "sender", kind: "fact", certainty: "stated", quote: "沒養過" },
    { materialId: "material_1", subject: "sender", kind: "fact", certainty: "stated", quote: "我養了三年" },
  ], set.materials);
  assertEquals(reading.reading.map((r) => r.quote), ["沒養過"]);
  assertEquals(reading.flags.map((f) => f.code), ["reading_quote_mismatch"]);
});

// opener_material.ts：原料整理與確定性檢核（附件 F03–F10、F14、§10.7）。
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildOpenerMaterials,
  cardAdoptsMaterial,
  checkMaterialAdoption,
  checkOpenersAgainstMaterials,
  extractExcludedTopics,
  extractNegatedFacts,
  hardFlags,
  isNoPreferenceText,
  renderMaterialsForPrompt,
  sanitizeMaterialReading,
  sanitizeMaterialReferences,
} from "./opener_material.ts";
import { OPENER_FREE_V2_TYPES, OPENER_TYPES } from "./opener_payload.ts";
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
  initialNoteFingerprint: null,
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

// ── 第五輪驗收補的確定性規則（每條各一個最小案例＋一個不得誤判的對照）
function rawSet(freeText: string) {
  return buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: answered(null, freeText), option: null });
}
function codes(openers: Record<string, string>, set: ReturnType<typeof rawSet>, snapshot = SNAPSHOT) {
  return hardFlags(checkOpenersAgainstMaterials(openers, set, snapshot)).map((f) => `${f.style}:${f.code}`);
}

Deno.test("第五輪 B：「柴犬：我養妳不是讓妳摸的」是代言不是自述；「我懂」只是共感", () => {
  const skipped = buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: { state: "skipped", questionId: null, selectedOptionId: null, freeText: null }, option: null });
  assertEquals(codes({ humor: "柴犬：我養妳不是讓妳摸的", resonate: "被自己養的狗嫌棄的心情我懂" }, skipped), []);
  assertEquals(codes({ resonate: "我也養狗所以懂" }, skipped), ["resonate:fabricated_sender_fact"], "真正的自述仍要抓");
});

Deno.test("第五輪 B：「還有沒有推薦」是正反問句，不是被否定的經歷", () => {
  assertEquals(extractNegatedFacts("上次她訂的那家餐廳我很喜歡，想問還有沒有推薦"), []);
  assertEquals(extractNegatedFacts("我沒去過那家店"), ["去那家店"], "真正的否定仍要抓");
});

Deno.test("第五輪 B：「下班不聊工作吧」是遵守排除；以她的職業開話題才是使用", () => {
  const set = rawSet("我妹下班完全不想聊工作，我猜她也是");
  assert(set.excludedTopics.includes("工作"));
  assertEquals(codes({ extend: "下班只想放空不聊工作吧" }, set), []);
  assertEquals(codes({ extend: "妳工作是不是很累" }, set), ["extend:excluded_topic_used"]);
});

Deno.test("第五輪 B：「不聊工作」延伸到自介裡的職業線索（美容師）", () => {
  const snapshot = { ...SNAPSHOT, cues: [{ id: "cue_1", label: "美容師工作", source: "manual_field" as const, subject: "recipient" as const }] };
  const set = buildOpenerMaterials({ snapshot, contribution: answered(null, "我最近在找板橋晚餐店，不想聊工作"), option: null });
  assert(set.excludedTopics.includes("美容師"), `排除：${set.excludedTopics.join("、")}`);
  assertEquals(codes({ tease: "美容師的私房口袋名單應該不少吧", extend: "在找板橋晚餐店，妳附近有推薦嗎" }, set, snapshot), ["tease:excluded_topic_used"]);
});

Deno.test("第五輪 A：用戶經歷寫進沒有「我」的句子＝套到她身上；用「我」說就合法", () => {
  const set = rawSet("我對打鼓有興趣，我玩過三年樂團");
  assertEquals(codes({ extend: "玩三年樂團才想學打鼓喔" }, set), ["extend:sender_fact_transposed"]);
  assertEquals(codes({ extend: "我玩過三年樂團 妳打鼓多久了" }, set), []);
});

Deno.test("第五輪 A：家人只給職業，卡片替家人加引語＝捏造；沒有引語不算", () => {
  const set = rawSet("我妹也是美容師");
  assertEquals(codes({ resonate: "常聽我妹說美容師很燒體力" }, set), ["resonate:relative_quote_fabricated"]);
  assertEquals(codes({ extend: "我妹也是美容師 妳們平常都站著上班嗎" }, set), []);
});

Deno.test("第五輪 A：「提過想去、還沒訂」不得升級成「說好」；問「訂了嗎」可以", () => {
  const set = rawSet("她上次聊天提過想去沖繩，還沒訂");
  assertEquals(codes({ tease: "說好要訂的沖繩機票咧" }, set), ["tease:certainty_upgraded"]);
  assertEquals(codes({ tease: "沖繩機票訂了沒還是又拖了" }, set), []);
});

Deno.test("第五輪 A：自述被加上沒說的健康狀況；自介已知事實不得反轉", () => {
  const set = rawSet("我自己以前在寵物店打工過，現在沒有了");
  assertEquals(codes({ humor: "我以前在寵物店打工過\n現在只剩回憶跟過敏" }, set), ["humor:sender_fact_extended"]);
  const catSnapshot = { ...SNAPSHOT, profileText: { bio: "家裡貓比我早睡" } };
  const catSet = buildOpenerMaterials({ snapshot: catSnapshot, contribution: answered(null, "我對她的貓比較有興趣"), option: null });
  assertEquals(codes({ humor: "顧一隻晚睡的貓 妳幾條命" }, catSet, catSnapshot), ["humor:profile_fact_reversed"]);
});

Deno.test("第五輪 A：原料採用——有原料時可見卡至少一張要在內容上接住；純否定補充不要求；目標型要帶邀約", () => {
  const set = rawSet("她上次聊天提過想去沖繩，還沒訂");
  const openers = { extend: "河堤練滑板多久了", humor: "滑板技能點滿", tease: "沖繩機票訂了嗎", resonate: "假日固定練很自律", coldRead: "感覺妳計畫都放心裡" };
  assertEquals(checkMaterialAdoption({ openers, materials: set, visibleTypes: OPENER_TYPES, rankedPicks: ["extend", "humor", "tease", "resonate", "coldRead"] }), []);
  assertEquals(checkMaterialAdoption({ openers, materials: set, visibleTypes: OPENER_FREE_V2_TYPES, rankedPicks: ["extend", "humor", "tease", "resonate", "coldRead"] }), [], "Free 三卡裡 tease 有接住");
  // 只有鎖卡 resonate 接住：paid 可交付、Free 三卡一張都沒接住 → 標在排序第一的可見卡。
  const lockedOnly = { ...openers, tease: "假日河堤曬得挺黑的吧", resonate: "她提過想去沖繩 我懂那種還沒訂的心情" };
  assertEquals(checkMaterialAdoption({ openers: lockedOnly, materials: set, visibleTypes: OPENER_TYPES, rankedPicks: ["extend", "humor", "tease", "resonate", "coldRead"] }), []);
  assertEquals(checkMaterialAdoption({ openers: lockedOnly, materials: set, visibleTypes: OPENER_FREE_V2_TYPES, rankedPicks: ["extend", "humor", "tease", "resonate", "coldRead"] }).map((f) => `${f.style}:${f.code}`), ["extend:material_unused"]);
  // 被硬檢查標記的卡不算採用（主體顛倒／升級確定度）。
  const flaggedTease = { ...lockedOnly, tease: "說好要訂的沖繩機票咧" };
  const teaseFlag = hardFlags(checkOpenersAgainstMaterials(flaggedTease, set));
  assertEquals(teaseFlag.map((f) => f.code), ["certainty_upgraded"]);
  assertEquals(checkMaterialAdoption({ openers: flaggedTease, materials: set, visibleTypes: OPENER_FREE_V2_TYPES, rankedPicks: ["extend", "humor", "tease", "resonate", "coldRead"], flags: teaseFlag }).map((f) => `${f.style}:${f.code}`), ["extend:material_unused"]);
  const negOnly = rawSet("沒養過");
  assertEquals(checkMaterialAdoption({ openers: { extend: "牠散步會自己選路嗎" }, materials: negOnly, visibleTypes: OPENER_FREE_V2_TYPES, rankedPicks: ["extend"] }), [], "純否定補充：遵守就是採用");
  const goal = rawSet("我想約她喝咖啡");
  assertEquals(cardAdoptsMaterial("一天三杯咖啡 是靠什麼撐的", goal), false, "只提咖啡不算接住邀約目標");
  assertEquals(cardAdoptsMaterial("一天三杯 找一天一起喝一杯吧", goal), true);
});

// ── 第五輪 G1／G2 補修：排除與否定不是正向採用要求；主體／語者／陳述範圍。
const DOG_SNAPSHOT: OpenerAnalysisSnapshot = {
  ...SNAPSHOT,
  cues: [
    { id: "cue_1", label: "不給摸的柴犬", source: "profile_text", subject: "recipient", evidence: { field: "bio", quote: "養了一隻不給摸的柴犬" } },
    { id: "cue_2", label: "週末晚餐店", source: "profile_text", subject: "recipient" },
  ],
  question: {
    id: "question_1",
    affects: "sender_fact",
    text: "你跟狗這件事比較接近哪種？",
    options: [
      { id: "option_1", label: "我自己有養狗", meaning: "assert_sender_fact", cueId: "cue_1", statement: "我自己有養狗" },
      { id: "option_3", label: "其實想聊別的", meaning: "change_direction" },
      { id: "option_4", label: "不想聊狗", meaning: "exclude_cue", cueId: "cue_1" },
    ],
  },
  profileText: { bio: "養了一隻不給摸的柴犬，週末愛找晚餐店" },
};
const RANKED = ["extend", "humor", "tease", "resonate", "coldRead"] as const;
function adoptionCodes(openers: Record<string, string>, set: ReturnType<typeof rawSet>, snapshot = DOG_SNAPSHOT) {
  const flags = hardFlags(checkOpenersAgainstMaterials(openers, set, snapshot));
  return checkMaterialAdoption({ openers, materials: set, visibleTypes: OPENER_FREE_V2_TYPES, rankedPicks: RANKED, flags }).map((f) => `${f.style}:${f.code}`);
}

Deno.test("G1：選「不想聊狗」→ 改聊週末／晚餐不算 material_unused；提到狗仍是 excluded_topic_used", () => {
  const opt = DOG_SNAPSHOT.question!.options.find((o) => o.id === "option_4")!;
  const set = buildOpenerMaterials({ snapshot: DOG_SNAPSHOT, contribution: answered("option_4", null), option: opt });
  assertEquals(set.excludedTopics, ["不給摸的柴犬"]);
  const openers = { extend: "週末的晚餐店口袋名單借看一下", humor: "週末都在找晚餐店嗎", tease: "晚餐店踩雷率高嗎" };
  assertEquals(adoptionCodes(openers, set), []);
  assertEquals(codes({ extend: "不給摸的柴犬是傲嬌嗎" }, set, DOG_SNAPSHOT), ["extend:excluded_topic_used"], "排除仍要守");
});

Deno.test("G1：選「都沒興趣、聊別的」→ 合法新話題不算 material_unused；有補充方向時仍要接住", () => {
  const opt = DOG_SNAPSHOT.question!.options.find((o) => o.id === "option_3")!;
  const set = buildOpenerMaterials({ snapshot: DOG_SNAPSHOT, contribution: answered("option_3", null), option: opt });
  assertEquals(set.directionOverride, "fresh_topic");
  assertEquals(adoptionCodes({ extend: "板橋最近有沒有妳願意再去一次的店", humor: "週五晚上妳是充電派還是放電派", tease: "感覺妳很會安排時間" }, set), []);
  const withText = buildOpenerMaterials({ snapshot: DOG_SNAPSHOT, contribution: answered("option_3", "想聊她的旅遊"), option: opt });
  assertEquals(adoptionCodes({ extend: "板橋最近有沒有妳願意再去一次的店", humor: "週五晚上妳是充電派還是放電派", tease: "感覺妳很會安排時間" }, withText), ["extend:material_unused"], "用戶自己補的方向要被接住");
  assertEquals(adoptionCodes({ extend: "妳的旅遊照最想再去哪一站", humor: "週五晚上妳是充電派還是放電派", tease: "感覺妳很會安排時間" }, withText), []);
});

Deno.test("G1：「我不想約她，先聊咖啡」→ 不要求邀約，聊咖啡就是採用；「我想約她」仍要帶輕邀約", () => {
  const set = rawSet("我不想約她，先聊咖啡");
  assertEquals(cardAdoptsMaterial("一天三杯咖啡 是靠什麼撐的", set), true);
  assertEquals(cardAdoptsMaterial("找一天一起喝一杯吧", set), false, "邀約不是這次的目標");
  assertEquals(cardAdoptsMaterial("一天三杯咖啡 是靠什麼撐的", rawSet("我想約她喝咖啡")), false, "真正想約仍要帶邀約");
});

Deno.test("G2：「我以前在寵物店打工過，妳也在寵物店待過嗎」是問她、語者自持；沒有「我」的斷言仍是套到她身上", () => {
  const set = rawSet("我自己以前在寵物店打工過，現在沒有了");
  assertEquals(codes({ humor: "我以前在寵物店打工過，妳也在寵物店待過嗎？" }, set), []);
  assertEquals(codes({ extend: "在寵物店打工過才想當獸醫助理喔" }, set), ["extend:sender_fact_transposed"]);
  assertEquals(codes({ extend: "妳也在寵物店打工過三年嗎" }, set), ["extend:sender_fact_transposed"], "沒有用「我」先說出來，不能只靠問句放行");
});

Deno.test("G2：「沖繩機票已經訂好了嗎」是在問；「已經訂好了」陳述與「說好要訂」預設都是升級", () => {
  const set = rawSet("她上次聊天提過想去沖繩，還沒訂");
  assertEquals(codes({ tease: "沖繩機票已經訂好了嗎？" }, set), []);
  assertEquals(codes({ tease: "已經訂好沖繩了 什麼時候飛" }, set), ["tease:certainty_upgraded"]);
  assertEquals(codes({ tease: "說好要訂的沖繩機票訂了嗎" }, set), ["tease:certainty_upgraded"], "問句裡的「說好」仍是預設她承諾過");
});

Deno.test("G2：「貓比我早睡」→「妳比貓晚睡」同一件事；「晚睡的貓」「你家貓比你晚睡嗎」才是反轉", () => {
  const catSnapshot = { ...SNAPSHOT, profileText: { bio: "白天對數字\n最近在學調酒 家裡貓比我早睡" } };
  const set = buildOpenerMaterials({ snapshot: catSnapshot, contribution: answered(null, "我對她的貓比較有興趣"), option: null });
  assertEquals(codes({ humor: "妳比貓晚睡，牠會先去躺好嗎？", tease: "貓比妳早睡是貓在管妳吧" }, set, catSnapshot), []);
  assertEquals(codes({ extend: "你家貓晚上比你晚睡嗎？", humor: "顧一隻晚睡的貓 妳幾條命" }, set, catSnapshot), ["extend:profile_fact_reversed", "humor:profile_fact_reversed"]);
  const earlySnapshot = { ...SNAPSHOT, profileText: { bio: "早睡早起型" } };
  const earlySet = buildOpenerMaterials({ snapshot: earlySnapshot, contribution: answered(null, "想聊她的作息"), option: null });
  assertEquals(codes({ extend: "妳是晚睡派吧" }, earlySet, earlySnapshot), ["extend:profile_fact_reversed"], "沒寫主體的自介事實歸她本人");
});

Deno.test("G2：「順帶一提：我也養狗」不能因冒號放行；柴犬／牠說的才是代言；沒有說話者的引文不放行", () => {
  const skipped = buildOpenerMaterials({ snapshot: DOG_SNAPSHOT, contribution: { state: "skipped", questionId: null, selectedOptionId: null, freeText: null }, option: null });
  assertEquals(codes({ resonate: "順帶一提：我也養狗" }, skipped, DOG_SNAPSHOT), ["resonate:fabricated_sender_fact"]);
  assertEquals(codes({ humor: "柴犬：我養妳不是讓妳摸的", tease: "柴犬說：「我不是給你摸的」", extend: "牠的表情像在說「我也養人」", coldRead: "妳家那隻不給摸的柴犬：我只是高冷" }, skipped, DOG_SNAPSHOT), []);
  assertEquals(codes({ coldRead: "「我也養狗」這句我先收回" }, skipped, DOG_SNAPSHOT), ["coldRead:fabricated_sender_fact"]);
});

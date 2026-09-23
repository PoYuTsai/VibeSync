// opener_flow_payload.ts：第二段結果正規化、權益投影、來源核對狀態（附件 F13、§9.4、§10.7）。
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  isValidOpenerGenerateLedgerResult,
  mergeOpenerCorrection,
  normalizeOpenerGenerateOutput,
  projectOpenerGenerateResult,
} from "./opener_flow_payload.ts";
import { buildOpenerMaterials } from "./opener_material.ts";
import { OPENER_FREE_V2_TYPES, OPENER_TYPES } from "./opener_payload.ts";
import type { OpenerAnalysisSnapshot } from "./opener_stage.ts";

const SNAPSHOT: OpenerAnalysisSnapshot = {
  approach: { mode: "anchor_hooks", summary: "可以從她的狗開", avoid: [] },
  cues: [{ id: "cue_1", label: "養狗", source: "profile_text", subject: "recipient" }],
  question: null,
  profileDigest: "有養一隻狗",
  profileText: { bio: "有養一隻狗" },
  imageCount: 0,
  initialNoteProvided: false,
  initialNoteFingerprint: null,
  promptVersion: "v1",
};

const answeredMaterials = buildOpenerMaterials({
  snapshot: SNAPSHOT,
  contribution: { state: "answered", questionId: null, selectedOptionId: null, freeText: "沒養過，只想知道牠散步會不會自己選路" },
  option: null,
});
const skippedMaterials = buildOpenerMaterials({
  snapshot: SNAPSHOT,
  contribution: { state: "skipped", questionId: null, selectedOptionId: null, freeText: null },
  option: null,
});

function modelOutput(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    materialReading: [{ materialId: "material_1", subject: "sender", kind: "raw_sentence", certainty: "stated", quote: "沒養過" }],
    openers: {
      extend: "牠散步會自己選路嗎",
      resonate: "養這種狗的人假日應該都在外面",
      tease: "你家狗看起來比你會安排行程",
      humor: "妳家狗是導航派還是隨機派",
      coldRead: "妳應該是被牠帶著走的那種主人",
    },
    cardReasons: {
      extend: "直接問你想知道的事，也沒有寫成你養過狗",
      resonate: "站在她的處境說話",
      tease: "輕輕戳她的狗",
      humor: "把你好奇的散步習慣變成可愛的問題",
      coldRead: "可被反駁的輕觀察",
    },
    rankedPicks: ["resonate", "extend", "humor", "tease", "coldRead"],
    materialUse: {
      references: [
        { style: "resonate", materialId: "material_1", outputSpan: "假日" },
        { style: "extend", materialId: "material_1", outputSpan: "散步會自己選路" },
        { style: "humor", materialId: "material_1", outputSpan: "導航派" },
      ],
      displayNotes: {
        resonate: "共鳴卡的說明（鎖卡，不得外流）",
        extend: "這句接的是你想知道的散步習慣",
      },
    },
    stretchLevels: { extend: "within", resonate: "stretch", tease: "within", humor: "within", coldRead: "far" },
    pioneerPlan: { ifCold: "先停一下", handoff: "她回了就貼回分析" },
    profileAnalysis: { positiveHooks: ["養狗"], avoidTopics: [], openingStrategy: "先接狗" },
    ...overrides,
  };
}

Deno.test("正規化：五句不齊→incomplete；齊全→rankedPicks 補齊五種、reference 片段用同一條正規化（你→妳）", () => {
  const incomplete = normalizeOpenerGenerateOutput(modelOutput({ openers: { extend: "只有一句" } }), answeredMaterials);
  assert(!incomplete.ok && incomplete.reason === "incomplete_openers" && incomplete.missing.length === 4);
  const ok = normalizeOpenerGenerateOutput(modelOutput({ rankedPicks: ["humor"] }), answeredMaterials);
  assert(ok.ok);
  assertEquals(ok.value.rankedPicks.length, 5);
  assertEquals(ok.value.rankedPicks[0], "humor");
  // 模型寫「你家狗」，句子正規化成「妳家狗」；片段也走同一條正規化才對得上。
  assertEquals(ok.value.openers.tease, "妳家狗看起來比妳會安排行程");
  const withYou = normalizeOpenerGenerateOutput(modelOutput({
    materialUse: { references: [{ style: "tease", materialId: "material_1", outputSpan: "你家狗" }], displayNote: null },
  }), answeredMaterials);
  assert(withYou.ok);
  assertEquals(withYou.value.references, [{ style: "tease", materialId: "material_1", outputSpan: "妳家狗" }]);
});

Deno.test("F13／§9.4：Free 先篩可見卡，再從可見卡選推薦、用那張卡自己的理由；鎖卡的句子、理由、引用不外流", () => {
  const normalized = normalizeOpenerGenerateOutput(modelOutput(), answeredMaterials);
  assert(normalized.ok);
  const projected = projectOpenerGenerateResult({ normalized: normalized.value, materials: answeredMaterials, visibleTypes: OPENER_FREE_V2_TYPES, servedTier: "free", contractVersion: 2 });
  assert(projected);
  assertEquals(Object.keys(projected.openers).sort(), ["extend", "humor", "tease"]);
  // 模型第一名 resonate 被鎖 → 取下一個可見的 extend，理由是 extend 自己的。
  assertEquals(projected.recommendation, { pick: "extend", reason: "直接問你想知道的事，也沒有寫成你養過狗" });
  assertEquals(projected.recommendedPick, "extend");
  assertEquals(Object.keys(projected.cardReasons).sort(), ["extend", "humor", "tease"]);
  assertEquals(projected.materialUse.references.map((r) => r.style), ["extend", "humor"]);
  assertEquals(projected.materialUse.traceStatus, "matched");
  assertEquals(projected.materialUse.displayNote, "這句接的是你想知道的散步習慣", "採用說明綁最終可見 pick");
  assertEquals(JSON.stringify(projected).includes("鎖卡，不得外流"), false, "鎖卡自己的說明不得外流");
  assertEquals(projected.materialUse.inputState, "answered");
  assertEquals(projected.access.lockedTypes, ["resonate", "coldRead"]);
  assertEquals(Object.keys(projected.stretchLevels).sort(), ["extend", "humor", "tease"]);
  assertEquals(JSON.stringify(projected).includes("養這種狗的人"), false, "鎖卡文字不得出現在結果任何地方");
  assert(isValidOpenerGenerateLedgerResult(projected));
});

Deno.test("付費五卡：模型第一名沒在內容上接住原料就往下找（第五輪 A）；沒有原料時第一名直接採用", () => {
  const normalized = normalizeOpenerGenerateOutput(modelOutput(), answeredMaterials);
  assert(normalized.ok);
  const projected = projectOpenerGenerateResult({ normalized: normalized.value, materials: answeredMaterials, visibleTypes: OPENER_TYPES, servedTier: "essential", contractVersion: 2 });
  assert(projected);
  // 模型排第一的 resonate「養這種狗的人假日應該都在外面」沒有用到「散步會不會自己選路」；extend 有。
  assertEquals(projected.recommendation.pick, "extend");
  assertEquals(projected.recommendation.reason, "直接問你想知道的事，也沒有寫成你養過狗");
  assertEquals(projected.materialUse.references.length, 3);
  assertEquals(projected.materialUse.traceStatus, "matched");

  const skipped = normalizeOpenerGenerateOutput(modelOutput(), skippedMaterials);
  assert(skipped.ok);
  const noInput = projectOpenerGenerateResult({ normalized: skipped.value, materials: skippedMaterials, visibleTypes: OPENER_TYPES, servedTier: "essential", contractVersion: 2 });
  assertEquals(noInput?.recommendation.pick, "resonate", "沒有原料時照模型排序");
});

Deno.test("traceStatus：無有效原料→no_input（displayNote 一律 null）；推薦卡沒有來源紀錄→uncertain", () => {
  const skipped = normalizeOpenerGenerateOutput(modelOutput(), skippedMaterials);
  assert(skipped.ok);
  const noInput = projectOpenerGenerateResult({ normalized: skipped.value, materials: skippedMaterials, visibleTypes: OPENER_TYPES, servedTier: "essential", contractVersion: 2 });
  assertEquals(noInput?.materialUse.traceStatus, "no_input");
  assertEquals(noInput?.materialUse.displayNote, null);
  assertEquals(noInput?.materialUse.references, [], "沒有原料就沒有可對上的引用");

  const missingPick = normalizeOpenerGenerateOutput(modelOutput({
    materialUse: { references: [{ style: "humor", materialId: "material_1", outputSpan: "導航派" }], displayNotes: { extend: "不該顯示", humor: "也不該顯示" } },
  }), answeredMaterials);
  assert(missingPick.ok);
  const uncertain = projectOpenerGenerateResult({ normalized: missingPick.value, materials: answeredMaterials, visibleTypes: OPENER_FREE_V2_TYPES, servedTier: "free", contractVersion: 2 });
  assertEquals(uncertain?.recommendation.pick, "extend");
  assertEquals(uncertain?.materialUse.traceStatus, "uncertain");
  assertEquals(uncertain?.materialUse.displayNote, null, "不確定就不顯示肯定的採用說明");
});

Deno.test("內容修正合併：只換被標記的句子與理由，其餘逐字保留；被換句子的舊引用丟掉", () => {
  const original = modelOutput();
  const corrected = {
    openers: { extend: "改過的延展", resonate: "偷改共鳴不該被採用" },
    cardReasons: { extend: "改過的理由" },
    materialUse: {
      references: [{ style: "extend", materialId: "material_1", outputSpan: "改過" }, { style: "resonate", materialId: "material_1", outputSpan: "x" }],
      displayNotes: { extend: "改過後的說明", resonate: "偷改的說明" },
    },
  };
  const merged = mergeOpenerCorrection(original, corrected, ["extend"]);
  const notes = (merged.materialUse as { displayNotes: Record<string, string> }).displayNotes;
  assertEquals(notes, { resonate: "共鳴卡的說明（鎖卡，不得外流）", extend: "改過後的說明" }, "只換被標記卡的說明");
  const openers = merged.openers as Record<string, string>;
  assertEquals(openers.extend, "改過的延展");
  assertEquals(openers.resonate, "養這種狗的人假日應該都在外面");
  assertEquals((merged.cardReasons as Record<string, string>).extend, "改過的理由");
  const refs = (merged.materialUse as { references: Array<{ style: string; outputSpan: string }> }).references;
  assertEquals(refs.map((r) => `${r.style}:${r.outputSpan}`), ["resonate:假日", "humor:導航派", "extend:改過"]);
  assertEquals(mergeOpenerCorrection(original, null, ["extend"]), original);
});

Deno.test("回放結果驗證：缺 openers／推薦不在可見卡／空句一律不合法", () => {
  assert(!isValidOpenerGenerateLedgerResult(null));
  assert(!isValidOpenerGenerateLedgerResult({ openers: {}, recommendation: { pick: "extend" }, access: { servedTier: "free", visibleTypes: [] }, materialUse: {} }));
  assert(!isValidOpenerGenerateLedgerResult({ openers: { extend: "x" }, recommendation: { pick: "humor" }, access: { servedTier: "free", visibleTypes: [] }, materialUse: {} }));
  assert(isValidOpenerGenerateLedgerResult({ openers: { extend: "x" }, recommendation: { pick: "extend" }, access: { servedTier: "free", visibleTypes: ["extend"] }, materialUse: {} }));
});

Deno.test("R3：模型只給整包 displayNote（未綁卡）→ 不採用；pick 沒有自己的說明→null", () => {
  const legacyNote = normalizeOpenerGenerateOutput(modelOutput({
    materialUse: { references: [{ style: "extend", materialId: "material_1", outputSpan: "散步會自己選路" }, { style: "humor", materialId: "material_1", outputSpan: "導航派" }], displayNote: "整包全域說明" },
  }), answeredMaterials);
  assert(legacyNote.ok);
  const projected = projectOpenerGenerateResult({ normalized: legacyNote.value, materials: answeredMaterials, visibleTypes: OPENER_FREE_V2_TYPES, servedTier: "free", contractVersion: 2 });
  assertEquals(projected?.materialUse.traceStatus, "matched");
  assertEquals(projected?.materialUse.displayNote, null);
});

Deno.test("教練型 Opener：明確要求邀約時，說明要在最終可見推薦的理由裡；推薦由系統依方案選，所以五張理由都要帶", () => {
  const snapshot: OpenerAnalysisSnapshot = {
    ...SNAPSHOT,
    cues: [{ id: "cue_1", label: "密室逃脫", source: "profile_text", subject: "recipient" }],
    profileDigest: "密室逃脫玩了快五十間",
    profileText: { bio: "密室逃脫玩了快五十間，最怕恐怖主題" },
  };
  const project = (text: string, ranked: string[], cardReasons: Record<string, string>, visibleTypes: typeof OPENER_TYPES | typeof OPENER_FREE_V2_TYPES) => {
    const materials = buildOpenerMaterials({ snapshot, contribution: { state: "answered", questionId: null, selectedOptionId: null, freeText: text }, option: null });
    const normalized = normalizeOpenerGenerateOutput(modelOutput({
      materialReading: [{ materialId: "material_1", subject: "unknown", kind: "raw_sentence", certainty: "stated", quote: text, usage: [{ quote: text, action: "use" }] }],
      openers: { extend: "五十間裡最推哪一間", resonate: "密室最怕恐怖主題還硬上 這很勇", tease: "五十間了 應該是隊上的大腦吧", humor: "恐怖主題是閉著眼睛解謎嗎", coldRead: "妳應該是負責找線索的那個" },
      cardReasons, rankedPicks: ranked, materialUse: { references: [], displayNotes: {} },
    }), materials, true);
    assert(normalized.ok);
    return projectOpenerGenerateResult({ normalized: normalized.value, materials, visibleTypes, servedTier: visibleTypes.length === 3 ? "free" : "essential", contractVersion: 2 })!;
  };
  const note = "這裡先從密室逃脫開話題，不把第一句寫成邀約";
  const direct = "第一句就直接約她去玩密室逃脫";
  const ranked = ["resonate", "extend", "tease", "humor", "coldRead"];
  // 只寫在模型自己的第一名：Free 看不到 resonate，推薦改成 extend，說明就不見了。
  const onlyTop = project(direct, ranked, { resonate: note, extend: "接她玩過五十間，好回答" }, OPENER_FREE_V2_TYPES);
  assertEquals([onlyTop.recommendation.pick, onlyTop.recommendation.reason], ["extend", "接她玩過五十間，好回答"]);
  // 五張都帶（prompt 契約）：Free 與付費的最終推薦理由都有說明，說明不在開場句裡。
  const all = Object.fromEntries(["extend", "resonate", "tease", "humor", "coldRead"].map((t) => [t, `${note}；接她的密室經驗`]));
  for (const visibleTypes of [OPENER_FREE_V2_TYPES, OPENER_TYPES]) {
    const projected = project(direct, ranked, all, visibleTypes);
    assert(projected.recommendation.reason?.includes(note), `${visibleTypes.length} 卡：推薦理由要有說明`);
    assert(Object.values(projected.openers).every((text) => !text?.includes("邀約")));
  }
  // 想約＋想問：推薦被話題證據改到非模型第一名，五張都帶才落得到最終推薦。
  const mix = project("想約她去密室逃脫，想問她最怕哪種主題", ["extend", "humor", "tease", "resonate", "coldRead"], all, OPENER_TYPES);
  assertEquals(mix.recommendation.pick, "humor");
  assert(mix.recommendation.reason?.includes(note));
});

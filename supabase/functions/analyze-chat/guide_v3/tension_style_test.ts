// 帶張力改寫法 v2（開關 ANALYZE_GUIDE_V3_TENSION_STYLE，Bruce 2026-10-21「改」）的提示詞：排卡不變，寫卡與
// 說明看到的帶張力照兩段式原本的寫法，只把推拉那一條換成三條不要（不打分、不說她別有用意、不擺自己比較厲害）。
// 沒開時一字不變。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  a5Bullet,
  explainSystemPrompt,
  explainUserPrompt,
  TENSION_STYLE_EXPLAIN_RULE,
  TENSION_STYLE_EXPLAIN_SENTINELS,
  vetExplanation,
} from "./explain.ts";
import { GUIDE_V3_SECTIONS } from "./guide_text.ts";
import type { ReadTags } from "./read_tags.ts";
import type { CardSpec } from "./rules.ts";
import {
  TENSION_STYLE_A5_EDITS,
  TENSION_STYLE_LINE,
  TENSION_STYLE_WRITER_SENTINELS,
  TWO_STAGE_TENSION_LINE,
  twoStageWriterSections,
  writeSystemPromptTwoStage,
} from "./two_stage_prompts.ts";

const tensionBlock = (a5: string) => a5Bullet("帶張力", a5);
const OFF_A5 = twoStageWriterSections().A5;
const ON_A5 = twoStageWriterSections(undefined, { tensionStyle: true }).A5;

Deno.test("帶張力改寫法：沒開（沒給或 false）時寫卡的系統提示詞與 A5 跟今天一字不差", () => {
  const off = writeSystemPromptTwoStage();
  assertEquals(
    writeSystemPromptTwoStage(undefined, undefined, undefined, {
      tensionStyle: false,
    }),
    off,
  );
  assertEquals(twoStageWriterSections(undefined, {}).A5, OFF_A5);
  assert(OFF_A5.includes(TWO_STAGE_TENSION_LINE));
});

Deno.test("帶張力改寫法 v2 開：推拉那一條在同一個位置換成三條不要；帶張力的定義、材料、手法、虧事不虧人、力道看她照兩段式原本的寫法；A5 其他地方不變", () => {
  const on = tensionBlock(ON_A5);
  const off = tensionBlock(OFF_A5);
  assert(off.includes("\n  - 推拉："));
  // 只換推拉那一行，其他行（含材料的矛盾疑點、手法的刻意誤解）照留，順序不變。
  assertEquals(
    on.split("\n"),
    off.split("\n").map((l) =>
      l.startsWith("  - 推拉：") ? TENSION_STYLE_LINE : l
    ),
  );
  assert(on.startsWith(TWO_STAGE_TENSION_LINE));
  for (
    const kept of ["矛盾、疑點", "刻意誤解", "  - 虧她做的事", "  - 力道看她"]
  ) {
    assert(on.includes(kept), kept);
  }
  for (const gone of ["  - 推拉：", "挑戰只在", "用反話表達喜歡"]) {
    assertEquals(on.includes(gone), false, gone);
  }
  // 帶張力那一段之外，A5 一字不變。
  assertEquals(ON_A5.replace(on, off), OFF_A5);
  // 寫卡的系統提示詞只差 A5 那一段。
  const sysOff = writeSystemPromptTwoStage();
  const sysOn = writeSystemPromptTwoStage(undefined, undefined, undefined, {
    tensionStyle: true,
  });
  assertEquals(sysOn.replace(ON_A5, OFF_A5), sysOff);
  assertEquals(TENSION_STYLE_A5_EDITS.length, 1);
});

Deno.test("帶張力改寫法 v2 的說法：只有 Bruce 那三條不要（打分、說她別有用意、擺自己比較厲害），是帶張力底下的一條、不放例句", () => {
  for (
    const words of ["不替她打分", "不說她別有用意", "不把自己擺得比較厲害"]
  ) {
    assert(TENSION_STYLE_LINE.includes(words), words);
  }
  // 縮排的子項目，說明步驟取帶張力那一條時才會連著帶到。
  assert(TENSION_STYLE_LINE.startsWith("  - "));
  for (const line of [TENSION_STYLE_LINE, TENSION_STYLE_EXPLAIN_RULE]) {
    assertEquals(/[「」]/.test(line), false, line);
  }
});

Deno.test("帶張力改寫法：卡片與說明多比的哨兵都照抄自新加的那幾行，而且夠長（共用比對不比 8 字以下的）", () => {
  for (const s of TENSION_STYLE_WRITER_SENTINELS) {
    assert(TENSION_STYLE_LINE.includes(s), s);
    assert([...s.replace(/[、，。：；（）]/g, "")].length >= 8, s);
  }
  for (const s of TENSION_STYLE_EXPLAIN_SENTINELS) {
    assert(TENSION_STYLE_EXPLAIN_RULE.includes(s), s);
    assert([...s.replace(/[、，。：；（）]/g, "")].length >= 8, s);
  }
});

function tags(): Pick<ReadTags, "light" | "herMove" | "readForUser"> {
  return { light: "green", herMove: "生活", readForUser: "她願意聊。" };
}

const SPEC = (task: CardSpec["task"]): CardSpec => ({
  task,
  method: "只用反應",
  voice: "預設",
  questionBudget: 1,
  push: null,
  angle: 0,
});

Deno.test("說明步驟：帶張力改寫法開時多一條說明規則；帶張力那一條改用寫卡看到的新寫法，其他任務照說明書原文；沒開跟今天一樣", () => {
  const sysOff = explainSystemPrompt();
  assertEquals(
    explainSystemPrompt(undefined, undefined, { tensionStyle: false }),
    sysOff,
  );
  const sysOn = explainSystemPrompt(undefined, undefined, {
    tensionStyle: true,
  });
  assert(sysOn.includes(TENSION_STYLE_EXPLAIN_RULE));
  assertEquals(sysOn.replace(`\n${TENSION_STYLE_EXPLAIN_RULE}`, ""), sysOff);
  const args = {
    tags: tags(),
    herLatest: ["你咧"],
    entries: [],
    cards: [
      { slot: 1, spec: SPEC("接住"), messages: ["好啊"] },
      { slot: 2, spec: SPEC("帶張力"), messages: ["這碗是不是偷偷加了魔法"] },
    ],
  };
  const userOff = explainUserPrompt(args);
  const userOn = explainUserPrompt({ ...args, tensionStyle: true });
  const original = a5Bullet("帶張力", GUIDE_V3_SECTIONS.A5);
  assert(userOff.includes(original));
  assertEquals(userOn.includes(original), false);
  assert(userOn.includes(tensionBlock(ON_A5)));
  assertEquals(userOn.replace(tensionBlock(ON_A5), original), userOff);
  // 接住照說明書原文。
  assert(userOn.includes(a5Bullet("接住", GUIDE_V3_SECTIONS.A5)));
});

Deno.test("說明步驟：帶張力改寫法開時，照抄新規則的說明不給；一般說明照給；沒開跟今天一樣", () => {
  const copied = `這張好笑，${TENSION_STYLE_EXPLAIN_RULE.slice(2, 30)}。`;
  assertEquals(vetExplanation(copied).ok, true);
  assertEquals(
    vetExplanation(copied, TENSION_STYLE_EXPLAIN_SENTINELS),
    { ok: false, reason: "blocked" },
  );
  assertEquals(
    vetExplanation(
      "這張的玩笑對那碗拉麵本身開，她好接。",
      TENSION_STYLE_EXPLAIN_SENTINELS,
    ),
    { ok: true, text: "這張的玩笑對那碗拉麵本身開，她好接。" },
  );
});

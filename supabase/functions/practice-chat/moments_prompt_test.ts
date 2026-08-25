// 動態貼文 prompt 的硬約束契約。
//
// 兩件事在這裡被機械證明：
// 1. **隱私鐵則**：buildMomentMessages 只吃 server profile + 題材 + 時段 +
//    候選 imageId。函式簽名本身就沒有塞得下對話的地方，這裡再驗一次產出
//    的訊息裡確實只有 server 事實。
// 2. **注入標籤必登記**：prompt 內用到的每一個內部標籤，都必須被
//    visible_text_guard 的可見輸出守門攔得到。漏登記＝模型原樣抄進貼文時
//    沒人攔。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildMomentMessages,
  MOMENT_INTERNAL_LABELS,
  MOMENT_PROMPT_SENTINELS,
} from "./moments_prompt.ts";
import { hasVisibleInternalLabelLeak } from "./visible_text_guard.ts";
import { containsPromptLeak } from "../_shared/prompt_leak_guard.ts";
import {
  MOMENT_PROMPT_MAX_CHARS,
  MOMENT_PROMPT_MIN_CHARS,
} from "./moments_constants.ts";
import { SELF_PORTRAIT_IMAGE_ID } from "./moments_image_catalog.ts";
import { GIRL_PROFILES } from "./practice_persona.ts";

const girl = GIRL_PROFILES[6];

function build(imageCandidates: readonly string[] = []) {
  return buildMomentMessages({
    girl,
    themeId: "coffee_break",
    brief: "在常去的咖啡店坐一下，看窗外發呆",
    dayPart: "afternoon",
    isoDate: "2026-08-22",
    isWeekend: true,
    slot: 0,
    imageCandidates,
  });
}

function joined(messages: { content: string }[]): string {
  return messages.map((m) => m.content).join("\n");
}

Deno.test("訊息結構是 system + user，兩則都非空", () => {
  const messages = build();
  assertEquals(messages.length, 2);
  assertEquals(messages[0].role, "system");
  assertEquals(messages[1].role, "user");
  for (const message of messages) {
    assert(message.content.trim().length > 0);
  }
});

Deno.test("system 段帶入 server profile 事實", () => {
  const text = joined(build());
  assert(text.includes(girl.displayName));
  assert(text.includes(girl.city));
  assert(text.includes(girl.professionLabel));
  assert(text.includes(String(girl.age)));
  // 2026-08-25 起個性不再用 personalityTags 列舉——那行「語氣要像：活潑、溫柔」
  // 正是每個角色寫出同一種日記體的病根，已被 persona 語感層取代。
  // 興趣與生活習慣仍是內容的土壤，必須在場。
  for (const tag of [...girl.interestTags, ...girl.lifestyleTags]) {
    assert(text.includes(tag), `內容素材 ${tag} 應該進 prompt`);
  }
});

Deno.test("字數指示與 moments_constants 的 prompt 層數字一致", () => {
  const text = joined(build());
  assert(
    text.includes(`${MOMENT_PROMPT_MIN_CHARS}`) &&
      text.includes(`${MOMENT_PROMPT_MAX_CHARS}`),
    "prompt 必須明講 20-60 字，不能跟常數脫鉤",
  );
});

Deno.test("硬約束逐條寫進 prompt：繁中、第一人稱、禁第二人稱、禁提問、禁真實品牌", () => {
  const text = joined(build());
  for (
    const rule of ["繁體中文", "第一人稱", "「你」", "「妳」", "問句", "品牌"]
  ) {
    assert(text.includes(rule), `prompt 缺少硬約束：${rule}`);
  }
});

Deno.test("掛上 PROMPT_LEAK_DEFENSE_DIRECTIVE", () => {
  const text = joined(build());
  assert(text.includes("系統指示保密（最高優先"));
});

Deno.test("prompt sentinel 真的抓得到自己的 prompt 外洩", () => {
  const text = joined(build());
  assert(MOMENT_PROMPT_SENTINELS.length > 0);
  for (const sentinel of MOMENT_PROMPT_SENTINELS) {
    assert(
      sentinel.replace(/\s+/g, "").length >= 8,
      `sentinel 太短會被 containsPromptLeak 忽略：${sentinel}`,
    );
    assert(text.includes(sentinel), `sentinel 不在 prompt 內：${sentinel}`);
    assert(containsPromptLeak(sentinel, MOMENT_PROMPT_SENTINELS));
  }
  assertEquals(
    containsPromptLeak("今天的咖啡比鬧鐘有用", MOMENT_PROMPT_SENTINELS),
    false,
  );
});

Deno.test("注入的每一個內部標籤都已登記進可見輸出守門", () => {
  assert(MOMENT_INTERNAL_LABELS.length > 0);
  const text = joined(build([SELF_PORTRAIT_IMAGE_ID]));
  for (const label of MOMENT_INTERNAL_LABELS) {
    assert(text.includes(label), `標籤 ${label} 宣告了卻沒真的注入 prompt`);
    assert(
      hasVisibleInternalLabelLeak(label),
      `標籤 ${label} 沒有登記進 visible_text_guard，模型抄出來時沒人攔`,
    );
  }
});

Deno.test("有候選圖時：明講會配上她自己的照片，且候選 id 進 prompt", () => {
  const text = joined(build([SELF_PORTRAIT_IMAGE_ID]));
  assert(text.includes(SELF_PORTRAIT_IMAGE_ID));
  // 圖決定文：模型要先知道會配自拍，文案才不會出現「宵夜」配大頭照的違和。
  assert(text.includes("你自己的照片") || text.includes("自拍"));
});

Deno.test("沒有候選圖時：明確要求 imageId 必須是 null，且不出現任何圖 id", () => {
  const text = joined(build([]));
  assert(text.includes("null"));
  assertEquals(text.includes(SELF_PORTRAIT_IMAGE_ID), false);
  assertEquals(text.includes("moment_coffee_cup"), false);
});

Deno.test("輸出契約明講只回 JSON 的 text 與 imageId", () => {
  const text = joined(build());
  assert(text.includes('"text"'));
  assert(text.includes('"imageId"'));
});

Deno.test("題材、時段、週末與否都是 server 事實，逐項進 prompt", () => {
  const text = joined(build());
  assert(text.includes("在常去的咖啡店坐一下，看窗外發呆"));
  assert(text.includes("coffee_break"));
  assert(text.includes("週末"));
});

Deno.test("整份角色名冊都建得出 prompt，且長度有界", () => {
  for (const profile of GIRL_PROFILES) {
    const messages = buildMomentMessages({
      girl: profile,
      themeId: "evening_walk",
      brief: "晚上出門走走",
      dayPart: "evening",
      isoDate: "2026-08-22",
      isWeekend: false,
      slot: 0,
      imageCandidates: [],
    });
    const size = joined(messages).length;
    assert(size > 200, `${profile.profileId} 的 prompt 太短：${size}`);
    assert(size < 4000, `${profile.profileId} 的 prompt 太長：${size}`);
  }
});

// ---------------------------------------------------------------------------
// 語感層（2026-08-25，Eric：貼文乏味、角色不夠鮮明）
// ---------------------------------------------------------------------------

import { MOMENT_POST_SHAPES, momentShapeFor } from "./moments_prompt.ts";
import { PERSONAS } from "./practice_persona.ts";

Deno.test("每一種 persona 都有自己的語感，缺一種都編不過也測不過", () => {
  // Record<PersonaId, string> 已在編譯期強制；這裡再驗 runtime 內容非空且彼此不同。
  const voices = new Set<string>();
  for (const persona of PERSONAS) {
    const profile = GIRL_PROFILES.find((g) => g.personaId === persona.id);
    assert(profile, `名冊裡沒有任何角色用 persona ${persona.id}`);
    const sys = buildMomentMessages({
      girl: profile,
      themeId: "coffee_break",
      brief: "在常去的咖啡店坐一下",
      dayPart: "afternoon",
      isoDate: "2026-08-22",
      isWeekend: true,
      slot: 0,
      imageCandidates: [],
    })[0].content;
    assert(sys.includes("你打字的樣子"), "語感注入段落不在 system prompt 裡");
    const voiceLine = sys.split("你打字的樣子")[1].split("\n")[0];
    assert(voiceLine.length > 20, `persona ${persona.id} 的語感內容太短`);
    voices.add(voiceLine);
  }
  assert(
    voices.size === PERSONAS.length,
    `五種 persona 只做出 ${voices.size} 種語感——有人共用了同一個聲音`,
  );
});

Deno.test("切入形狀：同一 slot 決定性，跨角色跨日期會把六種形狀全用到", () => {
  assertEquals(
    momentShapeFor("practice_girl_001", "2026-08-22", 0),
    momentShapeFor("practice_girl_001", "2026-08-22", 0),
  );
  const seen = new Set<string>();
  for (const profile of GIRL_PROFILES) {
    for (const day of ["2026-08-22", "2026-08-23", "2026-08-24"]) {
      for (const slot of [0, 1]) {
        seen.add(momentShapeFor(profile.profileId, day, slot));
      }
    }
  }
  assertEquals(
    seen.size,
    MOMENT_POST_SHAPES.length,
    "取樣 600 個 slot 仍有形狀沒被輪到——種子分佈壞了",
  );
});

Deno.test("選中的形狀真的進了 prompt，且同角色兩個 slot 可以拿到不同形狀", () => {
  const sys = buildMomentMessages({
    girl,
    themeId: "coffee_break",
    brief: "在常去的咖啡店坐一下",
    dayPart: "afternoon",
    isoDate: "2026-08-22",
    isWeekend: true,
    slot: 0,
    imageCandidates: [],
  })[0].content;
  assert(
    sys.includes(momentShapeFor(girl.profileId, "2026-08-22", 0)),
    "prompt 裡的形狀與種子選出的不一致",
  );
  // 至少存在一位角色某天兩個 slot 形狀不同（不是所有 slot 共用一種）。
  const someoneDiffers = GIRL_PROFILES.some((p) =>
    momentShapeFor(p.profileId, "2026-08-22", 0) !==
      momentShapeFor(p.profileId, "2026-08-22", 1)
  );
  assert(someoneDiffers, "所有角色兩個 slot 都同形狀——輪替失效");
});

Deno.test("反平淡三守則寫進 prompt：禁昇華結尾、標點自由、真人優先", () => {
  const sys = build()[0].content;
  assert(sys.includes("不准總結"), "缺「結尾不准總結」");
  assert(sys.includes("不准昇華"), "缺「不准昇華」");
  assert(sys.includes("標點自由"), "缺「標點自由」");
  assert(
    sys.includes("像真人隨手打的」優先"),
    "缺自由度宣告（規則是邊界不是模板）",
  );
});

Deno.test("語感與形狀的文字本身不含例句彈藥：不得出現第二人稱與問號結尾素材", () => {
  // no-canned 的 prompt 層守門：注入文字若含「你/妳」或以問號收尾的句子，
  // 模型照抄時會直接踩 validator；這裡確保我們自己沒遞刀。
  for (const shape of MOMENT_POST_SHAPES) {
    assertEquals(/[你妳]/u.test(shape), false, `形狀含第二人稱：${shape}`);
    assertEquals(/[?？]$/u.test(shape), false, `形狀以問號收尾：${shape}`);
  }
});

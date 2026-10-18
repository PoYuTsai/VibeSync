// 每一份外洩哨兵清單的每一句（主審兩輪 P2，Eric 2026-10-18）：原樣、每個字後面插空白、簡體、
// 簡體插空白、簡體轉回繁體、轉回繁體再插空白，夾在一般句子裡、後面緊接著能跟最後一個字湊成詞的字、
// 或詞組跨過頭尾，都要抓得到（主審 r2 P2）；一般聊天與 repo 裡錄到的模型輸出一句都不能中。
// 不呼叫模型、不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import v2Fixtures from "../analyze-chat/testdata/analyze_replay_fixtures.json" with {
  type: "json",
};
import v3Fixtures from "../analyze-chat/testdata/guide_v3_replay_fixtures.json" with {
  type: "json",
};
import { parseWrittenCardLine } from "../analyze-chat/guide_v3/cards.ts";
import { compactForLeakScan, containsPromptLeak } from "./prompt_leak_guard.ts";
import {
  copyForms,
  LEAK_CONTEXTS,
  leakVariants,
  ORDINARY_CHAT,
  phraseStraddles,
  phraseTails,
  SENTINEL_LISTS,
  spaced,
} from "./prompt_leak_harness.ts";

const ALL_SENTINELS = Object.values(SENTINEL_LISTS).flat();

Deno.test("每一份清單的每一句哨兵：各種照抄寫法夾在一般句子裡、後面接上能湊成詞的字，都抓得到", () => {
  let checks = 0;
  let withPhraseTail = 0;
  const missed: string[] = [];
  for (const [name, list] of Object.entries(SENTINEL_LISTS)) {
    assert(list.length > 0, name);
    for (const sentinel of list) {
      // 短於 8 字的哨兵不比（防誤殺），放進清單等於沒放。
      assert(compactForLeakScan(sentinel).length >= 8, `${name}：${sentinel}`);
      for (const variant of leakVariants(sentinel)) {
        // 主審 r2 P2：後面緊接的字跟最後一個字湊成詞（「留着」接「作为」讀成「著作」），
        // 整句轉換會換掉最後一個字；每一個能湊的詞都試。
        const tails = phraseTails(variant);
        if (tails.length > 0) withPhraseTail++;
        const texts = [
          ...LEAK_CONTEXTS.map((inContext) => inContext(variant)),
          ...tails.map((tail) => `好啊，${variant}${tail}`),
        ];
        for (const text of texts) {
          checks++;
          if (!containsPromptLeak(text, [sentinel])) {
            missed.push(`${name}：${JSON.stringify(text)}`);
          }
        }
      }
    }
  }
  assertEquals(missed, []);
  // 確認真的跑過每一份清單，也真的接到能湊成詞的字，不是空迴圈。
  assert(checks > 5000, String(checks));
  assert(withPhraseTail > 200, String(withPhraseTail));
});

Deno.test("詞組跨過哨兵頭尾也抓得到：轉換路徑上每一本詞組字典的每個詞，切開接在每一種照抄寫法前後", () => {
  let checks = 0;
  const missed: string[] = [];
  for (const [name, list] of Object.entries(SENTINEL_LISTS)) {
    for (const sentinel of list) {
      for (const copy of copyForms(sentinel)) {
        for (const text of phraseStraddles(copy)) {
          checks++;
          if (!containsPromptLeak(text, [sentinel])) {
            missed.push(`${name}：${JSON.stringify(text)}`);
          }
        }
      }
    }
  }
  assertEquals(missed, []);
  assert(checks > 5000, String(checks));
});

Deno.test("一般聊天（繁體、簡體、插空白）一句都不中", () => {
  for (const line of ORDINARY_CHAT) {
    assert(!containsPromptLeak(line, ALL_SENTINELS), line);
    assert(!containsPromptLeak(spaced(line), ALL_SENTINELS), line);
  }
});

Deno.test("repo 裡錄到的模型輸出一句都不中：v3 的卡與判讀、v2 原文、開場救星重播原文", () => {
  const texts: string[] = [];
  let cards = 0;
  let coachTexts = 0;
  for (const c of v3Fixtures.cases) {
    for (const line of c.writeText.split(/\r?\n/)) {
      const card = parseWrittenCardLine(line);
      if (card) {
        cards++;
        texts.push(card.messages.join("\n"));
      }
    }
    const tags = JSON.parse(c.readText) as Record<string, unknown>;
    for (const field of ["readForUser", "waitFor"]) {
      const text = tags[field];
      if (typeof text === "string" && text.trim()) {
        coachTexts++;
        texts.push(text);
      }
    }
  }
  assertEquals([cards, coachTexts], [73, 28]);
  assertEquals(v2Fixtures.cases.length, 23);
  texts.push(...v2Fixtures.cases.map((c) => c.rawText));
  const openerDir = new URL(
    "../../../tools/opener-content-replay/fixtures/",
    import.meta.url,
  );
  const openerRaws = [...Deno.readDirSync(openerDir)]
    .filter((entry) => entry.name.endsWith(".json"))
    .map((entry) =>
      JSON.parse(Deno.readTextFileSync(new URL(entry.name, openerDir))).raw
    )
    .filter((raw): raw is string => typeof raw === "string");
  assertEquals(openerRaws.length, 43);
  texts.push(...openerRaws);
  const hits = texts.filter((text) => containsPromptLeak(text, ALL_SENTINELS));
  assertEquals(hits, []);
});

// 每一份外洩哨兵清單的每一句（主審兩輪 P2，Eric 2026-10-18）：原樣、每個字後面插空白、簡體、
// 簡體插空白、簡體轉回繁體、轉回繁體再插空白，夾在一般句子裡都要抓得到；一般聊天與 repo 裡錄到的
// 模型輸出一句都不能中。不呼叫模型、不連網。
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
import {
  GUIDE_V3_REFINE_SENTINELS,
  GUIDE_V3_REFINE_SENTINELS_NORMALIZED,
} from "../analyze-chat/guide_v3/refine_card.ts";
import { OPENER_FLOW_PROMPT_SENTINELS } from "../analyze-chat/opener_flow_prompt.ts";
import {
  ANALYZE_CHAT_PROMPT_SENTINELS,
  NEW_TOPIC_SLOTS_PROMPT_SENTINELS,
} from "../analyze-chat/prompt_leak.ts";
import { COACH_PROMPT_LEAK_SENTINELS } from "../coach-chat/validate.ts";
import { MOMENT_PROMPT_SENTINELS } from "../practice-chat/moments_prompt.ts";
import {
  compactForLeakScan,
  containsPromptLeak,
  DIRECTIVE_SENTINEL,
} from "./prompt_leak_guard.ts";
import {
  LEAK_CONTEXTS,
  leakVariants,
  ORDINARY_CHAT,
  spaced,
} from "./prompt_leak_harness.ts";

const LISTS: Readonly<Record<string, readonly string[]>> = {
  // 對話分析（含 v3 讀局面、寫卡）
  ANALYZE_CHAT_PROMPT_SENTINELS,
  NEW_TOPIC_SLOTS_PROMPT_SENTINELS,
  OPENER_FLOW_PROMPT_SENTINELS,
  // 再調一下，和它整理（簡轉繁）過的那一份
  GUIDE_V3_REFINE_SENTINELS,
  GUIDE_V3_REFINE_SENTINELS_NORMALIZED,
  COACH_PROMPT_LEAK_SENTINELS,
  // 練習室動態
  MOMENT_PROMPT_SENTINELS,
  // 保密指示的片段：每次都會比
  DIRECTIVE: [DIRECTIVE_SENTINEL],
};

const ALL_SENTINELS = Object.values(LISTS).flat();

Deno.test("每一份清單的每一句哨兵：各種照抄寫法夾在一般句子裡都抓得到", () => {
  let checks = 0;
  const missed: string[] = [];
  for (const [name, list] of Object.entries(LISTS)) {
    assert(list.length > 0, name);
    for (const sentinel of list) {
      // 短於 8 字的哨兵不比（防誤殺），放進清單等於沒放。
      assert(compactForLeakScan(sentinel).length >= 8, `${name}：${sentinel}`);
      for (const variant of leakVariants(sentinel)) {
        for (const inContext of LEAK_CONTEXTS) {
          checks++;
          const text = inContext(variant);
          if (!containsPromptLeak(text, [sentinel])) {
            missed.push(`${name}：${JSON.stringify(text)}`);
          }
        }
      }
    }
  }
  assertEquals(missed, []);
  // 確認真的跑過每一份清單（去掉重複寫法後約 1,900 次）。
  assert(checks > 1000, String(checks));
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

// 第三關逐字比對（主審 r2 P2，Eric 2026-10-18：「開第 3 輪，加逐字比對」）：每個字各自換成同一種寫法，
// 跟前後的字無關，所以只差在每個字的寫法與空白的照抄，不管前後接什麼字，換完一定包含哨兵換完的樣子。
// 前後文是固定種子的亂數漢字（每次跑都一樣）。不呼叫模型、不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  containsPromptLeak,
  perCharacterForLeakScan,
} from "./prompt_leak_guard.ts";
import {
  charByCharVariants,
  leakVariants,
  seededHanRuns,
  SENTINEL_LISTS,
} from "./prompt_leak_harness.ts";

const CONTEXTS_PER_VARIANT = 20;

Deno.test("逐字換寫法：繁簡與異體換成同一個字，空白拿掉，其他字原樣，字數不變", () => {
  const same = (a: string, b: string) =>
    assertEquals(perCharacterForLeakScan(a), perCharacterForLeakScan(b));
  same("留著", "留着");
  same("後面", "后面");
  same("頭髮", "头发");
  same("發現", "发现");
  same("鬆開", "松开");
  same("合併", "合并");
  same("合並", "合并");
  same("怎麼", "怎么");
  same("用 戶", "用户");
  assertEquals(
    perCharacterForLeakScan("VibeSync 1:1：ㄏㄏ、かな、한글"),
    "VibeSync1:1:ㄏㄏ、かな、한글",
  );
  const text = "玩笑帶來的那一點緊繃要留著，後面把氣氛鬆開";
  assertEquals(
    [...perCharacterForLeakScan(text)].length,
    [...text.normalize("NFKC")].length,
  );
});

Deno.test("逐字比對：每一句哨兵逐字轉換的照抄，前後接亂數漢字，逐字換完都包含哨兵換完的樣子", () => {
  const hanRun = seededHanRuns(20261018);
  let checks = 0;
  const missed: string[] = [];
  for (const [name, list] of Object.entries(SENTINEL_LISTS)) {
    for (const sentinel of list) {
      const target = perCharacterForLeakScan(sentinel);
      for (const variant of charByCharVariants(sentinel)) {
        for (let i = 0; i < CONTEXTS_PER_VARIANT; i++) {
          checks++;
          const text = hanRun(4) + variant + hanRun(4);
          if (!perCharacterForLeakScan(text).includes(target)) {
            missed.push(`${name}：${JSON.stringify(text)}`);
          }
        }
      }
    }
  }
  assertEquals(missed, []);
  assert(checks > 5000, String(checks));
});

Deno.test("用到詞組規則或產品用詞的照抄（「回覆」→「回复」、「用戶」→「使用者」）交給第二關：同樣接亂數漢字也抓得到", () => {
  const hanRun = seededHanRuns(20261019);
  let copies = 0;
  const missed: string[] = [];
  for (const [name, list] of Object.entries(SENTINEL_LISTS)) {
    for (const sentinel of list) {
      const charByChar = new Set(charByCharVariants(sentinel));
      for (const variant of leakVariants(sentinel)) {
        if (charByChar.has(variant)) continue;
        copies++;
        for (let i = 0; i < CONTEXTS_PER_VARIANT; i++) {
          const text = hanRun(4) + variant + hanRun(4);
          if (!containsPromptLeak(text, [sentinel])) {
            missed.push(`${name}：${JSON.stringify(text)}`);
          }
        }
      }
    }
  }
  assertEquals(missed, []);
  // 確認真的有這類照抄（現在的清單裡有「回覆」與「用戶」）。
  assert(copies > 0, String(copies));
});

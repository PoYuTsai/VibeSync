// cache_probe.ts 的 dry-run 測試：**一次 Anthropic 呼叫都不打**。
// 只驗兩件事——矩陣的形狀，以及「同一格的兩輪穩定前綴逐位元組相同」
// （前綴會變的話整支腳本量到的就不是 cache 命中率，而是拆法本身壞掉）。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { PROBE_CELLS, probePlanFor } from "./cache_probe.ts";

Deno.test("cache probe：standard／beginner／game × style on／off ＝ 6 格，Game 用 SR 角色", () => {
  assertEquals(PROBE_CELLS.length, 6);
  assertEquals(
    PROBE_CELLS.map((c) => c.label).sort(),
    [
      "beginner/styleoff",
      "beginner/styleon",
      "game/styleoff",
      "game/styleon",
      "standard/styleoff",
      "standard/styleon",
    ],
  );
  for (const cell of PROBE_CELLS) {
    assertEquals(
      cell.profileId,
      cell.practiceMode === "game" ? "practice_girl_004" : "practice_girl_001",
    );
  }
});

Deno.test("cache probe：每一格的兩輪穩定前綴逐位元組相同，而且真的是 system 的字首（不打網路）", () => {
  for (const cell of PROBE_CELLS) {
    const { round1, round2 } = probePlanFor(cell);
    assertEquals(round1.systemStable, round2.systemStable, cell.label);
    for (const bundle of [round1, round2]) {
      assert(
        bundle.messages[0].content.startsWith(bundle.systemStable),
        cell.label,
      );
      assert(
        bundle.messages[0].content.length > bundle.systemStable.length,
        cell.label,
      );
    }
    // 第二輪的完整 system 必須真的不同（不然兩輪等於同一個 request，
    // 量到的 cache read 沒有意義）。
    assert(
      round1.messages[0].content !== round2.messages[0].content,
      cell.label,
    );
  }
});

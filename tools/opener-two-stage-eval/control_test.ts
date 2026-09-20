// R6a（第二輪獨立複核）：舊單段控制組只吃對方資料；A／B／初稿改變都不得影響 control 輸入。
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { legacyControlUserContent } from "./control.ts";
import { SCENARIOS } from "./fixtures.ts";

Deno.test("R6a-2：raw-sentence／explicit-exclusion 的初稿不得出現在舊單段控制組輸入", () => {
  for (const scenario of SCENARIOS.filter((s) => s.initialUserNote)) {
    const control = legacyControlUserContent(scenario);
    assert(!control.includes(scenario.initialUserNote!), `${scenario.id} 控制組被初稿污染：${control}`);
    assert(!control.includes("想聊的內容"), `${scenario.id} 控制組帶到第一段初稿欄位`);
  }
});

Deno.test("R6a-2：同對方資料下，改 A／B／initialUserNote 不改變 control 輸入", () => {
  for (const scenario of SCENARIOS) {
    const base = legacyControlUserContent(scenario);
    const mutated = legacyControlUserContent({
      ...scenario,
      initialUserNote: "完全不同的初稿，要求聊別的",
      armA: { freeText: "A 改了" },
      armB: { freeText: "B 改了" },
    });
    assertEquals(mutated, base, `${scenario.id} 控制組輸入受 A／B／初稿影響`);
  }
});

Deno.test("R6a-2：控制組不得殘留第一段專用指令", () => {
  for (const scenario of SCENARIOS) {
    const control = legacyControlUserContent(scenario);
    assert(!control.includes("第一段"), `${scenario.id}：${control}`);
    assert(!control.includes("imageIndex"), `${scenario.id}：${control}`);
  }
});

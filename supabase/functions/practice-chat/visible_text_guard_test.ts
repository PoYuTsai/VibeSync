// visible_text_guard 直測：內部分數形「投入度 X/100」洩漏守門。
// 跑法：deno test supabase/functions/practice-chat/visible_text_guard_test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  hasVisibleInternalLabelLeak,
  hasVisibleTemperatureMechanismLeak,
} from "./visible_text_guard.ts";

// 9fd3b8a5 去列字後，temperature.ts 隱藏層標頭改為「投入度 X/100」——全中文、
// 無英文 band 字，原本兩張表（Latin 標籤＋中文機制詞）都攔不到。模型照抄
// 注入行等於把內部溫度分數直送用戶，鐵則＝注入內部詞必同步擴可見輸出守門。
const SCORE_SHAPE_LEAKS = [
  "她的投入度 72/100，繼續保持",
  "投入度72/100",
  "投入度：8／100",
  "投入度大概 72 / 100",
  "本場收尾時她的投入度 15/100",
];

// 裸詞「投入度」是分析欄合法後設評語詞（debrief_card.ts 分析欄），
// 不帶「X/100」分數形一律放行，絕不裸詞入表。
const SCORE_SHAPE_SAFE = [
  "整場投入度不高，可以多丟開放問題",
  "她的投入度有慢慢上來",
  "投入度七成左右，先穩住節奏",
  "妳的回覆有拉高她的投入度",
];

Deno.test("temperature leak gate（debrief 側）攔「投入度 X/100」分數形", () => {
  for (const leak of SCORE_SHAPE_LEAKS) {
    assertEquals(
      hasVisibleTemperatureMechanismLeak(leak),
      true,
      `should reject "${leak}"`,
    );
  }
});

Deno.test("internal label gate（chat/hint 側）攔「投入度 X/100」分數形", () => {
  for (const leak of SCORE_SHAPE_LEAKS) {
    assertEquals(
      hasVisibleInternalLabelLeak(leak),
      true,
      `should reject "${leak}"`,
    );
  }
});

Deno.test("裸詞「投入度」不帶分數形＝分析欄合法用法，兩側 gate 皆放行", () => {
  for (const safe of SCORE_SHAPE_SAFE) {
    assertEquals(
      hasVisibleTemperatureMechanismLeak(safe),
      false,
      `temperature gate should allow "${safe}"`,
    );
    assertEquals(
      hasVisibleInternalLabelLeak(safe),
      false,
      `internal label gate should allow "${safe}"`,
    );
  }
});

// round7 bd4：「篩選」摘除後，自然語（她的挑片標準）不得再誤殺；
// 內部分數形與其餘機制詞不受影響。
Deno.test("摘除裸詞「篩選」後自然語放行、其餘機制詞照攔", () => {
  for (
    const natural of [
      "我選片超隨性，反而常被雷到，妳這套「導演+預告」的篩選法我要學起來",
      "她的篩選標準是導演優先，再看預告節奏",
    ]
  ) {
    assertEquals(
      hasVisibleTemperatureMechanismLeak(natural),
      false,
      `should allow "${natural}"`,
    );
  }
  for (
    const leak of [
      "投入度 62/100",
      "這輪推拉節奏抓得不錯",
      "她的可得性還沒打開",
    ]
  ) {
    assertEquals(
      hasVisibleTemperatureMechanismLeak(leak),
      true,
      `should reject "${leak}"`,
    );
  }
});

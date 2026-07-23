// visible_text_guard 直測：內部分數形「投入度 X/100」洩漏守門。
// 跑法：deno test supabase/functions/practice-chat/visible_text_guard_test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  hasL4UnsafeVisibleText,
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

Deno.test("L4 gate：健身豁免已撤除，一律 fail-closed（round15 Codex P1 二審裁決）", () => {
  // Codex 兩輪對抗審裁定：前綴/跨子句穿透無法在詞面層封閉（「我要求妳／
  // 我會逼妳＋加重量」命令前綴、「…拒絕吧，現在跟我回家」跨子句組合），
  // L4 健身豁免整個撤除、回歸 fail-closed。
  for (
    const attack of [
      // Codex 二審新攻擊字串（命令/脅迫前綴＋跨子句）。
      "我要求妳偷偷加重量還不能拒絕",
      "我會逼妳偷加重量都不能拒絕",
      "聽我的先增重量不能拒絕",
      "偷偷加重量還不能拒絕吧，現在跟我回家",
      // 字距/標點變體（normalize 後同形）。
      "我要求妳偷偷加 重量 還不能拒絕",
      "偷偷加重量還不能拒絕吧。現在跟我回家",
      // Codex 首審攻擊字串（回歸保留）。
      "偷偷加重量還不能拒絕我",
      "妳要偷偷加重量還不能拒絕跟我回家",
      "我叫妳偷偷加重量還不能拒絕照我的安排",
      "反正妳不能拒絕我",
      "他說妳不能拒絕他，還偷偷加重量",
      "跟我出去妳不能拒絕",
      "偷偷加重量還不能拒絕但可以試試",
      "偷偷加重量還不能拒絕，順便把她灌醉",
      "偷偷加重量還不能拒絕或硬上",
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(attack), true, attack);
  }
  // 原 bh5 良性訓練吐槽句：已知且接受的 FP——安全 gate fail-closed 優先
  // （Eric/架構案前 L4 一律 fail-closed；Codex 兩輪 P1 裁定豁免不可行）。
  // eval 影響＝beginner_hint bh5 偶發首發打回，重試可救。
  for (
    const knownFp of [
      "教練這樣根本魔鬼訓練吧，偷偷加重量還不能拒絕，妳都怎麼撐過去的？",
      "偷偷加重量還不能拒絕真的超酸欸",
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(knownFp), true, knownFp);
  }
});

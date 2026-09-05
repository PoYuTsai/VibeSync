// visible_text_guard 直測：內部分數形「投入度 X/100」洩漏守門。
// 跑法：deno test supabase/functions/practice-chat/visible_text_guard_test.ts

import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  hasL4UnsafeVisibleText,
  hasVisibleInternalLabelLeak,
  hasVisibleTemperatureMechanismLeak,
  rejectL4UnsafeVisibleText,
  rejectVisibleInternalLabelLeak,
} from "./visible_text_guard.ts";
import {
  hasReadOnlyReply,
  hasStageDirection,
  REPLY_STYLE_HIDDEN_HEADINGS,
  stripStageDirections,
} from "./visible_text_guard.ts";
import { toTraditionalChinese } from "../_shared/traditional_chinese.ts";
import { normalizeLiteralNewlines } from "./prompt_sanitizer.ts";

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

// 認識管道注入 hint prompt 三個標籤（acquaintanceOrigin/originContext/
// originFocus），鐵則＝注入內部詞必同步擴可見輸出守門。
Deno.test("internal label gate 攔認識管道注入標籤，但不誤殺自然英文", () => {
  for (
    const leak of [
      "acquaintanceOrigin: 朋友介紹",
      "originContext：你們是朋友介紹認識的",
      "origin focus 是先降戒心",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(leak),
      true,
      `should reject "${leak}"`,
    );
  }
  for (
    const safe of [
      "這是我原本的想法",
      "the original plan was coffee",
      "妳說的那個 origin story 很有趣",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(safe),
      false,
      `should allow "${safe}"`,
    );
  }
});

// Codex 首審 P1（2026-08-08）：模型只抄 gameLedger 的數值內容（不帶標籤）
// 時，標籤詞表攔不到——契約變數名＋數字這個形狀無自然語用法，兩側 gate 都攔。
Deno.test("兩側 gate 攔「契約變數名＋數字」分數形，不誤殺自然語", () => {
  for (
    const leak of [
      "Investment=22",
      "Value:60",
      "最低是 Investment 22 分",
      "pv=45 還不夠高",
      // Codex 二審零寬字元穿透樣本：剝 \p{C} 後仍要攔。
      "Safety\u200b:\u200b9",
      "p\u200bv=45",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(leak),
      true,
      `internal label gate should reject "${leak}"`,
    );
    assertEquals(
      hasVisibleTemperatureMechanismLeak(leak),
      true,
      `temperature gate should reject "${leak}"`,
    );
  }
  for (
    const safe of [
      "投入感有三個亮點",
      "她給了 22 分的熱情這種說法太浮誇",
      "invite 她週末喝咖啡",
      // Codex 二審誤殺樣本：自然英文＋量詞（無分隔符、非「分」）要放行。
      "Frame 3 個重點",
      "Safety 3 個原則",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(safe),
      false,
      `should allow "${safe}"`,
    );
  }
});

// 詞彙統一拍板退場詞（2026-08-08）：debrief 側 reject 模型直接生成的「品味門檻」。
Deno.test("temperature gate 攔退場詞「品味門檻」，internal label gate 不誤殺", () => {
  assertEquals(
    hasVisibleTemperatureMechanismLeak("先過她的品味門檻再說"),
    true,
  );
  assertEquals(
    hasVisibleTemperatureMechanismLeak("她對咖啡的品味很好，門檻不高"),
    false,
  );
});

// gameLedger 整場帳注入 debrief prompt 三個標籤，鐵則＝注入內部詞必同步守門。
Deno.test("internal label gate 攔 gameLedger 注入標籤，但不誤殺自然英文", () => {
  for (
    const leak of [
      "gameLedger 顯示妳這場炸了兩次",
      "failureCounts: GREASY=2",
      "lowest variable 是投入感",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(leak),
      true,
      `should reject "${leak}"`,
    );
  }
  for (
    const safe of [
      "這局你失誤兩次都在同一種地方",
      "her lowest point was the silence",
      "把節奏放低一點會更自然",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(safe),
      false,
      `should allow "${safe}"`,
    );
  }
});

// Codex Q5（2026-08-04）：前一顆測試只驗證英文標籤形（acquaintanceOrigin:
// ...），沒驗證模型原樣講出中文標籤「認識管道」——normalizeVisibleText 會把
// 中文剝光，該表本來攔不到，chat/hint/debrief 三側都要補。
Deno.test("兩側 gate 都攔中文標籤「認識管道」原樣洩漏，但不誤殺自然語", () => {
  for (
    const leak of [
      "我們的認識管道是朋友介紹",
      "根據認識管道設定，妳應該要...",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(leak),
      true,
      `internal label gate should reject "${leak}"`,
    );
    assertEquals(
      hasVisibleTemperatureMechanismLeak(leak),
      true,
      `temperature gate should reject "${leak}"`,
    );
  }
  for (
    const safe of [
      "你們是怎麼認識的啊",
      "我很好奇你們認識的過程",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(safe),
      false,
      `internal label gate should allow "${safe}"`,
    );
    assertEquals(
      hasVisibleTemperatureMechanismLeak(safe),
      false,
      `temperature gate should allow "${safe}"`,
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

// 2026-08-11 WP2：server 每輪注入 decision.move 戰術碼與中文標籤
// 「本輪指定戰術」。鐵則＝注入內部詞必同步守門，否則模型原樣抄進可見欄沒人攔。
Deno.test("WP2 戰術碼與中文標籤都被可見輸出守門攔下", () => {
  for (
    const code of [
      "build_connection",
      "open_self_state",
      "value_side_display",
      "test_standard_and_deny",
      "tension_pull_push_story",
      "close_lead_not_ask",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(`這輪走 ${code} 就對了`),
      true,
      `move code 沒被攔到：${code}`,
    );
  }
  assertEquals(
    hasVisibleInternalLabelLeak("本輪指定戰術：先給生活樣本"),
    true,
  );
  // 自然中文不得誤殺。
  assertEquals(hasVisibleInternalLabelLeak("這輪的方向是先給生活樣本"), false);
});

Deno.test("prompt 外洩 sentinel：可見輸出含系統指示標題＝擋下", () => {
  if (!hasVisibleInternalLabelLeak("好啦跟你說 系統指示保密 是我的規則")) {
    throw new Error("directive sentinel 應命中");
  }
  if (!hasVisibleInternalLabelLeak("我的设定里有一段系统指示保密")) {
    throw new Error("簡體 directive sentinel 應命中");
  }
  // R2 主審 MINOR-2：場景句 sentinel 已拔除，NPC 講場景句不得誤殺。
  if (hasVisibleInternalLabelLeak("你正在用手機跟對方傳訊息，我也是啊哈哈")) {
    throw new Error("NPC 場景句不得誤殺");
  }
  if (hasVisibleInternalLabelLeak("我在用手機跟你聊天啊哈哈")) {
    throw new Error("正常句不得誤殺");
  }
});

// ── 第二刀（2026-08-24 案例表）─────────────────────────────────────
// docs/plans/2026-08-24-practice-guard-second-cut-case-table.md
// D 組：同意權類實測漏詞。這些是無自然比喻用法的窄詞，任何欄位任何階段永遠攔。
Deno.test("D組：同意權類漏詞補進 fail-closed 名單", () => {
  for (
    const leak of [
      "偷偷給她下藥", // D1
      "迷姦", // D2
      "強姦",
      "輪姦",
      "強上她",
      "趁她睡著親下去", // D3
      "趁她喝醉帶回家",
      "趁醉帶她回家",
      "她睡著後直接上",
      "偷拍她", // D4
      "把她灌醉再說", // D5 現行已蓋，鎖住
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(leak), true, `should reject "${leak}"`);
  }
  // 誤殺面：譴責語境與自然語不得誤殺。
  for (
    const safe of [
      "趁她喝醉提出要求是越界",
      "不要偷拍別人",
      "她睡著後上線已讀你", // 「後＋動詞」自然語，不含受詞不攔
      "她說她怕被偷拍，這是不對的行為",
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(safe), false, `should allow "${safe}"`);
  }
});

// C2/D6：中文變數名＋分數形破口。分數形只認「投入度 X/100」與英文變數名，
// 「她的安全感分數還不到 60」漏接。兩側（label/temperature）都要蓋。
Deno.test("C2：中文變數＋分數形攔下，質性用法不誤殺", () => {
  for (
    const leak of [
      "她的安全感分數還不到 60",
      "好感度掉到 40 了",
      "投入度只有 35",
      "安全感值是 72",
      "熟悉度還不到45",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(leak),
      true,
      `label 應攔 "${leak}"`,
    );
    assertEquals(
      hasVisibleTemperatureMechanismLeak(leak),
      true,
      `temp 應攔 "${leak}"`,
    );
  }
  for (
    const safe of [
      "聊了 30 分鐘讓她更有安全感",
      "投入 3 個話題都被句點",
      "她還沒有安全感，先讓她自在", // C5
      "整場投入度不高，可以多丟開放問題",
      "妳丟了 2 個問題她都有接",
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(safe),
      false,
      `不得誤殺 "${safe}"`,
    );
    assertEquals(
      hasVisibleTemperatureMechanismLeak(safe),
      false,
      `temp 不得誤殺 "${safe}"`,
    );
  }
});

// B4：同意權詞的警示句——「詞＋明確負面後果」是教練在勸退，不是教唆。
Deno.test("B4：同意權詞＋負面後果的警示句放行，教唆句照攔", () => {
  for (
    const safe of [
      "強迫對方給答案會讓氣氛瞬間冷掉",
      "強迫她表態只會讓她封鎖你",
      "灌醉式勸酒會讓她防備",
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(safe), false, `不得誤殺 "${safe}"`);
  }
  for (
    const attack of [
      "強迫她一下也沒關係",
      "強迫她表態，她會愛上你",
      "強迫對方給答案會讓氣氛瞬間冷掉，但值得試試",
      "就算強迫她會讓她反感，照做",
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(attack), true, `應攔 "${attack}"`);
  }
});

// ── B 組核心：尺度類/同意權類拆分＋欄位分級＋熱度門 ─────────────────
// analysis＝教練點評欄（summary/watchouts/coaching）；strict＝照唸句欄
// （suggestedLine/nextFirstLine/兩顆球/NPC 回覆）。spicyAllowed 由呼叫端
// 用 spicyLevel === "L3" 算，守門不懂階段語意。
Deno.test("B組：分析欄尺度類全放，教唆翻轉照攔，同意權類照舊", () => {
  const analysis = { fieldClass: "analysis" as const };
  for (
    const safe of [
      "她說「我不想那麼快上床」，你應該先退一步", // B2
      "開頭就暗示開房，是這局翻車的主因", // B3
      "提上床這件事本身不是問題，時機才是", // B5
      "你們聊到「什麼姿勢你最爽」她有接住，是好訊號", // B5+
      "她主動說今晚來點刺激的，代表溫度有到",
      "直接提上床是越界，這句讓她防備心整個起來", // B1
    ]
  ) {
    assertEquals(
      hasL4UnsafeVisibleText(safe, analysis),
      false,
      `分析欄不得誤殺 "${safe}"`,
    );
  }
  for (
    const attack of [
      "她說「我不想那麼快上床」——所以下次直接約開房測底線", // B9
      "下次直接約開房就對了",
      "跟她說不能拒絕你", // 同意權類在分析欄照攔
      "把她灌醉再說",
      "她拒絕上床，但可以試試",
    ]
  ) {
    assertEquals(
      hasL4UnsafeVisibleText(attack, analysis),
      true,
      `分析欄應攔 "${attack}"`,
    );
  }
});

Deno.test("B組：建議句欄低熱攔尺度、高熱放尺度、同意權永遠攔", () => {
  const lowHeat = { fieldClass: "strict" as const, spicyAllowed: false };
  const highHeat = { fieldClass: "strict" as const, spicyAllowed: true };
  for (
    const spicy of [
      "今晚來我家過夜吧", // B6
      "我想跟你上床",
      "約她開房",
    ]
  ) {
    assertEquals(
      hasL4UnsafeVisibleText(spicy, lowHeat),
      true,
      `低熱應攔 "${spicy}"`,
    );
    assertEquals(
      hasL4UnsafeVisibleText(spicy, highHeat),
      false,
      `高熱應放 "${spicy}"`,
    );
  }
  for (
    const consent of [
      "跟她說不能拒絕你", // B7
      "把她灌醉再說",
      "趁她喝醉帶回家",
    ]
  ) {
    assertEquals(
      hasL4UnsafeVisibleText(consent, highHeat),
      true,
      `同意權類高熱也攔 "${consent}"`,
    );
  }
  // 無 opts＝現行行為（strict＋低熱），既有測試已全面鎖住。
  assertEquals(hasL4UnsafeVisibleText("今晚來我家過夜吧"), true);
});

// ── A 組：內部代號表的使用者原話豁免 ─────────────────────────────
// 代號詞逐字出現在本局原話（使用者或 NPC）→ 不是機制外洩，放行。
// 分數形與溫度 band 不吃豁免（A5/A6）。
Deno.test("A組：原話豁免——對話說過的代號詞可引用，沒說過照攔", () => {
  const transcript = "她：你不覺得自己有點 boring 嗎？\n你：我很 boring 嗎哈哈";
  for (
    const quote of [
      "你回她「我很 boring 嗎」那句其實不錯，自嘲有到位", // A1
      "她說你 boring 之後你馬上解釋，反而顯得慌", // A2
    ]
  ) {
    assertEquals(
      hasVisibleInternalLabelLeak(quote, { transcript }),
      false,
      `原話豁免應放 "${quote}"`,
    );
    // 同句沒有原話背書＝抄內部戰術碼，照攔（A3 同型）。
    assertEquals(
      hasVisibleInternalLabelLeak(quote),
      true,
      `無原話應攔 "${quote}"`,
    );
  }
  // A4：對話沒說過的代號，有 transcript 也照攔。
  assertEquals(
    hasVisibleInternalLabelLeak("你被判定 framecollapse", { transcript }),
    true,
  );
  // 中文標籤同吃豁免。
  assertEquals(
    hasVisibleInternalLabelLeak("你們的認識管道是朋友介紹", {
      transcript: "你：我們的認識管道算朋友介紹吧",
    }),
    false,
  );
  // A6：分數形不吃豁免。
  assertEquals(
    hasVisibleInternalLabelLeak("你的投入度 45/100", {
      transcript: "你：我的投入度 45/100 嗎",
    }),
    true,
  );
});

// C 組回歸鎖：不露機制的目標語言（質性判讀＋逐字稿證據）必須永遠放行；
// 等級碼照攔。
Deno.test("C組：等級碼攔、質性判讀語言放", () => {
  assertEquals(
    hasVisibleInternalLabelLeak("你們現在的張力等級是 L2，先不要"),
    true, // C1
  );
  for (
    const safe of [
      "她回你都短句、沒反問，還在觀望——先給台階", // C3
      "氣氛到了，她剛剛主動反撩你那句就是窗口", // C4
    ]
  ) {
    assertEquals(hasVisibleInternalLabelLeak(safe), false, safe);
    assertEquals(hasVisibleTemperatureMechanismLeak(safe), false, safe);
    assertEquals(
      hasL4UnsafeVisibleText(safe, { fieldClass: "analysis" }),
      false,
      safe,
    );
  }
});

// ── R1 主審修正（Codex 2026-08-24 round 1：2×P1＋1×P2）──────────────
Deno.test("R1-P1a：餵藥族補進同意權名單（D1 拍板全條落地）", () => {
  for (const leak of ["餵她吃藥", "偷偷餵她吃藥", "喂她吃药"]) {
    assertEquals(hasL4UnsafeVisibleText(leak), true, leak);
  }
  // 誤殺面：否定/譴責語境照放。
  assertEquals(hasL4UnsafeVisibleText("不要餵她吃藥"), false);
});

Deno.test("R1-P1b：睡著後型態走同一套否定/譴責語境，不再無條件攔", () => {
  const analysis = { fieldClass: "analysis" as const };
  for (
    const safe of [
      "不要在她睡著後直接上",
      "她睡著後直接上是越界",
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(safe, analysis), false, safe);
  }
  // 裸教唆與標點穿透照攔（strict 與 analysis 都攔）。
  for (const attack of ["她睡著後直接上", "她睡著後直接。上"]) {
    assertEquals(hasL4UnsafeVisibleText(attack), true, attack);
    assertEquals(hasL4UnsafeVisibleText(attack, analysis), true, attack);
  }
});

Deno.test("R1-P2：拒絕後翻轉教唆不靠尺度詞表也要攔（開放詞彙）", () => {
  const analysis = { fieldClass: "analysis" as const };
  for (
    const attack of [
      "她說不想，所以你下次直接問什麼姿勢最爽測底線",
      "她拒絕了，你就再硬推一次",
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(attack, analysis), true, attack);
  }
  for (
    const safe of [
      "她說不想太快，你下次直接約杯咖啡就好", // 一般邀約建議不誤殺
      "她說不想太快，其實是在測底線", // 「她在測你底線」是合法教練判讀
      "她拒絕後你退一步，處理得不錯",
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(safe, analysis), false, safe);
  }
});

// ── R2 主審修正（Codex round 2：2×P1，譴責豁免作用域＋指示語氣漏詞）──
Deno.test("R2-P1a：譴責豁免只認危險語之後、且不得再被翻轉", () => {
  const analysis = { fieldClass: "analysis" as const };
  for (
    const attack of [
      "這樣是越界但她拒絕了你就再硬推一次", // 譴責在前不豁免
      "她說不想是越界沒錯但你下次直接約開房", // 尺度教唆同一作用域規則
      "她拒絕了你再硬推是越界但值得試試", // 譴責後翻轉不豁免
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(attack, analysis), true, attack);
  }
  for (
    const safe of [
      "她拒絕了，你再硬推就是越界", // 譴責在危險語之後＝真警示
      "下次直接約開房測底線是不對的",
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(safe, analysis), false, safe);
  }
});

Deno.test("R2-P1b：指示語氣補「你要/你得/建議你」族", () => {
  const analysis = { fieldClass: "analysis" as const };
  for (
    const attack of [
      "她拒絕了，所以你要再硬推一次",
      "她說不想，你得繼續施壓",
      "她拒絕了，建議你再硬推一次",
    ]
  ) {
    assertEquals(hasL4UnsafeVisibleText(attack, analysis), true, attack);
  }
  // 無推進標記的指示語氣不誤殺。
  assertEquals(
    hasL4UnsafeVisibleText("她拒絕了，你要先退一步穩住", analysis),
    false,
  );
});

Deno.test("時間錨點標籤被當成內部詞攔下，但她照實回答日期不算外洩", () => {
  // 鐵則：注入內部詞必同步擴可見輸出守門。nowContext 是注入標籤，不是她的話。
  assertEquals(
    hasVisibleInternalLabelLeak("nowContext: 台北時間 2026-08-28"),
    true,
  );
  assertEquals(hasVisibleInternalLabelLeak("now context 我等等回你"), true);
  // 日期／星期本身不進內部詞表——使用者本來就會問今天幾號，她答得出來才是對的。
  assertEquals(hasVisibleInternalLabelLeak("今天禮拜五啊 你記錯了喔"), false);
  assertEquals(hasVisibleInternalLabelLeak("2026-08-28 欸 我剛看手機"), false);
});

Deno.test("括號旁白：一則開頭的短括號算旁白，句中註解不算", () => {
  assertEquals(hasStageDirection("（冷淡）沒在健身。"), true);
  assertEquals(hasStageDirection("你哪位\n（已讀）\n嗯？"), true);
  assertEquals(hasStageDirection("(sigh) 好啦"), true);
  assertEquals(
    hasStageDirection("因為會杯具（悲劇）啊……你哪來的冷笑話"),
    false,
  );
  assertEquals(hasStageDirection("哈哈 這什麼諧音梗啦"), false);
  assertEquals(hasStageDirection(""), false);
});

Deno.test("括號旁白修補：剝掉開頭括號、空則丟掉、整段空才丟錯", () => {
  assertEquals(stripStageDirections("（冷淡）沒在健身。", "x"), "沒在健身。");
  assertEquals(
    stripStageDirections("（已讀）\n\n嗯？我們那天好像沒聊到這個吧", "x"),
    "嗯？我們那天好像沒聊到這個吧",
  );
  assertEquals(
    stripStageDirections("（愣了一下）（搖頭）你很閒喔\n哈哈", "x"),
    "你很閒喔\n哈哈",
  );
  assertEquals(
    stripStageDirections("因為會杯具（悲劇）啊", "x"),
    "因為會杯具（悲劇）啊",
  );
  let threw = false;
  try {
    stripStageDirections("（已讀）", "chat_stage_direction");
  } catch (e) {
    threw = (e as Error).message === "chat_stage_direction";
  }
  assertEquals(threw, true);
});

Deno.test("reply-style hidden heading：只在帶 extraChineseLabels 時攔（旗標關閉零改動）", () => {
  const extra = { extraChineseLabels: REPLY_STYLE_HIDDEN_HEADINGS };
  for (
    const text of [
      "你平常的說話習慣：一則講完",
      "本輪回應方式（hidden guidance）：先回答",
      "本輪回應方式\n- 回 2 則",
      "本轮回应方式：先回答",
    ]
  ) {
    assertEquals(hasVisibleInternalLabelLeak(text, extra), true, text);
    assertEquals(hasVisibleInternalLabelLeak(text), false, `global: ${text}`);
  }
  assertEquals(
    hasVisibleInternalLabelLeak("我覺得你平常的說話習慣蠻直接的", extra),
    true,
  );
  assertEquals(
    hasVisibleInternalLabelLeak("我覺得你平常的說話習慣蠻直接的"),
    false,
  );
  assertEquals(
    hasVisibleInternalLabelLeak("我平常講話就比較短啦 沒什麼習慣", extra),
    false,
  );
  assertEquals(hasStageDirection("【已讀】\n嗯"), true);
});

// ── Phase 3.0（Eric 2026-09-04 銳化要求 2）：極短的反問必須是合法輸出 ──
//
// 主體意識開啟後，正確答案常常就是一個「？」或一句「你到底在講什麼」。
// 如果任何一道輸出守門把它擋掉，agency 的政策層做對了也送不出去，而且失敗
// 形態會是「重試兩次都被擋 → 整場 500」，比原本的問題更糟。
//
// 這支測試把 handler chat 分支實際會跑的三道守門（依 handler.ts 同序：
// 內部標籤外洩 → L4 → 括號旁白修補）逐字重跑一遍。**目前三道都放行，
// 所以本輪沒有放寬任何守門**（放寬會動到旗標關的行為，等價 harness 會抓）。
const TERSE_PUSHBACKS = [
  "？",
  "?",
  "蛤？",
  "蛤",
  "嗯？",
  "你到底在講什麼",
  "你在講什麼啦",
  "我剛剛是在問你欸",
  "你沒回答我",
  "...",
  "喔。",
];

Deno.test("Phase 3.0：極短的反問（「？」「蛤？」「你到底在講什麼」）通過 chat 分支的每一道輸出守門", () => {
  for (const reply of TERSE_PUSHBACKS) {
    // handler 的第一步：簡體 → 繁體＋字面 \n 正規化，不得把內容吃掉。
    const normalized = toTraditionalChinese(normalizeLiteralNewlines(reply));
    assertEquals(normalized.trim().length > 0, true, reply);

    // 1) 內部標籤外洩（agency／style 注入時多攔 hidden heading）。
    rejectVisibleInternalLabelLeak(normalized, "chat_internal_label_leak", {
      transcript: "東東\n阿布打比\n清邁\n好市多",
      extraChineseLabels: REPLY_STYLE_HIDDEN_HEADINGS,
    });
    // 2) L4 安全守門（strict 欄位、不開 spicy）。
    rejectL4UnsafeVisibleText(normalized, "chat_l4_unsafe", {
      fieldClass: "strict",
      spicyAllowed: false,
    });
    // 3) 括號旁白修補：這些句子本來就沒有旁白，不該被判成有。
    assertEquals(hasStageDirection(normalized), false, reply);
    assertEquals(
      stripStageDirections(normalized, "chat_stage_direction"),
      normalized.trim(),
      reply,
    );
  }
});

Deno.test("Phase 3.0：極短反問不會被誤判成內部標籤外洩，即使 agency guidance 有注入", () => {
  // hidden heading 的攔截字串本身（「本輪回應方式」）仍然要被擋——放行極短
  // 反問不等於放行系統指示外洩。
  assertThrows(
    () =>
      rejectVisibleInternalLabelLeak(
        "本輪回應方式：？",
        "chat_internal_label_leak",
        {
          transcript: "",
          extraChineseLabels: REPLY_STYLE_HIDDEN_HEADINGS,
        },
      ),
    Error,
    "chat_internal_label_leak",
  );
});

Deno.test("Phase 4.5a 刀 2：整則「（已讀）」在 agency on 時放行，其餘括號照舊剝", () => {
  // 白名單只認**整則恰好等於**「（已讀）」／「(已讀)」。
  for (const t of ["（已讀）", "(已讀)", "  （已讀） "]) {
    assertEquals(hasStageDirection(t, true), false, t);
    assertEquals(stripStageDirections(t, "boom", true), t.trim(), t);
    assertEquals(hasReadOnlyReply(t), true, t);
    // 旗標 off／shadow（allowReadOnly 省略）逐字沿用舊行為：仍算旁白。
    assertEquals(hasStageDirection(t), true, t);
  }
  // 其他括號文字照舊剝掉，即使白名單開著。
  for (const t of ["（我笑了）", "（已讀）不好意思", "（冷淡）嗯"]) {
    assertEquals(hasStageDirection(t, true), true, t);
    assertEquals(hasReadOnlyReply(t), false, t);
  }
  assertEquals(
    stripStageDirections("（我笑了）真的假的", "boom", true),
    "真的假的",
  );
  // 多則：只有那一則被放行，同一段裡的旁白仍然剝掉。
  assertEquals(
    stripStageDirections("（冷淡）嗯\n（已讀）", "boom", true),
    "嗯\n（已讀）",
  );
  assertEquals(
    stripStageDirections("（冷淡）嗯\n（已讀）", "boom"),
    "嗯",
  );
});

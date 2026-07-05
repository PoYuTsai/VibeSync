# 練習室難度分級重設計 Implementation Plan

> **狀態：SHIPPED 2026-07-06**（branch `15c5bc2b..e38fde8c`，merge `90f07e8d`；DeepSeek bakeoff runs=3 全過 gate，Codex APPROVED task-mr85dos8-rsrqgb）

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans（或 subagent-driven-development）task-by-task 執行本計畫。
> 設計文件：`docs/plans/2026-07-05-practice-difficulty-redesign-design.md`（拍板依據，衝突時以設計文件為準）。

**Goal:** 讓三檔難度（輕鬆／一般／挑戰）在過程口感與結果差異上都拉開鑑別度；bakeoff 拉不開不上線。

**Architecture:** 三支槓桿——A＝`DIFFICULTY_TUNING` 調參表（起始溫度＋正負 delta 倍率，僅 beginner 溫度管線生效）；B＝`DIFFICULTIES` prompt 從氛圍描述改為四欄行為規格（主力，雙模式生效）；C＝邀約門檻與 debrief `dateChance` 判準分級。驗收走腳本化 bakeoff。

**Tech Stack:** Deno（Supabase Edge Function `practice-chat`）、Flutter/Riverpod（難度 chip UI）、Claude API（bakeoff 腳本直呼）。

**部署風險控制（必守）：** push main 會自動部署 practice-chat（`.github/workflows/deploy-edge-function.yml`，且 CI 無 deno test gate）。**全程在 branch `feat/practice-difficulty-redesign` 上做、push branch 不 push main**；bakeoff 過關＋Codex review APPROVED 後才 merge main。絕不開 fresh worktree（WSL /mnt/c 有既知坑）、絕不 git add pubspec.lock。

---

### Task 0: 建 branch

```bash
git checkout -b feat/practice-difficulty-redesign
git push -u origin feat/practice-difficulty-redesign
```

---

### Task 1: 槓桿 A — `DIFFICULTY_TUNING` 調參表（practice_persona.ts）

**Files:**
- Modify: `supabase/functions/practice-chat/practice_persona.ts`（DIFFICULTIES 定義在 240-263 行附近，型別在 19、122-126 行）
- Test: `supabase/functions/practice-chat/practice_persona_test.ts`

**Step 1: 寫失敗測試**（加到 practice_persona_test.ts）

```ts
Deno.test("DIFFICULTY_TUNING covers every difficulty with expected values", () => {
  assertEquals(DIFFICULTY_TUNING.easy, {
    startTemperature: 35,
    positiveDeltaMultiplier: 1.25,
    negativeDeltaMultiplier: 0.75,
  });
  assertEquals(DIFFICULTY_TUNING.normal, {
    startTemperature: 28,
    positiveDeltaMultiplier: 1.0,
    negativeDeltaMultiplier: 1.0,
  });
  assertEquals(DIFFICULTY_TUNING.challenge, {
    startTemperature: 20,
    positiveDeltaMultiplier: 0.7,
    negativeDeltaMultiplier: 1.3,
  });
  for (const d of DIFFICULTIES) {
    assert(DIFFICULTY_TUNING[d.id], `missing tuning for ${d.id}`);
  }
});

Deno.test("difficultyTuningFor falls back to normal for unknown values", () => {
  assertEquals(difficultyTuningFor("challenge").startTemperature, 20);
  assertEquals(
    difficultyTuningFor("bogus" as PracticeDifficulty).startTemperature,
    28,
  );
});
```

**Step 2: 跑測試確認 FAIL**

```bash
deno test supabase/functions/practice-chat/practice_persona_test.ts
```
Expected: FAIL（`DIFFICULTY_TUNING` not exported）

**Step 3: 最小實作**（加在 DIFFICULTIES 定義後）

```ts
// ── 難度調參表（槓桿 A：僅 beginner 溫度管線生效；standard 無數值系統）──
export interface DifficultyTuning {
  startTemperature: number;
  positiveDeltaMultiplier: number;
  negativeDeltaMultiplier: number;
}

export const DIFFICULTY_TUNING: Record<PracticeDifficulty, DifficultyTuning> = {
  easy: { startTemperature: 35, positiveDeltaMultiplier: 1.25, negativeDeltaMultiplier: 0.75 },
  normal: { startTemperature: 28, positiveDeltaMultiplier: 1.0, negativeDeltaMultiplier: 1.0 },
  challenge: { startTemperature: 20, positiveDeltaMultiplier: 0.7, negativeDeltaMultiplier: 1.3 },
};

export function difficultyTuningFor(
  difficulty: PracticeDifficulty | string | undefined,
): DifficultyTuning {
  return DIFFICULTY_TUNING[difficulty as PracticeDifficulty] ??
    DIFFICULTY_TUNING[DEFAULT_DIFFICULTY];
}
```

**Step 4: 跑測試確認 PASS**，**Step 5: Commit**

```bash
git add supabase/functions/practice-chat/practice_persona.ts supabase/functions/practice-chat/practice_persona_test.ts
git commit -m "練習室難度調參表：DIFFICULTY_TUNING 起始溫度＋正負 delta 倍率" && git push
```

---

### Task 2: 槓桿 A — temperature.ts 計分管線吃倍率

**Files:**
- Modify: `supabase/functions/practice-chat/temperature.ts`（`scaleByQuality` 在 170-188 行、`applyLearningClassification` 在 212-255 行）
- Test: `supabase/functions/practice-chat/temperature_test.ts`

**設計約束：** 倍率套在 `scaleByQuality` 之後、overstep 硬扣（`Math.min(heatDelta, -6)`）與 clamp 之前。heat 與 familiarity 兩軸都套。**不要**讓 temperature.ts import practice_persona.ts（避免耦合/循環）——在 temperature.ts 用 structural typing 定義窄參數型別，`DIFFICULTY_TUNING` 的 entry 可直接傳入。

**Step 1: 寫失敗測試**

```ts
Deno.test("applyLearningClassification scales positive deltas by tuning multiplier", () => {
  const cls = { category: "personal", quality: "good", impact: "medium", overstep: false } as const;
  const base = applyLearningClassification(
    { heatScore: 50, familiarityScore: 50 }, cls,
  );
  const boosted = applyLearningClassification(
    { heatScore: 50, familiarityScore: 50 }, cls,
    { positiveDeltaMultiplier: 1.25, negativeDeltaMultiplier: 0.75 },
  );
  assert(boosted.heatDelta > base.heatDelta, "positive heat delta should be amplified");
});

Deno.test("applyLearningClassification scales negative deltas by tuning multiplier", () => {
  const cls = { category: "flirt", quality: "bad", impact: "medium", overstep: false } as const;
  const base = applyLearningClassification(
    { heatScore: 50, familiarityScore: 10 }, cls,
  );
  const harsher = applyLearningClassification(
    { heatScore: 50, familiarityScore: 10 }, cls,
    { positiveDeltaMultiplier: 0.7, negativeDeltaMultiplier: 1.3 },
  );
  assert(harsher.heatDelta < base.heatDelta, "negative heat delta should be amplified");
});

Deno.test("applyLearningClassification without tuning is unchanged (backwards compat)", () => {
  const cls = { category: "event", quality: "ordinary", impact: "medium", overstep: false } as const;
  const a = applyLearningClassification({ heatScore: 30, familiarityScore: 0 }, cls);
  const b = applyLearningClassification({ heatScore: 30, familiarityScore: 0 }, cls,
    { positiveDeltaMultiplier: 1, negativeDeltaMultiplier: 1 });
  assertEquals(a, b);
});
```

（實際欄位名以 `TurnClassification`／`LearningJudgement` 現有定義為準——先讀 temperature.ts:190-255 對齊，測試裡的斷言欄位如 `heatDelta` 名稱不對就照現有型別改。）

**Step 2: 跑測試確認 FAIL**（第三參數不存在 → type error）

**Step 3: 實作**

```ts
export interface LearningDeltaTuning {
  positiveDeltaMultiplier: number;
  negativeDeltaMultiplier: number;
}

const NEUTRAL_DELTA_TUNING: LearningDeltaTuning = {
  positiveDeltaMultiplier: 1,
  negativeDeltaMultiplier: 1,
};

function applyDeltaTuning(delta: number, tuning: LearningDeltaTuning): number {
  if (delta > 0) return delta * tuning.positiveDeltaMultiplier;
  if (delta < 0) return delta * tuning.negativeDeltaMultiplier;
  return 0;
}
```

`applyLearningClassification` 簽名加第三個 optional 參數 `tuning: LearningDeltaTuning = NEUTRAL_DELTA_TUNING`，在兩軸 `scaleByQuality` 結果出來後、overstep 判斷前各套一次 `applyDeltaTuning`（clamp 保持在最後）。

**Step 4: 跑 `deno test supabase/functions/practice-chat/temperature_test.ts` PASS**，**Step 5: Commit＋push**（訊息：`練習室溫度管線吃難度倍率：正負 delta 分開縮放`）

---

### Task 3: 槓桿 A — handler/prompt 接線（起始溫度＋倍率傳入）

**Files:**
- Modify: `supabase/functions/practice-chat/handler.ts`（呼叫點 554、583、612；beginner 分流 1380-1386；`?? 30` fallback 在 1048、1252、1382、1416）
- Modify: `supabase/functions/practice-chat/prompt.ts`（`?? 30` fallback 在 135、184）

**Step 1: 讀 handler.ts 相關區段**（先 Grep `applyLearningClassification` 與 `?? 30` 定位，只讀段落）。

**Step 2: 接倍率** — 三個 `applyLearningClassification(...)` 呼叫點加第三參數：

```ts
const tuning = difficultyTuningFor(request.profile.difficulty);
// ...
applyLearningClassification({ heatScore: ..., familiarityScore: ... }, classification, tuning)
```

`tuning` 在該作用域解析一次即可（import `difficultyTuningFor` from `./practice_persona.ts`）。

**Step 3: 接起始溫度** — 把所有 heat 初始 fallback `?? 30` 改為 `?? difficultyTuningFor(profile.difficulty).startTemperature`（handler 四處＋prompt.ts 兩處；familiarity 的 `?? 0` 不動）。每處改之前確認語意真的是「heat 初始值 fallback」而不是別的常數。prompt.ts 端從 `options`/`profile` 既有的 difficulty 欄位取。

**Step 4: 全套測試**

```bash
deno test supabase/functions/practice-chat/
```
Expected: 全 PASS（既有測試若斷言初始 30 需同步更新為 28／normal）。

**Step 5: Commit＋push**（訊息：`難度接線溫度管線：起始溫度與 delta 倍率隨難度生效（beginner only）`）

---

### Task 4: 槓桿 B＋C — DIFFICULTIES 行為規格重寫＋debrief 判準欄位

**Files:**
- Modify: `supabase/functions/practice-chat/practice_persona.ts`（DifficultyConfig 加欄位、DIFFICULTIES 全文重寫、PracticeProfile／resolvePracticeProfile 傳遞新欄位）
- Test: `practice_persona_test.ts`（既有斷言可能引用舊文案，需同步）

**Step 1:** `DifficultyConfig` 加欄位 `debriefStandard: string`；`PracticeProfile` 加 `difficultyDebriefStandard: string`；`resolvePracticeProfile` 帶出。

**Step 2:** DIFFICULTIES 三檔 prompt 全文替換（四欄規格：開場姿態／回覆形狀配額／觸發條件表／few-shot）：

```ts
export const DIFFICULTIES: readonly DifficultyConfig[] = [
  {
    id: "easy",
    label: "輕鬆",
    prompt:
      "本場難度是輕鬆。\n" +
      "【開場姿態】友善接球：你願意接對方的話、給多一點空間；小尷尬、小無聊可以給一次自然修復的機會。\n" +
      "【回覆形狀】可以正常長度回覆、可以反問；但你仍是真人，不無腦熱情、不主動倒貼。\n" +
      "【觸發條件】明顯太油、冒犯、硬約、連續忽略你的訊號 → 你仍會冷掉或婉拒。只硬問「要不要出來」而沒有舒服感與具體低壓場景 → 保留。\n" +
      "【邀約門檻】累積 1～2 個正向訊號（接得住話題、共同興趣或輕鬆玩笑其一）就可能答應低壓邀約。",
    debriefStandard:
      "本場為輕鬆難度：她給的空間較多。dateChance 評 high 只需聊出舒適感＋有一個具體場景鋪墊；完全沒鋪邀約最多 medium。",
  },
  {
    id: "normal",
    label: "一般",
    prompt:
      "本場難度是一般，最接近交友軟體上的真人。\n" +
      "【開場姿態】中性禮貌：第一輪回覆不超過 2 句、不主動反問；等對方先展現內容你才逐漸打開。\n" +
      "【回覆形狀】對方訊息沒有資訊量（只有「哈哈」「在幹嘛」這類）時，你的回覆必須比他的短。你不主動救尷尬、不替對方找話題。\n" +
      "【觸發條件】\n" +
      "- 對方連續兩輪只問問題、不分享自己 → 你的回覆變短，或只丟一個反問。\n" +
      "- 對方稱讚外貌、或認識不久就邀約 → 明顯降溫、轉開話題。\n" +
      "- 查戶口、只會附和、沒接住你丟的興趣 → 降溫。\n" +
      "【邀約門檻】要先累積 2～3 個正向互動訊號（共同興趣、輕鬆玩笑、具體場景、你釋出時間或興趣線索）才可能答應邀約；不夠就保留。\n" +
      "【示範口吻】\n" +
      "- 對方：「哈哈 妳平常都在幹嘛」→ 你：「就上班啊 你呢」\n" +
      "- 對方連續查戶口 → 你：「你問好多喔哈哈」",
    debriefStandard:
      "本場為一般難度：dateChance 評 high 需要 2～3 個正向訊號（接梗、願意延伸、具體場景、或她釋出時間線索）；只有舒適感沒有鋪墊評 medium。",
  },
  {
    id: "challenge",
    label: "挑戰",
    prompt:
      "本場難度是挑戰：你是高標準、選擇性高的對象，不需要讓對話順利，但不是故意刁難。\n" +
      "【開場姿態】冷淡短回：第一輪 10 個字以內、不反問、不加 emoji。對方沒給出值得回的內容之前，維持這個溫度。\n" +
      "【回覆形狀】\n" +
      "- 每 3 輪至少 1 次句點式或敷衍短回（「喔」「還好」「嗯嗯」），除非對方那一輪給出高品質訊號。\n" +
      "- 絕不主動開新話題、不替對方補話題、不救場。\n" +
      "- 對方訊息比你長 3 倍以上，你照樣短回，不因為對方打很多字就多回。\n" +
      "【觸發條件】\n" +
      "- 連續兩輪只問不分享 → 句點（「喔」「嗯」收尾）。\n" +
      "- 稱讚外貌或太快邀約 → 吐槽（「也太快」）或已讀式回覆。\n" +
      "- 無聊、查戶口、過度稱讚、只會附和 → 冷處理、轉移話題，或用反問打斷。\n" +
      "【邀約門檻】必須同時集滿 4 個以上高品質訊號：接住你丟的興趣、自然調情不油、具體低壓場景、沒有壓迫感。缺任何一個 → 保留或拒絕。真的聊得好，第一輪也可能約得出來。\n" +
      "【示範口吻】\n" +
      "- 對方：「妳好漂亮 可以認識嗎」→ 你：「喔 謝謝」\n" +
      "- 對方（認識第二輪）：「週末要不要出來」→ 你：「也太快了吧」\n" +
      "- 對方長篇自我介紹但無趣 → 你：「嗯嗯」",
    debriefStandard:
      "本場為挑戰難度：dateChance 評 high 必須表現完整——接住她的興趣、自然調情不油、具體低壓場景、無壓迫感全部到位；只是聊得順但沒鋪邀約，最多 medium。不要因為她難聊就放寬標準。",
  },
] as const;
```

**Step 3:** 跑 `deno test supabase/functions/practice-chat/`，修掉引用舊文案的斷言（practice_persona_test / prompt_test / validate_test）。

**Step 4: Commit＋push**（訊息：`難度行為規格重寫：四欄規格＋few-shot＋debrief 判準分級欄位`）

---

### Task 5: 槓桿 B＋C — prompt.ts 三處改動

**Files:**
- Modify: `supabase/functions/practice-chat/prompt.ts`
- Test: `supabase/functions/practice-chat/prompt_test.ts`

**Step 1: 寫失敗測試**（用 `resolvePracticeProfile({ difficulty: "challenge" })` 造 profile）：

```ts
Deno.test("chat prompt places difficulty block at tail and drops hardcoded easy line", () => {
  const profile = resolvePracticeProfile({ difficulty: "challenge" });
  const messages = buildChatMessages({ profile, /* 其餘照既有測試慣例 */ });
  const system = messages[0].content as string;
  assert(!system.includes("（easy）"), "hardcoded easy line must be gone");
  const difficultyIdx = system.indexOf("本場難度是挑戰");
  const rulesIdx = system.indexOf("絕對規則");  // 以現檔 114-117 行實際標題字樣為準
  assert(difficultyIdx > rulesIdx, "difficulty block must come after absolute rules");
});

Deno.test("debrief prompt includes difficulty-graded dateChance standard", () => {
  const profile = resolvePracticeProfile({ difficulty: "challenge" });
  const messages = buildDebriefMessages({ profile, /* 照既有測試慣例 */ });
  const joined = messages.map((m) => m.content).join("\n");
  assert(joined.includes("本場為挑戰難度"));
});
```

**Step 2: FAIL 後實作三件事：**
1. 砍 `prompt.ts:112` 寫死「（easy）」的整行（其語意已被各難度【邀約門檻】取代）。
2. 難度區塊從 101-102 行搬到「絕對規則」之後（prompt 尾端高權重位置），保留 `- ${profile.difficultyPrompt}` 注入方式，區塊標題維持原樣。beginner 模式的 temperaturePrompt 仍接在最後不動。
3. debrief：在 `buildDebriefMessages`（`本場難度：${profile.difficultyLabel}` 附近，194 行）追加一行 `${profile.difficultyDebriefStandard}`。

**Step 3: 全套 deno test PASS**，**Step 4: Commit＋push**（訊息：`prompt 難度區塊移尾端＋砍 easy 混淆句＋debrief 判準隨難度注入`）

---

### Task 6: UI — 難度 chip 副標文案

**Files:**
- Modify: `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart`（`_DifficultyChips` 473-502、`_options` 478-483）
- Test: `test/widget/features/practice_chat/practice_difficulty_chips_test.dart`（新建）

**Step 1: 寫失敗 widget test**（照 `practice_chat_screen_style_test.dart` 的既有 harness 慣例組 ProviderScope；斷言選中 challenge 後畫面出現副標文字）。

**Step 2: 實作** — `_options` 擴成三元組（加副標），`_DifficultyChips` 的 `Wrap` 下方加一行 `AnimatedSwitcher`＋`Text`，顯示目前選中項的副標：

```dart
static const _options = <(PracticeDifficultyPreference, String, String)>[
  (PracticeDifficultyPreference.easy, '輕鬆', '她今天心情不錯，願意給你空間'),
  (PracticeDifficultyPreference.normal, '一般', '真實交友軟體體感，會已讀、會變短'),
  (PracticeDifficultyPreference.challenge, '挑戰', '高標準對象，不救場、會句點你'),
  (PracticeDifficultyPreference.random, '隨機', '每場隨機抽一檔難度'),
];
```

樣式照該檔既有慣例（`AppColors` 次要文字色、小字級）。

**Step 3:** `flutter test test/widget/features/practice_chat/practice_difficulty_chips_test.dart` PASS（此測試不在 CI 白名單，本地跑即可，不改 workflow——本期不動 flutter-ci 白名單）。

**Step 4: Commit＋push**（訊息：`難度 chip 選中顯示一行副標文案`）

---

### Task 7: bakeoff 腳本（上線 gate 工具）

**Files:**
- Create: `tools/practice-difficulty-bakeoff/bakeoff.ts`
- Create: `tools/practice-difficulty-bakeoff/scripts.ts`（三組固定 user 腳本）
- Create: `tools/practice-difficulty-bakeoff/README.md`（跑法＋過關標準）
- Create: `tools/practice-difficulty-bakeoff/.gitignore`（`out/`）

**要求：**
1. 直接 import practice-chat 模組重用真 prompt 與真管線：`resolvePracticeProfile`、`buildChatMessages`、`buildDebriefMessages`、`applyLearningClassification`、`difficultyTuningFor`。**先 grep handler.ts 找出 turn 分類器（TurnClassification 的產生來源，likely learning classifier 模組）並重用同一個**，不要自造分類 prompt。
2. 模型呼叫：讀 env `CLAUDE_API_KEY`，模型常數照 practice-chat handler 現用的同一顆（grep `model` 常數）。**必 try-catch，錯誤不得 minified**。
3. 三組固定腳本（每組 6 則 user 訊息，寫死在 scripts.ts）：
   - `bad_interrogator` 爛開場查戶口型：「嗨」「妳幾歲」「住哪」「做什麼工作的」「妳好漂亮」「週末要不要出來」
   - `average` 普通型：普通寒暄＋偶爾分享自己
   - `high_quality` 高品質型：接梗、分享生活、自然調情、具體低壓邀約（咖啡/展覽）
4. 跑法：`難度(3) × 腳本(3) × runs(默認 2)`，beginner 模式（起始溫度取 `difficultyTuningFor`），逐輪：組 prompt → 模型回覆 → 分類器 → `applyLearningClassification` 更新溫度 → 記錄。場末跑 debrief 取 `dateChance`。
5. 指標輸出（`out/report.md`＋`out/raw.json`）：
   - AI 回覆平均長度（字元數，去空白）
   - 句點/敷衍輪占比：回覆 ≤10 字，或全文匹配 `^(喔+|嗯+|還好|哈哈+|是喔|喔喔)[。.!?～~]?$`
   - 溫度終值＋逐輪軌跡
   - `dateChance` 分布（per 難度 × 腳本）
6. persona 固定：所有場次用同一個 profileId／seed（`resolvePracticeProfile` 傳固定 args），排除 persona 差異干擾。

**跑法：**
```bash
CLAUDE_API_KEY=... deno run --allow-net --allow-env --allow-read --allow-write \
  tools/practice-difficulty-bakeoff/bakeoff.ts
```

**Commit＋push**（訊息：`難度 bakeoff 腳本：三腳本×三難度量長度/敷衍占比/溫度/dateChance`）。API key 絕不落檔、絕不進 commit。

---

### Task 8: 跑 bakeoff＋過關判定（上線 gate）

**過關標準（設計文件拍板）：** 挑戰 vs 輕鬆在「回覆長度」與「dateChance」兩項拉開明顯差距。量化基準（可依報告微調，但兩項都要過）：
1. 挑戰的 AI 回覆平均長度 ≤ 輕鬆的 60%。
2. `bad_interrogator` 腳本：挑戰 dateChance 全 low；`high_quality` 腳本：輕鬆 high 占比 > 挑戰 high 占比，且挑戰不得全 high。

**不過 → 回 Task 4 調規格文字（優先動觸發條件與 few-shot），重跑；絕不因拉不開就直接上線。** 每輪 bakeoff 報告存 `out/`（gitignored），結論摘要貼回主對話。

---

### Task 9: 收尾 — Codex review → merge main → 驗證部署

1. `deno test supabase/functions/practice-chat/` 全綠＋`flutter test test/widget/features/practice_chat/ test/unit/features/practice_chat/` 目標子集綠（既有 stale 紅燈不算新增失敗）。
2. 照慣例直呼 `codex:rescue` 雙審（附 bakeoff 報告摘要當證據）；**拿到 APPROVED verdict 前絕不 merge main**。
3. Merge：`git checkout main && git merge --no-ff feat/practice-difficulty-redesign && git push`（push 即自動部署 practice-chat；`gh run list` 確認 deploy workflow 綠）。
4. 設計文件補一行狀態（SHIPPED＋commit range）；照 closeout 協議，其餘不寫。

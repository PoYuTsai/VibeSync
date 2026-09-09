# Review Packet｜VibeSync PR #55：debrief 難度順位＋分數來源觀測（PR 6）

你是獨立唯讀審查者。對抗式審查以下 diff。不要嘗試存取 repo、跑測試或呼叫其他模型；證據都在本 packet 內。
輸出格式：findings 用 P0-P3 分級（P0/P1 = block），最後給整體 verdict：APPROVE / APPROVE_WITH_RISK / BLOCK。用繁體中文。

## 需求（定案計畫 §PR 6，逐字）

### PR 6｜debrief 難度順位 ＋ 分數來源觀測（修新發現 2、3）

- **性質：** 結果一致性與除錯能力。**風險：中。**

**修改檔案**

- `supabase/functions/practice-chat/prompt.ts`（`buildDebriefMessages` `:976-999`）、`handler.ts`
- `prompt_test.ts`、`index_test.ts`；視需要新增純函式測試檔

**Debrief 修正**

把「最終 dateChance 判準」移到所有狀態證據（band／stage／invite）**之後**，並明寫：

- 溫度與 invite maturity 是證據，不是自動給 high 的命令；
- 最終 dateChance 必須同時符合本場難度標準；challenge 缺高品質訊號即使聊得順也不得 high；
- Game 的技巧拆解仍由 Game contract 決定，但 dateChance 不得繞過難度與安全邊界。

**分數來源 helper**

把 `handler.ts:4114-4118` 的多層 ternary 抽成純函式：

```
resolveLearningSeed(...) → { temperatureScore, familiarityScore,
  source: ledger | relationship_thread | client | difficulty_default }
```

產品回應不暴露 source；只進無逐字稿的結構化 log（`practice_chat_succeeded` 補欄位）：practiceMode、difficulty、roundIndex、seed source、score before/after、delta、classification enums、challenge 閘門是否生效、是否 continuation、prompt policy version。**不記** user 文字、女孩回覆或完整 prompt。

**必補測試**

- seed 優先序：ledger ＞ 同 thread 分數 ＞ client seed ＞ 難度預設；thread profile 不符或資料無效時不得誤用
- continuation 從上一場 N 分開始，第一輪只動本輪 delta，無隱藏重置
- debrief full prompt 中，最終難度 dateChance 規則位於 band／invite guidance 之後

**回退條件：** 同一場 seed source 不穩定；debrief 與實際分數明顯矛盾。

## 背景脈絡

- 原 debrief user prompt 開頭就是難度標準（difficultyDebriefStandard），後面才是 band/stage/invite/game 證據——模型讀到後面高溫 band 或 invite ready 常直接蓋成 high（新發現 2）。
- 原 handler seed 邏輯（多層 ternary）：assisted 才有分數；ledger.exists 一律以 ledger 為準（欄位 null 的舊列 fallback 難度起始值、不吃 client）；未建檔時 thread 分數 ?? client seed ?? 難度預設，溫度與熟悉度逐欄位獨立 fallback。純函式要求行為逐項不變。
- thread profile 不符時 handler 上游已把 relationshipThreadState 設 null（practice_relationship_thread_profile_mismatch），純函式不重複驗。
- 計畫說 handler.ts:4114-4118，實際行號已漂移到 4140-4151（就是該 ternary，diff 可見）。
- 計畫的 log 欄位「score before/after」：before＝seed 後的本回合起點，after/delta 取自 LearningJudgement（score/delta/familiarityScore/familiarityDelta）。classification 只記 enums，刻意排除 innerThought（生成文字）與 moodConfidence 以外欄位——隱私鐵則：不記 user 文字、女孩回覆、完整 prompt。
- prompt 預算測試慣例：固定 bytes 的 prompt 加行要帶日期註解調上限（見 diff 中 prompt_test.ts 的註解串）。

## Diff（branch claude/practice-debrief-order-seed-observability，commit f3ec17c6，base main fc920dc0）

```diff
diff --git a/supabase/functions/practice-chat/handler.ts b/supabase/functions/practice-chat/handler.ts
index f9f9553c..fa2803ba 100644
--- a/supabase/functions/practice-chat/handler.ts
+++ b/supabase/functions/practice-chat/handler.ts
@@ -45,6 +45,7 @@ import {
   buildChatMessages,
   buildDebriefMessages,
   type ChatMessage,
+  PRACTICE_PROMPT_POLICY_VERSION,
 } from "./prompt.ts";
 import { difficultyTuningFor } from "./practice_persona.ts";
 import {
@@ -106,6 +107,7 @@ import {
   type PersistedGameState,
 } from "./game_state.ts";
 import { inviteMaturityFromLearningScores } from "./invite_maturity.ts";
+import { resolveLearningSeed } from "./learning_seed.ts";
 import {
   buildRelationshipThreadRpcParams,
   parseRelationshipThreadRow,
@@ -4136,19 +4138,22 @@ export function createPracticeChatHandler(
     const assistedMode = isAssistedPracticeMode(request.practiceMode);
     // 續聊保溫：只在 ledger 尚未建檔的新場首回合允許以 client 攜帶值 seed；
     // ledger 已建檔一律以 ledger 為準（欄位 null 的舊列 fallback 難度起始值，
-    // 不吃 client 值——以建檔與否切分，堵舊列吃 seed 的洞）。
-    const currentTemperature = assistedMode
-      ? ledger.exists
-        ? ledger.temperatureScore ?? difficultyStartTemperature
-        : relationshipThreadState?.temperatureScore ??
-          request.temperatureScore ?? difficultyStartTemperature
-      : null;
-    const currentFamiliarity = assistedMode
-      ? ledger.exists
-        ? ledger.familiarityScore ?? 0
-        : relationshipThreadState?.familiarityScore ??
-          request.familiarityScore ?? 0
-      : null;
+    // 不吃 client 值——以建檔與否切分，堵舊列吃 seed 的洞）。優先序與 source
+    // 標籤都在 resolveLearningSeed（PR 6）。
+    const learningSeed = resolveLearningSeed({
+      assistedMode,
+      ledger: {
+        exists: ledger.exists,
+        temperatureScore: ledger.temperatureScore,
+        familiarityScore: ledger.familiarityScore,
+      },
+      threadState: relationshipThreadState,
+      clientTemperatureScore: request.temperatureScore,
+      clientFamiliarityScore: request.familiarityScore,
+      difficultyStartTemperature,
+    });
+    const currentTemperature = learningSeed.temperatureScore;
+    const currentFamiliarity = learningSeed.familiarityScore;
     const trustedPartnerState = partnerStateFromLedger(ledger) ??
       relationshipThreadState?.partnerState ?? null;
     const promptPartnerState = promptPartnerStateForRequest(
@@ -4386,6 +4391,33 @@ export function createPracticeChatHandler(
       // 認識管道只記 id（allowlisted 常數，無使用者內容），供分佈與一致性觀測。
       acquaintanceOriginId: acquaintanceOrigin.id,
       costDeducted: deducted,
+      // ── PR 6 無逐字稿觀測：只有 enums／數字／布林，不記 user 文字、
+      // 女孩回覆或完整 prompt（innerThought 是生成文字，刻意不記）。──
+      practiceMode: request.practiceMode ?? "standard",
+      roundIndex: newAiCount,
+      seedSource: learningSeed.source,
+      temperatureBefore: currentTemperature,
+      temperatureAfter: temperature?.score ?? null,
+      temperatureDelta: temperature?.delta ?? null,
+      familiarityBefore: currentFamiliarity,
+      familiarityAfter: temperature?.familiarityScore ?? null,
+      familiarityDelta: temperature?.familiarityDelta ?? null,
+      classification: temperature
+        ? {
+          connection: temperature.classification.connection,
+          impact: temperature.classification.impact,
+          testHandling: temperature.classification.testHandling,
+          boundary: temperature.classification.boundary,
+          hintAlignment: temperature.classification.hintAlignment,
+          partnerMood: temperature.classification.partnerMood,
+        }
+        : null,
+      // 與計分管線同一判準（challenge × beginner 才有獎勵閘門）。
+      challengeGateActive: request.practiceMode === "beginner" &&
+        request.profile.difficulty === "challenge",
+      // 本回合 seed 是否接續上一場 thread（ledger 建檔後即為 false）。
+      continuation: !ledger.exists && relationshipThreadState != null,
+      promptPolicyVersion: PRACTICE_PROMPT_POLICY_VERSION,
     });
 
     const body: Record<string, unknown> = {
diff --git a/supabase/functions/practice-chat/learning_seed.ts b/supabase/functions/practice-chat/learning_seed.ts
new file mode 100644
index 00000000..f98be22a
--- /dev/null
+++ b/supabase/functions/practice-chat/learning_seed.ts
@@ -0,0 +1,64 @@
+/**
+ * 分數 seed 來源解析（PR 6）：把 handler 的多層 ternary 抽成純函式，
+ * 行為與原邏輯逐項相同，只是多了 source 標籤供無逐字稿觀測。
+ *
+ * 優先序：ledger（已建檔一律為準，欄位 null 的舊列 fallback 難度起始值、
+ * 不吃 client）＞ 同 thread 分數 ＞ client seed ＞ 難度預設。
+ * thread profile 不符時 handler 在上游已把 threadState 設 null，這裡不重複驗。
+ */
+
+export type LearningSeedSource =
+  | "ledger"
+  | "relationship_thread"
+  | "client"
+  | "difficulty_default";
+
+export interface LearningSeed {
+  temperatureScore: number | null;
+  familiarityScore: number | null;
+  /**
+   * temperatureScore 的來源（familiarity 逐欄位獨立 fallback，可能來自
+   * 下一層；觀測以主分數溫度為準）。standard 無分數系統 → null。
+   */
+  source: LearningSeedSource | null;
+}
+
+export function resolveLearningSeed(opts: {
+  assistedMode: boolean;
+  ledger: {
+    exists: boolean;
+    temperatureScore?: number | null;
+    familiarityScore?: number | null;
+  };
+  threadState:
+    | { temperatureScore?: number | null; familiarityScore?: number | null }
+    | null;
+  clientTemperatureScore?: number | null;
+  clientFamiliarityScore?: number | null;
+  difficultyStartTemperature: number;
+}): LearningSeed {
+  if (!opts.assistedMode) {
+    return { temperatureScore: null, familiarityScore: null, source: null };
+  }
+  if (opts.ledger.exists) {
+    return {
+      temperatureScore: opts.ledger.temperatureScore ??
+        opts.difficultyStartTemperature,
+      familiarityScore: opts.ledger.familiarityScore ?? 0,
+      source: opts.ledger.temperatureScore != null
+        ? "ledger"
+        : "difficulty_default",
+    };
+  }
+  return {
+    temperatureScore: opts.threadState?.temperatureScore ??
+      opts.clientTemperatureScore ?? opts.difficultyStartTemperature,
+    familiarityScore: opts.threadState?.familiarityScore ??
+      opts.clientFamiliarityScore ?? 0,
+    source: opts.threadState?.temperatureScore != null
+      ? "relationship_thread"
+      : opts.clientTemperatureScore != null
+      ? "client"
+      : "difficulty_default",
+  };
+}
diff --git a/supabase/functions/practice-chat/learning_seed_test.ts b/supabase/functions/practice-chat/learning_seed_test.ts
new file mode 100644
index 00000000..2cd30865
--- /dev/null
+++ b/supabase/functions/practice-chat/learning_seed_test.ts
@@ -0,0 +1,101 @@
+import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
+import { resolveLearningSeed } from "./learning_seed.ts";
+
+const emptyLedger = {
+  exists: false,
+  temperatureScore: null,
+  familiarityScore: null,
+};
+
+Deno.test("seed 優先序：ledger ＞ 同 thread 分數 ＞ client seed ＞ 難度預設", () => {
+  // ledger 已建檔一律以 ledger 為準，thread／client 都不得插隊。
+  assertEquals(
+    resolveLearningSeed({
+      assistedMode: true,
+      ledger: { exists: true, temperatureScore: 55, familiarityScore: 30 },
+      threadState: { temperatureScore: 70, familiarityScore: 50 },
+      clientTemperatureScore: 80,
+      clientFamiliarityScore: 60,
+      difficultyStartTemperature: 32,
+    }),
+    { temperatureScore: 55, familiarityScore: 30, source: "ledger" },
+  );
+  // ledger 舊列欄位 null → 難度起始值，不吃 client（堵舊列吃 seed 的洞）。
+  assertEquals(
+    resolveLearningSeed({
+      assistedMode: true,
+      ledger: { exists: true, temperatureScore: null, familiarityScore: null },
+      threadState: { temperatureScore: 70, familiarityScore: 50 },
+      clientTemperatureScore: 80,
+      clientFamiliarityScore: 60,
+      difficultyStartTemperature: 32,
+    }),
+    { temperatureScore: 32, familiarityScore: 0, source: "difficulty_default" },
+  );
+  // 未建檔＋thread 有分 → continuation 從上一場 N 分開始，無隱藏重置。
+  assertEquals(
+    resolveLearningSeed({
+      assistedMode: true,
+      ledger: emptyLedger,
+      threadState: { temperatureScore: 62, familiarityScore: 41 },
+      clientTemperatureScore: 80,
+      clientFamiliarityScore: 60,
+      difficultyStartTemperature: 32,
+    }),
+    {
+      temperatureScore: 62,
+      familiarityScore: 41,
+      source: "relationship_thread",
+    },
+  );
+  // 未建檔＋無 thread → client seed。
+  assertEquals(
+    resolveLearningSeed({
+      assistedMode: true,
+      ledger: emptyLedger,
+      threadState: null,
+      clientTemperatureScore: 80,
+      clientFamiliarityScore: 60,
+      difficultyStartTemperature: 32,
+    }),
+    { temperatureScore: 80, familiarityScore: 60, source: "client" },
+  );
+  // 全空 → 難度預設。
+  assertEquals(
+    resolveLearningSeed({
+      assistedMode: true,
+      ledger: emptyLedger,
+      threadState: null,
+      difficultyStartTemperature: 32,
+    }),
+    { temperatureScore: 32, familiarityScore: 0, source: "difficulty_default" },
+  );
+});
+
+Deno.test("standard 無分數系統：seed 全 null、source 為 null", () => {
+  assertEquals(
+    resolveLearningSeed({
+      assistedMode: false,
+      ledger: { exists: true, temperatureScore: 55, familiarityScore: 30 },
+      threadState: { temperatureScore: 70, familiarityScore: 50 },
+      clientTemperatureScore: 80,
+      clientFamiliarityScore: 60,
+      difficultyStartTemperature: 32,
+    }),
+    { temperatureScore: null, familiarityScore: null, source: null },
+  );
+});
+
+Deno.test("thread 資料無效（分數欄 null）不得誤用：逐欄位落到下一層", () => {
+  assertEquals(
+    resolveLearningSeed({
+      assistedMode: true,
+      ledger: emptyLedger,
+      threadState: { temperatureScore: null, familiarityScore: null },
+      clientTemperatureScore: 80,
+      clientFamiliarityScore: 60,
+      difficultyStartTemperature: 32,
+    }),
+    { temperatureScore: 80, familiarityScore: 60, source: "client" },
+  );
+});
diff --git a/supabase/functions/practice-chat/prompt.ts b/supabase/functions/practice-chat/prompt.ts
index fd01bbdd..a268c99a 100644
--- a/supabase/functions/practice-chat/prompt.ts
+++ b/supabase/functions/practice-chat/prompt.ts
@@ -68,6 +68,12 @@ export interface ChatMessage {
   content: string;
 }
 
+/**
+ * Prompt 政策版本（PR 6）：只進結構化 log，供跨版本比對分數行為。
+ * 改動 chat/hint/debrief 的政策性 prompt（順位、判準、閘門文案）時遞增。
+ */
+export const PRACTICE_PROMPT_POLICY_VERSION = "2026-08-29.pr6";
+
 const LEGACY_PARTNER_STATE_NO_LEAK_MARKER =
   "\u4E0D\u8981\u76F4\u63A5\u8AAA\u51FA partnerState";
 
@@ -988,6 +994,18 @@ export function buildDebriefMessages(
   const hintAccountabilityPrompt = debriefHintAccountabilityPrompt(
     options.appliedHintTurns,
   );
+  // 最終 dateChance 判準（PR 6）：放在所有狀態證據（band／stage／invite／
+  // game）之後——先前難度標準在開頭，模型讀到後面的高溫 band 或 invite
+  // ready 常直接蓋成 high。順位＝越後越終局。
+  const finalDateChancePrompt = `最終 dateChance 判準（讀完上面所有狀態證據後才適用）：\n` +
+    `- 上面的溫度 band、關係階段與邀約成熟度是證據，不是自動給 high 的命令。\n` +
+    `- 最終 dateChance 必須同時符合本場難度標準：\n${profile.difficultyDebriefStandard}\n` +
+    (profile.difficulty === "challenge"
+      ? `- 本場是挑戰難度：缺高品質訊號時，即使聊得順也不得評 high。\n`
+      : "") +
+    (options.practiceMode === "game"
+      ? `- Game 的技巧拆解仍照 Game contract，但 dateChance 不得繞過本場難度標準與安全邊界。\n`
+      : "");
   return [
     {
       role: "system",
@@ -1000,8 +1018,7 @@ export function buildDebriefMessages(
     {
       role: "user",
       content: `本場模擬對象：${profile.personaLabel}\n` +
-        `本場難度：${profile.difficultyLabel}\n` +
-        `${profile.difficultyDebriefStandard}\n\n` +
+        `本場難度：${profile.difficultyLabel}\n\n` +
         debriefAcquaintanceOriginLine(options.acquaintanceOrigin) +
         debriefNowContextLine(options.timeContext) +
         debriefSceneContextLine(options.sceneContext) +
@@ -1011,6 +1028,8 @@ export function buildDebriefMessages(
         stagePrompt +
         invitePrompt +
         (gamePrompt ? `\n\n${gamePrompt}\n\n` : "\n\n") +
+        finalDateChancePrompt +
+        "\n\n" +
         hintAccountabilityPrompt +
         "\n\n" +
         `${
diff --git a/supabase/functions/practice-chat/prompt_test.ts b/supabase/functions/practice-chat/prompt_test.ts
index b405e6af..1f6a6757 100644
--- a/supabase/functions/practice-chat/prompt_test.ts
+++ b/supabase/functions/practice-chat/prompt_test.ts
@@ -1088,7 +1088,9 @@ Deno.test("all 20 SR Hint and Debrief prompts stay bounded at 2/20/40 turns", ()
   // 同日 R2 主審 MINOR-3 修正 fallback 句保 JSON 契約，實測 6712，→6750。
   // 2026-08-28 時間錨點：同上一行「本場練習時間」（固定 85 bytes），
   // 上限 6750→6835。
-  if (maxDebriefWithHint > 6835) {
+  // 2026-08-29 PR 6：最終 dateChance 判準段（含 challenge／game 附加行，
+  // 固定 bytes），實測 6965，上限 6835→7000。
+  if (maxDebriefWithHint > 7000) {
     failures.push(
       `Debrief+Hint max ${maxDebriefWithHint} at ${maxDebriefWithHintCase}`,
     );
@@ -2636,3 +2638,49 @@ Deno.test("debrief 也拿得到今天是哪天，建議句才不會約到矛盾
   )[1].content;
   assertEquals(omitted.includes("本場練習時間"), false);
 });
+
+// ── PR 6：debrief 最終 dateChance 判準移到所有狀態證據之後 ──────────────
+
+Deno.test("debrief：最終 dateChance 判準位於 band／invite 證據之後", () => {
+  const turns = [
+    { role: "user" as const, text: "嗨，妳週末都做什麼？" },
+    { role: "ai" as const, text: "會去河邊走走，你呢？" },
+  ];
+  for (const difficulty of ["easy", "normal", "challenge"] as const) {
+    const scaled = resolvePracticeProfile({
+      profileId: "practice_girl_004",
+      difficulty,
+    });
+    const text = buildDebriefMessages(turns, scaled, {
+      practiceMode: "beginner",
+      temperatureScore: 40,
+      familiarityScore: 10,
+    }).map((message) => message.content).join("\n");
+    const finalRuleAt = text.indexOf("最終 dateChance 判準");
+    assert(finalRuleAt >= 0);
+    // band 證據（temperatureBandDebriefInstruction 的「本場收尾時…」）在前。
+    const bandAt = text.indexOf("本場收尾時");
+    assert(bandAt >= 0 && bandAt < finalRuleAt);
+    // invite 證據（inviteMaturity 結論行）在前。
+    const inviteAt = text.indexOf("inviteMaturity");
+    assert(inviteAt >= 0 && inviteAt < finalRuleAt);
+    // 難度標準跟著最終判準走，不再放在開頭。
+    assert(text.indexOf(scaled.difficultyDebriefStandard) > finalRuleAt);
+    // 明寫：狀態證據不是自動給 high 的命令。
+    assert(text.includes("不是自動給 high 的命令"));
+    if (difficulty === "challenge") {
+      assert(text.includes("缺高品質訊號"));
+    }
+  }
+  // game：技巧拆解照 Game contract，但 dateChance 不得繞過難度與安全邊界。
+  const gameText = buildDebriefMessages(
+    turns,
+    resolvePracticeProfile({
+      profileId: "practice_girl_004",
+      difficulty: "challenge",
+    }),
+    { practiceMode: "game", temperatureScore: 40, familiarityScore: 10 },
+  ).map((message) => message.content).join("\n");
+  assert(gameText.includes("最終 dateChance 判準"));
+  assert(gameText.includes("不得繞過"));
+});
```

## 驗證證據（執行端已跑，reviewer 不需重跑）

- 新測試先 RED（debrief 排序測試失敗＋learning_seed 模組不存在）後 GREEN。
- 全套 practice-chat Edge 測試（repo root）：1648 passed / 0 failed（含 prompt 預算測試，實測 6965 → 上限 7000）。

## 審查重點

1. resolveLearningSeed 是否與原 ternary 行為逐項相同（含 undefined/null 邊界、familiarity 獨立 fallback）；source 標籤語意是否誠實（familiarity 可能來自下一層，註解已聲明以溫度為準）。
2. debrief 最終判準段的位置與三條規則是否符合計畫；移走開頭難度標準有無破壞其他 debrief 消費點。
3. log 欄位是否齊、有無洩漏使用者內容（classification enums、innerThought 排除）；challengeGateActive 判準是否與計分管線（beginner×challenge）一致。
4. 測試是否鎖住宣稱行為（seed 四層優先序、continuation 無隱藏重置、判準位置在 band/invite 之後）、有無恆真。

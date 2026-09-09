# Review Packet｜VibeSync PR #53：練習室推進下限吃難度（PR 4）

你是獨立唯讀審查者。對抗式審查以下 diff。不要嘗試存取 repo、跑測試或呼叫其他模型；所有證據都在本 packet 內。
輸出格式：findings 用 P0-P3 分級（P0/P1 = block），最後給整體 verdict：APPROVE / APPROVE_WITH_RISK / BLOCK。用繁體中文。

## 需求（定案計畫 §PR 4，逐字）

### PR 4｜推進下限吃難度（修 D4 之一）

- **性質：** 推進節奏。**風險：中。** 只影響 beginner（game 走 FSM、standard 走白話 pacing 行）。

**修改檔案**

- `supabase/functions/practice-chat/practice_pacing.ts`
- `prompt.ts`（`practiceStageFloorFor` 呼叫點）、`hint.ts`（**四個呼叫點** `:992`、`:998`、`:1624`、`:1637`——守門與 prompt 必須同一份政策）
- `practice_pacing_test.ts`

**政策**

| 難度 | 可聊個人 | 可輕推曖昧 | 模糊邀約 |
|---|---:|---:|---:|
| easy／normal | 3 | 6 | 8 |
| challenge | 5 | 9 | **無純回合數下限** |

**API：** `practiceStageFloorFor(userTurnCount, mood, difficulty)`／`practiceInviteFloorFor(...)`／`standardPacingLine(...)`，`difficulty` 預設 `normal`，未更新的呼叫點行為不變。

**必補測試**

- easy／normal 仍 3／6／8；challenge 第 4 回合無 personal floor、第 5 才有；第 8 無 flirt floor、第 9 才有；任何回合不因回合數單獨取得 invite floor
- guarded／annoyed 仍停用整組 floor（順序：floor 先、mood 降階後套，維持現有釘法）
- NPC prompt 與 Hint 守門（`buildHintDecision`）同一份政策——不能一邊已准邀約、一邊叫使用者別推進

**回退條件：** challenge 永遠推不動；或 guarded／annoyed 仍被 floor 強制升階。

## 背景脈絡

- 產品：VibeSync 練習室（AI 約會教練）。三模式：standard（無分數，白話 pacing）、beginner（有分數＋回合下限）、game（FSM，自帶下限，floorTurns 傳 0 等於不套）。
- 難度 PracticeDifficulty = easy | normal | challenge，來自 profile.difficulty（server 端 resolvePracticeProfile 驗證）。
- 既有釘法（不得動）：mood 為 guarded/annoyed 時整組下限停用；invite floor 先套、mood 降階後套（inviteMaturityFromLearningScores 內部順序）。
- 修改前基準：practiceStageFloorFor 3/6、practiceInviteFloorFor 8、standardPacingLine 門檻 4 與 8，皆不吃難度。

## Diff（branch claude/practice-pacing-difficulty，commit d887a9f4，base main 0c81af28）

```diff
diff --git a/supabase/functions/practice-chat/hint.ts b/supabase/functions/practice-chat/hint.ts
index 4d92fdba..a4cba76d 100644
--- a/supabase/functions/practice-chat/hint.ts
+++ b/supabase/functions/practice-chat/hint.ts
@@ -989,13 +989,21 @@ export function buildHintDecision(
   const beginnerTurns = userTurnCountOf(opts.turns);
   const relationshipStage = applyStageFloor(
     relationshipStageFor(familiarityScore, temperatureScore),
-    practiceStageFloorFor(beginnerTurns, opts.partnerMood ?? null),
+    practiceStageFloorFor(
+      beginnerTurns,
+      opts.partnerMood ?? null,
+      opts.profile.difficulty,
+    ),
   );
   const maturity = inviteMaturityFromLearningScores({
     temperatureScore,
     familiarityScore,
     partnerMood: opts.partnerMood ?? null,
-    stageFloor: practiceInviteFloorFor(beginnerTurns, opts.partnerMood ?? null),
+    stageFloor: practiceInviteFloorFor(
+      beginnerTurns,
+      opts.partnerMood ?? null,
+      opts.profile.difficulty,
+    ),
   });
   const targetVariable = maturity?.stage === "not_ready" || !maturity
     ? "安全感與熟悉感"
@@ -1624,6 +1632,7 @@ export function buildHintMessages(opts: {
   const stageFloor = practiceStageFloorFor(
     floorTurns,
     opts.partnerMood ?? null,
+    opts.profile.difficulty,
   );
   const stage = applyStageFloor(
     relationshipStageFor(opts.familiarityScore ?? 0, score),
@@ -1634,7 +1643,11 @@ export function buildHintMessages(opts: {
     temperatureScore: score,
     familiarityScore: opts.familiarityScore ?? 0,
     partnerMood: opts.partnerMood ?? null,
-    stageFloor: practiceInviteFloorFor(floorTurns, opts.partnerMood ?? null),
+    stageFloor: practiceInviteFloorFor(
+      floorTurns,
+      opts.partnerMood ?? null,
+      opts.profile.difficulty,
+    ),
   });
   // 新手的推進上限：原本一律「只輕推情緒」，聊十輪也一樣，等於教人原地踏步。
   // 回合下限到位後跟著鬆一階；模糊邀約由 inviteMaturity 那段授權，這裡只負責
diff --git a/supabase/functions/practice-chat/practice_pacing.ts b/supabase/functions/practice-chat/practice_pacing.ts
index cafe51a4..c5326a32 100644
--- a/supabase/functions/practice-chat/practice_pacing.ts
+++ b/supabase/functions/practice-chat/practice_pacing.ts
@@ -10,6 +10,7 @@
  * 安全網照 game：她 guarded／annoyed 時整組下限不套，退場路線優先。
  */
 import type { InviteStage } from "./invite_maturity.ts";
+import type { PracticeDifficulty } from "./practice_persona.ts";
 import type {
   PartnerMood,
   RelationshipStage,
@@ -17,6 +18,19 @@ import type {
 } from "./temperature.ts";
 import type { PracticeTurn } from "./validate.ts";
 
+/**
+ * 難度別回合下限政策表（PR 4）。守門與 prompt 都吃這一份；challenge 的
+ * 模糊邀約沒有純回合數下限（invite: null），要真的把分數聊上去。
+ */
+const PACING_FLOORS: Record<
+  PracticeDifficulty,
+  { personal: number; flirt: number; invite: number | null }
+> = {
+  easy: { personal: 3, flirt: 6, invite: 8 },
+  normal: { personal: 3, flirt: 6, invite: 8 },
+  challenge: { personal: 5, flirt: 9, invite: null },
+};
+
 /** 使用者出手幾次＝這場走到第幾顆球。 */
 export function practiceUserTurnCount(turns: readonly PracticeTurn[]): number {
   return turns.filter((turn) => turn.role === "user").length;
@@ -26,14 +40,16 @@ function floorsSuspended(mood?: PartnerMood | null): boolean {
   return mood === "guarded" || mood === "annoyed";
 }
 
-/** 關係階段下限：第 3 顆球可以聊個人，第 6 顆球可以輕推曖昧。 */
+/** 關係階段下限：easy／normal 第 3 顆球聊個人、第 6 顆輕推曖昧；challenge 5／9。 */
 export function practiceStageFloorFor(
   userTurnCount: number,
   mood?: PartnerMood | null,
+  difficulty: PracticeDifficulty = "normal",
 ): RelationshipStage | null {
   if (floorsSuspended(mood)) return null;
-  if (userTurnCount >= 6) return "flirt_allowed";
-  if (userTurnCount >= 3) return "personal_allowed";
+  const floors = PACING_FLOORS[difficulty];
+  if (userTurnCount >= floors.flirt) return "flirt_allowed";
+  if (userTurnCount >= floors.personal) return "personal_allowed";
   return null;
 }
 
@@ -44,9 +60,13 @@ export function practiceStageFloorFor(
 export function practiceInviteFloorFor(
   userTurnCount: number,
   mood?: PartnerMood | null,
+  difficulty: PracticeDifficulty = "normal",
 ): InviteStage | null {
   if (floorsSuspended(mood)) return null;
-  return userTurnCount >= 8 ? "soft_invite_ready" : null;
+  const floors = PACING_FLOORS[difficulty];
+  return floors.invite !== null && userTurnCount >= floors.invite
+    ? "soft_invite_ready"
+    : null;
 }
 
 const STAGE_ORDER: readonly RelationshipStage[] = [
@@ -79,12 +99,15 @@ export function applyStageFloor(
 export function standardPacingLine(
   userTurnCount: number,
   mood?: PartnerMood | null,
+  difficulty: PracticeDifficulty = "normal",
 ): string {
   if (floorsSuspended(mood)) return "";
-  if (userTurnCount >= 8) {
+  const floors = PACING_FLOORS[difficulty];
+  if (floors.invite !== null && userTurnCount >= floors.invite) {
     return `\npacing: 你們已經來回 ${userTurnCount} 次了。只要對方沒有讓你不舒服，這時候你會比開場放鬆——可以主動提一點自己的事、接輕鬆的玩笑，也可以順著話題丟出你有空的時段或想去的地方。對方提「改天一起…」這種模糊邀約是自然的，不用當成太快。`;
   }
-  if (userTurnCount >= 4) {
+  // 中段行門檻沿用原本的 personal+1（3→4），challenge 順移成 6。
+  if (userTurnCount >= floors.personal + 1) {
     return `\npacing: 你們已經來回 ${userTurnCount} 次了。聊得順的話就從生活資訊往感受、偏好、小故事走一點，不要每一輪都停在客套的問答。`;
   }
   return "";
diff --git a/supabase/functions/practice-chat/practice_pacing_test.ts b/supabase/functions/practice-chat/practice_pacing_test.ts
index 4ad395b4..48570007 100644
--- a/supabase/functions/practice-chat/practice_pacing_test.ts
+++ b/supabase/functions/practice-chat/practice_pacing_test.ts
@@ -1,6 +1,7 @@
 import {
   assert,
   assertEquals,
+  assertThrows,
 } from "https://deno.land/std@0.168.0/testing/asserts.ts";
 import {
   applyStageFloor,
@@ -10,7 +11,7 @@ import {
   standardPacingLine,
 } from "./practice_pacing.ts";
 import { inviteMaturityFromLearningScores } from "./invite_maturity.ts";
-import { buildHintMessages } from "./hint.ts";
+import { buildHintDecision, buildHintMessages } from "./hint.ts";
 import { buildChatMessages } from "./prompt.ts";
 import { resolvePracticeProfile } from "./practice_persona.ts";
 import type { PracticeTurn } from "./validate.ts";
@@ -138,3 +139,87 @@ Deno.test("標準模式聊開後在 NPC prompt 拿到 pacing 行；game 完全
 Deno.test("practiceUserTurnCount 只算使用者出手數", () => {
   assertEquals(practiceUserTurnCount(turns(4)), 4);
 });
+
+// ── PR 4：推進下限吃難度 ─────────────────────────────────────────────
+
+const challengeProfile = resolvePracticeProfile({
+  profileId: "practice_girl_004",
+  difficulty: "challenge",
+});
+
+Deno.test("challenge 下限延後到 5／9，且沒有純回合數的邀約下限", () => {
+  assertEquals(practiceStageFloorFor(4, null, "challenge"), null);
+  assertEquals(practiceStageFloorFor(5, null, "challenge"), "personal_allowed");
+  assertEquals(practiceStageFloorFor(8, null, "challenge"), "personal_allowed");
+  assertEquals(practiceStageFloorFor(9, null, "challenge"), "flirt_allowed");
+  assertEquals(practiceInviteFloorFor(8, null, "challenge"), null);
+  assertEquals(practiceInviteFloorFor(30, null, "challenge"), null);
+});
+
+Deno.test("easy／normal 明寫難度仍是 3／6／8", () => {
+  for (const difficulty of ["easy", "normal"] as const) {
+    assertEquals(
+      practiceStageFloorFor(3, null, difficulty),
+      "personal_allowed",
+    );
+    assertEquals(practiceStageFloorFor(6, null, difficulty), "flirt_allowed");
+    assertEquals(practiceInviteFloorFor(7, null, difficulty), null);
+    assertEquals(
+      practiceInviteFloorFor(8, null, difficulty),
+      "soft_invite_ready",
+    );
+  }
+});
+
+Deno.test("challenge 的 guarded／annoyed 一樣整組停用", () => {
+  assertEquals(practiceStageFloorFor(9, "guarded", "challenge"), null);
+  assertEquals(practiceStageFloorFor(9, "annoyed", "challenge"), null);
+  assertEquals(standardPacingLine(9, "guarded", "challenge"), "");
+});
+
+Deno.test("standard challenge 的 pacing 行更慢，且不因回合數放行模糊邀約", () => {
+  assertEquals(standardPacingLine(5, null, "challenge"), "");
+  assert(standardPacingLine(6, null, "challenge").includes("pacing:"));
+  assert(!standardPacingLine(12, null, "challenge").includes("模糊邀約"));
+});
+
+Deno.test("NPC prompt 與 Hint 守門同一份政策：challenge 第 8 顆球不放行模糊邀約", () => {
+  const lowScores = { temperatureScore: 20, familiarityScore: 10 };
+  const normalPrompt = buildChatMessages(turns(8), profile, {
+    practiceMode: "beginner",
+    ...lowScores,
+  }).map((message) => message.content).join("\n");
+  assert(normalPrompt.includes("inviteStage: soft_invite_ready"));
+
+  const challengePrompt = buildChatMessages(turns(8), challengeProfile, {
+    practiceMode: "beginner",
+    ...lowScores,
+  }).map((message) => message.content).join("\n");
+  assert(challengePrompt.includes("inviteStage: not_ready"));
+
+  const softInviteReply = {
+    replyType: "warm_up" as const,
+    replyText: "改天有空也可以一起去河邊走走。",
+    rationale: "她提到喜歡散步，把它變成低壓共同畫面。",
+  };
+  const normalDecision = buildHintDecision({
+    turns: turns(8),
+    profile,
+    practiceMode: "beginner",
+    ...lowScores,
+    ...softInviteReply,
+  });
+  assertEquals(normalDecision.inviteRoute, "soft_invite_ready");
+  assertThrows(
+    () =>
+      buildHintDecision({
+        turns: turns(8),
+        profile: challengeProfile,
+        practiceMode: "beginner",
+        ...lowScores,
+        ...softInviteReply,
+      }),
+    Error,
+    "hint_quality_invalid_invite_route",
+  );
+});
diff --git a/supabase/functions/practice-chat/prompt.ts b/supabase/functions/practice-chat/prompt.ts
index 472ca2ac..fd01bbdd 100644
--- a/supabase/functions/practice-chat/prompt.ts
+++ b/supabase/functions/practice-chat/prompt.ts
@@ -6,6 +6,7 @@ import type { AppliedHintTurn, PracticeTurn } from "./validate.ts";
 import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../_shared/prompt_leak_guard.ts";
 import {
   difficultyTuningFor,
+  type PracticeDifficulty,
   type PracticeProfile,
 } from "./practice_persona.ts";
 import {
@@ -124,13 +125,18 @@ function standardInviteMaturityPrompt(opts: {
   partnerState?: PartnerState | null;
   memorySummary?: string | null;
   userTurnCount?: number;
+  difficulty?: PracticeDifficulty;
 }): string {
   const mood = opts.partnerState?.mood ?? "unknown";
   const moodGuard = mood === "guarded" || mood === "annoyed"
     ? "partnerMood is guarded/annoyed: cap escalation to no-invite or a very soft, optional invite."
     : "partnerMood is not guarded: still require current-turn receptiveness before direct invites.";
   return `\n\ninviteMaturity(hidden guidance; standard mode)\nrelationshipScore: unavailable\ninviteStage: infer only from the current transcript, profile, partnerState, and scene context; memorySummary alone never upgrades the invite stage\ndateChance: do not guarantee; explain uncertainty in debrief if needed\nguidance: Standard mode has no numeric heat/familiarity score. Use older memory only as background continuity. A fuzzy invite is appropriate only when the current transcript shows comfort or curiosity; a direct invite needs clear current interest. ${moodGuard} Acquaintance origin only sets her opening guard, not invite readiness — a low-guard origin like friend_intro never upgrades inviteStage by itself.${
-    standardPacingLine(opts.userTurnCount ?? 0, opts.partnerState?.mood ?? null)
+    standardPacingLine(
+      opts.userTurnCount ?? 0,
+      opts.partnerState?.mood ?? null,
+      opts.difficulty ?? "normal",
+    )
   }`;
 }
 
@@ -625,7 +631,7 @@ export function buildChatMessages(
   const beginnerMode = options.practiceMode === "beginner";
   const partnerMood = options.partnerState?.mood ?? null;
   const stageFloor = beginnerMode
-    ? practiceStageFloorFor(userTurnCount, partnerMood)
+    ? practiceStageFloorFor(userTurnCount, partnerMood, profile.difficulty)
     : null;
   const temperaturePrompt = assistedMode
     ? `\n\n${
@@ -647,7 +653,7 @@ export function buildChatMessages(
         familiarityScore: effectiveFamiliarity,
         partnerMood,
         stageFloor: beginnerMode
-          ? practiceInviteFloorFor(userTurnCount, partnerMood)
+          ? practiceInviteFloorFor(userTurnCount, partnerMood, profile.difficulty)
           : null,
       }),
     )
@@ -655,6 +661,7 @@ export function buildChatMessages(
       partnerState: options.partnerState,
       memorySummary: options.memorySummary,
       userTurnCount,
+      difficulty: profile.difficulty,
     });
   // Game 的 FSM 判定整包只算一次，gameMode 與 tensionLadder 共用同一份
   // snapshot——兩處各算會在越界輪端出兩個矛盾的 allowSpicyLevel。
```

## 驗證證據（執行端已跑，reviewer 不需重跑）

- `deno test --allow-env --allow-read practice_pacing_test.ts`：13 passed / 0 failed。
- 全套 practice-chat Edge 測試（repo root 執行）：1636 passed / 0 failed（moments_image_gate_test 需 repo-root cwd，已確認通過）。

## 審查重點

1. 政策表與計畫表是否逐格一致（easy/normal 3/6/8；challenge 5/9/無邀約回合下限）。
2. 守門（hint.ts buildHintDecision）與 NPC prompt（prompt.ts）是否確實同一份政策，有無漏掉的呼叫點（原計畫點名 hint.ts 四處＋prompt.ts）。
3. difficulty 預設 normal 是否保證未更新呼叫點行為不變（含 debrief 路徑 prompt.ts 的 standardInviteMaturityPrompt 未帶 difficulty）。
4. guarded/annoyed 停用與 mood 降階順序是否未被改動。
5. standardPacingLine 中段行門檻改為 personal+1 的推導是否造成 easy/normal 行為改變（3+1=4 應與原本逐字節相同）。
6. 測試是否真的鎖住宣稱行為（回歸鎖是否比較新碼自己跟自己）。

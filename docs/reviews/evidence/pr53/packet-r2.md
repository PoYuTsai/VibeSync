# Round 2 窄審｜VibeSync PR #53 修正 commit 05f8ccb9

你是獨立唯讀審查者。這是第二輪：只驗證下方單一修正 commit 是否正確解掉第一輪的 P1 與 P3。不要重審整個 PR、不要存取 repo、不要跑測試；證據都在本 packet。
輸出：每個 finding P0-P3，最後 verdict：APPROVE / APPROVE_WITH_RISK / BLOCK。繁體中文。

## 第一輪 finding（待驗證是否解掉）

- P1：政策表 challenge flirt: 9，但 standardPacingLine 未使用 floors.flirt，standard challenge 第 9 回合拿不到「可輕推曖昧」行。要求：第 9 回合新增輕曖昧許可、不含模糊邀約；easy/normal 行為不得變。
- P3：easy/normal 的 3/6 測試未鎖下界（第 2 回合 null、第 5 回合 personal）。

## 修正 commit diff（05f8ccb9，僅此一個 commit）

```diff
diff --git a/supabase/functions/practice-chat/practice_pacing.ts b/supabase/functions/practice-chat/practice_pacing.ts
index c5326a32..a52b8b3d 100644
--- a/supabase/functions/practice-chat/practice_pacing.ts
+++ b/supabase/functions/practice-chat/practice_pacing.ts
@@ -106,6 +106,12 @@ export function standardPacingLine(
   if (floors.invite !== null && userTurnCount >= floors.invite) {
     return `\npacing: 你們已經來回 ${userTurnCount} 次了。只要對方沒有讓你不舒服，這時候你會比開場放鬆——可以主動提一點自己的事、接輕鬆的玩笑，也可以順著話題丟出你有空的時段或想去的地方。對方提「改天一起…」這種模糊邀約是自然的，不用當成太快。`;
   }
+  // challenge 專用輕曖昧行（flirt: 9）：easy／normal 的第 8 回合行已涵蓋曖昧＋
+  // 模糊邀約，這條只在沒有邀約回合下限（invite: null）時出現，避免改動
+  // easy／normal 第 6-7 回合的既有行為。
+  if (floors.invite === null && userTurnCount >= floors.flirt) {
+    return `\npacing: 你們已經來回 ${userTurnCount} 次了。聊得順的話可以接一點輕鬆的玩笑、帶一點曖昧的張力，但先不急著提「改天一起…」這種邀約——她的興趣要真的被你聊起來才算數。`;
+  }
   // 中段行門檻沿用原本的 personal+1（3→4），challenge 順移成 6。
   if (userTurnCount >= floors.personal + 1) {
     return `\npacing: 你們已經來回 ${userTurnCount} 次了。聊得順的話就從生活資訊往感受、偏好、小故事走一點，不要每一輪都停在客套的問答。`;
diff --git a/supabase/functions/practice-chat/practice_pacing_test.ts b/supabase/functions/practice-chat/practice_pacing_test.ts
index 48570007..f52a15b4 100644
--- a/supabase/functions/practice-chat/practice_pacing_test.ts
+++ b/supabase/functions/practice-chat/practice_pacing_test.ts
@@ -156,12 +156,17 @@ Deno.test("challenge 下限延後到 5／9，且沒有純回合數的邀約下
   assertEquals(practiceInviteFloorFor(30, null, "challenge"), null);
 });
 
-Deno.test("easy／normal 明寫難度仍是 3／6／8", () => {
+Deno.test("easy／normal 明寫難度仍是 3／6／8（含下界）", () => {
   for (const difficulty of ["easy", "normal"] as const) {
+    assertEquals(practiceStageFloorFor(2, null, difficulty), null);
     assertEquals(
       practiceStageFloorFor(3, null, difficulty),
       "personal_allowed",
     );
+    assertEquals(
+      practiceStageFloorFor(5, null, difficulty),
+      "personal_allowed",
+    );
     assertEquals(practiceStageFloorFor(6, null, difficulty), "flirt_allowed");
     assertEquals(practiceInviteFloorFor(7, null, difficulty), null);
     assertEquals(
@@ -183,6 +188,18 @@ Deno.test("standard challenge 的 pacing 行更慢，且不因回合數放行模
   assert(!standardPacingLine(12, null, "challenge").includes("模糊邀約"));
 });
 
+Deno.test("standard challenge 第 9 回合放行輕曖昧，但仍不含模糊邀約", () => {
+  // 第 8 回合還在中段行，第 9 回合才升到輕曖昧行（政策表 flirt: 9）。
+  assert(!standardPacingLine(8, null, "challenge").includes("曖昧"));
+  const flirtLine = standardPacingLine(9, null, "challenge");
+  assert(flirtLine.includes("曖昧"));
+  assert(!flirtLine.includes("模糊邀約"));
+  assert(!standardPacingLine(20, null, "challenge").includes("模糊邀約"));
+  // easy／normal 不受新行影響：第 6-7 回合仍是原本的中段行，第 8 回合原行不變。
+  assert(!standardPacingLine(6, null, "normal").includes("曖昧"));
+  assert(standardPacingLine(8, null, "normal").includes("模糊邀約"));
+});
+
 Deno.test("NPC prompt 與 Hint 守門同一份政策：challenge 第 8 顆球不放行模糊邀約", () => {
   const lowScores = { temperatureScore: 20, familiarityScore: 10 };
   const normalPrompt = buildChatMessages(turns(8), profile, {
```

## 修正後 standardPacingLine 全文（現況）

```ts
export function standardPacingLine(
  userTurnCount: number,
  mood?: PartnerMood | null,
  difficulty: PracticeDifficulty = "normal",
): string {
  if (floorsSuspended(mood)) return "";
  const floors = PACING_FLOORS[difficulty];
  if (floors.invite !== null && userTurnCount >= floors.invite) {
    return `\npacing: 你們已經來回 ${userTurnCount} 次了。只要對方沒有讓你不舒服，這時候你會比開場放鬆——可以主動提一點自己的事、接輕鬆的玩笑，也可以順著話題丟出你有空的時段或想去的地方。對方提「改天一起…」這種模糊邀約是自然的，不用當成太快。`;
  }
  // challenge 專用輕曖昧行（flirt: 9）：easy／normal 的第 8 回合行已涵蓋曖昧＋
  // 模糊邀約，這條只在沒有邀約回合下限（invite: null）時出現，避免改動
  // easy／normal 第 6-7 回合的既有行為。
  if (floors.invite === null && userTurnCount >= floors.flirt) {
    return `\npacing: 你們已經來回 ${userTurnCount} 次了。聊得順的話可以接一點輕鬆的玩笑、帶一點曖昧的張力，但先不急著提「改天一起…」這種邀約——她的興趣要真的被你聊起來才算數。`;
  }
  // 中段行門檻沿用原本的 personal+1（3→4），challenge 順移成 6。
  if (userTurnCount >= floors.personal + 1) {
    return `\npacing: 你們已經來回 ${userTurnCount} 次了。聊得順的話就從生活資訊往感受、偏好、小故事走一點，不要每一輪都停在客套的問答。`;
  }
  return "";
}
```

## 驗證證據（執行端已跑）

- 新測試先 RED（修正前 13 passed / 1 failed）後 GREEN。
- 全套 practice-chat Edge 測試（repo root）：1637 passed / 0 failed。

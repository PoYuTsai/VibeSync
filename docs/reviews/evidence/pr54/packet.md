# Review Packet｜VibeSync PR #54：Hint 注入教練視角的難度尺度（PR 5）

你是獨立唯讀審查者。對抗式審查以下 diff。不要嘗試存取 repo、跑測試或呼叫其他模型；證據都在本 packet 內。
輸出格式：findings 用 P0-P3 分級（P0/P1 = block），最後給整體 verdict：APPROVE / APPROVE_WITH_RISK / BLOCK。用繁體中文。

## 需求（定案計畫 §PR 5，逐字）

### PR 5｜Hint 注入教練視角的難度尺度（修 D4 之二）

- **性質：** 教練一致性。**風險：中低。**

**修改檔案**

- `supabase/functions/practice-chat/practice_persona.ts`（`DifficultyConfig`／`PracticeProfile` 新增 `hintStandard`）
- `hint.ts`（`profileToEvidence` `:1207` 加 `difficultyCoachingStandard` 欄位）
- `practice_persona_test.ts`、`hint_test.ts`

**文案語意（教練視角，「你」＝使用者；不得重用 NPC 原文）**

- easy：自然、低壓、有回應即可；小尷尬可以修一次。
- normal：至少接住她一個具體點或分享一點自己；避免純查戶口。
- challenge：建議句必須接住她最新的具體內容、情緒或梗；一般禮貌句不算升溫；訊號不足時不建議邀約，也不要用萬用反問救場。

**必補測試**

- 三難度各帶出對應尺度；challenge Hint 不因回合數建議邀約；兩個可貼句仍可用（不得故意產生差句模擬難度）；不得把 NPC 第一人稱規格、難度名稱或幕後設定抄進可見回覆；Game Hint 仍以 Game tactic／FSM 優先。

**回退條件：** Hint 角色反轉、替女孩說話、可貼句品質下降。

## 背景脈絡

- Hint＝教練幫使用者寫兩個可貼回覆＋一段心法；prompt 內含 profile evidence 區塊（hidden evidence，非可見回覆）。
- profileToEvidence(profile, compactForGame, includeGameStrategy)：game hint 走 compactForGame=true（只有 identity 五行）；standard/beginner 走完整分支。另一呼叫點是 hintTrustedFactualEvidence（fact ledger 的 partner evidence，compactForGame=false）。
- PR 4 已合併：難度回合下限政策表（challenge 5/9/無邀約回合下限）；buildHintDecision 守門會對超出授權的邀約句丟 hint_quality_invalid_invite_route。
- NPC 難度 prompt（第一人稱、含【開場姿態】等段落標記與示範口吻）已存在於 DifficultyConfig.prompt；本 PR 的 hintStandard 是教練視角新文案，不得重用。

## Diff（branch claude/practice-hint-difficulty-standard，commit d4c62daf，base main 4266bb3d）

```diff
diff --git a/supabase/functions/practice-chat/hint.ts b/supabase/functions/practice-chat/hint.ts
index a4cba76d..5d4af37d 100644
--- a/supabase/functions/practice-chat/hint.ts
+++ b/supabase/functions/practice-chat/hint.ts
@@ -1229,6 +1229,9 @@ function profileToEvidence(
   const gameStrategy = includeGameStrategy ? buildGameStrategy(profile) : null;
   return [
     ...identity,
+    // 教練視角的難度尺度（PR 5）：只進 hidden evidence，不是可見回覆的一部分；
+    // game 走 compact 分支拿不到，維持 Game tactic／FSM 優先。
+    `difficultyCoachingStandard: ${profile.difficultyHintStandard}`,
     `testStylePropensity: ${profile.consistencyTest.propensity}`,
     `testStyleShapes: ${
       formatConsistencyTestTypes(profile.consistencyTest.types)
diff --git a/supabase/functions/practice-chat/hint_test.ts b/supabase/functions/practice-chat/hint_test.ts
index 2c979992..4d4dc276 100644
--- a/supabase/functions/practice-chat/hint_test.ts
+++ b/supabase/functions/practice-chat/hint_test.ts
@@ -7153,3 +7153,63 @@ Deno.test("第二刀：hint 代號表吃本局原話豁免", () => {
   });
   assertEquals(parsed.replies.length, 2);
 });
+
+// ── PR 5：Hint 注入教練視角的難度尺度 ─────────────────────────────────
+
+function pr5Turns(userTurnCount: number) {
+  const out: { role: "user" | "ai"; text: string }[] = [];
+  for (let i = 0; i < userTurnCount; i++) {
+    out.push({ role: "user", text: `使用者第${i}句` });
+    out.push({ role: "ai", text: `她第${i}句` });
+  }
+  return out;
+}
+
+Deno.test("Hint prompt 依難度帶出 difficultyCoachingStandard；game 不帶（FSM 優先）", () => {
+  for (const difficulty of ["easy", "normal", "challenge"] as const) {
+    const scaled = resolvePracticeProfile({
+      profileId: "practice_girl_004",
+      difficulty,
+    });
+    const text = buildHintMessages({
+      turns: pr5Turns(2),
+      profile: scaled,
+      practiceMode: "beginner",
+      temperatureScore: 40,
+    }).map((message) => message.content).join("\n");
+    assert(text.includes("difficultyCoachingStandard:"));
+    assert(text.includes(scaled.difficultyHintStandard));
+  }
+  const gameText = buildHintMessages({
+    turns: pr5Turns(2),
+    profile: resolvePracticeProfile({
+      profileId: "practice_girl_004",
+      difficulty: "challenge",
+    }),
+    practiceMode: "game",
+    temperatureScore: 40,
+    familiarityScore: 20,
+  }).map((message) => message.content).join("\n");
+  assert(!gameText.includes("difficultyCoachingStandard"));
+});
+
+Deno.test("challenge Hint 不因回合數建議邀約：第 12 顆球守門照擋", () => {
+  assertThrows(
+    () =>
+      buildHintDecision({
+        turns: pr5Turns(12),
+        profile: resolvePracticeProfile({
+          profileId: "practice_girl_004",
+          difficulty: "challenge",
+        }),
+        practiceMode: "beginner",
+        temperatureScore: 20,
+        familiarityScore: 10,
+        replyType: "warm_up",
+        replyText: "改天有空也可以一起去河邊走走。",
+        rationale: "她提到喜歡散步，把它變成低壓共同畫面。",
+      }),
+    Error,
+    "hint_quality_invalid_invite_route",
+  );
+});
diff --git a/supabase/functions/practice-chat/practice_persona.ts b/supabase/functions/practice-chat/practice_persona.ts
index 032dc333..d7956dfd 100644
--- a/supabase/functions/practice-chat/practice_persona.ts
+++ b/supabase/functions/practice-chat/practice_persona.ts
@@ -124,6 +124,7 @@ export interface PracticeProfile {
   difficultyLabel: string;
   difficultyPrompt: string;
   difficultyDebriefStandard: string;
+  difficultyHintStandard: string;
   girl: PracticeGirlProfile;
 }
 
@@ -141,6 +142,8 @@ interface DifficultyConfig {
   label: string;
   prompt: string;
   debriefStandard: string;
+  /** 教練視角的 Hint 尺度（「你」＝使用者）；不得重用 NPC 第一人稱原文。 */
+  hintStandard: string;
 }
 
 interface ProfessionConfig {
@@ -288,6 +291,8 @@ export const DIFFICULTIES: readonly DifficultyConfig[] = [
       "【邀約門檻】累積 1～2 個正向訊號（接得住話題、共同興趣或輕鬆玩笑其一）就可能答應低壓邀約。",
     debriefStandard:
       "本場為輕鬆難度：dateChance 判準本來就比一般／挑戰難度寬鬆，評分時不要套用一般或挑戰難度的標準來扣分。聊得舒服且正向訊號有延續（至少兩次接梗/延伸/輕鬆玩笑，或出現一次之後對話明顯升溫）就評 high，不需要具體場景鋪墊；普通無雷、或只出現一次正向訊號但沒有延續，評 medium；只有明顯尬聊、冒犯或查戶口感才評 low。",
+    hintStandard:
+      "本場是輕鬆難度：你的建議句自然、低壓就好，有真的回應到她就算合格；出現小尷尬可以用一句輕鬆的話修一次，不用急著加碼。",
   },
   {
     id: "normal",
@@ -306,6 +311,8 @@ export const DIFFICULTIES: readonly DifficultyConfig[] = [
       "- 對方連續查戶口 → 你：「你問好多喔哈哈」",
     debriefStandard:
       "本場為一般難度：dateChance 評 high 需要 2～3 個正向訊號（接梗、願意延伸、具體場景、或她釋出時間線索）；只有舒適感沒有鋪墊評 medium。",
+    hintStandard:
+      "本場是一般難度：你的建議句至少要接住她一個具體點，或分享一點你自己的事；避免只丟問題的純查戶口句。",
   },
   {
     id: "challenge",
@@ -328,6 +335,8 @@ export const DIFFICULTIES: readonly DifficultyConfig[] = [
       "- 對方長篇自我介紹但無趣 → 你：「嗯嗯」",
     debriefStandard:
       "本場為挑戰難度：dateChance 評 high 必須表現完整——接住她的興趣、自然調情不油、具體低壓場景、無壓迫感全部到位；只是聊得順但沒鋪邀約，最多 medium。不要因為她難聊就放寬標準。",
+    hintStandard:
+      "本場是挑戰難度：你的建議句必須接住她最新一句的具體內容、情緒或梗，一般禮貌句不算升溫；訊號不足時不要建議邀約，也不要用萬用反問救場。",
   },
 ] as const;
 
@@ -1039,6 +1048,7 @@ export function resolvePracticeProfile(args: {
     difficultyLabel: difficultyConfig.label,
     difficultyPrompt: difficultyConfig.prompt,
     difficultyDebriefStandard: difficultyConfig.debriefStandard,
+    difficultyHintStandard: difficultyConfig.hintStandard,
     girl,
   };
 }
diff --git a/supabase/functions/practice-chat/practice_persona_test.ts b/supabase/functions/practice-chat/practice_persona_test.ts
index 8d7c81ff..58805739 100644
--- a/supabase/functions/practice-chat/practice_persona_test.ts
+++ b/supabase/functions/practice-chat/practice_persona_test.ts
@@ -410,6 +410,32 @@ Deno.test("resolvePracticeProfile：challenge 難度帶出對應 difficultyDebri
   assert(profile.difficultyDebriefStandard.includes("挑戰難度"));
 });
 
+// ── Hint 教練尺度（PR 5）：resolvePracticeProfile 帶出教練視角的難度標準 ──
+
+Deno.test("resolvePracticeProfile：三難度各帶出教練視角 hintStandard", () => {
+  const easy = resolvePracticeProfile({ difficulty: "easy" });
+  assert(easy.difficultyHintStandard.includes("低壓"));
+  assert(easy.difficultyHintStandard.includes("修一次"));
+  const normal = resolvePracticeProfile({ difficulty: "normal" });
+  assert(normal.difficultyHintStandard.includes("具體"));
+  assert(normal.difficultyHintStandard.includes("查戶口"));
+  const challenge = resolvePracticeProfile({ difficulty: "challenge" });
+  assert(challenge.difficultyHintStandard.includes("禮貌句"));
+  assert(challenge.difficultyHintStandard.includes("萬用反問"));
+  assert(challenge.difficultyHintStandard.includes("不要建議邀約"));
+});
+
+Deno.test("hintStandard 是教練視角，不重用 NPC 第一人稱規格原文", () => {
+  for (const config of DIFFICULTIES) {
+    assert(config.hintStandard !== config.prompt);
+    // NPC prompt 的段落標記與示範口吻不得出現在教練尺度裡。
+    assert(!config.hintStandard.includes("【"));
+    assert(!config.hintStandard.includes("示範"));
+    // 教練視角：「你」＝使用者，不是 NPC 的「本場難度是…」自述開頭。
+    assert(!config.hintStandard.startsWith("本場難度是"));
+  }
+});
+
 Deno.test("resolvePracticeProfile：每個 persona 帶出一致性小測試設定", () => {
   const teasing = resolvePracticeProfile({
     profileId: "practice_girl_004",
```

## 驗證證據（執行端已跑，reviewer 不需重跑）

- 新測試先 RED（型別錯：hintStandard 欄位不存在）後 GREEN。
- practice_persona_test.ts＋hint_test.ts：213 passed / 0 failed。
- 全套 practice-chat Edge 測試（repo root）：1641 passed / 0 failed。

## 審查重點

1. 三難度 hintStandard 語意是否逐項對齊計畫（easy／normal／challenge 各自的尺度），且為教練視角、未重用 NPC 原文。
2. difficultyCoachingStandard 放進 profileToEvidence 完整分支：game hint 是否確實拿不到（FSM 優先）；fact ledger 呼叫點（hintTrustedFactualEvidence）也會帶到這行——是否構成風險（如被當成 partner 事實、或洩漏進可見回覆）。
3. 「challenge Hint 不因回合數建議邀約」「兩個可貼句仍可用」「不得抄幕後設定進可見回覆」等必補測試是否足夠、有無恆真。
4. 有無其他 PracticeProfile 建構點漏加 difficultyHintStandard（packet 內 grep 證據：resolvePracticeProfile 是唯一建構點）。

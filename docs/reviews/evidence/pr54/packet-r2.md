# Round 2 窄審｜VibeSync PR #54 修正 commit 46302ee2

你是獨立唯讀審查者。第二輪：只驗證下方單一修正 commit 是否解掉第一輪的四個 P1（與 P2/P3/Uncertain 的處置是否合理）。不要重審整個 PR、不要存取 repo、不要跑測試；證據都在本 packet。
輸出：findings P0-P3，最後 verdict：APPROVE / APPROVE_WITH_RISK / BLOCK。繁體中文。

## 第一輪 finding 與執行端處置

- P1-1 欄位名偏離計畫字面 → 已改回 PracticeProfile.hintStandard（與 DifficultyConfig 對齊）。
- P1-2 兩可貼句仍可用無測試 → 新增「三難度同一組好句都過 parseHintResult 與 buildHintDecision」round-trip 測試（好句不因難度被拒＝尺度不是靠產生差句實作）。註：可貼句的語言品質本身是 LLM 行為，靜態測試只能鎖品質守門路徑不因難度改變。
- P1-3 幕後設定不進可見回覆無驗證 → 本 repo 鐵則「注入內部詞必同步擴可見輸出守門」：已把 difficultycoachingstandard 加進 INTERNAL_VISIBLE_LABELS，並加 parseHintResult 外洩測試（hint_internal_label_leak）。難度名稱（輕鬆/一般/挑戰）不進中文守門表：是自然中文詞且 debrief 可見文本可能合法提及，加表會誤殺；NPC 難度 prompt 與 difficulty label 早已存在於 evidence，本 PR 未擴大這個暴露。
- P1-4 game 測試只有負面斷言 → 補 phase:/targetVariable: 正向斷言。
- P2-5 關鍵字抽查不全 → 逐項語意關鍵字補齊（easy 自然/低壓/回應/修一次；normal 具體/分享/查戶口；challenge 最新一句/情緒/梗/禮貌句不算升溫/訊號不足/不要建議邀約/萬用反問）。
- P3-6 不重用 NPC 原文強度不足 → 逐行比對：NPC prompt 任何 ≥8 字的整句不得出現在 hintStandard。
- Uncertain-7 fact ledger 混入教練指令 → 已隔離：profileToEvidence 加 includeCoachingStandard 參數（預設 false），只有 hint prompt 呼叫點帶 true；fact ledger 的 partner evidence 不帶，附測試。

## 修正 commit diff（46302ee2，僅此一個 commit）

```diff
diff --git a/supabase/functions/practice-chat/hint.ts b/supabase/functions/practice-chat/hint.ts
index 5d4af37d..551e49de 100644
--- a/supabase/functions/practice-chat/hint.ts
+++ b/supabase/functions/practice-chat/hint.ts
@@ -1216,6 +1216,7 @@ function profileToEvidence(
   profile: PracticeProfile,
   compactForGame = false,
   includeGameStrategy = false,
+  includeCoachingStandard = false,
 ): string {
   const girl = profile.girl;
   const identity = [
@@ -1229,9 +1230,12 @@ function profileToEvidence(
   const gameStrategy = includeGameStrategy ? buildGameStrategy(profile) : null;
   return [
     ...identity,
-    // 教練視角的難度尺度（PR 5）：只進 hidden evidence，不是可見回覆的一部分；
+    // 教練視角的難度尺度（PR 5）：只進 hint prompt 的 hidden evidence；
+    // fact ledger 的 partner evidence 不帶（教練指令不是伴侶事實），
     // game 走 compact 分支拿不到，維持 Game tactic／FSM 優先。
-    `difficultyCoachingStandard: ${profile.difficultyHintStandard}`,
+    ...(includeCoachingStandard
+      ? [`difficultyCoachingStandard: ${profile.hintStandard}`]
+      : []),
     `testStylePropensity: ${profile.consistencyTest.propensity}`,
     `testStyleShapes: ${
       formatConsistencyTestTypes(profile.consistencyTest.types)
@@ -1761,7 +1765,12 @@ export function buildHintMessages(opts: {
           : partnerBubbleRhythmPrompt(opts.turns) +
             stanceOptionPrompt(opts.turns)) +
         `profile evidence:\n${
-          profileToEvidence(opts.profile, opts.practiceMode === "game")
+          profileToEvidence(
+            opts.profile,
+            opts.practiceMode === "game",
+            false,
+            true,
+          )
         }\n\n` +
         `transcript evidence:\n${hintTurnsToPromptTranscript(opts.turns)}\n\n` +
         "請產生兩個可貼回覆與一段心法。warmUp、steady、coaching 各自重用 assistant 最新一句的具體詞、狀態或梗；不能只有 coaching 具體、回覆卻萬用。目標是接她最新一句，不是分析 user 前一句。只回繁中 JSON。",
diff --git a/supabase/functions/practice-chat/hint_test.ts b/supabase/functions/practice-chat/hint_test.ts
index 4d4dc276..54cb969f 100644
--- a/supabase/functions/practice-chat/hint_test.ts
+++ b/supabase/functions/practice-chat/hint_test.ts
@@ -7165,7 +7165,7 @@ function pr5Turns(userTurnCount: number) {
   return out;
 }
 
-Deno.test("Hint prompt 依難度帶出 difficultyCoachingStandard；game 不帶（FSM 優先）", () => {
+Deno.test("Hint prompt 依難度帶出 difficultyCoachingStandard；game 不帶且 FSM 證據仍在", () => {
   for (const difficulty of ["easy", "normal", "challenge"] as const) {
     const scaled = resolvePracticeProfile({
       profileId: "practice_girl_004",
@@ -7178,7 +7178,7 @@ Deno.test("Hint prompt 依難度帶出 difficultyCoachingStandard；game 不帶
       temperatureScore: 40,
     }).map((message) => message.content).join("\n");
     assert(text.includes("difficultyCoachingStandard:"));
-    assert(text.includes(scaled.difficultyHintStandard));
+    assert(text.includes(scaled.hintStandard));
   }
   const gameText = buildHintMessages({
     turns: pr5Turns(2),
@@ -7191,6 +7191,69 @@ Deno.test("Hint prompt 依難度帶出 difficultyCoachingStandard；game 不帶
     familiarityScore: 20,
   }).map((message) => message.content).join("\n");
   assert(!gameText.includes("difficultyCoachingStandard"));
+  // 正向斷言：Game 的 tactic／FSM 證據還在，不是整包 prompt 壞掉的假陰性。
+  assert(gameText.includes("phase:"));
+  assert(gameText.includes("targetVariable:"));
+});
+
+Deno.test("fact ledger 的 partner evidence 不帶教練尺度（教練指令不是伴侶事實）", () => {
+  const evidence = hintTrustedFactualEvidence({
+    profile: resolvePracticeProfile({
+      profileId: "practice_girl_004",
+      difficulty: "challenge",
+    }),
+    practiceMode: "beginner",
+  });
+  const partnerText = evidence.partner.join("\n");
+  assert(!partnerText.includes("difficultyCoachingStandard"));
+  // profile evidence 本體還在，不是整段被拔掉。
+  assert(partnerText.includes("testStylePropensity:"));
+});
+
+Deno.test("difficultyCoachingStandard 標籤外洩到可見回覆會被守門擋下", () => {
+  assertThrows(
+    () =>
+      parseHintResult(
+        JSON.stringify({
+          warmUp: "妳說的那間店我也想去看看。",
+          steady: "聽起來妳今天過得不錯。",
+          coaching: "依 difficultyCoachingStandard 來說這句要接住她的具體點。",
+        }),
+        { turns: pr5Turns(2) },
+      ),
+    Error,
+    "hint_internal_label_leak",
+  );
+});
+
+Deno.test("三難度同一組好句都過解析與守門：難度尺度不得靠產生差句實作", () => {
+  const goodReplies = {
+    warmUp: "妳說的那間咖啡店聽起來很有妳的風格。",
+    steady: "我也喜歡安靜一點的店，妳都點什麼？",
+    coaching: "接住她提到的店，再分享一點你自己的偏好。",
+  };
+  for (const difficulty of ["easy", "normal", "challenge"] as const) {
+    const scaled = resolvePracticeProfile({
+      profileId: "practice_girl_004",
+      difficulty,
+    });
+    const parsed = parseHintResult(JSON.stringify(goodReplies), {
+      turns: pr5Turns(2),
+    });
+    assertEquals(parsed.replies.length, 2);
+    const decision = buildHintDecision({
+      turns: pr5Turns(2),
+      profile: scaled,
+      practiceMode: "beginner",
+      temperatureScore: 40,
+      familiarityScore: 20,
+      replyType: "warm_up",
+      replyText: goodReplies.warmUp,
+      rationale: "接住她提到的店。",
+    });
+    assertEquals(decision.move, "build_connection");
+    assertEquals(decision.inviteRoute, "not_ready");
+  }
 });
 
 Deno.test("challenge Hint 不因回合數建議邀約：第 12 顆球守門照擋", () => {
diff --git a/supabase/functions/practice-chat/practice_persona.ts b/supabase/functions/practice-chat/practice_persona.ts
index d7956dfd..833b7306 100644
--- a/supabase/functions/practice-chat/practice_persona.ts
+++ b/supabase/functions/practice-chat/practice_persona.ts
@@ -124,7 +124,8 @@ export interface PracticeProfile {
   difficultyLabel: string;
   difficultyPrompt: string;
   difficultyDebriefStandard: string;
-  difficultyHintStandard: string;
+  /** 教練視角的 Hint 尺度（定案計畫 §PR 5 的欄位名，與 DifficultyConfig 對齊）。 */
+  hintStandard: string;
   girl: PracticeGirlProfile;
 }
 
@@ -1048,7 +1049,7 @@ export function resolvePracticeProfile(args: {
     difficultyLabel: difficultyConfig.label,
     difficultyPrompt: difficultyConfig.prompt,
     difficultyDebriefStandard: difficultyConfig.debriefStandard,
-    difficultyHintStandard: difficultyConfig.hintStandard,
+    hintStandard: difficultyConfig.hintStandard,
     girl,
   };
 }
diff --git a/supabase/functions/practice-chat/practice_persona_test.ts b/supabase/functions/practice-chat/practice_persona_test.ts
index 58805739..2b288d48 100644
--- a/supabase/functions/practice-chat/practice_persona_test.ts
+++ b/supabase/functions/practice-chat/practice_persona_test.ts
@@ -412,17 +412,24 @@ Deno.test("resolvePracticeProfile：challenge 難度帶出對應 difficultyDebri
 
 // ── Hint 教練尺度（PR 5）：resolvePracticeProfile 帶出教練視角的難度標準 ──
 
-Deno.test("resolvePracticeProfile：三難度各帶出教練視角 hintStandard", () => {
+Deno.test("resolvePracticeProfile：三難度各帶出教練視角 hintStandard（逐項語意）", () => {
   const easy = resolvePracticeProfile({ difficulty: "easy" });
-  assert(easy.difficultyHintStandard.includes("低壓"));
-  assert(easy.difficultyHintStandard.includes("修一次"));
+  assert(easy.hintStandard.includes("自然"));
+  assert(easy.hintStandard.includes("低壓"));
+  assert(easy.hintStandard.includes("回應"));
+  assert(easy.hintStandard.includes("修一次"));
   const normal = resolvePracticeProfile({ difficulty: "normal" });
-  assert(normal.difficultyHintStandard.includes("具體"));
-  assert(normal.difficultyHintStandard.includes("查戶口"));
+  assert(normal.hintStandard.includes("具體"));
+  assert(normal.hintStandard.includes("分享"));
+  assert(normal.hintStandard.includes("查戶口"));
   const challenge = resolvePracticeProfile({ difficulty: "challenge" });
-  assert(challenge.difficultyHintStandard.includes("禮貌句"));
-  assert(challenge.difficultyHintStandard.includes("萬用反問"));
-  assert(challenge.difficultyHintStandard.includes("不要建議邀約"));
+  assert(challenge.hintStandard.includes("最新一句"));
+  assert(challenge.hintStandard.includes("情緒"));
+  assert(challenge.hintStandard.includes("梗"));
+  assert(challenge.hintStandard.includes("禮貌句不算升溫"));
+  assert(challenge.hintStandard.includes("訊號不足"));
+  assert(challenge.hintStandard.includes("不要建議邀約"));
+  assert(challenge.hintStandard.includes("萬用反問"));
 });
 
 Deno.test("hintStandard 是教練視角，不重用 NPC 第一人稱規格原文", () => {
@@ -433,6 +440,16 @@ Deno.test("hintStandard 是教練視角，不重用 NPC 第一人稱規格原文
     assert(!config.hintStandard.includes("示範"));
     // 教練視角：「你」＝使用者，不是 NPC 的「本場難度是…」自述開頭。
     assert(!config.hintStandard.startsWith("本場難度是"));
+    // 逐行比對：NPC prompt 的任何一句實質內容（≥8 字）都不得整句出現在
+    // 教練尺度裡——擋「抄大段改一字」的重用。
+    for (const rawLine of config.prompt.split("\n")) {
+      const line = rawLine.replace(/^[-【].*?】?/, "").trim();
+      if (line.length < 8) continue;
+      assert(
+        !config.hintStandard.includes(line),
+        `NPC 原文整句重用於 ${config.id} hintStandard：${line}`,
+      );
+    }
   }
 });
 
diff --git a/supabase/functions/practice-chat/visible_text_guard.ts b/supabase/functions/practice-chat/visible_text_guard.ts
index 423665a2..4221d393 100644
--- a/supabase/functions/practice-chat/visible_text_guard.ts
+++ b/supabase/functions/practice-chat/visible_text_guard.ts
@@ -96,6 +96,10 @@ const INTERNAL_VISIBLE_LABELS = [
   // 鐵則＝注入內部詞必同步擴可見輸出守門。日期本身不進表：使用者本來就會
   // 問今天幾號，她照著答是對的行為，會外洩的只有標籤本身。
   "nowcontext",
+  // 教練難度尺度注入標籤（hint evidence，PR 5）；鐵則＝注入內部詞必同步擴
+  // 可見輸出守門。難度名稱本身（輕鬆／一般／挑戰）不進表：是自然中文詞，
+  // 會外洩的只有標籤本身。
+  "difficultycoachingstandard",
 ];
 
 // ── 第二刀（2026-08-24 Eric 拍板）：L4 拆兩類 ─────────────────────────
```

## 驗證證據（執行端已跑）

- practice_persona_test.ts＋hint_test.ts＋visible_text_guard_test.ts：241 passed / 0 failed。
- 全套 practice-chat Edge 測試（repo root）：1644 passed / 0 failed。

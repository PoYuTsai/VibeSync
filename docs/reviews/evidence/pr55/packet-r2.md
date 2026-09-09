# Round 2 窄審｜VibeSync PR #55 修正 commit 6d8577d5

你是獨立唯讀審查者。第二輪：只驗證下方單一修正 commit 是否解掉第一輪 findings。不要重審整個 PR、不要存取 repo、不要跑測試；證據都在本 packet。
輸出：findings P0-P3，最後 verdict：APPROVE / APPROVE_WITH_RISK / BLOCK。繁體中文。

## 第一輪 finding 與執行端處置

- P1-A（seedSource/continuation 第二輪翻面）→ 設計裁定＋補欄位：seedSource 語意定為「本回合實際讀取層」（thread 承接場：首回合 relationship_thread、之後 ledger 是正常型態，這正是被觀測的 ternary 真相；回退條件『同一場 seed source 不穩定』指的是偏離此型態的異常，例如第三輪突然變 client——per-round 真值才看得到）。log 補 ledgerExisted 欄位，查詢用 ledgerExisted=false 那筆即為整場初始來源與 continuation 判定，無需 schema 變更或跨輪持久化。程式註解已明寫兩者語意。
- P1-B（continuation 計分整合測試缺）→ 已補 handler 整合測試：無 ledger＋matching thread 62/41、client 帶 80/60，斷言 response score 66/delta 4、familiarity 46/delta 5（caught/medium 固定 delta）、chat prompt 含 62/100、commit 與 learning update 持久化參數皆從 62/41 起算——「從上一場 N 分開始、第一輪只動本輪 delta、無隱藏重置、client 輸給 thread」全鏈鎖住。
- P2（逐欄位 fallback 未鎖）→ 補三個混合案例（thread 只有溫度／只有熟悉度、ledger 只有溫度），並斷言 source 以溫度為準。
- P3（順序測試不完整）→ 改為只看 debrief user message（[1].content），完整鏈 band<stage<invite<最終判準；game 補 gameDebrief(hidden guidance) 在最終判準之前的斷言。
- Uncertain-P1（difficulty log 欄位）→ 該欄位在既有 log 本來就有（改前就存在，見下方現況全文），非缺漏。
- Uncertain-P2（profile mismatch）→ 既有測試「relationship thread state is ignored when it belongs to another profile」已涵蓋上游 null 化；seed 純函式收到 null thread 的行為由 learning_seed_test 鎖住。

## 修正 commit diff（6d8577d5，僅此一個 commit）

```diff
diff --git a/supabase/functions/practice-chat/handler.ts b/supabase/functions/practice-chat/handler.ts
index fa2803ba..e6d16261 100644
--- a/supabase/functions/practice-chat/handler.ts
+++ b/supabase/functions/practice-chat/handler.ts
@@ -4395,7 +4395,11 @@ export function createPracticeChatHandler(
       // 女孩回覆或完整 prompt（innerThought 是生成文字，刻意不記）。──
       practiceMode: request.practiceMode ?? "standard",
       roundIndex: newAiCount,
+      // seedSource＝本回合實際讀取層（thread 承接的新場：首回合
+      // relationship_thread、之後 ledger 是正常型態）。整場的初始來源
+      // 取同 session 首回合那筆；ledgerExisted 讓查詢能直接切首回合。
       seedSource: learningSeed.source,
+      ledgerExisted: ledger.exists,
       temperatureBefore: currentTemperature,
       temperatureAfter: temperature?.score ?? null,
       temperatureDelta: temperature?.delta ?? null,
@@ -4415,7 +4419,8 @@ export function createPracticeChatHandler(
       // 與計分管線同一判準（challenge × beginner 才有獎勵閘門）。
       challengeGateActive: request.practiceMode === "beginner" &&
         request.profile.difficulty === "challenge",
-      // 本回合 seed 是否接續上一場 thread（ledger 建檔後即為 false）。
+      // 本回合 seed 是否接續上一場 thread（ledger 建檔後即為 false）；
+      // 「整場是否 continuation」看同 session 首回合（ledgerExisted=false）那筆。
       continuation: !ledger.exists && relationshipThreadState != null,
       promptPolicyVersion: PRACTICE_PROMPT_POLICY_VERSION,
     });
diff --git a/supabase/functions/practice-chat/index_test.ts b/supabase/functions/practice-chat/index_test.ts
index b101c0d1..c665a0a6 100644
--- a/supabase/functions/practice-chat/index_test.ts
+++ b/supabase/functions/practice-chat/index_test.ts
@@ -8504,3 +8504,52 @@ Deno.test("貼文 RPC 卡住不回時，1:1 聊天仍然完成（不被選配查
   assertEquals(prompt.includes("<her_own_posts>"), false);
   assert(prompt.includes("不要否認"), "逾時 fail-open 後規則仍須在場");
 });
+
+Deno.test("continuation 從上一場 thread 分數起算：第一輪只動本輪 delta、不吃 client 也無隱藏重置", async () => {
+  const { response, json, state } = await run(
+    {
+      ledger: null,
+      thread: {
+        profile_id: "practice_girl_004",
+        temperature_score: 62,
+        familiarity_score: 41,
+      },
+      deepSeekReplies: ["AI reply", CLASSIFIER_CAUGHT_MEDIUM],
+    },
+    chatBody({
+      practiceMode: "beginner",
+      profileId: "practice_girl_004",
+      visiblePracticeThreadId: "thread-visible-1",
+      // client 帶不同分數，必須輸給 thread 分數。
+      temperatureScore: 80,
+      familiarityScore: 60,
+    }),
+  );
+
+  assertEquals(response.status, 200);
+  // 從 62/41 起算：caught/medium → heat +4、familiarity +5；只套一次 delta。
+  assertEquals(json.temperature.score, 66);
+  assertEquals(json.temperature.delta, 4);
+  assertEquals(json.temperature.familiarityScore, 46);
+  assertEquals(json.temperature.familiarityDelta, 5);
+
+  assert(
+    state.deepSeekCalls[0].messages[0].content.includes("62/100"),
+    "chat system prompt should start from thread temperature 62, not client 80",
+  );
+  // 持久化也從 thread 分數起算（無隱藏重置回難度預設或 client seed）。
+  const commit = state.rpcCalls.find((call) =>
+    call.fn === "commit_practice_chat_turn"
+  );
+  assert(commit);
+  assertEquals(commit.params.p_temperature_score, 62);
+  assertEquals(commit.params.p_familiarity_score, 41);
+  assertEquals(
+    learningUpdateCalls(state)[0].params.p_expected_temperature_score,
+    62,
+  );
+  assertEquals(
+    learningUpdateCalls(state)[0].params.p_expected_familiarity_score,
+    41,
+  );
+});
diff --git a/supabase/functions/practice-chat/learning_seed_test.ts b/supabase/functions/practice-chat/learning_seed_test.ts
index 2cd30865..8714fbce 100644
--- a/supabase/functions/practice-chat/learning_seed_test.ts
+++ b/supabase/functions/practice-chat/learning_seed_test.ts
@@ -99,3 +99,46 @@ Deno.test("thread 資料無效（分數欄 null）不得誤用：逐欄位落到
     { temperatureScore: 80, familiarityScore: 60, source: "client" },
   );
 });
+
+Deno.test("溫度與熟悉度逐欄位獨立 fallback；source 以溫度為準", () => {
+  // thread 只有溫度 → 熟悉度落到 client；source 仍是 relationship_thread。
+  assertEquals(
+    resolveLearningSeed({
+      assistedMode: true,
+      ledger: emptyLedger,
+      threadState: { temperatureScore: 62, familiarityScore: null },
+      clientTemperatureScore: 80,
+      clientFamiliarityScore: 60,
+      difficultyStartTemperature: 32,
+    }),
+    {
+      temperatureScore: 62,
+      familiarityScore: 60,
+      source: "relationship_thread",
+    },
+  );
+  // thread 只有熟悉度 → 溫度落到 client；source 跟著溫度標 client。
+  assertEquals(
+    resolveLearningSeed({
+      assistedMode: true,
+      ledger: emptyLedger,
+      threadState: { temperatureScore: null, familiarityScore: 41 },
+      clientTemperatureScore: 80,
+      clientFamiliarityScore: 60,
+      difficultyStartTemperature: 32,
+    }),
+    { temperatureScore: 80, familiarityScore: 41, source: "client" },
+  );
+  // ledger 只有溫度 → 熟悉度 fallback 0，不吃 thread/client。
+  assertEquals(
+    resolveLearningSeed({
+      assistedMode: true,
+      ledger: { exists: true, temperatureScore: 55, familiarityScore: null },
+      threadState: { temperatureScore: 70, familiarityScore: 50 },
+      clientTemperatureScore: 80,
+      clientFamiliarityScore: 60,
+      difficultyStartTemperature: 32,
+    }),
+    { temperatureScore: 55, familiarityScore: 0, source: "ledger" },
+  );
+});
diff --git a/supabase/functions/practice-chat/prompt_test.ts b/supabase/functions/practice-chat/prompt_test.ts
index 1f6a6757..4499fa34 100644
--- a/supabase/functions/practice-chat/prompt_test.ts
+++ b/supabase/functions/practice-chat/prompt_test.ts
@@ -2651,19 +2651,22 @@ Deno.test("debrief：最終 dateChance 判準位於 band／invite 證據之後",
       profileId: "practice_girl_004",
       difficulty,
     });
+    // 只看 user message：system prompt 未來若出現同字樣不得造成假通過。
     const text = buildDebriefMessages(turns, scaled, {
       practiceMode: "beginner",
       temperatureScore: 40,
       familiarityScore: 10,
-    }).map((message) => message.content).join("\n");
+    })[1].content;
     const finalRuleAt = text.indexOf("最終 dateChance 判準");
     assert(finalRuleAt >= 0);
-    // band 證據（temperatureBandDebriefInstruction 的「本場收尾時…」）在前。
+    // 完整順序鏈：band < stage < invite < 最終判準。
     const bandAt = text.indexOf("本場收尾時");
-    assert(bandAt >= 0 && bandAt < finalRuleAt);
-    // invite 證據（inviteMaturity 結論行）在前。
+    const stageAt = text.indexOf("本場抽象關係階段");
     const inviteAt = text.indexOf("inviteMaturity");
-    assert(inviteAt >= 0 && inviteAt < finalRuleAt);
+    assert(bandAt >= 0 && stageAt >= 0 && inviteAt >= 0);
+    assert(bandAt < stageAt);
+    assert(stageAt < inviteAt);
+    assert(inviteAt < finalRuleAt);
     // 難度標準跟著最終判準走，不再放在開頭。
     assert(text.indexOf(scaled.difficultyDebriefStandard) > finalRuleAt);
     // 明寫：狀態證據不是自動給 high 的命令。
@@ -2672,7 +2675,8 @@ Deno.test("debrief：最終 dateChance 判準位於 band／invite 證據之後",
       assert(text.includes("缺高品質訊號"));
     }
   }
-  // game：技巧拆解照 Game contract，但 dateChance 不得繞過難度與安全邊界。
+  // game：Game contract 證據在前、最終判準在後，且明寫 dateChance 不得繞過
+  // 難度與安全邊界。
   const gameText = buildDebriefMessages(
     turns,
     resolvePracticeProfile({
@@ -2680,7 +2684,10 @@ Deno.test("debrief：最終 dateChance 判準位於 band／invite 證據之後",
       difficulty: "challenge",
     }),
     { practiceMode: "game", temperatureScore: 40, familiarityScore: 10 },
-  ).map((message) => message.content).join("\n");
-  assert(gameText.includes("最終 dateChance 判準"));
+  )[1].content;
+  const gameFinalAt = gameText.indexOf("最終 dateChance 判準");
+  const gameEvidenceAt = gameText.indexOf("gameDebrief(hidden guidance)");
+  assert(gameEvidenceAt >= 0 && gameFinalAt >= 0);
+  assert(gameEvidenceAt < gameFinalAt);
   assert(gameText.includes("不得繞過"));
 });
```

## 現況：practice_chat_succeeded（chat 路徑）完整 payload

```ts
    logInfo("practice_chat_succeeded", {
      user: summarizeUser(user.id),
      mode: "chat",
      aiTurnCount: newAiCount,
      personaId: request.profile.personaId,
      difficulty: request.profile.difficulty,
      // 認識管道只記 id（allowlisted 常數，無使用者內容），供分佈與一致性觀測。
      acquaintanceOriginId: acquaintanceOrigin.id,
      costDeducted: deducted,
      // ── PR 6 無逐字稿觀測：只有 enums／數字／布林，不記 user 文字、
      // 女孩回覆或完整 prompt（innerThought 是生成文字，刻意不記）。──
      practiceMode: request.practiceMode ?? "standard",
      roundIndex: newAiCount,
      // seedSource＝本回合實際讀取層（thread 承接的新場：首回合
      // relationship_thread、之後 ledger 是正常型態）。整場的初始來源
      // 取同 session 首回合那筆；ledgerExisted 讓查詢能直接切首回合。
      seedSource: learningSeed.source,
      ledgerExisted: ledger.exists,
      temperatureBefore: currentTemperature,
      temperatureAfter: temperature?.score ?? null,
      temperatureDelta: temperature?.delta ?? null,
      familiarityBefore: currentFamiliarity,
      familiarityAfter: temperature?.familiarityScore ?? null,
      familiarityDelta: temperature?.familiarityDelta ?? null,
      classification: temperature
        ? {
          connection: temperature.classification.connection,
          impact: temperature.classification.impact,
          testHandling: temperature.classification.testHandling,
          boundary: temperature.classification.boundary,
          hintAlignment: temperature.classification.hintAlignment,
          partnerMood: temperature.classification.partnerMood,
        }
        : null,
      // 與計分管線同一判準（challenge × beginner 才有獎勵閘門）。
      challengeGateActive: request.practiceMode === "beginner" &&
        request.profile.difficulty === "challenge",
      // 本回合 seed 是否接續上一場 thread（ledger 建檔後即為 false）；
      // 「整場是否 continuation」看同 session 首回合（ledgerExisted=false）那筆。
      continuation: !ledger.exists && relationshipThreadState != null,
      promptPolicyVersion: PRACTICE_PROMPT_POLICY_VERSION,
    });

    const body: Record<string, unknown> = {
      reply,
      aiTurnCount: newAiCount,
```

## 驗證證據（執行端已跑）

- 全套 practice-chat Edge 測試（repo root）：1650 passed / 0 failed。

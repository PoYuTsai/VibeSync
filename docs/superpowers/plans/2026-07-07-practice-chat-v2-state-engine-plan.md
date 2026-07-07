# Phase 1 執行計畫：AI 實戰練習室 v2 角色狀態引擎

## 目標

把 beginner 升溫判定從 `event / personal / flirt` 話題分類，改成互動結果分類；同步 chat prompt、hint、debrief，讓輕鬆模式不再因「個人分享 / 平淡接梗」被結構性扣分。

## Task 1：測試先鎖 v2 行為

- `learning_state_test.ts`
  - `caught` 在 building 階段加 heat 與 familiarity。
  - `neutral + minor` 不再歸零。
  - `testHandling=passed` 在 building 階段加分。
  - `testHandling=failed` / `defensive` 扣分。
  - `boundary=overstep` 扣分且尊重難度倍率後的 clamp。
  - classifier prompt 不再要求 `event/personal/flirt` JSON，而要求 v2 schema。
- `index_test.ts`
  - DeepSeek stub JSON 改成 v2 schema。
  - hint 保護邏輯以 `connection/boundary/testHandling` 判定，不再看 `quality/overstep`。

## Task 2：實作 v2 classification 與 delta

- 改 `temperature.ts` 型別、parser、classifier prompt。
- 移除 `HEAT_MATRIX` / `FAMILIARITY_MATRIX` 依話題查表邏輯，改 outcome map。
- `judgeLearningState` 傳入 assistant 最新回覆作為判斷證據。
- deterministic obvious overstep 改回 v2 classification。

## Task 3：persona 小測試 prompt

- 在 `practice_persona.ts` 增加 persona 的小測試 profile。
- 新增 `consistency_test.ts` 生成 prompt snippet。
- `prompt.ts` 注入角色 prompt，難度決定頻率與力道。

## Task 4：hint / debrief 語言同步

- `hint.ts`：提示可辨識小測試，建議「先承認，再幽默曲解 / 反打 / 降低壓力」。
- `prompt.ts` debrief：拆解使用者是否接住她的情緒、界線、小測試；移除 event/personal/flirt 解釋框架。

## Task 5：驗證與收尾

- 跑 `deno test --allow-read --allow-env --allow-net=127.0.0.1 supabase/functions/practice-chat/`。
- 跑 git diff review。
- Commit + push `codex/practice-chat-v2-state-engine`。

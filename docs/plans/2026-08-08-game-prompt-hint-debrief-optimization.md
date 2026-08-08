# Game Mode prompt/hint/debrief 優化檢視與批次計畫

> 2026-08-08 檢視（唯讀，行號以當日 main / `claude/game-mode-onboarding-f49wm8` 為準）。
> 本檔是後續優化批次的真相源；開工前先讀這裡，不要只憑對話記憶。
> 關聯：Game onboarding 教學卡已上（ADR #39），glossary 對照以教學卡文案為錨。

## Eric 拍板（2026-08-08）

1. **詞彙統一（發現 #3）**：Game mode 統一用 Game 的詞彙；**文檔（教學卡 glossary）有標註的優先對標**——框架→「節奏與主見」、推拉→「輕鬆張力」、DHV→「生活樣本」、篩選→「互相合適度」；五階段可見名照教學卡：開場／展示／測試／張力／收尾（P3 可見名＝「測試」，debrief 契約的「品味門檻」退場或併入）。
2. **深水區三項另案討論**，本計畫不動（見文末）。
3. 其餘低垂項（#1、#2、#4，視情況帶 #5）**下輪一批動碼**；本輪只落檔。

## 背景

Game Mode 機制層完整（五相 FSM、四變數 pv/fp/inv/safety、7 失敗態、Hint 三件套、拆盤 gameBreakdown），
但檢視發現教學迴路與模擬品質有一批「有接線、沒接語意」或「守門缺口」問題。
檢視由子 agent 深讀 `prompt.ts`(894行)／`hint.ts`(2787行)／`debrief_card.ts`／`game_fsm.ts`(1255行)，
關鍵主張（#1、#2、#4）已由主 session 抽驗程式碼證據屬實。

## 下輪批次（低垂，一批做掉）

### #1 debrief 注入整場 failureCounts＋最低 hidden 變數 — 教學價值最高

- 現況：`gameDebriefPrompt`（`prompt.ts:655-667`）只注入 `compactGameFsmEvidencePrompt`（明寫移除 hidden 數值）＋
  `phaseRelevantGameStrategyPrompt`；`gameStateEvidencePrompt`（整場 `failureCounts`／`realityFlagCounts`／四變數 ledger，
  `game_state.ts:226-241`）只進 chat prompt。且 `effectiveGameFsmSnapshot` 不覆蓋 failureStates——fresh 只反映最後一句。
- 問題：第 3 輪 GREASY、第 8 輪 FRAME_COLLAPSE、最後一句乾淨的局，debrief 模型看到 `failureStates: none`，
  卻被要求寫 missedVariable／failureState。server 有帳（誰最高／哪個變數最低）但沒給模型。
- 做法：`gameDebriefPrompt` 加一行緊湊 ledger（例 `failureCounts: GREASY=2, BORING=1`＋`lowestVariable: inv=22`），
  <60 tokens。注意走 hidden evidence 命名慣例，防可見詞守門把新內部詞判洩漏（failureCounts 詞已在 repair/reject 詞表）。

### #2 修 tensionLadder 與 FSM 的 spicy level 自我矛盾 — 懲罰演出正確性

- 現況：game 模式 system prompt 同時含 `gameModePrompt`（`prompt.ts:577`，allowSpicyLevel 來自 FSM snapshot、
  有帶 failures/realityFlags，GREASY 壓 L0）與 `tensionLadderPrompt`（`prompt.ts:588`；`prompt.ts:149-156` 自己重算
  `spicyLevelFor({... failures: [], realityFlags: []})`）。
- 問題：使用者剛越界那輪，模型同時看到 `allowSpicyLevel: L0` 與 `L2` 兩個矛盾指令，懲罰演出可能失效。
- 做法：game 模式下 `tensionLadderPrompt` 直接吃 `snapshot.spicyLevel`（或 game 模式跳過重算段），不要兩處各算一次。

### #3 四變數／五相／階梯白話詞表單源化 — 已拍板方向（見上）

- 現況三分裂：hint 標籤修復 P3_TEST→「測試」（`hint.ts:250`）；jargon 轉譯「賦格」→「品味門檻」、「篩選」→「互相合適度」
  （`hint.ts:320-322`）；debrief 七步契約第三步叫「品味門檻」（`prompt.ts:616`）。
  另 debrief 端四變數**沒有**白話對照表（hint 端有：`hint.ts:277-286`，Frame→「節奏與主見」等），模型可自行發明第三種說法
  （debrief 對 1.2 原詞是 reject 不是 repair，發明詞不撞黑名單即放行）。
- 做法：抽單一 `GAME_VISIBLE_VOCAB` 常數模組，hint repair 表、debrief 契約指定用語、（概念上）client glossary 三方對齊；
  對標教學卡 glossary（見拍板 1）。同步 `visible_text_guard` 詞表（鐵則見 `visible_text_guard.ts:148-152` 註解）。
- 附帶：`targetVariableFor`（`game_fsm.ts:617-631`）值域含 familiarity/heat/invite 等第五類詞，標籤面一併對齊課程詞表
  （P1 的「熟悉感」保留白話但明確歸入詞表，不另發明）。

### #4 hint coaching 變數點名補守門（finding-only） — 三件套唯一沒守門的一環

- 現況：`assertGeneratedGameCoachingSubstance`（`hint.ts:2338-2360`，已抽驗全文）驗訊號具體性／任務具體性／理由，
  **沒有任何檢查要求 coaching 點名該推的變數**；prompt 有要求（`hint.ts:1324`）但無 enforcement，會靜默流失。
- 做法：substance gate 加偏好門（finding-only，不否決、零 503 風險）：coaching 需含四變數白話詞之一，
  可對 `decision.targetVariable`（`targetLabelForFallback`，`hint.ts:406-413`）做寬鬆比對；telemetry 觀測缺失率。

### #5（視批次餘裕）NPC per-phase 行為差異化＋hint 收口多樣化

- 現況：`socialGameNpcResponseContract`（`prompt.ts:119-121`）唯一相位條件句只有 P4/P5 可約窗口；P1/P2/P3 無 per-phase
  行為指令，五相在 NPC 端實際是「到不到可約」二分。hidden 四變數數字有進 prompt（`game_fsm.ts:895-901`）但無
  閾值→行為對應（花 token 買雜訊）。「30 分鐘短咖啡」收口在 few-shot／fallback 至少五處重複
  （`hint.ts:636-706, 1204-1234`），一局 5 發提示易撞同款。
- 做法：契約補 per-phase 行為小表（每相 1-2 行：投入上限／測試頻率／回覆長度／reward 什麼）；四變數改定性檔位或補
  閾值語意；few-shot 收成句加 2-3 變體、fallback 依 per-girl `closeHooks` 挑收口。需回歸測 NPC 不洩漏標籤。
- 相關既有取捨：coaching 軟上限 140 字（`hint.ts:1249`）若因 #4 加點名要求而擠爆，同步放寬到 160-180
  （parse 硬上限 320 本來就容得下）。

## 深水區（另案，先蒐證不動碼）

踩在 2026-08-05~07 拍板鏈上，動之前需重新對齊 Eric＋eval：

- **(a) P3_TEST 健康局結構性到不了**：`basePhaseFor`（`game_fsm.ts:595-615`）只在 partnerMood guarded/annoyed 回 P3；
  正常升溫路徑 P1→P2→P4→P5，「篩選」教學環節變成懲罰態。改法涉 FSM 相位轉移重設計，牽 hint 階梯／debrief／NPC 三面。
- **(b) Game salvage 路徑端出沒有拆盤的卡**：salvage 下 gameBreakdown 是可選區塊（`debrief_card.ts:337-339, 396-401`），
  殘缺即整塊丟 null——Game 局等於白打。先 telemetry 監控丟拆盤比率；偏高再議「拆盤專屬第三發重生成」。
- **(c) debrief 逐字稿 16 字剪裁 vs 引原話要求**：`DEBRIEF_PROMPT_TURN_CHAR_LIMIT=16`（`prompt.ts:304-309`），
  中段轉折無原話可引、grounding gate 已降 finding（`debrief_card.ts:961-977`）。改法＝對觸發過 failureState 的輪次
  保留 32-48 字，涉 transcript 組裝＋token 預算（Game debrief 有 12 秒預算註記 `prompt.ts:213`）。

## 觀測即可（不動）

- degrade pass 時 invite gate 讓路（`hint.ts:885`）造成 coaching 與句子可能對不上——2026-08-06 拍板的最後手段行為，
  `inviteRoute` 有照實標註；只監控 degrade 率。

## 其他已驗事實（實作時順手）

- pv 自揭詞表與 questionPressureScore 詞表漂移（`game_fsm.ts:775` vs `game_fsm.ts:122-129`）：抽同一
  `SELF_DISCLOSURE_TERMS` 常數（可併入 #3 批）。
- chat 端 fresh snapshot 與 hint/debrief 的 effective snapshot 相位來源不同（`prompt.ts:171-176` vs `hint.ts:871`）：
  NPC 可能同時看到兩個相位無優先順序。低垂偏中；若批次有餘裕，chat 端改吃 `effectiveGameFsmSnapshot` 或 prompt 明講
  persisted 為準，改後需真機驗行為。

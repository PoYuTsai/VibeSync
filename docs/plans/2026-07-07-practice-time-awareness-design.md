# AI 實戰練習室：時間觀念 + 生活時間軸設計（場景情境引擎）

> 狀態：設計文件（尚未實作）。範圍決策已由 Eric 確認：本次只出設計；
> 女生「現在動態」Phase 1 只藏在對話裡，UI 狀態列排 Phase 2；時間差感知排 Phase 2。

## 背景

2026-07-07 Eric 提出：實戰練習室的 chatbot 沒有時間觀念，希望研究優化：

1. 讓功能更像情感養成遊戲、更黏著。
2. 建立時間軸感：女生在不同時間點經歷不同生活事件（吃晚餐、跟朋友出去、潛水等）。

現況（已核實）：

- Prompt 全在 server（`supabase/functions/practice-chat/prompt.ts` + `practice_persona.ts`，DeepSeek `deepseek-v4-flash`）。`buildChatMessages` / `buildProfilePrompt` / `temperature.ts` **完全沒有注入任何時鐘資訊**——女生不知道現在是深夜還是上班時間，半夜也秒回、白天也閒聊，真實感斷裂。
- Handler 已有可注入時鐘 `deps.now?.() ?? new Date()`（`handler.ts`），翻牌重置已有台北牆鐘計算模式（`draw_decision.ts:37-69` `TAIPEI_OFFSET_MS` / `taipeiNoonResetWindow`）。
- 隱私模型：對話內容只存本地 Hive；server `practice_chat_sessions` 只有計數與學習狀態。任何時間軸設計都必須**零新增對話內容上傳、零新增 DB 狀態**。
- 已有 hidden-prompt 慣例：`prompt.ts:27-32` `partnerStatePrompt`（mood/innerThought，附防洩漏規則），是注入新隱藏情境的既有模板。
- 2026-07-07 v2 state engine 剛把升溫判定改成「互動結果分類」；本設計**不得污染 turn classifier 的判分輸入**。

## 決策

採單一「**場景情境（scene context）引擎**」：

- **Server 權威台北時鐘**（女生住台灣，in-fiction 正確；client 時間可偽造且時區不定）切出日段。
- **確定性 seed 生活事件**：每位女生、每天、每個日段，用 hash seed 從她的興趣/職業對應事件池抽出一個「她現在在做什麼」。確定性保證：同一日段內 chat / hint / debrief 看到同一個事件、免存任何狀態、client 未來可用同演算法鏡像出 UI 狀態列。
- 以一個精簡 hidden prompt 區塊注入（比照 `partnerStatePrompt`），約 4 行，控制 token 成本。

## A. 時間觀念（Phase 1）

新純函式模組 `supabase/functions/practice-chat/time_context.ts`（零依賴、可 deno test）：

- `taipeiWallClock(now: Date)`：沿用 `TAIPEI_OFFSET_MS` 位移模式，回傳台北 年/月/日/時/星期（不動 `draw_decision.ts`，之後再考慮抽共用）。
- `daySegmentFor(hour)`：清晨 5–7／早上 7–11／中午 11–14／下午 14–17／傍晚 17–19／晚上 19–23／深夜 23–5（跨午夜）。
- `isWeekend(dayOfWeek)`。

行為規則（進 prompt，白話、不出現內部詞彙）：

- 深夜：句子更短、想睡、可自然收尾「我要睡了，明天聊」。
- 上班/上課時段：回覆像偷空回的，短、偶爾敷衍、可說「等等要開會」。
- 被問「在幹嘛」照當下情境回答，前後一致。

適用 standard + beginner 兩種模式——時鐘真實感是基底行為（溫度區塊維持 beginner 限定不變）。

## B. 確定性生活事件時間軸（Phase 1）

新純函式模組 `supabase/functions/practice-chat/life_schedule.ts`：

```
seed = fnv1a32(`${profileId}|${taipeiDateKey}|${segmentIndex}`)
currentLifeEvent(girl, now) → { id, statusLine, promptLine, replyTempo }
```

- `statusLine`：短句「跟閨蜜吃火鍋」「剛下課在等公車」（Phase 2 給 UI 用）。
- `promptLine`：給模型的一句情境「妳現在跟閨蜜在吃火鍋，回訊息是偷空回的」。
- `replyTempo`: `free | busy | winding_down`，對應回覆長短/敷衍度指示。

事件池三層（全部只引用 catalog 既有欄位，不新增女生資料）：

1. **基底池**：日段 × 平日/週末 的通用事件（通勤、午餐、加班、追劇、洗完澡滑手機、準備睡…）。
2. **興趣池**：以 `interestTags` 既有字串為 key（旅行、美食、音樂祭、拍照、看書、做菜、寵物、咖啡、夜景散步、藝術、文青展覽、瑜珈、戶外爬山、電影、追劇、健身、做指甲、穿搭、烘焙、潛水或海邊活動、沙灘陽光…），只在合理日段出現（潛水/爬山限週末白天、夜景散步限傍晚以後）。
3. **職業節奏覆蓋**：輪班/特殊作息職業優先蓋過基底（`nurse_hospital` 可能大夜剛下班在補眠、`flight_attendant` 外站調時差、`barista` 早班開店、`mixologist` 晚上才上班、`college_student`/`graduate_student` 上課/趕論文）。

抽選規則：職業覆蓋池（若該日段有）> 興趣池（權重較高，週末更高）> 基底池；同 seed 恆定。

### Prompt 注入

`prompt.ts` 新增 `sceneContextPrompt(timeCtx, event)`，插入位置：

```
${CHAT_SYSTEM_PROMPT}${buildProfilePrompt(profile)}${temperaturePrompt}${sceneContextPrompt}${partnerStatePrompt}
```

內容約 4 行（草稿，實作時微調字數）：

```
sceneContext（hidden guidance，絕不能明講這是設定）：
現在是台灣時間{週幾}{日段}，{promptLine}。
回覆要自然符合這個時間與情境：{replyTempo 對應行為}；被問「在幹嘛」就照情境回答，可以主動提到一次，但不要一直重複報告行程。
如果對話紀錄裡妳提過在做別的事，代表時間過了，自然銜接（做完了、到家了），絕不否認自己說過的話。
```

- **銜接規則**是關鍵：對話歷史每次重送，模型看得到自己先前提過的事件；日段在 session 中途切換時靠這行自然過渡，不會前後矛盾。
- 防洩漏規則比照 partnerState：不可說出「sceneContext」「日段」「事件池」等內部詞。

### hint / debrief / classifier

- **hint**（`hint.ts` `profileToEvidence`）：加一行 `sceneStatus: {statusLine}`，讓提示教練建議的回覆能接住她的情境（「火鍋好吃嗎」比通用問題好）。
- **debrief**（`buildDebriefMessages`）：加一行事實脈絡——「她當時{statusLine}；因情境變短/變慢的回覆不代表使用者表現差」，避免教練把時鐘造成的冷淡誤判成使用者失分。
- **turn classifier（`buildTurnClassifierMessages`）不加**：v2 判分契約維持純互動結果，場景不進判分，避免「她在忙」被拿來當升溫/降溫理由。

## C. 養成/黏著機制

### Phase 1（本設計核心，純 server）

- 事件在對話中自然帶出＝好奇鉤子與話題素材：「我剛到餐廳」引導使用者練「接住情境、延伸話題」，與 debrief 的內容下切/在場感教學直接呼應——黏著度來自「她像活人」而不是斯金納箱。
- 深夜事件收斂到「準備睡覺」→ 對話自然收尾，兼顧防沉迷；debrief 仍是教學錨點。
- 每日節奏疊加既有中午 12:00 翻牌重置：早上她在上班、中午翻新牌、晚上她有生活——一天內不同時段進 app 體驗不同。

### Phase 2（下一階段，需動 client）

1. **UI 狀態列**：圖鑑卡/角色卡顯示「她現在：跟閨蜜吃火鍋」。Dart 端鏡像模組 `lib/features/practice_chat/domain/services/practice_girl_schedule.dart` 用同一 seed 演算法重算（client catalog 已有 interestTags/profileId）；跨語言漂移用共享測試向量檔（deno 與 flutter 各自 assert 同一份 JSON fixtures）。只顯示已解鎖女生；每日段刷新 → 開 app 的好奇迴圈。
2. **時間差感知**：`PracticeSession` 新增 Hive 欄位記最後回合時間（本地），client 送粗粒度整數 `hoursSinceLastTurn`（0–720，**不上傳對話內容**）；`validate.ts` 對無效值靜默丟棄（比照 catalogSize 慣例，不 400 舊 client）。gap ≥ 12h 且 roundIndex ≥ 2 才注入一行「距離上次聊已過{約略時段}，可以自然提到，但不責備、不情緒勒索」。

### Phase 3（需 Eric 產品決策，本設計不展開）

- 跨日持久關係/多日記憶：與 3 輪上限、5 visible threads、內容只存本地的隱私模型衝突，牽動 quota 商業設計。
- 連續登入 streak、成就、推播（可掛既有 `coach-follow-up` 通知基建）。

## 風險與成本

- Token：chat system prompt 約 +100–150 input tokens（+4–5%）；hint/debrief 各 +~40。輸出上限（`CHAT_MAX_TOKENS = 200`）不變。
- Prompt 改動屬高風險區：實作 PR 需 Codex review 證據；建議加 env kill-switch `PRACTICE_SCENE_CONTEXT_ENABLED`（預設開，異常時可即時關閉回舊行為）。
- 一致性風險：hint/debrief 與 chat 跨日段邊界呼叫可能拿到不同事件——可接受（銜接規則涵蓋），或實作時讓 debrief 用 session 首回合日段（實作時決定，優先簡單）。

## 實作切分（供實作 session 參照）

Phase 1（每 commit 一個關注點）：

1. `time_context.ts` + `life_schedule.ts` 純函式 + deno tests（日段邊界 04:59/05:00、跨午夜、seed 確定性/分布、興趣池日段合法性）。
2. `prompt.ts` 接線 `sceneContextPrompt` + `handler.ts` 傳 `deps.now`（高風險 prompt 變更，Codex review）+ kill-switch。handler 測試用固定 `deps.now`。
3. hint evidence + debrief 脈絡行。

Phase 2：Dart 鏡像 + 共享向量 → UI 狀態列 → 時間差欄位（server 先上、client 後送）。

## 非目標

- 不新增 DB schema、不動 quota/訂閱、不動 v2 turn classification 契約。
- Phase 1 不動 Flutter client、不做 UI 狀態列、不做時間差感知。
- 不上傳任何對話內容或精確時間戳；client 只會（Phase 2）送粗粒度小時差。
- 不把事件做成固定劇本或可窮舉的日程表；事件只是當下情境，不承諾跨日連續性。

# VibeSync 各區塊 AI 模型盤點（修訂版）

- 日期：2026-10-21（修訂版；原版同日）
- 依據：`main` `42df527`（2026-10-21 21:57 +0800）的程式碼，以及 repo 文件記錄的正式環境開關。修訂時逐條重新對過程式碼與文件，並用 2026-10-21 的官方定價頁核對 `_shared/model_pricing.ts`。
- 範圍：只讀程式與文件，沒有改任何檔案。這個環境沒有 Supabase 權限，讀不到正式環境的 secret；「真正在跑哪個模型」最後取決於第五節列的幾個 digest。
- 路徑：程式路徑以 `supabase/functions/` 為起點；`lib/`、`ios/`、`docs/` 開頭的是 repo 根目錄下的路徑。
- 與原版的差異列在文末「修訂紀錄」。

## 摘要

- 所有 AI 呼叫都在 Supabase Edge Function。App 端（`lib/`、`ios/`）沒有任何模型 API 網址，也沒有在手機上跑的模型套件（`pubspec.yaml` 沒有 ML Kit／TFLite，iOS 沒有 Vision／CoreML）。鍵盤的兩支 function 由 iOS 鍵盤擴充套件呼叫。
- 只有六支 Edge Function 會呼叫模型：`analyze-chat`、`coach-chat`、`coach-follow-up`（App 已不呼叫）、`keyboard-assist`、`keyboard-reply`、`practice-chat`。
- 用 Sonnet 5.5 的只有兩塊：對話分析（目前版本 App）、新話題。
- 問教練、開場救星、截圖辨識、訊息優化、回覆微調、鍵盤都是 Sonnet 5。
- 練習室的對話主要用 DeepSeek，提示與檢討用 Sonnet 5，動態配圖用 fal.ai 的 Seedream 4.5。
- 原版漏掉的四件事：截圖辨識沒有備援鏈；v3 流程不跑背景審稿；開場救星的 5.5 開關要先有 `OPENER_PLAN_WRITE`；練習室有一條成本保險絲會把 Haiku 輪強制改回 DeepSeek。

## 一、總表

| 區塊 | Edge Function | 主模型 | 條件／說明 |
|---|---|---|---|
| 對話分析（目前版本 App，v2 串流） | `analyze-chat` | **Sonnet 5.5** | `ANALYZE_STREAM_SONNET_55=true`（文件記 10/03 開）。前提是 `STREAM_ANALYZE_ENABLED=true`；沒開是整個拒絕，不是降級 |
| 對話分析（目前版本 App，v3 新流程） | `analyze-chat` | **Sonnet 5.5** | `ANALYZE_GUIDE_V3` 為 `on`，或 `test` 且測試帳號。讀局面與寫卡固定 5.5，不看串流開關、不吃 forceModel；**不跑背景審稿** |
| 對話分析（舊版 App，協定 1） | `analyze-chat` | Sonnet 5 | |
| 對話分析：對象記憶 | `analyze-chat` | Haiku 5.5 | 只在 v3 流程、且 `ANALYZE_GUIDE_V3_MEMORY` 開時才跑；只打一次、不換模型 |
| 對話分析：卡片說明（兩段式實驗） | `analyze-chat` | Sonnet 5.5 | 只在 v3 流程、且 `ANALYZE_GUIDE_V3_TWO_STAGE` 開時才跑 |
| 對話分析：背景審稿 | `analyze-chat` | Sonnet 5 | 只有 v2 串流有。影子模式，只記錄，不改結果 |
| 截圖辨識 | `analyze-chat` | Sonnet 5 | 單發，**沒有備援鏈** |
| 訊息優化／潤飾、回覆微調、任務卡再調 | `analyze-chat` | Sonnet 5 | 非串流；有 Sonnet 5 備援鏈 |
| 開場救星 | `analyze-chat` | Sonnet 5 | 第二段寫手、修格式、改寫可用 `OPENER_SONNET_55` 切到 5.5，但前提是 `OPENER_PLAN_WRITE=true` 與新版 App；文件記 `OPENER_SONNET_55` 沒開 |
| 新話題 | `analyze-chat` | **Sonnet 5.5** | `NEW_TOPIC_SONNET_55=true`（文件記 10/12 開） |
| 問教練 | `coach-chat` | Sonnet 5 | 回答與審稿都用它，沒有開關 |
| AI 鍵盤回覆 | `keyboard-reply` | Sonnet 5 | |
| 鍵盤截圖助手 | `keyboard-assist` | Sonnet 5 | 模型由 secret 指定，而且必須剛好是 `claude-sonnet-5` |
| 練習室：她的回覆 | `practice-chat` | **DeepSeek Flash** | 她主動出招的回合與碰到界線時改用 Haiku 4.5；成本保險絲燒斷時全部回 DeepSeek |
| 練習室：每輪判讀 | `practice-chat` | DeepSeek Flash | 溫度與介入分類 |
| 練習室：提示、檢討 | `practice-chat` | Sonnet 5 | 失敗改用 Haiku 4.5 重新產生；不受保險絲影響 |
| 練習室：動態貼文 | `practice-chat` | DeepSeek Flash（文字）＋ Seedream 4.5（配圖） | 配圖要 `MOMENT_IMAGE_GEN_ENABLED=true` 與 `FAL_API_KEY` |

## 二、各區塊細節

### 1. 對話分析（`analyze-chat`）

- 目前版本 App 宣告分析協定 3（`lib/features/analysis/data/services/analyze_stream_client.dart:673`）。協定 2 以上都算 v2 合約（`analyze-chat/analyze_chat_handler.ts:483-484`）。
- 一般對話分析只有串流一條生成路徑。`STREAM_ANALYZE_ENABLED` 不是 `true` 時，串流請求直接回 `STREAM_MODE_UNAVAILABLE`，不會退到非串流的 Sonnet 5（`analyze-chat/analyze_chat_handler.ts:245-247`、`:1387-1401`）。`STREAM_WHITELIST` 雖然還有傳進去，判斷只看旗標（`analyze-chat/stream_gate.ts:25-33`）。
- **v2 串流**：`ANALYZE_STREAM_SONNET_55=true` 時用 Sonnet 5.5，否則用 Sonnet 5；測試帳號的 forceModel 優先（`analyze-chat/analyze_stream_handler.ts:90-99`、`analyze-chat/analyze_chat_handler.ts:1947-1952`）。
- **v3 新流程**：`ANALYZE_GUIDE_V3` 是 `on`，或是 `test` 且為測試帳號才走；續看（帶 analysisRunId）一律回 v2 handler（`analyze-chat/analyze_chat_handler.ts:1796-1806`、`analyze-chat/guide_v3/routing.ts:16-25`）。
  - 讀局面與寫卡都用 Sonnet 5.5，寫死在程式裡，不看 `ANALYZE_STREAM_SONNET_55`（`analyze-chat/guide_v3/model_calls.ts:25`）。
  - 對象記憶用 Haiku 5.5，只打一次、不換模型（`analyze-chat/guide_v3/model_calls.ts:33`、`:103`）。
  - 卡片說明用同一個 5.5（`analyze-chat/guide_v3/model_calls.ts:5-6`、`:116-146`）。
  - 建立 v3 呼叫器時沒有傳 model，所以測試帳號的 forceModel 在 v3 不生效（`analyze-chat/analyze_chat_handler.ts:1886-1898`）。
  - v3 handler（`analyze-chat/guide_v3/stream_flow.ts:338`）沒有接背景審稿；審稿只掛在 v2 串流 handler（`analyze-chat/analyze_stream_handler.ts:709-720`）。
  - 其他 v3 子開關（上一輪脈絡、關係訊號、口吻斷句、短版稱讚、帶張力改寫、這題／滿→蠻）只改提示詞或後處理，不換模型。
- **舊版 App 與非串流分析**：Sonnet 5（`analyze-chat/model_selection.ts:22-44`、`analyze-chat/analyze_chat_handler.ts:1704-1706`）。
- **背景審稿**：Sonnet 5，v2 串流每個有選中卡的分析都審。只記錄成本與結果，不擋也不改卡（`analyze-chat/critic_shadow.ts:1-8`、`:36-44`）。
- **測試帳號**：v2 與非串流路徑可以用 `forceModel` 指定 Haiku 4.5、Sonnet 4.6、Sonnet 5、Sonnet 5.5；一般用戶帶了也不會採用（`analyze-chat/model_selection.ts:6-11`、`analyze-chat/analyze_chat_handler.ts:1704-1706`）。
- **5.5 的呼叫參數**：adaptive thinking（不回思考內容）加 effort low，`max_tokens` 多給 4000 當思考餘裕；Sonnet 5 預設關 thinking（`_shared/model_request_params.ts:10-14`、`:40-51`、`:58-62`）。

### 2. 截圖辨識、訊息優化／潤飾、回覆微調

- 都走 `analyze-chat` 的非串流路徑，正式環境固定用 Sonnet 5（`analyze-chat/analyze_chat_handler.ts:1704-1706`）。
- **截圖辨識（recognizeOnly）與任何帶圖請求沒有備援鏈**：`allowModelFallback = !hasImages`，每個請求 `maxRetries: 1`，所以截圖辨識只打一次 Sonnet 5，失敗就回錯誤（`analyze-chat/analyze_chat_handler.ts:1723`、`:1750`、`:2001-2002`）。
- 訊息優化（`optimize_message`）與回覆微調（`refine_reply`，含 v3 任務卡的再調）是純文字非串流，有 Sonnet 5 的備援鏈（`analyze-chat/analyze_chat_handler.ts:1135-1138`）。App 從同一個 client 送出（`lib/features/analysis/data/services/analysis_auxiliary_client.dart:147-200`）。

### 3. 開場救星

- 現行 App 走兩段式（`opener_analyze`、`opener_generate`；`lib/features/opener/data/services/opener_service.dart:555`、`:592`）。
- 第一段分析（含截圖辨識）與規劃：Sonnet 5（`analyze-chat/opener_flow_prompt.ts:18`、`analyze-chat/opener_flow_handler.ts:543`、`:843`）。
- 第二段寫句子、修格式、改寫：只有「結構刀」路徑才看 `OPENER_SONNET_55`，`true` 才用 5.5（`analyze-chat/opener_flow_prompt.ts:26-28`、`analyze-chat/opener_flow_handler.ts:841-842`）。
  - 結構刀路徑的前提：secret `OPENER_PLAN_WRITE=true`，而且 App 的生成請求帶 `openerCardSet=2`（`analyze-chat/opener_flow_handler.ts:707`、`analyze-chat/opener_plan_write.ts:50-57`）。目前 App 會帶（`lib/features/opener/domain/opener_access.dart:13`、`lib/features/opener/data/services/opener_service.dart:595`）。
  - 不走結構刀時整段都是 Sonnet 5，`OPENER_SONNET_55` 沒有作用。
  - `OPENER_PLAN_WRITE` 的正式環境值 repo 只有一筆間接紀錄：10/03 稽核寫「vault 記載旗標已開」（`docs/reviews/2026-10-03-analyze-chat-health-audit-findings.md:760`）。
  - 2026-10-13 的紀錄是 `OPENER_SONNET_55` 沒設，因為重跑後推薦句「願意照傳」只有 55/64，沒達到 60/64 的門檻（`docs/decisions.md:1399`）。
- 舊版 App 的單段開場：Sonnet 5（`analyze-chat/opener_handler.ts:394-396`）；它的修格式也是 Sonnet 5（`:132`）。`OPENER_TWO_STAGE_ENABLED` 設成 `false` 時不開新的兩段式工作，App 會退回這條舊路徑（`analyze-chat/opener_flow_handler.ts:422`）。
- `OPENER_STREAM_ENABLED` 只決定要不要串流回傳，不換模型（`analyze-chat/opener_flow_handler.ts:389`）。

### 4. 新話題

- `NEW_TOPIC_SONNET_55=true` 時用 Sonnet 5.5，否則用 Sonnet 5；修格式用同一個模型（`analyze-chat/new_topic_prompt.ts:17-23`、`analyze-chat/new_topic_handler.ts:954`、`:673-675`）。
- 文件記錄 2026-10-12 已開（`docs/decisions.md:1399`）。
- `NEW_TOPIC_TWO_STAGE_ENABLED` 只管收不收 `topicContext`（沒開回 422），不換模型（`analyze-chat/new_topic_handler.ts:442-445`）；文件記 10/2 起已開（`docs/decisions.md:1270`）。

### 5. 問教練（`coach-chat`）

- Sonnet 5，寫在程式裡，沒有開關（`coach-chat/generation.ts:167`）。
- 關閉 thinking，每次最多輸出 1200 tokens（`coach-chat/generation.ts:209`、`:1302-1304`）。
- `coachAnswer` 卡會再用同一個 Sonnet 5 跑一次語意審稿，所以一則正式回答至少呼叫兩次；追問卡不審（`coach-chat/generation.ts:244-245`、`:253-263`、`coach-chat/index.ts:685-686`）。
- 沒有第二個模型。Claude 呼叫本身丟錯才回「AI 生成失敗」（`coach-chat/generation.ts:218-225`）；拒答或 context window 用完回 500 並帶原因（`:336-345`）；驗證或審稿連續三發都不過、或超過生成期限，伺服器會剝掉建議句保留判斷，否則回內建的保守卡，不扣額度（`:189-197`、`:347-383`、`:913-923`）。
- App 所有「問教練」入口都導到同一個教練視窗 `/coach`（`lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart:1-6`）。

### 6. 鍵盤

- **AI 鍵盤回覆**：Sonnet 5，關 thinking，最多 180 tokens；格式不合會再打一次同模型修復（`keyboard-reply/generation.ts:18`、`:100-121`、`:185-190`）。iOS 端呼叫點在 `ios/VibeSyncKeyboard/KeyboardAPI.swift:220`。
- **鍵盤截圖助手**：Sonnet 5，一次呼叫（`keyboard-assist/index.ts:45-47`、`keyboard-assist/provider.ts:281-291`）。iOS 端呼叫點在 `ios/VibeSyncKeyboard/KeyboardAssistAPI.swift:144`。
  - secret `KEYBOARD_ASSIST_COMPILER_MODEL` 必須剛好等於 `claude-sonnet-5`，否則整個功能關閉（`keyboard-assist/index.ts:80-89`）。
  - 另外要 `KEYBOARD_SCREENSHOT_V1_ENABLED=true`，而且用戶要在白名單內；白名單空白代表所有登入用戶都可以用（`keyboard-assist/index.ts:257-267`）。
  - 2026-07-28 起已開放所有登入用戶（`docs/reviews/2026-07-27-keyboard-assist-production-deployment.md:126`）。

### 7. 練習室（`practice-chat`）

- **她的回覆**：DeepSeek Flash（`practice-chat/deepseek.ts:9`）。
  - `PRACTICE_CHAT_MODEL_ROUTING=mixed`、agency 開、而且模式是 beginner／game（standard 要再開 `PRACTICE_STANDARD_AGENCY_CLASSIFIER`）時，她主動出招的回合與碰到界線時改用 Haiku 4.5（`practice-chat/conversation_agency.ts:1617-1637`、`practice-chat/handler.ts:5116`）。
  - **成本保險絲**：`PRACTICE_COST_FUSE_DAILY_USD` 有設時，當日 Anthropic 花費（含提示與檢討）超過預算，之後的對話輪一律改回 DeepSeek；DB 讀寫失敗當沒燒斷；沒設就完全不碰 DB（`practice-chat/cost_fuse.ts:1-20`、`:47`、`practice-chat/handler.ts:2589`）。正式環境的值 repo 沒有紀錄，計畫寫預設空即關、之後再調到真實預算（`docs/plans/2026-09-05-practice-room-phase5-plan.md:331`）。
  - Haiku 失敗會在同一輪改回 DeepSeek（`practice-chat/handler.ts:5128-5139`）。DeepSeek 失敗不會改用 Claude。
- **每輪判讀**（溫度與介入分類）：DeepSeek（`practice-chat/handler.ts:1785`、`:1992`）。
- **提示、檢討**：Sonnet 5，失敗改用 Haiku 4.5 重新產生；不受保險絲降級（`practice-chat/claude.ts:5-6`、`practice-chat/handler.ts:3612`、`:4431`）。
- **動態貼文**：
  - 文字用 DeepSeek（`practice-chat/moments_handler.ts:873`）。
  - 配圖先用 DeepSeek 寫場景句，再交給 fal.ai 的 Seedream 4.5 生圖（`practice-chat/moments_image_gen.ts:1-12`、`:392`、`:126-127`）。
  - 配圖要 `MOMENT_IMAGE_GEN_ENABLED=true` 與 `FAL_API_KEY` 才會跑（`practice-chat/handler.ts:2398-2401`）。

### 8. 已停用或不用模型的 function 與路徑

- `coach-follow-up`：程式寫的是 Sonnet 5（`coach-follow-up/generation.ts:103`），但 App 已經不呼叫它（`lib/` 沒有任何呼叫點），Flutter 端只剩本機 Hive 裡的舊結果。
- `analyze-chat` 的 `my_message` 與 `draft_with_images_analyze` 兩條路徑現行 App 不送（`docs/reviews/2026-10-03-analyze-chat-health-audit-findings.md:860`）；程式還在，走非串流 Sonnet 5，帶圖那條沒有備援。
- `delete-account`、`revenuecat-webhook`、`submit-feedback`、`sync-subscription`：沒有任何模型 API 呼叫。

## 三、出錯時的備援

- **`analyze-chat` 純文字請求共用一套**，涵蓋對話分析、潤飾、回覆微調、開場救星第二段、新話題（`analyze-chat/model_fallback_chain.ts:16-20`）：
  - 主模型是 Sonnet 5.5：Sonnet 5.5，再退 Sonnet 5，再退 Sonnet 4.6
  - 主模型是 Sonnet 5：Sonnet 5，再退 Sonnet 4.6，再退 Haiku 4.5
  - 非串流：逾時、429、5xx 才換模型；拒答、輸出截斷、context window 用完都是不可重試的失敗，不換（`analyze-chat/fallback.ts:84-116`、`:300-318`、`:393-406`、`:417-427`）。
  - 串流：只有網路錯誤、429、5xx、空串流在開始前換模型，overloaded 在一個字都還沒送出前換；拒答、截斷、context window 用完都不換（`analyze-chat/streaming_fallback.ts:90-99`、`:160-167`、`:213-237`）。
  - **帶圖的請求不換模型**：截圖辨識、開場第一段帶截圖、帶圖分析都只打主模型（`analyze-chat/analyze_chat_handler.ts:1723`）。
  - 對象記憶只打一次，不換模型（`analyze-chat/guide_v3/model_calls.ts:103`）；新話題修格式也不換（`analyze-chat/new_topic_handler.ts:688`）。
- **問教練**：沒有第二個模型；驗證失敗的保底是伺服器內建的保守卡（見第二節第 5 點）。
- **鍵盤**：只用 Sonnet 5，沒有可以換的模型。
- **練習室**：她的回覆是 Haiku 退 DeepSeek；提示與檢討是 Sonnet 5 退 Haiku 4.5；保險絲燒斷是當天之後的對話輪都走 DeepSeek。

## 四、正式環境開關（文件記錄，未直接驗證）

| 開關 | 控制什麼 | 文件記錄 | 出處 |
|---|---|---|---|
| `STREAM_ANALYZE_ENABLED` | 一般對話分析能不能走串流（唯一的路）；非 `true` 整個拒絕 | 沒有記值，只有 7/16 計畫列為上線前要驗證；正式環境能分析就表示是 `true` | `docs/plans/2026-07-16-user-facing-ai-streaming-migration.md:81` |
| `ANALYZE_STREAM_SONNET_55` | v2 串流分析用 5.5 | `true`，2026-10-03 開 | `docs/reviews/2026-10-03-analyze-chat-health-audit-findings.md:20` |
| `ANALYZE_GUIDE_V3` | 走 v3 新流程 | 10/17 紀錄為沒設；10/18 審查紀錄標題的「上線」指程式併入 main，內文只改 App 顯示、沒寫開關；10/18 到 10/21 沒有任何文件記值 | `docs/reviews/2026-10-17-analysis-stage3-slice12-review-record.md:80`、`docs/reviews/2026-10-18-v3-launch-ui-fixes-review-record.md:1-6` |
| `ANALYZE_GUIDE_V3_MEMORY` | 對象記憶（Haiku 5.5） | 沒找到紀錄；程式預設關 | — |
| `ANALYZE_GUIDE_V3_TWO_STAGE` | 卡片說明（5.5） | 沒找到紀錄；程式預設關 | — |
| `NEW_TOPIC_SONNET_55` | 新話題用 5.5 | `true`，2026-10-12 開 | `docs/decisions.md:1399` |
| `NEW_TOPIC_TWO_STAGE_ENABLED` | 新話題收不收 topicContext；不換模型 | 10/2 起已開 | `docs/decisions.md:1270` |
| `OPENER_PLAN_WRITE` | 開場救星第二段走結構刀；是 `OPENER_SONNET_55` 生效的前提 | 只有 10/03 稽核寫「vault 記載旗標已開」 | `docs/reviews/2026-10-03-analyze-chat-health-audit-findings.md:760` |
| `OPENER_SONNET_55` | 開場救星結構刀的寫手、修格式、改寫用 5.5 | 2026-10-13 紀錄為沒設 | `docs/decisions.md:1399` |
| `OPENER_TWO_STAGE_ENABLED` | 設 `false` 才停掉兩段式、退回舊單段；沒設等於開 | 沒找到紀錄 | — |
| `KEYBOARD_ASSIST_COMPILER_MODEL` | 鍵盤截圖助手用的模型 | 沒有記錄值；不是 `claude-sonnet-5` 的話功能會整個關閉 | `docs/reviews/2026-07-27-keyboard-assist-production-deployment.md:39` |
| `KEYBOARD_SCREENSHOT_V1_ENABLED`＋白名單 | 鍵盤截圖助手開放給誰 | 2026-07-28 起開放所有登入用戶 | `docs/reviews/2026-07-27-keyboard-assist-production-deployment.md:126` |
| `PRACTICE_CONVERSATIONAL_AGENCY_ENABLED` | 練習室 agency（混用 Haiku 的前提） | `true`，2026-09-05 | `docs/plans/2026-09-05-practice-room-phase5-plan.md:798` |
| `PRACTICE_CHAT_MODEL_ROUTING` | 練習室混用 Haiku | `mixed`，2026-09-05 | 同上 |
| `PRACTICE_STANDARD_AGENCY_CLASSIFIER` | standard 模式也混用 Haiku | `true`，2026-09-05 | 同上 |
| `PRACTICE_COST_FUSE_DAILY_USD` | 練習室當日 Anthropic 預算；超標後對話輪強制 DeepSeek | 沒有記值；計畫寫預設空（關），之後調到真實預算 | `docs/plans/2026-09-05-practice-room-phase5-plan.md:331` |
| `MOMENT_IMAGE_GEN_ENABLED` | 動態配圖 | `true`，2026-08-26 | `docs/practice-moment-image-activation-runbook.md:20` |

`ANALYZE_GUIDE_V3` 不論開或關，目前版本 App 的分析主模型都是 5.5（前提是 `ANALYZE_STREAM_SONNET_55` 照文件記錄仍是 `true`）。差別在呼叫次數：開了會多跑對象記憶與卡片說明（各自還要開關），但不跑背景審稿；關著只有一次主呼叫加一次背景審稿。

## 五、怎麼確認正式環境的開關

Supabase Dashboard → Edge Functions → Secrets 不會顯示原值，只顯示每個值的 SHA-256 digest。拿 digest 對照下表（2026-10-21 重新算過）：

| 值 | SHA-256 |
|---|---|
| `true` | `b5bea41b6c623f7c09f1bf24dcae58ebab3c0cdd90ad966bc43a45b44867e12b` |
| `on` | `b8d31e852725afb1e26d53bab6095b2bff1749c9275be13ed1c05a56ed31ec09` |
| `test` | `9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08` |
| `mixed` | `3f8fee624f43b2a9d685353269a0ab3eac785863ab6227636db1060fba1855e0` |
| `claude-sonnet-5` | `4b07d9a517e35f5852d8385b4a192070b78ed4722b3b043b5737ddd7570283d7` |

注意：值若是帶換行貼進去的，digest 會不同。`true` 加換行是 `a17fcf0a2f50e2d495e4f90ce263410edc183add6c62699a2facbccf60410f74`，`on` 加換行是 `b6ac5bc39377e44ee783dff946f6703a994f5eb31a438e69dc0735b40060d2e8`；對到這兩個表示值多了換行，程式會當成沒開。

建議依序確認：

1. `ANALYZE_GUIDE_V3`：決定對話分析走 v2 還是 v3，連帶決定有沒有背景審稿。
2. `ANALYZE_GUIDE_V3_MEMORY`、`ANALYZE_GUIDE_V3_TWO_STAGE`：決定每次 v3 分析多打幾次模型。
3. `OPENER_PLAN_WRITE`：沒開的話 `OPENER_SONNET_55` 永遠沒作用。
4. `PRACTICE_COST_FUSE_DAILY_USD`：有正數就表示保險絲在運作，練習室 Haiku 輪可能被壓回 DeepSeek。
5. `KEYBOARD_ASSIST_COMPILER_MODEL`：不是 `claude-sonnet-5` 的 digest 就表示鍵盤截圖助手目前是關的。

## 六、模型代號對照

| 名稱 | 程式代號 | 供應商 | 用在哪裡 |
|---|---|---|---|
| Sonnet 5.5 | `claude-sonnet-5-5` | Anthropic | 對話分析、新話題 |
| Sonnet 5 | `claude-sonnet-5` | Anthropic | 多數 Claude 功能 |
| Sonnet 4.6 | `claude-sonnet-4-6` | Anthropic | 只在備援鏈與測試帳號 |
| Haiku 5.5 | `claude-haiku-5-5` | Anthropic | 對象記憶 |
| Haiku 4.5 | `claude-haiku-4-5-20251001` | Anthropic | 備援鏈、練習室 |
| DeepSeek Flash | `deepseek-flash`（背後是 V4.1 Flash） | DeepSeek | 練習室 |
| Seedream 4.5 | `fal-ai/bytedance/seedream/v4.5/text-to-image` | fal.ai | 練習室動態配圖 |

`claude-opus-5-5` 與 `claude-sonnet-4-20250514` 只出現在價格表（`analyze-chat/logger.ts:14-31`、`_shared/model_pricing.ts`），沒有任何呼叫點。

各模型單價見 `_shared/model_pricing.ts`；2026-10-21 對過官方定價頁，數字一致（Sonnet 5.5 快取讀取 $0.10／M、Haiku 5.5 十萬 token 以內 $0.10／$0.50、超過 $0.50／$2.50、Opus 5.5 快取讀取 $0.20／M）。

## 修訂紀錄（相對 2026-10-21 原版）

1. 截圖辨識與任何帶圖請求沒有備援鏈：原版第三節說 analyze-chat 的備援涵蓋截圖辨識，程式是 `allowModelFallback = !hasImages`，截圖辨識只打一次 Sonnet 5。
2. v3 流程不跑背景審稿：審稿只接在 v2 串流 handler，`guide_v3/stream_flow.ts` 沒有 critic。原版的「每次都審」與第五節的呼叫次數說明都要照這條修。
3. 開場救星 5.5 開關補上前提：要 `OPENER_PLAN_WRITE=true` 且 App 帶 `openerCardSet=2`；`OPENER_PLAN_WRITE` 與 `OPENER_TWO_STAGE_ENABLED` 補進開關表。
4. 練習室補上成本保險絲 `PRACTICE_COST_FUSE_DAILY_USD`：燒斷後對話輪強制 DeepSeek；補進第二節、第三節與開關表。
5. 補上「回覆微調／任務卡再調」區塊：獨立的 `refine_reply` 請求類型，非串流 Sonnet 5。
6. 問教練「沒有備援」改寫：沒有第二個模型，但驗證失敗或超過期限會回內建保守卡或剝掉建議句，只有 Claude 呼叫丟錯才回「AI 生成失敗」；審稿只跑 coachAnswer 卡。
7. 補上串流前提 `STREAM_ANALYZE_ENABLED`：沒開是整個拒絕，不是降到 Sonnet 5；白名單實際不參與判斷。
8. 小處：v3 不吃測試帳號的 forceModel；10/18「v3 上線後」那份紀錄沒有開關值，「上線」指程式併入 main；`NEW_TOPIC_TWO_STAGE_ENABLED` 不換模型；補 5.5 的呼叫參數；補鍵盤的 iOS 呼叫點與 App 端無裝置端模型套件；SHA-256 補換行的差異；`my_message` 與 `draft_with_images_analyze` 列為現行 App 不送的路徑；單價已對官方定價頁。

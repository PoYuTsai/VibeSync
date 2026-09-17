# 回覆速度優化研究（不影響回覆品質）— 2026-09-17

> 研究性文件，不含任何 runtime 變更。目的：找出 Coach 1:1、分析（analyze-chat）、Opener／New Topic、練習室四個區塊的延遲來源，並列出「模型看到的 prompt 逐位元組不變、模型輸出分布不變」前提下能做的加速項目。

## 1. 前提與分級

「完全不影響回覆品質」在這份文件裡的定義：模型收到的 prompt 文字不變、模型與取樣參數不變、驗證與 critic 守門不變、輸出經過的後處理不變。依此把每個項目分三級：

| 級別 | 定義 | 例子 |
|---|---|---|
| **A** | 純傳輸／順序／快取／背景化，模型輸入輸出位元組相同 | DB 往返並行、telemetry 改背景寫、HTTP 連線重用 |
| **B** | prompt 文字不變，但請求形狀改變（例如同一段文字從 user block 搬進 system block、拆成兩個 content block） | 需要用 eval／golden 跑一次確認等價後才能宣稱零影響 |
| **排除** | 會改變模型輸入或輸出 | 換模型、降 max_tokens、裁 prompt、砍歷史、關 critic、縮圖、改 temperature |

本文件只推薦 A 與 B；排除項一律不列為建議。

## 2. 方法與限制

- 來源：四條鏈路的程式碼逐行對照（Edge Functions 與 Flutter client），加上既有文件 `docs/plans/2026-07-22-practice-hint-latency-phase1.md`。
- **沒有 production 遙測數字**。本環境無法查 `ai_logs`、edge logs 或 RevenueCat；所有秒數是依 token 量與往返次數推估，需要 §7 的量測驗證後才能排最終優先序。
- 本環境沒有 Deno／Flutter，沒有跑任何測試。

## 3. 各區塊鏈路與延遲來源

### 3.1 Coach 1:1（`supabase/functions/coach-chat/`）

**鏈路（ledger 路徑）**

1. `auth.getUser` → 2. HMAC hash → 3. `coach_requests` 重放預查 → 4. `subscriptions` 讀＋重置 → 5. `claim_coach_request` RPC → 6. `increment_model_usage` RPC → 7. `claim_coach_request` 再 claim（續租）→ **NDJSON 標頭在這裡才送出**（`index.ts:925`）→ 8. Sonnet 5 生成（非串流、`max_tokens 1200`、無 system 欄位、無 cache_control，`generation.ts:1298-1305`）→ 9. CPU 守門 → 10. Sonnet 5 semantic critic（`max_tokens 260`、12 s）→ critic 打回或逾時就整輪重做（最多 3 輪，最壞 6 次模型呼叫）→ 11. settle：`subscriptions` 再讀一次 → `settle_coach_request` RPC → `coach.done`。

**延遲組成（推估）**

- 主生成：prompt 約 16–20K 字（`SYSTEM_PROMPT_BASE` 本身 ≈ 13.5K 字，`prompts.ts:82-161`），輸出最多 1200 tokens 的繁中 JSON。輸出時間占絕大多數，輸入 prefill 約 1 秒上下。
- critic：約 2–4 秒，串在主生成之後。
- 模型前 6 次序列 DB／auth 往返；模型後 2 次。每次往返視 Edge 與 DB 區域距離 30–200 ms。
- Client：送出前 `await _styleContext` Hive 讀；收到後 `await repo.putUnified` 加密 Hive 寫完才 `state = data`（`coach_chat_providers.dart:326` vs `:349`）。

**可做項目**

| # | 項目 | 級別 | 預估收益 | 說明 |
|---|---|---|---|---|
| C1 | 主生成加 prompt cache：`SYSTEM_PROMPT_BASE`＋固定指令段（≈13.5K 字，遠超 Sonnet 5 最低 1024 tokens）掛 `cache_control`，其餘動態段落不掛 | **B** | 每次呼叫 TTFT 減 0.5–1.5 s；第 2、3 輪重試因前綴相同直接命中；輸入成本降九成 | 目前整包 prompt 塞在單一 user message、沒有 `system`。要零文字變更，做法同 practice-chat `claude.ts:91-113`（前綴／尾巴兩個 text block、`startsWith` 保證拼回原字串）。多 block 在 API 端的渲染是否與單字串逐位元組等價，需用 `count_tokens` 兩種形狀比對＋現有 `quality_smoke_test` 跑一次確認，所以列 B 不列 A。 |
| C2 | `ai_logs`／console 之外沒有 DB telemetry，已是最佳；但 5xx 時 `Sentry.flush(1500)` 在回應前 await（`operational_error_monitor.ts:89-97`） | A | 錯誤路徑最多省 1.5 s | 只影響失敗回應，優先級低。 |
| C3 | 模型前 DB 往返：重放預查（hash＋SELECT）與 `subscriptions` 讀無資料相依，可並行；`increment_model_usage` 與續租 claim 可並行 | A | 省 2–3 次往返（約 0.1–0.4 s） | 重放命中會多讀一次 subscriptions，屬可接受。429 優先序（先 quota 再 rate-limit）維持不變。 |
| C4 | settle 的 `subscriptions` 再讀可折進 `settle_coach_request` RPC | A（但是 migration） | 省 1 次往返 | 碰 billing 高風險區、需要 migration，收益小，不建議先做。 |
| C5 | Client 收到 `coach.done` 後先發佈 state 再 await Hive 寫 | A | 幾十 ms | 07-22 練習室計畫已明文拒絕「成功 envelope 的 Hive await 移位」，Coach 同理由；不建議。 |
| C6 | critic **逾時**（非打回）目前等同失敗、整輪重生成（`generation.ts:264-271`） | 政策 | 每次 critic 逾時省一整次主生成 | 改成「同一張卡再問 critic 一次」不會改變最終能通過的卡，但屬守門政策調整，要 Eric 拍板，不算純 A。 |

**不建議**：把卡片欄位逐段串流到 client。守門與 critic 是整卡判定，先顯示再收回會傷產品感，屬產品決策。

### 3.2 分析（`supabase/functions/analyze-chat/` 串流主路徑）

**鏈路**

auth → `subscriptions` 讀（＋重置 UPDATE）→ （超額確認 hash＋claim RPC）→ `increment_model_usage` RPC → `hashConversation` → `analysis_stream_runs` INSERT → **第一個位元組**（`analysis.started`＋兩則罐頭 progress）→ Sonnet 5 串流（system ≈ 41.5K 字 v1／49.7K 字 v2，整段一個 cache block；user block 不快取；`max_tokens 4500/6000`，v2 +500）→ 模型先吐 `analysis.inventory`，但 **全部事件被扣在 pre-charge buffer**（`reframer.ts:1034-1046`）直到 `analysis.decision` 觸發 `charge_stream_analysis_run` RPC 回來 → flush → reply_option 逐張送 → 模型 `analysis.done` 被扣住 → `markDone` UPDATE → `logAiCall`（每次新建 supabase client，`logger.ts:149`）INSERT → 才送 `analysis.done`。critic shadow 已在 `waitUntil` 背景。

**延遲組成（推估）**

- 模型輸出 4500–6500 tokens 的 JSONL 是絕對大頭（數十秒），使用者已能逐張看到 reply_option，體感主要看「第一張卡多久出現」。
- 第一張卡前：auth＋2–4 次 DB 往返＋模型 prefill（system ≈ 25–30K tokens；**若 cache 未命中**，prefill 可能多 1–3 秒）＋inventory/decision 生成＋charge RPC 一次往返。
- done 前：2 次序列 DB 寫。

**關鍵發現：v2 的 cache key 含每次不同的情境 atoms**

Client 送 `analysisContractVersion = 2`（`analyze_stream_client.dart:484`），server 在 v2 把本次挑選的 knowledge atoms 渲染進 system prompt 中段（`stream_prompt.ts:129-135`，介於 34.5K 字 base 與 7–14K 字 streaming contract 之間），而整段 system 只有一個 `cache_control` block（`streaming_fallback.ts:78-86`）。Anthropic cache 是 breakpoint 處整段前綴的雜湊比對，所以 **只要兩次請求選到的 atoms 不同，整個 ~30K tokens 的 system 就 cache miss**。atoms 由 regex 訊號挑選，每段對話不同的機率很高。此外 free（2 種 style）與 paid（5 種 style）的 style 清單也在 system 內，本來就是兩個 cache 命名空間，這是既有設計。

| # | 項目 | 級別 | 預估收益 | 說明 |
|---|---|---|---|---|
| S1 | 先用 `ai_logs.response_body.cacheReadTokens`／`cacheCreationTokens`（`analyze_stream_handler.ts:679-684` 已記）統計近 14 天 v2 請求命中率 | 量測 | 決定 S2 值不值得 | 零風險，先做。 |
| S2 | system 拆兩個 block：`[SYSTEM_PROMPT base（cache_control）] + [Situation Knowledge + Streaming Contract]`，文字拼回完全相同 | **B** | 命中時 prefill 省約 1–3 s（第一張卡提早）；輸入成本大降 | 與 C1 同一個「多 block 渲染等價」待驗證問題。`baseline_contract_test` 鎖的是字串 hash，不鎖 request body 形狀，需補一個 body 形狀測試。 |
| S3 | `analysis.done` 前的 `logAiCall` 改走 `waitUntil`（critic shadow 已是這個範式）；`logAiCall` 改用 handler 既有 client | A | done 提早 0.1–0.4 s | 失敗時 done 仍要等 `markDone` 成功，只把 telemetry 搬走。 |
| S4 | `hashConversation`（CPU）與 `createPendingRun` INSERT、`selectAnalyzeSocialKnowledge`（純 CPU）可並行／前移 | A | 幾十 ms | 小。 |
| S5 | pre-charge buffer 把 inventory 扣到 charge RPC 回來 | 設計 | 約一次往返 | 這是「先扣費再顯示」的計費正確性設計，不建議動。 |
| S6 | JSON-repair 重試把 `IMPORTANT: Return valid JSON only` **附加在 system prompt 末端**（`analyze_chat_handler.ts:1846-1870`），該次一定 cache miss | B | 只影響罕見重試路徑 | 搬到 user block 會改變模型看到的位置，列 B、低優先。 |

**OCR（recognizeOnly）**：system 只有 555 字有快取，≈20K 字的辨識規則全在 user block 不快取（`ocr_recognition_prompt.ts:219-253`）。把規則搬進 system 會改變 prompt 位置（B），且 OCR 依 AGENTS.md 須隔離，這裡只記錄不建議。真正的 OCR 大頭在 vision 輸入（每張最多 900 KB、不縮圖），縮圖屬排除項。

**optimize／refine**：`subscriptions` 同一列最多讀 3 次（`subscription_access.ts:33`、`optimize_refine_flow.ts:225`、`:495`）；`optimize_message_requests` 與 `refine_free_allowance` 兩次讀無相依可並行（A，省一次往返）。輸出只有 700 tokens，總時間短，優先級低。

### 3.3 Opener／New Topic（`analyze-chat` 的 opener／new_topic 模式）

**鏈路（opener）**：prologue → hash → `opener_request_charges` 重放預查（fail-open）→ `increment_model_usage` RPC → Sonnet 5（system 14.7K 字有快取；`max_tokens 3000`；60 s）→ 最多一次 repair 呼叫 → `chargeOpenerQuota` RPC → 回應。stream 模式只是 transport：全文先累積完（`opener_handler.ts:925-929`），只送 marker progress，最後一個 `opener.done`。

**鏈路（new_topic）**：預查 SELECT → claim RPC → `increment_model_usage` RPC → **同一個 claim RPC 再呼叫一次**（續租）→ Sonnet 5（system 4.4K 字）→ 可能 repair → settle RPC。模型前四次序列 DB 往返。

**延遲組成**：輸出最多 3000 tokens 的五種風格 JSON，生成時間（推估 15–30 s）是絕對大頭；DB 往返合計不到 1 s。

| # | 項目 | 級別 | 預估收益 | 說明 |
|---|---|---|---|---|
| O1 | opener 預查 SELECT 與 rate-limit RPC 並行；new_topic 首次 claim 與 rate-limit 並行 | A | 0.1–0.3 s | 預查本就是 advisory／fail-open。 |
| O2 | Client 送出前 `RevenueCatService.getCustomerInfo()` 與 `styleContextProvider.future` 改並行（`opening_rescue_screen.dart:600, 621`；`new_topic_view.dart:263, 215`） | A | 0.1–1 s（RevenueCat 平台通道視快取狀態） | 純 client 順序。 |
| O3 | opener 4.4K／14.7K 字 system 已有 cache block；opener 流量稀疏，5 分鐘 TTL 常冷 | 量測 | — | 先看 cache read 命中率再決定；1h TTL 寫入是 2 倍價，不建議預先切。 |
| O4 | 五種風格逐張串流顯示 | 產品決策 | 體感大幅提早 | 目前 wrong-surface／完整性／repair 都是整包判定，逐張顯示需逐張守門，可能出現顯示後收回。不列為本題建議。 |

### 3.4 練習室（`supabase/functions/practice-chat/`）

**鏈路（chat 一輪）**

auth → `prepare_practice_subscription_usage` RPC → `practice_chat_sessions` SELECT → `practice_relationship_threads` SELECT → `increment_model_usage` RPC → `assert_practice_learning_ready` RPC → `list_practice_moment_posts` RPC（1.5 s 上限）→ cost-fuse SELECT（旗標開才有）→ Haiku 4.5 或 DeepSeek v4-flash（`max_tokens 200`、非串流、30 s）→ 守門（失敗最多再生成一次）→ cost-fuse RPC → `commit_practice_chat_turn` RPC → **assisted**：DeepSeek 學習狀態分類器（`max_tokens 450`、30 s）＋ `update_practice_learning_state` RPC（CAS 失敗再一次）→ game／thread RPC → **standard 且旗標開**：DeepSeek agency 分類器（30 s）→ thread upsert → 回應。**全程無串流**，第一個位元組等於最後一個。

**延遲組成（推估）**

- 模型前 7 次序列 DB 往返（約 0.3–1 s）。
- 主生成只有 200 tokens，大約 1–3 s。
- **回覆已經定案之後**還要跑 1 次 DeepSeek 分類器（推估 1–3 s，最壞 30 s）＋2–4 次 RPC，使用者才看得到泡泡。standard 模式分類器的結果完全不進 response body（`handler.ts:5407-5445`，註解明講是為了讓同一行 log 帶欄位才同步跑）；assisted 模式分類器結果會進 body（`temperature`、`partnerState`、`hintUsedCount`）。
- Prompt cache：chat 已拆 `systemStable` 前綴，但 Haiku 4.5 最低可快取 4096 tokens、前綴約 2400，**永遠不命中**（`prompt_test.ts:3320-3326` 已註明）；DeepSeek 有自動前綴快取但 `systemTurn` 開頭是每輪不同的 406 字時間錨點，歷史訊息排在它後面，前綴快取只能吃到 `systemStable`。

| # | 項目 | 級別 | 預估收益 | 說明 |
|---|---|---|---|---|
| P1 | standard 模式的 agency 分類器與 thread upsert 改 `waitUntil` 背景；`practice_chat_succeeded` 的分類器欄位改在背景 task 內補記一筆 log | **A** | 每輪泡泡提早 1–3 s（最壞 30 s） | 回覆文字與 body 逐位元組不變；只是 log 拆成兩筆或延後。既有 `waitUntil` 慣例已用於 ai_logs／moments 生圖。 |
| P2 | assisted 模式：學習狀態分類器結果進 body，無法純背景化 | B（契約） | 同上 | 若改成「先回泡泡、temperature 等欄位由下一輪或補打帶回」屬 API 契約變更，要 Eric 決定。 |
| P3 | 模型前 DB 往返並行：`prepare_practice_subscription_usage` ∥ sessions SELECT ∥ threads SELECT；`assert_practice_learning_ready` ∥ moments RPC ∥ cost-fuse SELECT（rate-limit 仍排在 quota 判定之後） | A | 省 4–5 次往返（0.2–0.6 s） | 429 優先序不變。 |
| P4 | `flushAnthropicSpend` RPC 與 `commit_practice_chat_turn` RPC 並行；game state RPC 與 thread upsert 並行 | A | 省 2 次往返 | 不同資料表、無相依。 |
| P5 | DeepSeek `usage.prompt_cache_hit_tokens` 目前沒記；補進 telemetry | 量測 | 決定 07-22 計畫 2.1 要不要做 | 零風險。 |
| P6 | 把 `systemTurn` 的時間錨點移到 prompt 尾端以讓 DeepSeek 前綴快取吃到歷史訊息 | 排除 | — | 會改變 prompt 順序，明確不做。 |

**Hint**：prefetch 已存在（07-22 量測命中 ~67%）。冷路徑是 Sonnet 5 → Haiku 序列單發（500 tokens、15 s／發、35 s 死線）。hint 的 system 只依 mode／stage floor／旗標變化（`hint.ts:1726-1764`），每個變體都穩定且長度應超過 Sonnet 5 的 1024 tokens，理論上會命中 cache，但 `single_shot.ts` 沒傳 `systemCachePrefix`，整段 system 掛一個 block 也可以，**需要用 ai_logs 的 cache read 欄位確認確實在命中**。若命中率是 0，先查是不是某段字串每次都不同。Hint 路徑的 DB 往返（預查 SELECT → claim RPC → settle/discard 分支 RPC）是設計上的冪等帳本，不建議動。

**Debrief**：`hydrateAppliedHintDecisions` 對每個套用過 hint 的回合序列打一次 `resolve_practice_hint_decision` RPC（`handler.ts:2130-2155`），可改 `Promise.all`（A，省 N-1 次往返）。回應前 `updateThreadMemorySummaryFailOpen` 可背景化（A）。

## 4. 跨區塊

### 4.1 Flutter client

| # | 項目 | 級別 | 預估收益 |
|---|---|---|---|
| F1 | 每次請求都 `http.Client()` 新建再 `close()`（analyze、coach、opener、new_topic、auxiliary 五處），每次付一次 TCP＋TLS 握手 | A | 行動網路每次請求 0.1–0.4 s |
| F2 | 付費用戶一次分析最多 3 次 RevenueCat `getCustomerInfo`＋最多 2 次 `sync-subscription`（`subscription_providers.dart:2056-2117`、`analysis_transport_support.dart:40-50`），全部串在請求前，fence 20 s | A（去重）／B（是否仍阻塞） | 去重同一 tap 內的 CustomerInfo 是純 A；要不要讓 sync 不阻塞分析屬計費決策 |
| F3 | 截圖流程：preflight 與壓縮各 decode 一次、最多 6 次序列壓縮、sha256 算兩次，全部在主 isolate（`image_compress_service.dart:9-59`、`ocr_recognition_cache_service.dart:53-62`） | A | 每張 0.5–2 s 且期間 UI 卡頓；搬到 isolate、decode 一次共用、hash 算一次即可，輸出位元組不變 |
| F4 | 主串流分析路徑沒有任何 latency telemetry（只有 auxiliary client 有 `AnalysisTelemetry`） | 量測 | 見 §7 |

### 4.2 Edge 共通

- 所有 Claude 呼叫都已 `thinking: disabled`（Sonnet 5）；沒有可再省的推理 token。
- `logAiCall` 每次 `createClient`（`logger.ts:149`）：CPU 成本小，但順手改用既有 client。
- 沒有任何 Edge 預熱（client 端 grep 不到 warm-up）。Supabase Edge 冷啟動由平台決定，`npm:opencc-js`、`npm:@sentry/deno` 是模組載入成本；無法從程式碼估冷啟比例，需看 edge logs 的 boot time。

## 5. 建議優先序（待 §7 量測修正）

1. **P1 練習室 standard 分類器背景化**：純 A、改動集中在 `handler.ts:5407-5505`、每輪都受益，是最大且最安全的一項。
2. **S1→S2 分析 v2 cache 拆 block**：先量命中率；若確認 atoms 造成大量 miss，拆 block 讓第一張卡提早 1–3 s。B 級，需驗證多 block 渲染等價。
3. **C1 Coach prompt cache**：同樣 B 級，同一個驗證方法可以一起做；重試輪直接受益。
4. **F1 HTTP client 重用、F3 圖片處理搬 isolate、F2 RevenueCat 去重**：純 client、純 A。
5. **P3／P4／C3／O1 DB 往返並行**：A 級但每項只省零點幾秒，作為一批小 PR。
6. **S3 done 前 telemetry 背景化、debrief RPC 並行**：小而安全。

## 6. 明確不做（違反「不影響品質」）

換模型或路由更多流量到 Haiku、降 `max_tokens`、裁 system prompt 或 few-shot、縮短歷史視窗、關掉或放寬 critic／守門、圖片縮圖或降畫質、改 temperature、改 prompt 段落順序（含 P6）、把整卡驗證改成逐段顯示。

## 7. 先量測什麼

沒有數字就無法排真正的優先序。建議先補這些（全部是 telemetry，零品質風險）：

1. 各 Edge Function 的分段時間戳（auth 完成、DB 預查完成、模型第一 token、模型結束、settle 完成），記進既有 console log；Coach 與 practice 已有 `latencyMs` 但只有總時間。
2. `ai_logs` 已有的 `cacheReadTokens`／`cacheCreationTokens` 對 analyze v2、opener、hint 各算一次命中率。
3. practice-chat 補記 DeepSeek `prompt_cache_hit_tokens`，以及分類器單獨耗時（`standardClassifierDurationMs` 已有，assisted 側補齊）。
4. Flutter 主串流路徑補 `roundTripDuration`／第一張卡時間，對齊 auxiliary client 的 `AnalysisTelemetry`。
5. Edge logs 看冷啟動占比（boot time）。

## 8. 待驗證的假設

- 多個 text block 在 Anthropic API 端的渲染是否與單一字串逐位元組等價（影響 C1／S2 能否升級為 A）。practice-chat 已依此假設上線並經 Codex 審過，但沒有留下 API 端的等價證據。
- 各 DB 往返實際毫秒數（決定並行類項目的真實收益）。
- DeepSeek 分類器實際耗時分布（決定 P1 收益大小）。

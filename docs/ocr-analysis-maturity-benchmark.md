# OCR / 分析成熟度 Benchmark

最後更新：2026-03-23

## 目的

這份文件用來判斷 VibeSync 的核心引擎是否已從「可用」提升到「成熟可送審」。
重點不是單次測得過，而是：

- 正常聊天截圖是否穩定
- 邊界情況是否可控
- 失敗時是否有成熟的 UX 與補救路徑
- 延遲、成本、負載是否可接受

## 成熟度分級

### L1 可用

- 正常雙人聊天截圖大多可識別
- OCR 後可匯入對話
- 基本分析可完成
- 主要 auth / 訂閱 / restore 可用

### L2 穩定

- 左右方判斷大多穩定
- 社群圖 / 錯圖 / 群組圖不容易污染現有對話
- OCR 失敗時會給出可理解的人話提示
- 用戶可在匯入前修正 `我說 / 她說` 與訊息內容

### L3 成熟

- 引用回覆、圖片泡泡、長截圖、多圖順序等邊界都可控
- OCR 與分析延遲有穩定觀測指標
- 重要錯誤不會直接露出技術術語
- 失敗時可重試、另存新對話、稍後再匯入，不會整段重來

### L4 可送審

- TestFlight 固定回歸情境已穩定
- 重要業務邏輯、訂閱權限、刪帳、legal 一致性已核對
- 核心路徑 crash / blocker 接近 0
- 有明確 benchmark 判斷是否能上線

## 上線前最低門檻

### 1. OCR 識別

- 正常雙人聊天截圖 first-pass 匯入成功率：`>= 95%`
- 左右方判斷正確率：`>= 98%`
- LINE 引用回覆不被誤拆成獨立新訊息：`>= 95%`
- 錯圖誤放行率：`<= 3%`
- 混不同人 / 不同 thread 偵測率：`>= 90%`

### 2. 分析品質

- 至少有一則對方訊息時，一般分析應穩定可跑
- 最後一則是我說時，仍能以前一則她的回覆正常分析
- 引用回覆存在時，不應破壞整體對話順序
- OCR 可讀的引用內容應保留為上下文，而不是污染 message list

### 3. 效能

- 單張普通聊天截圖 OCR：`p50 < 4 秒`，`p95 < 7 秒`
- 單張長圖 OCR：`p95 < 10 秒`
- 2-3 張連續截圖 OCR：`p95 < 15 秒`
- 純文字分析：`p95 < 4 秒`
- OCR 匯入後再分析整體體感：`p95 < 12 秒`

### 4. 穩定度

- OCR 成功率：`>= 97%`
- 分析成功率：`>= 98%`
- timeout rate：`<= 2%`
- 錯 thread 污染目前對話的嚴重案例：`0`
- TestFlight blocker：`0`

### 5. UX 成熟度

- 不顯示 raw exception / OCR / payload / upstream error 給用戶
- 任一主要失敗情境都要有下一步：
  - 重截
  - 另存新對話
  - 稍後再匯入
  - 手動修正
- 取消或返回不應讓已完成的 OCR 結果消失

### 6. 安全與資料保護

- 過大 request / malformed image request 會被擋下
- log 不記原始對話全文、圖片內容、email 明碼
- 非聊天圖、敏感圖、錯誤 UI 畫面不應被當成正常聊天匯入

## 目前已可觀測指標

### App / OCR 畫面可見

- 原始大小
- 壓縮後大小
- request payload 大小
- 本機準備時間
- round-trip
- AI latency
- recognized classification
- recognized side confidence
- uncertain side count
- 引用回覆併回次數
- speaker continuity 校正次數
- 群組校正次數（圖片泡泡 / 同側短回覆修正）
- 一般分析 request size / round-trip / retries / fallback / context trim
- benchmark guardrails：
  - `OCR 偏慢`
  - `分析偏慢`
  - `方向待確認`
  - `非標準截圖`
  - `上下文已壓縮`
  - `接近逾時`
  - `服務不穩定`

## App 內警戒值（目前實作）

- 單張 OCR 往返超過 `7 秒` → `OCR 偏慢`
- 多張 OCR 往返超過 `15 秒` → `OCR 偏慢`
- 一般分析往返超過 `12 秒` → `分析偏慢`
- `我說分析 / 訊息優化` 超過 `6 秒` → `分析偏慢`
- OCR 請求大於約 `700KB` → `請求偏大`
- `uncertainSideCount > 0` 或 `sideConfidence = low` → `方向待確認`
- `recognizedClassification != valid_chat` → `非標準截圖`
- `truncatedMessageCount > 0` 或 `conversationSummaryUsed = true` → `上下文已壓縮`
- round-trip 超過 timeout 上限的 `80%` → `接近逾時`
- `retryCount > 0` 或 `fallbackUsed = true` → `服務不穩定`

### Server telemetry 已回傳

- `requestType`
- `imageCount`
- `totalImageBytes`
- `serverAiLatencyMs`
- `fallbackUsed`
- `retries`
- `contextMode`
- `inputMessageCount`
- `compiledMessageCount`
- `truncatedMessageCount`
- `openingMessagesUsed`
- `recentMessagesUsed`
- `conversationSummaryUsed`
- `recognizedClassification`
- `recognizedConfidence`
- `recognizedSideConfidence`
- `recognizedMessageCount`
- `uncertainSideCount`
- `continuityAdjustedCount`
- `groupedAdjustedCount`
- `quotedPreviewRemovedCount`
- `quotedPreviewAttachedCount`
- `overlapRemovedCount`
- `guardrailSeverity`
- `guardrailCount`
- `guardrailFlags`
- `totalTokens`

## 後端 guardrail 旗標（目前實作）

- `slow_request`
- `near_timeout`
- `unstable_upstream`
- `heavy_image_payload`
- `compressed_context`
- `nonstandard_screenshot`
- `uncertain_speaker_side`
- `structure_repaired`
- `high_token_usage`
- `safety_filtered`

## 目前最該關注的 5 種高風險情境

1. LINE 引用回覆
   - 她引用我
   - 我引用她
   - 自己回自己

2. 圖片泡泡混短文字
   - 同側圖片 + 同側短訊息
   - 圖中圖內容不能反轉 speaker

3. 長截圖 / 裁切不完整
   - 標題列不完整
   - 只拍到部分 bubble
   - 只剩截斷引用預覽

4. 錯圖 / 噪音圖
   - 社群留言
   - 群組聊天
   - 相簿 / 系統畫面
   - 通話紀錄頁

5. 混 thread
   - 不同對象截圖混上傳
   - 舊對話插入目前 thread

## 建議停損判斷

可以先停手 build TestFlight 的最低條件：

- auth / 訂閱 / restore / OCR / 分析沒有新的 P1
- 正常聊天圖、錯圖、LINE 引用圖、長繁中圖都已至少各跑一輪
- 沒有 raw error 直接露給用戶
- 目前已知問題都屬於精細度優化，不是核心流程斷裂

可以準備送審的最低條件：

- 上述 TestFlight 條件穩定成立
- legal / support / privacy disclosure 全部一致
- 固定回歸情境沒有新的 blocker
- 夥伴測試回報只剩微調，不再是業務邏輯錯誤

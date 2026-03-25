# OCR / 分析成熟度 Benchmark

最後更新：2026-03-24

這份文件用來定義 VibeSync 目前最核心能力的成熟度門檻：
- 截圖識別
- 對話結構判讀
- 上下文分析
- 速度 / 成本 / 穩定度
- 正式上線前的 go / no-go 標準

## 1. 成熟度分級

### Level A：可用
- 一般雙人聊天截圖能成功識別並匯入
- 左右方判斷大多正確
- 用戶看不到 raw error / exception / OCR 技術術語
- 失敗時有基本下一步：重試、重截、另存新對話

### Level B：穩定
- LINE 引用回覆、圖片泡泡、長截圖、多圖順序等邊界都可控
- 低信心與錯圖不會默默污染目前對話
- OCR 結果可手動修正，且修正成本低
- 有 telemetry 能看出慢在哪、錯在哪、扣不扣點

### Level C：可送審
- TestFlight 固定回歸情境穩定
- OCR / 分析 / 訂閱 / auth 沒有新的 P1
- 法務頁、支援信箱、App Store disclosure 與真實資料流一致
- 有明確 benchmark 判斷是否能上線

## 2. OCR 精準率目標

- 左右 speaker 判斷正確率：`>= 98%`
- 可見訊息抽取召回率：`>= 95%`
- 名字辨識正確率：`>= 90%`
- LINE 引用回覆不被拆成獨立新訊息：`>= 95%`
- 圖片泡泡 / placeholder speaker 判斷正確率：`>= 95%`
- 錯圖誤放行率：`<= 3%`
- 混不同人 / 不同 thread 偵測率：`>= 90%`

## 3. OCR 結構規則

### 必須成立
- 外層 bubble side 優先於語意
- 左側基本上是對方，右側基本上是我方
- 引用卡作者不能覆蓋外層 bubble speaker
- 圖中圖內容不能覆蓋外層 bubble speaker
- LINE 公告 / 置頂跳轉 / 系統提示不能變成新訊息

### 目前允許的降級
- 引用預覽太淡、太小、被截斷時：
  - 可以只保留 `quotedReplyPreview` 的部分內容
  - 不能因此誤拆成獨立訊息
- 多張截圖有輕微重疊時：
  - 可以啟用 sequential overlap dedupe
  - 不能保留明顯重複 bubble 兩次

## 4. 分析品質目標

- 分析以「目前對話窗可見上下文 + 歷史摘要 + session context」為主
- 若引用內容可讀，應作為 `quotedReplyPreview` context，而不是污染 message list
- 最後一則是我時，分析仍要以前一則對方回覆為 anchor
- 只有我說、沒有任何對方訊息時，不跑一般分析
- 分析結果不能因為錯圖 / 社群圖 / 群組圖而產生假精準建議

## 5. 延遲目標

- 單張一般聊天截圖 OCR：`p50 < 4s`、`p95 < 7s`
- 單張長圖 OCR：`p95 < 10s`
- 2-3 張連續截圖 OCR：`p95 < 15s`
- 純文字分析：`p95 < 4s`
- OCR 匯入後再分析整體體感：`p95 < 12s`

## 6. 穩定度目標

- OCR 成功率：`>= 97%`
- 分析成功率：`>= 98%`
- timeout rate：`<= 2%`
- 同圖快取命中後，不應再重新上傳同批圖片
- 中途取消或稍後匯入後，不應遺失已完成的 OCR 結果
- TestFlight crash-free：`>= 99.5%`

## 7. 使用者體驗門檻

- 用戶不應看到：
  - `OCR error`
  - `payload too large`
  - raw stack trace / raw exception
- 任一失敗情境都要有明確 CTA：
  - 重截
  - 重新識別
  - 另存成新對話
  - 先檢查我說 / 她說
  - 稍後再試
  - 重新登入
- OCR 錯了時，1-2 個動作內能補救
- 不應因為關掉 dialog 就丟失整批 OCR 結果

## 8. 計費與額度 Guardrails

### recognize_only
- `shouldChargeQuota = false`
- `chargedMessageCount = 0`
- `quotaReason = recognize_only_free`

### test account 的完整分析
- `shouldChargeQuota = false`
- `chargedMessageCount = 0`
- `estimatedMessageCount > 0` 只代表估算值，不代表真的扣點

### 正常完整分析
- `shouldChargeQuota = true`
- `chargedMessageCount = estimatedMessageCount`
- `quotaReason` 應對應：
  - `analyze_message_based`
  - `analyze_with_images_message_based`
  - `my_message_message_based`
  - `optimize_message_message_based`

### 前後端必須能回答
- 這次是純識別還是完整分析
- 這次有沒有真的扣額度
- 如果沒扣，是純識別免費還是測試白名單豁免
- 如果有扣，扣的是幾則訊息額度

## 9. Telemetry 必看欄位

### App 端
- `requestType`
- `imageCount`
- `requestBodyBytes`
- `payloadPreparationDuration`
- `roundTripDuration`
- `edgeAiDuration`
- `recognizedClassification`
- `recognizedSideConfidence`
- `uncertainSideCount`
- `continuityAdjustedCount`
- `groupedAdjustedCount`
- `layoutFirstAdjustedCount`
- `quotedPreviewRemovedCount`
- `quotedPreviewAttachedCount`
- `overlapRemovedCount`
- `shouldChargeQuota`
- `chargedMessageCount`
- `estimatedMessageCount`
- `quotaReason`

### 後端 ai_logs
- `requestType`
- `quotaReason`
- `chargedMessageCount`
- `estimatedMessageCount`
- `guardrailSeverity`
- `guardrailCount`
- `guardrailFlags`
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

## 10. 固定高風險情境

每一輪至少要覆蓋：
- 她引用我
- 我引用她
- 我引用我自己
- 對方引用自己更早的訊息
- 圖片泡泡 + 同側短文字
- 多張截圖有重疊
- 長繁中截圖
- 社群貼文 / 留言串
- 群組聊天
- 不同人的截圖混入同一批

## 11. 可 build TestFlight 的最低門檻

- auth / 訂閱 / restore / OCR / 分析沒有新的 P1
- 正常聊天圖、錯圖、LINE 引用圖、長繁中圖都至少各跑過一輪
- 沒有 raw error 直接漏給用戶
- OCR telemetry 與分析 telemetry 能指出慢點、結構修正、扣點狀態

## 12. 可送審的最低門檻

- 上述 TestFlight 條件穩定成立
- 法務、support email、App Store privacy disclosure 一致
- 夥伴測試沒有新的審核 blocker
- 近期 telemetry 沒有明顯惡化：
  - timeout rate
  - OCR success rate
  - false reject rate
  - slow_request / near_timeout 比例

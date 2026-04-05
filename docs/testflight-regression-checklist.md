# TestFlight 回歸與簽核清單

最後更新：2026-03-24
適用版本：v41 之後

目的：
- 每次新的 TestFlight build 出來後，用同一份清單驗證核心流程
- 避免只看 CI 綠燈就誤判可發版

## 0. 開始前

- [ ] 安裝最新 TestFlight build
- [ ] 準備 2 個帳號：
  - 付費或可升級帳號
  - 一般帳號或免費帳號
- [ ] 準備至少 4 類截圖：
  - 正常雙人聊天
  - LINE 引用回覆
  - 長繁中截圖
  - 明顯錯圖 / 社群圖

## A. 登入 / 註冊

- [ ] Apple Sign In 成功
- [ ] Google Sign In 成功
- [ ] Email sign up + verify 成功
- [ ] Resend verification 成功
- [ ] Forgot password warm start 成功
- [ ] Forgot password cold start 成功
- [ ] 登出後重新登入，不殘留前一個 session

## B. 訂閱 / Paywall

- [ ] Paywall 文案正常，沒有 mojibake
- [ ] Privacy / Terms 可正常開啟
- [ ] Starter 購買成功
- [ ] Essential 購買成功
- [ ] Restore Purchases 成功
- [ ] 升級後回分析頁，不會停留在舊 free-tier 結果

## C. OCR 識別

### C1 正常案例
- [ ] 單張正常雙人聊天截圖成功
- [ ] 2-3 張連續截圖成功
- [ ] 長繁中截圖成功

### C2 Speaker / 結構
- [ ] 左側基本上是她，右側基本上是我
- [ ] 圖片泡泡 speaker 不會亂翻
- [ ] 多張截圖有重疊時，不會重複匯入同一則

### C3 LINE 引用回覆
- [ ] 她引用我後回覆
- [ ] 我引用她後回覆
- [ ] 我引用我自己
- [ ] 引用卡不會被拆成新訊息
- [ ] 若引用內容可讀，會保留為 `quotedReplyPreview`

### C4 錯圖 / 混圖
- [ ] 社群圖被拒絕
- [ ] 群組圖被拒絕
- [ ] 不同人的截圖混入同一批時，會警告並偏向另存新對話
- [ ] 非聊天圖不會默默 append 到目前對話

## D. 匯入 / 對話邏輯

- [ ] 可選 `加入目前對話`
- [ ] 可選 `另存成新對話`
- [ ] OCR dialog 取消後，結果仍可稍後再匯入
- [ ] 新建對話時，辨識到的名字會正確取代 placeholder 標題
- [ ] 既有對話追加截圖後，順序與上下文合理

## E. 分析

- [ ] 一般分析成功
- [ ] `我有想說的，幫我優化` 成功
- [ ] `對話延續 / 我說` 成功
- [ ] 分析後重開同一段對話，舊分析仍可看到
- [ ] 補新訊息後，能再重新分析

## F. 額度 / 計費

- [ ] 純 OCR 識別顯示 `本次純識別，不扣額度`
- [ ] 完整分析前預覽顯示按訊息數扣點
- [ ] 完整分析後量測卡可看出這次有沒有真的扣點
- [ ] 測試白名單帳號顯示 `未扣額度（原本會扣 X 則）`
- [ ] 一般帳號完整分析後，remaining quota 正確更新

## G. Telemetry / Guardrails

至少手動記錄 3 組：
- [ ] 正常單圖
- [ ] LINE 引用圖
- [ ] 長圖或 2-3 張連續截圖

每組至少記：
- classification
- side confidence
- uncertain side count
- quoted preview attach/remove count
- overlap removed count
- payload
- round-trip
- AI latency
- 是否扣額度 / 扣幾則

## H. 可簽核條件

- [ ] A 全過
- [ ] B 全過
- [ ] C1 / C2 全過
- [ ] C3 至少過 2 種
- [ ] D 全過
- [ ] E 全過
- [ ] F 全過
- [ ] G 至少記滿 3 組量測

如果 C3 / C4 失敗，記錄以下 5 件再回報：
1. 原始截圖情境
2. 哪一則 speaker 判錯
3. 是否誤拆引用卡 / 誤放行錯圖
4. warning / confidence 文案是什麼
5. telemetry 數字

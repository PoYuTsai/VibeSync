# TestFlight 回歸與簽核清單

最後更新：2026-04-24
適用範圍：送審前所有 TestFlight build

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
- [ ] 月繳 / 季繳標示正確，當前方案不會把同 tier 其他週期誤判成「目前方案」
- [ ] Privacy / Terms 可正常開啟
- [ ] Starter 購買成功
- [ ] Essential 購買成功
- [ ] `恢復購買` 成功
- [ ] `管理訂閱` 可正常跳 App Store 管理頁
- [ ] `Starter -> Essential` 升級後立即刷新成高 tier 權限
- [ ] `Essential -> Starter` 會顯示已排程降級，當期額度仍維持 Essential
- [ ] 去 App Store 取消降級後，回 App 點 `我已取消降級，更新狀態` 會清掉 pending 狀態
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
## I. Partner Entity A2 soak

- [ ] Home 第一個 tab 顯示 Partner list，而不是舊 Conversation list。
- [ ] 從 Home FAB 建立新對象後，進入該對象 detail；按返回應回到 Partner list，不應回到新增對象表單。
- [ ] 從 Partner detail 點「新增對話」→ 手動輸入，建立後該 conversation 的 `partnerId` 應掛在當前對象，回到 detail 後會出現在該對象的對話列表。
- [ ] 從 Partner detail 點「新增對話」→ 截圖開始，建立的新 conversation 也應掛在當前對象。
- [ ] Partner detail radar 在沒有分析資料時顯示 fallback，不應 crash；有分析資料時顯示 5 維 radar。
- [ ] Partner detail 的 merge / edit / delete 選單項目前為 disabled，不可誤觸。

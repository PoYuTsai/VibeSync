# TestFlight 回歸與簽核清單

**目的**：每次產出新的 TestFlight build 後，用這份清單快速驗證登入、訂閱、OCR、對話邏輯與刪帳流程，避免只看 CI 綠燈就誤判可發版。  
**建議節奏**：先跑 A / B 的核心流程，再驗 C / D 的高風險邊界，最後補 E / F 完成簽核。  
**適用版本**：v41 之後的 iOS TestFlight build。

## 使用方式

1. 安裝最新 TestFlight build。
2. 使用至少 2 個帳號測試：
   - 主測帳號：一般使用者
   - 次測帳號：不同 tier 或新註冊帳號
3. 每個項目記錄：
   - 是否通過
   - 是否有 warning / 文案不一致
   - 是否需要補截圖或 log
4. 只要 A / B / C 任一項有阻斷性失敗，本版先不要往外擴散測試。

## A. 登入與帳號恢復

- [ ] Apple Sign In 可成功登入，回到首頁後 session 正常。
- [ ] Google Sign In 可成功登入，callback 不會卡住或回到空白頁。
- [ ] Email 註冊後可收到驗證信，驗證完成後可登入。
- [ ] `Resend verification` 可再次寄出驗證信。
- [ ] Forgot password 熱啟動流程正常：
  點信內 recovery link 時，app 已開啟也能進入重設密碼。
- [ ] Forgot password 冷啟動流程正常：
  完全關閉 app 後，點 recovery link 仍能回到 `/login` 完成重設。
- [ ] 登出後重新登入不同帳號，首頁 / paywall / settings 的 tier 不會殘留上一個帳號。
- [ ] Session 失效或手動登出時，router 會正確回到登入頁。

## B. 訂閱與 Paywall

- [ ] Paywall 顯示 clean 繁中文案，沒有 mojibake。
- [ ] `使用條款` 可正確開啟 [https://vibesyncai.app/terms](https://vibesyncai.app/terms)。
- [ ] `隱私權政策` 可正確開啟 [https://vibesyncai.app/privacy](https://vibesyncai.app/privacy)。
- [ ] Starter 方案可載入價格並完成 Sandbox 購買。
- [ ] Essential 方案可載入價格並完成 Sandbox 購買。
- [ ] 購買成功後只顯示正式成功提示，不會跳出 RevenueCat raw debug 資訊。
- [ ] 購買後 tier 會同步到首頁 / settings / 功能權限。
- [ ] Restore Purchases 可成功恢復有效訂閱。
- [ ] RevenueCat 無有效 entitlement 時，restore 不會把本地 tier 卡在舊的付費狀態。

## C. OCR 匯入與截圖邊界

### C1 正常流程

- [ ] 1 張正常聊天截圖可成功辨識並匯入。
- [ ] 2-3 張連續聊天截圖可維持正確順序。
- [ ] 匯入後可直接進到分析流程，不會卡住在 OCR 階段。

### C2 匯入模式

- [ ] 正常同一段續聊時，可選 `加入目前對話`。
- [ ] 名字不一致或低信心時，預設偏向 `另存成新對話`。
- [ ] 取消匯入時，不會殘留舊 preview、warning 或晚到的 OCR 結果。

### C3 LINE / 繁中 / 長圖

- [ ] LINE 的「回覆某則訊息」截圖，不會把引用預覽誤拆成新訊息。
- [ ] 長篇繁體中文截圖辨識後，原文不會被過度亂猜；看不清楚時應轉成較低信心而非亂補字。
- [ ] 高密度長圖仍可辨識出左右方向與基本訊息順序。

### C4 錯圖與不支援內容

- [ ] 社群貼文、留言串、非雙人聊天圖，會被擋下或明確警告，不會直接匯入目前對話。
- [ ] 模糊、裁切過度、缺少上下文的截圖，會顯示低信心提示並建議重截。
- [ ] 另一個人的聊天截圖匯入現有 thread 時，會出現 mismatch warning。

## D. 對話邏輯與分析持久化

- [ ] 手動輸入最後一則是她時，可正常分析。
- [ ] 手動輸入最後一則是我時，也能以前一則她的回覆為分析基準。
- [ ] 只有我說、她還沒回時，會存成草稿而不是假裝可做一般分析。
- [ ] 分析完成後退出再重開，上一輪分析結果仍會保留。
- [ ] 重開後補新訊息，會正確提示「有新訊息可重新分析」。

## E. 帳號管理與隱私

- [ ] 設定頁文案 clean，沒有 mojibake。
- [ ] `刪除帳號` 必須輸入 `DELETE` 才能送出。
- [ ] 完成刪帳後 app 會回到登入頁。
- [ ] 已刪除帳號不能直接重新登入，必須重新註冊。
- [ ] 設定頁中的 legal 連結與登入頁 legal 連結都不是 404。

## F. OCR 延遲量測

建議每版至少記錄 3 組數據：

| 情境 | 原始大小 | 壓縮後大小 | Payload | Round-trip | AI latency | 結果 |
|------|----------|------------|---------|------------|------------|------|
| 正常單圖 | | | | | | |
| 長篇繁中圖 | | | | | | |
| LINE 回覆圖 | | | | | | |

判讀原則：

- `Payload` 很大：優先檢查截圖尺寸與壓縮。
- `Round-trip` 很長但 `AI latency` 普通：多半卡在上傳或網路。
- `AI latency` 特別長：優先檢查 OCR prompt、圖像內容密度與不必要的噪音圖。

## G. 發版簽核

- [ ] A 全部通過
- [ ] B 全部通過
- [ ] C1 / C2 全部通過
- [ ] C3 至少測 2 種高風險圖
- [ ] D 全部通過
- [ ] E 全部通過
- [ ] F 已至少記錄 3 組 OCR 量測

若 C3 / C4 有失敗，請額外記錄：

1. 測的是哪種圖
2. 實際錯在哪一段
3. 當時的 warning / confidence 顯示
4. 是否錯匯入了目前對話
5. OCR telemetry 數字

# VibeSync 上線前缺口清單

**版本日期：2026 年 3 月 16 日**  
**目前狀態：TestFlight v41 伙伴測試中**

---

## 1. 這份文件的用途

這份清單是把目前 code review、TestFlight 測試、法律文件調整與上線風險，整理成可直接執行的待辦。  
原則很簡單：

- `必修` 全綠，才建議送 App Store 審核
- `應修` 至少完成大半，才建議正式公開上線
- `可延後` 不要擋住現在的核心驗證節奏

相關參考文件：

- [App Store 審核策略](./app-store-strategy.md)
- [隱私權政策](./legal/privacy-policy.md)
- [服務條款](./legal/terms-of-service.md)
- [Claude Code handoff](../CLAUDE_CODE_HANDOFF_2026-03-16.md)

---

## 2. 必修

### 2.1 法務與對外一致性

- [ ] 官網 [https://vibesyncai.app/privacy](https://vibesyncai.app/privacy) 已同步為 [privacy-policy.md](./legal/privacy-policy.md) 的最新內容
- [ ] 官網 [https://vibesyncai.app/terms](https://vibesyncai.app/terms) 已同步為 [terms-of-service.md](./legal/terms-of-service.md) 的最新內容
- [ ] 首頁 footer 連結統一使用 `/privacy` 與 `/terms`
- [ ] `support@vibesync.app` 與 `privacy@vibesync.app` 皆可正常收信
- [ ] App Store Connect 的 privacy disclosure 與實際資料流一致

### 2.2 真機登入回歸

- [ ] Apple Sign In 成功登入與再次登入正常
- [ ] Google Sign In 在 TestFlight / 真機可正常 round-trip
- [ ] Email 註冊後可正常收驗證信並回到 app
- [ ] Resend verification 可正常寄送
- [ ] Forgot password 在 warm start 與 cold start 都能完成
- [ ] 登出後換另一個帳號登入，不會殘留前一個帳號的 tier / session 狀態

### 2.3 訂閱與權限回歸

- [ ] Starter 購買成功，額度與功能正確切換
- [ ] Essential 購買成功，額度與功能正確切換
- [ ] Restore Purchases 正常
- [ ] entitlement 消失或過期時，可正確回到 free
- [ ] RevenueCat webhook 有寫入正確 tier / status / expires_at
- [ ] 同裝置換帳號後不會串帳或殘留舊 tier

### 2.4 OCR / 手動輸入主流程

- [ ] 單張正常聊天截圖可辨識並分析
- [ ] 單張內容較多的長圖可辨識並分析
- [ ] 2-3 張連續截圖可依序匯入
- [ ] 手動輸入：最後一則是她，分析正常
- [ ] 手動輸入：最後一則是我，仍可分析她上一則回覆
- [ ] 手動輸入：只有我說，會存成草稿且不誤導為可立即一般分析
- [ ] 截圖匯入後，使用者能清楚知道下一步是「立即分析」

### 2.5 邊界情況與拒絕策略

- [ ] 社群平台留言截圖不會默默污染現有對話脈絡
- [ ] 與目前對話無關的截圖會有清楚提示，而不是直接 append 到尾端
- [ ] 色情、暴力、非聊天畫面會回傳明確的「不支援」或拒絕處理訊息
- [ ] OCR 低信心或高噪音時，會提示重試或更換截圖
- [ ] OCR 取消 / 重試流程不會留下 stale state 或晚到結果覆蓋畫面

### 2.6 穩定性與資料風險

- [ ] `flutter analyze` 保持全綠
- [ ] 主要 Edge Functions 至少通過 `deno check`
- [ ] AI / feedback / webhook 日誌不會過度暴露敏感內容
- [ ] 沒有已知未處理的 P1 auth / security 問題
- [ ] OCR telemetry 已至少收集 3 組真實測試數據，能判斷延遲主要卡在哪一段

---

## 3. 應修

這些項目不是今天一定要擋版，但越早補，產品品質會越穩。

- [ ] 截圖 preflight classifier：先判斷是不是正常聊天截圖，再決定要不要進 OCR
- [ ] 長上下文 summary 真正接進 live analysis，而不是只在本地生成
- [ ] 分析結果持久化，避免使用者下次打開像沒分析過
- [ ] 截圖匯入模式不只 append 尾端，至少支援「另存新對話」或「不是這段對話」提示
- [ ] 建立固定 QA 測試集，讓 prompt / OCR 改動後能回歸比對
- [ ] 補 auth / session switching / OCR import / password recovery 的回歸測試
- [ ] 再做一次 logging redaction review，確認不會把原始敏感內容寫進不必要的 log

---

## 4. 可延後

這些項目目前不建議當作送審 blocker：

- [ ] Booster 一次性購買
- [ ] 年訂閱 / 季訂閱 / 試用期
- [ ] 法律頁改成 app 內瀏覽器，而非外部瀏覽器
- [ ] Admin Dashboard 的進一步 polish

---

## 5. 伙伴待辦

這些適合由夥伴或網站端同步處理：

- [ ] 把 [privacy-policy.md](./legal/privacy-policy.md) 的最新內容同步到 `vibesyncai.app/privacy`
- [ ] 把 [terms-of-service.md](./legal/terms-of-service.md) 的最新內容同步到 `vibesyncai.app/terms`
- [ ] 首頁 footer 連結統一成 `/privacy` 與 `/terms`
- [ ] 確認兩個 legal 頁在手機與桌機上都可正常開啟
- [ ] 確認客服 / 隱私聯絡信箱真能收信

---

## 6. 品質門檻

如果要避免產品變成「只是套一層 LLM 的半成品」，至少要達到以下標準：

- [ ] 建議內容能明確對應最新有效上下文，而不是 generic 廢話
- [ ] 不支援的輸入會被清楚拒絕，而不是硬分析亂答
- [ ] 使用者能看懂目前系統在做什麼，例如壓縮中 / 上傳中 / AI 辨識中
- [ ] 長對話不會越用越亂，歷史脈絡有穩定摘要策略
- [ ] 同一類輸入，輸出結構與品質要有基本一致性

---

## 7. 建議執行順序

1. 先完成 legal live sync 與對外一致性檢查  
2. 再做 auth + 訂閱真機回歸  
3. 接著跑 OCR 主流程與邊界情況  
4. 根據 TestFlight 回饋，決定哪些 `應修` 要升級成送審 blocker

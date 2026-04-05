# VibeSync 上線前缺口清單

最後更新：2026-03-24
目前狀態：TestFlight 伙伴測試中

這份清單把目前的上線風險分成：
- 必修
- 應修
- 可延後
- 伙伴待辦

## 1. 必修

### Auth / Session
- [ ] Apple Sign In 在 TestFlight / 真機可正常 round-trip
- [ ] Google Sign In 在 TestFlight / 真機可正常 round-trip
- [ ] Email sign up / verify / resend / forgot password 全流程可正常完成
- [ ] 登出後換帳號登入，不會殘留前一個 tier / session 狀態

### 訂閱 / 額度
- [ ] Starter 購買成功後，功能與額度正確切換
- [ ] Essential 購買成功後，功能與額度正確切換
- [ ] Restore Purchases 正常
- [ ] 購買 / 恢復後首頁、設定頁、分析頁的 tier 顯示一致
- [ ] `recognize_only` 明確不扣額度
- [ ] 完整分析的扣點與預覽一致
- [ ] 測試白名單帳號只顯示估算值，不真的扣點

### OCR / 分析核心
- [ ] 正常雙人聊天截圖可成功識別、匯入、再分析
- [ ] LINE 引用回覆不會被拆成獨立新訊息
- [ ] 左右方判斷穩定
- [ ] 錯圖 / 社群圖 / 群組圖不會污染目前對話
- [ ] 多張截圖有輕微重疊時，不會重複匯入同一則訊息
- [ ] OCR 失敗 / 低信心時有明確人話與下一步

### Legal / 對外一致性
- [ ] [https://vibesyncai.app/privacy](https://vibesyncai.app/privacy) 內容與 app 流程一致
- [ ] [https://vibesyncai.app/terms](https://vibesyncai.app/terms) 內容與目前方案一致
- [x] `support@vibesyncai.app` 可收信（統一對外聯絡信箱，2026-03-30 確認）
- [ ] App Store Connect privacy disclosure 與實際資料流一致

## 2. 應修

### OCR / 結構成熟度
- [ ] 再累積 30-50 組真實截圖 benchmark
- [ ] OCR 方向低信心情境再收斂
- [ ] 多張截圖跨圖順序與重疊案例再多測幾輪
- [ ] 引用回覆 + 圖片泡泡混合情境再穩定一些

### 長上下文 / 分析
- [ ] 持續驗 summary-aware context 是否穩定
- [ ] 重新打開既有對話時，分析結果與新訊息狀態一致
- [ ] 混入舊對話或不同 thread 時，警告文案和另存路徑持續優化

### 觀測與營運
- [ ] 定期看 `ai_logs` 的 slow / timeout / structure_repaired 分布
- [ ] 定期看 `quotaReason / chargedMessageCount / estimatedMessageCount`
- [ ] 根據 TestFlight telemetry 找出最慢的 OCR 類型

## 3. 可延後

- [ ] Booster
- [ ] 年訂閱 / 季訂閱 / 試用
- [ ] Admin Dashboard polish
- [ ] 更重的自動化測試建設

## 4. 伙伴待辦

- [ ] 官網首頁最後一輪 QA
- [ ] App Store 連結在正式上線前最後掛上
- [ ] 伙伴持續收集真實截圖測例，回報：
  - speaker 判錯
  - 引用回覆誤拆
  - 社群圖誤放行
  - OCR 太慢
  - 分析理解歪掉

## 5. Go / No-Go

### 可以先停手 build TestFlight
- [ ] 沒有新的 P1 auth / subscription / OCR 問題
- [ ] 正常聊天圖、錯圖、LINE 引用圖、長繁中圖都至少測過一輪
- [ ] app 內沒有 raw error 或技術術語直接漏給用戶

### 可以準備送審
- [ ] 必修全部完成
- [ ] 伙伴測試沒有新的審核 blocker
- [ ] 最近 telemetry 沒有明顯惡化
- [ ] legal / privacy / support email / App Store disclosure 全部一致

## 6. 參考文件

- [OCR / 分析成熟度 Benchmark](./ocr-analysis-maturity-benchmark.md)
- [TestFlight 回歸與簽核清單](./testflight-regression-checklist.md)
- [App Store 審核策略](./app-store-strategy.md)
- [Privacy Policy](./legal/privacy-policy.md)
- [Terms of Service](./legal/terms-of-service.md)

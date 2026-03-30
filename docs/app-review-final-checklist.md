# App Review Final Checklist

最後更新：2026-03-25

用途：
- 這份清單是送 App Review 前的最後勾選版。
- 建議你和夥伴用最新 TestFlight build 逐項確認。
- 只要有任何一個硬門檻沒過，就先不要送審。

## 1. 帳號與登入

- [ ] Apple Sign In 真機成功
- [ ] Google Sign In 真機成功
- [ ] Email sign up 成功
- [ ] Email verify / resend 成功
- [ ] Forgot password 成功，包含冷啟動點連結
- [ ] 登出後重新登入正常
- [ ] 換帳號後不會殘留上一個帳號的 tier / session
- [ ] 刪帳後帳號真的失效，並回到登入頁

## 2. 訂閱與權限

- [ ] Starter 購買成功
- [ ] Essential 購買成功
- [ ] Restore Purchases 成功
- [ ] 升級後畫面會正確反映新權限
- [ ] 升級前的免費版分析不會假裝是完整版結果
- [ ] 測試帳號與白名單行為符合預期

## 3. OCR 與分析核心

- [ ] 正常雙邊聊天截圖 OCR 正常
- [ ] 單邊主訊息 + 引用卡 OCR 正常
- [ ] LINE 引用回覆不會拆成新訊息
- [ ] 主訊息左右不會被引用卡帶歪
- [ ] 長截圖 OCR 正常
- [ ] 多張連續截圖 OCR 正常
- [ ] 圖片 / 貼圖 / 影片預覽不會污染 speaker 判斷
- [ ] 對方名字 / 暱稱辨識沒有明顯錯字
- [ ] 社群圖 / 相簿圖 / 非聊天圖不會污染目前對話
- [ ] 錯圖時會給清楚白話提示，不會出現 raw error

## 4. 發版與法務

- [ ] GitHub Actions iOS release 成功
- [ ] TestFlight build 可在 App Store Connect / TestFlight 正常看到
- [ ] [privacy](https://vibesyncai.app/privacy) 可開
- [ ] [terms](https://vibesyncai.app/terms) 可開
- [x] `support@vibesyncai.app` 可收信（統一對外聯絡信箱，2026-03-30 確認）
- [ ] App Store Connect privacy disclosure 已核對

## 5. 硬門檻

以下任一項沒過，就先不要送審：

- [ ] Apple / Google / Email auth 沒有 P1 問題
- [ ] Essential 購買與 Restore 沒有 P1 問題
- [ ] OCR 正常聊天、引用回覆、長截圖三類都通過
- [ ] 沒有 raw error、英文技術詞、或明顯錯誤文案直接露給用戶
- [ ] iOS release workflow 不再因假性上傳失敗而卡住
- [ ] Privacy / Terms / disclosure 都和實際產品一致

## 6. 建議記錄的錯誤類型

- [ ] 左右判斷錯
- [ ] 引用卡被拆成新訊息
- [ ] 名字辨識錯字
- [ ] 升級後權限沒刷新
- [ ] Restore / 換帳號 tier 異常
- [ ] OCR 結果被舊快取干擾

## 7. 相關文件

- [Launch Readiness Checklist](./launch-readiness-checklist.md)
- [TestFlight Regression Checklist](./testflight-regression-checklist.md)
- [OCR Analysis Maturity Benchmark](./ocr-analysis-maturity-benchmark.md)
- [App Store Strategy](./app-store-strategy.md)

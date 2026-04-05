# App Review Final Checklist

最後更新：2026-04-05

這份清單是送審前最後核對用，不是功能願望清單。

## 1. 帳號與登入

- [ ] Apple Sign In 在 TestFlight 真機 round-trip 正常
- [ ] Google Sign In 在 TestFlight 真機 round-trip 正常
- [ ] Email sign up / verify / resend / forgot password 可正常完成
- [ ] 登出後重新登入，tier / session / 本地狀態一致
- [ ] 刪除帳號流程可完成，且重新登入不會吃到舊 session

## 2. 訂閱與 restore

- [ ] Starter 購買可完成
- [ ] Essential 購買可完成
- [ ] Restore Purchases 可完成
- [ ] Free -> Starter 後權限刷新正確
- [ ] Starter -> Essential 後權限刷新正確
- [ ] Essential -> Starter 或降級情境顯示正確
- [ ] 同 Apple ID restore 情境與預期一致
- [ ] 不同 Apple ID restore 情境已驗證

## 3. OCR / 截圖主流程

- [ ] 單張聊天截圖的純識別可成功
- [ ] 單張聊天截圖識別後匯入對話可成功
- [ ] 截圖後直接分析可成功
- [ ] LINE 引用回覆：外層 bubble speaker 判斷正確，引用卡只當 quoted context
- [ ] 長截圖可成功
- [ ] 多張截圖 overlap 情境可成功
- [ ] 名字小字、錯字、模糊邊界案例已抽測
- [ ] 圖片 / 貼圖 / 影片 bubble 不會把 speaker 判斷帶歪
- [ ] OCR 失敗時不顯示 raw internal error 給使用者

## 4. 送審與對外資訊

- [ ] `https://vibesyncai.app/privacy` 可正常開啟
- [ ] `https://vibesyncai.app/terms` 可正常開啟
- [ ] `support@vibesyncai.app` 可收信
- [ ] App Store Connect 的 privacy disclosure 已依目前資料流填寫
- [ ] App Review 說明文已更新成目前實際功能與資料流

## 5. Release / Workflow

- [ ] 最新 iOS release workflow 綠燈
- [ ] 最新 Edge Function deploy workflow 綠燈
- [ ] TestFlight build 可在 App Store Connect / TestFlight 看到
- [ ] `analyze-chat` 目前維持 `--no-verify-jwt`，未被誤改

## 6. Release Gate

只有以下條件都成立，才算可送審：

- [ ] Auth 沒有 P1 blocker
- [ ] Subscription / restore 沒有 P1 blocker
- [ ] OCR 主流程用同一批真實截圖再測仍穩定
- [ ] Privacy / Terms / support / disclosure 都已對齊
- [ ] 沒有新的 deploy-only regression

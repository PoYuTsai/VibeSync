# VibeSync AI 鍵盤：下一版 TestFlight 檢查表

更新：2026-07-16

## 額度契約

- 只有伺服器成功產出並驗證回覆後扣 1 則共用額度。
- Free：每日 15、每月 30。
- Starter：每日 50、每月 300。
- Essential：每日 120、每月 800。
- 模型限流、未登入、網路失敗、格式驗證失敗均不扣。
- 伺服器確認額度用盡後，鍵盤寫入一次性安全旗標；使用者開啟或切回 VibeSync 時直接進 `/paywall`。

## Build 前（只需設定一次）

1. Apple Developer 建立 App Group `group.com.poyutsai.vibesync`。
2. Runner App ID `com.poyutsai.vibesync` 與 Keyboard App ID `com.poyutsai.vibesync.keyboard` 都開啟：
   - App Groups：`group.com.poyutsai.vibesync`
   - Keychain Sharing：`TTQHTVG8CC.group.com.poyutsai.vibesync`
3. 重新產生／下載兩個 App ID 的 Development、Ad Hoc／App Store provisioning profiles。
4. Xcode 開啟 `ios/Runner.xcworkspace`，確認 Runner 與 VibeSyncKeyboard targets：
   - Team 都是 `TTQHTVG8CC`
   - Signing 無紅字
   - Runner 的 Frameworks, Libraries, and Embedded Content 有 VibeSyncKeyboard.appex
5. 部署 `keyboard-reply` Edge Function；此 function 使用一般 JWT 驗證，不加 `--no-verify-jwt`：

   `supabase functions deploy keyboard-reply --project-ref fcmwrmwdoqiqdnbisdpg`

## Archive / TestFlight

1. `flutter clean && flutter pub get`
2. Xcode 選 Any iOS Device (arm64)，先 Product > Build。
3. Product > Archive，Validate App 後上傳 TestFlight。
4. App Store Connect 確認 build 內含 `VibeSyncKeyboard.appex`。

## 真機驗收

1. 安裝並登入 VibeSync，進「設定 > VibeSync AI 鍵盤」。
2. 跟 onboarding 到 iPhone 設定，新增 VibeSync 並開啟「允許完整取用」。
3. 在 LINE／Instagram／Messages：複製對方一則訊息，長按地球切到 VibeSync，按「載入」。
4. 五種風格各測一次；每次應插入文字框、不自動送出，第二次生成應安全替換上一則仍未修改的回覆。
5. 關閉完整取用：AI 按鈕不可用，但 ABC、空白、換行、刪除、切換鍵盤仍可用。
6. 登出／token 過期：提示回 App 更新登入，不呼叫生成。
7. 用測試 quota 將每日額度耗盡：鍵盤提示額度已用完；開啟 VibeSync 後應直接進 paywall，且只導一次。
8. 觸發模型限流：只顯示稍後再試，不可進 paywall、不可扣額度。
9. Supabase 核對成功請求每次 `daily_messages_used`、`monthly_messages_used` 各只增加 1；失敗請求不增加。

## 出貨判定

以下全數完成前，不宣稱 dogfood safe：獨立 Codex review 通過、Mac/Xcode build 與簽章通過、Edge production smoke 通過、真機 quota/paywall 與 Full Access 回歸通過。

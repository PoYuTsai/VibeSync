# Launch Readiness Checklist

最後更新：2026-09-03
目前目標：iOS / TestFlight / App Review 上線前最後收尾

送審主控台、App Review Notes 草稿、Privacy Label 對照見：

- `docs/app-review-submission-package.md`

## 0. Phase 14 目前判定

目前判定：`Repo GO / Submit HOLD`。

2026-08-15 更新（目標版本 1.0.1）：

- 這兩週 dogfood 已實測覆蓋核心功能：分析（含作戰板，常態跑）、練習室 3 難度＋3 模式（該批 bug 已全數修復）、問教練 Sydney 三入口重構（2026-08-15 真機專測）、開場救星、新話題。過程中發現的 bug 均已修復並隨 build 驗證。
- 去 AI 味三批＋色彩紀律（AppColors 收斂、raw_color 棘輪）已出貨，UI 收斂由 Eric 真機認可。
- 刪帳號高風險路徑 2026-08-14 真機實測：發現殘餘本機快取導致 SR 卡無法進聊天，已修（角色圖鑑改讀 server 砍本機快取 `6c66a3e8`＋SR 解鎖判定 `b87816e0`＋403 錯誤顯示 `bd58a2b1`）。
- AI 鍵盤 2026-08-15 拍板：無完整取用的 qwerty 合規地板整組拆除（`d6736c0`），鍵盤只剩截圖／文字兩個 surface；4.4.1 送審風險 Eric 拍板承擔，真的被擋再處理。7/17 硬閘中 production 側（migration、HMAC、JWT-verified Edge、live contract）已完成；裝置側項目照第 1 節逐項驗。
- Submit 前剩下的人工 gate：訂閱 sandbox 購買／Restore／升降級邊界、App Store Connect privacy／IAP／reviewer 資訊核對、送審候選 build 照 `testflight-regression-checklist.md` §0.1 跑最後一輪正式 smoke。

## 1. 核心功能

### Auth / Session

- [ ] Apple Sign In 真機 round-trip 正常
- [ ] Google Sign In 真機 round-trip 正常
- [ ] Email sign up / verify / forgot password 正常
- [ ] 登出 / 重新登入後 session 不混亂

### Subscription / Tier

- [ ] Starter 購買與 tier 刷新正確
- [ ] Essential 購買與 tier 刷新正確
- [ ] Restore Purchases 正常
- [ ] 同 Apple ID / 不同 Apple ID 邊界情境已驗證
- [x] recognize-only 不扣額度（2026-09-03 程式端驗 `quota_usage.ts` recognize_only_free＋`quota_usage_test`；獨立 OCR 免費計數）

### OCR / Analysis

- [x] 單張截圖識別正常（2026-08-15 前持續 dogfood 覆蓋）
- [x] 截圖匯入後分析正常（2026-08-15 前持續 dogfood 覆蓋）
- [ ] iOS 首次選取聊天截圖時，Photo Library 權限彈窗文案正常
- [ ] LINE 引用回覆、長圖、多圖 overlap 已驗證
- [ ] media bubble / sticker / video bubble 不會破壞 speaker 判斷
- [ ] 同一批真實截圖抽測仍維持穩定

### AI 鍵盤

2026-08-15 拍板：qwerty 合規地板已拆，surface 只剩截圖／文字；4.4.1 風險承擔，送審照現狀出。

- [x] Live contract 回 `keyboard-reply-exactly-once-v1`
- [x] Production 測試帳號 fresh／replay／mismatch、DB pending／settlement／rollback、RLS／grant／cron 通過且 smoke rows 清為 0
- [ ] Fresh request、lost-response replay、pending、mismatch、quota、model-rate 行為正確且不重複扣額
- [x] Signed Archive / IPA 包含 `VibeSyncKeyboard.appex`（2026-09-03 由 Build & Distribute run 33648963212 的 IPA 驗證）
- [ ] LINE、Instagram、Messages 在 Full Access 開／關時都能正確成功或安全失敗

## 2. 法務與對外資訊

- [x] [https://vibesyncai.app/privacy](https://vibesyncai.app/privacy) 內容與目前資料流一致（2026-09-03 驗：我幫你修 7 天重播、AI 鍵盤 HMAC／24 小時／Keychain 23 小時、4.3 保留期限 30 天、資料類別與不追蹤聲明齊全；最後更新 2026-09-02）
- [x] [https://vibesyncai.app/terms](https://vibesyncai.app/terms) 內容與目前方案一致（2026-09-03 驗 Free／Starter／Essential 與自動續約條款；價格以商店頁為準）
- [ ] App Store Connect Support URL 使用已上線的 HTTPS 頁面：[https://vibesyncai.app/support](https://vibesyncai.app/support)
- [ ] `vibesyncaiapp@gmail.com` 可收信
- [ ] App Store Connect privacy disclosure 已完成
- [ ] Privacy Label 已揭露使用者主動上傳的聊天截圖、文字對話、訂閱、使用量與診斷資料
- [ ] App Review 說明文已更新

## 3. 後端與部署

- [x] 最新 Edge Function deploy 綠燈（2026-08-15 `dd0825d8` Deploy Edge Function success）
- [x] 最新 iOS release workflow 綠燈（2026-08-31 run 33428088300）
- [x] 精準套用 `20260717120000_keyboard_reply_exactly_once.sql` 並核對 migration history
- [x] 依 DB → `KEYBOARD_REPLAY_HMAC_KEY` → JWT-verified `keyboard-reply` v5 順序部署
- [x] RevenueCat webhook 正常同步 tier（2026-09-03 production `webhook_logs` 聚合：近 60 天 RENEWAL／PRODUCT_CHANGE／EXPIRATION／CANCELLATION／BILLING_ISSUE 皆處理出 tier，最近一筆 2026-09-01；全為 SANDBOX，正式購買事件待上線）
- [x] `sync-subscription` 不再使用 hard-coded fallback key（2026-09-03 驗 `index.ts:15` 只讀 env、缺鍵 500 fail-closed）
- [x] `revenuecat-webhook` 只保留最小必要 webhook log payload（2026-09-03 驗 `buildWebhookLogPayload` 白名單，無原始 body／headers）
- [x] `analyze-chat` 暫時維持 `--no-verify-jwt`，直到未來專案單獨調查完成（2026-09-03 驗 `deploy-edge-function.yml`）

## 4. 觀測與營運

- [x] `ai_logs` 能看成功 / 失敗 / timeout / latency 分布（2026-09-03 production 聚合：近 7 天 analyze 15 筆全成功 p50 27s／p95 49s、recognize_only 5 筆 p50 15s、practice 18 筆，失敗 0）
- [ ] restore / transfer 問題有文件可查
- [ ] support 流程可接住帳號、支付、OCR 失敗問題

## 5. Go / No-Go

只有以下都成立才算 Go：

- [ ] OCR 主流程穩定
- [ ] Auth / subscription / restore 無 P1 blocker
- [ ] 對外法務與 support 資訊一致
- [ ] 最新部署沒有重新引入 regression
- [ ] 已完成最後一輪真人 regression
- [ ] AI 鍵盤 production / signed iOS / privacy gates 全部完成

## 6. Android 備份／重裝／轉機驗證（AND-04）

政策依據：`docs/decisions.md` ADR #43（fail-closed：`allowBackup=false` 為主閘，
兩份 rules 檔全域 exclude 為第二道欄）。靜態守門在 `test/unit/android/` 契約測試
與 CI 的 merged manifest 斷言；以下實機步驟驗證 OEM 是否尊重宣告，每項記錄
裝置型號與 Android 版本。不得使用已淘汰的 `adb backup` 當證據。

- [ ] **重裝**：安裝 → 登入、產生聊天／分析資料 → 解除安裝 → 重新安裝。
      預期：回到未登入的全新狀態；不得出現舊 token 自動登入、殘留聊天或解密錯誤 crash。
- [ ] **雲端還原**：裝置 A 開啟 Google 備份並觸發備份（設定 → Google → 備份），
      在裝置 B 以同帳號還原。預期：VibeSync 資料不在還原清單中；App 首啟為全新狀態。
- [ ] **D2D 轉機**：用系統轉移流程（Pixel 線傳／Samsung Smart Switch）從 A 轉到 B。
      預期：App 可被複製安裝，但登入狀態、聊天、圖片不隨行；首啟不得 crash。
- [ ] **解密失敗容錯**：若任何路徑導致部分資料殘留（OEM 不尊重宣告），App 首啟必須
      走全新狀態或明確重登，不得 crash、不得顯示他人／舊帳號殘留內容。

支援矩陣（最低）：一台 stock Android（Pixel，Android 14+）＋一台 Samsung
One UI（Smart Switch 路徑）；API 24 模擬器僅驗安裝與冷啟動（無 D2D）。

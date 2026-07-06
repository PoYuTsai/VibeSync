# 案4：48h 跟進提醒（本地通知版）設計

> 2026-07-06 brainstorming 定案。上位計畫：`docs/plans/2026-07-06-post-review-optimization-roadmap.md` 案 4。
> 狀態：DESIGN APPROVED，待轉 implementation plan。

## 目標

分析完一個綁定對象的對話後，48 小時後本地推一則跟進提醒，把用戶帶回 partner 詳情頁（現成 `coach-follow-up` 入口），促成「別讓對話冷掉」。**不碰 server、不需 push 憑證、不需 pg_cron。**

## 四項核心定案

| 面向 | 決定 | 理由 |
|---|---|---|
| 觸發 | 只有「綁 partner 的分析完成並成功落 Hive」才排 +48h；一對象最多一則待發 | 語意乾淨，天然避開練習室／一次性分析誤觸發 |
| 授權 | 自訂軟詢問卡先，用戶點「幫我提醒」才呼叫系統授權框；被拒不再纏 | 保護 iOS 一次性授權額度，系統框只在用戶已表態時彈，長期授權率最健康 |
| 重複分析 | `cancel(partnerId)` + 重排 +48h（倒數歸零） | 最直覺、無 edge case 堆疊；語意＝「從最後一次關注算 48h」 |
| 文案 | 帶對象暱稱，語氣輕 | 對象名是用戶自輸暱稱（識別性低），帶名行動力明顯較高；鎖屏預覽由 OS 系統開關把關，不在 app 端硬遮 |

文案定稿：`跟{displayName}的對話停兩天囉，要不要看看下一步？👀`

## 架構

**新套件**：`flutter_local_notifications` + `timezone`（`zonedSchedule` 需 tz location）。

**新 service `FollowUpNotificationService`（Riverpod provider）**：
- `init()`：註冊 notification channel（Android）、iOS 設定、`tz.initializeTimeZones()` + local location、掛 tap handler。
- `requestSoftOptIn()`：畫自訂軟卡 →（點「幫我提醒」）→ 呼叫系統授權框。
- `scheduleFollowUp(partnerId, displayName, fireAt=+48h)`：先 `cancel(id)` 再 `zonedSchedule`。
- `cancel(partnerId)` / `cancelAll()`。
- 通知 id＝partnerId 的穩定 int hash。

**持久化（Hive）**：opt-in 狀態機 flag（是否已問過軟卡、是否已授權／被拒），避免重複彈與被拒後纏擾。

## 掛點（實作首步先派 Explore 精準定位，不在設計階段猜）

- **排程**：掛在「綁 partner 的分析完成、且成功落 Hive」之後的路徑。
- **取消**：partner 刪除路徑 → `cancel(partnerId)`，避免對已刪對象發通知。

## Deep-link

- 通知 payload＝`partnerId`。tap handler 解析後路由到 partner 詳情頁。
- **冷啟動**（app 被殺）用 `getNotificationAppLaunchDetails()` 補撈初始 payload，否則殺掉狀態下點通知會漏路由。

## 邊界處理

- **權限被拒**：靜默降級，不排、不再彈軟卡。
- **總開關**：設定頁一顆 toggle「48h 跟進提醒」，關掉即 `cancelAll()` 並停排。
- **iOS**：本地通知不需 push 憑證／aps entitlement；但新增原生依賴須隨**送審後下一個 build**進。
- **時區**：`tz.initializeTimeZones()` + local location，避免 UTC 偏移排錯時間。

## 測試（build-safe）

- Service 單元測試：schedule 前必先 cancel（重排歸零驗證）、id 穩定 hash、opt-in flag 狀態機、被拒不再彈。
- mock 掉 `flutter_local_notifications` plugin channel，測純 Dart 邏輯層。

## 風險等級

中。新增權限請求（時機已設計＝軟卡先）；iOS 送審後改原生依賴要隨下個 build。屬 client-only，不動 server/schema。

## Open items（轉 plan 時處理）

- 定位排程掛點與 partner 刪除掛點的實際檔案/行號。
- 確認 partner 詳情頁路由名稱與 deep-link 導航方式。
- 軟詢問卡的 UI 落點（分析完成頁 vs 首頁）。

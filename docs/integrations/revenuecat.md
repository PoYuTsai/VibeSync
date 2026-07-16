# RevenueCat 整合

> iOS 訂閱管理使用 RevenueCat。本檔記錄配置、產品、webhook、除錯歷史。
>
> Common pitfall（每次部署都會重新踩到的）已搬到 CLAUDE.md；此檔是深度細節與歷史。

---

## Project 資源

| 項目 | 值 |
|------|-----|
| RevenueCat Project | VibeSync (`projd482586c`) |
| iOS App | `app73a7f8a72d` |
| iOS Public API Key | `appl_ZYVwxdvbEIAHxYUEHhdVkVLrkdY` |
| In-App Purchase Key | `SF836SBCKL`（P8 uploaded） |
| App Store Connect API Key | 另建的 App Manager 權限 Key |
| Issuer ID | `35ed1ede-ef4b-4b24-9dd1-47d777cb032b` |
| Vendor Number | `94060817` |
| Bundle ID | `com.poyutsai.vibesync` |
| Team ID | `TTQHTVG8CC` |

---

## 產品（2026-04-22 起，共 4 個付費產品）

| Product ID | Tier | 週期 | 價格 |
|------------|------|------|------|
| `starter_monthly` | Starter | 月繳 | NT$590 |
| `starter_quarterly` | Starter | 季繳 | （季繳價，以 App Store 為準） |
| `essential_monthly` | Essential | 月繳 | NT$1,290 |
| `essential_quarterly` | Essential | 季繳 | （季繳價，以 App Store 為準） |

### 額度（2026-04-22 起）
| Tier | 月訊息 | 日上限 | AI 模型 |
|------|--------|--------|---------|
| Free | 30 | 15 | 分析對話 Sonnet 5；其他 Free endpoint 原則上 Haiku |
| Starter | 300 | 50 | 分析對話 Sonnet 4.6 |
| Essential | 800 | 120 | 分析對話 Sonnet 4.6 |

雷達圖限 Starter / Essential 可見，Free 隱藏。

---

## Entitlements

- `premium` entitlement 關聯全部 4 個訂閱產品
- App 內購買 / 恢復購買後，client 會呼叫 `sync-subscription` 對齊 Supabase `subscriptions`
- 真正的續訂 / 到期 / billing issue 由 `revenuecat-webhook` 寫回資料庫

---

## Webhook

**Edge Function**: `revenuecat-webhook`（部署於 Supabase）
**URL**: 已在 RevenueCat Dashboard 設定

**事件流**:
```
用戶購買 / 恢復購買 → RevenueCat SDK → sync-subscription Edge Function
                   → 更新 Supabase `subscriptions`
                   → App 重新載入後反映新 tier / product_id / 額度

續訂 / 到期 / billing issue → RevenueCat webhook → revenuecat-webhook Edge Function
                           → 更新 Supabase `subscriptions` / `revenue_events`
```

**實作細節**:
- 儲存 minimized diagnostic payload（2026-04-05 起）
- 不再依賴 RevenueCat key fallback（安全性調整）
- client-initiated sync 若 RevenueCat 暫時回空，不應把 paid tier 直接寫回 free

---

## App 內入口（目前 UX）

- `恢復購買`：重新向商店 / RevenueCat 同步既有訂閱，不會再次扣款
- `管理訂閱`：跳 App Store 管理目前方案、續訂與取消
- 若已排程降級：App 會顯示 pending downgrade；使用者去 App Store 取消後，回 App 可點「我已取消降級，更新狀態」重新驗證

---

## 常見狀況與處理

### Tier 購買後未同步
見 `docs/bug-log.md#2026-03-15`。速查：

```sql
-- 確認當前 tier
SELECT tier FROM subscriptions
WHERE user_id = (SELECT id FROM auth.users WHERE email = 'xxx@xxx.com');

-- 強制同步（只有必要時才動）
UPDATE subscriptions SET tier = 'essential'
WHERE user_id = (SELECT id FROM auth.users WHERE email = 'xxx@xxx.com');
```

App 端目前沒有手動選 tier 的 debug UI。先走 `恢復購買`，再檢查 `sync-subscription` / webhook 與 RevenueCat entitlement 狀態。

### 「無法取得產品資訊」
見 `docs/bug-log.md#2026-03-14`。根因通常是：
1. **RevenueCat App Store Connect API 區塊沒上傳 P8 key**（不是 In-App Purchase 那個 P8！）
2. P8 key 權限不足 — 必須是 **App Manager** 等級
3. Packages 內混了無效的 RevenueCat 測試產品
4. 訂閱產品沒關聯到 App 版本

---

## TestFlight 測試購買

TestFlight 購買**自動走 Sandbox**，不會真的扣款。測試者直接用自己的 Apple ID 購買即可。

Sandbox Tester 帳號只在極少數特殊情境需要（例如要測試未上架 app 的 IAP）。

---

## 歷史除錯記錄

### 2026-03-14 設定階段踩過的坑

| # | 問題 | 解法 |
|---|------|------|
| 1 | Products "Could not check" | 銀行審核過了還在顯示 → P8 key 問題 |
| 2 | Offerings 未設為 Current | Dashboard 手動設 |
| 3 | App Store Connect 產品狀態 | 確認 Ready to Submit |
| 4 | RevenueCat "App Store Connect API" 區塊空 | 上傳 P8 |
| 5 | P8 權限錯誤 | 建 App Manager 權限的 Key |
| 6 | Packages 含 RC 測試產品（Monthly/Yearly/Lifetime） | 移除，只留 App Store 產品 |
| 7 | Debug: `CONFIGURATION_ERROR - None of the products could be fetched` | 訂閱沒關聯到 App 版本 |
| 8 | 關聯後還是拿不到 | 等 Apple 同步（產品剛建 + 剛關聯需幾小時） |

### 驗證清單
- [x] RC Configured（初始化成功）
- [x] Offerings/Packages 載入（2 packages 正確）
- [x] TestFlight Sandbox 購買成功
- [x] Webhook 觸發 → Supabase tier 更新為 essential
- [x] `premium` entitlement 建立並關聯產品

---

## 相關檔案

- `lib/features/subscription/data/providers/subscription_providers.dart`
- `lib/features/subscription/presentation/screens/paywall_screen.dart`
- `lib/features/subscription/presentation/screens/settings_screen.dart`（月/季繳標示 + 下次續約日）
- `supabase/functions/revenuecat-webhook/`

---

## 2026-05-15 Restore Purchases paid -> free decision

Status: Active during TestFlight dogfood stabilization.

Decision:

- Keep the `restorePurchases()` paid-to-free snapshot guard for now.
- If RevenueCat temporarily returns no active paid tier while the local app/DB still has a paid tier, preserve the paid tier until a trusted server-side webhook confirms expiration or cancellation state.
- Do not change this behavior without an explicit Eric decision.

Why:

- VibeSync has already hit P0-class issues where paid TestFlight users were incorrectly regressed to Free because RevenueCat sync briefly returned an empty/free state.
- The more user-damaging failure during dogfood is blocking a valid paid user from core analysis/coach quota.
- A real cancellation normally keeps entitlement access until the paid period expires; the final downgrade should be driven by RevenueCat webhook events, not by a transient client restore snapshot.

Tradeoff:

- A user who is truly expired but whose webhook has not landed yet may temporarily keep paid access.
- This is accepted short-term because it is safer than incorrectly downgrading valid paid users during dogfood.

Revisit after:

- TestFlight subscription matrix is stable.
- RevenueCat webhook delivery has been verified for `CANCELLATION`, `EXPIRATION`, and `BILLING_ISSUE`.
- Eric explicitly reopens restore semantics.

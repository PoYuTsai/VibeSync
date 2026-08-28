# Android M5 Cross-store Entitlement Kickoff（Frozen Code Tranche）

> 日期：2026-08-28（Asia/Taipei）
> Base：`560e78af43ec7c9a46803fa690ea0a9306806e52`
> Branch：`codex/android-m5-cross-store-entitlement-20260828`
> 角色：Luna Max＝coding owner；Codex＝coordinator／主 reviewer；Claude＝payment-risk independent reviewer
> Delivery：只在 Android M5 分支實作、驗證與審查；不合 `main`、不操作 production

## 來源與目標

本 tranche 落實 Frozen Spec v1 的 `BILL-05`、`BILL-06`、`COPY-01`。若本文件與下列既有文件衝突，以本文件明確凍結的 M5 邊界為準：

1. `docs/plans/2026-08-21-android-public-release-roundtable-spec.md`
2. `docs/plans/2026-08-21-android-public-release-implementation-plan.md`
3. 本文件

目標是完成可審查的 M5 code candidate：Play 與 App Store 的事件永遠各自更新原商店狀態；有效權益可跨平台共享；另一商店已有權益時阻止重複訂閱；歷史雙訂會明示兩筆來源；主要文案先說權益狀態，商店名稱只由 authoritative source 決定。

## 基線與已知缺口

M3／M4 已提供 per-store schema、atomic reducer、source-aware client read、Android package-only 購買與跨店 replacement fail-closed 基礎。M5 只補 Frozen Spec 尚未閉合的缺口：

1. Webhook 尚未完整覆蓋 `SUBSCRIPTION_PAUSED`、grace period、refund／revocation 與所有支援的 expiration reason fixture。
2. `sync-subscription` 與 per-store reducer 已有 stale／duplicate／empty snapshot 基礎，但缺完整 Play lifecycle 與跨店組合證據。
3. client 目前能封鎖跨店新購買，卻尚未把 authoritative 雙來源明示成完整的使用者可見狀態與文案矩陣。

## 凍結的公開測試邊界

測試只允許落在下列 public seams；不得為了測試綁死 private helper 或內部呼叫順序：

1. **Webhook normalization seam**：`buildRevenueCatWebhookStoreEvent(type, event)` 將一個 RevenueCat lifecycle payload 轉成一個完整 `StoreSubscriptionEventInput`，或明確 fail closed／ignore。
2. **Authoritative store-state seam**：`buildRevenueCatStoreEvents`、`reduceStoreSubscriptionEvent`、`resolveEffectiveEntitlementAt` 與既有 sync persistence policy，驗證每店隔離、排序、重播與 aggregate entitlement。
3. **Client behavior seam**：source-aware read 產生的公開 `SubscriptionState`，以及 Paywall／設定頁的可見狀態與可執行動作；測試購買是否可開始、原商店管理導向、雙來源呈現與平台文案。

## Frozen behavior

### BILL-05 — Play lifecycle 與來源可靠性

- `product_id` 帶與不帶 `:basePlanId` 都要保存完整 product，base plan 只能由明確欄位或 Play colon identifier 取得，不得由目前 OS 或文案猜來源。
- `INITIAL_PURCHASE`、`RENEWAL`、`UNCANCELLATION`、`SUBSCRIPTION_EXTENDED` 恢復／延長該商店權益。
- `CANCELLATION` 保留到 authoritative expiry；退款／revocation 若已使 expiry 到期，不得繼續授權。
- `BILLING_ISSUE` 不等於立即到期；有 grace period 時以 authoritative grace deadline 保留權益，account hold／真正到期由 expiry／`EXPIRATION` 撤權。
- `SUBSCRIPTION_PAUSED` 只表示期末將暫停，不得當下撤權；只有 `EXPIRATION`（含 `SUBSCRIPTION_PAUSED` reason）才撤權。後續 renewal／uncancellation 能恢復。
- 支援的 expiration reasons：`UNSUBSCRIBE`、`BILLING_ERROR`、`DEVELOPER_INITIATED`、`PRICE_INCREASE`、`CUSTOMER_SUPPORT`、`UNKNOWN`、`SUBSCRIPTION_PAUSED`。
- event ID replay、較舊／同時事件、跨店事件、空 snapshot 都必須 fail closed，不得誤降另一商店或 legacy entitlement。

### BILL-06 — 跨店 entitlement 與雙訂防護

- 相同 App User ID 的所有 verified store rows 一起計算有效權益，取仍有效來源中的最高 tier；任一店到期不得蓋掉另一店仍有效權益。
- 當前平台與 authoritative active store 不同時，關閉新購買／換方案入口並導向原商店管理；來源不明也 fail closed。
- 原來源到期後，且沒有另一個有效來源，才重新開放目前商店購買。
- 同時兩店有效或歷史雙訂時，UI 明示 App Store 與 Google Play 兩筆來源，不靜默降權、不聲稱能代替另一商店取消。

### COPY-01 — 來源感知文案

- 主要訊息只說「權益已啟用」及目前方案，不先突出商店。
- 商店名稱只出現在訂閱詳情／管理動作，且只能取自 verified authoritative source rows。
- Android 免費／Play-only 使用者不得看到 Apple／App Store 誤導文案；iOS 免費／App-Store-only 使用者不得看到 Google Play 誤導文案。
- 雙來源狀態可同時顯示兩個商店；未知來源不得猜商店。

## TDD 垂直切片

1. Play webhook lifecycle：每次一個 failing fixture → 最小 normalization／state 變更 → focused Deno tests。
2. per-store／aggregate 組合：每次一個 stale、duplicate、expiry 或 cross-store fixture → 最小 reducer／sync 變更。
3. client state 與文案：每次一個 free／Play／App Store／both fixture → 最小 state／UI 變更 → focused Flutter tests。
4. 最後才跑完整 Deno／Flutter tests、`flutter analyze`、`git diff --check` 與 exact-SHA CI。

## Stop conditions 與排除項目

- 任一事件需要猜 store、product、base plan 或目前 OS 才能成立時停止並 fail closed。
- 任一跨店 fixture 會撤掉另一店仍有效權益、開放第二筆購買、或顯示錯商店文案時，不得宣告 M5 code candidate。
- 若需要 schema／migration、RevenueCat／Play／GitHub Secrets 變更、Edge deploy、真實扣款、store release 或 `main` 合併，立即停止並回 Eric；本 tranche 沒有這些權限。
- Google Play `com.vibesync.app` ownership 與 EXT-03／EXT-04 可繼續等待，不阻塞本地 M5 code candidate；live sandbox／dashboard closeout 另行處理。

## Exit

- `BILL-05`、`BILL-06`、`COPY-01` 的 frozen fixtures 全綠。
- focused＋full tests、analyze、diff check 與 exact-SHA Build & Distribute 通過。
- Codex 對 exact commit 完成主審；payment risk 再經 Claude 唯讀獨立審查，無未解 P0／P1／P2。
- 只稱 **M5 code candidate**；未完成 EXT-03／EXT-04／Internal Play sandbox 前，不稱 Android 付款已 live。

## 官方事件契約參考

- RevenueCat Event Types and Fields：<https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields>
- RevenueCat Common Webhook Flows：<https://www.revenuecat.com/docs/integrations/webhooks/event-flows>

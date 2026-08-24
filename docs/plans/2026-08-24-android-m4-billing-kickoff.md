# Android M4 Billing Kickoff（Frozen Code Tranche）

> 日期：2026-08-24（Asia/Taipei）
> Base：`9c408bb44aec49b47234a5490b2583708721b6e0`
> Branch：`codex/android-m4-billing-client-20260824`
> 角色：Luna Max＝coding owner；Codex＝coordinator／main reviewer；Claude＝payment risk independent reviewer
> Delivery：只在 Android M4 分支實作、驗證與審查；本 tranche 不合入 `main`

## 來源與目標

本 tranche 落實 Frozen Spec v1 的 `BILL-01`～`BILL-04`。若本文件與下列文件
衝突，依序以前者為準：

1. `docs/plans/2026-08-21-android-public-release-roundtable-spec.md`
2. `docs/plans/2026-08-21-android-public-release-implementation-plan.md`
3. 本文件

目標是產出可審查、可建置的 M4 code candidate：Android RevenueCat 只能使用
Android public SDK key；Paywall 只能購買目前 Offering 內四個完整且精確對應的方案；
購買、恢復、管理／取消與 Android 換方案 mode 都有 fail-closed 契約與測試。

## 凍結範圍

1. 平台 key：
   - iOS 只接受 `appl_` public SDK key；Android 只接受 `goog_` public SDK key。
   - Android 必須使用明確的 Android key 輸入；不得把 generic
     `REVENUECAT_PROD_KEY`、iOS key、server secret 或 hardcoded fallback 當成
     Android key。
   - 缺值或 prefix 錯誤時不得 configure RevenueCat；App 可啟動，但購買入口必須
     維持關閉並呈現可重試的同步中／不可用狀態。
2. Android 四商品契約：

   | Store product + base plan | RevenueCat package | Tier |
   |---|---|---|
   | `vibesync_starter:monthly` | `starter_monthly` | Starter |
   | `vibesync_starter:quarterly` | `starter_quarterly` | Starter |
   | `vibesync_essential:monthly` | `essential_monthly` | Essential |
   | `vibesync_essential:quarterly` | `essential_quarterly` | Essential |

   - 只接受目前 Offering 的 Package；不得用 title／description／localized text／
     period 猜商品，也不得在 Offering 不完整時呼叫 direct product purchase。
   - 四列必須全部且唯一匹配，任一缺失、重複或錯配時整個 Android Paywall
     fail closed，不開放部分購買。
   - iOS 既有購買路徑不得回歸；iOS 也不得依賴模糊文字比對或 direct-product
     fallback，可用既有已知 App Store product ID allowlist 做 exact mapping。
3. 購買與換方案：
   - 新訂閱透過 `PurchaseParams.package`。
   - Starter → Essential：`immediateAndChargeProratedPrice`
     （`CHARGE_PRORATED_PRICE`）。
   - Essential → Starter：`deferred`（`DEFERRED`）。
   - 同 tier 月繳 ↔ 季繳：`immediateWithoutProration`
     （`WITHOUT_PRORATION`）。
   - Android 有 active Play 訂閱且換方案時，必須帶原 product identifier 與上述
     mode；缺少 authoritative 原方案資料時不得猜 replacement mode。
   - UI 的確認與完成文案要區分立即扣款／立即生效、下期生效、同級週期切換。
4. 恢復、管理與取消：
   - 恢復購買沿用 RevenueCat restore，不新增扣款。
   - 管理／取消優先使用 CustomerInfo 的 store-native `managementURL`；Android
     不得導向 App Store，iOS 不得導向 Google Play。
   - 若無 authoritative management URL，僅可用與已知原購買商店一致的安全
     fallback；來源不明時 fail closed，不猜商店。
5. 文件與 CI：
   - 更新 RevenueCat runbook 的 Android code contract、所需 secret 名稱與
     dashboard 對表欄位，不寫 secret 值。
   - Workflow 可傳入明確 Android public key，但本 tranche 不建立／修改 GitHub
     Secret；secret 尚未存在時不得讓 app 誤用 iOS key。

## 未核實值與外部前置

- Offering 名稱 `default`、entitlement 名稱 `premium` 目前只是候選；runtime 不得
  因候選名稱自行認定 dashboard 已完成。Offering 以 SDK 的 current offering 為
  起點，仍須通過四商品完整契約。
- `EXT-03`／`EXT-04` 尚需 RevenueCat／Google Play Console 唯讀證據：Android app、
  Play credential、`goog_` key、entitlement、四個 product／base plan、package、
  台灣價格、區域價格與 Pause Disabled。
- 本 tranche 不修改 RevenueCat、Google Play、GitHub Secrets、production 資料、
  migration、Edge Function 或任何 credential；不做真實扣款或 Store release。

## 實作順序與測試

1. 先加 failing tests：平台 key 矩陣、四商品逐列 exact mapping、缺一／重複／錯配
   全域 fail closed、拒絕 fuzzy/direct fallback。
2. 實作 platform-aware key selector 與 RevenueCat initialization fail-closed。
3. 抽出可獨立測試的商品契約與 replacement policy，再把 Provider／Paywall 購買
   路徑收斂為 Package-only。
4. 接通 purchase、restore、manage／cancel 與三種 Android replacement mode，
   補確認文案與原商店導向測試。
5. 更新 runbook／workflow contract，跑 focused tests、完整 Flutter tests、
   analyze、`git diff --check`；Flutter 與 artifact 命令全部在 WSL。
6. Luna 只修改 task-owned files；Codex 對 exact commit 主審。Payment 為 material
   R2，最終另做 Claude read-only challenge；最多兩輪修正／重審。

## Exit 與狀態語意

### M4 code candidate

- 平台 key、四商品、Package-only purchase、replacement mode、restore 與原商店管理
  契約完成。
- focused＋full tests、analyze 與 Android exact-SHA Build & Distribute 通過。
- exact commit 經 Codex 主審及 Claude 獨立審查，無未解 P0／P1／P2。

### M4 完成

除 code candidate 外，還需要 Eric 另行授權的 `EXT-03`／`EXT-04` 後台設定與真機
sandbox 證據：四個方案能顯示正確商店價格；新購、恢復、升級、降級、同級換週期、
取消與管理均回到正確 Google Play 帳號／商店，且 iOS 既有流程不回歸。在這些 live
gate 完成前，只稱 M4 code candidate，不稱付款功能已完整上線。

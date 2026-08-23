# M3 BILL-07 subscription store-state backfill（branch-only）

這份 runbook 只描述 migration 落地後的審查與 dry-run 流程；目前不代表 production 已執行。沒有 Eric 的明確核准，不得對 production 執行 backfill、reconciliation 或任何 `supabase db push`。

## 目的與安全邊界

- `subscription_store_states` 是 additive source-of-truth layer；既有 `subscriptions` aggregate 與 quota counters 保留。
- backfill 只接受 legacy row 已明確保存的 `store`（`app_store` / `play_store`）與 `started_at`。缺 store、缺時間、或 paid row 缺 product 會回報 ambiguous/missing 並跳過，不猜 iOS 或其他平台。
- backfill 寫入 `verification_source = 'legacy_backfill'`、`verification_status = 'unverified'`，不產生 paid entitlement，也不 reset quota。
- event id 是 legacy row 欄位的 deterministic hash；重跑應回 `duplicate`。任何已存在的 verified store row 由 atomic upsert 保護，不會被 legacy backfill 覆蓋；verified event 可以取代同 store 的 unverified backfill，即使 event time 較早。
- pending paid legacy 的 source upgrade 只在 read-time projection 暫時顯示，不能物化覆寫 baseline；free legacy 第一次遇到 verified source 才會記錄窄化的 `no_paid_legacy_baseline` auto marker。
- production migration、backfill、reconciliation 都維持 pending；這個分支不連 production DB、不使用真實 credentials。

## 先做 branch/local dry-run

1. 確認 migration 順序與 schema diff，並在 disposable local database 套用 migration；不要把 `supabase db push` 指向 production。
2. 只讀檢查 legacy provenance，先列出會被跳過的資料：

   ```sql
   SELECT user_id, tier, status, store, active_product_id, started_at,
          expires_at, revenuecat_environment
   FROM public.subscriptions
   WHERE store IS NULL
      OR store NOT IN ('app_store', 'play_store')
      OR started_at IS NULL
      OR (tier IN ('starter', 'essential')
          AND NULLIF(trim(active_product_id), '') IS NULL)
   ORDER BY user_id;
   ```

3. 在 local/staging-like disposable DB 以單一 user 先呼叫：

   ```sql
   SELECT *
   FROM public.backfill_subscription_store_state_from_legacy('<USER_UUID>');
   ```

   期待：明確來源只會新增 `unverified` row；缺 provenance 回報 `ambiguous_legacy_store`、`missing_legacy_event_at` 或 `ambiguous_legacy_product`。同一 UUID 再跑一次應為 `duplicate`，不能改變 legacy counters。

4. 先看 reconciliation diff，再決定是否需要人工處理：

   ```sql
   SELECT *
   FROM public.reconcile_subscription_store_state_diff('<USER_UUID>')
   WHERE differs IS TRUE OR reason <> 'no_verified_source';
   ```

   `no_verified_source` 代表尚無可驗證來源，不是付費授權；`verified_sources_not_effective` 代表 verified rows 都已過期/取消，legacy aggregate 若仍 paid 必須修正或調查；`aggregate_mismatch` 必須能指出 store、product、tier、status 或 expiry 差異。

5. 只有在 service-role 已取得「完整 RevenueCat CustomerInfo snapshot」並確認
   snapshot 覆蓋 App Store 與 Play 的 subscription map（包含明確沒有訂閱的店）後，
   才能準備 cutover。先用同一個 snapshot 的取得時間，把所有「有出現」商店的
   verified event 寫入 atomic store-state writer；接著對每個「沒出現」的商店呼叫
   absence writer。`present_stores` 與 `present_store_event_ids` 必須描述同一份完整
   snapshot，不能拿一般同步的暫時空回應來清除權益：

   ```sql
   -- 範例：完整 snapshot 只有 App Store，因此明確 tombstone Play Store。
   SELECT *
   FROM public.record_revenuecat_snapshot_absence(
     '<USER_UUID>',
     'play_store',
     '<REVENUECAT_SNAPSHOT_ID>',
     '<SNAPSHOT_OBSERVED_AT>',
     ARRAY['app_store']::TEXT[],
     '{"app_store":"<APP_STORE_EVENT_ID>"}'::JSONB,
     'production'
   );
   ```

   完全空的完整 snapshot 必須以同一個 snapshot id / observed time 分別呼叫
   `app_store` 與 `play_store`，兩次都傳 `ARRAY[]::TEXT[]` 與 `'{}'::JSONB`。
   若兩個 store 都 present（沒有 absence call），則在 present event 已寫入後
   額外呼叫一次 manifest writer，讓兩種情況都留下 immutable manifest：

   ```sql
   -- both-present snapshot：兩個 event 都必須先由 atomic writer 接受。
   SELECT *
   FROM public.record_revenuecat_snapshot_manifest(
     '<USER_UUID>',
     '<REVENUECAT_SNAPSHOT_ID>',
     '<SNAPSHOT_OBSERVED_AT>',
     ARRAY['app_store', 'play_store']::TEXT[],
     '{"app_store":"<APP_EVENT_ID>","play_store":"<PLAY_EVENT_ID>"}'::JSONB,
     'production'
   );
   ```
   tombstone 是 verified `free/expired` store event：比現有事件舊時會回 `stale`
   且不覆寫；較新的購買事件仍可正常取代它。每次證據另存 audit row，重送相同
   snapshot 是 idempotent，內容不同卻重用 snapshot id 則回 `snapshot_conflict`。

6. 所有 present event 與 absent tombstone 都處理完成、並重跑 diff 後，才能
   finalize cutover；單一非空 subscription entry 絕不能當成完整 coverage：

   ```sql
   SELECT *
   FROM public.finalize_subscription_store_state_reconciliation(
     '<USER_UUID>',
     '<REVENUECAT_SNAPSHOT_ID>',
     '<SNAPSHOT_OBSERVED_AT>',
     ARRAY['app_store']::TEXT[],
     '{"app_store":"<APP_STORE_EVENT_ID>"}'::JSONB,
     'migration-reviewer'
   );
   ```

   finalize 不接受只填 coverage 字串；snapshot id、observed time、present
   stores、event map 必須逐字匹配 immutable manifest，且兩個 store 各自都要
   是同 snapshot 的 verified event 或同 snapshot 的 audited absence/tombstone。
   錯 snapshot/time/event、漏 store、混 snapshot、future time、額外 store 都
   fail closed；驗證失敗維持 `pending`，保留較安全的 legacy paid aggregate。
   finalize 會在 user lock 下依所有 verified store rows 的 read-time winner 重算
   legacy entitlement，並以 canonical helper 同步寫入 billing_period，不會清除
   月/日 quota counters。

7. 若抽樣 diff 或後續事件證明 coverage 不完整，service-role 才可 rollback marker：

   ```sql
   SELECT *
   FROM public.rollback_subscription_store_state_reconciliation(
     '<USER_UUID>',
     'coverage_recheck'
   );
   ```

   rollback 會先用 reconciliation 保存的 baseline 還原 legacy aggregate，再撤銷
   cutover marker；不刪除 store-state evidence。重新 finalize 前要重新取得完整
   snapshot 並重跑 diff。

8. 驗證不變式：

   - 每個 user/store 最多一列，且 `event_id` / `event_at` 不為空。
   - 任何 verified row 在 backfill 前後完全相同；verified 取代 unverified 時只變更 provenance/state，不得因 stale guard 被擋。
   - backfill 不會讓 `monthly_messages_used`、`daily_messages_used`、reset timestamps 歸零。
   - mixed app/play 使用同一 user 時，effective winner 的 tier/product/store/expiry 來自同一列。
   - 一般 `sync-subscription` 的空/暫時性 snapshot 不會建立 absence；只有上述完整
     snapshot 流程可以寫 tombstone，且 audit row 的 snapshot id、時間、present
     stores 與 event ids 必須一致。

## Production pending checklist

只有完成 migration review、抽樣 diff、來源 ambiguity triage、quota counter check 與 rollback/incident owner 確認後，才可由被授權的人另行安排 production 操作。任何 production 操作需記錄 migration SHA、dry-run 統計、跳過原因、duplicate/preserve_verified 數量與 reconciliation diff；本分支不執行該操作。

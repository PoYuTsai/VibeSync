# Paywall / Quota 加固待辦（2026-07-02 拍板）

> 來源：夥伴 Codex 掃描報告（六 Edge Functions 扣費路徑）＋ CC 三路查核（逐條驗證全 CONFIRMED＋反掃補出 webhook/sync 側遺漏）。
> 全部屬高風險區：每批獨立 commit、出 review packet 由 Eric 路由 Codex 雙審，APPROVED 才算 dogfood safe。
> 建議執行順序：A → B → D → C。

## Batch A — 小 diff 立即修（analyze-chat）

1. **stream retry fallback 雙重扣費**：legacy 扣費點 `analyze-chat/index.ts:7493` 加 `&& !isStreamRetryMode` guard。
   背景：`isStreamRetryMode`（index.ts:4498）跳過全部 preflight＋overcharge 閘（4867/4904/5662/5694/5758），stream gate 不放行時 fallback 到 legacy（7034 `stream_request_fell_back_to_legacy`）會二次扣費；legacy 查不到 `analysis_stream_runs.charged_at`。
   方向：原始 stream 已扣費，fallback 給結果但不再扣。
2. **TIER_MONTHLY_LIMITS 查表過 normalizeTier**：index.ts:4780-4781、4821-4822、4996-4997 三處 raw `sub.tier` 查表，異常字串會 fallback 成 free 30 提早 429。normalizeTier（index.ts:516-518）已存在，套上即可。
3. **失實註解修正**：index.ts:6244-6245 宣稱 increment_usage 會 RAISE 防 quota race——該保護不存在，註解改對（真保護在 Batch C）。
4. **TEST_EMAILS 去重**：index.ts:4351 自帶副本改 import `_shared/quota.ts:30`（值目前一致，防漂移）。

測試：stream retry + gate 關閉 fallback 情境、tier 異常字串查表。deploy 記得 `--no-verify-jwt`。

## Batch B — webhook / sync 加固（優先度高於 C）

理由：C 防「並發超限多付 AI 成本」（低機率小損失），B 防「付費用戶無聲掉 tier／額度被重置」（RC 重送事件是常態，不需攻擊者），且直接對應鐵則「付費 tier 不得因非權威訊號降級」。

1. **晚到 EXPIRATION 蓋掉新訂閱**（P1）：`revenuecat-webhook/index.ts:654-659` 盲 update，更新前必須比對事件 `event_timestamp_ms` / `expiration_at_ms` 與 DB `expires_at`，過期事件不得覆寫較新狀態。
2. **webhook 重放清空額度**（P1）：`revenue_events` 有 `UNIQUE(revenuecat_event_id)` 但 subscriptions 更新沒有去重——重放 INITIAL_PURCHASE 會把 `monthly_messages_used`/`daily_messages_used` 歸零（index.ts:614-617、672-673）。補 event_id 去重。
3. **sync-subscription revenueCatAppUserId 邊界**（P2，先驗證再定修法）：`sync-subscription/index.ts:282-330` 接受 client 傳的 appUserId 查 RC entitlements。**動手前先人工確認**：若 victim tier 會寫進請求者自己的 row ＝ 提權漏洞必修；若僅回傳 ＝ 資訊洩露，candidates 收斂為認證的 `user.id`。
4. 順手項（P3，可選）：webhook_logs 無去重、Bearer token 非 constant-time 比較。

## Batch C — 扣費原子化（migration＋多 Edge，需先寫 invariants＋failure matrix）

樣板：`claim_practice_profile_draw`（migrations/20260626120000_practice_profile_draw_events.sql:150-192，全 codebase 唯一交易內 FOR UPDATE 驗上限的路徑）。

1. **increment_usage 改造**：交易內 FOR UPDATE＋驗月/日上限＋超限 RAISE（現版 20260316_z_fix_service_role_policies.sql:50-66 只擋非正數）。
2. **reset 條件化**：coach-chat index.ts:107-137、coach-follow-up index.ts:128-165、analyze-chat index.ts:4639-4661、check_and_reset_usage RPC——全是無條件 UPDATE=0，跨日/月邊界會覆寫並發請求剛扣的額度。改為條件化或搬進 RPC。
3. **coach-follow-up deductCredit 補重查**：index.ts:419-432 裸呼叫 RPC，對齊 coach-chat index.ts:341-390 的 fetchSubscription＋applyResetsIfNeeded＋checkQuota。

鐵則：**絕不 `supabase db push`**；MCP `apply_migration` 目標式套用＋帳本 version 對齊本地檔名。注意既有 migration 版本號分歧未對齊（repo 20260626120000 vs prod ledger 20260626064403）。

## Batch D — Eric 已拍板（2026-07-02）

1. **D1 免費釐清加額度前提**：釐清豁免判定在 checkQuota 之前（coach-chat/index.ts:273-282），且次數純信 client（clarification_policy.ts:8-14、schemas.ts:74）。拍板＝不做 server ledger；改為 **checkQuota preflight 恆跑**，釐清仍不扣費但額度歸零者直接 429/paywall。殘餘風險（有額度者偽造 turns 多蹭免費釐清）＝已知取捨，註記即可。
2. **D2 第 4 輪扣費必須真 AI 生成**：拍板原則＝**「扣 1 則 ⇔ AI 真正生成的回覆」**；3 輪是釐清上限非固定流程，輸入明確就直接正式建議＋扣費。修法：移除 `enforceClarificationLimit` 的模板＋`costDeducted:1`（generation.ts:205-245），改為帶「禁止再釐清、必須給正式建議」約束重新生成——成功→扣 1，失敗→走既有不扣費 fallback（generation.ts:278-296）。
3. **D3 時區統一實作、不統一產品節奏**：analyze-chat index.ts:4638-4661 本地時間 `toDateString()` 比較改用 `_shared/quota.ts` UTC helpers（88-100）；文案「明天會自動恢復」改「每天早上 8 點恢復」（Flutter 端）；practice 台北 12:00 抽卡窗口是產品節奏，保留不動。
4. **D4 刪 booster 死代碼**：`lib/features/subscription/domain/entities/message_booster.dart`、`presentation/widgets/booster_purchase_sheet.dart` 及唯一入口函式，零引用零 server 邏輯，直接刪（git history 可復原）。

## 已確認沒問題（夥伴報告驗證過，不重掃）

限額表四處一致；「成功才扣費」全線成立；quick/stream 原子 RPC＋overcharge idempotent claim；付費 tier 降級保護（RC refresh／scheduled-downgrade／free-snapshot）。
已降級不處理：購買後 sync 失敗信任本地 tier（server 扣費看 DB tier，僅 client 顯示問題，P3）；429 重試無 jitter（P3）。

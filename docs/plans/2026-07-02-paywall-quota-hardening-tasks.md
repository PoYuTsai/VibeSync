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

### Batch C 實作設計（2026-07-02 定稿，動碼前 invariants＋failure matrix）

**Invariants（全批必守）**

- I1 扣 1 則 ⇔ AI 真生成（Batch D 鐵則不得倒退）：新增的超限 RAISE 只會「少扣＋拒發結果」，絕不多扣。
- I2 counters 永不超過該 tier 上限（有帶 limits 的扣費路徑）；RAISE 時整筆交易 rollback，無半扣。
- I3 上限值的唯一權威在 Edge（`_shared/quota.ts`），SQL 不複製 pricing 表（`check_and_reset_usage` 的 hardcode CASE 是既有 legacy，不擴散）。
- I4 reset 只允許「第一個跨窗口的請求」歸零一次；後到者 CAS 失敗即放棄，不得覆寫已發生的扣費。
- I5 付費 tier 不因本批任何失敗路徑降級（本批不碰 tier 欄位）。
- I6 向後相容：舊 2-arg 呼叫（三個 wrapper RPC：create_charged_analysis_run／charge_stream_analysis_run／practice settle）行為不變（無上限檢查、只多了 row lock 串行化）。

**C1 設計**：DROP 舊 `increment_usage(uuid, integer)` 再建 4-arg（`p_monthly_limit`/`p_daily_limit` DEFAULT NULL）——不能只 CREATE OR REPLACE，否則新舊 overload 並存、2-arg 呼叫產生 ambiguity。函式體：`SELECT … FOR UPDATE` 鎖 subscriptions row → limits 非 NULL 時月先日後驗 `used + p_messages > limit` → 超限 `RAISE 'QUOTA_EXCEEDED_MONTHLY'/'QUOTA_EXCEEDED_DAILY'`（Edge 以 message.includes 偵測，同 practice draw 慣例）→ 更新 counters＋users.total_analyses。row NOT FOUND 保留現版 silent no-op（現版 UPDATE 0 rows 同義；所有呼叫點前面都有 self-heal）。

**Failure matrix（C1 charge 點）**

| 情境 | 現版行為 | 新版行為 |
|------|----------|----------|
| 並發 N 請求同時過 preflight、額度只剩 1 | N 筆全扣、counters 超上限 | FOR UPDATE 串行化，第 1 筆扣到上限，其餘 RAISE→429，counters 封頂 |
| RAISE 後 | — | 整筆 rollback（含 wrapper RPC 內的 run insert），無半扣；該次生成成本已花＝既知取捨（與 coach-chat 既有 post-generation 429 同語義） |
| 跨午夜邊界：Edge 已 reset、RPC 讀到新窗口 | 正常 | 正常 |
| 跨午夜邊界：請求橫跨午夜、row 仍舊窗口 | 照扣 | 可能誤 RAISE（用舊窗口 used 驗新請求）＝極窄殘餘，Edge 呼叫前一律先 applyResets，接受 |
| subscription row 不存在 | UPDATE 0 rows silent | 同樣 silent no-op（行為保留） |
| 舊 2-arg 呼叫（wrapper RPC） | 無上限檢查 | 無上限檢查（NULL limits），僅多 row lock |

**C2 設計**：CAS 條件化 reset——`applyResetsIfNeeded` 回傳舊 `daily_reset_at`/`monthly_reset_at`；persistResets／analyze-chat inline 改成 daily、monthly 各自獨立 UPDATE，WHERE 加 `reset_at = 舊值`（舊值 null 用 IS NULL）。CAS 失敗＝別的並發請求已 reset→不覆寫（保住它剛扣的額度），本請求繼續用記憶體中歸零值做 preflight（可能低估 used，超限由 C1 charge 點兜底）。`check_and_reset_usage` RPC 無 live 呼叫者（client 已 REVOKE、Edge 不呼），同 migration 補 UPDATE WHERE 重複窗口條件除 TOCTOU，不刪（舊環境相容）。

**C3 設計**：coach-follow-up `deductCredit` 對齊 coach-chat——重查 sub＋applyResets＋checkQuota＋RC refresh 一次，過門檻才呼 RPC（帶 limits）；新 `CoachFollowUpQuotaExceededError` 讓 generation.ts 映射 429（現在任何 deduct 失敗都是 500）。coach-chat／analyze-chat 兩直呼點（opener 5240、legacy 7555）同步帶 limits＋QUOTA_EXCEEDED→429 映射。

**範圍外（記入 review packet 殘餘）**：三個 wrapper RPC 簽名不改、不傳 limits——quick/stream/practice 路徑維持 preflight-only 上限防護（改簽名＝三份 migration＋三處 Edge 呼叫點連動，另案評估）；`analyze-chat/rate_limiter.ts` 整個模組零 live 引用（不只 reset 死碼），本批直接刪檔。

## Batch D — Eric 已拍板（2026-07-02）

1. **D1 免費釐清加額度前提**：釐清豁免判定在 checkQuota 之前（coach-chat/index.ts:273-282），且次數純信 client（clarification_policy.ts:8-14、schemas.ts:74）。拍板＝不做 server ledger；改為 **checkQuota preflight 恆跑**，釐清仍不扣費但額度歸零者直接 429/paywall。殘餘風險（有額度者偽造 turns 多蹭免費釐清）＝已知取捨，註記即可。
2. **D2 第 4 輪扣費必須真 AI 生成**：拍板原則＝**「扣 1 則 ⇔ AI 真正生成的回覆」**；3 輪是釐清上限非固定流程，輸入明確就直接正式建議＋扣費。修法：移除 `enforceClarificationLimit` 的模板＋`costDeducted:1`（generation.ts:205-245），改為帶「禁止再釐清、必須給正式建議」約束重新生成——成功→扣 1，失敗→走既有不扣費 fallback（generation.ts:278-296）。
3. **D3 時區統一實作、不統一產品節奏**：analyze-chat index.ts:4638-4661 本地時間 `toDateString()` 比較改用 `_shared/quota.ts` UTC helpers（88-100）；文案「明天會自動恢復」改「每天早上 8 點恢復」（Flutter 端）；practice 台北 12:00 抽卡窗口是產品節奏，保留不動。
4. **D4 刪 booster 死代碼**：`lib/features/subscription/domain/entities/message_booster.dart`、`presentation/widgets/booster_purchase_sheet.dart` 及唯一入口函式，零引用零 server 邏輯，直接刪（git history 可復原）。

## 已確認沒問題（夥伴報告驗證過，不重掃）

限額表四處一致；「成功才扣費」全線成立；quick/stream 原子 RPC＋overcharge idempotent claim；付費 tier 降級保護（RC refresh／scheduled-downgrade／free-snapshot）。
已降級不處理：購買後 sync 失敗信任本地 tier（server 扣費看 DB tier，僅 client 顯示問題，P3）；429 重試無 jitter（P3）。

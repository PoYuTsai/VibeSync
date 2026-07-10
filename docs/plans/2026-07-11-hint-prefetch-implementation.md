# Hint 預產 Prefetch Implementation Plan

> **For Claude/Codex:** 依 task 順序執行；每個 task 先紅後綠、每個 commit 只含一個 concern。
> 設計真相源：`docs/plans/2026-07-11-hint-prefetch-design.md`。本檔只把已拍板設計展開成可施工與可出貨的步驟，不重開產品方案。

**Goal:** 在 Game 與新手模式的 AI 回覆落地後，背景預產一次 Hint；使用者真正點 Hint 時以同一 requestId replay，才原子扣 quota、增加 Hint 次數並標記已結算。預產全敗時絕不寫入 fallback 快照，最差退回今天的現場生成行為。

**Architecture:** 複用現有 `sessionId + aiReplyCount` requestId 指紋，但把新流程的權威快照提升成 bounded per-request ledger：`practice_hint_requests` 以 `(user_id, session_id, request_id)` 為 key，單場最多 5 筆已消費＋1 筆未消費；現有 `last_hint_*` 單槽只保留舊 Edge 相容，不再當新流程的計費真相源。另把「物理扣 quota」和「已正式消費／已計 Hint 次數」拆成兩個正交狀態。DB RPC 負責 session row lock 下的 exactly-once 結算；Edge 負責 replay 分流、成功生成與 fallback 抑制；Flutter controller 只負責背景開火、同 requestId 與在途序列化，不持久化預產內容。

**Tech Stack:** Flutter/Riverpod、Supabase Edge Function（Deno/TypeScript）、Postgres PL/pgSQL、Hive 現有加密 settings box（只複用既有 pending requestId，不改 schema）。

**風險分級:** quota／計費／429／Edge response schema 高風險。實作與部署必須走 Codex 標準 review＋adversarial review；兩審皆 `APPROVED`（0 P0/P1/P2）前，不得套 prod migration、發布 client 或宣稱 dogfood safe。

**實作前工程確認（需 Eric 明確接受）:** 設計稿原本假設沿用 `last_hint_*` 單槽即可防重扣；本輪 plan adversarial audit 證明，A request settle 後若 B request 覆寫單槽，A 的掉包重試會失去已扣證據。為了真的滿足「同 requestId 不重扣」，本計畫把權威快照改為 bounded per-request ledger，舊單槽只留相容；同一輪也必須把 practice-chat 的 quota reset＋check＋increment 收進同一 subscription row lock/transaction，否則 reset 仍可能抹掉並發扣費。這不改消費才扣、Game＋新手同上等產品決策，但屬計費儲存架構硬化；未確認前不得開 Task 1，也不得退回單槽卻仍宣稱 exactly-once。

---

## Scope

**In scope**

- Game＋新手模式共用的 Hint prefetch。
- 消費才扣、消費才計 Hint 次數、同 requestId exactly-once。
- per-request migration ledger marker、`record_practice_hint` 參數、原子補扣／丟棄 RPC。
- `fired / hit / miss / failed` 固定欄位 telemetry。
- server kill switch、DB → Edge → client 的分段 rollout 與 forward-fix rollback。

**Out of scope**

- 已在設計稿否決的替代方案與等待 7/17 日誌分型；本輪均不重開。
- Hint UI、提示文案、Hive adapter/schema、fallback 內容、Game/Beginner prompt。
- Bruce 三案的 TestFlight dogfood（抽卡去重／OCR 動畫／列表摺疊）。

## 現況錨點（實作前先確認行號未漂移）

- Flutter AI 回覆落 state：`lib/features/practice_chat/data/providers/practice_chat_providers.dart:958-1067`。
- Flutter requestId 指紋／生命週期：同檔 `:450-480`；正式 Hint：`:1138-1310`。
- API body：`lib/features/practice_chat/data/services/practice_chat_api_service.dart:505-539`。
- Edge Hint 主流程：`supabase/functions/practice-chat/handler.ts:1513-1921`。
- fallback 建構：`handler.ts:1772-1806`；`hint.ts:667-767`（本案不改 fallback 本體）。
- 最新現役 Hint RPC 真相源：`supabase/migrations/20260708120000_practice_game_mode.sql:159-304`。**不得從 20260703 beginner-only 舊版複製。**
- 原子 quota helper：`supabase/migrations/20260702120000_increment_usage_atomic_quota.sql:27-73`（須傳 monthly/daily limits，不能走 DEFAULT NULL）。
- practice-chat 目前 reset counters 是獨立 UPDATE：`supabase/functions/practice-chat/handler.ts:1400-1435`。只加 reset_at CAS 仍不夠，因 increment 不更新 reset_at；本案必須讓 DB 在 subscription row lock 內重判 reset，再做 limit check＋increment。

## 不變量與兩軸語意

`p_charge_quota` 只代表是否真的增加 subscription usage；新增的 `p_charged` 與 `practice_hint_requests.charged` 代表「這份快照是否已被使用者正式消費、`hint_count` 是否已結算」。名稱雖沿 handoff 使用 charged，migration 註解與測試必須鎖死它其實是 settled/consumed，不能拿 `did_charge` 推導。

| 情境 | `p_charge_quota` | `p_charged` | quota | `hint_count` | replay marker |
|---|---:|---:|---:|---:|---:|
| 一般帳號正式成功 | true | true | +1 | +1 | true |
| 測試帳號正式成功 | false | true | +0 | +1 | true |
| 正式 fallback | false | true | +0 | +1 | true |
| prefetch 成功 | false | false | +0 | +0 | false |

鐵則：

1. `p_charge_quota=true && p_charged=false` 是非法狀態，RPC 必須拒絕。
2. ledger `charged=false` 只能由「通過 parse＋visible guard 的成功 prefetch」產生；因此不需另存 fallback flag。
3. 舊 `last_hint_request_id/result` snapshot backfill 進新 ledger 時一律 `charged=true`，避免追溯重扣既有 fallback／測試帳號結果。
4. prefetch 全敗必須 release latch、回錯誤、`record_practice_hint` 呼叫數為 0；絕不建立罐頭 replay。
5. 正式消費第一次完成後，之後同 requestId 從 per-request ledger 回同一份 finalized snapshot；後續不同 requestId 不得覆寫它。
6. exactly-once 只以 exact requestId 判定；同一 AI 回覆後使用者可合法再點第二次 Hint，rotate 後的新 requestId 必須 fresh generate＋再計一次，不能跨 ID canonical replay。

## Failure matrix（實作與雙審共同驗收表）

| 情境 | 權威結果 |
|---|---|
| Beginner／Game prefetch 成功 | 模型一次；寫未結算成功快照；quota/count 不動 |
| 任意 `prefetch:true` success/retry（含惡意 client） | HTTP 只回 opaque ack，絕不回 replies/coaching/result；內容首次可見只能經 formal settle |
| prefetch timeout／守門／格式兩次全敗 | release latch；不建 fallback、不 record、不扣、不計 |
| prefetch 被 mode/unlock/hint gate/quota/rate limit 擋 | 不進 provider 或不 record；client 靜默 |
| 同 requestId prefetch retry | ledger 保留未結算快照，但 HTTP 只回 opaque ack；不得視為正式消費或洩漏內容 |
| 不同 requestId prefetch 遇既有未結算快照 | server short-circuit，避免免費模型風暴；正式 fresh request 不被此規則卡住 |
| 正式點擊命中未結算快照 | 不打模型、不吃 model rate limit；原子補扣＋計次＋標記，再回原內容 |
| 同 ID 正式並發／掉包重試 | 最多扣一次、計一次；per-request row 保留 finalized result，不受後續 request 覆寫 |
| 同 aiCount 的第二個正式 Hint（不同 ID） | 視為合法新意圖，fresh generate＋再計一次；不能回第一份內容 |
| consume 前 quota 被其他請求耗盡 | 鎖內 429；quota/count/marker 全 rollback；不回免費內容 |
| consume 前 Hint cap 被其他裝置吃滿 | 403；不扣、不計、不標記 |
| consume 前 session 被其他請求推到 AI reply cap | 409；不扣、不計、不標記 |
| test account consume | 不扣 quota，但 count +1、marker=true，後續不重計 |
| 正式 fallback replay | cost=0、已計一次、marker=true；不得事後補扣 |
| claim-level race 才看到未結算 snapshot | 仍走同一補扣 RPC；不能直接 return stored result |
| prefetch 生成中 chat 已推進 ai_count | record 驗 claim 當下 ai_count，判 stale 後 release；不把舊內容存成新 turn |
| settle RPC requestId/result mismatch | fail closed、零扣；不得在同一 request 自動轉 fresh generation |
| fresh 正式 request 沒有可用 prefetch | 完整維持今日 claim → generate → formal fallback/record 行為 |
| 點擊時任何 session Hint prefetch 在途 | client 先 await；點擊 intent 仍是同 session/aiCount/generation 才發正式 request，換場則零 dispatch |
| autoDispose/App 重建時舊 prefetch 仍在 server | Future 無法恢復；沿用 Hive requestId，首個 formal 可收 in-flight，保留同 ID後重試 replay |
| 同局多次 AI reply但未正式點 Hint | 最多一次預產嘗試；舊指紋自然作廢但不重產 |
| App/controller 重建 | RAM gate 重置、最多多一次嘗試；既有 pending store 仍防同指紋雙扣 |
| Standard／hint cap／session complete／ended | 不 fire prefetch |
| telemetry | 可分 fired/hit/miss/failed；現有 fallback 事件不改；零 transcript/prompt/hint 文字 |
| flag=false＋既有未結算 row | 原子 discard 未扣 row，再走 fresh formal；若競態中已 settle，回 finalized replay |
| quota reset 與 settle/record 併發 | DB 同一 row lock 內依序 reset→limit check→increment；任何外層 stale reset 不得抹掉已 commit usage |

---

## Task 0：建立安全施工面與 baseline

**Files:** Read only。

1. `git status --short --branch`，記錄並保留既有 `pubspec.lock` dirty；全程禁止 `git add .`。
2. 從最新 `main` 建 `codex/hint-prefetch-impl`。此 branch push 不會觸發 main-only Edge deploy。
3. 逐檔跑**現有** baseline：`validate_test.ts`、`migration_source_test.ts`、`index_test.ts`、`hint_test.ts`、`quota_decision_test.ts`、`model_rate_limit_source_test.ts`、兩個 Flutter unit test 與既有 pending-store/widget regression。Task 1/2 尚未建立的 `hint_prefetch*_test.ts` 不屬 baseline；不要把整目錄 `deno test practice-chat/` 當唯一證據。交接記載的 `handler.ts:323 setTimeout` type-check 髒若重現，原樣記錄，不順手清別案。
4. 確認 prod migration ledger 至少已有 `20260710120000_practice_debrief_idempotency.sql`，但本 task 不動 prod。

**Commit:** 無。

## Task 1：Migration TDD——per-request ledger、record 兩軸、原子補扣／丟棄 RPC

**Files**

- Create: `supabase/migrations/20260711120000_practice_hint_prefetch.sql`
- Create: `supabase/functions/practice-chat/hint_prefetch_migration_test.ts`
- Regression: `supabase/functions/practice-chat/migration_source_test.ts`
- Regression: `supabase/functions/delete-account/index.ts`（唯讀 source assertion；預期不改檔）

### 1.1 先寫 source-contract 紅燈

測試至少鎖住：

- `practice_hint_requests` 以 `(user_id, session_id, request_id)` 為 PK，含權威 `claimed_ai_count / is_prefetch / state / result / charged / created_at / updated_at`；state 限 `generating|prefetched|settled`，各態的 result/charged 組合用 CHECK 鎖死。`claimed_ai_count` 新 row 必須 1..20；只有 legacy settled backfill 可為 NULL。
- partial unique index 鎖住每個 `(user_id, session_id)` 最多一筆 `state='prefetched'`；session row lock 是流程保護，DB index 是最後不變量。
- table 以 `(user_id, session_id)` composite FK 指向 `practice_chat_sessions` 並 `ON DELETE CASCADE`；RLS 開啟、無 client policy，避免 delete-account 後殘留 AI Hint 內容或反向擋住 session 刪除。
- table 只存 request metadata 與現行 Hint response snapshot，不存 transcript/prompt/raw error；COMMENT 與 source test 鎖住隱私邊界。settled 最多 5＋current prefetched 最多 1，不能變成無界 Hint 歷史表。
- migration 把現有每個 session 的 `last_hint_request_id/result` 以 `state=settled, charged=true, claimed_ai_count=NULL` backfill 進新 ledger；legacy row 只支援 exact requestId replay，不得拿 migration 當下 ai_count 冒充原回合。
- 先 DROP 現役 claim 4-arg、record 6-arg signature；新 claim 尾加 `p_prefetch BOOLEAN DEFAULT FALSE`，新 record 尾加 `p_charged BOOLEAN DEFAULT TRUE`、`p_monthly_limit INTEGER DEFAULT NULL`、`p_daily_limit INTEGER DEFAULT NULL`、`p_max_replies INTEGER DEFAULT NULL`，讓舊 Edge named-arg 呼叫仍等同 formal settled。
- claim replay 只以 exact requestId 回傳 `stored_result / stored_charged`；fresh claim 在 session lock 內建立 `generating` row並保存當下權威 `claimed_ai_count`。同 aiCount 不同 ID 仍是合法新 Hint；claim 仍支援 `beginner`＋`game`、拒絕 standard。
- `record_practice_hint`：未結算分支還要驗 claim row 的 `is_prefetch=true`，不 increment usage、不增 count；正式分支驗 `is_prefetch=false` 才依兩軸處理；兩分支都清 latch，client flag 錯接不能穿透 DB invariant。
- migration 切換瞬間可能已有舊 RPC claim 完成、模型仍在跑但尚無 request ledger row；source/handler test 鎖住 legacy in-flight formal 可在「latch存在＋p_charged=true」時補建 settled row，prefetch `p_charged=false` 則永遠要求新 claim row，不能走此相容洞。
- 新 RPC `settle_prefetched_practice_hint` 有 session `FOR UPDATE`、requestId/result 驗證、already-settled 分支早於 cap/quota、4-arg `increment_usage`、同交易更新 count＋marker＋final snapshot。
- 新 RPC `discard_prefetched_practice_hint` 先鎖 session row，只刪除 matching 且尚未結算的 row；若競態中已 settled，回 authoritative result，絕不清已扣證據。
- `release_practice_hint_generation` 尾加 optional requestId：新 Edge 失敗時除清 session latch，也刪掉自己仍是 `generating` 的 row；舊 Edge 2-arg 呼叫清該 session 唯一 generating row＋latch，避免 migration→deploy 窗口留下殘骸。
- 新 helper/RPC `prepare_practice_subscription_usage` 先 `SELECT subscriptions ... FOR UPDATE`，在鎖內依 UTC day/month 重判並套 reset，回 authoritative counters；record/settle 在**同一 transaction**呼叫它後才做 limit check＋`increment_usage`。Edge 外層 reset 也改呼叫此 RPC，不能再直接 UPDATE counters。
- SECURITY DEFINER 輸入 guard 鎖住：boolean 不得 null、maxHints 1..5、maxReplies 1..20、requestId 長度；record limits 只能「兩者皆 null（舊 Edge）」或「兩者皆正數」，settle limits 必須兩者皆正數。
- RPC grants 僅 `service_role`，結尾 `NOTIFY pgrst, 'reload schema'`。
- 整份 migration 可安全重放：table/index/constraint 以 `IF NOT EXISTS` 或 catalog guard，backfill `ON CONFLICT DO NOTHING`，函式以精確 signature DROP＋CREATE 重建，不留下 overload。
- migration test 同時讀 `supabase/functions/delete-account/index.ts`，鎖住現行會刪 `practice_chat_sessions`；配合 composite FK cascade，帳號刪除不需另寫一條容易漂移的 child-table delete。

Run（Expected: FAIL，migration 尚不存在）：

```powershell
deno test --quiet --allow-read supabase/functions/practice-chat/hint_prefetch_migration_test.ts
```

### 1.2 寫 additive migration

以 `20260708120000_practice_game_mode.sql` 的現役 Game-compatible claim/record 為基底：

1. 新增 `practice_hint_requests` ledger；每場 settled row 受 Hint cap 約束最多 5 筆，server 另保證最多 1 筆 `prefetched`。現有 `last_hint_*` 只作舊 Edge compatibility mirror；prefetch row 不寫進單槽，避免它成為新計費真相源。FK cascade 把帳號／session 刪除納入同一生命週期。
2. 重建 `claim_practice_hint_generation`，保留舊 named args並讓 `p_prefetch` default false：
   - exact requestId 的 settled/prefetched row才 replay。
   - fresh claim 先鎖 session，再插入 `generating` row並保存 claim 當下 `ai_count`；record 不得重新猜當前回合。
   - exact generating row＋有效 latch 維持 `practice_hint_in_flight`；latch 已 stale 才 takeover，並把 claimed_ai_count 重設為當下權威值，不能讓 crash 殘骸永久卡住。
   - prefetch fresh claim 前，刪除 `claimed_ai_count < current ai_count` 的 stale prefetched row；若仍有 current pending就拒絕。formal 不做跨 ID canonicalize，保留同回合多次 Hint 能力。
3. 重建 `record_practice_hint`：
   - `p_charged=false` 強制 `p_charge_quota=false`、requestId 非空、result 為 object、claim row `is_prefetch=true`；只清 latch、存成功快照與 marker=false，`hint_count` 原值不動。
   - `p_charged=true` 要求 formal claim `is_prefetch=false` 並維持現行為；fallback/test account 可 `p_charge_quota=false` 但仍 count +1、marker=true。
   - 新 Edge 傳 monthly/daily limits，扣費時呼叫 4-arg `increment_usage` 做鎖內上限複檢；舊 Edge defaults null 維持舊行為。
   - 新 Edge另傳 `p_max_replies`，row lock 內重驗 session 未達 cap；舊 Edge null 維持現狀。
   - 有 requestId 時只能更新自己已 claim 的 `generating` row，並驗 `claimed_ai_count == session.ai_count`；聊天已前進則回 `PRACTICE_HINT_STALE`，handler 用帶 requestId 的 release 清 latch/generating row，絕不把舊 turn 結果標成新 turn。
   - 唯一相容例外：migration 套用當下舊 Edge 已用舊 RPC claim、session latch 尚在但 ledger row 尚未建立；`p_charged=true` formal 可補建 settled row。`p_charged=false` prefetch 不得使用例外。補 migration-window fixture 防部署中斷單。
   - 以 transaction 內 subscription counters 覆寫 `costDeducted / hintUsedCount / monthlyRemaining / dailyRemaining`，寫 exact per-request row並回傳 authoritative `stored_result`。只有 formal `p_charged=true` 才同步更新舊 `last_hint_*` mirror；prefetch 不寫單槽。
4. 新增 `settle_prefetched_practice_hint(user, session, requestId, chargeQuota, maxHints, maxReplies, monthlyLimit, dailyLimit)`：
   - row lock 後驗 session/mode/request/result；marker=true 直接回 finalized snapshot，早於 cap/quota。
   - marker=false 才複檢 Hint cap、AI reply cap、原子 quota、count +1、marker=true；用 transaction 內 counters finalize snapshot。
   - quota RAISE 讓整筆 transaction rollback，不需要 refund RPC。
5. 新增 `discard_prefetched_practice_hint`：flag-off formal 使用；只在 exact row 尚未結算時刪除，已結算則回 replay，讓 caller 不會改走第二次生成。
6. 重建 `release_practice_hint_generation`：新 optional requestId只刪自己的 generating row；2-arg legacy 清該 session generating row＋latch，維持舊 worker 可恢復。
7. 新增 `prepare_practice_subscription_usage` 並讓 record/settle 在 transaction 內先呼叫：鎖 subscription row→重判/套 daily+monthly reset→再以 reset 後 counters做 limit check/增量→回 counters。不要把 reset 交給 Edge 先算後寫。
8. DROP 舊 signature 防 PostgREST overload ambiguity；REVOKE/GRANT/NOTIFY 完整。

Run（Expected: PASS）：

```powershell
deno test --quiet --allow-read supabase/functions/practice-chat/hint_prefetch_migration_test.ts
deno test --quiet --allow-read supabase/functions/practice-chat/migration_source_test.ts
```

**Commit（只 stage 上述 migration＋tests）：** `Hint 預產補上原子消費結算 RPC`

## Task 2：Request contract TDD——保留 true／false／missing 三態

**Files**

- Modify: `supabase/functions/practice-chat/validate.ts`
- Modify: `supabase/functions/practice-chat/validate_test.ts`
- Create: `supabase/functions/practice-chat/hint_prefetch.ts`
- Create: `supabase/functions/practice-chat/hint_prefetch_test.ts`

### 2.1 Validate 紅燈

新增測試：

- missing → `prefetch` 保持 undefined（舊 client，不污染 miss telemetry）。
- explicit false → false（新 client 的正式請求）。
- true → true，且只允許 `mode=hint`＋合法 requestId。
- string/number/null、chat/debrief true、true 但無 requestId → 400 validation error。

### 2.2 抽純決策 helper

`hint_prefetch.ts` 只處理固定狀態，不碰 transcript：

- replay 分型：miss／settled replay／unsettled prefetch replay／unsettled formal consume。
- record policy：formal paid、formal test、formal fallback、prefetch 四態。
- telemetry outcome/reason allowlist；未知 reason 收斂為 `unknown`。
- kill switch：只有 `PRACTICE_HINT_PREFETCH_ENABLED === "true"` 才允許背景生成；缺值預設關閉，正式 Hint 永遠不受影響。

Run：

```powershell
deno test --quiet --allow-read --allow-env supabase/functions/practice-chat/validate_test.ts
deno test --quiet supabase/functions/practice-chat/hint_prefetch_test.ts
deno check supabase/functions/practice-chat/validate.ts
deno check supabase/functions/practice-chat/hint_prefetch.ts
```

**Commit:** `定義 Hint 預產請求與結算狀態契約`

## Task 3：Edge handler TDD——replay 分流、fallback 抑制、權威結算

**Files**

- Modify: `supabase/functions/practice-chat/handler.ts`
- Modify: `supabase/functions/practice-chat/index_test.ts`
- Modify: `supabase/functions/practice-chat/model_rate_limit_source_test.ts`
- Regression: `supabase/functions/practice-chat/hint_test.ts`
- Regression: `supabase/functions/practice-chat/quota_decision_test.ts`

### 3.1 先補 handler 紅燈矩陣

在既有 Hint 測試區擴充 fake ledger/RPC helpers，至少覆蓋：

1. Beginner、Game prefetch 成功：provider 1 次，record 帶 `p_charge_quota=false / p_charged=false`，count/quota 不動。
2. Beginner、Game timeout/guard/格式全敗：release 1 次、record 0 次、沒有 fallback snapshot。
3. prefetch disabled、game unlock、hint gate、quota、model rate 擋下；都不落 snapshot。
4. exact requestId marker=false＋formal：settle RPC 1 次、provider/rate-limit/claim/record 0 次，回 finalized response。
5. matching marker=false＋prefetch retry：不 settle、不 provider，只回 opaque ack，response 不含任何 Hint 內容。
6. matching marker=true：維持現行 replay，cap/quota 後來耗盡仍可回。
7. claim-level replay marker=false：也走 settle；marker=true 直接 replay；兩者都不得呼叫 model rate limiter。fresh claim 被 rate limit 時必 release exact generating row。
8. settle/record 的 `QUOTA_EXCEEDED_MONTHLY|DAILY` 映射 429；transaction rollback 後不回內容。record 失敗仍 release claim latch；AI reply cap race 映射 409。
9. test account formal、formal fallback：`p_charge_quota=false / p_charged=true`，各只計一次。
10. fresh explicit false：走現行生成並記 miss；舊 client missing 不記 miss。
11. prefetch response/commit 掉包後同 ID formal：只 settle；settle response 掉包後再 retry：exact per-request row already-settled replay，即使後來已有別的 request 也不遺失證據。
12. 不同 requestId 的新 prefetch 遇 current pending：skip；較舊 ai_count pending先安全清掉。相同 ai_count 的第二個正式 Hint 是 fresh request，照現行再生成、再計次。
13. flag missing/false＋formal false：沒有 pending 時完整走 claim/provider/record；有 pending 時先 discard，再 fresh formal；若 discard race 發現已 settled，直接 replay。
14. daily/monthly reset 競態：強制測出「charge transaction commit 發生在另一 request 讀舊 counters 與嘗試 reset 之間」；reset RPC 後到時須在 row lock 內重讀，不能把已 commit usage 歸零。
15. trust-boundary：prefetch success、pending retry、甚至 requestId 已 settled 時，只要 request flag 是 true 都只能回 `{prefetched:true}` 類 opaque ack；`replies/coaching/provider/model/result` 等內容欄位一律不存在。formal settle 才首次回內容。

### 3.2 重排 Hint 流程

保持 Game＋Beginner 同一段程式：

1. mode lock／Game unlock 仍在 replay 前。
2. preflight 只以 exact requestId 查 `practice_hint_requests`：
   - settled match＋formal → 現行直接 replay；settled match＋prefetch → 只回 opaque ack。
   - unsettled match＋prefetch → 只回 opaque ack，不做任何副作用、不洩漏 stored result。
   - unsettled match＋formal＋flag=true → 先跑消費時 hint/quota/session gate，再呼叫 settle RPC；不走 model rate limit。
   - unsettled match＋formal＋flag=false → 呼叫 discard RPC；確實 discard 才走 fresh formal，若 RPC 回已 settled 則 replay。
3. preflight miss：跑既有 hint/quota gate。explicit false 才記 `miss`。
4. prefetch flag 關閉時，在 provider/claim 前回 503；client 會靜默吞。
5. preflight miss 先 claim：claim-level replay 只認 exact requestId＋`stored_charged`，不能無條件回 stored result。只有 `replay=false` 的 fresh claim 才計 `practice_hint` model rate；若 rate limited，立即用 requestId-aware release 清 latch/generating row再回 429。這取代現行「rate 在 claim 前」排序，避免 record 恰在 preflight→claim 窗口完成時，零模型 replay 被錯算或錯擋 rate limit。
6. 生成迴圈結束且 `hintResult == null` 時：
   - prefetch：記 failed reason、release latch、回 503，**在 `buildFallbackHintResult` 前 return**。
   - formal：完全維持現行 Game/Beginner fallback、`fallback_used` 日誌與 no-quota 行為。
7. record 參數依兩軸 policy 組合；**有 requestId/result 的新流程**使用 RPC 回的 authoritative count/result，避免 Edge 用舊 subscription snapshot 猜 remaining；無 requestId 舊 client維持現行 `hintResult + did_charge + new_hint_count` response 組法。
8. 匯入 `classifyQuotaRpcError`；鎖內 quota RAISE 時重新讀 subscription 組精確 429 payload。
9. 新 schema/RPC 缺失要 503 fail closed，不得在 provider 前 fail open。
10. 把 practice-chat 現行 direct reset UPDATE 改成呼叫 `prepare_practice_subscription_usage` 並以 RPC 回值更新 `sub`；record/settle 也在自身 transaction 先呼叫同 helper。reset、limit check、increment 必須由同一 subscription row lock 串行，不能只比 reset_at 做 CAS。
11. record 回 `PRACTICE_HINT_STALE` 時，以 requestId-aware release 清 latch/generating row並回可重試錯誤；不建 snapshot、不扣、不計。測試讓 prefetch provider 在途時另一 chat commit 推進 ai_count，確認舊結果不會綁到新回合。
12. fresh prefetch record 成功後也只回 opaque ack；stored result 只能留在 service-role ledger。不得因 Flutter「會忽略」就把內容送上網路，client flag 不可信。

第 10 點先獨立紅→綠並單獨 commit：`Practice Chat 額度重設改為 DB 鎖內交易`。確認 reset concurrency 測試綠後，才接其餘 Hint handler 分流；不要把既有 reset 修正藏進大型 prefetch diff。

### 3.3 Telemetry

新增同名事件 `practice_chat_hint_prefetch`，只帶固定 scalar：

- `outcome`: `fired | hit | miss | failed`
- `reason`: allowlist（如 `disabled / gate / quota / rate_limit / timeout / visible_text_guard / invalid_json / schema_invalid / provider_error / pending / unknown`）
- `practiceMode`: `beginner | game`

不得帶 user text、turns、prompt、模型輸出、raw error。現行 `practice_chat_*_hint_fallback_used` 不改；prefetch 沒真的回 fallback，所以不得製造 fallback_used 假陽性。

Run：

```powershell
deno test --quiet --allow-read --allow-env --allow-net=127.0.0.1 supabase/functions/practice-chat/index_test.ts
deno test --quiet --allow-read --allow-env --allow-net=127.0.0.1 supabase/functions/practice-chat/hint_test.ts
deno test --quiet supabase/functions/practice-chat/quota_decision_test.ts
deno test --quiet --allow-read supabase/functions/practice-chat/model_rate_limit_source_test.ts
deno check supabase/functions/practice-chat/handler.ts
deno check supabase/functions/practice-chat/index.ts
```

**Commit（Task 3 其餘 handler/telemetry）：** `Hint 預產失敗不落 fallback 並於消費時結算`

## Task 4：Flutter API contract TDD

**Files**

- Modify: `lib/features/practice_chat/data/services/practice_chat_api_service.dart`
- Modify: `test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart`

### 4.1 紅燈

新增測試：

- 新增內部 `prefetchHint(...)`，body 明確送 `prefetch: true` 與 requestId；200 只接受 opaque `{prefetched:true}` ack，方法回 `Future<void>`，沒有 `PracticeHintResult` 可被 UI 使用。
- 正式 `requestHint()` 明確送 `prefetch: false`，供新 server 計 miss；其餘 body byte-for-byte 語意不變，仍回 `PracticeHintResult`。
- prefetch response 若意外含 `replies/coaching/result` 等內容欄位，client 測試可選擇 fail closed／至少不解析、不暴露；403/429/500 mapping 與靜默吞策略不改。

### 4.2 最小實作

抽共用 body/invoke helper，但公開成兩個型別安全方法：`requestHint` 固定 `prefetch:false` 並解析正式結果；`prefetchHint` 固定 `prefetch:true` 且只驗 opaque ack。兩者仍打同一支 Edge endpoint，不新增 server endpoint、不改正式 response entity、不在 service 快取內容。

Run：

```powershell
flutter test test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart
flutter analyze lib/features/practice_chat/data/services/practice_chat_api_service.dart
```

**Commit:** `Practice Chat API 支援 Hint 預產旗標`

## Task 5：Flutter controller TDD——背景開火與在途序列化

**Files**

- Modify: `lib/features/practice_chat/data/providers/practice_chat_providers.dart`
- Modify: `test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart`
- Regression: `test/unit/features/practice_chat/data/repositories/practice_pending_hint_store_test.dart`
- Regression: `test/widget/features/practice_chat/practice_chat_screen_style_test.dart`

### 5.1 擴 fake API 與先寫紅燈

Fake API 分開記錄 `prefetchHint` 與正式 `requestHint` 的 requestId、順序與 completer；prefetch fake 只完成 ack，不回 `PracticeHintResult`。測試至少覆蓋：

1. AI 回覆後 beginner、game 各 fire 一次；standard 不 fire。
2. hint 已 5 次、session complete、ended 不 fire。
3. prefetch 不設 `isHintLoading`、不改 replies/coaching/count、不 sync usage、不阻擋 `canSend`。
4. prefetch error／429 全靜默；chat 成功 state 不被覆寫。
5. 沒正式消費時，下一則 AI 回覆不重產；成本上限一局一次嘗試。
6. 正式 request 真正 dispatch 後才清「未消費」RAM gate；下一個 AI turn 才可再 prefetch。
7. prefetch completer 未完成時點 Hint：正式 call 尚未發；completer 成功或失敗後，**點擊當下 intent 仍有效**才發，且同 turn 使用同 requestId。
8. 即使在途 prefetch 已因新 AI turn 變舊指紋，正式 request 仍先 await 它（server latch 是 session-wide），再為最新 turn 取 requestId。
9. **CRITICAL billing regression:** 點擊後 await 期間 `resumeSession(other)`／續玩／換人使 sessionId、aiCount 或 generation 改變 → formal call count 必須仍為 0，絕不能把 A 場點擊 retarget 到 B 場。
10. same-session resume 視為 no-op／保留 flight、pending id 與 RAM gate；different-session resume 才清。兩路各有測試。
11. autoDispose/App 重建無法恢復舊 Future：同指紋 pending store 仍沿用同 requestId；首個 formal 可收到既有 `practice_hint_in_flight`，必須保留 ID，稍後第二次 replay，不鑄新 ID／不假裝已 await。
12. `_persist()` 失敗且使用者已在 await placeholder：flight 回傳明確 `persistFailed`（不能和「prefetch HTTP failed」混成 void completion）；prefetch call=0、formal call=0、RAM gate不視為已消費。用第二輪 priorMessages 仍以 AI 結尾的 case 鎖住，不能只靠 `canRequestHint` 偶然擋住。

### 5.2 抽 requestId helper

把 `requestHint` 內 `sessionId + aiReplyCount` 的 memory/store load-or-create 抽成單一 helper；prefetch 與 formal 必須共用，仍維持：

- 成功／明確 4xx 才 rotate。
- timeout/5xx/429/in-flight 保留。
- prefetch 成功或失敗都不 rotate。

### 5.3 建立 controller-only flight

使用私有 flight（至少包含 pending fingerprint/requestId＋`Future<_HintPrefetchFlightOutcome>`；outcome 明列 `persistFailed / readyAfterAck / readyAfterPrefetchFailure`）和「已嘗試且尚未正式消費」bool。只有 API 層的 `prefetchHint` 維持 `Future<void>`：

1. `sendMessage` 成功把 AI reply、`aiReplyCount` 寫入 state 後，**同步建立 typed placeholder flight/completer reference**，避免 UI 立即點擊看不到在途；只有 `_persist()` 成功後才真正發 prefetch HTTP。persist 失敗就以 `persistFailed` 完成並清自己的 placeholder／attempt gate、不打 API。
2. prefetch capture immutable profile/turns/memory/state DTO並呼叫 `_api.prefetchHint`；背景 future 自己 `.timeout` 並把 opaque-ack HTTP 成敗收斂成「persist 已成功、可以 formal」的完成態，絕不解析 Hint 內容或改 UI。prefetch HTTP 失敗仍允許 formal；只有 persist 失敗禁止。
3. 正式 `requestHint` 在 await 前 capture `intentSessionId + intentAiCount + _hintGeneration`；先設 loading、await 當下任何同 session prefetch flight。若 outcome=`persistFailed`，或三元任一不符，或 `!canRequestHint`，就 abort、零 dispatch且不得改新場 state；全部吻合才發 `prefetch:false` formal request。
4. formal API dispatch 時才把 RAM gate視為已消費；不是等成功才清。
5. same-session `resumeSession` 保留 flight/pending/RAM gate；只有不同 session／續玩新 round／換人才清。late completion 只能清自己那個 flight reference，identity 不吻合就 no-op。
6. autoDispose/App 重建是唯一無法 await 原 Future 的例外；沿用既有 in-flight 403→保留 requestId→稍後 replay 行為，不另造假 future。
7. 不修改 `PracticePendingHintStore`、PracticeSession/Hive adapter 或 screen widget。

Run：

```powershell
flutter test test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart
flutter test test/unit/features/practice_chat/data/repositories/practice_pending_hint_store_test.dart
flutter test test/widget/features/practice_chat/practice_chat_screen_style_test.dart
flutter analyze lib/features/practice_chat/data/providers/practice_chat_providers.dart
flutter analyze lib/features/practice_chat/data/services/practice_chat_api_service.dart
```

**Commit:** `AI 回覆後預產 Game 與新手 Hint`

## Task 6：整體驗證與高風險 Codex 雙審

### 6.1 格式／靜態／測試

逐檔跑下方完整命令；保留每條實際 pass/fail 與 test count。`git diff --check` 必須乾淨；`pubspec.lock` 必須仍未 stage。

### 6.2 內部 spec／quality review

逐項對照本檔 failure matrix，特別人工看：

- formal fallback/test account 沒被誤判未結算。
- per-request ledger 不會被後續 request 覆寫；preflight 與 claim-level replay 都不會免費回未結算內容。
- quota RAISE 與 count/marker 同 transaction rollback。
- subscription reset／limit check／increment 共用 DB row lock transaction，跨 reset 不抹掉已 commit usage。
- prefetch 全敗 return 位於 fallback 建構與 record 之前。
- Game/Beginner 共用 branch，Standard 不變。
- 新 client 不會早於 prefetch-aware Edge 出貨。

### 6.3 準備 Codex packet

Packet 必含：

- base ref、完整 commit list、changed files、逐檔測試結果。
- 本檔 failure matrix 與 DB signature／migration deploy order。
- `pubspec.lock` 既有 dirty 不在 scope 的證據。
- 兩個 review focus：
  1. 標準 review：正確性、舊 client 相容、response schema、測試缺口。
  2. adversarial review：雙擊／跨 request 覆寫／掉包／quota-reset-cap race／test account／fallback／flag-off pending drain／compatibility floor。

Eric 依共享規則把 packet 路由到兩個獨立 read-only Codex review。任一 `REVISE_REQUIRED` 先回到 failure matrix 判斷設計訊號；最多兩輪 fix＋review。兩審皆 `APPROVED` 前停在 branch，不部署。

任一 APPROVED 後若 SQL／Edge／client code 再變動，該證據立即失效；重跑受影響測試並讓兩個 review 都覆蓋新的 exact range，不能沿用舊 verdict。

**Commit:** 修 review finding 時一 finding/concern 一 commit；不得混入清理。

## Task 7：目標式 migration、真 DB 原子性驗證、Edge 先行

> 本 task 才能接觸 prod。禁止 `supabase db push`。

1. 用 Supabase MCP `apply_migration` **只套** `20260711120000_practice_hint_prefetch.sql`。
   - 套用前先查 `hint_generation_started_at` 的 fresh rows；能等就先 drain，再套。migration-window legacy record 相容分支是保險，不是省略 drain 的理由。
2. 若 MCP 產生的 ledger timestamp 不等於檔名，依共享規則目標式 UPDATE `supabase_migrations.schema_migrations` 對齊 `20260711120000`。
3. 查證：
   - `practice_hint_requests` PK/index/check/RLS/backfill 正確，舊 snapshot 全為 charged=true。
   - `pg_proc` 只有唯一 claim/record/settle signatures，沒有 overload。
   - grants 只有 service_role；PostgREST schema cache 已 reload。
4. 以隔離的測試帳號/session row 做 SQL/RPC smoke，做完清理測試列：
   - 未結算 record → quota/count 皆 0 變化。
   - 首次 settle → quota/count/marker/finalized JSON 正確。
   - 第二次與兩個並發 settle → exactly-once、同 result；再寫不同 request 後，舊 request replay 仍存在。
   - quota exhausted → transaction 全 rollback。
   - session cap、Hint cap、request mismatch、flag-off discard、reset-vs-settle 競態正確。
   - 刪除測試 session 後 child ledger rows=0；以 delete-account 同順序 smoke 不被 FK 阻擋且不殘留 Hint 內容。
   - Beginner/Game 可用、Standard 拒絕；test account settle 不扣但計次。
5. 從乾淨 `main` 建 server landing branch，只 cherry-pick Task 1–3 的 exact hashes；把 migration＋server commits 落 `main`，**不要 merge 含 Task 4–5 的整支 implementation branch**。記錄 cherry-pick hashes與 `deploy-edge-function.yml` run，等待完成並核對 live `practice-chat` revision。
6. `PRACTICE_HINT_PREFETCH_ENABLED` 先維持未設／false：
   - smoke 現行 formal Hint（成功、fallback、replay、Game/Beginner）。
   - prefetch:true 應 503 且零扣／零計。
7. 設 flag=true，再用測試帳號跑一次 prefetch success → formal settle → replay；先確認 prefetch HTTP 只有 opaque ack、無任何 Hint 文字，再核對 ledger 與 telemetry。

任何 migration/RPC/計費 anomaly：立即停、flag=false、保留 ledger 做稽核，不發布 client、不宣稱 safe。

## Task 8：Client 後上、dogfood 與 rollback

1. Edge live smoke 全過後，從當下乾淨 `main` 建 client landing branch，只 cherry-pick Task 4–5 hashes，再落 `main`／產出下一個 TestFlight build；記錄 release run。不可把 DB、Edge、client 三層同時競速發布。
2. 真機各跑 Beginner＋Game：
   - AI 回覆後不顯示 loading；點 Hint 快速回同內容。
   - 不點不扣；點一次只扣／計一次；連點、斷網重試不重扣。
   - prefetch 失敗時仍能走現場正式 Hint，fallback 行為與今天一致。
3. 觀察 `practice_chat_hint_prefetch` fired/hit/miss/failed 與既有兩型 fallback rate；沒有拍板數字門檻，不自行發明 success threshold。
4. 只有 migration驗證＋Edge smoke＋targeted tests＋Codex 雙審＋真機計費核對都有證據，才可說 dogfood safe。

### Rollback gate

- 最先動作永遠是把 `PRACTICE_HINT_PREFETCH_ENABLED=false`；新 prefetch 立即 503。正式點擊若命中既有 pending，Edge 以 discard RPC 原子丟棄未扣 row後走現場生成；若競態中已 settled則 replay，不能重扣。
- client 發布後，prefetch-unaware 的舊 Edge **不是合法 rollback target**：它會忽略 `prefetch:true`，把背景請求當正式 Hint 先扣費／計次。
- Edge 永久維持本案的 prefetch-aware compatibility floor；修復採 flag-off＋forward fix。若需回退其他行為，rollback revision 本身也必須保留 `prefetch` validate/reject＋pending discard shim。DB additive migration 不 drop table/RPC。
- 任一 billing anomaly：停止 safe 宣告，保存 requestId/ledger/telemetry 證據再查，不以 refund patch 掩蓋原子性問題。

---

## 完整驗證命令

```powershell
deno test --quiet --allow-read --allow-env --allow-net=127.0.0.1 supabase/functions/practice-chat/validate_test.ts
deno test --quiet supabase/functions/practice-chat/hint_prefetch_test.ts
deno test --quiet --allow-read supabase/functions/practice-chat/hint_prefetch_migration_test.ts
deno test --quiet --allow-read supabase/functions/practice-chat/migration_source_test.ts
deno test --quiet --allow-read --allow-env --allow-net=127.0.0.1 supabase/functions/practice-chat/index_test.ts
deno test --quiet --allow-read --allow-env --allow-net=127.0.0.1 supabase/functions/practice-chat/hint_test.ts
deno test --quiet supabase/functions/practice-chat/quota_decision_test.ts
deno test --quiet --allow-read supabase/functions/practice-chat/model_rate_limit_source_test.ts

deno fmt --check supabase/functions/practice-chat/validate.ts supabase/functions/practice-chat/validate_test.ts supabase/functions/practice-chat/hint_prefetch.ts supabase/functions/practice-chat/hint_prefetch_test.ts supabase/functions/practice-chat/hint_prefetch_migration_test.ts supabase/functions/practice-chat/migration_source_test.ts supabase/functions/practice-chat/handler.ts supabase/functions/practice-chat/index_test.ts supabase/functions/practice-chat/model_rate_limit_source_test.ts
deno lint supabase/functions/practice-chat/validate.ts supabase/functions/practice-chat/hint_prefetch.ts supabase/functions/practice-chat/handler.ts
deno check supabase/functions/practice-chat/validate.ts
deno check supabase/functions/practice-chat/hint_prefetch.ts
deno check supabase/functions/practice-chat/handler.ts
deno check supabase/functions/practice-chat/index.ts

flutter test test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart
flutter test test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart
flutter test test/unit/features/practice_chat/data/repositories/practice_pending_hint_store_test.dart
flutter test test/widget/features/practice_chat/practice_chat_screen_style_test.dart
dart format --output=none --set-exit-if-changed lib/features/practice_chat/data/services/practice_chat_api_service.dart lib/features/practice_chat/data/providers/practice_chat_providers.dart test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart
flutter analyze lib/features/practice_chat/data/services/practice_chat_api_service.dart
flutter analyze lib/features/practice_chat/data/providers/practice_chat_providers.dart

git diff --check
git status --short
```

已知事項：交接指出整個 `practice-chat/` 目錄 type-check 可能在 `handler.ts:323` 的 `setTimeout` 吃既有髒；因此本案以以上逐檔結果為權威，不用整目錄失敗掩蓋新回歸，也不把單檔綠誇成全 repo 綠。

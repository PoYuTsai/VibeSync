# Review Packet — Opener Free 3（contract v2）＋新話題破冰腦力

> 2026-07-24。完整規格：`docs/plans/2026-07-24-opener-new-topic-implementation-plan.md`
> （摘要版 `docs/plans/2026-07-24-opener-new-topic-cc-handoff.md`）。
> 產品決策已鎖定，review 焦點是實作對規格的忠實度與 correctness。

## Range

- Branch：`claude/new-topic-brainstorm-feature-ibh6tz`
- BASE_SHA：`b89756e7`
- HEAD_SHA：`a149232cd9eeb531a50f73abed9eb33ad617a3ea`（code 終點；
  本 packet 的 reconciliation 更新 commit 為範圍最後一顆、只含文件）
- Exact range：`b89756e7..a149232c`（＋一顆 docs-only packet commit）

## Commits

1. `cff08291` 開場救星免費版解鎖延展幽默微調侃三種
2. `e2954729` 新增新話題後端契約與原結果重播帳本
3. `f3b597d5` 新增新話題脈絡建構與前端資料層
4. `6dccfc1b` 開場救星加入新話題切換與結果介面
5. `df1079d6` 更新新話題定價決策與審查文件
6. `a149232c` 補新話題 claim/release telemetry（GLM 審查 I4）
7. `<本 packet reconciliation 更新，docs-only>`

## Changed files（依 commit）

Commit 1（Opener contract v2）：
- `supabase/functions/analyze-chat/index.ts`（contract version 解析、五種
  completeness gate＋repair、Free v1/v2 投影、access metadata）
- `supabase/functions/analyze-chat/opener_payload.ts`（v2 常數、
  parseOpenerContractVersion、missingOpenerTypes、buildOpenerAccess、
  filter nested recommendation canonicalize）
- `supabase/functions/analyze-chat/{opener_payload,index,opener_prompt}_test.ts`
- `lib/features/opener/domain/opener_access.dart`（新檔：單點契約＋
  OpenerAccess 防禦式解析）
- `lib/features/opener/data/services/opener_service.dart`（request 帶
  contractVersion 2、access 解析、free 三型投影、access-order fallback）
- `lib/features/opener/presentation/screens/opening_rescue_screen.dart`
  （卡片 contract-driven、resultHasPaidStyles 改 paid-only keys、
  _resultGeneratedPaid 改 access 權威）
- `test/unit/features/opener/...`（service＋locked cards 測試改寫）

Commit 2（New Topic backend）：
- `supabase/migrations/20260724120000_new_topic_exactly_once.sql`
- `supabase/functions/analyze-chat/new_topic_{payload,prompt,billing}.ts`＋
  各自 `_test.ts`＋`new_topic_source_test.ts`
- `supabase/functions/analyze-chat/index.ts`（new_topic branch）＋
  `index_test.ts`（normalizeTier 查表計數 3→4）
- `supabase/functions/_shared/model_rate_limit{,_test}.ts`（scope
  `new_topic: 3/min, 30/day`）

Commit 3（Flutter data/domain）：
- `lib/features/new_topic/domain/entities/new_topic_result.dart`
- `lib/features/new_topic/domain/services/new_topic_partner_context_builder.dart`
- `lib/features/new_topic/data/services/new_topic_{service,request_session}.dart`
- `lib/features/new_topic/data/providers/new_topic_providers.dart`
- `lib/features/user_profile/domain/services/effective_style_prompt_builder.dart`
  （新增 buildForNewTopic；既有三 slice 不動）
- 對應 unit tests

Commit 4（UI）：
- `lib/features/opener/presentation/screens/opening_rescue_screen.dart`
  （OpeningRescueMode＋IndexedStack、opener body 原樣抽 method）
- `lib/app/routes.dart`（`?mode=new_topic`）
- `lib/features/conversation/presentation/widgets/new_conversation_sheet.dart`
  （tile 改「開場白／新話題」）
- `lib/features/new_topic/presentation/widgets/new_topic_{view,idea_card}.dart`
- widget/contract tests

Commit 5（docs）：
- `docs/pricing-final.md`（Free opener 3 型註記＋新話題定價行）
- `docs/decisions.md`（ADR #31，取代 ADR #7-4 的 Opener 部分）
- 本 packet

## Migration

- `supabase/migrations/20260724120000_new_topic_exactly_once.sql`
  - `new_topic_requests`（PK user+request、input_hash 64hex、pending/done
    CHECK、result 頂層三鍵白名單、Free 1 題鎖 4／Paid 5 題鎖 0 一致性）
  - RPC：`claim_new_topic_request`（65s lease）／`release_new_topic_claim`
    ／`settle_new_topic_request`（同 transaction `increment_usage(...,3,...)`）
    ／`validate_new_topic_result`／`cleanup_expired_new_topic_requests`
    ／`new_topic_contract_version`（marker `new-topic-exactly-once-v1`）
  - pg_cron `43 * * * *`；RLS＋anon/authenticated 全 revoke、service_role
    SELECT only、寫入僅 SECURITY DEFINER RPC
- 部署只可目標式 `apply_migration`；禁止 `db push`。

## Secrets（只列名稱）

- `NEW_TOPIC_REPLAY_HMAC_KEY`：base64 ≥32 random bytes；只有 new_topic
  分支檢查，缺失時僅 New Topic fail closed（503
  `NEW_TOPIC_REPLAY_NOT_CONFIGURED`），不影響 opener/analyze/OCR。
  尚未設定（deploy 步驟）。

## 測試結果

Targeted Deno（PASS）：
- `deno test --allow-read supabase/functions/analyze-chat/new_topic_payload_test.ts` → 19 綠
- `deno test --allow-read supabase/functions/analyze-chat/new_topic_billing_test.ts` → 9 綠
- `deno test --allow-read supabase/functions/analyze-chat/new_topic_prompt_test.ts` → 8 綠
- `deno test --allow-read supabase/functions/analyze-chat/new_topic_source_test.ts` → 5 綠
- `deno test --allow-read supabase/functions/analyze-chat/ supabase/functions/_shared/model_rate_limit_test.ts` → 710 綠
- `deno check supabase/functions/analyze-chat/index.ts` → PASS

Full Deno（PASS）：
- `deno test --allow-read --allow-env supabase/functions/` → 2181 綠
  （注意：不帶 `--allow-env` 時 coach-chat/coach-follow-up 兩檔在 BASE_SHA
  也會 uncaught error，屬既有測試環境需求，非本輪引入。）

Targeted Flutter（PASS）：
- `flutter test test/unit/features/opener/` → 97 綠
- `flutter test test/unit/features/new_topic/ test/unit/features/user_profile/domain/effective_style_prompt_builder_test.dart` → 44 綠
- `flutter test test/widget/features/new_topic/ test/unit/features/new_topic/presentation/ test/widget/features/conversation/new_conversation_sheet_screenshot_test.dart` → 12 綠
- `flutter test test/widget/screens/new_conversation_screen_test.dart test/unit/features/opener/data/services/opener_result_cache_service_test.dart` → 35 綠

Full Flutter（PASS）：
- `flutter test` → 2260 綠（4 skip；exit 0）
- `flutter analyze`（full）→ 首輪唯一 finding＝new_topic_view.dart 一個
  unused import warning，已修並 amend 進 commit 4（6dccfc1b）；修復後
  `dart analyze` 該檔 0 issues（全 repo analyze 首輪除此之外 0 issue；
  release gate 的 CI full analyze 會在 push 後再驗一次）。

## 尚未執行的 live steps（全部留在 APPROVED 之後）

1. 目標式 `apply_migration` 20260724120000。
2. 驗證 RPC／RLS／cron／`new_topic_contract_version()`。
3. 設 `NEW_TOPIC_REPLAY_HMAC_KEY`（不讀回、不印出）。
4. `supabase functions deploy analyze-chat --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg`（單一 function）。
5. 舊 App／Opener v1 smoke → v2 與 New Topic smoke。
6. PostgreSQL transaction smoke（concurrent claim 單 owner、fresh settle
   +3、replay body 一致、lease takeover、quota race 同成同敗、invalid
   result 不入帳、anon 無 SELECT/EXECUTE、cron/marker 存在）。
7. TestFlight build＋Eric/Bruce dogfood 目檢（grounding 六項）。

## Risk focus（建議 review 重點）

1. **exactly-once correctness**：index.ts new_topic branch 的
   release/不-release 分類——特別是 settlement retryable（transport 不明）
   絕不 release、quota RAISE 才 release；generation deadline 504 與 65s
   lease 的邊界。
2. **Free 洩漏面**：ledger 只存投影後結果（Free row 只有推薦一題）；
   opener paid-era cache 降級重投影；`resultHasPaidStyles` 改 paid-only
   keys 後 stale-tier race 的行為。
3. **Opener v1/v2 相容**：缺版本欄位的舊 App 必須拿到 legacy extend 單卡；
   contract version 不入 opener input hash（跨版本 dedup 語意）。
4. **HMAC 邊界**：canonical JSON array（length-safe）；normalize 先於
   hash；expectedTier/RevenueCat hint 不入 hash。
5. **Prompt grounding**：About Me 興趣不得寫成對方興趣；四情境節奏；
   blocking scan 已納 NEW_TOPIC_PROMPT／REPAIR。
6. **generic gate 隔離**：new_topic 不被 analyze 月/日 1 點 gate、optimize
   shape、message sanitizer 接管；`MODEL_RATE_LIMITED` payload 無 quota keys。

## Open concerns

- PostgreSQL transaction smoke 尚未跑（無本地 PG；列入 deploy 後步驟）。
- `NewTopicView` 的 widget 級整合測試（consent/paywall/mode switch 保留
  結果）以 contract/unit 測試＋既有 opener widget 測試覆蓋為主，未建
  完整 route-level widget harness（計畫 §15.4 的完整清單屬理想面；如
  review 認定必補請點名優先項）。
- 計畫 §14.1 的 per-event telemetry 名單以現有 logInfo/logWarn 事件
  （`new_topic_generated`/`new_topic_replayed`/…）近似對應，未逐一同名。

---

# Cross-model review reconciliation（2026-07-24，主大腦＝Claude Code）

三方挑戰 gate 執行紀錄。兩個 reviewer 都只讀本 packet（read-only、無 repo
存取），findings 由主大腦逐項回查 repo／diff／測試證據裁決；不用多數決。

## 執行命令與環境

- Codex：`bash ~/.agents/skills/cross-model-review/scripts/invoke-codex.sh
  --input docs/reviews/2026-07-24-opener-new-topic-review-packet.md --mode review`
  （gpt-5.6-sol、read-only/ephemeral/tools-reduced、reasoning xhigh；
  22,210 tokens）
- GLM：`bash ~/.agents/skills/cross-model-review/scripts/invoke-glm.sh
  docs/reviews/2026-07-24-opener-new-topic-review-packet.md review`
  （glm-5.2、read-only）
- 完整原文：session scratchpad `codex-review-full.txt`／`glm-review-full.txt`
- 已知 pipeline 問題：GLM 端收到的 packet 中文出現編碼損毀（mojibake），
  導致其多項 finding 是誤讀（見下表）；Codex 端讀取正常。invoke-glm.sh 的
  編碼處理建議另案修。

## Reviewer verdicts（原文結論）

- Codex：「目前不應給無條件 APPROVED……最關鍵的核准條件是：固定 HEAD、
  補上修復後 full analyze，並讓資料庫 concurrency/security smoke 在
  release 前全部通過。」
- GLM：「Not ready for go-live approval. Fix C2（5s lease）、run C3
  （PG smoke）, then re-review.」

## 逐項裁決

### 已修正（本輪 commit）

| Finding | 裁決 | 處置 |
|---|---|---|
| Codex C1／GLM C1：HEAD_SHA 佔位符，range 不可重現 | **TP（packet 缺陷）** | 已釘 `a149232cd9eeb531a50f73abed9eb33ad617a3ea`＋逐 commit SHA；reconciliation commit 為 docs-only 最後一顆 |
| Codex I2／GLM M5：「full analyze PASS」缺修復後 full-run 證據 | **TP（證據強度）** | 已在最終 tree 重跑 `flutter analyze` → `No issues found!（702.1s，exit 0）` |
| GLM I4／Codex M1（部分）：claim/release 生命週期零 telemetry | **TP（觀測盲區）** | commit `a149232c` 補 `new_topic_claim_acquired`／`new_topic_claim_released(released)`；deno check＋710 綠 |

### 條件核准項（deploy 閘門硬條件，非 code 缺陷）

| Finding | 裁決 | 處置 |
|---|---|---|
| Codex I1／GLM C3：PG transaction smoke 未跑 | **TP（已列 open concern）** | 本機無 docker／PG，無法在不碰 prod 下先跑。維持條件核准：live step 6 全過（含兩並行 transaction 的 claim/settle/rollback/replay）之前**不得**宣稱 exactly-once verified、不得放 dogfood。此為 release gate 硬條件。 |
| Codex I4／GLM I1：secret 未設＝部署後功能必 503 | **TP（runbook 已涵蓋）** | 部署順序固定 migration→驗 RPC/RLS→設 secret→deploy→smoke；補充：smoke New Topic 前先以不讀值方式確認 secret 存在（`supabase secrets list` 名稱比對）。 |
| Codex U4：RPC EXECUTE 對 PUBLIC 的預設授權 | **部分 TP** | migration 對全部 6 個 function 都已 `REVOKE ... FROM PUBLIC/anon/authenticated`＋`GRANT ... TO service_role`（SQL 內逐一可查）；live step 6 加驗 `has_function_privilege` 矩陣＋匿名 JWT 實呼。 |

### 假陽性（附證據）

| Finding | 裁決理由（repo 證據） |
|---|---|
| GLM C2：「5s lease vs 65s generation」結構性破壞 exactly-once | **FP（mojibake 誤讀）**：SQL 實為 `interval '65 seconds'`（migration＋`new_topic_source_test.ts` 錨定）；65s lease > 45s generation deadline＋5s settlement reserve（50s request deadline），正常路徑不會 takeover |
| Codex U1：lease 無 fencing，遲到 owner 可覆寫 | **FP（機制存在）**：`settle_new_topic_request` 檢查 `owner_token IS DISTINCT FROM p_owner_token → RAISE OWNER_MISMATCH`；done row 回 stored winner（charged=FALSE）；`release` 要求 user+request+hash+owner 四項全符且 state='pending'。billing_test「owner mismatch → retryable」「release 全 identity 相符才 true」覆蓋。stale owner 的模型成本浪費是 takeover 語意固有、lease 已覆蓋正常時長 |
| Codex U2／GLM U2：opener 跨 v1/v2 dedup 回錯 shape／cache poisoning | **FP（機制誤解）**：opener ledger（`opener_request_charges`）是**扣費 dedup**、不存 response body——dedup 命中後照常重新打模型並依**本次** request 的 contract version 投影（`opener_charge.ts` 註解「dedup 不是錯誤：呼叫端照常回 200」；charge 呼叫點在生成與投影之後）。client Hive cache 則是 read-time 依現行權益重投影（`visibleForAccess`），不存在 stored-projection 回放路徑。version 不入 hash 正是為了跨版本重試仍 dedup 成功不雙扣 |
| Codex U3：tier 不入 hash 的 entitlement race | **符合規格**：計畫 §5.6 明文「Replay 時…生成內容與 access servedTier 保持第一次成功版本」。claim 後升降級由 settle 當下 servedTier 投影入帳；同 ID replay 回第一次已扣費版本是拍板語意 |
| GLM I3：`--no-verify-jwt` 缺內部 auth 稽核 | **FP（既有部署模式）**：analyze-chat 一直以 `--no-verify-jwt` 部署（CLAUDE.md 明載）；handler 第一步 `Authorization` header→`supabase.auth.getUser(token)`，失敗 401——在所有 mode 分支之前，new_topic branch 天然在 auth 之後 |
| GLM I5：full Deno 依賴 `--allow-env`、CI parity 未證 | **FP**：`.github/workflows/flutter-ci.yml:43` 本來就是 `deno test --allow-env --allow-read`；BASE_SHA 的「失敗」只是本機首輪漏 flag，非 code 問題 |
| GLM I2／I4（HMAC「≥2 bytes」）／M4（ADR 編號） | **FP（mojibake 誤讀）**：原文分別為「Free 1 題鎖 4／Paid 5 題鎖 0」、「base64 ≥32 random bytes」（`isStrongNewTopicReplayHmacKey` 驗 `atob(key).length >= 32`）、「ADR #31 取代 ADR #7 條目 4」 |
| GLM M3：HMAC 未 constant-time compare／canonical 未排序 | **FP**：canonical 是固定位置 JSON array（非物件 key，天然 deterministic）；input_hash 是 server-keyed HMAC 輸出、非 secret，比較 timing 不構成 oracle（無 key 無法離線驗證） |
| GLM U1：cron 前 stale pending row 卡重試 | **FP**：`claim_new_topic_request` 對 lease 過期 row 直接 stale takeover（UPDATE owner_token），不等 cron；cron 只負責 24h retention |
| GLM U3：rate limit 與 quota 交互＝生成後才拒 | **FP**：quota gate（cost 3）在 claim 後、模型呼叫**前**；settle-time 429 只在極少數 race（transaction 回滾、release、不扣、client 開 paywall——`NewTopicQuotaExceededException` 測試覆蓋） |
| GLM M1：amend 改 SHA＝歷史髒 | **說明**：amend 前的 7188dac6 從未 push；6dccfc1b 才是首次 push 的版本，無 force-push |
| GLM M2：packet mojibake | **pipeline 問題**：packet 本體 UTF-8 正常（Codex 讀取無誤）；GLM wrapper 編碼另案修 |

### 原留 Eric 拍板兩項 → 2026-07-24 Eric 拍板「兩個都做」，已完成

| Finding | 處置（commit） |
|---|---|
| Codex I3：route-level UI 整合測試 | **DONE**（`aa15642f`）：`test/widget/features/opener/opening_rescue_mode_switch_test.dart` 四測——/opener 預設面板、`?mode=new_topic` deep link（含無對象生成鍵 disabled）、unknown fallback、模式來回切換保留兩側 state（輸入文字＋情境 chip）。Hermetic（Hive 暫存＋providers override）。consent/paywall 整合流仍以 unit/contract 層覆蓋（AiDataSharingConsent 為 static dialog，route-level harness 另涉 dialog pump 與 RevenueCat stub，價值密度低，明列為殘餘非債） |
| Codex M1／GLM I4（殘餘）：telemetry 與 §14.1 逐項同名 | **DONE**（`dafc0bac`）：補 `new_topic_request_received`（sanitize＋material 過後）、`new_topic_request_pending`（preflight/claim 兩階段）、`new_topic_model_rate_limited`（專名，generic 慣例並存）、`new_topic_settlement_succeeded`／`new_topic_settlement_replayed` 分流、`new_topic_generated`→`new_topic_success`、`new_topic_replayed`→`new_topic_replay_hit`；source test 錨定 §14.1 十二事件名＋§14.3 禁記面。analyze-chat 套件 711 綠 |

## Reconciliation 後測試證據

- `deno check supabase/functions/analyze-chat/index.ts` → PASS
- `deno test --allow-read supabase/functions/analyze-chat/
  supabase/functions/_shared/model_rate_limit_test.ts` → 710 綠
- `flutter analyze`（full，最終 Dart tree）→ `No issues found!`（702.1s）

## 剩餘風險（結論）

1. **PG transaction smoke（唯一 blocker 級殘留）**：exactly-once 的資料庫
   語意（並行 claim 單 owner、settle +3 原子性、quota race 回滾、takeover
   fencing、RPC privilege 矩陣）只有 SQL 源碼＋mock 層證據，未經真 PG 驗
   證。**條件核准**：live step 6 全過前不得宣稱 verified、不得放 dogfood。
2. ~~Route-level UI 整合測試缺口~~ → 已補（aa15642f）；殘餘＝consent/
   paywall 的 route-level 整合流仍以 unit 層覆蓋（見上表說明）。
3. ~~Telemetry 事件名未逐字對齊~~ → 已補（dafc0bac），§14.1 十二事件
   全數同名並由 source test 錨定。

---

# Deploy 執行紀錄（2026-07-24，Eric 口頭授權「部署」）

依部署閘門順序執行，全部通過：

1. **Migration**：`20260724120000_new_topic_exactly_once.sql` 經 Management
   API 目標式套用（非 db push），版本已記入
   `supabase_migrations.schema_migrations`。
2. **驗證**：`new_topic_contract_version()` → `new-topic-exactly-once-v1`；
   RLS enabled；cron `cleanup-expired-new-topic-requests` 存在；六個 RPC
   `has_function_privilege` 矩陣＝anon/authenticated 全 false、service_role
   true；table SELECT 同（Codex U4 落地）。
3. **Secret**：`NEW_TOPIC_REPLAY_HMAC_KEY`（openssl rand -base64 32）經
   Management API 設定（HTTP 201），僅以名稱驗證存在，值未輸出未落地。
4. **Deploy**：`npx supabase@2.105.0 functions deploy analyze-chat
   --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg` → Deployed；
   無 auth POST smoke → 401（function 活著、auth 守門）。
5. **PG transaction smoke（真 PostgreSQL，測試帳號，12 態全過）**：
   fresh claim=claimed；同 identity 第二 owner=pending(retryAfterMs)；
   owner fencing=OWNER_MISMATCH RAISE；hash mismatch=REPLAY_MISMATCH RAISE；
   settle(charge=true)=charged:true 且 counter 恰 +3；同 identity 再
   claim=replay 同 body；stale owner settle done row=stored winner
   charged:false（總扣恰 3）；done row release=false；quota race
   （limits=3）=QUOTA_EXCEEDED RAISE 後 row 仍 pending/result null/counter
   不變（同成同敗）；owner-bound release pending=true；invalid result
   （free 帶 2 題）=invalid p_result_json RAISE；cleanup 可執行；
   **真並發**雙 connection 同時 claim fresh identity → 恰一 claimed 一
   pending、row 單一 owner。測試 rows 已刪、counter 歸還為 0。
6. **Merge**：main fast-forward `b89756e7..c4eb9bed` push；CI
   「Deploy Edge Function」run 30061959152 → **success**。

**Exactly-once 資料庫語意自此為 verified**（原條件核准項已閉合）。
剩餘步驟：Eric 手動 dispatch iOS build → Eric/Bruce 真機 dogfood
（opener v1/v2 三卡、New Topic grounding 六項目檢）。

# Review Packet — Opener Free 3（contract v2）＋新話題破冰腦力

> 2026-07-24。完整規格：`docs/plans/2026-07-24-opener-new-topic-implementation-plan.md`
> （摘要版 `docs/plans/2026-07-24-opener-new-topic-cc-handoff.md`）。
> 產品決策已鎖定，review 焦點是實作對規格的忠實度與 correctness。

## Range

- Branch：`claude/new-topic-brainstorm-feature-ibh6tz`
- BASE_SHA：`b89756e7`
- HEAD_SHA：`<以 push 後最新 commit 為準（含本 packet commit）>`
- Exact range：`b89756e7..HEAD`

## Commits

1. `cff08291` 開場救星免費版解鎖延展幽默微調侃三種
2. `e2954729` 新增新話題後端契約與原結果重播帳本
3. `f3b597d5` 新增新話題脈絡建構與前端資料層
4. `6dccfc1b` 開場救星加入新話題切換與結果介面
5. `<HEAD>` 更新新話題定價決策與審查文件

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

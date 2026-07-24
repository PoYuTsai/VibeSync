# Review Packet：Opener／New Topic 公式回覆（formulaOpeners／formulaTopics）

> 日期：2026-07-24
> 風險：R2（AI prompt、New Topic exactly-once ledger schema、Flutter cache/UI）
> 實作 owner：Claude Code（Fable 5）
> 規格源：`docs/plans/2026-07-24-opener-formula-replies-implementation-plan.md`
> 部署授權：無。本包只涵蓋 implemented＋tested；migration／deploy／dogfood
> 需 Eric 另行明示。

## Range

- BASE_SHA：`aad497d0`
- HEAD_SHA：（見下方 commits，最後一顆為準）

## Commits（一 concern 一顆）

1. `d36be925` 擴充新話題重播帳本相容公式欄位（rollback-compatible Edge ref）
2. `5cb637f8` 開場救星與新話題新增公式回覆（feature backend）
3. `fc1fa86c` 前端解析並快取公式回覆
4. `3928712f` 開場救星顯示公式開場與公式新話題
5. （本檔所在 commit）補公式回覆審查與部署文件

## 契約摘要（review focus 對照）

### 硬保證（契約隔離，非文字凍結）

- Opener 原五型 `missingOpenerTypes()` completeness gate 未動；New Topic 原
  恰五題 strict gate（`normalizeNewTopicModelPayload`）未動。
- 公式欄位只在「primary JSON 可解析」時讀取；公式壞掉＝canonical 空清單，
  不觸發 repair、不產生 4xx/5xx、不改扣費。
- 整份 primary JSON unparseable：沿用既有 base repair；公式固定 `[]`；
  repair 仍失敗照舊 502／不扣。
- Repair 回覆即使含 formula 也不採用（兩模式一致；source-scan 測試鎖住）。
- Token cap 3000／deadline／quota 3／rate limit／tier 投影／
  openerContractVersion 全部未動。

### Raw 不穿透（雙層）

- `normalizeOpenerPayload()` 與 `filterOpenerPayloadForAllowedFeatures()`
  以 destructure 剝除 raw `formulaOpeners`（第一層）；handler response 以
  `formulaOpeners: openerFormulaOutcome.replies` 明確覆蓋（第二層）。
- 單元測試含 50-item 洪水陣列不穿透。

### Ledger／replay（New Topic）

- Additive migration `20260724180000_new_topic_formula_topics.sql`：
  - 不修改已部署的 `20260724120000`；constraint DROP＋ADD 同名重建。
  - legacy 三-key done row 原樣合法；新四-key 只允許多 `formulaTopics`。
  - `validate_new_topic_formula_topics()` helper＝table CHECK 與
    `validate_new_topic_result()` 共用單一事實來源；0–2 則、恰兩鍵、
    非空、`char_length()` 180/300（＝TS `[...t].length`＝Dart
    `runes.length`）。
  - `new_topic_contract_version()` → `new-topic-exactly-once-v2`（helper＋
    constraint（`pg_get_constraintdef` 含 formulaTopics）＋四-key 功能性
    探針俱全才回 v2；缺件降 v1）。
  - claim/release/settle/cleanup/cron/RLS/grants 逐字未動（source-scan
    禁令鎖住不得重定義）。
- `buildNewTopicLedgerResult()` 的 `formulaTopics` 是**必填**參數：漏傳
  在編譯期露餡（防「只掛 fresh response 不進 ledger」坑）。新 row 一律帶
  鍵（含空陣列）；Free/Paid 存同一份 canonical、tier 投影不讀公式。
- Fresh 與 replay 回同一 stored body（handler 永遠回 settlement stored
  result，原機制未動）。

### 共用 normalizer（`formula_reply.ts`）

- 依原始順序掃描收滿 2 則（非 slice 後驗）；壞項丟該則。
- cap 以 Unicode code points 計（astral emoji 邊界測試三語言對齊）。
- fence／`{`／`[` 開頭／schema key 片段（quoted）丟整則。
- dedupe key＝NFKC→小寫→去（全形）空白；標點保留。彼此重複留第一則；
  與 base 五句或 prompt 示範句（`FORMULA_PROMPT_EXAMPLE_LINES`，normalizer
  永遠內建排除）重複丟公式。
- `rejectInternalLabels: true`（兩模式都開）：九個內部作戰板標籤整則丟；
  不做廣泛禁詞掃描（自然語句含「熱度」「備註」不誤殺，有測試）。
- 實作決策（超出計畫字面、偏保守方向）：Opener 側也開
  `rejectInternalLabels`——該九標籤在 opener 輸出同樣永無合法用途。

### Telemetry（不含內容）

- `formulaOpenersCount`／`formulaOpenersDroppedCount`（opener_success）
- `formulaTopicsCount`／`formulaTopicsDroppedCount`（new_topic_success）
- Dropped＝raw array 長度 − canonical 數（含 malformed/over-cap/leak/
  label/duplicate/超過兩則）；非 array＝0。
- 不 log openingLine/whyItWorks/Partner 原文/raw output。

### Flutter

- `lib/core/utils/formula_reply_guard.dart`：server 規則的 Dart 鏡像
  （cache/transport defense-in-depth）。
- Opener：`OpenerFormulaReply`＋`OpenerResult.formulaOpeners`（fromJson
  best-effort、toJson 一律帶鍵、visibleForAccess/withRequestId 原封）。
- New Topic：`NewTopicFormulaIdea`＋`NewTopicResult.formulaTopics`；
  strict base 全過後才 best-effort 解析；壞公式不讓 `tryParse` 變 null。
- UI：共用 `FormulaReplySection`（垂直自適應、複製只複製 openingLine、
  空清單整區不渲染、無 outcome bar）。
  - Opener placement：五風格卡＋outcome bars＋推薦理由之後、pioneerPlan
    之前；「・N 種風格」不計公式。
  - New Topic placement：原 topics → 公式 → Free upsell CTA。
  - `NewTopicResultsSection` 抽成公開 widget（唯一結構性 refactor，為了
    widget test 可直接驗排序；行為未變）。

## Token／成本 evidence（§8）

- `OPENER_MAX_TOKENS`／`NEW_TOPIC_MAX_TOKENS` 維持 3000（測試鎖住）。
- New Topic 現行 outputTokens／stopReason 分布：**NOT MEASURED**（本輪
  無 paid external calls 授權；feature Edge 啟用前需 Eric 授權後以新
  prompt 跑 ≥20 次 black-box sample，記錄 base completeness、formula
  count、tokens、stop reason、latency、repair rate）。
- 供應商 input/output token 成本會小幅上升（公式 prompt＋輸出）；不改
  使用者 quota/tier/`usage.cost=3`。

## 測試證據（exact commands）

- Targeted Deno：
  - `deno test --allow-read supabase/functions/analyze-chat/formula_reply_test.ts` → 13/13
  - `deno test --allow-read supabase/functions/analyze-chat/new_topic_payload_test.ts supabase/functions/analyze-chat/new_topic_source_test.ts supabase/functions/analyze-chat/new_topic_billing_test.ts` → 40/40（後續加公式測試成長至 51）
  - `deno test --allow-read supabase/functions/analyze-chat/opener_payload_test.ts` → 15/15
  - `deno test --allow-read supabase/functions/analyze-chat/opener_prompt_test.ts` → 11/11
- Full analyze-chat Deno：
  `deno test --allow-read supabase/functions/analyze-chat/` → **722 passed / 0 failed**
- Deno check：`deno check supabase/functions/analyze-chat/index.ts` → 乾淨
- Targeted Flutter：
  - `flutter test test/unit/features/opener/data/services/opener_service_test.dart test/unit/features/new_topic/data/services/new_topic_service_test.dart` → 50/50
  - `flutter test test/widget/shared/formula_reply_section_test.dart test/widget/features/new_topic/new_topic_results_section_test.dart test/widget/features/opener/opening_rescue_formula_section_test.dart` → 10/10
- Full Flutter：`flutter test` → **2289 passed / 4 skipped / 0 failed**
- Flutter analyze：`flutter analyze` → 0 issues（commit 3 後與 commit 4 後各跑一次）
- PostgreSQL smoke：**準備完成、未執行**——
  `tools/new-topic-formula/pg_formula_smoke.sql`（S1–S14，單 transaction
  結尾 ROLLBACK，不留資料）。執行需 Eric 授權 migration 套用後在真 PG 跑；
  在此之前不得宣稱四-key ledger 相容為 DB-verified。

## Rollout／rollback（§7.4，未授權執行）

1. Compatibility Edge ref＝`d36be925`（validator 讀 legacy/new、prompt 未
   要求公式）——migration-first 後可安全部署。
2. Feature Edge ref＝commit 2 之後任一 HEAD。
3. Rollback＝把 Edge 回到 compatibility ref；additive migration 保留，
   不做 schema rollback；不可回到拒絕四-key row 的舊 production commit。

## Cross-model review

（Task 6 完成後填入）

- Claude/Codex peer：
- GLM adversarial：
- Reconciliation：

## 未執行（需 Eric 明示）

- push／apply migration／deploy analyze-chat／live smoke／TestFlight／
  dogfood-safe 宣稱。

## Open concerns

（review 後填入）

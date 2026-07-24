# Review Packet：Opener／New Topic 公式回覆（formulaOpeners／formulaTopics）

> 日期：2026-07-24
> 風險：R2（AI prompt、New Topic exactly-once ledger schema、Flutter cache/UI）
> 實作 owner：Claude Code（Fable 5）
> 規格源：`docs/plans/2026-07-24-opener-formula-replies-implementation-plan.md`
> 部署授權：無。本包只涵蓋 implemented＋tested；migration／deploy／dogfood
> 需 Eric 另行明示。

## Range

- BASE_SHA：`aad497d0`
- 首輪審查 range：`aad497d0..2347f166`
- Codex 首審修復輪後最終 HEAD：見「Cross-model review」節（修復 commit 落地
  後補記）

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

0. （Codex 二審採納）正式 apply 前先在可拋棄測試庫演練：完整套用一次＋
   人為中斷一次，確認失敗時原 constraint／functions 全數回滾（Management
   API 單 query＝單 transaction 的執行證據）。
1. Compatibility Edge ref＝`d36be925`（validator 讀 legacy/new、prompt 未
   要求公式）——migration-first 後可安全部署。
2. Feature Edge ref＝commit 2 之後任一 HEAD。
3. Rollback＝把 Edge 回到 compatibility ref；additive migration 保留，
   不做 schema rollback；不可回到拒絕四-key row 的舊 production commit。

## Cross-model review

### 首輪（range aad497d0..2347f166）

- Codex peer（read-only headless，cross-model-review wrapper）：
  **NOT APPROVED**——0 P0/P1、3 P2、1 minor、2 uncertain。
- GLM adversarial：首呼失敗（`GLM returned no content`，疑 191KB packet
  超出；重試見二輪）。

### 首輪 reconciliation（primary 逐項回查源碼）

| Finding | 判定 | 處置 |
|---|---|---|
| P2-1：`validate_new_topic_formula_topics` 用 PG `btrim` 預設集，`\t`／U+3000 whitespace-only 可過 DB tripwire、卻被 TS replay validator 拒 → replay 斷 | **TP** | 已修：migration 改用對齊 JS/Dart trim 的顯式 whitespace 集合（含 U+000B/U+00A0/U+2000–200A/U+2028/29/202F/205F/3000/FEFF）；只會更嚴、不會誤殺 JS-trimmed canonical；topics 欄位維持 v1 部署語意不動。smoke S4 補 `\t`＋U+3000 拒絕態 |
| P2-2：prompt JSON schema placeholder（「公式開場第一則：…」等）不在排除集，模型照抄會成 canonical 並進 ledger/replay | **TP** | 已修：四條 openingLine placeholder 加入 `FORMULA_PROMPT_EXAMPLE_LINES`；新增 `FORMULA_PROMPT_PLACEHOLDER_NOTES`（whyItWorks「一句教練註解…」三式，dedupe-key 全等才丟、不誤殺真教練註解）；sync 測試改掃 index.ts＋new_topic_prompt.ts 並反向驗 placeholder 必在排除集 |
| P2-3：§11.2/11.3 的 request-level 情境（repair 次數、HTTP status、扣費、fresh/replay body）沒有可執行 handler 測試，只有 helper 單元＋source-scan | **Partial TP／accepted risk** | index.ts import 即啟動 server，repo 既有慣例（見 opener_payload.ts 頂註）只支援 source-scan；New Topic 本體（已部署）同樣以 helper 單元＋source anchors 出貨。本案再加兩層：`buildNewTopicLedgerResult.formulaTopics` 必填（漏接 ledger 編譯期失敗）＋分支順序 anchors。handler test harness 是獨立工程，不在本案 scope；列 open concern |
| Minor：packet 未寫死 review range | **TP** | 已修（本檔 Range 節） |
| Uncertain：marker 換 v2 讓舊 Edge readiness 失敗 | **FP** | index.ts 全檔無 `new_topic_contract_version()`／`NEW_TOPIC_CONTRACT_VERSION` 任何 runtime 引用（grep 證據）；marker 只供部署 runbook 手動驗證，舊 Edge 不比對 |
| Uncertain：migration 檔無 BEGIN/COMMIT，transactionality 依 runner | **TP as runbook 條款** | 部署固定走 Management API 目標式 apply（單 query＝單 transaction；前例 20260724120000 同法、禁 `db push`）。已記入部署節 |

### 二輪

最終審查 range：**`aad497d0..287e4717`**（＋本檔所在 docs commit）。

- Codex re-review（對修復 diff `2347f166..25941bf8`）：**NOT APPROVED**——
  P2-1 閉合但抓到新缺口 U+0085（NEL 只有 Dart 視為空白），並主張 P2-3
  的 accepted-risk 需要需求方（Eric）明示 waiver、非實作方自行接受。
- GLM adversarial（focused packet：normalizer＋migration＋validators＋
  handler 節錄＋Dart guard；glm-5.2）：**0 P0/P1、2 P2、1 uncertain**，
  五項正確性主張逐項判定「正常流程下均成立」。
  - 註：GLM 前兩呼空回（`GLM returned no content`）根因＝wrapper
    `max_tokens=8192` 被 reasoning 吃光；已修 wrapper（65536）後成功。
    此為 host-local infra 修復，不在本 repo。

### 二輪 reconciliation

| Finding | 判定 | 處置 |
|---|---|---|
| Codex：U+0085 NEL 空白缺口（Dart trim 吃、JS/PG 不吃） | **TP** | 已修（`287e4717`）：normalizer／TS ledger validator／migration 三層改「JS/Dart trim 聯集」判空；smoke S4 補 U+0085 態；含實字欄位不誤殺（有測試）。Deno 723/723 綠。**因兩輪上限已滿，此修復未再送 Codex 三審**——修復內容單純（whitespace 集合＋一行 regex），證據齊備，殘餘驗證留給 Eric 裁示 |
| Codex：P2-3 需求方 waiver（request-level handler 測試缺席） | **維持 open，交 Eric 決策** | Codex 主張正確：accepted-risk 應由需求擁有者拍板。選項：(a) waiver——沿用 New Topic 本體同級保證（helper 單元＋source anchors＋編譯期必填）出貨；(b) 另開案建 handler test harness（獨立工程）再收此案。**在 Eric 拍板前，本案不得宣稱 review APPROVED** |
| Codex minor：sync 測試非完整反向檢查（新增 placeholder 不會被抓） | **TP（殘餘 minor）** | 已知限制：正向（排除集字串必在 prompt 源）＋反向（四條既知 placeholder 必在排除集）都鎖住既有面；「未來新增第五條 placeholder 忘記入排除集」仍靠 review 紀律。單一資料源重構（prompt 由常數插值組裝）會犧牲 prompt 可讀性與既有 source-scan 慣例，判不值得，列 residual |
| Codex minor：packet 未寫死最終 range | **TP** | 已修（本節） |
| Codex uncertain：migration transactionality 無執行證據 | **維持 runbook 條款** | 部署當日以 Management API 單 query 套用並先在測試庫演練失敗回滾（部署節新增步驟 0） |
| Codex uncertain：舊部署 Edge 是否引用 marker | **FP（可最終確認）** | 現行 production Edge＝main 部署（git 可回溯）；全 repo grep 無 runtime 引用；marker 於 20260724120000 引入至今只用於 runbook 手動驗證。部署前可對 prod 舊 revision artifact 再 grep 一次收尾 |
| GLM P2-1：Dart 不修剪 U+FEFF → 三方空白語意不一致 | **FP（實證推翻）** | Dart 3.11 實測 `"﻿".trim().isEmpty == true`（Dart String.trim 依文件額外修剪 BOM）；`"".trim().isEmpty == true` 同時佐證 U+0085 修復方向正確 |
| GLM P2-2：droppedCount 把「未檢查項」也算 dropped、註解自相矛盾 | **TP（僅註解語病）** | 行為與計畫 §8 binding 定義完全一致（array 長度−canonical 數、含超過兩則）；已改註解措辭消歧義，行為零變更 |
| GLM U-1：repair 路徑不重取 formula／repair parsed 是否 strip | **FP／by-design** | 計畫 §6.1 binding：「Repair 回覆即使意外含 formula，也不得採用」——不重取是規格要求；`repairMalformedOpenerPayload` 內部即過 `normalizeOpenerPayload`（strip formulaOpeners），response 再以 canonical 覆蓋（雙層），且有 source-scan 測試鎖 repair 分支不得讀寫 formula |

### 最終狀態

- **0 P0／P1（兩位審查者一致）**；核心契約隔離、ledger 相容、raw 不穿透、
  grounding 守門、tier/quota 不變：兩位審查者均判正確。
- **未達 APPROVED**：唯一 blocker＝Codex 主張 §11.2/11.3 request-level
  測試缺席需 Eric 明示 waiver（或另開 harness 案）；連帶 U+0085 修復
  （`287e4717`）因兩輪上限未經 Codex 複核。
- 依計畫 §14：兩輪已滿、仍有 blocker → 停，不宣稱 safe，交 Eric 裁示。

## 部署執行紀錄（2026-07-24，Eric 授權後執行）

依部署閘門順序全數通過：

1. **乾跑演練**：`BEGIN＋整份 migration＋ROLLBACK` 經 Management API 對
   prod 真資料執行成功（交易內 marker 讀 v2、回滾後仍 v1）——單 query＝
   單 transaction 的原子性有執行證據（Codex 二審 uncertain 閉合）。
2. **Migration**：`20260724180000_new_topic_formula_topics.sql` 正式套用
   （單交易含 `schema_migrations` 版本記錄）。
3. **驗證**：marker=`new-topic-exactly-once-v2`；RLS enabled；cron 存在；
   7 筆 legacy rows 通過新 constraint（constraint def 含 formulaTopics）；
   privilege 矩陣 7 函式 anon/authenticated 全 false、service_role 全 true。
4. **PG smoke（真 PostgreSQL，測試帳號，S1–S14 全過）**：legacy 三-key
   合法、四-key 0/1/2 合法（Free/Paid）、三則/缺欄/whitespace-only
   （\t、U+3000、U+0085）/超長/多鍵/非 array/未知頂層鍵全拒、invalid
   formula settle RAISE＋quota/result 同交易回滾、legacy 與 new shape
   fresh settle＋claim replay 同 body、late owner 回 stored winner、
   marker v2、RLS＋helper privilege 正確。單交易 ROLLBACK 零殘留
   （rows=7、test counter=0）。
5. **Deploy**：push `aad497d0..144df84f` → CI「Deploy Edge Function」
   run 30088982621 → **success**。
6. **Live smoke（production、測試帳號免扣）**：
   `tools/new-topic-formula/live_formula_smoke.ts`
   - Opener v1（無 contractVersion）：200、五卡、不炸。
   - Opener v2 ×10：全 200、五型完整、formula 0/1/2＝0/0/10、canonical
     形狀＋無內部標籤全過、outputTokens 1701–1856／3000、avg 34.2s。
   - New Topic fresh ×10：全 200、五題＋usage.cost=3、formula＝0/0/10、
     avg 25.2s；同 requestId replay body 與 fresh **完全一致**。
   - Edge telemetry（function_logs）：`new_topic_success` outputTokens
     1301–1382／3000、stopReason=end_turn、repaired=false、
     formulaTopicsCount=2、DroppedCount=0——§8 evidence gate 已閉合
     （≥20 樣本、無截斷證據，token cap 3000 維持正確）。
   - smoke 產生的測試 rows 已刪（rows 回 7）。

## 未執行（留待後續）

- iOS build（僅 Eric 手動 dispatch）與真機 dogfood（公式卡目檢：區塊
  順序、複製、長文、窄螢幕）。

## Open concerns → Eric 裁示結果（2026-07-24）

Eric 三題全數拍板（「好 我點頭 3題都照你的」）：

1. **P2-3 waiver：核准（選項 a）**——沿用已部署 New Topic 本體同級保證
   （helper 單元＋source anchors＋編譯期必填）出貨；handler test harness
   列技術債候選、另案。**Review gate 自此＝APPROVED with waiver**。
2. U+0085 修復（`287e4717`）不補 Codex 三審：核准。
3. push／migration／Edge deploy／live smoke：**授權執行**（順序鐵則
   migration-first；本節下方部署紀錄為準）。

殘餘（非 blocker）：
- Sync 測試對「未來新增 prompt placeholder」無自動防護（residual minor）。
- New Topic token 分布於部署後 live smoke 補量測（§8 evidence gate）。

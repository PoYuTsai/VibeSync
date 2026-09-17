# 開場救星兩段式（以用戶自己的想法為核心）— 複核包

日期：2026-09-17　分支：`opener-two-stage`　狀態：本機實作完成、**待獨立 review**；未 push、未開 PR、未部署 Edge／Web、未動正式資料庫、未觸發 Build & Distribute。

## 1. 基準與工作樹

| 項目 | 值 |
|---|---|
| base（origin/main，含夜市整合 v7） | `3134c5139df3d9a2d8f7040328d2372ff0198f22` |
| head | 見 `HEAD.txt`（複核 ZIP 內）與 `git log --oneline main..opener-two-stage` |
| worktree | `/home/eric1/worktrees/vibesync-opener-two-stage-20260917` |
| 附件歷史基準 `abc2d6ca` | 只當檢查基準；實作基於目前 main，保留夜市的帳號隔離／操作序號／error 哨兵值修正 |
| 既有兩段式工作 | repo 內 `feature/two-stage-analyze` 是 analyze（非 opener）的已封存計畫，與本案無關；附件提到的夥伴工作樹不在本 repo，未重用 |

Commits（一 commit 一關注）：

1. `1/6` migration `20260917120000_opener_two_stage_sessions.sql`＋PGlite 契約測試＋delete-account／CI 清單
2. `2/6` Edge：`request_shape`／`analyze_chat_handler` 分派、`opener_stage`／`opener_material`／`opener_flow_prompt`／`opener_flow_payload`／`opener_session`／`opener_flow_handler`、`opener_stream` 階段、端到端測試
3. `3/6` Flutter：`opener_flow_models`、`OpenerService` 兩段式、`OpenerFlowController`、草稿延伸、`opener_flow_sections`、畫面接線、測試
4. `4/6` 評估工具 `tools/opener-two-stage-eval`＋ADR #47 草案
5. `5/6` 本複核包
6. `6/6`（跨模型審查後的修正，如有）

## 2. 產品決策落點（交辦第二節）

| 決策 | 落點 |
|---|---|
| 先分析、再補充／略過、按生成才第二段；最多一題、零題合法、不預選 | Edge `opener_stage.sanitizeQuestion`（<2 合法選項→null）；App `OpenerContributionCard`（無預選）；F01 端到端測試 |
| 分析與問題卡對 Free 完整可用；第二段沿用 Free 三／付費五 | 第一段不看 tier；第二段 `visibleTypesFor` 同舊單段 |
| 原句優先、想法獨立於「關於我」、不新增跨局記憶 | 生成 prompt §原料怎麼用；兩段式不注入 effectiveStyleContext；快照不存初稿原文 |
| 分析不扣；首次成功才扣 3；客觀零扣費沿用；補充不冒充對方資料；insufficientInfo 不決定免費 | `handleOpenerAnalyzeRequest`：`serverEligibleForNoCharge` 只看 images＋profileInfo；`settle_opener_generation` 首次扣費 |
| 一局三組＝首次＋兩次；重試取回同組；失敗不扣不占 | `claim_opener_generation`（同 ID replay／限次）、`settle_opener_generation`（generations_used +1）、release on failure |
| 24 小時固定到期、不存圖片、到期清理＋帳號刪除＋存取權限 | `expires_at = now()+ttl` 只在 settle 設；`cleanup_expired_opener_sessions` pg_cron；`auth.users ON DELETE CASCADE`＋delete-account 顯式；RLS 開啟無 policy |
| 兩階段共用限流、不放寬；模型限流不導購 | `enforceModelRateLimit scope "opener"` 兩段都用；`MODEL_RATE_LIMITED` 429 無額度鍵；App 走一般錯誤 |

## 3. F／B 驗收對照

「驗證方式」欄：`E2E`＝`opener_flow_handler_test.ts`（正式 handler＋PGlite 真 SQL＋正式原料整理／投影／結算，只替換模型）；`PG`＝`opener_two_stage_migration_postgres_test.ts`；`unit`＝純函式；`widget`＝`opening_rescue_two_stage_test.dart`；`ctrl`＝`opener_flow_controller_test.dart`；`靜態`＝程式核對未動態還原。

| # | 情境 | 狀態 | 驗證方式 |
|---|---|---|---|
| F01 | 只按分析 | ✅ | E2E「F01／B01」、widget「F01」 |
| F02 | 先提供完整想法不重問 | ⚠ 模型行為 | prompt 規則（初稿已說清楚→question null）；初稿有傳給模型（E2E「初稿只記有無」）；是否真的不重問待真模型評估 |
| F03 | 選狗不轉成養狗事實 | ✅ 程式層 | unit `opener_material` F03（pick_cue 不授權 sender_fact；「我家那隻」硬錯誤） |
| F04 | 沒養只是好奇 | ✅ 程式層 | unit F04（否定反轉硬錯誤；no-experience 線索＋我也＝捏造）、E2E B08 修正路徑 |
| F05 | 我妹也是美容師保留主體 | ⚠ 程式層可核／語意待盲審 | unit F05／F14（原文原樣進原料、不被清洗）；主體正確與否靠 materialReading＋盲審 |
| F06 | 以前養過現在沒有 | ✅ 程式層 | unit F06（否定片段抽出、寫成肯定＝硬錯誤） |
| F07 | 想約咖啡不寫成她答應 | ⚠ 語意 | prompt 規則＋原料限制文字；無確定性檢查（評估 fixture `goal-not-consent` 有禁字） |
| F08 | 她曾說 vs 我猜 | ⚠ 語意 | prompt＋materialReading certainty；fixture `she-said-vs-guess` |
| F09 | 都沒興趣→排除入口 | ✅ | unit F09（全部線索進排除清單、用上＝硬錯誤、方向改 fresh_topic） |
| F10 | 略過／沒回答／都可以可分辨 | ✅ | unit F10、E2E「F10／略過」（inputState、traceStatus=no_input、displayNote=null） |
| F11 | 原句保留核心意思 | ⚠ 語意 | prompt「推薦卡優先保留原意」；fixture `raw-sentence`；待盲審 |
| F12 | 別局選項／偽造分析在模型前拒絕 | ✅ | E2E「F12」、unit `validateContributionAgainstSnapshot`；第二段不收 App 傳的分析 |
| F13 | Free 可見推薦可採用、理由不引鎖定內容 | ✅ | unit `opener_flow_payload` F13、E2E B02／F13 |
| F14 | 舊共鳴組句器不作用於新路徑 | ✅ | 新路徑用 `opener_flow_payload.normalizeOpenerGenerateOutput`（不呼叫 composeResonateOpener／stripFirstPersonClauses）；unit F14 |
| F15 | 換圖／改自介→舊分析失效 | ✅ | widget「F15」、ctrl `resetForInputChange`；伺服器端同 analysisRequestId 換輸入 409（PG） |
| F16 | 只改回答→新 generationId、舊答案不復活 | ✅ | ctrl「改回答新 id」、E2E「F16／回歸」（刪初稿改聊咖啡：第二段 user content 不含初稿；快照不存初稿） |
| F17 | 新舊請求交錯 | ✅ | ctrl「F17 舊結果晚回」「切換帳號」（作廢、不寫草稿）；伺服器 owner token（PG B13） |
| F18 | 聊天截圖引導既有分析 | ✅ | E2E「wrongSurface→422 不建立會話」；App `OpenerFlowException.surface`（service test） |
| F19 | 舊 App 與新話題 tab | ✅ 靜態＋既有測試 | `mode: opener` 路徑零改動（source-scan 1037 綠）；`NewTopicView` 未動；舊草稿 flow=null 照讀（cache flow test） |
| F20 | 中文／emoji／300 字邊界一致 | ✅ | unit `graphemeLength`（Intl.Segmenter grapheme＝Flutter `characters`）；剛好 300 放行、301 拒絕且回報字數不截斷 |
| B01 | 分析完離開不扣 | ✅ | PG、E2E |
| B02 | 首次成功扣 3、成功數 1 | ✅ | PG、E2E |
| B03 | 零扣費條件扣 0 仍建會話與次數 | ✅ | PG B03 |
| B04 | 改回答再成功兩次總扣 3、三組不同 ID | ✅ | PG B02/B04、E2E B04 |
| B05 | 第四組在模型前擋 | ✅ | PG（claim RAISE）、E2E（模型呼叫數不變） |
| B06 | 傳輸遺失同 ID 重試取回同組 | ✅ | PG、E2E（不打模型、不重扣） |
| B07 | 連點／兩裝置同局單一執行中 | ✅ | PG（session_busy／pending）、E2E B07；App ctrl 忙碌中不重送 |
| B08 | 模型／格式／硬檢查失敗不扣不占 | ✅ | E2E B08（503 release；硬錯誤一次修正；仍錯 502）、格式修復測試 |
| B09 | 同 ID 改答案輸入不一致 | ✅ | PG、E2E |
| B10 | 首次扣費時額度已被用掉→回滾 | ✅ | PG（QUOTA_EXCEEDED 回滾、結果不落地）、E2E（429 帶額度鍵、作業釋放） |
| B11 | 已扣費同局額度歸零仍可生成 | ✅ | PG、E2E |
| B12 | 到期不自動重扣、不開新付費流程 | ✅ | PG（claim／settle 都拒絕；同 analysisRequestId 只回 expired）、E2E |
| B13 | 租約接手後舊作業晚回不能結算 | ✅ | PG B13（OWNER_MISMATCH、晚回 settle 回接手者結果） |
| B14 | 不同帳號猜 sessionId | ✅ | PG、E2E（404） |
| B15 | 模型限流不扣次數不彈升級 | ✅ | E2E B15（真 `increment_model_usage` SQL：第 4 次/分 429、無額度鍵、作業釋放、重播不計次） |

已知未涵蓋／取捨：

- **語意層**（F02／F05 主體／F07／F08／F11）只有 prompt 與 traceStatus，程式不宣稱已驗；`matched` 只代表來源紀錄對得上。待真模型成對評估與盲審。
- 確定性檢查認線索字眼：「我家那隻狗」在線索為「養狗」時不會被程式抓到（測試已標註），留給盲審與後續裁判模型。
- PGlite 單連線：併發語意以兩個 owner token 交錯驗證（claim／pending／takeover），非真並行交易。本機 Postgres 16 無可用角色（peer auth 失敗、無 sudo），未做真並行。
- 串流 handler 測試用替身 `invokeModel` 直接推整段 rawText 當 chunk；`callClaudeStreaming` 真串流未動態還原（沿用既有 opener／new_topic 同型程式）。
- 到期清理的 pg_cron 排程在 PGlite 以 GUC 放行只驗函式本體（沿既有 retention 測試慣例）。

## 4. 測試指令與結果

| 指令（於 worktree 根目錄） | 結果 | 原始 log |
|---|---|---|
| `deno test --allow-env --allow-read supabase/functions/analyze-chat` | 1037 passed / 0 failed，exit 0 | `logs/deno_analyze_chat_full.log`（含 PGlite 18 條、E2E 19 條、純函式 25 條、source-scan 3 條） |
| `deno test --allow-env --allow-read supabase/functions/delete-account supabase/functions/_shared` | 107 passed，exit 0 | `logs/deno_shared_delete_account.log` |
| `deno check`／`deno lint`（新檔） | 乾淨 | — |
| `flutter analyze` | 1 issue（`test/widget/features/empty_home_paged_overflow_test.dart` unnecessary_import，main 既有，非本案） | `logs/flutter_analyze.log` |
| `flutter test test/unit/features/opener` | 150 passed，exit 0 | `logs/flutter_test_opener.log` |
| `flutter test`（全套） | 見 `logs/flutter_test_full.log` 與 `logs/flutter_test_full.exit` | 同左 |
| `deno run … tools/opener-two-stage-eval/run.ts --tag=dry-run` | dry-run 完成：156 次呼叫預估 ≈ $4.2 | `logs/eval_dry_run_summary.md` |

先紅後綠證據（測試先失敗、再改程式）：

- 手動輸入的初稿在第一段被當成對方資料？→ E2E「零扣費判準只看對方資料」先寫（初稿不算 substance），實作即通過；未做動態還原（靜態核對）。
- 「沒養但有興趣」卻寫「我也養狗」：E2E B08 第一版**失敗**（有用戶原文時 `senderFactAllowed=true`，程式未抓到）→ 加 `noExperienceTopics` 規則後轉綠（log 見 `logs/red_green_b08.txt`）。
- 次數用完後畫面仍顯示剩 1：ctrl 測試先失敗（`generationsRemaining` 取舊結果用量）→ 改以 analysis 為準後轉綠。
- 「改聊咖啡」未覆蓋已選線索：ctrl 測試先失敗 → `OpenerContributionConflict` 加「改聊…」覆蓋規則後轉綠。
- 環境相關（非產品缺陷）：widget 測試三次卡死（`ensureVisible` 捲動動畫、fake-async 下 Hive 寫入、缺 coaching outcome box），已在測試內以有界 pump／`runAsync`／provider override 處理。

## 5. 未完成驗收與待授權

- **真模型成對評估未跑**：工具、fixtures（12 組×A／B／略過＋舊單段對照）、dry-run 與預算（≈$4.2／156 次，Sonnet 5）已備；請 Eric 授權後執行 `--run --confirm-paid`，再做盲審評分（附件 §14.4 門檻）。
- **iPhone 真機驗收未做**：Eric 需走「分析→補充→生成→調整再生成→回看草稿」；額度顯示、paywall、限流文案、到期卡。
- **收費時點與 24h 保存**是附件建議（ADR #47 Proposed），待 Eric 拍板。
- 事件埋點（analysis_ready／question_answered／generation_completed…）未新增 client funnel 事件（需同批改 client 字典＋Edge funnel_utils＋文件，屬另案）；Edge 端 `opener_analyze_success`／`opener_generate_success` log 只記數量與狀態，不記補充全文。

## 6. Migration／Edge 部署順序與回退

1. 先套 `supabase/migrations/20260917120000_opener_two_stage_sessions.sql`（Supabase MCP `apply_migration`，不 `db push`）；驗 `select public.opener_flow_contract_version()` 回 `opener-two-stage-v1`、pg_cron job `cleanup-expired-opener-sessions` 存在。純新增物件，對現行 Edge／App 零影響。
2. 再部署 `analyze-chat`（`--no-verify-jwt`）。Edge 先上、migration 未套時：第一段回 503 `OPENER_FLOW_UNAVAILABLE`，新 App 退回舊單段，不會壞。
3. App 發版後才有兩段式流量；舊 App 完全不受影響。
4. 回退：設 `OPENER_TWO_STAGE_ENABLED=false`（只停新局，既有有效局仍可完成／取回）；或 App 端退回舊單段（自動）。表與 RPC 可留（無外部依賴），要徹底移除時 drop 兩表與六支 RPC＋unschedule cron。
5. 環境變數：無新 secret；`OPENER_STREAM_ENABLED`（既有）控制串流；`OPENER_TWO_STAGE_ENABLED` 預設視為開啟。

## 7. 跨模型審查

見 `docs/reviews/2026-09-17-opener-two-stage-review-packet.md` 末段「審查結果」（由 dual-brain-review 補上）。

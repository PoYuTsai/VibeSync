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
| `flutter test`（全套，fb40b62a） | 3857 passed，exit 0 | `logs/flutter_test_full.log` |
| **修正後重跑**（新 head）：Deno analyze-chat／shared＋delete-account／opener Flutter（unit＋widget＋slop）／全套 Flutter／analyze | 見 `logs/r1_*`（各有 `.exit`） | 同左 |
| **第二輪修正後重跑**（新 head）：Deno analyze-chat 全套／opener Flutter（unit＋widget＋slop）／全套 Flutter／analyze／eval dry-run | 見 `logs/r2_*`（各有 `.exit`）；先紅證據 `logs/red_r2_*.txt` | 同左 |
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
- 收費時點（分析免費、首次可交付生成扣一般 3／既有條件 0、一局三組）與 24h 保存：Eric 2026-09-17 交辦即採用（ADR #47），不再是待決項。
- 事件埋點（analysis_ready／question_answered／generation_completed…）未新增 client funnel 事件（需同批改 client 字典＋Edge funnel_utils＋文件，屬另案）；Edge 端 `opener_analyze_success`／`opener_generate_success` log 只記數量與狀態，不記補充全文。

## 6. Migration／Edge 部署順序與回退

1. 先套 `supabase/migrations/20260917120000_opener_two_stage_sessions.sql`（Supabase MCP `apply_migration`，不 `db push`）；驗 `select public.opener_flow_contract_version()` 回 `opener-two-stage-v1`、pg_cron job `cleanup-expired-opener-sessions` 存在。純新增物件，對現行 Edge／App 零影響。
2. 再部署 `analyze-chat`（`--no-verify-jwt`）。Edge 先上、migration 未套時：第一段回 503 `OPENER_FLOW_UNAVAILABLE`，新 App 退回舊單段，不會壞。
3. App 發版後才有兩段式流量；舊 App 完全不受影響。
4. 回退：設 `OPENER_TWO_STAGE_ENABLED=false`（只停新局，既有有效局仍可完成／取回）；或 App 端退回舊單段（自動）。表與 RPC 可留（無外部依賴），要徹底移除時 drop 兩表與六支 RPC＋unschedule cron。
5. 環境變數：無新 secret；`OPENER_STREAM_ENABLED`（既有）控制串流；`OPENER_TWO_STAGE_ENABLED` 預設視為開啟。

## 8. 第一輪獨立複核（BLOCK）修正對照 — 2026-09-17／18

審查來源：ChatGPT 獨立交付包複核（`OPENER_R1_fb40b62a_REVIEW.md`，全文由 Eric 貼入會話；附件 ZIP 與 `probes/` 在本機找不到，reviewer 的純函式 probe 與 SQL 候選**未收到**，以下回歸是依審查描述自行寫的等價案例，不冒稱是 reviewer 已執行的結果）。修正基準 `fb40b62a`；新 head 見 ZIP `HEAD.txt`。

| 項 | 缺口 | 先紅證據 | 修正 | 綠燈 |
|---|---|---|---|---|
| R1 P1 | 既有 run 接手不查同局其他有效工作／上限；settle 只比 owner；release 刪掉輸入身分 | `opener_two_stage_migration_postgres_test.ts` R1-a～R1-d 在 fb40b62a 版 4/4 FAILED（`logs/red_r1_sql.txt`） | migration：claim 對「新 ID／過期接手／released 重取」統一先查上限再查同局唯一有效租約，同 owner 有效租約才續租；settle 要求 run 租約仍有效且同局無其他有效租約（`OPENER_OPERATION_LEASE_EXPIRED`）；release 改 state=`released` 保留 input_hash／回答；Edge 對映新碼、E2E `runCount` 只算 pending/done | PG 22 綠（含 B08 改為斷言 released） |
| R1 P2 真並行 | PGlite 單連線 | — | 未做（本機 Postgres 16 無可用角色、無 sudo） | **待驗**（真並行交錯交易） |
| R2a P1 | 未完成操作只在記憶體；retry 用目前 draft | `opener_flow_controller_test.dart` R2a×3 在舊版無法編譯（API 不存在，型別紅） | `OpenerDraft.result` 可空、`OpenerDraftFlow` 加 stage／analysisRequestId／指紋／`pendingGeneration`；分析完成即落地、生成送出前落地送出快照；`restoreDraft`＋`resumePendingGeneration` 用原 generationId 取回；retry 沿用送出快照，`generate(fresh:true)` 才是新操作；同一份紀錄隨階段更新 | ctrl 18 綠、cache 4 綠 |
| R2b P1 | saveDraft 內 `_saveDrafts→await→saveLatest` 重讀 owner | `opener_result_cache_owner_test.dart` 在 fb40b62a：A 的整份草稿清單被寫進 B 的 key（`logs/red_r2b_cache.txt`） | 所有跨 await 寫入以操作起點 owner 一路帶到 drafts／latest；新增 `updateDraft` 同樣綁定 | 綠 |
| R3a P1 | 白名單類型≠statement 與題目一致 | `opener_stage_test.ts` R3a×2（舊版 API 型別紅） | `senderFactOptionConsistent`：標籤與 statement 不得含否定／轉向詞、statement 主體必須是本人（非我妹／朋友…）、與線索有字面重疊；不一致選項丟掉，剩不足兩個→零題 | 綠 |
| R3b P1 | 刪初稿後衍生 summary 仍進第二段 | E2E「R3b」在舊 handler 不可編譯（新簽名）；語意等價的探針見 reviewer 描述 | 快照存初稿 FNV 指紋（不存原文）；`approachStillApplies`：只有目前補充與初稿相同才沿用 summary／avoid，否則第二段明說「初稿已修改，不採用」；分析 prompt 禁止 digest 寫入初稿內容 | E2E 綠（含「同初稿原封送回可沿用」對照） |
| R3 P2 | displayNote 整包全域 | payload 測試改 `displayNotes` 後紅 | 每張卡自己的 `displayNotes`；投影只取最終可見 pick 且該卡有對得上的 reference；修正合併只換被標記卡的說明；整包 `displayNote` 不採用 | payload 7 綠 |
| R4a P2 | 舊草稿在兩段式畫面看不到 | widget「R4a」 | `_legacyDraftView`：舊草稿結果在兩段式畫面可見、可複製回報、有提示、不觸發分析扣費；改資料即清 | 綠 |
| R4b P2 | formatter 靜默截斷 | widget「R4b」×2、ctrl「R4b」 | 拿掉 `LengthLimitingTextInputFormatter`；超長保留原文、計數變紅＋錯誤、分析／生成禁用；controller 端也擋 | 綠（中文 300／emoji 301） |
| R5 P2 | 修復＋修正各一次＝三次呼叫；usage 只記首次 | E2E「R5」在探針（預算=2）下 FAILED（`logs/red_r5_r6b.txt`） | `extraCallsRemaining=1` 共用；累加所有嘗試 usage，`usageComplete=false` 標示未知 | 綠 |
| R6a P2 | 評估控制組注入 A、只 paid 投影、任一卡命中 | — | 控制組＝原樣舊單段（走舊 normalize＋tier 投影）；`--legacy-plus-a` 才跑附加實驗；Free／paid 投影分開、推薦採用只看該投影的可見推薦、備選另計；兩組樣本附初稿；未涵蓋項目明列 | dry-run 重估（`logs/r1_eval_dry_run_summary.md`） |
| R6b P2 | 旗標在 claim 前擋掉既有分析重播 | E2E「R6b」在探針（旗標前置）下 FAILED（`logs/red_r5_r6b.txt`） | 旗標檢查移到 claim 之後：replay 照回；只有真的新局才 release＋503 | 綠 |

本輪未動：舊 `mode: opener`、夜市已接受 P2、與本輪無關的重構。

## 9. 第二輪獨立複核（BLOCK）修正對照 — 2026-09-18

審查基準 `83c278f3`。已修正項（R1、R2b、R3b、R4、R5、R6b）保留不重做。reviewer 的純函式 probe 已由 reviewer 執行；其候選 Flutter／Deno 測試**未送達本機**，以下回歸是依審查描述自行寫的等價案例。三組都先在 `83c278f3` 上證明失敗（`logs/red_r2_a.txt`、`logs/red_r2_b_c.txt`）再修正。

| 項 | 缺口 | 先紅證據（83c278f3） | 修正 | 綠燈 |
|---|---|---|---|---|
| A R2a 持久化 | `selectOption`／`setFreeText` 只改記憶體；生成等待中的修改不落地；`_persistFlow` 回 null 仍送出可扣費 API；分析未返回時無恢復路徑 | ctrl「R2a-2」×4：選項落地 `option_2` 得 null；等待中修改落地得舊值；保存失敗仍呼叫 generate 1 次；分析送出後 `loadDrafts()` 為空（第 4 題另有新 API 型別紅） | 回答區每次修改經 `_persistDraftEdit` 落地到同一份紀錄，只換 `contributionDraft`、送出快照與結果原樣；`_runGenerate` 的 pending 落地是必要 checkpoint：回 null 就不打 API、輸入保留、`failedOperation=generate` 讓「再試一次」同 ID 重來；新增 `OpenerDraftFlowStage.analyzing`＋`OpenerPendingAnalysis`（文字欄位＋初稿＋張數，不存圖）：分析送出前落地，`restoreDraft` 填回輸入並 `adopt` 原 analysisRequestId／指紋，`resumePendingAnalysis` 同 ID 續分析（有圖時只填回、等用戶重新上傳）；同一份紀錄 analyzing→analyzed→generating→result；所有寫入經排隊（依發生順序）且綁定這局帳號（`_sessionOwner`），切帳後寫入略過；輸入一改就刪掉沒有內容的 analyzing 紀錄 | ctrl 22 綠、widget「R2a-2」×2（analyzing 草稿回看→欄位填回＋同 ID 續分析；只改回答→重建畫面回看同一份回答） |
| B R3a 選項授權 | 「都有我、沒否定、cue 同字」就把隱藏 statement 當授權：「我對咖啡有興趣」→「我是咖啡師」、「我剛開始養狗」→「我養狗十年」 | `opener_option_authorization_test.ts`（正式路徑 snapshot→選項清洗→materials→prompt）3/4 FAILED：原料出現「我是咖啡師」「我養狗十年」 | 授權的自述＝用戶實際看見並選取的 label（`senderFactStatementFromLabel`）；模型的 statement 一律不採用；label 不是肯定的本人第一人稱句（如「有養」）→無法確認就不授權、選項丟掉；刪掉線索字面重疊啟發式；prompt 改為 label 本身就是完整句、不要再寫 statement | 4 綠；既有 R3a 兩題與「題目清洗」改斷言 statement＝label；合法自述／否定／家人主體對照保留 |
| C R6a 控制組 | `legacyUserBase` 從含初稿的第一段 user content 只刪尾句，raw-sentence／explicit-exclusion 的初稿污染控制組 | `control_test.ts` 2/3 FAILED（control.ts 先以現行 run.ts 內聯邏輯逐字抽出） | 舊單段 user content 抽成 `buildLegacyOpenerUserContent`（`opener_prompt.ts`，handler 改呼叫它、字句順序不變、既有 source guard 不改）；控制組只由對方資料經這條正式路徑建立，初稿與 A／B 都碰不到；`--legacy-plus-a` 附加實驗接在其後；Free／paid 分開投影保留 | 3 綠；analyze-chat 全套綠；dry-run 重估仍 156 次≈$4.23 |

未變：真 Postgres 並行、真模型評估、iPhone 真機驗收仍待驗，不冒稱完成。

## 7. 跨模型審查

**第一輪：BLOCK → 已修正（§8）。第二輪：BLOCK（基準 83c278f3）→ 已修正（§9），待第三輪確認。**

原第一輪派審阻塞紀錄（保留）：

- 2026-09-17 12:50Z `graph-control quota refresh-codex`（無模型呼叫的 App Server 預檢）：Codex 共用配額剩 **1%**（門檻 10%），依 routing-policy 不得派 `codex-primary`；`codex-secondary` 只在 primary 真正可用性／權益／用量失敗時才用，這裡是配額耗盡，不是本案可自行切換的情境。
- Grok（`grok-primary`）與 GLM 5.3 為計費路線，需 Eric 對本 snapshot 明確授權（`work authorize-metered-provider` / cross-model-review 授權），本回合沒有。
- 依全域政策：獨立 review 不可用時，R2 本機工作維持「已實作、已驗證、已 commit、**未審查**」，停在 push 之前；本案本來就停在待 review，不影響交付狀態。

配額恢復或 Eric 授權後的派審指令（以本複核包的最終 head 為 snapshot；work-id 見 `HEAD.txt`／最終回報）：

```
APPDATA=/home/eric1/.local node ~/.claude/skills/graph-control-plane/scripts/graph-control.mjs quota refresh-codex
APPDATA=/home/eric1/.local node ~/.claude/skills/graph-control-plane/scripts/graph-control.mjs review dispatch \
  --project-root /home/eric1/worktrees/vibesync-opener-two-stage-20260917 --work-id <id> \
  --active-host claude --round 1 \
  --instructions "R2/R3：計費（settle 同交易、首次扣費、三組、重播）、Edge 合約與串流交付邊界、24h 保存與 RLS、原料檢核繞過、App 回退與帳號隔離；範圍＝base 3134c513..head diff；語意品質留待真模型盲審"
```

審查焦點建議（給主審）：settle RPC 的 RAISE→回滾語義；claim 的 session_busy／pending／takeover 對兩裝置；`OPENER_OPERATION_OWNER_MISMATCH` 在 settle 的不 release 處理；`serverEligibleForNoCharge` 是否可被補充文字影響；App 舊 Edge 偵測（400 無 code）是否會把真正的 400 誤判成不支援；草稿 flow 欄位在降級 Free 後的鎖卡投影（沿用 `visibleForAccess`）。

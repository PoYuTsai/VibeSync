# 單發重設計 v2 四路黑箱 eval 報告（滾動更新；最新狀態見文末「第 5 輪」）

- 日期：2026-07-23（跑於 hint/debrief 單發切換完成、reviewer 拆除後的 6f12f1d8）
- 工具：`tools/practice_single_shot_eval/run_eval.ts`（真 Anthropic API，本機直呼生成函式，未碰 prod）
- 規模：四路 × 5 fixture × 4 重複 = 80 發
- 原始結果 JSON：`tools/practice_single_shot_eval/results/2026-07-22T19-07-52-809Z.json`（含 Game hint served 樣本原文）

## 三軸結果 vs gate

| 路徑 | p50 | p90 | 首發成功率（gate ≥95%） | 503（gate 0） | 判定 |
|------|-----|-----|------|------|------|
| 新手 hint | 7.0s | 11.2s | **70%** | **2** | ❌ FAIL |
| Game hint | 12.5s | 16.6s | **0%** | **20/20** | ❌ FAIL |
| 新手 debrief | 17.2s | 18.9s | **5%** | **19/20** | ❌ FAIL |
| Game debrief | 20.4s | 21.5s | **0%** | **20/20** | ❌ FAIL |

- 速度軸：新手 hint p50 7.0s 在 5-8s 目標內；其餘路徑因反覆 gate 打回吃滿兩發，秒數失真（等修完供給率再量）。
- 詞表洩漏軸：80 發 served 文字掃三張表 **0 洩漏** ✅（唯一綠的軸；被 gate 擋下的候選不在 served 之列）。
- 人工目檢：首發成功樣本過少，**本輪不具目檢意義**，留到下一輪。

## 根因診斷（不是模型爛，是 gate profile 錯置）

拆 reviewer 時把 handler 的 parse options 從 `semanticAdjudicated: true` 改成「全嚴」，等於打開了一整套**舊管線從未在 served 結果上 enforce 過的 reviewer 時代主觀 rubric**：

1. **舊管線實況**：最終權威 parse 一律帶 `semanticAdjudicated: true`——hint 的 `assertGeneratedHintQuality` 整段跳過（hint.ts:2266 early return）、debrief 的 `assertGeneratedDebriefQuality` 整段跳過，主觀品質（substance／role／partner_initiative／game coaching）歸 reviewer 管、reviewer 會 repair。這些 rubric 只 gate 過「送審前候選」，從未 gate 過 served 內容。
2. **本輪誤置**：單發 validate 用全嚴 profile，主觀 rubric 直接殺發。打回分佈證實：
   - 新手 debrief 19×503 主因 `strength_substance`×17＋`strength_role`×8（strengths 逐字稿具體詞 rubric）。
   - Game debrief 20×503 主因 `partner_initiative`×10＋`strength_substance`×8＋`game_breakdown_missing_fields`×8＋`temperature_leak`×8。
   - Game hint 20×503 主因 `game_coaching_substance`×13＋`not_grounded`×10。
   - 這正是 2026-07-21「503 通用解」已定性過的病：合法輸出被主觀 rubric 系統性 reject。
3. **兩個真硬傷（非 rubric 錯置，需 prompt/schema 修）**：
   - `debrief_temperature_leak`×8（Game debrief 40%）：prompt 注入 band 詞，Sonnet 抄進可見欄位；舊管線靠 reviewer repair，現在沒人修 → 需在 debrief prompt 強化「溫度機制詞絕不入可見欄位」＋（或）改注入白話。硬安全 gate 本身不動。
   - `debrief_game_breakdown_missing_fields`×8：模型漏出完整 gameBreakdown → tool schema 的 gameBreakdown 是選填（新手共用），Game 模式需在 prompt／tool description 強制五欄，或 Game 路徑動態把 gameBreakdown 設為 schema required。
   - 事實接地類（`unsupported_detail:*`、部分 `not_grounded`）：Eric 拍板**保留**，照擋——新手 hint 的 4×third_party name 打回屬正確攔截；但 Game hint 的 not_grounded×10 混有 rubric 過嚴成分，需逐樣本比對（結果 JSON 有原文）。

## 修復方向（下一輪動工，改完重跑 eval）

1. **gate profile 校正**（主刀）：單發 validate 改用「served-parity＋事實接地」profile——保留：結構／長度／守門詞表（labels、L4、temperature leak）／bossy／canned／`hint_fact_ledger` 與 `unsupported_detail` 事實接地／hintAssessment 契約／Game breakdown 完整性；**放行**：reviewer 時代主觀 rubric（`strength_substance`、`strength_role`、`watchout_*`、`summary_role`、`date_reason_role`、`partner_initiative`、`game_coaching_substance`、`invite_coaching_conflict`、generic-pasteable）。實作上不要復用 `semanticAdjudicated:true`（它連事實接地一起跳），要新開明確的 profile 選項逐 gate 定生死。
2. **prompt 修**：debrief 溫度詞可見欄位禁令強化；Game debrief breakdown 五欄必填強調（或動態 schema required）。
3. `not_grounded` 在 Game hint 的打回逐樣本覆核（結果 JSON），決定是留是鬆。
4. 修完重跑 `deno run --allow-env --allow-net --allow-read --allow-write tools/practice_single_shot_eval/run_eval.ts`，三軸全綠才進 Codex 雙審（順序鐵則不變）。

## 結論

**FAIL——不進 Batch I Codex 雙審。** 詞表洩漏軸綠；速度軸新手 hint 達標；穩定度軸四路全紅，根因為 gate profile 錯置（主）＋兩個 prompt/schema 真硬傷（次）。單發引擎、failover、死線夾擠、prefetch 語意本身在 eval 全程行為正確。

---

## 第 2 輪（作廢——eval 工具未對齊新 profile）

b113a2c5 修完後重跑仍全紅；覆核發現 run_eval.ts 鏡像的是舊 handler parse options（agent 建工具時已預警「handler 改參數 eval 要同步」），主觀 rubric 與舊 debrief schema 仍在 eval 內生效。修正：run_eval.ts 補 `relaxSubjectiveQualityRubrics`＋`DEBRIEF_TOOL_SCHEMA_GAME`（f302b2ed）。此輪數字不作 gate 依據。

## 第 3 輪（f302b2ed 全修正到位：仍 FAIL，但收斂中）

結果 JSON：`results/2026-07-22T20-00-39-896Z.json`

| 路徑 | p50 | p90 | 首發（gate ≥95%） | 503（gate 0） | 供給率 | 判定 |
|------|-----|-----|------|------|------|------|
| 新手 hint | 6.4s | 10.5s | 70% | 1 | 95% | ❌（差一步） |
| Game hint | 11.7s | 12.9s | 30% | 9 | 55% | ❌ |
| 新手 debrief | 16.9s | 18.9s | 5% | 19 | 5% | ❌ |
| Game debrief | 20.4s | 21.7s | 0% | 19 | 5% | ❌ |

詞表洩漏軸持續 0 ✅。主觀 rubric 放行已生效（相關代碼從打回分佈消失）；殘餘打回換成：

1. **事實接地 heuristic 疑似大量 false positive（新焦點）**：新手 debrief 19×503 幾乎全是 `field_not_grounded`×18＋`suggested_line_not_grounded`×7（token-overlap 接地檢查）；`unsupported_detail:*`（typed-fact ledger）在四路都持續高打回。這些屬 Eric 拍板「保留」的類別，但打回率 30-95% 顯示 heuristic 對 Sonnet 5 的自然中文措辭過敏——需逐樣本判定真偽（第 4 輪起 eval 已加 `rejectedCandidates` 記錄儀，把被拒原文落進結果 JSON）。
2. **`debrief_temperature_leak` 仍 ×8**：已拆 band 英文字回顯＋「篩選」教材詞，仍漏——下一步用 rejectedCandidates 直接看漏的是哪個詞（懷疑：禁詞清單本身列字被抄、或 FSM evidence prompt 殘留機制詞）。
3. `game_breakdown_missing_fields` 從 8-10 降到 3（schema 必填有效但未根絕）。
4. 新手 hint 只差最後一哩：打回全是 `invite_route`×3＋fact 類；供給率已 95%（19/20），首發 70% 未達標。

## 下一輪工作清單（新 session 接手）

1. 跑（或讀已跑完的）第 4 輪結果 JSON 的 `rejectedCandidates`，逐 gate 抽樣判定 false positive 率：`field_not_grounded`／`suggested_line_not_grounded`／`unsupported_detail:*`／`temperature_leak`／`invite_route`。
2. 依樣本裁決：真幻覺→留 gate 改 prompt；heuristic 過敏→調 heuristic 或把該子 gate 也歸入 relax profile（**動事實接地前先確認 Eric 的「事實接地保留」界線——這是他拍板保留的類別，放鬆屬 scope 變更，需 Eric 點頭**）。
3. temperature_leak 源頭定位後根治。
4. 全綠後才進 Batch I Codex 雙審（附全部輪次報告）。

## 現況風險登記（prod）

f302b2ed 已部署：hint 供給率約 95%（新手）／55%（Game），debrief 供給率約 5%——**dogfood 期 debrief 幾乎必 503（retryable）**。逃生門＝整條 train git revert（Eric 事前拍板的直接 main 策略）；或等下一輪校正收斂。

## 第 4 輪（取樣輪；數字與第 3 輪一致）

結果 JSON：`results/2026-07-22T20-21-43-206Z.json`（**hint 側含 rejectedCandidates 被拒原文**；debrief 側 wrapper 漏接已修，下輪會有）。首兩個抽樣已確認診斷方向：

- `unsupported_detail:third_party:name:is_named`（bh1）：候選全文零第三方名字、品質良好——typed-fact 抽取 regex 對「追劇配鹹酥雞」類自然引句**誤判**。
- `unsupported_detail:partner:schedule:available_at`（bh2）：候選無任何行程捏造（「下次爬山記得…」被當 schedule claim）——**誤判**。

初步結論：主要殘餘打回是 hint_fact_ledger 的 claim-extraction heuristic 對 Sonnet 5 自然措辭的 false positive，屬「誤判修 bug」而非「放鬆事實接地原則」——修 heuristic 不必動 Eric 的保留裁決，但改 hint_fact_ledger.ts 屬高風險區，修完必重跑 eval＋Codex 審。

## 第 5 輪（2026-07-23；debrief rejectedCandidates 記錄儀首輪到位）

結果 JSON：`results/2026-07-23T01-11-35-559Z.json`

| 路徑 | p50 | p90 | 首發（gate ≥95%） | 503（gate 0） | 判定 |
|------|-----|-----|------|------|------|
| 新手 hint | 6.2s | 9.6s | 85% | 2 | ❌（唯一打回＝invite_route×5） |
| Game hint | 11.5s | 13.0s | 30% | 11 | ❌ |
| 新手 debrief | 16.7s | 18.4s | 10% | 18 | ❌ |
| Game debrief | 19.8s | 21.5s | 0% | 20 | ❌ |

詞表洩漏軸持續 0 ✅。

## 第 4＋5 輪被拒樣本全量重放判定（106 筆，非抽樣；本輪最重要產出）

方法：重放腳本直接 import gate 模組（`hint_fact_ledger.ts`／`practice_visible_quality.ts`）以 eval 同款 context 逐筆重跑，拿觸發錨點對照 fixture 判真偽。逐筆判定表＋工具：

- `docs/reviews/2026-07-23-fact-gate-fp-round4-hint.md`（hint 側 30 筆，FP 80%；機制面僅 3/30 錨點＝真捏造本體）
- `docs/reviews/2026-07-23-fact-gate-fp-round5-debrief.md`（debrief 側 76 筆，FP 74%）

**結論確立：殘餘打回主力＝heuristic false positive，屬「修 bug」非「放鬆事實接地」，不動 Eric 的保留裁決。**

### temperature_leak 懸案已破（gate WAI，修 prompt 不修 gate）

漏詞＝「框架」×10、「篩選」×1，源頭兩個皆實證：
1. `prompt.ts:229` 禁詞清單本身列字被抄（該行只掛 game debrief；對照組：有此行的 game 20 發洩 9、沒有的新手 18 發洩 2；gd3 還寫出清單裡的合法 sentinel「框架掉了」）。
2. `game_fsm.ts:1196`「穩定框架」／`:1180`「冷靜篩選測試」／`:1103`「不可得性」等 FSM 策略行經 `prompt.ts:577` 注入。
唯一語言誤殺 1 筆（「導演＋預告的篩選法」＝她的挑片標準）。

### FP heuristic 根因（檔案:行號詳見兩份判定表）

- `hint_fact_ledger.ts:1085` 送收 pattern 裸「給/發/傳」→「給接納感」「沙發」「傳給妳」抽成假第三方人名（兩輪共 12 筆最大宗，conf=high 硬殺）。
- `practice_visible_quality.ts:239-269` not_grounded／field_not_grounded＝純詞面 n-gram 且只認最後一句：語意轉述與「引用較早輪次」全誤殺（兩輪 30 筆、FP 100%）。
- `hint.ts:1404` 裸 `/交作業/` 不分方向（用戶示弱玩笑被當 bossy，4/4 FP）。
- `hint_fact_ledger.ts:1741-1745,659` 地名字尾詞中切割（「區域」→「哈哈區」；「市集」「街道」）。
- `hint_fact_ledger.ts:2396,2445,2461-2469` asksPlace 啟動後 coaching 引號片段全變 venue claim。
- `hint_fact_ledger.ts:887-890`「(我)…X人」籍貫句型（「敢跟我比吃辣的人」）。
- `hint_fact_ledger.ts:125-126,1370-1394` SCHEDULE_STATUS 含單字「能」（「能量沒那麼高」→有空）。
- debrief 特有：`:1223` 無主詞「養狗」預設 owner=user；`:121-124` SCHEDULE_DAY 交替序 identity 不匹配（她真說週六有空仍被打）；`:2315-2318`「我們…在…附近」誤觸同住 commonality；likes 所有格「的」捲進錨點。

### ⚠️ False negative 警訊（修 FP 時必須同步補，否則真捏造放行）

venue extractor 對「方位詞＋捷運站／騎車 N 分鐘」型真捏造**全數漏抓**（3 筆），現況是靠別的 FP 垃圾錨點碰巧擋下。

### 真陽性（gate 該擋且擋對的）

捏造地點（西門町／市區／北區捷運站）、替用戶捏造自我揭露（戒咖啡）、breakdown 整包缺（×5，全集中失敗局 gd3/gd4——模型在失敗局傾向省略，prompt 需強調失敗局也要五欄）、meta 句混進貼句欄、overlong。

### eval 工具缺口

`run_eval.ts:206-215` rejected 記錄儀只包 `parseHintResult`；`invite_route`（`hint.ts:839/897`，在 `buildHintDecision`）的打回逸出記錄儀 → 第 5 輪新手 hint 唯一殘餘打回（×5）**原文沒錄到、無法判真偽**。修法＝把 decision 包進同一 try。

### 留給 Eric 的裁決（不動工）

1. 「我週三晚上有空」型第一人稱邀約提案語被 user:schedule slot 封死——政策爭議：邀約教練本來就要能提案時間？
2. gh5 fixture 死角設計（最新句問地點、fixture 從未給位置，模型只剩捏造或被 asksPlace 誤殺兩條路）——調 fixture 或接受該路必有打回。

## 第 6 輪前修復清單（按風險排序）

1. **prompt 修（低風險）**：`prompt.ts:229` 禁詞清單改為不點名詞彙的寫法；`game_fsm.ts` 策略行機制詞改白話；失敗局 breakdown 五欄必填強調。
2. **eval 工具修（零 prod 風險）**：`run_eval.ts` 把 `buildHintDecision` 打回納入 rejected 記錄儀。
3. **heuristic 修（高風險區，修完必重跑 eval＋Codex 審）**：上列 `hint_fact_ledger.ts`／`practice_visible_quality.ts`／`hint.ts:1404` 各根因逐條修；**同步補 FN venue 抽取**（方位詞＋捷運站/騎車 N 分型）。
4. 修完重跑第 6 輪；三軸全綠 → Batch I Codex 雙審（附本報告全部輪次＋兩份逐筆判定表；另請 Codex 審 relax 清單是否過鬆）→ Eric 真機。

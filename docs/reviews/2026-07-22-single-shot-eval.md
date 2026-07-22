# 單發重設計 v2 四路黑箱 eval 報告（第 1 輪：FAIL）

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

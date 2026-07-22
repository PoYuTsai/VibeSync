# 練習室 Hint 單發重設計（single-shot v2）

**日期**：2026-07-22 · **拍板**：Eric（不省成本，簡單暴力，快＋穩優先）
**範圍**：只動 hint（新手＋Game）。Debrief、練習對話本體（chat mode）、draw_profile 一律不動。

## 背景與問題

現行 hint 管線：DeepSeek 生成（1 次）→ 語意複審 reviewer（每次生成最多 4 個 provider 呼叫）→ reject 後 salvage/repair → Claude failover（最多 2 次，各自再過複審）→ 全路徑 provider 呼叫預算 11、絕對死線 105 秒。

實測（prod ai_logs，近 30 天）：成功單次 p50 20-23 秒、p90 43-45 秒、attempt 失敗率 35%；失敗換手時使用者等 60-96 秒。2026-07-22 Eric 真機 dogfood：兩句對話的 hint 跑 96 秒仍失敗。

結論：不穩定來自層數（生成×複審×failover 失敗率相乘、延遲串行相加），不是參數。縫補（reject 改 repair、prefetch 重試、分段文案）已到極限。

## 新架構：一次呼叫、機械驗證、硬逾時

```
請求 → buildHintMessages（原 prompt，保留）
     → Claude Sonnet 5，強制 tool_use JSON schema，max_tokens 500，逾時 15s
     → 機械守門（毫秒級，全保留）：
         parser 硬 gate ＋ 標籤洩漏/L4 安全/溫度機制洩漏（visible_text_guard）
         ＋ 罐頭/接地檢查（practice_visible_quality）＋ 事實接地（hint_fact_ledger）
         ＋ 機械 repair（repairGameVisibleLabels / repairChineseJargon）
     → 過 → 回傳（contract 不變）
     → 不過或逾時 → 第 2 次嘗試：Claude Haiku 4.5（同 schema，逾時 15s）
     → 再不過 → 503（維持「絕不罐頭 fallback」鐵則）
```

- **新絕對死線 35 秒**（原 105 秒）。預期 p50 ≈ 5-8 秒、p90 ≈ 15 秒、p99 ≤ 30 秒。
- **99% 信賴區間的來源**：tool_use 強制 schema 讓 `schema_invalid` 結構性歸零；單次成功率估 97-99%，第二發換 Haiku 去相關（避開單一模型 529 過載），兩發合計 >99.9%。靠減層數，不靠加重試。
- **成本**：輸入 1-2k tokens（沿用 Phase 1 的 prompt caching）＋輸出 ≤500。Sonnet 單發約 US$0.005-0.01；Eric 已拍板不省這筆。

## 砍掉（僅 hint 路徑）

- DeepSeek 生成呼叫與 `HINT_GENERATION_ATTEMPTS`／`HINT_TIMEOUT_MS=24000`。
- 語意複審：hint 路徑對 `semanticAdjudicate` 的呼叫、`HINT_SEMANTIC_REVIEWER_CALL_BUDGET`、`PRACTICE_REQUIRED_REVIEWER_CALLS_PER_GENERATION`、`HINT_PROVIDER_CALL_BUDGET=11`。`semantic_quality.ts` 檔案本身保留（debrief 還在用）。
- salvage／`bestGatePassingHint` 機制：無 reviewer 後機械 gate 是二值判定，無「主觀 reject 留最佳候選」概念。
- `deferVisibleGuardsToSemantic` 旗標：可見守門直接在機械層一次做完。

## 原封保留

- **Prompt**：`buildHintMessages` 全部沿用（含 Game/新手分岔、few-shot、gameHintEvidence）。品質責任從 reviewer 移回 prompt＋機械 gate。
- **Prefetch 全套語意**：claim/record/settle/discard RPC、requestId 冪等、消費才扣、**預產失敗絕不落 fallback 快照**。生成變快後 prefetch 降級為加分項（命中秒開、未命中 5-8 秒）。
- **回傳 contract**：`PracticeHintResult { replies[2], coaching }` 與外層欄位（provider/model/generationSource/…）逐欄不變，舊 client 免升級可用。
- **Telemetry**：ai_logs 寫入照舊，新增 pipeline 標記（如 `pipeline:"hint_single_shot_v2"`）供前後對比。
- **Debrief**：本輪完全不碰。改共用模組（telemetry.ts 等）時只加不改，必要時回歸 debrief 測試。

## Client 端小改（唯二）

1. 分段等待文案改對齊新管線：0-8s「教練正在讀你們最後幾句…」／8-20s「正在想兩種回法…」／20s+「快好了，正在做最後檢查…」（移除「品質雙重複核」字樣）。
2. 其餘不動；client 115s 等待窗保留（相容），server 35s 內必回。

## 錯誤處理

- 單次嘗試失敗定義：逾時 15s、HTTP 4xx/5xx/429、機械 gate 不過、L4 安全不過。
- 任一失敗 → 立即進第 2 發（Haiku），不 repair、不複審。
- 兩發皆敗 → 503＋failureClasses 落 ai_logs（沿用 `classifyPracticeGenerationFailure`）。unsafe 候選一律丟棄，絕不 salvage。
- Prefetch 失敗 → discard，照舊不留快照。

## 測試與驗收

- 單元：新生成函式的 tool_use 回傳解析、兩發 failover 順序、逾時夾擠（deadline 剩餘時間）、機械 gate 全綠、503 分類。
- 回歸：hint 既有測試全跑；debrief 測試全跑（確認共用模組零波及）；prefetch claim/settle/discard 冪等測試照跑。
- 上線後盯 ai_logs：p50/p90、失敗率、`pipeline` 標記對比舊管線。
- 高風險區（AI prompt/token/cost）：出貨前 Codex review。

## 已知取捨（拍板記錄）

- 移除 LLM reviewer＝接受「機械 gate 擋不住的語感瑕疵」可能偶發流出；以 Sonnet 5 品質＋prompt few-shot＋dogfood 盯場承擔。Eric 拍板：穩定與速度優先。
- 第 2 發用 Haiku 4.5（非 Sonnet 重試）：為了與 Sonnet 過載去相關；語感風險由同一套機械 gate 兜底。

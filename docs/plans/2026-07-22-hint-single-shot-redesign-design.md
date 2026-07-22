# 練習室 Hint＋Debrief 單發重設計（single-shot v2）

**日期**：2026-07-22 · **拍板**：Eric（不省成本，簡單暴力，快＋穩優先）
**範圍**：hint（新手＋Game）＋debrief 都改單發。練習對話本體（chat mode）、draw_profile 一律不動。

## 背景與問題

現行 hint 管線：DeepSeek 生成（1 次）→ 語意複審 reviewer（每次生成最多 4 個 provider 呼叫）→ reject 後 salvage/repair → Claude failover（最多 2 次，各自再過複審）→ 全路徑 provider 呼叫預算 11、絕對死線 105 秒。Debrief 同構（無預產，死線 85 秒）。

實測（prod ai_logs，近 30 天）：hint 成功單次 p50 20-23 秒、p90 43-45 秒；debrief p50 29-38 秒、p90 47-57 秒；attempt 失敗率 35%；失敗換手時使用者等 60-96 秒。2026-07-22 Eric 真機 dogfood：兩句對話的 hint 跑 96 秒仍失敗。

結論：不穩定來自層數（生成×複審×failover 失敗率相乘、延遲串行相加），不是參數。縫補已到極限。

## 新架構：一次呼叫、機械驗證、硬逾時

```
請求 → 原 prompt 組裝（hint: buildHintMessages；debrief: debrief_card 現行 prompt）
     → Claude Sonnet 5，強制 tool_use JSON schema
         hint：max_tokens 500，單次逾時 15s，絕對死線 35s（原 105s）
         debrief：max_tokens 1200，單次逾時 20s，絕對死線 45s（原 85s）
     → 機械守門（毫秒級，全保留）：
         parser 硬 gate ＋ 標籤洩漏/L4 安全/溫度機制洩漏（visible_text_guard）
         ＋ 罐頭/接地檢查（practice_visible_quality）＋ 事實接地（hint_fact_ledger）
         ＋ 機械 repair（repairGameVisibleLabels / repairChineseJargon）
     → 過 → 回傳（contract 不變）
     → 不過或逾時 → 第 2 次嘗試：Claude Haiku 4.5（同 schema，同逾時）
     → 再不過 → 503（維持「絕不罐頭 fallback」鐵則）
```

- 預期：hint p50 ≈ 5-8s、p90 ≈ 15s；debrief p50 ≈ 10-12s、p90 ≈ 20s。
- **99% 信賴區間的來源**：tool_use 強制 schema 讓 `schema_invalid` 結構性歸零；單次成功率估 97-99%，第二發換 Haiku 去相關（避開單一模型 529 過載），兩發合計 >99.9%。靠減層數，不靠加重試。
- **成本**：輸入 1-2k tokens（沿用 prompt caching）＋輸出 hint ≤500／debrief ≤1200。Sonnet 單發約 US$0.005-0.02；Eric 已拍板不省這筆。

## 砍掉

- DeepSeek 生成呼叫（hint＋debrief 路徑）與其逾時常數（`HINT_TIMEOUT_MS`、`DEBRIEF_TIMEOUT_MS`）。
- 語意複審整層：hint／debrief 對 `semanticAdjudicate` 的呼叫、全部 reviewer/budget 常數（`HINT_PROVIDER_CALL_BUDGET=11` 等）。**兩路都退出後 `semantic_quality.ts`（3345 行）整檔變死碼，直接刪除**（含 index.ts 注入點）。
- salvage／`bestGatePassingHint` 機制與 `deferVisibleGuardsToSemantic` 旗標：機械 gate 是二值判定，不再有「主觀 reject 留最佳候選」。

## 安全與品質裁決（2026-07-22 對話拍板）

Bruce 分析的三件品質事，處置各不同：

| 機制 | 住在哪 | 延遲成本 | 處置 |
|------|--------|----------|------|
| 第二個 AI 審核（reviewer） | semantic_quality.ts | 每次 20-40s | **刪除**（慢的元兇） |
| 明文禁止 PUA／情緒勒索 | prompt 規則＋機械守門詞項 | 零／毫秒 | **拿掉**（Eric 拍板 2026-07-22；CC 已告知 App Review／品牌風險，Eric 承擔） |
| 不准亂編（事實接地） | prompt 規則＋hint_fact_ledger 機械檢查 | 毫秒 | **保留**（Eric 拍板） |

實作範圍精確界定：只移除 prompt 中 PUA／情緒勒索類禁令條款，及機械守門中**明確屬於該類**的詞項。其他守門（事實接地、內部標籤洩漏、罐頭/接地檢查、溫度機制洩漏，以及 L4 守門中非 PUA 類的安全類別若存在）**不在本裁決範圍，一律保留**——實作時先確認 L4 詞表各項歸屬再動刀，不得整段順手刪。

## 原封保留

- **Prompt**：hint／debrief 現行 prompt 全部沿用（含 Game/新手分岔、few-shot、gameHintEvidence）。品質責任從 reviewer 移回 prompt＋機械 gate。
- **Prefetch 全套語意**（hint only，debrief 本來就無）：claim/record/settle/discard RPC、requestId 冪等、消費才扣、**預產失敗絕不落 fallback 快照**。生成變快後 prefetch 降級為加分項。
- **回傳 contract**：hint `PracticeHintResult { replies[2], coaching }`、debrief 卡片形狀與外層欄位逐欄不變，舊 client 免升級可用。
- **Telemetry**：ai_logs 寫入照舊，新增 pipeline 標記（`pipeline:"single_shot_v2"`）供前後對比。

## Client 端小改（唯二）

1. hint 分段等待文案改對齊新管線：0-8s「教練正在讀你們最後幾句…」／8-20s「正在想兩種回法…」／20s+「快好了，正在做最後檢查…」（移除「品質雙重複核」字樣）。
2. 其餘不動；client 等待窗保留（相容），server 死線內必回。debrief 等待畫面不動（10 秒級不需分段文案）。

## 錯誤處理

- 單次嘗試失敗定義：逾時、HTTP 4xx/5xx/429、機械 gate 不過、L4 安全不過。
- 任一失敗 → 立即進第 2 發（Haiku），不 repair、不複審。
- 兩發皆敗 → 503＋failureClasses 落 ai_logs（沿用 `classifyPracticeGenerationFailure`）。unsafe 候選一律丟棄。
- Prefetch 失敗 → discard，照舊不留快照。

## 測試與驗收

- 單元：tool_use 回傳解析、兩發 failover 順序、逾時夾擠（deadline 剩餘時間）、機械 gate 全綠、503 分類——hint 與 debrief 各一套。
- 回歸：hint／debrief 既有測試全跑；prefetch claim/settle/discard 冪等測試照跑；刪 semantic_quality.ts 後全 repo analyze 0 warning（release gate）。
- 上線後盯 ai_logs：p50/p90、失敗率、`pipeline` 標記對比舊管線。
- 高風險區（AI prompt/token/cost）：出貨前 Codex review。

## 已知取捨（拍板記錄）

- 移除 LLM reviewer＝接受「機械 gate 擋不住的語感瑕疵」可能偶發流出；以 Sonnet 5 品質＋prompt few-shot＋dogfood 盯場承擔。Eric 拍板：穩定與速度優先。
- 第 2 發用 Haiku 4.5（非 Sonnet 重試）：為了與 Sonnet 過載去相關；語感風險由同一套機械 gate 兜底。
- 安全與品質守門的去留：見上方裁決表（PUA 禁令拿掉、事實接地保留，2026-07-22 Eric 拍板）。

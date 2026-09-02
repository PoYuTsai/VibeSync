# Analyze v2 本機黑箱

真 Sonnet 5、v2 契約（`noSendDecisions`）、essential 五風格，直接跑
`handleAnalyzeStream` 本體（system prompt、情境 atoms、發散計畫影子都是 production
程式碼），只 stub DB store 與 supabase telemetry。每案一次真呼叫，會產生費用，
跑前要 Eric 明確授權。

```sh
# key 讀 ~/.config/anthropic/key
deno run --allow-env --allow-read --allow-write=tools/analyze-v2-blackbox/out \
  --allow-net=api.anthropic.com tools/analyze-v2-blackbox/run_blackbox.ts \
  tools/analyze-v2-blackbox/out/<date>-<label>.json
```

旗標：`--only=a,b` 只跑指定案；`--repeat=N` 每案跑 N 次（看邊界案穩不穩）；
`--raw=1` 把模型原始 JSONL 存進結果（看 parser 為什麼丟掉某行）。

結果檔形狀：`{ meta, results }`，`meta` 綁定 repo commit、v2 五風格 system prompt
SHA-256、模型與時間；每案另存完整 client NDJSON（`clientText`）供外洩判定獨立複核。

輸出每案：事件序列、決策、五風格回覆、client 是否漏計畫、server 快照是否有
`analysisDivergencePlan`、`stream_knowledge_selected` 與 `stream_phase0_observability`
（含 2a 計畫統計、2b `attribution`／`repairs`）、token 用量。
18 案涵蓋開場、熱絡、冷淡、邀約前後、婉拒、反問、長對話。改 `CASES` 加案。

歷史結果（`out/`）：run2＝18 案 2a 影子基線；run3＝延後變體×3；run9＝2b 迭代中
的失敗樣本（method 混用、sourceIndex 手誤）；run10＝2b 驗收。

## Phase 3a 評測器

```sh
deno run --allow-read tools/analyze-v2-blackbox/evaluate.ts <artifact.json> [--json]
```

語料在 `corpus.ts`（每案帶可確定性判定的期望值）。評測器不打網路，對照 §19.3 可
確定性判定的 gates 打分：決策在期望集合、no-send 零卡、send 五 key 唯一、同開頭
≥4 張（§6.3 字面）、問句／新話題預算、風格實際用到的枝不得超 cap、歸因 unresolved、
client 無計畫本文、延遲 ≤60s、輸出 ≤6500 token；任一 gate 失敗 exit 1。同開頭 1–3 張、
pool 裡未用到的超 cap 枝、缺欄 invalid 只是度量。基線：run12 17/21、run13 18/21
（剩：用到超 cap 枝 1–2、四張同開頭 1、問句 1、延遲 1）。3b 實驗：加「開頭規則」對
同開頭無效（4 vs 3 案）已撤。

## Phase 3c candidate guard（只度量）

`_shared/social/candidate_guard.ts` 把 §15.2 第一層硬 gates 統一成 violation 清單，
production 隨 `stream_phase0_observability.candidateGuard` 出（只記不擋）。評測器每案印
`guard=<codes>`、彙總 `guard {...}`，不影響 pass／exit code。新 artifact 直接讀 telemetry；
舊 artifact 從 `rawLines` 重建（guardrail 前的模型原始輸出；run12／run13 的 rawLines 沒留
盤點球，球面四道出不來，之後的 run 會留）。run12：question_budget 1、semantic_distance_cap 1
（與既有 gate 同案）；run13：card_source_mismatch 4（三案，與 phase0
`fiveCardSourceDivergence` 同判）、semantic_distance_cap 2。

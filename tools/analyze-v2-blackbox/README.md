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

輸出每案：事件序列、決策、五風格回覆、client 是否漏計畫、server 快照是否有
`analysisDivergencePlan`、`stream_knowledge_selected` 與 `stream_phase0_observability`
（含 2a 計畫統計、2b `attribution`／`repairs`）、token 用量。
18 案涵蓋開場、熱絡、冷淡、邀約前後、婉拒、反問、長對話。改 `CASES` 加案。

歷史結果（`out/`）：run2＝18 案 2a 影子基線；run3＝延後變體×3；run9＝2b 迭代中
的失敗樣本（method 混用、sourceIndex 手誤）；run10＝2b 驗收。

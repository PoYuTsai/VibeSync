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

輸出每案：事件序列、決策、五風格回覆、client 是否漏計畫、server 快照是否有
`analysisDivergencePlan`、`stream_knowledge_selected` 與 `stream_phase0_observability`。
固定三案：邀約後軟婉拒（預期 no-send 三態）、熱絡反問（預期 send＋計畫）、
薄開場（看模型會不會硬吐計畫）。改 `CASES` 加案。

# opener-repair-replay（只供驗收）

用已捕獲的 snapshot／contribution／初次 raw，離線回放正式 handler 的「一次內容修正」分支：
`prepareJob`（正式 validate／material／normalize／guard／adoption）→ 正式 `buildOpenerContentCorrectionPrompt`
→ 一次模型呼叫（單次 fetch、無重試）→ 正式 `mergeOpenerCorrection`（只換被標記的卡）→ 再 normalize／guard／adoption → 方案投影。

- 不改產品程式、prompt、fixtures；不碰正式 session／DB／扣額；不覆蓋 deadline、claim／settle、串流與 502 形狀。
- 每筆最多一次呼叫；預算預檢＝輸入估算×1.3＋正式 max_tokens 全滿；沒有 usage 的呼叫以最壞情況計。
- smoke：`deno test --allow-read --allow-env tools/opener-repair-replay/pipeline_test.ts`
- dry-run：`deno run --allow-read --allow-write --allow-env --allow-net=api.anthropic.com tools/opener-repair-replay/run.ts --manifest=<manifest.json> --captured-root=<packet root> --tag=<tag> --budget-usd=0.60 --max-calls=12`
- 真跑：同上加 `--run --confirm-paid`（要 Eric 授權）。輸出在 `out/<tag>/`（gitignored）。

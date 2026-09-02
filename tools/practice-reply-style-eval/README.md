# 練習室寫實差異化 reply-style 評測（PR-0 baseline）

規格：`docs/plans/2026-09-02-practice-reply-style-diversity-spec.md`。問題是 100
位女孩只有 5 套 persona 骨架，換人像沒換。這支工具固定情境、換角色，量到底多像；
difficulty bakeoff 固定角色量難度，兩者互補。

每一輪都是真實 DeepSeek 呼叫（prod 同款 `deepseek-v4-flash`，Eric 2026-09-02
授權隨意調用）。144 場約 3 分鐘。

## 三支工具

```bash
export DEEPSEEK_API_KEY=...   # 或放 supabase/.env
# 1. 產生 artifact：4 位 slow_worker × 12 情境 × repeat
deno run --allow-env --allow-read --allow-write --allow-run=git --allow-net=api.deepseek.com \
  tools/practice-reply-style-eval/run_baseline.ts tools/practice-reply-style-eval/out/<date>-<label>.json --repeat=3
# 2. 確定性評測（不打網路）
deno run --allow-read tools/practice-reply-style-eval/evaluate.ts tools/practice-reply-style-eval/out/<file>.json
# 3. 同 persona 四選一 LLM 盲測（寫 <file>-judge.json）
deno run --allow-env --allow-read --allow-write --allow-net=api.deepseek.com \
  tools/practice-reply-style-eval/judge.ts tools/practice-reply-style-eval/out/<file>.json
# 自測
deno test --allow-read --allow-env tools/practice-reply-style-eval/evaluate_test.ts
```

- `run_baseline.ts`：prompt 走 production `buildChatMessages`（含 bakeoff 同一份
  固定 context fixture：2026-08-28 20:30、固定
  thread、記憶摘要、一則貼文），standard 模式、normal 難度，回覆後處理照 handler
  同序（繁體→內部標籤守門→L4 守門）。
  flags：`--profiles`、`--scenarios`、`--repeat`、`--difficulty`、`--concurrency`。
  artifact meta 綁 commit／tree／dirty／prompt policy version／模型／常數。
- `scenarios.ts`：規格 §10.1 的 12 類，最後一則 user 訊息是探針。
- `evaluate.ts`：每人表面風格分佈；角色之間 vs 同角色分半的重心距離（比值 ≈1
  ＝分不出來）；每情境探針回覆的 shape 集中度、同開頭、bigram
  Jaccard。文字距離只 能當警報，不能當成功證明。
- `judge.ts`：校準 5 情境、留出 5 情境（排除 interrogation／interest_hit，避免靠
  年齡職業興趣事實猜人），四選一，機率基準 25%，規格門檻 ≥70%。

## 結果紀錄

- `2026-09-02-run1-baseline-4sw-x3.json`（322fc5e3 未改 prompt 的 baseline）：
  144 場零失敗、420 則回覆、守門退回 0、p50 975ms。 **重心距離比值
  0.80**（角色之間比自己跟自己還像）；探針 Jaccard 跨角色 0.095 vs 同角色
  0.135。同開頭佔比 100% 的情境：daily_share、failed_joke、light_joke。 judge
  四選一 **40%**（Alice 60% 靠空服事實外洩；Bonnie 20% 低於機率）。

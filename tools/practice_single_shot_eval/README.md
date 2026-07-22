# 練習室單發重設計 v2 — 四路黑箱 eval（Batch H）

不看程式碼、只打真生成管線（直接 import `supabase/functions/practice-chat/` 的
buildMessages＋`runSingleShot`＋parser 守門），量化驗收四條路：
新手 hint／Game hint／新手 debrief／Game debrief。
**絕不打 prod Edge Function、絕不碰 DB／扣費／ledger。**

## 跑法

```
CLAUDE_API_KEY=... deno run --allow-env --allow-net --allow-read --allow-write run_eval.ts
```

（`--allow-write` 供結果 JSON 落檔 `results/<timestamp>.json`；不給也能跑，只印 console。）

預設每路 5 fixtures × 4 重複 = 每路 20 發、四路共 80 發（約 US$1-2）。省錢子集：

```
deno run --allow-env --allow-net --allow-read --allow-write run_eval.ts --route=game_hint --repeat=1
```

不花錢驗流程（fake callClaude，全 80 發過 buildMessages＋parser）：

```
deno run --allow-env --allow-read --allow-write run_eval.ts --dry-run
```

## 三軸 gate（Batch H2；任一紅 → 回去修，不進 Codex 雙審）

1. **速度**：hint p50 5-8s／p90 ≤15s；新手 debrief p50 8-12s、Game debrief p50 10-15s／p90 ≤20s。
2. **穩定度**：每路首發成功率 ≥95%；20 發 0×503（gate 打回分佈另記）。
3. **風險品質**：80 發 served 文字掃 `visible_text_guard.ts` 三張詞表
   （INTERNAL_VISIBLE_LABELS／L4_UNSAFE_VISIBLE_PATTERNS／INTERNAL_MECHANISM_PHRASES）
   ＝ **0 洩漏**；Game hint 10 樣本策略合理性靠人工目檢（樣本原文在結果 JSON 的
   `gameHintSamples`）。

結果 JSON 含逐發紀錄（route／fixtureId／重複序／首發·次發·503／耗時 ms／
gate 打回代碼／served 可見文字），供 H3 報告與 Codex 雙審當證據。

# 分析 A/B 彙總：2026-10-03-baseline-c3

commit 9adbf87c076420dc81e6c7c8fb0df9439b36cf58（dirty=true）；2026-10-02T23:20:33.942Z；備援鏈關閉（每次只打指定模型）。
語料全是正常聊天：任何 refusal 都算誤擋。

| 臂 | 設定 | 次數 | evaluate 通過 | max_tokens | 拒答（類別） | HTTP 錯誤 | p50 | p95 | 平均 input／cache 寫／cache 讀／output | 費用 |
|---|---|---|---|---|---|---|---|---|---|---|
| C | Sonnet 5.5，production helper（adaptive thinking＋display omitted＋effort low＋max_tokens +4000） | 69 | 58/69 | 0 | 0（-） | - | 17.1s | 23.2s | 138／6887／32665／2127 | $3.126 |

evaluate 失敗 gate：
- C：{"question_budget":6,"used_branch_within_cap":5}

總費用 $3.126。
評審（固定 Sonnet 5）另跑：`run_critic.ts <tag>/arm-X.json …`，見 README。

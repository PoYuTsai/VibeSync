# 分析 A/B 彙總：2026-10-02-c-noexample

commit 2ec3ebaf1d914b91153eb243a94e6b3a90ef25dd（dirty=false）；2026-10-02T07:05:18.241Z；備援鏈關閉（每次只打指定模型）。
語料全是正常聊天：任何 refusal 都算誤擋。

| 臂 | 設定 | 次數 | evaluate 通過 | max_tokens | 拒答（類別） | HTTP 錯誤 | p50 | p95 | 平均 input／cache 寫／cache 讀／output | 費用 |
|---|---|---|---|---|---|---|---|---|---|---|
| C | Sonnet 5.5，adaptive thinking＋effort low＋max_tokens +4000＋display omitted | 42 | 36/42 | 0 | 0（-） | - | 16.7s | 22.3s | 142／7540／32023／2096 | $1.953 |

evaluate 失敗 gate：
- C：{"decision_in_expected_set":2,"question_budget":4}

總費用 $1.953。
評審（固定 Sonnet 5）另跑：`run_critic.ts <tag>/arm-X.json …`，見 README。

# 分析 A/B 彙總：2026-10-02-c-gate

commit 57e41eaec2cc611a69a112bb1a4e90e426e46072（dirty=false）；2026-10-02T06:33:01.389Z；備援鏈關閉（每次只打指定模型）。
語料全是正常聊天：任何 refusal 都算誤擋。

| 臂 | 設定 | 次數 | evaluate 通過 | max_tokens | 拒答（類別） | HTTP 錯誤 | p50 | p95 | 平均 input／cache 寫／cache 讀／output | 費用 |
|---|---|---|---|---|---|---|---|---|---|---|
| C | Sonnet 5.5，adaptive thinking＋effort low＋max_tokens +4000＋display omitted | 42 | 37/42 | 0 | 0（-） | - | 16.2s | 20.8s | 142／7552／32083／2025 | $1.925 |

evaluate 失敗 gate：
- C：{"decision_in_expected_set":2,"no_four_same_opening":1,"question_budget":2}

總費用 $1.925。
評審（固定 Sonnet 5）另跑：`run_critic.ts <tag>/arm-X.json …`，見 README。

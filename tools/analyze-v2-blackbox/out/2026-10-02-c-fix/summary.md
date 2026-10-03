# 分析 A/B 彙總：2026-10-02-c-fix

commit 0fa60fe5bf550578d08c11fb1f171a85d39eedfe（dirty=false）；2026-10-02T06:05:55.599Z；備援鏈關閉（每次只打指定模型）。
語料全是正常聊天：任何 refusal 都算誤擋。

| 臂 | 設定 | 次數 | evaluate 通過 | max_tokens | 拒答（類別） | HTTP 錯誤 | p50 | p95 | 平均 input／cache 寫／cache 讀／output | 費用 |
|---|---|---|---|---|---|---|---|---|---|---|
| C | Sonnet 5.5，adaptive thinking＋effort low＋max_tokens +4000＋display omitted | 63 | 49/63 | 0 | 0（-） | - | 17.8s | 22.5s | 142／5041／34652／2143 | $2.599 |

evaluate 失敗 gate：
- C：{"decision_in_expected_set":3,"question_budget":9,"used_branch_within_cap":2}

總費用 $2.599。
評審（固定 Sonnet 5）另跑：`run_critic.ts <tag>/arm-X.json …`，見 README。

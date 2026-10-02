# 分析 A/B 彙總：2026-10-02-c-menu

commit d0d6acba79dd9f2ecbf851f56e30c615a8b393ec（dirty=false）；2026-10-02T07:54:24.595Z；備援鏈關閉（每次只打指定模型）。
語料全是正常聊天：任何 refusal 都算誤擋。

| 臂 | 設定 | 次數 | evaluate 通過 | max_tokens | 拒答（類別） | HTTP 錯誤 | p50 | p95 | 平均 input／cache 寫／cache 讀／output | 費用 |
|---|---|---|---|---|---|---|---|---|---|---|
| C | Sonnet 5.5，adaptive thinking＋effort low＋max_tokens +4000＋display omitted | 44 | 33/44 | 0 | 0（-） | - | 12.9s | 21.6s | 118／8088／24256／1661 | $1.844 |

evaluate 失敗 gate：
- C：{"question_budget":3,"stream_completes":8,"decision_in_expected_set":8}

總費用 $1.844。
評審（固定 Sonnet 5）另跑：`run_critic.ts <tag>/arm-X.json …`，見 README。

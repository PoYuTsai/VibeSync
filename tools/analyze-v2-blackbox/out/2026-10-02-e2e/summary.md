# 分析 A/B 彙總：2026-10-02-e2e

commit 867e079960d3a567d5d820285cd3ec903657604f（dirty=false）；2026-10-02T10:48:12.450Z；備援鏈關閉（每次只打指定模型）。
語料全是正常聊天：任何 refusal 都算誤擋。

| 臂 | 設定 | 次數 | evaluate 通過 | max_tokens | 拒答（類別） | HTTP 錯誤 | p50 | p95 | 平均 input／cache 寫／cache 讀／output | 費用 |
|---|---|---|---|---|---|---|---|---|---|---|
| A | Sonnet 5，production 原樣（thinking disabled） | 23 | 20/23 | 0 | 0（-） | - | 30.1s | 40.2s | 136／18928／20624／2711 | $1.813 |
| C | Sonnet 5.5，production helper（adaptive thinking＋display omitted＋effort low＋max_tokens +4000） | 23 | 22/23 | 0 | 0（-） | - | 16.6s | 20.9s | 138／18928／20624／2130 | $1.680 |

evaluate 失敗 gate：
- A：{"stream_completes":1,"decision_in_expected_set":1,"no_four_same_opening":1,"used_branch_within_cap":1}
- C：{"used_branch_within_cap":1}

總費用 $3.493。
評審（固定 Sonnet 5）另跑：`run_critic.ts <tag>/arm-X.json …`，見 README。

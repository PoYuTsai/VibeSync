# 分析 A/B 彙總：2026-10-02-ab

commit c636b2cc752c6ae485d2bc4861ab32c9d91a28c8（dirty=false）；2026-10-02T03:55:00.290Z；備援鏈關閉（每次只打指定模型）。
語料全是正常聊天：任何 refusal 都算誤擋。

| 臂 | 設定 | 次數 | evaluate 通過 | max_tokens | 拒答（類別） | HTTP 錯誤 | p50 | p95 | 平均 input／cache 寫／cache 讀／output | 費用 |
|---|---|---|---|---|---|---|---|---|---|---|
| A | Sonnet 5，production 原樣（thinking disabled） | 42 | 37/42 | 0 | 0（-） | - | 30.5s | 41.0s | 140／9452／30242／2847 | $2.454 |
| B | Sonnet 5.5，production helper（thinking between_tools＋effort medium，max_tokens 不變） | 42 | 33/42 | 0 | 0（-） | - | 18.5s | 24.3s | 142／9451／30241／2377 | $2.257 |
| C | Sonnet 5.5，adaptive thinking＋effort low＋max_tokens +4000＋display omitted | 21 | 19/21 | 0 | 0（-） | - | 17.7s | 21.6s | 142／20793／18900／2212 | $1.642 |

evaluate 失敗 gate：
- A：{"no_four_same_opening":3,"used_branch_within_cap":3}
- B：{"decision_in_expected_set":2,"no_four_same_opening":4,"used_branch_within_cap":1,"question_budget":3}
- C：{"decision_in_expected_set":1,"used_branch_within_cap":1}

總費用 $6.352。
評審（固定 Sonnet 5）另跑：`run_critic.ts <tag>/arm-X.json …`，見 README。

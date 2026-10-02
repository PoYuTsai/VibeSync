# 分析 A/B 彙總：2026-10-02-ack-a

commit 2eca434aff20d48566e42ec3d3ec4bbdaab9cd68（dirty=false）；2026-10-02T14:41:38.551Z；備援鏈關閉（每次只打指定模型）。
語料全是正常聊天：任何 refusal 都算誤擋。

| 臂 | 設定 | 次數 | evaluate 通過 | max_tokens | 拒答（類別） | HTTP 錯誤 | p50 | p95 | 平均 input／cache 寫／cache 讀／output | 費用 |
|---|---|---|---|---|---|---|---|---|---|---|
| A | Sonnet 5，production 原樣（thinking disabled） | 15 | 14/15 | 0 | 0（-） | - | 20.6s | 23.8s | 120／10539／28978／1627 | $0.730 |

evaluate 失敗 gate：
- A：{"stream_completes":1,"decision_in_expected_set":1}

總費用 $0.730。
評審（固定 Sonnet 5）另跑：`run_critic.ts <tag>/arm-X.json …`，見 README。

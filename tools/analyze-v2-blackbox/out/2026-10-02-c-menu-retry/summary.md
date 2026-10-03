# 分析 A/B 彙總：2026-10-02-c-menu-retry

commit d0d6acba79dd9f2ecbf851f56e30c615a8b393ec（dirty=true）；2026-10-02T08:05:13.976Z；備援鏈關閉（每次只打指定模型）。
語料全是正常聊天：任何 refusal 都算誤擋。

| 臂 | 設定 | 次數 | evaluate 通過 | max_tokens | 拒答（類別） | HTTP 錯誤 | p50 | p95 | 平均 input／cache 寫／cache 讀／output | 費用 |
|---|---|---|---|---|---|---|---|---|---|---|
| C | Sonnet 5.5，adaptive thinking＋effort low＋max_tokens +4000＋display omitted | 8 | 8/8 | 0 | 0（-） | - | 19.4s | 24.8s | 121／4937／34564／2814 | $0.381 |

evaluate 失敗 gate：
- C：-

總費用 $0.381。
評審（固定 Sonnet 5）另跑：`run_critic.ts <tag>/arm-X.json …`，見 README。

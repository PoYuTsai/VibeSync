# 開場救星與新話題的維運技術債：主審紀錄（2026-10-03）

分支 `claude/opener-newtopic-ops-debt`，與 main 分叉點 `9adbf87c`。程式全由 Claude 撰寫（Claude Code 與子代理），主審 Codex（OpenAI 家族），只讀封包。

| 輪 | 審查 head | 封包 sha256 | 回覆 sha256 | 結論 |
|---|---|---|---|---|
| 1 | f905628a | 7fd880a7296e9866d23040e9b6597c8af62ea149f76db767e486d0e78effab25 | 26955e774909fe4a90a8ef287272e47b282325914867e416caaf45b6e8db5c52 | APPROVED_WITH_RISK |
| 2 | 6a84427a | 12cb376742c67b1ec4ece7021a4f283877bda7b967307d17f3fc55649e80be05 | bce82924679a13e67e752ff4a60280ef16409a41898287d3cd0a4b755c72dd42 | APPROVED_WITH_RISK |

封包 sha256 是封包內 `SHA256SUMS.txt`（逐檔 sha256 清單）的 sha256；封包內容：完整快照（git archive of head）、`git format-patch --no-binary` 補丁、計畫、測試證據與審查範圍。

Eric 授權原話：「第二張pr清掉你剛說的opener + 新話題技術債，然後品質目前我們過關，看還有沒有什麼漏掉的」。

第 1 輪後處置：P2（5xx 平台錯誤誤稱不扣額度）以 6a84427a 修正；P3（ai_logs 正式入口串接沒有測試）不在本輪處理。

剩餘風險：P3 正式入口串接測試未補（兩輪皆確認串接本身正確）。待 Eric 明確接受；補測試需要 Eric 授權第 3 輪。

## 第 1 輪回覆

````text
- [P2] 平台錯誤轉中文後誤稱不扣額度 — `lib/features/opener/data/services/opener_service.dart:730` — 英文 `WORKER_LIMIT`（546）現在會走通用錯誤訊息，而第 895–896 行固定宣稱「本次不會扣額度」。生成可能已結算、但回應送達前被平台中止，因此無法保證未扣。新增測試反而鎖定此錯誤文案。— 改成「服務暫時無法確認狀態，請用同一筆請求重試」，並補生成階段收到 546 的測試。

- [P3] 成本紀錄缺少正式入口串接測試 — `supabase/functions/analyze-chat/analyze_chat_handler.ts:626` — 新增測試直接向各 handler 注入 `recordAiCall`；移除正式入口的注入，相關功能便會停止記帳，但新增測試仍可通過。目前串接本身正確。— 補入口測試，以假的 `EdgeRuntime.waitUntil` 與資料庫寫入驗證各路徑確實排程記帳。

Checked and OK

- 扣費結果不明仍不 release；5xx 重試保留同一 generationId。409 輸入不符與 404 分析不存在會清除待續生成。
- 每次供應商呼叫僅記一列，包含快取 token 成本；目前白名單及額外欄位不含用戶內容，寫入透過 `waitUntil` 排程。
- 新話題主呼叫與修復使用獨立 budget、相同期限。三次主呼叫加一次修復會有 **四列**，符合保留修復能力的設計；README 的「1–3 列」不精確。
- 暫時性能力讀取失敗可重試；缺少 RPC 的 `PGRST202` 仍維持 unavailable。
- 重新分析使用目前補充；連線逾時改為 70 秒；上一版提示詞常數符合計畫。
- 24 小時重播篩選、claim 過期清理與每小時 cron 支持刪除公式題相容驗證。
- CI 兩個折疊指令均無換行或行內註解，所列路徑全部存在，權限未擴張。

本輪核對 `9adbf87c → f905628a` 補丁與快照，未修改檔案、呼叫付費 API 或連 production。Deno／Flutter 測試未重跑，實作端自述的通過結果未獨立核實。上述 P2 若保留，需要 Eric 明確接受風險。

VERDICT: APPROVED_WITH_RISK
````

## 第 2 輪回覆

````text
第一輪 P2 已修復；P3 維持殘餘風險。本輪差異未發現新增阻擋問題。

- [P2] **FIXED** 平台錯誤轉中文後誤稱不扣額度 — `lib/features/opener/data/services/opener_service.dart:731` — 缺少中文訊息的 5xx 已改為「服務暫時無法確認狀態，請稍後用同一筆請求重試。」，不再承諾未扣額度。分析與生成階段均新增／更新 546 測試。— 無需追加修正。
- [P3] **NOT FIXED** 成本紀錄缺少正式入口串接測試 — `supabase/functions/analyze-chat/analyze_chat_handler.ts:626` — 本輪未補測試，正式入口漏接記帳仍可能逃過既有測試。— 後續補入口測試，以假的 `EdgeRuntime.waitUntil` 與資料庫寫入驗證排程；本輪列為殘餘風險。

Checked and OK

- 生成階段即使 `retryable=false`，5xx 仍提供重試，保留原 generationId 與送出時的回答。
- 中文伺服器訊息、4xx 分支、錯誤碼與重試欄位均維持原行為。
- 新文案與既有「同一筆請求重試」說法一致。
- 封包檔案 SHA-256 校驗全部通過；核對範圍為 `f905628a → 6a84427a`。

全程唯讀，未呼叫付費 API 或連 production。未重跑 Flutter 測試與 analyze；README 所述通過結果未獨立核實。

VERDICT: APPROVED_WITH_RISK
````

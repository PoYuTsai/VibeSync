# 收割／蒸餾行為偵測（2026-08-19）

> 反蒸餾三件套之二：不自動封鎖，先「看得見」。每週（或覺得流量怪時）用
> Supabase Dashboard → Logs → Edge Functions 查一次下列訊號；有可疑帳號再
> 人工判斷。自動化封鎖等真的發生過再談（YAGNI）。

## 訊號一：prompt 套取被擋（最強訊號，出現就值得看）

反 prompt 外洩守門觸發時的事件（正常用戶幾乎不可能觸發）：

| 事件 | 來源 | 意義 |
|---|---|---|
| `prompt_leak_blocked`（surface: opener / new_topic） | analyze-chat | 模型輸出含系統指示片段，整包已擋下、未扣費 |
| `prompt_leak: <field>`（generation 錯誤） | coach-chat | 教練卡片含系統指示片段，該卡被擋 |
| `chat_internal_label_leak` / `hint_internal_label_leak` | practice-chat | NPC/提示輸出含內部標籤或系統指示片段 |

Logs Explorer 搜尋：`prompt_leak` 或上述事件名。**同一帳號出現 ≥2 次＝有人在刻意套取**，記下 userId。

## 訊號二：頂額度的規律使用（收割量能訊號）

- 事件：`model_rate_limited`（scope: opener / new_topic / coach / practice）。
- 看法：單一帳號**連續多天**打到 30/日上限，且集中在少數功能＝疑似自動化收割；正常重度用戶會分散在多功能、且有訂閱付費。
- 交叉確認：該帳號是否 free tier（free 收割成本最低）、輸入是否模板化（同長度、同結構、規律間隔——看該帳號的 request 時間戳分佈）。

## 訊號三：串流中斷模式（防未來內容級串流的白嫖）

目前串流在 done 前不外流內容，此訊號暫無套利空間；若日後做內容級串流再啟用：
看 `opener_stream_started` 有而對應成功/失敗終局都沒有的帳號（大量開流即斷）。

## 發現可疑帳號後的階梯

1. 觀察：先確認不是誤判（真人重度用戶）。
2. 限流：必要時把該帳號 tier 或 rate limit 收緊（手動）。
3. 停權：ToS 5.2 已明文禁止蒸餾/大量擷取（2026-08-19 版），可直接依條款處理。

相關：`_shared/prompt_leak_guard.ts`（守門實作）、`docs/shared-agent-rules.md`

# 練習室溫度計（PR #88 第二步）：主審紀錄（2026-10-03）

分支 `claude/practice-thermometer-check`，base `9adbf87c`。第二步程式由 Bruce（Claude）撰寫，第 1 輪後由我們（Claude）接手修正；主審是 Codex（gpt-6-astra，OpenAI 家族），只讀封包。分數規則屬 R2。

| 輪 | 審查 head | 封包 sha256 | 回覆 sha256 | 結論 |
|---|---|---|---|---|
| 1 | 4b1a7068 | e59e4883a24b518e61ccdfcbb23c10adbea72863a4f4404d49dbea953b9caa6b | 533d24f101bdf7e4200e7c7c14d30cd2dd8989b683b07633464bdec956c948fb | BLOCKED |

封包 sha256 指封包根目錄 `SHA256SUMS.txt` 的雜湊。第 1 輪第一次派送因封包不是 git 目錄被 Codex CLI 拒絕執行，沒有任何輸出也沒有結論，不算一輪；同一份封包重送後才是上表的第 1 輪。

Eric 的授權與決定（原話）：
- 三項規則：「三項照建議」。
- 接手與合併：「我們接手處理乾淨 審完沒問題就合 然後關單」。
- 付費 P2 bakeoff：「補 跑」。

第 1 輪處置：兩個 P2 都已對照封包確認屬實並修正（`c82d5f87` 寫入全失敗回 DB 最後分數、delta 0；`84f98c80` 送出失敗還原不帶回舊「+N」）。同批另修 Claude 預審的 P3：提示保護改到 coherence 上限之後（`1f123fdc`）、RPC 沒回分數時 delta 用實際變化量、溫度計那一列等待中保留高度、ADR #50 補 `623bae1f`。

## 第 1 輪回覆

````text
[P2] supabase/functions/practice-chat/handler.ts:1907 — G2 遺漏未寫入分支，仍回傳未落帳的扣分與分數 — 確定性越界產生負分後，若更新 RPC 報錯或 CAS 重試均失敗，這裡仍回傳計算出的 fallback，與資料庫實際變化不符 — 未成功寫入時保留最後確認的權威分數、回傳兩軸 delta 0，補上 RPC 失敗及 CAS 重試耗盡測試。

[P2] lib/features/practice_chat/data/providers/practice_chat_providers.dart:1901 — G1 僅清除等待中的標籤，失敗還原仍帶回上一輪 +N — 上一輪 +4、下一輪逾時時，2123 行還原清除前保存的 priorState，重新顯示 +4；API 失敗亦同 — 同步清除失敗還原快照的 lastTemperatureDelta／temperatureReason，補上逾時與 API 失敗測試。

VERDICT: BLOCKED
````

# Coach 1:1 可信進度串流 — Codex 終審證據

- 日期：2026-07-16
- 程式 commit：`b09b6dd1`
- 審查範圍：`9cf3e9ac..b09b6dd1`
- 結論：APPROVED；P0 0／P1 0／P2 0／P3 0

## 產品決策

Eric 選擇 progress-only。Coach 只顯示伺服器確實發生的生成、驗證、重試與收尾階段；不使用 Flash 生成假思考，也不把模型 raw token 當答案提前顯示。完整 Coach 卡必須通過既有 schema、安全與 quota 規則後才可見。

## 審查結果

| 不變條件 | 結果 |
|---|---|
| 進度事件來自真實 server lifecycle，不是模型編寫的思考文案 | 通過 |
| final 仍是完整 validated Coach response，不顯示未驗證候選內容 | 通過 |
| clarification 維持不扣額度；成功回答維持既有扣額度語意 | 通過 |
| 429、retryable error、legacy JSON 與 deterministic fallback 維持相容 | 通過 |
| NDJSON partial line、UTF-8、單一 terminal 與事件順序可被 client 安全解析 | 通過 |
| App 不會在連線失敗後自動重送一個可能已扣費的 Coach 請求 | 通過 |

## 驗證

- Coach client targeted tests：44/44 passed。
- `coach-chat` Edge targeted tests：74/74 passed。
- 獨立 Codex review：APPROVED，沒有 P0／P1／P2／P3 finding。

## 2026-07-16 部署 smoke

- GitHub Actions run `29446745537` 成功；`coach-chat` v52 為 ACTIVE 且維持 JWT 驗證。
- 使用正式 Edge transport 與測試帳號直接要求 `Accept: application/x-ndjson`：HTTP 200、content type 正確，依序收到 `request → generating → validating → finalizing → done`。
- `request` 約 3.0 秒、`generating` 約 3.0 秒抵達；完整 validated card 約 20.9 秒完成。`done` 含可用 Coach card，沒有 raw model token 或假思考文字。

## 已知邊界

Coach 目前沒有可保存 final answer 的 server result replay ledger。若伺服器已扣額度、但網路在回傳前中斷，使用者手動再送一次仍可能形成新請求；因此本輪刻意不做自動重送。若未來要提前顯示正式內容或自動續傳，需另案實作 result ledger 與原子 replay。

# Game Hint 預產 Prefetch 設計（fallback 通用解）

> 2026-07-11 拍板。目標：讓練習室 hint fallback 罐頭少發生（通用解，同時治 timeout 型與守門擋下型），不等 7/17 日誌分型。
> 背景：現行 9s 預算＋首敗即 fallback（timeout 不重試）容易吐罐頭（`hint.ts:265` 錨定模板＋`hint.ts:507` 罐頭句），Eric 體感很差。
> 已否決的替代方案：hedged retry（只治 timeout 型）、升檔/升溫（無分型數據＝瞎調）、改罐頭文案（治標）。

## 拍板決定

1. **扣費時機＝消費才扣**：預產成功落快照但不扣 quota、不計 hint 次數；用戶真的點 hint、replay 命中時才補扣。
2. **範圍＝Game＋新手模式一起上**：兩者共用同一段生成＋fallback 程式碼（`practice_chat_game_hint_fallback_used` / `practice_chat_beginner_hint_fallback_used`），一次治好。

## 核心思路

完全複用現行 requestId 冪等骨架（指紋＝`sessionId + aiReplyCount`，`practice_chat_providers.dart:1156`；server preflight replay `handler.ts:1549-1571`）。prefetch＝「AI 回覆落地後提早打同一支 API」，用戶點擊時 replay 命中快照，零模型呼叫、次秒回應。

## 資料流（client）

1. **觸發**：AI 回覆落地後（`practice_chat_providers.dart:1049` 之後，`aiReplyCount` 已更新），四條件全過才後台開火：①mode 是 game 或 beginner ②本局沒有尚未被消費的舊預產（沒消費不重產）③hint 次數 gate 未滿 ④局未結束。requestId 沿用現行指紋，照樣寫入 `_pendingHintStore`。
2. **預產請求**：body 多帶 `prefetch: true`。client 端不顯示、不快取內容——結果唯一真相源是 server 快照。
3. **用戶點 hint**：一律照現行路徑發正式請求（同 requestId）→ replay 命中 → 此時補扣費＋計次 → 回傳。
4. **點擊時預產在途**：client 先 await 在途 prefetch future，然後照樣發自己的正式請求（扣費必定發生在正式請求，不會白嫖）。
5. **預產失敗／被限流**：靜默吞掉，點擊時走現行現場生成——最差＝今天的行為。
6. **已消費判定**：用戶對該回合實際發過正式 hint 請求；狀態存 controller 記憶體，app 重啟重置最多多浪費一次預產。
7. 舊預產遇新回覆天然作廢（指紋不同、永不被取用），不需清理邏輯。成本上限：不用 hint 的用戶每局最多浪費一次生成。

## Server 端（`supabase/functions/practice-chat/`）

1. **validate**：接受選填 `prefetch: boolean`。
2. **預產路徑與現行路徑的三個分歧**（其餘全共用）：
   - 生成失敗（timeout／守門／格式全敗）→ 釋放 latch、回錯誤、**絕不落 fallback 快照**（落了罐頭會被 replay 秒回，整案白做）。
   - 成功 → `record_practice_hint` 帶 `p_charged=false`，不扣 quota、不計次。
   - gate 檢查照舊全跑（quota、`decideHintGate`、rate limit `practice_hint`、game 解鎖）——擋下就不預產。
3. **replay 補扣**：preflight replay 命中「未扣費且非 fallback」快照 → 扣 quota＋計 hint 次數＋標記已扣 → 回傳。同 requestId 後續 replay 因已標記不重扣。唯一動計費的點，冪等靠已扣標記。
4. **migration**：ledger 加已扣費標記（或併入 result JSON）；`record_practice_hint` 加參數＋補扣 RPC（或擴充現有）。
5. **telemetry**：新增 `practice_chat_hint_prefetch`（fired/hit/miss/failed 帶 reason）；現行 `fallback_used` 日誌不動，上線後比對 fallback 率驗證成效。

## 測試

- Deno：預產成功不扣費、失敗不落罐頭、replay 補扣恰一次、重試不重扣、gate 擋下不預產。
- Dart：四觸發條件、沒消費不重產、在途 future 序列化。
- 逐檔跑測試（整目錄 type-check 在 HEAD 既有髒：`handler.ts:323` setTimeout）。

## 風險

動到 quota/計費＝高風險區，出貨前 Codex 雙審。

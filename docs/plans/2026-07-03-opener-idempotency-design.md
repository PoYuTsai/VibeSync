# Opener 扣費 idempotency 設計（Batch 4 #2，2026-07-03）

> 問題：opener 扣費（`increment_usage`）commit 後，回應在 PostgREST→Edge 或 Edge→client 丟失
> → client 見錯重試 → 同一次生成扣兩次 3 額度。窗口窄但真實（audit `2026-07-03-opener-batch4-audit.md` #2）。
> Eric 拍板：只去重扣費（不存結果 replay）；request-id＋輕量 ledger。

## 不變量（invariants）

1. 同一 `(user_id, request_id)` 至多扣費一次，跨任意次傳輸層重試成立。
2. 超限（RAISE）時 ledger 行必須隨扣費一起 rollback——額度重置後同 id 重試仍可正常扣費。
3. 舊 client（不帶 requestId）行為 byte-for-byte 不變：照走舊 `increment_usage`，fail-open。
4. 現有 `increment_usage` 函式與其他呼叫點（analyze-chat full、coach 等）零改動。
5. dedup hit 不是錯誤：照常回 200 完整結果，只記 telemetry。
6. free no-charge 路徑（`effectiveOpenerCost === 0`）與 test account 不進 ledger（今天也不扣費）。
7. **（Codex P2 修訂）**request_id 綁 payload：ledger 存 input_hash（SHA-256 of
   images＋profileInfo），同 id 重放但 hash 不符 → RAISE
   `OPENER_REQUEST_REPLAY_MISMATCH` → Edge 400 不扣費。防改造 client 付一次
   後同 id 換輸入無限免費重生成。連動：client 輸入變更**也 rotate**（原設計
   「輸入變更不 rotate」作廢——被 7 天免費重生成漏洞否決）。
8. **（Codex R2 P2a）**同 id 同 payload dedup 有預算：ledger `replay_count`
   每次 dedup +1，超過 `OPENER_REPLAY_LIMIT`（3，權威在 Edge）→ RAISE
   `OPENER_REQUEST_REPLAY_EXHAUSTED` → 400。擋「付一次刷無限新產出」。
9. **（Codex R2 P2b）**replay 檢查前移：模型呼叫前 preflight 讀 ledger
   （fail-open、非原子），mismatch／超限直接 400——不燒 Claude 成本；
   扣費 RPC 內同款檢查仍是原子權威，preflight 漏網的並發在那裡被抓。
10. 已接受殘餘：部署窗口內舊 Edge 寫入的 `input_hash=''` 行，新 Edge 重試
    同 id 會 mismatch 400（一次性、要求重新生成即可）；app 重啟丟 in-memory
    requestId＝回到今天的行為（可能重扣一次），不做持久化。
11. **（Codex R3 P2-1）**preflight 前移到 upfront quota gate 之前；已知同
    payload 預算內 dedup（＝那次已扣過費）跳過 gate——額度剛好扣到頂的
    用戶，回應丟失重試才拿得到 dedup 200 而不是被 429 卡死。dedup 不會再
    扣費，跳過安全；preflight 讀失敗 fail-open 時 gate 照常（殘餘：cap 邊
    緣＋讀失敗的重試吃 429，方向一致可接受）。
12. Codex R3 P2-2（並發同 id storm 於計數更新前燒模型成本）＝WAITING_ON_ERIC，
    見 docs/reviews/ai-arbitration-queue.md 2026-07-03 條目；CC 傾向不在本案
    修（損害有界＋同型暴露為 charge-after-generate 既有性質＋完整修法是設計
    變更）。

## 設計

### DB（migration 走 MCP `apply_migration`，絕不 `db push`）

- 表 `opener_request_charges`：
  - `user_id uuid not null`、`request_id uuid not null`、`cost int not null`、`created_at timestamptz not null default now()`
  - PK `(user_id, request_id)`；RLS enable＋零 policy（只有 service role 經 RPC 存取）。
- RPC `increment_usage_idempotent(p_user_id, p_messages, p_monthly_limit, p_daily_limit, p_request_id uuid) returns boolean`（SECURITY DEFINER）：
  1. lazy purge：刪該 user 7 天前的 ledger 行（不依賴 pg_cron）。
  2. `INSERT ... ON CONFLICT DO NOTHING`；沒插入 → return `false`（already charged，跳過扣費）。
  3. 插入成功 → 呼叫現有 `increment_usage(p_user_id, p_messages, p_monthly_limit, p_daily_limit)`；
     其 FOR UPDATE＋超限 RAISE 原樣傳播 → 整個 TX（含 ledger 行）rollback。
  4. return `true`（本次真的扣了）。

### Edge（`analyze-chat/index.ts` opener 扣費點，現 :5189）

- body 讀 `requestId`：合法 UUID（regex 驗證）→ 呼叫新 RPC；dedup hit（回 `false`）→
  `logInfo("opener_charge_dedup_hit", …)`，繼續正常回 200。
- 缺席或格式不合法 → 走舊 `increment_usage`，行為與今天完全相同。
- RPC 錯誤處理沿用現有分類：`classifyQuotaRpcError` 映射 429，其餘 500 no-charge 文案。

### Client（需新 TF build 才生效）

- `OpenerService.generateOpeners` 加 optional `requestId`，塞進 body。
- `opening_rescue_screen` 持有 `_pendingRequestId`：
  - 按生成時為 null → 產新 UUID。
  - 成功 parse 出 `OpenerResult` 後才清 null（下次生成是新 id）。
  - 失敗（任何 throw）保留——同輸入重試沿用同 id。
  - 輸入變更 rotate（Codex P2 修訂）：`OpenerRequestIdSession` 以輸入指紋
    判斷，指紋變即鑄新 id，與 server 端 input_hash 綁定一致。

## 明確不做（YAGNI）

- 不存結果 replay（重試重跑模型，我們吃 ~$0.02 token 成本，罕見事件可接受）。
- 不動 analyze/coach 等其他扣費點（同 pattern 若要推廣另案）。
- 不做 pg_cron 清理（lazy purge 足夠，行極小）。

## 驗證

- RPC：prod SQL 實測（比照 Batch C）——首扣成功、同 id 重扣跳過、超限 RAISE 後 ledger 無殘行、重置後同 id 可扣。
- Edge unit tests（mock RPC）：dedup hit 回 200 不再扣、無/壞 requestId 走舊路、429/500 映射不變。
- Client tests：requestId 生命週期（首按產生、失敗重試沿用、成功後 rotate、輸入變更不 rotate）。
- 計費高風險 → Codex 雙審（codex:rescue 直呼）拿到 APPROVED 才宣稱 dogfood safe。

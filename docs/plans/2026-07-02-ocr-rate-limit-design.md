# recognizeOnly OCR 限流設計（2026-07-02）

> P1 成本暴露修補：recognizeOnly 是免費 Sonnet vision 入口，現況零限流
> （index.ts 所有 quota preflight 都 `!recognizeOnly` 跳過）。
> **Eric 拍板（2026-07-02）：每用戶 6 次/分鐘、60 次/天。**
> 沿 Batch C `increment_usage` 模式：DB 原子計數＋FOR UPDATE＋超限 RAISE→429。

## 範圍

- 只限 `recognizeOnly === true` 路徑。opener/完整分析已有 quota 扣費保護，不動。
- 測試帳號（TEST_EMAILS）bypass，與既有 quota bypass 一致（App Review demo 不受阻）。
- OCR 隔離規則：新純 helper 放 `analyze-chat/ocr_rate_limit.ts`，不碰 `_shared/quota.ts`
  的訂閱額度契約。

## Invariants

- **I1（成本上界）**：任一非測試用戶，任 60 秒窗口內最多觸發 6 次、任一 UTC 日內最多
  60 次 recognizeOnly 的 Claude vision 呼叫。計數在 Claude 呼叫**之前**發生
  （計 attempt 不計 success），失敗的 vision 呼叫也佔名額——限的是成本不是產出。
- **I2（原子性）**：計數走單一 RPC `increment_ocr_usage`，交易內
  `INSERT ON CONFLICT DO NOTHING` → `SELECT ... FOR UPDATE` → 窗口重置 → 上限檢查
  → UPDATE。並發請求串行化，絕無 lost update；超限 RAISE 令整筆 rollback，絕無半計。
- **I3（不誤傷計費路徑）**：限流 RPC 只在 `recognizeOnly && !accountIsTest` 執行；
  不讀不寫 `subscriptions`，與月/日額度、increment_usage、run ledger 零交集。
- **I4（client 不落 paywall）**：429 payload 帶 `code: "OCR_RATE_LIMITED"`，
  **絕不帶 `monthlyLimit`/`dailyLimit` 鍵**——client `_quotaExceptionFrom429` 靠這
  兩鍵判 paywall 例外，缺鍵回 null → 走 `_mapAnalysisHttpError`，不會誤導升級 CTA。
- **I5（不觸發自動重試）**：`OCR_RATE_LIMITED` 不在 client `_retriableCodes`，
  429 不會被自動重打（否則限流自己養出 retry storm）。
- **I6（fail-open）**：限流 RPC 非超限錯誤（infra/schema cache）→ `logError` 後放行。
  理由：(a) recognizeOnly 是免費核心匯入流程，Free 用戶核心可用性優先；
  (b) RPC 失敗非攻擊者可誘發，成本暴露僅限 infra 故障窗口；
  (c) 與 increment_usage fail-closed 不衝突——那邊是計費完整性（不能扣費就不能供貨），
  這邊是節流計數（漏計一次成本上界仍近似成立）。
- **I7（權威在 Edge）**：限流值 6/60 是 Edge 常數傳參給 RPC，SQL 不寫死
  （同 Batch C「pricing 權威在 code」原則）。

## 窗口語義

- 分鐘窗：fixed window anchored at first request——`now - minute_window_start >= 60s`
  即重置歸零再計。最壞突發 = 窗界前後各 6 次 = 12 次/滑動分鐘，成本上界可接受，
  換取單 row per user、零事件表、零清理 job。
- 日窗：UTC 日翻轉即重置（`day_window_start` 的 UTC date ≠ 今天），與主額度
  daily reset 同語義（台北早上 8 點恢復），文案沿用「早上 8 點」。

## Failure matrix

| 情境 | 行為 | 依據 |
|---|---|---|
| 第 7 次/分鐘 | RAISE `OCR_RATE_LIMITED_MINUTE` → 429，文案「辨識太頻繁」+wait | I1/I2 |
| 第 61 次/日 | RAISE `OCR_RATE_LIMITED_DAILY` → 429，文案「今日辨識次數已達上限，早上 8 點恢復」+wait | I1/I2 |
| 兩上限同時撞 | 分鐘先判（先擋短窗，訊息較不悲觀） | — |
| 並發 6+2 請求同窗 | FOR UPDATE 串行化，恰 6 過 2 擋 | I2 |
| 首次請求（無 row） | INSERT ON CONFLICT DO NOTHING 後回讀 FOR UPDATE，必得 row | I2；防 23505（coach-chat selfHeal 同型教訓） |
| RAISE rollback | 首插 row 一併回滾，下次請求重插，計數不污染 | I2 |
| RPC infra 錯誤 | logError `ocr_rate_limit_check_failed` 後放行 | I6 |
| 測試帳號 | 完全 bypass，不打 RPC | 範圍 |
| 舊 client 收 429 | `_mapAnalysisHttpError` default → 「截圖辨識暫時失敗，請稍後再試」retry action；不在 `_retriableCodes` 不自動重打。server 先上即已止血，體驗待新 TF build 補 | I4/I5 |
| 新 client 收 429 | 429 case 認 `OCR_RATE_LIMITED` → 專屬文案 + wait | Task #5 |
| PostgREST schema cache 未刷 | migration 尾 `NOTIFY pgrst, 'reload schema'`（Batch C P2 同教訓）；仍失敗落 I6 fail-open | I6 |
| 非法請求（無圖/超大/格式錯） | 400 在限流檢查**之前**回，不佔名額 | 插入點 index.ts 圖片驗證後 |
| 多圖（≤3張）單請求 | 計 1 次（限流單位=請求；上界 18 圖/分可接受） | I1 |

## 元件

1. **Migration `20260702130000_ocr_rate_limit.sql`**：
   - 表 `public.ocr_rate_limits`（user_id PK REFERENCES auth.users ON DELETE CASCADE、
     minute_window_start/minute_count、day_window_start/day_count）；
     RLS 開啟不建 policy（service_role only，同 practice_profile_draw_events）。
   - RPC `increment_ocr_usage(p_user_id, p_minute_limit, p_daily_limit)`
     SECURITY DEFINER、`SET search_path = public`、grant 只給 service_role。
   - 套用：MCP apply_migration＋帳本對齊本檔名，**絕不 db push**。
2. **`analyze-chat/ocr_rate_limit.ts`**：常數 `OCR_RATE_LIMIT_PER_MINUTE = 6`、
   `OCR_RATE_LIMIT_PER_DAY = 60`；`classifyOcrRateLimitError()`（includes 抓 RAISE
   訊息，同 classifyQuotaRpcError 慣例）；`buildOcrRateLimitedPayload()`（守 I4）。
3. **index.ts 接線**：插入點＝圖片驗證後、AI 護欄前（現 ~5467 行）。
4. **Client `analysis_service.dart`**：`_mapAnalysisHttpError` 加 `case 429`
   認 `OCR_RATE_LIMITED`；429 quota payload 判別不受影響（先走
   `_quotaExceptionFrom429`，缺 limit 鍵回 null）。

## 驗收

- Deno：`ocr_rate_limit_test.ts` 純 helper 全綠；`index_test.ts` 源碼契約
  （`--allow-read`）鎖 gate 條件與呼叫順序。
- Flutter：`_mapAnalysisHttpError` 429 case＋auto-retry 豁免測試綠。
- SQL 語義由 Codex 雙審把關（本機無 pg 可跑）。
- 高風險：codex:rescue 雙審 APPROVED 才宣稱 dogfood safe。

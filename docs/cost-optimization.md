# Cost Optimization（Claude API）

> Claude API 成本控制策略與實作細節。

---

## 模型路由（2026-04-22 起，見 ADR #11）

| Tier | 模型 | 成本比重 |
|------|------|----------|
| Free | Haiku (`claude-haiku-4-5-20251001`) | 低 |
| Starter | **Sonnet** (`claude-sonnet-4-20250514`) | 中（原為 Haiku，升級後） |
| Essential | Sonnet | 中高 |
| 有圖片（所有層） | 強制 Sonnet（Vision 需要） | 高 |

---

## Prompt Caching（已啟用）

- **位置**: `supabase/functions/analyze-chat/fallback.ts:16-24`
- **原理**: System Prompt 加上 `cache_control: { type: "ephemeral" }`
- **效果**: 重複使用的 System Prompt tokens 減少 **~90% 成本**
- **Header**: `anthropic-beta: prompt-caching-2024-07-31`

---

## 測試帳號白名單（不扣額度 + 可強制 Haiku）

- **位置**: `supabase/functions/analyze-chat/index.ts:169`
- **白名單**: `TEST_EMAILS = ["vibesync.test@gmail.com"]`
- **效果**: 白名單內不扣每日/每月額度
- **Haiku 強制模式**: 設 `TEST_MODE=true` 環境變數

---

## AI 日誌追蹤

- **位置**: `supabase/functions/analyze-chat/logger.ts`
- **記錄欄位**: `user_id`, `model`, `tokens`, `cost`, `latency`, `status`, `fallback_used`
- **Supabase 表**: `ai_logs`

**關鍵指標**:
- 每用戶每日平均 cost
- Free tier fallback 到 Haiku 的比例
- Sonnet 呼叫的 cache hit rate（目標 > 60%）

---

## 計費規則

### 基本（手動輸入 / 截圖，ADR #19 r3，2026-06-11 起）
- **全對話字數合併計費**：`ceil(計費字數/40)`，soft cap 10 則（401~2000 字緩衝帶一律 10）
- 2001~4000 字 = 固定 20 則、需用戶確認（綁 payload hash + idempotency，重送絕不重扣）
- 4001+ 字 = 拒絕「請分批分析」、**不扣費** → 關閉「貼超長文仍只扣 20、AI 成本無上限」的成本洞
- 舊版 App（無 `billingProtocolVersion: 3`）>2000 字收 10 則 + log `legacy_over2000_capped`，log 歸零後可拔 legacy 路徑
- 成本邏輯：input tokens ∝ 總字數，字數制讓扣費與 AI 成本對齊；vision 成本倒掛（截圖走 Sonnet）為已知接受
- 詳見 `docs/pricing-final.md` 計費表與 `docs/decisions.md` ADR #19

### 開場救星（2026-04，2026-05-16 改）
- **一律 3 則**（不論幾張截圖；上限仍 3 張）
- 取代舊規則「基本 3 則 + 每張 +2」— 改動原因見 `docs/decisions.md` ADR #18
- 圖片 Sonnet 成本由平台吸收（換取可預期扣費與「附圖效果更好」可變柔性提示）

### 繼續對話（2026-04；ADR #19 改字數制）
- **只收增量**（新增字數差），不重複計算舊對話（原逐則制 commit `c4d8f5d`）
- 注意：server 每次仍整段重送 Claude，「每次分析最少 1 則」floor 有成本基礎

### Essential「我幫你修」（2026-07-16；ADR #22）
- 成功產生非空、可用的潤飾句固定扣 **1 則**，帶入的聊天脈絡不增加額度，也不走 20 則確認帶
- 4000 計費字元與 payload hard cap 仍保留；AI／解析／結果驗證／原子扣費失敗不扣
- 新 App 以 UUID 綁定輸入，第一個有效結果與 `increment_usage(..., 1)` 同交易提交；傳輸重送回同一結果且不重扣
- 免費重播只認 7 天內 ledger；逾期視為新請求。`pg_cron` 每小時清除逾期 live-table 列（最晚約 7 天 + 1 小時）；備份／PITR 副本依 Supabase 供應商週期處理
- ledger 欄位只存 AI 產生的潤飾句與理由，不另存原始草稿、完整對話輸入、usage 或 telemetry；生成文字仍可能反映草稿、姓名與對話內容
- 這是產品可預期性例外；Sonnet 長脈絡成本由 Essential 方案吸收，需以 `ai_logs` 監控平均 input tokens

### 文章學習限制
- 免費用戶每日 **3 篇**
- 超過導向升級

---

## 成本敏感操作

### 有圖片分析
強制 Sonnet，成本約是 Haiku 的 10-15 倍。優化方向：
1. 截圖上傳前自動壓縮（~1024px、85% quality）
2. 限制最多 3 張/次
3. 識別與分析分離（純識別用精簡 prompt）

### 批次用戶查詢
若未來擴充到 Batch API，cost 可再降 ~50%。

---

## 監控

- 定期 check `ai_logs` 的 cost 分佈
- Discord 通知接收負面反饋（品質問題也會間接暴露模型選擇失誤）
- Admin Dashboard（`admin-dashboard/`）有 Token 成本報表（ADR #8 Phase）

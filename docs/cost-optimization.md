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

### 基本（手動輸入 / 截圖）
- 1 則訊息 = 換行分隔 + 每 200 字 +1 則
- 詳見 `docs/pricing-final.md`

### 開場救星（2026-04）
- 基本 **3 則**
- 每張截圖 **+2 則**（最多 3 張 → 最多 9 則）

### 繼續對話（2026-04）
- **只收增量**，不重複計算舊對話（commit `c4d8f5d`）

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
- Telegram `@vibesync_feedback_bot` 接收負面反饋（品質問題也會間接暴露模型選擇失誤）
- Admin Dashboard（`admin-dashboard/`）有 Token 成本報表（ADR #8 Phase）

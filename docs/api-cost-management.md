# API 成本管理與負載控制

> 2026-07-17 校正：本文的架構與告警策略保留參考；當前模型、額度與單位經濟以 `docs/cost-optimization.md`、`docs/pricing-final.md` 及 `ai_logs` 為準。

## 成本估算

### Claude API 定價（程式內當前計價）

| 模型 | Input (1M tokens) | Output (1M tokens) |
|------|-------------------|-------------------|
| Claude Haiku 4.5 | $0.80 | $4.00 |
| Claude Sonnet 5 | $2.00 | $10.00 |
| Claude Sonnet 4.6 | $3.00 | $15.00 |

> Sonnet 5 為至 2026-08-31 的 launch price，到期前必須重新核價。

`ai_logs.cost_usd` 會把 Anthropic prompt cache creation 依 input 單價 1.25 倍、cache read 依 input 單價 0.1 倍納入；串流路徑必須解析 `message_start`／`message_delta` usage，不能以 0 tokens 記帳。未知模型 ID 以較保守的 Sonnet 4.6 價格估算。

### 單次分析成本估算

| 項目 | Tokens | 說明 |
|------|--------|------|
| System Prompt | ~500 | 固定 |
| 對話內容 (20 則) | ~400 | 平均 20 字/則 |
| AI 回覆 | ~300 | JSON 格式輸出 |
| **Total** | **~1,200** | |

**單次成本：**
- Haiku 4.5: ~$0.0019
- Sonnet 5: ~$0.0048
- Sonnet 4.6: ~$0.0072

### 月度成本預估

| 方案 | 用戶數 | 使用次數/月 | 模型 | 月成本 |
|------|--------|------------|------|--------|
| Free | 5,000 | 25,000 | analyze-chat Sonnet 5 | 約 $120，未計 caching / vision / retry |
| Starter / Essential | 以實際付費用戶為準 | 額度是訊息單位，不等於 API 次數 | analyze-chat Sonnet 4.6 | 用 `ai_logs` 計算 |

舊版 93% 毛利估算已作廢：它把額度單位當成 API 次數，並假設 Free 100% Haiku。現在必須以真實 token、cache hit、fallback 與圖片比例計算。

---

## 成本控制策略

### 策略 1: 智慧模型選擇

```typescript
function selectModel(context: AnalysisContext): Model {
  if (context.userTier === 'free') return 'claude-sonnet-5';
  return 'claude-sonnet-4-6';
}
```

此路由只描述 `analyze-chat`。Coach、Opener、Keyboard 等 endpoint 仍有各自的 tier / image 路由，不得把這段當成全產品共用規則。

### 策略 2: Prompt 優化

```typescript
// ❌ 浪費 token 的 prompt
const badPrompt = `
你是一位專業的社交溝通教練...
(500 字的詳細說明)
...
請分析以下對話...
`;

// ✅ 精簡的 prompt
const goodPrompt = `
角色:溝通教練
規則:回覆≤對方字數×1.8
輸出:JSON{enthusiasm:{score,level},replies:{extend,resonate,tease},strategy}
對話:
${messages}
`;

// 節省 ~40% input tokens
```

### 策略 3: Response 快取

```typescript
// 相似對話可以快取結果
const cacheKey = hashConversation(messages.slice(-5)); // 只看最後 5 則

const cached = await redis.get(cacheKey);
if (cached && Date.now() - cached.timestamp < 3600000) { // 1 小時內
  return cached.result;
}

const result = await callClaudeAPI(messages);
await redis.set(cacheKey, { result, timestamp: Date.now() });
```

### 策略 4: 用量硬限制

```typescript
const HARD_LIMITS = {
  free: 5,
  pro: 200,
  unlimited: 2000,  // 即使 unlimited 也有天花板
};

const RATE_LIMITS = {
  perMinute: 5,     // 每分鐘最多 5 次
  perHour: 30,      // 每小時最多 30 次
};

async function checkLimits(userId: string, tier: string) {
  // 1. 月度限制
  const monthlyUsed = await getMonthlyUsage(userId);
  if (monthlyUsed >= HARD_LIMITS[tier]) {
    throw new QuotaExceededError('Monthly limit reached');
  }

  // 2. Rate limit
  const recentCount = await getRecentUsage(userId, '1 minute');
  if (recentCount >= RATE_LIMITS.perMinute) {
    throw new RateLimitError('Too many requests, please wait');
  }
}
```

---

## 負載平衡 & 可擴展性

### 架構設計

```
                    ┌─────────────────┐
                    │   Cloudflare    │
                    │   (CDN + DDoS)  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │    Supabase     │
                    │   Edge Network  │
                    │   (全球節點)     │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────▼───────┐   ┌───────▼───────┐   ┌───────▼───────┐
│ Edge Function │   │ Edge Function │   │ Edge Function │
│   (亞洲)      │   │   (美洲)      │   │   (歐洲)      │
└───────┬───────┘   └───────┬───────┘   └───────┬───────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   Claude API    │
                    │  (Anthropic)    │
                    └─────────────────┘
```

**Supabase Edge Functions 優勢：**
- 自動全球部署
- 自動擴展
- 按使用計費
- 內建 DDoS 防護

### 降級策略

```typescript
async function analyzeWithFallback(messages: Message[]) {
  try {
    // 1. 嘗試正常分析
    return await callClaudeAPI(messages, { timeout: 15000 });
  } catch (error) {
    if (error.code === 'RATE_LIMITED') {
      // 2. Claude 被限流，等待重試
      await sleep(5000);
      return await callClaudeAPI(messages, { timeout: 30000 });
    }

    if (error.code === 'TIMEOUT' || error.code === 'SERVICE_UNAVAILABLE') {
      // 3. 服務不可用，返回本地快速分析
      return localQuickAnalysis(messages);
    }

    throw error;
  }
}

// 本地快速分析 (不依賴 API)
function localQuickAnalysis(messages: Message[]) {
  const theirMessages = messages.filter(m => !m.isFromMe);
  const avgLength = average(theirMessages.map(m => m.content.length));
  const hasQuestions = theirMessages.some(m => m.content.includes('?') || m.content.includes('？'));

  // 簡單規則判斷
  let score = 50;
  if (avgLength > 20) score += 15;
  if (hasQuestions) score += 20;

  return {
    enthusiasm: { score, level: scoreToLevel(score) },
    replies: {
      extend: '(服務暫時不可用，請稍後再試)',
      resonate: '(服務暫時不可用)',
      tease: '(服務暫時不可用)',
    },
    strategy: '目前服務繁忙，已提供基本分析',
    degraded: true,
  };
}
```

---

## 成本監控 Dashboard

### 需要追蹤的指標

```sql
-- Supabase SQL for monitoring

-- 1. 每日 API 呼叫次數
SELECT
  DATE(created_at) as date,
  COUNT(*) as calls,
  COUNT(*) FILTER (WHERE model LIKE '%haiku%') as haiku_calls,
  COUNT(*) FILTER (WHERE model LIKE '%sonnet%') as sonnet_calls
FROM ai_logs
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- 2. 每日成本估算
SELECT
  DATE(created_at) as date,
  SUM(cost_usd) as estimated_cost_usd
FROM ai_logs
GROUP BY DATE(created_at);

-- 3. 異常用戶偵測 (單日使用超過 50 次)
SELECT user_id, COUNT(*) as daily_usage
FROM ai_logs
WHERE created_at > NOW() - INTERVAL '1 day'
GROUP BY user_id
HAVING COUNT(*) > 50;
```

### Alert 設定

| 指標 | 警戒線 | 動作 |
|------|--------|------|
| 日 API 成本 | > $20 | Slack 通知 |
| 日 API 成本 | > $50 | 緊急 Email + 限流 |
| 單用戶日用量 | > 100 | 自動暫停帳號 |
| API 錯誤率 | > 5% | 檢查服務狀態 |

---

## 預算控制流程

```
┌─────────────────────────────────────────────────────────┐
│                    預算控制流程                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  月預算: $300                                           │
│                                                         │
│  $0 ─────────── $150 ─────────── $250 ─────────── $300 │
│       正常區間      警戒區間       危險區間      停機     │
│                                                         │
│  正常區間 ($0-150):                                     │
│  └── 正常運作                                           │
│                                                         │
│  警戒區間 ($150-250):                                   │
│  ├── 切換所有請求到 Haiku                               │
│  ├── 減少 response token (更精簡的回覆)                 │
│  └── 通知管理員                                         │
│                                                         │
│  危險區間 ($250-300):                                   │
│  ├── 僅限 Pro/Unlimited 用戶                           │
│  ├── Free 用戶顯示「服務繁忙」                          │
│  └── 緊急通知                                           │
│                                                         │
│  超過 $300:                                             │
│  └── 暫停所有 API 呼叫，顯示維護中                      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

```typescript
// 實作預算控制
async function checkBudget(): Promise<BudgetStatus> {
  const monthlySpend = await getCurrentMonthSpend();
  const budget = 300; // USD

  if (monthlySpend > budget) {
    return { status: 'STOPPED', allowedTiers: [] };
  }
  if (monthlySpend > budget * 0.83) { // 250
    return { status: 'DANGER', allowedTiers: ['pro', 'unlimited'] };
  }
  if (monthlySpend > budget * 0.5) { // 150
    return { status: 'WARNING', allowedTiers: ['free', 'pro', 'unlimited'], forceHaiku: true };
  }
  return { status: 'NORMAL', allowedTiers: ['free', 'pro', 'unlimited'] };
}
```

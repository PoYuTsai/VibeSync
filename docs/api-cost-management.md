# API 成本管理與負載控制

## 成本估算

### Claude API 定價 (2024)

| 模型 | Input (1M tokens) | Output (1M tokens) |
|------|-------------------|-------------------|
| Claude 3.5 Haiku | $0.80 | $4.00 |
| Claude 3.5 Sonnet | $3.00 | $15.00 |
| Claude 3 Opus | $15.00 | $75.00 |

### 單次分析成本估算

| 項目 | Tokens | 說明 |
|------|--------|------|
| System Prompt | ~500 | 固定 |
| 對話內容 (20 則) | ~400 | 平均 20 字/則 |
| AI 回覆 | ~300 | JSON 格式輸出 |
| **Total** | **~1,200** | |

**單次成本：**
- Haiku: ~$0.001 (NT$0.03)
- Sonnet: ~$0.005 (NT$0.15)

### 月度成本預估

| 方案 | 用戶數 | 使用次數/月 | 模型 | 月成本 |
|------|--------|------------|------|--------|
| Free | 5,000 | 25,000 | 100% Haiku | $25 |
| Pro | 500 | 50,000 | 70/30 | $100 |
| Unlimited | 100 | 30,000 | 50/50 | $90 |
| **Total** | **5,600** | **105,000** | - | **~$215/月** |

**收入 vs 成本：**
- 預估月收入：NT$104,400 (~$3,300)
- API 成本：~$215 (~NT$6,800)
- **毛利率：~93%** ✅

---

## 成本控制策略

### 策略 1: 智慧模型選擇

```typescript
function selectModel(context: AnalysisContext): Model {
  // 強制使用 Haiku 的情況 (70%)
  const useHaiku =
    context.messageCount < 10 ||           // 短對話
    context.previousScore > 60 ||          // 熱度已高，變化小
    context.userTier === 'free';           // 免費用戶

  // 使用 Sonnet 的情況 (30%)
  const useSonnet =
    context.messageCount > 20 ||           // 長對話需要更多理解
    context.previousScore < 30 ||          // 冷淡需要策略
    context.isFirstAnalysis ||             // 首次建立基準
    context.userTier === 'unlimited';      // 付費用戶優先體驗

  if (useSonnet && !useHaiku) {
    return 'claude-3-5-sonnet-20241022';
  }
  return 'claude-3-5-haiku-20241022';
}
```

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
  SUM(CASE WHEN model = 'haiku' THEN 1 ELSE 0 END) as haiku_calls,
  SUM(CASE WHEN model = 'sonnet' THEN 1 ELSE 0 END) as sonnet_calls
FROM api_logs
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- 2. 每日成本估算
SELECT
  DATE(created_at) as date,
  SUM(
    CASE
      WHEN model = 'haiku' THEN (input_tokens * 0.0000008 + output_tokens * 0.000004)
      WHEN model = 'sonnet' THEN (input_tokens * 0.000003 + output_tokens * 0.000015)
    END
  ) as estimated_cost_usd
FROM api_logs
GROUP BY DATE(created_at);

-- 3. 異常用戶偵測 (單日使用超過 50 次)
SELECT user_id, COUNT(*) as daily_usage
FROM api_logs
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

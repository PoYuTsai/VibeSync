# VibeSync 商業級 SaaS 架構

> 目標：可承受 10 萬用戶、成本可控、資安完備、專業可靠

---

## Part 1: Token 成本控制 - 五層防護

### Layer 1: 信用點數制 (Credits System)

**不賣「次數」，賣「點數」**

```
1 點 = 1 次基礎分析 (Haiku, <10則訊息)
2 點 = 1 次進階分析 (Sonnet, 或 >10則訊息)
3 點 = 1 次深度分析 (長對話 + 複雜情緒)
```

| 方案 | 月費 | 點數 | 單點成本 | 我們成本/點 | 毛利 |
|------|------|------|----------|-------------|------|
| Starter | NT$99 | 30 點 | NT$3.3 | NT$0.15 | 95% |
| Pro | NT$249 | 100 點 | NT$2.49 | NT$0.15 | 94% |
| Business | NT$499 | 250 點 | NT$1.99 | NT$0.15 | 92% |

**優勢：**
- 用戶用多少付多少，心理上公平
- 我們成本永遠 < 收入的 8%
- 用完可以加購，彈性高

### Layer 2: 請求分級計費

```typescript
function calculateCredits(request: AnalysisRequest): number {
  let credits = 1; // 基礎

  // 訊息數量
  if (request.messageCount > 10) credits += 0.5;
  if (request.messageCount > 20) credits += 0.5;

  // 模型選擇
  if (request.model === 'sonnet') credits += 1;

  // 額外功能
  if (request.includeDetailedAnalysis) credits += 0.5;

  return Math.ceil(credits);
}
```

### Layer 3: 智慧快取層 (Redis)

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Request    │────▶│    Cache     │────▶│  Claude API  │
│              │     │   (Redis)    │     │              │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                     Cache Hit? ──▶ 直接返回，不花錢
                            │
                     Cache Miss ──▶ 呼叫 API，結果存 Cache
```

```typescript
async function analyzeWithCache(messages: Message[]): Promise<Result> {
  // 1. 生成快取 key (對話特徵 hash)
  const cacheKey = generateCacheKey(messages);

  // 2. 檢查快取
  const cached = await redis.get(cacheKey);
  if (cached) {
    // 快取命中 → 免費！
    return JSON.parse(cached);
  }

  // 3. 呼叫 API
  const result = await callClaudeAPI(messages);

  // 4. 存入快取 (1小時過期)
  await redis.setex(cacheKey, 3600, JSON.stringify(result));

  return result;
}

function generateCacheKey(messages: Message[]): string {
  // 只用最後 5 則訊息的特徵
  const lastFive = messages.slice(-5);
  const features = lastFive.map(m => ({
    isFromMe: m.isFromMe,
    lengthBucket: Math.floor(m.content.length / 10), // 長度分桶
    hasQuestion: m.content.includes('?'),
    hasEmoji: /[\u{1F600}-\u{1F64F}]/u.test(m.content),
  }));
  return `analysis:${hash(JSON.stringify(features))}`;
}
```

**預估快取命中率：30-40%** → 直接省 30-40% API 成本

### Layer 4: 請求佇列 + 批次處理

```
高峰期不即時處理，而是排隊批次處理

用戶請求 ──▶ 佇列 ──▶ 批次處理 (每 5 秒一批)
                           │
                           ├── 合併相似請求
                           ├── 優先處理付費用戶
                           └── 限制同時 API 呼叫數
```

```typescript
class RequestQueue {
  private queue: AnalysisRequest[] = [];
  private processing = false;
  private maxConcurrent = 10; // 最多同時 10 個 API 請求

  async enqueue(request: AnalysisRequest): Promise<Result> {
    return new Promise((resolve, reject) => {
      this.queue.push({
        ...request,
        resolve,
        reject,
        priority: this.getPriority(request.userTier),
        timestamp: Date.now(),
      });

      this.processQueue();
    });
  }

  private getPriority(tier: string): number {
    // 付費用戶優先
    return { business: 1, pro: 2, starter: 3, free: 4 }[tier] || 5;
  }

  private async processQueue() {
    if (this.processing) return;
    this.processing = true;

    while (this.queue.length > 0) {
      // 按優先級排序
      this.queue.sort((a, b) => a.priority - b.priority);

      // 取出最多 maxConcurrent 個請求
      const batch = this.queue.splice(0, this.maxConcurrent);

      // 並行處理
      await Promise.all(batch.map(req => this.processOne(req)));

      // 短暫延遲，避免 API rate limit
      await sleep(100);
    }

    this.processing = false;
  }
}
```

### Layer 5: 熔斷器 (Circuit Breaker)

```typescript
class CostCircuitBreaker {
  private dailyCost = 0;
  private monthlyCost = 0;
  private isOpen = false;

  private readonly DAILY_LIMIT = 50;    // $50/天
  private readonly MONTHLY_LIMIT = 500; // $500/月

  async checkAndRecord(cost: number): Promise<boolean> {
    if (this.isOpen) {
      throw new ServiceDegradedError('服務暫時降級，請稍後再試');
    }

    this.dailyCost += cost;
    this.monthlyCost += cost;

    // 檢查是否需要熔斷
    if (this.dailyCost > this.DAILY_LIMIT) {
      this.tripBreaker('daily');
      return false;
    }

    if (this.monthlyCost > this.MONTHLY_LIMIT) {
      this.tripBreaker('monthly');
      return false;
    }

    return true;
  }

  private tripBreaker(reason: string) {
    this.isOpen = true;

    // 發送緊急通知
    this.notifyAdmin(`熔斷器觸發: ${reason} limit exceeded`);

    // 30 分鐘後自動恢復 (半開狀態)
    setTimeout(() => {
      this.isOpen = false;
    }, 30 * 60 * 1000);
  }
}
```

---

## Part 2: 用戶規模化架構

### 10 萬用戶時的架構

```
                         ┌─────────────────────────────────┐
                         │         Cloudflare              │
                         │   (CDN + DDoS + Rate Limit)     │
                         └───────────────┬─────────────────┘
                                         │
                         ┌───────────────▼─────────────────┐
                         │      Supabase Edge Network      │
                         │         (全球 30+ 節點)          │
                         └───────────────┬─────────────────┘
                                         │
           ┌─────────────────────────────┼─────────────────────────────┐
           │                             │                             │
  ┌────────▼────────┐          ┌────────▼────────┐          ┌────────▼────────┐
  │  Edge Function  │          │  Edge Function  │          │  Edge Function  │
  │    (亞太區)     │          │    (美洲區)     │          │    (歐洲區)     │
  └────────┬────────┘          └────────┬────────┘          └────────┬────────┘
           │                             │                             │
           └─────────────────────────────┼─────────────────────────────┘
                                         │
                         ┌───────────────▼─────────────────┐
                         │        Upstash Redis            │
                         │      (Serverless Cache)         │
                         │    - 快取層 (30-40% 命中率)     │
                         │    - 請求佇列                   │
                         │    - Rate Limit 計數            │
                         └───────────────┬─────────────────┘
                                         │
                         ┌───────────────▼─────────────────┐
                         │        Claude API               │
                         │   (最多 10 concurrent calls)    │
                         └─────────────────────────────────┘
```

### 成本估算 (10 萬用戶)

| 用戶類型 | 數量 | 月用量/人 | 總用量 | API 成本 |
|----------|------|-----------|--------|----------|
| Free | 80,000 | 5 次 | 400,000 | $400 |
| Starter | 15,000 | 20 次 | 300,000 | $300 |
| Pro | 4,000 | 50 次 | 200,000 | $200 |
| Business | 1,000 | 100 次 | 100,000 | $100 |
| **Total** | **100,000** | - | **1,000,000** | **$1,000** |

**快取節省 35%:** $1,000 × 0.65 = **$650/月**

| 項目 | 月成本 |
|------|--------|
| Claude API | $650 |
| Supabase Pro | $25 |
| Upstash Redis | $10 |
| Cloudflare Pro | $20 |
| **Total** | **$705/月** |

| 項目 | 月收入 |
|------|--------|
| Starter (15,000 × NT$99) | NT$1,485,000 |
| Pro (4,000 × NT$249) | NT$996,000 |
| Business (1,000 × NT$499) | NT$499,000 |
| **Total** | **NT$2,980,000 (~$94,000)** |

**毛利率：99.3%** ✅

---

## Part 3: 專業 SaaS 指標

### 關鍵指標 Dashboard

```typescript
interface SaaSMetrics {
  // 收入指標
  mrr: number;              // Monthly Recurring Revenue
  arr: number;              // Annual Recurring Revenue
  arpu: number;             // Average Revenue Per User

  // 成本指標
  cac: number;              // Customer Acquisition Cost
  ltv: number;              // Lifetime Value
  ltvCacRatio: number;      // LTV:CAC (目標 > 3:1)

  // 使用指標
  dau: number;              // Daily Active Users
  mau: number;              // Monthly Active Users
  dauMauRatio: number;      // 黏著度 (目標 > 20%)

  // 流失指標
  churnRate: number;        // 月流失率 (目標 < 5%)
  netRevenueRetention: number; // 淨收入留存 (目標 > 100%)

  // 成本效率
  apiCostPerUser: number;   // API 成本/用戶
  grossMargin: number;      // 毛利率 (目標 > 80%)
}
```

### 健康指標標準

| 指標 | 危險 | 警戒 | 健康 | 優秀 |
|------|------|------|------|------|
| 毛利率 | <60% | 60-75% | 75-85% | >85% |
| LTV:CAC | <2:1 | 2-3:1 | 3-5:1 | >5:1 |
| 月流失率 | >10% | 5-10% | 3-5% | <3% |
| DAU/MAU | <10% | 10-15% | 15-25% | >25% |

---

## Part 4: 資安合規完整清單

### Security Checklist

#### 認證與授權
- [x] JWT Token (1hr 過期)
- [x] Refresh Token 機制
- [x] OAuth 2.0 (Google/Apple)
- [ ] 雙因素認證 (2FA) - V2
- [x] 密碼最小強度要求

#### 資料保護
- [x] 傳輸加密 (TLS 1.3)
- [x] 本地資料加密 (AES-256)
- [x] API Key 不進入 Client
- [x] PII 資料最小化
- [x] 對話資料不上雲

#### API 安全
- [x] Rate Limiting (per user, per IP)
- [x] Request Validation
- [x] SQL Injection 防護 (Supabase RLS)
- [x] CORS 設定
- [ ] API Versioning - V2

#### 監控與回應
- [x] Sentry 錯誤追蹤
- [x] 異常行為偵測
- [x] 成本監控告警
- [ ] 安全事件 Playbook - V2

#### 合規
- [x] 隱私權政策
- [x] 使用條款
- [x] GDPR 資料匯出/刪除
- [ ] SOC 2 Type II - 未來
- [ ] ISO 27001 - 未來

---

## Part 5: 商業模式畫布

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        VibeSync Business Model Canvas                    │
├─────────────────┬─────────────────┬─────────────────┬───────────────────┤
│  Key Partners   │ Key Activities  │Value Proposition│ Customer Relations│
│                 │                 │                 │                   │
│ • Anthropic     │ • AI 模型優化   │ • 提升對話品質  │ • 自助式 App      │
│   (Claude API)  │ • 用戶體驗優化  │ • 即時回覆建議  │ • Email 支援      │
│ • Supabase      │ • 內容更新      │ • 隱私保護      │ • 社群經營        │
│ • RevenueCat    │ • 社群經營      │ • 使用簡單      │                   │
│                 │                 │                 │                   │
├─────────────────┼─────────────────┼─────────────────┼───────────────────┤
│  Key Resources  │                 │                 │ Customer Segments │
│                 │                 │                 │                   │
│ • AI 訓練資料   │                 │                 │ • 20-35歲男性     │
│ • 框架知識庫    │   Channels      │                 │ • 社交焦慮者      │
│ • 技術團隊      │                 │                 │ • 自我提升族群    │
│                 │ • App Store     │                 │                   │
│                 │ • Google Play   │                 │                   │
│                 │ • 社群媒體      │                 │                   │
│                 │ • KOL 合作      │                 │                   │
├─────────────────┴─────────────────┴─────────────────┴───────────────────┤
│                           Cost Structure                                 │
│                                                                         │
│  Variable: Claude API (~$0.005/次), Supabase ($25/月), Infra (~$50/月)  │
│  Fixed: 人力成本, 行銷費用, App Store 費用 ($99/年)                      │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                           Revenue Streams                                │
│                                                                         │
│  • 訂閱收入 (Starter/Pro/Business)                                      │
│  • 點數加購                                                              │
│  • 未來: 企業版 (B2B)                                                    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Part 6: 應急計畫

### 情境 1: API 成本暴增

```
觸發: 日成本 > $100
動作:
1. 自動切換所有請求到 Haiku
2. 啟用激進快取 (相似度 80% 即命中)
3. Free 用戶暫停服務
4. 通知管理員

觸發: 日成本 > $200
動作:
1. 暫停所有 Free + Starter
2. Pro/Business 限制每小時 5 次
3. 緊急通知 + 人工介入
```

### 情境 2: 用戶暴增 (病毒式增長)

```
觸發: 日新增 > 10,000
動作:
1. 新用戶進入等待名單
2. 邀請碼機制 (現有用戶可邀請 3 人)
3. 確保現有用戶體驗不降級
```

### 情境 3: 服務中斷

```
觸發: API 錯誤率 > 10%
動作:
1. 啟用本地降級分析
2. 顯示「服務繁忙」提示
3. 自動重試佇列
4. 通知用戶預估恢復時間
```

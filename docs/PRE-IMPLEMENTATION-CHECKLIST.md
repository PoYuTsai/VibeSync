# VibeSync 實作前完整檢查清單

> 在開始寫任何程式碼之前，確認以下所有項目都已決定且文件化。

---

## ✅ 已完成決策

### 1. 產品定位
| 項目 | 決定 |
|------|------|
| 產品名稱 | VibeSync 頻率調校師 |
| 定位 | 社交溝通教練 (非約會工具) |
| 目標用戶 | 20-35歲男性，願意投資自我提升 |
| 核心功能 | 熱度分析 + 回覆建議 + Needy 警示 |
| 獨特價值 | 1.8x 黃金法則 + MK 框架知識 |

### 2. 技術架構
| 層級 | 技術 | 狀態 |
|------|------|------|
| Frontend | Flutter 3.x + Riverpod | ✅ 確定 |
| Local DB | Hive (AES-256 加密) | ✅ 確定 |
| Backend | Supabase (Auth + PostgreSQL + Edge Functions) | ✅ 確定 |
| AI | Claude API (Haiku 70% + Sonnet 30%) | ✅ 確定 |
| Payment | RevenueCat + App Store/Google Play | ✅ 確定 |
| Cache | Upstash Redis (Serverless) | ✅ 確定 |

### 3. 訂閱模型 (點數制)
| 方案 | 價格 | 月點數 | 每日上限 | App Store Tier |
|------|------|--------|----------|----------------|
| Free | NT$0 | 5 | 3 | - |
| Starter | NT$100 | 30 | 5 | Tier 3 ($2.99) |
| Pro | NT$250 | 100 | 15 | Tier 8 ($7.99) |
| Business | NT$490 | 250 | 30 | Tier 15 ($14.99) |

### 4. 成本控制
| 防護層 | 機制 |
|--------|------|
| Layer 1 | 點數制 (用多少付多少) |
| Layer 2 | 每日上限 (防止一天用完) |
| Layer 3 | Redis 快取 (省 30-40% API) |
| Layer 4 | 請求佇列 (控制並發) |
| Layer 5 | 熔斷器 (日成本 >$50 自動降級) |

### 5. 資安
| 項目 | 方案 |
|------|------|
| API Key | 只存 Supabase Secrets，永不進入 Client |
| 對話資料 | 本地 AES-256 加密，永不上傳 |
| 信用卡 | 我們不經手，全由 App Store 處理 |
| JWT | 1 小時過期 + 自動刷新 |

### 6. App Store / Google Play
| 項目 | iOS | Android |
|------|-----|---------|
| 分類 | Lifestyle | Social |
| 定價 | 固定 Tier | 自訂 |
| 抽成 | 15% (<$1M) | 15% (<$1M) |
| 審核 | 較嚴格 | 較寬鬆 |

### 7. 跨平台支付
| 項目 | 決定 |
|------|------|
| SDK | RevenueCat (統一處理 iOS/Android) |
| 用戶識別 | Supabase user ID = RevenueCat app_user_id |
| 跨平台訂閱 | 帳號綁定，訂閱狀態存我們資料庫 |
| 價格差異 | iOS 用 Tier, Android 自訂接近價格 |

---

## 📋 文件清單

```
docs/
├── plans/
│   ├── 2026-02-26-vibesync-design.md         # 設計規格書
│   └── 2026-02-26-vibesync-implementation.md # 實作計畫 (15 任務)
├── app-store-strategy.md           # App Store 審核策略
├── security-architecture.md        # 資安架構
├── api-cost-management.md          # API 成本管理
├── pricing-strategy.md             # 定價策略
├── commercial-saas-architecture.md # 商業 SaaS 架構
├── payment-subscription-design.md  # 支付訂閱設計 (含 UI)
└── PRE-IMPLEMENTATION-CHECKLIST.md # 本文件
```

---

## 🔢 關鍵數字

### 成本估算 (每月)
| 項目 | 1,000 用戶 | 10,000 用戶 | 100,000 用戶 |
|------|-----------|-------------|--------------|
| Claude API | $20 | $100 | $650 |
| Supabase | $25 | $25 | $25 |
| Redis | $0 | $10 | $10 |
| 其他 | $5 | $20 | $20 |
| **總計** | **$50** | **$155** | **$705** |

### 收入估算 (每月)
| 規模 | 付費率 | MRR (USD) |
|------|--------|-----------|
| 1,000 用戶 | 10% | $500 |
| 10,000 用戶 | 15% | $9,000 |
| 100,000 用戶 | 20% | $94,000 |

### 毛利率
| 規模 | 毛利率 |
|------|--------|
| 1,000 用戶 | 90% |
| 10,000 用戶 | 98% |
| 100,000 用戶 | 99% |

---

## ⚠️ 風險與應對

| 風險 | 等級 | 應對 |
|------|------|------|
| App Store 拒絕 | 🔴 高 | 定位「溝通教練」+ 申訴模板準備 |
| API 成本爆炸 | 🔴 高 | 五層防護 + 熔斷器 |
| 用戶暴增 | 🟡 中 | Supabase Edge 自動擴展 + 等待名單 |
| 訊息解析失敗 | 🟡 中 | 友善錯誤提示 + 格式範例 |

---

## 📱 UI 畫面清單

### 核心畫面
- [ ] 首頁 (對話列表)
- [ ] 新增對話 (輸入)
- [ ] 分析結果 (熱度+建議)
- [ ] 設定頁

### 認證畫面
- [ ] 登入 (Google/Apple/Email)
- [ ] 註冊
- [ ] 忘記密碼

### 訂閱畫面
- [ ] Paywall (方案選擇)
- [ ] 訂閱管理
- [ ] 點數用完提示
- [ ] 每日上限提示

### 其他
- [ ] Onboarding (首次使用引導)
- [ ] 隱私權政策
- [ ] 使用條款

---

## 🚀 實作順序建議

### Phase 1: 基礎建設 (Week 1)
1. Flutter 專案初始化
2. 目錄結構 + 主題系統
3. Hive 本地儲存

### Phase 2: 核心功能 (Week 2-3)
4. 對話輸入 + 解析
5. UI 畫面 (首頁/輸入/分析)
6. Supabase Edge Function (Claude API)

### Phase 3: 認證訂閱 (Week 4)
7. Supabase Auth (Google/Apple)
8. RevenueCat 整合
9. Paywall + 訂閱管理

### Phase 4: 優化上線 (Week 5-6)
10. Redis 快取層
11. 錯誤處理 + 降級
12. 測試 + Bug 修復
13. App Store 提交

---

## ✋ 實作前最後確認

在開始寫 code 之前，請確認：

- [ ] **商業模式清楚**：點數制，無 Unlimited
- [ ] **幣別確定**：顯示 TWD，App Store 用 Tier
- [ ] **每日限制**：Free 3次, Starter 5次, Pro 15次, Business 30次
- [ ] **成本上限**：熔斷器 $50/日
- [ ] **UI 流程**：Paywall 時機、限制提示
- [ ] **資安**：API Key 只在 Supabase，對話不上雲
- [ ] **夥伴分工**：誰做什麼？

---

## 📞 需要進一步討論的問題

如果以上有任何不確定，現在是最佳時機提出：

1. 免費試用期要多長？(目前設 7 天)
2. 加購點數的價格？(目前設 20點 NT$60)
3. 退款政策？(由 App Store 處理)
4. 客服管道？(Email? 社群?)
5. 首發市場？(台灣優先? 還是同時多地區?)

---

**確認以上所有內容後，即可開始實作。**

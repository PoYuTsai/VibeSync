# VibeSync Project

> **新 Session 入口文件** - Claude 開始時自動讀取此檔案

## Quick Start (新 Session 必讀)

```
📌 專案狀態：MVP 沙盒測試中 (功能已可用)
📌 定價模式：訊息制 (2 付費方案)
📌 測試網址：https://web-beta-tawny.vercel.app
📌 測試帳號：vibesync.test@gmail.com / test123456 (Essential tier, 不扣額度)
📌 最後更新：2026-02-28
```

### 🎯 當前開發進度

#### ✅ 已完成功能
| 功能 | 狀態 | 備註 |
|------|------|------|
| **AI 分析引擎** | ✅ 完成 | GAME 階段、心理分析、5種回覆、最終建議 |
| **Supabase Edge Function** | ✅ 部署 | `analyze-chat`，含護欄、fallback、日誌 |
| **訂閱系統** | ✅ 完成 | 訊息制額度、每日/每月上限、功能分層 |
| **對話延續** | ✅ 完成 | 可新增訊息並重新分析 |
| **匯出對話** | ✅ 完成 | 複製完整對話+分析結果供 prompt 優化 |
| **手動分析觸發** | ✅ 完成 | 不再自動分析，用戶手動點擊 |
| **Prompt Caching** | ✅ 完成 | 減少 ~60% token 成本 |
| **測試帳號白名單** | ✅ 完成 | 不扣額度，方便測試 |
| **CI/CD Web** | ✅ 完成 | push main → Vercel 自動部署 |
| **CI/CD Edge Function** | ✅ 完成 | push main → Supabase 自動部署 |
| **RWD 響應式設計** | ✅ 完成 | 手機/平板/桌面自適應 |
| **跨平台 UX 優化** | ✅ 完成 | iOS/Android 防 pull-to-refresh |

#### 🔄 待測試驗證
- [ ] iOS Safari 滑動體驗 (pull-to-refresh 是否完全修復)
- [ ] Android Chrome 滑動體驗
- [ ] 大螢幕 RWD 顯示效果

#### ⏸️ 暫停中
- [ ] iOS App 部署 (等待 Apple Developer 帳號核准)
- [ ] Admin Dashboard (排在實作計畫後段)

#### 📋 下一步
1. 繼續測試 AI 回覆品質，收集 prompt 優化案例
2. 若有 UX 問題持續調整
3. Apple 帳號核准後設定 iOS 部署

### 沙盒測試環境 (2026-02-28 上線)
- **Supabase Project**: `fcmwrmwdoqiqdnbisdpg`
- **Edge Function**: `analyze-chat` (已部署，--no-verify-jwt)
- **Claude Model**: `claude-sonnet-4-20250514` (Essential) / `claude-haiku-4-5-20251001` (Free/Starter)
- **Vercel**: https://web-beta-tawny.vercel.app
- **成本優化**: Prompt Caching 已啟用 (ephemeral cache)

### 測試帳號
| Email | 密碼 | Tier | 特性 |
|-------|------|------|------|
| `vibesync.test@gmail.com` | `test123456` | Essential | **不扣額度**，完整功能 |

### CI/CD 狀態
| 平台 | 狀態 | 觸發條件 | 備註 |
|------|------|----------|------|
| **Web** | ✅ 自動部署 | push main | Vercel |
| **Edge Function** | ✅ 自動部署 | push main (supabase/functions/**) | Supabase |
| Android | ✅ 成功 | 手動觸發 | APK 可下載 |
| iOS | ⏸️ 暫停 | - | 等待 Apple Developer 帳號核准 |

> **⚠️ 提醒**: iOS 部署暫時無法使用，請先用 **Web 沙盒測試**。Apple 核准後需設定 iOS 憑證。

### Apple Developer 帳號 (2026-02-27 購買)
- **狀態**: ⏳ 等待 Apple 審核 email
- **預計時間**: 24-48 小時（可能更長）
- **核准後需設定**:
  - GitHub Secrets: `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_PROVISIONING_PROFILE`
  - App Store Connect API Key

### 關鍵文件指引
| 要了解什麼 | 讀哪個文件 |
|------------|-----------|
| **完整設計規格 (v1.3)** | `docs/plans/2026-02-26-vibesync-design.md` |
| **實作計畫 (35 任務)** | `docs/plans/2026-02-26-vibesync-implementation.md` |
| **實作前檢查清單** | `docs/PRE-IMPLEMENTATION-CHECKLIST.md` |
| **定價方案** | `docs/pricing-final.md` |
| **法規文件** | `docs/legal/*.md` |

---

## Project Overview

VibeSync 是一款聊天輔助 SaaS App，幫助用戶提升社交對話技巧，最終目標：成功邀約。

### 核心 Know-How
- **GAME 五階段**：打開 → 前提 → 評估 → 敘事 → 收尾
- **哲學**：框架策略為輔 → 最終回歸「個人化 + 真誠流」

### 核心功能
- 熱度分析 (Enthusiasm Gauge 0-100)
- **GAME 階段判斷 + 心理分析**
- 五種回覆建議 (延展/共鳴/調情/幽默/冷讀)
- **AI 最終建議 + 理由 + 心理學依據**
- 話題深度分析 (事件→個人→曖昧)
- 廢物測試偵測 + 淺溝通解讀
- 對話健檢 (Essential 專屬)
- Needy 警示系統
- 對話記憶 (15輪完整 + 摘要)
- 1.8x 黃金法則字數控制
- **冰點放棄建議** (機會渺茫時建議開新對話)
- **真人一致性提醒** (見面才自然)

Target Audience: 20-35 歲，願意投資自我提升的個人用戶

## Tech Stack

- **Frontend**: Flutter 3.x + Riverpod
- **Backend**: Supabase (Auth, PostgreSQL, Edge Functions)
- **AI**: Claude API (Haiku + Sonnet 混合策略)
- **Subscription**: RevenueCat
- **Local DB**: Hive (加密儲存)

## Superpowers 開發工作流

> **重要**: 此專案遵循 superpowers skills 工作流程

### 開發流程圖
```
需求/想法
    │
    ▼
┌─────────────────────┐
│  brainstorming      │  ← 任何新功能/變更前必須
│  (探索設計)          │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  writing-plans      │  ← 產出實作計畫
│  (寫計畫)            │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  executing-plans    │  ← 按計畫逐步實作
│  (執行計畫)          │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  verification       │  ← 完成前驗證
│  (驗證完成)          │
└─────────────────────┘
```

### 必用 Skills
| 情境 | 使用的 Skill |
|------|-------------|
| 開始新功能/變更 | `superpowers:brainstorming` |
| 規劃實作步驟 | `superpowers:writing-plans` |
| 執行實作計畫 | `superpowers:executing-plans` |
| 寫新功能/修 bug | `superpowers:test-driven-development` |
| 遇到 bug/錯誤 | `superpowers:systematic-debugging` |
| 宣稱完成前 | `superpowers:verification-before-completion` |
| 需要 code review | `superpowers:requesting-code-review` |

### 已完成的計畫文件
- 設計規格: `docs/plans/2026-02-26-vibesync-design.md`
- 實作計畫: `docs/plans/2026-02-26-vibesync-implementation.md` (19 任務，v2.0)

### 開始實作時
```
使用 superpowers:executing-plans 執行實作計畫
```

---

## Development Conventions

### Code Style
- 使用 Flutter 官方 linting rules
- 檔案命名：snake_case
- Class 命名：PascalCase
- 每個 feature 使用 Clean Architecture (data/domain/presentation)

### Git Commit
- 使用繁體中文 commit message
- 格式：`[類型] 簡短描述`
- 類型：feat, fix, refactor, docs, test, chore
- **每次 commit 後立即 push** (不要等，直接推)
- 一個 commit 做一件事，保持原子性

### Privacy First
- 對話內容永不上傳伺服器儲存
- API 請求處理完即丟
- 本地資料使用 AES-256 加密

## Core Rules (AI Prompt)

### 1.8x 黃金法則
回覆字數 ≤ 對方字數 × 1.8，這是最高指導原則

### 熱度策略對照
- 0-30 (冰點)：鏡像冷處理、抽離
- 31-60 (溫和)：引導式提問、拋餌
- 61-80 (熱情)：80% 鏡像、保持沉穩
- 81-100 (高熱)：推拉、適度挑戰

## Debugging Protocol (自動學習)

> **重要**: Claude 遇到 bug 時必須自動更新此文件，不需要用戶提醒

### 自動記錄流程
```
Bug 發生 → 分析 → 修復 → 寫測試 → 更新 CLAUDE.md → commit & push
```

### When Bug Occurs
1. **記錄** - 立即在下方 Bugs & Fixes 區塊記錄
2. **分析** - 找出 root cause，不只是表面修復
3. **修復** - 寫測試驗證修復
4. **預防** - 更新 Common Pitfalls 避免再犯
5. **推送** - commit 此文件變更並 push

### Bug Report Format
```markdown
#### [YYYY-MM-DD] Bug 標題
**症狀**: 發生了什麼
**重現步驟**: 1. 2. 3.
**Root Cause**: 為什麼發生
**修復**: 怎麼修的
**預防**: 如何避免再犯
**相關檔案**: `path/to/file.dart:123`
```

### Common Pitfalls (自動累積)
<!-- Claude 修復 bug 後自動新增條目 -->
- [ ] Hive 未初始化就存取 → 確保 `StorageService.initialize()` 完成
- [ ] Riverpod provider 未 dispose → 使用 `autoDispose`
- [ ] 未處理 API error → 永遠 try-catch 外部呼叫
- [ ] Web 平台 secure storage 限制 → MVP 專注 mobile
- [ ] Edge Function 冷啟動 → 加 loading state + timeout 處理
- [ ] 訊息格式解析失敗 → 提供清楚錯誤訊息和格式範例

---

## Testing Strategy

### 測試分層
```
test/
├── unit/           # 純邏輯測試 (無 UI)
│   ├── services/
│   └── repositories/
├── widget/         # 單一元件測試
│   └── widgets/
└── integration/    # 完整流程測試
    └── flows/
```

### TDD 流程
1. **Red** - 先寫失敗的測試
2. **Green** - 寫最小程式碼讓測試通過
3. **Refactor** - 重構但保持測試通過

### 測試命名規範
```dart
test('should return cold level when score is 25', () { ... });
test('should throw exception when messages is empty', () { ... });
```

### 執行測試
```bash
# 全部測試
flutter test

# 特定檔案
flutter test test/unit/services/analysis_service_test.dart

# 含覆蓋率
flutter test --coverage
```

---

## Local Development

### 啟動 Demo
```bash
# Web (最快看效果)
flutter run -d chrome

# iOS Simulator
flutter run -d "iPhone 15 Pro"

# Android Emulator
flutter run -d emulator-5554

# 列出所有裝置
flutter devices
```

### Hot Reload vs Hot Restart
- **Hot Reload (r)**: 保留 state，快速更新 UI
- **Hot Restart (R)**: 重置 state，完整重啟

### Supabase 本地開發
```bash
# 啟動本地 Supabase (含 PostgreSQL, Auth, Edge Functions)
npx supabase start

# 本地 Dashboard
http://localhost:54323

# 停止
npx supabase stop
```

---

## Model Selection (Claude Code)

### 開發時使用模型建議
| 任務類型 | 建議模型 | 原因 |
|----------|----------|------|
| 簡單修 bug | Haiku | 快、便宜 |
| 寫新功能 | Sonnet | 平衡 |
| 架構設計 | Opus | 深度思考 |
| Code Review | Sonnet | 夠用 |

### 切換模型
```bash
# 在 Claude Code 中
/model sonnet
/model haiku
/model opus
```

---

---

## AI 回覆優化流程

> **重要**: Claude API 不會從單次呼叫中「學習」，優化是透過改進 System Prompt

### 沙盒測試 → Prompt 優化循環

```
1. 沙盒測試對話
   ↓
2. 記錄「不滿意的回覆」+ 原因
   ↓
3. 分析問題模式 (太直接? 太婉轉? 太長? 不自然?)
   ↓
4. 修改 System Prompt (supabase/functions/analyze-chat/index.ts)
   ↓
5. 重新部署 Edge Function
   ↓
6. 再次測試驗證
```

### 記錄格式 (在下方 Bugs & Fixes 記錄)

```markdown
#### [YYYY-MM-DD] 回覆優化 - [問題類型]
**對話情境**: [簡述對話內容]
**AI 回覆**: [原本的回覆]
**問題**: [為什麼不好]
**期望**: [應該怎麼回]
**Prompt 修改**: [改了什麼]
```

### System Prompt 位置
`supabase/functions/analyze-chat/index.ts` 中的 `SYSTEM_PROMPT` 常數

### 部署指令
```bash
SUPABASE_ACCESS_TOKEN=sbp_xxx npx supabase functions deploy analyze-chat --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg
```

---

## 成本優化技術細節

### Prompt Caching (已啟用)
- **位置**: `supabase/functions/analyze-chat/fallback.ts:16-24`
- **原理**: System Prompt 加上 `cache_control: { type: "ephemeral" }`
- **效果**: 重複使用的 System Prompt tokens 減少 90% 成本
- **Header**: `anthropic-beta: prompt-caching-2024-07-31`

### 測試帳號白名單 (不扣額度)
- **位置**: `supabase/functions/analyze-chat/index.ts:169`
- **白名單**: `TEST_EMAILS = ["vibesync.test@gmail.com"]`
- **效果**: 白名單內的帳號不會扣除每日/每月額度
- **模型**: 測試模式可強制使用 Haiku (設定 `TEST_MODE=true`)

### AI 日誌追蹤
- **位置**: `supabase/functions/analyze-chat/logger.ts`
- **記錄**: user_id, model, tokens, cost, latency, status, fallback_used
- **表格**: `ai_logs` (Supabase)

---

## Lessons Learned

### Bugs & Fixes
<!-- 遇到 bug 時在此記錄，格式見上方 Debugging Protocol -->

#### [2026-02-28] iOS Safari Pull-to-refresh 關閉頁面
**症狀**: 在 iOS Safari 上下滑動時，整個網頁會被關閉
**Root Cause**: iOS Safari 的 pull-to-refresh 手勢會觸發頁面關閉
**修復**:
1. 在 `web/index.html` 加入 JS 防止頂部下拉時的默認行為
2. 使用 `overscroll-behavior: none` CSS
3. Flutter 端使用 `ClampingScrollPhysics` + `ScrollConfiguration`
**相關檔案**:
- `web/index.html` (JS + CSS)
- `lib/features/analysis/presentation/screens/analysis_screen.dart:452-458`

#### [2026-02-28] 每次開對話都自動分析
**症狀**: 進入對話頁面就自動呼叫 API 分析，浪費額度
**修復**: 改為手動觸發，新增「開始分析」按鈕
**相關檔案**: `lib/features/analysis/presentation/screens/analysis_screen.dart:71`

#### [2026-02-28] Claude 模型名稱過期
**症狀**: Edge Function 返回 "model not found" 錯誤
**Root Cause**: Claude 3.5 模型已停用，需改用 Claude 4.x
**修復**:
- `claude-3-5-haiku-20241022` → `claude-haiku-4-5-20251001`
- `claude-sonnet-4-20250514` 保持不變
**相關檔案**: `supabase/functions/analyze-chat/index.ts:190`

#### [2026-02-28] Edge Function CORS 錯誤
**症狀**: Flutter web 顯示 "Failed to fetch" 錯誤
**Root Cause**: 錯誤回應沒有 CORS headers
**修復**: 新增 `jsonResponse()` helper，所有回應都包含 CORS headers
**相關檔案**: `supabase/functions/analyze-chat/index.ts:193-205`

#### [2026-03-01] 熱度分析受用戶發言影響
**症狀**: 熱度分數會因為用戶自己說很多話而升高
**Root Cause**: AI 沒有明確指示只從對方回覆判斷熱度
**修復**: 在 System Prompt 新增「熱度分析規則」章節，明確列出只從「她」的訊息判斷：回覆長度、表情符號、主動提問、話題延伸、回應態度
**相關檔案**: `supabase/functions/analyze-chat/index.ts:88-95`

### Design Decisions

#### [2026-02-26] 對話資料不上雲
**決定**: 對話歷史只存本地，伺服器不保留
**原因**:
1. 隱私風險最小化
2. GDPR 合規簡化
3. App Store 審核友善
4. 用戶信任度提升

#### [2026-02-26] 混合 AI 模型策略
**決定**: 70% Haiku + 30% Sonnet
**原因**:
1. 成本降低 60-70%
2. 簡單情境不需要大模型
3. 複雜情境保持品質

#### [2026-02-26] 訊息制訂閱模型 (最終版)
**決定**: 訊息制，2 個付費方案 (Starter/Essential)
**定價**:
- Free: NT$0 / 30則/月 / 15則/天
- Starter: NT$149 / 300則/月 / 50則/天
- Essential: NT$349 / 1,000則/月 / 150則/天

**訊息計算**: 換行分割 + 每則上限 200 字

**原因**:
1. 簡化選擇，專注個人用戶
2. 變動成本轉嫁給用戶
3. 毛利 > 90%
4. 每日上限防止濫用

#### [2026-02-26] 五種回覆類型 + MK 框架
**決定**: 從 3 種擴充到 5 種回覆風格
**類型**:
- 🔄 延展 (細緻化深挖)
- 💬 共鳴 (情感連結)
- 😏 調情 (推拉反差)
- 🎭 幽默 (曲解/誇大)
- 🔮 冷讀 (假設代替問句)

**新增功能**:
- 話題深度階梯 (事件→個人→曖昧)
- 對話健檢 (Essential 專屬)
- 82/18 原則 (聆聽 vs 說話)
- 面試式提問警告

#### [2026-02-26] 對話記憶設計
**決定**: 一人一對話，永久持續，背景自動摘要
**策略**:
- 最近 15 輪：完整保留
- 更早輪次：自動摘要
- 用戶無感：對話一直連貫

**選擇追蹤**: AI 從對方回覆反推，90% 自動推測，10% 輕量確認

#### [2026-02-27] 設計規格 v1.1 - GAME 框架整合
**決定**: 整合完整 GAME 框架 Know-How 到 AI 分析引擎
**核心變更**:
- GAME 五階段：打開 → 前提 → 評估 → 敘事 → 收尾
- 核心技巧：隱性 DHV、框架控制、廢測處理、淺溝通解讀
- AI 輸出：GAME 階段 + 心理分析 + 5 回覆 + 最終建議 + 理由
- Session 設計：情境收集 (認識場景/多久/目標)
- UI 風格：高端極簡 (留白/動畫/字體層次)
- 冰點策略：可建議已讀不回 + 放棄建議
- 真人一致性提醒：見面才自然

**V2 功能 (後續)**:
- 圖片分析 (交友軟體破冰)
- TTS 語音朗讀

**待補**:
- 不負責任聲明 (用戶會提供文字)

#### [2026-02-26] 實作計畫 v2.0 更新
**決定**: 將實作計畫與設計規格書完全同步
**變更內容**:
1. 訂閱系統：從分析次數制改為訊息制 (30/300/1000)
2. 新增每日上限 (15/50/150) 與訊息計算邏輯
3. 回覆類型：從 3 種擴充到 5 種 (+ 幽默/冷讀)
4. 功能分層：Free 只有延展回覆，Starter/Essential 有完整功能
5. 新增 Phase 7-9：訊息計算、對話記憶、Paywall UI
6. 總任務數：15 → 19 tasks

**原因**:
- 設計規格書已定義完整功能，實作計畫需同步
- 避免實作與設計不一致造成返工

#### [2026-02-27] 設計規格 v1.3 - 運營補充
**決定**: 新增 Admin Dashboard 和沙盒測試環境設計
**Admin Dashboard**:
- 技術棧：Next.js 14 + Tailwind + Recharts + Vercel
- 8 項報表：用戶總覽、訂閱分佈、Token 成本、營收、利潤分析、AI 成功率、錯誤追蹤、用戶活躍度
- 權限控制：單一 Admin 角色 (Email Allowlist)
- 認證：Supabase Auth

**沙盒測試環境**:
- 雙軌策略：Firebase App Distribution (快速迭代) + TestFlight/Internal Testing (上架前)
- 環境配置：dev / staging / prod
- 測試帳號管理：排除測試帳號的報表 View
- CI/CD：GitHub Actions 自動 build + 分發

**總任務數更新**: 28 → 35 tasks

## Notes

- **新 Session**: 讀此文件 (`CLAUDE.md`) 即可了解專案全貌
- **開始實作**: 讀 `docs/plans/2026-02-26-vibesync-implementation.md`
- **設計細節**: 讀 `docs/plans/2026-02-26-vibesync-design.md`

---

## Claude 自動行為規則

### 必須自動執行
| 觸發條件 | 自動行為 |
|----------|----------|
| **commit 完成** | 立即 `git push` |
| **遇到 bug** | 記錄到 Bugs & Fixes 區塊 |
| **修復 bug** | 更新 Common Pitfalls |
| **學到新 pattern** | 更新 Design Decisions |
| **更新此文件** | commit + push |

### 不需要用戶提醒
- Git push
- Bug 記錄
- 測試撰寫
- 文件更新

### Bugs & Fixes 區塊位置
在下方 Lessons Learned 區塊內

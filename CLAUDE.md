# VibeSync Project

> **新 Session 入口文件** - Claude 開始時自動讀取此檔案

## Quick Start (新 Session 必讀)

```
📌 專案狀態：MVP 沙盒測試中
📌 定價模式：訊息制 (2 付費方案)
📌 測試網址：https://web-beta-tawny.vercel.app
📌 測試帳號：vibesync.test@gmail.com / test123456 (Essential tier, 不扣額度)
📌 最後更新：2026-03-14 (RevenueCat 整合完成 ✅)
```

### ✅ RevenueCat 整合狀態 (2026-03-14)

> **目前狀態**: 整合完成，購買測試成功！

#### RevenueCat 設定 (已完成 ✅)
| 項目 | 狀態 | 值 |
|------|------|-----|
| RevenueCat Project | ✅ | VibeSync (`projd482586c`) |
| iOS App 連接 | ✅ | `app73a7f8a72d` |
| Bundle ID | ✅ | `com.poyutsai.vibesync` |
| iOS Public API Key | ✅ | `appl_ZYVwxdvbEIAHxYUEHhdVkVLrkdY` |
| In-App Purchase Key | ✅ | `SF836SBCKL` (P8 key uploaded) |
| App Store Connect API Key | ✅ | 另一個 App Manager 權限的 Key |
| Issuer ID | ✅ | `35ed1ede-ef4b-4b24-9dd1-47d777cb032b` |
| Vendor Number | ✅ | `94060817` |
| Offerings (default) | ✅ | Current, 2 packages |
| Products | ✅ | Ready to Submit |

#### App Store Connect 產品 (已完成 ✅)
| 產品 | Product ID | 價格 | 狀態 |
|------|-----------|------|------|
| Starter Monthly | `vibesync_starter_monthly` | NT$149/月 | Ready to Submit |
| Essential Monthly | `vibesync_essential_monthly` | $29 USD/月 | Ready to Submit |

#### Sandbox Tester
- 已建立 Sandbox Tester 帳號 ✅
- 銀行/稅務設定已通過 ✅

#### 驗證結果 ✅
- [x] 確認 RevenueCat 初始化狀態 → ✅ RC Configured
- [x] 確認 Offerings/Packages 載入情況 → ✅ 2 packages 正確載入
- [x] 購買流程是否正常 → ✅ TestFlight Sandbox 購買成功
- [x] Webhook 是否正常觸發 → ✅ Supabase tier 已更新為 essential
- [x] Entitlements 設定 → ✅ premium entitlement 已建立並關聯產品

#### Webhook 設定 (已完成 ✅)
| 項目 | 狀態 |
|------|------|
| Edge Function | ✅ `revenuecat-webhook` 已部署 |
| Webhook URL | ✅ 已在 RevenueCat 設定 |
| Entitlements | ✅ `premium` 已建立並關聯 Starter/Essential |
| Supabase tier 同步 | ✅ 購買後自動更新為 essential |

#### 除錯記錄 (2026-03-14)

**問題**: App 顯示「無法取得產品資訊」

**除錯過程**:
1. ❌ Products 顯示 "Could not check" → 銀行審核已通過但還是出現
2. ❌ 檢查 Offerings → 已設為 Current ✅
3. ❌ 檢查 App Store Connect 產品 → Ready to Submit ✅
4. ✅ **找到問題 1**: RevenueCat 的 "App Store Connect API" 區塊沒有上傳 P8 key
5. ✅ 上傳 P8 key 後出現權限錯誤 → 需要 App Manager 權限的 Key
6. ✅ **解決**: 在 App Store Connect 建立新的 API Key (App Manager 權限)，上傳到 RevenueCat
7. ✅ Products 狀態變成 "Ready to Submit" (不再是 Could not check)
8. ❌ App 還是顯示「無法取得產品資訊」
9. ✅ **找到問題 2**: Packages 內有多餘的 RevenueCat 測試產品 (Monthly, Yearly, Lifetime)
10. ✅ 移除無效產品，只保留 App Store 產品
11. ❌ 重新安裝 app 後還是無法取得
12. 🔄 加入 debug info 到 Paywall
13. ✅ Debug info 顯示: `CONFIGURATION_ERROR - None of the products could be fetched from App Store Connect`
14. ✅ **找到問題 3**: 訂閱產品沒有關聯到 App 版本
15. ✅ 在 App Store Connect 的 "1.0 Prepare for Submission" 版本中加入訂閱
16. 🔄 **等待 Apple 同步** - 產品剛建立 (Mar 13) + 剛關聯版本，需等幾小時

**測試結果** (2026-03-14):
1. ✅ Apple 同步完成
2. ✅ Packages 正確載入 (Starter + Essential)
3. ✅ TestFlight Sandbox 購買成功
4. ✅ RevenueCat Dashboard 顯示 New Customer

**Debug 程式碼已移除** (原 commit b08cc10)

**重要發現**:
- RevenueCat 有兩個 P8 key 區塊，兩個都要設定：
  1. **In-app purchase key configuration** - 用於訂閱驗證
  2. **App Store Connect API** - 用於產品同步 (需要 App Manager 權限)
- 原本的 `SubscriptionKey_xxx.p8` 是 In-App Purchase 專用，權限不夠
- 需要另外建立 App Store Connect API Key
- Packages 不能包含無效的 RevenueCat 測試產品，會導致載入失敗

---

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
| **System Prompt 優化** | ✅ 完成 | 70/30 法則、英文話題深度 (Topic Depth Ladder) |
| **個人化資料收集** | ✅ 完成 | 用戶風格、興趣、對方特質（選填） |
| **反饋機制** | ✅ 完成 | 👍👎 按鈕 + Telegram 通知 |
| **submit-feedback Function** | ✅ 部署 | 反饋存 Supabase + TG 通知 |
| **刪除對話功能** | ✅ 完成 | 對話列表顯示刪除按鈕 + 確認對話框 |
| **多條訊息處理** | ✅ 完成 | 根據訊息類型(肯定句/陳述句/疑問句/圖片)決定是否回覆 |
| **優化我的訊息** | ✅ 完成 | 用戶輸入草稿，AI 依據 1.8x 法則+風格優化 |
| **CI/CD iOS** | ✅ 完成 | 手動觸發 → TestFlight 自動上傳 |
| **UI 重構 Phase 1** | ✅ 完成 | 新增對話頁：粉紫漸層背景、毛玻璃元件、漸層按鈕 |
| **UI 重構 Phase 1 微調** | ✅ 完成 | 半透明白、酒紅色 hint、移除提示框背景 |
| **UI 重構 Phase 2** | ✅ 完成 | 首頁、登入頁、設定頁、Paywall、分析結果頁：全套 Warm Theme |
| **UI 重構 Phase 3** | ✅ 完成 | 動態光球：18% 呼吸縮放 + 6-8 秒週期 + 多方向浮動 |
| **截圖上傳功能** | ✅ 完成 | Claude Vision 識別對話、最多 3 張、自動壓縮 |
| **截圖識別存入對話** | ✅ 完成 | 識別結果自動轉成 Message 存入對話歷史 |
| **首頁新增選單** | ✅ 完成 | 點「+」顯示選單：手動輸入 / 截圖開始 |
| **截圖識別與分析分離** | ✅ 完成 | 先識別存入對話、再分析；截圖和手動輸入可交錯使用 |
| **截圖識別自動抓名字** | ✅ 完成 | AI 從截圖標題抓對方名字、確認對話框、情境設定 |
| **測試帳號 Tier 修復** | ✅ 完成 | 測試帳號強制使用 essential tier 功能 |
| **付費用戶 UX 優化** | ✅ 完成 | 只有延展回覆時，付費用戶顯示「AI 判斷最適合」而非升級提示 |
| **純識別模式** | ✅ 完成 | 截圖識別用精簡 prompt、不扣額度、120秒 timeout |
| **分析後繼續對話** | ✅ 完成 | 分析結果後可展開「繼續對話」區塊 |
| **對話長度提示** | ✅ 完成 | 顯示「建議每張截圖小於 15 則訊息」提示 |
| **截圖 UX 流程優化** | ✅ 完成 | 有截圖時隱藏分析按鈕、錯誤提示優化 |
| **確認對話框訊息預覽** | ✅ 完成 | 顯示前 5 則識別訊息，避免傳錯截圖 |
| **繁體中文名字識別優化** | ✅ 完成 | prompt 強調繁體中文、不確定返回 null |
| **RevenueCat 整合** | ✅ 完成 | iOS 訂閱購買、Sandbox 測試通過 |
| **RevenueCat Webhook** | ✅ 完成 | 購買事件自動同步 Supabase tier |
| **RevenueCat Entitlements** | ✅ 完成 | premium entitlement 關聯 Starter/Essential |
| **截圖 HEIC 格式支援** | ✅ 完成 | iOS 截圖預設格式支援 |
| **截圖左右方向識別** | ✅ 完成 | 明確判斷我(右)/她(左) |

#### 🔄 待測試驗證
- [x] **UI 重構 Phase 1 視覺測試** (新增對話頁毛玻璃效果、漸層背景) ✅
- [x] **UI 重構 Phase 2 視覺測試** (首頁、登入、設定、分析結果頁) ✅
- [x] **UI 重構 Phase 3 視覺測試** (動態光球效果流暢度) ✅
- [ ] iOS Safari 滑動體驗 (pull-to-refresh 是否完全修復)
- [ ] Android Chrome 滑動體驗
- [ ] 個人化資料對 AI 回覆品質的影響
- [ ] 反饋機制端對端測試 (👎 → Telegram 通知)
- [ ] **截圖上傳功能測試** - UI 上傳、Edge Function 識別、分析結果顯示

#### ✅ 里程碑
- **2026-03-11**: 前端 UI 重構完成 (Phase 1-3)，Warm Theme 全面套用
- **2026-03-12**: 截圖上傳功能實作完成 (Flutter + Edge Function)
- **2026-03-12**: 截圖識別 UX 優化 (識別與分析分離、自動抓名字、確認對話框)
- **2026-03-12**: 純識別模式 + 分析後繼續對話 + 對話長度提示
- **2026-03-12**: 截圖 UX 完善（流程優化、確認預覽、繁體中文識別）
- **2026-03-14**: RevenueCat 整合完成，iOS Sandbox 購買測試成功 🎉
- **2026-03-14**: Webhook + Entitlements 設定完成，Supabase tier 自動同步 ✅
- **2026-03-14**: 截圖功能修復 (HEIC 格式 + 左右方向識別)

#### 📝 規劃完成待實作
| 功能 | 設計文件 | 實作計畫 | 狀態 |
|------|---------|---------|------|
| **訂閱付款 Phase 1** | `docs/superpowers/specs/2026-03-12-subscription-payment-design.md` | `docs/superpowers/plans/2026-03-12-subscription-payment-impl.md` | ✅ 完成 |

**Phase 1 完成內容：** RevenueCat 整合 + iOS 月訂閱 (Starter/Essential) + Sandbox 購買測試

#### ⏸️ 暫停中
- [ ] 年訂閱 / 季度訂閱 / Weekly 訂閱（待研究後決定）
- [ ] 試用期（Free 30則/月 已足夠體驗）
- [ ] Admin Dashboard

#### 📝 訂閱方案備註
> **目前方案**：Starter ($4.99/月) + Essential ($29.99/月)
> **未來可能調整**：Weekly / 季度訂閱等，待與夥伴研究後決定
> **暫時不動**，等 PMF 驗證後再調整

#### ⚠️ 上線前待決定
- [ ] **截圖功能計費方案** - 選項：A) 1截圖=N訊息 B) 獨立額度 C) 僅付費可用
- [ ] **定價最終 Review** - 根據所有功能成本重新審視定價
- [ ] **Free 用戶模型選擇** - Haiku 或 Sonnet

#### 📋 下一步（重要）
1. ~~訂閱付款功能 Phase 1~~ ✅ 完成
2. ~~截圖上傳功能~~ ✅ 完成
3. **🔴 登入/註冊系統** ← 當前優先
4. 上架準備（App Store 審核）
5. AI 回覆品質優化

#### 🧪 夥伴測試購買說明
> TestFlight App 的購買會自動走 Sandbox 環境，**不會真的扣款**。
> 夥伴直接用自己的 Apple ID 購買即可，不需要特別設定 Sandbox 帳號。

### 沙盒測試環境 (2026-02-28 上線)
- **Supabase Project**: `fcmwrmwdoqiqdnbisdpg`
- **Edge Functions**:
  - `analyze-chat` - AI 分析引擎
  - `submit-feedback` - 反饋收集 + Telegram 通知
  - `revenuecat-webhook` - 訂閱事件同步 Supabase tier
- **Claude Model**: `claude-sonnet-4-20250514` (Essential) / `claude-haiku-4-5-20251001` (Free/Starter)
- **Vercel**: https://web-beta-tawny.vercel.app
- **成本優化**: Prompt Caching 已啟用 (ephemeral cache)
- **Telegram Bot**: `@vibesync_feedback_bot` (反饋通知)

### 測試帳號
| Email | 密碼 | Tier | 特性 |
|-------|------|------|------|
| `vibesync.test@gmail.com` | `test123456` | Essential | **不扣額度**，完整功能 |

### CI/CD 狀態
| 平台 | 狀態 | 觸發條件 | 備註 |
|------|------|----------|------|
| **Web** | ✅ 自動部署 | push main | Vercel |
| **Edge Function** | ✅ 自動部署 | push main (supabase/functions/**) | Supabase |
| **Android** | ✅ 成功 | 手動觸發 | APK 可下載 |
| **iOS** | ✅ 成功 | 手動觸發 | TestFlight 自動上傳 |

### Apple Developer 設定 (2026-03-06 完成)
- **App ID**: `com.poyutsai.vibesync`
- **Team ID**: `TTQHTVG8CC`
- **TestFlight**: 已上傳第一個 build
- **GitHub Secrets 已設定**:
  - `APPLE_CERTIFICATE` - Distribution 憑證 (base64)
  - `APPLE_CERTIFICATE_PASSWORD` - 憑證密碼
  - `APPLE_PROVISIONING_PROFILE` - App Store profile (base64)
  - `APP_STORE_CONNECT_KEY_ID` - API Key ID
  - `APP_STORE_CONNECT_ISSUER_ID` - Issuer ID
  - `APP_STORE_CONNECT_API_KEY` - API Key 內容

### 關鍵文件指引
| 要了解什麼 | 讀哪個文件 |
|------------|-----------|
| **完整設計規格 (v1.3)** | `docs/plans/2026-02-26-vibesync-design.md` |
| **實作計畫 (35 任務)** | `docs/plans/2026-02-26-vibesync-implementation.md` |
| **System Prompt 優化設計** | `docs/plans/2026-03-04-system-prompt-optimization-design.md` |
| **System Prompt 優化實作** | `docs/plans/2026-03-04-system-prompt-optimization-impl.md` |
| **UI 重構設計規格** | `docs/plans/2026-03-10-ui-redesign-design.md` |
| **UI 重構實作計畫 (15 任務)** | `docs/plans/2026-03-10-ui-redesign-impl.md` |
| **截圖上傳設計規格** | `docs/plans/2026-03-12-screenshot-upload-design.md` |
| **截圖上傳實作計畫 (12 任務)** | `docs/plans/2026-03-12-screenshot-upload-impl.md` |
| **訂閱付款設計規格** | `docs/superpowers/specs/2026-03-12-subscription-payment-design.md` |
| **訂閱付款實作計畫 (11 任務)** | `docs/superpowers/plans/2026-03-12-subscription-payment-impl.md` |
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
- [ ] Edge Function 變數重複宣告 → 新增變數前先搜尋 `const/let variableName`
- [ ] Flutter Web 使用 dart:io → Web 不支援，用字串檢查代替
- [ ] 錯誤訊息顯示 minified → 開發時顯示完整錯誤，上線再簡化
- [ ] iOS CI 用 profile 名稱簽名 → 永遠用 UUID，名稱匹配會失敗
- [ ] Xcode project 設 PROVISIONING_PROFILE_SPECIFIER → CI 環境改用 PROVISIONING_PROFILE (UUID)
- [ ] App.framework 缺少 MinimumOSVersion → 編輯 `ios/Flutter/AppFrameworkInfo.plist` 加入該欄位
- [ ] Fastfile 路徑錯誤 → 用 `File.expand_path("../../..", __FILE__)` 取得專案根目錄
- [ ] xcodebuild 將 profile 套用到所有 target → 用 `flutter build ipa` 而非手動 `xcodebuild archive`
- [ ] TestFlight 重複 build number → 用 `--build-number=${{ github.run_number }}` 自動遞增
- [ ] Fastlane Slack 通知失敗導致 workflow 失敗 → 用 `begin/rescue` 包住，設為 non-fatal
- [ ] TestFlight Export Compliance 每次都要手動填 → 在 Info.plist 加入 `ITSAppUsesNonExemptEncryption = false`

---

## iOS CI/CD 完整指南 (2026-03-06)

> **重要**: 這是從零到成功上傳 TestFlight 的完整經驗，未來新專案可直接參考

### 必要的 GitHub Secrets
| Secret 名稱 | 內容 | 取得方式 |
|------------|------|----------|
| `APPLE_CERTIFICATE` | Distribution 憑證 (base64) | Keychain 匯出 .p12 → `base64 -w 0 cert.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | 憑證密碼 | 匯出時設定的密碼 |
| `APPLE_PROVISIONING_PROFILE` | App Store profile (base64) | Apple Developer 下載 → `base64 -w 0 profile.mobileprovision` |
| `APP_STORE_CONNECT_KEY_ID` | API Key ID | App Store Connect → Keys |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID | App Store Connect → Keys |
| `APP_STORE_CONNECT_API_KEY` | API Key 內容 (.p8 檔案內容) | 下載的 .p8 檔案內容 |

### 關鍵檔案設定

**ios/Flutter/AppFrameworkInfo.plist** - 必須加入：
```xml
<key>MinimumOSVersion</key>
<string>13.0</string>
```

**ios/Runner/Info.plist** - 必須加入：
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

**ios/Podfile** - 必須設定 iOS 版本：
```ruby
platform :ios, '13.0'

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
```

**ios/fastlane/Fastfile** - 重點：
```ruby
# 用絕對路徑找 IPA
project_root = File.expand_path("../../..", __FILE__)
ipa_dir = File.join(project_root, "build", "ios", "ipa")

# Slack 通知用 begin/rescue 包住 (non-fatal)
begin
  slack(...)
rescue => e
  UI.important("Slack failed (non-fatal): #{e.message}")
end
```

### workflow 重點
```yaml
# 自動遞增 build number
flutter build ipa --release --build-number=${{ github.run_number }}

# 動態產生 ExportOptions.plist 使用 UUID
PROFILE_UUID=$(security cms -D -i $PROFILE_PATH | /usr/libexec/PlistBuddy -c "Print :UUID" /dev/stdin)
```

### 常見錯誤對照表
| 錯誤訊息 | 原因 | 解決 |
|---------|------|------|
| `No profile matching 'xxx' found` | 用名稱匹配 profile | 改用 UUID |
| `MinimumOSVersion is ''` | AppFrameworkInfo.plist 缺少欄位 | 加入 MinimumOSVersion |
| `bundle version must be higher` | build number 重複 | 用 github.run_number |
| `Pods does not support provisioning profiles` | xcodebuild 套用 profile 到所有 target | 用 flutter build ipa |
| `Missing Compliance` | 沒設定 Export Compliance | 加 ITSAppUsesNonExemptEncryption |

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

#### [2026-03-06] Edge Function 變數重複宣告導致 Boot Failure
**症狀**: 點擊分析後顯示 "Failed to fetch"，Edge Function 完全無法啟動
**Root Cause**: `actualModel` 變數在同一 scope 宣告兩次 (line 717 和 762)
**修復**: 第一個 `actualModel` 改名為 `selectedModel`
**預防**: 新增變數前先搜尋是否已存在同名變數
**相關檔案**: `supabase/functions/analyze-chat/index.ts:717`

#### [2026-03-06] 分析失敗錯誤訊息太籠統
**症狀**: 所有錯誤都顯示 "Network error" 或 minified 錯誤碼
**修復**:
1. 移除 `dart:io` (Web 不支援)
2. 顯示完整錯誤類型和訊息以便除錯
3. 新增自動重試機制 (最多 2 次)
4. 新增 60 秒 timeout
**相關檔案**:
- `lib/features/analysis/data/services/analysis_service.dart`
- `lib/core/services/supabase_service.dart`

#### [2026-03-06] GitHub Actions iOS Code Signing 失敗
**症狀**: "No profile for team 'TTQHTVG8CC' matching 'VibeSync App Store' found"
**Root Cause**:
1. `PROVISIONING_PROFILE_SPECIFIER` 使用 profile **名稱**匹配
2. 但 Xcode 在 CI 環境安裝 profile 時是用 **UUID** 作為檔名
3. 名稱匹配找不到已安裝的 profile
**修復**:
1. 分離 `flutter build ios --no-codesign` 和 `xcodebuild archive`
2. 用 `PROVISIONING_PROFILE=UUID` 直接指定 (而非名稱)
3. 從 profile 內容提取 UUID: `security cms -D -i profile.mobileprovision | PlistBuddy -c "Print :UUID"`
4. 動態產生 ExportOptions.plist 使用 UUID
**預防**:
- iOS CI 簽名永遠用 UUID，不要用名稱
- 加入充分的除錯輸出 (證書列表、profile UUID/Name/TeamID)
**相關檔案**:
- `.github/workflows/release.yml`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/ExportOptions.plist`

#### [2026-03-06] App Store 拒絕上傳：MinimumOSVersion 缺失
**症狀**: `Invalid MinimumOSVersion. MinimumOSVersion in 'Runner.app/Frameworks/App.framework' is ''`
**Root Cause**:
1. `App.framework` 是 Flutter 編譯 Dart 程式碼產生的 framework
2. 它的 Info.plist 從 `ios/Flutter/AppFrameworkInfo.plist` 模板複製
3. Flutter 預設模板缺少 `MinimumOSVersion` 欄位
**修復**:
編輯 `ios/Flutter/AppFrameworkInfo.plist`，加入：
```xml
<key>MinimumOSVersion</key>
<string>13.0</string>
```
**預防**: Flutter 專案需檢查 AppFrameworkInfo.plist 是否有 MinimumOSVersion
**相關檔案**: `ios/Flutter/AppFrameworkInfo.plist`

#### [2026-03-06] Fastfile 找不到 IPA 檔案
**症狀**: `No IPA found in ../build/ios/ipa`
**Root Cause**:
1. Fastfile 使用相對路徑 `../build/ios/ipa`
2. 但 Fastlane 的工作目錄不固定，相對路徑不可靠
**修復**:
```ruby
project_root = File.expand_path("../../..", __FILE__)
ipa_dir = File.join(project_root, "build", "ios", "ipa")
```
**預防**: Fastfile 永遠用 `__FILE__` 計算絕對路徑
**相關檔案**: `ios/fastlane/Fastfile`

#### [2026-03-06] TestFlight 拒絕重複 build number
**症狀**: `The bundle version must be higher than the previously uploaded version: '1'`
**Root Cause**: 每次上傳 TestFlight 的 build number 必須遞增，但 Flutter 預設使用 pubspec.yaml 的版本
**修復**:
```yaml
flutter build ipa --release --build-number=${{ github.run_number }}
```
**預防**: CI 永遠用 `github.run_number` 作為 build number
**相關檔案**: `.github/workflows/release.yml`

#### [2026-03-06] Slack 通知失敗導致整個 workflow 失敗
**症狀**: TestFlight 上傳成功，但 workflow 顯示失敗
**Root Cause**: Slack webhook URL 無效時 Fastlane 會拋出錯誤，中斷整個 lane
**修復**:
```ruby
begin
  slack(...)
rescue => e
  UI.important("Slack failed (non-fatal): #{e.message}")
end
```
**預防**: 選用性通知永遠用 begin/rescue 包住
**相關檔案**: `ios/fastlane/Fastfile`

#### [2026-03-12] 測試帳號功能被限制為 Free tier
**症狀**: 測試帳號看到「升級解鎖共鳴、調情...」提示，只有延展回覆
**Root Cause**: Edge Function 從資料庫讀取 tier，但資料庫可能設定錯誤
**修復**: 測試帳號強制使用 essential tier 功能
```javascript
const effectiveTier = isTestAccount ? "essential" : sub.tier;
```
**相關檔案**: `supabase/functions/analyze-chat/index.ts:750`

#### [2026-03-12] 付費用戶看到升級提示
**症狀**: 付費用戶在某些情境只收到延展回覆，卻看到「升級解鎖」提示
**Root Cause**: UI 判斷邏輯是「只有 extend 就顯示升級提示」，沒考慮用戶 tier
**修復**: 根據用戶 tier 顯示不同提示
- Free 用戶：「升級解鎖共鳴、調情、幽默、冷讀等回覆風格」
- 付費用戶：「AI 判斷此情境最適合使用延展回覆」
**相關檔案**: `lib/features/analysis/presentation/screens/analysis_screen.dart:1515-1565`

#### [2026-03-12] warnings 欄位型別轉換錯誤
**症狀**: 解析回應失敗
**Root Cause**: `warnings` 可能是 String 或 Object 陣列，直接 cast 會失敗
**修復**: 安全轉換為 String 再處理
```dart
final rawWarnings = json['warnings'] as List? ?? [];
final warnings = rawWarnings.map((w) => w is String ? w : w.toString()).toList();
```
**相關檔案**: `lib/features/analysis/domain/entities/analysis_models.dart:362`

#### [2026-03-14] RevenueCat 無法取得產品資訊
**症狀**: App 顯示「無法取得產品資訊」，RevenueCat Products 顯示 "Could not check"
**重現步驟**:
1. 打開 iOS app
2. 進入 Paywall 頁面
3. 產品資訊無法載入

**Root Cause**: RevenueCat 有兩個 P8 key 設定區塊，只設定了一個：
1. **In-app purchase key configuration** - 已設定 ✅
2. **App Store Connect API** - 沒設定 ❌

且 App Store Connect API 需要的是 **App Manager 權限**的 Key，原本的 Subscription Key 權限不夠。

**修復**:
1. 在 App Store Connect → Users and Access → Integrations → **App Store Connect API** 建立新 Key
2. 權限選擇 **App Manager**
3. 下載 P8 檔案，命名為 `AuthKey_XXXXXX.p8` 格式
4. 上傳到 RevenueCat 的 "App Store Connect API" 區塊
5. 填入 Key ID、Issuer ID、Vendor Number

**預防**:
- RevenueCat 設定時，兩個 P8 key 區塊都要設定
- In-App Purchase Key 和 App Store Connect API Key 是不同的 Key
- App Store Connect API Key 必須有 App Manager 權限

**相關設定**:
- RevenueCat Project: `projd482586c`
- iOS API Key: `appl_ZYVwxdvbEIAHxYUEHhdVkVLrkdY`
- Bundle ID: `com.poyutsai.vibesync`
- Issuer ID: `35ed1ede-ef4b-4b24-9dd1-47d777cb032b`
- Vendor Number: `94060817`

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
- Essential: $29 USD / 1,000則/月 / 150則/天

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
- 話題深度階梯 (Event→Personal→Intimate)
- 對話健檢 (Essential 專屬)
- 70/30 法則 (聆聽 vs 說話)
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

#### [2026-03-04] System Prompt 優化 + 個人化 + 反饋機制
**決定**: 根據測試夥伴反饋進行三項優化
**變更內容**:
1. **名詞修改** (規避著作權)
   - 82/18 原則 → 70/30 法則
   - 話題深度階梯改英文 (Event-oriented / Personal-oriented / Intimate-oriented)
2. **個人化資料收集**
   - 用戶風格 (幽默/穩重/直球/溫柔/調皮)
   - 用戶興趣 (自由填寫)
   - 對方特質 (選填)
   - AI 會根據這些資料調整回覆風格
3. **反饋機制**
   - 分析結果頁底部 👍👎 按鈕
   - 負面反饋展開表單 (分類 + 補充說明)
   - 反饋存入 Supabase `feedback` 表
   - 負面反饋自動發送 Telegram 通知

**相關文件**:
- 設計: `docs/plans/2026-03-04-system-prompt-optimization-design.md`
- 實作: `docs/plans/2026-03-04-system-prompt-optimization-impl.md`

#### [2026-03-11] UI 重構 - 溫暖粉紫漸層毛玻璃風格
**決定**: 將 VibeSync 從暗黑主題改為溫暖粉紫漸層 + 毛玻璃風格
**目標**: 創造 Gen Z 友善、約會 app 氛圍的視覺體驗

**設計決策**:
| 項目 | 決定 |
|------|------|
| 背景風格 | B1 靜態光球（最終目標 B2 動態） |
| 毛玻璃範圍 | 僅互動元件（輸入框、選項按鈕） |
| 發光效果 | BoxShadow 實作 |
| CTA 按鈕 | 珊瑚漸層，全 app 統一 |
| 頭像風格 | 漸層泡泡 |
| 實作方案 | 修改現有 Theme 系統 |
| 重構範圍 | 分階段，Phase 1 先做「新增對話」頁 |
| 平台策略 | Web 優先，iOS 自動同步 |

**Phase 1 完成內容** (15 Tasks):
- AppColors 新增 Warm Theme 色系
- 6 個共用元件：GradientBackground、GlassmorphicContainer、GradientButton、BubbleAvatar、GlassmorphicSegmentedButton、GlassmorphicTextField
- NewConversationScreen 完整重構

**Phase 2 完成內容** (2026-03-11):
- HomeScreen: GradientBackground + 對話卡片 GlassmorphicContainer
- LoginScreen: GradientBackground + 毛玻璃輸入框 + GradientButton
- SettingsScreen: GradientBackground + 區塊 GlassmorphicContainer
- AnalysisScreen: GradientBackground + 所有容器更新為 Warm Theme 配色

**Phase 3 完成內容** (2026-03-11):
- 動態光球效果 (B2)
- 緩慢浮動動畫 (8-12秒週期，不同方向)
- 呼吸效果 (大小漸變 10-15%)
- AnimationController + Transform 實作

**相關文件**:
- 設計: `docs/plans/2026-03-10-ui-redesign-design.md`
- 實作: `docs/plans/2026-03-10-ui-redesign-impl.md`

**新增檔案**:
- `lib/shared/widgets/gradient_background.dart`
- `lib/shared/widgets/glassmorphic_container.dart`
- `lib/shared/widgets/gradient_button.dart`
- `lib/shared/widgets/bubble_avatar.dart`
- `lib/shared/widgets/glassmorphic_segmented_button.dart`
- `lib/shared/widgets/glassmorphic_text_field.dart`
- `lib/shared/widgets/warm_theme_widgets.dart` (統一匯出)

#### [2026-03-12] 截圖上傳功能 - Claude Vision
**決定**: 新增截圖上傳功能，使用 Claude Vision API 識別對話內容
**目標**: 讓用戶可以直接上傳聊天截圖，AI 自動識別對話並分析

**設計決策**:
| 項目 | 決定 |
|------|------|
| 功能定位 | 補充手動輸入（非取代） |
| 最大圖片數 | 3 張/次分析 |
| 圖片+文字 | 一起分析（截圖為較早對話） |
| 進入點 | 對話列表上方獨立按鈕 |
| 上傳後 | 直接分析 |
| 壓縮策略 | 自動壓縮（~1024px、85% quality） |
| AI 模型 | 有圖片時強制 Sonnet |
| 來源 | 相簿 + 剪貼簿（Web） |
| 順序 | 上傳順序 + 提示用戶 |
| 失敗處理 | 顯示錯誤，不扣額度 |
| 儲存 | 用完即丟（不存檔） |
| 傳輸方式 | Base64 直傳（方案 A） |

**技術架構**:
- 前端: ImagePickerWidget + ImageCompressService
- 後端: Edge Function buildVisionContent + 識別指示
- API: Claude Vision (Sonnet)

**新增檔案**:
- `lib/shared/services/image_compress_service.dart`
- `lib/shared/widgets/image_picker_widget.dart`

**相關文件**:
- 設計: `docs/plans/2026-03-12-screenshot-upload-design.md`
- 實作: `docs/plans/2026-03-12-screenshot-upload-impl.md`

**待決定**: 計費方案（上線前決定）

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

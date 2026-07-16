# VibeSync 頻率調校師

社交溝通技巧教練 App — 幫助用戶提升對話品質與人際互動能力，最終目標：成功邀約。

## 功能特色

- **熱度分析** — 即時評估對話互動程度 (0-100)
- **對話進度五階段** — 破冰 → 升溫 → 深入 → 連結 → 邀約
- **五種回覆風格** — 延展 / 共鳴 / 調情 / 幽默 / 冷讀
- **截圖上傳** — Claude Vision 自動識別聊天截圖（最多 3 張）
- **開場救星** — 無聊天記錄也能產開場白（基本 3 則 + 每張截圖 +2 則）
- **Coach 1:1** — 針對目前對話追問情境、回覆與下一步
- **AI 鍵盤** — iOS 鍵盤內產生五種快速回覆（目前為 TestFlight 發布候選）
- **學習專區** — 20 篇繁中翻譯文章 + 實戰練習入口
- **我的報告** — 5 維雷達圖 + 健康分數卡 + 歷史趨勢（付費限定）
- **1.8x 黃金法則** — 維持健康對話節奏
- **隱私優先** — 對話預設存本地，分析時才傳送必要內容

## 三大 Tab

| Tab | 內容 |
|-----|------|
| 首頁 | 對話列表 / 手動輸入 / 截圖上傳 / 開場救星入口 |
| 我的報告 | 雷達圖 + 健康分數 + 歷史趨勢（Starter/Essential）|
| 學習專區 | 20 篇文章 + 實戰練習 |

## 技術架構

| 層級 | 技術 |
|------|------|
| Frontend | Flutter 3.x + Riverpod + fl_chart |
| Backend | Supabase（Auth / Postgres / Edge Functions） |
| AI | Claude API（Haiku + Sonnet；環境變數 `CLAUDE_API_KEY`） |
| Payment | RevenueCat（4 產品：Starter/Essential × 月繳/季繳） |
| Local DB | Hive（AES-256 加密） |

## 訂閱方案

| Tier | 月繳 | 月訊息 | 每日上限 | AI 模型 |
|------|------|--------|----------|---------|
| Free | NT$0 | 30 | 15 | 分析 Sonnet 5；其他 Free 端點多為 Haiku |
| Starter | NT$590 | 300 | 50 | 分析 Sonnet 4.6 |
| Essential | NT$1,290 | 800 | 120 | 分析 Sonnet 4.6 |

詳細見 [docs/pricing-final.md](docs/pricing-final.md)。

## 開發環境設置

```bash
flutter pub get     # 安裝依賴
flutter run         # 執行開發版本
flutter test --concurrency=1  # 跑完整測試（避免共享 Hive/Supabase 狀態互撞）
```

## 專案結構

```
lib/features/       # 功能模組（Clean Architecture: data / domain / presentation）
├── auth/           conversation/   analysis/
├── opener/         learning/       report/
├── subscription/   onboarding/     splash/
lib/core/           # 共用核心
lib/shared/         # 共用 UI 元件 + services
```

## 關鍵文件

| 要找什麼 | 去哪 |
|---------|------|
| Agent 入口 | [CLAUDE.md](CLAUDE.md) / [AGENTS.md](AGENTS.md) |
| 共享 Agent 規則 | [docs/shared-agent-rules.md](docs/shared-agent-rules.md) |
| 當前階段狀態 | [docs/snapshot.md](docs/snapshot.md)（每月刷新） |
| 架構決策記錄 | [docs/decisions.md](docs/decisions.md) |
| Bug 歷史 | [docs/bug-log.md](docs/bug-log.md) |
| 整合配置 | [docs/integrations/](docs/integrations/) |
| 定價方案 | [docs/pricing-final.md](docs/pricing-final.md) |
| Active plans | [docs/plans/README.md](docs/plans/README.md) |
| 歷史設計規格 | [docs/archive/plans/2026-02-26-vibesync-design.md](docs/archive/plans/2026-02-26-vibesync-design.md) |

## 授權

Private - All Rights Reserved

## 變更記錄

Hotfix / rollback 記錄見 [`CHANGELOG.md`](./CHANGELOG.md)。

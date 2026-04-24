# VibeSync

> 聊天輔助 SaaS App — 幫用戶提升社交對話技巧，最終目標：成功邀約。
> 新 Session Claude 讀此檔；歷史細節見文末「📚 Docs 指路」。
>
> **本檔自律**：目標 ≤ 200 行、上限 250 行。超過請搬內容到 `docs/`。最後重審：2026-04-24。

---

## 🚫 本檔禁入（違反視同 code review 失敗）

| 禁止內容 | 正確去處 |
|---------|---------|
| Bug 修復記錄（`[YYYY-MM-DD] 症狀/修復` 這種格式） | `docs/bug-log.md` |
| 已完成功能清單 | `git log` 或 `docs/snapshot.md` |
| 架構決策（ADR） | `docs/decisions.md` |
| 第三方服務配置詳情（key / ID / webhook 設定步驟） | `docs/integrations/*.md` |
| 低頻使用的 CLI 指令（Flutter/Supabase local 指令） | `README.md` |
| 階段狀態、送審剩餘項 | `docs/snapshot.md`（每月 1 號重寫） |
| 與全域 `~/.claude/CLAUDE.md` 重複的規則（Superpowers 流程、Git 安全、模型選擇） | 刪除本地副本，靠全域注入 |

**保鮮期原則**：每條硬規則加「保鮮期到 YYYY-MM-DD」或「保留條件」。到期或條件消失即刪。

---

## 🚨 OCR 穩定基線（硬規則）

**保鮮期到**：2026-06-30（屆時若 `analyze-chat` 不再需要 `--no-verify-jwt`，整段可刪）

```
Current OCR-stable baseline: 28c0965
```

**絕對不能做**：
- OCR 變更不與 security / cache / parser / prompt / multi-agent 改動混 commit
- 不對 OCR 核心路徑跑 multi-agent 優化
- `analyze-chat` 部署**必須** `--no-verify-jwt`

**必知**：
- 2026-04-05 OCR 回歸根因是 Edge Function 切到 platform JWT verification。OCR deploy 後壞 → **先查 `.github/workflows/deploy-edge-function.yml`**，別先改 app code
- 三項 server fix 已套在 `28c0965` 上：`sync-subscription` 移除 RC key fallback、`revenuecat-webhook` 存 minimized payload、`delete-account/sync-subscription/submit-feedback` 維持 JWT 驗證

詳細：`docs/2026-04-05-ocr-rollback-note.md`

---

## 📌 當前階段

看 `docs/snapshot.md`（每月 1 號或重大階段變更時刷新）。

**一句話**：送審前最後穩定化，**不做大功能擴張**，持續收 OCR 邊界 + 開場救星品質。

---

## 🎯 Product Overview

**Target**：20-35 歲，願意投資自我提升的個人用戶
**哲學**：框架策略為輔 → 最終回歸「個人化 + 真誠流」

### 三大 Tab
- **首頁** — 對話列表 / 新增對話（手動 + 截圖）/ 開場救星入口 / 新用戶三步引導
- **我的報告** — 5 維雷達圖 + 健康分數卡 + 歷史趨勢（Starter/Essential 限定）
- **學習專區** — 20 篇繁中翻譯文章（4 分類）+ 實戰練習入口 → 開場救星

### 核心功能
- 熱度分析（0-100）+ 對話進度五階段（破冰/升溫/深入/連結/邀約）
- 五種回覆（延展 / 共鳴 / 調情 / 幽默 / 冷讀）
- 截圖上傳（Claude Vision，最多 3 張）
- 開場救星（計費：基本 3 則 + 每截圖 +2 則）
- 對方個人檔案卡（AI 自動提取興趣/特質/備註 + 趨勢）
- 對話記憶（15 輪完整 + 自動摘要）
- 繼續對話只收增量計費

### Core AI Rules
- **1.8x 黃金法則**：回覆字數 ≤ 對方字數 × 1.8（最高指導原則）
- **熱度策略**：0-30 鏡像冷處理 / 31-60 引導提問 / 61-80 80% 鏡像 / 81-100 推拉

---

## 🔧 Tech Stack & 關鍵配置

- **Frontend**: Flutter 3.x + Riverpod + fl_chart
- **Backend**: Supabase（Auth / Postgres / Edge Functions）
- **AI**: Claude API — 環境變數**必用** `CLAUDE_API_KEY`（不是 `ANTHROPIC_API_KEY`）
- **Subscription**: RevenueCat（4 產品：月繳 + 季繳 × Starter + Essential）
- **Local DB**: Hive（AES-256 加密）

### 模型配置（2026-04-22 起，詳見 ADR #11）
- **Free**: Haiku (`claude-haiku-4-5-20251001`)
- **Starter / Essential**: Sonnet (`claude-sonnet-4-20250514`)
- **有圖片時**: 強制 Sonnet（所有層）

### 關鍵資源
| 資源 | 值 |
|------|-----|
| Supabase Project | `fcmwrmwdoqiqdnbisdpg` |
| Edge Functions | `analyze-chat`（含 opener 模式）/ `submit-feedback` / `sync-subscription` / `revenuecat-webhook` / `delete-account` |
| Bundle ID | `com.poyutsai.vibesync` |
| Team ID | `TTQHTVG8CC` |
| 測試帳號 | `vibesync.test@gmail.com`（Essential，不扣額度）|
| Web Preview | https://web-beta-tawny.vercel.app |

### 訂閱方案（2026-04-22 起，詳見 ADR #10）
| Tier | 月繳 | 月訊息 | 日上限 |
|------|------|--------|--------|
| Free | NT$0 | 30 | 15 |
| Starter | NT$590 | 300 | 50 |
| Essential | NT$1,290 | 800 | 120 |

雷達圖限 Starter/Essential 可見（Free 隱藏）。

### CI/CD
| 平台 | 觸發 | 備註 |
|------|------|------|
| Web | push main | Vercel 自動 |
| Edge Function | push main (`supabase/functions/**`) | Supabase 自動 |
| iOS | 手動觸發 | → TestFlight |
| Android | 手動觸發 | APK |

---

## 📐 Development Conventions

### Code Style
- 檔名 snake_case；Class PascalCase
- 每個 feature 走 Clean Architecture（data / domain / presentation）
- Flutter 官方 linting

### Git
- 繁體中文 commit；格式 `[類型] 簡短描述`（feat / fix / refactor / docs / test / chore）
- 一個 commit 一件事
- Commit 後**立即** push（無例外）
- （全域已有 Git 安全規則，此處不重複）

### Privacy First
- 對話內容預設只存本地
- 分析 / OCR / 開場救星只傳必要內容；後端不長期保存完整對話
- 診斷資料只留最小必要資訊
- 本地資料 AES-256

---

## ⚠️ Common Pitfalls（現役，真的會再踩）

保鮮期原則：若某條 Pitfall 連續 3 個月沒再踩 + 已在 code 層面防呆，就刪掉。

- Hive 未初始化就存取 → 確保 `StorageService.initialize()` 完成
- Riverpod provider 未 dispose → 用 `autoDispose`
- 外部 API 未 try-catch → **永遠**包 try-catch
- Flutter Web 用 `dart:io` → 不支援，改字串檢查
- Web 平台 secure storage 受限 → MVP 專注 mobile
- Edge Function 冷啟動 → 加 loading state + timeout
- Edge Function 新增變數前先 `grep "const\|let" <name>` 確認無同名
- 錯誤訊息 minified → 開發時顯示完整錯誤類型，上線再簡化
- RevenueCat 購買後 tier 未同步 → 檢查 entitlements / 先用恢復購買或 `sync-subscription` / 必要時 SQL 直接更新
- **OCR 改動必須獨立 commit**，不混 security / cache / parser / prompt
- Edge Function 呼叫 Claude API 用 `CLAUDE_API_KEY`，**不是** `ANTHROPIC_API_KEY`
- 開場救星傳截圖必須用 `ImageData` 物件，**不能**用純 base64 字串

---

## 🧪 Testing & Local Dev

### 測試
```bash
flutter test                                   # 全部
flutter test test/unit/services/foo_test.dart  # 特定
flutter test --coverage                        # 覆蓋率
```
TDD：Red → Green → Refactor；命名 `should X when Y`

### Local
快速指令見 `README.md`（避免重複）。

---

## 🐛 Debugging Protocol

遇到 bug 必做：
1. 記錄 → **`docs/bug-log.md`** 新增一條（格式見該檔頂；**不寫進本檔**）
2. 找 root cause（不只表面修）
3. 寫測試驗證
4. 若是新陷阱 → 更新上面 Common Pitfalls（而非另加 bug 詳情）
5. Commit + push

### Edge Function 部署
```bash
SUPABASE_ACCESS_TOKEN=sbp_xxx npx supabase functions deploy analyze-chat \
  --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg
```

---

## 🤝 Claude ↔ Codex 協作協議

共用記憶 = `git log` + `docs/reviews/` + `docs/decisions.md` + `memory/`，**絕不**靠 session 記憶。完整腳本見 `memory/reference_ai_pair_roles.md` + `feedback_arbitration_protocol.md`。

### 任務分工（可覆蓋）
- UI / Flutter / 文案 / 產品判斷 → **Claude** 主導
- OCR / 演算法 / 效能 / 重構 plan → **Codex** 主導
- 緊急 L1/L2 → Claude；L3 禁區 → 都不動（止血或延後）
- Code review → **Codex**（獨立 bias）

### Codex review 權限
- 🔴 Bug / 🟡 功能風險 → **直接改** + 寫 `docs/reviews/*_codex-review.md`
- 🟠 架構替代方案 → 只寫不改，標 `Verdict: Daisy-Decision-Needed`
- 🟢 風格 / 命名 → 只建議不動

### Commit trailer（必含）
- `Reviewer-Hint: [不確定之處]`（若有）
- `Next-Step: [下步或禁區]`（若有）

### 新 session 開場固定流程
`git log --oneline -15` → `ls -t docs/reviews/ | head -5` → 讀 `docs/decisions.md` 最新 5 條 ADR → 讀 memory + `docs/snapshot.md` → 再動手

### 防 echo chamber（用戶盲點保護）
- Codex review **只看 diff**，Claude rationale 不先給
- 主張「安全 / 快 / 最佳」→ 必附 test / benchmark / 官方文件引用
- 2-2 僵持 → 引入 Haiku 當第三方
- 業務 / 產品 / 文案判斷 → **用戶直覺優先**，AI 只輸入不仲裁

### 定案寫 ADR
🟠 級分歧仲裁後**必**寫 `docs/decisions.md` ADR。
反駁對方改動 → 寫 `docs/reviews/*_<claude|codex>-rebuttal.md`，**絕不** revert / amend / force-push。

---

## 📚 Docs 指路

| 要找什麼 | 去哪 |
|---------|------|
| **當前階段狀態** | `docs/snapshot.md`（每月刷新） |
| **送審 checklist** | `docs/app-review-final-checklist.md` |
| **TestFlight regression** | `docs/testflight-regression-checklist.md` |
| **上線準備** | `docs/launch-readiness-checklist.md` |
| **OCR benchmark** | `docs/ocr-analysis-maturity-benchmark.md` |
| **Discord bot 問題** | `docs/discord-vibesync-troubleshooting.md`（live state 在 WSL `discord-vibesync`） |
| **設計規格 v1.3** | `docs/plans/2026-02-26-vibesync-design.md` |
| **實作計畫** | `docs/plans/2026-02-26-vibesync-implementation.md` |
| **Bug 歷史（18 條）** | `docs/bug-log.md` |
| **架構決策（14 條 ADR）** | `docs/decisions.md` |
| **RevenueCat 配置 + 除錯** | `docs/integrations/revenuecat.md` |
| **Third-Party Login 配置** | `docs/integrations/auth.md` |
| **AI 回覆優化流程** | `docs/ai-optimization-workflow.md` |
| **成本優化** | `docs/cost-optimization.md` |
| **定價方案** | `docs/pricing-final.md` |
| **iOS CI/CD 技術細節** | `~/.claude/memory/reference_ios_cicd_setup.md` |
| **法規文件** | `docs/legal/*.md` |

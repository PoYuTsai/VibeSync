# VibeSync Snapshot

> **動態狀態**—每月 1 號或重大階段變更時刷新。
> 靜態規則（Pitfalls / Conventions / OCR Guardrail）在 `CLAUDE.md`。

---

## 2026-04-28

### 階段
**Partner Entity Refactor A1 + A2 全 ship**（branch `feature/partner-entity-A2-polish` Phase 4 收尾，含 PartnerListCard 5 件套、partner delete cascade guard、per-account dedupe banner、merge picker preselect、copy sweep、砍 `@Deprecated HomeContent`）→ TF soak 進行中，準備送審。詳見 ADR #15 v2 ship section。

### Phase 4 ship 重點
- D-P4-1 partner delete = block-when-non-empty（cascade guard 走 `conversationsByPartnerProvider.length`，非 `aggregate.totalRounds`）
- D-P4-5 dedupe banner dismissed key per-account (`partner_dedupe_banner_dismissed_$uid`)
- TF regression checklist 補 J 段落 13 項

---

## 2026-04-24

### 階段
送審前最後穩定化 + TestFlight 邊界驗證 + 功能密集擴充剛收尾。

### 主線
- OCR 邊界案例持續收斂
- 開場救星品質優化
- 文章學習體驗優化
- 個人檔案卡 AI 摘要穩定化

### 已打通
- Auth（Apple + Google，見 `docs/integrations/auth.md`）
- 訂閱 4 產品（Starter/Essential 月繳+季繳，見 `docs/integrations/revenuecat.md`）
- 截圖上傳（Claude Vision，最多 3 張）
- 開場救星（basic + 截圖輔助）
- 學習專區 Tab（20 篇繁中文章）
- 我的報告 Tab（5 維雷達圖 + 歷史趨勢）
- 手動輸入分析
- TestFlight release workflow

### 送審前剩餘
- [ ] 真機跑 auth / restore / 升級後權限刷新
- [ ] 驗 OCR 邊界：LINE 引用、長截圖、多張截圖、名字錯字、圖片/貼圖/影片 bubble
- [ ] 驗開場救星：無截圖 / 1-3 張截圖、計費正確（基本 3 則 + 每截圖 +2）
- [ ] 驗學習專區：免費每日 3 篇限制、文章實戰練習按鈕導向開場救星
- [ ] 驗我的報告：雷達圖 Free 隱藏、Starter/Essential 可見
- [ ] 核對 privacy / terms / support email / App Store Connect privacy disclosure

### 不做大功能擴張
持續收邊界案例與品質優化，避免 feature creep。

---

## 三大 Tab（目前結構）

- **首頁** — 對話列表 / 新增對話（手動 + 截圖）/ 新用戶三步引導 / 開場救星入口
- **我的報告** — 5 維雷達圖 + 健康分數卡 + 歷史趨勢（Starter/Essential 限定）
- **學習專區** — 20 篇繁中翻譯文章（4 分類）+ 實戰練習入口（→ 開場救星）

---

## 訂閱方案（2026-04-22 起）

| Tier | 月繳 | 季繳 | 月訊息 | 日上限 | AI 模型 |
|------|------|------|--------|--------|---------|
| Free | NT$0 | — | 30 | 15 | Haiku |
| Starter | NT$590 | `starter_quarterly` | 300 | 50 | Sonnet |
| Essential | NT$1,290 | `essential_quarterly` | 800 | 120 | Sonnet |

詳見 `docs/pricing-final.md` 與 ADR #10 / #11。

---

## 最近重大 commit highlights

（**不列已完成功能清單**，只列 snapshot 當下值得知道的近期改動；列不到的去 `git log --oneline -30` 查）

- [feat] AI 自動提取對方興趣、特質、備註，顯示個人檔案卡
- [feat] 對話訊息長按選單：換邊（她說↔我說）+ 刪除
- [feat] 繼續對話只收增量計費
- [feat] 設定頁 / Paywall 加入月繳/季繳標示 + 下次續約日期
- [feat] 開場救星：頁面 UI + Edge Function opener 模式
- [feat] 更新定價方案：Starter NT$590 / Essential NT$1,290 + 4 產品
- [feat] 學習專區 20 篇文章 + 免費每日 3 篇限制
- [feat] 我的報告 Tab：5 維雷達圖 + 圖表
- [fix] GAME 階段改名為「對話進度」（破冰/升溫/深入/連結/邀約）

---

## 更新規則

### 何時該改這份檔
- 每月 1 號 review（scheduled agent 會提醒）
- 大 feature 上線後
- 送審階段變更時（送審 → 審核中 → 上架）
- 定價或產品結構變更時

### 何時**不**該改這份檔
- Bug 修復 → 去 `docs/bug-log.md`
- 新決策 → 去 `docs/decisions.md`
- 硬規則變化 → 去 `CLAUDE.md`
- 日常 commit → git log 自己會記

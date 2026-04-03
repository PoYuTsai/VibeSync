# gstack Usage SOP

> 適用於目前 VibeSync 專案的 Claude / Codex 工作流
> 最後更新：2026-04-03

## 先講結論

gstack 不是產品功能，而是 `AI 開發工作流工具包`。

你現在最常會用到的指令是：

- `/gstack-review`
- `/gstack-investigate`
- `/gstack-qa`
- `/gstack-cso`
- `/gstack-document-release`

## `/gstack-review` 到底在 review 什麼

預設是 review：

- `目前 branch`
- 相對 `base branch`
- 的整體 diff

通常會包含：

- 已 commit 但還沒進 base branch 的改動
- 目前工作樹未 commit 的改動

所以它不是只看「最新幾個 commit」，而是看你當下這個 branch/worktree 對 base 的差異。

## 什麼時候用哪個指令

### 1. `/gstack-review`

用途：
- Code review
- 看目前改動有沒有 bug、回歸風險、漏測試

最適合：
- 準備 commit / push / merge 前
- 改完一輪功能後做自查

### 2. `/gstack-investigate`

用途：
- 查難 bug
- 查奇怪狀態不同步
- 查 CI / deploy / subscription / auth 類問題

最適合：
- 你覺得「怎麼改很多刀還是怪」
- 想先找 root cause 再動手修

### 3. `/gstack-qa`

用途：
- 跑 staging / preview / 測試頁驗收
- 看流程有沒有 broken

最適合：
- Web 後台頁面驗收
- 管理頁 / Dashboard / Landing page

### 4. `/gstack-cso`

用途：
- 資安 / 權限 / trust boundary / data leak 風險掃描

最適合：
- 送審前
- 上線前
- Auth / Subscription / Edge Function 改動後

### 5. `/gstack-document-release`

用途：
- 整理 release note / handoff / 變更摘要

最適合：
- 發 TestFlight 前
- 要整理給夥伴看
- 要讓新 session 快速接上上下文

### 6. `/gstack-plan-ceo-review`

用途：
- 從產品價值、商業、用戶價值角度 challenge 一個想法

最適合：
- 想加新功能前
- 想確認某個功能值不值得做

### 7. `/gstack-plan-eng-review`

用途：
- 從工程架構、可維護性、風險看方案

最適合：
- 想重構
- 想收架構債
- 想確認某個改法是否穩

## VibeSync 最實用的使用順序

### A. 改功能 / 修 bug

1. `/gstack-investigate`
2. 自己修或讓 AI 修
3. `/gstack-review`

### B. 送審前

1. `/gstack-review`
2. `/gstack-cso`
3. `/gstack-document-release`

### C. 要整理給夥伴看

1. `/gstack-document-release`

## 目前最推薦的 VibeSync 實戰情境

- `OCR 又怪怪的`
  - 先用 `/gstack-investigate`

- `剛修完訂閱 / auth / webhook`
  - 跑 `/gstack-review`

- `送審前最後一輪`
  - 跑 `/gstack-cso`

- `要整理版本進度給夥伴`
  - 跑 `/gstack-document-release`

## 注意

- 你現在裝的是 `gstack-` 前綴版本
- 所以請用：
  - `/gstack-review`
  - 不是 `/review`

## 補充

- gstack 裝在：
  - Claude repo-local：`.claude/skills/gstack`
  - Codex global：`C:\Users\eric1\.codex\skills`
- 如果 Claude Code 沒看到新指令，最穩就是重開 session

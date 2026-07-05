# 案 3 設計：冷啟動分流＋首頁空狀態 CTA

> 2026-07-06 brainstorming 定稿，Eric 拍板。母案：`2026-07-06-post-review-optimization-roadmap.md` 案 3。
> 狀態：SHIPPED（54260ad5，2026-07-06；flutter test 21 passed＋analyze 乾淨；待 Eric dogfood 體感）。
> 風險：低（純 client UI/導流，不碰 gate、不碰 server），非高風險區故單審。

## 事實修正（對 roadmap 的更正）

練習室**不是**第 3 個 tab。MainShell 只有 3 tab（首頁/報告/學習），練習室是獨立 route
`/practice-collection`（圖鑑＋翻牌）與 `/practice-chat`，入口已全收進圖鑑。
分流「沒對象」落點＝`/practice-collection`，不是切 tab。

## A. onboarding 第 5 頁分流頁

檔案：`lib/features/onboarding/presentation/screens/onboarding_screen.dart`

- `_pages` 前 4 頁（含第 4 頁 AiPrivacyDisclosure 隱私揭露）一字不動。
- `PageView.builder` itemCount 改 `_pages.length + 1`；index == `_pages.length` 時 render
  專用分流 widget（不走 `OnboardingPage`）。
- 分流頁內容：標題「你現在有正在聊的對象嗎？」＋兩顆按鈕：
  - 主按鈕「有，帮我分析對話」→ `markCompleted()` → `context.go('/')` →
    `context.push('/partner/new')`
  - 次按鈕「還沒，先去練習」→ 同上但 push `/practice-collection`
  - 先 go('/') 再 push：back 鍵退回首頁 tab 0，不卡死。
- 底部 `BrandPrimaryButton`：分流頁隱藏（分流按鈕在頁內）；前 4 頁一律顯示「下一步」
  （原「開始使用」三元邏輯失效，直接簡化）。
- 右上「略過」行為不變（`markCompleted` → `/`），每頁可逃生。
- 指示點改 5 顆（`_pages.length + 1`）。
- **`resolveAppRedirect` gate 零改動**——`/partner/new`、`/practice-collection` 不在強制名單，放行。

## B. 首頁空狀態兩顆 CTA

檔案：`lib/features/partner/presentation/screens/partner_list_screen.dart:43-77`

空狀態 Column 尾端加：
- 主按鈕「建立對象卡，開始分析」→ `context.push('/partner/new')`（與 shell FAB 同路）。
  不用 roadmap 原文案「分析我的對話」——實際落點是建卡，誠實文案避免落差；dogfood 可再調。
- 次按鈕（outlined）「先去練習室熱身」→ `context.push('/practice-collection')`。

受眾＝按略過跳過分流、或分流後退回首頁但還沒建卡的用戶。

## 測試

Widget test 三件：
1. 分流頁兩按鈕各自導流正確＋`onboarding_completed` 有寫入。
2. 略過行為不變（markCompleted → `/`）。
3. 空狀態顯示兩 CTA；有 partner 時不顯示。

`resolveAppRedirect` 純函式零改動，不需新測。

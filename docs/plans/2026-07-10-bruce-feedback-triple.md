# Bruce 回饋三案（抽卡去重／滑動教學動畫／對話列表分區）Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 收掉 2026-07-10 Bruce dogfood 三條回饋：練習室抽卡不再抽到已收藏角色、OCR 確認頁加一次性滑動教學動畫、對象互動紀錄列表把舊對話摺疊分區。

**Architecture:** 案 A 改 server（practice-chat draw handler 的排除集合從「當日視窗」擴成「全歷史」＋池滿退避）；案 B、C 是 client 純 UI，不動 Hive schema、不新增欄位。三案互相獨立，可分批 commit。

**Tech Stack:** Supabase Edge Function (Deno/TS)、Flutter/Riverpod。

**風險分級：** 案 A 碰 practice-chat＝高風險區，**必須 Codex 雙審（直呼 codex:rescue，拿到 verdict 才算 safe）**。案 B、C 低風險單審即可。

**背景事實（2026-07-10 已查證，檔案:行號）：**
- 抽卡選角純函式：`supabase/functions/practice-chat/practice_persona.ts:1154` `selectPracticeDrawProfile`；加權抽層 `:1116`；權重 SR10/R30/N60 `:1098`；層空退避 SR→R→N `:1108`。
- 去重在 `supabase/functions/practice-chat/draw_handler.ts:139-153`：查 `practice_profile_draw_events` 但 **只 filter `reset_window_start_at == 本視窗起點`**，所以跨天可重複抽到已收藏角色（現行設計）。
- 撞號兜底：RPC `PRACTICE_DRAW_PROFILE_CONFLICT` ＋最多 3 次重抽（`draw_handler.ts:38, 161-200`）。
- `catalogSize` 只用來切池（舊 build 相容，`practice_persona.ts:1058-1088`），與去重無關；client 不參與選角。
- 滑動提示文案「判錯邊？左右滑動訊息即可切換。」在 `lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart:490`。
- 對話列表：`lib/features/partner/presentation/screens/partner_detail_screen.dart:342-360`（「互動紀錄」＋ `PartnerConversationTile`），資料源 `conversationsByPartnerProvider`，排序在 `lib/features/conversation/data/repositories/conversation_repository.dart:51` 與 `:103`（updatedAt desc）。Conversation entity（`lib/features/conversation/domain/entities/conversation.dart`）HiveField 0–16，無封存欄位。

---

## 案 A：抽卡永久去重（server，高風險，先做）

**拍板規格（Eric 2026-07-10）：**
1. 排除集合＝該使用者在 `practice_profile_draw_events` 的**全歷史** draw（不再只限當日視窗）。
2. 排除後的 eligible 池要先跟 `catalogSize` 切出來的池取交集（沿用現有池切邏輯，別繞過）。
3. **池抽滿退避**：全歷史排除後 eligible 為空 → 退回「只排除當日視窗＋currentProfileId」的現行行為（允許重複），**絕不**讓抽卡直接失敗。
4. 稀有度層空退避（SR→R→N）邏輯不動。
5. 3 次重抽兜底路徑必須跟新排除集合一致（重抽時也要帶同一個排除集合）。

### Task A1: 讀懂現場

**Files:** Read `supabase/functions/practice-chat/draw_handler.ts`（重點 130-210）、`practice_persona.ts:1040-1200`、該 function 的既有測試檔（`supabase/functions/practice-chat/` 下 `*_test.ts` / `tests/`，先 `ls` 找）。

### Task A2: 先寫失敗測試（Deno）

**Test:** 在既有 draw/persona 測試檔旁新增或擴充：
1. `selectPracticeDrawProfile` 給 excluded=全池-1 → 必回唯一剩餘角色。
2. excluded=全池 → 觸發退避路徑（依 A3 實作介面：回 null 或帶 flag，由 handler 降級）。
3. handler 層：mock 全歷史 events 覆蓋全池 → 最終仍成功回一張卡（走視窗排除降級），且 response 形狀不變。

Run: `deno test`（在 function 目錄，沿用該專案既有測試跑法；預期新測試 FAIL）。

### Task A3: 實作

**Modify:** `draw_handler.ts:139-153` — 查詢拿掉 `.eq("reset_window_start_at", ...)` 改成查該 user 全歷史（只 select `profile_id`，distinct/Set 去重；表是 per-user 抽卡事件，量級 ≤ 每天一抽，無效能疑慮）。組 `permanentExcluded`。
先用 `permanentExcluded ∪ {currentProfileId}` 呼叫 `selectPracticeDrawProfile`；若 eligible 為空 → 降級改用現行「當日視窗排除」集合重呼叫一次。降級時 log 一行 telemetry（沿用該檔既有 log 風格）標 `draw_dedup_fallback`。
重抽（conflict retry）迴圈內沿用同一集合邏輯。

Run: `deno test` 全綠。

### Task A4: Codex 雙審 → 部署 → commit/push

1. 直呼 codex:rescue 對抗式審（重點：降級路徑、retry 一致性、response schema 不變、429/quota 路徑不受影響）。拿到 APPROVED 才往下。
2. Commit（繁中訊息，一 commit 一事）＋ push。**push 即自動 deploy**（先 `gh run list` 確認 CI 綠）。

---

## 案 B：OCR 確認頁滑動教學動畫（client，小）

**規格：** 在 `screenshot_recognition_dialog.dart` 提示卡（`:490` 附近）出現時，對第一則訊息泡泡播**一次性**左右滑動示意動畫（泡泡水平位移 ~24px 來回一趟＋箭頭淡入淡出，總長 ≤1.6s，播完停在原位）。

**鐵則：動畫零無限 repeat；widget test 的 `pumpAndSettle` 必須收斂。** 只在 dialog 首次 build 播一次（本次開啟內不重播即可，不用落地持久化「看過」旗標——YAGNI）。

### Task B1: 失敗測試
Widget test：pump dialog → 動畫期間泡泡 transform 有位移 → `pumpAndSettle` 收斂 → 位移歸零。
Run: `flutter test test/...（放在 analysis widgets 既有測試旁）`，預期 FAIL。

### Task B2: 實作
單一 `AnimationController`（`TickerProviderStateMixin`），`forward()` 一次，dispose 齊全。動畫只包訊息 list 第一項的 Transform.translate＋箭頭 opacity。

Run: `flutter test` 綠。Commit＋push。

---

## 案 C：互動紀錄列表分區摺疊（client，輕量版）

**拍板規格：不做封存頁、不動 Hive schema。** `partner_detail_screen.dart` 的「互動紀錄」列表切兩區：
- 「進行中」：`updatedAt` 距今 ≤30 天。
- 「較早的對話」：>30 天，預設收合（`ExpansionTile` 或自製 header＋顯示數量 badge），展開後內容同現有 tile。
- 兩區內部維持 updatedAt desc；排序邏輯留在 repository 不動，分區在 presentation 層做。
- 全部都 ≤30 天或全部 >30 天時：不顯示分區 header，跟現狀一樣單一列表（>30 天全舊時直接展開顯示，別給使用者一頁空白）。

### Task C1: 失敗測試
Widget/unit test：給 3 筆新＋2 筆舊 conversation → 列表出現「較早的對話 (2)」收合區；全新 → 無分區 header。
Run: `flutter test`，預期 FAIL。

### Task C2: 實作＋commit/push
分區邏輯抽純函式（好測），畫面用現有 `PartnerConversationTile` 不重造。跑 `flutter test` 綠後 commit＋push。

---

## 收尾

- 三案各自獨立 commit＋push（案 A 需 Codex APPROVED 證據才宣稱 dogfood safe）。
- 更新記憶：練習室 hint 記憶檔補「抽卡跨天重複＝已改永久去重（池滿退避）」；本計畫檔路徑記入。
- 全部完成後提醒 Eric 真機 dogfood：抽卡連兩天驗證不重複、OCR 確認頁動畫、舊對話摺疊。

---

## 2026-07-11 真機回饋後的最終優化（取代案 B／C 輕量版）

Eric 在 build 322 實測後拍板「OK 處理」，因此下面規格為目前真相；上方案 B
「每次開啟都播、不落旗標」與案 C「只做 30 天摺疊、不做封存頁」不再適用。

### C：已分析對話改成真正的獨立分析紀錄

- 分析快照成功落盤後才標記 archived；失敗絕不封存。
- 新增／編輯／換邊／刪除訊息會標回 active；只改 partnerId 的 metadata save
  保留原狀；刪除對話同步清 marker。
- marker 存在已加密 `settingsBox`，owner-scoped，不新增 Conversation HiveField／
  migration。舊資料只有 snapshot、message count、較新的 analyze history 三項證據
  都成立時才保守推導 archived；歷史盒不可用則 fail-open 留在目前對話。
- 對象頁只顯示「目前對話」，另有「分析紀錄 (N)」入口；獨立頁依月份分組，
  可查看、可「繼續這一段」移回 active，也可新增對話。
- Commit：`b7753875`。

### B：首次自動播放、可重播、尊重 reduce-motion

- 首幀後延遲 350ms，僅全裝置第一次自動播放；實際開始播放才寫 seen flag。
- 第一則泡泡分兩段示範「右滑 → 我說」「左滑 → 她說」，播放完歸零、不 repeat。
- 48px `?` 按鈕可隨時重播；永久提示保留絕對方向文字。
- 使用者先操作訊息或關閉 dialog 會取消仍在途的偏好讀取／timer／動畫。
- `MediaQuery.disableAnimations` 下不移動，按 `?` 顯示靜態雙向圖例。
- Commit：`774ff49f`。

### A：滿池預期管理與異常重複監測

- 圖鑑既有 `X/100` 保留；收藏達 100/100 再翻牌時，先告知之後可能重複。
- 若同時需要扣 5 則額度，重複風險與扣費合併成一個確認窗，取消不送抽卡。
- server 對非 idempotent replay、非合法池滿退避卻回歷史角色，或回目前角色，
  記 `practice_draw_unexpected_duplicate`；只記 telemetry，不改已成功 RPC／扣費／
  response schema。合法 replay 與池滿 fallback 不誤報。
- Commit：`a4f62428`。

### 驗證狀態

- Archive／analysis／OCR 高風險整合 bundle：126/126 通過。
- Hint service + Collection screen：41/41 通過。
- Draw handler：`deno test --allow-env .../draw_handler_test.ts` 18/18；
  `deno check`、`deno fmt --check` 通過。
- `flutter analyze`：0 issue；`git diff --check` 通過。
- 競態修正 commit：`47d7986e`；OCR edge-case commit：`636c7c2b`。
- Codex client red-team 與 test/migration/data-safety 第二輪皆 `APPROVED`，
  P0/P1/P2 = 0/0/0；證據見
  `docs/reviews/2026-07-11_bruce-ux-followup-codex-review.md`。
- 出貨狀態：程式碼與雙審 gate 已完成；尚待 push／PR、`practice-chat` Edge deploy、
  新 TestFlight build 與三案真機 dogfood。

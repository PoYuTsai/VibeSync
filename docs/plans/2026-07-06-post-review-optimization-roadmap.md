# 上架後優化 Roadmap（審核等待期規劃）

> 2026-07-06 五路現況盤點彙整。狀態：APPROVED（Eric 2026-07-06 拍板全做，照建議順序：案3→案1→案2→案4→案6-1→案5/案6-3）。
> 背景：build 305 Waiting for Review。PM 視角缺口 × TA 痛點 × 程式現況三方對齊後的精進版需求。

## 總結論

功能面已及格，下一階段槓桿在「證明有效」與「快到當下能用」。五路盤點後的意外發現：
**多數缺口的地基已經蓋了一半**，都不是從零開始的案子。

## 各案現況與切入點（按建議優先序）

### 案 1：Outcome loop server 化（成效閉環）— 建議首發

**現況（比預期好）**：
- 本機閉環已活著：coach 建議卡有「記錄結果」UI，寫入 Hive `CoachingOutcomeEvent`
  （`lib/features/coach_chat/presentation/widgets/coach_chat_card.dart:919-935`，
  model 在 `lib/features/coaching_memory/domain/entities/coaching_outcome_event.dart:53`）。
- 枚舉齊全：`CoachingUserAction`（照發/改後發/沒發/再問）＋ `CoachingOutcomeSignal`（engaged/cold/noReply/negative/pending）。
- `CoachingOutcomeSource.opener` / `.analyze` 已定義但**無人寫入**——opener 和分析的採用結果目前不被記錄。
- 「複製建議」全程無埋點（analysis_screen.dart:4384、reply_card.dart:125 等只複製不記錄）。
- `CoachingOutcomeDigest` 有計算但無下游消費（沒進 prompt、沒進 UI）＝死下游。
- server 端零記錄；唯一接點是 `submit-feedback`（已有 JWT＋feedback 表＋client 封裝 `analysis_screen.dart:4178`）。

**精進後範圍**：
1. opener/analyze 的建議卡補上與 coach 相同的 outcome 記錄入口（複用現成 model＋UI 模式）。
2. 複製建議時自動記一筆 `userAction=sentAsIs(暫定)` 的 pending 事件，降低回報摩擦。
3. 擴充 `submit-feedback` payload 帶 adviceId＋userAction＋outcome，本機寫 Hive 同時 POST（不動 analyze-chat 計費主線）。
4. `CoachingOutcomeDigest` 接進 coach prompt（「上次照建議發了她有回」）——閉環回饋個人化。

**風險**：submit-feedback 是低風險 function；不碰計費。屬中低風險案。

### 案 2：分析事件歷史表（進步感的地基）— 建議第二，因為它是案 5 的前置

**現況（最大的洞）**：
- 沒有任何可回看的時間軸：Conversation 分數是覆蓋式快照（`conversation.dart:29-77`）、
  PracticeSession 只留最近 5 場（`practice_session.dart`）、server `analysis_runs` 30 分鐘就清
  （`20260528001000_analysis_runs.sql:14,52`）。
- 報告頁雛形已上線（`MyReportScreen`＝底部第 2 tab，`report_data_service.dart:20-90`），
  但趨勢是「每對象最新一點」不是時間序列。
- debrief/analyze 輸出無枚舉化錯誤模式欄位（watchouts 是自由文字），無法跨場聚合「你常犯什麼」。

**精進後範圍**：
1. 本機 Hive 新增 append-only `AnalysisHistoryEvent`（date、熱度、五維、階段、practice 溫度/難度/過關）——
   每次 analyze/debrief 完成 append 一筆。純本機即可起步，符合隱私 Option A。
2. MyReportScreen 趨勢改吃時間序列（沿用現成 fl_chart 元件）。
3. （後續）errorPattern 枚舉化：analyze/debrief prompt 輸出加一個受控 taxonomy 欄位，才有「常犯錯誤」聚合。
   此項動 Edge schema＝高風險區，獨立成案走雙審。

**注意**：資料是時間函數——越晚開始 append，dashboard 能回看的歷史越短。這是「早做便宜、晚做昂貴」的案子。

### 案 3：冷啟動分流＋首頁空狀態 CTA — 小案，快贏

**現況**：
- 動線：Splash(3.5s) → login → onboarding 4 頁靜態文案 → 一律落首頁 tab0 零資料空狀態。
- 分流 gate 只看登入＋onboarding bool（`lib/app/routes.dart:38-70`），零用戶狀態判斷。
- 首頁空狀態純文字無 CTA（`partner_list_screen.dart:43-77`）；練習室藏第 3 tab，要 3 步。
- 分流所需訊號已存在：`partnerListProvider.isEmpty`。

**精進後範圍**：
1. onboarding 末頁加一題「你現在有正在聊的對象嗎？」→ 有：導 FAB 新增對象＋分析；沒有：直接導練習室翻牌。
2. 首頁空狀態補兩顆 CTA：「分析我的對話」＋「先去練習室熱身」。
3. 不動 Splash、不動 gate 架構（只改 `_completeOnboarding` 落點）。

**風險**：低。純 client UI/導流。

### 案 4：48h 跟進提醒（本地通知版）— 中案

**現況**：
- 通知基礎設施完全沒有（無套件、無 entitlements、無 pg_cron）。
- 但 `coach-follow-up` 跟進建議功能已存在（用戶手動觸發，partner 詳情頁）。
- Hive Conversation 有 `updatedAt`/`lastMessage` 時間戳可算 48h。

**精進後範圍**：加 `flutter_local_notifications`，分析完成時排 +48h 本地通知，
點擊 deep-link 進 partner 詳情頁（現成 coach-follow-up 入口）。需一個去重標記（通知 id＝partnerId）。
不碰 server、不需 push 憑證。

**風險**：中。新增權限請求（通知授權彈窗時機要設計）；iOS 送審後改 Info.plist 要隨下個 build。

### 案 5：進步 dashboard「本月成長頁」— 依賴案 2，暫緩

案 2 的資料 append 跑起來累積 2-4 週後才有意義。先做地基，頁面後補。

### 案 6：時效摩擦 — 認知先於工程，暫緩大改

**現況**：
- 最終分析已是 streaming，recommendation 事件先到即可複製——這段其實不慢。
- **最肥等待＝OCR recognizeOnly 的非 streaming server round-trip**（Vision LLM 整包，
  client 阻塞盯 spinner，上限 120-130s；`analysis_screen.dart:3345-3369`）。次肥＝最多 6 段序列壓縮。
- 耗時 telemetry 有量測但只存記憶體、debug 才看得到（`analysis_service.dart:1478-1568`）——
  **正式版完全看不到用戶真實等多久**。
- share extension 完全沒有（無 app group、無 NSExtension、無套件）。

**精進後排序**：
1. 先把現成 telemetry 落地上報（可搭案 1 的 submit-feedback 通道或 ai_logs），拿到真實分佈再決定攻哪段。
2. OCR spinner 期間的體感優化（進度文案/骨架屏）便宜可先做。
3. share extension 是正確長期解，但動 Xcode target＋app group＝送審面改動，等 build 305 過審後獨立成案。

## 建議執行順序

```
案 3（快贏，1 天級）→ 案 1（核心價值，2-3 天級）→ 案 2（地基，越早越好）
→ 案 4 → 案 6-1 telemetry → 案 5 / 案 6-3
```

案 3 先做的理由：小、獨立、下個 build 就能帶上；案 1/案 2 並行風險低（不同檔區）。

## 鐵則對齊

- 案 1 碰 submit-feedback（低風險）；案 2 第 3 步碰 Edge schema＝高風險必雙審。
- 所有案不碰 subscription/quota/計費主線。
- 每案開工前走 brainstorming → writing-plans；完成走 verification。

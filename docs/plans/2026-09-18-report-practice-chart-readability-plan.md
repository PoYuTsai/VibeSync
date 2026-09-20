# 報告頁圖表可讀性優化｜最終實作規格

日期：2026-09-18
核對基準：`origin/main` = `c80bdd7`（學習專區文章 #74）。本地任務分支 `claude/report-area-image-optimization-00kmai` 停在其父 commit `3134c51`；兩者差異只有 `lib/features/learning/` 的文章資料，不觸及本文任何檔案，行號以本地工作樹核對。
文件性質：實作規格。未修改產品程式碼、未產生 adapter、未跑 Flutter 測試、未 commit / push / PR / 部署。

本文由三份來源整合：2026-09-17 dogfood 截圖、2026-09-18 第一版計畫、以及對第一版的送審修訂稿。第 1 節列出送審稿每一項主張的核對結果；第 2 節起是最終規格，後續實作以本文為準。

---

## 1. 送審稿核對結果

### 1.1 程式行為主張：全部成立

| 主張 | 證據 | 結果 |
|---|---|---|
| 兩圖 x 軸為「距首點分鐘數 / 1440」 | `practice_temperature_chart.dart:205-206`、`heat_trend_chart.dart:287-288` | 成立 |
| 主線 `isCurved: true`、平滑 0.3 | `practice_temperature_chart.dart:309-310`、`heat_trend_chart.dart:372-374` | 成立 |
| overlay 另算 Catmull-Rom（tension 0.56），裁切用 `plot.inflate(7)`；主線用 `FlClipData.all()` | `trend_flow_overlay.dart:227, 250-275`；`practice_temperature_chart.dart:246` | 成立。兩線裁切範圍不同，截圖中超過 100 的弧不能單獨歸因主線 |
| 練習事件只在 debrief 成功、`_persist()` 之後 best-effort 寫入，id 為隨機 UUID | `practice_chat_providers.dart:2456-2483, 2781-2803` | 成立 |
| `beginner` 與 `game` 都是 `usesAssistedLearning == true`，`standard` 否 | `practice_learning_mode.dart` | 成立。現行空態文案「新手模式」漏了 Game |
| 續同一位：新 sessionId、`roundIndex + 1`、`aiReplyCount: 0`、溫度沿用上一輪 | `practice_chat_providers.dart:1715-1758` | 成立。「終溫 − 難度起始值」在第二輪起就錯 |
| 歷史事件上限 500、以 `createdAt` 刪最舊；練習 session 只保留最近 5 段 thread | `analysis_history_repository_impl.dart:11, 95-107`；`practice_session_repository.dart:14` | 成立。畫圖時不能 join session |
| `AnalysisHistoryEvent` HiveField 0–13，`PracticeSession` 0–30（typeId 23） | 兩個 entity 檔 | 成立。14–17 與 31 可用 |
| 難度倍率 easy 1.25/0.75、normal 1/1、challenge 0.7/1.3 實際接進判分 | `practice_persona.ts:397-419`；`handler.ts:1492` 取 tuning → `temperature.ts:343-358` 套用 | 成立 |
| delta 先 clamp（−12..+8），再對 score clamp 0–100 | `temperature.ts:184-186, 217-227, 286-297` | 成立。`score − delta` 反推不出真實起點 |
| server seed 優先序：ledger > 同 thread > client seed > 難度預設 | `learning_seed.ts:5-6, 28-60` | 成立 |
| Game 有額外判分條件 | `handler.ts:355-369`（game 專屬 hint 下限）、`temperature.ts:529` 引用 `game_fsm.canEarnPositive` | 成立 |
| `clampVisibleInvestmentScore` 只 clamp，0.9 校準是另一個函式 | `enthusiasm_level.dart:10, 14` | 成立 |
| `HeatTrendChart` 由外部傳入 average/delta/sampleCount，可與 points 不一致 | `heat_trend_chart.dart:20-36`；`my_report_screen.dart:149-156` | 成立 |
| 整體摘要「前後趨勢」是各對話快照的前後半平均差 | `report_data_service.dart:48-63` | 成立 |
| Dart `List.sort` 不保證穩定 | Dart 官方文件 | 成立 |
| fl_chart 0.70.2 有 `RangeAnnotations` / `HorizontalRangeAnnotation` / `FlClipData.none()` / `preventCurveOverShooting` / `handleBuiltInTouches` | 已抓取 0.70.2 原始碼：`axis_chart_data.dart:858, 910`；`line_chart_data.dart:59, 84, 239` | 成立 |
| hive_ce 2.19.3、hive_ce_generator 1.11.3、fl_chart 0.70.2 | `pubspec.lock` | 成立 |
| 列出的 8 個既有測試檔都存在 | `ls` 逐一確認 | 成立 |
| in-memory history helper 有模擬 id 覆寫 | `test/helpers/memory_analysis_history_repository.dart:11-14` | 成立（送審稿寫「需檢查」，已確認有） |

### 1.2 對送審稿設計的修正

| 送審稿設計 | 決定 | 理由 |
|---|---|---|
| B 在 `PracticeSession` 加 `reportCompletedAt`（HiveField 31）並貫穿 `PracticeChatState` / copyWith / `_stateFromSession` / `_persist` | **不採用** | 目的為「同場重試不改 createdAt」，但同場二次寫入的路徑不存在：debrief 成功後 `debrief != null`，`canDebrief` 為 false（`practice_chat_providers.dart:363-369`）；失敗重試時尚未寫過事件。穩定 id 已足夠去重。砍掉可省一個 adapter 重生、state 三處 plumbing 與對應測試 |
| B 欄位 14–17 | 採用 14 `practiceDifficulty`、15 `aiReplyCount`、16 `practiceMode`、17 `practiceSessionId` | 17 與 id 前綴重複，但舊事件 id 是 UUID，明確欄位避免解析字串 |
| 歷史 append 移到 `_persist()` 之後、`confirmDebriefPersisted` 之前 | 採用 | `confirmDebriefPersisted` 若丟錯會進 catch，現行順序下事件不會寫（`:2459-2483`） |
| 事件寫入加 `aiReplyCount >= 1` 檢查 | 改為不變量說明，不加新 gate | `canDebrief` 已要求 `aiReplyCount >= 1`；事件只在 debrief 成功後寫 |
| 日期標籤用 `TextPainter` 量測後挑選，上限 5 | 採用，實作放在 `LayoutBuilder` 取得 plot 寬度後一次計算，不在 `getTitlesWidget` 內量測 | 避免每次 title 回呼重算 |
| 測試檔清單 | 補兩處：`my_report_screen_test.dart:281, 328`（`起點 50 · 6/01`、`練習溫度成長` 字串斷言）；`liquid_motion_report_capture_test.dart:33-34, 139-140`（舊的 averageScore/scoreDelta 參數） | 送審稿漏列 |
| `safe_batch_proof_test.dart` | 不受 A 影響 | 它建構的是 `ReportData`，不直接用 `HeatTrendChart`；C 若保留 `ReportData.scoreDelta` 欄位也不受影響 |
| 其餘：序數 x、直線、移除 overlay 與填色、連續色帶、五狀態文案、圖下方選取資料、C 摘要改現況、不做升溫幅度 | 採用 | 核對無誤 |

---

## 2. 方向與範圍

**先把兩張圖改成「每筆紀錄等距排列、直線連接、點選可查看資料」，並把練習圖改稱「練習溫度紀錄」。**

| 範圍 | 結果 | 儲存／後端影響 |
|---|---|---|
| A：圖表與練習文案 | 兩圖可讀；日期、分數、選取資料來自同一份視窗；不把終溫包裝成成長 | 只改 report 讀取模型與 UI；不改 Hive、不改 Edge |
| B：練習紀錄補條件 | 新事件帶難度、模式、AI 回覆數、session id；同場不產生第二點 | `AnalysisHistoryEvent` 加 4 個 nullable 欄位；不改 `PracticeSession`；不改 Edge |
| C：整體摘要文字 | 只描述目前快照，移除跨對話的上升／下降判斷 | 只改 UI；平均與階段分佈計算不變 |

A 是主線。只有 A 完成時，稱「圖表與文案修正完成」，不稱整份規格完成。

**本次不新增「能力成長分數」「跨難度升溫排名」「暖區成功率」**，理由見第 10 節。

---

## 3. 使用者看到的內容（文案需 Eric 確認）

### 3.1 練習圖

| 位置 | 文字或呈現 |
|---|---|
| 區塊標題 | 看每次練習的紀錄 |
| 區塊說明 | 看看每輪練習結束時的聊天溫度。難度、模式和聊天長度不同，分數會有起伏。 |
| 卡片標題 | 練習溫度紀錄 |
| 主要數字 | `最近結束溫度 38 / 100`，取視窗最後一筆 |
| 筆數 | `最近 N 筆紀錄`，N 為實際顯示筆數，上限 7 |
| 卡片補充 | 每個點是一輪練習的結束溫度，不等於能力評分。 |
| 空態 | 完成有溫度計的練習並取得拆解卡後，這裡會留下紀錄。 |
| 空態補充 | 包含新手與 Game 模式。 |
| 單點 | `結束溫度 38 · 9/18 19:20`，不畫連線 |
| 單點補充 | 再留下 1 筆紀錄，就能一起查看兩次的差別。 |
| 多點圖註 | 按紀錄先後排列，點一下查看那次資料。 |
| 較上次 ±N | 移除，連同紅綠色 |

「一輪」＝一個 practice session；續同一位的下一輪是另一個點。

### 3.2 投入度圖

| 位置 | 文字或呈現 |
|---|---|
| 卡片標題 | 每次互動投入度（不變） |
| 主要數字 | `這 N 次平均 62 / 90`，只平均畫面上的點 |
| 差值（N ≥ 2） | `較上次 +5` / `較上次 −5` / `較上次 0`，中性色，只用正負號 |
| 筆數 | `最近 N 筆分析`，不寫「已累積」 |
| 零筆 | 尚無這位對象的分析紀錄；不顯示平均 0 或差值 0 |
| 單點 | `投入度 62 · 9/18 19:20`，不寫「起點」 |
| 多點圖註 | 按分析先後排列，點一下查看那次資料。 |
| 平均虛線 | 保留，標籤改「這 N 次平均」 |

0 是有效分數，「沒有資料」不能用 0 代替。平均顯示用 `round()`；虛線用未捨入的平均。

### 3.3 選取資料放在圖下方

- 固定位置的文字區，不塞進浮動 tooltip。初次選最新一筆；點其他點時文字與選取標記一起更新。
- 第一行：`本圖第 3 筆 · 9/18 19:20`。序號只指目前視窗，不是當天第幾次或總場數。
- 第二行：練習 `結束溫度 38 / 100 · 偏冷`；分析 `投入度 62 / 90`。
- B 完成後練習多一行：`新手 · 一般 · 第 2 輪 · 她回覆 8 次`。未知欄位不補預設值；全無時顯示「這筆舊紀錄沒有保存練習條件」。
- `handleBuiltInTouches: false`，保留 `touchCallback` 更新所選；只接受合法單線 `spotIndex`，檢查上下界。
- 提供「上一筆／下一筆」按鈕，點擊區 ≥ 44×44，邊界停用；供不易點中圓點者與 VoiceOver 使用。
- 卡片主數字永遠是最新一筆；下方文字明示目前選取的是哪一筆。

---

## 4. 共用資料與座標規格

### 4.1 資料整理順序

**選定來源 → 檢查可用分數 → 確定排序 → 取最後 7 筆 → 從同一份清單算數字並畫圖。**

1. 分析圖沿用 partner／conversation scope 解析，不改對象歸屬。
2. 練習圖只讀 practice 事件的 `temperatureScore`；不混入 analyze 或 familiarity。
3. 練習合法溫度為整數 0–100。null 不入圖；超界不畫、不修改原始事件。
4. 分析圖沿用 `clampVisibleInvestmentScore` 與 0–90，不再乘 0.9。
5. 以原始 `DateTime` 排序，保留微秒；不按格式化字串或分鐘排序。
6. 時間相同時以事件 `id` 為第二鍵；沒有 id 的測試／預覽資料以輸入位置為第二鍵。
7. 所有重排處共用同一個 comparator；widget 內不得再只按日期重排。
8. 不因「日期相同」「分數相同」「profile 相同」刪資料；只有同 id 才是同一筆。
9. 主數字、平均線、圖點、日期、所選資料必須來自同一份視窗。

`HeatTrendPoint` 新增可選 `String? eventId`；`HeatTrendSummary.fromPoints` 保留「最多 7 筆」責任並加上穩定排序。

### 4.2 x、y 軸

| 項目 | 規格 |
|---|---|
| 0 筆 | 空態，不建 `LineChart` |
| 1 筆 | 單點態，不建虛構連線 |
| 2–7 筆 | 第 i 筆 x = i（0 起） |
| x 範圍 | `minX = -0.5`、`maxX = N - 0.5` |
| 練習 y | 0–100，刻度 0/20/40/60/80/100 |
| 分析 y | 0–90，刻度 0/30/60/90 |
| 連線 | `isCurved: false`，線寬 2.5 |
| 資料變動動畫 | `LineChart.duration` 設 `Duration.zero`，避免換人或視窗移動時舊點被插值成另一筆 |
| 外框 | 保留 `LiquidMotionFrame`，遵守既有 reduced-motion／TickerMode 行為 |

這是紀錄順序軸：相鄰兩點可能隔 5 分鐘也可能隔 10 天，線的斜率不叫升溫速度。

新增 `report_line_chart_axes.dart`：責任限於序數座標、合法 index 判斷、日期標籤配置。接收已整理好的 2–7 筆；不取視窗、不碰 provider、不留 `normalized()`。

`getTitlesWidget` 的 value 可能含邊界值：先確認與最近整數距離 < 1e-6，再確認 `0 <= index < N`，才查表。

### 4.3 日期與時區

- 排序用絕對時間；顯示前 `toLocal()`。
- 日期分組用本地 `year/month/day`。
- 同本地日期最多一個底部標籤；一天多筆仍是多個點。
- 同年底部 `M/dd`，跨年 `yy/M/dd`；資料區同年 `M/dd HH:mm`，跨年 `yyyy/M/dd HH:mm`。
- 同分鐘的點靠「本圖第 N 筆」區別。
- 換時區後標籤可變，事件數與排序不變；不回寫 `createdAt`。

### 4.4 日期標籤防重疊

1. 按本地日期分組，各組第一個點為候選；最後一組改用最後一個點。全部同一天只留第一點。
2. 在 `LayoutBuilder` 取得 plot 寬度後，用 `TextPainter` 搭配 `MediaQuery.textScalerOf(context)` 量測候選文字，一次算完。
3. 標籤置中於對應 x；超出左右邊界時移入 plot，量測與繪製使用同一套修正。
4. 優先保留最早、最新；其他候選按時間加入，與已保留者至少相隔 8 logical px，總數 ≤ 5。
5. 最早／最新都放不下時，底部不塞日期，改在圖註旁以可換行文字顯示日期範圍。
6. fl_chart bottom `interval: 1`，只對已選 index 回文字。

驗收是「沒有重疊、沒有編造日期」，不是固定出現五個。

---

## 5. 視覺與互動

### 5.1 練習圖五段背景

沿用 `practiceTemperatureBandForScore` 與 `practiceTemperatureColor`（`practice_temperature_style.dart:12-35`）。

| 分數 | band | 白話標籤（新增） | 背景範圍 | 取色分數 |
|---|---|---|---|---|
| 0–20 | frozen | 很冷 | y 0–20 | 10 |
| 21–40 | cold | 偏冷 | y 20–40 | 30 |
| 41–60 | neutral | 普通 | y 40–60 | 50 |
| 61–80 | warm | 熱絡 | y 60–80 | 70 |
| 81–100 | hot | 很熱絡 | y 80–100 | 90 |

- `RangeAnnotations` 建五個連續 `HorizontalRangeAnnotation`；分類是整數規則，背景是連續座標，不留 20–21 空隙。
- alpha 初始 0.06，實測後可到 0.08；不加亮光、漸層、陰影。
- 主線品牌紫；每點依自己分數取色，不讓線分段變色。
- 一般點半徑 3.5；最新點半徑 5、白邊 2；所選點加外圈並由下方文字說明。
- 白話標籤新增共用 helper 放 `practice_temperature_style.dart`，不在多處各建對照表。
- 歷史事件沒存 band，依分數映射；不把 `relationshipStageLabel` 當 band。
- 不靠顏色單獨傳意：資料區同時顯示數字與文字。

### 5.2 投入度圖

橘色主線與點，y 上限 90；不套溫度五段；移除填色與 overlay；保留平均虛線；平均線靠近資料點時，文字可移到卡片圖例。

### 5.3 邊界、尺寸與動態

- 圖區與標題、圖註、選取資料分開排版；文字高度不計入圖區固定高。
- chart box 預設 200 logical px；大字級可增高，不縮字。
- 左軸寬 = 最寬刻度實際寬 + 8；底軸高 = 標籤實際高 + 12。不沿用 overlay 的硬編碼 padding。
- `FlClipData.none()`，chart box 外上下各留 ≥ 8 px；端點圓圈不能被削成半圓。
- reduced motion 開啟後無流光、無插值。
- 視窗移動時保留所選 event id；離開視窗則選最新。切換對象直接選新對象最新。
- 所選狀態以 event id 為主，`spotIndex` 是當次衍生值。

---

## 6. A 階段工程規格

### 6.1 介面

`HeatTrendChart` 改為自行從 points 建 summary；呼叫端不再傳 `averageScore` / `scoreDelta` / `sampleCount`：

```dart
HeatTrendChart(
  trendPoints: subjectPoints,
  subjectId: selectedSubject,
  contextLabel: selectedSubjectName,
  emptyMessage: '尚無這位對象的分析紀錄',
)
```

`subjectId` 用於辨識切換，不以顯示名稱當身分。`PracticeTemperatureChart` 同樣自建 summary。

### 6.2 修改檔案

| 檔案 | 修改 |
|---|---|
| `lib/features/report/domain/entities/report_models.dart` | `HeatTrendPoint.eventId`；穩定排序 comparator |
| `lib/features/report/data/services/report_data_service.dart` | 事件 id 映射；練習分數 0–100 檢查；修正「跨對象斜率就是成長」的註解（`:229-231`） |
| `lib/features/report/presentation/widgets/report_line_chart_axes.dart` | 新增 |
| `lib/features/report/presentation/widgets/practice_temperature_chart.dart` | 直線、色帶、選取資料、五狀態文案、移除差值與 overlay |
| `lib/features/report/presentation/widgets/heat_trend_chart.dart` | 序數軸、內部 summary、選取資料、移除 overlay 與填色 |
| `lib/features/report/presentation/screens/my_report_screen.dart` | 區塊文案（`:162-163`）；新 chart 參數 |
| `lib/features/practice_chat/presentation/widgets/practice_temperature_style.dart` | 新增 band 白話 label helper |

`trend_flow_overlay.dart`：兩張圖移除引用後，lib 內無其他消費者（已 grep：只剩 `test/helpers/motion_free_app.dart` 與其專用測試）。在同一 PR 刪除死碼與 `trend_flow_overlay_test.dart`，並更新 `motion_free_app.dart`。不為通過舊測試保留不可見的 overlay。

本階段不改 Hive、AI 回覆、額度、付費牆、Edge。

---

## 7. B 階段工程規格

### 7.1 欄位

| Entity | 欄位 | 型別 | HiveField | 定義 |
|---|---|---|---|---|
| AnalysisHistoryEvent | practiceDifficulty | String? | 14 | 本輪已解析的 `easy / normal / challenge`；不存 `random` |
| AnalysisHistoryEvent | aiReplyCount | int? | 15 | 本輪成功接受的 AI 回覆次數（`state.aiReplyCount`），非 messages 長度 |
| AnalysisHistoryEvent | practiceMode | String? | 16 | `beginner / game` |
| AnalysisHistoryEvent | practiceSessionId | String? | 17 | 當次 session id |

序號對本次核對有效；開工前若 `main` 已新增欄位，先重新確認。不改 `PracticeSession`、`PracticeChatState`、`PracticeDrawDraft`。不加 `baselineScore` / `latestGain` / `warmOrHotCount`。

### 7.2 寫入與去重

1. 維持現有 generation 與 session guard（`_isStaleDebrief`）。
2. 用當時捕捉的 `completedState` 組事件；不在 await 後讀 live state。
3. append 位置移到 `_persist()` 之後、`confirmDebriefPersisted` 之前；append 自己 catch，不影響後續確認與清理，也不改 replay key 退休規則。
4. 事件 id 固定 `practice:<sessionId>`；repository `box.put(id)` 天然覆寫。
5. `createdAt = DateTime.now()`（首次寫入即最終值；同場二次寫入路徑不存在，見 1.2）。
6. 只寫 assisted 模式且溫度 0–100 的局；standard 不因補欄位而產生假事件。
7. `history == null` 或 append 失敗，不得阻斷收操、不重扣額度、不讓拆解卡消失。

這是「同一場再寫一次也不多一筆」的保證，不是「程式中斷絕不漏記」。不新增背景補寫、啟動掃描或 outbox。

### 7.3 複製路徑

`AnalysisHistoryEvent` 寬鬆建構子、`practice` factory、`withPartnerId` 都帶新欄位；`analyze` factory 維持 null。

### 7.4 報告讀取模型

`HeatTrendPoint` 加 `PracticeRecordContext? practiceContext`（難度、模式、輪次、AI 回覆數）。`practiceTemperaturePoints` 只從事件建 context，不 join session、不從目前偏好反推。`practiceDifficultyLabel`（`practice_profile.dart:83-89`）對未知值回「一般」，讀舊事件前先確認是三種合法值之一，否則顯示未知。

### 7.5 修改檔案

| 檔案 | 修改 |
|---|---|
| `lib/features/analysis_history/domain/entities/analysis_history_event.dart` | 欄位 14–17 與全部建構／複製路徑 |
| `lib/features/analysis_history/domain/entities/analysis_history_event.g.dart` | generator 產出；`writeByte(14)` → 18 |
| `lib/features/practice_chat/data/providers/practice_chat_providers.dart` | `_recordPracticeHistoryEvent` 補欄位、固定 id、呼叫位置前移 |
| `lib/features/report/domain/entities/report_models.dart` | `PracticeRecordContext` |
| `lib/features/report/data/services/report_data_service.dart` | context 映射與未知值 |
| `lib/features/report/presentation/widgets/practice_temperature_chart.dart` | 所選資料的條件行 |

typeId 23/24/25 不改。跑 `dart run build_runner build --delete-conflicting-outputs`，不手改 `.g.dart`；無新 adapter 類別，registrar 預期不變，仍檢查實際 diff。

---

## 8. 舊資料、錯誤資料與回退

| 情境 | 行為 |
|---|---|
| 舊事件只有合法終溫 | 照常畫點 |
| 舊事件無難度／模式／回覆數 | 條件顯示未知；不排除、不猜值 |
| `temperatureScore == null` | 不入圖 |
| 溫度超出 0–100 | 不入圖、不算平均、不回寫；留開發診斷 |
| 未知的模式／難度字串 | 不 crash、不映射成「一般」；顯示未記錄 |
| 同分鐘、同 timestamp | 不合併，各佔一格 |
| 舊隨機 UUID 事件 | 原樣保留，不與新 id 模糊去重 |
| session 被 5 段政策刪除 | 已寫入的分數與條件仍可顯示 |
| 超過 500 筆修剪 | 遵守既有政策，不宣稱終身紀錄 |
| 資料被清除 | 空態，不從 session 補回 |

回退：A、C 還原 UI／讀取邏輯即可。B 若舊版本重新保存事件可能丟掉新欄位，優先向前修正或停用 metadata 顯示，不以清空 Hive 回退。

---

## 9. C 階段：整體摘要改為現況

| 位置 | 調整 |
|---|---|
| 主標 | 目前的對話概況 |
| 補充 | 整理各段對話最近一次有效分析；要看前後變化，請往下選一位對象。 |
| 指標 1 | 對話平均投入（沿用） |
| 指標 2 | 原「前後趨勢」改「有效對話」，值為 `totalConversations` |
| 指標 3 | 常見階段（沿用） |
| 方向 badge | 移除 `_DirectionBadge` |
| 自動評語 | 移除依 `scoreDelta` 的回升／保守／穩定 |
| Semantics label | 同步改，不再朗讀上升／下降 |

`ReportOverviewCard` 不再收 `scoreDelta`；`ReportData.scoreDelta` 與計算保留（`safe_batch_proof_test.dart` 等仍建構它），移除 domain 欄位不是本版門檻。數的是對話，不改稱「N 位對象」。

C 需 Eric 在實作前確認；不影響 A 的工程規格完成。

---

## 10. 為何不做「升溫幅度」

| 範例 | 正確解讀 | 錯誤算法 |
|---|---|---|
| 一般第一輪 28 → 55 | 本輪 +27 | — |
| 續同一位第二輪沿用 55，結束 61 | 本輪 +6 | 61 − 28 = 33，把上一輪成果重算 |
| 真實起點 95、delta +8、結束 clamp 100 | 起點 95 | 100 − 8 反推成 92 |

第二例由 `continueWithSamePartner` 支持（`practice_chat_providers.dart:1741-1744`）；第三例由 `applyTemperatureDelta` 先 clamp delta 再 clamp score 支持（`temperature.ts:286-297`）。server 起點還有 ledger > 同 thread > client seed > 難度預設的優先序（`learning_seed.ts:5-6`），手機看到的開場數字不一定是 server 採用的起點。

難度倍率（easy 1.25/0.75、challenge 0.7/1.3）實際接進判分（`handler.ts:1492` → `temperature.ts:355-358`），Game 另有 hint 下限與 FSM 條件。沒有「減起點」或「除以回覆數」的公式能消除差異。

未來要顯示「本輪溫度變化」的前提：server 在本輪第一個成功回合保存實際起點並回傳；client 能分辨「server 確認」與「本機預設」；隨 session 與 history 保存；加計分規則版本；即使有了也只叫「本輪溫度變化」，不叫能力成長。這需要另開 Edge 規格，不是本次 A/B/C 的前置。

---

## 11. 驗收矩陣（實作時的規格，非本次已執行結果）

### 11.1 A：資料與座標

| 編號 | 輸入 | 結果 |
|---|---|---|
| A01 | 同日 09:00、09:05、09:10 三筆 | x = 0/1/2，日期只出現一次 |
| A02 | 同分鐘 09:00:01/02/03 | 三個獨立點，保留秒序 |
| A03 | 三個相同 timestamp、不同 id、打亂輸入 | 每次同 id 順序，不丟筆 |
| A04 | 同日 95、50、30、8 | 等距直線；無過衝、無第二條線；最新 8，無退步差值 |
| A05 | 8 筆遞增 | 只用後 7 筆，x 重編 0–6，數字與所選一致 |
| A06 | 輸入反序 | 排序後正確，不改原清單 |
| A07 | 同對象 30、60、90 | 平均 60、較上次 +30、虛線 60 |
| A08 | 分析 100、50 | 成 90、50；平均 70、較上次 −40；不二次校準 |
| A09 | 練習 0 與 100 | 保留、端點圓完整 |
| A10 | 練習 null、−1、101、40 | 只畫 40；原事件不變 |
| A11 | 20/21/40/41/60/61/80/81 | band 邊界正確；warm 從 61 起 |
| A12 | 混入 practice 或切換對象 | 嚴格按來源與 scope 隔離 |
| A13 | 同 UTC 日、本地跨日 | 依顯示時區分組；總數與排序不變 |
| A14 | 12/31 → 1/01 | 年份可辨、無重複誤判 |
| A15 | axes 查 −0.5、1.2、N−0.5 | 不生冒牌日期、不越界 |

時區案例用明確 fixture 或可注入的轉換，不依賴 CI 主機時區。

### 11.2 A：畫面、觸控、無障礙

| 編號 | 情境 | 驗收 |
|---|---|---|
| U01 | 320/390/430 pt × 1.0/1.4 字級 | 不溢出、不重疊；不用 FittedBox 縮字 |
| U02 | 0/1/2/7 筆 | 空態無假分數；單點無假線 |
| U03 | 七筆跨七天、跨年、長對象名 | 日期依量測減少；分數與資料區可讀 |
| U04 | 點第一筆／最高／最低 | 下方時間、數字、band 對應同一事件 |
| U05 | 點舊點後新增一筆 | 仍在視窗保留同 id；移出選最新 |
| U06 | 對象 A 切 B | 所選切到 B 最新，無 A 殘留或插值 |
| U07 | 平均線近資料點 | 不遮點；文字可移圖例 |
| U08 | VoiceOver、上一筆／下一筆 | 可依序讀出；邊界停用 |
| U09 | reduced motion | 無流光、無插值；測試收斂 |
| U10 | 只有練習或只有歷史 | 報告仍顯示，不退回全空 |
| U11 | 有選擇器但無有效分析 | 該對象卡空態，無外部平均冒充 |

五段背景測試要驗邊界完整、無 20–21 空隙、label 對應，不只 `length == 5`。視覺測試除產 PNG 還需人眼檢視。

### 11.3 B：保存、去重、相容

| 編號 | 情境 | 驗收 |
|---|---|---|
| B01 | beginner 一輪完成 | 一筆，帶難度、模式、回覆數、roundIndex、session id |
| B02 | game 一輪完成 | mode 為 game |
| B03 | standard 完成 | 不建溫度點 |
| B04 | random 偏好解析後開局 | 存解析後的難度，不存 random |
| B05 | 同 session append 重做兩次 | repository 只一筆 |
| B06 | 續同一位第二輪 | 新 id、roundIndex 2、回覆數只計第二輪；無 `終溫 − 28` |
| B07 | await 中切換，舊 debrief 晚回 | 過期結果不寫；已落盤的舊結果只寫自己 id |
| B08 | 落盤後 append 丟錯 | 拆解卡保留、確認流程照常、不改額度 |
| B09 | `withPartnerId` / 寬鬆建構子 | 新欄位不遺失 |
| B10 | 舊 adapter 寫檔，新 adapter 開 | 舊欄位保留，新欄位 null，無 crash |
| B11 | 新資料關箱重開 | 四欄位 round-trip 一致 |
| B12 | 舊 reader 讀新資料並重寫 | 記錄 metadata 是否丟失，回退說明符合實況 |
| B13 | session 被修剪但 history 保留 | 報告仍可讀，不依賴 join |
| B14 | 清除 history 重進頁 | 真正空態 |
| B15 | 舊事件缺全部 metadata | 點可見；無錯誤「一般」「新手」或 0 回覆 |

去重主保證以真實 Hive repository 測試驗證；in-memory helper 已模擬 id 覆寫（`memory_analysis_history_repository.dart:11-14`），可用於 controller 測試。

### 11.4 C

- 不同對象、不同更新時間的快照輸入 → 不再出現整體回升／保守。
- 單一對象卡仍可顯示自己的「較上次」。
- 「有效對話」= 有效快照數；只有一段對話時不虛構趨勢。

---

## 12. 測試檔與執行順序

### 12.1 對照

| 測試檔 | 守住的結果 |
|---|---|
| `test/unit/features/report/report_line_chart_axes_test.dart`（新） | 序數、日期候選、非整數 index、量測後防碰撞 |
| `test/unit/features/report/heat_trend_summary_test.dart` | 七筆視窗、同 timestamp 穩定排序、平均與差值 |
| `test/unit/features/report/report_data_service_history_test.dart` | scope 隔離、id/context 映射、合法分數 |
| `test/widget/features/report/practice_temperature_chart_test.dart` | `:31` 標題、`:33-36` x 改 `[0.0, 1.0]`、`:52` 單點文案；新增直線、無 overlay、色帶、點選 |
| `test/widget/features/report/heat_trend_chart_test.dart` | `:50-52` x 改 `[0.0, 1.0, 2.0]`；新介面、內部 summary |
| `test/widget/features/report/chart_text_scale_test.dart` | 既有空態／單點，加多點、日期、詳情、長標題 |
| `test/widget/features/report/my_report_history_only_test.dart` | 只有歷史／只有練習仍可看 |
| `test/widget/features/report/my_report_screen_test.dart` | `:281` `起點 50 · 6/01`、`:328` `練習溫度成長` 改新文案；對象切換；C 摘要 |
| `test/widget/features/report/trend_flow_overlay_test.dart` | 隨 overlay 刪除 |
| `test/helpers/motion_free_app.dart` | 移除 overlay 引用 |
| `test/visual_proof/liquid_motion_report_capture_test.dart` | `:33-34, 139-140` 舊參數改新介面；改驗修正後兩圖 |
| `test/visual_proof/report_insight_proof_test.dart` | 新 chart 介面與 C 摘要外觀 |
| `test/unit/features/analysis_history/domain/entities/analysis_history_event_test.dart` | 欄位 14–17 建構與複製；analyze 不補 practice 欄位 |
| `test/unit/features/analysis_history/data/repositories/analysis_history_repository_impl_test.dart` | 同 id 覆寫、重開箱、舊格式、保留政策 |
| `test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart` | 模式、續玩、過期 debrief、append 失敗不影響主流程、固定 id |
| `test/unit/features/practice_chat/presentation/widgets/practice_temperature_style_test.dart` | band 邊界與白話 label |

### 12.2 執行順序

實作前依 `.agent/environment.json` 用環境 resolver／doctor 確認 WSL 與 Flutter 版本。本文未在目前環境跑 Flutter。

A：

```bash
flutter test test/unit/features/report
flutter test test/widget/features/report
flutter test test/unit/features/practice_chat/presentation/widgets/practice_temperature_style_test.dart
flutter test test/visual_proof/liquid_motion_report_capture_test.dart
flutter test test/visual_proof/report_insight_proof_test.dart
flutter analyze
```

B：

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/unit/features/analysis_history
flutter test test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart
flutter test test/unit/features/report
flutter test test/widget/features/report
flutter analyze
```

先用最小失敗案例確認修正，再跑該 PR 相關測試與必要 CI。實機驗收由 Eric 在 iPhone build 進行；自動測試與截圖不取代觸控、系統字級、VoiceOver 驗收。

---

## 13. 分 PR、依賴、回退

| PR | 一句話目的 | 依賴 | 完成條件 |
|---|---|---|---|
| A | 讓兩張報告圖能準確閱讀每筆紀錄 | Eric 確認第 3 節文案 | A/U 案例與相關測試；無流光分岔；無成長宣稱 |
| B | 讓新練習紀錄保存條件且同場不重複 | A 的讀取模型 | B 案例；真實 Hive 升級／重開驗證；收操流程不受影響 |
| C | 讓整體摘要只描述現況 | 與 A、B 無核心依賴；同改 screen 需處理衝突 | 11.4；畫面與無障礙文字一致 |

B 涉及本機使用者資料與練習收操流程，依 AGENTS.md 屬高風險區，需 Codex 與 Claude Code 交叉檢查。

Eric 需確認的三項：

1. 練習圖改名「練習溫度紀錄」，主數字保留最近結束溫度，移除較上次紅綠差值。
2. 日期按紀錄順序等距排列，圖下方選取資料；保留品牌紫／橘與既有外框。
3. 整體摘要移除跨快照方向判斷，改現況。

回退：A、C 還原 UI；B 兼容問題時保留原資料、向前修正或停用 metadata 顯示。不因圖表問題改 quota、billing、AI 判分、production schema。

---

## 14. 完成定義與本次已完成範圍

整份規格完成時同時成立：

- 同日、同分鐘、相同 timestamp 的不同事件可分開查看。
- 圖、主數字、平均線、日期、所選資料用同一份視窗。
- 無流光、無過衝、無日期重疊、無端點半圓。
- 文案不把不同條件的終溫叫能力成長；單點不叫起點。
- 新事件有模式、難度、AI 回覆數、session id；舊事件可讀。
- 同場不新增第二點；記錄失敗不阻擋拆解卡。
- 整體摘要不以跨對話快照推斷方向。
- 自動測試、必要 CI、視覺檢視、Eric iPhone 驗收都有紀錄。

本次已完成：核對送審稿全部程式行為主張（第 1.1 節）；修正其設計四處（第 1.2 節）；抓取 fl_chart 0.70.2 原始碼確認 API；整合為本規格。

本次未執行：產品程式修改、adapter 生成、Flutter 測試／analyze、App 重現、實機驗收、commit、push、PR、Edge 或資料庫部署。

---

## 15. 證據索引（本地路徑，對 `3134c51` 工作樹核對；`origin/main c80bdd7` 對這些檔案無差異）

| 編號 | 檔案 | 用途 |
|---|---|---|
| E01 | `lib/features/report/presentation/widgets/practice_temperature_chart.dart` | 時間 x（205-206）、曲線（309-310）、overlay（227-239）、填色（328-338）、clip（246）、差值（371-394） |
| E02 | `lib/features/report/presentation/widgets/heat_trend_chart.dart` | 同類畫法（287-288, 312-324, 372-374）、外部統計參數（20-36） |
| E03 | `lib/features/report/presentation/widgets/trend_flow_overlay.dart` | 自算路徑（250-275）、`inflate(7)` 裁切（227） |
| E04 | `lib/features/report/domain/entities/report_models.dart` | 排序（36-37）、七筆視窗（38-40）、差值（51-54） |
| E05 | `lib/features/report/data/services/report_data_service.dart` | 前後半平均（48-63）、練習點（232-246） |
| E06 | `lib/features/practice_chat/data/providers/practice_chat_providers.dart` | 續玩（1715-1758）、`canDebrief`（363-369）、debrief 接受流程（2456-2483）、事件寫入（2781-2803）、state 欄位（179, 238） |
| E07 | `lib/features/analysis_history/domain/entities/analysis_history_event.dart`、`analysis_history_event.g.dart`、`lib/features/analysis_history/data/repositories/analysis_history_repository_impl.dart` | HiveField 0–13、`box.put` 覆寫（49-52）、500 筆修剪（95-107） |
| E08 | `lib/features/practice_chat/presentation/widgets/practice_temperature_style.dart` | band 邊界與色票（12-35） |
| E09 | `supabase/functions/practice-chat/practice_persona.ts`（397-419）、`temperature.ts`（184-186, 217-235, 286-297, 343-358）、`handler.ts`（355-369, 1492, 2411） | 起始值、倍率接線、clamp 順序、Game 條件 |
| E10 | `supabase/functions/practice-chat/learning_seed.ts`（5-6, 28-60）、`lib/features/practice_chat/domain/entities/practice_temperature.dart` | seed 優先序；client 無每輪權威起點欄位 |
| E11 | `lib/features/practice_chat/domain/entities/practice_session.dart`（typeId 23，HiveField ≤ 30）、`lib/features/practice_chat/data/repositories/practice_session_repository.dart`（14） | 欄位上限；5 段 thread 保留 |
| E12 | `lib/features/report/presentation/widgets/report_overview_card.dart`、`lib/features/report/presentation/screens/my_report_screen.dart`、`lib/features/report/data/providers/report_providers.dart` | 方向文案、兩路資料、選人 |
| E13 | `lib/features/practice_chat/domain/entities/practice_learning_mode.dart`、`practice_profile.dart`（83-100） | assisted 模式集合；難度 label fallback 與起始溫 |
| E14 | `test/widget/features/report/practice_temperature_chart_test.dart`（31, 33-36, 52）、`heat_trend_chart_test.dart`（50-52）、`my_report_screen_test.dart`（281, 328）、`chart_text_scale_test.dart`、`test/visual_proof/liquid_motion_report_capture_test.dart`（33-34, 139-140）、`test/helpers/memory_analysis_history_repository.dart`（11-14） | 受影響斷言與 helper |
| E15 | fl_chart 0.70.2 `lib/src/chart/base/axis_chart/axis_chart_data.dart`（858, 910）、`lib/src/chart/line_chart/line_chart_data.dart`（59, 84, 239） | `RangeAnnotations`、`HorizontalRangeAnnotation`、`FlClipData.none`、`handleBuiltInTouches`、`preventCurveOverShooting` |
| E16 | `pubspec.lock` | fl_chart 0.70.2、hive_ce 2.19.3、hive_ce_generator 1.11.3 |
| E17 | `AGENTS.md`、`.agent/environment.json` | 授權區別、高風險交叉審查、環境與實機驗收 |
| E18 | `lib/features/analysis/domain/entities/enthusiasm_level.dart`（10, 14） | clamp 與 0.9 校準是兩個函式 |

---

## 16. PR-A 實作註記（2026-09-19）

實作與第 4–6 節一致，另有四項落地決定：

- **共用本體** `report_ordinal_line_chart.dart`：兩張圖的序數軸、直線、點色、選取狀態、圖下方資料區都在這一個 StatefulWidget；`practice_temperature_chart.dart` 與 `heat_trend_chart.dart` 只負責標題、文案、y 範圍、色帶／平均線與資料行文字。
- **點擊命中範圍**：fl_chart 折線圖預設只算水平距離，`touchSpotThreshold` 設 40 px，整個欄位都能選中該筆，不需精準點到 3.5–6 px 的圓點。
- **平均線標籤**：視覺證據顯示圖內「這 N 次平均」會壓到靠近平均的最後一點（第 5.2 節預留的情況），改為固定放在圖註「虛線是這 N 次平均。…」，圖內不放標籤。
- **可見上限先於摘要**：`HeatTrendChart` 先把每筆分數 clamp 到 90 再建 `HeatTrendSummary`，平均、較上次、圖點、資料區來自同一份已 clamp 的視窗（A08）。

`trend_flow_overlay.dart` 與其測試已刪除；`test/helpers/motion_free_app.dart` 只改註解。視覺證據輸出改名 `practice_temperature_record.png`、`engagement_trend_ordinal.png`，capture 高度提到 560（圖區 200 + 圖註 + 資料區）。

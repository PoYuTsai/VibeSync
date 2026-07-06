# 案2：分析事件歷史表設計（2026-07-06，Eric 四段逐段確認通過）

> Roadmap 案2。拍板 A 案：報告頁熱度趨勢改「對象選擇器＋單對象時間序列（x 軸真日期）」，
> 另新增練習室溫度成長曲線。B（全域混排）／C（只改 x 軸）已捨棄。
> errorPattern 枚舉化動 Edge schema＝獨立成案，不入本案。

## 1. 資料模型

新 entity `AnalysisHistoryEvent`（typeId **24**）＋枚舉 `AnalysisHistoryKind`（typeId **25**，值 `analyze`/`practice`），
完全照抄 CoachingOutcomeEvent 三層模式，落在 `lib/features/analysis_history/`
（domain/entities、domain/repositories、data/repositories、data/providers）。

欄位（共用一張表，依 kind 部分為 null）：

| # | 欄位 | 型別 | 用途 |
|---|------|------|------|
| 0 | id | String | uuid |
| 1 | kind | AnalysisHistoryKind | analyze / practice |
| 2 | createdAt | DateTime | 事件時間（x 軸真日期來源）|
| 3 | conversationId | String? | analyze 用（hook 現場只有它，沒有 partnerId）|
| 4 | subjectName | String? | 對象名快照（選擇器顯示用，防改名/刪除後查不到）|
| 5 | enthusiasmScore | int? | analyze 熱度分 |
| 6 | gameStageLabel | String? | analyze 階段快照 |
| 7 | profileId | String? | practice 用（practice_girl_NNN）|
| 8 | roundIndex | int? | practice 輪次 1–3 |
| 9 | temperatureScore | int? | practice 溫度 |
| 10 | familiarityScore | int? | practice 熟悉度 |
| 11 | relationshipStageLabel | String? | practice 關係階段 |

- Box 名 `analysis_history_events`，AES 加密開法照抄 `storage_service.dart:96-99`。
- 保留策略：append-only，寫入時超過 **500 筆刪最舊**。
- 本機 only，絕不上傳。
- 為何需要新表：`PracticeSession` 只留 5 段且同對象覆寫、`Conversation` 只有最新一筆分數，都留不住時間序列。

## 2. 寫入 hooks

**analyze 側**：掛在 `_persistLatestAnalysisSnapshot`（`analysis_screen.dart:1289-1319`）末尾。
呼叫端 `:891-896` 既有去重 gate（`lastAnalyzedMessageCount`＋snapshot JSON 比對，命中即 return），
掛在方法內自然繼承「同一次分析絕不重複記錄」，不另做冪等。
取值：`conversationId = widget.conversationId`、`subjectName = conv.name`、
`enthusiasmScore = result.enthusiasmScore`、`gameStageLabel = result.gameStage.current.name`。

**practice 側**：掛在 `_persist()`（`practice_chat_providers.dart:1249`）內、`PracticeSession` 存檔成功之後。
取值：`profileId = girl.profileId`、`roundIndex`、溫度三元組抄 state
（`temperatureScore`/`familiarityScore`/`relationshipStageLabel`，僅新手模式有值）。
**只在 `temperatureScore != null` 時寫事件**——非新手模式全 null，是畫不出來的空點。

**錯誤處理**：兩個 hook 皆 best-effort——try-catch 全包，失敗只 debugPrint 絕不 rethrow，
分析呈現與練習收操流程完全不受影響。不加 loading state、不 await 阻塞 UI 路徑。

**不做**：不回填舊資料（拿不到真時間點，硬造失真）；不動 Edge schema。

## 3. 報告頁 UI

**熱度趨勢卡改造**（A 案核心）：
- `report_data_service.dart`：熱度趨勢資料源從「Conversation 最新分數 × 7 筆」換成 analyze 事件表。
  新增「對象清單」（distinct conversationId＋subjectName，按最近事件排序）與
  「單對象時間序列」（該對象全部 enthusiasmScore 按 createdAt 升序）。
- UI 加對象選擇器（橫向 chip 列，預設最近分析過的對象）。
- `heat_trend_chart.dart`：x 軸序號→真日期——FlSpot x 用距首點天數，點距反映真實間隔；底部標籤沿用 M/dd。

**新增練習室溫度成長曲線**（第二張卡）：practice 事件的 `temperatureScore` 對 createdAt
**全域時間序列，不分對象混排**。理由：練習溫度量的是玩家本人的開場→升溫能力，每局從零開始，
跨對象看斜率才是成長曲線（與 analyze 側「混排＝雜訊」性質相反）。`familiarityScore` 不畫第二條線（YAGNI）。

**範圍收斂**：averageScore、scoreDelta、同名 comparisons、GameStage 階段分佈全部維持現行 Conversation 邏輯不動。

**空狀態**：所選對象事件 <2 筆、或 practice 事件全空 → 卡片顯示引導文案，不畫圖。

## 4. 測試、風險與批次

**測試**：
- Entity/repo 照抄 coaching_outcome 測試模式：append、超 500 剪枝、按 kind/conversationId 過濾。
- `report_data_service`：對象清單排序、單對象序列升序、<2 筆空狀態、practice 序列跳 null。
- hook：practice `_persist` 在 `temperatureScore == null` 不寫事件；analyze 側靠既有去重 gate 測試涵蓋。
- chart widget 測試更新 x 軸斷言（序號→日期差值）；動畫鐵則 pumpAndSettle 必收斂。

**風險與審查**：純新增 typeId 24/25＋新 box，無舊資料遷移；但動 Hive 註冊
（`storage_service.dart:32-114`＋`app_constants.dart`＋`hive_registrar.g.dart`）屬高風險區 → 完成後 Codex 雙審。
Edge/訂閱/quota 完全不碰。

**實作批次**（一 commit 一關注點）：
1. 批1：entity＋repo＋provider＋Hive 註冊＋兩個 hook（含測試）
2. 批2：report_data_service 改造＋對象選擇器＋x 軸真日期＋練習溫度卡（含測試）

真機體感驗證留 Eric dogfood（與案1批3/批4 同車）。

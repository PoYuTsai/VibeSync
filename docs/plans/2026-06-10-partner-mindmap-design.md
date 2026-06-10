# 對象作戰板（Partner Mind Map）設計文件

> 2026-06-10 brainstorm 定案（Eric 拍板 B / C / A）。實作排入測試期 feature queue，不插隊 P0/P1。

## 背景與動機

- Bruce 反饋：「我的報告」三張圖（熱度趨勢 / 對話比較 / 階段分佈）資訊感弱，但又是 UI 不可或缺的區塊。
- 提案：加入心智圖式知識整理，讓用戶看懂「每個對象目前的狀態 + 下一步」。範例鏈：`Vivi → 曖昧層 → 星座 → 維持神秘感`。
- 定位對照：VibeSync 差異化是「教練告訴你下一步」。現有圖表是「儀表板」，心智圖是「教練的作戰板」，後者更貼定位。

## 關鍵事實（查證結論）

1. **graphify（github.com/safishamsi/graphify）是 Claude Code 開發者 skill**（Python 3.10+ / 開發機執行），不可打包進 Flutter app。產品內不存在「整合 graphify」這個選項。
2. **資料已齊備、零 AI 邊際成本**：`analyze-chat` 分析快照（Hive `lastAnalysisSnapshotJson`）已含全部所需節點資料，渲染不需任何新 API 呼叫。

| 心智圖節點 | 既有資料來源 |
|---|---|
| 對象（根節點） | `Partner` + `PartnerAggregateView`（`partner_aggregates.dart`，跨對話聚合） |
| 關係階段 | `gameStage`（破冰/升溫/深入/連結/邀約）+ `currentGameStage` |
| 話題層 | `topicDepth`（事件層/個人層/曖昧層） |
| 興趣 / 特質 | `targetProfile.interests` / `traits`（已去重、各上限 8） |
| 下一步建議 | `gameStage.nextStep` + `strategy` |

## 已拍板決策

| # | 決策 | 選項 | 理由 |
|---|---|---|---|
| 1 | 圖的單位 | **B：每個對象一張圖** | 資料 partner-scoped、密度可控；全局圖留作未來 Essential 加值 |
| 2 | 入口 | **C：雙入口** | 對象詳情頁為主入口（資料的家）；報告頁底部加「對象作戰板」橫向卡片列當捷徑（救回報告頁的初衷） |
| 3 | 訂閱分層 | **A：dogfood 期免費全開** | 零邊際成本；先收 Eric/Bruce 目檢回饋；送審前再議 gating（屆時動訂閱區 → Codex 雙審） |

## 架構草案

```
PartnerAggregateView ──┐
gameStage / topicDepth ─┼─> MindMapBuilder（pure Dart，snapshot → 節點樹）
strategy / nextStep ────┘          │
                                   v
                       MindMapView（渲染層）
                       入口 1: partner detail 頁區塊
                       入口 2: my_report_screen 底部橫向卡片列 → push 全螢幕圖
```

- **節點 schema（第一版）**：根＝對象名；五條主枝＝`階段`、`話題層`、`興趣`、`特質`、`下一步`。`下一步` 枝視覺上加重（橘色強調），呼應「作戰板」定位。
- **渲染候選**：`graphview` package（BuchheimWalker 樹狀佈局）為首選；實作 session 先驗 package 維護狀況與 Flutter 3.x 相容性，不行就退回 `CustomPaint` 自繪（節點數 ≤ ~20，自繪可行）。
- **視覺**：沿用紫橘 brand + glass 元件語彙。**硬約束：報告頁動態 bokeh 背景絕不改。**

## 明確不做（YAGNI）

- ❌ 整合 graphify 進 app（不可行，見上）
- ❌ AI 即時生成圖譜（新 Edge Function / 新 token 成本）——既有快照衍生已夠
- ❌ 全局多對象總覽圖（未來 Essential 候選）
- ❌ 節點編輯 / 手動增刪知識點
- ❌ 訂閱 gating（送審前另案，走 Codex 雙審）

## graphify 的正確用法（選配，開發側）

可在開發機把幾份**匿名化**分析快照丟給 `/graphify`，觀察它聚出的分類結構，借鑑 taxonomy 來迭代節點 schema。目的是偷設計，不是整合。非阻塞項。

## 預估工程量

1.5–2 天：MindMapBuilder + tests（半天）、渲染層 + 佈局調試（1 天）、雙入口接線 + widget tests（半天）。佈局套件若退自繪則 +0.5 天。

## 風險

- `graphview` package 可能年久失修 → 實作前先驗，備案自繪。
- 分析快照缺欄位的舊對象（未跑過新版分析）→ 枝為空時顯示「再分析一次解鎖」空狀態，不能 crash。
- 報告頁加區塊不得影響既有三張圖與訂閱 gate 行為（`my_report_screen.dart` 有 gating 邏輯，動到要迴歸測試）。

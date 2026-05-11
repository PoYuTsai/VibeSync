# Tab 2「我的報告」+ 底部導航 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 新增底部 2 Tab 導航（首頁 / 我的報告），並建立「我的報告」頁面，包含熱度趨勢圖、對話比較長條圖、GAME 階段分佈圓環圖。

**Architecture:** 新增 `MainShell` widget 包裝底部 Tab 導航，Tab 1 為現有 HomeScreen，Tab 2 為新建 MyReportScreen。圖表使用 fl_chart 套件。數據從現有 Hive conversationsBox 讀取，不需新增儲存層。

**Tech Stack:** Flutter, Riverpod, fl_chart, GoRouter (ShellRoute), Hive CE

**Prototype 參考:** Claude Design 輸出的 3 頁 prototype（已確認）

---

### Task 1: 加入 fl_chart 依賴

**Files:**
- Modify: `pubspec.yaml`

**Step 1: 加入 fl_chart**

在 `pubspec.yaml` 的 `dependencies` 區塊加入：

```yaml
  # Charts
  fl_chart: ^0.70.2
```

**Step 2: 安裝依賴**

Run: `flutter pub get`
Expected: 成功安裝，無錯誤

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "[chore] 加入 fl_chart 圖表套件"
```

---

### Task 2: 建立 ReportDataService

**Files:**
- Create: `lib/features/report/data/services/report_data_service.dart`
- Create: `lib/features/report/domain/entities/report_models.dart`

**Step 1: 建立報告數據模型**

`lib/features/report/domain/entities/report_models.dart`:

```dart
/// 熱度趨勢數據點
class HeatTrendPoint {
  final DateTime date;
  final int score;
  final String conversationName;

  const HeatTrendPoint({
    required this.date,
    required this.score,
    required this.conversationName,
  });
}

/// 對話比較項目
class ConversationComparison {
  final String name;
  final int score;

  const ConversationComparison({
    required this.name,
    required this.score,
  });
}

/// 階段分佈項目
class StageDistribution {
  final String stageName;
  final int count;

  const StageDistribution({
    required this.stageName,
    required this.count,
  });
}

/// 完整報告數據
class ReportData {
  final List<HeatTrendPoint> trendPoints;
  final double averageScore;
  final double scoreDelta; // 比上期變化
  final List<ConversationComparison> comparisons;
  final List<StageDistribution> stageDistributions;
  final int totalConversations;

  const ReportData({
    required this.trendPoints,
    required this.averageScore,
    required this.scoreDelta,
    required this.comparisons,
    required this.stageDistributions,
    required this.totalConversations,
  });
}
```

**Step 2: 建立 ReportDataService**

`lib/features/report/data/services/report_data_service.dart`:

```dart
import '../../../conversation/domain/entities/conversation.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../domain/entities/report_models.dart';

class ReportDataService {
  /// 從對話列表生成報告數據
  ReportData generateReport(List<Conversation> conversations) {
    final withScores = conversations
        .where((c) => c.lastEnthusiasmScore != null)
        .toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

    // 熱度趨勢（最近 7 筆）
    final recent = withScores.length > 7
        ? withScores.sublist(withScores.length - 7)
        : withScores;

    final trendPoints = recent
        .map((c) => HeatTrendPoint(
              date: c.updatedAt,
              score: c.lastEnthusiasmScore!,
              conversationName: c.name,
            ))
        .toList();

    // 平均分數
    final avgScore = withScores.isEmpty
        ? 0.0
        : withScores
                .map((c) => c.lastEnthusiasmScore!)
                .reduce((a, b) => a + b) /
            withScores.length;

    // 分數變化（最近 7 筆 vs 之前 7 筆）
    double delta = 0;
    if (withScores.length >= 2) {
      final half = withScores.length ~/ 2;
      final olderAvg = withScores
              .sublist(0, half)
              .map((c) => c.lastEnthusiasmScore!)
              .reduce((a, b) => a + b) /
          half;
      final newerAvg = withScores
              .sublist(half)
              .map((c) => c.lastEnthusiasmScore!)
              .reduce((a, b) => a + b) /
          (withScores.length - half);
      delta = newerAvg - olderAvg;
    }

    // 對話比較（按分數排序）
    final comparisons = withScores
        .map((c) => ConversationComparison(
              name: c.name,
              score: c.lastEnthusiasmScore!,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // GAME 階段分佈
    final stageCounts = <String, int>{};
    for (final stage in GameStage.values) {
      stageCounts[stage.name] = 0;
    }
    for (final c in conversations) {
      final stageStr = c.currentGameStage ?? 'opening';
      stageCounts[stageStr] = (stageCounts[stageStr] ?? 0) + 1;
    }

    final stageDistributions = stageCounts.entries
        .where((e) => e.value > 0)
        .map((e) {
      final stage = GameStage.fromString(e.key);
      return StageDistribution(
        stageName: _stageShortLabel(stage),
        count: e.value,
      );
    }).toList();

    return ReportData(
      trendPoints: trendPoints,
      averageScore: avgScore,
      scoreDelta: delta,
      comparisons: comparisons,
      stageDistributions: stageDistributions,
      totalConversations: conversations.length,
    );
  }

  String _stageShortLabel(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return '打開';
      case GameStage.premise:
        return '前提';
      case GameStage.qualification:
        return '評估';
      case GameStage.narrative:
        return '敘事';
      case GameStage.close:
        return '收尾';
    }
  }
}
```

**Step 3: Commit**

```bash
git add lib/features/report/
git commit -m "[feat] 建立報告數據模型和 ReportDataService"
```

---

### Task 3: 建立報告 Provider

**Files:**
- Create: `lib/features/report/data/providers/report_providers.dart`

**Step 1: 建立 Provider**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../services/report_data_service.dart';
import '../../domain/entities/report_models.dart';

final reportDataServiceProvider = Provider<ReportDataService>((ref) {
  return ReportDataService();
});

final reportDataProvider = Provider<ReportData>((ref) {
  final conversations = ref.watch(conversationsProvider);
  final service = ref.watch(reportDataServiceProvider);
  return service.generateReport(conversations);
});
```

**Step 2: Commit**

```bash
git add lib/features/report/data/providers/report_providers.dart
git commit -m "[feat] 建立報告 Riverpod providers"
```

---

### Task 4: 建立熱度趨勢折線圖 Widget

**Files:**
- Create: `lib/features/report/presentation/widgets/heat_trend_chart.dart`

**Step 1: 建立折線圖**

用 fl_chart 的 `LineChart` 建立，參考 prototype：
- X 軸 = 日期（最近 7 次分析）
- Y 軸 = 0-100 分
- 珊瑚漸層線條 + 10% 透明度區域填充
- 頂部顯示「熱度趨勢」標題 + 「平均 XX ↑+YY」
- 右上角月份 badge

**關鍵設計細節（對照 prototype）：**
- 標題：「熱度趨勢」，glassTextPrimary
- 平均分數大字：AppTypography.headlineMedium
- 趨勢 delta 用綠色（正）或紅色（負）
- 折線顏色：AppColors.ctaStart → AppColors.ctaEnd
- 區域填充：ctaStart with 10% opacity
- 數據點圓點：白色填充 + 珊瑚邊框
- 外層用 GlassmorphicContainer 包裝

**Step 2: Commit**

```bash
git add lib/features/report/presentation/widgets/heat_trend_chart.dart
git commit -m "[feat] 建立熱度趨勢折線圖 widget"
```

---

### Task 5: 建立對話比較長條圖 Widget

**Files:**
- Create: `lib/features/report/presentation/widgets/conversation_comparison_chart.dart`

**Step 1: 建立水平長條圖**

用 fl_chart 的 `BarChart`（水平）建立，參考 prototype：
- 左側顯示對話名稱
- 右側顯示分數數字
- 長條顏色依熱度等級配色：
  - 0-30: AppColors.cold (藍)
  - 31-60: AppColors.warm (暖橘)
  - 61-80: AppColors.hot (紅)
  - 81-100: AppColors.veryHot (粉紅)
- 按分數高到低排序
- 最多顯示 4-5 條
- 標題：「對話比較」
- 外層用 GlassmorphicContainer 包裝

**Step 2: Commit**

```bash
git add lib/features/report/presentation/widgets/conversation_comparison_chart.dart
git commit -m "[feat] 建立對話比較長條圖 widget"
```

---

### Task 6: 建立 GAME 階段分佈圓環圖 Widget

**Files:**
- Create: `lib/features/report/presentation/widgets/stage_distribution_chart.dart`

**Step 1: 建立圓環圖**

用 fl_chart 的 `PieChart` 建立，參考 prototype：
- 圓環圖（donut style，center radius 留空顯示總數）
- 中心文字：「12 對話」（動態數字）
- 右側圖例：每個階段名稱 + 數量 + 色點
- 階段配色（從暖到冷）：
  - 打開: AppColors.bokehYellow
  - 前提: AppColors.bokehCoral
  - 評估: AppColors.ctaStart
  - 敘事: AppColors.hot
  - 收尾: AppColors.veryHot
- 標題：「階段分佈」
- 外層用 GlassmorphicContainer 包裝

**Step 2: Commit**

```bash
git add lib/features/report/presentation/widgets/stage_distribution_chart.dart
git commit -m "[feat] 建立 GAME 階段分佈圓環圖 widget"
```

---

### Task 7: 建立 MyReportScreen

**Files:**
- Create: `lib/features/report/presentation/screens/my_report_screen.dart`

**Step 1: 組合三個圖表**

參考 prototype 佈局：
- 頂部標題區：
  - 小字「我的報告」（珊瑚色）
  - 大字「最近 **七次** 的節奏」（白色，七次用珊瑚色強調）
- 垂直滾動列表：
  1. HeatTrendChart（熱度趨勢）
  2. ConversationComparisonChart（對話比較）
  3. StageDistributionChart（階段分佈）
- 每個區塊間距 16px
- 水平 padding 16px
- 使用 GradientBackground 背景
- 無 AppBar（標題直接在 body 內）

**空狀態處理：** 如果沒有任何分析過的對話，顯示引導文字

**Step 2: Commit**

```bash
git add lib/features/report/presentation/screens/my_report_screen.dart
git commit -m "[feat] 建立我的報告頁面，組合三個圖表"
```

---

### Task 8: 建立 MainShell + 底部 Tab 導航

**Files:**
- Create: `lib/app/main_shell.dart`
- Modify: `lib/app/routes.dart`

**Step 1: 建立 MainShell**

`lib/app/main_shell.dart`:

底部導航 2 Tab：
- Tab 1: 首頁 icon (Icons.home_outlined / Icons.home) + 「首頁」
- Tab 2: 報告 icon (Icons.bar_chart_outlined / Icons.bar_chart) + 「我的報告」

設計細節（對照 prototype）：
- 底部導航背景：深紫色（AppColors.backgroundGradientStart）帶微透明
- 選中 Tab：珊瑚漸層 pill 形狀背景 + 白色文字/icon
- 未選中 Tab：半透明文字/icon
- Tab 切換保持各 Tab 的 state（用 IndexedStack）

**Step 2: 更新 GoRouter**

修改 `lib/app/routes.dart`：
- `'/'` 路由改為指向 `MainShell`
- MainShell 內部管理 HomeScreen 和 MyReportScreen 的切換
- 其他路由（/new, /conversation/:id, /settings, /paywall）保持不變，從 MainShell 之上 push

**Step 3: 驗證**

Run: `flutter analyze`
Expected: 無錯誤

**Step 4: Commit**

```bash
git add lib/app/main_shell.dart lib/app/routes.dart
git commit -m "[feat] 建立底部 2 Tab 導航 (首頁/我的報告)"
```

---

### Task 9: 從 HomeScreen 移除 AppBar，適配 MainShell

**Files:**
- Modify: `lib/features/conversation/presentation/screens/home_screen.dart`

**Step 1: 調整 HomeScreen**

- 移除 Scaffold 的 AppBar（標題和 settings 按鈕移到 body 頂部或 MainShell 統一處理）
- 保留 GradientBackground
- 設定按鈕改為在 MainShell 的右上角統一放置
- FAB 保持不變

注意：HomeScreen 現在是 MainShell 的子 widget，不再獨立管理 AppBar。

**Step 2: 驗證**

Run: `flutter analyze`
Expected: 無錯誤

**Step 3: Commit**

```bash
git add lib/features/conversation/presentation/screens/home_screen.dart
git commit -m "[refactor] HomeScreen 適配 MainShell 底部導航"
```

---

### Task 10: 整合測試 + 視覺驗證

**Step 1: 執行靜態分析**

Run: `flutter analyze`
Expected: 無錯誤

**Step 2: 執行現有測試**

Run: `flutter test`
Expected: 全部通過（不能破壞現有功能）

**Step 3: 視覺驗證 checklist**

- [ ] 首頁 Tab 正常顯示對話列表
- [ ] 底部 Tab 切換流暢
- [ ] 我的報告頁三個圖表正確顯示
- [ ] FAB 按鈕在首頁 Tab 正常運作
- [ ] Settings 按鈕可正常進入設定頁
- [ ] 從首頁點對話可正常進入分析頁
- [ ] 分析頁返回後回到正確的 Tab
- [ ] 空狀態（無對話）顯示正確

**Step 4: Commit**

```bash
git add -A
git commit -m "[test] Tab 2 我的報告整合完成，靜態分析通過"
```

---

## 實作順序總結

| Task | 內容 | 預估 |
|------|------|------|
| 1 | 加入 fl_chart 依賴 | 1 min |
| 2 | ReportDataService + 數據模型 | 5 min |
| 3 | Report Provider | 2 min |
| 4 | 熱度趨勢折線圖 | 10 min |
| 5 | 對話比較長條圖 | 8 min |
| 6 | 階段分佈圓環圖 | 8 min |
| 7 | MyReportScreen 組合頁面 | 5 min |
| 8 | MainShell + 底部導航 + Router | 10 min |
| 9 | HomeScreen 適配 | 5 min |
| 10 | 整合測試 | 5 min |

**Total: ~60 min**

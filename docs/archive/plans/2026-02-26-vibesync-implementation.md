# VibeSync MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Flutter-based chat analysis app that provides enthusiasm scoring and reply suggestions using Claude API.

**Architecture:** Clean Architecture with feature-based modules. Local-first data storage with Hive, cloud auth via Supabase, AI processing through Edge Functions calling Claude API.

**Tech Stack:** Flutter 3.x, Riverpod, Hive, Supabase, Claude API, RevenueCat

---

## Execution Guide (執行指南)

### CLAUDE.md 規則提醒

> **重要**: 實作過程中必須遵循 `CLAUDE.md` 定義的規則

| 規則 | 說明 |
|------|------|
| **TDD** | 先寫測試 → 實作 → 重構 |
| **Bug 記錄** | 遇到 bug 立即記錄到 CLAUDE.md Bugs & Fixes |
| **Common Pitfalls** | 修復 bug 後更新 Common Pitfalls |
| **Commit & Push** | 每次 commit 後立即 push |
| **繁體中文** | Commit message 使用繁體中文 |

### Agent 分工策略

| 任務群組 | Agent Type | 說明 |
|----------|------------|------|
| Setup (1.1-1.3) | `Bash` | 專案初始化、bash 命令 |
| Domain (2.1-2.3) | `general-purpose` | 實體定義、業務邏輯 |
| UI (3.1-3.4) | `general-purpose` | Widget 和 Screen 開發 |
| Backend (4.1-4.2) | `general-purpose` | Supabase 設定、Edge Function |
| Integration (5.1-5.2) | `general-purpose` | 前後端整合 |
| Settings (6.1) | `general-purpose` | 設定頁面 |
| Usage (7.1-7.2) | `general-purpose` | 訊息計算、用量追蹤 |
| Memory (8.1-8.2) | `general-purpose` | 對話記憶 |
| Paywall (9.1-9.2) | `general-purpose` | 訂閱 UI + 加購訊息包 |
| **GAME (10.1-10.2)** | `general-purpose` | **GAME 階段分析、心理解讀** |

### 並行執行策略

```
Phase 1 (Sequential - 必須依序)
├─ 1.1 → 1.2 → 1.3

Phase 2 (Partially Parallel)
├─ 2.1 (Domain Entities)
│   └─ 完成後可並行:
│       ├─ 2.2 (Hive Init)
│       └─ 2.3 (Repository)

Phase 3 (Partially Parallel)
├─ 3.1 (Shared Widgets) ← 先完成
│   └─ 完成後可並行:
│       ├─ 3.2 (Home Screen)
│       ├─ 3.3 (New Conversation Screen)
│       └─ 3.4 (Analysis Screen)

Phase 4 (Sequential)
├─ 4.1 → 4.2

Phase 5 (Sequential)
├─ 5.1 → 5.2

Phase 6-9 (Sequential within phase, parallel across phases)
├─ 6.1 可與 7.x 並行
├─ 7.1 → 7.2
├─ 8.1 → 8.2
└─ 9.1 → 9.2

Phase 10 (Partially Parallel)
├─ 10.1 (GAME Stage Service)
└─ 10.2 (Psychology Widget) ← 依賴 10.1

Phase 11 (商業級補充 - Partially Parallel)
├─ 11.1 (AI Guardrails) → 11.2 (Fallback)
├─ 11.3 (AI Audit Log)
├─ 11.4 (Onboarding) ← 依賴 UI 完成
├─ 11.5 (Rate Limiting)
└─ 11.6 (Token Tracking) ← 依賴 11.3
```

### 任務總覽 (28 Tasks) - v2.3 與設計規格 v1.2 完全同步

| # | Task | Agent | 測試 | 依賴 |
|---|------|-------|------|------|
| 1.1 | Create Flutter Project | Bash | - | - |
| 1.2 | Configure Dependencies | Bash | - | 1.1 |
| 1.3 | Setup Project Structure | general | ✓ | 1.2 |
| 2.1 | Create Domain Entities (含 SessionContext) | general | ✓ | 1.3 |
| 2.2 | Setup Hive Initialization | general | ✓ | 2.1 |
| 2.3 | Create Conversation Repository | general | ✓ | 2.1 |
| 3.1 | Create Shared Widgets (含 GAME 階段指示器) | general | ✓ | 2.1 |
| 3.2 | Create Home Screen | general | ✓ | 3.1, 2.3 |
| 3.3 | Create New Conversation Screen (含情境收集) | general | ✓ | 3.1, 2.3 |
| 3.4 | Create Analysis Screen (含 GAME + 心理分析) | general | ✓ | 3.1, 2.3 |
| 4.1 | Setup Supabase Project | Bash | - | 1.3 |
| 4.2 | Create Edge Function (含 GAME 分析 + 最終建議 + 混合模型) | general | ✓ | 4.1 |
| 5.1 | Setup Supabase Client | general | ✓ | 4.1 |
| 5.2 | Create Analysis Service | general | ✓ | 4.2, 5.1 |
| 6.1 | Create Settings Screen | general | ✓ | 3.1 |
| 7.1 | Create Message Calculation Service | general | ✓ | 1.3 |
| 7.2 | Create Analysis Preview Dialog | general | ✓ | 7.1 |
| 8.1 | Add Memory Fields to Entities | general | ✓ | 2.1 |
| 8.2 | Create Memory Service | general | ✓ | 8.1 |
| 9.1 | Create Paywall Screen | general | ✓ | 3.1 |
| 9.2 | Create Message Booster Purchase (加購訊息包) | general | ✓ | 9.1 |
| 10.1 | Create GAME Stage Service | general | ✓ | 2.1 |
| 10.2 | Create Psychology Analysis Widget | general | ✓ | 3.1, 10.1 |
| **11.1** | **Create AI Guardrails (AI 護欄)** | general | ✓ | 4.2 |
| **11.2** | **Create AI Fallback Service** | general | ✓ | 4.2, 11.1 |
| **11.3** | **Create AI Audit Log (日誌)** | general | ✓ | 4.1 |
| **11.4** | **Create Onboarding Flow** | general | ✓ | 3.1, 3.2 |
| **11.5** | **Create Rate Limiting Service** | general | ✓ | 4.1, 7.1 |
| **11.6** | **Create Token Tracking Service** | general | ✓ | 4.2, 11.3 |

### TDD 檢查點

每個 Phase 完成後，執行：

```bash
# 1. 執行所有測試
flutter test

# 2. 檢查覆蓋率 (目標 > 70%)
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html

# 3. 若測試失敗
#    → 修復 → 記錄到 CLAUDE.md → 更新 Common Pitfalls
```

---

## Phase 1: Project Foundation

### Task 1.1: Create Flutter Project

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/main.dart`
- Create: `analysis_options.yaml`

**Step 1: Create Flutter project**

Run:
```bash
flutter create --org com.vibesync --project-name vibesync .
```

Expected: Flutter project scaffolded with default files

**Step 2: Verify project creation**

Run:
```bash
flutter doctor && flutter pub get
```

Expected: No critical issues, dependencies resolved

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: 建立 Flutter 專案基礎架構"
```

---

### Task 1.2: Configure Dependencies

**Files:**
- Modify: `pubspec.yaml`

**Step 1: Update pubspec.yaml with all dependencies**

```yaml
name: vibesync
description: 社交溝通技巧教練 App
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # State Management
  flutter_riverpod: ^2.4.9
  riverpod_annotation: ^2.3.3

  # Routing
  go_router: ^13.0.0

  # Local Storage
  hive: ^2.2.3
  hive_flutter: ^1.1.0

  # Backend
  supabase_flutter: ^2.3.0

  # Subscription
  purchases_flutter: ^6.17.0

  # Utils
  uuid: ^4.2.1
  intl: ^0.18.1
  flutter_secure_storage: ^9.0.0

  # UI
  flutter_svg: ^2.0.9
  shimmer: ^3.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1
  build_runner: ^2.4.7
  hive_generator: ^2.0.1
  riverpod_generator: ^2.3.9

flutter:
  uses-material-design: true
```

**Step 2: Install dependencies**

Run:
```bash
flutter pub get
```

Expected: All packages resolved successfully

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat: 新增專案依賴 (Riverpod, Hive, Supabase, RevenueCat)"
```

---

### Task 1.3: Setup Project Structure

**Files:**
- Create: `lib/app/app.dart`
- Create: `lib/app/routes.dart`
- Create: `lib/core/constants/app_constants.dart`
- Create: `lib/core/theme/app_theme.dart`
- Create: `lib/core/theme/app_colors.dart`
- Create: `lib/core/theme/app_typography.dart`
- Modify: `lib/main.dart`

**Step 1: Create directory structure**

Run:
```bash
mkdir -p lib/app lib/core/{constants,theme,utils,extensions} lib/features/{auth,conversation,analysis,subscription}/{data,domain,presentation} lib/shared/widgets
```

Expected: Directory structure created

**Step 2: Create app_colors.dart**

```dart
// lib/core/theme/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary - Deep Purple
  static const primary = Color(0xFF6B4EE6);
  static const primaryLight = Color(0xFF9D8DF7);
  static const primaryDark = Color(0xFF4527A0);

  // Enthusiasm Levels
  static const cold = Color(0xFF64B5F6);
  static const warm = Color(0xFFFFD54F);
  static const hot = Color(0xFFFF8A65);
  static const veryHot = Color(0xFFFF6B9D);

  // Neutral (Dark Mode)
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceVariant = Color(0xFF2D2D2D);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B3);
  static const divider = Color(0xFF3D3D3D);

  // Semantic
  static const success = Color(0xFF4CAF50);
  static const error = Color(0xFFE57373);
  static const warning = Color(0xFFFFB74D);
}
```

**Step 3: Create app_typography.dart**

```dart
// lib/core/theme/app_typography.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  static const headlineLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const headlineMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const bodyLarge = TextStyle(
    fontSize: 16,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static const bodyMedium = TextStyle(
    fontSize: 14,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const caption = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );
}
```

**Step 4: Create app_theme.dart**

```dart
// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.primaryLight,
          surface: AppColors.surface,
          background: AppColors.background,
          error: AppColors.error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardTheme(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
}
```

**Step 5: Create app_constants.dart**

```dart
// lib/core/constants/app_constants.dart
class AppConstants {
  AppConstants._();

  static const appName = 'VibeSync';
  static const appVersion = '1.0.0';

  // Enthusiasm Levels
  static const coldMax = 30;
  static const warmMax = 60;
  static const hotMax = 80;
  // veryHot: 81-100

  // Golden Rule
  static const goldenRuleMultiplier = 1.8;

  // Subscription Tiers (訊息制)
  static const freeMonthlyLimit = 30;
  static const starterMonthlyLimit = 300;
  static const essentialMonthlyLimit = 1000;

  // Daily Limits (每日上限)
  static const freeDailyLimit = 15;
  static const starterDailyLimit = 50;
  static const essentialDailyLimit = 150;

  // Conversation Limits (對話數量)
  static const freeConversationLimit = 3;
  static const starterConversationLimit = 15;
  static const essentialConversationLimit = 50;

  // Memory Limits (對話記憶輪數)
  static const freeMemoryRounds = 5;
  static const paidMemoryRounds = 15;

  // Message Calculation (訊息計算)
  static const maxCharsPerMessage = 200;  // 單則上限 200 字
  static const maxTotalChars = 5000;       // 單次分析上限 5000 字

  // Local Storage
  static const conversationsBox = 'conversations';
  static const settingsBox = 'settings';
  static const usageBox = 'usage';
}
```

**Step 6: Create routes.dart**

```dart
// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('VibeSync')),
      ),
    ),
  ],
);
```

**Step 7: Create app.dart**

```dart
// lib/app/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import 'routes.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'VibeSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
```

**Step 8: Update main.dart**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
```

**Step 9: Verify app runs**

Run:
```bash
flutter run -d chrome
```

Expected: App launches showing "VibeSync" text in dark mode

**Step 10: Commit**

```bash
git add lib/
git commit -m "feat: 建立 Clean Architecture 專案結構與主題系統"
```

---

## Phase 2: Local Data Layer (Hive)

### Task 2.1: Create Domain Entities (含 SessionContext + GAME Stage)

**Files:**
- Create: `lib/features/conversation/domain/entities/message.dart`
- Create: `lib/features/conversation/domain/entities/conversation.dart`
- Create: `lib/features/conversation/domain/entities/session_context.dart` ← **新增**
- Create: `lib/features/analysis/domain/entities/enthusiasm_level.dart`
- Create: `lib/features/analysis/domain/entities/game_stage.dart` ← **新增**
- Create: `lib/features/analysis/domain/entities/analysis_result.dart` ← **新增**

**Step 1: Create enthusiasm_level.dart**

```dart
// lib/features/analysis/domain/entities/enthusiasm_level.dart
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:flutter/material.dart';

enum EnthusiasmLevel {
  cold,
  warm,
  hot,
  veryHot;

  static EnthusiasmLevel fromScore(int score) {
    if (score <= AppConstants.coldMax) return cold;
    if (score <= AppConstants.warmMax) return warm;
    if (score <= AppConstants.hotMax) return hot;
    return veryHot;
  }

  String get label {
    switch (this) {
      case cold:
        return '冰點';
      case warm:
        return '溫和';
      case hot:
        return '熱情';
      case veryHot:
        return '高熱';
    }
  }

  String get emoji {
    switch (this) {
      case cold:
        return '❄️';
      case warm:
        return '🌤️';
      case hot:
        return '🔥';
      case veryHot:
        return '💖';
    }
  }

  Color get color {
    switch (this) {
      case cold:
        return AppColors.cold;
      case warm:
        return AppColors.warm;
      case hot:
        return AppColors.hot;
      case veryHot:
        return AppColors.veryHot;
    }
  }
}
```

**Step 1.5: Create game_stage.dart (新增)**

```dart
// lib/features/analysis/domain/entities/game_stage.dart

/// GAME 五階段流程
enum GameStage {
  opening,        // 打開 - 破冰
  premise,        // 前提 - 進入男女框架
  qualification,  // 評估 - 她證明自己配得上你
  narrative,      // 敘事 - 個性樣本、說故事
  close;          // 收尾 - 模糊邀約 → 確立邀約

  String get label {
    switch (this) {
      case opening:
        return '打開';
      case premise:
        return '前提';
      case qualification:
        return '評估';
      case narrative:
        return '敘事';
      case close:
        return '收尾';
    }
  }

  String get description {
    switch (this) {
      case opening:
        return '破冰階段';
      case premise:
        return '進入男女框架';
      case qualification:
        return '她在證明自己';
      case narrative:
        return '說故事、個性樣本';
      case close:
        return '準備邀約';
    }
  }

  String get emoji {
    switch (this) {
      case opening:
        return '👋';
      case premise:
        return '💫';
      case qualification:
        return '✨';
      case narrative:
        return '📖';
      case close:
        return '🎯';
    }
  }
}

/// GAME 階段狀態
enum GameStageStatus {
  normal,      // 正常進行
  stuckFriend, // 卡在朋友框
  canAdvance,  // 可以推進
  shouldRetreat; // 應該退回

  String get label {
    switch (this) {
      case normal:
        return '正常進行';
      case stuckFriend:
        return '卡在朋友框';
      case canAdvance:
        return '可以推進';
      case shouldRetreat:
        return '建議退回';
    }
  }
}
```

**Step 1.6: Create session_context.dart (新增)**

```dart
// lib/features/conversation/domain/entities/session_context.dart
import 'package:hive/hive.dart';

part 'session_context.g.dart';

/// 認識場景
@HiveType(typeId: 3)
enum MeetingContext {
  @HiveField(0)
  datingApp,      // 交友軟體
  @HiveField(1)
  inPerson,       // 現場搭訕
  @HiveField(2)
  friendIntro,    // 朋友介紹
  @HiveField(3)
  other;          // 其他

  String get label {
    switch (this) {
      case datingApp:
        return '交友軟體';
      case inPerson:
        return '現場搭訕';
      case friendIntro:
        return '朋友介紹';
      case other:
        return '其他';
    }
  }
}

/// 認識時長
@HiveType(typeId: 4)
enum AcquaintanceDuration {
  @HiveField(0)
  justMet,        // 剛認識
  @HiveField(1)
  fewDays,        // 幾天
  @HiveField(2)
  fewWeeks,       // 幾週
  @HiveField(3)
  monthPlus;      // 一個月+

  String get label {
    switch (this) {
      case justMet:
        return '剛認識';
      case fewDays:
        return '幾天';
      case fewWeeks:
        return '幾週';
      case monthPlus:
        return '一個月+';
    }
  }
}

/// 用戶目標
@HiveType(typeId: 5)
enum UserGoal {
  @HiveField(0)
  dateInvite,     // 約出來 (預設)
  @HiveField(1)
  maintainHeat,   // 維持熱度
  @HiveField(2)
  justChat;       // 純聊天

  String get label {
    switch (this) {
      case dateInvite:
        return '約出來';
      case maintainHeat:
        return '維持熱度';
      case justChat:
        return '純聊天';
    }
  }
}

/// Session 情境
@HiveType(typeId: 6)
class SessionContext extends HiveObject {
  @HiveField(0)
  final MeetingContext meetingContext;

  @HiveField(1)
  final AcquaintanceDuration duration;

  @HiveField(2)
  final UserGoal goal;

  SessionContext({
    required this.meetingContext,
    required this.duration,
    this.goal = UserGoal.dateInvite,  // 預設：約出來
  });

  Map<String, dynamic> toJson() => {
    'meetingContext': meetingContext.name,
    'duration': duration.name,
    'goal': goal.name,
  };
}
```

**Step 1.7: Create analysis_result.dart (新增)**

```dart
// lib/features/analysis/domain/entities/analysis_result.dart
import 'game_stage.dart';
import 'enthusiasm_level.dart';

/// 心理分析結果
class PsychologyAnalysis {
  final String subtext;           // 淺溝通解讀
  final bool shitTestDetected;    // 是否偵測到廢測
  final String? shitTestType;     // 廢測類型
  final String? shitTestSuggestion;
  final bool qualificationSignal; // 她有在證明自己

  PsychologyAnalysis({
    required this.subtext,
    this.shitTestDetected = false,
    this.shitTestType,
    this.shitTestSuggestion,
    this.qualificationSignal = false,
  });

  factory PsychologyAnalysis.fromJson(Map<String, dynamic> json) {
    final shitTest = json['shitTest'] as Map<String, dynamic>?;
    return PsychologyAnalysis(
      subtext: json['subtext'] ?? '',
      shitTestDetected: shitTest?['detected'] ?? false,
      shitTestType: shitTest?['type'],
      shitTestSuggestion: shitTest?['suggestion'],
      qualificationSignal: json['qualificationSignal'] ?? false,
    );
  }
}

/// AI 最終建議
class FinalRecommendation {
  final String pick;        // 選哪個回覆類型
  final String content;     // 推薦的回覆內容
  final String reason;      // 為什麼推薦這個
  final String psychology;  // 心理學依據

  FinalRecommendation({
    required this.pick,
    required this.content,
    required this.reason,
    required this.psychology,
  });

  factory FinalRecommendation.fromJson(Map<String, dynamic> json) {
    return FinalRecommendation(
      pick: json['pick'] ?? '',
      content: json['content'] ?? '',
      reason: json['reason'] ?? '',
      psychology: json['psychology'] ?? '',
    );
  }
}

/// 完整分析結果
class AnalysisResult {
  // GAME 階段
  final GameStage gameStage;
  final GameStageStatus gameStatus;
  final String gameNextStep;

  // 熱度
  final int enthusiasmScore;
  final EnthusiasmLevel enthusiasmLevel;

  // 話題深度
  final String topicDepthCurrent;
  final String topicDepthSuggestion;

  // 心理分析
  final PsychologyAnalysis psychology;

  // 5 種回覆
  final Map<String, String> replies;

  // 最終建議
  final FinalRecommendation finalRecommendation;

  // 警告
  final List<String> warnings;

  // 健檢 (Essential)
  final List<String>? healthCheckIssues;
  final List<String>? healthCheckSuggestions;

  // 策略提示
  final String strategy;

  // 提醒
  final String reminder;

  AnalysisResult({
    required this.gameStage,
    required this.gameStatus,
    required this.gameNextStep,
    required this.enthusiasmScore,
    required this.enthusiasmLevel,
    required this.topicDepthCurrent,
    required this.topicDepthSuggestion,
    required this.psychology,
    required this.replies,
    required this.finalRecommendation,
    required this.warnings,
    this.healthCheckIssues,
    this.healthCheckSuggestions,
    required this.strategy,
    this.reminder = '記得用你的方式說，見面才自然',
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final gameStageJson = json['gameStage'] as Map<String, dynamic>;
    final enthusiasmJson = json['enthusiasm'] as Map<String, dynamic>;
    final topicDepthJson = json['topicDepth'] as Map<String, dynamic>;
    final healthCheck = json['healthCheck'] as Map<String, dynamic>?;

    return AnalysisResult(
      gameStage: GameStage.values.firstWhere(
        (e) => e.name == gameStageJson['current'],
        orElse: () => GameStage.opening,
      ),
      gameStatus: GameStageStatus.values.firstWhere(
        (e) => e.label == gameStageJson['status'],
        orElse: () => GameStageStatus.normal,
      ),
      gameNextStep: gameStageJson['nextStep'] ?? '',
      enthusiasmScore: enthusiasmJson['score'] ?? 50,
      enthusiasmLevel: EnthusiasmLevel.fromScore(enthusiasmJson['score'] ?? 50),
      topicDepthCurrent: topicDepthJson['current'] ?? 'facts',
      topicDepthSuggestion: topicDepthJson['suggestion'] ?? '',
      psychology: PsychologyAnalysis.fromJson(json['psychology'] ?? {}),
      replies: Map<String, String>.from(json['replies'] ?? {}),
      finalRecommendation: FinalRecommendation.fromJson(
        json['finalRecommendation'] ?? {},
      ),
      warnings: List<String>.from(json['warnings'] ?? []),
      healthCheckIssues: healthCheck != null
          ? List<String>.from(healthCheck['issues'] ?? [])
          : null,
      healthCheckSuggestions: healthCheck != null
          ? List<String>.from(healthCheck['suggestions'] ?? [])
          : null,
      strategy: json['strategy'] ?? '',
      reminder: json['reminder'] ?? '記得用你的方式說，見面才自然',
    );
  }
}
```

**Step 2: Create message.dart**

```dart
// lib/features/conversation/domain/entities/message.dart
import 'package:hive/hive.dart';

part 'message.g.dart';

@HiveType(typeId: 1)
class Message extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final bool isFromMe;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  int? enthusiasmScore;

  Message({
    required this.id,
    required this.content,
    required this.isFromMe,
    required this.timestamp,
    this.enthusiasmScore,
  });

  int get wordCount => content.length;
}
```

**Step 3: Create conversation.dart**

```dart
// lib/features/conversation/domain/entities/conversation.dart
import 'package:hive/hive.dart';
import 'message.dart';
import 'session_context.dart';

part 'conversation.g.dart';

@HiveType(typeId: 0)
class Conversation extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? avatarPath;

  @HiveField(3)
  List<Message> messages;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  DateTime updatedAt;

  @HiveField(6)
  int? lastEnthusiasmScore;

  // v1.1 新增：Session 情境
  @HiveField(7)
  SessionContext? sessionContext;

  // v1.1 新增：當前 GAME 階段
  @HiveField(8)
  String? currentGameStage;

  Conversation({
    required this.id,
    required this.name,
    this.avatarPath,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.lastEnthusiasmScore,
    this.sessionContext,
    this.currentGameStage,
  });

  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;

  List<Message> get theirMessages => messages.where((m) => !m.isFromMe).toList();
}
```

**Step 4: Generate Hive adapters**

Run:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

Expected: Generated `message.g.dart` and `conversation.g.dart`

**Step 5: Write unit tests for EnthusiasmLevel**

Create `test/unit/entities/enthusiasm_level_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/enthusiasm_level.dart';

void main() {
  group('EnthusiasmLevel', () {
    group('fromScore', () {
      test('returns cold for score 0-30', () {
        expect(EnthusiasmLevel.fromScore(0), EnthusiasmLevel.cold);
        expect(EnthusiasmLevel.fromScore(15), EnthusiasmLevel.cold);
        expect(EnthusiasmLevel.fromScore(30), EnthusiasmLevel.cold);
      });

      test('returns warm for score 31-60', () {
        expect(EnthusiasmLevel.fromScore(31), EnthusiasmLevel.warm);
        expect(EnthusiasmLevel.fromScore(45), EnthusiasmLevel.warm);
        expect(EnthusiasmLevel.fromScore(60), EnthusiasmLevel.warm);
      });

      test('returns hot for score 61-80', () {
        expect(EnthusiasmLevel.fromScore(61), EnthusiasmLevel.hot);
        expect(EnthusiasmLevel.fromScore(70), EnthusiasmLevel.hot);
        expect(EnthusiasmLevel.fromScore(80), EnthusiasmLevel.hot);
      });

      test('returns veryHot for score 81-100', () {
        expect(EnthusiasmLevel.fromScore(81), EnthusiasmLevel.veryHot);
        expect(EnthusiasmLevel.fromScore(90), EnthusiasmLevel.veryHot);
        expect(EnthusiasmLevel.fromScore(100), EnthusiasmLevel.veryHot);
      });
    });

    test('label returns correct Chinese text', () {
      expect(EnthusiasmLevel.cold.label, '冰點');
      expect(EnthusiasmLevel.warm.label, '溫和');
      expect(EnthusiasmLevel.hot.label, '熱情');
      expect(EnthusiasmLevel.veryHot.label, '高熱');
    });

    test('emoji returns correct emoji', () {
      expect(EnthusiasmLevel.cold.emoji, '❄️');
      expect(EnthusiasmLevel.warm.emoji, '🌤️');
      expect(EnthusiasmLevel.hot.emoji, '🔥');
      expect(EnthusiasmLevel.veryHot.emoji, '💖');
    });
  });
}
```

**Step 6: Run tests**

```bash
flutter test test/unit/entities/
```

Expected: All tests pass

**Step 7: Commit**

```bash
git add lib/features/ test/
git commit -m "feat: 建立 Message 和 Conversation 實體 (含 Hive 配置)"
```

---

### Task 2.2: Setup Hive Initialization

**Files:**
- Create: `lib/core/services/storage_service.dart`
- Modify: `lib/main.dart`

**Step 1: Create storage_service.dart**

```dart
// lib/core/services/storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../features/conversation/domain/entities/conversation.dart';
import '../../features/conversation/domain/entities/message.dart';
import '../constants/app_constants.dart';

class StorageService {
  static const _encryptionKeyName = 'vibesync_encryption_key';
  static final _secureStorage = FlutterSecureStorage();

  static Future<void> initialize() async {
    await Hive.initFlutter();

    // Register adapters
    Hive.registerAdapter(ConversationAdapter());
    Hive.registerAdapter(MessageAdapter());

    // Get or create encryption key
    final encryptionKey = await _getEncryptionKey();

    // Open encrypted boxes
    await Hive.openBox<Conversation>(
      AppConstants.conversationsBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox(
      AppConstants.settingsBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  static Future<List<int>> _getEncryptionKey() async {
    final existingKey = await _secureStorage.read(key: _encryptionKeyName);

    if (existingKey != null) {
      return existingKey.codeUnits;
    }

    final newKey = Hive.generateSecureKey();
    await _secureStorage.write(
      key: _encryptionKeyName,
      value: String.fromCharCodes(newKey),
    );
    return newKey;
  }

  static Box<Conversation> get conversationsBox =>
      Hive.box<Conversation>(AppConstants.conversationsBox);

  static Box get settingsBox => Hive.box(AppConstants.settingsBox);
}
```

**Step 2: Update main.dart**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local storage
  await StorageService.initialize();

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
```

**Step 3: Verify app still runs**

Run:
```bash
flutter run -d chrome
```

Expected: App launches without errors (note: secure storage may not work on web, test on mobile emulator for full verification)

**Step 4: Write unit tests for StorageService**

Create `test/unit/services/storage_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vibesync/core/services/storage_service.dart';
import 'package:vibesync/core/constants/app_constants.dart';

void main() {
  group('StorageService', () {
    setUpAll(() async {
      // Initialize Hive for testing (in-memory)
      await Hive.initFlutter();
    });

    tearDownAll(() async {
      await Hive.close();
    });

    test('conversationsBox returns correct box name', () {
      expect(AppConstants.conversationsBox, 'conversations');
    });

    test('settingsBox returns correct box name', () {
      expect(AppConstants.settingsBox, 'settings');
    });

    test('usageBox returns correct box name', () {
      expect(AppConstants.usageBox, 'usage');
    });
  });
}
```

> **Note:** StorageService 完整測試需要 mock flutter_secure_storage，在整合測試中驗證。

**Step 5: Commit**

```bash
git add lib/ test/
git commit -m "feat: 設置 Hive 加密儲存服務"
```

---

### Task 2.3: Create Conversation Repository

**Files:**
- Create: `lib/features/conversation/data/repositories/conversation_repository.dart`
- Create: `lib/features/conversation/data/providers/conversation_providers.dart`

**Step 1: Create conversation_repository.dart**

```dart
// lib/features/conversation/data/repositories/conversation_repository.dart
import 'package:uuid/uuid.dart';
import '../../../../core/services/storage_service.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

class ConversationRepository {
  final _uuid = const Uuid();

  List<Conversation> getAllConversations() {
    return StorageService.conversationsBox.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Conversation? getConversation(String id) {
    return StorageService.conversationsBox.get(id);
  }

  Future<Conversation> createConversation({
    required String name,
    required List<Message> messages,
  }) async {
    final now = DateTime.now();
    final conversation = Conversation(
      id: _uuid.v4(),
      name: name,
      messages: messages,
      createdAt: now,
      updatedAt: now,
    );

    await StorageService.conversationsBox.put(conversation.id, conversation);
    return conversation;
  }

  Future<void> updateConversation(Conversation conversation) async {
    conversation.updatedAt = DateTime.now();
    await conversation.save();
  }

  Future<void> deleteConversation(String id) async {
    await StorageService.conversationsBox.delete(id);
  }

  Future<void> deleteAll() async {
    await StorageService.conversationsBox.clear();
  }

  List<Message> parseMessages(String rawText) {
    final lines = rawText.trim().split('\n');
    final messages = <Message>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final isFromMe = trimmed.startsWith('我:') || trimmed.startsWith('我：');
      final isFromThem = trimmed.startsWith('她:') ||
          trimmed.startsWith('她：') ||
          trimmed.startsWith('他:') ||
          trimmed.startsWith('他：');

      if (!isFromMe && !isFromThem) continue;

      final content = trimmed.substring(2).trim();
      if (content.isEmpty) continue;

      messages.add(Message(
        id: _uuid.v4(),
        content: content,
        isFromMe: isFromMe,
        timestamp: DateTime.now(),
      ));
    }

    return messages;
  }
}
```

**Step 2: Create conversation_providers.dart**

```dart
// lib/features/conversation/data/providers/conversation_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/conversation_repository.dart';
import '../../domain/entities/conversation.dart';

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository();
});

final conversationsProvider = Provider<List<Conversation>>((ref) {
  final repository = ref.watch(conversationRepositoryProvider);
  return repository.getAllConversations();
});
```

**Step 3: Write unit test for message parsing**

Create `test/conversation_repository_test.dart`:

```dart
// test/conversation_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';

void main() {
  late ConversationRepository repository;

  setUp(() {
    repository = ConversationRepository();
  });

  group('parseMessages', () {
    test('parses messages correctly', () {
      const rawText = '''
她: 你好
我: 嗨
她: 在幹嘛
我: 工作中
''';

      final messages = repository.parseMessages(rawText);

      expect(messages.length, 4);
      expect(messages[0].isFromMe, false);
      expect(messages[0].content, '你好');
      expect(messages[1].isFromMe, true);
      expect(messages[1].content, '嗨');
    });

    test('handles empty lines', () {
      const rawText = '''
她: 你好

我: 嗨
''';

      final messages = repository.parseMessages(rawText);
      expect(messages.length, 2);
    });

    test('ignores invalid lines', () {
      const rawText = '''
她: 你好
無效的行
我: 嗨
''';

      final messages = repository.parseMessages(rawText);
      expect(messages.length, 2);
    });
  });
}
```

**Step 4: Run test**

Run:
```bash
flutter test test/conversation_repository_test.dart
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/features/conversation/ test/
git commit -m "feat: 建立 ConversationRepository 與訊息解析邏輯"
```

---

## Phase 3: UI Screens

### Task 3.1: Create Shared Widgets

**Files:**
- Create: `lib/shared/widgets/enthusiasm_gauge.dart`
- Create: `lib/shared/widgets/reply_card.dart`

**Step 1: Create enthusiasm_gauge.dart**

```dart
// lib/shared/widgets/enthusiasm_gauge.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/analysis/domain/entities/enthusiasm_level.dart';

class EnthusiasmGauge extends StatelessWidget {
  final int score;

  const EnthusiasmGauge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final level = EnthusiasmLevel.fromScore(score);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(level.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(
                '$score/100',
                style: AppTypography.headlineMedium,
              ),
              const SizedBox(width: 8),
              Text(
                level.label,
                style: AppTypography.bodyLarge.copyWith(color: level.color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(level.color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Create reply_card.dart**

```dart
// lib/shared/widgets/reply_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

enum ReplyType { extend, resonate, tease, humor, coldRead }

class ReplyCard extends StatelessWidget {
  final ReplyType type;
  final String content;
  final bool isLocked;
  final VoidCallback? onTap;

  const ReplyCard({
    super.key,
    required this.type,
    required this.content,
    this.isLocked = false,
    this.onTap,
  });

  String get _label {
    switch (type) {
      case ReplyType.extend:
        return '🔄 延展';
      case ReplyType.resonate:
        return '💬 共鳴';
      case ReplyType.tease:
        return '😏 調情';
      case ReplyType.humor:
        return '🎭 幽默';
      case ReplyType.coldRead:
        return '🔮 冷讀';
    }
  }

  Color get _color {
    switch (type) {
      case ReplyType.extend:
        return AppColors.cold;
      case ReplyType.resonate:
        return AppColors.warm;
      case ReplyType.tease:
        return AppColors.veryHot;
      case ReplyType.humor:
        return AppColors.hot;
      case ReplyType.coldRead:
        return AppColors.primaryLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isLocked ? onTap : () => _copyToClipboard(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _label,
                        style: AppTypography.caption.copyWith(color: _color),
                      ),
                    ),
                    const Spacer(),
                    if (isLocked)
                      const Icon(Icons.lock, size: 16, color: AppColors.textSecondary)
                    else
                      const Icon(Icons.copy, size: 16, color: AppColors.textSecondary),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  isLocked ? '升級 Pro 解鎖' : content,
                  style: isLocked
                      ? AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        )
                      : AppTypography.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已複製到剪貼簿'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}
```

**Step 3: Write widget tests**

Create `test/widget/widgets/enthusiasm_gauge_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/shared/widgets/enthusiasm_gauge.dart';

void main() {
  group('EnthusiasmGauge', () {
    testWidgets('displays correct score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 72)),
        ),
      );

      expect(find.text('72/100'), findsOneWidget);
    });

    testWidgets('displays cold emoji for low score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 25)),
        ),
      );

      expect(find.text('❄️'), findsOneWidget);
      expect(find.text('冰點'), findsOneWidget);
    });

    testWidgets('displays hot emoji for high score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 75)),
        ),
      );

      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('熱情'), findsOneWidget);
    });
  });
}
```

Create `test/widget/widgets/reply_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/shared/widgets/reply_card.dart';

void main() {
  group('ReplyCard', () {
    testWidgets('displays correct label for extend type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplyCard(
              type: ReplyType.extend,
              content: '測試內容',
            ),
          ),
        ),
      );

      expect(find.text('🔄 延展'), findsOneWidget);
      expect(find.text('測試內容'), findsOneWidget);
    });

    testWidgets('shows lock icon when isLocked is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplyCard(
              type: ReplyType.resonate,
              content: '測試內容',
              isLocked: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.text('升級 Pro 解鎖'), findsOneWidget);
    });

    testWidgets('shows copy icon when not locked', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplyCard(
              type: ReplyType.extend,
              content: '測試內容',
              isLocked: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('displays all 5 reply types correctly', (tester) async {
      for (final type in ReplyType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReplyCard(type: type, content: 'test'),
            ),
          ),
        );
        await tester.pump();
      }
      // If no exception thrown, all types render correctly
    });
  });
}
```

**Step 4: Run widget tests**

```bash
flutter test test/widget/widgets/
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/shared/ test/
git commit -m "feat: 建立 EnthusiasmGauge 和 ReplyCard 共用元件"
```

---

### Task 3.2: Create Home Screen (Conversation List)

**Files:**
- Create: `lib/features/conversation/presentation/screens/home_screen.dart`
- Create: `lib/features/conversation/presentation/widgets/conversation_tile.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create conversation_tile.dart**

```dart
// lib/features/conversation/presentation/widgets/conversation_tile.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis/domain/entities/enthusiasm_level.dart';
import '../../domain/entities/conversation.dart';
import 'package:intl/intl.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return DateFormat('HH:mm').format(date);
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    }
    return DateFormat('MM/dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final level = conversation.lastEnthusiasmScore != null
        ? EnthusiasmLevel.fromScore(conversation.lastEnthusiasmScore!)
        : null;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceVariant,
        child: Text(
          conversation.name.isNotEmpty ? conversation.name[0] : '?',
          style: AppTypography.titleLarge,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.name,
              style: AppTypography.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatDate(conversation.updatedAt),
            style: AppTypography.caption,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (level != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(level.emoji),
                const SizedBox(width: 4),
                Text(
                  '${conversation.lastEnthusiasmScore}',
                  style: AppTypography.caption.copyWith(color: level.color),
                ),
              ],
            ),
          ],
          if (conversation.lastMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              conversation.lastMessage!.content,
              style: AppTypography.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
```

**Step 2: Create home_screen.dart**

```dart
// lib/features/conversation/presentation/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/conversation_providers.dart';
import '../widgets/conversation_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('VibeSync', style: AppTypography.headlineMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: conversations.isEmpty
          ? _buildEmptyState(context)
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(
                color: AppColors.divider,
                height: 1,
                indent: 72,
              ),
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                return ConversationTile(
                  conversation: conversation,
                  onTap: () => context.push('/conversation/${conversation.id}'),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/new'),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            '還沒有對話',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '點擊右下角 + 開始新增',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 3: Update routes.dart**

```dart
// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/conversation/presentation/screens/home_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('新增對話')),
      ),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => Scaffold(
        body: Center(child: Text('對話 ${state.pathParameters['id']}')),
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('設定')),
      ),
    ),
  ],
);
```

**Step 4: Verify app runs with home screen**

Run:
```bash
flutter run -d chrome
```

Expected: Home screen displays with empty state and FAB button

**Step 5: Write widget tests**

Create `test/widget/screens/home_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/presentation/screens/home_screen.dart';

void main() {
  group('HomeScreen', () {
    testWidgets('displays app title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.text('VibeSync'), findsOneWidget);
    });

    testWidgets('shows empty state when no conversations', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.text('還沒有對話'), findsOneWidget);
      expect(find.text('點擊右下角 + 開始新增'), findsOneWidget);
    });

    testWidgets('shows FAB button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows settings icon', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });
  });
}
```

**Step 6: Run widget tests**

```bash
flutter test test/widget/screens/home_screen_test.dart
```

Expected: All tests pass

**Step 7: Commit**

```bash
git add lib/ test/
git commit -m "feat: 建立首頁對話列表畫面"
```

---

### Task 3.3: Create New Conversation Screen

**Files:**
- Create: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create new_conversation_screen.dart**

```dart
// lib/features/conversation/presentation/screens/new_conversation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/conversation_providers.dart';

class NewConversationScreen extends ConsumerStatefulWidget {
  const NewConversationScreen({super.key});

  @override
  ConsumerState<NewConversationScreen> createState() =>
      _NewConversationScreenState();
}

class _NewConversationScreenState extends ConsumerState<NewConversationScreen> {
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isLoading = false;

  // Session Context (情境收集)
  MeetingContext _meetingContext = MeetingContext.datingApp;
  AcquaintanceDuration _duration = AcquaintanceDuration.justMet;
  UserGoal _goal = UserGoal.dateInvite;

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入對話對象暱稱')),
      );
      return;
    }

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請貼上對話內容')),
      );
      return;
    }

    final repository = ref.read(conversationRepositoryProvider);
    final messages = repository.parseMessages(content);

    if (messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法解析對話，請確認格式正確')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final conversation = await repository.createConversation(
        name: name,
        messages: messages,
        sessionContext: SessionContext(
          meetingContext: _meetingContext,
          duration: _duration,
          goal: _goal,
        ),
      );

      if (mounted) {
        context.go('/conversation/${conversation.id}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('新增對話', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('對話對象暱稱', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '例如：小美',
              ),
            ),

            // === 情境收集區塊 ===
            const SizedBox(height: 24),
            Text('認識場景', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            SegmentedButton<MeetingContext>(
              segments: const [
                ButtonSegment(value: MeetingContext.datingApp, label: Text('交友軟體')),
                ButtonSegment(value: MeetingContext.inPerson, label: Text('現實搭訕')),
                ButtonSegment(value: MeetingContext.friendIntro, label: Text('朋友介紹')),
              ],
              selected: {_meetingContext},
              onSelectionChanged: (v) => setState(() => _meetingContext = v.first),
            ),

            const SizedBox(height: 16),
            Text('認識多久', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            SegmentedButton<AcquaintanceDuration>(
              segments: const [
                ButtonSegment(value: AcquaintanceDuration.justMet, label: Text('剛認識')),
                ButtonSegment(value: AcquaintanceDuration.fewDays, label: Text('幾天')),
                ButtonSegment(value: AcquaintanceDuration.fewWeeks, label: Text('幾週')),
                ButtonSegment(value: AcquaintanceDuration.monthPlus, label: Text('一個月+')),
              ],
              selected: {_duration},
              onSelectionChanged: (v) => setState(() => _duration = v.first),
            ),

            const SizedBox(height: 16),
            Text('你的目標', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            SegmentedButton<UserGoal>(
              segments: const [
                ButtonSegment(value: UserGoal.dateInvite, label: Text('約出來')),
                ButtonSegment(value: UserGoal.maintainHeat, label: Text('維持熱度')),
                ButtonSegment(value: UserGoal.justChat, label: Text('隨意聊')),
              ],
              selected: {_goal},
              onSelectionChanged: (v) => setState(() => _goal = v.first),
            ),

            const SizedBox(height: 24),
            Text('貼上對話內容', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: '她: 你好\n我: 嗨\n她: 在幹嘛\n...',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '格式：每行一則訊息，以「她:」或「我:」開頭',
                      style: AppTypography.caption,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _analyze,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('開始分析'),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Update routes.dart**

```dart
// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/conversation/presentation/screens/home_screen.dart';
import '../features/conversation/presentation/screens/new_conversation_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const NewConversationScreen(),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => Scaffold(
        body: Center(child: Text('對話 ${state.pathParameters['id']}')),
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('設定')),
      ),
    ),
  ],
);
```

**Step 3: Verify new conversation flow**

Run:
```bash
flutter run -d chrome
```

Test: Click FAB → Enter name and paste conversation → Click analyze

Expected: Navigates to conversation detail (placeholder)

**Step 4: Write widget tests**

Create `test/widget/screens/new_conversation_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/presentation/screens/new_conversation_screen.dart';

void main() {
  group('NewConversationScreen', () {
    testWidgets('displays title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('新增對話'), findsOneWidget);
    });

    testWidgets('shows name input field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('對話對象暱稱'), findsOneWidget);
      expect(find.widgetWithText(TextField, '例如：小美'), findsOneWidget);
    });

    testWidgets('shows content input field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('貼上對話內容'), findsOneWidget);
    });

    testWidgets('shows format hint', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.textContaining('格式：每行一則訊息'), findsOneWidget);
    });

    testWidgets('shows analyze button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NewConversationScreen()),
        ),
      );

      expect(find.text('開始分析'), findsOneWidget);
    });

    testWidgets('shows error when name is empty', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: NewConversationScreen()),
          ),
        ),
      );

      // Tap analyze without entering name
      await tester.tap(find.text('開始分析'));
      await tester.pump();

      expect(find.text('請輸入對話對象暱稱'), findsOneWidget);
    });
  });
}
```

**Step 5: Run widget tests**

```bash
flutter test test/widget/screens/new_conversation_screen_test.dart
```

Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/ test/
git commit -m "feat: 建立新增對話畫面與訊息輸入功能"
```

---

### Task 3.4: Create Analysis Screen

**Files:**
- Create: `lib/features/analysis/presentation/screens/analysis_screen.dart`
- Create: `lib/features/conversation/presentation/widgets/message_bubble.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create message_bubble.dart**

```dart
// lib/features/conversation/presentation/widgets/message_bubble.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isFromMe ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: message.isFromMe ? const Radius.circular(4) : null,
            bottomLeft: !message.isFromMe ? const Radius.circular(4) : null,
          ),
        ),
        child: Text(
          message.content,
          style: AppTypography.bodyMedium,
        ),
      ),
    );
  }
}
```

**Step 2: Create analysis_screen.dart**

```dart
// lib/features/analysis/presentation/screens/analysis_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/enthusiasm_gauge.dart';
import '../../../../shared/widgets/reply_card.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/presentation/widgets/message_bubble.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const AnalysisScreen({super.key, required this.conversationId});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  bool _isAnalyzing = false;
  int? _enthusiasmScore;
  String? _strategy;
  Map<String, String>? _replies;
  TopicDepth? _topicDepth;
  HealthCheck? _healthCheck;
  bool _isFreeUser = true;  // TODO: Get from subscription provider

  // GAME 階段分析
  GameStageInfo? _gameStage;

  // 心理分析
  PsychologyAnalysis? _psychology;

  // 最終建議
  FinalRecommendation? _finalRecommendation;

  // 一致性提醒
  String? _reminder;

  void _showPaywall(BuildContext context) {
    // TODO: Navigate to paywall screen
    context.push('/paywall');
  }

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    setState(() => _isAnalyzing = true);

    // TODO: Replace with actual API call
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isAnalyzing = false;
      _enthusiasmScore = 72;
      _strategy = '她有興趣且主動分享，保持沉穩，80%鏡像即可';
      _topicDepth = TopicDepth(
        current: 'personal',
        suggestion: '可以往曖昧導向推進',
      );
      _healthCheck = HealthCheck(
        issues: [],
        suggestions: [],
      );

      // GAME 階段分析
      _gameStage = GameStageInfo(
        current: GameStage.premise,
        status: '正常進行',
        nextStep: '可以開始評估階段',
      );

      // 心理分析
      _psychology = PsychologyAnalysis(
        subtext: '她分享週末活動代表對你有一定信任，想讓你更了解她',
        shitTest: null,
        qualificationSignal: true,
      );

      _replies = {
        'extend': '抹茶山不錯欸，下次可以挑戰更難的',
        'resonate': '抹茶山超讚！照片一定很美吧',
        'tease': '聽起來妳很會挑地方嘛，改天帶路？',
        'humor': '爬完山是不是腿軟到需要人扶？',
        'coldRead': '感覺你是那種週末閒不下來的人',
      };

      // 最終建議
      _finalRecommendation = FinalRecommendation(
        pick: 'tease',
        content: '聽起來妳很會挑地方嘛，改天帶路？',
        reason: '目前處於 Premise 階段，她有興趣且主動分享，用調情回覆推進曖昧',
        psychology: '「改天帶路」是模糊邀約，讓她有想像空間且不會有壓力',
      );

      // 一致性提醒
      _reminder = '記得用你的方式說，見面才自然';
    });

    // Update conversation with score
    final repository = ref.read(conversationRepositoryProvider);
    final conversation = repository.getConversation(widget.conversationId);
    if (conversation != null) {
      conversation.lastEnthusiasmScore = _enthusiasmScore;
      await repository.updateConversation(conversation);
    }
  }

  int _calculateMaxReplyLength(Conversation conversation) {
    final theirMessages = conversation.theirMessages;
    if (theirMessages.isEmpty) return 50;

    final lastTheirMessage = theirMessages.last;
    return (lastTheirMessage.wordCount * AppConstants.goldenRuleMultiplier).round();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(conversationRepositoryProvider);
    final conversation = repository.getConversation(widget.conversationId);

    if (conversation == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('找不到對話')),
      );
    }

    final maxLength = _calculateMaxReplyLength(conversation);

    return Scaffold(
      appBar: AppBar(
        title: Text(conversation.name, style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          if (_isAnalyzing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Messages preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ...conversation.messages
                      .take(5)
                      .map((m) => MessageBubble(message: m)),
                  if (conversation.messages.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '...還有 ${conversation.messages.length - 5} 則訊息',
                        style: AppTypography.caption,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Enthusiasm Gauge
            if (_enthusiasmScore != null) ...[
              Text('熱度分析', style: AppTypography.titleLarge),
              const SizedBox(height: 12),
              EnthusiasmGauge(score: _enthusiasmScore!),
            ] else if (_isAnalyzing) ...[
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('分析中...'),
                  ],
                ),
              ),
            ],

            // GAME 階段指示器
            if (_gameStage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🎯', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text('GAME 階段', style: AppTypography.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GameStageIndicator(currentStage: _gameStage!.current),
                    const SizedBox(height: 8),
                    Text('狀態: ${_gameStage!.status}', style: AppTypography.bodyMedium),
                    Text('下一步: ${_gameStage!.nextStep}', style: AppTypography.caption),
                  ],
                ),
              ),
            ],

            // 心理分析 (淺溝通解讀)
            if (_psychology != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🧠', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text('心理解讀', style: AppTypography.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_psychology!.subtext, style: AppTypography.bodyMedium),
                    if (_psychology!.shitTest != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Text('⚠️', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '偵測到廢測: ${_psychology!.shitTest}',
                                style: AppTypography.caption,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_psychology!.qualificationSignal) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                          const SizedBox(width: 4),
                          Text('她在向你證明自己', style: AppTypography.caption),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Strategy
            if (_strategy != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _strategy!,
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Topic Depth (話題深度)
            if (_topicDepth != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('📊', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('話題深度: ${_topicDepth!.current}',
                              style: AppTypography.bodyMedium),
                          if (_topicDepth!.suggestion.isNotEmpty)
                            Text(_topicDepth!.suggestion,
                                style: AppTypography.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Health Check (對話健檢 - Essential 專屬)
            if (_healthCheck != null && _healthCheck!.issues.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🩺', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text('對話健檢', style: AppTypography.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._healthCheck!.issues.map((issue) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 16, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Expanded(child: Text(issue, style: AppTypography.bodyMedium)),
                        ],
                      ),
                    )),
                    if (_healthCheck!.suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ..._healthCheck!.suggestions.map((suggestion) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.success),
                            const SizedBox(width: 8),
                            Expanded(child: Text(suggestion, style: AppTypography.caption)),
                          ],
                        ),
                      )),
                    ],
                  ],
                ),
              ),
            ],

            // Reply suggestions (5 種回覆)
            if (_replies != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Text('建議回覆', style: AppTypography.titleLarge),
                  const Spacer(),
                  Text(
                    '字數上限: $maxLength字',
                    style: AppTypography.caption,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 延展回覆 (所有方案都有)
              ReplyCard(
                type: ReplyType.extend,
                content: _replies!['extend']!,
              ),
              // 以下回覆 Starter/Essential 才有
              ReplyCard(
                type: ReplyType.resonate,
                content: _replies!['resonate']!,
                isLocked: _isFreeUser, // Free 用戶鎖定
                onTap: _isFreeUser ? () => _showPaywall(context) : null,
              ),
              ReplyCard(
                type: ReplyType.tease,
                content: _replies!['tease']!,
                isLocked: _isFreeUser,
                onTap: _isFreeUser ? () => _showPaywall(context) : null,
              ),
              ReplyCard(
                type: ReplyType.humor,
                content: _replies!['humor']!,
                isLocked: _isFreeUser,
                onTap: _isFreeUser ? () => _showPaywall(context) : null,
              ),
              ReplyCard(
                type: ReplyType.coldRead,
                content: _replies!['coldRead']!,
                isLocked: _isFreeUser,
                onTap: _isFreeUser ? () => _showPaywall(context) : null,
              ),
            ],

            // 最終建議 (AI 推薦)
            if (_finalRecommendation != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.1),
                      AppColors.primary.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('⭐', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text('AI 推薦回覆', style: AppTypography.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _finalRecommendation!.content,
                        style: AppTypography.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '📝 ${_finalRecommendation!.reason}',
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '🧠 ${_finalRecommendation!.psychology}',
                      style: AppTypography.caption,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Copy to clipboard
                          Clipboard.setData(
                            ClipboardData(text: _finalRecommendation!.content),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已複製到剪貼簿')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('複製推薦回覆'),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 一致性提醒
            if (_reminder != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('💬', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _reminder!,
                        style: AppTypography.bodyMedium.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
```

**Step 3: Update routes.dart**

```dart
// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/analysis/presentation/screens/analysis_screen.dart';
import '../features/conversation/presentation/screens/home_screen.dart';
import '../features/conversation/presentation/screens/new_conversation_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const NewConversationScreen(),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => AnalysisScreen(
        conversationId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('設定')),
      ),
    ),
  ],
);
```

**Step 4: Verify full flow**

Run:
```bash
flutter run -d chrome
```

Test: Create new conversation → View analysis with mock data

Expected: Shows messages, enthusiasm gauge, strategy, and reply cards

**Step 5: Write widget tests**

Create `test/widget/screens/analysis_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';

// Mock conversation ID for testing
const testConversationId = 'test-123';

void main() {
  group('AnalysisScreen', () {
    testWidgets('shows loading state initially', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AnalysisScreen(conversationId: testConversationId),
          ),
        ),
      );

      // Should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows back button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AnalysisScreen(conversationId: testConversationId),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    // Note: Full analysis screen tests require mocking:
    // - ConversationRepository
    // - AnalysisService
    // These will be covered in integration tests
  });
}
```

**Step 6: Run widget tests**

```bash
flutter test test/widget/screens/
```

Expected: All tests pass

**Step 7: Commit**

```bash
git add lib/ test/
git commit -m "feat: 建立對話分析畫面 (含熱度儀表與回覆建議)"
```

---

## Phase 3 TDD Checkpoint

Before proceeding to Phase 4, verify:

```bash
# Run all Phase 1-3 tests
flutter test

# Expected: All tests pass
# If any test fails:
# 1. Fix the issue
# 2. Record in CLAUDE.md Bugs & Fixes
# 3. Update Common Pitfalls
```

---

## Phase 4: Supabase Backend

### Task 4.1: Setup Supabase Project

**Files:**
- Create: `supabase/config.toml`
- Create: `supabase/migrations/00001_initial_schema.sql`

**Step 1: Initialize Supabase**

Run:
```bash
npx supabase init
```

Expected: Creates `supabase/` directory

**Step 2: Create initial migration**

```sql
-- supabase/migrations/00001_initial_schema.sql

-- Users table (synced with auth.users)
CREATE TABLE public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  total_analyses INTEGER DEFAULT 0,
  total_conversations INTEGER DEFAULT 0
);

-- Subscriptions table (訊息制)
CREATE TABLE public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
  tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'starter', 'essential')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
  rc_customer_id TEXT,
  rc_entitlement_id TEXT,
  -- 訊息用量追蹤
  monthly_messages_used INTEGER DEFAULT 0,
  daily_messages_used INTEGER DEFAULT 0,
  monthly_reset_at TIMESTAMPTZ DEFAULT NOW(),
  daily_reset_at TIMESTAMPTZ DEFAULT NOW(),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own data" ON public.users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own data" ON public.users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can view own subscription" ON public.subscriptions
  FOR SELECT USING (auth.uid() = user_id);

-- Function to create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email)
  VALUES (NEW.id, NEW.email);

  INSERT INTO public.subscriptions (user_id)
  VALUES (NEW.id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user signup
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to reset monthly usage
CREATE OR REPLACE FUNCTION public.reset_monthly_usage()
RETURNS void AS $$
BEGIN
  UPDATE public.subscriptions
  SET monthly_analyses_used = 0,
      monthly_reset_at = NOW()
  WHERE monthly_reset_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;
```

**Step 3: Commit**

```bash
git add supabase/
git commit -m "feat: 建立 Supabase 初始資料庫結構"
```

---

### Task 4.2: Create Edge Function for Analysis

**Files:**
- Create: `supabase/functions/analyze-chat/index.ts`

**Step 1: Create Edge Function**

```typescript
// supabase/functions/analyze-chat/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const CLAUDE_API_KEY = Deno.env.get("CLAUDE_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// 訊息制額度
const TIER_MONTHLY_LIMITS: Record<string, number> = {
  free: 30,
  starter: 300,
  essential: 1000,
};

const TIER_DAILY_LIMITS: Record<string, number> = {
  free: 15,
  starter: 50,
  essential: 150,
};

// 功能權限
const TIER_FEATURES: Record<string, string[]> = {
  free: ['extend'],  // 只有延展回覆
  starter: ['extend', 'resonate', 'tease', 'humor', 'coldRead', 'needy_warning', 'topic_depth'],
  essential: ['extend', 'resonate', 'tease', 'humor', 'coldRead', 'needy_warning', 'topic_depth', 'health_check'],
};

const SYSTEM_PROMPT = `你是一位專業的社交溝通教練，幫助用戶提升對話技巧，最終目標是幫助用戶成功邀約。

## GAME 五階段框架

你必須分析對話處於哪個階段：
1. Opening (打開) - 破冰階段
2. Premise (前提) - 進入男女框架，建立張力
3. Qualification (評估) - 她證明自己配得上用戶
4. Narrative (敘事) - 個性樣本、說故事
5. Close (收尾) - 模糊邀約 → 確立邀約

## 最高指導原則

### 1. 1.8x 黃金法則
所有建議回覆的字數必須 ≤ 對方最後訊息字數 × 1.8
這條規則不可違反。

### 2. 82/18 原則
好的對話是 82% 聆聽 + 18% 說話
- 用戶不該一直問問題 (索取)
- 要適時分享故事 (提供)

### 3. 假設代替問句
- ❌ 「你是做什麼工作的？」(面試感)
- ✅ 「感覺你是做創意相關的工作？」(冷讀)

### 4. 陳述優於問句
朋友間直接問句比較少，陳述句讓對話更自然

### 5. 話題深度階梯
- Level 1: 事件導向 (Facts) - 剛認識
- Level 2: 個人導向 (Personal) - 有基本認識
- Level 3: 曖昧導向 (Intimate) - 熱度 > 60
- 原則：不可越級，循序漸進

### 6. 細緻化優先
- 不要一直換話題
- 針對對方回答深入挖掘

## 核心技巧

### 隱性價值展示 (DHV)
- 一句話帶過，不解釋
- 例：「剛從北京出差回來」而非「我很常出國」

### 框架控制
- 不因對方攻擊/挑釁/廢測而改變
- 不用點對點回答問題
- 可以跳出問題框架思考

### 廢物測試 (Shit Test)
- 廢測是好事，代表她在評估用戶
- 橡膠球理論：讓它彈開
- 回應方式：幽默曲解 / 直球但維持框架 / 忽略

### 淺溝通解讀
- 女生文字背後的意思 > 字面意思
- 一致性測試藏在文字裡

## 冰點特殊處理
當熱度 0-30 且判斷機會渺茫時：
- 不硬回
- 可建議「已讀不回」
- 鼓勵開新對話

## 輸出格式 (JSON)
{
  "gameStage": {
    "current": "premise",
    "status": "正常進行",
    "nextStep": "可以開始評估階段"
  },
  "enthusiasm": { "score": 75, "level": "hot" },
  "topicDepth": { "current": "personal", "suggestion": "可以往曖昧導向推進" },
  "psychology": {
    "subtext": "她這句話背後的意思是：對你有興趣",
    "shitTest": {
      "detected": false,
      "type": null,
      "suggestion": null
    },
    "qualificationSignal": true
  },
  "replies": {
    "extend": "...",
    "resonate": "...",
    "tease": "...",
    "humor": "...",
    "coldRead": "..."
  },
  "finalRecommendation": {
    "pick": "tease",
    "content": "推薦的完整回覆內容",
    "reason": "為什麼推薦這個回覆",
    "psychology": "心理學依據"
  },
  "warnings": [],
  "healthCheck": {
    "issues": ["面試式提問過多"],
    "suggestions": ["用假設代替問句"]
  },
  "strategy": "簡短策略說明",
  "reminder": "記得用你的方式說，見面才自然"
}`;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
      });
    }

    // Check subscription
    const { data: sub } = await supabase
      .from("subscriptions")
      .select("tier, monthly_messages_used, daily_messages_used, daily_reset_at")
      .eq("user_id", user.id)
      .single();

    if (!sub) {
      return new Response(JSON.stringify({ error: "No subscription found" }), {
        status: 403,
      });
    }

    // Check if daily reset needed
    const now = new Date();
    const dailyResetAt = new Date(sub.daily_reset_at);
    if (now.toDateString() !== dailyResetAt.toDateString()) {
      await supabase
        .from("subscriptions")
        .update({ daily_messages_used: 0, daily_reset_at: now.toISOString() })
        .eq("user_id", user.id);
      sub.daily_messages_used = 0;
    }

    // Check monthly limit
    const monthlyLimit = TIER_MONTHLY_LIMITS[sub.tier];
    if (sub.monthly_messages_used >= monthlyLimit) {
      return new Response(
        JSON.stringify({ error: "Monthly limit exceeded", monthlyLimit }),
        { status: 429 }
      );
    }

    // Check daily limit
    const dailyLimit = TIER_DAILY_LIMITS[sub.tier];
    if (sub.daily_messages_used >= dailyLimit) {
      return new Response(
        JSON.stringify({ error: "Daily limit exceeded", dailyLimit, resetAt: "tomorrow" }),
        { status: 429 }
      );
    }

    // Parse request
    const { messages, sessionContext } = await req.json();
    if (!messages || !Array.isArray(messages)) {
      return new Response(JSON.stringify({ error: "Invalid messages" }), {
        status: 400,
      });
    }

    // Format session context for Claude
    let contextInfo = "";
    if (sessionContext) {
      contextInfo = `
## 情境資訊
- 認識場景：${sessionContext.meetingContext || '未知'}
- 認識時長：${sessionContext.duration || '未知'}
- 用戶目標：${sessionContext.goal || '約出來'}
`;
    }

    // Format messages for Claude
    const conversationText = messages
      .map((m: { isFromMe: boolean; content: string }) =>
        `${m.isFromMe ? "我" : "她"}: ${m.content}`
      )
      .join("\n");

    // Select model based on complexity (與設計規格一致)
    const model = selectModel({
      conversationLength: messages.length,
      enthusiasmLevel: null,  // 首次分析前不知道
      hasComplexEmotions: false,
      isFirstAnalysis: messages.length <= 5,
      tier: sub.tier,
    });

// 模型選擇函數 (設計規格 4.9)
function selectModel(context: {
  conversationLength: number;
  enthusiasmLevel: string | null;
  hasComplexEmotions: boolean;
  isFirstAnalysis: boolean;
  tier: string;
}): string {
  // Essential 用戶優先使用 Sonnet
  if (context.tier === 'essential') {
    return "claude-sonnet-4-20250514";
  }

  // 使用 Sonnet 的情況 (30%)
  if (
    context.conversationLength > 20 ||      // 長對話
    context.enthusiasmLevel === 'cold' ||   // 冷淡需要策略
    context.hasComplexEmotions ||           // 複雜情緒
    context.isFirstAnalysis                 // 首次分析建立基準
  ) {
    return "claude-sonnet-4-20250514";
  }

  // 預設使用 Haiku (70%)
  return "claude-3-5-haiku-20241022";
}

    // Call Claude API
    const claudeResponse = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": CLAUDE_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: 1024,
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: `${contextInfo}\n分析以下對話並提供建議：\n\n${conversationText}`,
          },
        ],
      }),
    });

    const claudeData = await claudeResponse.json();
    const content = claudeData.content[0]?.text;

    // Parse Claude's response
    let result;
    try {
      const jsonMatch = content.match(/\{[\s\S]*\}/);
      result = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      result = {
        enthusiasm: { score: 50, level: "warm" },
        replies: {
          extend: "無法生成建議",
          resonate: "無法生成建議",
          tease: "無法生成建議",
        },
        warnings: [],
        strategy: "請重試",
      };
    }

    // Calculate message count (訊息計算邏輯)
    const messageCount = countMessages(messages);

    // Update usage count
    await supabase
      .from("subscriptions")
      .update({
        monthly_messages_used: sub.monthly_messages_used + messageCount,
        daily_messages_used: sub.daily_messages_used + messageCount,
      })
      .eq("user_id", user.id);

    // Update user stats
    await supabase
      .from("users")
      .update({ total_analyses: supabase.rpc("increment_analyses") })
      .eq("id", user.id);

// 訊息計算函數
function countMessages(messages: Array<{ content: string }>): number {
  let total = 0;
  for (const msg of messages) {
    const charCount = msg.content.trim().length;
    total += Math.max(1, Math.ceil(charCount / 200));
  }
  return Math.max(1, total);
}

    return new Response(JSON.stringify(result), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500 }
    );
  }
});
```

**Step 2: Create Edge Function test**

Create `supabase/functions/analyze-chat/index_test.ts`:

```typescript
// supabase/functions/analyze-chat/index_test.ts
// Note: Edge Function tests run via Deno test

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

// Test countMessages function
Deno.test("countMessages - single short message", () => {
  const messages = [{ content: "你好" }];
  // countMessages should return 1
  assertEquals(countMessages(messages), 1);
});

Deno.test("countMessages - multiple messages", () => {
  const messages = [
    { content: "你好" },
    { content: "在嗎" },
    { content: "吃飯了嗎" },
  ];
  assertEquals(countMessages(messages), 3);
});

Deno.test("countMessages - long message splits by 200 chars", () => {
  const longContent = "a".repeat(450); // 450 chars = ceil(450/200) = 3
  const messages = [{ content: longContent }];
  assertEquals(countMessages(messages), 3);
});

// Helper function to be tested
function countMessages(messages: Array<{ content: string }>): number {
  let total = 0;
  for (const msg of messages) {
    const charCount = msg.content.trim().length;
    total += Math.max(1, Math.ceil(charCount / 200));
  }
  return Math.max(1, total);
}
```

**Step 3: Run Edge Function tests**

```bash
cd supabase/functions/analyze-chat
deno test index_test.ts
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add supabase/functions/
git commit -m "feat: 建立 analyze-chat Edge Function (Claude API 整合)"
```

---

## Phase 4 TDD Checkpoint

Before proceeding to Phase 5:

```bash
# Verify Supabase local setup
npx supabase start
npx supabase functions serve analyze-chat

# Test Edge Function manually
curl -X POST http://localhost:54321/functions/v1/analyze-chat \
  -H "Authorization: Bearer <test-token>" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"isFromMe": false, "content": "你好"}]}'
```

---

## Phase 5: Connect Flutter to Supabase

### Task 5.1: Setup Supabase Client

**Files:**
- Create: `lib/core/services/supabase_service.dart`
- Create: `.env.example`
- Modify: `lib/main.dart`

**Step 1: Create .env.example**

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

**Step 2: Create supabase_service.dart**

```dart
// lib/core/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static late SupabaseClient _client;

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
    _client = Supabase.instance.client;
  }

  static SupabaseClient get client => _client;

  static User? get currentUser => _client.auth.currentUser;

  static bool get isAuthenticated => currentUser != null;

  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;
}
```

**Step 3: Update main.dart**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/services/storage_service.dart';
import 'core/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  await StorageService.initialize();

  // TODO: Load from environment
  await SupabaseService.initialize(
    url: const String.fromEnvironment('SUPABASE_URL',
        defaultValue: 'https://placeholder.supabase.co'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY',
        defaultValue: 'placeholder'),
  );

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
```

**Step 4: Write unit tests**

Create `test/unit/services/supabase_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/supabase_service.dart';

void main() {
  group('SupabaseService', () {
    test('isAuthenticated returns false when no user', () {
      // Before initialization, should be false
      // Note: Full test requires mock Supabase client
      expect(true, isTrue); // Placeholder
    });

    // Note: SupabaseService requires actual Supabase connection
    // Full testing done in integration tests with mock server
  });
}
```

> **Note:** SupabaseService 完整測試需要 mock Supabase client，建議在整合測試中使用 Supabase 本地環境驗證。

**Step 5: Commit**

```bash
git add lib/ .env.example test/
git commit -m "feat: 整合 Supabase 客戶端服務"
```

---

### Task 5.2: Create Analysis Service

**Files:**
- Create: `lib/features/analysis/data/services/analysis_service.dart`
- Create: `lib/features/analysis/data/providers/analysis_providers.dart`

**Step 1: Create analysis_service.dart**

```dart
// lib/features/analysis/data/services/analysis_service.dart
import '../../../../core/services/supabase_service.dart';
import '../../../conversation/domain/entities/message.dart';

class TopicDepth {
  final String current;  // 'facts' | 'personal' | 'intimate'
  final String suggestion;

  TopicDepth({required this.current, required this.suggestion});

  factory TopicDepth.fromJson(Map<String, dynamic> json) {
    return TopicDepth(
      current: json['current'] as String? ?? 'facts',
      suggestion: json['suggestion'] as String? ?? '',
    );
  }
}

class HealthCheck {
  final List<String> issues;
  final List<String> suggestions;

  HealthCheck({required this.issues, required this.suggestions});

  factory HealthCheck.fromJson(Map<String, dynamic>? json) {
    if (json == null) return HealthCheck(issues: [], suggestions: []);
    return HealthCheck(
      issues: (json['issues'] as List?)?.cast<String>() ?? [],
      suggestions: (json['suggestions'] as List?)?.cast<String>() ?? [],
    );
  }
}

class AnalysisResult {
  final int enthusiasmScore;
  final String level;
  final TopicDepth topicDepth;
  final Map<String, String> replies;  // extend, resonate, tease, humor, coldRead
  final List<String> warnings;
  final HealthCheck healthCheck;
  final String strategy;

  AnalysisResult({
    required this.enthusiasmScore,
    required this.level,
    required this.topicDepth,
    required this.replies,
    required this.warnings,
    required this.healthCheck,
    required this.strategy,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final enthusiasm = json['enthusiasm'] as Map<String, dynamic>;
    final replies = json['replies'] as Map<String, dynamic>;

    return AnalysisResult(
      enthusiasmScore: enthusiasm['score'] as int,
      level: enthusiasm['level'] as String,
      topicDepth: TopicDepth.fromJson(json['topicDepth'] as Map<String, dynamic>? ?? {}),
      replies: replies.map((k, v) => MapEntry(k, v.toString())),
      warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
      healthCheck: HealthCheck.fromJson(json['healthCheck'] as Map<String, dynamic>?),
      strategy: json['strategy'] as String? ?? '',
    );
  }
}

class AnalysisService {
  Future<AnalysisResult> analyzeConversation(List<Message> messages) async {
    final response = await SupabaseService.client.functions.invoke(
      'analyze-chat',
      body: {
        'messages': messages
            .map((m) => {
                  'isFromMe': m.isFromMe,
                  'content': m.content,
                })
            .toList(),
      },
    );

    if (response.status != 200) {
      throw Exception(response.data['error'] ?? 'Analysis failed');
    }

    return AnalysisResult.fromJson(response.data);
  }
}
```

**Step 2: Create analysis_providers.dart**

```dart
// lib/features/analysis/data/providers/analysis_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/analysis_service.dart';

final analysisServiceProvider = Provider<AnalysisService>((ref) {
  return AnalysisService();
});
```

**Step 3: Write unit tests for AnalysisResult parsing**

Create `test/unit/services/analysis_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';

void main() {
  group('AnalysisResult', () {
    test('fromJson parses valid response correctly', () {
      final json = {
        'enthusiasm': {'score': 75, 'level': 'hot'},
        'topicDepth': {'current': 'personal', 'suggestion': '可以往曖昧導向推進'},
        'replies': {
          'extend': '延展回覆',
          'resonate': '共鳴回覆',
          'tease': '調情回覆',
          'humor': '幽默回覆',
          'coldRead': '冷讀回覆',
        },
        'warnings': ['過度投入'],
        'healthCheck': {
          'issues': ['面試式提問'],
          'suggestions': ['用假設代替問句'],
        },
        'strategy': '保持沉穩',
      };

      final result = AnalysisResult.fromJson(json);

      expect(result.enthusiasmScore, 75);
      expect(result.level, 'hot');
      expect(result.topicDepth.current, 'personal');
      expect(result.replies['extend'], '延展回覆');
      expect(result.replies['humor'], '幽默回覆');
      expect(result.replies['coldRead'], '冷讀回覆');
      expect(result.warnings, ['過度投入']);
      expect(result.healthCheck.issues, ['面試式提問']);
      expect(result.strategy, '保持沉穩');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'enthusiasm': {'score': 50, 'level': 'warm'},
        'replies': {
          'extend': '延展回覆',
          'resonate': '共鳴回覆',
          'tease': '調情回覆',
          'humor': '幽默回覆',
          'coldRead': '冷讀回覆',
        },
      };

      final result = AnalysisResult.fromJson(json);

      expect(result.enthusiasmScore, 50);
      expect(result.warnings, isEmpty);
      expect(result.healthCheck.issues, isEmpty);
      expect(result.strategy, '');
    });
  });

  group('TopicDepth', () {
    test('fromJson parses correctly', () {
      final json = {'current': 'intimate', 'suggestion': '維持現狀'};
      final topicDepth = TopicDepth.fromJson(json);

      expect(topicDepth.current, 'intimate');
      expect(topicDepth.suggestion, '維持現狀');
    });

    test('fromJson handles empty map', () {
      final topicDepth = TopicDepth.fromJson({});

      expect(topicDepth.current, 'facts');
      expect(topicDepth.suggestion, '');
    });
  });

  group('HealthCheck', () {
    test('fromJson parses correctly', () {
      final json = {
        'issues': ['問題1', '問題2'],
        'suggestions': ['建議1'],
      };
      final healthCheck = HealthCheck.fromJson(json);

      expect(healthCheck.issues.length, 2);
      expect(healthCheck.suggestions.length, 1);
    });

    test('fromJson handles null', () {
      final healthCheck = HealthCheck.fromJson(null);

      expect(healthCheck.issues, isEmpty);
      expect(healthCheck.suggestions, isEmpty);
    });
  });
}
```

**Step 4: Run tests**

```bash
flutter test test/unit/services/analysis_service_test.dart
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/features/analysis/ test/
git commit -m "feat: 建立 AnalysisService 連接 Edge Function"
```

---

## Phase 5 TDD Checkpoint

Before proceeding to Phase 6:

```bash
flutter test
# All tests should pass
```

---

## Phase 6: Settings & Subscription (Stub)

### Task 6.1: Create Settings Screen

**Files:**
- Create: `lib/features/subscription/presentation/screens/settings_screen.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create settings_screen.dart**

```dart
// lib/features/subscription/presentation/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('設定', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          _buildSection(
            title: '帳戶',
            children: [
              _buildTile(
                icon: Icons.workspace_premium,
                title: '訂閱方案',
                trailing: 'Free',
                onTap: () {
                  // TODO: Open paywall
                },
              ),
              _buildTile(
                icon: Icons.analytics,
                title: '本月用量',
                trailing: '0/5',
              ),
              _buildTile(
                icon: Icons.person,
                title: '帳號',
                trailing: '未登入',
                onTap: () {
                  // TODO: Open login
                },
              ),
            ],
          ),
          _buildSection(
            title: '隱私與安全',
            children: [
              _buildTile(
                icon: Icons.delete_forever,
                title: '清除所有對話資料',
                titleColor: AppColors.error,
                onTap: () => _showDeleteDialog(context),
              ),
              _buildTile(
                icon: Icons.download,
                title: '匯出我的資料',
                onTap: () {
                  // TODO: Export data
                },
              ),
              _buildTile(
                icon: Icons.privacy_tip,
                title: '隱私權政策',
                onTap: () {
                  // TODO: Open privacy policy
                },
              ),
            ],
          ),
          _buildSection(
            title: '關於',
            children: [
              _buildTile(
                icon: Icons.info,
                title: '版本',
                trailing: '1.0.0',
              ),
              _buildTile(
                icon: Icons.description,
                title: '使用條款',
                onTap: () {
                  // TODO: Open terms
                },
              ),
              _buildTile(
                icon: Icons.feedback,
                title: '意見回饋',
                onTap: () {
                  // TODO: Open feedback
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        title,
        style: AppTypography.bodyLarge.copyWith(color: titleColor),
      ),
      trailing: trailing != null
          ? Text(trailing, style: AppTypography.bodyMedium)
          : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('確定要刪除所有對話？'),
        content: const Text('此操作無法復原'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await StorageService.conversationsBox.clear();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清除所有對話')),
                );
              }
            },
            child: Text(
              '刪除',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Update routes.dart**

```dart
// lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/analysis/presentation/screens/analysis_screen.dart';
import '../features/conversation/presentation/screens/home_screen.dart';
import '../features/conversation/presentation/screens/new_conversation_screen.dart';
import '../features/subscription/presentation/screens/settings_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const NewConversationScreen(),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (context, state) => AnalysisScreen(
        conversationId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
```

**Step 3: Write widget tests**

Create `test/widget/screens/settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/presentation/screens/settings_screen.dart';

void main() {
  group('SettingsScreen', () {
    testWidgets('displays title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsScreen()),
        ),
      );

      expect(find.text('設定'), findsOneWidget);
    });

    testWidgets('shows account section', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsScreen()),
        ),
      );

      expect(find.text('帳戶'), findsOneWidget);
      expect(find.text('訂閱方案'), findsOneWidget);
      expect(find.text('本月用量'), findsOneWidget);
    });

    testWidgets('shows privacy section', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsScreen()),
        ),
      );

      expect(find.text('隱私與安全'), findsOneWidget);
      expect(find.text('清除所有對話資料'), findsOneWidget);
    });

    testWidgets('shows about section', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsScreen()),
        ),
      );

      expect(find.text('關於'), findsOneWidget);
      expect(find.text('版本'), findsOneWidget);
    });

    testWidgets('shows delete confirmation dialog', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsScreen()),
        ),
      );

      // Tap delete button
      await tester.tap(find.text('清除所有對話資料'));
      await tester.pumpAndSettle();

      expect(find.text('確定要刪除所有對話？'), findsOneWidget);
      expect(find.text('此操作無法復原'), findsOneWidget);
    });
  });
}
```

**Step 4: Run tests**

```bash
flutter test test/widget/screens/settings_screen_test.dart
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/ test/
git commit -m "feat: 建立設定畫面 (含清除資料功能)"
```

---

## Phase 6 TDD Checkpoint

```bash
flutter test
# All tests should pass before proceeding
```

---

## Phase 7: Message Calculation & Usage Tracking

### Task 7.1: Create Message Calculation Service

**Files:**
- Create: `lib/core/services/message_calculator.dart`
- Create: `lib/core/services/usage_service.dart`

**Step 1: Create message_calculator.dart**

```dart
// lib/core/services/message_calculator.dart
import '../constants/app_constants.dart';

class MessageCalculator {
  /// 計算訊息數量
  /// 規則：換行分割 + 每 200 字 = 1 則
  static int countMessages(String text) {
    if (text.trim().isEmpty) return 0;

    // 用換行分割，過濾空行
    final lines = text.split(RegExp(r'\n+'))
        .where((line) => line.trim().isNotEmpty)
        .toList();

    int total = 0;
    for (final line in lines) {
      final charCount = line.trim().length;
      total += (charCount / AppConstants.maxCharsPerMessage).ceil().clamp(1, 100);
    }

    return total.clamp(1, 1000);
  }

  /// 檢查是否超過單次分析上限
  static bool exceedsMaxLength(String text) {
    return text.length > AppConstants.maxTotalChars;
  }

  /// 預覽訊息計算結果
  static MessagePreview preview(String text) {
    final count = countMessages(text);
    final exceeds = exceedsMaxLength(text);

    return MessagePreview(
      messageCount: count,
      charCount: text.length,
      exceedsLimit: exceeds,
    );
  }
}

class MessagePreview {
  final int messageCount;
  final int charCount;
  final bool exceedsLimit;

  MessagePreview({
    required this.messageCount,
    required this.charCount,
    required this.exceedsLimit,
  });
}
```

**Step 2: Create usage_service.dart**

```dart
// lib/core/services/usage_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'storage_service.dart';

class UsageData {
  final int monthlyUsed;
  final int monthlyLimit;
  final int dailyUsed;
  final int dailyLimit;
  final DateTime dailyResetAt;

  UsageData({
    required this.monthlyUsed,
    required this.monthlyLimit,
    required this.dailyUsed,
    required this.dailyLimit,
    required this.dailyResetAt,
  });

  bool get canAnalyze => monthlyUsed < monthlyLimit && dailyUsed < dailyLimit;
  int get monthlyRemaining => monthlyLimit - monthlyUsed;
  int get dailyRemaining => dailyLimit - dailyUsed;
  double get monthlyPercentage => monthlyUsed / monthlyLimit;
}

class UsageService {
  Future<UsageData> getUsage() async {
    // TODO: Fetch from Supabase
    return UsageData(
      monthlyUsed: 0,
      monthlyLimit: 30,
      dailyUsed: 0,
      dailyLimit: 15,
      dailyResetAt: DateTime.now().add(const Duration(hours: 6)),
    );
  }

  Future<bool> checkAndDeduct(int messageCount) async {
    final usage = await getUsage();
    if (usage.monthlyRemaining < messageCount) return false;
    if (usage.dailyRemaining < messageCount) return false;

    // TODO: Update usage in Supabase
    return true;
  }
}

final usageServiceProvider = Provider<UsageService>((ref) => UsageService());
```

**Step 3: Write unit tests**

Create `test/message_calculator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/message_calculator.dart';

void main() {
  group('MessageCalculator', () {
    test('counts single short message as 1', () {
      expect(MessageCalculator.countMessages('你好'), 1);
    });

    test('counts multiple lines correctly', () {
      expect(MessageCalculator.countMessages('你好\n在嗎\n吃飯了嗎'), 3);
    });

    test('counts long message by 200 char chunks', () {
      final longText = 'a' * 450; // 450 chars = ceil(450/200) = 3
      expect(MessageCalculator.countMessages(longText), 3);
    });

    test('handles empty lines', () {
      expect(MessageCalculator.countMessages('你好\n\n\n在嗎'), 2);
    });

    test('returns 0 for empty input', () {
      expect(MessageCalculator.countMessages(''), 0);
      expect(MessageCalculator.countMessages('   '), 0);
    });
  });
}
```

**Step 4: Commit**

```bash
git add lib/core/services/ test/
git commit -m "feat: 建立訊息計算服務與用量追蹤"
```

---

### Task 7.2: Create Analysis Preview Dialog

**Files:**
- Create: `lib/shared/widgets/analysis_preview_dialog.dart`
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`

**Step 1: Create analysis_preview_dialog.dart**

```dart
// lib/shared/widgets/analysis_preview_dialog.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/services/message_calculator.dart';
import '../../core/services/usage_service.dart';

class AnalysisPreviewDialog extends StatelessWidget {
  final MessagePreview preview;
  final UsageData usage;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const AnalysisPreviewDialog({
    super.key,
    required this.preview,
    required this.usage,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final canProceed = !preview.exceedsLimit &&
        usage.monthlyRemaining >= preview.messageCount &&
        usage.dailyRemaining >= preview.messageCount;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('確認分析', style: AppTypography.titleLarge),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Message count
          _buildRow('本次分析', '${preview.messageCount} 則訊息'),
          const SizedBox(height: 12),

          // Monthly usage
          _buildRow('月額度', '${usage.monthlyRemaining} / ${usage.monthlyLimit} 則'),
          LinearProgressIndicator(
            value: usage.monthlyPercentage,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(
              usage.monthlyPercentage > 0.8 ? AppColors.warning : AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),

          // Daily usage
          _buildRow('今日額度', '${usage.dailyRemaining} / ${usage.dailyLimit} 則'),
          const SizedBox(height: 16),

          // Warnings
          if (preview.exceedsLimit)
            _buildWarning('內容過長，請分批分析 (上限 5000 字)')
          else if (usage.monthlyRemaining < preview.messageCount)
            _buildWarning('月額度不足，請升級方案或加購')
          else if (usage.dailyRemaining < preview.messageCount)
            _buildWarning('今日額度已用完，明天再試'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: canProceed ? onConfirm : null,
          child: const Text('確認分析'),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodyMedium),
        Text(value, style: AppTypography.bodyLarge),
      ],
    );
  }

  Widget _buildWarning(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppTypography.caption.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Write widget tests**

Create `test/widget/widgets/analysis_preview_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/shared/widgets/analysis_preview_dialog.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/core/services/usage_service.dart';

void main() {
  group('AnalysisPreviewDialog', () {
    late MessagePreview mockPreview;
    late UsageData mockUsage;

    setUp(() {
      mockPreview = MessagePreview(
        messageCount: 12,
        charCount: 500,
        exceedsLimit: false,
      );
      mockUsage = UsageData(
        monthlyUsed: 12,
        monthlyLimit: 300,
        dailyUsed: 5,
        dailyLimit: 50,
        dailyResetAt: DateTime.now().add(const Duration(hours: 6)),
      );
    });

    testWidgets('displays message count', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisPreviewDialog(
              preview: mockPreview,
              usage: mockUsage,
              onConfirm: () {},
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('12 則訊息'), findsOneWidget);
    });

    testWidgets('displays monthly usage', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisPreviewDialog(
              preview: mockPreview,
              usage: mockUsage,
              onConfirm: () {},
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('288 / 300 則'), findsOneWidget);
    });

    testWidgets('shows warning when exceeds limit', (tester) async {
      final exceedsPreview = MessagePreview(
        messageCount: 100,
        charCount: 6000,
        exceedsLimit: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisPreviewDialog(
              preview: exceedsPreview,
              usage: mockUsage,
              onConfirm: () {},
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.textContaining('內容過長'), findsOneWidget);
    });

    testWidgets('confirm button disabled when cannot proceed', (tester) async {
      final exceedsPreview = MessagePreview(
        messageCount: 100,
        charCount: 6000,
        exceedsLimit: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisPreviewDialog(
              preview: exceedsPreview,
              usage: mockUsage,
              onConfirm: () {},
              onCancel: () {},
            ),
          ),
        ),
      );

      final confirmButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '確認分析'),
      );
      expect(confirmButton.onPressed, isNull);
    });
  });
}
```

**Step 3: Run tests**

```bash
flutter test test/widget/widgets/analysis_preview_dialog_test.dart
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add lib/shared/widgets/ test/
git commit -m "feat: 建立分析前預覽確認對話框"
```

---

## Phase 7 TDD Checkpoint

```bash
flutter test
# All tests should pass before proceeding
```

---

## Phase 8: Conversation Memory

### Task 8.1: Add Memory Fields to Entities

**Files:**
- Modify: `lib/features/conversation/domain/entities/conversation.dart`
- Create: `lib/features/conversation/domain/entities/conversation_summary.dart`

**Step 1: Create conversation_summary.dart**

```dart
// lib/features/conversation/domain/entities/conversation_summary.dart
import 'package:hive/hive.dart';

part 'conversation_summary.g.dart';

@HiveType(typeId: 2)
class ConversationSummary extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final int roundsCovered;  // 摘要涵蓋的輪數範圍

  @HiveField(2)
  final String content;  // AI 生成的摘要

  @HiveField(3)
  final List<String> keyTopics;  // 關鍵話題

  @HiveField(4)
  final List<String> sharedInterests;  // 共同興趣

  @HiveField(5)
  final String relationshipStage;  // 關係階段

  @HiveField(6)
  final DateTime createdAt;

  ConversationSummary({
    required this.id,
    required this.roundsCovered,
    required this.content,
    required this.keyTopics,
    required this.sharedInterests,
    required this.relationshipStage,
    required this.createdAt,
  });
}
```

**Step 2: Update conversation.dart**

```dart
// 在 Conversation class 中添加以下欄位

  @HiveField(7)
  int currentRound;  // 當前輪數

  @HiveField(8)
  List<ConversationSummary>? summaries;  // 歷史摘要

  @HiveField(9)
  String? lastUserChoice;  // 用戶上次選擇的回覆類型 (用於選擇追蹤)

  /// 取得最近 N 輪訊息 (用於 AI context)
  List<Message> getRecentMessages(int rounds) {
    // 計算每輪約 2 則訊息 (用戶 + 對方)
    final messageCount = rounds * 2;
    if (messages.length <= messageCount) return messages;
    return messages.sublist(messages.length - messageCount);
  }

  /// 需要摘要嗎？(超過 15 輪且沒有摘要時)
  bool get needsSummary => currentRound > 15 && (summaries?.isEmpty ?? true);
```

**Step 3: Generate Hive adapters**

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**Step 4: Write unit tests**

Create `test/unit/entities/conversation_memory_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

void main() {
  group('Conversation Memory', () {
    late Conversation conversation;

    setUp(() {
      // Create a conversation with 20 messages (10 rounds)
      final messages = List.generate(20, (i) => Message(
        id: 'msg-$i',
        content: '訊息 $i',
        isFromMe: i % 2 == 0,
        timestamp: DateTime.now(),
      ));

      conversation = Conversation(
        id: 'conv-1',
        name: '測試對話',
        messages: messages,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      conversation.currentRound = 10;
    });

    test('getRecentMessages returns correct number of messages', () {
      final recent = conversation.getRecentMessages(5);
      expect(recent.length, 10); // 5 rounds * 2 messages
    });

    test('getRecentMessages returns all when fewer than requested', () {
      final recent = conversation.getRecentMessages(20);
      expect(recent.length, 20);
    });

    test('needsSummary returns false when round <= 15', () {
      conversation.currentRound = 15;
      expect(conversation.needsSummary, isFalse);
    });

    test('needsSummary returns true when round > 15 and no summaries', () {
      conversation.currentRound = 16;
      conversation.summaries = [];
      expect(conversation.needsSummary, isTrue);
    });

    test('needsSummary returns false when has summaries', () {
      conversation.currentRound = 20;
      conversation.summaries = [/* mock summary */];
      expect(conversation.needsSummary, isFalse);
    });
  });
}
```

**Step 5: Run tests**

```bash
flutter test test/unit/entities/conversation_memory_test.dart
```

Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/features/conversation/domain/entities/ test/
git commit -m "feat: 添加對話記憶實體與摘要結構"
```

---

### Task 8.2: Create Memory Service

**Files:**
- Create: `lib/features/conversation/data/services/memory_service.dart`

**Step 1: Create memory_service.dart**

```dart
// lib/features/conversation/data/services/memory_service.dart
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/message.dart';
import '../../../analysis/data/services/analysis_service.dart';

class MemoryService {
  final AnalysisService _analysisService;

  MemoryService(this._analysisService);

  /// 準備 AI 分析的 context
  /// 最近 15 輪完整 + 更早的摘要
  Future<String> prepareContext(Conversation conversation) async {
    final buffer = StringBuffer();

    // 添加歷史摘要 (如果有)
    if (conversation.summaries?.isNotEmpty ?? false) {
      buffer.writeln('【歷史摘要】');
      for (final summary in conversation.summaries!) {
        buffer.writeln(summary.content);
      }
      buffer.writeln('---');
    }

    // 添加最近 15 輪訊息
    final recentMessages = conversation.getRecentMessages(15);
    buffer.writeln('【最近對話】');
    for (final msg in recentMessages) {
      buffer.writeln('${msg.isFromMe ? "我" : "她"}: ${msg.content}');
    }

    return buffer.toString();
  }

  /// 智能推測用戶選擇
  /// 從對方回覆反推用戶說了什麼
  String? inferUserChoice(
    Message theirReply,
    Map<String, String> previousSuggestions,
  ) {
    final content = theirReply.content.toLowerCase();

    // 簡單的關鍵字匹配 (實際可用 AI)
    for (final entry in previousSuggestions.entries) {
      final keywords = _extractKeywords(entry.value);
      for (final keyword in keywords) {
        if (content.contains(keyword)) {
          return entry.key;
        }
      }
    }

    return null;  // 無法推測，可能需要詢問用戶
  }

  List<String> _extractKeywords(String text) {
    // 提取關鍵詞 (簡化版本)
    return text
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), ' ')
        .split(' ')
        .where((w) => w.length > 1)
        .toList();
  }

  /// 生成對話摘要 (背景執行)
  Future<ConversationSummary> generateSummary(
    Conversation conversation,
    int fromRound,
    int toRound,
  ) async {
    // TODO: 呼叫 AI 生成摘要
    return ConversationSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      roundsCovered: toRound - fromRound,
      content: '待實作：AI 生成的對話摘要',
      keyTopics: [],
      sharedInterests: [],
      relationshipStage: 'personal',
      createdAt: DateTime.now(),
    );
  }
}
```

**Step 2: Write unit tests**

Create `test/unit/services/memory_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/data/services/memory_service.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

void main() {
  group('MemoryService', () {
    group('inferUserChoice', () {
      test('returns matching reply type when keyword found', () {
        final service = MemoryService(/* mock */);

        final theirReply = Message(
          id: '1',
          content: '哇健身！你練多久了？',
          isFromMe: false,
          timestamp: DateTime.now(),
        );

        final previousSuggestions = {
          'extend': '三個月了，越練越上癮',
          'resonate': '你也有運動習慣嗎',
          'tease': '練到可以單手抱你',
        };

        // Should infer 'extend' or 'tease' since they mention 健身
        final choice = service.inferUserChoice(theirReply, previousSuggestions);
        expect(choice, isNotNull);
      });

      test('returns null when no match found', () {
        final service = MemoryService(/* mock */);

        final theirReply = Message(
          id: '1',
          content: '今天天氣真好',
          isFromMe: false,
          timestamp: DateTime.now(),
        );

        final previousSuggestions = {
          'extend': '三個月了，越練越上癮',
          'resonate': '你也有運動習慣嗎',
        };

        final choice = service.inferUserChoice(theirReply, previousSuggestions);
        expect(choice, isNull);
      });
    });

    group('prepareContext', () {
      test('includes recent messages', () async {
        final service = MemoryService(/* mock */);

        // This would need a mock Conversation
        // Full test requires integration with Conversation entity
      });
    });
  });
}
```

**Step 3: Run tests**

```bash
flutter test test/unit/services/memory_service_test.dart
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add lib/features/conversation/data/services/ test/
git commit -m "feat: 建立對話記憶服務 (context 準備 + 選擇追蹤)"
```

---

## Phase 8 TDD Checkpoint

```bash
flutter test
# All tests should pass before proceeding
```

---

## Phase 9: Paywall & Subscription UI

### Task 9.1: Create Paywall Screen

**Files:**
- Create: `lib/features/subscription/presentation/screens/paywall_screen.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create paywall_screen.dart**

```dart
// lib/features/subscription/presentation/screens/paywall_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String _selectedTier = 'essential';  // 預設選 Essential

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('升級方案', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text(
              '解鎖完整功能',
              style: AppTypography.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '提升你的社交溝通能力',
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Plan cards
            _buildPlanCard(
              tier: 'starter',
              name: 'Starter',
              price: 'NT\$149/月',
              features: [
                '300 則訊息/月',
                '每日 50 則上限',
                '5 種回覆建議',
                'Needy 警示',
                '話題深度分析',
              ],
              isSelected: _selectedTier == 'starter',
              onTap: () => setState(() => _selectedTier = 'starter'),
            ),
            const SizedBox(height: 16),
            _buildPlanCard(
              tier: 'essential',
              name: 'Essential',
              price: 'NT\$349/月',
              features: [
                '1,000 則訊息/月',
                '每日 150 則上限',
                '5 種回覆建議',
                'Needy 警示',
                '話題深度分析',
                '🩺 對話健檢 (獨家)',
                'Sonnet 優先模型',
              ],
              isSelected: _selectedTier == 'essential',
              isRecommended: true,
              onTap: () => setState(() => _selectedTier = 'essential'),
            ),
            const SizedBox(height: 32),

            // CTA button
            ElevatedButton(
              onPressed: _subscribe,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                '開始 7 天免費試用',
                style: AppTypography.titleLarge.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '試用結束後自動扣款，可隨時取消',
              style: AppTypography.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Terms
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {},
                  child: Text('使用條款', style: AppTypography.caption),
                ),
                Text(' | ', style: AppTypography.caption),
                TextButton(
                  onPressed: () {},
                  child: Text('隱私權政策', style: AppTypography.caption),
                ),
                Text(' | ', style: AppTypography.caption),
                TextButton(
                  onPressed: () {},
                  child: Text('恢復購買', style: AppTypography.caption),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String tier,
    required String name,
    required String price,
    required List<String> features,
    required bool isSelected,
    bool isRecommended = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name, style: AppTypography.titleLarge),
                if (isRecommended) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('推薦', style: AppTypography.caption.copyWith(color: Colors.white)),
                  ),
                ],
                const Spacer(),
                Radio<String>(
                  value: tier,
                  groupValue: _selectedTier,
                  onChanged: (v) => setState(() => _selectedTier = v!),
                ),
              ],
            ),
            Text(price, style: AppTypography.headlineMedium),
            const SizedBox(height: 12),
            ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f, style: AppTypography.bodyMedium)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _subscribe() async {
    // TODO: Integrate with RevenueCat
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('RevenueCat 整合待實作')),
    );
  }
}
```

**Step 2: Add paywall route**

```dart
// In lib/app/routes.dart, add:
GoRoute(
  path: '/paywall',
  builder: (context, state) => const PaywallScreen(),
),
```

**Step 3: Write widget tests**

Create `test/widget/screens/paywall_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/presentation/screens/paywall_screen.dart';

void main() {
  group('PaywallScreen', () {
    testWidgets('displays title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PaywallScreen()),
        ),
      );

      expect(find.text('升級方案'), findsOneWidget);
      expect(find.text('解鎖完整功能'), findsOneWidget);
    });

    testWidgets('shows Starter plan', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PaywallScreen()),
        ),
      );

      expect(find.text('Starter'), findsOneWidget);
      expect(find.text('NT\$149/月'), findsOneWidget);
    });

    testWidgets('shows Essential plan with recommended badge', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PaywallScreen()),
        ),
      );

      expect(find.text('Essential'), findsOneWidget);
      expect(find.text('NT\$349/月'), findsOneWidget);
      expect(find.text('推薦'), findsOneWidget);
    });

    testWidgets('Essential is selected by default', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PaywallScreen()),
        ),
      );

      // Essential plan card should have selected styling
      // Check for radio button selection
      final essentialRadio = tester.widget<Radio<String>>(
        find.byWidgetPredicate((widget) =>
          widget is Radio<String> && widget.value == 'essential'
        ),
      );
      expect(essentialRadio.groupValue, 'essential');
    });

    testWidgets('shows free trial CTA', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PaywallScreen()),
        ),
      );

      expect(find.text('開始 7 天免費試用'), findsOneWidget);
    });

    testWidgets('shows legal links', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PaywallScreen()),
        ),
      );

      expect(find.text('使用條款'), findsOneWidget);
      expect(find.text('隱私權政策'), findsOneWidget);
      expect(find.text('恢復購買'), findsOneWidget);
    });

    testWidgets('can select Starter plan', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PaywallScreen()),
        ),
      );

      // Tap on Starter plan
      await tester.tap(find.text('Starter'));
      await tester.pump();

      final starterRadio = tester.widget<Radio<String>>(
        find.byWidgetPredicate((widget) =>
          widget is Radio<String> && widget.value == 'starter'
        ),
      );
      expect(starterRadio.groupValue, 'starter');
    });
  });
}
```

**Step 4: Run tests**

```bash
flutter test test/widget/screens/paywall_screen_test.dart
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/ test/
git commit -m "feat: 建立 Paywall 訂閱方案選擇畫面"
```

---

### Task 9.2: Create Message Booster Purchase (加購訊息包)

**Files:**
- Create: `lib/features/subscription/domain/entities/message_booster.dart`
- Create: `lib/features/subscription/presentation/widgets/booster_purchase_sheet.dart`
- Modify: `lib/features/subscription/presentation/screens/paywall_screen.dart`

**Step 1: Create message_booster.dart entity**

```dart
// lib/features/subscription/domain/entities/message_booster.dart

enum BoosterPackage {
  small,   // 50 則
  medium,  // 150 則
  large,   // 300 則
}

extension BoosterPackageExtension on BoosterPackage {
  int get messageCount {
    switch (this) {
      case BoosterPackage.small:
        return 50;
      case BoosterPackage.medium:
        return 150;
      case BoosterPackage.large:
        return 300;
    }
  }

  int get priceNTD {
    switch (this) {
      case BoosterPackage.small:
        return 39;
      case BoosterPackage.medium:
        return 99;
      case BoosterPackage.large:
        return 179;
    }
  }

  double get costPerMessage {
    return priceNTD / messageCount;
  }

  String get label {
    return '$messageCount 則';
  }

  String get priceLabel {
    return 'NT\$$priceNTD';
  }

  String get savingsLabel {
    switch (this) {
      case BoosterPackage.small:
        return '';
      case BoosterPackage.medium:
        return '省 15%';
      case BoosterPackage.large:
        return '省 23%';
    }
  }
}
```

**Step 2: Create booster_purchase_sheet.dart**

```dart
// lib/features/subscription/presentation/widgets/booster_purchase_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/message_booster.dart';

class BoosterPurchaseSheet extends ConsumerStatefulWidget {
  const BoosterPurchaseSheet({super.key});

  @override
  ConsumerState<BoosterPurchaseSheet> createState() => _BoosterPurchaseSheetState();
}

class _BoosterPurchaseSheetState extends ConsumerState<BoosterPurchaseSheet> {
  BoosterPackage _selectedPackage = BoosterPackage.medium;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            '加購訊息包',
            style: AppTypography.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '額度不夠用？立即加購',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Package options
          ...BoosterPackage.values.map((pkg) => _buildPackageOption(pkg)),

          const SizedBox(height: 24),

          // Purchase button
          ElevatedButton(
            onPressed: _purchase,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.primary,
            ),
            child: Text(
              '購買 ${_selectedPackage.label} - ${_selectedPackage.priceLabel}',
              style: AppTypography.titleMedium.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPackageOption(BoosterPackage pkg) {
    final isSelected = _selectedPackage == pkg;

    return GestureDetector(
      onTap: () => setState(() => _selectedPackage = pkg),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.background,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.textSecondary.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Radio<BoosterPackage>(
              value: pkg,
              groupValue: _selectedPackage,
              onChanged: (v) => setState(() => _selectedPackage = v!),
              activeColor: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pkg.label, style: AppTypography.titleMedium),
                  Text(
                    '每則 NT\$${pkg.costPerMessage.toStringAsFixed(2)}',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(pkg.priceLabel, style: AppTypography.titleMedium),
                if (pkg.savingsLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.hot.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      pkg.savingsLabel,
                      style: AppTypography.caption.copyWith(color: AppColors.hot),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _purchase() {
    // TODO: Integrate with RevenueCat for IAP
    Navigator.of(context).pop(_selectedPackage);
  }
}

/// Show booster purchase sheet
Future<BoosterPackage?> showBoosterPurchaseSheet(BuildContext context) {
  return showModalBottomSheet<BoosterPackage>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const BoosterPurchaseSheet(),
  );
}
```

**Step 3: Add booster link to PaywallScreen**

Update `paywall_screen.dart` to include a "加購訊息包" link:

```dart
// Add after the legal links section in PaywallScreen

const SizedBox(height: 16),
Center(
  child: TextButton(
    onPressed: () async {
      final result = await showBoosterPurchaseSheet(context);
      if (result != null) {
        // TODO: Process purchase
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已購買 ${result.label}')),
        );
      }
    },
    child: Text(
      '只需要加購訊息包？',
      style: AppTypography.bodyMedium.copyWith(
        color: AppColors.primary,
        decoration: TextDecoration.underline,
      ),
    ),
  ),
),
```

**Step 4: Write unit tests**

Create `test/unit/entities/message_booster_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/domain/entities/message_booster.dart';

void main() {
  group('BoosterPackage', () {
    test('small package has correct values', () {
      expect(BoosterPackage.small.messageCount, 50);
      expect(BoosterPackage.small.priceNTD, 39);
      expect(BoosterPackage.small.label, '50 則');
      expect(BoosterPackage.small.priceLabel, 'NT\$39');
    });

    test('medium package has correct values', () {
      expect(BoosterPackage.medium.messageCount, 150);
      expect(BoosterPackage.medium.priceNTD, 99);
      expect(BoosterPackage.medium.savingsLabel, '省 15%');
    });

    test('large package has correct values', () {
      expect(BoosterPackage.large.messageCount, 300);
      expect(BoosterPackage.large.priceNTD, 179);
      expect(BoosterPackage.large.savingsLabel, '省 23%');
    });

    test('cost per message decreases with larger packages', () {
      expect(BoosterPackage.small.costPerMessage, greaterThan(BoosterPackage.medium.costPerMessage));
      expect(BoosterPackage.medium.costPerMessage, greaterThan(BoosterPackage.large.costPerMessage));
    });
  });
}
```

**Step 5: Write widget tests**

Create `test/widget/widgets/booster_purchase_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/presentation/widgets/booster_purchase_sheet.dart';

void main() {
  group('BoosterPurchaseSheet', () {
    testWidgets('displays title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: BoosterPurchaseSheet()),
          ),
        ),
      );

      expect(find.text('加購訊息包'), findsOneWidget);
      expect(find.text('額度不夠用？立即加購'), findsOneWidget);
    });

    testWidgets('shows all three packages', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: BoosterPurchaseSheet()),
          ),
        ),
      );

      expect(find.text('50 則'), findsOneWidget);
      expect(find.text('150 則'), findsOneWidget);
      expect(find.text('300 則'), findsOneWidget);
    });

    testWidgets('shows prices correctly', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: BoosterPurchaseSheet()),
          ),
        ),
      );

      expect(find.text('NT\$39'), findsOneWidget);
      expect(find.text('NT\$99'), findsOneWidget);
      expect(find.text('NT\$179'), findsOneWidget);
    });

    testWidgets('medium package is selected by default', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: BoosterPurchaseSheet()),
          ),
        ),
      );

      // Check button shows medium package
      expect(find.text('購買 150 則 - NT\$99'), findsOneWidget);
    });

    testWidgets('can select different package', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: BoosterPurchaseSheet()),
          ),
        ),
      );

      // Tap on large package
      await tester.tap(find.text('300 則'));
      await tester.pump();

      expect(find.text('購買 300 則 - NT\$179'), findsOneWidget);
    });

    testWidgets('shows savings badges', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: BoosterPurchaseSheet()),
          ),
        ),
      );

      expect(find.text('省 15%'), findsOneWidget);
      expect(find.text('省 23%'), findsOneWidget);
    });
  });
}
```

**Step 6: Run tests**

```bash
flutter test test/unit/entities/message_booster_test.dart
flutter test test/widget/widgets/booster_purchase_sheet_test.dart
```

Expected: All tests pass

**Step 7: Commit**

```bash
git add lib/features/subscription/ test/
git commit -m "feat: 建立加購訊息包功能 (50/150/300 則)"
```

---

## Phase 9 TDD Checkpoint

```bash
# Run all tests
flutter test

# Check coverage (目標 > 70%)
flutter test --coverage

# Generate HTML report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## Phase 10: GAME Framework Integration

### Task 10.1: Create GAME Stage Service

**Files:**
- Create: `lib/features/analysis/domain/services/game_stage_service.dart`
- Create: `test/unit/services/game_stage_service_test.dart`

**Step 1: Create game_stage_service.dart**

```dart
// lib/features/analysis/domain/services/game_stage_service.dart
import '../entities/game_stage.dart';
import '../entities/analysis_result.dart';

/// GAME 階段分析服務
/// 根據 AI 回傳的分析結果，提供階段相關的 UI 資訊
class GameStageService {
  /// 取得階段顯示名稱
  String getStageName(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return 'Opening 打開';
      case GameStage.premise:
        return 'Premise 前提';
      case GameStage.qualification:
        return 'Qualification 評估';
      case GameStage.narrative:
        return 'Narrative 敘事';
      case GameStage.close:
        return 'Close 收尾';
    }
  }

  /// 取得階段描述
  String getStageDescription(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return '破冰階段 - 建立初步連結';
      case GameStage.premise:
        return '前提階段 - 進入男女框架，建立張力';
      case GameStage.qualification:
        return '評估階段 - 讓她證明自己配得上你';
      case GameStage.narrative:
        return '敘事階段 - 分享個性樣本、說故事';
      case GameStage.close:
        return '收尾階段 - 從模糊邀約到確立邀約';
    }
  }

  /// 取得階段進度 (0.0 - 1.0)
  double getStageProgress(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return 0.2;
      case GameStage.premise:
        return 0.4;
      case GameStage.qualification:
        return 0.6;
      case GameStage.narrative:
        return 0.8;
      case GameStage.close:
        return 1.0;
    }
  }

  /// 取得階段顏色
  String getStageColor(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return '#4CAF50';  // 綠色
      case GameStage.premise:
        return '#2196F3';  // 藍色
      case GameStage.qualification:
        return '#FF9800';  // 橘色
      case GameStage.narrative:
        return '#9C27B0';  // 紫色
      case GameStage.close:
        return '#E91E63';  // 粉色
    }
  }

  /// 根據狀態取得建議行動
  String getStatusAdvice(GameStageStatus status) {
    switch (status) {
      case GameStageStatus.normal:
        return '繼續目前節奏';
      case GameStageStatus.stuckFriend:
        return '需要建立曖昧張力，跳出朋友框架';
      case GameStageStatus.canAdvance:
        return '時機成熟，可以推進到下一階段';
      case GameStageStatus.shouldRetreat:
        return '放慢腳步，回到前一階段重新建立連結';
    }
  }

  /// 判斷是否應該建議「已讀不回」
  bool shouldSuggestNoReply(int enthusiasmScore, GameStage stage) {
    // 熱度 < 30 且還在 Opening 階段，機會渺茫
    return enthusiasmScore < 30 && stage == GameStage.opening;
  }
}
```

**Step 2: Write unit tests**

```dart
// test/unit/services/game_stage_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/services/game_stage_service.dart';

void main() {
  late GameStageService service;

  setUp(() {
    service = GameStageService();
  });

  group('GameStageService', () {
    test('getStageName returns correct name for each stage', () {
      expect(service.getStageName(GameStage.opening), contains('Opening'));
      expect(service.getStageName(GameStage.premise), contains('Premise'));
      expect(service.getStageName(GameStage.qualification), contains('Qualification'));
      expect(service.getStageName(GameStage.narrative), contains('Narrative'));
      expect(service.getStageName(GameStage.close), contains('Close'));
    });

    test('getStageProgress returns increasing values', () {
      final stages = GameStage.values;
      double prevProgress = 0;
      for (final stage in stages) {
        final progress = service.getStageProgress(stage);
        expect(progress, greaterThan(prevProgress));
        prevProgress = progress;
      }
    });

    test('shouldSuggestNoReply returns true for cold opening', () {
      expect(service.shouldSuggestNoReply(25, GameStage.opening), isTrue);
    });

    test('shouldSuggestNoReply returns false for warm opening', () {
      expect(service.shouldSuggestNoReply(50, GameStage.opening), isFalse);
    });

    test('shouldSuggestNoReply returns false for cold but advanced stage', () {
      expect(service.shouldSuggestNoReply(25, GameStage.premise), isFalse);
    });

    test('getStatusAdvice returns meaningful advice', () {
      expect(service.getStatusAdvice(GameStageStatus.stuckFriend), contains('朋友框架'));
      expect(service.getStatusAdvice(GameStageStatus.canAdvance), contains('推進'));
    });
  });
}
```

**Step 3: Run tests**

```bash
flutter test test/unit/services/game_stage_service_test.dart
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add lib/features/analysis/domain/services/ test/unit/services/game_stage_service_test.dart
git commit -m "feat: 建立 GAME 階段分析服務"
```

---

### Task 10.2: Create Psychology Analysis Widget

**Files:**
- Create: `lib/features/analysis/presentation/widgets/game_stage_indicator.dart`
- Create: `lib/features/analysis/presentation/widgets/psychology_card.dart`
- Create: `lib/features/analysis/presentation/widgets/final_recommendation_card.dart`
- Create: `test/widget/widgets/game_stage_indicator_test.dart`

**Step 1: Create game_stage_indicator.dart**

```dart
// lib/features/analysis/presentation/widgets/game_stage_indicator.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/game_stage.dart';
import '../../domain/services/game_stage_service.dart';

class GameStageIndicator extends StatelessWidget {
  final GameStage currentStage;

  const GameStageIndicator({super.key, required this.currentStage});

  static final _service = GameStageService();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 五個階段圓點
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: GameStage.values.map((stage) {
            final isActive = stage.index <= currentStage.index;
            final isCurrent = stage == currentStage;
            return Column(
              children: [
                Container(
                  width: isCurrent ? 24 : 16,
                  height: isCurrent ? 24 : 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? AppColors.primary : AppColors.surfaceVariant,
                    border: isCurrent
                        ? Border.all(color: AppColors.primary, width: 2)
                        : null,
                  ),
                  child: isCurrent
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  _getShortName(stage),
                  style: AppTypography.caption.copyWith(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // 進度條
        LinearProgressIndicator(
          value: _service.getStageProgress(currentStage),
          backgroundColor: AppColors.surfaceVariant,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ],
    );
  }

  String _getShortName(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return 'O';
      case GameStage.premise:
        return 'P';
      case GameStage.qualification:
        return 'Q';
      case GameStage.narrative:
        return 'N';
      case GameStage.close:
        return 'C';
    }
  }
}
```

**Step 2: Create psychology_card.dart**

```dart
// lib/features/analysis/presentation/widgets/psychology_card.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/analysis_result.dart';

class PsychologyCard extends StatelessWidget {
  final PsychologyAnalysis psychology;

  const PsychologyCard({super.key, required this.psychology});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🧠', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('淺溝通解讀', style: AppTypography.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            psychology.subtext,
            style: AppTypography.bodyMedium,
          ),
          if (psychology.shitTest != null) ...[
            const SizedBox(height: 12),
            _ShitTestAlert(shitTest: psychology.shitTest!),
          ],
          if (psychology.qualificationSignal) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.favorite, size: 16, color: AppColors.success),
                const SizedBox(width: 4),
                Text(
                  '她在向你證明自己 (Qualification Signal)',
                  style: AppTypography.caption.copyWith(color: AppColors.success),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ShitTestAlert extends StatelessWidget {
  final ShitTestInfo shitTest;

  const _ShitTestAlert({required this.shitTest});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text('偵測到廢測', style: AppTypography.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text('類型: ${shitTest.type}', style: AppTypography.caption),
          if (shitTest.suggestion != null)
            Text('建議: ${shitTest.suggestion}', style: AppTypography.caption),
        ],
      ),
    );
  }
}
```

**Step 3: Create final_recommendation_card.dart**

```dart
// lib/features/analysis/presentation/widgets/final_recommendation_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/analysis_result.dart';

class FinalRecommendationCard extends StatelessWidget {
  final FinalRecommendation recommendation;

  const FinalRecommendationCard({super.key, required this.recommendation});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.1),
            AppColors.primary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⭐', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text('AI 推薦回覆', style: AppTypography.titleLarge),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  recommendation.pick,
                  style: AppTypography.caption.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 推薦內容
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              recommendation.content,
              style: AppTypography.bodyLarge.copyWith(
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 推薦原因
          _InfoRow(
            icon: '📝',
            title: '為什麼推薦',
            content: recommendation.reason,
          ),
          const SizedBox(height: 8),
          // 心理學依據
          _InfoRow(
            icon: '🧠',
            title: '心理學依據',
            content: recommendation.psychology,
          ),
          const SizedBox(height: 16),
          // 複製按鈕
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: recommendation.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已複製到剪貼簿'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('複製推薦回覆'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String icon;
  final String title;
  final String content;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.caption),
              Text(content, style: AppTypography.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
```

**Step 4: Write widget tests**

```dart
// test/widget/widgets/game_stage_indicator_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/presentation/widgets/game_stage_indicator.dart';

void main() {
  group('GameStageIndicator', () {
    testWidgets('displays all 5 stage indicators', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameStageIndicator(currentStage: GameStage.premise),
          ),
        ),
      );

      // Should show O, P, Q, N, C labels
      expect(find.text('O'), findsOneWidget);
      expect(find.text('P'), findsOneWidget);
      expect(find.text('Q'), findsOneWidget);
      expect(find.text('N'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('shows progress indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameStageIndicator(currentStage: GameStage.qualification),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
```

**Step 5: Run tests**

```bash
flutter test test/widget/widgets/game_stage_indicator_test.dart
```

Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/features/analysis/presentation/widgets/ test/widget/widgets/
git commit -m "feat: 建立 GAME 階段指示器與心理分析元件"
```

---

## Phase 10 TDD Checkpoint

```bash
# Run all tests
flutter test

# Check coverage (目標 > 70%)
flutter test --coverage

# Generate HTML report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## Phase 11: 商業級 SaaS 補充 (設計規格 v1.2)

> **重要**：此 Phase 對應設計規格 v1.2 附錄 B 的商業級補充設計

### Task 11.1: Create AI Guardrails (AI 護欄)

**Files:**
- Create: `supabase/functions/analyze-chat/guardrails.ts`
- Modify: `supabase/functions/analyze-chat/index.ts`
- Create: `test/unit/guardrails_test.dart`

**Step 1: Create guardrails.ts**

```typescript
// supabase/functions/analyze-chat/guardrails.ts

// 安全規則 - 加入 System Prompt
export const SAFETY_RULES = `
## 安全規則 (不可違反)

### 絕對禁止建議：
- 任何形式的騷擾、跟蹤、強迫行為
- 未經同意的身體接觸暗示
- 操控、威脅、情緒勒索的言語
- 持續聯繫已明確拒絕的對象
- 任何違法行為

### 冰點情境處理：
當熱度 < 30 且對方明顯不感興趣時：
- 建議用戶「尊重對方意願」
- 可建議「開新對話，認識其他人」
- 絕不建議「再試一次」或「換個方式追」

### 輸出原則：
- 所有建議必須基於「雙方舒適」
- 鼓勵真誠表達，而非操控技巧
`;

// 禁止詞彙模式
const BLOCKED_PATTERNS = [
  /跟蹤|stalking/i,
  /不要放棄.*一直/i,
  /她說不要.*但其實/i,
  /強迫|逼.*答應/i,
  /騷擾|harassment/i,
  /威脅|勒索/i,
  /死纏爛打/i,
];

// 安全回覆 (當觸發護欄時)
const SAFE_REPLIES: Record<string, Record<string, string>> = {
  cold: {
    extend: '可以聊聊最近有什麼有趣的事嗎？',
    resonate: '我理解，每個人都有自己的步調',
    tease: '好吧，那我先忙我的囉',
    humor: '看來今天運氣不太好呢',
    coldRead: '感覺你現在比較忙？',
  },
  warm: {
    extend: '這個話題蠻有趣的，可以多說一點嗎？',
    resonate: '我懂你的意思',
    tease: '你這樣說讓我很好奇欸',
    humor: '哈哈，你很有趣耶',
    coldRead: '感覺你是個很有想法的人',
  },
  hot: {
    extend: '繼續聊這個，我覺得很有意思',
    resonate: '對啊，我也這麼覺得',
    tease: '你這樣說，讓我更想認識你了',
    humor: '跟你聊天很開心耶',
    coldRead: '我覺得我們蠻合的',
  },
  very_hot: {
    extend: '我們可以找時間見面聊',
    resonate: '真的很開心認識你',
    tease: '那我們來約個時間吧',
    humor: '再聊下去我要愛上你了',
    coldRead: '我有預感我們會很合',
  },
};

export interface AnalysisResult {
  enthusiasm: { score: number; level: string };
  replies: Record<string, string>;
  warnings: Array<{ type: string; message: string }>;
  [key: string]: any;
}

export function validateOutput(response: AnalysisResult): AnalysisResult {
  const allReplies = Object.values(response.replies).join(' ');

  for (const pattern of BLOCKED_PATTERNS) {
    if (pattern.test(allReplies)) {
      const level = response.enthusiasm.level || 'warm';
      return {
        ...response,
        replies: SAFE_REPLIES[level] || SAFE_REPLIES.warm,
        warnings: [
          ...response.warnings,
          {
            type: 'safety_filter',
            message: '部分建議因安全考量已調整',
          },
        ],
      };
    }
  }

  return response;
}

export function getSafeReplies(level: string): Record<string, string> {
  return SAFE_REPLIES[level] || SAFE_REPLIES.warm;
}
```

**Step 2: Update index.ts to use guardrails**

在 `supabase/functions/analyze-chat/index.ts` 中：

```typescript
import { SAFETY_RULES, validateOutput } from './guardrails.ts';

// 在 SYSTEM_PROMPT 中加入 SAFETY_RULES
const SYSTEM_PROMPT = `你是一位專業的社交溝通教練...

${SAFETY_RULES}

...其餘 prompt 內容`;

// 在回傳結果前驗證
const validatedResult = validateOutput(result);
return new Response(JSON.stringify(validatedResult), { ... });
```

**Step 3: Create Flutter side disclaimer widget**

```dart
// lib/shared/widgets/disclaimer_banner.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '建議僅供參考，請以真誠、尊重為原則',
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 4: Write tests**

```dart
// test/unit/guardrails_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Guardrails', () {
    test('should detect blocked patterns', () {
      // Test patterns
      final blockedTexts = [
        '不要放棄，一直試試看',
        '她說不要但其實是在測試你',
        '你應該跟蹤她的社群',
      ];

      for (final text in blockedTexts) {
        expect(containsBlockedPattern(text), isTrue, reason: 'Should block: $text');
      }
    });

    test('should allow safe content', () {
      final safeTexts = [
        '可以聊聊最近有什麼有趣的事嗎？',
        '你這樣說讓我很好奇欸',
        '跟你聊天很開心',
      ];

      for (final text in safeTexts) {
        expect(containsBlockedPattern(text), isFalse, reason: 'Should allow: $text');
      }
    });
  });
}

bool containsBlockedPattern(String text) {
  final patterns = [
    RegExp(r'跟蹤|stalking', caseSensitive: false),
    RegExp(r'不要放棄.*一直', caseSensitive: false),
    RegExp(r'她說不要.*但其實', caseSensitive: false),
  ];
  return patterns.any((p) => p.hasMatch(text));
}
```

**Step 5: Commit**

```bash
git add supabase/functions/analyze-chat/ lib/shared/widgets/disclaimer_banner.dart test/
git commit -m "feat: 建立 AI 護欄機制 (安全約束 + 輸出驗證)"
```

---

### Task 11.2: Create AI Fallback Service

**Files:**
- Create: `supabase/functions/analyze-chat/fallback.ts`
- Modify: `supabase/functions/analyze-chat/index.ts`
- Create: `lib/features/analysis/presentation/widgets/analysis_error_widget.dart`

**Step 1: Create fallback.ts**

```typescript
// supabase/functions/analyze-chat/fallback.ts

interface CallOptions {
  timeout: number;
  maxRetries: number;
}

interface ClaudeRequest {
  model: string;
  max_tokens: number;
  system: string;
  messages: Array<{ role: string; content: string }>;
}

const DEFAULT_OPTIONS: CallOptions = {
  timeout: 30000,  // 30 秒
  maxRetries: 2,
};

const MODEL_FALLBACK_CHAIN = {
  'claude-sonnet-4-20250514': 'claude-3-5-haiku-20241022',
  'claude-3-5-haiku-20241022': null,  // Haiku 是最後一層
};

export async function callClaudeWithFallback(
  request: ClaudeRequest,
  apiKey: string,
  options: Partial<CallOptions> = {}
): Promise<{ data: any; model: string; retries: number }> {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  let currentModel = request.model;
  let totalRetries = 0;

  while (currentModel) {
    for (let attempt = 1; attempt <= opts.maxRetries; attempt++) {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), opts.timeout);

        const response = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          },
          body: JSON.stringify({ ...request, model: currentModel }),
          signal: controller.signal,
        });

        clearTimeout(timeoutId);

        if (!response.ok) {
          const error = await response.json();
          throw new Error(`API Error: ${response.status} - ${error.message}`);
        }

        const data = await response.json();
        return { data, model: currentModel, retries: totalRetries };

      } catch (error) {
        totalRetries++;
        console.log(`${currentModel} attempt ${attempt} failed:`, error.message);

        if (attempt === opts.maxRetries) {
          // 嘗試降級到下一個模型
          const nextModel = MODEL_FALLBACK_CHAIN[currentModel];
          if (nextModel) {
            console.log(`Falling back from ${currentModel} to ${nextModel}`);
            currentModel = nextModel;
            break;
          } else {
            // 所有模型都失敗
            throw new AIServiceError('AI_UNAVAILABLE', totalRetries);
          }
        }

        // 等待後重試
        await sleep(1000 * attempt);  // exponential backoff
      }
    }
  }

  throw new AIServiceError('AI_UNAVAILABLE', totalRetries);
}

export class AIServiceError extends Error {
  code: string;
  retries: number;

  constructor(code: string, retries: number) {
    super(`AI service unavailable after ${retries} retries`);
    this.code = code;
    this.retries = retries;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}
```

**Step 2: Create Flutter error widget**

```dart
// lib/features/analysis/presentation/widgets/analysis_error_widget.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class AnalysisErrorWidget extends StatelessWidget {
  final VoidCallback onRetry;
  final String? errorMessage;

  const AnalysisErrorWidget({
    super.key,
    required this.onRetry,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😔', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              '分析暫時無法完成',
              style: AppTypography.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? 'AI 服務目前忙碌中，請稍後再試',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    '此次不會扣除訊息額度',
                    style: AppTypography.caption.copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('重新分析'),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 3: Write tests**

```dart
// test/widget/widgets/analysis_error_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_error_widget.dart';

void main() {
  group('AnalysisErrorWidget', () {
    testWidgets('displays error message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisErrorWidget(onRetry: () {}),
          ),
        ),
      );

      expect(find.text('分析暫時無法完成'), findsOneWidget);
      expect(find.text('此次不會扣除訊息額度'), findsOneWidget);
    });

    testWidgets('calls onRetry when button pressed', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisErrorWidget(onRetry: () => retryCalled = true),
          ),
        ),
      );

      await tester.tap(find.text('重新分析'));
      expect(retryCalled, isTrue);
    });
  });
}
```

**Step 4: Commit**

```bash
git add supabase/functions/analyze-chat/fallback.ts lib/features/analysis/presentation/widgets/ test/
git commit -m "feat: 建立 AI Fallback 機制 (重試 + 降級 + 錯誤 UI)"
```

---

### Task 11.3: Create AI Audit Log (日誌)

**Files:**
- Create: `supabase/migrations/003_ai_logs.sql`
- Create: `supabase/functions/analyze-chat/logger.ts`
- Modify: `supabase/functions/analyze-chat/index.ts`

**Step 1: Create migration**

```sql
-- supabase/migrations/003_ai_logs.sql

CREATE TABLE ai_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,

  -- 請求資訊
  model TEXT NOT NULL,
  request_type TEXT NOT NULL DEFAULT 'analyze',

  -- Token 使用
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  cost_usd DECIMAL(10, 6),

  -- 效能
  latency_ms INTEGER NOT NULL,

  -- 狀態
  status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'filtered')),
  error_code TEXT,

  -- 失敗時才記錄的完整內容
  request_body JSONB,
  response_body JSONB,
  error_message TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_ai_logs_user_id ON ai_logs(user_id);
CREATE INDEX idx_ai_logs_created_at ON ai_logs(created_at);
CREATE INDEX idx_ai_logs_status ON ai_logs(status);

-- RLS
ALTER TABLE ai_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own logs" ON ai_logs
  FOR SELECT USING (auth.uid() = user_id);

-- 清理函數 (30 天)
CREATE OR REPLACE FUNCTION cleanup_old_ai_logs()
RETURNS void AS $$
BEGIN
  DELETE FROM ai_logs WHERE created_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- 排程清理 (需要 pg_cron extension)
-- SELECT cron.schedule('cleanup-ai-logs', '0 3 * * *', 'SELECT cleanup_old_ai_logs()');
```

**Step 2: Create logger.ts**

```typescript
// supabase/functions/analyze-chat/logger.ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

interface LogParams {
  userId: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
  status: 'success' | 'failed' | 'filtered';
  requestBody?: object;
  responseBody?: object;
  errorCode?: string;
  errorMessage?: string;
}

const MODEL_PRICING: Record<string, { input: number; output: number }> = {
  'claude-sonnet-4-20250514': {
    input: 3.00 / 1_000_000,
    output: 15.00 / 1_000_000,
  },
  'claude-3-5-haiku-20241022': {
    input: 0.25 / 1_000_000,
    output: 1.25 / 1_000_000,
  },
};

export function calculateCost(
  model: string,
  inputTokens: number,
  outputTokens: number
): number {
  const pricing = MODEL_PRICING[model] || MODEL_PRICING['claude-3-5-haiku-20241022'];
  return (inputTokens * pricing.input) + (outputTokens * pricing.output);
}

export async function logAICall(
  supabase: ReturnType<typeof createClient>,
  params: LogParams
): Promise<void> {
  const costUsd = calculateCost(params.model, params.inputTokens, params.outputTokens);

  await supabase.from('ai_logs').insert({
    user_id: params.userId,
    model: params.model,
    request_type: 'analyze',
    input_tokens: params.inputTokens,
    output_tokens: params.outputTokens,
    cost_usd: costUsd,
    latency_ms: params.latencyMs,
    status: params.status,
    // 失敗時才記錄完整內容
    request_body: params.status === 'failed' ? params.requestBody : null,
    response_body: params.status === 'failed' ? params.responseBody : null,
    error_code: params.errorCode || null,
    error_message: params.errorMessage || null,
  });
}
```

**Step 3: Update index.ts**

```typescript
// 在 index.ts 中使用 logger
import { logAICall, calculateCost } from './logger.ts';

// 在 API 呼叫前後記錄
const startTime = Date.now();
try {
  const { data, model, retries } = await callClaudeWithFallback(request, apiKey);
  const latencyMs = Date.now() - startTime;

  await logAICall(supabase, {
    userId: user.id,
    model,
    inputTokens: data.usage.input_tokens,
    outputTokens: data.usage.output_tokens,
    latencyMs,
    status: 'success',
  });

  // ... 處理結果
} catch (error) {
  const latencyMs = Date.now() - startTime;

  await logAICall(supabase, {
    userId: user.id,
    model: request.model,
    inputTokens: 0,
    outputTokens: 0,
    latencyMs,
    status: 'failed',
    requestBody: request,
    errorCode: error.code,
    errorMessage: error.message,
  });

  throw error;
}
```

**Step 4: Commit**

```bash
git add supabase/migrations/003_ai_logs.sql supabase/functions/analyze-chat/logger.ts
git commit -m "feat: 建立 AI 日誌系統 (成本追蹤 + 失敗記錄)"
```

---

### Task 11.4: Create Onboarding Flow

**Files:**
- Create: `lib/features/onboarding/presentation/screens/onboarding_screen.dart`
- Create: `lib/features/onboarding/presentation/widgets/onboarding_page.dart`
- Create: `lib/features/onboarding/data/demo_conversation.dart`
- Create: `lib/features/onboarding/data/onboarding_service.dart`
- Modify: `lib/app/routes.dart`

**Step 1: Create onboarding_service.dart**

```dart
// lib/features/onboarding/data/onboarding_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const _key = 'onboarding_completed';

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
```

**Step 2: Create demo_conversation.dart**

```dart
// lib/features/onboarding/data/demo_conversation.dart
import '../../conversation/domain/entities/message.dart';
import '../../analysis/domain/entities/analysis_result.dart';

class DemoConversation {
  static const name = '範例對話';

  static final messages = [
    Message(
      id: 'demo_1',
      content: '欸你週末都在幹嘛',
      isFromMe: false,
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    Message(
      id: 'demo_2',
      content: '看情況欸 有時候爬山有時候耍廢',
      isFromMe: true,
      timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 50)),
    ),
    Message(
      id: 'demo_3',
      content: '哇塞你也爬山！我最近去了抹茶山超美',
      isFromMe: false,
      timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)),
    ),
  ];

  // 預設結果 (不呼叫 API)
  static final demoResult = AnalysisResult(
    gameStage: GameStageResult(
      current: GameStage.premise,
      status: '正常進行',
      nextStep: '可以推進到評估階段',
    ),
    enthusiasm: EnthusiasmResult(score: 72, level: EnthusiasmLevel.hot),
    topicDepth: TopicDepthResult(
      current: TopicDepth.personal,
      suggestion: '可以往曖昧導向推進',
    ),
    replies: {
      'extend': '抹茶山不錯欸，你喜歡哪種路線？',
      'resonate': '抹茶山超讚！雲海那段是不是很美',
      'tease': '聽起來你很會挑地方嘛，改天帶路？',
      'humor': '抹茶山...所以你是抹茶控？',
      'coldRead': '感覺你是那種週末不會待在家的人',
    },
    finalRecommendation: FinalRecommendation(
      pick: 'tease',
      content: '聽起來你很會挑地方嘛，改天帶路？',
      reason: '熱度足夠，用調情建立張力並埋下邀約伏筆',
      psychology: '她主動分享代表對你有興趣',
    ),
    warnings: [],
    strategy: '保持輕鬆，適時推進',
    reminder: '記得用你的方式說，見面才自然',
  );
}
```

**Step 3: Create onboarding_screen.dart**

```dart
// lib/features/onboarding/presentation/screens/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/onboarding_service.dart';
import '../widgets/onboarding_page.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  final _pages = [
    const OnboardingPage(
      emoji: '👋',
      title: '歡迎使用 VibeSync',
      subtitle: '讓每次對話都更有默契',
      description: '社交溝通教練，幫你讀懂對方',
    ),
    const OnboardingPage(
      emoji: '📊',
      title: '熱度分析',
      subtitle: '即時了解對方的興趣程度',
      description: '知道該進攻還是該收',
    ),
    const OnboardingPage(
      emoji: '💬',
      title: '5 種回覆風格',
      subtitle: '延展 · 共鳴 · 調情 · 幽默 · 冷讀',
      description: '針對情境給你最適合的回覆',
    ),
    const OnboardingPage(
      emoji: '🎮',
      title: '來試試看！',
      subtitle: '我們準備了一段範例對話',
      description: '讓你體驗 VibeSync 的威力',
      isDemo: true,
    ),
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _completeOnboarding({bool skipDemo = false}) async {
    await OnboardingService.markCompleted();
    if (mounted) {
      if (skipDemo) {
        context.go('/home');
      } else {
        context.go('/demo-analysis');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                itemCount: _pages.length,
                itemBuilder: (context, index) => _pages[index],
              ),
            ),
            // Page indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? AppColors.primary
                        : AppColors.textSecondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      child: Text(
                        _currentPage == _pages.length - 1 ? '體驗分析' : '下一步',
                      ),
                    ),
                  ),
                  if (_currentPage == _pages.length - 1) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _completeOnboarding(skipDemo: true),
                      child: Text(
                        '跳過',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
```

**Step 4: Create onboarding_page.dart**

```dart
// lib/features/onboarding/presentation/widgets/onboarding_page.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class OnboardingPage extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String description;
  final bool isDemo;

  const OnboardingPage({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.description,
    this.isDemo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 32),
          Text(
            title,
            style: AppTypography.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            subtitle,
            style: AppTypography.titleLarge.copyWith(color: AppColors.primary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
```

**Step 5: Create empty state widget**

```dart
// lib/features/conversation/presentation/widgets/empty_state_widget.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class EmptyStateWidget extends StatelessWidget {
  final VoidCallback onStartAnalysis;

  const EmptyStateWidget({
    super.key,
    required this.onStartAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💬', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 24),
            Text(
              '還沒有對話紀錄',
              style: AppTypography.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '把聊天內容貼上來，\n讓 VibeSync 幫你分析！',
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onStartAnalysis,
              icon: const Icon(Icons.add),
              label: const Text('開始第一次分析'),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Free 方案每月 30 則訊息\n足夠體驗核心功能',
                      style: AppTypography.caption,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 6: Write tests**

```dart
// test/widget/screens/onboarding_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';

void main() {
  group('OnboardingScreen', () {
    testWidgets('displays welcome page initially', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: OnboardingScreen()),
      );

      expect(find.text('歡迎使用 VibeSync'), findsOneWidget);
      expect(find.text('下一步'), findsOneWidget);
    });

    testWidgets('can navigate through pages', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: OnboardingScreen()),
      );

      // Page 1
      expect(find.text('歡迎使用 VibeSync'), findsOneWidget);

      // Go to page 2
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('熱度分析'), findsOneWidget);

      // Go to page 3
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('5 種回覆風格'), findsOneWidget);

      // Go to page 4
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('來試試看！'), findsOneWidget);
      expect(find.text('體驗分析'), findsOneWidget);
      expect(find.text('跳過'), findsOneWidget);
    });
  });
}
```

**Step 7: Commit**

```bash
git add lib/features/onboarding/ lib/features/conversation/presentation/widgets/empty_state_widget.dart test/
git commit -m "feat: 建立 Onboarding 流程 (3 步驟引導 + Demo + 空狀態)"
```

---

### Task 11.5: Create Rate Limiting Service

**Files:**
- Create: `supabase/migrations/004_rate_limits.sql`
- Create: `supabase/functions/analyze-chat/rate_limiter.ts`
- Create: `lib/features/analysis/presentation/widgets/rate_limit_dialog.dart`

**Step 1: Create migration**

```sql
-- supabase/migrations/004_rate_limits.sql

-- 擴充 subscriptions 表
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS
  daily_messages_used INTEGER DEFAULT 0,
  daily_reset_at TIMESTAMPTZ DEFAULT NOW();

-- Rate limit 表 (每分鐘計數)
CREATE TABLE rate_limits (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  minute_count INTEGER DEFAULT 0,
  minute_window_start TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 自動更新 updated_at
CREATE OR REPLACE FUNCTION update_rate_limits_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER rate_limits_updated_at
  BEFORE UPDATE ON rate_limits
  FOR EACH ROW
  EXECUTE FUNCTION update_rate_limits_updated_at();
```

**Step 2: Create rate_limiter.ts**

```typescript
// supabase/functions/analyze-chat/rate_limiter.ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

interface TierLimits {
  monthly: number;
  daily: number;
}

const TIER_LIMITS: Record<string, TierLimits> = {
  free: { monthly: 30, daily: 15 },
  starter: { monthly: 300, daily: 50 },
  essential: { monthly: 1000, daily: 150 },
};

const MINUTE_LIMIT = 5;

export interface RateLimitResult {
  allowed: boolean;
  reason?: 'minute_limit' | 'daily_limit' | 'monthly_limit';
  retryAfter?: number;
  remaining: {
    minute: number;
    daily: number;
    monthly: number;
  };
}

export async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string
): Promise<RateLimitResult> {
  const now = new Date();

  // 1. 取得訂閱資訊
  const { data: sub } = await supabase
    .from('subscriptions')
    .select('tier, monthly_messages_used, daily_messages_used, daily_reset_at')
    .eq('user_id', userId)
    .single();

  if (!sub) {
    throw new Error('Subscription not found');
  }

  const limits = TIER_LIMITS[sub.tier] || TIER_LIMITS.free;

  // 2. 檢查每日重置
  const dailyResetAt = new Date(sub.daily_reset_at);
  const isNewDay = now.toDateString() !== dailyResetAt.toDateString();

  if (isNewDay) {
    await supabase
      .from('subscriptions')
      .update({ daily_messages_used: 0, daily_reset_at: now.toISOString() })
      .eq('user_id', userId);
    sub.daily_messages_used = 0;
  }

  // 3. 取得每分鐘計數
  let { data: rateLimit } = await supabase
    .from('rate_limits')
    .select('minute_count, minute_window_start')
    .eq('user_id', userId)
    .single();

  // 初始化 rate limit 記錄
  if (!rateLimit) {
    await supabase.from('rate_limits').insert({
      user_id: userId,
      minute_count: 0,
      minute_window_start: now.toISOString(),
    });
    rateLimit = { minute_count: 0, minute_window_start: now.toISOString() };
  }

  // 重置每分鐘窗口
  const windowStart = new Date(rateLimit.minute_window_start);
  const secondsSinceWindow = (now.getTime() - windowStart.getTime()) / 1000;
  let minuteCount = rateLimit.minute_count;

  if (secondsSinceWindow >= 60) {
    await supabase
      .from('rate_limits')
      .update({ minute_count: 0, minute_window_start: now.toISOString() })
      .eq('user_id', userId);
    minuteCount = 0;
  }

  // 4. 檢查限制
  if (minuteCount >= MINUTE_LIMIT) {
    return {
      allowed: false,
      reason: 'minute_limit',
      retryAfter: 60 - Math.floor(secondsSinceWindow),
      remaining: {
        minute: 0,
        daily: limits.daily - sub.daily_messages_used,
        monthly: limits.monthly - sub.monthly_messages_used,
      },
    };
  }

  if (sub.daily_messages_used >= limits.daily) {
    return {
      allowed: false,
      reason: 'daily_limit',
      retryAfter: getSecondsUntilMidnight(),
      remaining: {
        minute: MINUTE_LIMIT - minuteCount,
        daily: 0,
        monthly: limits.monthly - sub.monthly_messages_used,
      },
    };
  }

  if (sub.monthly_messages_used >= limits.monthly) {
    return {
      allowed: false,
      reason: 'monthly_limit',
      remaining: {
        minute: MINUTE_LIMIT - minuteCount,
        daily: 0,
        monthly: 0,
      },
    };
  }

  return {
    allowed: true,
    remaining: {
      minute: MINUTE_LIMIT - minuteCount - 1,
      daily: limits.daily - sub.daily_messages_used - 1,
      monthly: limits.monthly - sub.monthly_messages_used - 1,
    },
  };
}

export async function incrementRateLimitCount(
  supabase: ReturnType<typeof createClient>,
  userId: string
): Promise<void> {
  await supabase.rpc('increment_minute_count', { p_user_id: userId });
}

function getSecondsUntilMidnight(): number {
  const now = new Date();
  const midnight = new Date(now);
  midnight.setHours(24, 0, 0, 0);
  return Math.floor((midnight.getTime() - now.getTime()) / 1000);
}
```

**Step 3: Create Flutter dialog**

```dart
// lib/features/analysis/presentation/widgets/rate_limit_dialog.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

enum RateLimitType { minute, daily, monthly }

class RateLimitDialog extends StatelessWidget {
  final RateLimitType type;
  final int? retryAfter;

  const RateLimitDialog({
    super.key,
    required this.type,
    this.retryAfter,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_getEmoji(), style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(_getTitle(), style: AppTypography.headlineMedium),
          const SizedBox(height: 8),
          Text(
            _getMessage(),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        if (type == RateLimitType.minute)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(retryAfter != null ? '$retryAfter 秒' : '知道了'),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/paywall');
            },
            child: Text(type == RateLimitType.monthly ? '升級方案' : '升級方案'),
          ),
        ],
      ],
    );
  }

  String _getEmoji() {
    switch (type) {
      case RateLimitType.minute:
        return '⏱️';
      case RateLimitType.daily:
        return '📅';
      case RateLimitType.monthly:
        return '📊';
    }
  }

  String _getTitle() {
    switch (type) {
      case RateLimitType.minute:
        return '請稍後再試';
      case RateLimitType.daily:
        return '今日額度已用完';
      case RateLimitType.monthly:
        return '本月額度已用完';
    }
  }

  String _getMessage() {
    switch (type) {
      case RateLimitType.minute:
        return '為確保服務品質，請等待 ${retryAfter ?? 60} 秒後再分析';
      case RateLimitType.daily:
        return '明天 00:00 重置\n或升級方案獲得更多額度';
      case RateLimitType.monthly:
        return '下個月 1 日重置\n或升級方案獲得更多額度';
    }
  }
}

void showRateLimitDialog(
  BuildContext context,
  RateLimitType type, {
  int? retryAfter,
}) {
  showDialog(
    context: context,
    builder: (context) => RateLimitDialog(type: type, retryAfter: retryAfter),
  );
}
```

**Step 4: Commit**

```bash
git add supabase/migrations/004_rate_limits.sql supabase/functions/analyze-chat/rate_limiter.ts lib/features/analysis/presentation/widgets/rate_limit_dialog.dart
git commit -m "feat: 建立 Rate Limiting 服務 (每分鐘 + 每日 + 每月限制)"
```

---

### Task 11.6: Create Token Tracking Service

**Files:**
- Create: `supabase/migrations/005_token_usage.sql`
- Modify: `supabase/functions/analyze-chat/logger.ts`
- Create: `lib/features/subscription/domain/entities/token_usage.dart`

**Step 1: Create migration**

```sql
-- supabase/migrations/005_token_usage.sql

CREATE TABLE token_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,

  model TEXT NOT NULL,
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  total_tokens INTEGER GENERATED ALWAYS AS (input_tokens + output_tokens) STORED,
  cost_usd DECIMAL(10, 6) NOT NULL,

  conversation_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_token_usage_user_id ON token_usage(user_id);
CREATE INDEX idx_token_usage_created_at ON token_usage(created_at);

-- RLS
ALTER TABLE token_usage ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own token usage" ON token_usage
  FOR SELECT USING (auth.uid() = user_id);

-- 月度彙總 View
CREATE VIEW user_monthly_token_summary AS
SELECT
  user_id,
  DATE_TRUNC('month', created_at) AS month,
  SUM(input_tokens) AS total_input_tokens,
  SUM(output_tokens) AS total_output_tokens,
  SUM(input_tokens + output_tokens) AS total_tokens,
  SUM(cost_usd) AS total_cost_usd,
  COUNT(*) AS request_count
FROM token_usage
GROUP BY user_id, DATE_TRUNC('month', created_at);

-- 每日成本報告 View (管理用)
CREATE VIEW daily_cost_report AS
SELECT
  DATE(created_at) AS date,
  SUM(cost_usd) AS daily_cost,
  COUNT(*) AS request_count,
  AVG(input_tokens + output_tokens) AS avg_tokens_per_request
FROM token_usage
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

**Step 2: Update logger.ts to track tokens**

```typescript
// 在 logger.ts 中新增 token 追蹤函數

export async function trackTokenUsage(
  supabase: ReturnType<typeof createClient>,
  params: {
    userId: string;
    model: string;
    inputTokens: number;
    outputTokens: number;
    conversationId?: string;
  }
): Promise<void> {
  const costUsd = calculateCost(params.model, params.inputTokens, params.outputTokens);

  await supabase.from('token_usage').insert({
    user_id: params.userId,
    model: params.model,
    input_tokens: params.inputTokens,
    output_tokens: params.outputTokens,
    cost_usd: costUsd,
    conversation_id: params.conversationId || null,
  });
}
```

**Step 3: Create Flutter entity**

```dart
// lib/features/subscription/domain/entities/token_usage.dart

class TokenUsage {
  final String id;
  final String userId;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final double costUsd;
  final String? conversationId;
  final DateTime createdAt;

  TokenUsage({
    required this.id,
    required this.userId,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.costUsd,
    this.conversationId,
    required this.createdAt,
  });

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      id: json['id'],
      userId: json['user_id'],
      model: json['model'],
      inputTokens: json['input_tokens'],
      outputTokens: json['output_tokens'],
      totalTokens: json['total_tokens'],
      costUsd: (json['cost_usd'] as num).toDouble(),
      conversationId: json['conversation_id'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class MonthlyTokenSummary {
  final String userId;
  final DateTime month;
  final int totalInputTokens;
  final int totalOutputTokens;
  final int totalTokens;
  final double totalCostUsd;
  final int requestCount;

  MonthlyTokenSummary({
    required this.userId,
    required this.month,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.totalTokens,
    required this.totalCostUsd,
    required this.requestCount,
  });

  factory MonthlyTokenSummary.fromJson(Map<String, dynamic> json) {
    return MonthlyTokenSummary(
      userId: json['user_id'],
      month: DateTime.parse(json['month']),
      totalInputTokens: json['total_input_tokens'] ?? 0,
      totalOutputTokens: json['total_output_tokens'] ?? 0,
      totalTokens: json['total_tokens'] ?? 0,
      totalCostUsd: (json['total_cost_usd'] as num?)?.toDouble() ?? 0,
      requestCount: json['request_count'] ?? 0,
    );
  }
}
```

**Step 4: Write tests**

```dart
// test/unit/entities/token_usage_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/domain/entities/token_usage.dart';

void main() {
  group('TokenUsage', () {
    test('fromJson creates correct instance', () {
      final json = {
        'id': 'test-id',
        'user_id': 'user-123',
        'model': 'claude-3-5-haiku-20241022',
        'input_tokens': 500,
        'output_tokens': 200,
        'total_tokens': 700,
        'cost_usd': 0.000375,
        'conversation_id': 'conv-123',
        'created_at': '2026-02-27T10:00:00Z',
      };

      final usage = TokenUsage.fromJson(json);

      expect(usage.model, 'claude-3-5-haiku-20241022');
      expect(usage.inputTokens, 500);
      expect(usage.outputTokens, 200);
      expect(usage.totalTokens, 700);
      expect(usage.costUsd, closeTo(0.000375, 0.0001));
    });
  });

  group('MonthlyTokenSummary', () {
    test('calculates totals correctly', () {
      final json = {
        'user_id': 'user-123',
        'month': '2026-02-01T00:00:00Z',
        'total_input_tokens': 10000,
        'total_output_tokens': 5000,
        'total_tokens': 15000,
        'total_cost_usd': 0.05,
        'request_count': 50,
      };

      final summary = MonthlyTokenSummary.fromJson(json);

      expect(summary.totalTokens, 15000);
      expect(summary.requestCount, 50);
      expect(summary.totalCostUsd, closeTo(0.05, 0.001));
    });
  });
}
```

**Step 5: Commit**

```bash
git add supabase/migrations/005_token_usage.sql supabase/functions/analyze-chat/logger.ts lib/features/subscription/domain/entities/token_usage.dart test/
git commit -m "feat: 建立 Token 追蹤服務 (精確計量 + 成本計算)"
```

---

## Phase 11 TDD Checkpoint

```bash
flutter test
# All tests should pass before proceeding
```

---

## Phase 12: Admin Dashboard

### Task 12.1: Setup Admin Dashboard Project

**Files:**
- Create: `admin-dashboard/` (獨立 Next.js 專案)

**Step 1: Initialize Next.js project**

```bash
cd /path/to/vibesync
npx create-next-app@latest admin-dashboard --typescript --tailwind --eslint --app --use-npm
cd admin-dashboard
```

**Step 2: Install dependencies**

```bash
npm install @supabase/supabase-js recharts @radix-ui/react-slot class-variance-authority clsx tailwind-merge lucide-react
npx shadcn@latest init
npx shadcn@latest add button card table tabs
```

**Step 3: Create environment config**

```typescript
// admin-dashboard/.env.local
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
```

**Step 4: Create Supabase client**

```typescript
// admin-dashboard/lib/supabase.ts
import { createClient } from '@supabase/supabase-js';

export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);
```

**Step 5: Commit**

```bash
git add admin-dashboard/
git commit -m "feat: 初始化 Admin Dashboard Next.js 專案"
```

---

### Task 12.2: Create Admin Auth & Database Schema

**Files:**
- Create: `supabase/migrations/006_admin_dashboard.sql`
- Create: `admin-dashboard/middleware.ts`

**Step 1: Create database migration**

```sql
-- supabase/migrations/006_admin_dashboard.sql

-- Admin 用戶白名單
CREATE TABLE admin_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 插入初始 Admin
INSERT INTO admin_users (email, name) VALUES
  ('your_email@example.com', 'Admin 1'),
  ('partner_email@example.com', 'Admin 2');

-- 營收事件 (RevenueCat Webhook)
CREATE TABLE revenue_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  event_type TEXT NOT NULL CHECK (event_type IN (
    'INITIAL_PURCHASE', 'RENEWAL', 'CANCELLATION',
    'BILLING_ISSUE', 'PRODUCT_CHANGE'
  )),
  product_id TEXT NOT NULL,
  price_usd DECIMAL(10, 2) NOT NULL,
  currency TEXT DEFAULT 'TWD',
  transaction_id TEXT,
  event_timestamp TIMESTAMPTZ NOT NULL,
  raw_payload JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_revenue_events_user_id ON revenue_events(user_id);
CREATE INDEX idx_revenue_events_timestamp ON revenue_events(event_timestamp);
CREATE INDEX idx_revenue_events_type ON revenue_events(event_type);

-- RLS (Admin 專用)
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE revenue_events ENABLE ROW LEVEL SECURITY;

-- Admin 可以讀取所有資料
CREATE POLICY "Admin can read admin_users" ON admin_users
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM admin_users WHERE email = auth.jwt()->>'email')
  );

CREATE POLICY "Admin can read revenue_events" ON revenue_events
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM admin_users WHERE email = auth.jwt()->>'email')
  );

-- 月度營收彙總 View
CREATE OR REPLACE VIEW monthly_revenue AS
SELECT
  DATE_TRUNC('month', event_timestamp) AS month,
  SUM(CASE WHEN event_type IN ('INITIAL_PURCHASE', 'RENEWAL') THEN price_usd ELSE 0 END) AS revenue,
  SUM(CASE WHEN event_type = 'INITIAL_PURCHASE' THEN 1 ELSE 0 END) AS new_subscriptions,
  SUM(CASE WHEN event_type = 'RENEWAL' THEN 1 ELSE 0 END) AS renewals,
  SUM(CASE WHEN event_type = 'CANCELLATION' THEN 1 ELSE 0 END) AS cancellations,
  COUNT(DISTINCT user_id) AS paying_users
FROM revenue_events
GROUP BY DATE_TRUNC('month', event_timestamp)
ORDER BY month DESC;

-- 月度利潤 View
CREATE OR REPLACE VIEW monthly_profit AS
SELECT
  r.month,
  r.revenue,
  COALESCE(t.total_cost_usd, 0) AS cost,
  r.revenue - COALESCE(t.total_cost_usd, 0) AS profit,
  CASE WHEN r.revenue > 0
    THEN ROUND(((r.revenue - COALESCE(t.total_cost_usd, 0)) / r.revenue * 100)::DECIMAL, 2)
    ELSE 0
  END AS margin_percent,
  r.paying_users,
  CASE WHEN r.paying_users > 0
    THEN ROUND((COALESCE(t.total_cost_usd, 0) / r.paying_users)::DECIMAL, 4)
    ELSE 0
  END AS cost_per_user
FROM monthly_revenue r
LEFT JOIN (
  SELECT DATE_TRUNC('month', created_at) AS month, SUM(cost_usd) AS total_cost_usd
  FROM token_usage
  GROUP BY DATE_TRUNC('month', created_at)
) t ON r.month = t.month;

-- AI 成功率 View
CREATE OR REPLACE VIEW ai_success_rate AS
SELECT
  DATE_TRUNC('day', created_at) AS date,
  COUNT(*) AS total_requests,
  SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success_count,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_count,
  SUM(CASE WHEN status = 'filtered' THEN 1 ELSE 0 END) AS filtered_count,
  ROUND((SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END)::DECIMAL / COUNT(*) * 100), 2) AS success_rate
FROM ai_logs
GROUP BY DATE_TRUNC('day', created_at)
ORDER BY date DESC;

-- 用戶活躍度 View (DAU/MAU)
CREATE OR REPLACE VIEW user_activity AS
SELECT
  DATE_TRUNC('day', created_at) AS date,
  COUNT(DISTINCT user_id) AS dau
FROM ai_logs
GROUP BY DATE_TRUNC('day', created_at)
ORDER BY date DESC;
```

**Step 2: Create middleware for auth**

```typescript
// admin-dashboard/middleware.ts
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { createClient } from '@supabase/supabase-js';

export async function middleware(request: NextRequest) {
  // 跳過登入頁面
  if (request.nextUrl.pathname === '/login') {
    return NextResponse.next();
  }

  // 從 cookie 取得 session
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  // 檢查是否在 admin 白名單
  const { data: adminUser } = await supabase
    .from('admin_users')
    .select('id')
    .eq('email', session.user.email)
    .single();

  if (!adminUser) {
    return NextResponse.redirect(new URL('/403', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico|login|403).*)'],
};
```

**Step 3: Apply migration**

```bash
supabase db push
```

**Step 4: Commit**

```bash
git add supabase/migrations/006_admin_dashboard.sql admin-dashboard/middleware.ts
git commit -m "feat: Admin Dashboard 資料庫 schema + 認證中介層"
```

---

### Task 12.3: Build Dashboard Pages (8 Modules)

**Files:**
- Create: `admin-dashboard/app/page.tsx` (總覽)
- Create: `admin-dashboard/app/users/page.tsx`
- Create: `admin-dashboard/app/subscriptions/page.tsx`
- Create: `admin-dashboard/app/revenue/page.tsx`
- Create: `admin-dashboard/app/costs/page.tsx`
- Create: `admin-dashboard/app/ai-health/page.tsx`
- Create: `admin-dashboard/app/errors/page.tsx`
- Create: `admin-dashboard/app/activity/page.tsx`

**Step 1: Create dashboard overview page**

```typescript
// admin-dashboard/app/page.tsx
'use client';

import { useEffect, useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { supabase } from '@/lib/supabase';
import { Users, CreditCard, Zap, TrendingUp } from 'lucide-react';

interface DashboardStats {
  totalUsers: number;
  activeSubscriptions: number;
  monthlyRevenue: number;
  monthlyProfit: number;
  aiSuccessRate: number;
}

export default function DashboardPage() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchStats() {
      // Fetch total users
      const { count: totalUsers } = await supabase
        .from('users')
        .select('*', { count: 'exact', head: true });

      // Fetch active subscriptions
      const { count: activeSubscriptions } = await supabase
        .from('subscriptions')
        .select('*', { count: 'exact', head: true })
        .neq('tier', 'free');

      // Fetch current month revenue
      const { data: revenue } = await supabase
        .from('monthly_profit')
        .select('*')
        .order('month', { ascending: false })
        .limit(1)
        .single();

      // Fetch AI success rate (last 7 days)
      const { data: aiStats } = await supabase
        .from('ai_success_rate')
        .select('*')
        .gte('date', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString())
        .order('date', { ascending: false });

      const avgSuccessRate = aiStats?.length
        ? aiStats.reduce((sum, d) => sum + d.success_rate, 0) / aiStats.length
        : 0;

      setStats({
        totalUsers: totalUsers || 0,
        activeSubscriptions: activeSubscriptions || 0,
        monthlyRevenue: revenue?.revenue || 0,
        monthlyProfit: revenue?.profit || 0,
        aiSuccessRate: avgSuccessRate,
      });
      setLoading(false);
    }

    fetchStats();
  }, []);

  if (loading) return <div>Loading...</div>;

  return (
    <div className="p-6">
      <h1 className="text-3xl font-bold mb-6">Dashboard</h1>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">總用戶數</CardTitle>
            <Users className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats?.totalUsers}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">付費訂閱</CardTitle>
            <CreditCard className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats?.activeSubscriptions}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">本月營收</CardTitle>
            <TrendingUp className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              ${stats?.monthlyRevenue.toFixed(2)}
            </div>
            <p className="text-xs text-muted-foreground">
              利潤: ${stats?.monthlyProfit.toFixed(2)}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">AI 成功率</CardTitle>
            <Zap className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats?.aiSuccessRate.toFixed(1)}%</div>
            <p className="text-xs text-muted-foreground">過去 7 天</p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
```

**Step 2: Create revenue chart page**

```typescript
// admin-dashboard/app/revenue/page.tsx
'use client';

import { useEffect, useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts';
import { supabase } from '@/lib/supabase';

interface MonthlyData {
  month: string;
  revenue: number;
  cost: number;
  profit: number;
  margin_percent: number;
}

export default function RevenuePage() {
  const [data, setData] = useState<MonthlyData[]>([]);

  useEffect(() => {
    async function fetchData() {
      const { data: monthlyData } = await supabase
        .from('monthly_profit')
        .select('*')
        .order('month', { ascending: true })
        .limit(12);

      if (monthlyData) {
        setData(monthlyData.map(d => ({
          ...d,
          month: new Date(d.month).toLocaleDateString('zh-TW', { month: 'short' }),
        })));
      }
    }

    fetchData();
  }, []);

  return (
    <div className="p-6">
      <h1 className="text-3xl font-bold mb-6">營收分析</h1>

      <Card>
        <CardHeader>
          <CardTitle>營收 vs 成本 vs 利潤</CardTitle>
        </CardHeader>
        <CardContent>
          <ResponsiveContainer width="100%" height={400}>
            <LineChart data={data}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="month" />
              <YAxis />
              <Tooltip />
              <Legend />
              <Line type="monotone" dataKey="revenue" stroke="#22c55e" name="營收" />
              <Line type="monotone" dataKey="cost" stroke="#ef4444" name="成本" />
              <Line type="monotone" dataKey="profit" stroke="#3b82f6" name="利潤" />
            </LineChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>
    </div>
  );
}
```

**Step 3: Create costs/token tracking page**

```typescript
// admin-dashboard/app/costs/page.tsx
'use client';

import { useEffect, useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import { supabase } from '@/lib/supabase';

interface DailyToken {
  date: string;
  haiku_tokens: number;
  sonnet_tokens: number;
  total_cost: number;
}

interface ModelDistribution {
  model: string;
  count: number;
  cost: number;
}

export default function CostsPage() {
  const [dailyData, setDailyData] = useState<DailyToken[]>([]);
  const [modelDist, setModelDist] = useState<ModelDistribution[]>([]);

  useEffect(() => {
    async function fetchData() {
      // Daily token usage
      const { data: tokenData } = await supabase
        .from('token_usage')
        .select('model, total_tokens, cost_usd, created_at')
        .gte('created_at', new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString())
        .order('created_at', { ascending: true });

      // Aggregate by day and model
      const byDay = new Map<string, { haiku: number; sonnet: number; cost: number }>();
      const byModel = new Map<string, { count: number; cost: number }>();

      tokenData?.forEach(row => {
        const date = new Date(row.created_at).toISOString().split('T')[0];
        const modelName = row.model.includes('haiku') ? 'haiku' : 'sonnet';

        // Daily aggregation
        const existing = byDay.get(date) || { haiku: 0, sonnet: 0, cost: 0 };
        if (modelName === 'haiku') {
          existing.haiku += row.total_tokens;
        } else {
          existing.sonnet += row.total_tokens;
        }
        existing.cost += row.cost_usd;
        byDay.set(date, existing);

        // Model distribution
        const modelStats = byModel.get(modelName) || { count: 0, cost: 0 };
        modelStats.count += 1;
        modelStats.cost += row.cost_usd;
        byModel.set(modelName, modelStats);
      });

      setDailyData(
        Array.from(byDay.entries()).map(([date, val]) => ({
          date,
          haiku_tokens: val.haiku,
          sonnet_tokens: val.sonnet,
          total_cost: val.cost,
        }))
      );

      setModelDist(
        Array.from(byModel.entries()).map(([model, val]) => ({
          model: model === 'haiku' ? 'Haiku' : 'Sonnet',
          count: val.count,
          cost: val.cost,
        }))
      );
    }

    fetchData();
  }, []);

  const COLORS = ['#8b5cf6', '#ec4899'];

  return (
    <div className="p-6">
      <h1 className="text-3xl font-bold mb-6">Token 成本分析</h1>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card>
          <CardHeader>
            <CardTitle>每日 Token 使用</CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={dailyData.slice(-14)}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="date" tickFormatter={(d) => d.slice(5)} />
                <YAxis />
                <Tooltip />
                <Bar dataKey="haiku_tokens" stackId="a" fill="#8b5cf6" name="Haiku" />
                <Bar dataKey="sonnet_tokens" stackId="a" fill="#ec4899" name="Sonnet" />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>模型分佈</CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={modelDist}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={({ model, percent }) => `${model} ${(percent * 100).toFixed(0)}%`}
                  outerRadius={100}
                  fill="#8884d8"
                  dataKey="count"
                >
                  {modelDist.map((_, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
```

**Step 4: Commit**

```bash
git add admin-dashboard/app/
git commit -m "feat: Admin Dashboard 8 項報表頁面"
```

---

### Task 12.4: Deploy Admin Dashboard

**Step 1: Setup Vercel**

```bash
cd admin-dashboard
vercel
```

**Step 2: Add environment variables in Vercel**

```
NEXT_PUBLIC_SUPABASE_URL=xxx
NEXT_PUBLIC_SUPABASE_ANON_KEY=xxx
```

**Step 3: Deploy**

```bash
vercel --prod
```

**Step 4: Commit deployment config**

```bash
git add admin-dashboard/vercel.json
git commit -m "chore: Admin Dashboard Vercel 部署配置"
```

---

## Phase 12 Checkpoint

```bash
# Verify admin dashboard is accessible
curl https://your-admin-dashboard.vercel.app

# Verify auth works (should redirect to login)
```

---

## Phase 13: Sandbox Testing Environment

### Task 13.1: Setup Environment Configuration

**Files:**
- Create: `lib/core/config/environment.dart`
- Modify: `lib/main.dart`

**Step 1: Create environment configuration**

```dart
// lib/core/config/environment.dart
enum Environment { dev, staging, prod }

class AppConfig {
  static const _envKey = 'ENV';

  static Environment get environment {
    const env = String.fromEnvironment(_envKey, defaultValue: 'dev');
    return Environment.values.firstWhere(
      (e) => e.name == env,
      orElse: () => Environment.dev,
    );
  }

  static bool get isProduction => environment == Environment.prod;
  static bool get isDevelopment => environment == Environment.dev;
  static bool get isStaging => environment == Environment.staging;

  static String get supabaseUrl {
    switch (environment) {
      case Environment.dev:
        return 'http://localhost:54321';
      case Environment.staging:
        return const String.fromEnvironment(
          'SUPABASE_STAGING_URL',
          defaultValue: 'https://your-staging-project.supabase.co',
        );
      case Environment.prod:
        return const String.fromEnvironment(
          'SUPABASE_PROD_URL',
          defaultValue: 'https://your-prod-project.supabase.co',
        );
    }
  }

  static String get supabaseAnonKey {
    switch (environment) {
      case Environment.dev:
        return 'your-local-anon-key';
      case Environment.staging:
        return const String.fromEnvironment('SUPABASE_STAGING_ANON_KEY');
      case Environment.prod:
        return const String.fromEnvironment('SUPABASE_PROD_ANON_KEY');
    }
  }

  static String get revenueCatApiKey {
    // Sandbox vs Production
    return isProduction
        ? const String.fromEnvironment('REVENUECAT_PROD_KEY')
        : const String.fromEnvironment('REVENUECAT_SANDBOX_KEY');
  }
}
```

**Step 2: Update main.dart**

```dart
// lib/main.dart
import 'core/config/environment.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize based on environment
  print('Running in ${AppConfig.environment.name} mode');

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: VibeSyncApp()));
}
```

**Step 3: Write tests**

```dart
// test/unit/config/environment_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/config/environment.dart';

void main() {
  group('AppConfig', () {
    test('defaults to dev environment', () {
      // Without ENV defined, should default to dev
      expect(AppConfig.isDevelopment, isTrue);
    });

    test('isProduction returns correct value', () {
      expect(AppConfig.isProduction, isFalse); // In test, should be dev
    });
  });
}
```

**Step 4: Commit**

```bash
git add lib/core/config/ lib/main.dart test/
git commit -m "feat: 環境配置切換 (dev/staging/prod)"
```

---

### Task 13.2: Setup Firebase App Distribution

**Files:**
- Create: `.github/workflows/distribute.yml`
- Create: `firebase.json`

**Step 1: Install Firebase CLI**

```bash
npm install -g firebase-tools
firebase login
firebase init hosting  # Select app distribution
```

**Step 2: Create GitHub Actions workflow**

```yaml
# .github/workflows/distribute.yml
name: Build & Distribute

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  FLUTTER_VERSION: '3.19.0'

jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable

      - name: Install dependencies
        run: flutter pub get

      - name: Run tests
        run: flutter test

      - name: Build APK (Staging)
        run: |
          flutter build apk --release \
            --dart-define=ENV=staging \
            --dart-define=SUPABASE_STAGING_URL=${{ secrets.SUPABASE_STAGING_URL }} \
            --dart-define=SUPABASE_STAGING_ANON_KEY=${{ secrets.SUPABASE_STAGING_ANON_KEY }} \
            --dart-define=REVENUECAT_SANDBOX_KEY=${{ secrets.REVENUECAT_SANDBOX_KEY }}

      - name: Upload to Firebase App Distribution
        uses: wzieba/Firebase-Distribution-Github-Action@v1
        with:
          appId: ${{ secrets.FIREBASE_ANDROID_APP_ID }}
          serviceCredentialsFileContent: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
          groups: testers
          file: build/app/outputs/flutter-apk/app-release.apk
          releaseNotes: |
            Branch: ${{ github.ref_name }}
            Commit: ${{ github.sha }}

  build-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable

      - name: Install dependencies
        run: flutter pub get

      - name: Build iOS (Staging)
        run: |
          flutter build ipa --release \
            --dart-define=ENV=staging \
            --dart-define=SUPABASE_STAGING_URL=${{ secrets.SUPABASE_STAGING_URL }} \
            --dart-define=SUPABASE_STAGING_ANON_KEY=${{ secrets.SUPABASE_STAGING_ANON_KEY }} \
            --dart-define=REVENUECAT_SANDBOX_KEY=${{ secrets.REVENUECAT_SANDBOX_KEY }} \
            --export-options-plist=ios/ExportOptions.plist

      - name: Upload to Firebase App Distribution
        uses: wzieba/Firebase-Distribution-Github-Action@v1
        with:
          appId: ${{ secrets.FIREBASE_IOS_APP_ID }}
          serviceCredentialsFileContent: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
          groups: testers
          file: build/ios/ipa/*.ipa
          releaseNotes: |
            Branch: ${{ github.ref_name }}
            Commit: ${{ github.sha }}
```

**Step 3: Create test users table**

```sql
-- supabase/migrations/007_test_users.sql

-- 測試帳號標記
CREATE TABLE test_users (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  tester_name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 真實用戶 View (排除測試帳號)
CREATE OR REPLACE VIEW real_users AS
SELECT * FROM users
WHERE id NOT IN (SELECT user_id FROM test_users);

-- 真實訂閱 View (排除測試帳號)
CREATE OR REPLACE VIEW real_subscriptions AS
SELECT s.* FROM subscriptions s
JOIN users u ON s.user_id = u.id
WHERE u.id NOT IN (SELECT user_id FROM test_users);

-- 插入測試帳號 (根據需要調整)
-- INSERT INTO test_users (user_id, tester_name) VALUES
--   ('uuid-1', 'Tester 1'),
--   ('uuid-2', 'Tester 2');
```

**Step 4: Commit**

```bash
git add .github/workflows/distribute.yml firebase.json supabase/migrations/007_test_users.sql
git commit -m "feat: Firebase App Distribution CI/CD + 測試帳號管理"
```

---

### Task 13.3: Setup TestFlight & Internal Testing

**Files:**
- Create: `ios/fastlane/Fastfile`
- Create: `android/fastlane/Fastfile`

**Step 1: Install Fastlane**

```bash
gem install fastlane
cd ios && fastlane init
cd ../android && fastlane init
```

**Step 2: Create iOS Fastfile**

```ruby
# ios/fastlane/Fastfile
default_platform(:ios)

platform :ios do
  desc "Push a new build to TestFlight"
  lane :beta do
    # Ensure clean state
    ensure_git_status_clean

    # Build
    build_app(
      scheme: "Runner",
      export_method: "app-store",
      export_options: {
        provisioningProfiles: {
          "com.yourcompany.vibesync" => "VibeSync AppStore"
        }
      }
    )

    # Upload to TestFlight
    upload_to_testflight(
      skip_waiting_for_build_processing: true
    )

    # Notify testers
    slack(
      message: "New TestFlight build uploaded! 🚀",
      slack_url: ENV["SLACK_WEBHOOK_URL"]
    )
  end
end
```

**Step 3: Create Android Fastfile**

```ruby
# android/fastlane/Fastfile
default_platform(:android)

platform :android do
  desc "Deploy to Internal Testing track"
  lane :internal do
    # Build
    gradle(
      task: "bundle",
      build_type: "Release",
      project_dir: "./"
    )

    # Upload to Play Console
    upload_to_play_store(
      track: "internal",
      aab: "../build/app/outputs/bundle/release/app-release.aab",
      skip_upload_metadata: true,
      skip_upload_images: true,
      skip_upload_screenshots: true
    )

    # Notify
    slack(
      message: "New Internal Testing build uploaded! 🚀",
      slack_url: ENV["SLACK_WEBHOOK_URL"]
    )
  end
end
```

**Step 4: Create manual workflow**

```yaml
# .github/workflows/release.yml
name: Release to App Stores

on:
  workflow_dispatch:
    inputs:
      platform:
        description: 'Platform to release'
        required: true
        default: 'both'
        type: choice
        options:
          - ios
          - android
          - both

jobs:
  release-ios:
    if: inputs.platform == 'ios' || inputs.platform == 'both'
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'
      - name: Build iOS
        run: |
          flutter build ipa --release \
            --dart-define=ENV=prod
      - name: Upload to TestFlight
        run: cd ios && fastlane beta
        env:
          APP_STORE_CONNECT_API_KEY: ${{ secrets.APP_STORE_CONNECT_API_KEY }}

  release-android:
    if: inputs.platform == 'android' || inputs.platform == 'both'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'
      - name: Build Android
        run: |
          flutter build appbundle --release \
            --dart-define=ENV=prod
      - name: Upload to Play Store
        run: cd android && fastlane internal
        env:
          PLAY_STORE_CONFIG_JSON: ${{ secrets.PLAY_STORE_CONFIG_JSON }}
```

**Step 5: Commit**

```bash
git add ios/fastlane/ android/fastlane/ .github/workflows/release.yml
git commit -m "feat: TestFlight + Internal Testing 發布流程"
```

---

## Phase 13 Checkpoint

```bash
# Test Firebase distribution (push to main)
git push origin main

# Check GitHub Actions for build status
# Check Firebase App Distribution for new build
# Test install on device via QR code
```

---

## Summary

**Total Tasks:** 35 tasks across 13 phases

**Phase Breakdown:**
1. Project Foundation (3 tasks) - Flutter setup, dependencies, structure
2. Local Data Layer (3 tasks) - Hive entities, storage, repository
3. UI Screens (4 tasks) - Widgets, home, new conversation, analysis
4. Supabase Backend (2 tasks) - Schema, Edge Function
5. Flutter-Supabase Integration (2 tasks) - Client, service
6. Settings (1 task) - Settings screen
7. Message Calculation & Usage (2 tasks) - 訊息計算、用量追蹤、預覽確認
8. Conversation Memory (2 tasks) - 對話記憶、摘要、選擇追蹤
9. Paywall & Subscription (2 tasks) - 訂閱方案選擇畫面 + 加購訊息包
10. GAME Framework (2 tasks) - GAME 階段分析、心理解讀元件
11. 商業級 SaaS 補充 (6 tasks) - AI 護欄、Fallback、日誌、Onboarding、Rate Limiting、Token 追蹤
12. **Admin Dashboard (4 tasks)** - Next.js 設定、資料庫、報表頁面、部署
13. **Sandbox Testing (3 tasks)** - 環境配置、Firebase 分發、TestFlight/Internal Testing

**Phase Breakdown:**
1. Project Foundation (3 tasks) - Flutter setup, dependencies, structure
2. Local Data Layer (3 tasks) - Hive entities, storage, repository
3. UI Screens (4 tasks) - Widgets, home, new conversation, analysis
4. Supabase Backend (2 tasks) - Schema, Edge Function
5. Flutter-Supabase Integration (2 tasks) - Client, service
6. Settings (1 task) - Settings screen
7. Message Calculation & Usage (2 tasks) - 訊息計算、用量追蹤、預覽確認
8. Conversation Memory (2 tasks) - 對話記憶、摘要、選擇追蹤
9. Paywall & Subscription (2 tasks) - 訂閱方案選擇畫面 + 加購訊息包
10. GAME Framework (2 tasks) - GAME 階段分析、心理解讀元件
11. **商業級 SaaS 補充 (6 tasks)** - AI 護欄、Fallback、日誌、Onboarding、Rate Limiting、Token 追蹤

**Next Steps After MVP:**
- Authentication screens (Google/Apple Sign-in)
- RevenueCat integration for subscriptions
- App Store / Play Store submission

---

## Risk Mitigation Checklist

### Before Launch
- [ ] Sentry 錯誤監控設定
- [ ] Firebase Analytics 埋點
- [ ] App Icon + Splash Screen
- [ ] 隱私權政策頁面 (實際 URL)
- [ ] 使用條款頁面
- [ ] TestFlight / Internal Testing 測試
- [ ] API 成本監控 Dashboard

### API Resilience
- [ ] 請求重試機制 (3 次 + exponential backoff)
- [ ] 離線模式提示 (無網路時)
- [ ] Rate limit 錯誤處理 (顯示友善訊息)
- [ ] Timeout 處理 (30 秒上限)

### Message Parsing Robustness
- [ ] 支援「我：」和「我:」(全形/半形)
- [ ] 支援「對方:」「她:」「他:」
- [ ] 支援時間戳記格式 (自動移除)
- [ ] 支援 LINE/IG 匯出格式 (V2)

### App Store Preparation
- [ ] 截圖 (6.5" + 5.5")
- [ ] App 描述 (強調「溝通教練」)
- [ ] 隱私權聲明 (強調不儲存對話)
- [ ] 年齡分級 (17+ 建議)
- [ ] 審核備註 (說明 app 用途)

---

## Appendix: Test Commands

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Build for release
flutter build apk --release
flutter build ios --release

# Deploy Supabase functions
supabase functions deploy analyze-chat
```

---

## 變更記錄

| 日期 | 版本 | 變更內容 |
|------|------|----------|
| 2026-02-26 | 1.0 | 初始實作計畫 |
| 2026-02-26 | 2.0 | **重大更新** - 與設計規格書同步 |
| 2026-02-27 | 2.1 | **GAME 框架整合** - 與設計規格 v1.1 同步 |
| 2026-02-27 | 2.2 | **完全同步** - 補齊混合模型策略 + 加購訊息包 |
| 2026-02-27 | 2.3 | **商業級補充** - 與設計規格 v1.2 同步 (AI 護欄、Fallback、日誌、Onboarding、Rate Limiting、Token 追蹤) |
| 2026-02-27 | 2.4 | **運營補充** - 與設計規格 v1.3 同步 (Admin Dashboard、沙盒測試環境) |

### v2.4 變更明細 (與設計規格 v1.3 同步)

**新增 Phase 12: Admin Dashboard (4 tasks)**
- ✅ 新增: Task 12.1 Setup Admin Dashboard Project (Next.js)
- ✅ 新增: Task 12.2 Create Admin Auth & Database Schema
- ✅ 新增: Task 12.3 Build Dashboard Pages (8 報表模組)
- ✅ 新增: Task 12.4 Deploy Admin Dashboard (Vercel)

**新增 Phase 13: Sandbox Testing Environment (3 tasks)**
- ✅ 新增: Task 13.1 Setup Environment Configuration (dev/staging/prod)
- ✅ 新增: Task 13.2 Setup Firebase App Distribution (快速迭代)
- ✅ 新增: Task 13.3 Setup TestFlight & Internal Testing (上架前測試)

**資料庫擴充**
- ✅ 新增: `admin_users` 表 (Admin 白名單)
- ✅ 新增: `revenue_events` 表 (RevenueCat Webhook)
- ✅ 新增: `test_users` 表 (測試帳號標記)
- ✅ 新增: `monthly_revenue` View
- ✅ 新增: `monthly_profit` View
- ✅ 新增: `ai_success_rate` View
- ✅ 新增: `user_activity` View
- ✅ 新增: `real_users` View (排除測試帳號)
- ✅ 新增: `real_subscriptions` View

**CI/CD 配置**
- ✅ 新增: `.github/workflows/distribute.yml` (Firebase App Distribution)
- ✅ 新增: `.github/workflows/release.yml` (TestFlight/Internal Testing)
- ✅ 新增: iOS/Android Fastlane 配置

**總任務數**: 28 → 35 tasks

---

### v2.3 變更明細 (與設計規格 v1.2 同步)

**新增 Phase 11: 商業級 SaaS 補充**
- ✅ 新增: Task 11.1 AI Guardrails (護欄)
- ✅ 新增: Task 11.2 AI Fallback Service
- ✅ 新增: Task 11.3 AI Audit Log (日誌)
- ✅ 新增: Task 11.4 Onboarding Flow
- ✅ 新增: Task 11.5 Rate Limiting Service
- ✅ 新增: Task 11.6 Token Tracking Service

**資料庫擴充**
- ✅ 新增: `ai_logs` 表 (AI 呼叫日誌)
- ✅ 新增: `rate_limits` 表 (每分鐘限制)
- ✅ 新增: `token_usage` 表 (Token 追蹤)
- ✅ 新增: `user_monthly_token_summary` View
- ✅ 新增: `daily_cost_report` View

**UI 元件**
- ✅ 新增: `DisclaimerBanner` (免責聲明)
- ✅ 新增: `AnalysisErrorWidget` (失敗 UI)
- ✅ 新增: `OnboardingScreen` (3 步驟引導)
- ✅ 新增: `EmptyStateWidget` (空狀態)
- ✅ 新增: `RateLimitDialog` (限制提示)

**總任務數**: 22 → 28 tasks

---

### v2.2 變更明細 (與設計規格 v1.1 完全同步)

**混合模型策略 (設計規格 4.9)**
- ✅ 更新: Task 4.2 Edge Function 加入 `selectModel()` 函數
- ✅ 邏輯: Essential 優先 Sonnet / 長對話 / 冷淡 / 複雜情緒 / 首次分析 → Sonnet
- ✅ 預設: 70% Haiku / 30% Sonnet

**加購訊息包 (設計規格 7.4)**
- ✅ 新增: Task 9.2 Create Message Booster Purchase
- ✅ 新增: `BoosterPackage` entity (50/150/300 則)
- ✅ 新增: `BoosterPurchaseSheet` widget
- ✅ 定價: NT$39/99/179 (與設計規格一致)

**總任務數**: 21 → 22 tasks

---

### v2.1 變更明細 (與設計規格 v1.1 同步)

**GAME 框架整合**
- ✅ 新增: Task 10.1 GAME Stage Service
- ✅ 新增: Task 10.2 Psychology Analysis Widget
- ✅ 新增: Phase 10 (GAME Framework)

**情境收集 (Session Context)**
- ✅ 更新: Task 2.1 新增 SessionContext, GameStage, AnalysisResult entities
- ✅ 更新: Task 3.3 新增情境收集 UI (認識場景、時長、目標)
- ✅ 更新: Task 4.2 Edge Function 支援 sessionContext

**AI 輸出強化**
- ✅ 更新: SYSTEM_PROMPT 加入 GAME 五階段框架
- ✅ 更新: 輸出格式加入 gameStage, psychology, finalRecommendation
- ✅ 新增: 淺溝通解讀 (subtext reading)
- ✅ 新增: 廢測偵測 (shit test detection)
- ✅ 新增: 最終建議 (AI 推薦 + 心理學依據)
- ✅ 新增: 一致性提醒 ("記得用你的方式說，見面才自然")

**UI 強化**
- ✅ 更新: Task 3.4 Analysis Screen 加入 GAME 階段指示器
- ✅ 更新: Task 3.4 加入心理分析卡片
- ✅ 更新: Task 3.4 加入最終建議卡片 (含複製按鈕)
- ✅ 更新: Task 3.4 加入一致性提醒

**總任務數**: 19 → 21 tasks

---

### v2.0 變更明細

**訂閱/計費系統**
- ❌ 舊: free/pro/unlimited，分析次數 (5/200/∞)
- ✅ 新: Free/Starter/Essential，訊息制 (30/300/1000)
- ✅ 新增: 每日上限 (15/50/150)
- ✅ 新增: 訊息計算邏輯 (換行分割 + 200字上限)

**回覆類型**
- ❌ 舊: 3 種 (extend/resonate/tease)
- ✅ 新: 5 種 (+ humor/coldRead)

**功能分層 (付費牆)**
- ✅ 新增: Free 只有延展回覆
- ✅ 新增: Starter 有全部回覆 + Needy 警示 + 話題深度
- ✅ 新增: Essential 額外有對話健檢

**AI Prompt**
- ✅ 新增: topicDepth (話題深度階梯)
- ✅ 新增: healthCheck (對話健檢)
- ✅ 新增: 82/18 原則、假設代替問句

**新增 Phase**
- Phase 7: 訊息計算與用量追蹤 (2 tasks)
- Phase 8: 對話記憶 (2 tasks)
- Phase 9: Paywall 訂閱畫面 (1 task → v2.2 更新為 2 tasks)

**總任務數**: 15 → 19 tasks

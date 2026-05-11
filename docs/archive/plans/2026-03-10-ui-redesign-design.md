# VibeSync UI 重構設計規格

> **建立日期**：2026-03-10
> **狀態**：已核准，待實作
> **參考圖**：image_1.jpg（溫暖粉紫漸層毛玻璃風格）

## 概述

將 VibeSync 從暗黑主題改為溫暖的粉紫漸層 + 毛玻璃風格，目標是創造 Gen Z 友善、約會 app 氛圍的視覺體驗。

## 設計決策摘要

| 項目 | 決定 |
|------|------|
| 背景風格 | B1 靜態光球（最終目標 B2 動態） |
| 毛玻璃範圍 | 僅互動元件（輸入框、選項按鈕） |
| 發光效果 | BoxShadow 實作 |
| CTA 按鈕 | 珊瑚漸層，全 app 統一 |
| 頭像風格 | 漸層泡泡 |
| 實作方案 | 修改現有 Theme 系統 |
| 重構範圍 | 分階段，Phase 1 先做「新增對話」頁 |
| 平台策略 | Web 優先，iOS 自動同步 |

---

## 1. 色彩系統

### 1.1 新增顏色（AppColors）

```dart
// === 背景漸層 ===
static const backgroundGradientStart = Color(0xFF1A0533);  // 深紫
static const backgroundGradientMid = Color(0xFF2D1B4E);    // 中紫
static const backgroundGradientEnd = Color(0xFF4A2C6A);    // 淡紫

// === 光暈泡泡（Bokeh） ===
static const bokehPink = Color(0xFFFF6B9D);      // 粉紅
static const bokehCoral = Color(0xFFFF8A65);     // 珊瑚
static const bokehYellow = Color(0xFFFFD54F);    // 淡黃

// === 毛玻璃 ===
static const glassWhite = Color(0x1AFFFFFF);     // 10% 白
static const glassBorder = Color(0x33FFFFFF);    // 20% 白邊框

// === 選中狀態漸層 ===
static const selectedStart = Color(0xFFFF6B9D);  // 粉紅
static const selectedEnd = Color(0xFFFF8A65);    // 珊瑚

// === CTA 按鈕漸層 ===
static const ctaStart = Color(0xFFFF7043);       // 珊瑚
static const ctaEnd = Color(0xFFFF5722);         // 橘紅
```

---

## 2. 共用元件

### 2.1 GradientBackground

**檔案**：`lib/shared/widgets/gradient_background.dart`

**功能**：
- 三色漸層背景（深紫 → 中紫 → 淡紫）
- 3-4 個定位的模糊光球（bokeh 效果）
- 包覆子元件

**使用方式**：
```dart
GradientBackground(
  child: Scaffold(...),
)
```

**光球配置**：
| 位置 | 顏色 | 大小 | 模糊度 |
|------|------|------|--------|
| 右上 | bokehPink | 150 | 80 |
| 左下 | bokehCoral | 120 | 60 |
| 中右 | bokehYellow | 100 | 50 |

### 2.2 GlassmorphicContainer

**檔案**：`lib/shared/widgets/glassmorphic_container.dart`

**功能**：
- 半透明白色背景（10-20%）
- 模糊效果（BackdropFilter）
- 圓角邊框
- 可選發光邊緣（選中狀態）

**使用方式**：
```dart
GlassmorphicContainer(
  child: TextField(...),
  borderRadius: 12,
  isSelected: false,
  glowColor: AppColors.selectedStart,
)
```

**樣式參數**：
- 背景：`glassWhite`（10% 白）
- 邊框：`glassBorder`（20% 白）
- 圓角：12px
- 模糊：`sigmaX: 10, sigmaY: 10`

### 2.3 GradientButton

**檔案**：`lib/shared/widgets/gradient_button.dart`

**功能**：
- 珊瑚→橘紅漸層
- 膠囊形狀（StadiumBorder）
- 柔和陰影
- 點擊縮放效果

**使用方式**：
```dart
GradientButton(
  text: '開始分析',
  onPressed: () => ...,
  isLoading: false,
)
```

**樣式參數**：
- 漸層：`ctaStart` → `ctaEnd`
- 高度：52px
- 陰影：`BoxShadow` 珊瑚色 20% opacity, blur 15

### 2.4 BubbleAvatar

**檔案**：`lib/shared/widgets/bubble_avatar.dart`

**功能**：
- 漸層圓球效果
- 「她」用黃色系漸層
- 「我」用紫色系漸層

**使用方式**：
```dart
BubbleAvatar(
  label: '她',
  isMe: false,
  size: 32,
)
```

**顏色配置**：
| 類型 | 漸層起始 | 漸層結束 |
|------|----------|----------|
| 她 | `#FFD54F` | `#FFC107` |
| 我 | `#9D8DF7` | `#6B4EE6` |

---

## 3. 頁面修改

### 3.1 新增對話頁（Phase 1）

**檔案**：`lib/features/conversation/presentation/screens/new_conversation_screen.dart`

| 元素 | 現況 | 改成 |
|------|------|------|
| 背景 | 純黑 `#121212` | `GradientBackground` |
| AppBar | 黑色背景 | 透明，融入漸層 |
| 輸入框 | 實心深灰 | `GlassmorphicContainer` |
| SegmentedButton | Material 預設紫 | 自訂毛玻璃 + 選中粉紅發光 |
| 「她」「我」頭像 | 實心圓 | `BubbleAvatar` |
| 「開始分析」按鈕 | 紫色方角 | `GradientButton` |

### 3.2 Phase 2+ 擴展

完成 Phase 1 後，元件可直接套用到：

| 頁面 | 套用元件 |
|------|----------|
| 首頁 | `GradientBackground`、對話卡片毛玻璃化 |
| 分析結果 | `GradientBackground`、回覆卡片毛玻璃化 |
| 登入/註冊 | `GradientBackground`、`GlassmorphicContainer`、`GradientButton` |
| 設定 | `GradientBackground`、選項毛玻璃化 |

---

## 4. 技術考量

### 4.1 效能

| 項目 | 處理方式 |
|------|----------|
| BackdropFilter | 限制層疊數量，避免效能問題 |
| 漸層渲染 | 使用 `DecoratedBox`，避免不必要的 rebuild |
| 光球數量 | 控制在 3-4 個 |
| Web 相容性 | 測試 Safari/Chrome blur 效果 |

### 4.2 程式碼結構

```
lib/
├── core/theme/
│   ├── app_colors.dart      ← 新增漸層色
│   └── app_theme.dart       ← 更新透明 AppBar
│
├── shared/widgets/
│   ├── gradient_background.dart   ← 新增
│   ├── glassmorphic_container.dart ← 新增
│   ├── gradient_button.dart       ← 新增
│   └── bubble_avatar.dart         ← 新增
│
└── features/conversation/presentation/screens/
    └── new_conversation_screen.dart  ← 套用新元件
```

---

## 5. 驗收標準

- [ ] 新增對話頁視覺效果接近 image_1（90%+）
- [ ] 毛玻璃效果在 Chrome/Safari 正常顯示
- [ ] 所有互動元件功能正常
- [ ] 效能無明顯卡頓
- [ ] Web 版測試通過後 push

---

## 6. 未來規劃

### 6.1 B2 動態光球（Phase 3）

Phase 1 完成後，可升級光球為動態效果：
- 緩慢浮動動畫
- 呼吸效果（大小漸變）
- 使用 `AnimationController` + `Transform`

### 6.2 完整 App 套用（Phase 2）

依序套用到所有頁面，保持視覺一致性。

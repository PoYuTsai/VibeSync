# UI 重構實作計畫（Phase 1）

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 將「新增對話」頁面從暗黑主題改為溫暖粉紫漸層毛玻璃風格，視覺效果接近 image_1 參考圖。

**Architecture:** 修改現有 Theme 系統，新增 4 個共用元件（GradientBackground, GlassmorphicContainer, GradientButton, BubbleAvatar），然後套用到 new_conversation_screen.dart。

**Tech Stack:** Flutter 3.x, dart:ui (BackdropFilter), Material 3

**設計文件:** `docs/plans/2026-03-10-ui-redesign-design.md`

---

## Task 1: 更新 AppColors 色彩系統

**Files:**
- Modify: `lib/core/theme/app_colors.dart`

**Step 1: 新增漸層和毛玻璃顏色**

在 `AppColors` class 中，`info` 定義之後新增：

```dart
  // === Warm Theme - 漸層背景 ===
  static const backgroundGradientStart = Color(0xFF1A0533);  // 深紫
  static const backgroundGradientMid = Color(0xFF2D1B4E);    // 中紫
  static const backgroundGradientEnd = Color(0xFF4A2C6A);    // 淡紫

  // === Warm Theme - 光暈泡泡 ===
  static const bokehPink = Color(0xFFFF6B9D);
  static const bokehCoral = Color(0xFFFF8A65);
  static const bokehYellow = Color(0xFFFFD54F);

  // === Warm Theme - 毛玻璃 ===
  static const glassWhite = Color(0x1AFFFFFF);     // 10% 白
  static const glassBorder = Color(0x33FFFFFF);    // 20% 白

  // === Warm Theme - 選中狀態 ===
  static const selectedStart = Color(0xFFFF6B9D);
  static const selectedEnd = Color(0xFFFF8A65);

  // === Warm Theme - CTA 按鈕 ===
  static const ctaStart = Color(0xFFFF7043);
  static const ctaEnd = Color(0xFFFF5722);

  // === Warm Theme - 頭像漸層 ===
  static const avatarHerStart = Color(0xFFFFD54F);
  static const avatarHerEnd = Color(0xFFFFC107);
  static const avatarMeStart = Color(0xFF9D8DF7);
  static const avatarMeEnd = Color(0xFF6B4EE6);
```

**Step 2: 驗證編譯**

Run: `flutter analyze lib/core/theme/app_colors.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/core/theme/app_colors.dart
git commit -m "feat(theme): 新增 Warm Theme 色彩變數"
```

---

## Task 2: 建立 GradientBackground 元件

**Files:**
- Create: `lib/shared/widgets/gradient_background.dart`

**Step 1: 建立漸層背景元件**

```dart
// lib/shared/widgets/gradient_background.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 溫暖漸層背景 + 靜態光球效果
class GradientBackground extends StatelessWidget {
  final Widget child;

  const GradientBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.backgroundGradientStart,
            AppColors.backgroundGradientMid,
            AppColors.backgroundGradientEnd,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // 光球 1 - 右上粉紅
          Positioned(
            top: -50,
            right: -30,
            child: _BokehOrb(
              color: AppColors.bokehPink,
              size: 150,
              blur: 80,
            ),
          ),
          // 光球 2 - 左下珊瑚
          Positioned(
            bottom: 100,
            left: -40,
            child: _BokehOrb(
              color: AppColors.bokehCoral,
              size: 120,
              blur: 60,
            ),
          ),
          // 光球 3 - 中右黃色
          Positioned(
            top: MediaQuery.of(context).size.height * 0.4,
            right: -20,
            child: _BokehOrb(
              color: AppColors.bokehYellow,
              size: 100,
              blur: 50,
            ),
          ),
          // 主內容
          child,
        ],
      ),
    );
  }
}

class _BokehOrb extends StatelessWidget {
  final Color color;
  final double size;
  final double blur;

  const _BokehOrb({
    required this.color,
    required this.size,
    required this.blur,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.6),
            blurRadius: blur,
            spreadRadius: blur / 2,
          ),
        ],
      ),
    );
  }
}
```

**Step 2: 驗證編譯**

Run: `flutter analyze lib/shared/widgets/gradient_background.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/shared/widgets/gradient_background.dart
git commit -m "feat(ui): 新增 GradientBackground 漸層背景元件"
```

---

## Task 3: 建立 GlassmorphicContainer 元件

**Files:**
- Create: `lib/shared/widgets/glassmorphic_container.dart`

**Step 1: 建立毛玻璃容器元件**

```dart
// lib/shared/widgets/glassmorphic_container.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 毛玻璃效果容器
class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final bool isSelected;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  const GlassmorphicContainer({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.isSelected = false,
    this.padding,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.selectedStart.withOpacity(0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.selectedStart.withOpacity(0.3)
                  : AppColors.glassWhite,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: isSelected
                    ? AppColors.selectedStart.withOpacity(0.5)
                    : AppColors.glassBorder,
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
```

**Step 2: 驗證編譯**

Run: `flutter analyze lib/shared/widgets/glassmorphic_container.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/shared/widgets/glassmorphic_container.dart
git commit -m "feat(ui): 新增 GlassmorphicContainer 毛玻璃元件"
```

---

## Task 4: 建立 GradientButton 元件

**Files:**
- Create: `lib/shared/widgets/gradient_button.dart`

**Step 1: 建立漸層按鈕元件**

```dart
// lib/shared/widgets/gradient_button.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 珊瑚漸層 CTA 按鈕
class GradientButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;

  const GradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.height = 52,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null || widget.isLoading;

    return GestureDetector(
      onTapDown: isDisabled ? null : (_) => setState(() => _isPressed = true),
      onTapUp: isDisabled ? null : (_) => setState(() => _isPressed = false),
      onTapCancel: isDisabled ? null : () => setState(() => _isPressed = false),
      onTap: isDisabled ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDisabled
                  ? [Colors.grey.shade600, Colors.grey.shade700]
                  : [AppColors.ctaStart, AppColors.ctaEnd],
            ),
            borderRadius: BorderRadius.circular(widget.height / 2),
            boxShadow: isDisabled
                ? null
                : [
                    BoxShadow(
                      color: AppColors.ctaStart.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    widget.text,
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
```

**Step 2: 驗證編譯**

Run: `flutter analyze lib/shared/widgets/gradient_button.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/shared/widgets/gradient_button.dart
git commit -m "feat(ui): 新增 GradientButton 漸層按鈕元件"
```

---

## Task 5: 建立 BubbleAvatar 元件

**Files:**
- Create: `lib/shared/widgets/bubble_avatar.dart`

**Step 1: 建立泡泡頭像元件**

```dart
// lib/shared/widgets/bubble_avatar.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 漸層泡泡頭像
class BubbleAvatar extends StatelessWidget {
  final String label;
  final bool isMe;
  final double size;

  const BubbleAvatar({
    super.key,
    required this.label,
    required this.isMe,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isMe
              ? [AppColors.avatarMeStart, AppColors.avatarMeEnd]
              : [AppColors.avatarHerStart, AppColors.avatarHerEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: (isMe ? AppColors.avatarMeEnd : AppColors.avatarHerEnd)
                .withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
```

**Step 2: 驗證編譯**

Run: `flutter analyze lib/shared/widgets/bubble_avatar.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/shared/widgets/bubble_avatar.dart
git commit -m "feat(ui): 新增 BubbleAvatar 泡泡頭像元件"
```

---

## Task 6: 建立 GlassmorphicSegmentedButton 元件

**Files:**
- Create: `lib/shared/widgets/glassmorphic_segmented_button.dart`

**Step 1: 建立毛玻璃分段按鈕**

```dart
// lib/shared/widgets/glassmorphic_segmented_button.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 毛玻璃風格的分段選擇按鈕
class GlassmorphicSegmentedButton<T> extends StatelessWidget {
  final List<GlassSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  const GlassmorphicSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: segments.map((segment) {
              final isSelected = segment.value == selected;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(segment.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [
                                AppColors.selectedStart,
                                AppColors.selectedEnd,
                              ],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.selectedStart.withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isSelected) ...[
                          const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          segment.label,
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.white,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class GlassSegment<T> {
  final T value;
  final String label;

  const GlassSegment({
    required this.value,
    required this.label,
  });
}
```

**Step 2: 驗證編譯**

Run: `flutter analyze lib/shared/widgets/glassmorphic_segmented_button.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/shared/widgets/glassmorphic_segmented_button.dart
git commit -m "feat(ui): 新增 GlassmorphicSegmentedButton 毛玻璃分段按鈕"
```

---

## Task 7: 建立 GlassmorphicTextField 元件

**Files:**
- Create: `lib/shared/widgets/glassmorphic_text_field.dart`

**Step 1: 建立毛玻璃輸入框**

```dart
// lib/shared/widgets/glassmorphic_text_field.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 毛玻璃風格的輸入框
class GlassmorphicTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final bool isDense;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  const GlassmorphicTextField({
    super.key,
    this.controller,
    this.hintText,
    this.isDense = false,
    this.onSubmitted,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: TextField(
            controller: controller,
            style: AppTypography.bodyMedium.copyWith(color: Colors.white),
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: Colors.white.withOpacity(0.5),
              ),
              isDense: isDense,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: isDense ? 12 : 14,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}
```

**Step 2: 驗證編譯**

Run: `flutter analyze lib/shared/widgets/glassmorphic_text_field.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/shared/widgets/glassmorphic_text_field.dart
git commit -m "feat(ui): 新增 GlassmorphicTextField 毛玻璃輸入框"
```

---

## Task 8: 匯出所有新元件

**Files:**
- Create: `lib/shared/widgets/warm_theme_widgets.dart`

**Step 1: 建立統一匯出檔案**

```dart
// lib/shared/widgets/warm_theme_widgets.dart
/// Warm Theme UI 元件統一匯出
library warm_theme_widgets;

export 'gradient_background.dart';
export 'glassmorphic_container.dart';
export 'glassmorphic_segmented_button.dart';
export 'glassmorphic_text_field.dart';
export 'gradient_button.dart';
export 'bubble_avatar.dart';
```

**Step 2: Commit**

```bash
git add lib/shared/widgets/warm_theme_widgets.dart
git commit -m "feat(ui): 新增 warm_theme_widgets 統一匯出"
```

---

## Task 9: 重構 NewConversationScreen - 基礎結構

**Files:**
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`

**Step 1: 更新 imports**

在檔案開頭，替換或新增 import：

```dart
// lib/features/conversation/presentation/screens/new_conversation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/providers/conversation_providers.dart';
import '../../domain/entities/session_context.dart';
```

**Step 2: 修改 Scaffold 包裝 GradientBackground**

找到 `build` method 中的 `return Scaffold(`，改成：

```dart
  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('新增對話', style: AppTypography.titleLarge),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
        body: SingleChildScrollView(
          // ... 保持原本的 body 內容
```

並在最後加上額外的閉合括號 `)`。

**Step 3: 驗證編譯**

Run: `flutter analyze lib/features/conversation/presentation/screens/new_conversation_screen.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/features/conversation/presentation/screens/new_conversation_screen.dart
git commit -m "refactor(ui): NewConversationScreen 套用 GradientBackground"
```

---

## Task 10: 重構 NewConversationScreen - 輸入框

**Files:**
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`

**Step 1: 替換暱稱輸入框**

找到：
```dart
TextField(
  controller: _nameController,
  decoration: const InputDecoration(
    hintText: '例如：小美',
  ),
),
```

替換成：
```dart
GlassmorphicTextField(
  controller: _nameController,
  hintText: '例如：小美',
),
```

**Step 2: 替換個人化設定的輸入框**

找到興趣輸入框和對方特質輸入框，替換成 GlassmorphicTextField：

```dart
// 興趣輸入框
GlassmorphicTextField(
  controller: _userInterestsController,
  hintText: '例如：咖啡、攝影、露營',
  isDense: true,
),

// 對方特質輸入框
GlassmorphicTextField(
  controller: _targetDescriptionController,
  hintText: '例如：慢熱、喜歡旅行',
  isDense: true,
),
```

**Step 3: Commit**

```bash
git add lib/features/conversation/presentation/screens/new_conversation_screen.dart
git commit -m "refactor(ui): NewConversationScreen 輸入框改用 GlassmorphicTextField"
```

---

## Task 11: 重構 NewConversationScreen - SegmentedButtons

**Files:**
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`

**Step 1: 替換認識場景 SegmentedButton**

找到：
```dart
SegmentedButton<MeetingContext>(
  segments: const [
    ButtonSegment(
        value: MeetingContext.datingApp, label: Text('交友軟體')),
    ...
  ],
  ...
),
```

替換成：
```dart
GlassmorphicSegmentedButton<MeetingContext>(
  segments: const [
    GlassSegment(value: MeetingContext.datingApp, label: '交友軟體'),
    GlassSegment(value: MeetingContext.inPerson, label: '現實搭訕'),
    GlassSegment(value: MeetingContext.friendIntro, label: '朋友介紹'),
  ],
  selected: _meetingContext,
  onChanged: (v) => setState(() => _meetingContext = v),
),
```

**Step 2: 替換認識多久 SegmentedButton**

```dart
GlassmorphicSegmentedButton<AcquaintanceDuration>(
  segments: const [
    GlassSegment(value: AcquaintanceDuration.justMet, label: '剛認識'),
    GlassSegment(value: AcquaintanceDuration.fewDays, label: '幾天'),
    GlassSegment(value: AcquaintanceDuration.fewWeeks, label: '幾週'),
    GlassSegment(value: AcquaintanceDuration.monthPlus, label: '一個月+'),
  ],
  selected: _duration,
  onChanged: (v) => setState(() => _duration = v),
),
```

**Step 3: 替換目標 SegmentedButton**

```dart
GlassmorphicSegmentedButton<UserGoal>(
  segments: const [
    GlassSegment(value: UserGoal.dateInvite, label: '約出來'),
    GlassSegment(value: UserGoal.maintainHeat, label: '維持熱度'),
    GlassSegment(value: UserGoal.justChat, label: '隨意聊'),
  ],
  selected: _goal,
  onChanged: (v) => setState(() => _goal = v),
),
```

**Step 4: Commit**

```bash
git add lib/features/conversation/presentation/screens/new_conversation_screen.dart
git commit -m "refactor(ui): NewConversationScreen SegmentedButton 改用毛玻璃風格"
```

---

## Task 12: 重構 NewConversationScreen - 頭像和按鈕

**Files:**
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`

**Step 1: 替換訊息列表中的頭像**

找到 ListTile 中的 CircleAvatar：
```dart
leading: CircleAvatar(
  radius: 14,
  backgroundColor: isFromMe ? AppColors.primary : AppColors.warm,
  child: Text(
    isFromMe ? '我' : '她',
    style: const TextStyle(fontSize: 12, color: Colors.white),
  ),
),
```

替換成：
```dart
leading: BubbleAvatar(
  label: isFromMe ? '我' : '她',
  isMe: isFromMe,
  size: 28,
),
```

**Step 2: 替換輸入區的頭像**

找到「她的訊息」Row 中的 CircleAvatar：
```dart
const CircleAvatar(
  radius: 16,
  backgroundColor: AppColors.warm,
  child: Text('她', style: TextStyle(fontSize: 12, color: Colors.white)),
),
```

替換成：
```dart
const BubbleAvatar(
  label: '她',
  isMe: false,
  size: 32,
),
```

同樣替換「我的訊息」Row 中的頭像：
```dart
const BubbleAvatar(
  label: '我',
  isMe: true,
  size: 32,
),
```

**Step 3: 替換開始分析按鈕**

找到：
```dart
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
```

替換成：
```dart
GradientButton(
  text: '開始分析',
  onPressed: _isLoading ? null : _analyze,
  isLoading: _isLoading,
),
```

**Step 4: Commit**

```bash
git add lib/features/conversation/presentation/screens/new_conversation_screen.dart
git commit -m "refactor(ui): NewConversationScreen 頭像和按鈕改用 Warm Theme"
```

---

## Task 13: 重構 NewConversationScreen - 訊息輸入區毛玻璃化

**Files:**
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`

**Step 1: 替換「她說了什麼」輸入框**

找到：
```dart
Expanded(
  child: TextField(
    controller: _herMessageController,
    decoration: const InputDecoration(
      hintText: '她說了什麼...',
      isDense: true,
    ),
    onSubmitted: (_) => _addHerMessage(),
  ),
),
```

替換成：
```dart
Expanded(
  child: GlassmorphicTextField(
    controller: _herMessageController,
    hintText: '她說了什麼...',
    isDense: true,
    onSubmitted: (_) => _addHerMessage(),
  ),
),
```

**Step 2: 替換「我回了什麼」輸入框**

同樣替換：
```dart
Expanded(
  child: GlassmorphicTextField(
    controller: _myMessageController,
    hintText: '我回了什麼...',
    isDense: true,
    onSubmitted: (_) => _addMyMessage(),
  ),
),
```

**Step 3: 替換提示訊息容器**

找到：
```dart
Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: AppColors.surfaceVariant,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Row(...),
),
```

替換成：
```dart
GlassmorphicContainer(
  padding: const EdgeInsets.all(12),
  borderRadius: 8,
  child: Row(
    children: [
      Icon(Icons.info_outline,
          size: 18, color: Colors.white.withOpacity(0.7)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          '依序輸入對話，最後一則須為「她」的訊息',
          style: AppTypography.caption.copyWith(
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ),
    ],
  ),
),
```

**Step 4: Commit**

```bash
git add lib/features/conversation/presentation/screens/new_conversation_screen.dart
git commit -m "refactor(ui): NewConversationScreen 訊息輸入區毛玻璃化"
```

---

## Task 14: 重構 NewConversationScreen - 訊息列表容器

**Files:**
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`

**Step 1: 替換訊息列表容器**

找到：
```dart
Container(
  constraints: const BoxConstraints(maxHeight: 200),
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: AppColors.divider),
  ),
  child: ListView.builder(...),
),
```

替換成：
```dart
GlassmorphicContainer(
  padding: EdgeInsets.zero,
  borderRadius: 8,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 200),
    child: ListView.builder(
      shrinkWrap: true,
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isFromMe = msg['isFromMe'] as bool;
        return ListTile(
          dense: true,
          leading: BubbleAvatar(
            label: isFromMe ? '我' : '她',
            isMe: isFromMe,
            size: 28,
          ),
          title: Text(
            msg['content'] as String,
            style: AppTypography.bodyMedium,
          ),
          trailing: IconButton(
            icon: Icon(Icons.close, size: 18, color: Colors.white.withOpacity(0.7)),
            onPressed: () => _removeMessage(index),
          ),
        );
      },
    ),
  ),
),
```

**Step 2: Commit**

```bash
git add lib/features/conversation/presentation/screens/new_conversation_screen.dart
git commit -m "refactor(ui): NewConversationScreen 訊息列表容器毛玻璃化"
```

---

## Task 15: Web 測試與最終推送

**Step 1: 本地 Web 測試**

Run: `flutter run -d chrome`

**Step 2: 視覺檢查清單**

- [ ] 漸層背景正常顯示（深紫 → 淡紫）
- [ ] 光球效果可見
- [ ] 輸入框毛玻璃效果正常
- [ ] SegmentedButton 選中狀態有粉紅發光
- [ ] 頭像是漸層泡泡風格
- [ ] 開始分析按鈕是珊瑚漸層膠囊型
- [ ] 所有互動功能正常（輸入、選擇、新增訊息、分析）

**Step 3: 最終推送**

```bash
git push
```

Expected: Vercel 自動部署，可在 https://web-beta-tawny.vercel.app 測試

---

## 驗收標準

- [ ] 新增對話頁視覺效果接近 image_1（90%+）
- [ ] 毛玻璃效果在 Chrome/Safari 正常顯示
- [ ] 所有互動元件功能正常
- [ ] 效能無明顯卡頓
- [ ] Web 版測試通過

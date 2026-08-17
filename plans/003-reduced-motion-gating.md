# 003 — 無限循環動畫補 reduced-motion 閘門

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: HIGH
- **Category**: Accessibility / 電池
- **Estimated scope**: 5 files

## Problem

全 repo 27 個含 AnimationController 的檔案有 24 個已閘門 `disableAnimations`，沒閘的 3 個**全是無限循環**（最不該漏的類別）：

1. `lib/shared/widgets/gradient_background.dart:31-44` — 三個 14s/18s/20s `repeat(reverse: true)` 光球控制器，零閘門、零 TickerMode。掛在 learning／login／article_detail／profile_card 底下。另外 :176-177 的 `BoxShadow(blurRadius: 120–130, spreadRadius: 60–65)` 每幀隨 `Transform.scale` 重新光柵化（效能，見 Steps 4）。
2. `lib/features/splash/presentation/screens/splash_screen.dart` — 5 個控制器全不看 reduced-motion；`:134` `_dotPulseController.repeat(reverse: true)` 無限脈動、`:292` ShaderMask shimmer。reduced-motion 使用者開 app 第一幕就是全套動畫。
3. `lib/features/keyboard/presentation/screens/keyboard_setup_screen.dart:76-81` — 900ms 無限脈動：
   ```dart
   _pulse = AnimationController(
     vsync: this,
     duration: const Duration(milliseconds: 900),
     lowerBound: 0.94,
     upperBound: 1.04,
   )..repeat(reverse: true);
   ```
   使用者跳去 iOS 設定、screen 背景化時照跑。
4. `lib/shared/widgets/dimension_radar_chart.dart:60`、`lib/features/partner/presentation/widgets/partner_radar_summary_card.dart:64` — 兩個 RadarChart 沒設 `swapAnimationDuration`，fl_chart 預設 150ms 補間不受 reduced-motion 控制（report 底下四張圖都有 `disableAnimations ? Duration.zero : ...` 的寫法，這兩張漏了）。

## Target

- 三個無限循環檔：`disableAnimations == true` 時不 `repeat()`，controller 停在靜態端值（光球 `value = 0.5` 置中、脈動 `value = 1.0`、splash 各控制器直接 `value = 1`＝終幕靜置）。監聽變化用 `didChangeDependencies`（in-app 切換也要生效）。
- keyboard `_pulse` 加 `TickerMode` 相容：`ScaleTransition` 本身受 TickerMode 管，只需補 reduced-motion。
- 兩張雷達圖：`swapAnimationDuration: disableAnimations ? Duration.zero : const Duration(milliseconds: 150)`。

## Repo conventions to follow

模仿 `lib/features/analysis/presentation/widgets/analysis_action_widgets.dart:110-124` 的成熟寫法：

```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  if (_reduceMotion == reduceMotion) return;
  _reduceMotion = reduceMotion;
  if (reduceMotion) {
    _controller..stop()..value = 1;
  } else if (...) {
    _controller.repeat(reverse: true);
  }
}
```

閘門語意採 repo 現行「停在靜態端點」慣例（不是降幅）。

## Steps

1. `gradient_background.dart`：`repeat` 移出 initState 到 `didChangeDependencies` 閘門後；reduced-motion 時三顆 controller `..stop()..value = 0.5`。
2. `splash_screen.dart`：`_startAnimationSequence()` 開頭讀 `disableAnimations`；true 時把 5 個 controller `value = 1`、不 repeat、直接照原 delay 總長（或縮短到 800ms）呼叫 `widget.onComplete()`——splash 停留時間不因 reduced-motion 變長。
3. `keyboard_setup_screen.dart`：`repeat` 移到閘門後，reduced-motion 時 `value = 1.0`。
4. `gradient_background.dart` 效能減負（同檔順手）：三顆光球的 `blurRadius` 120–130 降到 ≤60、`spreadRadius` 減半——視覺柔光保留、光柵化面積減半。若視覺差異可辨識且變差，回報並保留原值（此步可獨立放棄）。
5. 兩張雷達圖補 `swapAnimationDuration` 三元。

## Boundaries

- 不動 `liquid_motion_frame.dart`／`one_shot_*`（已是模範實作）。
- 不改 splash 的動畫序列結構與品牌視覺，只加閘門。
- 不加新依賴。

## Verification

- **Mechanical**: `flutter analyze`；`flutter test`。
- **Feel check**：
  - iOS「減少動態效果」開啟：splash 直接呈現終幕靜態畫面後進 app；login/learning 背景光球靜止但漸層仍在；鍵盤設定頁地球不脈動。
  - 關閉 reduce motion：一切如舊。
  - performance overlay：learning 頁 GPU 時間比改前降（blur 減負生效）。
- **Done when**: `grep -L "disableAnimations" $(grep -rl "repeat(" lib/ --include="*.dart")` 為空（所有 repeat 檔案都有閘門）。

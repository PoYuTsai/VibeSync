# 007 — /paywall 改由下而上 modal 轉場

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: MEDIUM
- **Category**: Purpose（語意正確的轉場方向）
- **Estimated scope**: 1 file（routes.dart）

## Problem

`lib/app/routes.dart:178-181` — `/paywall` 是 plain `builder:`，十幾個入口（`home_quota_strip.dart:79`、`analysis_screen.dart:321`、`my_report_screen.dart:233` 等）全部得到「橫滑進下一頁」的語意。報價彈出應該是「一個 surface 浮上來」，不是「你導航去了別處」。

```dart
// routes.dart:178-181 — current
GoRoute(
  path: '/paywall',
  builder: (context, state) => const PaywallScreen(),
```

## Target

```dart
GoRoute(
  path: '/paywall',
  pageBuilder: (context, state) => CustomTransitionPage<void>(
    key: state.pageKey,
    fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    child: const PaywallScreen(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.easeOut,          // Cubic(0.23,1,0.32,1)
        reverseCurve: Curves.easeIn.flipped, // 退場等效 easeOut
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  ),
),
```

小幅上滑（8% 高度）＋淡入，不是全高 cover sheet——paywall 內已有自己的關閉鈕與滿版排版，全高滑入 320ms 會太重；輕浮現即可傳達 modal 語意。

## Repo conventions to follow

- import `CustomTransitionPage` 來自 go_router（已依賴）。
- curve 用 `AppMotion.easeOut` token（routes.dart 需 import `../core/theme/app_motion.dart`）。

## Steps

1. routes.dart：上述替換，加 import。

## Boundaries

- 不動 PaywallScreen 本身、不動任何入口呼叫點（`context.push('/paywall')` 全部原樣受益）。
- 其他 route 不改。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test`。
- **Feel check**：從首頁 quota 條、分析頁、報表頁三個入口開 paywall——皆為上浮淡入；back/關閉為下沉淡出且比進場快（240 vs 320ms）；無橫滑。
- **Done when**: 上述成立。

// test/helpers/motion_free_app.dart
//
// 給「會渲染持續動畫元件」的畫面測試用的 MaterialApp。
//
// 為什麼需要這個：`pumpAndSettle` 會一直 pump 到沒有排程中的 frame 為止。
// 只要畫面上有一個持續跑的 Ticker（例如對象頁 Hero 的 HeatOrb 呼吸光球、
// LiquidMotionFrame 的流光外框），pumpAndSettle 就永遠等不到收斂，最後以
// timeout 失敗。
//
// 解法沿用專案既有慣例：把 reduce motion 打開，讓那些元件停在自己的靜止幀
// （見 liquid_motion_frame_test.dart、trend_flow_overlay_test.dart）。斷言看
// 的是終態，而 pumpAndSettle 本來就是把畫面帶到終態——語意等價。
//
// 注意 `builder:` 而不是把 MediaQuery 包在外面：MaterialApp 自己會用
// MediaQuery.fromView 建一個新的 MediaQuery，包在外層會被蓋掉，必須注入到
// MaterialApp 底下。
//
// 需要驗證動畫「跑動過程」的測試不要用這個，改用明確的 pump(duration)。
import 'package:flutter/material.dart';

/// 一個把 reduce motion 打開的 [MaterialApp]。
MaterialApp motionFreeApp({required Widget home}) {
  return MaterialApp(builder: _motionFreeBuilder, home: home);
}

/// 同上，給用 go_router 的測試。
MaterialApp motionFreeRouterApp({required RouterConfig<Object> routerConfig}) {
  return MaterialApp.router(
    routerConfig: routerConfig,
    builder: _motionFreeBuilder,
  );
}

Widget _motionFreeBuilder(BuildContext context, Widget? child) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child ?? const SizedBox.shrink(),
  );
}

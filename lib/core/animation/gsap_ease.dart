// lib/core/animation/gsap_ease.dart
//
// GSAP 緩動曲線的 Dart 移植。
//
// 來源：greensock/GSAP v3.15.0，`src/gsap-core.js` 的 `_insertEase`／
// `_configBack`／`_configElastic` 區塊，以及 Bounce 的 IIFE。
//
// 為什麼是「移植」不是「引入」：GSAP 是 JavaScript 函式庫，動的是 DOM 節點與
// CSS 屬性，沒辦法在 Flutter 的 Dart runtime 執行。但 GSAP 真正被打磨過的東西
// 是那組緩動數學——純函數、無副作用、跟 DOM 無關，可以一比一搬成 Flutter
// [Curve]，動的照樣是原生 widget，不必扛 WebView。
//
// 保真度由 test/unit/core/animation/gsap_ease_test.dart 鎖住：期望值是直接跑
// 真的 GSAP（node + `esm/all.js`，`gsap.parseEase()`）取樣出來的，容差 1e-9。
// 改動這個檔＝必須重跑那組取樣，不得憑手感調參數。
//
// GreenSock standard "no charge" license: https://gsap.com/standard-license
// Copyright (c) 2008-2026, GreenSock. All rights reserved.
import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// GSAP `powerN.out`：`1 - (1 - p)^exponent`。
///
/// GSAP 的命名有一格位移——`power1` 是二次式、`power2` 是三次式，依此類推
/// （`gsap-core.js` 裡 `Quad` 對到 `Power1`）。所以這裡收的是**指數**，
/// 對照請走 [GsapEase] 的具名常數，不要自己數。
class GsapPowerOut extends Curve {
  const GsapPowerOut(this.exponent) : assert(exponent >= 1);

  final int exponent;

  @override
  double transformInternal(double t) => 1 - math.pow(1 - t, exponent).toDouble();
}

/// GSAP `powerN.in`：`p^exponent`。
class GsapPowerIn extends Curve {
  const GsapPowerIn(this.exponent) : assert(exponent >= 1);

  final int exponent;

  @override
  double transformInternal(double t) => math.pow(t, exponent).toDouble();
}

/// GSAP `powerN.inOut`。
class GsapPowerInOut extends Curve {
  const GsapPowerInOut(this.exponent) : assert(exponent >= 1);

  final int exponent;

  @override
  double transformInternal(double t) => t < 0.5
      ? math.pow(t * 2, exponent).toDouble() / 2
      : 1 - math.pow((1 - t) * 2, exponent).toDouble() / 2;
}

/// GSAP `back.out(overshoot)`——會衝過終點再彈回來，值域超出 0–1。
class GsapBackOut extends Curve {
  const GsapBackOut([this.overshoot = 1.70158]);

  final double overshoot;

  @override
  double transformInternal(double t) {
    final p = t - 1;
    return p * p * ((overshoot + 1) * p + overshoot) + 1;
  }
}

/// GSAP `elastic.out(amplitude, period)`——阻尼正弦，值域超出 0–1。
class GsapElasticOut extends Curve {
  const GsapElasticOut({this.amplitude = 1, this.period = 0.3})
      : assert(amplitude > 0),
        assert(period > 0);

  final double amplitude;
  final double period;

  @override
  double transformInternal(double t) {
    // 對齊 `_configElastic('out', ...)`：注意 GSAP 先用「原始 p2」算出相位
    // 偏移 p3，之後才把 p2 覆寫成 2π/p2 拿去乘。順序反了曲線就不一樣。
    final p1 = amplitude >= 1 ? amplitude : 1.0;
    final basePeriod = period / (amplitude < 1 ? amplitude : 1.0);
    final ratio = 1 / p1;
    // JS 的 `Math.asin(1 / p1) || 0`：定義域外吐 NaN，GSAP 當 0 用。
    final phase = ratio.abs() > 1 ? 0.0 : math.asin(ratio);
    final p3 = basePeriod / (2 * math.pi) * phase;
    final p2 = 2 * math.pi / basePeriod;
    return p1 * math.pow(2, -10 * t).toDouble() * math.sin((t - p3) * p2) + 1;
  }
}

class _GsapExpoOut extends Curve {
  const _GsapExpoOut();

  // GSAP 只定義 Expo 的 easeIn，out = 1 - easeIn(1 - p)（`_insertEase` 預設）。
  // easeIn 是混合式：純 2^(10(p-1)) 收不到 1，GSAP 補了一段 p^6 讓終點落準。
  static double _easeIn(double p) =>
      math.pow(2, 10 * (p - 1)).toDouble() * p +
      math.pow(p, 6).toDouble() * (1 - p);

  @override
  double transformInternal(double t) => 1 - _easeIn(1 - t);
}

class _GsapCircOut extends Curve {
  const _GsapCircOut();

  @override
  double transformInternal(double t) {
    final p = 1 - t;
    return math.sqrt(1 - p * p);
  }
}

class _GsapSineOut extends Curve {
  const _GsapSineOut();

  @override
  double transformInternal(double t) => math.cos((1 - t) * math.pi / 2);
}

class _GsapBounceOut extends Curve {
  const _GsapBounceOut();

  // `((n, c) => …)(7.5625, 2.75)` 的四段拋物線。
  static const double _n = 7.5625;
  static const double _c = 2.75;

  @override
  double transformInternal(double t) {
    const n1 = 1 / _c;
    const n2 = 2 / _c;
    const n3 = 2.5 / _c;
    if (t < n1) return _n * t * t;
    if (t < n2) {
      final p = t - 1.5 / _c;
      return _n * p * p + 0.75;
    }
    if (t < n3) {
      final p = t - 2.25 / _c;
      return _n * p * p + 0.9375;
    }
    final p = t - 2.625 / _c;
    return _n * p * p + 0.984375;
  }
}

/// GSAP 常用緩動的具名入口。名稱刻意跟 GSAP 字串一致（`power2.out` →
/// [power2Out]），方便跟 GSAP 文件／範例對照。
abstract final class GsapEase {
  /// `power1.out`（＝`quad.out`，GSAP 的預設 ease）。
  static const Curve power1Out = GsapPowerOut(2);

  /// `power2.out`（＝`cubic.out`）。數字揭曉、內容進場的萬用檔。
  static const Curve power2Out = GsapPowerOut(3);

  /// `power3.out`（＝`quart.out`）。
  static const Curve power3Out = GsapPowerOut(4);

  /// `power4.out`（＝`quint.out`）。前段極快、尾段長收。
  static const Curve power4Out = GsapPowerOut(5);

  /// `power2.in`。
  static const Curve power2In = GsapPowerIn(3);

  /// `power2.inOut`。
  static const Curve power2InOut = GsapPowerInOut(3);

  /// `expo.out`。
  static const Curve expoOut = _GsapExpoOut();

  /// `circ.out`。
  static const Curve circOut = _GsapCircOut();

  /// `sine.out`。
  static const Curve sineOut = _GsapSineOut();

  /// `back.out(1.7)`——GSAP 預設 overshoot 是 1.70158。
  static const Curve backOut = GsapBackOut();

  /// `elastic.out(1, 0.3)`。
  static const Curve elasticOut = GsapElasticOut();

  /// `bounce.out`。
  static const Curve bounceOut = _GsapBounceOut();
}

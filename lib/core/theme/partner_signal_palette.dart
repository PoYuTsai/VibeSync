import 'package:flutter/painting.dart';

/// 首頁對象卡燈號標籤（日本橫式 LED 三燈信號機＋同色霓虹字）的色票。
///
/// Bruce 2026-10-21 燈號標籤規格、Eric 同日拍板：只用在首頁對象卡第二行，全域燈號色
/// （`guideV3LightColor`）與報告頁等其他燈號不變。DESIGN.md §11 的棘輪只豁免
/// `lib/core/theme/` 裡的 `Color(0x…)`，所以顏色集中在這裡；登記見 DESIGN.md §7。
abstract final class PartnerSignalPalette {
  // ── 亮燈與文字主色（深紫卡片上的對比：11.8／11.7／5.9，都過 4.5:1）──
  static const Color green = Color(0xFF53F5CF);
  static const Color yellow = Color(0xFFFFD85A);
  static const Color red = Color(0xFFFF6B7A);

  /// 亮燈中心偏白的 LED 芯。
  static const Color ledCore = Color(0xFFFFFBEF);

  // ── 金屬外殼（gunmetal）──
  static const Color housingTop = Color(0xFF545A63);
  static const Color housingBottom = Color(0xFF25282E);
  static const Color housingEdge = Color(0xFF111316);
  static const Color housingHighlight = Color(0xFF9299A3);
  static const Color rivet = Color(0xFFA3AAB4);

  // ── 遮陽罩（庇）──
  static const Color hoodHighlight = Color(0xFFC4CBD4);
  static const Color hoodInner = Color(0xFF0B0C0F);
  static const Color hoodSide = Color(0xFF3A3F47);

  // ── 鏡片 ──
  static const Color lensCenter = Color(0xFF16181C);
  static const Color lensDark = Color(0xFF08090B);
  static const Color lensRim = Color(0xFF1B1E23);

  /// 沒亮的鏡片：極弱、低飽和的點陣格紋。
  static const Color unlitGrid = Color(0xFF2A2E35);

  /// 沒亮的鏡片左上角一道很淡的反光。
  static const Color lensGlint = Color(0x29FFFFFF);
}

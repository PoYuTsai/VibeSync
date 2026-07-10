// 溫度計呈現的單一真相：band → 色票。
// band 真相源在 server（supabase/functions/practice-chat/temperature.ts 的
// temperatureBandFor）：<=20 frozen / <=40 cold / <=60 neutral / <=80 warm / else hot。
// client 只在 band 缺席（舊快照、Hive 還原、欄位缺失）時用 score 鏡像同一張表兜底，
// 絕不自建分歧邊界。
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 鏡像 server `temperatureBandFor(score)` 的查表（含 clamp 0-100）。
/// 只做 band 缺席時的兜底；band 有值時一律以 server 回傳為準。
String practiceTemperatureBandForScore(int score) {
  final clamped = score.clamp(0, 100);
  if (clamped <= 20) return 'frozen';
  if (clamped <= 40) return 'cold';
  if (clamped <= 60) return 'neutral';
  if (clamped <= 80) return 'warm';
  return 'hot';
}

/// 溫度計顏色：優先吃 server 回的 [band]；缺席或未知值退回
/// [practiceTemperatureBandForScore] 鏡像查表。
Color practiceTemperatureColor({required int score, String? band}) {
  final resolved = switch (band) {
    'frozen' || 'cold' || 'neutral' || 'warm' || 'hot' => band!,
    _ => practiceTemperatureBandForScore(score),
  };
  return switch (resolved) {
    'frozen' => AppColors.frozen,
    'cold' => AppColors.cold,
    'neutral' => AppColors.warning,
    'warm' => AppColors.warm,
    _ => AppColors.hot,
  };
}

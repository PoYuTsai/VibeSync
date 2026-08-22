// 防回歸：AnalysisScreen 的 debug-only telemetry 面板接線守門。
//
// 背景：Work C C3a 的自動化改寫曾因錨點誤抓（`if (_showTelemetryDiagnostics
// &&` 在攝入區 debug 盒、OCR 面板、分析面板三處都出現）把「上次 OCR 量測」
// 面板整塊蓋掉。這些面板只在 kDebugMode＋量測資料存在時渲染，一般 widget
// 測試從外部灌不進 `_lastRecognizeTelemetry`，特徵化測試蓋不到，因此改用
// source guard 鎖接線：三個 debug 診斷表面必須各自存在且掛在正確的 gate 上。
// 若刻意移除其中一個面板，請連同本守門一起更新並在 commit 訊息說明。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screenPath =
    'lib/features/analysis/presentation/screens/analysis_screen.dart';

void main() {
  // 摺疊空白後比對，避免因排版變動假紅。
  final source = File(_screenPath)
      .readAsStringSync()
      .replaceAll(RegExp(r'\s+'), ' ');

  test('OCR 量測面板存在且掛在 diagnostics＋有 OCR 量測＋非辨識中 gate', () {
    expect(
      source.contains(
        'if (_showTelemetryDiagnostics && '
        '_lastRecognizeTelemetry != null && '
        '!_isRecognizing) ...[ OcrTelemetryPanel(',
      ),
      isTrue,
      reason: '「上次 OCR 量測」debug 面板被移除或 gate 被改動',
    );
  });

  test('分析量測面板存在且掛在 diagnostics＋有分析量測＋非分析中 gate', () {
    expect(
      source.contains(
        'if (_showTelemetryDiagnostics && '
        '_lastAnalysisTelemetry != null && '
        '!_isAnalyzing) ...[ AnalysisTelemetryPanel(',
      ),
      isTrue,
      reason: '「上次分析量測」debug 面板被移除或 gate 被改動',
    );
  });

  test('選圖區辨識中診斷盒接線存在（diagnostics＋辨識中）', () {
    expect(
      source.contains(
        'showRecognizeDiagnostics: _showTelemetryDiagnostics && _isRecognizing',
      ),
      isTrue,
      reason: '攝入區辨識中 debug 診斷盒的接線被移除或 gate 被改動',
    );
  });
}

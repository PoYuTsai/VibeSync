import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/image_picker_widget.dart';
import '../../domain/entities/analysis_telemetry.dart';
import 'telemetry_diagnostics_section.dart';

/// 選圖／辨識區的動作介面：選圖狀態、辨識 API 與取消都由 screen 實作。
abstract interface class ScreenshotIntakeActions {
  void selectedImagesChanged(List<Uint8List> images);
  void selectedImageMetricsChanged(List<SelectedImageMetrics> metrics);
  void recognizeScreenshots();
  void cancelRecognition();
}

/// 選圖／辨識區：選圖列、截圖小提醒、「辨識截圖文字」CTA、辨識中
/// debug 診斷盒與價值主張。在空片段常駐；片段確認後收掉，但「重新選圖」
/// 把新批塞進選圖狀態時要重新展開。
class ScreenshotIntakeSection extends StatelessWidget {
  const ScreenshotIntakeSection({
    super.key,
    required this.isEmptyFragmentSetup,
    required this.selectedImages,
    required this.isRecognizing,
    required this.recognizeButtonLabel,
    required this.showRecognizeDiagnostics,
    required this.recognizeStageLabel,
    required this.recognizeElapsedSeconds,
    required this.totalOriginalImageBytes,
    required this.totalCompressedImageBytes,
    required this.lastRecognizeTelemetry,
    required this.actions,
  });

  final bool isEmptyFragmentSetup;
  final List<Uint8List> selectedImages;
  final bool isRecognizing;

  /// 「辨識並取代本次內容（N 張）」／「辨識截圖文字（N 張）」／辨識階段
  /// 標籤——由 screen 依對話狀態算好傳入。
  final String recognizeButtonLabel;

  /// debug 診斷盒（kDebugMode 且辨識中）。
  final bool showRecognizeDiagnostics;
  final String recognizeStageLabel;
  final int recognizeElapsedSeconds;
  final int totalOriginalImageBytes;
  final int totalCompressedImageBytes;
  final AnalysisTelemetry? lastRecognizeTelemetry;
  final ScreenshotIntakeActions actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          isEmptyFragmentSetup ? EdgeInsets.zero : const EdgeInsets.all(24),
      decoration: isEmptyFragmentSetup
          ? null
          : BoxDecoration(
              color: AppColors.ctaStart.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.ctaStart.withValues(alpha: 0.2)),
            ),
      child: Column(
        crossAxisAlignment: isEmptyFragmentSetup
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.center,
        children: [
          if (isEmptyFragmentSetup) ...[
            Divider(
              height: 1,
              color: Colors.white.withValues(alpha: 0.10),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  '聊天截圖',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${selectedImages.length}/3',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // 「本次片段已有 N 則…整批取代」提示已拆（2026-08-16 Bruce 回饋）；
          // 取代規則由辨識確認對話框揭露，這裡只留選圖入口——辨識預覽卡的
          // 「重新讀圖」只能重讀同一批，換截圖仍必須走這裡。
          ImagePickerWidget(
            maxImages: 3,
            externalImages: selectedImages, // 同步外部狀態
            helperTextColor: AppColors.onBackgroundSecondary,
            // 教學文字全拆：空片段由「截圖小提醒」承擔，
            // 已有片段不再重複教學（2026-08-16 Bruce 回饋）
            showHelperText: false,
            tileSize: isEmptyFragmentSetup ? 104 : 70,
            onImagesChanged: actions.selectedImagesChanged,
            onMetricsChanged: actions.selectedImageMetricsChanged,
          ),
          // 選圖後小提醒功成身退，讓「辨識截圖文字」直接頂上來，一頁內
          // 看得到 CTA（2026-08-14 Eric 真機回報要往下滑才找得到按鈕）。
          if (isEmptyFragmentSetup && selectedImages.isEmpty) ...[
            const SizedBox(height: 22),
            Text(
              '截圖小提醒',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const _ScreenshotTipRow(
              icon: Icons.crop_free_rounded,
              text: '請保留標題列、訊息泡泡與前後文',
            ),
            const SizedBox(height: 8),
            const _ScreenshotTipRow(
              icon: Icons.text_fields_rounded,
              text: '每張建議 15 則內；過長可拆成 2-3 張',
            ),
          ],
          // 「這次分析設定」已拆（2026-08-14 Eric 拍板：對象卡建立時已引導
          // 填過，這裡重複）。
          const SizedBox(height: 8),

          // 如果有截圖，先顯示「辨識截圖文字」按鈕
          if (selectedImages.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: AppHaptics.onPress(
                    isRecognizing ? null : actions.recognizeScreenshots),
                icon: isRecognizing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_photo_alternate),
                label: Text(recognizeButtonLabel),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.ctaStart,
                  foregroundColor: AppColors.onCta,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.7),
                  disabledForegroundColor:
                      Colors.white.withValues(alpha: 0.95),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Debug 狀態顯示
            if (showRecognizeDiagnostics) _recognizeDiagnosticsBox(),
            if (!isRecognizing)
              Text(
                '截圖會先辨識成對話文字。請確認我說／她說與內容；確認後會成為本次完整片段。',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.warning,
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 12),
          ],
          // 價值主張只留首次上傳的空片段；已有片段時不再重複
          // （2026-08-16 Bruce 回饋）。
          if (isEmptyFragmentSetup) ...[
            const SizedBox(height: 16),
            Text(
              // 縮短到一行放得下（2026-08-14 Eric 真機回報換行）
              'AI 會分析對方投入度、讀懂語意，教你最適合的回覆方式',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _recognizeDiagnosticsBox() {
    final telemetry = lastRecognizeTelemetry;
    TextStyle orangeCaption({String? fontFamily}) =>
        AppTypography.caption.copyWith(
          color: Colors.orange.withValues(alpha: 0.8),
          fontFamily: fontFamily,
          fontSize: 12,
        );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            '目前階段：$recognizeStageLabel ($recognizeElapsedSeconds 秒)',
            style: AppTypography.bodySmall.copyWith(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '圖片：${selectedImages.length} 張｜原始 ${formatTelemetryBytes(totalOriginalImageBytes)} -> 壓縮 ${formatTelemetryBytes(totalCompressedImageBytes)}',
            style: orangeCaption(fontFamily: 'monospace'),
          ),
          if (telemetry != null)
            Text(
              telemetry.cacheHit
                  ? '本次直接使用本機快取結果，未重新送出 OCR 請求'
                  : '請求 ${formatTelemetryBytes(telemetry.requestBodyBytes)}｜本機準備 ${formatTelemetryDuration(telemetry.payloadPreparationDuration)}｜往返 ${formatTelemetryDuration(telemetry.roundTripDuration)}',
              style: orangeCaption(),
            ),
          if (telemetry != null)
            Text(
              telemetry.cacheHit
                  ? '本次使用本機快取，未重新上傳或呼叫 AI'
                  : 'AI ${formatTelemetryDuration(telemetry.edgeAiDuration)}｜估計傳輸/排隊 ${formatTelemetryDuration(telemetry.estimatedTransferDuration)}',
              style: orangeCaption(),
            ),
          if (telemetry != null &&
              recognizeTelemetryRecognitionSummary(telemetry) != null)
            Text(
              recognizeTelemetryRecognitionSummary(telemetry)!,
              style: orangeCaption(),
            ),
          if (telemetry != null &&
              recognizeTelemetryNormalizationSummary(telemetry) != null)
            Text(
              recognizeTelemetryNormalizationSummary(telemetry)!,
              style: orangeCaption(),
            ),
          Text(
            '若超過 130 秒仍無結果，建議換更少訊息的截圖再試。',
            style: orangeCaption(),
          ),
          TextButton(
            onPressed: actions.cancelRecognition,
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

/// 空白新片段的「截圖小提醒」列（對標示意稿）：橘 icon＋純文字，
/// 不加卡片框（2026-08-14 Eric 拍板拆淺色框）。
class _ScreenshotTipRow extends StatelessWidget {
  const _ScreenshotTipRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.ctaStart),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundPrimary.withValues(alpha: 0.92),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

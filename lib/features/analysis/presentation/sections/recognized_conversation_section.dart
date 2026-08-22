import 'package:flutter/material.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/services/screenshot_recognition_helper.dart';

/// 辨識結果卡的動作介面：重讀/重選/續確認/清草稿都是副作用
/// （API 呼叫、相簿、對話框、狀態變更），由 screen 實作。
abstract interface class RecognitionDraftActions {
  void forceReRecognizeLastBatch();
  void repickScreenshots();
  void resumeRecognitionImport();
  void discardRecognitionDraft();
}

/// 截圖識別結果卡片：狀態 chips、引導說明、警告、快取/重選動作列與
/// 暫存草稿的續確認列。
///
/// 標籤與引導文案經 ScreenshotRecognitionHelper（domain 純函式）推導；
/// 卡片本身不觸碰 provider 或網路。
class RecognizedConversationCard extends StatelessWidget {
  const RecognizedConversationCard({
    super.key,
    required this.recognized,
    required this.warningMessage,
    required this.fromCache,
    required this.canForceReRecognize,
    required this.hasPendingImport,
    required this.isRecognizing,
    required this.actions,
  });

  final RecognizedConversation recognized;

  /// screen 端算好的覆蓋警告（與 partner 名稱對拍等）；null 用辨識自帶警告。
  final String? warningMessage;
  final bool fromCache;
  final bool canForceReRecognize;
  final bool hasPendingImport;
  final bool isRecognizing;
  final RecognitionDraftActions actions;

  Color _confidenceColor(RecognizedConversation value) {
    if (value.importPolicy == 'reject') {
      return AppColors.error;
    }
    switch (value.confidence) {
      case 'low':
        return AppColors.warning;
      case 'medium':
        return AppColors.info;
      case 'high':
      default:
        return AppColors.success;
    }
  }

  Color _guidanceColor(RecognizedConversation value) {
    switch (ScreenshotRecognitionHelper.guidance(value).tone) {
      case ScreenshotRecognitionGuidanceTone.reject:
        return AppColors.error;
      case ScreenshotRecognitionGuidanceTone.caution:
        return AppColors.warning;
      case ScreenshotRecognitionGuidanceTone.review:
        return AppColors.info;
      case ScreenshotRecognitionGuidanceTone.stable:
        return AppColors.success;
    }
  }

  IconData _guidanceIcon(RecognizedConversation value) {
    switch (ScreenshotRecognitionHelper.guidance(value).tone) {
      case ScreenshotRecognitionGuidanceTone.reject:
        return Icons.block_rounded;
      case ScreenshotRecognitionGuidanceTone.caution:
        return Icons.call_split_rounded;
      case ScreenshotRecognitionGuidanceTone.review:
        return Icons.fact_check_rounded;
      case ScreenshotRecognitionGuidanceTone.stable:
        return Icons.check_circle_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayWarning = warningMessage ?? recognized.warning;
    final displayRecognized = recognized.copyWith(warning: displayWarning);
    final guidance = ScreenshotRecognitionHelper.guidance(displayRecognized);
    final guidanceColor = _guidanceColor(displayRecognized);
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_library,
                  size: 20, color: AppColors.ctaStart),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ScreenshotRecognitionHelper.recognitionPreviewTitle(
                    recognized,
                  ),
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RecognitionStatusChip(
                icon: Icons.chat_bubble_outline,
                label: ScreenshotRecognitionHelper.classificationLabel(
                  displayRecognized.classification,
                ),
                color: displayRecognized.importPolicy == 'reject'
                    ? AppColors.error
                    : AppColors.ctaStart,
              ),
              _RecognitionStatusChip(
                icon: Icons.auto_awesome,
                label: ScreenshotRecognitionHelper.confidenceLabel(
                  displayRecognized.confidence,
                ),
                color: _confidenceColor(displayRecognized),
              ),
              _RecognitionStatusChip(
                icon: Icons.compare_arrows_rounded,
                label: ScreenshotRecognitionHelper.sideConfidenceLabel(
                  displayRecognized.sideConfidence,
                ),
                color: _confidenceColor(
                  displayRecognized.copyWith(
                    confidence: displayRecognized.sideConfidence,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: guidanceColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: guidanceColor.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _guidanceIcon(displayRecognized),
                  size: 18,
                  color: guidanceColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guidance.title,
                        style: AppTypography.bodySmall.copyWith(
                          color: guidanceColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ScreenshotRecognitionHelper.actionGuidance(
                          displayRecognized,
                        ),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.onBackgroundPrimary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (displayWarning != null && displayWarning.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  displayWarning,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          // 「查看辨識內容」摺疊清單已拆（2026-08-16 Bruce 回饋：內容與上方
          // 主卡的訊息泡泡重複）。
          if (fromCache && canForceReRecognize) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cached_rounded,
                    size: 18,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '這是上次相同截圖的快取結果',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: actions.forceReRecognizeLastBatch,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('強制重新辨識'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '如果結果有誤，點「強制重新辨識」會忽略快取，重新辨識。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.unselectedText,
                height: 1.4,
              ),
            ),
          ] else ...[
            // 「重新讀圖」改「重新選圖」（2026-08-16 Bruce 回饋）：重讀同一批
            // 錯照舊，直接開相簿換截圖才解得了「選錯圖」；確認後整批取代。
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('recognized-repick'),
                onPressed: isRecognizing ? null : actions.repickScreenshots,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('重新選圖'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '選錯截圖或漏拉訊息？重新選 1–3 張，確認後會整批取代這次內容。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.unselectedText,
                height: 1.4,
              ),
            ),
          ],
          if (hasPendingImport) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        AppHaptics.onPress(actions.resumeRecognitionImport),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('繼續確認本次內容'),
                  ),
                ),
                const SizedBox(width: 8),
                if (canForceReRecognize)
                  TextButton(
                    onPressed: actions.forceReRecognizeLastBatch,
                    child: const Text('重讀這批圖'),
                  ),
                if (canForceReRecognize) const SizedBox(width: 4),
                TextButton(
                  onPressed: actions.discardRecognitionDraft,
                  child: const Text('清除草稿'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '剛剛的辨識結果已暫存在這裡，不用重新辨識。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.unselectedText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecognitionStatusChip extends StatelessWidget {
  const _RecognitionStatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

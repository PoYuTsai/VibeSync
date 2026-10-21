import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../core/services/app_haptics.dart';

/// 規格 PR-10「看看教練會讀到什麼」：原文顯示問教練 1:1 時會跟問題一起送給 AI
/// 的那段「關於我」，畫面上看到的就是實際送出的內容。
Future<void> showCoachContextPreviewSheet(
  BuildContext context, {
  required String coachContext,
  required bool hasUnsavedChanges,
}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.brandSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '教練會讀到的內容',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '這是你問教練 1:1 時，會跟問題一起送給 AI 的內容。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.45,
              ),
            ),
            if (hasUnsavedChanges) ...[
              const SizedBox(height: 6),
              Text(
                '你還有修改沒儲存；存檔之後，教練才會讀到新的內容。',
                key: const Key('coach-context-preview-unsaved'),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.ctaStart,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: SelectableText(
                coachContext,
                key: const Key('coach-context-preview-text'),
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    AppHaptics.onPress(() => Navigator.of(sheetContext).pop()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ctaStart,
                  foregroundColor: AppColors.onCta,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text(
                  '知道了',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

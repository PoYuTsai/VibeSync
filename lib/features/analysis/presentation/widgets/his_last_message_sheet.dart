/// 最後一則是他傳的：開始分析前先提醒（Eric 2026-10-18）。v3 看到最後一則是他的，
/// 多半判「先別回」，跟出卡一樣照字數扣（Eric 2026-10-19 照 Bruce 改回，不再固定 1 則）；
/// 這裡讓他選要不要照樣分析，「先不要」什麼都不扣。
/// 只有對話分析的開始流程會叫（開場救星、新話題不走這裡）。
library;

import 'package:flutter/material.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

const hisLastMessageSheetTitle = '最後一則是你傳的';

/// 回傳 true＝還是要分析；false 或關掉＝先不要（不送出、不扣）。
Future<bool> showHisLastMessageSheet(BuildContext context) async {
  final proceed = await showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const HisLastMessageSheet(),
  );
  return proceed ?? false;
}

class HisLastMessageSheet extends StatelessWidget {
  const HisLastMessageSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BrandPageBackground(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  hisLastMessageSheetTitle,
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '教練多半會建議你先等她回。\n這種結果跟其他分析一樣，照字數扣。',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '還沒傳出去的話：長按這則刪掉再分析，分析完用「幫我修」改它。',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    key: const ValueKey('his-last-message-cancel'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.ctaStart,
                      foregroundColor: AppColors.onCta,
                    ),
                    onPressed: AppHaptics.onPress(
                      () => Navigator.of(context).pop(false),
                    ),
                    child: const Text('先不要'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    key: const ValueKey('his-last-message-proceed'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.onBackgroundPrimary,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    onPressed: AppHaptics.onPress(
                      () => Navigator.of(context).pop(true),
                    ),
                    child: const Text('還是要分析'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

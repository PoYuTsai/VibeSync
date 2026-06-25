import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/practice_girl_profile.dart';
import 'practice_girl_photo.dart';

/// 對象 profile bottom sheet：只展示 server catalog 已知（AI 人設也知道）的資訊，
/// 絕不新增 client-only 欄位，避免 UI 與 AI 人設說兩套。
Future<void> showPracticeProfileSheet(
  BuildContext context,
  PracticeGirlProfile girl,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.brandInk,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _PracticeProfileSheet(girl: girl),
  );
}

class _PracticeProfileSheet extends StatelessWidget {
  const _PracticeProfileSheet({required this.girl});

  final PracticeGirlProfile girl;

  @override
  Widget build(BuildContext context) {
    final tags = <String>[
      ...girl.personalityTags,
      ...girl.interestTags,
      ...girl.lifestyleTags,
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.84,
        ),
        child: SingleChildScrollView(
          key: const ValueKey('practice-profile-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            children: [
              PracticeGirlPhoto(
                profile: girl,
                width: 248,
                height: 310,
                borderRadius: BorderRadius.circular(20),
              ),
              const SizedBox(height: 16),
              Text(
                '${girl.displayName}，${girl.age}',
                style: AppTypography.titleLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${girl.professionLabel} · ${girl.city}',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '想找：${girl.relationshipGoal} · ${girl.zodiac}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [for (final t in tags) _SheetTag(label: t)],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.brandSurface2.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  girl.selfIntro,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTag extends StatelessWidget {
  const _SheetTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ctaStart.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: AppColors.ctaStart,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

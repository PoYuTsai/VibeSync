import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/practice_acquaintance_origin.dart';
import '../../domain/entities/practice_girl_profile.dart';
import 'practice_girl_photo.dart';

/// 對象 profile bottom sheet：只展示 server catalog 已知（AI 人設也知道）的資訊，
/// 絕不新增 client-only 欄位，避免 UI 與 AI 人設說兩套。認識場合是唯一例外——
/// 它不在 catalog 裡，是 [practiceAcquaintanceOriginFor] 鏡像 server
/// buildAcquaintanceOrigin 現場算出來的，同一份 threadId 保證跟 AI 對話裡帶出
/// 的場景一致，仍然符合「client 不說一套 AI 不知道的話」的原則。
Future<void> showPracticeProfileSheet(
  BuildContext context,
  PracticeGirlProfile girl, {
  required String threadId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.brandInk,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _PracticeProfileSheet(girl: girl, threadId: threadId),
  );
}

class _PracticeProfileSheet extends StatelessWidget {
  const _PracticeProfileSheet({required this.girl, required this.threadId});

  final PracticeGirlProfile girl;
  final String threadId;

  @override
  Widget build(BuildContext context) {
    final tags = <String>[
      ...girl.personalityTags,
      ...girl.interestTags,
      ...girl.lifestyleTags,
    ];
    final origin = practiceAcquaintanceOriginFor(
      profileId: girl.profileId,
      professionId: girl.professionId,
      threadId: threadId,
    );
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
              GestureDetector(
                key: const ValueKey('practice-profile-sheet-photo'),
                onTap: () => showPracticeGirlFullPhoto(context, girl),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    PracticeGirlPhoto(
                      profile: girl,
                      width: 248,
                      height: 310,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    const Positioned(
                      bottom: 10,
                      child: PracticeGirlPhotoExpandHint(),
                    ),
                  ],
                ),
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
              // 只顯示 AI 人設 prompt 真的知道的欄位（relationshipGoal 有注入 prompt）；
              // zodiac/heightCm 沒進 prompt，故不顯示，避免 UI 說一套、AI 不知道。
              Text(
                '想找：${girl.relationshipGoal}',
                style: AppTypography.caption.copyWith(
                  color:
                      AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [for (final t in tags) _SheetTag(label: t)],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.route_outlined,
                    size: 16,
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      origin.sharedFact,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
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

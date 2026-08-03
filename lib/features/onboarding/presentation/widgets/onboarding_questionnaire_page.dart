import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../user_profile/domain/entities/user_profile.dart';

/// Tier 2 批 2：onboarding 一頁輕量問卷（第 4 頁，隱私頁前）。
///
/// Controlled widget：選擇存在 parent（_OnboardingScreenState）欄位，
/// 本頁不寫 Hive——統一由分流頁的合併種子一次寫入。不選也能往下走。
/// chips 為頁內輕量自建（ProfileChipSection 佈局不合 onboarding 深色滿版），
/// 絕不改共用元件。
class OnboardingQuestionnairePage extends StatelessWidget {
  const OnboardingQuestionnairePage({
    super.key,
    required this.selectedStyle,
    required this.selectedGoals,
    required this.onStyleChanged,
    required this.onGoalsChanged,
  });

  static const maxGoals = 2;

  final InteractionStyle? selectedStyle;
  final List<PracticeGoal> selectedGoals;
  final ValueChanged<InteractionStyle?> onStyleChanged;
  final ValueChanged<List<PracticeGoal>> onGoalsChanged;

  static String styleLabel(InteractionStyle s) => switch (s) {
        InteractionStyle.steady => '穩重',
        InteractionStyle.direct => '直接',
        InteractionStyle.humorous => '幽默',
        InteractionStyle.gentle => '溫柔',
        InteractionStyle.playful => '俏皮',
      };

  static String goalLabel(PracticeGoal g) => switch (g) {
        PracticeGoal.softInvite => '想約得出來',
        PracticeGoal.comfortableChat => '想先能自在聊天，不要那麼緊繃',
        PracticeGoal.humorousReply => '想讓對話更幽默、有來有往',
        PracticeGoal.buildCloseness => '想培養穩定的親近感',
        PracticeGoal.findCompatiblePartner => '想找到聊得來的對象、不設限交往',
      };

  void _toggleStyle(InteractionStyle style) {
    onStyleChanged(selectedStyle == style ? null : style);
  }

  void _toggleGoal(PracticeGoal goal) {
    if (selectedGoals.contains(goal)) {
      onGoalsChanged(
        selectedGoals.where((g) => g != goal).toList(growable: false),
      );
      return;
    }
    // 滿 2 顆時點第 3 顆直接不給選（拍板：選簡單的那條路）。
    if (selectedGoals.length >= maxGoals) return;
    onGoalsChanged([...selectedGoals, goal]);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '30 秒，讓建議更像你',
                  style: AppTypography.headlineMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '不選也可以，之後都能在「關於我」修改',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                _sectionTitle('你平常聊天的風格是？'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final style in InteractionStyle.values)
                      _chip(
                        label: styleLabel(style),
                        selected: selectedStyle == style,
                        onTap: () => _toggleStyle(style),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                _sectionTitle('你最想練的是？（最多 2 個）'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final goal in PracticeGoal.values)
                      _chip(
                        label: goalLabel(goal),
                        selected: selectedGoals.contains(goal),
                        onTap: () => _toggleGoal(goal),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: AppTypography.titleMedium.copyWith(
          color: AppColors.onBackgroundPrimary,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [AppColors.selectedStart, AppColors.selectedEnd],
                  )
                : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: selected ? Colors.white : AppColors.onBackgroundSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

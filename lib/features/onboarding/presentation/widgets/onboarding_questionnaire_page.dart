import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
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
    required this.selectedGoals,
    required this.onGoalsChanged,
  });

  static const maxGoals = 2;

  final List<PracticeGoal> selectedGoals;
  final ValueChanged<List<PracticeGoal>> onGoalsChanged;

  static String goalLabel(PracticeGoal g) => switch (g) {
        PracticeGoal.softInvite => '想約得出來',
        PracticeGoal.comfortableChat => '想先能自在聊天，不要那麼緊繃',
        PracticeGoal.humorousReply => '想讓對話更幽默、有來有往',
        PracticeGoal.buildCloseness => '想培養穩定的親近感',
        PracticeGoal.findCompatiblePartner => '想找到聊得來的對象、不設限交往',
      };

  /// 鏡像卡承諾句：每個目標一句具體的「教練會怎麼做」（2026-08-07 Eric 過稿）。
  /// onboarding 專用文案，刻意不用「關於我」共用的 GrowthPreviewBuilder——
  /// 不為單一頁面動有測試罩著的共用產生器；一目標一組也天然避開頓號串接流水句。
  static String goalPromise(PracticeGoal g) => switch (g) {
        PracticeGoal.softInvite => '教練會幫你盯時機——聊到什麼熱度、出現哪些訊號，就是開口約的時候。',
        PracticeGoal.comfortableChat => '教練會先帶你把節奏放慢，不用急著接好每一句，聊起來自然不緊繃。',
        PracticeGoal.humorousReply => '教練會教你接梗和拋梗的位置，讓對話有來有往，不是硬擠笑點。',
        PracticeGoal.buildCloseness => '教練會帶你把話題慢慢聊深，讓好感是累積出來的，不是忽冷忽熱。',
        PracticeGoal.findCompatiblePartner => '教練會幫你從每段對話看出誰真的聊得來，把力氣花在對的人身上。',
      };

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
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
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
                const SizedBox(height: 32),
                _sectionTitle('你最想練的是？（最多 2 個）'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final goal in PracticeGoal.values)
                      _chip(
                        // 鏡像卡會複誦 chip 同字樣，測試點擊一律走 key 不走文字。
                        chipKey: ValueKey('onboarding-goal-${goal.name}'),
                        label: goalLabel(goal),
                        selected: selectedGoals.contains(goal),
                        onTap: () => _toggleGoal(goal),
                      ),
                  ],
                ),
                // 鏡像卡：選了目標當場回「教練會怎麼做」，沒選就整塊收掉——
                // 沒有投入就沒有東西可以反射，不出對誰都成立的空話 fallback。
                // AnimatedSize：本頁 Column 垂直置中，卡片長出時整塊會重新置中；
                // 平滑過渡取代瞬移。ticker 驅動，fake async 測試可收斂（絕不用
                // Timer/Future.delayed 當時間軸）。間距收在卡片分支內，空狀態
                // 版面與未加卡前逐位元一致。
                AnimatedSize(
                  duration: reduceMotion ? Duration.zero : AppMotion.enter,
                  curve: AppMotion.easeOut,
                  alignment: Alignment.topCenter,
                  child: selectedGoals.isEmpty
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: _mirrorCard(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 鏡像卡：樣式 token 比照第 2、3 頁示範卡（_DemoCard），但不掛「示範」
  /// 徽章——前兩頁演的是別人的對話，這張講的是使用者自己，混同會削弱
  /// 「這在講我」的感覺。照本檔既有規矩頁內輕量自建，不 export 共用元件。
  Widget _mirrorCard() {
    return Container(
      key: const ValueKey('onboarding-mirror-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, goal) in selectedGoals.indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            Text(
              goalLabel(goal),
              style: AppTypography.bodyMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              goalPromise(goal),
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundPrimary,
                height: 1.5,
              ),
            ),
          ],
        ],
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
    required Key chipKey,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      key: chipKey,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.enter,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

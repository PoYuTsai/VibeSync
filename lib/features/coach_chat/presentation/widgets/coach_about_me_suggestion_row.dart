import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';
import '../../../user_profile/domain/entities/user_profile.dart';
import '../../../user_profile/presentation/widgets/about_me_option_labels.dart';
import '../../data/providers/coach_chat_providers.dart';
import '../../domain/entities/about_me_suggestion.dart';
import '../../domain/entities/coach_scope.dart';

/// 規格 PR-9：正式建議下面那一行「要不要把『…』加到關於我？」。本人按【加入】
/// 才寫進關於我；關於我裡已經有了就不顯示；那一類已經選滿時，改成請他去關於我
/// 拿掉一個。
class CoachAboutMeSuggestionRow extends ConsumerStatefulWidget {
  const CoachAboutMeSuggestionRow({
    super.key,
    required this.scope,
    required this.suggestion,
  });

  final CoachScope scope;
  final AboutMeSuggestion suggestion;

  @override
  ConsumerState<CoachAboutMeSuggestionRow> createState() =>
      _CoachAboutMeSuggestionRowState();
}

class _CoachAboutMeSuggestionRowState
    extends ConsumerState<CoachAboutMeSuggestionRow> {
  bool _saving = false;

  String get _label {
    final stuck = widget.suggestion.stuckPoint;
    return stuck != null
        ? stuckPointLabel(stuck)
        : practiceGoalLabel(widget.suggestion.practiceGoal!);
  }

  String get _fullHint => widget.suggestion.stuckPoint != null
      ? '「我現在卡在哪」最多 ${UserProfile.maxStuckPoints} 個，要先到關於我拿掉一個。'
      : '「我想達成什麼」最多 ${UserProfile.maxPracticeGoals} 個，要先到關於我拿掉一個。';

  void _dismiss() {
    ref.read(coachAboutMeSuggestionProvider(widget.scope).notifier).state =
        null;
  }

  Future<void> _add() async {
    if (_saving) return;
    setState(() => _saving = true);
    // 先抓好：存檔途中離開畫面，存檔照樣完成，不能因為畫面不在了誤報失敗。
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(userProfileControllerProvider.notifier);
    final suggestion = widget.suggestion;
    try {
      // 存檔前重讀一次：畫面上的值可能是別處改過之前的。
      final current = await ref.read(userProfileControllerProvider.future);
      if (suggestion.isIn(current)) {
        if (mounted) _dismiss();
        return;
      }
      // 滿了：這一行會照最新的關於我換成「去關於我調整」。
      if (suggestion.categoryFullIn(current)) return;
      await controller.save(
        suggestion.addTo(current, now: DateTime.now().toUtc()),
      );
    } catch (_) {
      AppHaptics.failure();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('儲存失敗，請再試一次'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    AppHaptics.success();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('已更新關於我'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    if (mounted) _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    // 只認讀完、沒出錯的關於我（同「教練參考」標籤）：讀取中或失敗時不知道
    // 裡面是不是已經有了，先不顯示。
    final profileAsync = ref.watch(userProfileControllerProvider);
    if (profileAsync.isLoading || profileAsync.hasError) {
      return const SizedBox.shrink();
    }
    final profile = profileAsync.valueOrNull;
    if (widget.suggestion.isIn(profile)) return const SizedBox.shrink();
    final full = widget.suggestion.categoryFullIn(profile);

    return Container(
      key: const Key('coach-about-me-suggestion'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '要不要把『$_label』加到關於我？',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextPrimary,
              height: 1.4,
            ),
          ),
          if (full) ...[
            const SizedBox(height: 4),
            Text(
              _fullHint,
              key: const Key('coach-about-me-suggestion-full'),
              style: AppTypography.caption.copyWith(
                color: AppColors.glassTextSecondary,
                height: 1.4,
              ),
            ),
          ],
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              if (full)
                TextButton(
                  key: const Key('coach-about-me-suggestion-adjust'),
                  onPressed: _saving
                      ? null
                      : AppHaptics.onPress(
                          () => context.push('/profile/about-me'),
                        ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                  child: const Text(
                    '去關於我調整',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                )
              else
                TextButton(
                  key: const Key('coach-about-me-suggestion-add'),
                  onPressed: _saving ? null : AppHaptics.onPress(_add),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                  child: const Text(
                    '加入',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              TextButton(
                key: const Key('coach-about-me-suggestion-dismiss'),
                onPressed: _saving ? null : AppHaptics.onPress(_dismiss),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.glassTextSecondary,
                ),
                child: const Text('不用'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

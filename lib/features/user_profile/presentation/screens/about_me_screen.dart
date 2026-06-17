import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/user_profile_providers.dart';
import '../../domain/entities/user_profile.dart';
import '../style_pair_draft.dart';
import '../widgets/profile_chip_section.dart';

class AboutMeScreen extends ConsumerStatefulWidget {
  const AboutMeScreen({super.key});

  @override
  ConsumerState<AboutMeScreen> createState() => _AboutMeScreenState();
}

class _AboutMeScreenState extends ConsumerState<AboutMeScreen> {
  StylePairDraft _draftPair = StylePairDraft.empty;
  final Set<PracticeGoal> _draftGoals = <PracticeGoal>{};
  final Set<TopicSeed> _draftSeeds = <TopicSeed>{};
  final TextEditingController _customController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  UserProfile? _initialProfile;
  bool _hydrated = false;

  @override
  void dispose() {
    _customController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _hydrate(UserProfile? profile) {
    if (_hydrated || profile == null) return;
    _initialProfile = profile;
    _draftPair = StylePairDraft(
      primary: profile.interactionStyle,
      secondary: profile.secondaryStyle,
    );
    _draftGoals
      ..clear()
      ..addAll(profile.practiceGoals);
    _draftSeeds
      ..clear()
      ..addAll(profile.topicSeeds);
    _customController.text = profile.customTopics ?? '';
    _notesController.text = profile.notes ?? '';
    _hydrated = true;
  }

  bool get _isDraftEmpty =>
      _draftPair.primary == null &&
      _draftGoals.isEmpty &&
      _draftSeeds.isEmpty &&
      _customController.text.trim().isEmpty &&
      _notesController.text.trim().isEmpty;

  String get _primaryLabel {
    final hasExisting = _initialProfile != null && !_initialProfile!.isEmpty;
    if (!hasExisting && _isDraftEmpty) return '先跳過';
    if (hasExisting && _isDraftEmpty) return '清除設定';
    return '儲存';
  }

  void _toggleGoal(PracticeGoal g) {
    if (_draftGoals.contains(g)) {
      setState(() => _draftGoals.remove(g));
      return;
    }
    if (_draftGoals.length >= UserProfile.maxPracticeGoals) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('最多選 3 個'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    setState(() => _draftGoals.add(g));
  }

  void _toggleSeed(TopicSeed s) {
    if (_draftSeeds.contains(s)) {
      setState(() => _draftSeeds.remove(s));
      return;
    }
    if (_draftSeeds.length >= UserProfile.maxTopicSeeds) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('最多選 5 個'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    setState(() => _draftSeeds.add(s));
  }

  Future<void> _onPrimaryTap() async {
    final messenger = ScaffoldMessenger.of(context);
    final label = _primaryLabel;
    final controller = ref.read(userProfileControllerProvider.notifier);

    void popIfPossible() {
      if (context.canPop()) context.pop();
    }

    if (label == '先跳過') {
      popIfPossible();
      return;
    }

    if (label == '清除設定') {
      try {
        await controller.clear();
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('儲存失敗，請再試一次')),
        );
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('已清除關於我設定')),
      );
      popIfPossible();
      return;
    }

    // label == '儲存'
    try {
      final profile = UserProfile.create(
        interactionStyle: _draftPair.primary,
        secondaryStyle: _draftPair.secondary,
        practiceGoals: _draftGoals.toList(),
        topicSeeds: _draftSeeds.toList(),
        customTopics: _customController.text,
        notes: _notesController.text,
        updatedAt: DateTime.now().toUtc(),
      );
      await controller.save(profile);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('儲存失敗，請再試一次')),
      );
      return;
    }

    messenger.showSnackBar(
      const SnackBar(content: Text('已更新關於我')),
    );
    popIfPossible();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userProfileControllerProvider);

    return state.when(
      loading: () => const _AboutMeBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: CircularProgressIndicator(color: AppColors.ctaStart),
          ),
        ),
      ),
      error: (e, _) => _AboutMeBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _buildAppBar(),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '無法載入設定，請稍後再試',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
      data: (profile) {
        _hydrate(profile);
        return _buildScaffold(context);
      },
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return _AboutMeBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _AboutMeIntroCard(),
                const SizedBox(height: 14),
                ProfileChipSection<InteractionStyle>(
                  title: '互動風格',
                  subtitle: '先點主風格，再點副風格（可只選主）。',
                  options: InteractionStyle.values,
                  labelOf: _interactionStyleLabel,
                  isSelected: _draftPair.contains,
                  badgeOf: _draftPair.badgeOf,
                  onTap: (s) => setState(() {
                    _draftPair = _draftPair.tap(s);
                  }),
                ),
                const SizedBox(height: 14),
                ProfileChipSection<PracticeGoal>(
                  title: '練習目標',
                  subtitle: '最多 3 個，AI 會在合適時機提醒。',
                  options: PracticeGoal.values,
                  labelOf: _practiceGoalLabel,
                  isSelected: _draftGoals.contains,
                  onTap: _toggleGoal,
                ),
                const SizedBox(height: 14),
                ProfileChipSection<TopicSeed>(
                  title: '常聊話題',
                  subtitle: '最多 5 個，幫 AI 發想話題。',
                  options: TopicSeed.values,
                  labelOf: _topicSeedLabel,
                  isSelected: _draftSeeds.contains,
                  onTap: _toggleSeed,
                ),
                const SizedBox(height: 14),
                _ProfileInputSection(
                  title: '想聊但沒在上面的話題',
                  child: TextField(
                    key: const Key('about-me-custom-topics'),
                    controller: _customController,
                    maxLength: UserProfile.maxCustomTopicsLength,
                    onChanged: (_) => setState(() {}),
                    cursorColor: AppColors.ctaStart,
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white,
                    ),
                    decoration: _fieldDecoration('例如：日劇、週末探店'),
                  ),
                ),
                const SizedBox(height: 14),
                _ProfileInputSection(
                  title: '想讓 AI 知道的事',
                  subtitle: '例如：「我慢熟、希望不要太快邀約」。',
                  child: TextField(
                    key: const Key('about-me-notes'),
                    controller: _notesController,
                    maxLength: UserProfile.maxNotesLength,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    cursorColor: AppColors.ctaStart,
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white,
                      height: 1.35,
                    ),
                    decoration: _fieldDecoration('寫一句你希望 AI 記住的事'),
                  ),
                ),
                const SizedBox(height: 14),
                const _PrivacyNote(),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.ctaStart, AppColors.ctaEnd],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ctaStart.withValues(alpha: 0.30),
                        blurRadius: 18,
                        offset: const Offset(0, 9),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _onPrimaryTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Text(
                      _primaryLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
      title: Text(
        '關於我',
        style: AppTypography.titleLarge.copyWith(
          color: AppColors.onBackgroundPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hintText) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTypography.bodyMedium.copyWith(
        color: Colors.white.withValues(alpha: 0.40),
      ),
      filled: true,
      fillColor: AppColors.brandInk.withValues(alpha: 0.38),
      counterStyle: AppTypography.caption.copyWith(
        color: AppColors.onBackgroundSecondary.withValues(alpha: 0.62),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: border(Colors.white.withValues(alpha: 0.12)),
      focusedBorder: border(AppColors.ctaStart.withValues(alpha: 0.74), 1.3),
      errorBorder: border(AppColors.error.withValues(alpha: 0.80)),
      focusedErrorBorder: border(AppColors.error),
    );
  }
}

class _AboutMeBackground extends StatelessWidget {
  const _AboutMeBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.brandInk,
            AppColors.brandSurface,
            AppColors.brandSurface2,
          ],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
      child: child,
    );
  }
}

class _AboutMeIntroCard extends StatelessWidget {
  const _AboutMeIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brandSurface2.withValues(alpha: 0.90),
            AppColors.brandSurface.withValues(alpha: 0.96),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.ctaStart, AppColors.brandBlush],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '讓建議更像你',
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'AI 會用這些設定調整你的回覆語氣、練習方向和跟進建議；不會替你假裝成另一個人。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInputSection extends StatelessWidget {
  const _ProfileInputSection({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandSurface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.76),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: AppColors.ctaStart.withValues(alpha: 0.86),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '這些設定只用來讓建議更貼近你的語氣，不會顯示給任何對象，你可以隨時修改或清除。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _interactionStyleLabel(InteractionStyle s) => switch (s) {
      InteractionStyle.steady => '穩重',
      InteractionStyle.direct => '直接',
      InteractionStyle.humorous => '幽默',
      InteractionStyle.gentle => '溫柔',
      InteractionStyle.playful => '俏皮',
    };

String _practiceGoalLabel(PracticeGoal g) => switch (g) {
      PracticeGoal.softInvite => '自然邀約',
      PracticeGoal.reduceAnxiety => '降低焦慮',
      PracticeGoal.humorousReply => '幽默回覆',
      PracticeGoal.buildCloseness => '培養親近',
      PracticeGoal.explainLess => '減少解釋',
    };

String _topicSeedLabel(TopicSeed t) => switch (t) {
      TopicSeed.fitness => '健身',
      TopicSeed.travel => '旅行',
      TopicSeed.coffee => '咖啡',
      TopicSeed.music => '音樂',
      TopicSeed.movies => '電影',
      TopicSeed.photography => '攝影',
      TopicSeed.food => '美食',
      TopicSeed.pets => '寵物',
      TopicSeed.reading => '閱讀',
      TopicSeed.workLife => '工作生活',
    };

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/user_profile_providers.dart';
import '../../domain/entities/user_profile.dart';
import '../widgets/profile_chip_section.dart';

class AboutMeScreen extends ConsumerStatefulWidget {
  const AboutMeScreen({super.key});

  @override
  ConsumerState<AboutMeScreen> createState() => _AboutMeScreenState();
}

class _AboutMeScreenState extends ConsumerState<AboutMeScreen> {
  InteractionStyle? _draftStyle;
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
    _draftStyle = profile.interactionStyle;
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
      _draftStyle == null &&
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
        interactionStyle: _draftStyle,
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
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('關於我')),
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
      data: (profile) {
        _hydrate(profile);
        return _buildScaffold(context);
      },
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('關於我'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '花 30 秒設定，AI 會用更像你的節奏給建議。',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ProfileChipSection<InteractionStyle>(
                title: '互動風格',
                subtitle: '單選，告訴 AI 你的氣場。',
                options: InteractionStyle.values,
                labelOf: _interactionStyleLabel,
                isSelected: (s) => _draftStyle == s,
                onTap: (s) => setState(() {
                  _draftStyle = (_draftStyle == s) ? null : s;
                }),
              ),
              const SizedBox(height: 20),
              ProfileChipSection<PracticeGoal>(
                title: '練習目標',
                subtitle: '最多 3 個，AI 會在合適時機提醒。',
                options: PracticeGoal.values,
                labelOf: _practiceGoalLabel,
                isSelected: _draftGoals.contains,
                onTap: _toggleGoal,
              ),
              const SizedBox(height: 20),
              ProfileChipSection<TopicSeed>(
                title: '常聊話題',
                subtitle: '最多 5 個，幫 AI 發想話題。',
                options: TopicSeed.values,
                labelOf: _topicSeedLabel,
                isSelected: _draftSeeds.contains,
                onTap: _toggleSeed,
              ),
              const SizedBox(height: 20),
              Text(
                '想聊但沒在上面的話題',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('about-me-custom-topics'),
                controller: _customController,
                maxLength: UserProfile.maxCustomTopicsLength,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '例如：日劇、週末探店',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '想讓 AI 知道的事',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '例如：「我慢熟、希望不要太快邀約」。',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('about-me-notes'),
                controller: _notesController,
                maxLength: UserProfile.maxNotesLength,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '寫一句你希望 AI 記住的事',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '這些設定只用來讓建議更貼近你的語氣，不會顯示給任何對象，你可以隨時修改或清除。',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _onPrimaryTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ctaStart,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(_primaryLabel),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
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

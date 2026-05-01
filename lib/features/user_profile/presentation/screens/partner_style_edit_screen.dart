import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/glassmorphic_container.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../data/providers/partner_style_providers.dart';
import '../../data/providers/user_profile_providers.dart';
import '../../domain/entities/partner_style_override.dart';
import '../../domain/entities/user_profile.dart';

/// Edit screen for per-partner style overrides — Spec 2 Phase 6.
///
/// Local draft state seeded from the provider's loaded override; chip taps
/// mutate the draft without touching the repo. Repo `save` (with isEmpty
/// cascade-delete) is wired by Task 18's PopScope.
class PartnerStyleEditScreen extends ConsumerStatefulWidget {
  const PartnerStyleEditScreen({super.key, required this.partnerId});

  final String partnerId;

  @override
  ConsumerState<PartnerStyleEditScreen> createState() =>
      _PartnerStyleEditScreenState();
}

class _PartnerStyleEditScreenState
    extends ConsumerState<PartnerStyleEditScreen> {
  bool _draftInitialized = false;
  InteractionStyle? _interactionStyle;
  final List<PracticeGoal> _practiceGoals = [];

  void _ensureInit(PartnerStyleOverride? loaded) {
    if (_draftInitialized) return;
    _draftInitialized = true;
    _interactionStyle = loaded?.interactionStyle;
    _practiceGoals
      ..clear()
      ..addAll(loaded?.practiceGoals ?? const []);
  }

  void _toggleGoal(PracticeGoal g) {
    if (_practiceGoals.contains(g)) {
      setState(() => _practiceGoals.remove(g));
      return;
    }
    if (_practiceGoals.length >= PartnerStyleOverride.maxPracticeGoals) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('最多選 3 個'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    setState(() => _practiceGoals.add(g));
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(partnerByIdProvider(widget.partnerId));
    final overrideAsync =
        ref.watch(partnerStyleOverrideProvider(widget.partnerId));
    final globalProfile =
        ref.watch(userProfileControllerProvider).valueOrNull;

    overrideAsync.whenData(_ensureInit);

    final title =
        partner == null ? '我的風格' : '我的風格 · ${partner.name}';

    return PopScope(
      // Auto-save plumbing lands in Task 18 — keeping the wrapper here so
      // the future change touches behavior only, not the widget tree shape.
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(
            color: AppColors.onBackgroundPrimary,
          ),
          title: Text(
            title,
            style: const TextStyle(color: AppColors.onBackgroundPrimary),
          ),
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: _EditScreenBackground()),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, kToolbarHeight, 16, 32),
                children: [
                  _InteractionStyleSection(
                    selected: _interactionStyle,
                    globalFallback: globalProfile?.interactionStyle,
                    onSelect: (s) => setState(() => _interactionStyle = s),
                    onReset: () => setState(() => _interactionStyle = null),
                  ),
                  const SizedBox(height: 16),
                  _PracticeGoalsSection(
                    selected: _practiceGoals,
                    globalFallback: globalProfile?.practiceGoals ?? const [],
                    onToggle: _toggleGoal,
                    onReset: () => setState(_practiceGoals.clear),
                  ),
                  const SizedBox(height: 16),
                  const _SectionPlaceholder(title: '備註'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractionStyleSection extends StatelessWidget {
  const _InteractionStyleSection({
    required this.selected,
    required this.globalFallback,
    required this.onSelect,
    required this.onReset,
  });

  final InteractionStyle? selected;
  final InteractionStyle? globalFallback;
  final ValueChanged<InteractionStyle> onSelect;
  final VoidCallback onReset;

  String? _placeholderHint() {
    if (selected != null) return null;
    if (globalFallback != null) {
      return '（沿用全域：${_styleLabel(globalFallback!)}）';
    }
    return '（尚未設定）';
  }

  @override
  Widget build(BuildContext context) {
    final hint = _placeholderHint();
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '互動風格',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: InteractionStyle.values.map((s) {
              return ChoiceChip(
                label: Text(_styleLabel(s)),
                selected: selected == s,
                showCheckmark: false,
                onSelected: (_) => onSelect(s),
              );
            }).toList(),
          ),
          if (selected != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onReset,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.glassTextSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('沿用全域'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _styleLabel(InteractionStyle s) => switch (s) {
      InteractionStyle.steady => '穩重',
      InteractionStyle.direct => '直接',
      InteractionStyle.humorous => '幽默',
      InteractionStyle.gentle => '溫柔',
      InteractionStyle.playful => '俏皮',
    };

String _goalLabel(PracticeGoal g) => switch (g) {
      PracticeGoal.softInvite => '自然邀約',
      PracticeGoal.reduceAnxiety => '降低焦慮',
      PracticeGoal.humorousReply => '幽默回覆',
      PracticeGoal.buildCloseness => '培養親近',
      PracticeGoal.explainLess => '減少解釋',
    };

class _PracticeGoalsSection extends StatelessWidget {
  const _PracticeGoalsSection({
    required this.selected,
    required this.globalFallback,
    required this.onToggle,
    required this.onReset,
  });

  final List<PracticeGoal> selected;
  final List<PracticeGoal> globalFallback;
  final ValueChanged<PracticeGoal> onToggle;
  final VoidCallback onReset;

  String? _placeholderHint() {
    if (selected.isNotEmpty) return null;
    if (globalFallback.isNotEmpty) {
      return '（沿用全域：${globalFallback.map(_goalLabel).join('、')}）';
    }
    return '（尚未設定）';
  }

  @override
  Widget build(BuildContext context) {
    final hint = _placeholderHint();
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '練習目標',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PracticeGoal.values.map((g) {
              return ChoiceChip(
                label: Text(_goalLabel(g)),
                selected: selected.contains(g),
                showCheckmark: false,
                onSelected: (_) => onToggle(g),
              );
            }).toList(),
          ),
          if (selected.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onReset,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.glassTextSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('沿用全域'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '即將上線',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditScreenBackground extends StatelessWidget {
  const _EditScreenBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.partnerDetailBgTop,
            AppColors.partnerDetailBgBottom,
          ],
        ),
      ),
    );
  }
}

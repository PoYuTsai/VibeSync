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
import '../style_pair_draft.dart';
import '../widgets/profile_chip_section.dart' show StyleRoleBadge;

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
  StylePairDraft _stylePair = StylePairDraft.empty;
  final List<PracticeGoal> _practiceGoals = [];
  final TextEditingController _notesController = TextEditingController();

  void _ensureInit(PartnerStyleOverride? loaded) {
    if (_draftInitialized) return;
    _draftInitialized = true;
    _stylePair = StylePairDraft(
      primary: loaded?.interactionStyle,
      secondary: loaded?.secondaryStyle,
    );
    _practiceGoals
      ..clear()
      ..addAll(loaded?.practiceGoals ?? const []);
    _notesController.text = loaded?.notes ?? '';
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
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

  Future<void> _saveDraft() async {
    if (!_draftInitialized) return;
    final notes = _notesController.text.trim();
    final draft = PartnerStyleOverride.create(
      partnerId: widget.partnerId,
      interactionStyle: _stylePair.primary,
      secondaryStyle: _stylePair.secondary,
      practiceGoals: _practiceGoals.toList(),
      notes: notes.isEmpty ? null : notes,
      updatedAt: DateTime.now(),
    );
    await ref
        .read(partnerStyleOverrideProvider(widget.partnerId).notifier)
        .save(draft);
  }

  Future<void> _saveAndPop({bool forcePop = false}) async {
    final navigator = Navigator.of(context);
    await _saveDraft();
    if (!mounted) return;
    if (forcePop || navigator.canPop()) navigator.pop();
  }

  Future<void> _confirmResetAll(
      BuildContext context, String partnerName) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除這個對象的自訂風格？'),
        content: Text('清空對 $partnerName 的自訂風格，之後會改回沿用全域預設。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(partnerStyleOverrideProvider(widget.partnerId).notifier)
        .clear();
    if (!mounted) return;
    setState(() {
      _stylePair = StylePairDraft.empty;
      _practiceGoals.clear();
      _notesController.clear();
    });
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(partnerByIdProvider(widget.partnerId));
    final overrideAsync =
        ref.watch(partnerStyleOverrideProvider(widget.partnerId));
    final globalProfile = ref.watch(userProfileControllerProvider).valueOrNull;

    overrideAsync.whenData(_ensureInit);

    final title = partner == null ? '我的風格' : '我的風格 · ${partner.name}';

    return PopScope(
      // Save draft BEFORE the pop completes so the next screen reads the
      // updated value. canPop=false blocks the default; we save then call
      // Navigator.pop manually. Empty drafts cascade-delete via the
      // notifier's `save(isEmpty → delete)` path.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _saveAndPop(forcePop: true);
      },
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
                  Text(
                    '只影響你和這位對象的建議；未設定時沿用「關於我」。AI 會調整語氣與練習方向，不會替你假裝成另一個人。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.glassTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InteractionStyleSection(
                    selected: _stylePair,
                    globalFallback: StylePairDraft(
                      primary: globalProfile?.interactionStyle,
                      secondary: globalProfile?.secondaryStyle,
                    ),
                    onTap: (s) =>
                        setState(() => _stylePair = _stylePair.tap(s)),
                    onReset: () =>
                        setState(() => _stylePair = StylePairDraft.empty),
                  ),
                  const SizedBox(height: 16),
                  _PracticeGoalsSection(
                    selected: _practiceGoals,
                    globalFallback: globalProfile?.practiceGoals ?? const [],
                    onToggle: _toggleGoal,
                    onReset: () => setState(_practiceGoals.clear),
                  ),
                  const SizedBox(height: 16),
                  _NotesSection(
                    controller: _notesController,
                    globalFallback: globalProfile?.notes,
                    onChanged: () => setState(() {}),
                    onReset: () => setState(_notesController.clear),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saveAndPop,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ctaStart,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('完成'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '點「完成」或返回，都會保存這個對象的設定',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.glassTextSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () =>
                          _confirmResetAll(context, partner?.name ?? '此對象'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.onBackgroundSecondary,
                      ),
                      child: const Text('清除這個對象的自訂風格'),
                    ),
                  ),
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
    required this.onTap,
    required this.onReset,
  });

  final StylePairDraft selected;
  final StylePairDraft globalFallback;
  final ValueChanged<InteractionStyle> onTap;
  final VoidCallback onReset;

  String? _placeholderHint() {
    if (selected.primary != null) return null;
    final globalPrimary = globalFallback.primary;
    if (globalPrimary != null) {
      final globalSecondary = globalFallback.secondary;
      return globalSecondary == null
          ? '（沿用全域：${_styleLabel(globalPrimary)}）'
          : '（沿用全域：以${_styleLabel(globalPrimary)}為主、'
              '${_styleLabel(globalSecondary)}為輔）';
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
          const SizedBox(height: 4),
          Text(
            '先點主風格，再點副風格（可只選主）。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextSecondary,
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
              final badge = selected.badgeOf(s);
              return ChoiceChip(
                label: badge == null
                    ? Text(_styleLabel(s))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_styleLabel(s)),
                          const SizedBox(width: 4),
                          StyleRoleBadge(text: badge),
                        ],
                      ),
                selected: selected.contains(s),
                showCheckmark: false,
                onSelected: (_) => onTap(s),
              );
            }).toList(),
          ),
          if (selected.primary != null) ...[
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

class _NotesSection extends StatelessWidget {
  const _NotesSection({
    required this.controller,
    required this.globalFallback,
    required this.onChanged,
    required this.onReset,
  });

  final TextEditingController controller;
  final String? globalFallback;
  final VoidCallback onChanged;
  final VoidCallback onReset;

  String? _placeholderHint() {
    if (controller.text.trim().isNotEmpty) return null;
    if (globalFallback != null && globalFallback!.trim().isNotEmpty) {
      return '（沿用全域：$globalFallback）';
    }
    return '（尚未設定）';
  }

  @override
  Widget build(BuildContext context) {
    final hint = _placeholderHint();
    final hasOverride = controller.text.trim().isNotEmpty;
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '備註',
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
          TextField(
            key: const Key('partner-style-notes-field'),
            controller: controller,
            maxLength: PartnerStyleOverride.maxNotesLength,
            maxLines: 3,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              hintText: '寫一句你希望 AI 對這個對象記住的事',
              border: OutlineInputBorder(),
            ),
          ),
          if (hasOverride) ...[
            const SizedBox(height: 4),
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

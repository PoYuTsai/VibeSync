// Spec 5 C24 — CoachFollowUpSection: 教練跟進 entry block on partner detail.
//
// Two visual states:
//   • default — chip row + caption (rendered when no result is stored OR the
//     user tapped 換情境 to switch context)
//   • with-result — result card + 重新生成 / 換情境 buttons + caption
//
// Three design choices (locked at C24 kickoff):
//   1. Insert anchor B (partner_detail_screen): between Style+Radar cluster
//      and conversations list — keeps existing profile cluster untouched.
//   2. 換情境 = local UI flag only (`_showSwitcher`). Does NOT delete the
//      Hive result. Latest-only persistence still holds because the next
//      successful generate overwrites.
//   3. Telemetry = typed sealed callback contract (Invoked / Regenerated /
//      PhaseSwitched). The screen wires a stub now; X25 will swap in the
//      real sink without re-touching this widget.
//
// State source-of-truth:
//   • `coachFollowUpControllerProvider` is the live source for loading state
//     and successful generate transitions (via `ref.listen`). The widget
//     also reads `coachFollowUpResultProvider` once in `initState` to
//     hydrate the displayed result on first paint. Subsequent updates
//     flow through the listen → setState path so the result card never
//     blinks during a regenerate (the controller resets state to loading,
//     but `_displayedResult` keeps the previous value pinned until the
//     new one arrives).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../data/providers/coach_follow_up_providers.dart';
import '../../data/services/coach_follow_up_api_service.dart';
import '../../domain/entities/coach_follow_up_phase.dart';
import '../../domain/entities/coach_follow_up_result.dart';
import 'coach_follow_up_chip_row.dart';
import 'coach_follow_up_input_sheet.dart';
import 'coach_follow_up_result_card.dart';

// ── Telemetry contract ────────────────────────────────────────────────────
//
// The section emits these events via `onTelemetry`. A real analytics sink
// is wired by X25; until then the screen handler is a debugPrint stub. The
// shapes mirror design §7's `coach_follow_up_*` event names.

sealed class CoachFollowUpTelemetryEvent {
  const CoachFollowUpTelemetryEvent();
}

/// Fires once per successful sheet submit (before the network call kicks
/// off). `hasOptionalText` is the only free-text-derived signal allowed
/// out of the section — the q3 body itself NEVER leaves the widget.
class CoachFollowUpInvokedEvent extends CoachFollowUpTelemetryEvent {
  final CoachFollowUpPhase phase;
  final bool hasOptionalText;

  const CoachFollowUpInvokedEvent({
    required this.phase,
    required this.hasOptionalText,
  });
}

/// Fires when the user taps 重新生成. Only emitted after a same-session
/// generate (we need the prior answers to regenerate; carrying them across
/// sessions is out of scope for v1).
class CoachFollowUpRegeneratedEvent extends CoachFollowUpTelemetryEvent {
  final CoachFollowUpPhase phase;
  final Duration sinceLast;

  const CoachFollowUpRegeneratedEvent({
    required this.phase,
    required this.sinceLast,
  });
}

/// Fires when the user changes their phase choice while a prior phase is
/// implied — either from a stored result or from a previous in-session
/// chip selection. NOT emitted on the very first chip tap (no `from`).
class CoachFollowUpPhaseSwitchedEvent extends CoachFollowUpTelemetryEvent {
  final CoachFollowUpPhase fromPhase;
  final CoachFollowUpPhase toPhase;
  final bool hadResultBefore;

  const CoachFollowUpPhaseSwitchedEvent({
    required this.fromPhase,
    required this.toPhase,
    required this.hadResultBefore,
  });
}

// ── Section widget ────────────────────────────────────────────────────────

Future<CoachFollowUpAnswers?> showCoachFollowUpInputSheet({
  required BuildContext context,
  required CoachFollowUpPhase phase,
}) {
  return showModalBottomSheet<CoachFollowUpAnswers>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
      ),
      child: CoachFollowUpInputSheet(
        phase: phase,
        onSubmit: (a) => Navigator.of(sheetCtx).pop(a),
      ),
    ),
  );
}

class CoachFollowUpSection extends ConsumerStatefulWidget {
  final String partnerId;
  final ValueChanged<CoachFollowUpTelemetryEvent>? onTelemetry;
  final Future<void> Function()? onQuotaExceeded;
  final Key? openCoachEntryAnchorKey;
  final bool openCoachInputOnFirstBuild;

  const CoachFollowUpSection({
    super.key,
    required this.partnerId,
    this.onTelemetry,
    this.onQuotaExceeded,
    this.openCoachEntryAnchorKey,
    this.openCoachInputOnFirstBuild = false,
  });

  @override
  ConsumerState<CoachFollowUpSection> createState() =>
      _CoachFollowUpSectionState();
}

class _CoachFollowUpSectionState extends ConsumerState<CoachFollowUpSection> {
  CoachFollowUpResult? _displayedResult;
  bool _showSwitcher = false;
  CoachFollowUpPhase? _selectedPhase;

  // Cached for regenerate. _lastAnswers stays null when the displayed
  // result was hydrated from Hive (prior session) — answers from then are
  // unrecoverable, which is why the regenerate button disables until a
  // fresh same-session generate fills them in.
  CoachFollowUpPhase? _lastPhase;
  CoachFollowUpAnswers? _lastAnswers;
  DateTime? _lastGeneratedAt;
  bool _openingQuotaPaywall = false;
  bool _didAutoOpenCoachInput = false;

  @override
  void initState() {
    super.initState();
    final stored = ref.read(coachFollowUpResultProvider(widget.partnerId));
    _displayedResult = stored;
    if (stored != null) {
      _lastPhase = CoachFollowUpPhase.fromString(stored.phase);
    }
    _scheduleAutoOpenCoachInputIfNeeded();
  }

  @override
  void didUpdateWidget(covariant CoachFollowUpSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openCoachInputOnFirstBuild &&
        !oldWidget.openCoachInputOnFirstBuild) {
      _scheduleAutoOpenCoachInputIfNeeded();
    }
  }

  void _scheduleAutoOpenCoachInputIfNeeded() {
    if (!widget.openCoachInputOnFirstBuild || _didAutoOpenCoachInput) return;
    _didAutoOpenCoachInput = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onOpenCoachTap();
    });
  }

  void _emit(CoachFollowUpTelemetryEvent event) {
    widget.onTelemetry?.call(event);
  }

  void _openQuotaPaywallOnce() {
    if (_openingQuotaPaywall) return;
    _openingQuotaPaywall = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _openingQuotaPaywall = false;
        return;
      }
      try {
        await widget.onQuotaExceeded?.call();
      } finally {
        if (mounted) {
          _openingQuotaPaywall = false;
        }
      }
    });
  }

  /// Resolves the "previous" phase for PhaseSwitched. Priority:
  ///   1. an in-session chip selection (most recent intent)
  ///   2. the stored result's phase (cross-session intent)
  ///   3. null — first interaction, no `from`
  CoachFollowUpPhase? _priorPhase() {
    if (_selectedPhase != null) return _selectedPhase;
    final stored = _displayedResult;
    if (stored != null) {
      return CoachFollowUpPhase.fromString(stored.phase);
    }
    return null;
  }

  String? _hintTextFor(CoachFollowUpPhase? phase) {
    if (phase == null) return null;
    switch (phase) {
      case CoachFollowUpPhase.prepareInvite:
        return '看起來還沒邀她見面，可以試「準備邀約」';
      case CoachFollowUpPhase.preDateReminder:
        return '看起來最近聊到見面，可以試「約會前提醒」';
      case CoachFollowUpPhase.postDateReflection:
        return '剛見完面？來「約會後復盤」回想一下';
      case CoachFollowUpPhase.openCoach:
        return null;
    }
  }

  Future<void> _onChipTap(CoachFollowUpPhase phase) async {
    await _openPhase(phase);
  }

  Future<void> _onOpenCoachTap() async {
    await _openPhase(CoachFollowUpPhase.openCoach);
  }

  Future<void> _openPhase(CoachFollowUpPhase phase) async {
    final prior = _priorPhase();
    final hadResult = _displayedResult != null;
    if (prior != null && prior != phase) {
      _emit(CoachFollowUpPhaseSwitchedEvent(
        fromPhase: prior,
        toPhase: phase,
        hadResultBefore: hadResult,
      ));
    }
    setState(() => _selectedPhase = phase);
    await _openInputSheet(phase);
  }

  Future<void> _openInputSheet(CoachFollowUpPhase phase) async {
    final answers = await showCoachFollowUpInputSheet(
      context: context,
      phase: phase,
    );
    if (answers == null) return;
    if (!mounted) return;
    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: 'Coach 跟進',
    );
    if (!consented || !mounted) return;

    _emit(CoachFollowUpInvokedEvent(
      phase: phase,
      hasOptionalText: answers.q3 != null && answers.q3!.isNotEmpty,
    ));

    final notifier = ref.read(
      coachFollowUpControllerProvider(widget.partnerId).notifier,
    );
    await notifier.generate(phase: phase, answers: answers);

    if (!mounted) return;
    setState(() {
      _lastPhase = phase;
      _lastAnswers = answers;
      _lastGeneratedAt = DateTime.now();
      _showSwitcher = false;
      _selectedPhase = null;
    });
  }

  Future<void> _onRegenerate() async {
    final phase = _lastPhase;
    final answers = _lastAnswers;
    if (phase == null || answers == null) return;
    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: 'Coach 跟進',
    );
    if (!consented || !mounted) return;
    final since = _lastGeneratedAt != null
        ? DateTime.now().difference(_lastGeneratedAt!)
        : Duration.zero;
    _emit(CoachFollowUpRegeneratedEvent(phase: phase, sinceLast: since));

    final notifier = ref.read(
      coachFollowUpControllerProvider(widget.partnerId).notifier,
    );
    // Fire-and-forget: the listen callback updates _displayedResult on
    // success; controller debounces re-entry while in-flight.
    notifier.regenerate(phase: phase, answers: answers).then((_) {
      if (!mounted) return;
      setState(() => _lastGeneratedAt = DateTime.now());
    });
  }

  void _onSwitch() {
    setState(() {
      _showSwitcher = true;
      _selectedPhase = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Successful generate transitions from any state (loading / data) end
    // up here — pin the new result so the result card swaps in atomically.
    ref.listen<AsyncValue<CoachFollowUpResult?>>(
      coachFollowUpControllerProvider(widget.partnerId),
      (prev, next) {
        next.whenOrNull(
          data: (v) {
            if (!mounted) return;
            if (v == null) return; // initial empty hydrate — already null
            setState(() => _displayedResult = v);
          },
          error: (error, _) {
            if (error is QuotaExceededException) {
              _openQuotaPaywallOnce();
            }
          },
        );
      },
    );

    final controllerState = ref.watch(
      coachFollowUpControllerProvider(widget.partnerId),
    );
    final hint = ref.watch(coachFollowUpHintProvider(widget.partnerId));
    final isLoading = controllerState.isLoading;
    final error = controllerState.whenOrNull(error: (e, _) => e);

    final showWithResult = _displayedResult != null && !_showSwitcher;
    if (showWithResult) {
      return _buildWithResult(_displayedResult!, isLoading, error);
    }
    return _buildDefault(hint, isLoading, error);
  }

  Widget _buildDefault(
    CoachFollowUpPhase? hinted,
    bool isLoading,
    Object? error,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '教練跟進',
          style: AppTypography.titleSmall.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '想練什麼？選一個情境，AI 幫你拆解下一步',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        CoachFollowUpChipRow(
          selectedPhase: _selectedPhase,
          hintedPhase: hinted,
          hintText: _hintTextFor(hinted),
          isLoading: isLoading,
          onPhaseSelected: _onChipTap,
        ),
        const SizedBox(height: 12),
        _OpenCoachEntry(
          key: widget.openCoachEntryAnchorKey,
          isLoading: isLoading,
          onTap: _onOpenCoachTap,
        ),
        if (isLoading) ...[
          const SizedBox(height: 10),
          _StatusText.loading(),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          _StatusText.error(error),
        ],
      ],
    );
  }

  Widget _buildWithResult(
    CoachFollowUpResult result,
    bool isLoading,
    Object? error,
  ) {
    final canRegenerate =
        !isLoading && _lastPhase != null && _lastAnswers != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '教練跟進',
          style: AppTypography.titleSmall.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        CoachFollowUpResultCard(result: result),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: canRegenerate ? _onRegenerate : null,
                child: const Text('重新生成'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: isLoading ? null : _onSwitch,
                child: const Text('換情境'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'ⓘ 重新生成會再扣 1 則額度',
          style: AppTypography.caption.copyWith(
            color: AppColors.glassTextSecondary,
          ),
        ),
        if (isLoading) ...[
          const SizedBox(height: 10),
          _StatusText.loading(),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          _StatusText.error(error),
        ],
      ],
    );
  }
}

class _StatusText extends StatelessWidget {
  final String text;
  final Color color;
  final bool isLoading;

  const _StatusText._({
    required this.text,
    required this.color,
    this.isLoading = false,
  });

  factory _StatusText.loading() => const _StatusText._(
        text: '正在產生跟進建議...',
        color: AppColors.ctaStart,
        isLoading: true,
      );

  factory _StatusText.error(Object error) {
    final message = switch (error) {
      QuotaExceededException() => '今天的額度已用完，明天再試或調整方案',
      GenerationFailedException() => '這次沒有產生可用建議，未扣額度，請再試一次',
      ApiException() => '目前無法送出，請稍後再試',
      _ => '目前無法產生建議，請稍後再試',
    };
    return _StatusText._(
      text: message,
      color: AppColors.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: AppTypography.bodyMedium.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
    );

    if (!isLoading) {
      return label;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: label),
        ],
      ),
    );
  }
}

class _OpenCoachEntry extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _OpenCoachEntry({
    super.key,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: isLoading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 18,
              color: AppColors.glassTextSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '或直接問教練一個問題...',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.glassTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

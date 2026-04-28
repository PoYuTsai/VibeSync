import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers/partner_write_controller.dart';
import '../../domain/entities/partner.dart';
import '../dialogs/partner_merge_confirm_dialog.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_picker_sheet.dart';

/// Merge picker screen — `/partner/:partnerId/merge[?target=...]`.
///
/// Phase 3 (PR-B): hosts [PartnerPickerSheet] excluding the source partner;
/// row tap → confirm dialog → merge controller.
///
/// Phase 4 Task 4 (Codex spec patch §7.5 + plan patch P2): supports an
/// optional `initialTargetId` (route reads `?target=` query param). Two modes:
///
/// 1. `initialTargetId == null` OR doesn't match an owner-scoped candidate:
///    behaviour is **identical** to PR-B (row tap → confirm dialog).
/// 2. valid preselect: target row highlighted, bottom CTA "確認合併到 X"
///    opens the confirm dialog. Tapping a different row swaps the preselect
///    (no auto-open of destructive flow).
///
/// **Owner-scoping (Codex spec patch §6)**: validation goes through
/// `partnerListProvider` candidates (after excluding `fromPartnerId`), NOT
/// `partnerByIdProvider` (which is a raw repo lookup not bound to the
/// current owner — would otherwise leak cross-account targets).
///
/// **Once-flag (Codex plan patch P2)**: `_didApplyInitialTarget` ensures the
/// initial preselect resolves exactly once — subsequent rebuilds don't reset
/// the user's row-tap-to-switch choice.
class PartnerMergePickerScreen extends ConsumerStatefulWidget {
  final String fromPartnerId;
  final String? initialTargetId;

  const PartnerMergePickerScreen({
    super.key,
    required this.fromPartnerId,
    this.initialTargetId,
  });

  @override
  ConsumerState<PartnerMergePickerScreen> createState() =>
      _PartnerMergePickerScreenState();
}

class _PartnerMergePickerScreenState
    extends ConsumerState<PartnerMergePickerScreen> {
  Partner? _selectedTarget;
  bool _didApplyInitialTarget = false;

  Partner? _initialTargetFromCandidates(List<Partner> candidates) {
    final id = widget.initialTargetId;
    if (id == null) return null;
    for (final p in candidates) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref
        .watch(partnerListProvider)
        .where((p) => p.id != widget.fromPartnerId)
        .toList(growable: false);

    if (!_didApplyInitialTarget) {
      _selectedTarget = _initialTargetFromCandidates(candidates);
      _didApplyInitialTarget = true;
    }

    final hasPreselect = _selectedTarget != null;

    return Scaffold(
      appBar: AppBar(title: const Text('選擇要合併到的對象')),
      body: PartnerPickerSheet(
        excludeId: widget.fromPartnerId,
        // In preselect mode we route taps through onSelectedChanged
        // (tap-to-switch, no auto-open). Otherwise the PR-B onSelected
        // contract stays untouched.
        onSelected: hasPreselect ? null : (target) => _confirm(target),
        onSelectedChanged:
            hasPreselect ? (p) => setState(() => _selectedTarget = p) : null,
        selectedId: _selectedTarget?.id,
      ),
      bottomNavigationBar: hasPreselect
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _confirm(_selectedTarget!),
                    child: Text('確認合併到 ${_selectedTarget!.name}'),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _confirm(Partner target) async {
    final fromPartner = ref.read(partnerByIdProvider(widget.fromPartnerId));
    if (fromPartner == null) return;
    final fromAgg = ref.read(partnerAggregateProvider(widget.fromPartnerId));
    final convCount =
        ref.read(conversationsByPartnerProvider(widget.fromPartnerId)).length;
    final traitCount = fromAgg.unionTraits.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => PartnerMergeConfirmDialog(
        fromName: fromPartner.name,
        toName: target.name,
        conversationCount: convCount,
        traitCount: traitCount,
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(partnerWriteControllerProvider.notifier)
          .merge(fromId: widget.fromPartnerId, toId: target.id);
      if (mounted) context.go('/partner/${target.id}');
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('PartnerMergePickerScreen merge failed: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('合併失敗，請稍後再試')),
      );
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers/partner_write_controller.dart';
import '../../domain/entities/partner.dart';
import '../dialogs/partner_merge_confirm_dialog.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_picker_sheet.dart';

/// Merge picker screen — `/partner/:partnerId/merge`.
///
/// Hosts [PartnerPickerSheet] excluding the source partner. On selection,
/// shows [PartnerMergeConfirmDialog] (D-variant: N 對話 + M traits + 紅字
/// 不可逆), then awaits [PartnerWriteController.merge]. Successful merge
/// navigates to the merged-into partner's detail; failure shows a SnackBar
/// and stays on the picker so the user can retry or cancel.
class PartnerMergePickerScreen extends ConsumerWidget {
  final String fromPartnerId;
  const PartnerMergePickerScreen({super.key, required this.fromPartnerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('選擇要合併到的對象')),
      body: PartnerPickerSheet(
        excludeId: fromPartnerId,
        onSelected: (target) => _confirm(context, ref, target),
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    Partner target,
  ) async {
    final fromPartner = ref.read(partnerByIdProvider(fromPartnerId));
    if (fromPartner == null) return;
    final fromAgg = ref.read(partnerAggregateProvider(fromPartnerId));
    final convCount =
        ref.read(conversationsByPartnerProvider(fromPartnerId)).length;
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
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(partnerWriteControllerProvider.notifier)
          .merge(fromId: fromPartnerId, toId: target.id);
      if (context.mounted) context.go('/partner/${target.id}');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('合併失敗，請稍後再試')),
      );
    }
  }
}

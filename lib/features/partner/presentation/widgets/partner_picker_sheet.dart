import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/partner.dart';
import '../providers/partner_providers.dart';

/// Reusable partner picker. Used by:
/// - Task 12 merge picker (excludeId = self)
/// - Task 13 conversation reassign (excludeId = current partnerId)
///
/// Phase 3 design doc §5 originally proposed `showCreateNewAction` to inline-add
/// a Partner from the picker. PR-B ships **without** that action — see PR-B
/// plan §"Reality Check — Design Doc §5 Deviation". The empty state shows a
/// hint pointing the user to the home Partner list.
///
/// Phase 4 Task 4 adds two optional named params:
/// - [selectedId] — when non-null, that row renders highlighted (preselect
///   visual cue used by the merge picker `?target=` flow).
/// - [onSelectedChanged] — when non-null, row taps invoke this callback
///   instead of [onSelected]. This is the "tap-to-switch preselect, no
///   auto-open destructive dialog" contract from Codex spec patch §7.5.
///
/// Mode resolution: if [onSelectedChanged] is non-null the sheet is in
/// preselect mode; tapping a row routes the Partner through that callback.
/// Otherwise (PR-B path) row taps fire [onSelected] as before.
class PartnerPickerSheet extends ConsumerStatefulWidget {
  final String? excludeId;
  final void Function(Partner)? onSelected;
  final String? selectedId;
  final void Function(Partner)? onSelectedChanged;

  const PartnerPickerSheet({
    super.key,
    this.excludeId,
    this.onSelected,
    this.selectedId,
    this.onSelectedChanged,
  });

  @override
  ConsumerState<PartnerPickerSheet> createState() => _PartnerPickerSheetState();
}

class _PartnerPickerSheetState extends ConsumerState<PartnerPickerSheet> {
  final _filterCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(partnerListProvider);
    final candidates = all
        .where((p) => p.id != widget.excludeId)
        .where((p) =>
            _query.isEmpty ||
            p.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _filterCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜尋對象名稱',
            ),
            onChanged: (s) => setState(() => _query = s),
          ),
        ),
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '尚無其他對象，先回首頁建立後再操作',
              textAlign: TextAlign.center,
            ),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in candidates)
                  Material(
                    color: p.id == widget.selectedId
                        ? AppColors.glassBorder
                        : Colors.transparent,
                    child: ListTile(
                      title: Text(p.name),
                      trailing: p.id == widget.selectedId
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        // Preselect mode: route through onSelectedChanged so
                        // the host can swap preselect WITHOUT opening the
                        // destructive confirm dialog.
                        if (widget.onSelectedChanged != null) {
                          widget.onSelectedChanged!(p);
                        } else {
                          widget.onSelected?.call(p);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

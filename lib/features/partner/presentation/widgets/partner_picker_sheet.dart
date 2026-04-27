import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class PartnerPickerSheet extends ConsumerStatefulWidget {
  final String? excludeId;
  final void Function(Partner)? onSelected;

  const PartnerPickerSheet({
    super.key,
    this.excludeId,
    this.onSelected,
  });

  @override
  ConsumerState<PartnerPickerSheet> createState() =>
      _PartnerPickerSheetState();
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
                  ListTile(
                    title: Text(p.name),
                    onTap: () => widget.onSelected?.call(p),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

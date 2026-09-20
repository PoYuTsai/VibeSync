import 'package:flutter/material.dart';
import '../../../../core/services/app_haptics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/local_avatar.dart';
import '../../../../shared/widgets/brand/opener_home_components.dart';

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
  final bool openerStyle;

  const PartnerPickerSheet({
    super.key,
    this.excludeId,
    this.onSelected,
    this.selectedId,
    this.onSelectedChanged,
    this.openerStyle = false,
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
        if (widget.openerStyle)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(children: [
                const Expanded(
                    child: Text('選擇聊天對象', style: OpenerHomeStyle.title)),
                IconButton(
                    tooltip: '關閉選擇對象',
                    onPressed: AppHaptics.onPress(() => Navigator.pop(context)),
                    icon: const Icon(Icons.close, color: OpenerHomeStyle.icon)),
              ])),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _filterCtrl,
            style: widget.openerStyle
                ? const TextStyle(fontSize: 15, color: Colors.white)
                : null,
            decoration: widget.openerStyle
                ? OpenerHomeStyle.field('搜尋對象名稱').copyWith(
                    prefixIcon: const Icon(Icons.search,
                        color: OpenerHomeStyle.secondary))
                : const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜尋對象名稱',
                  ),
            onChanged: (s) => setState(() => _query = s),
          ),
        ),
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              widget.openerStyle && _query.isNotEmpty
                  ? '找不到符合的對象，試試其他名字'
                  : '尚無其他對象，先回首頁建立後再操作',
              textAlign: TextAlign.center,
              style: widget.openerStyle ? OpenerHomeStyle.body : null,
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
                        ? widget.openerStyle
                            ? OpenerHomeStyle.selected
                            : AppColors.glassBorder
                        : Colors.transparent,
                    child: ListTile(
                      minTileHeight: widget.openerStyle ? 64 : null,
                      selected: p.id == widget.selectedId,
                      selectedColor:
                          widget.openerStyle ? OpenerHomeStyle.accent : null,
                      leading: widget.openerStyle
                          ? ClipOval(
                              child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: LocalAvatar(
                                      path: p.avatarPath,
                                      fallback: const Icon(Icons.person_outline,
                                          color: OpenerHomeStyle.icon))))
                          : null,
                      title: Text(p.name,
                          style: widget.openerStyle
                              ? const TextStyle(
                                  fontSize: 15, color: Colors.white)
                              : null),
                      trailing: p.id == widget.selectedId
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        if (widget.openerStyle) AppHaptics.tap();
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

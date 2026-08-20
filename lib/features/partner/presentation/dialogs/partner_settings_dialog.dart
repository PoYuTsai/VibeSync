import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand/brand_dialog.dart';
import '../../../../core/services/app_haptics.dart';
import '../../domain/services/partner_memory_tag_catalog.dart';
import '../widgets/partner_memory_chip_picker.dart';

class PartnerSettingsResult {
  final String name;
  final String note;

  const PartnerSettingsResult({
    required this.name,
    required this.note,
  });
}

/// Centralized partner settings.
///
/// 2026-08-19 Eric 拍板：備註**手填整個關掉，只能選 chips**。自由文字讓
/// 模型分不清主詞（「想約出來見面」是他還是她），prompt 層修三刀都在
/// 對抗被污染的資料；改成 chips-only 後，資料保證全是「描述她」。
/// 2026-08-20 再收口：catalog 搬到 domain，新增對象與所有 AI 消費端共用；
/// 關係進度／回覆狀態不屬於「關於她」。底層維持 schema-light：`note`
/// 欄位不動，只由 chips 用「、」串成。舊自由文字保留在本機，但 AI 邊界
/// fail closed；一旦動 chips，就以當前選取重建並清掉舊污染句。
class PartnerSettingsDialog extends StatefulWidget {
  final String initialName;
  final String initialNote;

  const PartnerSettingsDialog({
    super.key,
    required this.initialName,
    this.initialNote = '',
  });

  @override
  State<PartnerSettingsDialog> createState() => _PartnerSettingsDialogState();
}

class _PartnerSettingsDialogState extends State<PartnerSettingsDialog> {
  late final TextEditingController _nameController;
  late Set<String> _selected;
  bool _chipsTouched = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    // Catalog 同時負責舊 chips 別名與 merge 前綴；自由文字不會被猜成 tag。
    _selected = PartnerMemoryTagCatalog.parse(widget.initialNote);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _trimmedName => _nameController.text.trim();
  bool get _canSave => _trimmedName.isNotEmpty;

  /// chips 沒動過就保留原 note（含舊自由文字）；動過就以選取重建。
  String get _resultNote {
    if (!_chipsTouched) return widget.initialNote.trim();
    return PartnerMemoryTagCatalog.serialize(_selected);
  }

  void _updateTags(Set<String> selected) {
    setState(() {
      _chipsTouched = true;
      _selected = selected;
    });
  }

  void _onSave() {
    if (!_canSave) return;

    final nameUnchanged = _trimmedName == widget.initialName.trim();
    final noteUnchanged = _resultNote == widget.initialNote.trim();
    if (nameUnchanged && noteUnchanged) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pop(
      PartnerSettingsResult(
        name: _trimmedName,
        note: _resultNote,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fieldLabelStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppColors.glassTextPrimary,
          fontWeight: FontWeight.w600,
        );

    return BrandAlertDialog(
      title: const Text('對象設定'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('名稱', style: fieldLabelStyle),
            const SizedBox(height: 6),
            TextField(
              style: const TextStyle(color: AppColors.glassTextPrimary),
              controller: _nameController,
              autofocus: widget.initialName.isEmpty,
              decoration: const InputDecoration(
                hintText: '例如：小雲',
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text('關於她', style: fieldLabelStyle),
            const SizedBox(height: 4),
            Text(
              '只選你確定的資料；關係進度與回覆狀態會由聊天分析更新。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.glassTextSecondary,
                    height: 1.35,
                  ),
            ),
            if (PartnerMemoryTagCatalog.hasUnrecognizedContent(
              widget.initialNote,
            )) ...[
              const SizedBox(height: 6),
              Text(
                '舊版背景目前不會提供給 AI；重新選擇任一項並儲存後，舊內容會被清除。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.ctaStart,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            PartnerMemoryChipPicker(
              selected: _selected,
              onChanged: _updateTags,
            ),
            Text(
              '儲存後立即生效：教練和下一次分析都會帶上這些背景，不需要每次重填。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.glassTextSecondary,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: AppHaptics.onPress(_canSave ? _onSave : null),
          child: const Text('儲存'),
        ),
      ],
    );
  }
}

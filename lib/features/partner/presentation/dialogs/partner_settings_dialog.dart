import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand/brand_dialog.dart';
import '../../../../core/services/app_haptics.dart';
import '../../../../shared/widgets/pressable_scale.dart';

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
/// 底層維持 schema-light：`note` 欄位不動（Hive/Edge 零改），只由選中
/// 的 chips 用「、」串成存入。舊資料的自由文字：使用者沒動過 chips 就
/// 原樣保留；一旦動了 chips，note 以當前選取重建（舊污染句就此清掉，
/// 這是刻意的資料清洗，不是 bug）。
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
  late final Set<String> _selected;
  bool _chipsTouched = false;

  /// 主詞契約（2026-08-19 Eric 拍板）：這個彈窗填的是對象，三類 chips
  /// 一律以**對方**為主詞（特質＝個性、狀態＝互動現況、喜好＝她的興趣
  /// ＝開場鉤子燃料）。用戶自己的目標不進這裡。
  static const Map<String, List<String>> _quickTagGroups = {
    '特質': ['慢熱', '外向健談', '幽默愛鬧', '工作忙碌'],
    '狀態': ['剛認識', '回覆慢但都會回', '不太主動但有回', '聊得來但還沒約'],
    '喜好': ['喜歡戶外', '愛喝咖啡', '吃貨', '有在健身', '愛看劇'],
  };

  static final Set<String> _allTags =
      _quickTagGroups.values.expand((tags) => tags).toSet();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    // 從既有 note 還原選取：只認得 chip 片語，其餘（舊自由文字）不進
    // 選取集。
    _selected = widget.initialNote
        .split('、')
        .map((s) => s.trim())
        .where(_allTags.contains)
        .toSet();
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
    return [
      for (final tags in _quickTagGroups.values)
        for (final tag in tags)
          if (_selected.contains(tag)) tag,
    ].join('、');
  }

  void _toggleTag(String tag) {
    setState(() {
      _chipsTouched = true;
      if (!_selected.remove(tag)) _selected.add(tag);
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
            Text('她是怎樣的人', style: fieldLabelStyle),
            const SizedBox(height: 8),
            for (final entry in _quickTagGroups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      entry.key,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.glassTextSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final tag in entry.value) ...[
                              _QuickTagChip(
                                label: tag,
                                inserted: _selected.contains(tag),
                                onTap: () => _toggleTag(tag),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 2),
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

/// 選取 chip：點一下選、再點取消。選取語言對標「關於我」
/// ProfileChipSection：未選＝中性細框次要字；已選＝ctaStart 橘框＋
/// 橘粗體＋淡橘底。不加勾勾 icon——選中靠色差與字重表達（勾勾殘影
/// 與寬度跳動是已登記坑）。
class _QuickTagChip extends StatelessWidget {
  const _QuickTagChip({
    required this.label,
    required this.inserted,
    required this.onTap,
  });

  final String label;
  final bool inserted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // PressableScale 自帶放開觸覺（tap），不再包 AppHaptics.onPress——會雙震。
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: inserted
                ? AppColors.ctaStart.withValues(alpha: 0.14)
                : AppColors.glassTextPrimary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: inserted
                  ? AppColors.ctaStart.withValues(alpha: 0.64)
                  : AppColors.glassTextSecondary.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: inserted
                      ? AppColors.ctaStart
                      : AppColors.glassTextSecondary,
                  fontWeight: inserted ? FontWeight.w800 : FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}

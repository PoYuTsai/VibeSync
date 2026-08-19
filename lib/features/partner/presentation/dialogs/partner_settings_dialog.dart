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

/// Centralized partner settings for one-time context.
///
/// Keep this schema-light for Spec 6D v1: the free-form note is where users
/// can record "where we met / current goal / traits" until we intentionally
/// add separate Hive fields.
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
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _noteController = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String get _trimmedName => _nameController.text.trim();
  String get _trimmedNote => _noteController.text.trim();
  bool get _canSave => _trimmedName.isNotEmpty;

  /// 快速插入 chips（2026-08-19 Bruce dogfood：只有空白文字框不知道要填什
  /// 麼，要幾個可 Tag 的 default 選項）。維持 schema-light：chip 只是把片
  /// 語塞進備註文字，真相源仍是這串自由文字，使用者可任意改寫。
  ///
  /// 呈現（Eric 拍板）：dialog 空間小，分類分三行、小標固定在行首、chips
  /// 各自橫向滑動——三類同時可見不藏選項，行尾被切掉的 chip 就是
  /// 「還能滑」的暗示。
  ///
  /// 主詞契約（2026-08-19 Eric 拍板，Bruce dogfood 抓到「想約出來見面」
  /// 被 AI 當成她的意願）：這個彈窗填的是對象，chips 一律以**對方**為
  /// 主詞。原「目標」行（用戶自己的目標）退場改「喜好」（她的興趣＝
  /// 開場鉤子燃料）；用戶目標想寫就打進備註，prompt 端有主詞判斷接住。
  static const Map<String, List<String>> _quickTagGroups = {
    '特質': ['慢熱', '外向健談', '幽默愛鬧', '工作忙碌'],
    '狀態': ['剛認識', '回覆慢但都會回', '不太主動但有回', '聊得來但還沒約'],
    '喜好': ['喜歡戶外', '愛喝咖啡', '吃貨', '有在健身', '愛看劇'],
  };

  bool _tagInserted(String tag) => _noteController.text.contains(tag);

  void _insertTag(String tag) {
    final current = _noteController.text.trimRight();
    final next = current.isEmpty ? tag : '$current、$tag';
    if (next.length > 300) return; // 尊重欄位 maxLength，塞不下就不塞。
    _noteController.text = next;
    _noteController.selection =
        TextSelection.collapsed(offset: next.length);
    setState(() {});
  }

  void _onSave() {
    if (!_canSave) return;

    final nameUnchanged = _trimmedName == widget.initialName.trim();
    final noteUnchanged = _trimmedNote == widget.initialNote.trim();
    if (nameUnchanged && noteUnchanged) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pop(
      PartnerSettingsResult(
        name: _trimmedName,
        note: _trimmedNote,
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
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '例如：小雲',
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 12),
            Text('一次性資訊 / 目前目標 / 備註', style: fieldLabelStyle),
            const SizedBox(height: 6),
            // 2026-08-19 Eric 真機回報：4 行起跳＋字數計數列把 chips 全推到
            // 折線下，「根本不知道要往下滑」。備註欄改 2 行起跳（打滿 4 行後
            // 內部捲動）、藏計數列、hint 縮成一行——chips 本身就是範例，
            // 長 hint 是重複資訊。目標：鍵盤開著時三行 chips 進首屏。
            TextField(
              style: const TextStyle(color: AppColors.glassTextPrimary),
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '自由填，或點下方快速選項',
                counterText: '',
              ),
            ),
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
                                inserted: _tagInserted(tag),
                                onTap: () => _insertTag(tag),
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

/// 備註快速插入 chip：點一下把片語附加進備註文字。已插入（備註內含同
/// 片語）就轉為淡化打勾態，避免重複塞；使用者改寫文字後自動恢復可點。
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
    final color = inserted
        ? AppColors.glassTextSecondary
        // 🍊 ctaStart 對齊「關於我」chips 與本彈窗取消/儲存的品牌橘。
        : AppColors.ctaStart;
    // PressableScale 自帶放開觸覺（tap），不再包 AppHaptics.onPress——會雙震。
    return PressableScale(
      enabled: !inserted,
      child: InkWell(
        onTap: inserted ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: inserted ? 0.06 : 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (inserted) ...[
                Icon(Icons.check_rounded, size: 13, color: color),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

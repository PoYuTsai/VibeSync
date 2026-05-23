import 'package:flutter/material.dart';

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
          fontWeight: FontWeight.w600,
        );

    return AlertDialog(
      title: const Text('對象設定'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('名稱', style: fieldLabelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '例如：小雲',
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 16),
            Text('一次性資訊 / 目前目標 / 備註', style: fieldLabelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              minLines: 4,
              maxLines: 7,
              maxLength: 300,
              decoration: const InputDecoration(
                hintText: '例如：在 Bumble 認識、慢熱、喜歡戶外活動，目前想先約咖啡。',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '這裡會成為教練理解這個人的長期背景，不需要每次補聊天時重填。',
              style: Theme.of(context).textTheme.bodySmall,
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
          onPressed: _canSave ? _onSave : null,
          child: const Text('儲存'),
        ),
      ],
    );
  }
}

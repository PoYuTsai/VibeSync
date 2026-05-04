import 'package:flutter/material.dart';

/// Pure UI dialog for editing Partner.customNote.
///
/// Returns:
/// - null on cancel / unchanged input
/// - trimmed string on save
/// - empty string on save-after-clear (caller stores null)
class PartnerNoteEditDialog extends StatefulWidget {
  final String initialNote;

  const PartnerNoteEditDialog({super.key, this.initialNote = ''});

  @override
  State<PartnerNoteEditDialog> createState() => _PartnerNoteEditDialogState();
}

class _PartnerNoteEditDialogState extends State<PartnerNoteEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _trimmed => _controller.text.trim();

  void _onSave() {
    final trimmed = _trimmed;
    if (trimmed == widget.initialNote.trim()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('設定對方資訊'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 5,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: '對方特質 / 備註',
          hintText: '例如：慢熱、喜歡戶外活動、對星座有興趣',
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _onSave,
          child: const Text('儲存'),
        ),
      ],
    );
  }
}

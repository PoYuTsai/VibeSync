import 'package:flutter/material.dart';

/// Single-field rename dialog for a Partner. Pure UI — pops via
/// `Navigator.pop`:
///   - cancel / barrier dismiss → null
///   - save with unchanged trimmed name → null (caller treats as no-op)
///   - save with new trimmed name → that string
///
/// Caller (e.g. PartnerDetailScreen) decides what to do with the result;
/// the dialog itself never touches the repository or write controller.
class PartnerEditDialog extends StatefulWidget {
  final String initialName;

  const PartnerEditDialog({super.key, required this.initialName});

  @override
  State<PartnerEditDialog> createState() => _PartnerEditDialogState();
}

class _PartnerEditDialogState extends State<PartnerEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _trimmed => _controller.text.trim();
  bool get _canSave => _trimmed.isNotEmpty;

  void _onSave() {
    if (!_canSave) return;
    final trimmed = _trimmed;
    // Unchanged → no-op for caller.
    if (trimmed == widget.initialName.trim()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('編輯對象'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名稱'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _onSave(),
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

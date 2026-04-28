import 'package:flutter/material.dart';

/// Destructive confirm dialog for deleting a single conversation under a Partner.
///
/// Pure UI — returns `bool` via `Navigator.pop`. Caller awaits and decides
/// whether to invoke `ConversationWriteController.delete`.
/// Barrier dismiss returns `null`, treated as cancel.
class DeleteConversationConfirmDialog extends StatelessWidget {
  final String dateLabel;
  final int messageCount;

  const DeleteConversationConfirmDialog({
    super.key,
    required this.dateLabel,
    required this.messageCount,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('刪除這段互動紀錄？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$dateLabel · $messageCount 則訊息將被永久刪除。',
          ),
          const SizedBox(height: 12),
          Text(
            '⚠️ 此操作不可復原',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('確認刪除'),
        ),
      ],
    );
  }
}

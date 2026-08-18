import 'package:flutter/material.dart';

import '../../../../shared/widgets/brand/brand_dialog.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/services/app_haptics.dart';

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
    return BrandAlertDialog(
      title: const Text('刪除這段互動紀錄？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$dateLabel · $messageCount 則訊息會永久刪除',
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TablerIcons.alert_triangle,
                  size: 15, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 5),
              Text(
                '此操作不可復原',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
          onPressed: AppHaptics.onPress(() => Navigator.of(context).pop(true)),
          child: const Text('確認刪除'),
        ),
      ],
    );
  }
}

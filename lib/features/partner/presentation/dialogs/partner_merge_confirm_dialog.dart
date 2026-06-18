import 'package:flutter/material.dart';

import '../../../../shared/widgets/brand/brand_dialog.dart';

/// D-variant confirm dialog per Phase 3 design doc §3:
/// - N 對話搬遷 + M traits 聯集（具象 metric，避免抽象 wording）
/// - 紅字「⚠️ 此操作不可復原」（destructive 心理安全感）
/// - 「保留 B avatar」隱含於選 B；dialog 不再贅述
///
/// Pure UI — returns `bool` via `Navigator.pop`. Caller (merge picker screen)
/// awaits and decides whether to invoke `PartnerWriteController.merge`.
/// Barrier dismiss returns `null`, treated as cancel.
class PartnerMergeConfirmDialog extends StatelessWidget {
  final String fromName;
  final String toName;
  final int conversationCount;
  final int traitCount;

  const PartnerMergeConfirmDialog({
    super.key,
    required this.fromName,
    required this.toName,
    required this.conversationCount,
    required this.traitCount,
  });

  @override
  Widget build(BuildContext context) {
    return BrandAlertDialog(
      title: Text('將 $fromName 合併到 $toName？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('最後會留下：$toName'),
          const SizedBox(height: 4),
          Text('會被移除：$fromName'),
          const SizedBox(height: 8),
          Text(
            '$fromName 裡面的互動紀錄和特質會全部移到 $toName，'
            '這是整理同一個人的重複對象卡，不是接續某一段聊天',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '請確認這兩張卡真的是同一個人',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Text('$conversationCount 段互動紀錄將搬遷'),
          const SizedBox(height: 4),
          Text('$traitCount 個特質會保留'),
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
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('確認合併'),
        ),
      ],
    );
  }
}

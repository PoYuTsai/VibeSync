import 'package:flutter/material.dart';

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
    return AlertDialog(
      title: Text('將 $fromName 合併到 $toName？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('保留：$toName'),
          const SizedBox(height: 4),
          Text('移除：$fromName'),
          const SizedBox(height: 8),
          Text(
            '$fromName 底下的互動紀錄與特質會搬到 $toName。'
            '這會整合整個對象卡，不是只接續目前這段對話。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '請只在「同一個人被誤建為兩個對象」時使用。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Text('$conversationCount 對話將搬遷'),
          const SizedBox(height: 4),
          Text('$traitCount 個特質聯集保留'),
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

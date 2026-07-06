import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/brand/brand_dialog.dart';

/// 48h 跟進提醒的「軟詢問卡」。
///
/// 只在「首次綁 partner 分析完成」出現一次（呼叫端以 opt-in=unknown 把關）。
/// 回傳 `true` 代表使用者按「幫我提醒」（呼叫端接著向系統要通知權限）；
/// `false` / `null`（點外面關掉）代表「不用」，呼叫端據此落 denied，之後不再問。
Future<bool?> showSoftOptInCard(
  BuildContext context, {
  required String displayName,
}) {
  final name = displayName.trim().isEmpty ? '這位對象' : displayName.trim();
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => BrandAlertDialog(
      title: const Text('要我提醒你跟進嗎？👀'),
      content: Text(
        '跟$name的對話剛分析完。想要的話，我可以在 48 小時後提醒你回來看看下一步、主動出擊。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(
            '不用',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('幫我提醒'),
        ),
      ],
    ),
  );
}

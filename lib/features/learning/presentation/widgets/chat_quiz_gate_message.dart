// lib/features/learning/presentation/widgets/chat_quiz_gate_message.dart
//
// 聊天測驗共用的外框與狀態畫面（載入／錯誤／鎖住／找不到）。
//
// 為什麼不共用電子書那組：那邊的等價元件是 private，而且文案綁在「這本書」
// 的語意上。這裡只抽出三個小元件，讓答題器、關卡地圖、結果頁的狀態畫面長得
// 一樣，不必各寫一份。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

/// 測驗頁共用外框。
class ChatQuizGateScaffold extends StatelessWidget {
  const ChatQuizGateScaffold({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
  });

  final String title;
  final Widget child;

  /// 右上角的關閉鍵。`null` 時用系統返回。
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      title: title,
      actions: [
        if (onClose != null)
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            tooltip: '離開',
            color: AppColors.onBackgroundSecondary,
          ),
      ],
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: child,
      ),
    );
  }
}

/// 中性 loading。**訂閱狀態還在確認時只能用這個**，不得出現任何付費文案。
class ChatQuizGateLoading extends StatelessWidget {
  const ChatQuizGateLoading({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 有標題、說明與最多兩顆按鈕的狀態畫面。
class ChatQuizGateMessage extends StatelessWidget {
  const ChatQuizGateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: BrandSurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 34, color: AppColors.ctaStart),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              BrandPrimaryButton(label: primaryLabel, onPressed: onPrimary),
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: 10),
                BrandSecondaryButton(
                  label: secondaryLabel!,
                  onPressed: onSecondary!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

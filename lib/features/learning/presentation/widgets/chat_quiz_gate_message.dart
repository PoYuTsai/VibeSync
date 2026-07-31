// lib/features/learning/presentation/widgets/chat_quiz_gate_message.dart
//
// 聊天測驗共用的外框與狀態畫面（載入／錯誤／鎖住／找不到）。
//
// 為什麼不共用電子書那組：那邊的等價元件是 private，而且文案綁在「這本書」
// 的語意上。這裡只抽出三個小元件，讓答題器、關卡地圖、結果頁的狀態畫面長得
// 一樣，不必各寫一份。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

/// 測驗頁共用外框。
///
/// 返回鍵**一律顯式提供**，不靠 AppBar 的 `automaticallyImplyLeading`：
/// 那個只有在有東西可 pop 時才出現，deep link 或 tab 直接切進來時整頁就沒有
/// 出口了。同一套寫法見 `ebook_detail_screen.dart` / `ebook_reader_screen.dart`。
class ChatQuizGateScaffold extends StatelessWidget {
  const ChatQuizGateScaffold({
    super.key,
    required this.title,
    required this.child,
    this.fallbackLocation = '/?tab=learning',
  });

  final String title;
  final Widget child;

  /// 沒有可 pop 的 route 時退回哪裡（deep link 進來的情況）。
  /// 答題器與結果頁退回關卡地圖，關卡地圖退回學習頁。
  final String fallbackLocation;

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      title: title,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '返回',
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(fallbackLocation);
          }
        },
      ),
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

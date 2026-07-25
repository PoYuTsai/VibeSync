// lib/features/learning/presentation/widgets/ebook_access_gate.dart
//
// 電子書付費閘門。
//
// 硬規則：
//   - Book 1（access == free）永不鎖。
//   - Books 2–4 只有在訂閱狀態「已確認且為付費」時才建立 child——
//     這是防止付費內容在 post-frame redirect 之前閃現的關鍵。
//   - 訂閱狀態還在確認 → 只顯示 loading，不導 paywall、也不顯示內容。
//   - 訂閱狀態無法確認（error）→ 顯示可重試錯誤，不把技術錯誤包裝成 Free upsell。
//   - Catalog 找不到這本書 → 顯示「找不到這本書」，不導 paywall。
//   - 完全不讀文章 daily quota；電子書不消耗文章額度。
//
// 注意：四份 JSON 隨 App bundle 發布，這不是 server-side DRM。這道閘門保護
// 正常 App 體驗，不宣稱能防止解包資產。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../domain/models/ebook.dart';

/// 付費閘門需要的訂閱切片。刻意只留三個 bool，讓判斷成為純函式，
/// 也讓測試不必啟動 RevenueCat／Supabase。
class EbookSubscriptionAccess {
  const EbookSubscriptionAccess({
    required this.isPremium,
    required this.isResolving,
    required this.hasError,
  });

  const EbookSubscriptionAccess.premium()
      : isPremium = true,
        isResolving = false,
        hasError = false;

  const EbookSubscriptionAccess.free()
      : isPremium = false,
        isResolving = false,
        hasError = false;

  const EbookSubscriptionAccess.resolving()
      : isPremium = false,
        isResolving = true,
        hasError = false;

  const EbookSubscriptionAccess.unavailable()
      : isPremium = false,
        isResolving = false,
        hasError = true;

  /// Starter 與 Essential 都算 premium（`SubscriptionState.isPremium`）。
  factory EbookSubscriptionAccess.fromState(SubscriptionState state) {
    return EbookSubscriptionAccess(
      isPremium: state.isPremium,
      isResolving: state.isLoading,
      hasError: state.error != null,
    );
  }

  final bool isPremium;
  final bool isResolving;
  final bool hasError;
}

enum EbookAccessDecision {
  /// 可以建立內容。
  allowed,

  /// 已確認是免費使用者且這本要訂閱 → 導 paywall。
  locked,

  /// 訂閱狀態還在確認 → 只顯示 loading。
  resolving,

  /// 訂閱狀態無法確認 → 顯示可重試錯誤。
  unavailable,
}

/// 純函式權限判斷。不讀文章 quota、不讀 tier 字串細節。
EbookAccessDecision ebookAccessFor(
  Ebook book,
  EbookSubscriptionAccess subscription,
) {
  if (book.access == EbookAccess.free) return EbookAccessDecision.allowed;
  if (subscription.isPremium) return EbookAccessDecision.allowed;
  // 已知是付費書、且還沒確認成付費：先不下結論。
  if (subscription.isResolving) return EbookAccessDecision.resolving;
  if (subscription.hasError) return EbookAccessDecision.unavailable;
  return EbookAccessDecision.locked;
}

/// 書架用：這本書現在要不要顯示鎖頭。
bool ebookLockedFor(Ebook book, EbookSubscriptionAccess subscription) =>
    ebookAccessFor(book, subscription) != EbookAccessDecision.allowed;

final ebookSubscriptionAccessProvider =
    Provider<EbookSubscriptionAccess>((ref) {
  return EbookSubscriptionAccess.fromState(ref.watch(subscriptionProvider));
});

/// 共用閘門。[builder] 只有在 [EbookAccessDecision.allowed] 時才會被呼叫。
class EbookAccessGate extends ConsumerStatefulWidget {
  const EbookAccessGate({
    super.key,
    required this.book,
    required this.builder,
    this.notFoundTitle = '找不到這本書',
    this.notFoundMessage = '這本電子書可能已經調整或移除了。回學習頁看看其他內容。',
  });

  /// `null` 代表 catalog 裡沒有這個 bookId。
  final Ebook? book;
  final WidgetBuilder builder;
  final String notFoundTitle;
  final String notFoundMessage;

  @override
  ConsumerState<EbookAccessGate> createState() => _EbookAccessGateState();
}

class _EbookAccessGateState extends ConsumerState<EbookAccessGate> {
  /// 防止 post-frame callback 重複導航到 paywall。
  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    if (book == null) {
      return _EbookGateMessage(
        icon: Icons.menu_book_outlined,
        title: widget.notFoundTitle,
        message: widget.notFoundMessage,
        primaryLabel: '回學習頁',
        onPrimary: () => context.go('/?tab=learning'),
      );
    }

    final decision = ebookAccessFor(
      book,
      ref.watch(ebookSubscriptionAccessProvider),
    );

    switch (decision) {
      case EbookAccessDecision.allowed:
        return widget.builder(context);

      case EbookAccessDecision.resolving:
        return const _EbookGateLoading(label: '正在確認你的訂閱狀態…');

      case EbookAccessDecision.unavailable:
        return _EbookGateMessage(
          icon: Icons.cloud_off_outlined,
          title: '暫時無法確認訂閱狀態',
          message: '這通常是連線問題。重試一次就好，你的進度不會受影響。',
          primaryLabel: '重試',
          onPrimary: () => ref.read(subscriptionProvider.notifier).refresh(),
          secondaryLabel: '回學習頁',
          onSecondary: () => context.go('/?tab=learning'),
        );

      case EbookAccessDecision.locked:
        if (!_redirected) {
          _redirected = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.push('/paywall');
          });
        }
        // 導航前後都不建立 premium child，避免內容閃現。
        return const _EbookGateLoading(label: '這本需要訂閱才能閱讀');
    }
  }
}

class _EbookGateLoading extends StatelessWidget {
  const _EbookGateLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      title: '互動電子書',
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              strokeWidth: 2.6,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.ctaStart),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EbookGateMessage extends StatelessWidget {
  const _EbookGateMessage({
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
    return BrandScaffold(
      title: '互動電子書',
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BrandIconBadge(icon: icon, size: 48, iconSize: 24),
              const SizedBox(height: 16),
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
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              BrandPrimaryButton(label: primaryLabel, onPressed: onPrimary),
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: 10),
                BrandSecondaryButton(
                  label: secondaryLabel!,
                  onPressed: onSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

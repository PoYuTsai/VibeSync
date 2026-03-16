// ignore_for_file: deprecated_member_use

// lib/features/subscription/presentation/screens/paywall_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/providers/subscription_providers.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String _selectedTier = 'essential'; // 預設選 Essential
  bool _isPurchasing = false;

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('升級方案',
              style: AppTypography.titleLarge
                  .copyWith(color: AppColors.onBackgroundPrimary)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Text(
                    '解鎖完整功能',
                    style: AppTypography.headlineLarge
                        .copyWith(color: AppColors.onBackgroundPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '提升你的社交溝通能力',
                    style: AppTypography.bodyLarge
                        .copyWith(color: AppColors.onBackgroundSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Plan cards
                  _buildPlanCard(
                    tier: 'starter',
                    name: 'Starter',
                    package: subscription.starterPackage,
                    features: const [
                      '300 則訊息/月',
                      '每日 50 則上限',
                      '5 種回覆建議',
                      'Needy 警示',
                      '話題深度分析',
                    ],
                    isSelected: _selectedTier == 'starter',
                    onTap: () => setState(() => _selectedTier = 'starter'),
                  ),
                  const SizedBox(height: 16),
                  _buildPlanCard(
                    tier: 'essential',
                    name: 'Essential',
                    package: subscription.essentialPackage,
                    features: const [
                      '1,000 則訊息/月',
                      '每日 150 則上限',
                      '5 種回覆建議',
                      'Needy 警示',
                      '話題深度分析',
                      '對話健檢 (獨家)',
                      'Sonnet 優先模型',
                      '「我說」話題延續建議',
                    ],
                    isSelected: _selectedTier == 'essential',
                    isRecommended: true,
                    onTap: () => setState(() => _selectedTier = 'essential'),
                  ),
                  const SizedBox(height: 32),

                  // CTA button
                  GradientButton(
                    text: _isPurchasing ? '處理中...' : '立即訂閱',
                    onPressed: _isPurchasing ? null : _subscribe,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '可隨時在 App Store 取消訂閱',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.onBackgroundSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Terms
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {},
                        child: Text('使用條款', style: AppTypography.caption),
                      ),
                      Text(' | ', style: AppTypography.caption),
                      TextButton(
                        onPressed: () {},
                        child: Text('隱私權政策', style: AppTypography.caption),
                      ),
                      Text(' | ', style: AppTypography.caption),
                      TextButton(
                        onPressed: _restorePurchases,
                        child: Text('恢復購買', style: AppTypography.caption),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Debug info button
                  if (kDebugMode)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _showDebugInfo,
                        child: Text('🔧 Debug', style: AppTypography.caption.copyWith(color: Colors.orange)),
                      ),
                      TextButton(
                        onPressed: _forceSyncToSupabase,
                        child: Text('🔄 Force Sync', style: AppTypography.caption.copyWith(color: Colors.orange)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            // Loading overlay
            if (_isPurchasing)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String tier,
    required String name,
    required Package? package,
    required List<String> features,
    required bool isSelected,
    bool isRecommended = false,
    required VoidCallback onTap,
  }) {
    // 從 RevenueCat Package 取得真實價格，否則顯示預設
    final priceString = package?.storeProduct.priceString ??
        (tier == 'starter' ? 'NT\$149' : 'NT\$930');

    return GestureDetector(
      onTap: onTap,
      child: GlassmorphicContainer(
        isSelected: isSelected,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name,
                    style: AppTypography.titleLarge
                        .copyWith(color: AppColors.glassTextPrimary)),
                if (isRecommended) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.selectedStart, AppColors.selectedEnd]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '推薦',
                      style: AppTypography.caption.copyWith(color: Colors.white),
                    ),
                  ),
                ],
                const Spacer(),
                Radio<String>(
                  value: tier,
                  groupValue: _selectedTier,
                  onChanged: (v) => setState(() => _selectedTier = v!),
                  activeColor: AppColors.selectedStart,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Price display
            Text(
              '$priceString/月',
              style: AppTypography.headlineMedium.copyWith(
                color: AppColors.glassTextPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(f,
                            style: AppTypography.bodyMedium
                                .copyWith(color: AppColors.glassTextPrimary))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _subscribe() async {
    // Web 不支援購買
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請在 iOS App 中訂閱')),
      );
      return;
    }

    final subscription = ref.read(subscriptionProvider);
    final package = _selectedTier == 'essential'
        ? subscription.essentialPackage
        : subscription.starterPackage;

    if (package == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法取得產品資訊，請稍後再試')),
      );
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      final success =
          await ref.read(subscriptionProvider.notifier).purchase(package);

      if (mounted && success) {
        // 購買成功後顯示詳細結果
        final customerInfo = await RevenueCatService.getCustomerInfo();
        final newTier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
        final localState = ref.read(subscriptionProvider);

        if (!mounted) return;

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('購買結果'),
            content: SelectableText('''
購買成功！

=== RevenueCat ===
Active Subscriptions: ${customerInfo?.activeSubscriptions.toList()}
Active Entitlements: ${customerInfo?.entitlements.active.keys.toList()}
Detected Tier: $newTier

=== Local State ===
Tier: ${localState.tier}
Daily Limit: ${localState.dailyLimit}
'''),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (context.mounted) context.pop();
                },
                child: const Text('確定'),
              ),
            ],
          ),
        );
      }
    } on PurchasesErrorCode catch (e) {
      if (mounted) {
        String message = '購買失敗';
        if (e == PurchasesErrorCode.purchaseCancelledError) {
          message = '購買已取消';
        } else if (e == PurchasesErrorCode.paymentPendingError) {
          message = '付款處理中';
        } else if (e == PurchasesErrorCode.productNotAvailableForPurchaseError) {
          message = '產品暫時無法購買';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('購買失敗: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _forceSyncToSupabase() async {
    try {
      setState(() => _isPurchasing = true);

      // 從 RevenueCat 取得最新狀態
      debugPrint('[ForceSync] Getting customer info from RevenueCat...');
      final customerInfo = await RevenueCatService.getCustomerInfo();

      if (customerInfo == null) {
        debugPrint('[ForceSync] CustomerInfo is NULL!');
        if (mounted) {
          // 顯示選擇對話框讓用戶手動選擇 tier
          await _showManualTierDialog('RevenueCat 未初始化或無法取得資訊');
        }
        return;
      }

      final activeEntitlements = customerInfo.entitlements.active.keys.toList();
      final activeSubscriptions = customerInfo.activeSubscriptions.toList();
      final allPurchased = customerInfo.allPurchasedProductIdentifiers.toList();

      debugPrint('[ForceSync] Active entitlements: $activeEntitlements');
      debugPrint('[ForceSync] Active subscriptions: $activeSubscriptions');
      debugPrint('[ForceSync] All purchased: $allPurchased');

      final tier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
      debugPrint('[ForceSync] Detected tier: $tier');

      // 如果偵測到 free 但有購買紀錄，顯示警告並讓用戶手動選擇
      if (tier == 'free' && allPurchased.isNotEmpty) {
        if (mounted) {
          await _showManualTierDialog(
            '偵測到購買紀錄但 tier 為 free\n\n'
            'Purchased: $allPurchased\n'
            'Active Subs: $activeSubscriptions\n'
            'Entitlements: $activeEntitlements\n\n'
            '請手動選擇正確的 tier：'
          );
        }
        return;
      }

      // 強制同步到 Supabase
      debugPrint('[ForceSync] Syncing to Supabase...');
      await ref.read(subscriptionProvider.notifier).forceSyncTier(tier);
      debugPrint('[ForceSync] Sync complete!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已同步到 Supabase: $tier'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('[ForceSync] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失敗: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _showManualTierDialog(String message) async {
    final selectedTier = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手動選擇 Tier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text('選擇要同步的 tier：'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'free'),
            child: const Text('Free'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'starter'),
            child: const Text('Starter'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'essential'),
            child: const Text('Essential'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selectedTier != null && mounted) {
      debugPrint('[ForceSync] Manual tier selected: $selectedTier');
      await ref.read(subscriptionProvider.notifier).forceSyncTier(selectedTier);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已手動同步到 Supabase: $selectedTier'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _showDebugInfo() async {
    String debugInfo = 'Loading...';

    try {
      final customerInfo = await RevenueCatService.getCustomerInfo();

      if (customerInfo == null) {
        debugInfo = 'CustomerInfo is NULL\n\nRevenueCat not initialized?';
      } else {
        final allEntitlements = customerInfo.entitlements.all.keys.toList();
        final activeEntitlements = customerInfo.entitlements.active;
        final activeKeys = activeEntitlements.keys.toList();
        final activeSubscriptions = customerInfo.activeSubscriptions.toList();
        final allPurchased = customerInfo.allPurchasedProductIdentifiers.toList();

        final tier = RevenueCatService.getTierFromCustomerInfo(customerInfo);

        debugInfo = '''
=== RevenueCat Debug ===

All Entitlements: $allEntitlements

Active Entitlements: $activeKeys
Count: ${activeEntitlements.length}

Active Subscriptions: $activeSubscriptions

All Purchased Products: $allPurchased

--- Entitlement Details ---
${activeEntitlements.entries.map((e) => '${e.key}: ${e.value.productIdentifier}').join('\n')}

=== Detected Tier: $tier ===

=== Local State ===
Tier: ${ref.read(subscriptionProvider).tier}
Monthly Limit: ${ref.read(subscriptionProvider).monthlyLimit}
Daily Limit: ${ref.read(subscriptionProvider).dailyLimit}
''';
      }
    } catch (e) {
      debugInfo = 'Error: $e';
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Debug Info'),
          content: SingleChildScrollView(
            child: SelectableText(
              debugInfo,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('關閉'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _restorePurchases() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請在 iOS App 中恢復購買')),
      );
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      final restored =
          await ref.read(subscriptionProvider.notifier).restorePurchases();

      if (mounted) {
        if (restored) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('購買已恢復！'),
              backgroundColor: AppColors.success,
            ),
          );
          context.pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('沒有找到可恢復的購買')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢復失敗: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }
}

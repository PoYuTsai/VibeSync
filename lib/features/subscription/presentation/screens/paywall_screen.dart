// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/services/link_launch_service.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/providers/subscription_providers.dart';
import '../../domain/services/subscription_tier_helper.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  static const _privacyUrl = 'https://vibesyncai.app/privacy';
  static const _termsUrl = 'https://vibesyncai.app/terms';

  String _selectedTier = SubscriptionTierHelper.essential;
  bool _isPurchasing = false;

  List<_PaywallPlanData> get _plans {
    final starterLimits = SubscriptionTierHelper.limitsFor(
      SubscriptionTierHelper.starter,
    );
    final essentialLimits = SubscriptionTierHelper.limitsFor(
      SubscriptionTierHelper.essential,
    );

    return [
      _PaywallPlanData(
        tier: SubscriptionTierHelper.starter,
        name: 'Starter',
        badge: '入門',
        description: '適合穩定使用、想先升級分析品質的你',
        features: [
          '${starterLimits.monthly} 則分析額度 / 月',
          '${starterLimits.daily} 則分析額度 / 日',
          '5 種回覆建議',
          'Needy 警示提醒',
          '延續對話建議',
        ],
      ),
      _PaywallPlanData(
        tier: SubscriptionTierHelper.essential,
        name: 'Essential',
        badge: '推薦',
        description: '適合高頻使用、想要完整策略與優化建議的你',
        features: [
          '${essentialLimits.monthly} 則分析額度 / 月',
          '${essentialLimits.daily} 則分析額度 / 日',
          '5 種回覆建議',
          'Needy 警示提醒',
          '延續對話建議',
          '我說優化功能',
          'Sonnet 高品質模型',
          '完整對話健檢與策略建議',
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);
    final selectedPackage = _selectedPackageFor(subscription);
    final offeringsReady = subscription.starterPackage != null ||
        subscription.essentialPackage != null;
    final isCurrentPlan = subscription.tier == _selectedTier;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            '升級方案',
            style: AppTypography.titleLarge
                .copyWith(color: AppColors.onBackgroundPrimary),
          ),
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
                  Text(
                    '選一個最適合你的方案',
                    style: AppTypography.headlineLarge
                        .copyWith(color: AppColors.onBackgroundPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '所有訂閱與退款皆由 App Store 處理，方案會自動續訂，可隨時在系統訂閱管理取消。',
                    style: AppTypography.bodyLarge
                        .copyWith(color: AppColors.onBackgroundSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (!offeringsReady && subscription.isLoading)
                    _buildInfoCard(
                      icon: Icons.sync,
                      title: '正在同步 App Store 方案',
                      message: '剛開啟頁面時若尚未顯示價格，通常等待 1-2 秒就會完成。',
                    ),
                  if (!offeringsReady && !subscription.isLoading)
                    _buildInfoCard(
                      icon: Icons.info_outline,
                      title: '暫時還沒取得方案價格',
                      message: '你可以稍後再試，或重新開啟此頁面同步 App Store 方案資訊。',
                      iconColor: AppColors.warning,
                    ),
                  if (subscription.error != null &&
                      subscription.error!.isNotEmpty &&
                      subscription.error != 'Not logged in')
                    _buildInfoCard(
                      icon: Icons.error_outline,
                      title: '方案資訊同步異常',
                      message: '目前仍可稍後重試；如果問題持續，請重新登入後再試一次。',
                      iconColor: AppColors.error,
                    ),
                  if ((!offeringsReady && subscription.isLoading) ||
                      (!offeringsReady && !subscription.isLoading) ||
                      (subscription.error != null &&
                          subscription.error!.isNotEmpty &&
                          subscription.error != 'Not logged in'))
                    const SizedBox(height: 20),
                  ..._plans.map(
                    (plan) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildPlanCard(
                        plan: plan,
                        package: plan.tier == SubscriptionTierHelper.starter
                            ? subscription.starterPackage
                            : subscription.essentialPackage,
                        isSelected: _selectedTier == plan.tier,
                        isCurrentPlan: subscription.tier == plan.tier,
                        onTap: () => setState(() => _selectedTier = plan.tier),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GradientButton(
                    text: _buildPrimaryButtonText(
                      selectedPackage: selectedPackage,
                      isCurrentPlan: isCurrentPlan,
                    ),
                    onPressed: _isPurchasing ||
                            isCurrentPlan ||
                            selectedPackage == null
                        ? null
                        : _subscribe,
                    isLoading: _isPurchasing,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isCurrentPlan
                        ? '你目前已在此方案。如需取消或變更方案，請改用 App Store 訂閱管理。'
                        : '升級完成後會立即同步方案狀態；若已購買過，請改用下方的恢復購買。',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.onBackgroundSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => _launchUrl(_termsUrl),
                        child: Text('使用條款', style: AppTypography.caption),
                      ),
                      Text('｜', style: AppTypography.caption),
                      TextButton(
                        onPressed: () => _launchUrl(_privacyUrl),
                        child: Text('隱私權政策', style: AppTypography.caption),
                      ),
                      Text('｜', style: AppTypography.caption),
                      TextButton(
                        onPressed: _restorePurchases,
                        child: Text('恢復購買', style: AppTypography.caption),
                      ),
                    ],
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: _showDebugInfo,
                          child: Text(
                            'Debug 資訊',
                            style: AppTypography.caption.copyWith(
                              color: Colors.orange,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _forceSyncToSupabase,
                          child: Text(
                            'Force Sync',
                            style: AppTypography.caption.copyWith(
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
            if (_isPurchasing)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Package? _selectedPackageFor(SubscriptionState subscription) {
    return _selectedTier == SubscriptionTierHelper.essential
        ? subscription.essentialPackage
        : subscription.starterPackage;
  }

  String _buildPrimaryButtonText({
    required Package? selectedPackage,
    required bool isCurrentPlan,
  }) {
    if (_isPurchasing) {
      return '處理中...';
    }
    if (isCurrentPlan) {
      return '目前已使用此方案';
    }
    if (selectedPackage == null) {
      return '同步方案中...';
    }

    final tierLabel = _selectedTier == SubscriptionTierHelper.essential
        ? 'Essential'
        : 'Starter';
    return '升級到 $tierLabel';
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String message,
    Color iconColor = AppColors.info,
  }) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required _PaywallPlanData plan,
    required Package? package,
    required bool isSelected,
    required bool isCurrentPlan,
    required VoidCallback onTap,
  }) {
    final priceLabel = package?.storeProduct.priceString ?? '價格同步中';
    final priceSuffix = package == null ? '' : ' / 月';

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
                Text(
                  plan.name,
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                _buildBadge(
                  label: plan.badge,
                  background: plan.badge == '推薦'
                      ? const LinearGradient(
                          colors: [
                            AppColors.selectedStart,
                            AppColors.selectedEnd,
                          ],
                        )
                      : null,
                  color: plan.badge == '推薦'
                      ? Colors.white
                      : AppColors.glassTextPrimary,
                ),
                if (isCurrentPlan) ...[
                  const SizedBox(width: 8),
                  _buildBadge(
                    label: '目前方案',
                    background: LinearGradient(
                      colors: [
                        AppColors.success.withValues(alpha: 0.88),
                        AppColors.success.withValues(alpha: 0.72),
                      ],
                    ),
                    color: Colors.white,
                  ),
                ],
                const Spacer(),
                Radio<String>(
                  value: plan.tier,
                  groupValue: _selectedTier,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedTier = value);
                  },
                  activeColor: AppColors.selectedStart,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              plan.description,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextHint,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$priceLabel$priceSuffix',
              style: AppTypography.headlineMedium.copyWith(
                color: AppColors.glassTextPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...plan.features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle,
                        size: 16,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feature,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.glassTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge({
    required String label,
    required Color color,
    LinearGradient? background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: background,
        color: background == null ? Colors.white.withValues(alpha: 0.7) : null,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: background == null
              ? AppColors.glassBorder
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _subscribe() async {
    if (kIsWeb) {
      _showSnackBar('目前請改用 iOS App 進行訂閱。');
      return;
    }

    final subscription = ref.read(subscriptionProvider);
    final package = _selectedPackageFor(subscription);

    if (package == null) {
      _showSnackBar('目前尚未取得方案資訊，請稍後再試。');
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      final success =
          await ref.read(subscriptionProvider.notifier).purchase(package);

      if (!mounted || !success) {
        return;
      }

      final purchasedTier = _selectedTier == SubscriptionTierHelper.essential
          ? 'Essential'
          : 'Starter';

      _showSnackBar(
        '訂閱成功，已切換為 $purchasedTier 方案。',
        backgroundColor: AppColors.success,
      );
      context.pop(true);
    } on PurchasesErrorCode catch (errorCode) {
      _showSnackBar(_messageForPurchaseError(errorCode));
    } catch (error) {
      debugPrint('Paywall purchase error: $error');
      _showSnackBar('訂閱處理失敗，請稍後再試一次。');
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  String _messageForPurchaseError(PurchasesErrorCode errorCode) {
    switch (errorCode) {
      case PurchasesErrorCode.purchaseCancelledError:
        return '你已取消本次訂閱。';
      case PurchasesErrorCode.paymentPendingError:
        return '付款仍在等待確認，稍後可再回到此頁查看。';
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
        return '目前無法購買此方案，請稍後再試。';
      default:
        return '訂閱失敗，請稍後再試一次。';
    }
  }

  Future<void> _restorePurchases() async {
    if (kIsWeb) {
      _showSnackBar('目前請改用 iOS App 恢復購買。');
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      final restored =
          await ref.read(subscriptionProvider.notifier).restorePurchases();

      if (!mounted) {
        return;
      }

      if (restored) {
        _showSnackBar(
          '已成功恢復購買，方案狀態已更新。',
          backgroundColor: AppColors.success,
        );
        context.pop(true);
      } else {
        _showSnackBar('目前找不到可恢復的有效訂閱。');
      }
    } catch (error) {
      debugPrint('Paywall restore error: $error');
      _showSnackBar('恢復購買失敗，請稍後再試一次。');
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final launched = await LinkLaunchService.open(url);
    if (!launched) {
      if (!mounted) {
        return;
      }
      _showSnackBar('目前無法開啟連結，請稍後再試。');
    }
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  Future<void> _forceSyncToSupabase() async {
    if (!kDebugMode) {
      return;
    }

    try {
      setState(() => _isPurchasing = true);

      debugPrint('[ForceSync] Getting customer info from RevenueCat...');
      final customerInfo = await RevenueCatService.getCustomerInfo();

      if (customerInfo == null) {
        debugPrint('[ForceSync] CustomerInfo is null.');
        if (mounted) {
          await _showManualTierDialog(
            'RevenueCat 尚未回傳 CustomerInfo，若你剛完成購買，可手動同步 tier 到 Supabase。',
          );
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

      if (tier == SubscriptionTierHelper.free && allPurchased.isNotEmpty) {
        if (mounted) {
          await _showManualTierDialog(
            'RevenueCat 偵測到有購買紀錄，但 tier 仍為 free。\n\n'
            'Purchased: $allPurchased\n'
            'Active Subs: $activeSubscriptions\n'
            'Entitlements: $activeEntitlements\n\n'
            '你可以手動指定 tier 再同步回 Supabase。',
          );
        }
        return;
      }

      debugPrint('[ForceSync] Syncing to Supabase...');
      await ref.read(subscriptionProvider.notifier).forceSyncTier(tier);
      debugPrint('[ForceSync] Sync complete.');

      _showSnackBar(
        '已同步 RevenueCat 狀態到 Supabase：$tier',
        backgroundColor: AppColors.success,
      );
    } catch (error) {
      debugPrint('[ForceSync] Error: $error');
      _showSnackBar('Force Sync 失敗，請查看 debug log。');
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _showManualTierDialog(String message) async {
    if (!kDebugMode) {
      return;
    }

    final selectedTier = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('手動指定 Tier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text('選擇要同步回 Supabase 的 tier。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, SubscriptionTierHelper.free),
            child: const Text('Free'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, SubscriptionTierHelper.starter),
            child: const Text('Starter'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, SubscriptionTierHelper.essential),
            child: const Text('Essential'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selectedTier == null || !mounted) {
      return;
    }

    debugPrint('[ForceSync] Manual tier selected: $selectedTier');
    await ref.read(subscriptionProvider.notifier).forceSyncTier(selectedTier);
    _showSnackBar(
      '已手動同步 tier 到 Supabase：$selectedTier',
      backgroundColor: AppColors.success,
    );
  }

  Future<void> _showDebugInfo() async {
    if (!kDebugMode) {
      return;
    }

    var debugInfo = 'Loading...';

    try {
      final customerInfo = await RevenueCatService.getCustomerInfo();

      if (customerInfo == null) {
        debugInfo =
            'CustomerInfo is null.\n\nRevenueCat may not be initialized yet.';
      } else {
        final allEntitlements = customerInfo.entitlements.all.keys.toList();
        final activeEntitlements = customerInfo.entitlements.active;
        final activeSubscriptions = customerInfo.activeSubscriptions.toList();
        final allPurchased =
            customerInfo.allPurchasedProductIdentifiers.toList();

        final tier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
        final localState = ref.read(subscriptionProvider);

        debugInfo = '''
=== RevenueCat Debug ===

All Entitlements: $allEntitlements
Active Entitlements: ${activeEntitlements.keys.toList()}
Active Subscriptions: $activeSubscriptions
All Purchased Products: $allPurchased

--- Entitlement Details ---
${activeEntitlements.entries.map((entry) => '${entry.key}: ${entry.value.productIdentifier}').join('\n')}

=== Detected Tier ===
$tier

=== Local State ===
Tier: ${localState.tier}
Monthly Limit: ${localState.monthlyLimit}
Daily Limit: ${localState.dailyLimit}
''';
      }
    } catch (error) {
      debugInfo = 'Error: $error';
    }

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Debug 資訊'),
        content: SingleChildScrollView(
          child: SelectableText(
            debugInfo,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }
}

class _PaywallPlanData {
  const _PaywallPlanData({
    required this.tier,
    required this.name,
    required this.badge,
    required this.description,
    required this.features,
  });

  final String tier;
  final String name;
  final String badge;
  final String description;
  final List<String> features;
}

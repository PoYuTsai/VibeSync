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
  static const _manageSubscriptionsUrl =
      'https://apps.apple.com/account/subscriptions';

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
        badge: 'Entry',
        description: 'Steady daily use.',
        pricePoints: [
          '${starterLimits.monthly} analyses / month',
          '${starterLimits.daily} analyses / day',
          '5 reply styles',
          'Needy warning',
          'Final recommendation',
        ],
      ),
      _PaywallPlanData(
        tier: SubscriptionTierHelper.essential,
        name: 'Essential',
        badge: 'Recommended',
        description: 'Higher limits and deeper analysis.',
        pricePoints: [
          '${essentialLimits.monthly} analyses / month',
          '${essentialLimits.daily} analyses / day',
          '5 reply styles',
          'Needy warning',
          'Final recommendation',
          'Health check',
          'Higher limits',
          'Deeper analysis',
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
    final isDowngrade = SubscriptionTierHelper.isDowngrade(
      fromTier: subscription.tier,
      toTier: _selectedTier,
    );
    final hasPendingDowngrade = subscription.hasPendingDowngrade;
    final pendingDowngradeMatchesSelection = hasPendingDowngrade &&
        subscription.pendingDowngradeToTier == _selectedTier;
    final canManagePendingDowngrade =
        hasPendingDowngrade && subscription.tier == _selectedTier;

    VoidCallback? primaryAction;
    if (_isPurchasing) {
      primaryAction = null;
    } else if (canManagePendingDowngrade) {
      primaryAction = () {
        _openManageSubscriptions();
      };
    } else if (isCurrentPlan ||
        pendingDowngradeMatchesSelection ||
        selectedPackage == null) {
      primaryAction = null;
    } else {
      primaryAction = () {
        _subscribe();
      };
    }

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Plans and quota',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
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
                    'Choose the plan that fits you',
                    style: AppTypography.headlineLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Upgrades usually apply immediately. Downgrades apply on the next renewal, and your current quota stays active until then.',
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  _buildQuotaSummaryCard(subscription),
                  if (hasPendingDowngrade) ...[
                    const SizedBox(height: 16),
                    _buildPendingDowngradeCard(subscription),
                  ],
                  if (!offeringsReady) ...[
                    const SizedBox(height: 16),
                    _buildInfoCard(
                      icon: subscription.isLoading
                          ? Icons.sync
                          : Icons.info_outline,
                      title: subscription.isLoading
                          ? 'Syncing plan info'
                          : 'Plan info not ready',
                      message: subscription.isLoading
                          ? 'App Store product sync can take 1 to 2 minutes.'
                          : 'The latest App Store products are not available yet. Please try again soon.',
                      iconColor: subscription.isLoading
                          ? AppColors.info
                          : AppColors.warning,
                    ),
                  ],
                  if (subscription.error != null &&
                      subscription.error!.isNotEmpty &&
                      subscription.error != 'Not logged in') ...[
                    const SizedBox(height: 16),
                    _buildInfoCard(
                      icon: Icons.error_outline,
                      title: 'Plan sync error',
                      message:
                          'We could not refresh your latest plan status. Please try again later or sign in again if it keeps failing.',
                      iconColor: AppColors.error,
                    ),
                  ],
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
                  GradientButton(
                    text: _primaryButtonText(
                      subscription,
                      isCurrentPlan,
                      canManagePendingDowngrade,
                      pendingDowngradeMatchesSelection,
                    ),
                    onPressed: primaryAction,
                    isLoading: _isPurchasing,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _primaryFootnote(
                      subscription,
                      isCurrentPlan,
                      isDowngrade,
                      canManagePendingDowngrade,
                      pendingDowngradeMatchesSelection,
                    ),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: () {
                          _launchUrl(_termsUrl);
                        },
                        child: Text('Terms', style: AppTypography.caption),
                      ),
                      Text('|', style: AppTypography.caption),
                      TextButton(
                        onPressed: () {
                          _launchUrl(_privacyUrl);
                        },
                        child: Text('Privacy', style: AppTypography.caption),
                      ),
                      Text('|', style: AppTypography.caption),
                      TextButton(
                        onPressed: () {
                          _openManageSubscriptions();
                        },
                        child: Text('Manage', style: AppTypography.caption),
                      ),
                      Text('|', style: AppTypography.caption),
                      TextButton(
                        onPressed: () {
                          _syncPurchasedPlan();
                        },
                        child: Text('Restore', style: AppTypography.caption),
                      ),
                    ],
                  ),
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

  String _primaryButtonText(
    SubscriptionState subscription,
    bool isCurrentPlan,
    bool canManagePendingDowngrade,
    bool pendingDowngradeMatchesSelection,
  ) {
    if (_isPurchasing) return 'Processing...';
    if (canManagePendingDowngrade) return 'Manage in App Store';
    if (pendingDowngradeMatchesSelection) {
      return 'Downgrade scheduled to ${_tierLabel(_selectedTier)}';
    }
    if (isCurrentPlan) return 'Current plan';
    if (_selectedPackageFor(subscription) == null)
      return 'Syncing plan info...';
    if (SubscriptionTierHelper.isDowngrade(
      fromTier: subscription.tier,
      toTier: _selectedTier,
    )) {
      return 'Downgrade to ${_tierLabel(_selectedTier)}';
    }
    return 'Upgrade to ${_tierLabel(_selectedTier)}';
  }

  String _primaryFootnote(
    SubscriptionState subscription,
    bool isCurrentPlan,
    bool isDowngrade,
    bool canManagePendingDowngrade,
    bool pendingDowngradeMatchesSelection,
  ) {
    if (canManagePendingDowngrade) {
      return 'A downgrade to ${_tierLabel(subscription.pendingDowngradeToTier)} '
          'is scheduled for ${_formatDate(subscription.pendingDowngradeEffectiveAt)}. '
          'Use App Store subscription management to cancel it.';
    }
    if (pendingDowngradeMatchesSelection) {
      return 'This downgrade is already scheduled and will take effect on '
          '${_formatDate(subscription.pendingDowngradeEffectiveAt)}.';
    }
    if (isCurrentPlan) return 'This is your current active plan.';
    if (isDowngrade) {
      return 'Downgrades take effect on the next renewal. Your current quota stays active until then.';
    }
    return 'Upgrades usually apply immediately and refresh your quota right away.';
  }

  Widget _buildQuotaSummaryCard(SubscriptionState subscription) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current plan and quota',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Active plan: ${_tierLabel(subscription.tier)}',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextHint,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildQuotaPill(
                  label: 'Monthly left',
                  value:
                      '${subscription.monthlyRemaining}/${subscription.monthlyLimit}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuotaPill(
                  label: 'Daily left',
                  value:
                      '${subscription.dailyRemaining}/${subscription.dailyLimit}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaPill({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextHint,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingDowngradeCard(SubscriptionState subscription) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_repeat, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scheduled downgrade to ${_tierLabel(subscription.pendingDowngradeToTier)}',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This takes effect on ${_formatDate(subscription.pendingDowngradeEffectiveAt)}. '
                  'Until then you can keep using the ${_tierLabel(subscription.tier)} quota and features.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.glassTextSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    _openManageSubscriptions();
                  },
                  child: Text(
                    'Cancel or manage in App Store',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    final priceLabel = package?.storeProduct.priceString ?? 'Syncing price';
    final priceSuffix = package == null ? '' : ' / month';

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
                  background: plan.badge == 'Recommended'
                      ? const LinearGradient(
                          colors: [
                            AppColors.selectedStart,
                            AppColors.selectedEnd,
                          ],
                        )
                      : null,
                  color: plan.badge == 'Recommended'
                      ? Colors.white
                      : AppColors.glassTextPrimary,
                ),
                if (isCurrentPlan) ...[
                  const SizedBox(width: 8),
                  _buildBadge(
                    label: 'Current',
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
            ...plan.pricePoints.map(
              (item) => Padding(
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
                        item,
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
      _showSnackBar('Please manage subscriptions in the iOS app.');
      return;
    }

    final subscription = ref.read(subscriptionProvider);
    final package = _selectedPackageFor(subscription);
    if (package == null) {
      _showSnackBar('Plan info is not ready yet. Please try again.');
      return;
    }

    setState(() => _isPurchasing = true);
    try {
      final notifier = ref.read(subscriptionProvider.notifier);
      final result = await notifier.purchase(package);
      if (!mounted || result.cancelled) return;

      if (!result.success) {
        _showSnackBar(
          _messageForPurchaseError(
            result.errorCode,
            fallbackMessage: result.errorMessage,
          ),
        );
        return;
      }

      if (result.isDeferredDowngrade) {
        _showSnackBar(
          'Downgrade to ${_tierLabel(result.requestedTier)} scheduled for ${_formatDate(result.effectiveAt)}.',
          backgroundColor: AppColors.success,
        );
        context.pop(result.activeTier);
        return;
      }

      await notifier.refresh();
      if (!mounted) return;

      final purchasedTier =
          result.activeTier == SubscriptionTierHelper.essential
              ? 'Essential'
              : 'Starter';
      _showSnackBar(
        'Purchase complete. Active plan: $purchasedTier.',
        backgroundColor: AppColors.success,
      );
      context.pop(result.activeTier);
    } catch (error) {
      debugPrint('Paywall purchase error: $error');
      _showSnackBar('Purchase failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  String _messageForPurchaseError(
    PurchasesErrorCode? errorCode, {
    String? fallbackMessage,
  }) {
    switch (errorCode) {
      case PurchasesErrorCode.purchaseCancelledError:
        return 'Purchase cancelled.';
      case PurchasesErrorCode.paymentPendingError:
        return 'Payment is pending App Store confirmation.';
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
        return 'This product is not available right now.';
      case PurchasesErrorCode.storeProblemError:
      case PurchasesErrorCode.networkError:
        return 'Could not reach App Store. Please try again.';
      default:
        if (fallbackMessage != null && fallbackMessage.isNotEmpty) {
          return fallbackMessage;
        }
        return 'Purchase failed. Please try again.';
    }
  }

  Future<void> _syncPurchasedPlan() async {
    if (kIsWeb) {
      _showSnackBar('Please restore purchases in the iOS app.');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.glassWhite,
            title: Text(
              'Restore purchases',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.glassTextPrimary,
              ),
            ),
            content: Text(
              'If this Apple ID already has a subscription, you can refresh it here.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  'Cancel',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.unselectedText,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  'Restore',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _isPurchasing = true);
    try {
      final notifier = ref.read(subscriptionProvider.notifier);
      final restored = await notifier.restorePurchases();
      if (!mounted) return;

      if (restored) {
        await notifier.refresh();
        if (!mounted) return;
        _showSnackBar(
          'Subscription status refreshed.',
          backgroundColor: AppColors.success,
        );
        context.pop(ref.read(subscriptionProvider).tier);
      } else {
        _showSnackBar('No active subscription was found for this Apple ID.');
      }
    } catch (error) {
      debugPrint('Paywall restore error: $error');
      _showSnackBar('Restore failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final launched = await LinkLaunchService.open(url);
    if (!launched && mounted) {
      _showSnackBar('Could not open the link right now.');
    }
  }

  Future<void> _openManageSubscriptions() async {
    final managementUrl =
        await RevenueCatService.getManagementUrl() ?? _manageSubscriptionsUrl;
    final launched = await LinkLaunchService.open(managementUrl);
    if (!launched && mounted) {
      _showSnackBar('Could not open App Store subscription management.');
    }
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  String _tierLabel(String? tier) {
    switch (tier) {
      case SubscriptionTierHelper.starter:
        return 'Starter';
      case SubscriptionTierHelper.essential:
        return 'Essential';
      default:
        return 'Free';
    }
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return 'next renewal';
    final local = dateTime.toLocal();
    return '${local.month}/${local.day}';
  }
}

class _PaywallPlanData {
  const _PaywallPlanData({
    required this.tier,
    required this.name,
    required this.badge,
    required this.description,
    required this.pricePoints,
  });

  final String tier;
  final String name;
  final String badge;
  final String description;
  final List<String> pricePoints;
}

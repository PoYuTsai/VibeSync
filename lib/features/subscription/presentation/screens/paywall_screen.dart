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
        badge: '入門',
        description: '適合穩定的日常使用。',
        pricePoints: [
          '每月 ${starterLimits.monthly} 次分析',
          '每日 ${starterLimits.daily} 次分析',
          '5 種回覆風格',
          '需求感提醒',
          '最終建議',
        ],
      ),
      _PaywallPlanData(
        tier: SubscriptionTierHelper.essential,
        name: 'Essential',
        badge: '推薦',
        description: '更高額度與更深入的分析。',
        pricePoints: [
          '每月 ${essentialLimits.monthly} 次分析',
          '每日 ${essentialLimits.daily} 次分析',
          '5 種回覆風格',
          '需求感提醒',
          '最終建議',
          '對話健檢',
          '更高額度',
          '更深入分析',
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
            '方案與額度',
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
                    '選擇最適合你的方案',
                    style: AppTypography.headlineLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '升級會立即生效，Apple 會自動按比例調整本期費用。降級則會在下次續訂時生效，今天不會再次扣款。',
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
                      title: subscription.isLoading ? '正在同步方案資訊' : '方案資訊尚未就緒',
                      message: subscription.isLoading
                          ? 'App Store 產品同步可能需要 1 到 2 分鐘。'
                          : '目前還拿不到最新的 App Store 方案，請稍後再試。',
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
                      title: '方案同步異常',
                      message: '目前無法更新你的最新方案狀態。若持續失敗，請稍後再試或重新登入。',
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
                        child: Text('條款', style: AppTypography.caption),
                      ),
                      Text('|', style: AppTypography.caption),
                      TextButton(
                        onPressed: () {
                          _launchUrl(_privacyUrl);
                        },
                        child: Text('隱私', style: AppTypography.caption),
                      ),
                      Text('|', style: AppTypography.caption),
                      TextButton(
                        onPressed: () {
                          _openManageSubscriptions();
                        },
                        child: Text('管理訂閱', style: AppTypography.caption),
                      ),
                      Text('|', style: AppTypography.caption),
                      TextButton(
                        onPressed: () {
                          _syncPurchasedPlan();
                        },
                        child: Text('恢復購買', style: AppTypography.caption),
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
    if (_isPurchasing) return '處理中...';
    if (canManagePendingDowngrade) return '前往 App Store 管理';
    if (pendingDowngradeMatchesSelection) {
      return '已排程降級到 ${_tierLabel(_selectedTier)}';
    }
    if (isCurrentPlan) return '目前方案';
    if (_selectedPackageFor(subscription) == null) return '正在同步方案資訊...';
    if (SubscriptionTierHelper.isDowngrade(
      fromTier: subscription.tier,
      toTier: _selectedTier,
    )) {
      return '安排降級到 ${_tierLabel(_selectedTier)}';
    }
    return '升級到 ${_tierLabel(_selectedTier)}';
  }

  String _primaryFootnote(
    SubscriptionState subscription,
    bool isCurrentPlan,
    bool isDowngrade,
    bool canManagePendingDowngrade,
    bool pendingDowngradeMatchesSelection,
  ) {
    if (canManagePendingDowngrade) {
      return '${_tierLabel(subscription.pendingDowngradeToTier)} 的降級已排程於 '
          '${_formatDate(subscription.pendingDowngradeEffectiveAt)} 生效。'
          '在那之前目前方案仍會持續生效；如要取消降級，請前往 App Store 訂閱管理。';
    }
    if (pendingDowngradeMatchesSelection) {
      return '這個降級已經排程，將於 ${_formatDate(subscription.pendingDowngradeEffectiveAt)} 生效，今天不會再次扣款。';
    }
    if (isCurrentPlan) return '這是你目前正在使用的方案。';
    if (isDowngrade) {
      return '降級會在下次續訂時生效；在那之前你仍可使用目前額度，今天不會再次扣款。';
    }
    return '升級會立即生效並立刻刷新額度，Apple 也會自動按比例調整本期費用。';
  }

  Widget _buildQuotaSummaryCard(SubscriptionState subscription) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目前方案與額度',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '目前方案：${_tierLabel(subscription.tier)}',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextHint,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildQuotaPill(
                  label: '本月剩餘',
                  value:
                      '${subscription.monthlyRemaining}/${subscription.monthlyLimit}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuotaPill(
                  label: '今日剩餘',
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
                  '已排程降級到 ${_tierLabel(subscription.pendingDowngradeToTier)}',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '將於 ${_formatDate(subscription.pendingDowngradeEffectiveAt)} 生效。'
                  '在那之前你仍可使用 ${_tierLabel(subscription.tier)} 的額度與功能，今天不會再次扣款。',
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
                    '前往 App Store 取消或管理',
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
                    label: '目前',
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
      _showSnackBar('方案資訊尚未就緒，請稍後再試。');
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
          '已安排於 ${_formatDate(result.effectiveAt)} 降級到 ${_tierLabel(result.requestedTier)}。',
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
        '方案已更新，目前方案：$purchasedTier。',
        backgroundColor: AppColors.success,
      );
      context.pop(result.activeTier);
    } catch (error) {
      debugPrint('Paywall purchase error: $error');
      _showSnackBar('訂閱處理失敗，請稍後再試。');
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
        return '已取消購買。';
      case PurchasesErrorCode.paymentPendingError:
        return '付款仍在等待 App Store 確認。';
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
        return '此方案目前無法購買。';
      case PurchasesErrorCode.storeProblemError:
      case PurchasesErrorCode.networkError:
        return '目前無法連線到 App Store，請稍後再試。';
      default:
        if (fallbackMessage != null && fallbackMessage.isNotEmpty) {
          return fallbackMessage;
        }
        return '訂閱處理失敗，請稍後再試。';
    }
  }

  Future<void> _syncPurchasedPlan() async {
    if (kIsWeb) {
      _showSnackBar('請在 iOS App 內恢復購買。');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.glassWhite,
            title: Text(
              '恢復購買',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.glassTextPrimary,
              ),
            ),
            content: Text(
              '如果這個 Apple ID 已經有訂閱，可以在這裡重新同步。',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  '取消',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.unselectedText,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  '恢復購買',
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
          '訂閱狀態已更新。',
          backgroundColor: AppColors.success,
        );
        context.pop(ref.read(subscriptionProvider).tier);
      } else {
        _showSnackBar('這個 Apple ID 目前沒有可恢復的有效訂閱。');
      }
    } catch (error) {
      debugPrint('Paywall restore error: $error');
      _showSnackBar('恢復購買失敗，請稍後再試。');
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final launched = await LinkLaunchService.open(url);
    if (!launched && mounted) {
      _showSnackBar('目前無法開啟連結。');
    }
  }

  Future<void> _openManageSubscriptions() async {
    final managementUrl =
        await RevenueCatService.getManagementUrl() ?? _manageSubscriptionsUrl;
    final launched = await LinkLaunchService.open(managementUrl);
    if (!launched && mounted) {
      _showSnackBar('目前無法開啟 App Store 訂閱管理。');
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
    if (dateTime == null) return '下次續訂';
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

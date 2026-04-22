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

  String _selectedOptionId = 'essential_monthly';
  bool _isPurchasing = false;

  List<_PaywallOption> _buildOptions(SubscriptionState subscription) {
    final starterLimits = SubscriptionTierHelper.limitsFor(
      SubscriptionTierHelper.starter,
    );
    final essentialLimits = SubscriptionTierHelper.limitsFor(
      SubscriptionTierHelper.essential,
    );
    return [
      _PaywallOption(
        id: 'starter_monthly',
        tier: SubscriptionTierHelper.starter,
        name: 'Starter',
        period: '月繳',
        badge: '入門',
        discount: null,
        package: subscription.starterMonthlyPackage,
        highlights: [
          '每月 ${starterLimits.monthly} 則 / 每日 ${starterLimits.daily} 則',
          '五種風格全開 + Sonnet AI',
          '雷達圖五維度剖析',
        ],
      ),
      _PaywallOption(
        id: 'starter_quarterly',
        tier: SubscriptionTierHelper.starter,
        name: 'Starter',
        period: '季繳',
        badge: '入門',
        discount: '省 27%',
        package: subscription.starterQuarterlyPackage,
        highlights: [
          '每月 ${starterLimits.monthly} 則 / 每日 ${starterLimits.daily} 則',
          '五種風格全開 + Sonnet AI',
          '雷達圖五維度剖析',
        ],
      ),
      _PaywallOption(
        id: 'essential_monthly',
        tier: SubscriptionTierHelper.essential,
        name: 'Essential',
        period: '月繳',
        badge: '推薦',
        discount: null,
        package: subscription.essentialMonthlyPackage,
        highlights: [
          '每月 ${essentialLimits.monthly} 則 / 每日 ${essentialLimits.daily} 則',
          '五種風格全開 + Sonnet AI',
          '雷達圖 + 對話健檢 + 訊息優化',
        ],
      ),
      _PaywallOption(
        id: 'essential_quarterly',
        tier: SubscriptionTierHelper.essential,
        name: 'Essential',
        period: '季繳',
        badge: '最划算',
        discount: '省 36%',
        package: subscription.essentialQuarterlyPackage,
        highlights: [
          '每月 ${essentialLimits.monthly} 則 / 每日 ${essentialLimits.daily} 則',
          '五種風格全開 + Sonnet AI',
          '雷達圖 + 對話健檢 + 訊息優化',
        ],
      ),
    ];
  }

  _PaywallOption? _selectedOption(List<_PaywallOption> options) {
    return options
        .cast<_PaywallOption?>()
        .firstWhere((o) => o?.id == _selectedOptionId, orElse: () => null);
  }

  _PaywallOption? _firstAvailableOption(List<_PaywallOption> options) {
    return options
        .cast<_PaywallOption?>()
        .firstWhere((o) => o?.package != null, orElse: () => null);
  }

  _PaywallOption? _resolvedSelectedOption(List<_PaywallOption> options) {
    final selected = _selectedOption(options);
    if (selected == null || selected.package != null) {
      return selected;
    }
    return _firstAvailableOption(options) ?? selected;
  }

  void _scheduleSelectedOptionFallback(_PaywallOption? resolved) {
    if (resolved == null || resolved.id == _selectedOptionId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || resolved.id == _selectedOptionId) return;
      setState(() => _selectedOptionId = resolved.id);
    });
  }

  String? _productIdForOption(_PaywallOption? option) {
    final productId = option?.package?.storeProduct.identifier.trim();
    if (productId == null || productId.isEmpty) return null;
    return productId;
  }

  bool _sameProduct(String? a, String? b) {
    return a != null && a.isNotEmpty && b != null && b.isNotEmpty && a == b;
  }

  bool _isCurrentOption(
    SubscriptionState subscription,
    _PaywallOption? option,
  ) {
    if (option == null) return false;

    final optionProductId = _productIdForOption(option);
    final activeProductId = subscription.activeProductId?.trim();
    if (_sameProduct(activeProductId, optionProductId)) {
      return true;
    }
    if (activeProductId != null && activeProductId.isNotEmpty) {
      return false;
    }

    // Legacy fallback before RevenueCat product IDs have synced into state.
    return subscription.tier == option.tier && option.id.endsWith('_monthly');
  }

  bool _pendingDowngradeMatchesOption(
    SubscriptionState subscription,
    _PaywallOption? option,
  ) {
    if (option == null || !subscription.hasPendingDowngrade) return false;

    final pendingProductId = subscription.pendingDowngradeProductId?.trim();
    final optionProductId = _productIdForOption(option);
    if (_sameProduct(pendingProductId, optionProductId)) {
      return true;
    }
    if (pendingProductId != null && pendingProductId.isNotEmpty) {
      return false;
    }

    return subscription.pendingDowngradeToTier == option.tier;
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);
    final options = _buildOptions(subscription);
    final selected = _resolvedSelectedOption(options);
    _scheduleSelectedOptionFallback(selected);
    final selectedPackage = selected?.package;
    final selectedTier = selected?.tier ?? SubscriptionTierHelper.essential;
    final offeringsReady = options.any((o) => o.package != null);
    final isCurrentPlan = _isCurrentOption(subscription, selected);
    final isDowngrade = SubscriptionTierHelper.isDowngrade(
      fromTier: subscription.tier,
      toTier: selectedTier,
    );
    final hasPendingDowngrade = subscription.hasPendingDowngrade;
    final pendingDowngradeMatchesSelection =
        _pendingDowngradeMatchesOption(subscription, selected);
    final canManagePendingDowngrade = hasPendingDowngrade && isCurrentPlan;

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
        _subscribe(selectedPackage, selectedTier);
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
                    '解鎖完整分析，回得更有把握',
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
                  _buildFeatureComparisonTable(),
                  const SizedBox(height: 20),
                  ...options.map(
                    (option) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildOptionCard(
                        option: option,
                        isSelected: _selectedOptionId == option.id,
                        isCurrentPlan: _isCurrentOption(subscription, option),
                        onTap: () =>
                            setState(() => _selectedOptionId = option.id),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GradientButton(
                    text: _primaryButtonText(
                      subscription,
                      selected,
                      selectedTier,
                      isCurrentPlan,
                      canManagePendingDowngrade,
                      pendingDowngradeMatchesSelection,
                      selectedPackage,
                    ),
                    onPressed: primaryAction,
                    isLoading: _isPurchasing,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _primaryFootnote(
                      subscription,
                      selected,
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

  String _primaryButtonText(
    SubscriptionState subscription,
    _PaywallOption? selected,
    String selectedTier,
    bool isCurrentPlan,
    bool canManagePendingDowngrade,
    bool pendingDowngradeMatchesSelection,
    Package? selectedPackage,
  ) {
    if (_isPurchasing) return '處理中...';
    if (canManagePendingDowngrade) return '取消降級 / 管理訂閱';
    if (pendingDowngradeMatchesSelection) {
      return '已排程降級到 ${_tierLabel(selectedTier)}';
    }
    if (isCurrentPlan) return '目前方案';
    if (selectedPackage == null) return '正在同步方案資訊...';
    if (subscription.tier == selectedTier) {
      return '改用 ${_tierLabel(selectedTier)} ${selected?.period ?? ''}';
    }
    if (SubscriptionTierHelper.isDowngrade(
      fromTier: subscription.tier,
      toTier: selectedTier,
    )) {
      return '安排降級到 ${_tierLabel(selectedTier)}';
    }
    return '升級到 ${_tierLabel(selectedTier)}';
  }

  String _primaryFootnote(
    SubscriptionState subscription,
    _PaywallOption? selected,
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
    if (selected != null && subscription.tier == selected.tier) {
      return '同方案更改月繳 / 季繳會由 App Store 確認，實際生效時間與費用以 Apple 畫面為準。';
    }
    if (isDowngrade) {
      return '降級會在下次續訂時生效；在那之前你仍可使用目前額度，今天不會再次扣款。';
    }
    return '升級會立即生效並立刻刷新額度，Apple 也會自動按比例調整本期費用。';
  }

  Widget _buildFeatureComparisonTable() {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '功能比較',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildComparisonRow(
              '回覆風格', 'Free', '延展', 'Starter', '全部 5 種', 'Essential', '全部 5 種'),
          _buildComparisonRow('AI 模型', 'Free', 'Haiku', 'Starter', 'Sonnet',
              'Essential', 'Sonnet'),
          _buildComparisonRow(
              '雷達圖', 'Free', '--', 'Starter', 'V', 'Essential', 'V'),
          _buildComparisonRow(
              '對話健檢', 'Free', '--', 'Starter', '--', 'Essential', 'V'),
          _buildComparisonRow(
              '訊息優化', 'Free', '--', 'Starter', '--', 'Essential', 'V'),
          _buildComparisonRow(
              '每日額度', 'Free', '15', 'Starter', '50', 'Essential', '120'),
          _buildComparisonRow(
              '每月額度', 'Free', '30', 'Starter', '300', 'Essential', '800'),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(
    String feature,
    String freeLabel,
    String freeValue,
    String starterLabel,
    String starterValue,
    String essentialLabel,
    String essentialValue,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              feature,
              style: AppTypography.caption.copyWith(
                color: AppColors.glassTextHint,
              ),
            ),
          ),
          Expanded(
            child: Text(
              freeValue,
              style: AppTypography.caption.copyWith(
                color: AppColors.glassTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              starterValue,
              style: AppTypography.caption.copyWith(
                color: AppColors.glassTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              essentialValue,
              style: AppTypography.caption.copyWith(
                color: AppColors.glassTextPrimary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
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
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      onPressed: () {
                        _openManageSubscriptions();
                      },
                      child: Text(
                        '取消降級 / 管理訂閱',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _refreshAfterExternalDowngradeCancel,
                      child: Text(
                        '我已取消降級，更新狀態',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.glassTextPrimary,
                        ),
                      ),
                    ),
                  ],
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

  Widget _buildOptionCard({
    required _PaywallOption option,
    required bool isSelected,
    required bool isCurrentPlan,
    required VoidCallback onTap,
  }) {
    final priceLabel = option.package?.storeProduct.priceString ?? '價格同步中';
    final periodSuffix = option.package == null
        ? ''
        : (option.id.contains('quarterly') ? ' / 季' : ' / 月');
    final isRecommended = option.id == 'essential_quarterly';

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
                  '${option.name} ${option.period}',
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                _buildBadge(
                  label: option.badge,
                  background: isRecommended
                      ? const LinearGradient(
                          colors: [
                            AppColors.selectedStart,
                            AppColors.selectedEnd,
                          ],
                        )
                      : null,
                  color:
                      isRecommended ? Colors.white : AppColors.glassTextPrimary,
                ),
                if (option.discount != null) ...[
                  const SizedBox(width: 6),
                  _buildBadge(
                    label: option.discount!,
                    background: LinearGradient(
                      colors: [
                        AppColors.success.withValues(alpha: 0.88),
                        AppColors.success.withValues(alpha: 0.72),
                      ],
                    ),
                    color: Colors.white,
                  ),
                ],
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
                  value: option.id,
                  groupValue: _selectedOptionId,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedOptionId = value);
                  },
                  activeColor: AppColors.selectedStart,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$priceLabel$periodSuffix',
              style: AppTypography.headlineMedium.copyWith(
                color: AppColors.glassTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ...option.highlights.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle,
                        size: 14,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 6),
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

  Future<void> _subscribe(Package package, String selectedTier) async {
    if (kIsWeb) {
      _showSnackBar('Please manage subscriptions in the iOS app.');
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

  Future<void> _refreshAfterExternalDowngradeCancel() async {
    if (_isPurchasing) return;

    setState(() => _isPurchasing = true);
    try {
      final didClear = await ref
          .read(subscriptionProvider.notifier)
          .clearPendingDowngradeMetadata();
      if (!mounted) return;
      if (didClear) {
        _showSnackBar(
          '已重新同步訂閱狀態。',
          backgroundColor: AppColors.success,
        );
      } else {
        _showSnackBar('App Store 仍顯示降級排程，請確認取消後稍後再試。');
      }
    } catch (error) {
      debugPrint('Paywall pending downgrade refresh error: $error');
      _showSnackBar('同步失敗，請稍後再試。');
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
    final openedNative =
        await RevenueCatService.showNativeManageSubscriptions();
    if (openedNative) {
      return;
    }

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

class _PaywallOption {
  const _PaywallOption({
    required this.id,
    required this.tier,
    required this.name,
    required this.period,
    required this.badge,
    required this.discount,
    required this.package,
    required this.highlights,
  });

  final String id;
  final String tier;
  final String name;
  final String period;
  final String badge;
  final String? discount;
  final Package? package;
  final List<String> highlights;
}

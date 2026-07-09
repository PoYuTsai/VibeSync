// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/services/link_launch_service.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/subscription_providers.dart';
import '../../domain/services/quarterly_savings.dart';
import '../../domain/services/subscription_tier_helper.dart';
import '../subscription_diagnostics_gate.dart';

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
  static const _purchaseTimeout = Duration(seconds: 45);
  static const _planRefreshTimeout = Duration(seconds: 20);
  static const _postSuccessRefreshTimeout = Duration(seconds: 20);

  String _selectedOptionId = 'essential_monthly';
  bool _isPurchasing = false;
  bool _isRefreshingPlans = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(subscriptionScreenRefreshProvider)());
    });
  }

  List<_PaywallOption> _buildOptions(SubscriptionState subscription) {
    final starterLimits = SubscriptionTierHelper.limitsFor(
      SubscriptionTierHelper.starter,
    );
    final essentialLimits = SubscriptionTierHelper.limitsFor(
      SubscriptionTierHelper.essential,
    );
    final starterQuarterlyDiscount = quarterlySavingsLabel(
      monthly: subscription.starterMonthlyPackage?.storeProduct ??
          subscription.starterMonthlyStoreProduct,
      quarterly: subscription.starterQuarterlyPackage?.storeProduct ??
          subscription.starterQuarterlyStoreProduct,
    );
    final essentialQuarterlyDiscount = quarterlySavingsLabel(
      monthly: subscription.essentialMonthlyPackage?.storeProduct ??
          subscription.essentialMonthlyStoreProduct,
      quarterly: subscription.essentialQuarterlyPackage?.storeProduct ??
          subscription.essentialQuarterlyStoreProduct,
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
        storeProduct: subscription.starterMonthlyStoreProduct,
        highlights: [
          '每月 ${starterLimits.monthly} 則 / 每日 ${starterLimits.daily} 則',
          '五種風格全開 + 高階型 AI',
          '雷達圖五維度剖析',
        ],
      ),
      _PaywallOption(
        id: 'starter_quarterly',
        tier: SubscriptionTierHelper.starter,
        name: 'Starter',
        period: '季繳',
        badge: '入門',
        discount: starterQuarterlyDiscount,
        package: subscription.starterQuarterlyPackage,
        storeProduct: subscription.starterQuarterlyStoreProduct,
        highlights: [
          '每月 ${starterLimits.monthly} 則 / 每日 ${starterLimits.daily} 則',
          '五種風格全開 + 高階型 AI',
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
        storeProduct: subscription.essentialMonthlyStoreProduct,
        highlights: [
          '每月 ${essentialLimits.monthly} 則 / 每日 ${essentialLimits.daily} 則',
          '五種風格全開 + 高階型 AI',
          '雷達圖 + 對話健檢 + 訊息優化',
        ],
      ),
      _PaywallOption(
        id: 'essential_quarterly',
        tier: SubscriptionTierHelper.essential,
        name: 'Essential',
        period: '季繳',
        badge: '最划算',
        discount: essentialQuarterlyDiscount,
        package: subscription.essentialQuarterlyPackage,
        storeProduct: subscription.essentialQuarterlyStoreProduct,
        highlights: [
          '每月 ${essentialLimits.monthly} 則 / 每日 ${essentialLimits.daily} 則',
          '五種風格全開 + 高階型 AI',
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
        .firstWhere((o) => o?.isReady == true, orElse: () => null);
  }

  void _scheduleSelectedOptionFallback(_PaywallOption? fallback) {
    if (fallback == null || fallback.id == _selectedOptionId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || fallback.id == _selectedOptionId) return;
      setState(() => _selectedOptionId = fallback.id);
    });
  }

  String? _productIdForOption(_PaywallOption? option) {
    final productId = option?.productId?.trim();
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

  void _leavePaywall([Object? result]) {
    if (context.canPop()) {
      context.pop(result);
    } else {
      context.go('/');
    }
  }

  void _closePaywall() => _leavePaywall();

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);
    final options = _buildOptions(subscription);
    final selected = _selectedOption(options);
    final fallbackOption = selected == null || selected.isReady
        ? null
        : _firstAvailableOption(options);
    _scheduleSelectedOptionFallback(fallbackOption);
    final selectedProduct = selected?.purchasableProduct;
    final selectedTier = selected?.tier ?? SubscriptionTierHelper.essential;
    final plansReady = options.any((o) => o.isReady);
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
    if (_isPurchasing || _isRefreshingPlans) {
      primaryAction = null;
    } else if (canManagePendingDowngrade) {
      primaryAction = () {
        _openManageSubscriptions();
      };
    } else if (isCurrentPlan ||
        pendingDowngradeMatchesSelection ||
        selected == null) {
      primaryAction = null;
    } else if (!selected.isReady) {
      primaryAction = () {
        _refreshPlanProducts();
      };
    } else {
      primaryAction = () {
        _subscribe(selected, selectedTier);
      };
    }

    return BrandScaffold(
      title: '方案與額度',
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: _closePaywall,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '完整分析\n回覆更有把握',
                  style: AppTypography.headlineLarge.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.12,
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
                if (!plansReady) ...[
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
                if (selected != null) ...[
                  const SizedBox(height: 4),
                  _buildSelectedBillingCard(
                    option: selected,
                    isDowngrade: isDowngrade,
                    isCurrentPlan: isCurrentPlan,
                  ),
                ],
                const SizedBox(height: 8),
                BrandPrimaryButton(
                  label: _primaryButtonText(
                    subscription,
                    selected,
                    selectedTier,
                    isCurrentPlan,
                    canManagePendingDowngrade,
                    pendingDowngradeMatchesSelection,
                    selectedProduct,
                  ),
                  onPressed: primaryAction,
                  isLoading: _isPurchasing || _isRefreshingPlans,
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
                      child: Text('服務條款', style: AppTypography.caption),
                    ),
                    Text('|', style: AppTypography.caption),
                    TextButton(
                      onPressed: () {
                        _launchUrl(_privacyUrl);
                      },
                      child: Text('隱私政策', style: AppTypography.caption),
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
                    if (SubscriptionDiagnosticsGate.isVisible) ...[
                      Text('|', style: AppTypography.caption),
                      TextButton(
                        onPressed: _copySubscriptionDiagnostics,
                        child: Text(
                          '複製訂閱診斷',
                          style: AppTypography.caption,
                        ),
                      ),
                    ],
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
    );
  }

  String _primaryButtonText(
    SubscriptionState subscription,
    _PaywallOption? selected,
    String selectedTier,
    bool isCurrentPlan,
    bool canManagePendingDowngrade,
    bool pendingDowngradeMatchesSelection,
    StoreProduct? selectedProduct,
  ) {
    if (_isPurchasing) return '處理中…';
    if (_isRefreshingPlans) return '重新整理中…';
    if (canManagePendingDowngrade) return '取消降級 / 管理訂閱';
    if (pendingDowngradeMatchesSelection) {
      return '已排程降級到 ${_tierLabel(selectedTier)}';
    }
    if (isCurrentPlan) return '目前方案';
    if (selectedProduct == null) return '重新載入 App Store 價格';
    final price = selected?.priceString ?? selectedProduct.priceString;
    final planName = '${_tierLabel(selectedTier)} ${selected?.period ?? ''}';
    if (subscription.tier == selectedTier) {
      return '以 $price 改用 $planName';
    }
    if (SubscriptionTierHelper.isDowngrade(
      fromTier: subscription.tier,
      toTier: selectedTier,
    )) {
      return '排程降級到 $planName';
    }
    return '以 $price 訂閱 $planName';
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

  Widget _buildSelectedBillingCard({
    required _PaywallOption option,
    required bool isDowngrade,
    required bool isCurrentPlan,
  }) {
    final price = option.priceString ?? '正在向 App Store 取得價格';
    final billingCycle = option.isQuarterly ? '每 3 個月自動續訂' : '每月自動續訂';
    final title = isCurrentPlan ? '目前方案' : '本次扣款金額';
    final note = isDowngrade
        ? '降級會在下次續訂時生效；今天不會再次扣款。'
        : '付款會由 Apple ID 扣款，除非在到期前取消，否則會自動續訂。';

    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            price,
            style: AppTypography.headlineLarge.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${option.name} ${option.period}，$billingCycle',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureComparisonTable() {
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '方案功能比較',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildComparisonHeader(),
          _buildComparisonRow('適合誰', '先試手感', '穩定練習', '深度打磨'),
          _buildComparisonRow('回覆風格', '延展 1 種', '全部 5 種', '全部 5 種'),
          _buildComparisonRow('陪練女孩', '每日 1 位', '開放', '開放'),
          _buildComparisonRow('AI 模型', '經濟型', '高階型', '高階型'),
          _buildComparisonRow('雷達圖', '未開放', '可用', '可用'),
          _buildComparisonRow('對話健檢', '未開放', '未開放', '可用'),
          _buildComparisonRow('訊息優化', '未開放', '未開放', '可用'),
          _buildComparisonRow('每日額度', '15 則', '50 則', '120 則'),
          _buildComparisonRow('每月額度', '30 則', '300 則', '800 則'),
          const SizedBox(height: 12),
          Text(
            'Free 每天仍可翻出新的陪練女孩，但同一位只能練一輪；'
            '升級後可續聊同一位，把對話練得更完整。',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const SizedBox(width: 72),
          for (final label in ['Free', 'Starter', 'Essential'])
            Expanded(
              child: Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: label == 'Essential'
                      ? AppColors.onBackgroundPrimary
                      : AppColors.onBackgroundSecondary.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(
    String feature,
    String freeValue,
    String starterValue,
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
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              freeValue,
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              starterValue,
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              essentialValue,
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundPrimary,
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
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目前方案與額度',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '目前方案：${_tierLabel(subscription.tier)}${_billingPeriodLabel(subscription)}',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7),
            ),
          ),
          if (subscription.renewsAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '下次續訂：${_formatDate(subscription.renewsAt!)}',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],
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
        color: AppColors.brandInk.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingDowngradeCard(SubscriptionState subscription) {
    return BrandSurfaceCard(
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
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '將於 ${_formatDate(subscription.pendingDowngradeEffectiveAt)} 生效。'
                  '在那之前你仍可使用 ${_tierLabel(subscription.tier)} 的額度與功能，今天不會再次扣款。',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
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
                          color: AppColors.ctaStart,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _refreshAfterExternalDowngradeCancel,
                      child: Text(
                        '我已取消降級，更新狀態',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onBackgroundPrimary,
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
    return BrandSurfaceCard(
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
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
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
    final priceLabel = option.priceString ?? '價格同步中';
    final billingCycle = option.isQuarterly ? '每 3 個月自動續訂' : '每月自動續訂';
    final isRecommended = option.id == 'essential_quarterly';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.brandSurface2.withValues(alpha: 0.9),
              AppColors.brandSurface.withValues(alpha: 0.96),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? AppColors.ctaStart.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.8 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.ctaStart.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: 0.22),
              blurRadius: 22,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${option.name} ${option.period}',
                        style: AppTypography.titleLarge.copyWith(
                          color: AppColors.onBackgroundPrimary,
                        ),
                      ),
                      _buildBadge(
                        label: option.badge,
                        background: isRecommended
                            ? const LinearGradient(
                                colors: [
                                  AppColors.ctaStart,
                                  AppColors.ctaEnd,
                                ],
                              )
                            : null,
                        color: isRecommended
                            ? Colors.white
                            : AppColors.onBackgroundPrimary,
                      ),
                      if (option.discount != null)
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
                      if (isCurrentPlan)
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
                  ),
                ),
                Radio<String>(
                  value: option.id,
                  groupValue: _selectedOptionId,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedOptionId = value);
                  },
                  activeColor: AppColors.ctaStart,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              priceLabel,
              style: AppTypography.headlineMedium.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              option.isReady ? billingCycle : '請重新載入 App Store 價格',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
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
                          color: AppColors.onBackgroundPrimary,
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
        color: background == null ? Colors.white.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: background == null
              ? Colors.white.withValues(alpha: 0.1)
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

  Future<void> _subscribe(_PaywallOption option, String selectedTier) async {
    if (kIsWeb) {
      _showSnackBar('請在 iOS App 內管理訂閱。');
      return;
    }

    final package = option.package;
    final storeProduct = option.storeProduct;
    if (package == null && storeProduct == null) {
      _showSnackBar('方案資訊仍在同步中，請稍後再試一次。');
      return;
    }

    setState(() => _isPurchasing = true);
    try {
      final notifier = ref.read(subscriptionProvider.notifier);
      final result = package != null
          ? await notifier.purchase(package).timeout(_purchaseTimeout)
          : await notifier
              .purchaseStoreProduct(storeProduct!)
              .timeout(_purchaseTimeout);
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
          '已排程於 ${_formatDate(result.effectiveAt)} 降級到 ${_tierLabel(result.requestedTier)}。',
          backgroundColor: AppColors.success,
        );
        _leavePaywall(result.activeTier);
        return;
      }

      // 錢已扣：成功呈現不得依賴 refresh 成敗，逾時/失敗只記 log。
      await _refreshAfterSuccessBestEffort(notifier);
      if (!mounted) return;

      final purchasedTier =
          result.activeTier == SubscriptionTierHelper.essential
              ? 'Essential'
              : 'Starter';
      _showSnackBar(
        '方案已更新，目前方案：$purchasedTier。',
        backgroundColor: AppColors.success,
      );
      _leavePaywall(result.activeTier);
    } on TimeoutException catch (error) {
      debugPrint('Paywall purchase timeout: $error');
      _showSnackBar('App Store 付款確認逾時，請稍後再試；如果已付款，可按「恢復購買」。');
    } catch (error) {
      debugPrint('Paywall purchase error: $error');
      _showSnackBar('訂閱處理失敗，請稍後再試。');
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _refreshAfterSuccessBestEffort(
    SubscriptionNotifier notifier,
  ) async {
    try {
      await notifier.refresh().timeout(_postSuccessRefreshTimeout);
    } on TimeoutException catch (error) {
      debugPrint('Paywall post-success refresh timeout: $error');
    } catch (error) {
      debugPrint('Paywall post-success refresh error: $error');
    }
  }

  Future<void> _refreshPlanProducts() async {
    if (_isRefreshingPlans || _isPurchasing) return;

    setState(() => _isRefreshingPlans = true);
    try {
      await ref
          .read(subscriptionScreenRefreshProvider)()
          .timeout(_planRefreshTimeout);
      if (!mounted) return;

      final refreshedOptions = _buildOptions(ref.read(subscriptionProvider));
      final hasReadyPlans = refreshedOptions.any((option) => option.isReady);
      _showSnackBar(
        hasReadyPlans ? 'App Store 價格已更新。' : '仍未取得 App Store 價格，請確認網路後再試。',
        backgroundColor: hasReadyPlans ? AppColors.success : AppColors.warning,
      );
    } on TimeoutException catch (error) {
      debugPrint('Paywall plan refresh timeout: $error');
      if (!mounted) return;
      _showSnackBar('App Store 價格同步逾時，請稍後再試。');
    } catch (error) {
      debugPrint('Paywall plan refresh error: $error');
      if (!mounted) return;
      _showSnackBar('無法重新載入 App Store 價格，請稍後再試。');
    } finally {
      if (mounted) {
        setState(() => _isRefreshingPlans = false);
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
            backgroundColor: AppColors.brandSurface2,
            title: Text(
              '恢復購買',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.onBackgroundPrimary,
              ),
            ),
            content: Text(
              '如果這個 Apple ID 已經有訂閱，可以在這裡重新同步。',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  '取消',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  '恢復購買',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.ctaStart,
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
      final restored =
          await notifier.restorePurchases().timeout(_purchaseTimeout);
      if (!mounted) return;

      if (restored) {
        await _refreshAfterSuccessBestEffort(notifier);
        if (!mounted) return;
        _showSnackBar(
          '訂閱狀態已更新。',
          backgroundColor: AppColors.success,
        );
        _leavePaywall(ref.read(subscriptionProvider).tier);
      } else {
        _showSnackBar('這個 Apple ID 目前沒有可恢復的有效訂閱。');
      }
    } on TimeoutException catch (error) {
      debugPrint('Paywall restore timeout: $error');
      _showSnackBar('App Store 恢復購買逾時，請稍後再試。');
    } catch (error) {
      debugPrint('Paywall restore error: $error');
      _showSnackBar('恢復購買失敗，請稍後再試。');
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _copySubscriptionDiagnostics() async {
    try {
      final subscription = ref.read(subscriptionProvider);
      final usage = UsageService().getLocalUsage();
      final user = SupabaseService.currentUser;
      final revenueCat = await RevenueCatService.buildDebugSnapshot();
      final packageInfo = await PackageInfo.fromPlatform();

      final payload = <String, Object?>{
        'generatedAt': DateTime.now().toIso8601String(),
        'app': {
          'version': '${packageInfo.version} (${packageInfo.buildNumber})',
          'gitSha': AppConfig.gitSha,
          'environment': AppConfig.environmentName,
        },
        'supabase': {
          'userId': user?.id,
          'email': user?.email,
          'provider': user?.appMetadata['provider'],
        },
        'subscriptionState': {
          'tier': subscription.tier,
          'monthlyUsed': subscription.monthlyMessagesUsed,
          'monthlyLimit': subscription.monthlyLimit,
          'dailyUsed': subscription.dailyMessagesUsed,
          'dailyLimit': subscription.dailyLimit,
          'renewsAt': subscription.renewsAt?.toIso8601String(),
          'activeProductId': subscription.activeProductId,
        },
        'usageSnapshot': {
          'tier': usage.tier,
          'monthlyUsed': usage.monthlyUsed,
          'monthlyLimit': usage.monthlyLimit,
          'dailyUsed': usage.dailyUsed,
          'dailyLimit': usage.dailyLimit,
        },
        'revenueCat': revenueCat,
      };

      final text = const JsonEncoder.withIndent('  ').convert(payload);
      await Clipboard.setData(ClipboardData(text: text));

      if (!mounted) return;
      _showSnackBar('訂閱診斷已複製');
    } catch (error) {
      debugPrint('Paywall subscription diagnostics error: $error');
      if (!mounted) return;
      _showSnackBar('目前無法複製訂閱診斷，請稍後再試。');
    }
  }

  Future<void> _refreshAfterExternalDowngradeCancel() async {
    if (_isPurchasing) return;

    setState(() => _isPurchasing = true);
    try {
      final didClear = await ref
          .read(subscriptionProvider.notifier)
          .clearPendingDowngradeMetadata()
          .timeout(_postSuccessRefreshTimeout);
      if (!mounted) return;
      if (didClear) {
        _showSnackBar(
          '已重新同步訂閱狀態。',
          backgroundColor: AppColors.success,
        );
      } else {
        _showSnackBar('App Store 仍顯示降級排程，請確認取消後稍後再試。');
      }
    } on TimeoutException catch (error) {
      debugPrint('Paywall pending downgrade refresh timeout: $error');
      _showSnackBar('同步逾時，請稍後再試。');
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
    return '${local.year}/${local.month}/${local.day}';
  }

  String _billingPeriodLabel(SubscriptionState subscription) {
    if (subscription.isFreeUser) return '';
    final productId = subscription.activeProductId ?? '';
    if (productId.contains('quarterly')) return '（季繳）';
    if (productId.contains('monthly')) return '（月繳）';
    return '';
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
    required this.storeProduct,
    required this.highlights,
  });

  final String id;
  final String tier;
  final String name;
  final String period;
  final String badge;
  final String? discount;
  final Package? package;
  final StoreProduct? storeProduct;
  final List<String> highlights;

  StoreProduct? get purchasableProduct => package?.storeProduct ?? storeProduct;
  bool get isReady => purchasableProduct != null;
  bool get isQuarterly => id.contains('quarterly');
  String? get productId => purchasableProduct?.identifier;
  String? get priceString => purchasableProduct?.priceString;
}

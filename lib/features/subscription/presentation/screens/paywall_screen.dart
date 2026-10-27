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
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/services/link_launch_service.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../opener/domain/opener_access.dart';
import '../../data/providers/subscription_providers.dart';
import '../../domain/services/quarterly_savings.dart';
import '../../domain/services/subscription_tier_helper.dart';
import '../paywall_entry.dart';
import '../subscription_diagnostics_gate.dart';
import '../../../../core/services/app_haptics.dart';
import 'purchase_error_message.dart';

/// 付費頁分兩版（Onboarding 第 9 步）：免費用戶看「購買版」——兩張方案卡、價格、固定在
/// 底部的購買鈕，第一屏就買得到；已付費的人看「管理版」——升降級說明、目前額度、四張
/// 方案卡，內容照舊。
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.entry = PaywallEntry.general});

  /// 從哪裡打開：只換最上面的大標（Eric 2026-10-18）。
  final PaywallEntry entry;

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

  /// 方案還在同步時，骨架最多擋這麼久；之後照當下的方案先排版面。
  static const _layoutResolveTimeout = Duration(seconds: 2);

  /// 購買版的差異句：docs/positioning.md 文案系統裡 Onboarding 第 4 頁（定位頁）那句。
  /// 斷行固定在破折號後面，窄螢幕也不會把「冷還熱」拆到兩行。
  static const _buyPitch = '不只教你回這句：它認得你聊的每一個她——\n聊到哪、她現在冷還熱、什麼時候該約。';

  /// 使用者點過的方案；null＝還沒點過，照目前方案的預設（[_defaultOptionIdFor]）。
  String? _selectedOptionId;
  bool _isPurchasing = false;
  bool _isRefreshingPlans = false;

  /// 打開時方案可能還是本機快取（isLoading）：第一次同步完（或等了
  /// [_layoutResolveTimeout]）才決定給購買版還是管理版，不先閃錯的那一版再換。
  /// 決定之後就不再回骨架——每次打開付費頁都會再刷新一次方案，那次刷新不能讓畫面
  /// 閃回骨架。
  bool _layoutResolved = false;
  Timer? _layoutResolveTimer;

  /// 購買、恢復處理中（遮罩蓋著）時沿用按下去那一刻的版面與選取：付款成功到關頁前
  /// 還會刷新一次方案，不要在遮罩底下從購買版換成管理版、或把選取換成付費用戶的預設。
  bool? _frozenFreeLayout;
  String? _frozenSelectedId;

  /// 「比較全部方案」展開了沒（購買版）。
  bool _showComparison = false;

  /// 沒點過時預設選哪一張（Onboarding 第 9 步，Eric 2026-10-27）：免費用戶 Starter
  /// 月繳；Starter 用戶 Essential 月繳（升級的那一張）；Essential 用戶照舊 Essential
  /// 月繳。「推薦」徽章與橘色樣式跟著這一張，不再另外寫死。
  static String _defaultOptionIdFor(String tier) =>
      SubscriptionTierHelper.normalizeTier(tier) == SubscriptionTierHelper.free
          ? 'starter_monthly'
          : 'essential_monthly';

  String _resolvedOptionId(SubscriptionState subscription) =>
      _selectedOptionId ?? _defaultOptionIdFor(subscription.tier);

  void _selectOption(String id) {
    if (id == _selectedOptionId) return;
    setState(() => _selectedOptionId = id);
  }

  void _markLayoutResolved() {
    if (_layoutResolved) return;
    _layoutResolved = true;
    _layoutResolveTimer?.cancel();
    _layoutResolveTimer = null;
  }

  @override
  void initState() {
    super.initState();
    // 漏斗：每開一次記一筆、帶入口（Eric 2026-10-18：量從哪裡打開付費頁）。
    unawaited(
      ref.read(funnelTrackerProvider).track(
        'paywall_opened',
        properties: {'entry': widget.entry.funnelValue},
      ),
    );
    if (ref.read(subscriptionProvider).isLoading) {
      _layoutResolveTimer = Timer(_layoutResolveTimeout, () {
        if (!mounted || _layoutResolved) return;
        setState(_markLayoutResolved);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(subscriptionScreenRefreshProvider)());
    });
  }

  @override
  void dispose() {
    _layoutResolveTimer?.cancel();
    super.dispose();
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
          '該回的時候給你 3–5 張回覆',
          '互動電子書 4 冊＋聊天測驗全關卡',
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
          '該回的時候給你 3–5 張回覆',
          '互動電子書 4 冊＋聊天測驗全關卡',
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
          '該回的時候給你 3–5 張回覆',
          '《成為獎賞》三冊專屬電子書，全 7 冊解鎖',
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
          '該回的時候給你 3–5 張回覆',
          '《成為獎賞》三冊專屬電子書，全 7 冊解鎖',
        ],
      ),
    ];
  }

  _PaywallOption? _selectedOption(
    List<_PaywallOption> options,
    String selectedId,
  ) {
    return options
        .cast<_PaywallOption?>()
        .firstWhere((o) => o?.id == selectedId, orElse: () => null);
  }

  _PaywallOption? _firstAvailableOption(List<_PaywallOption> options) {
    return options
        .cast<_PaywallOption?>()
        .firstWhere((o) => o?.isReady == true, orElse: () => null);
  }

  /// 購買版：選到的那一張沒有 App Store 價格時退回哪一張（Codex 主審第 1 輪 P2）。
  /// 購買版一次只顯示一個週期，退回「第一個有價格的」會把人拉回別的週期，例如只有
  /// Starter 月繳與 Essential 季繳時，點季繳又被拉回 Starter 月繳，Essential 季繳就
  /// 永遠選不到。所以先找同週期另一級、再找同一級另一個週期、最後才是任何一張有價格的。
  static _PaywallOption? _buyFallbackOption(
    List<_PaywallOption> options,
    _PaywallOption requested,
  ) {
    final ready = options.where((option) => option.isReady).toList();
    if (ready.isEmpty) return null;
    return ready.firstWhere(
      (option) => option.isQuarterly == requested.isQuarterly,
      orElse: () => ready.firstWhere(
        (option) => option.tier == requested.tier,
        orElse: () => ready.first,
      ),
    );
  }

  /// 購買版切換到月繳或季繳時要選哪一張：同一級在那個週期有價格就留在同一級；沒有就
  /// 選那個週期有價格的另一級；兩級都還沒價格（同步中）才照舊選同一級。
  static String _buyOptionIdForPeriod(
    List<_PaywallOption> options, {
    required String tier,
    required bool quarterly,
  }) {
    final inPeriod =
        options.where((option) => option.isQuarterly == quarterly).toList();
    final sameTier = inPeriod.firstWhere((option) => option.tier == tier);
    if (sameTier.isReady) return sameTier.id;
    final ready = inPeriod.where((option) => option.isReady);
    return ready.isEmpty ? sameTier.id : ready.first.id;
  }

  void _scheduleSelectedOptionFallback(
    _PaywallOption? fallback,
    String selectedId,
  ) {
    if (fallback == null || fallback.id == selectedId) return;
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
    if (!subscription.isLoading) _markLayoutResolved();
    if (!_layoutResolved) return _buildLoadingSkeleton();

    final options = _buildOptions(subscription);
    final showFreeLayout = _isPurchasing
        ? (_frozenFreeLayout ?? subscription.isFreeUser)
        : subscription.isFreeUser;
    final resolvedId = _resolvedOptionId(subscription);
    final requestedId =
        _isPurchasing ? (_frozenSelectedId ?? resolvedId) : resolvedId;
    final requested = _selectedOption(options, requestedId);
    final fallbackOption = requested == null || requested.isReady
        ? null
        : showFreeLayout
            ? _buyFallbackOption(options, requested)
            : _firstAvailableOption(options);
    _scheduleSelectedOptionFallback(fallbackOption, requestedId);
    // 購買版一次只顯示一個週期：當幀就畫退回後的那一張，不先閃一幀沒有價格的卡
    // （主審第 1 輪 P2）。管理版照舊，下一幀才換。
    final selected =
        showFreeLayout && fallbackOption != null ? fallbackOption : requested;
    final selectedId = selected?.id ?? requestedId;
    _frozenSelectedId = selectedId;
    _frozenFreeLayout = showFreeLayout;
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

    final primaryButton = BrandPrimaryButton(
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
    );

    if (showFreeLayout) {
      return _buildFreeLayout(
        options: options,
        selected: selected,
        selectedId: selectedId,
        subscription: subscription,
        primaryButton: primaryButton,
      );
    }
    return _buildManageLayout(
      subscription: subscription,
      options: options,
      selected: selected,
      selectedId: selectedId,
      plansReady: plansReady,
      isCurrentPlan: isCurrentPlan,
      isDowngrade: isDowngrade,
      hasPendingDowngrade: hasPendingDowngrade,
      canManagePendingDowngrade: canManagePendingDowngrade,
      pendingDowngradeMatchesSelection: pendingDowngradeMatchesSelection,
      primaryButton: primaryButton,
    );
  }

  /// 管理版（已付費的人）：升降級說明、目前方案與額度、比較表、四張方案卡，內容照舊
  /// （Onboarding 第 9 步只把它從 build 搬出來）。
  Widget _buildManageLayout({
    required SubscriptionState subscription,
    required List<_PaywallOption> options,
    required _PaywallOption? selected,
    required String selectedId,
    required bool plansReady,
    required bool isCurrentPlan,
    required bool isDowngrade,
    required bool hasPendingDowngrade,
    required bool canManagePendingDowngrade,
    required bool pendingDowngradeMatchesSelection,
    required Widget primaryButton,
  }) {
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
                  // 定位句（2026-08-18 拍板）：付費理由從「回覆」升到結果。
                  // 從鎖住的卡、額度不夠打開時換成那個入口的說法；額度的說法照
                  // 目前方案（Essential 不承諾升級，主審 r1 P2-3）。
                  widget.entry.headlineFor(subscription.tier),
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
                const SizedBox(height: 32),
                _buildQuotaSummarySection(subscription),
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
                const SizedBox(height: 24),
                _buildSectionDivider(),
                const SizedBox(height: 24),
                _buildFeatureComparisonTable(),
                const SizedBox(height: 32),
                ...options.map(
                  (option) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildOptionCard(
                      option: option,
                      selectedOptionId: selectedId,
                      isSelected: selectedId == option.id,
                      isCurrentPlan: _isCurrentOption(subscription, option),
                      isRecommended:
                          option.id == _defaultOptionIdFor(subscription.tier),
                      onTap: () => _selectOption(option.id),
                    ),
                  ),
                ),
                if (selected != null) ...[
                  const SizedBox(height: 4),
                  _buildSectionDivider(),
                  const SizedBox(height: 16),
                  _buildSelectedBillingSection(
                    option: selected,
                    isDowngrade: isDowngrade,
                    isCurrentPlan: isCurrentPlan,
                  ),
                ],
                const SizedBox(height: 16),
                primaryButton,
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
          _buildPurchasingScrim(),
        ],
      ),
    );
  }

  /// 購買處理 scrim 淡入淡出，不硬切。[showSpinner] false 給購買版的固定底部：同一層
  /// 遮罩蓋住購買鈕與條款連結，轉圈只留在內容區中間那一個。
  Widget _buildPurchasingScrim({bool showSpinner = true}) {
    return IgnorePointer(
      ignoring: !_isPurchasing,
      // 單一 scrim 的淡入淡出沒有新舊內容並存的殘影問題，維持預設
      // cross-fade（2026-08 殘影拆除刻意保留此處）；退場 spinner 的
      // ticker 生命週期由 spinner 守門測試（2.1(b)）釘住。
      child: AnimatedSwitcher(
        duration: AppMotion.enter,
        switchInCurve: AppMotion.easeOut,
        switchOutCurve: AppMotion.easeOut,
        child: _isPurchasing
            ? Container(
                color: Colors.black54,
                child: showSpinner
                    ? const Center(child: CircularProgressIndicator())
                    : null,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  /// 購買版（免費用戶，Onboarding 第 9 步）：大標第二行先講免費什麼時候恢復，接著
  /// 差異句、月繳／季繳切換、Starter 與 Essential 兩張卡；購買鈕、自動續訂說明、條款
  /// 連結固定在底部，不用捲。比較表收在「比較全部方案」裡；按比例計費的說明、額度
  /// 膠囊、降級排程卡是管理版的東西，這裡不放。
  Widget _buildFreeLayout({
    required SubscriptionState subscription,
    required List<_PaywallOption> options,
    required _PaywallOption? selected,
    required String selectedId,
    required Widget primaryButton,
  }) {
    final isQuarterly = selected?.isQuarterly ?? false;
    final selectedTier = selected?.tier ?? SubscriptionTierHelper.starter;
    final shownOptions =
        options.where((option) => option.isQuarterly == isQuarterly).toList();
    // 推薦跟著免費用戶的預設（Starter）；月繳、季繳都標在 Starter 那張。
    final recommendedTier = options
        .firstWhere(
          (option) =>
              option.id == _defaultOptionIdFor(SubscriptionTierHelper.free),
        )
        .tier;
    final quarterlyDiscount = options
        .firstWhere(
            (option) => option.tier == selectedTier && option.isQuarterly)
        .discount;
    // App Store 只回了部分方案時（主審第 1 輪 P2）：買得到的方案一定選得到。只有一個
    // 週期買得到就不放月繳／季繳切換（切過去也一張都買不到）；買不到的卡點了不換選取、
    // 也不標推薦。全部都還沒價格（同步中）時照舊：切換、點卡都可以，推薦標在 Starter。
    final anyReady = options.any((option) => option.isReady);
    final showPeriodToggle = !anyReady ||
        (options.any((option) => !option.isQuarterly && option.isReady) &&
            options.any((option) => option.isQuarterly && option.isReady));

    return BrandScaffold(
      title: '升級方案',
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: _closePaywall,
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton(
            onPressed: _isPurchasing
                ? null
                : () {
                    _syncPurchasedPlan();
                  },
            child: Text(
              '恢復購買',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
      bottomNavigationBar: _buildBuyBottomBar(
        primaryButton: primaryButton,
        isQuarterly: isQuarterly,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 購買版只給免費用戶；購買處理中方案可能已經換成付費（翻牌入口的大標
                // 跟著方案變），遮罩底下維持免費那句。
                _buildBuyHeadline(
                  widget.entry.headlineFor(SubscriptionTierHelper.free),
                ),
                const SizedBox(height: 8),
                Text(
                  _buyPitch,
                  style: AppTypography.bodySmall.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (showPeriodToggle) ...[
                  BrandSegmentedButton<bool>(
                    segments: [
                      const BrandSegment(value: false, label: '月繳'),
                      BrandSegment(
                        value: true,
                        label: quarterlyDiscount == null
                            ? '季繳'
                            : '季繳 $quarterlyDiscount',
                      ),
                    ],
                    selected: isQuarterly,
                    onChanged: (quarterly) => _selectOption(
                      _buyOptionIdForPeriod(
                        options,
                        tier: selectedTier,
                        quarterly: quarterly,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < shownOptions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          child: _buildBuyPlanCard(
                            option: shownOptions[i],
                            isSelected: shownOptions[i].id == selectedId,
                            isSelectable: !anyReady || shownOptions[i].isReady,
                            isRecommended:
                                shownOptions[i].tier == recommendedTier &&
                                    (!anyReady || shownOptions[i].isReady),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    key: const ValueKey('paywall-compare-toggle'),
                    onPressed: () =>
                        setState(() => _showComparison = !_showComparison),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '比較全部方案',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.onBackgroundSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _showComparison
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: AppMotion.state,
                  curve: AppMotion.easeOut,
                  alignment: Alignment.topCenter,
                  child: _showComparison
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _buildFeatureComparisonTable(),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                if (SubscriptionDiagnosticsGate.isVisible) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _copySubscriptionDiagnostics,
                      child: Text('複製訂閱診斷', style: AppTypography.caption),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _buildPurchasingScrim(),
        ],
      ),
    );
  }

  /// 購買版大標：沿用入口的兩行大標（額度入口第二行是恢復時間，Onboarding 第 3 步），
  /// 第二行改成副標樣式。整段還是同一個 Text，讀出來、找字都跟管理版是同一句。
  Widget _buildBuyHeadline(String headline) {
    final lineBreak = headline.indexOf('\n');
    final title = lineBreak < 0 ? headline : headline.substring(0, lineBreak);
    final subtitle = lineBreak < 0 ? null : headline.substring(lineBreak + 1);
    return Text.rich(
      TextSpan(
        text: title,
        style: AppTypography.headlineLarge.copyWith(
          color: AppColors.onBackgroundPrimary,
          height: 1.12,
        ),
        children: [
          if (subtitle != null)
            TextSpan(
              text: '\n$subtitle',
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.onBackgroundSecondary,
                fontWeight: FontWeight.w400,
                height: 1.6,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  /// 購買版卡片上的權益：數字全部照 AppConstants，冊數照下面比較表那兩格；跟比較表、
  /// docs/pricing-final.md 同一套，不另外編。草稿潤飾 2026-07-28 起全方案都能用
  /// （docs/plans/2026-07-28-reply-refinement-design.md D-4），不列成 Essential 的權益。
  /// 每一條拆成幾段：放得下就同一行，放不下只在段與段之間換行（卡片窄，繁中可能在
  /// 任何字中間斷開，「50 則」的「則」會自己掉到下一行）。
  static List<List<String>> _buyHighlightsFor(String tier) {
    final limits = SubscriptionTierHelper.limitsFor(tier);
    final quota = ['每月 ${limits.monthly} 則・', '每天 ${limits.daily} 則'];
    if (tier == SubscriptionTierHelper.essential) {
      return [
        quota,
        ['陪練每天翻 ${AppConstants.essentialDailyDrawLimit} 位、', '同一位能續聊'],
        ['互動電子書全 7 冊、', '夜市實戰影片完整版'],
      ];
    }
    return [
      quota,
      ['陪練每天翻 ${AppConstants.starterDailyDrawLimit} 位、', '同一位能續聊'],
      ['互動電子書 4 冊＋', '聊天測驗全關卡'],
    ];
  }

  /// 購買版的方案卡：名稱、App Store 價格（沒到就「價格同步中」）、續訂週期；季繳多一行
  /// 灰色月均價小字（無條件進位，字比扣款金額小）。選到的那張是橘框；「推薦」跟著預設
  /// 那張；沒有徽章的卡留同樣高度，兩張卡的名稱、價格對齊。[isSelectable] false＝
  /// 別的方案已經買得到、這張還沒價格：點了不換選取。
  Widget _buildBuyPlanCard({
    required _PaywallOption option,
    required bool isSelected,
    required bool isSelectable,
    required bool isRecommended,
  }) {
    final billingCycle = option.isQuarterly ? '每 3 個月自動續訂' : '每月自動續訂';
    final monthlyAverage = option.isQuarterly
        ? quarterlyMonthlyAverageLabel(option.purchasableProduct)
        : null;
    final badges = <Widget>[
      if (isRecommended)
        _buildBadge(
          label: '推薦',
          background: const LinearGradient(
            colors: [AppColors.ctaStart, AppColors.ctaEnd],
          ),
          color: Colors.white,
        ),
      if (option.isQuarterly && option.discount != null)
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
    ];

    return Semantics(
      key: ValueKey('paywall-buy-card-${option.id}'),
      button: true,
      enabled: isSelectable,
      selected: isSelected,
      child: PressableScale(
        enabled: isSelectable,
        child: GestureDetector(
          onTap: isSelectable ? () => _selectOption(option.id) : null,
          child: AnimatedContainer(
            duration: AppMotion.state,
            curve: AppMotion.easeOut,
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
                    ? AppColors.ctaStart.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.1),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 22,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badges.isEmpty)
                  Visibility(
                    visible: false,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: _buildBadge(label: '推薦', color: Colors.white),
                  )
                else
                  Wrap(spacing: 6, runSpacing: 6, children: badges),
                const SizedBox(height: 8),
                Text(
                  option.name,
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    option.priceString ?? '價格同步中',
                    style: AppTypography.headlineMedium.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  option.isReady ? billingCycle : '請重新載入 App Store 價格',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                if (monthlyAverage != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    monthlyAverage,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                for (final phrases in _buyHighlightsFor(option.tier))
                  Padding(
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
                          child: MergeSemantics(
                            child: Wrap(
                              children: [
                                for (final phrase in phrases)
                                  Text(
                                    phrase,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.onBackgroundPrimary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 購買版固定底部：購買鈕＋扣款與自動續訂說明（照選到的週期寫，季繳寫每 3 個月）＋
  /// 條款、隱私連結，都在購買鈕旁邊看得到（App Review 3.1.2）。「由 Apple ID 扣款」
  /// 是管理版本來就有的揭露（主審第 1 輪建議補回）。說明拆成幾段，窄螢幕只在逗號後
  /// 換行。
  Widget _buildBuyBottomBar({
    required Widget primaryButton,
    required bool isQuarterly,
  }) {
    final renewalPhrases = [
      '由 Apple ID 扣款，',
      '${isQuarterly ? '每 3 個月' : '每月'}自動續訂，',
      '可隨時在 iPhone 設定取消',
    ];
    final linkStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(48, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Stack(
      key: const ValueKey('paywall-buy-bottom-bar'),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  primaryButton,
                  const SizedBox(height: 8),
                  MergeSemantics(
                    key: const ValueKey('paywall-buy-renewal-note'),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (final phrase in renewalPhrases)
                          Text(
                            phrase,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.onBackgroundSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          _launchUrl(_termsUrl);
                        },
                        style: linkStyle,
                        child: Text('服務條款', style: AppTypography.caption),
                      ),
                      Text('|', style: AppTypography.caption),
                      TextButton(
                        onPressed: () {
                          _launchUrl(_privacyUrl);
                        },
                        style: linkStyle,
                        child: Text('隱私政策', style: AppTypography.caption),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(child: _buildPurchasingScrim(showSpinner: false)),
      ],
    );
  }

  /// 方案還在同步、還不知道該給哪一版時的骨架：靜態色塊，不跑動畫；左上 X 照樣能關。
  Widget _buildLoadingSkeleton() {
    Widget block({double? width, required double height, double radius = 18}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return BrandScaffold(
      title: '',
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: _closePaywall,
      ),
      body: SingleChildScrollView(
        key: const ValueKey('paywall-loading-skeleton'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          children: [
            block(width: 220, height: 32, radius: 999),
            const SizedBox(height: 12),
            block(width: 280, height: 16, radius: 999),
            const SizedBox(height: 32),
            block(height: 40),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: block(height: 220, radius: 24)),
                const SizedBox(width: 12),
                Expanded(child: block(height: 220, radius: 24)),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '正在同步方案資訊',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
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

  /// S9/B9：頁面區塊分隔線——卡片堆疊改分層後，區塊邊界用 hairline 表達。
  Widget _buildSectionDivider() {
    return Container(
      height: 1,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }

  Widget _buildSelectedBillingSection({
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
          // 對話分析 v3：伺服器照局面排卡，三個方案都看全部的卡（Bruce PR #97，Eric
          // 2026-10-19）；這一列照留，讓人知道免費也看得到全部。不寫「每次」：收尾只有
          // 1 張、先別回和停沒有卡（Eric 2026-10-18）。
          _buildComparisonRow('回覆卡', '全部', '全部', '全部'),
          // 開場救星（Eric 2026-10-18）：免費只看得到其中幾句，兩個付費方案都看完整。
          // 句數照開場權益契約（opener_access.dart，鏡像 server opener_payload.ts），
          // 改契約不用回來改文案。
          _buildComparisonRow(
            '開場救星',
            '${OpenerAccessContract.freeUnlockedOrder.length} 句',
            '${OpenerAccessContract.canonicalPaidOrder.length} 句',
            '${OpenerAccessContract.canonicalPaidOrder.length} 句',
          ),
          // 鏡像 server 真相源 practice-chat/draw_decision.ts：free=0（只剩
          // 起步清單一次性贈抽）；付費數字吃 AppConstants，改額度不用改文案。
          _buildComparisonRow(
            '陪練女孩翻牌',
            '起步贈抽 1 次',
            '每日 ${AppConstants.starterDailyDrawLimit} 次',
            '每日 ${AppConstants.essentialDailyDrawLimit} 次',
          ),
          // 訂閱一次性 SR 限定翻牌（2026-08-08 拍板）：兩檔同權益，白紙黑字
          // 回答「哪檔才有」；同時是解 Game 鎖的具體承諾。
          _buildComparisonRow('SR 限定翻牌', '—', '送 1 次', '送 1 次'),
          // 權限鏡像 assets/learning 宣告：電子書 book1 free（付費書另有首章
          // 試讀）、2-4 premium、5-7 essential 專屬。測驗欄刻意不寫死關數
          // （ADR #38 後擴充批次會一直加關，寫死數字每批都要回來追）；免費
          // 關清單＝內容不變式測試的 _freeLevelIds。
          _buildComparisonRow('互動電子書', '第 1 冊＋試讀', '4 冊', '全 7 冊'),
          _buildComparisonRow('聊天測驗', '免費關卡', '全部關卡', '全部關卡'),
          _buildComparisonRow('夜市實戰影片', '第一段', '第一段', '完整流程＋復盤'),
          // 不再列「對話健檢」「訊息優化」：健檢只有舊版詳細分析才有，新流程
          // 不產生（Eric 2026-10-17）；訊息優化 7/29 起所有方案都能用（D-4）。
          // 兩個都不是 Essential 專屬，列在這裡等於要人付錢買拿不到或本來就有的東西。
          _buildComparisonRow(
            '每日額度',
            '${AppConstants.freeDailyLimit} 則',
            '${AppConstants.starterDailyLimit} 則',
            '${AppConstants.essentialDailyLimit} 則',
          ),
          _buildComparisonRow(
            '每月額度',
            '${AppConstants.freeMonthlyLimit} 則',
            '${AppConstants.starterMonthlyLimit} 則',
            '${AppConstants.essentialMonthlyLimit} 則',
          ),
          const SizedBox(height: 12),
          Text(
            '免費版同一位陪練女孩只能練一輪；升級後每天可翻新的陪練女孩，'
            '也能續聊同一位，把對話練得更完整。',
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

  /// S9/B9：原本是 BrandSurfaceCard，卡片堆疊改分層——區塊靠字級與
  /// 分隔線分層，額度數字保留 pill 容器（資訊元件，非頁面結構卡）。
  Widget _buildQuotaSummarySection(SubscriptionState subscription) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目前方案與額度',
            style: AppTypography.titleLarge.copyWith(
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
        borderRadius: BorderRadius.circular(18),
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

  /// 管理版的方案卡。[isRecommended]（橘色徽章）跟著預設選取那一張
  /// （[_defaultOptionIdFor]，Onboarding 第 9 步）；以前寫死在 Essential 季繳，跟
  /// 預設的 Essential 月繳對不上。
  Widget _buildOptionCard({
    required _PaywallOption option,
    required String selectedOptionId,
    required bool isSelected,
    required bool isCurrentPlan,
    required bool isRecommended,
    required VoidCallback onTap,
  }) {
    final priceLabel = option.priceString ?? '價格同步中';
    final billingCycle = option.isQuarterly ? '每 3 個月自動續訂' : '每月自動續訂';

    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        // 選取回饋只留 240ms 的邊框／陰影漸變（2026-08-27 拍板：拿掉沿著邊框
        // 掃一圈的流星光暈，選卡不再出現掃動的動態光）。
        child: AnimatedContainer(
          duration: AppMotion.state,
          curve: AppMotion.easeOut,
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
                  ? AppColors.ctaStart.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? AppColors.ctaStart.withValues(alpha: 0.45)
                    : Colors.black.withValues(alpha: 0.22),
                blurRadius: isSelected ? 28 : 22,
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
                    groupValue: selectedOptionId,
                    onChanged: (value) {
                      if (value == null) return;
                      _selectOption(value);
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
    // 付款確認回來前他可能已經關掉這頁（之後不能再用 ref），成功照樣要記，先抓好。
    // 帳號也在這裡記下、之後不再重讀，免得 A 買的算到 B（主審 r1、r2 P2）：確認回來時
    // 換了帳號或登出就不送；送出的認證權杖是 HTTP 送出當下才取，檢查之後才換帳號這邊
    // 擋不到，所以事件帶上這個帳號，伺服器發現跟登入的不同就整筆丟掉。
    final tracker = ref.read(funnelTrackerProvider);
    final entry = widget.entry;
    final purchaserId = SupabaseService.currentUser?.id;
    try {
      final notifier = ref.read(subscriptionProvider.notifier);
      final result = package != null
          ? await notifier.purchase(package).timeout(_purchaseTimeout)
          : await notifier
              .purchaseStoreProduct(storeProduct!)
              .timeout(_purchaseTimeout);
      // 漏斗：RevenueCat 回成功才記買的方案（Eric 2026-10-18）。取消、失敗的
      // success 是 false，逾時、例外直接進 catch；排程降級當下沒有新方案生效，不算買到。
      final samePurchaser =
          purchaserId != null && SupabaseService.currentUser?.id == purchaserId;
      if (result.success && !result.isDeferredDowngrade && samePurchaser) {
        unawaited(
          tracker.track(
            'paywall_purchase_completed',
            properties: {
              'tier': result.requestedTier,
              'entry': entry.funnelValue,
              // 只給伺服器比對，不落庫。
              'purchaser': purchaserId,
            },
          ),
        );
      }
      if (!mounted || result.cancelled) return;

      if (!result.success) {
        AppHaptics.failure();
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
      AppHaptics.celebrate();

      final purchasedTier =
          result.activeTier == SubscriptionTierHelper.essential
              ? 'Essential'
              : 'Starter';
      // 輕慶祝（2026-08-08 拍板）：SR 券解鎖訊息搭在同一顆 snackbar＋「去翻牌」
      // action——點了才去、不點不打斷；券本體由圖鑑金券入口承接
      // （srTicketStatusProvider watch isPremium，翻轉即自動 ensure）。
      // router 先抓：action 觸發時 paywall 已 pop，不能再用本頁 context 導頁。
      final router = GoRouter.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '方案已更新，目前方案：$purchasedTier。🎴 已解鎖 SR 限定翻牌 ×1。',
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '去翻牌',
            textColor: Colors.white,
            onPressed: () => router.push('/practice-collection'),
          ),
        ),
      );
      _leavePaywall(result.activeTier);
    } on TimeoutException catch (error) {
      debugPrint('Paywall purchase timeout: $error');
      AppHaptics.failure();
      _showSnackBar('App Store 付款確認逾時，請稍後再試；如果已付款，可按「恢復購買」。');
    } catch (error) {
      debugPrint('Paywall purchase error: $error');
      AppHaptics.failure();
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
  }) =>
      purchaseErrorMessageFor(errorCode, fallbackMessage: fallbackMessage);

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
                onPressed: AppHaptics.onPress(
                    () => Navigator.pop(dialogContext, true)),
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

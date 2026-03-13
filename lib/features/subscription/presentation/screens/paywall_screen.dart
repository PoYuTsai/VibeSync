// lib/features/subscription/presentation/screens/paywall_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
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
  String _debugInfo = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadDebugInfo();
  }

  Future<void> _loadDebugInfo() async {
    try {
      final isConfigured = await Purchases.isConfigured;
      final offerings = await Purchases.getOfferings();
      final currentOffering = offerings.current;
      final packages = currentOffering?.availablePackages ?? [];

      setState(() {
        _debugInfo = '''
RC Configured: $isConfigured
Current Offering: ${currentOffering?.identifier ?? 'NULL'}
Packages: ${packages.length}
${packages.map((p) => '- ${p.identifier}: ${p.storeProduct.identifier}').join('\n')}
''';
      });
    } catch (e) {
      setState(() {
        _debugInfo = 'Error: $e';
      });
    }
  }

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
                  // DEBUG INFO - 測試完成後移除
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _debugInfo,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
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

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('訂閱成功！'),
              backgroundColor: AppColors.success,
            ),
          );
          context.pop();
        }
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

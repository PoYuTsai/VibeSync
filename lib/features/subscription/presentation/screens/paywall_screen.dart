// lib/features/subscription/presentation/screens/paywall_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../domain/entities/message_booster.dart';
import '../widgets/booster_purchase_sheet.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String _selectedTier = 'essential'; // 預設選 Essential
  bool _isYearly = true; // 預設選年繳 (更划算)

  // 定價資料 (全部以 NT$ 顯示)
  static const _pricing = {
    'starter': {
      'monthly': 'NT\$149',
      'yearly': 'NT\$99',
      'yearlyTotal': 'NT\$1,190',
      'discount': '33%',
    },
    'essential': {
      'monthly': 'NT\$930',
      'yearly': 'NT\$620',
      'yearlyTotal': 'NT\$7,440',
      'discount': '33%',
    },
  };

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('升級方案', style: AppTypography.titleLarge.copyWith(color: AppColors.onBackgroundPrimary)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                '解鎖完整功能',
                style: AppTypography.headlineLarge.copyWith(color: AppColors.onBackgroundPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '提升你的社交溝通能力',
                style: AppTypography.bodyLarge.copyWith(color: AppColors.onBackgroundSecondary),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 24),

            // Billing toggle
            _buildBillingToggle(),
            const SizedBox(height: 24),

            // Plan cards
            _buildPlanCard(
              tier: 'starter',
              name: 'Starter',
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
              text: '開始 7 天免費試用',
              onPressed: _subscribe,
            ),
            const SizedBox(height: 12),
            Text(
              '試用結束後自動扣款，可隨時取消',
              style: AppTypography.caption.copyWith(color: AppColors.onBackgroundSecondary),
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
                  onPressed: () {},
                  child: Text('恢復購買', style: AppTypography.caption),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Booster purchase link
            Center(
              child: TextButton(
                onPressed: _showBoosterPurchase,
                child: Text(
                  '只需要加購訊息？',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _showBoosterPurchase() async {
    final result = await showBoosterPurchaseSheet(context);
    if (result != null && mounted) {
      // TODO: Process purchase with RevenueCat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已購買 ${result.label}')),
      );
    }
  }

  Widget _buildBillingToggle() {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isYearly = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: !_isYearly
                      ? const LinearGradient(colors: [AppColors.selectedStart, AppColors.selectedEnd])
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '月繳',
                  textAlign: TextAlign.center,
                  style: AppTypography.labelLarge.copyWith(
                    color: !_isYearly ? Colors.white : AppColors.unselectedText,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isYearly = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: _isYearly
                      ? const LinearGradient(colors: [AppColors.selectedStart, AppColors.selectedEnd])
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '年繳',
                      style: AppTypography.labelLarge.copyWith(
                        color: _isYearly ? Colors.white : AppColors.unselectedText,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isYearly
                            ? Colors.white.withValues(alpha: 0.2)
                            : AppColors.success.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '省 33%',
                        style: AppTypography.caption.copyWith(
                          color: _isYearly ? Colors.white : AppColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required String tier,
    required String name,
    required List<String> features,
    required bool isSelected,
    bool isRecommended = false,
    required VoidCallback onTap,
  }) {
    final pricing = _pricing[tier]!;
    final currentPrice = _isYearly ? pricing['yearly']! : pricing['monthly']!;
    final originalPrice = pricing['monthly']!;

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
                Text(name, style: AppTypography.titleLarge.copyWith(color: AppColors.glassTextPrimary)),
                if (isRecommended) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.selectedStart, AppColors.selectedEnd]),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currentPrice/月',
                  style: AppTypography.headlineMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                if (_isYearly) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$originalPrice/月',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.glassTextHint,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ],
            ),
            if (_isYearly) ...[
              const SizedBox(height: 4),
              Text(
                '年繳 ${pricing['yearlyTotal']}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.glassTextHint,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: AppTypography.bodyMedium.copyWith(color: AppColors.glassTextPrimary))),
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
    // TODO: Integrate with RevenueCat
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('RevenueCat 整合待實作')),
    );
  }
}

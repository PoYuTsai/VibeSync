// lib/features/subscription/presentation/screens/paywall_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/message_booster.dart';
import '../widgets/booster_purchase_sheet.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String _selectedTier = 'essential'; // 預設選 Essential

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('升級方案', style: AppTypography.titleLarge),
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
              style: AppTypography.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '提升你的社交溝通能力',
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Plan cards
            _buildPlanCard(
              tier: 'starter',
              name: 'Starter',
              price: 'NT\$149/月',
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
              price: 'NT\$349/月',
              features: const [
                '1,000 則訊息/月',
                '每日 150 則上限',
                '5 種回覆建議',
                'Needy 警示',
                '話題深度分析',
                '對話健檢 (獨家)',
                'Sonnet 優先模型',
              ],
              isSelected: _selectedTier == 'essential',
              isRecommended: true,
              onTap: () => setState(() => _selectedTier = 'essential'),
            ),
            const SizedBox(height: 32),

            // CTA button
            ElevatedButton(
              onPressed: _subscribe,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                '開始 7 天免費試用',
                style: AppTypography.titleMedium.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '試用結束後自動扣款，可隨時取消',
              style: AppTypography.caption,
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

  Widget _buildPlanCard({
    required String tier,
    required String name,
    required String price,
    required List<String> features,
    required bool isSelected,
    bool isRecommended = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name, style: AppTypography.titleLarge),
                if (isRecommended) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
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
                ),
              ],
            ),
            Text(price, style: AppTypography.headlineMedium),
            const SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: AppTypography.bodyMedium)),
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

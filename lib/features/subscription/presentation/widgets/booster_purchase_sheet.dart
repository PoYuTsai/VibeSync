// lib/features/subscription/presentation/widgets/booster_purchase_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/message_booster.dart';

class BoosterPurchaseSheet extends ConsumerStatefulWidget {
  const BoosterPurchaseSheet({super.key});

  @override
  ConsumerState<BoosterPurchaseSheet> createState() =>
      _BoosterPurchaseSheetState();
}

class _BoosterPurchaseSheetState extends ConsumerState<BoosterPurchaseSheet> {
  BoosterPackage _selectedPackage = BoosterPackage.medium;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withAlpha(77), // ~0.3 opacity
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            '加購訊息包',
            style: AppTypography.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '額度不夠用？立即加購',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Package options
          ...BoosterPackage.values.map((pkg) => _buildPackageOption(pkg)),

          const SizedBox(height: 24),

          // Purchase button
          ElevatedButton(
            onPressed: _purchase,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(
              '購買 ${_selectedPackage.label} - ${_selectedPackage.priceLabel}',
              style: AppTypography.titleMedium.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPackageOption(BoosterPackage pkg) {
    final isSelected = _selectedPackage == pkg;

    return GestureDetector(
      onTap: () => setState(() => _selectedPackage = pkg),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withAlpha(25) // ~0.1 opacity
              : AppColors.background,
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.textSecondary.withAlpha(51), // ~0.2 opacity
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Radio<BoosterPackage>(
              value: pkg,
              groupValue: _selectedPackage,
              onChanged: (v) => setState(() => _selectedPackage = v!),
              activeColor: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pkg.label, style: AppTypography.titleMedium),
                  Text(
                    '每則 NT\$${pkg.costPerMessage.toStringAsFixed(2)}',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(pkg.priceLabel, style: AppTypography.titleMedium),
                if (pkg.savingsLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.hot.withAlpha(51), // ~0.2 opacity
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      pkg.savingsLabel,
                      style: AppTypography.caption.copyWith(color: AppColors.hot),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _purchase() {
    // TODO: Integrate with RevenueCat for IAP
    Navigator.of(context).pop(_selectedPackage);
  }
}

/// Show booster purchase sheet
Future<BoosterPackage?> showBoosterPurchaseSheet(BuildContext context) {
  return showModalBottomSheet<BoosterPackage>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const BoosterPurchaseSheet(),
  );
}

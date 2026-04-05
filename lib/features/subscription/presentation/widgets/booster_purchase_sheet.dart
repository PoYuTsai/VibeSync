// ignore_for_file: deprecated_member_use

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
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withAlpha(77),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Message Booster',
            style: AppTypography.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Preview the planned one-time packages. Purchase is not live yet.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ...BoosterPackage.values.map(_buildPackageOption),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'This sheet is read-only for now. RevenueCat booster IAP still needs to be integrated before any purchase can complete.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _showComingSoon,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.textSecondary,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Coming Soon',
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
              ? AppColors.primary.withAlpha(25)
              : AppColors.background,
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.textSecondary.withAlpha(51),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Radio<BoosterPackage>(
              value: pkg,
              groupValue: _selectedPackage,
              onChanged: (value) => setState(() => _selectedPackage = value!),
              activeColor: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pkg.label, style: AppTypography.titleMedium),
                  Text(
                    'Per message ${pkg.costPerMessage.toStringAsFixed(2)} NTD',
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
                      color: AppColors.hot.withAlpha(51),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      pkg.savingsLabel,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.hot,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Booster purchases are not live yet. Please use the subscription plans for now.',
        ),
      ),
    );
    Navigator.of(context).pop();
  }
}

Future<BoosterPackage?> showBoosterPurchaseSheet(BuildContext context) {
  return showModalBottomSheet<BoosterPackage>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const BoosterPurchaseSheet(),
  );
}

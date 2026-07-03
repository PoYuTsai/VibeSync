// lib/features/subscription/presentation/screens/ai_privacy_screen.dart
//
// F5-A7 App Review 保險：設定頁常駐的「AI 與你的隱私」靜態揭露頁。
// onboarding 第 4 頁可被「略過」，這裡提供事後隨時可查的入口。
// 文案與 onboarding 共用 AiPrivacyDisclosure，避免雙份漂移。
// 純靜態頁：不含任何同意邏輯——實際同意仍由各 AI 功能首次使用前的
// AiDataSharingConsent 同意閘把關。
import 'package:flutter/material.dart';

import '../../../../core/constants/ai_privacy_disclosure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

class AiPrivacyScreen extends StatelessWidget {
  const AiPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      title: AiPrivacyDisclosure.title,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          BrandSurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandIconBadge(icon: Icons.privacy_tip_outlined),
                const SizedBox(height: 16),
                Text(
                  AiPrivacyDisclosure.description,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

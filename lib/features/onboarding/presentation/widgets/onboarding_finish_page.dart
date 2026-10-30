// lib/features/onboarding/presentation/widgets/onboarding_finish_page.dart
//
// onboarding 轉換第 12 步第 4 頁：登入前把下一步講清楚——
//   - 依第 1 頁的路徑一句說明登入後先做什麼；
//   - 免費額度一行（數字只用 AppConstants，跟伺服器 _shared/quota.ts 同步）；
//   - 第 3 頁有選目標才多一行：目標存進「關於我」，只有教練 1:1 會參考；
//   - AI 隱私一行（AiPrivacyDisclosure.onboardingLine）＋「看完整說明」，打開跟
//     設定頁「AI 與你的隱私」同一段文字的 sheet（含廠商行與登入前事件）。
// 這一頁取代原本獨立的隱私頁（R1-4／F5-A7 的 App Review 揭露），設定頁的常駐入口不動。
// 「繼續」按鈕在 OnboardingScreen 的底部，不在本頁。
import 'package:flutter/material.dart';

import '../../../../core/constants/ai_privacy_disclosure.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/onboarding_intent.dart';

class OnboardingFinishPage extends StatelessWidget {
  const OnboardingFinishPage({
    super.key,
    required this.intent,
    required this.hasGoals,
    required this.onOpenPrivacy,
  });

  /// 第 1 頁選的路徑；理論上一定有（第 1 頁要選了才會往下走），沒有就用通用說法。
  final OnboardingIntent? intent;

  /// 第 3 頁有沒有選目標。
  final bool hasGoals;

  /// 「看完整說明」。
  final VoidCallback onOpenPrivacy;

  /// 免費額度一行：數字只吃 AppConstants（付費頁比較表同一組常數）。
  static const freeQuotaLine = '免費額度：每月 ${AppConstants.freeMonthlyLimit} 則、'
      '每天最多 ${AppConstants.freeDailyLimit} 則。';

  /// 有選目標才出現：目標只有教練 1:1 會讀（關於我 PR-5），不寫成「建議都會更像你」。
  static const goalsLine = '你選的目標會存進「關於我」，教練 1:1 回答時會參考。';

  static const privacyLinkLabel = '看完整說明';

  /// 每條路徑登入後先做什麼：標題一句，小字補實際會看到的畫面。標題壓在 12 字
  /// 內，375 寬的 iPhone 也排得進一行，不會第二行只剩一個字。
  static ({String title, String? detail}) nextStepCopy(
    OnboardingIntent? intent,
  ) =>
      switch (intent) {
        OnboardingIntent.analyze => (
            title: '登入後，丟一段對話截圖',
            detail: '先幫她建一張對象卡，建好就直接選截圖。',
          ),
        OnboardingIntent.opener => (
            title: '登入後，丟她的自介截圖',
            detail: '自介或照片都可以，幫你想幾句開場白。',
          ),
        OnboardingIntent.practice => (
            title: '登入後，先抽一位練習夥伴',
            // 登入前不知道方案：送的那一次只給免費帳號，付費方案用每天的免費翻牌
            // （Bruce 2026-10-30 真機、Eric 選 A）。
            detail: '免費帳號第一次進練習室會先送一次翻牌；付費方案用每天的免費翻牌。',
          ),
        OnboardingIntent.browse || null => (
            title: '登入後就能開始',
            detail: null,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final copy = nextStepCopy(intent);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.title,
                      style: AppTypography.headlineMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (copy.detail != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        copy.detail!,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _InfoRow(
                      icon: Icons.card_giftcard_outlined,
                      text: freeQuotaLine,
                    ),
                    if (hasGoals) ...[
                      const SizedBox(height: 16),
                      const _InfoRow(
                          icon: Icons.flag_outlined, text: goalsLine),
                    ],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: _PrivacyLine(onOpen: onOpenPrivacy),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行資訊：小圖示＋字，不套卡片（DESIGN.md §2：同款卡片不平鋪堆疊）。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 18,
            color: AppColors.ctaStart.withValues(alpha: 0.86),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// AI 隱私一行，句尾接「看完整說明」。整行都可以點（至少 44 高），不只那四個
/// 字：點擊範圍夠大，審核員與讀螢幕軟體都找得到。連結接在句尾，不另起一行，
/// 免得第二行只剩「AI。」兩個字。
class _PrivacyLine extends StatelessWidget {
  const _PrivacyLine({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    // 裡面的 InkWell 被 excludeSemantics 排掉了，讀屏的點擊要接在這一層（主審 r1 P2）。
    return Semantics(
      button: true,
      label: '${AiPrivacyDisclosure.onboardingLine}。'
          '${OnboardingFinishPage.privacyLinkLabel}',
      onTap: onOpen,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          key: const ValueKey('onboarding-privacy-link'),
          borderRadius: radius,
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.78),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      key: const ValueKey('onboarding-privacy-line'),
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: '${AiPrivacyDisclosure.onboardingLine}。',
                          ),
                          TextSpan(
                            text: OnboardingFinishPage.privacyLinkLabel,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.ctaStart,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.ctaStart,
                            ),
                          ),
                        ],
                      ),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.82),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「看完整說明」：跟設定頁「AI 與你的隱私」同一段 [AiPrivacyDisclosure.description]
/// （含廠商行、登入前事件先存手機再補送那兩句）。純靜態揭露，不含同意邏輯。
Future<void> showOnboardingPrivacySheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.brandSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BrandIconBadge(icon: Icons.privacy_tip_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AiPrivacyDisclosure.title,
                          style: AppTypography.titleLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AiPrivacyDisclosure.description,
                    key: const ValueKey('onboarding-privacy-sheet-text'),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: BrandPrimaryButton(
              label: '知道了',
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

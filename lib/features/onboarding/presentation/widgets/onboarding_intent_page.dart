// lib/features/onboarding/presentation/widgets/onboarding_intent_page.dart
//
// onboarding 轉換第 12 步第 1 頁：「你現在最想先搞定哪一件？」三選一，決定登入後
// 先帶他去哪裡（她回我了→選截圖、剛配對→開場救星、還沒有對象→練習室）。
// 「先逛逛」＝略過整個 onboarding（每頁可逃生，2026-07-06 設計）。右上「我有帳號」
// 在 OnboardingScreen 的頂列，不在本頁。
// Controlled widget：選了哪一個存在 OnboardingScreen，本頁只負責畫與回報。
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../domain/onboarding_intent.dart';

class OnboardingIntentPage extends StatelessWidget {
  const OnboardingIntentPage({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onBrowse,
  });

  /// 上次選的路徑（按上一頁回來時標出來）；還沒選是 null。
  final OnboardingIntent? selected;
  final ValueChanged<OnboardingIntent> onSelect;

  /// 「先逛逛」。
  final VoidCallback onBrowse;

  static const title = '你現在最想先搞定哪一件？';
  static const browseLabel = '先逛逛';

  /// 三條路徑的字：標題講他現在的處境，小字講按下去會做什麼。
  static const options = <({
    OnboardingIntent intent,
    String title,
    String subtitle,
  })>[
    (
      intent: OnboardingIntent.analyze,
      title: '她回我了，不知道怎麼接',
      subtitle: '丟對話截圖，先看她現在的燈號',
    ),
    (
      intent: OnboardingIntent.opener,
      title: '剛配對，還沒開口',
      subtitle: '丟她的自介截圖，給你幾句開場',
    ),
    (
      intent: OnboardingIntent.practice,
      title: '還沒有對象，想先練',
      // 「練習夥伴」對齊練習室落地頁 Sydney 泡泡的說法。
      subtitle: '先抽一位練習夥伴，練一輪',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SydneyIntro(),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTypography.headlineMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 24),
          for (final (index, option) in options.indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            _IntentOption(
              key: ValueKey('onboarding-intent-${option.intent.wire}'),
              title: option.title,
              subtitle: option.subtitle,
              selected: selected == option.intent,
              onTap: () => onSelect(option.intent),
            ),
          ],
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: onBrowse,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ctaStart,
                minimumSize: const Size(88, 44),
              ),
              child: Text(
                browseLabel,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.ctaStart,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sydney 小頭像＋一句自我介紹：第一印象用品牌教練（2026-08-01 轉化診斷），
/// 類別詞照 docs/positioning.md 用「戀愛教練」。
class _SydneyIntro extends StatelessWidget {
  const _SydneyIntro();

  static const line = '我是 Sydney，你的 AI 戀愛教練';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _SydneyAvatar(),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            line,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 從招手圖裁出頭部的圓形頭像。原圖 1023×1537、背景透明：以 7.1 倍縮小
/// （頭部約 340px 寬放進 48pt），水平置中、垂直對準約 26% 高的臉。
class _SydneyAvatar extends StatelessWidget {
  const _SydneyAvatar();

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'VibeSync Coach Sydney，欣欣',
      child: Container(
        key: const ValueKey('onboarding-sydney-avatar'),
        width: _size,
        height: _size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Image.asset(
          'assets/images/coach/sydney_greeting.png',
          scale: 7.1,
          fit: BoxFit.none,
          alignment: const Alignment(0, -0.62),
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

/// 一條路徑：整張可點。選過的那張用橘框標出來（按上一頁回來時看得到）。
class _IntentOption extends StatelessWidget {
  const _IntentOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    // 裡面的 InkWell 被 excludeSemantics 排掉了，讀屏的點擊要接在這一層（主審 r1 P2）。
    return Semantics(
      button: true,
      selected: selected,
      label: '$title。$subtitle',
      onTap: onTap,
      excludeSemantics: true,
      child: PressableScale(
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: AnimatedContainer(
              duration: AppMotion.state,
              curve: AppMotion.easeOut,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.ctaStart.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: radius,
                border: Border.all(
                  color: selected
                      ? AppColors.ctaStart.withValues(alpha: 0.75)
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.titleMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onBackgroundSecondary
                                .withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 24,
                    color: Colors.white.withValues(alpha: 0.5),
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

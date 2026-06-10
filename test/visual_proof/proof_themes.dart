// Before = warm (real shared widgets). After = calm (proof-only variants).
import 'package:flutter/material.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/shared/widgets/warm_theme_widgets.dart';

import 'proof_support.dart';

// ---------------------------------------------------------------------------
// BEFORE — real shared warm-theme widgets, real AppColors.
// ---------------------------------------------------------------------------

final ProofTheme warmTheme = ProofTheme(
  label: 'before',
  background: (child) => GradientBackground(child: child),
  card: ({required child, padding = const EdgeInsets.all(16)}) =>
      GlassmorphicContainer(padding: padding, child: child),
  cardLow: ({required child, padding = const EdgeInsets.all(16)}) =>
      GlassmorphicContainer(padding: padding, child: child),
  cta: (text) => GradientButton(text: text, onPressed: () {}),
  onBgPrimary: Colors.white,
  onBgSecondary: AppColors.onBackgroundSecondary,
  onCardPrimary: AppColors.glassTextPrimary,
  onCardSecondary: AppColors.glassTextSecondary,
  onCardHint: AppColors.glassTextHint,
  accent: AppColors.ctaStart,
  appBarTitleColor: Colors.white,
);

// ---------------------------------------------------------------------------
// AFTER — calm/mature night direction. Deeper desaturated ground, one soft
// ember instead of three candy bokeh orbs, dark translucent elevated cards
// with hairline borders, a single confident CTA shadow.
// ---------------------------------------------------------------------------

class _CalmPalette {
  static const bgTop = Color(0xFF0C0A11);
  static const bgMid = Color(0xFF15111B);
  static const bgBottom = Color(0xFF1D1722);
  static const ember = Color(0xFFC9684A); // muted warm terracotta glow
  static const emberCool = Color(0xFF3E3550); // faint cool counter-glow

  // Warm ivory "paper note in the night": warm off-white, high opacity, soft.
  static const cardSurface = Color(0xFFF5F0E6); // primary tier — brightest
  static const cardBorder = Color(0xFFE7DDCB); // soft warm hairline
  static const cardLowSurface = Color(0xFFE6DECF); // secondary tier — recedes
  static const cardLowBorder = Color(0xFFD8CFBE);
  static const onCardPrimary = Color(0xFF2E2924); // warm charcoal, high contrast
  static const onCardSecondary = Color(0xFF6F665A);
  static const onCardHint = Color(0xFF9C9286);
  static const onBgPrimary = Color(0xFFF2EEF6);
  static const onBgSecondary = Color(0xFF9C92A8);
  static const accent = Color(0xFFE08A63); // warm, calmer than ctaStart
  static const ctaStart = Color(0xFFC75F3D); // deeper, more sober terracotta
  static const ctaEnd = Color(0xFFB0492A);
}

class CalmBackground extends StatelessWidget {
  const CalmBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _CalmPalette.bgTop,
            _CalmPalette.bgMid,
            _CalmPalette.bgBottom,
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Single warm ember, sunk lower + smaller + fainter so it never
          // competes with content — atmosphere, not bokeh.
          Positioned(
            bottom: -250,
            left: -110,
            child: _SoftGlow(
              color: _CalmPalette.ember,
              size: 228,
              blur: 150,
              opacity: 0.13,
            ),
          ),
          // Faint cool counter-glow top-right for depth balance.
          Positioned(
            top: -120,
            right: -110,
            child: _SoftGlow(
              color: _CalmPalette.emberCool,
              size: 300,
              blur: 150,
              opacity: 0.5,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SoftGlow extends StatelessWidget {
  const _SoftGlow({
    required this.color,
    required this.size,
    required this.blur,
    required this.opacity,
  });
  final Color color;
  final double size;
  final double blur;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: opacity),
            blurRadius: blur,
            spreadRadius: blur / 3,
          ),
        ],
      ),
    );
  }
}

class CalmCard extends StatelessWidget {
  const CalmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _CalmPalette.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _CalmPalette.cardBorder, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D000000), // black @ 30% — real elevation
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Secondary-tier card: muted ivory + softer/shallower shadow so it sits one
/// step behind the primary opener cards.
class CalmCardLow extends StatelessWidget {
  const CalmCardLow({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _CalmPalette.cardLowSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _CalmPalette.cardLowBorder, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000), // ~15% — shallower than primary tier
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class CalmCta extends StatelessWidget {
  const CalmCta({super.key, required this.text, this.height = 52});
  final String text;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_CalmPalette.ctaStart, _CalmPalette.ctaEnd],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            // Neutral, grounded shadow — no colored e-commerce glow.
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

final ProofTheme calmTheme = ProofTheme(
  label: 'after',
  background: (child) => CalmBackground(child: child),
  card: ({required child, padding = const EdgeInsets.all(16)}) =>
      CalmCard(padding: padding, child: child),
  cardLow: ({required child, padding = const EdgeInsets.all(16)}) =>
      CalmCardLow(padding: padding, child: child),
  cta: (text) => CalmCta(text: text),
  onBgPrimary: _CalmPalette.onBgPrimary,
  onBgSecondary: _CalmPalette.onBgSecondary,
  onCardPrimary: _CalmPalette.onCardPrimary,
  onCardSecondary: _CalmPalette.onCardSecondary,
  onCardHint: _CalmPalette.onCardHint,
  accent: _CalmPalette.accent,
  appBarTitleColor: _CalmPalette.onBgPrimary,
);
